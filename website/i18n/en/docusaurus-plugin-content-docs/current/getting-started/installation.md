---
sidebar_position: 1
title: Installation
description: Install WezTerm Codex Status Line with npx or uvx.
---

import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';

# Installation

Install the status line with `npx` or `uvx`. Both entry points provide the same commands and configuration.

## Requirements

- [WezTerm](https://wezterm.org/) is installed.
- Codex CLI supports the `SessionStart` hook.
- `npx` requires Node.js 20 or later.
- `uvx` requires uv and Python 3.10 or later. uv can download Python when needed.
- Windows requires PowerShell 5.1 or later.

Git is optional and is used to display the branch and project name. The default icon requires a Nerd Font; [switch to plain text](../guides/configuration.md#rendering-and-icons) if icons render as boxes.

macOS has not yet been verified on physical hardware, and Linux has not yet been verified in a Wayland/X11 desktop environment.

## Run the installer

uvx downloads from PyPI and npx downloads from npm.

<Tabs groupId="installer">
<TabItem value="npx" label="npx">

```sh
npx --yes wezterm-codex-status-line@0.1.2 install --no-title-bridge
```

</TabItem>
<TabItem value="uvx" label="uvx">

```sh
uvx wezterm-codex-status-line@0.1.2 install --no-title-bridge
```

</TabItem>
</Tabs>

The command installs status line files under `~/.config/wezterm` and adds the Codex session-start hook. Next, [configure WezTerm](./wezterm-config.md).

## Enable the terminal title bridge

The terminal title lets the status line show a model and reasoning change immediately after `/model`, before another message is sent. On Windows, replace `--no-title-bridge` with `--title-bridge`.

Keep `--no-title-bridge` on macOS and Linux; automatic Codex terminal-title configuration is not supported there yet.

The installer writes this to the Codex configuration:

```toml title="$CODEX_HOME/config.toml"
[tui]
terminal_title = ["app-name", "model", "reasoning", "project-name"]
```

The new setting takes effect in the next Codex session. If an older title bridge is already enabled, run `update --title-bridge` to add the model field while preserving the original title configuration for uninstall. See [Local files and data](../reference/security-and-files.md#terminal-title).

## Custom module directory

The default module directory is `~/.config/wezterm`. If WezTerm uses another configuration directory, pass `--wezterm-module-dir` before the subcommand:

```sh
npx --yes wezterm-codex-status-line@0.1.2 --wezterm-module-dir ./wezterm-config install --no-title-bridge
```

The directory must be on WezTerm's Lua module search path. Use the same path with `configure`, `doctor`, `update`, and `uninstall`.

## Next step

[Configure WezTerm](./wezterm-config.md), then start Codex to see the status line.
