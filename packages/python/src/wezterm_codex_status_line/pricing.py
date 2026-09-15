from __future__ import annotations

import json
import re
from importlib import resources
from math import floor, isfinite
from typing import Any

BUILTIN_PRICES = json.loads(resources.files(__package__).joinpath(
    "assets", "contract", "model-pricing.json").read_text(encoding="utf-8"))["models"]
ALIASES = {"astra": "gpt-6-astra", "sol": "gpt-5.6-sol", "terra": "gpt-5.6-terra", "luna": "gpt-5.6-luna"}


def resolve_model_price(model: str | None, pricing: dict[str, Any] | None = None) -> dict[str, float] | None:
    if not model or not model.strip():
        return None
    full = model.strip().lower()
    bare = full.rsplit("/", 1)[-1]
    base = re.sub(r"-\d{4}-\d{2}-\d{2}$", "", bare)
    for prices in ((pricing or {}).get("models", {}), BUILTIN_PRICES):
        for key in dict.fromkeys((full, bare, base, ALIASES.get(base, base))):
            if key in prices:
                return prices[key]
    return None


def _token_count(value: Any) -> float | None:
    return max(0, value) if isinstance(value, (int, float)) and not isinstance(value, bool) and isfinite(value) else None


def usage_counts(usage: dict[str, Any]) -> dict[str, float | None]:
    cached = _token_count(usage.get("cached")) or 0
    input_raw = _token_count(usage.get("input_raw"))
    net_input = _token_count(usage.get("input"))
    if input_raw is None and net_input is not None:
        input_raw = net_input + cached
    return {"input": input_raw, "cached": min(cached, input_raw) if input_raw is not None else cached,
            "output": _token_count(usage.get("output"))}


def cache_rate(usage: dict[str, Any]) -> float | None:
    counts = usage_counts(usage)
    return floor(counts["cached"] / counts["input"] * 1000 + 0.5) / 10 if counts["input"] else None


def estimate_cost(model: str | None, usage: dict[str, Any], pricing: dict[str, Any] | None = None) -> float | None:
    price = resolve_model_price(model, pricing)
    counts = usage_counts(usage)
    if not price or counts["input"] is None or counts["output"] is None:
        return None
    cost = ((counts["input"] - counts["cached"]) * price["input"]
            + counts["cached"] * price["cached_input"] + counts["output"] * price["output"]) / 1_000_000
    return cost if isfinite(cost) else None


def cost_text(cost: float | None) -> str:
    if cost is None:
        return "Cost —"
    if 0 < cost < 0.01:
        return "Cost <$0.01"
    return f"Cost ~${floor(cost * 100 + 0.5 + 1e-9) / 100:.2f}"
