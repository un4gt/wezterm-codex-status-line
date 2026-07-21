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


def create_fake_codex(root: Path, initial_state: dict[str, object]) -> tuple[Path, Path]:
    state_path = root / "fake-codex-state.json"
    state = {
        "present": False,
        "value": None,
        "version": "v1",
        "version_counter": 1,
        "writes": [],
        "conflicts_remaining": 0,
        "config_file": str(root / "codex-home" / "config.toml"),
    }
    state.update(initial_state)
    state_path.write_text(json.dumps(state), encoding="utf-8")

    server_path = root / "fake_codex.py"
    server_path.write_text(
        r'''import json
import os
import sys

state_path = os.environ["FAKE_CODEX_STATE"]


def load_state():
    with open(state_path, "r", encoding="utf-8") as handle:
        return json.load(handle)


def save_state(state):
    with open(state_path, "w", encoding="utf-8") as handle:
        json.dump(state, handle)


def send(message):
    print(json.dumps(message, separators=(",", ":")), flush=True)


for raw_line in sys.stdin:
    line = raw_line.lstrip("\ufeff").strip()
    if not line:
        continue
    message = json.loads(line)
    method = message.get("method")
    request_id = message.get("id")
    if method == "initialize":
        send({"id": request_id, "result": {"codexHome": os.environ.get("CODEX_HOME")}})
    elif method == "initialized":
        continue
    elif method == "config/read":
        state = load_state()
        user_config = {}
        effective_value = None
        if state["present"]:
            user_config = {"tui": {"terminal_title": state["value"]}}
            effective_value = state["value"]
        send({
            "id": request_id,
            "result": {
                "config": {"tui": {"terminal_title": effective_value}},
                "origins": {},
                "layers": [{
                    "name": {"type": "user", "file": state["config_file"], "profile": None},
                    "version": state["version"],
                    "config": user_config,
                }],
            },
        })
    elif method == "config/batchWrite":
        state = load_state()
        params = message["params"]
        if state.get("conflicts_remaining", 0) > 0:
            state["conflicts_remaining"] -= 1
            save_state(state)
            send({
                "id": request_id,
                "error": {
                    "code": -32000,
                    "message": "Configuration was modified since last read.",
                    "data": {"code": "ConfigVersionConflict"},
                },
            })
            continue
        if params.get("expectedVersion") != state["version"]:
            send({
                "id": request_id,
                "error": {
                    "code": -32000,
                    "message": "Configuration was modified since last read.",
                    "data": {"code": "ConfigVersionConflict"},
                },
            })
            continue
        edit = params["edits"][0]
        value = edit.get("value")
        state["present"] = value is not None
        state["value"] = value
        state["version_counter"] += 1
        state["version"] = f"v{state['version_counter']}"
        state["writes"].append(params)
        save_state(state)
        send({
            "id": request_id,
            "result": {
                "status": "ok",
                "version": state["version"],
                "filePath": state["config_file"],
                "overriddenMetadata": None,
            },
        })
    else:
        send({"id": request_id, "error": {"code": -32601, "message": "unknown method"}})
''',
        encoding="utf-8",
    )
    command_path = root / "codex.cmd"
    command_path.write_text(
        f'@echo off\r\n"{sys.executable}" "{server_path}" %*\r\n',
        encoding="utf-8",
    )
    return command_path, state_path


