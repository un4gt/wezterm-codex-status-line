---
sidebar_position: 1
title: 安装
description: 使用 npx 或 uvx 安装 WezTerm Codex Status Line。
---

import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';

# 安装

使用 `npx` 或 `uvx` 安装状态栏。两个入口提供相同的命令和配置，任选一个即可。

## 要求

- 已安装 [WezTerm](https://wezterm.org/)。
- Codex CLI 支持 `SessionStart` hook。
- 使用 `npx` 时，需要 Node.js 20 或更高版本。
- 使用 `uvx` 时，需要 uv 和 Python 3.10 或更高版本。uv 可以按需下载 Python。
- Windows 需要 PowerShell 5.1 或更高版本。

Git 用于显示分支和项目名，为可选依赖。默认图标需要 Nerd Font；显示方块或乱码时，可[切换为纯文本](../guides/configuration.md#渲染与图标)。

macOS 暂未完成实机验证；Linux 暂未完成 Wayland/X11 桌面验证。

## 运行安装命令

选择一种方式安装：uvx 从 PyPI 下载，npx 从 npm 下载。

<Tabs groupId="installer">
<TabItem value="npx" label="npx">

```sh
npx --yes wezterm-codex-status-line@0.1.2 install --no-title-bridge
```

</TabItem>
<TabItem value="uvx" label="uvx">

```sh
uvx wezterm-codex-status-line install --no-title-bridge
```

</TabItem>
</Tabs>

命令将状态栏文件安装到 `~/.config/wezterm`，并添加 Codex 会话启动 hook。接下来[配置 WezTerm](./wezterm-config.md)，加载状态栏。

## 启用终端标题

终端标题可以让状态栏在 `/model` 切换后及时显示模型和推理强度，无需发送新消息。Windows 用户可将安装命令末尾的 `--no-title-bridge` 替换为 `--title-bridge` 来启用此功能。

macOS 和 Linux 请保留 `--no-title-bridge`。这两个平台暂不支持自动配置 Codex 终端标题。

启用后，安装器会在 Codex 配置中写入：

```toml title="$CODEX_HOME/config.toml"
[tui]
terminal_title = ["app-name", "model", "reasoning", "project-name"]
```

新配置从下一次 Codex 会话开始生效。已启用旧标题桥的用户运行 `update --title-bridge` 后，安装器会补上模型字段，并保留卸载时需要恢复的原始标题配置。关闭此功能时，状态栏仍可读取会话记录中的模型、推理强度和用量。卸载时的标题恢复规则见[本地文件与数据](../reference/security-and-files.md#终端标题)。

## 自定义目录

默认安装目录为 `~/.config/wezterm`。如果 WezTerm 使用其他配置目录，在子命令之前传入 `--wezterm-module-dir`：

```sh
npx --yes wezterm-codex-status-line@0.1.2 --wezterm-module-dir ./wezterm-config install --no-title-bridge
```

该目录需要位于 WezTerm 的 Lua 模块搜索路径中。以后运行 `configure`、`doctor`、`update` 或 `uninstall` 时，也要传入同一路径。文件位置和环境变量见[本地文件与数据](../reference/security-and-files.md)。

## 下一步

[配置 WezTerm](./wezterm-config.md)，然后启动 Codex 查看状态栏。
