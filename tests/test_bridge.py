from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tempfile
import threading
import unittest
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PY_BRIDGE = ROOT / "codex_statusline_bridge.py"
PS_BRIDGE = ROOT / "codex_statusline_bridge.ps1"
INSTALLER = ROOT / "install.ps1"
THREAD_ID = "019f75fc-a8b9-7382-8b0c-9739278f57a4"
SESSION_ID = "019f75fc-a8b9-7382-8b0c-9739278f0000"


def payload(rollout: Path) -> str:
    return json.dumps(
        {
            "session_id": SESSION_ID,
            "transcript_path": str(rollout),
            "cwd": str(rollout.parent),
            "hook_event_name": "SessionStart",
            "model": "gpt-5.6-sol",
            "permission_mode": "default",
            "source": "resume",
        }
    )


def ps_quote(value: str | Path) -> str:
    return "'" + str(value).replace("'", "''") + "'"


class QuietHttpHandler(SimpleHTTPRequestHandler):
    def log_message(self, format: str, *args: object) -> None:
        pass


class BridgeTests(unittest.TestCase):
    def test_python_hook_and_installer(self) -> None:
        with tempfile.TemporaryDirectory(prefix="codex-statusline-py-") as temp:
            home = Path(temp)
            existing = {
                "description": "existing",
                "hooks": {
                    "SessionStart": [
                        {"hooks": [{"type": "command", "command": "echo existing"}]}
                    ]
                },
            }
            (home / "hooks.json").write_text(json.dumps(existing), encoding="utf-8")

            install = [sys.executable, str(PY_BRIDGE), "--install", "--codex-home", str(home)]
            subprocess.run(install, check=True, capture_output=True, text=True)
            hooks = json.loads((home / "hooks.json").read_text(encoding="utf-8"))
            plugin_handler = next(
                handler
                for group in hooks["hooks"]["SessionStart"]
                for handler in group.get("hooks", [])
                if "codex_statusline_bridge" in str(handler)
            )
            plugin_handler["command"] = 'python3 "C:/Users/me/.wezterm/codex_statusline_bridge.py"'
            plugin_handler["commandWindows"] = (
                'powershell.exe -File "C:/Users/me/.wezterm/codex_statusline_bridge.ps1"'
            )
            (home / "hooks.json").write_text(json.dumps(hooks), encoding="utf-8")
            subprocess.run(install, check=True, capture_output=True, text=True)
            hooks = json.loads((home / "hooks.json").read_text(encoding="utf-8"))
            handlers = [
                handler
                for group in hooks["hooks"]["SessionStart"]
                for handler in group.get("hooks", [])
            ]
            self.assertEqual(sum("codex_statusline_bridge" in str(item) for item in handlers), 1)
            self.assertTrue(any(item.get("command") == "echo existing" for item in handlers))
            self.assertTrue(any(str(PY_BRIDGE) in item.get("command", "") for item in handlers))
            self.assertTrue((home / "wezterm-statusline" / "bridge.json").exists())

            no_wezterm_env = os.environ.copy()
            no_wezterm_env.update({"CODEX_HOME": str(home)})
            no_wezterm_env.pop("WEZTERM_PANE", None)
            subprocess.run(
                [sys.executable, str(PY_BRIDGE)],
                input="not-json",
                env=no_wezterm_env,
                check=True,
                capture_output=True,
                text=True,
            )
            self.assertFalse((home / "wezterm-statusline" / "panes").exists())

            env = os.environ.copy()
            env.update({"CODEX_HOME": str(home), "WEZTERM_PANE": "42"})
            rollout = home / "sessions" / "2026" / "07" / "19" / "rollout.jsonl"
            rollout.parent.mkdir(parents=True)
            rollout.write_text(
                json.dumps({"type": "session_meta", "payload": {"id": THREAD_ID}}) + "\n",
                encoding="utf-8",
            )
            subprocess.run(
                [sys.executable, str(PY_BRIDGE)],
                input=payload(rollout),
                env=env,
                check=True,
                capture_output=True,
                text=True,
            )
            mapping = json.loads(
                (home / "wezterm-statusline" / "panes" / "42.json").read_text(encoding="utf-8")
            )
            self.assertEqual(mapping["thread_id"], THREAD_ID)
            self.assertEqual(mapping["session_id"], SESSION_ID)
            self.assertEqual(mapping["rollout_path"], str(rollout))
            self.assertTrue(mapping["generation"])

            subprocess.run(
                [sys.executable, str(PY_BRIDGE), "--uninstall", "--codex-home", str(home)],
                check=True,
                capture_output=True,
                text=True,
            )
            hooks = json.loads((home / "hooks.json").read_text(encoding="utf-8"))
            handlers = [
                handler
                for group in hooks["hooks"]["SessionStart"]
                for handler in group.get("hooks", [])
            ]
            self.assertEqual([item.get("command") for item in handlers], ["echo existing"])

    @unittest.skipUnless(shutil.which("pwsh") or shutil.which("powershell"), "PowerShell unavailable")
    def test_powershell_hook_and_installer(self) -> None:
        shell = shutil.which("pwsh") or shutil.which("powershell")
        assert shell is not None
        with tempfile.TemporaryDirectory(prefix="codex-statusline-ps-") as temp:
            home = Path(temp)
            install = [
                shell,
                "-NoProfile",
                "-File",
                str(PS_BRIDGE),
                "-Install",
                "-CodexHome",
                str(home),
            ]
            subprocess.run(install, check=True, capture_output=True, text=True)
            hooks = json.loads((home / "hooks.json").read_text(encoding="utf-8-sig"))
            plugin_handler = next(
                handler
                for group in hooks["hooks"]["SessionStart"]
                for handler in group.get("hooks", [])
                if "codex_statusline_bridge" in str(handler)
            )
            plugin_handler["command"] = 'python3 "C:/Users/me/.wezterm/codex_statusline_bridge.py"'
            plugin_handler["commandWindows"] = (
                'powershell.exe -File "C:/Users/me/.wezterm/codex_statusline_bridge.ps1"'
            )
            (home / "hooks.json").write_text(json.dumps(hooks), encoding="utf-8")
            subprocess.run(install, check=True, capture_output=True, text=True)
            hooks = json.loads((home / "hooks.json").read_text(encoding="utf-8-sig"))
            handlers = [
                handler
                for group in hooks["hooks"]["SessionStart"]
                for handler in group.get("hooks", [])
            ]
            self.assertEqual(sum("codex_statusline_bridge" in str(item) for item in handlers), 1)
            self.assertTrue(
                any(str(PS_BRIDGE).lower() in item.get("commandWindows", "").lower() for item in handlers)
            )

            no_wezterm_env = os.environ.copy()
            no_wezterm_env.update({"CODEX_HOME": str(home)})
            no_wezterm_env.pop("WEZTERM_PANE", None)
            subprocess.run(
                [shell, "-NoProfile", "-File", str(PS_BRIDGE)],
                input="not-json",
                env=no_wezterm_env,
                check=True,
                capture_output=True,
                text=True,
            )
            self.assertFalse((home / "wezterm-statusline" / "panes").exists())

            env = os.environ.copy()
            env.update({"CODEX_HOME": str(home), "WEZTERM_PANE": "77"})
            rollout = home / "sessions" / "rollout.jsonl"
            rollout.parent.mkdir(parents=True)
            rollout.write_text(
                json.dumps({"type": "session_meta", "payload": {"id": THREAD_ID}}) + "\n",
                encoding="utf-8",
            )
            subprocess.run(
                [shell, "-NoProfile", "-File", str(PS_BRIDGE)],
                input=payload(rollout),
                env=env,
                check=True,
                capture_output=True,
                text=True,
            )
            mapping = json.loads(
                (home / "wezterm-statusline" / "panes" / "77.json").read_text(encoding="utf-8-sig")
            )
            self.assertEqual(mapping["thread_id"], THREAD_ID)
            self.assertEqual(mapping["session_id"], SESSION_ID)
            self.assertEqual(mapping["rollout_path"], str(rollout))

    @unittest.skipUnless(shutil.which("powershell.exe"), "Windows PowerShell unavailable")
    def test_windows_full_installer(self) -> None:
        shell = shutil.which("powershell.exe")
        assert shell is not None
        with tempfile.TemporaryDirectory(prefix="codex-statusline-install-") as temp:
            root = Path(temp)
            home = root / "codex-home"
            module_dir = root / "wezterm-modules"
            command = [
                shell,
                "-NoProfile",
                "-ExecutionPolicy",
                "Bypass",
                "-File",
                str(INSTALLER),
                "-Install",
                "-CodexHome",
                str(home),
                "-WezTermModuleDir",
                str(module_dir),
            ]
            subprocess.run(command, check=True, capture_output=True, text=True)

            self.assertEqual(
                (module_dir / "codex_statusline.lua").read_bytes(),
                (ROOT / "codex_statusline.lua").read_bytes(),
            )
            self.assertEqual(
                (module_dir / "codex_statusline_core.lua").read_bytes(),
                (ROOT / "codex_statusline_core.lua").read_bytes(),
            )
            bridge_bin = home / "wezterm-statusline" / "bin"
            installed_ps = bridge_bin / "codex_statusline_bridge.ps1"
            installed_py = bridge_bin / "codex_statusline_bridge.py"
            self.assertTrue(installed_ps.exists())
            self.assertTrue(installed_py.exists())

            hooks = json.loads((home / "hooks.json").read_text(encoding="utf-8-sig"))
            handlers = [
                handler
                for group in hooks["hooks"]["SessionStart"]
                for handler in group.get("hooks", [])
            ]
            self.assertEqual(len(handlers), 1)
            self.assertIn(str(installed_ps).lower(), handlers[0]["commandWindows"].lower())
            manifest = json.loads(
                (home / "wezterm-statusline" / "bridge.json").read_text(encoding="utf-8-sig")
            )
            self.assertEqual(manifest["schema"], 2)
            self.assertEqual(Path(manifest["wezterm_module_dir"]), module_dir)

            uninstall = command.copy()
            uninstall[uninstall.index("-Install")] = "-Uninstall"
            subprocess.run(uninstall, check=True, capture_output=True, text=True)
            self.assertFalse((module_dir / "codex_statusline.lua").exists())
            self.assertFalse((module_dir / "codex_statusline_core.lua").exists())
            hooks = json.loads((home / "hooks.json").read_text(encoding="utf-8-sig"))
            self.assertEqual(hooks["hooks"]["SessionStart"], [])

    @unittest.skipUnless(shutil.which("powershell.exe"), "Windows PowerShell unavailable")
    def test_windows_remote_bootstrap(self) -> None:
        shell = shutil.which("powershell.exe")
        assert shell is not None
        handler = partial(QuietHttpHandler, directory=str(ROOT))
        server = ThreadingHTTPServer(("127.0.0.1", 0), handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            with tempfile.TemporaryDirectory(prefix="codex-statusline-remote-") as temp:
                root = Path(temp)
                home = root / "codex-home"
                module_dir = root / "wezterm-modules"
                base_url = f"http://127.0.0.1:{server.server_port}"
                installer_url = f"{base_url}/install.ps1"
                command = (
                    f"$source = Invoke-RestMethod {ps_quote(installer_url)}; "
                    "& ([scriptblock]::Create([string]$source)) -Install "
                    f"-CodexHome {ps_quote(home)} "
                    f"-WezTermModuleDir {ps_quote(module_dir)} "
                    f"-SourceBaseUrl {ps_quote(base_url)}"
                )
                subprocess.run(
                    [shell, "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", command],
                    check=True,
                    capture_output=True,
                    text=True,
                )
                self.assertTrue((module_dir / "codex_statusline.lua").exists())
                self.assertTrue((module_dir / "codex_statusline_core.lua").exists())
                self.assertTrue(
                    (home / "wezterm-statusline" / "bin" / "codex_statusline_bridge.ps1").exists()
                )
                self.assertTrue((home / "hooks.json").exists())
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=5)


if __name__ == "__main__":
    unittest.main()
