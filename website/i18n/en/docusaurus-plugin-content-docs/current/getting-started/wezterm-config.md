---
sidebar_position: 2
title: Configure WezTerm
description: Load the status line, verify the installation, and start your first Codex session.
---

import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';

# Configure WezTerm

After installation, call `setup()` once from your WezTerm configuration.

## Load the status line

Add this before `return config`:

```lua
config.status_update_interval = 500
require("codex_statusline").setup()
```

`status_update_interval` is measured in milliseconds. Keep your existing positive interval if you already set one.

A minimal configuration looks like this:

```lua title="~/.wezterm.lua"
local wezterm = require("wezterm")
local config = wezterm.config_builder()

config.status_update_interval = 500
require("codex_statusline").setup()

return config
```

The default `~/.config/wezterm` directory is on WezTerm's module search path. With a custom directory, make sure `require("codex_statusline")` can find the installed module.

## Verify the installation

Reload the WezTerm configuration. The default Windows shortcut is `Ctrl+Shift+R`. Then run:

<Tabs groupId="installer">
<TabItem value="npx" label="npx">

```sh
npx --yes wezterm-codex-status-line@0.1.2 doctor
```

</TabItem>
<TabItem value="uvx" label="uvx">

```sh
uvx wezterm-codex-status-line@0.1.2 doctor
```

</TabItem>
</Tabs>

`OK` means the installation files and configuration are valid. If a check fails, follow the [troubleshooting guide](../troubleshooting/common-issues.md).

## Start Codex

Start `codex` in a WezTerm pane and send a message. The status line appears below that pane after Codex reports usage data. Multiple Codex panes can show independent status lines.

## Adjust the appearance

Use the [interactive preview](/preview) to select fields and colors, then follow [Configure the status line](../guides/configuration.md) to import the JSON.
