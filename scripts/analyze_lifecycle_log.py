from __future__ import annotations

import argparse
import json
import re
from collections.abc import Iterable
from pathlib import Path
from typing import Any


TIME_RE = re.compile(r"(?P<hour>\d{2}):(?P<minute>\d{2}):(?P<second>\d{2})\.(?P<millis>\d{3})")
UPDATE_RE = re.compile(
    r"codex_statusline: update w=(?P<window>\S+) tab_id=(?P<tab>\S+) pane_id=(?P<pane>\S+)"
    r".*? active=(?P<active>true|false) tree=(?P<tree>true|false|nil)"
    r".*? reason=(?P<reason>\S+)"
)
CREATED_RE = re.compile(
    r"codex_statusline: created status pane id=(?P<pane>\S+) w=(?P<window>\S+) tab_id=(?P<tab>\S+)"
)
CLOSE_RE = re.compile(
    r"codex_statusline: requesting exact status pane close id=(?P<pane>\S+)"
    r" w=(?P<window>\S+) tab_id=(?P<tab>\S+) reason=(?P<reason>\S+)"
)
STALE_RE = re.compile(
    r"codex_statusline: (?:unable to verify status pane id|stale status pane lookup failed; forgetting id)="
    r"(?P<pane>\S+)"
)
LOAD_MARKER = "codex_statusline: CODEX_STATUSLINE_LOADED"
OWNER_RE = re.compile(r"\bowner_id=(\d+)\b")
LIFECYCLE_RE = re.compile(r"\blifecycle=(running|exited|unknown)\b")
GENERATION_RE = re.compile(r"\bgeneration=(\S+)")
COMPLETED_RE = re.compile(r"codex_statusline: status pane close completed id=(?P<pane>\S+)")
TIMEOUT_RE = re.compile(r"codex_statusline: status pane close timed out id=(?P<pane>\S+)")
DEFERRED_RE = re.compile(r"codex_statusline: layout deferred owner_id=\d+ reason=(?P<reason>\S+)")


def latest_default_log(home: Path | None = None) -> Path | None:
    base = (home or Path.home()) / ".local" / "share" / "wezterm"
    candidates = sorted(
        base.glob("wezterm-gui.exe-log-*.txt"),
        key=lambda path: path.stat().st_mtime,
        reverse=True,
    )
    return candidates[0] if candidates else None


def latest_load_segment(lines: list[str]) -> tuple[list[str], int]:
    start = 0
    for index, line in enumerate(lines):
        if LOAD_MARKER in line:
            start = index
    return lines[start:], start + 1


def warning(code: str, session: str, message: str, **details: Any) -> dict[str, Any]:
    return {"code": code, "session": session, "message": message, **details}


