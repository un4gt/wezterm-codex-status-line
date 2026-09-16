---
sidebar_position: 2
title: 本地文件与数据
description: 查询配置文件位置、数据读取范围和卸载后的保留文件。
---

# 本地文件与数据

状态栏使用本地 Codex 会话记录和 WezTerm 窗格信息。运行时不发送网络请求，也不收集遥测。

`npx` 和 `uvx` 下载软件包时需要访问 GitHub Releases；uv 还可能下载 Python 和依赖。

## 文件位置

`~` 表示用户主目录。`$CODEX_HOME` 未设置时，默认为 `~/.codex`。

| 路径 | 用途 |
| --- | --- |
| `~/.config/wezterm/codex_statusline.lua` | WezTerm 加载入口 |
| `~/.config/wezterm/codex_statusline_core.lua` | 状态栏模块 |
| `~/.config/wezterm/codex_statusline/` | 状态栏子模块 |
| `~/.config/wezterm/codex_statusline_config.json` | 显示配置，由 `configure` 创建 |
| `$CODEX_HOME/hooks.json` | Codex hook 配置 |
| `$CODEX_HOME/config.toml` | Codex 配置；启用终端标题时修改 |
| `$CODEX_HOME/wezterm-statusline/bin/` | 会话启动脚本 |
| `$CODEX_HOME/wezterm-statusline/bridge.json` | 安装版本、路径、文件校验值和标题恢复记录 |
| `$CODEX_HOME/wezterm-statusline/panes/` | 窗格与 Codex 会话的映射 |

使用 `--codex-home`、`--wezterm-module-dir` 或 `--config-file` 时，路径随之变化。运行 `doctor` 并添加全局选项 `--json`，可以查看实际使用的路径。

## 各命令的更改

| 命令 | 更改 |
| --- | --- |
| `install`、`update` | 安装状态栏文件，添加或更新会话启动 hook |
| `configure` | 保存显示配置 |
| `preview`、`doctor` | 读取配置并输出结果 |
| `uninstall` | 移除状态栏文件和本项目的 hook，恢复终端标题 |

安装后需要自行在 WezTerm 配置中加载模块，并重新加载配置，步骤见[配置 WezTerm](../getting-started/wezterm-config.md)。

## Hook 备份

修改 `hooks.json` 前，安装器会创建带 `.bak-*` 后缀的备份。已有的其他 hook 和配置字段会保留。

本项目的会话启动脚本也可能在其他终端中被 Codex 调用。没有有效 WezTerm 窗格 ID 时，脚本会直接退出。

## 终端标题

使用 `--title-bridge` 安装时，会修改 Codex 配置中的 `tui.terminal_title`，并保存原值。

卸载时，如果当前值仍是安装器写入的值，就恢复原值；如果你在安装后修改过标题配置，则保留你的修改。配置版本冲突会中止操作并报错。

## 读取的数据

状态栏读取当前窗格的进程信息、工作目录、标题和 WezTerm user vars，以及相关的 Codex 配置和会话记录。Git 分支和项目名来自当前目录的本地 Git 查询。

调试日志和诊断输出可能包含用户名、路径、会话 ID 和 hook 命令。提交公开问题报告前，请移除私人信息。

## 卸载后保留的文件

默认保留 `codex_statusline_config.json`。使用 `uninstall --purge-config` 可以一并删除它。

会话映射文件和备份文件可能保留在 `$CODEX_HOME` 下。它们包含本机路径和会话 ID，分享前请检查内容。

卸载步骤见[更新与卸载](../getting-started/update-uninstall.md#卸载)。
