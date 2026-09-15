---
sidebar_position: 1
title: 项目概览
description: 了解 WezTerm Codex Status Line 的用途、边界与支持范围。
slug: /
---

# WezTerm Codex Status Line

WezTerm Codex Status Line 是一个本地 WezTerm 扩展。当前 pane 运行 Codex CLI 时，它会创建独立的底部状态 pane，显示与该 pane 绑定的 Codex thread 信息。

:::note[与 Codex 原生状态栏的区别]

本项目不会修改 Codex TUI，也不会替换或配置 Codex 自带的 footer。文档中的 `render.segment_order` 只控制 WezTerm 底部 pane。

:::

## 当前显示内容

当前版本提供 26 个可排序、可隐藏并可单独配色的 segment。默认启用常用字段，高级字段可在[交互预览](/preview)中打开：

| 分组 | Segment |
| --- | --- |
| 核心 | `label`、`model`、`reasoning`、`activity`、`provider`、`personality`、`service_tier` |
| 项目 | `cwd`、`project`、`git`、`permissions`、`approval` |
| 上下文与 Token | `context`、`context_used`、`context_window`、`used_tokens`、`cache_rate`、`cost`、`input_tokens`、`cached_tokens`、`output_tokens`、`reasoning_tokens` |
| 线程 | `thread_id`、`task_progress`、`codex_version` |
| 标记 | `icon`，默认 Terminal 标识 `` 并固定在状态 pane 右边缘 |

宽度足够且数据完整时，默认输出类似：

```text
CODEX | gpt-5.6-sol | high | p:openai | ~/src/app | main | Ctx ███████░░░ 72% left | ↑10M ↓204K | Cache 60% | Cost ~$22.48 | 
```

具体字段、宽度阈值和 token 口径见[显示与数据口径](./guides/display-and-data.md)。

## 运行方式

1. Lua 模块从当前 pane 的前台进程信息开始识别 Codex。
2. `SessionStart` hook 通过 `WEZTERM_PANE` 写入 pane 与 thread 的映射。
3. Lua 校验映射后增量读取对应 rollout JSONL，并独立查询当前目录的 Git 分支。
4. Codex 退出后，模块只对已记录的状态 pane ID 发起定向关闭。

默认 `auto` 绑定模式在 bridge 已安装时优先使用精确映射。`codex resume` 的新映射尚未到达时，只会在同 CWD、启动时间之后且候选唯一的条件下临时回退；条件不满足时显示等待状态，不猜测 thread。

## 项目边界

- 运行时数据只在本机读取，不上传模型、路径、thread ID 或 token 用量。
- 安装器不会编辑 `.wezterm.lua`，也不会主动 reload WezTerm。
- 状态 pane 无法安全定向关闭时会被保留，不会退回到关闭当前活动 pane 的操作。
- Git 是可选能力；查询失败只隐藏分支，不影响其他 segment。
- Powerline 字形不会自动检测。字体不含相关 glyph 时，应关闭 Powerline 渲染。

## 快速开始

1. 按[安装指南](./getting-started/installation.md)安装 Lua 模块与 `SessionStart` bridge。
2. 手动完成[WezTerm 配置](./getting-started/wezterm-config.md)。
3. 运行 `doctor` 检查文件、Hook、配置引入和资源完整性。
4. 在 WezTerm 中启动新的 Codex 会话并发送第一条消息。
