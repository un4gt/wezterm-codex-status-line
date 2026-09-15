from __future__ import annotations

import json
import unittest
import jsonschema
from copy import deepcopy
from importlib import resources

from wezterm_codex_status_line.render import SEGMENT_IDS, build_render_plan, compact_number
from wezterm_codex_status_line import __version__


def load_asset(name: str):
    path = resources.files("wezterm_codex_status_line").joinpath("assets", "contract", name)
    return json.loads(path.read_text(encoding="utf-8"))


class RenderContractTests(unittest.TestCase):
    def test_optional_model_display(self) -> None:
        config = load_asset("default-config.json")
        schema = load_asset("config.schema.json")
        self.assertEqual(config["options"]["render"]["model_display"], "name")
        del config["options"]["render"]["model_display"]
        jsonschema.validate(config, schema)
        for value in ("name", "icon_name", "icon", "auto", "", True, 1, None):
            config["options"]["render"]["model_display"] = value
            with self.subTest(value=value):
                if value in ("name", "icon_name", "icon"):
                    jsonschema.validate(config, schema)
                else:
                    with self.assertRaises(jsonschema.ValidationError):
                        jsonschema.validate(config, schema)

    def test_model_display_tracks_active_model(self) -> None:
        config = load_asset("default-config.json")
        examples = (
            ("gpt-6-astra", "✦"), ("gpt-5.6-sol", "☀"),
            ("openai/gpt-5.6-terra", "⊕"), ("GPT-5.6-LUNA", "☾"),
            ("Astra", "✦"), ("Sol", "☀"), ("Terra", "⊕"), ("Luna", "☾"),
            ("gpt-5.6-codex", None), ("solar", None), ("terramodel", None),
            ("lunatic", None), ("toString", None), ("", None), (None, None),
        )
        for display in (None, "name", "icon_name", "icon"):
            if display is None:
                config["options"]["render"].pop("model_display", None)
            else:
                config["options"]["render"]["model_display"] = display
            for model, icon in examples:
                expected = model or None
                if icon and display in ("icon", "icon_name"):
                    expected = icon if display == "icon" else f"{icon} {model}"
                for columns in (50, 140):
                    with self.subTest(model=model, display=display, columns=columns):
                        plan = build_render_plan(config, {"model": model}, columns)
                        actual = next((segment["text"] for line in plan["lines"]
                                       for segment in line if segment["kind"] == "model"), None)
                        self.assertEqual(actual, expected)
        config["options"]["render"]["disabled_segments"].append("model")
        plan = build_render_plan(config, {"model": "gpt-6-astra"}, 140)
        self.assertFalse(any(segment["kind"] == "model" for line in plan["lines"] for segment in line))

    def test_optional_layout_debounce(self) -> None:
        config = load_asset("default-config.json")
        schema = load_asset("config.schema.json")
        del config["options"]["bottom_pane"]["layout_debounce_ms"]
        jsonschema.validate(config, schema)
        for delay in (250, 1000, 5000, 249, 5001, 250.5, "1000", None):
            config["options"]["bottom_pane"]["layout_debounce_ms"] = delay
            with self.subTest(delay=delay):
                if delay in (250, 1000, 5000):
                    jsonschema.validate(config, schema)
                else:
                    with self.assertRaises(jsonschema.ValidationError):
                        jsonschema.validate(config, schema)

    def test_default_segment_order_is_complete_and_icon_is_last(self) -> None:
        options = load_asset("default-config.json")["options"]
        order = options["render"]["segment_order"]
        self.assertEqual(order, SEGMENT_IDS)
        self.assertEqual(len(order), len(set(order)))
        self.assertEqual(order[-1], "icon")
        self.assertEqual(options["icon"]["text"], "")

    def test_compact_numbers(self) -> None:
        self.assertEqual(compact_number(999), "999")
        self.assertEqual(compact_number(100_000), "100K")
        self.assertEqual(compact_number(200_000), "200K")
        self.assertEqual(compact_number(100_000_000), "100M")
        self.assertEqual(compact_number(999_950), "1M")
        self.assertEqual(compact_number(4_203_817), "4.2M")

    def test_project_icon_precedes_installed_plugin_version(self) -> None:
        config = load_asset("default-config.json")
        order = config["options"]["render"]["segment_order"]
        config["options"]["render"]["segment_order"] = ["icon", *(item for item in order if item != "icon")]
        plan = build_render_plan(config, load_asset("sample-state.json"), 140)
        self.assertEqual(plan["lines"][0][-2]["kind"], "icon")
        self.assertEqual(plan["lines"][0][-1]["kind"], "version")
        self.assertEqual(plan["lines"][0][-1]["text"], f"v{__version__}")

    def test_render_cases(self) -> None:
        defaults = load_asset("default-config.json")
        schema = load_asset("config.schema.json")
        old = deepcopy(defaults)
        del old["options"]["pricing"]
        jsonschema.validate(old, schema)
        for value in (-1, 1000001, None, "1", True):
            invalid = deepcopy(defaults)
            invalid["options"]["pricing"] = {"models": {"my-model": {"input": value, "cached_input": 0, "output": 2}}}
            with self.assertRaises(jsonschema.ValidationError):
                jsonschema.validate(invalid, schema)
        for fixture in load_asset("usage-cases.json"):
            config = deepcopy(defaults)
            if "pricing" in fixture:
                config["options"]["pricing"] = fixture["pricing"]
            jsonschema.validate(config, schema)
            for rows in (1, 2):
                for powerline in (True, False):
                    with self.subTest(name=fixture["name"], rows=rows, powerline=powerline):
                        config["options"]["bottom_pane"]["rows"] = rows
                        config["options"]["render"]["powerline"] = powerline
                        plan = build_render_plan(config, {"model": fixture["model"], "usage": fixture["usage"]}, 180)
                        actual = {segment["kind"]: segment["text"] for segment in plan["lines"][rows - 1]}
                        self.assertEqual([actual.get(key) for key in ("used_tokens", "cache_rate", "cost")], fixture["expected"])

    def test_layout_cases(self) -> None:
        defaults = load_asset("default-config.json")
        sample = load_asset("sample-state.json")
        for fixture in load_asset("render-cases.json"):
            with self.subTest(fixture["name"]):
                config = deepcopy(defaults)
                if fixture["patch"].get("rows"):
                    config["options"]["bottom_pane"]["rows"] = fixture["patch"]["rows"]
                if fixture["patch"].get("modelDisplay"):
                    config["options"]["render"]["model_display"] = fixture["patch"]["modelDisplay"]
                if fixture["patch"].get("disabledAdd"):
                    disabled = config["options"]["render"]["disabled_segments"]
                    config["options"]["render"]["disabled_segments"] = list(
                        dict.fromkeys([*disabled, *fixture["patch"]["disabledAdd"]])
                    )
                state = deepcopy(sample)
                state.update(fixture.get("state", {}))
                plan = build_render_plan(config, state, fixture["columns"])
                actual = {
                    "layout": plan["layout"],
                    "lines": [[[segment["kind"], segment["text"]] for segment in line] for line in plan["lines"]],
                }
                expected = json.loads(json.dumps(fixture["expected"]).replace("$version", f"v{__version__}"))
                self.assertEqual(actual, expected)


if __name__ == "__main__":
    unittest.main()
