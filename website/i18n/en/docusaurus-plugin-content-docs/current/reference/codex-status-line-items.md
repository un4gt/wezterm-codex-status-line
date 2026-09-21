---
sidebar_position: 3
title: Using the native Codex status line
description: Compare the WezTerm status line with the native Codex status line.
---

# Using the native Codex status line

The native Codex status line lives at the bottom of the Codex interface. This extension runs in a separate WezTerm pane. Both can be enabled together.

## Configuration locations

| Status line | Configuration |
| --- | --- |
| Native Codex status line | The Codex `/statusline` command or Codex configuration |
| WezTerm Codex Status Line | The web preview, `configure`, or Lua `setup({...})` |

The installer does not change native Codex status line options. `--title-bridge` configures the terminal title so WezTerm can read the reasoning effort and live model.

## Field names

The two status lines use different field names:

| Native Codex field | This extension |
| --- | --- |
| `current-dir` | `cwd` |
| `git-branch` | `git` |
| `context-remaining` | `context` |
| `context-used` | `context_used` |
| `context-window-size` | `context_window` |
| `total-input-tokens` | `input_tokens` |
| `total-output-tokens` | `output_tokens` |
| `thread-id` | `thread_id` |
| `codex-version` | `codex_version` |

See [Displayed data](../guides/display-and-data.md#all-26-fields) for the complete list.

## Data differences

This extension reads local session records, so it can briefly lag behind the Codex interface. Quotas, Enterprise credits, and PR status are outside its scope. `used_tokens` includes cached input, and cost is estimated per request using the model active for that request.
