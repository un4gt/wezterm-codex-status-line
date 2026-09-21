---
sidebar_position: 1
title: Configuration options
description: Configuration keys, defaults, and value ranges for the status line.
---

# Configuration options

This page lists configuration keys, defaults, and ranges. Start with [Configure the status line](../guides/configuration.md). JSON options live under `options`; Lua options are passed to `setup({...})`.

## Basics and logging

| Option | Default | Purpose |
| --- | --- | --- |
| `debug` | `false` | Log process matching, session association, and pane lifecycle details |
| `label` | `CODEX` | Fixed status label, 1–24 characters |
| `codex_home` | `""` | Override `$CODEX_HOME`; empty uses the environment or `~/.codex` |
| `log.enabled` | `true` | Write module-load logs |
| `log.marker` | `CODEX_STATUSLINE_LOADED` | Load-log marker |
| `compat.update_right_status` | `false` | Support WezTerm versions using `update-right-status` |
| `codex_config.enabled` | `true` | Read model, reasoning, and service-tier defaults from Codex config |
| `codex_config.path` | `""` | Custom Codex `config.toml` path |
| `codex_config.cache_ttl_seconds` | `5` | Codex configuration cache time |

## Bottom pane, Git, and title

| Option | Default | Purpose |
| --- | --- | --- |
| `bottom_pane.enabled` | `true` | Create the separate bottom status pane |
| `bottom_pane.rows` | `1` | One or two rows when created; dragged height is preserved |
| `bottom_pane.layout_debounce_ms` | `1000` | Wait for layout stability, 250–5000 ms |
| `bottom_pane.close_grace_seconds` | `2` | Delay after Codex exit is confirmed |
| `bottom_pane.prevent_focus` | `true` | Return focus to the Codex pane |
| `git.enabled` | `true` | Query the Git root and branch |
| `git.cache_ttl_seconds` | `5` | Git cache time |
| `title_bridge.enabled` | `true` | Read model and reasoning from the pane title |
| `title_bridge.app_name` | `codex` | Application name in the terminal title |

Enable the Codex title format from the [installation guide](../getting-started/installation.md#enable-the-terminal-title-bridge). The `codex-statusline-show` event restores a manually hidden status pane.

## Session binding

| Option | Default | Purpose |
| --- | --- | --- |
| `sessions.enabled` | `true` | Read pane-to-session mappings and session records |
| `sessions.binding_mode` | `auto` | `auto`, `hook`, or `heuristic` |
| `sessions.bridge_dir` | `""` | Override `$CODEX_HOME/wezterm-statusline` |
| `sessions.allow_fallback_latest` | `false` | Allow the newest record when the working directory is unknown |
| `sessions.resume_fallback_enabled` | `true` | Temporarily use a unique record while resuming in `auto` mode |
| `sessions.resume_fallback_max_age_seconds` | `30` | Candidate activity window, 1–300 |
| `sessions.resume_fallback_clock_skew_seconds` | `5` | Timestamp tolerance, 0–30 |
| `sessions.resume_fallback_scan_ttl_seconds` | `2` | Resume candidate scan cache |
| `sessions.cache_ttl_seconds` | `5` | Mapping and record-path cache |
| `sessions.full_scan_ttl_seconds` | `300` | Full session scan cache |
| `sessions.tail_ttl_seconds` | `1` | Incremental tail-read interval |
| `sessions.open_fail_clear_seconds` | `30` | How long to retain data after repeated read failures |
| `sessions.initial_seek_bytes` | `131072` | Initial bytes read from the file tail |
| `sessions.activity_seek_bytes` | `65536` | Initial activity scan size |
| `sessions.activity_max_seek_bytes` | `8388608` | Maximum activity scan size |
| `sessions.max_meta_lines` | `40` | Maximum metadata lines on the first scan |
| `sessions.max_tail_lines` | `200` | Maximum tail and cost-history lines per scan |

`auto` uses the hook mapping and can temporarily use a unique matching record during resume. `hook` always waits for an exact mapping. `heuristic` matches by working directory and activity time. Keep `allow_fallback_latest = false` when several sessions run in parallel.

## Process matching and user vars

| Option | Default | Purpose |
| --- | --- | --- |
| `process_match.enabled` | `true` | Check whether Codex runs in the pane |
| `process_match.names` | `codex`, `codex.exe` | Recognized Codex process names |
| `process_match.argv_markers` | `/@openai/codex/bin/codex.js` | Node.js launch marker |
| `process_match.terminal_names` | WezTerm process names | Process-tree terminal boundaries |
| `process_match.grace_seconds` | `5` | Process-signal cache time |
| `process_match.tree_cache_ttl_seconds` | `1` | Process-tree cache time |
| `user_vars.model` | `codex_model`, `CODEX_MODEL` | Candidate model variables |
| `user_vars.thinking` | thinking/reasoning candidates | Candidate reasoning variables |
| `user_vars.provider` | provider candidates | Candidate provider variables |
| `user_vars.active` | `codex_active`, `CODEX_ACTIVE` | Candidate activity variables |

Adjust matching only after confirming that the local Codex launch mode is different. Overly broad matching can identify unrelated processes.

## Activity labels

`activity.labels` controls `plan`, `review`, `goal_active`, `goal_paused`, `goal_blocked`, `goal_usage_limited`, `goal_budget_limited`, and `goal_complete`. Defaults are `PLAN`, `REVIEW`, `GOAL`, `GOAL PAUSED`, `GOAL BLOCKED`, `GOAL LIMITED`, `GOAL BUDGET`, and `GOAL DONE`. The fixed priority is `REVIEW > PLAN > GOAL`.

## Rendering and icons

| Option | Default | Purpose |
| --- | --- | --- |
| `icon.text` | `` | Project Terminal glyph before the plugin version |
| `render.powerline` | `true` | Use colored Powerline separators |
| `render.plain_fallback` | `true` | Use plain separators without Powerline |
| `render.model_display` | `name` | `name`, `icon_name`, or `icon` |
| `render.segment_order` | 26 IDs | Field order; `icon` remains the right anchor |
| `render.disabled_segments` | 14 advanced fields | Hidden fields; an empty array enables all |

Model icons are matched case-insensitively for Astra, Sol, Terra, and Luna, including provider prefixes and dated IDs. Configure `theme.bg`, `theme.fg`, `theme.dim`, and per-segment colors with six-digit hexadecimal values. `theme.glyphs` accepts `sep`, `branch`, and `folder`.

## Cost and custom model prices

Built-in prices are USD per million tokens and include current GPT-5.x and Codex model families. The preview can override each model's input, cached-input, and output prices:

```lua
require("codex_statusline").setup({
  pricing = {
    models = {
      ["gpt-5.6-sol"] = { input = 3, cached_input = 0.3, output = 15 },
      ["my-model"] = { input = 1, cached_input = 0, output = 2 },
    },
  },
})
```

Up to 64 finite, non-negative overrides are accepted. Full IDs take precedence, followed by normalized provider/date variants and aliases. A model without a price displays `Cost —`; changing a model does not reprice another model's history.
