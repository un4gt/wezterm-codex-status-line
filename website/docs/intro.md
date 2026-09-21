---
sidebar_position: 1
title: 概览
description: 为 WezTerm 中的 Codex CLI 添加可配置的底部状态栏。
slug: /
---

# WezTerm Codex Status Line

WezTerm Codex Status Line 在每个 Codex 窗格下方显示独立的状态栏。你可以查看模型、推理强度、工作目录、Git 分支，以及上下文和 Token 用量。

```text
CODEX | gpt-5.6-sol | high | ~/src/app | main | Ctx 72% left | ↑10M ↓204K | Cache 60% | Cost ~$22.48 |  v0.1.2
```

状态栏支持 26 个可配置字段，以及颜色、图标和一行或两行布局。窗口变窄时，会自动缩短或隐藏部分字段。数据来自本地 Codex 会话记录，运行时无需网络请求。

## 开始使用

1. [安装状态栏](./getting-started/installation.md)。
2. [在 WezTerm 中加载](./getting-started/wezterm-config.md)。
3. 启动 Codex 并发送一条消息，查看状态栏。

安装需要 WezTerm 和支持 `SessionStart` hook 的 Codex CLI。平台要求见[安装指南](./getting-started/installation.md#要求)。

## 自定义显示

打开[交互预览](/preview)，调整字段和配色，再下载 JSON 并导入。你也可以使用终端配置向导或 Lua。操作步骤见[配置状态栏](./guides/configuration.md)。

常用资料：

- [显示内容](./guides/display-and-data.md)：字段含义、Token 统计和费用估算。
- [配置选项](./reference/settings.md)：配置键、默认值和取值范围。
- [命令行参考](./guides/cli-reference.md)：命令、参数和退出码。
- [故障排查](./troubleshooting/common-issues.md)：安装检查、等待状态和显示问题。

本扩展使用独立的 WezTerm 窗格，可以与 [Codex 原生状态栏](./reference/codex-status-line-items.md)同时使用。