def analyze_lines(
    lines: Iterable[str],
    *,
    slow_exit_seconds: float = 4.0,
    stale_lookup_limit: int = 3,
) -> dict[str, Any]:
    states: dict[str, dict[str, Any]] = {}
    warnings: list[dict[str, Any]] = []
    last_clock: float | None = None
    day_offset = 0.0
    parsed_events = 0

    def event_time(line: str) -> float | None:
        nonlocal day_offset, last_clock
        match = TIME_RE.search(line)
        if not match:
            return None
        clock = (
            int(match["hour"]) * 3600
            + int(match["minute"]) * 60
            + int(match["second"])
            + int(match["millis"]) / 1000
        )
        absolute = clock + day_offset
        if last_clock is not None and absolute < last_clock - 43200:
            day_offset += 86400
            absolute = clock + day_offset
        last_clock = absolute
        return absolute

    def state_for(key: str) -> dict[str, Any]:
        return states.setdefault(
            key,
            {
                "last_active": False,
                "sessions": 0,
                "exit_signal_at": None,
                "status_pane": None,
                "pending_close_pane": None,
                "restart_wait": None,
                "stale": {},
                "owner_mode": key.startswith("owner:"),
                "generation": None,
                "deferred": None,
                "lifecycle": None,
            },
        )

    for line_number, line in enumerate(lines, 1):
        timestamp = event_time(line)
        if timestamp is None:
            continue

        owner = OWNER_RE.search(line)

        def key_for(match: re.Match[str]) -> str:
            return f"owner:{owner[1]}" if owner else f"{match['window']}:{match['tab']}"

        match = DEFERRED_RE.search(line)
        if match and owner:
            parsed_events += 1
            state = state_for(f"owner:{owner[1]}")
            state["deferred"] = match["reason"]
            if match["reason"] == "user-hidden":
                state["status_pane"] = None
                state["restart_wait"] = None
            continue

        match = COMPLETED_RE.search(line)
        if match and owner:
            parsed_events += 1
            state = state_for(f"owner:{owner[1]}")
            if state["pending_close_pane"] == match["pane"]:
                state["pending_close_pane"] = None
            if state["status_pane"] == match["pane"]:
                state["status_pane"] = None
            continue

        match = TIMEOUT_RE.search(line)
        if match and owner:
            parsed_events += 1
            key = f"owner:{owner[1]}"
            state_for(key)["deferred"] = "close-timeout"
            warnings.append(warning("CLOSE_TIMEOUT", key, "exact status pane close was not confirmed within 10s",
                                    pane_id=match["pane"], line=line_number))
            continue

        match = UPDATE_RE.search(line)
        if match:
            parsed_events += 1
            key = key_for(match)
            state = state_for(key)
            active = match["active"] == "true"
            tree = match["tree"]
            reason = match["reason"]

            lifecycle = LIFECYCLE_RE.search(line)
            state["lifecycle"] = lifecycle[1] if lifecycle else None
            generation = GENERATION_RE.search(line)
            new_generation = generation[1] if generation and generation[1] != "nil" else None
            changed = new_generation is not None and state["generation"] is not None and new_generation != state["generation"]
            if active and (not state["last_active"] or changed):
                state["sessions"] += 1
                if state["pending_close_pane"] is not None:
                    state["restart_wait"] = {
                        "line": line_number,
                        "old_pane": state["pending_close_pane"],
                    }

            if new_generation is not None:
                state["generation"] = new_generation
            if state["lifecycle"] == "unknown":
                state["exit_signal_at"] = None
                continue
            if state["last_active"] and (tree == "false" or reason == "terminal-boundary"):
                state["exit_signal_at"] = state["exit_signal_at"] or timestamp
            elif active and tree == "true":
                state["exit_signal_at"] = None

            if not active and state["last_active"] and state["exit_signal_at"] is None:
                state["exit_signal_at"] = timestamp
            state["last_active"] = active
            continue

        match = CREATED_RE.search(line)
        if match:
            parsed_events += 1
            key = key_for(match)
            state = state_for(key)
            if state["owner_mode"] and state["status_pane"] not in (None, match["pane"]):
                warnings.append(warning("OVERLAPPING_STATUS_GENERATIONS", key,
                                        "new status was created before the old status disappeared",
                                        pane_id=match["pane"], old_pane_id=state["status_pane"], line=line_number))
            state["status_pane"] = match["pane"]
            state["pending_close_pane"] = None
            state["restart_wait"] = None
            state["deferred"] = None
            continue

        match = CLOSE_RE.search(line)
        if match:
            parsed_events += 1
            key = key_for(match)
            state = state_for(key)
            signal_at = state["exit_signal_at"]
            if signal_at is not None and not state["deferred"] and match["reason"] == "inactive":
                delay = max(0.0, timestamp - signal_at)
                if delay > slow_exit_seconds:
                    warnings.append(
                        warning(
                            "SLOW_EXIT",
                            key,
                            f"status pane close was requested {delay:.3f}s after the exit signal",
                            delay_seconds=round(delay, 3),
                            pane_id=match["pane"],
                            line=line_number,
                        )
                    )
            state["pending_close_pane"] = match["pane"]
            state["exit_signal_at"] = None
            continue

        match = STALE_RE.search(line)
        if match:
            parsed_events += 1
            pane_id = match["pane"]
            for state in states.values():
                if state["status_pane"] == pane_id or state["pending_close_pane"] == pane_id:
                    stale = state["stale"].setdefault(
                        pane_id,
                        {"count": 0, "first_line": line_number, "last_line": line_number},
                    )
                    stale["count"] += 1
                    stale["last_line"] = line_number
                    break

    for key, state in states.items():
        restart = state["restart_wait"]
        # New logs explicitly report timeout/overlap. A pending or deferred layout
        # at EOF is not evidence of a failed recreation.
        if restart is not None and not state["owner_mode"]:
            warnings.append(
                warning(
                    "STATUS_NOT_RECREATED",
                    key,
                    "Codex became active after a close request but no fresh status pane was created",
                    old_pane_id=restart["old_pane"],
                    line=restart["line"],
                )
            )
        for pane_id, stale in state["stale"].items():
            if stale["count"] >= stale_lookup_limit:
                warnings.append(
                    warning(
                        "STALE_PANE_LOOKUP_LOOP",
                        key,
                        f"stale status pane {pane_id} was looked up {stale['count']} times",
                        pane_id=pane_id,
                        count=stale["count"],
                        first_line=stale["first_line"],
                        last_line=stale["last_line"],
                    )
                )

    return {
        "parsed_events": parsed_events,
        "sessions": sum(state["sessions"] for state in states.values()),
        "warnings": warnings,
    }


def format_report(result: dict[str, Any], path: Path) -> str:
    lines = [
        f"Log: {path}",
        f"Parsed lifecycle events: {result['parsed_events']}",
        f"Detected Codex sessions: {result['sessions']}",
    ]
    warnings = result["warnings"]
    if not warnings:
        lines.append("Lifecycle warnings: none")
        return "\n".join(lines)

    lines.append(f"Lifecycle warnings: {len(warnings)}")
    for item in warnings:
        lines.append(f"- {item['code']} [{item['session']}]: {item['message']}")
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description="Analyze WezTerm Codex status-line lifecycle logs.")
    parser.add_argument("log", nargs="?", type=Path, help="WezTerm GUI log; defaults to the latest user log")
    parser.add_argument("--json", action="store_true", help="Print machine-readable JSON")
    parser.add_argument("--slow-exit-seconds", type=float, default=4.0)
    parser.add_argument("--all-loads", action="store_true", help="Include events before the latest module load")
    args = parser.parse_args()

    path = args.log or latest_default_log()
    if path is None or not path.is_file():
        parser.error("no WezTerm GUI log was found")

    lines = path.read_text(encoding="utf-8", errors="replace").splitlines(keepends=True)
    start_line = 1
    if not args.all_loads:
        lines, start_line = latest_load_segment(lines)
    result = analyze_lines(lines, slow_exit_seconds=max(0.0, args.slow_exit_seconds))
    result["start_line"] = start_line
    if args.json:
        print(json.dumps({"log": str(path), **result}, ensure_ascii=False, indent=2))
    else:
        print(format_report(result, path))
    return 1 if result["warnings"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