def read_fake_codex_state(path: Path) -> dict[str, object]:
    return json.loads(path.read_text(encoding="utf-8"))


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

            manifest_path = home / "wezterm-statusline" / "bridge.json"
            manifest_path.write_text(
                json.dumps({"schema": 3, "codex_title_bridge": {"enabled": True}}),
                encoding="utf-8",
            )
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
            self.assertTrue(manifest_path.exists())

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

            manifest_path = home / "wezterm-statusline" / "bridge.json"
            manifest_path.write_text(
                json.dumps({"schema": 3, "codex_title_bridge": {"enabled": True}}),
                encoding="utf-8",
            )
            uninstall = install.copy()
            uninstall[uninstall.index("-Install")] = "-Uninstall"
            subprocess.run(uninstall, check=True, capture_output=True, text=True)
            self.assertTrue(manifest_path.exists())

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
            self.assertEqual(manifest["schema"], 3)
            self.assertEqual(Path(manifest["wezterm_module_dir"]), module_dir)

            uninstall = command.copy()
            uninstall[uninstall.index("-Install")] = "-Uninstall"
            subprocess.run(uninstall, check=True, capture_output=True, text=True)
            self.assertFalse((module_dir / "codex_statusline.lua").exists())
            self.assertFalse((module_dir / "codex_statusline_core.lua").exists())
            hooks = json.loads((home / "hooks.json").read_text(encoding="utf-8-sig"))
            self.assertEqual(hooks["hooks"]["SessionStart"], [])

    @unittest.skipUnless(shutil.which("powershell.exe"), "Windows PowerShell unavailable")
    def test_windows_title_bridge_restores_existing_value(self) -> None:
        shell = shutil.which("powershell.exe")
        assert shell is not None
        with tempfile.TemporaryDirectory(prefix="codex-statusline-title-existing-") as temp:
            root = Path(temp)
            home = root / "codex-home"
            module_dir = root / "wezterm-modules"
            fake_codex, state_path = create_fake_codex(
                root,
                {"present": True, "value": ["thread-title"]},
            )
            env = os.environ.copy()
            env.update(
                {
                    "CODEX_STATUSLINE_CODEX_COMMAND": str(fake_codex),
                    "FAKE_CODEX_STATE": str(state_path),
                }
            )
            command = [
                shell,
                "-NoProfile",
                "-ExecutionPolicy",
                "Bypass",
                "-File",
                str(INSTALLER),
                "-Install",
                "-EnableCodexTitleBridge",
                "-CodexHome",
                str(home),
                "-WezTermModuleDir",
                str(module_dir),
            ]
            subprocess.run(command, env=env, check=True, capture_output=True, text=True)

            installed = read_fake_codex_state(state_path)
            self.assertEqual(installed["value"], ["app-name", "reasoning", "project-name"])
            self.assertEqual(len(installed["writes"]), 1)
            self.assertFalse(installed["writes"][0]["reloadUserConfig"])
            manifest = json.loads(
                (home / "wezterm-statusline" / "bridge.json").read_text(encoding="utf-8-sig")
            )
            title_record = manifest["codex_title_bridge"]
            self.assertTrue(title_record["original_present"])
            self.assertEqual(title_record["original_value"], ["thread-title"])

            subprocess.run(command, env=env, check=True, capture_output=True, text=True)
            self.assertEqual(len(read_fake_codex_state(state_path)["writes"]), 1)

            uninstall = command.copy()
            uninstall.remove("-EnableCodexTitleBridge")
            uninstall[uninstall.index("-Install")] = "-Uninstall"
            subprocess.run(uninstall, env=env, check=True, capture_output=True, text=True)
            restored = read_fake_codex_state(state_path)
            self.assertTrue(restored["present"])
            self.assertEqual(restored["value"], ["thread-title"])
            self.assertEqual(len(restored["writes"]), 2)

    @unittest.skipUnless(shutil.which("powershell.exe"), "Windows PowerShell unavailable")
    def test_windows_title_bridge_removes_added_value_after_version_retry(self) -> None:
        shell = shutil.which("powershell.exe")
        assert shell is not None
        with tempfile.TemporaryDirectory(prefix="codex-statusline-title-new-") as temp:
            root = Path(temp)
            home = root / "codex-home"
            module_dir = root / "wezterm-modules"
            fake_codex, state_path = create_fake_codex(root, {"conflicts_remaining": 1})
            env = os.environ.copy()
            env.update(
                {
                    "CODEX_STATUSLINE_CODEX_COMMAND": str(fake_codex),
                    "FAKE_CODEX_STATE": str(state_path),
                }
            )
            command = [
                shell,
                "-NoProfile",
                "-ExecutionPolicy",
                "Bypass",
                "-File",
                str(INSTALLER),
                "-Install",
                "-EnableCodexTitleBridge",
                "-CodexHome",
                str(home),
                "-WezTermModuleDir",
                str(module_dir),
            ]
            subprocess.run(command, env=env, check=True, capture_output=True, text=True)
            installed = read_fake_codex_state(state_path)
            self.assertEqual(installed["conflicts_remaining"], 0)
            self.assertEqual(installed["value"], ["app-name", "reasoning", "project-name"])

            uninstall = command.copy()
            uninstall.remove("-EnableCodexTitleBridge")
            uninstall[uninstall.index("-Install")] = "-Uninstall"
            subprocess.run(uninstall, env=env, check=True, capture_output=True, text=True)
            restored = read_fake_codex_state(state_path)
            self.assertFalse(restored["present"])
            self.assertIsNone(restored["value"])
            self.assertTrue(all(not write["reloadUserConfig"] for write in restored["writes"]))

    @unittest.skipUnless(shutil.which("powershell.exe"), "Windows PowerShell unavailable")
    def test_windows_title_bridge_preserves_later_user_change(self) -> None:
        shell = shutil.which("powershell.exe")
        assert shell is not None
        with tempfile.TemporaryDirectory(prefix="codex-statusline-title-changed-") as temp:
            root = Path(temp)
            home = root / "codex-home"
            module_dir = root / "wezterm-modules"
            fake_codex, state_path = create_fake_codex(root, {})
            env = os.environ.copy()
            env.update(
                {
                    "CODEX_STATUSLINE_CODEX_COMMAND": str(fake_codex),
                    "FAKE_CODEX_STATE": str(state_path),
                }
            )
            command = [
                shell,
                "-NoProfile",
                "-ExecutionPolicy",
                "Bypass",
                "-File",
                str(INSTALLER),
                "-Install",
                "-EnableCodexTitleBridge",
                "-CodexHome",
                str(home),
                "-WezTermModuleDir",
                str(module_dir),
            ]
            subprocess.run(command, env=env, check=True, capture_output=True, text=True)

            changed = read_fake_codex_state(state_path)
            changed["present"] = True
            changed["value"] = ["thread-title", "git-branch"]
            changed["version_counter"] = int(changed["version_counter"]) + 1
            changed["version"] = f"v{changed['version_counter']}"
            state_path.write_text(json.dumps(changed), encoding="utf-8")

            uninstall = command.copy()
            uninstall.remove("-EnableCodexTitleBridge")
            uninstall[uninstall.index("-Install")] = "-Uninstall"
            result = subprocess.run(
                uninstall,
                env=env,
                check=True,
                capture_output=True,
                text=True,
            )
            self.assertIn("keeping the current user value", result.stdout + result.stderr)
            preserved = read_fake_codex_state(state_path)
            self.assertEqual(preserved["value"], ["thread-title", "git-branch"])

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
