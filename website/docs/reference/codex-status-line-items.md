---
sidebar_position: 3
title: 与 Codex 原生状态栏配合使用
description: 区分 WezTerm 状态栏和 Codex 原生状态栏的配置与数据。
---

# 与 Codex 原生状态栏配合使用

Codex 原生状态栏位于 Codex 界面底部，本扩展的状态栏位于独立的 WezTerm 窗格中。两者可以同时使用。

## 配置位置

| 状态栏 | 配置入口 |
| --- | --- |
| Codex 原生状态栏 | Codex 中的 `/statusline` 命令或 Codex 配置 |
| WezTerm Codex Status Line | 网页预览、`configure` 或 Lua `setup({...})` |

本扩展的安装命令不修改 Codex 原生状态栏选项。`--title-bridge` 配置的是终端标题，供 WezTerm 读取推理强度。

## 字段名称

两个状态栏使用不同的字段名称。编辑本扩展 JSON 时，请使用右侧的配置 ID：

| Codex 原生字段 | 本扩展字段 |
| --- | --- |
| `current-dir` | `cwd` |
| `git-branch` | `git` |
| `context-remaining` | `context` |
| `context-used` | `context_used` |
| `context-window-size` | `context_window` |
| `total-input-tokens` | `input_tokens` |
| `total-output-tokens` | `output_tokens` |
| `thread-id` | `thread_id` |
| `codex-version` | `codex_version` |

完整字段列表见[显示内容](../guides/display-and-data.md#全部-26-个字段)。

## 数据差异

本扩展根据本地会话记录显示数据，因此可能与 Codex 界面存在短暂延迟。调用额度、Enterprise credits、PR 状态等数据不在本扩展的显示范围内。

本扩展的 `used_tokens` 显示累计输入和输出，输入包含缓存。费用使用当前模型单价估算，具体统计方法见[Token 与费用](../guides/display-and-data.md#token-与费用)。
