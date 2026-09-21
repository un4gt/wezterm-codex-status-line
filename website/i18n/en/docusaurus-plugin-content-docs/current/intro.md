---
sidebar_position: 1
title: Overview
description: A configurable bottom status line for Codex CLI in WezTerm.
slug: /
---

# WezTerm Codex Status Line

WezTerm Codex Status Line gives every Codex pane its own status line. It shows the model, reasoning effort, working directory, Git branch, context, and token usage.

```text
CODEX | gpt-5.6-sol | high | ~/src/app | main | Ctx 72% left | ↑10M ↓204K | Cache 60% | Cost ~$22.48 |  v0.1.2
```

The status line has 26 configurable fields, colors, icons, and one- or two-row layouts. It shortens or hides lower-priority fields when the terminal is narrow. Data comes from local Codex session records; the plugin does not make model or telemetry requests at runtime.

## Get started

1. [Install the status line](./getting-started/installation.md).
2. [Load it in WezTerm](./getting-started/wezterm-config.md).
3. Start Codex and send a message to see the status line.

Installation requires WezTerm and a Codex CLI that supports the `SessionStart` hook. See the [installation requirements](./getting-started/installation.md#requirements).

## Customize the display

Open the [interactive preview](/preview), adjust fields and colors, download the JSON, and import it locally. You can also use the terminal wizard or Lua. See [Configure the status line](./guides/configuration.md).

Useful references:

- [Displayed data](./guides/display-and-data.md): fields, token accounting, and cost estimates.
- [Configuration options](./reference/settings.md): keys, defaults, and value ranges.
- [CLI reference](./guides/cli-reference.md): commands, arguments, and exit codes.
- [Troubleshooting](./troubleshooting/common-issues.md): installation, waiting states, and display issues.

This extension uses a separate WezTerm pane and can run alongside the [native Codex status line](./reference/codex-status-line-items.md).
