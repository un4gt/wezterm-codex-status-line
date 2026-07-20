#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import shlex
import shutil
import sys
import tempfile
import time
import uuid
from pathlib import Path
from typing import Any


BRIDGE_PY = "codex_statusline_bridge.py"
BRIDGE_PS1 = "codex_statusline_bridge.ps1"


def codex_home(override: str | None = None) -> Path:
    value = override or os.environ.get("CODEX_HOME")
    return Path(value).expanduser().resolve() if value else Path.home() / ".codex"


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
        try:
            os.unlink(temp_name)
        except FileNotFoundError:
            pass


def is_our_handler(handler: Any) -> bool:
    if not isinstance(handler, dict):
        return False
    return BRIDGE_PY in str(handler.get("command", "")) or BRIDGE_PS1 in str(
        handler.get("commandWindows", "")
    )


def handler_config() -> dict[str, Any]:
    script_dir = Path(__file__).resolve().parent
    py_path = script_dir / BRIDGE_PY
    ps_path = script_dir / BRIDGE_PS1
    return {
        "type": "command",
        "command": f"{shlex.quote(sys.executable)} {shlex.quote(str(py_path))}",
        "commandWindows": (
            'powershell.exe -NoProfile -ExecutionPolicy Bypass -File '
            f'"{ps_path}"'
        ),
        "timeout": 5,
    }


def load_hooks(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {
            "description": "Hooks used by the WezTerm Codex statusline bridge.",
            "hooks": {},
        }
    with path.open("r", encoding="utf-8-sig") as handle:
        value = json.load(handle)
    if not isinstance(value, dict):
        raise ValueError(f"hooks document must be an object: {path}")
    hooks = value.setdefault("hooks", {})
    if not isinstance(hooks, dict):
        raise ValueError(f"hooks field must be an object: {path}")
    return value


def backup(path: Path) -> None:
    if path.exists():
        stamp = time.strftime("%Y%m%d-%H%M%S") + f"-{int(time.time() * 1000) % 1000:03d}"
        backup_path = path.with_name(f"{path.name}.bak-{stamp}")
        if backup_path.exists():
            backup_path = backup_path.with_name(f"{backup_path.name}-{uuid.uuid4().hex}")
        shutil.copy2(path, backup_path)


def install(home: Path) -> None:
    home.mkdir(parents=True, exist_ok=True)
    hooks_path = home / "hooks.json"
    document = load_hooks(hooks_path)
    session_start = document["hooks"].setdefault("SessionStart", [])
    if not isinstance(session_start, list):
        raise ValueError("hooks.SessionStart must be an array")

    expected = handler_config()
    found = False
    changed = False
    for group in session_start:
        if not isinstance(group, dict) or not isinstance(group.get("hooks"), list):
            continue
        updated_handlers: list[Any] = []
        for handler in group["hooks"]:
            if not is_our_handler(handler):
                updated_handlers.append(handler)
                continue
            if found:
                changed = True
                continue
            found = True
            if handler == expected:
                updated_handlers.append(handler)
            else:
                updated_handlers.append(expected)
                changed = True
        group["hooks"] = updated_handlers

    if not found:
        session_start.append({"hooks": [expected]})
        changed = True

    if changed:
        backup(hooks_path)
        write_json_atomic(hooks_path, document)

    manifest = {
        "schema": 1,
        "installed_at_unix_ms": int(time.time() * 1000),
        "powershell_bridge": str(Path(__file__).resolve().with_name(BRIDGE_PS1)),
        "python_bridge": str(Path(__file__).resolve()),
    }
    write_json_atomic(home / "wezterm-statusline" / "bridge.json", manifest)
    print(f"Codex statusline bridge installed in {hooks_path}")


def uninstall(home: Path) -> None:
    hooks_path = home / "hooks.json"
    if hooks_path.exists():
        document = load_hooks(hooks_path)
        session_start = document["hooks"].get("SessionStart", [])
        kept_groups: list[Any] = []
        changed = False
        if isinstance(session_start, list):
            for group in session_start:
                if not isinstance(group, dict) or not isinstance(group.get("hooks"), list):
                    kept_groups.append(group)
                    continue
                handlers = group["hooks"]
                kept = [handler for handler in handlers if not is_our_handler(handler)]
                changed = changed or len(kept) != len(handlers)
                if kept:
                    copied = dict(group)
                    copied["hooks"] = kept
                    kept_groups.append(copied)
        if changed:
            backup(hooks_path)
            document["hooks"]["SessionStart"] = kept_groups
            write_json_atomic(hooks_path, document)

    manifest = home / "wezterm-statusline" / "bridge.json"
    try:
        manifest.unlink()
    except FileNotFoundError:
        pass
    print("Codex statusline bridge uninstalled.")


def run_hook(home: Path) -> None:
    pane_id = os.environ.get("WEZTERM_PANE", "")
    if not pane_id.isdigit():
        return
    raw = sys.stdin.read()
    if not raw:
        return
    payload = json.loads(raw)
    session_id = str(uuid.UUID(str(payload.get("session_id", ""))))
    transcript_path = payload.get("transcript_path")
    if not isinstance(transcript_path, str):
        transcript_path = None

    thread_id = session_id
    if transcript_path:
        try:
            with Path(transcript_path).open("r", encoding="utf-8") as handle:
                for _ in range(20):
                    line = handle.readline()
                    if not line:
                        break
                    try:
                        item = json.loads(line)
                    except json.JSONDecodeError:
                        continue
                    if item.get("type") == "session_meta" and isinstance(item.get("payload"), dict):
                        candidate = item["payload"].get("id")
                        if candidate:
                            thread_id = str(uuid.UUID(str(candidate)))
                            break
        except OSError:
            pass

    mapping = {
        "schema": 1,
        "pane_id": pane_id,
        "thread_id": thread_id,
        "session_id": session_id,
        "rollout_path": transcript_path,
        "cwd": str(payload.get("cwd", "")),
        "source": str(payload.get("source", "")),
        "generation": str(uuid.uuid4()),
        "written_at_unix_ms": int(time.time() * 1000),
    }
    write_json_atomic(home / "wezterm-statusline" / "panes" / f"{pane_id}.json", mapping)


def main() -> None:
    parser = argparse.ArgumentParser(description="Codex SessionStart bridge for WezTerm")
    action = parser.add_mutually_exclusive_group()
    action.add_argument("--install", action="store_true")
    action.add_argument("--uninstall", action="store_true")
    parser.add_argument("--codex-home")
    args = parser.parse_args()
    home = codex_home(args.codex_home)
    if args.install:
        install(home)
    elif args.uninstall:
        uninstall(home)
    else:
        run_hook(home)


if __name__ == "__main__":
    main()
