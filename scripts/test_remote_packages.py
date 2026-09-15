from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import tempfile
import threading
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class QuietHandler(SimpleHTTPRequestHandler):
    def log_message(self, format: str, *args: object) -> None:
        pass


def one_archive(pattern: str) -> Path:
    matches = list(ROOT.glob(pattern))
    if len(matches) != 1:
        raise RuntimeError(f"Expected one {pattern} archive, found {len(matches)}")
    return matches[0]


def check_cli(name: str, command: list[str], root: Path, env: dict[str, str], version: str) -> None:
    user = root / f"{name}-user"
    user.mkdir()
    module = user / "wezterm"
    config = module / "codex_statusline_config.json"
    env = {**env, "CODEX_STATUSLINE_USER_HOME": str(user)}
    common = ["--codex-home", str(user / "codex"), "--wezterm-module-dir", str(module), "--json"]

    def invoke(args: list[str], expected: int = 0) -> str:
        print(f"{name}: {' '.join(args)}", flush=True)
        result = subprocess.run(
            [*command, *common, *args], cwd=root, env=env, capture_output=True,
            text=True, encoding="utf-8", timeout=180,
        )
        if result.returncode != expected:
            raise RuntimeError(
                f"{name} {args}: expected exit {expected}, got {result.returncode}\n"
                f"{result.stdout}\n{result.stderr}"
            )
        return result.stdout

    if invoke(["--version"]).strip() != version:
        raise RuntimeError(f"{name}: unexpected package version")
    invoke(["install", "--no-title-bridge"])
    invoke(["configure", "--label", "REMOTE", "--rows", "2", "--no-powerline"])
    saved_config = config.read_bytes()
    wezterm_config = user / ".wezterm.lua"
    wezterm_config.write_text('require("codex_statusline").setup()\n', encoding="utf-8")
    invoke(["doctor"])
    invoke(["update", "--no-title-bridge"])
    invoke(["doctor"])
    invoke(["uninstall"], expected=3)
    if not (module / "codex_statusline.lua").exists():
        raise RuntimeError(f"{name}: guarded uninstall removed the module")
    wezterm_config.unlink()
    invoke(["uninstall"])
    if (module / "codex_statusline.lua").exists() or config.read_bytes() != saved_config:
        raise RuntimeError(f"{name}: uninstall failed to remove modules or preserve config")
    print(f"{name}: remote package installation and lifecycle passed", flush=True)


def main() -> None:
    parser = argparse.ArgumentParser(description="Test package URLs in isolated npx and uvx environments")
    parser.add_argument("--base-url", help="Published release download URL; defaults to serving local archives")
    args = parser.parse_args()
    npx, uvx = shutil.which("npx"), shutil.which("uvx")
    if not npx or not uvx:
        raise RuntimeError("Both npx and uvx must be available on PATH")
    version = json.loads((ROOT / "packages/npm/package.json").read_text(encoding="utf-8"))["version"]
    archives = [one_archive("packages/npm/*.tgz"), one_archive("packages/python/dist/*.whl")]
    with tempfile.TemporaryDirectory(prefix="wcsline-remote-packages-") as temp:
        root = Path(temp)
        artifacts = root / "artifacts"
        artifacts.mkdir()
        for archive in archives:
            shutil.copy2(archive, artifacts / archive.name)
        npm_config = root / "npmrc"
        npm_config.write_text("", encoding="utf-8")
        env = {
            **os.environ,
            "npm_config_cache": str(root / "npm-cache"),
            "npm_config_userconfig": str(npm_config),
            "npm_config_registry": "https://registry.npmjs.org/",
            "npm_config_update_notifier": "false",
            "UV_CACHE_DIR": str(root / "uv-cache"),
            "UV_TOOL_DIR": str(root / "uv-tools"),
            "UV_NO_CONFIG": "1",
            "PYTHONPATH": "",
            "PYTHONIOENCODING": "utf-8",
            "NO_COLOR": "1",
        }
        def check_packages(base: str) -> None:
            base = base.rstrip("/") + "/"
            check_cli("npx", [npx, "--yes", f"--package={base}{archives[0].name}",
                              "wezterm-codex-status-line"], root, env, version)
            check_cli("uvx", [uvx, "--from", f"{base}{archives[1].name}",
                              "wezterm-codex-status-line"], root, env, version)

        if args.base_url:
            check_packages(args.base_url)
            return

        server = ThreadingHTTPServer(("127.0.0.1", 0), partial(QuietHandler, directory=str(artifacts)))
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        base = f"http://127.0.0.1:{server.server_port}/"
        try:
            check_packages(base)
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=5)


if __name__ == "__main__":
    main()
