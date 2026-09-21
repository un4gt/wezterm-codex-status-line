---
sidebar_position: 1
title: Troubleshooting
description: Check the installation and solve status line, session, and display problems.
---

import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';

# Troubleshooting

## Check the installation

Run `doctor` first:

<Tabs groupId="installer">
<TabItem value="npx" label="npx">

```sh
npx --yes wezterm-codex-status-line@0.1.2 doctor
```

</TabItem>
<TabItem value="uvx" label="uvx">

```sh
uvx wezterm-codex-status-line doctor
```

</TabItem>
</Tabs>

`OK` means a check passed and `MISSING` means it did not. Add the global `--json` option for details:

```sh
npx --yes wezterm-codex-status-line@0.1.2 --json doctor
```

## Status line module not found

For `module 'codex_statusline' not found`, verify that `codex_statusline.lua` exists in the module directory and that WezTerm contains:

```lua
require("codex_statusline").setup()
```

The default directory is `~/.config/wezterm`. A custom directory must be on WezTerm's Lua module path. Run a complete update if a child module is missing:

```sh
npx --yes wezterm-codex-status-line@0.1.2 update
```

## Session-start hook failed

Run `doctor` and inspect `hooks` and `asset_integrity`. Ensure the reported `codex_home` matches the directory used by Codex, then run `update` and start a new session. Check `hooks.json` if another terminal still reports the error.

## Codex is running but no status line appears

1. Confirm `setup()` is loaded and reload WezTerm.
2. Set `config.status_update_interval = 500` or keep another positive interval.
3. Start a new Codex session and send a message.
4. Run `doctor` and confirm the module and hook checks.

`doctor` checks files; it cannot verify a live pane.

## Persistent `waiting`

The status line has not found a record for the current pane. Send a message, then check the session hook, `$CODEX_HOME`, the local WezTerm pane, and whether several sessions share the same directory. In `auto` mode, ambiguous matches remain `waiting`.

## Persistent `tokens: waiting`

The session is associated, but no token usage has arrived. Send a message and wait for Codex to return usage data; opening the session picker alone does not create usage data.

## `/model` still shows the old model

Enable the [terminal title bridge](../getting-started/installation.md#enable-the-terminal-title-bridge). It reads the new model before the next message. Windows users can run `update --title-bridge`, reload WezTerm, and start or resume Codex again. A title like `codex | gpt-5.6-sol | high | app` includes the live model; the old three-part title only provided reasoning in real time.

## Imported configuration has no effect

Run `configure --from <path>` to import the downloaded JSON, then reload WezTerm. Importing JSON inside the web preview only changes the browser preview. Check whether `setup({...})` overrides the same options.

## Invalid JSON configuration

Use `--dry-run`:

```sh
npx --yes wezterm-codex-status-line@0.1.2 configure --from ./codex_statusline_config.json --dry-run
```

Export a complete configuration from the preview. Common errors include missing fields, unknown keys, invalid color formats, duplicate fields, and an empty order list.

## Icons render as boxes

Use a Nerd Font or disable Powerline:

```sh
npx --yes wezterm-codex-status-line@0.1.2 configure --no-powerline
```

Set `icon.text` to `>_` if the project icon remains unreadable.

## Duplicate status lines

Update the plugin and reload WezTerm. Close extra panes after confirming that only one status line remains per Codex pane. The version marker helps verify which installation is active.

## Incorrect placement after splitting

Split before starting Codex. Splitting above an existing status line can make it span multiple panes; the plugin preserves the layout. Restart Codex or emit `codex-statusline-show` after manually closing it.

## Status line remains after Codex exits

The plugin waits two seconds after confirming exit. If the process is still alive or cannot be inspected, it keeps the pane. Run `update`, reload WezTerm, and inspect `bottom_pane.close_grace_seconds` and debug logs.

## Download failures

Package installation needs access to npm or PyPI. uv may also need access to download Python and dependencies. Check terminal proxy settings (`HTTP_PROXY` and `HTTPS_PROXY`) and network access to the selected registry.

## Collect debug information

Enable logging:

```lua
require("codex_statusline").setup({ debug = true })
```

When filing an [Issue](https://github.com/un4gt/wezterm-codex-status-line/issues), include your OS, WezTerm, Codex, and plugin versions, reproduction steps, `--json doctor` output, `CODEX_STATUSLINE_LOADED`, and relevant logs. Remove usernames, paths, session IDs, and private commands before sharing. Disable `debug` after troubleshooting.
