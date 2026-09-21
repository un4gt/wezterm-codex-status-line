---
sidebar_position: 1
title: Configure the status line
description: Adjust the status line in the web preview or terminal, then import and apply the configuration.
---

import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';

# Configure the status line

Use the web preview, the terminal wizard, or Lua. Reload WezTerm after changing configuration.

## Import web configuration

Open the [interactive preview](/preview), adjust fields, colors, icons, and rows, then download `codex_statusline_config.json`.

<Tabs groupId="installer">
<TabItem value="npx" label="npx">

```sh
npx --yes wezterm-codex-status-line@0.1.2 configure --from ./codex_statusline_config.json
```

</TabItem>
<TabItem value="uvx" label="uvx">

```sh
uvx wezterm-codex-status-line configure --from ./codex_statusline_config.json
```

</TabItem>
</Tabs>

The command validates and saves the file, normally at `~/.config/wezterm/codex_statusline_config.json`. Reload WezTerm afterward. The preview's model, token, and task data are sample values; the installed status line uses live session data.

## Use the terminal wizard

Run `configure` without options:

```sh
npx --yes wezterm-codex-status-line@0.1.2 configure
# Or:
uvx wezterm-codex-status-line configure
```

Follow the prompts for the label, rows, fields, and colors. You can also use direct options:

```sh
npx --yes wezterm-codex-status-line@0.1.2 configure --rows 2 --label CODEX
```

Add `--dry-run` to validate and preview without saving.

## Use Lua

Pass only the options you want to override:

```lua
require("codex_statusline").setup({
  label = "CODEX",
  bottom_pane = { rows = 2 },
  render = { powerline = false },
})
```

See [Configuration options](../reference/settings.md) for the complete schema.

## Configuration precedence

Values are merged in this order, with later values taking precedence:

1. Built-in defaults.
2. `options` in `codex_statusline_config.json`.
3. Options passed to `setup({...})`.

Nested objects are merged and arrays are replaced as a whole. Keep `require("codex_statusline").setup()` with no options to use the imported JSON completely.

## Rendering and icons

The preview supports one- or two-row layouts, Powerline separators, and three model display modes: name, icon plus name, or icon only. If your font lacks Powerline or Nerd Font glyphs, run:

```sh
npx --yes wezterm-codex-status-line@0.1.2 configure --no-powerline
```

Set the project icon to `>_` if it still renders incorrectly. Lua can select the model display mode:

```lua
require("codex_statusline").setup({
  render = { model_display = "icon_name" },
})
```

## Cost and custom model prices

The preview's cost section can edit built-in prices or add a model. Prices are USD per million tokens and are saved with the JSON.

```lua
require("codex_statusline").setup({
  pricing = {
    models = {
      ["my-model"] = { input = 1, cached_input = 0, output = 2 },
    },
  },
})
```

Cost is accumulated per request using the model used for that request; changing models does not reprice historical usage. The estimate is not an invoice. See [Displayed data](./display-and-data.md#tokens-and-cost) and [Configuration options](../reference/settings.md#cost-and-custom-model-prices).

## Custom configuration paths

The configuration file normally sits beside `codex_statusline.lua`. If you installed with `--wezterm-module-dir`, use the same option with `configure`. `--config-file` changes the CLI read/write location; WezTerm still reads its configuration from the module directory.
