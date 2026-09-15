from __future__ import annotations

from . import __version__
from .pricing import cache_rate, cost_text, estimate_cost, usage_counts

from copy import deepcopy
from math import floor, isfinite
import re
from typing import Any


SEGMENT_IDS = [
    "label",
    "model",
    "reasoning",
    "activity",
    "provider",
    "personality",
    "service_tier",
    "cwd",
    "project",
    "git",
    "permissions",
    "approval",
    "context",
    "context_used",
    "context_window",
    "used_tokens",
    "cache_rate",
    "cost",
    "input_tokens",
    "cached_tokens",
    "output_tokens",
    "reasoning_tokens",
    "thread_id",
    "task_progress",
    "codex_version",
    "icon",
]
LEGACY_SEGMENT_IDS = [
    "label",
    "model",
    "reasoning",
    "provider",
    "cwd",
    "git",
    "context",
    "used_tokens",
]
DROP_ORDER = [
    "provider",
    "personality",
    "service_tier",
    "codex_version",
    "thread_id",
    "approval",
    "permissions",
    "cached_tokens",
    "reasoning_tokens",
    "input_tokens",
    "output_tokens",
    "context_window",
    "context_used",
    "task_progress",
    "project",
    "cwd",
    "cache_rate",
    "cost",
    "used_tokens",
    "git",
    "reasoning",
    "model",
]
USAGE_SEGMENT_IDS = {
    "context",
    "context_used",
    "context_window",
    "used_tokens",
    "cache_rate",
    "cost",
    "input_tokens",
    "cached_tokens",
    "output_tokens",
    "reasoning_tokens",
}
DEFAULT_ACTIVITY_LABELS = {
    "plan": "PLAN",
    "review": "REVIEW",
    "goal_active": "GOAL",
    "goal_paused": "GOAL PAUSED",
    "goal_blocked": "GOAL BLOCKED",
    "goal_usage_limited": "GOAL LIMITED",
    "goal_budget_limited": "GOAL BUDGET",
    "goal_complete": "GOAL DONE",
}


def _round_half_up(value: float) -> int:
    return floor(value + 0.5)


def compact_number(value: float | int | None) -> str | None:
    if value is None:
        return None
    number = float(value)
    if not isfinite(number):
        return None
    absolute = abs(number)
    sign = "-" if number < 0 else ""
    if absolute < 1000:
        return f"{sign}{_round_half_up(absolute)}"

    units = ((1e12, "T"), (1e9, "B"), (1e6, "M"), (1e3, "K"))
    for index, (divisor, suffix) in enumerate(units):
        if absolute < divisor:
            continue
        scaled = absolute / divisor
        digits = 2 if scaled < 10 else 1 if scaled < 100 else 0
        formatted = f"{scaled:.{digits}f}"
        if float(formatted) >= 1000 and index > 0:
            divisor, suffix = units[index - 1]
            scaled = absolute / divisor
            digits = 2 if scaled < 10 else 1 if scaled < 100 else 0
            formatted = f"{scaled:.{digits}f}"
        if "." in formatted:
            formatted = formatted.rstrip("0").rstrip(".")
        return f"{sign}{formatted}{suffix}"
    return f"{sign}{_round_half_up(absolute)}"


def context_bar(percent: float, cells: int) -> str:
    safe = max(0, min(100, percent))
    width = max(1, int(cells))
    filled = max(0, min(width, _round_half_up((safe / 100) * width)))
    return "█" * filled + "░" * (width - filled)


def render_layout(columns: int) -> str:
    if columns < 60:
        return "tiny"
    if columns < 90:
        return "narrow"
    if columns < 120:
        return "medium"
    return "wide"


