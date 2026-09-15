from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from typer.testing import CliRunner

from wezterm_codex_status_line.cli import (
    CliFailure,
    State,
    app,
    perform_install,
    perform_uninstall,
)


class CliIntegrationTests(unittest.TestCase):
    def test_install_configure_guard_and_uninstall(self) -> None:
        with tempfile.TemporaryDirectory(prefix="wcsline-python-test-") as temp:
            root = Path(temp)
            codex = root / "codex"
            wezterm = root / "wezterm"
            config_path = wezterm / "codex_statusline_config.json"
            state = State(root, codex, wezterm, config_path, True)
            runner = CliRunner()
            common = ["--codex-home", str(codex), "--wezterm-module-dir", str(wezterm), "--config-file", str(config_path), "--json"]

            result = runner.invoke(app, [
                *common, "configure", "--label", "TEST", "--rows", "2", "--disable", "provider",
                "--no-powerline",
                "--theme-bg", "#010203", "--theme-fg", "#f1f2f3",
                "--color", "label:#112233:#ffffff", "--color", "git:#223344:#aabbcc",
            ])
            self.assertEqual(result.exit_code, 0, result.output)
            configured = json.loads(config_path.read_text(encoding="utf-8"))
            self.assertEqual(configured["options"]["bottom_pane"]["rows"], 2)
            self.assertFalse(configured["options"]["render"]["powerline"])
            self.assertEqual(configured["options"]["theme"]["bg"], "#010203")
            self.assertEqual(configured["options"]["theme"]["segments"]["git"], {"bg": "#223344", "fg": "#aabbcc"})

            configured["options"]["pricing"] = {"models": {"gpt-5.6-sol": {"input": 3, "cached_input": 1, "output": 5}}}
            imported = root / "custom-pricing.json"
            imported.write_text(json.dumps(configured), encoding="utf-8")
            result = runner.invoke(app, [*common, "configure", "--from", str(imported)])
            self.assertEqual(result.exit_code, 0, result.output)
            self.assertEqual(json.loads(config_path.read_text(encoding="utf-8"))["options"]["pricing"], configured["options"]["pricing"])

            result = runner.invoke(app, [*common, "preview"])
            self.assertEqual(result.exit_code, 0, result.output)
            preview = json.loads(result.output)["preview"]
            self.assertIn("gpt-5.6-sol", preview)
            self.assertIn("↑10M ↓204K", preview)
            self.assertIn("Cache 60%", preview)
            self.assertIn("Cost ~$19.02", preview)

            perform_install(state, False, False, False)
            manifest = json.loads((codex / "wezterm-statusline" / "bridge.json").read_text(encoding="utf-8-sig"))
            self.assertEqual(manifest["schema"], 4)
            self.assertEqual(manifest["package"]["runner"], "uvx")
            source = Path(__file__).resolve().parents[3]
            modules = [path.relative_to(source) for path in (source / "codex_statusline").rglob("*.lua")]
            self.assertTrue(modules)
            for module in modules:
                self.assertEqual((wezterm / module).read_bytes(), (source / module).read_bytes())
                self.assertIn(str(wezterm / module), manifest["lua_modules"])

            wezterm_config = wezterm / "wezterm.lua"
            wezterm_config.write_text('require("codex_statusline").setup()\n', encoding="utf-8")
            result = runner.invoke(app, [*common, "doctor"])
            self.assertEqual(result.exit_code, 0, result.output)
            self.assertEqual(json.loads(result.output)["status"], "unchanged")

            config_path.write_text("{invalid json", encoding="utf-8")
            result = runner.invoke(app, [*common, "doctor"])
            self.assertEqual(result.exit_code, 1, result.output)
            self.assertEqual(json.loads(result.output)["warnings"], ["config"])
            config_path.write_text(json.dumps(configured, indent=2) + "\n", encoding="utf-8")

            installed_core = wezterm / "codex_statusline_core.lua"
            core_content = installed_core.read_bytes()
            installed_core.write_text("corrupted", encoding="utf-8")
            result = runner.invoke(app, [*common, "doctor"])
            self.assertEqual(result.exit_code, 1, result.output)
            self.assertEqual(json.loads(result.output)["warnings"], ["asset_integrity"])
            installed_core.write_bytes(core_content)
            layout = wezterm / "codex_statusline" / "layout.lua"
            content = layout.read_bytes()
            layout.unlink()
            result = runner.invoke(app, [*common, "doctor"])
            self.assertEqual(result.exit_code, 1, result.output)
            self.assertEqual(json.loads(result.output)["warnings"], ["asset_integrity"])
            layout.write_bytes(content)

            with self.assertRaises(CliFailure) as blocked:
                perform_uninstall(state, True, False, False)
            self.assertEqual(blocked.exception.exit_code, 3)

            wezterm_config.unlink()
            perform_uninstall(state, False, False, False)
            self.assertTrue(config_path.exists())
            for module in modules:
                self.assertFalse((wezterm / module).exists())


if __name__ == "__main__":
    unittest.main()
