---
sidebar_position: 3
title: 更新与卸载
description: 更新状态栏、保留配置或卸载已安装的文件。
---

import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';

# 更新与卸载

## 更新

从 [Releases](https://github.com/un4gt/wezterm-codex-status-line/releases) 选择目标版本，将其安装命令中的 `install --no-title-bridge` 替换为 `update`。

下面以 v0.1.0 为例：

<Tabs groupId="installer">
<TabItem value="npx" label="npx">

```sh
npx --yes --package=https://github.com/un4gt/wezterm-codex-status-line/releases/download/v0.1.0/wezterm-codex-status-line-0.1.0.tgz wezterm-codex-status-line update
```

</TabItem>
<TabItem value="uvx" label="uvx">

```sh
uvx --from https://github.com/un4gt/wezterm-codex-status-line/releases/download/v0.1.0/wezterm_codex_status_line-0.1.0-py3-none-any.whl wezterm-codex-status-line update
```

</TabItem>
</Tabs>

`update` 保留显示配置和终端标题设置。完成后重新加载 WezTerm 配置，再运行 `doctor` 检查安装。

命令中的下载地址决定目标版本。重复使用 v0.1.0 的地址会重新安装 v0.1.0。

## 卸载

先从 WezTerm 配置中移除 `codex_statusline` 的加载语句及 `setup()` 调用，例如：

```lua
require("codex_statusline").setup()
```

重新加载 WezTerm 配置，然后运行：

<Tabs groupId="installer">
<TabItem value="npx" label="npx">

```sh
npx --yes --package=https://github.com/un4gt/wezterm-codex-status-line/releases/download/v0.1.0/wezterm-codex-status-line-0.1.0.tgz wezterm-codex-status-line uninstall
```

</TabItem>
<TabItem value="uvx" label="uvx">

```sh
uvx --from https://github.com/un4gt/wezterm-codex-status-line/releases/download/v0.1.0/wezterm_codex_status_line-0.1.0-py3-none-any.whl wezterm-codex-status-line uninstall
```

</TabItem>
</Tabs>

`uninstall` 移除状态栏文件和本项目的 Codex hook，默认保留 `codex_statusline_config.json`。要同时删除显示配置，在命令末尾添加 `--purge-config`。

如果命令提示模块仍被引用，请检查 `~/.wezterm.lua`、`~/.config/wezterm/wezterm.lua` 及它们加载的其他配置文件。

## 关闭终端标题功能

`update --no-title-bridge` 会保留已经写入的标题设置。要恢复原来的 Codex 标题，先按上面的步骤卸载，再使用 `install --no-title-bridge` 重新安装，最后恢复 WezTerm 中的 `setup()` 调用。

## 预览更改

在 `install`、`configure`、`update` 或 `uninstall` 后添加 `--dry-run`，可以查看操作结果而不写入文件：

```sh
npx --yes --package=https://github.com/un4gt/wezterm-codex-status-line/releases/download/v0.1.0/wezterm-codex-status-line-0.1.0.tgz wezterm-codex-status-line update --dry-run
```

自定义安装目录需要继续传入相同的 `--wezterm-module-dir` 等路径选项。完整参数见[命令行参考](../guides/cli-reference.md)。
