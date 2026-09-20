from __future__ import annotations

import hashlib
import json
import os
import re
import selectors
import shutil
import subprocess
import sys
import tempfile
import time
import uuid
from dataclasses import dataclass
from importlib import resources
from pathlib import Path
from typing import Any

import jsonschema
import questionary
import typer

from . import __version__
from .render import SEGMENT_IDS, build_render_plan


app = typer.Typer(add_completion=False, invoke_without_command=True, no_args_is_help=False)
TITLE_VALUE = ["app-name", "model", "reasoning", "project-name"]
HEX_COLOR = re.compile(r"^#[0-9a-fA-F]{6}$")
ASSET_NAMES = [
    "codex_statusline_bridge.ps1",
    "codex_statusline_bridge.py",
    "codex_statusline_bridge.js",
    "codex_statusline_core.lua",
    "codex_statusline/version.lua",
    "codex_statusline/domain/common.lua",
    "codex_statusline/domain/process.lua",
    "codex_statusline/domain/session.lua",
    "codex_statusline/domain/prices.lua",
    "codex_statusline/domain/pricing.lua",
    "codex_statusline/domain/render.lua",
    "codex_statusline/util.lua",
    "codex_statusline/config.lua",
    "codex_statusline/session_index.lua",
    "codex_statusline/rollout.lua",
    "codex_statusline/git.lua",
    "codex_statusline/process.lua",
    "codex_statusline/formatting.lua",
    "codex_statusline/legacy_renderer.lua",
    "codex_statusline/renderer.lua",
    "codex_statusline/layout.lua",
    "codex_statusline/state.lua",
    "codex_statusline/wezterm_adapter.lua",
    "codex_statusline/lifecycle.lua",
    "codex_statusline.lua",
]


class CliFailure(RuntimeError):
    def __init__(self, message: str, exit_code: int = 1) -> None:
        super().__init__(message)
        self.exit_code = exit_code


@dataclass
class State:
    user_home: Path
    codex_home: Path
    module_dir: Path
    config_path: Path
    json_output: bool = False
    no_color: bool = False
    yes: bool = False

    @property
    def bridge_root(self) -> Path:
        return self.codex_home / "wezterm-statusline"

    @property
    def bridge_bin(self) -> Path:
        return self.bridge_root / "bin"

    @property
    def manifest(self) -> Path:
        return self.bridge_root / "bridge.json"

    @property
    def hooks(self) -> Path:
        return self.codex_home / "hooks.json"


def asset_path(name: str) -> Path:
    return Path(str(resources.files("wezterm_codex_status_line").joinpath("assets", name)))


def read_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8-sig"))


