---
sidebar_position: 1
title: 配置状态栏
description: 在网页或终端中调整状态栏，并导入和应用配置。
---

import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';

# 配置状态栏

你可以在网页中预览状态栏，也可以使用终端配置向导或 Lua。修改配置后，重新加载 WezTerm 配置以应用更改。

## 导入网页配置

打开[交互预览](/preview)，调整字段、颜色、图标和行数。拖动终端宽度滑块，可以检查不同窗口宽度下的显示效果。

点击“下载 JSON”，得到 `codex_statusline_config.json`。在文件所在目录运行：

<Tabs groupId="installer">
<TabItem value="npx" label="npx">

```sh
npx --yes --package=https://github.com/un4gt/wezterm-codex-status-line/releases/download/v0.1.1/wezterm-codex-status-line-0.1.1.tgz wezterm-codex-status-line configure --from ./codex_statusline_config.json
```

</TabItem>
<TabItem value="uvx" label="uvx">

```sh
uvx wezterm-codex-status-line configure --from ./codex_statusline_config.json
```

</TabItem>
</Tabs>

也可以将 `--from` 后的路径换成文件的完整路径。路径包含空格时，用引号包围。

命令会检查 JSON 并保存配置。默认保存位置为：

```text
~/.config/wezterm/codex_statusline_config.json
```

重新加载 WezTerm 配置，Windows 默认快捷键为 `Ctrl+Shift+R`。

网页中的模型、Token 和任务进度是预览数据，导入后状态栏会使用实际会话的数据。网页的“导入 JSON”用于重新编辑配置；应用到本机仍需运行上面的命令。

## 使用终端向导

运行 `configure`：

<Tabs groupId="installer">
<TabItem value="npx" label="npx">

```sh
npx --yes --package=https://github.com/un4gt/wezterm-codex-status-line/releases/download/v0.1.1/wezterm-codex-status-line-0.1.1.tgz wezterm-codex-status-line configure
```

</TabItem>
<TabItem value="uvx" label="uvx">

```sh
uvx wezterm-codex-status-line configure
```

</TabItem>
</Tabs>

按提示修改标签、行数、显示字段和配色。向导保存到同一个配置文件。

也可以直接提供参数。例如，使用两行布局并修改标签：

```sh
npx --yes --package=https://github.com/un4gt/wezterm-codex-status-line/releases/download/v0.1.1/wezterm-codex-status-line-0.1.1.tgz wezterm-codex-status-line configure --rows 2 --label CODEX
```

在命令末尾添加 `--dry-run`，可以先检查和预览结果。其他参数见[命令行参考](./cli-reference.md#configure)。

## 使用 Lua

在 `setup()` 中传入要修改的选项：

```lua
require("codex_statusline").setup({
  label = "CODEX",
  bottom_pane = { rows = 2 },
  render = { powerline = false },
})
```

Lua 只需要填写要覆盖的选项。完整选项见[配置选项](../reference/settings.md)。

## 配置优先级

配置按以下顺序合并，后面的值覆盖前面的值：

1. 内置默认值。
2. `codex_statusline_config.json` 中的 `options`。
3. `setup({...})` 中的选项。

如果希望完全使用导入的 JSON，保留 `require("codex_statusline").setup()` 即可。

嵌套对象合并，数组整体替换。例如，在 Lua 中设置 `disabled_segments = {}` 会清空隐藏字段列表。

## 渲染与图标

在预览页的“显示与主题”中，可以选择一行或两行布局、Powerline 分隔符和模型显示方式。

字体不包含 Powerline 或 Nerd Font 图标时，关闭 Powerline：

```sh
npx --yes --package=https://github.com/un4gt/wezterm-codex-status-line/releases/download/v0.1.1/wezterm-codex-status-line-0.1.1.tgz wezterm-codex-status-line configure --no-powerline
```

如果项目图标仍显示异常，将预览页中的“项目图标”改成 `>_`。

“模型显示”支持仅名称、图标加名称和仅图标。Lua 示例：

```lua
require("codex_statusline").setup({
  render = { model_display = "icon_name" },
})
```

字段列表和窗口缩小时的显示规则见[显示内容](./display-and-data.md)。

## 费用与自定义模型价格

预览页的“费用与模型单价”可修改内置单价或添加模型。价格以美元/百万 Token 为单位，随 JSON 一起保存。

Lua 示例：

```lua
require("codex_statusline").setup({
  pricing = {
    models = {
      ["my-model"] = { input = 1, cached_input = 0, output = 2 },
    },
  },
})
```

`Cost` 按各次请求使用的模型分别累计，切换模型不会改变此前用量的价格归属。修改某个模型的单价会更新该模型对应的估算费用，结果不代表实际账单。价格匹配规则见[配置选项](../reference/settings.md#费用与自定义模型价格)，计算方法见[Token 与费用](./display-and-data.md#token-与费用)。

## 自定义配置路径

默认配置文件与 `codex_statusline.lua` 位于同一目录。如果安装时使用了 `--wezterm-module-dir`，运行 `configure` 时也传入同一路径。

`--config-file` 只指定 CLI 的读写位置。WezTerm 仍从模块目录读取 `codex_statusline_config.json`，因此日常配置应使用默认位置或指定模块目录。