def _activity_text(config: dict[str, Any], state: dict[str, Any]) -> str | None:
    activity = state.get("activity") or {}
    labels = config["options"].get("activity", {}).get("labels", {})
    if activity.get("review"):
        return labels.get("review") or DEFAULT_ACTIVITY_LABELS["review"]
    if activity.get("mode") == "plan":
        return labels.get("plan") or DEFAULT_ACTIVITY_LABELS["plan"]
    goal = activity.get("goal") or {}
    status = goal.get("status")
    key_by_status = {
        "active": "goal_active",
        "paused": "goal_paused",
        "blocked": "goal_blocked",
        "usageLimited": "goal_usage_limited",
        "budgetLimited": "goal_budget_limited",
        "complete": "goal_complete",
    }
    key = key_by_status.get(status)
    return (labels.get(key) or DEFAULT_ACTIVITY_LABELS[key]) if key else None


MODEL_ICONS = {"astra": "✦", "sol": "☀", "terra": "⊕", "luna": "☾"}


def _model_text(model: str | None, display: str = "name") -> str | None:
    if not model or display not in {"icon_name", "icon"}:
        return model
    for token in re.findall(r"[a-z0-9]+", model.lower()):
        if icon := MODEL_ICONS.get(token):
            return icon if display == "icon" else f"{icon} {model}"
    return model


def _segment_text(
    segment_id: str,
    config: dict[str, Any],
    state: dict[str, Any],
    layout: str,
) -> str | None:
    options = config["options"]
    if segment_id == "label":
        return state.get("label") or options.get("label") or "CODEX"
    if segment_id == "model":
        return _model_text(state.get("model"), options["render"].get("model_display", "name"))
    if segment_id in {"reasoning", "cwd", "project", "git", "permissions", "approval"}:
        return state.get(segment_id)
    if segment_id == "activity":
        return _activity_text(config, state)
    if segment_id == "provider":
        provider = state.get("provider")
        return f"p:{provider}" if provider and layout == "wide" else provider
    if segment_id == "personality":
        return f"persona:{state['personality']}" if state.get("personality") else None
    if segment_id == "service_tier":
        return f"tier:{state['service_tier']}" if state.get("service_tier") else None
    if segment_id == "thread_id":
        return f"id:{str(state['thread_id'])[:8]}" if state.get("thread_id") else None
    if segment_id == "task_progress":
        progress = state.get("task_progress") or {}
        completed = progress.get("completed")
        total = progress.get("total")
        return f"Tasks {floor(completed)}/{floor(total)}" if completed is not None and total else None
    if segment_id == "codex_version":
        version = str(state.get("codex_version") or "").removeprefix("v")
        return f"v{version}" if version else None
    if segment_id == "icon":
        return options.get("icon", {}).get("text") or ""

    usage = state.get("usage")
    if segment_id == "used_tokens" and usage is not None:
        counts = usage_counts(usage)
        if counts["input"] is None and counts["output"] is None:
            return None
        return f"↑{compact_number(counts['input']) or '—'} ↓{compact_number(counts['output']) or '—'}"
    if segment_id == "cache_rate" and usage is not None:
        rate = cache_rate(usage)
        return "Cache —" if rate is None else f"Cache {rate:g}%"
    if segment_id == "cost" and usage is not None:
        return cost_text(estimate_cost(state.get("model"), usage, options.get("pricing")))
    if segment_id == "context":
        if not usage:
            return state.get("waiting")
        percent = usage.get("context_remaining_percent")
        if percent is not None:
            rounded = max(0, min(100, _round_half_up(float(percent))))
            if layout in {"wide", "medium"}:
                cells = 10 if layout == "wide" else 8
                return f"Ctx {context_bar(rounded, cells)} {rounded}% left"
            return f"Ctx {rounded}% left" if layout == "narrow" else f"Ctx {rounded}%"
        current = compact_number(usage.get("context_tokens"))
        return f"Ctx {current}" if current else state.get("waiting")
    if not usage:
        return None
    if segment_id == "context_used" and usage.get("context_remaining_percent") is not None:
        remaining = max(0, min(100, _round_half_up(float(usage["context_remaining_percent"]))))
        return f"Ctx {100 - remaining}% used"
    value_by_segment = {
        "context_window": (usage.get("context_window"), " window", False),
        "input_tokens": (usage_counts(usage)["input"], "", False),
        "cached_tokens": (usage.get("cached"), " cached", True),
        "output_tokens": (usage.get("output"), "", False),
        "reasoning_tokens": (usage.get("reasoning"), " reasoning", True),
    }
    if segment_id not in value_by_segment:
        return None
    value, suffix, omit_zero = value_by_segment[segment_id]
    compact = compact_number(value)
    prefix = {"input_tokens": "↑", "output_tokens": "↓"}.get(segment_id, "")
    return f"{prefix}{compact}{suffix}" if compact and (not omit_zero or compact != "0") else None


