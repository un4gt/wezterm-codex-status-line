---
sidebar_position: 2
title: Displayed data
description: Field meanings, layout rules, token accounting, and cost estimates.
---

# Displayed data

The status line provides 26 configurable fields. Use the [interactive preview](/preview) to choose fields, order, and colors. The `v0.1.2` marker at the right is the plugin version; `codex_version` is the Codex CLI version.

## All 26 fields

| Field | Meaning |
| --- | --- |
| `label` | Fixed label, default `CODEX` |
| `model` | Current model |
| `reasoning` | Reasoning effort such as `high` |
| `activity` | Review, Plan, or Goal state |
| `provider` | Model provider |
| `personality` | Session personality setting |
| `service_tier` | Service tier |
| `cwd` | Working directory |
| `project` | Git root name, omitted outside Git |
| `git` | Current Git branch |
| `permissions` | Sandbox permission summary |
| `approval` | Approval policy |
| `context` | Remaining context percentage or meter |
| `context_used` | Used context percentage |
| `context_window` | Context capacity, such as `272K window` |
| `used_tokens` | Cumulative input and output, such as `↑10M ↓204K` |
| `cache_rate` | Cached input divided by total input |
| `cost` | Estimated cost, such as `Cost ~$22.48` |
| `input_tokens` | Cumulative input including cached input |
| `cached_tokens` | Cumulative cached input |
| `output_tokens` | Cumulative output including reasoning output |
| `reasoning_tokens` | Cumulative reasoning output |
| `thread_id` | First eight characters of the session ID |
| `task_progress` | Preview-only task progress |
| `codex_version` | Codex CLI version |
| `icon` | Project icon, fixed before the plugin version |

Quota, PR, and Enterprise credit data are outside the extension's scope.

## Special states

`activity` displays `REVIEW`, `PLAN`, or a Goal state. The priority is `REVIEW`, then `PLAN`, then Goal. Goal states include active, paused, blocked, usage limited, budget limited, and complete. Labels can be changed with `activity.labels`.

## Width and rows

| Columns | Behavior |
| ---: | --- |
| Under 60 | Keep label, model, activity, context, and the right marker |
| 60–89 | Hide advanced metadata and token details |
| 90–119 | Use an eight-cell context meter |
| 120 or more | Use a ten-cell meter and show more fields |

When space is still short, lower-priority fields are hidden. Two-row layouts put context, tokens, cache rate, and cost on the second row.

## Tokens and cost

`used_tokens` shows cumulative input and output. Input includes cached input, and output includes reasoning output. `cache_rate` is cached input divided by total input. A missing input shows `Cache —`; a nonzero input with no cache hit shows `Cache 0%`.

Cost is estimated per request and then summed:

```text
request cost = ((input - cached input) × input price
             + cached input × cached price
             + output × output price) / 1,000,000
session cost = sum of request costs
```

Prices are USD per million tokens. Switching models does not change the price assigned to earlier requests. Incomplete history or missing model pricing yields `Cost —`. The estimate excludes long-context, acceleration, cache-write, and tool charges.

## Remaining context

The context fields use the latest request, while token totals cover the whole session. The remaining percentage uses Codex's 12,000-token baseline, is clamped to 0–100%, and falls back to the current context token count when capacity is unknown.

## Waiting states

| Display | Meaning |
| --- | --- |
| `waiting` | No session record has been associated with the current pane |
| `tokens: waiting` | A session is associated, but no usage data has arrived |

A new session normally needs one message first. See [waiting-state troubleshooting](../troubleshooting/common-issues.md#persistent-waiting).

## Refresh rate

The plugin checks process and session changes every second and Git information every five seconds. WezTerm's `status_update_interval` also affects the visible refresh rate.
