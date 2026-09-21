---
sidebar_position: 2
title: 配置 WezTerm
description: 加载状态栏，检查安装并启动第一个 Codex 会话。
---

import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';

# 配置 WezTerm

安装完成后，在 WezTerm 配置中调用一次 `setup()`。

## 加载状态栏

在现有配置的 `return config` 之前加入：

```lua
config.status_update_interval = 500
require("codex_statusline").setup()
```

`status_update_interval` 设置状态更新间隔，单位为毫秒。已有刷新间隔时可以保留原值。

如果还没有 WezTerm 配置文件，可以创建：

```lua title="~/.wezterm.lua"
local wezterm = require("wezterm")
local config = wezterm.config_builder()

config.status_update_interval = 500
require("codex_statusline").setup()

return config
```

默认安装目录 `~/.config/wezterm` 位于 WezTerm 的模块搜索路径中。使用自定义目录时，请确认 `require("codex_statusline")` 能找到该目录下的模块。

## 检查安装

重新加载 WezTerm 配置。Windows 默认快捷键为 `Ctrl+Shift+R`。

然后运行：

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

检查项显示 `OK` 表示安装文件和配置有效。如果检查失败，按[故障排查](../troubleshooting/common-issues.md)中的步骤处理。

## 启动 Codex

在 WezTerm 窗格中启动 `codex`，并发送一条消息。状态栏会出现在该窗格下方，Token 用量在 Codex 返回用量数据后显示。

多个 Codex 窗格可以同时显示各自的状态栏。`doctor` 只检查安装与配置；正在运行的会话需要在 WezTerm 中确认。

## 调整外观

打开[交互预览](/preview)选择字段和配色，然后按照[配置状态栏](../guides/configuration.md)导入 JSON。
