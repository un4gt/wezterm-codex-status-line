---
sidebar_position: 3
title: Sessions and panes
description: Understand multiple Codex sessions, resumed sessions, and pane layout behavior.
---

# Sessions and panes

Every WezTerm pane running Codex gets its own status line. Multiple Codex sessions can run in one tab.

## Session association

The `SessionStart` hook records the relationship between a Codex session and its WezTerm pane. The status line uses that mapping to read local session records and display the model, reasoning effort, and usage.

The default `auto` mode uses the exact hook mapping. After resuming a session, the new mapping may appear only after the first message. While waiting, a single matching active session in the same directory can be used temporarily; ambiguous matches remain `waiting`.

To always wait for the hook mapping:

```lua
require("codex_statusline").setup({
  sessions = { binding_mode = "hook" },
})
```

See [configuration options](../reference/settings.md#session-binding) for the other modes.

## Layout

The status line creates a one- or two-row area below the Codex pane, reserves one separator row, and keeps at least five rows for Codex.

```lua
require("codex_statusline").setup({
  bottom_pane = { rows = 2 },
})
```

After you drag the separator, the status line keeps the chosen height. During resizing or splitting it waits for the layout to settle before repositioning.

Split the tab before starting Codex. Splitting the pane above an existing status line can make it span multiple panes; the plugin keeps the existing layout and realigns when only one Codex pane remains.

## Tabs, hiding, and recovery

The status line remains when focus or tabs change. Moving the Codex pane to another tab closes the old status line and creates one in the new location.

Closing the status line manually hides it until the next Codex session. Emit the `codex-statusline-show` event to restore it:

```lua
{
  key = "S",
  mods = "CTRL|SHIFT",
  action = wezterm.action.EmitEvent("codex-statusline-show"),
}
```

This is only an example; the plugin has no default recovery shortcut.

## After Codex exits

After confirming that Codex exited, the status line waits two seconds before closing. If the process state cannot be confirmed, the existing content remains.

## SSH and tmux

Remote Codex process detection and tmux pane detection are not supported yet. The status line must be able to read the local pane process information and local Codex session records.