def _plan_width(segments: list[dict[str, str]], powerline: bool) -> int:
    return sum(
        len(segment["text"])
        + (2 if powerline else 0)
        + ((1 if powerline else 2) if index else 0)
        for index, segment in enumerate(segments)
    )


def _fit(segments: list[dict[str, str]], columns: int, powerline: bool) -> list[dict[str, str]]:
    result = deepcopy(segments)
    for segment_id in DROP_ORDER:
        if _plan_width(result, powerline) <= columns:
            break
        result = [segment for segment in result if segment["kind"] != segment_id]
    return result


def _theme_for(options: dict[str, Any], segment_id: str) -> dict[str, str]:
    theme = options["theme"]
    segment_theme = theme.get("segments", {}).get(segment_id) or {}
    return {
        "bg": segment_theme.get("bg") or theme["bg"],
        "fg": segment_theme.get("fg") or theme["fg"],
    }


def _ordered_ids(configured: list[str]) -> list[str]:
    order = list(dict.fromkeys(configured))
    appendable = ["activity", "icon"] if all(item in LEGACY_SEGMENT_IDS for item in order) else SEGMENT_IDS
    expanded = list(dict.fromkeys([*order, *appendable]))
    return [item for item in expanded if item != "icon"] + [item for item in expanded if item == "icon"]


def build_render_plan(config: dict[str, Any], state: dict[str, Any], columns: int) -> dict[str, Any]:
    columns = max(1, int(columns or 120))
    layout = render_layout(columns)
    options = config["options"]
    render = options["render"]
    disabled = set(render.get("disabled_segments", []))
    if layout == "tiny":
        hidden = {
            "reasoning", "provider", "personality", "service_tier", "cwd", "project", "git",
            "permissions", "approval", "context_used", "context_window", "used_tokens", "cache_rate", "cost",
            "input_tokens", "cached_tokens", "output_tokens", "reasoning_tokens", "thread_id",
            "task_progress", "codex_version",
        }
    elif layout == "narrow":
        hidden = {
            "provider", "personality", "service_tier", "project", "permissions", "approval",
            "context_used", "context_window", "input_tokens", "cached_tokens", "output_tokens",
            "reasoning_tokens", "thread_id", "task_progress", "codex_version", "cache_rate", "cost",
        }
    else:
        hidden = set()

    configured = render.get("segment_order") or SEGMENT_IDS
    segments: list[dict[str, str]] = []
    for segment_id in _ordered_ids(configured):
        if segment_id in disabled or segment_id in hidden:
            continue
        text = _segment_text(segment_id, config, state, layout)
        if not text:
            continue
        segments.append({"kind": segment_id, "text": text, **_theme_for(options, segment_id)})

    version = {
        "kind": "version", "text": f"v{__version__}",
        "bg": options["theme"]["bg"], "fg": options["theme"].get("dim") or options["theme"]["fg"],
    }
    powerline = render.get("powerline", True)
    if options["bottom_pane"]["rows"] == 1:
        lines = [_fit([*segments, version], columns, powerline)]
    else:
        metadata = [segment for segment in segments if segment["kind"] not in USAGE_SEGMENT_IDS]
        lines = [
            _fit([*metadata, version], columns, powerline),
            _fit([segment for segment in segments if segment["kind"] in USAGE_SEGMENT_IDS], columns, powerline),
        ]
    return {"layout": layout, "columns": columns, "lines": lines}
