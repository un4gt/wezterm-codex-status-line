---
sidebar_position: 3
title: Update and uninstall
description: Update the status line while preserving configuration, or remove the installed files.
---

import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';

# Update and uninstall

## Update

Use `--refresh` with uvx to fetch the latest PyPI package. npx fetches the latest npm package; the examples below pin version `0.1.2`.

<Tabs groupId="installer">
<TabItem value="npx" label="npx">

```sh
npx --yes wezterm-codex-status-line@0.1.2 update
```

</TabItem>
<TabItem value="uvx" label="uvx">

```sh
uvx --refresh wezterm-codex-status-line update
```

</TabItem>
</Tabs>

`update` preserves the display configuration and terminal-title settings. Reload WezTerm, then run `doctor`.

The package version in the npx or uvx command selects the target version. For example, `uvx wezterm-codex-status-line@0.1.2 update` pins uvx to this release.

## Uninstall

Remove the `codex_statusline` module load and `setup()` call from your WezTerm configuration first:

```lua
require("codex_statusline").setup()
```

Reload WezTerm, then run:

<Tabs groupId="installer">
<TabItem value="npx" label="npx">

```sh
npx --yes wezterm-codex-status-line@0.1.2 uninstall
```

</TabItem>
<TabItem value="uvx" label="uvx">

```sh
uvx wezterm-codex-status-line uninstall
```

</TabItem>
</Tabs>

`uninstall` removes status line files and this project's Codex hook. It keeps `codex_statusline_config.json` by default; add `--purge-config` to remove it too.

If the command reports that the module is still referenced, check `~/.wezterm.lua`, `~/.config/wezterm/wezterm.lua`, and files loaded by them.

## Disable the terminal title bridge

`update --no-title-bridge` does not remove an existing title setting. To restore the original Codex title, uninstall as above, reinstall with `install --no-title-bridge`, and add the WezTerm `setup()` call again.

## Preview changes

Add `--dry-run` to `install`, `configure`, `update`, or `uninstall` to inspect the result without writing files:

```sh
npx --yes wezterm-codex-status-line@0.1.2 update --dry-run
```

Pass the same `--wezterm-module-dir` and other path options when using a custom installation directory. See the [CLI reference](../guides/cli-reference.md).