def write_json_atomic(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temp_name = tempfile.mkstemp(prefix=f".{path.name}.", suffix=".tmp", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as handle:
            json.dump(value, handle, ensure_ascii=True, indent=2)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temp_name, path)
    finally:
        Path(temp_name).unlink(missing_ok=True)


def backup(path: Path) -> None:
    if path.exists():
        stamp = time.strftime("%Y%m%d-%H%M%S") + f"-{int(time.time() * 1000) % 1000:03d}"
        shutil.copy2(path, path.with_name(f"{path.name}.bak-{stamp}"))


def validate_config(value: Any) -> dict[str, Any]:
    schema = read_json(asset_path("contract/config.schema.json"))
    try:
        jsonschema.validate(value, schema)
    except jsonschema.ValidationError as error:
        raise CliFailure(f"Invalid config: {error.message}", 2) from error
    return value


def default_config() -> dict[str, Any]:
    return read_json(asset_path("contract/default-config.json"))


def load_config(state: State) -> dict[str, Any]:
    return validate_config(read_json(state.config_path)) if state.config_path.exists() else default_config()


def is_our_handler(handler: Any) -> bool:
    return isinstance(handler, dict) and "codex_statusline_bridge." in f"{handler.get('command', '')} {handler.get('commandWindows', '')}"


def expected_python_hook(state: State) -> dict[str, Any]:
    base_python = Path(getattr(sys, "_base_executable", sys.executable)).resolve()
    return {
        "type": "command",
        "command": f'"{base_python}" "{state.bridge_bin / "codex_statusline_bridge.py"}"',
        "commandWindows": f'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "{state.bridge_bin / "codex_statusline_bridge.ps1"}"',
        "timeout": 5,
    }


def load_hooks(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {"description": "Hooks used by the WezTerm Codex statusline bridge.", "hooks": {}}
    value = read_json(path)
    if not isinstance(value, dict) or not isinstance(value.setdefault("hooks", {}), dict):
        raise CliFailure(f"Invalid hooks document: {path}", 2)
    return value


def merge_hook(state: State) -> None:
    document = load_hooks(state.hooks)
    groups = document["hooks"].get("SessionStart", [])
    kept: list[Any] = []
    for group in groups if isinstance(groups, list) else []:
        if not isinstance(group, dict) or not isinstance(group.get("hooks"), list):
            kept.append(group)
            continue
        handlers = [handler for handler in group["hooks"] if not is_our_handler(handler)]
        if handlers:
            kept.append({**group, "hooks": handlers})
    document["hooks"]["SessionStart"] = [*kept, {"hooks": [expected_python_hook(state)]}]
    backup(state.hooks)
    write_json_atomic(state.hooks, document)


def remove_hook(state: State) -> None:
    if not state.hooks.exists():
        return
    document = load_hooks(state.hooks)
    groups = document["hooks"].get("SessionStart", [])
    kept = []
    for group in groups if isinstance(groups, list) else []:
        if not isinstance(group, dict) or not isinstance(group.get("hooks"), list):
            kept.append(group)
            continue
        handlers = [handler for handler in group["hooks"] if not is_our_handler(handler)]
        if handlers:
            kept.append({**group, "hooks": handlers})
    document["hooks"]["SessionStart"] = kept
    backup(state.hooks)
    write_json_atomic(state.hooks, document)


def copy_assets(state: State) -> None:
    staged: list[tuple[Path, Path]] = []
    try:
        for name in ASSET_NAMES:
            destination = (state.module_dir if name.endswith(".lua") else state.bridge_bin) / name
            destination.parent.mkdir(parents=True, exist_ok=True)
            temp = destination.with_name(f"{destination.name}.{os.getpid()}.{uuid.uuid4().hex}.tmp")
            shutil.copy2(asset_path(name), temp)
            staged.append((temp, destination))
        for temp, destination in staged:
            os.replace(temp, destination)
    finally:
        for temp, _ in staged:
            temp.unlink(missing_ok=True)


def load_manifest(state: State) -> dict[str, Any]:
    try:
        value = read_json(state.manifest)
        return value if isinstance(value, dict) else {}
    except (OSError, ValueError):
        return {}


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def installed_assets_healthy(state: State) -> bool:
    assets = load_manifest(state).get("assets")
    if not isinstance(assets, dict):
        return False
    recorded = {os.path.normcase(str(Path(path).resolve())): value for path, value in assets.items()}
    for name in ASSET_NAMES:
        path = (state.module_dir if name.endswith(".lua") else state.bridge_bin) / name
        if not path.exists() or recorded.get(os.path.normcase(str(path.resolve()))) != sha256(path):
            return False
    return True


def update_manifest(state: State, title_record: dict[str, Any] | None = None) -> None:
    files = [(state.module_dir if name.endswith(".lua") else state.bridge_bin) / name for name in ASSET_NAMES]
    manifest = {
        **load_manifest(state),
        "schema": 4,
        "package": {"name": "wezterm-codex-status-line", "version": __version__, "runner": "uvx", "installed_at_unix_ms": int(time.time() * 1000)},
        "wezterm_module_dir": str(state.module_dir),
        "config_path": str(state.config_path),
        "lua_modules": [str(path) for path in files if path.suffix == ".lua"],
        "bridge_bin": str(state.bridge_bin),
        "bridge_runtime": str(Path(getattr(sys, "_base_executable", sys.executable)).resolve()),
        "assets": {str(path): sha256(path) for path in files if path.exists()},
    }
    if title_record:
        manifest["codex_title_bridge"] = title_record
    write_json_atomic(state.manifest, manifest)


def wezterm_require(state: State) -> Path | None:
    candidates = [state.user_home / ".wezterm.lua", state.module_dir / "wezterm.lua"]
    pattern = re.compile(r"require\s*\(\s*[\"']codex_statusline[\"']\s*\)")
    return next((path for path in candidates if path.exists() and pattern.search(path.read_text(encoding="utf-8-sig"))), None)


def run_powershell(action: str, state: State, title_bridge: bool = False) -> None:
    executable = shutil.which("powershell.exe") or shutil.which("pwsh")
    if not executable:
        raise CliFailure("PowerShell is required on Windows")
    args = [executable, "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(asset_path("install.ps1")), f"-{action}", "-UserHome", str(state.user_home), "-CodexHome", str(state.codex_home), "-WezTermModuleDir", str(state.module_dir)]
    if action == "Install" and title_bridge:
        args.append("-EnableCodexTitleBridge")
    result = subprocess.run(args, check=False, capture_output=state.json_output, text=True)
    if result.returncode:
        details = f": {(result.stderr or result.stdout).strip()}" if state.json_output else ""
        raise CliFailure(f"PowerShell {action.lower()} failed{details}")


class RpcClient:
    def __init__(self, codex_home: Path) -> None:
        command = os.environ.get("CODEX_STATUSLINE_CODEX_COMMAND") or shutil.which("codex")
        if not command:
            raise CliFailure("Codex CLI was not found in PATH")
        self.process = subprocess.Popen([command, "app-server", "--stdio"], cwd=codex_home, env={**os.environ, "CODEX_HOME": str(codex_home)}, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, encoding="utf-8")
        self.selector = selectors.DefaultSelector()
        assert self.process.stdout is not None
        self.selector.register(self.process.stdout, selectors.EVENT_READ)
        self.next_id = 1

    def request(self, method: str, params: Any) -> Any:
        request_id = self.next_id
        self.next_id += 1
        assert self.process.stdin is not None and self.process.stdout is not None
        self.process.stdin.write(json.dumps({"id": request_id, "method": method, "params": params}, separators=(",", ":")) + "\n")
        self.process.stdin.flush()
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline:
            if not self.selector.select(max(0, deadline - time.monotonic())):
                break
            line = self.process.stdout.readline()
            if not line:
                break
            try:
                response = json.loads(line)
            except ValueError:
                continue
            if response.get("id") != request_id:
                continue
            if response.get("error"):
                raise CliFailure(f"Codex app-server error: {response['error']}")
            return response.get("result")
        raise CliFailure(f"Timed out waiting for {method}")

    def close(self) -> None:
        self.selector.close()
        if self.process.stdin:
            self.process.stdin.close()
        self.process.terminate()
        try:
            self.process.wait(timeout=1)
        except subprocess.TimeoutExpired:
            self.process.kill()


def title_state(value: dict[str, Any], codex_home: Path) -> dict[str, Any]:
    layer = next((layer for layer in value.get("layers", []) if layer.get("name", {}).get("type") == "user" and layer.get("name", {}).get("profile") is None), None)
    tui = (layer or {}).get("config", {}).get("tui", {})
    present = "terminal_title" in tui
    return {"present": present, "value": tui.get("terminal_title"), "effective": value.get("config", {}).get("tui", {}).get("terminal_title"), "version": (layer or {}).get("version"), "file": (layer or {}).get("name", {}).get("file") or str(codex_home / "config.toml")}


def enable_title_bridge(state: State, existing: dict[str, Any] | None) -> dict[str, Any]:
    client = RpcClient(state.codex_home)
    try:
        before = title_state(client.request("config/read", {"includeLayers": True}), state.codex_home)
        if existing and existing.get("enabled") and before["value"] != existing.get("installed_value"):
            raise CliFailure("tui.terminal_title changed after installation; refusing to overwrite it", 3)
        if before["value"] != TITLE_VALUE:
            client.request("config/batchWrite", {"edits": [{"keyPath": "tui.terminal_title", "value": TITLE_VALUE, "mergeStrategy": "replace"}], "filePath": before["file"], "expectedVersion": before["version"], "reloadUserConfig": False})
        after = title_state(client.request("config/read", {"includeLayers": True}), state.codex_home)
        if after["value"] != TITLE_VALUE:
            raise CliFailure("Codex did not persist tui.terminal_title")
        if existing and existing.get("enabled"):
            return {**existing, "installed_value": TITLE_VALUE, "version_after": after["version"]}
        return {"enabled": True, "key_path": "tui.terminal_title", "config_file": after["file"], "original_present": before["present"], "original_value": before["value"], "installed_value": TITLE_VALUE, "version_before": before["version"], "version_after": after["version"]}
    finally:
        client.close()


def restore_title_bridge(state: State, record: dict[str, Any]) -> None:
    client = RpcClient(state.codex_home)
    try:
        current = title_state(client.request("config/read", {"includeLayers": True}), state.codex_home)
        if current["value"] != record.get("installed_value"):
            return
        value = record.get("original_value") if record.get("original_present") else None
        client.request("config/batchWrite", {"edits": [{"keyPath": "tui.terminal_title", "value": value, "mergeStrategy": "replace"}], "filePath": current["file"], "expectedVersion": current["version"], "reloadUserConfig": False})
    finally:
        client.close()


def emit(state: State, command: str, status: str, changes: list[str], warnings: list[str] | None = None, **extra: Any) -> None:
    result = {
        "schema": 1,
        "command": command,
        "version": __version__,
        "status": status,
        "changes": changes,
        "warnings": warnings or [],
        "paths": {
            "codex_home": str(state.codex_home),
            "wezterm_module_dir": str(state.module_dir),
            "config": str(state.config_path),
            "manifest": str(state.manifest),
            "hooks": str(state.hooks),
        },
        **extra,
    }
    if state.json_output:
        typer.echo(json.dumps(result, ensure_ascii=False, indent=2))
    elif status == "changed":
        typer.echo(f"{command}: complete")


def perform_install(state: State, title_bridge: bool, update: bool, dry_run: bool) -> None:
    if dry_run:
        emit(state, "update" if update else "install", "unchanged", ["dry-run"])
        return
    if sys.platform == "win32":
        run_powershell("Install", state, title_bridge)
        update_manifest(state)
    else:
        existing = load_manifest(state)
        title_record = enable_title_bridge(state, existing.get("codex_title_bridge")) if title_bridge else existing.get("codex_title_bridge")
        copy_assets(state)
        merge_hook(state)
        update_manifest(state, title_record)
    emit(state, "update" if update else "install", "changed", ["updated" if update else "installed"])


@app.callback()
def callback(
    ctx: typer.Context,
    codex_home: Path | None = typer.Option(None, "--codex-home"),
    wezterm_module_dir: Path | None = typer.Option(None, "--wezterm-module-dir"),
    config_file: Path | None = typer.Option(None, "--config-file"),
    json_output: bool = typer.Option(False, "--json"),
    no_color: bool = typer.Option(False, "--no-color"),
    yes: bool = typer.Option(False, "--yes"),
    version: bool = typer.Option(False, "--version"),
) -> None:
    if version:
        typer.echo(__version__)
        raise typer.Exit()
    user_home = Path(os.environ.get("CODEX_STATUSLINE_USER_HOME", Path.home())).expanduser().resolve()
    module_dir = (wezterm_module_dir or user_home / ".config" / "wezterm").expanduser().resolve()
    state = State(user_home, (codex_home or Path(os.environ.get("CODEX_HOME", user_home / ".codex"))).expanduser().resolve(), module_dir, (config_file or module_dir / "codex_statusline_config.json").expanduser().resolve(), json_output, no_color, yes)
    ctx.obj = state
    if ctx.invoked_subcommand is None:
        if not sys.stdin.isatty():
            typer.echo(ctx.get_help())
            raise typer.Exit()
        choice = questionary.select("选择操作", choices=["install", "configure", "doctor", "uninstall"]).ask()
        if not choice:
            raise typer.Exit(2)
        if choice == "install":
            perform_install(state, bool(questionary.confirm("启用 Codex terminal title bridge？", default=True).ask()), False, False)
        elif choice == "configure":
            perform_configure(state, None, None, None, None, None, None, False, 120)
        elif choice == "doctor":
            perform_doctor(state)
        else:
            perform_uninstall(state, False, False, False)


@app.command()
def install(ctx: typer.Context, title_bridge: bool | None = typer.Option(None, "--title-bridge/--no-title-bridge"), dry_run: bool = False) -> None:
    state: State = ctx.obj
    if title_bridge is None:
        if state.yes:
            title_bridge = True
        elif not sys.stdin.isatty():
            raise CliFailure("Non-interactive install requires --title-bridge or --no-title-bridge", 2)
        title_bridge = bool(questionary.confirm("启用 Codex terminal title bridge？", default=True).ask())
    perform_install(state, title_bridge, False, dry_run)


@app.command()
def update(ctx: typer.Context, title_bridge: bool | None = typer.Option(None, "--title-bridge/--no-title-bridge"), dry_run: bool = False) -> None:
    state: State = ctx.obj
    if title_bridge is None:
        title_bridge = bool(load_manifest(state).get("codex_title_bridge", {}).get("enabled"))
    perform_install(state, title_bridge, True, dry_run)


def render_text(config: dict[str, Any], sample: dict[str, Any], width: int, color: bool = False) -> str:
    plan = build_render_plan(config, sample, width)
    use_ansi = color and config["options"]["render"]["powerline"]
    rendered_lines = []
    for line in plan["lines"]:
        if not use_ansi:
            rendered_lines.append(" | ".join(segment["text"] for segment in line))
            continue
        rendered = []
        for segment in line:
            bg = tuple(int(segment["bg"][index:index + 2], 16) for index in (1, 3, 5))
            fg = tuple(int(segment["fg"][index:index + 2], 16) for index in (1, 3, 5))
            rendered.append(f"\x1b[48;2;{bg[0]};{bg[1]};{bg[2]}m\x1b[38;2;{fg[0]};{fg[1]};{fg[2]}m {segment['text']} \x1b[0m")
        rendered_lines.append("".join(rendered))
    return "\n".join(rendered_lines)


def color_validator(value: str) -> bool | str:
    return True if HEX_COLOR.fullmatch(value or "") else "请输入 #RRGGBB"


def apply_color_specs(config: dict[str, Any], specs: list[str]) -> None:
    for spec in specs:
        parts = spec.split(":")
        if len(parts) != 3 or parts[0] not in SEGMENT_IDS or not HEX_COLOR.fullmatch(parts[1]) or not HEX_COLOR.fullmatch(parts[2]):
            raise CliFailure(f"Invalid --color {spec}; expected segment:#RRGGBB:#RRGGBB", 2)
        segment_id, bg, fg = parts
        config["options"]["theme"]["segments"][segment_id] = {"bg": bg, "fg": fg}


def perform_configure(
    state: State,
    from_path: Path | None,
    label: str | None,
    rows: int | None,
    binding_mode: str | None,
    segments: str | None,
    disable: str | None,
    dry_run: bool,
    width: int,
    theme_bg: str | None = None,
    theme_fg: str | None = None,
    theme_dim: str | None = None,
    colors: list[str] | None = None,
    powerline: bool | None = None,
) -> None:
    config = validate_config(read_json(from_path)) if from_path else load_config(state)
    colors = colors or []
    scripted = any(value is not None for value in (from_path, label, rows, binding_mode, segments, disable, theme_bg, theme_fg, theme_dim, powerline)) or bool(colors)
    if sys.stdin.isatty() and not scripted:
        label = questionary.text("状态标签", default=config["options"]["label"]).ask()
        if label is None:
            raise CliFailure("Cancelled", 2)
        rows_answer = questionary.select("状态 pane 行数", choices=[1, 2], default=config["options"]["bottom_pane"]["rows"]).ask()
        if rows_answer is None:
            raise CliFailure("Cancelled", 2)
        rows = int(rows_answer)
        powerline_answer = questionary.confirm("使用 Powerline segment", default=config["options"]["render"]["powerline"]).ask()
        if powerline_answer is None:
            raise CliFailure("Cancelled", 2)
        powerline = bool(powerline_answer)
        enabled = questionary.checkbox("显示项目", choices=SEGMENT_IDS, default=[item for item in SEGMENT_IDS if item not in config["options"]["render"]["disabled_segments"]]).ask()
        if enabled is None:
            raise CliFailure("Cancelled", 2)
        segments = questionary.text("显示顺序（逗号分隔）", default=",".join(config["options"]["render"]["segment_order"])).ask()
        if segments is None:
            raise CliFailure("Cancelled", 2)
        config["options"]["render"]["powerline"] = powerline
        config["options"]["render"]["disabled_segments"] = [item for item in SEGMENT_IDS if item not in enabled]
        customize_theme = questionary.confirm("自定义主题颜色？", default=False).ask()
        if customize_theme is None:
            raise CliFailure("Cancelled", 2)
        if customize_theme:
            theme_bg = questionary.text("终端背景色", default=config["options"]["theme"]["bg"], validate=color_validator).ask()
            theme_fg = questionary.text("默认文字色", default=config["options"]["theme"]["fg"], validate=color_validator).ask()
            theme_dim = questionary.text("弱化文字色", default=config["options"]["theme"]["dim"], validate=color_validator).ask()
            themed = questionary.checkbox("选择要改色的 segment", choices=SEGMENT_IDS).ask()
            if theme_bg is None or theme_fg is None or theme_dim is None or themed is None:
                raise CliFailure("Cancelled", 2)
            for segment_id in themed:
                current = config["options"]["theme"]["segments"][segment_id]
                bg = questionary.text(f"{segment_id} 背景色", default=current["bg"], validate=color_validator).ask()
                fg = questionary.text(f"{segment_id} 文字色", default=current["fg"], validate=color_validator).ask()
                if bg is None or fg is None:
                    raise CliFailure("Cancelled", 2)
                config["options"]["theme"]["segments"][segment_id] = {"bg": bg, "fg": fg}
    if label:
        config["options"]["label"] = label
    if rows in {1, 2}:
        config["options"]["bottom_pane"]["rows"] = rows
    if binding_mode in {"auto", "hook", "heuristic"}:
        config["options"]["sessions"]["binding_mode"] = binding_mode
    if powerline is not None:
        config["options"]["render"]["powerline"] = powerline
    if segments:
        config["options"]["render"]["segment_order"] = [item.strip() for item in segments.split(",")]
    if disable is not None:
        config["options"]["render"]["disabled_segments"] = [item.strip() for item in disable.split(",") if item.strip()]
    if theme_bg:
        config["options"]["theme"]["bg"] = theme_bg
    if theme_fg:
        config["options"]["theme"]["fg"] = theme_fg
    if theme_dim:
        config["options"]["theme"]["dim"] = theme_dim
    apply_color_specs(config, colors)
    validate_config(config)
    if not state.json_output:
        typer.echo("\n" + render_text(config, read_json(asset_path("contract/sample-state.json")), width, sys.stdout.isatty() and not state.no_color) + "\n")
    if not dry_run:
        write_json_atomic(state.config_path, config)
    emit(state, "configure", "unchanged" if dry_run else "changed", ["dry-run" if dry_run else "configured"])


@app.command("configure")
def configure_command(
    ctx: typer.Context,
    from_path: Path | None = typer.Option(None, "--from"),
    label: str | None = None,
    rows: int | None = None,
    binding_mode: str | None = None,
    segments: str | None = None,
    disable: str | None = None,
    theme_bg: str | None = typer.Option(None, "--theme-bg"),
    theme_fg: str | None = typer.Option(None, "--theme-fg"),
    theme_dim: str | None = typer.Option(None, "--theme-dim"),
    color: list[str] | None = typer.Option(None, "--color"),
    powerline: bool | None = typer.Option(None, "--powerline/--no-powerline"),
    dry_run: bool = False,
    width: int = 120,
) -> None:
    perform_configure(ctx.obj, from_path, label, rows, binding_mode, segments, disable, dry_run, width, theme_bg, theme_fg, theme_dim, color, powerline)


@app.command("config", hidden=True)
def config_alias(
    ctx: typer.Context,
    from_path: Path | None = typer.Option(None, "--from"),
    label: str | None = None,
    rows: int | None = None,
    binding_mode: str | None = None,
    segments: str | None = None,
    disable: str | None = None,
    theme_bg: str | None = typer.Option(None, "--theme-bg"),
    theme_fg: str | None = typer.Option(None, "--theme-fg"),
    theme_dim: str | None = typer.Option(None, "--theme-dim"),
    color: list[str] | None = typer.Option(None, "--color"),
    powerline: bool | None = typer.Option(None, "--powerline/--no-powerline"),
    dry_run: bool = False,
    width: int = 120,
) -> None:
    perform_configure(ctx.obj, from_path, label, rows, binding_mode, segments, disable, dry_run, width, theme_bg, theme_fg, theme_dim, color, powerline)


@app.command()
def preview(ctx: typer.Context, width: int = 120, state_file: Path | None = typer.Option(None, "--state")) -> None:
    state: State = ctx.obj
    sample = read_json(state_file) if state_file else read_json(asset_path("contract/sample-state.json"))
    output = render_text(load_config(state), sample, width, sys.stdout.isatty() and not state.no_color)
    if state.json_output:
        emit(state, "preview", "unchanged", [], preview=output)
    else:
        typer.echo(output)


def perform_doctor(state: State) -> None:
    config_healthy = True
    if state.config_path.exists():
        try:
            validate_config(read_json(state.config_path))
        except (CliFailure, OSError, ValueError):
            config_healthy = False
    checks = {
        "manifest": state.manifest.exists(),
        "lua_entry": (state.module_dir / "codex_statusline.lua").exists(),
        "lua_core": (state.module_dir / "codex_statusline_core.lua").exists(),
        "asset_integrity": installed_assets_healthy(state),
        "hooks": state.hooks.exists() and "codex_statusline_bridge" in state.hooks.read_text(encoding="utf-8-sig"),
        "wezterm_require": wezterm_require(state) is not None,
        "config": config_healthy,
    }
    if not state.json_output:
        for name, ok in checks.items():
            typer.echo(f"{'OK' if ok else 'MISSING'}  {name}")
    emit(state, "doctor", "unchanged" if all(checks.values()) else "failed", [], [name for name, ok in checks.items() if not ok])
    if not all(checks.values()):
        raise typer.Exit(1)


@app.command()
def doctor(ctx: typer.Context) -> None:
    perform_doctor(ctx.obj)


def perform_uninstall(state: State, force: bool, purge_config: bool, dry_run: bool) -> None:
    active = wezterm_require(state)
    if active:
        raise CliFailure(f'Remove require("codex_statusline") from {active}, then run uninstall again', 3)
    if dry_run:
        emit(state, "uninstall", "unchanged", ["dry-run"])
        return
    manifest = load_manifest(state)
    if sys.platform == "win32":
        run_powershell("Uninstall", state)
    else:
        if manifest.get("codex_title_bridge"):
            restore_title_bridge(state, manifest["codex_title_bridge"])
        remove_hook(state)
        for name in ASSET_NAMES:
            ((state.module_dir if name.endswith(".lua") else state.bridge_bin) / name).unlink(missing_ok=True)
        state.manifest.unlink(missing_ok=True)
    if purge_config:
        state.config_path.unlink(missing_ok=True)
    emit(state, "uninstall", "changed", ["uninstalled"])


@app.command()
def uninstall(ctx: typer.Context, force: bool = False, purge_config: bool = False, dry_run: bool = False) -> None:
    perform_uninstall(ctx.obj, force, purge_config, dry_run)


def main() -> None:
    try:
        app()
    except CliFailure as error:
        typer.echo(f"Error: {error}", err=True)
        raise SystemExit(error.exit_code) from error


if __name__ == "__main__":
    main()
