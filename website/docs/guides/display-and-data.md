---
sidebar_position: 3
title: 显示与数据口径
description: 理解 26 个字段、特殊状态、响应式规则、Token 和费用估算。
---

# 显示与数据口径

## 当前支持范围

当前渲染器公开 26 个可排序、可隐藏并可单独配色的 segment。默认只启用日常可读的一组字段；高级字段仍会出现在[交互预览](/preview)中，需显式打开。

状态栏最右端固定显示当前已安装插件的版本号，例如 `v0.1.0`，使用 `theme.dim` 配色。它独立于以下可配置字段，关闭项目图标仍会保留；双行布局只在第一行显示一次。`codex_version` 字段则显示 Codex CLI 的版本。

### 全部 26 个字段

| Segment | 显示内容 | 真实运行时来源 |
| --- | --- | --- |
| `label` | 默认 `CODEX` | 配置 |
| `model` | 当前模型 | turn context、session meta、user var 或 Codex 配置回退 |
| `reasoning` | reasoning effort | turn context、session meta、user var 或 Codex 配置回退 |
| `activity` | `REVIEW`、`PLAN` 或 Goal 状态 | rollout 结构化事件 |
| `provider` | provider；wide 时为 `p:<id>` | thread settings、turn context、session meta 或 user var |
| `personality` | `persona:<value>` | thread settings 或 turn context |
| `service_tier` | `tier:<value>` | thread settings、turn context 或 Codex 配置回退 |
| `cwd` | 当前工作目录 | pane 或 rollout 元数据 |
| `project` | Git 根目录名 | 本机 Git 查询；非 Git 目录省略 |
| `git` | 当前 Git 分支 | 本机 Git 查询，rollout 元数据回退 |
| `permissions` | 沙箱/权限摘要 | thread settings 或 turn context |
| `approval` | 审批策略 | thread settings 或 turn context |
| `context` | 剩余比例、进度条或等待状态 | 最近 token usage |
| `context_used` | 已用上下文比例 | `100 - context_remaining_percent` |
| `context_window` | 例如 `272K window` | model context window |
| `used_tokens` | 例如 `↑10M ↓204K` | 累计输入（含缓存）与累计输出 |
| `cache_rate` | 例如 `Cache 60%` | 缓存输入 ÷ 总输入 |
| `cost` | 例如 `Cost ~$22.48` | 当前模型价格与累计 Token 的估算 |
| `input_tokens` | 累计 raw input，含缓存 | total token usage |
| `cached_tokens` | 累计 cached input | total token usage |
| `output_tokens` | 累计 output | total token usage |
| `reasoning_tokens` | reasoning output 子集 | total token usage |
| `thread_id` | `id:` 加线程 ID 前 8 位 | session meta |
| `task_progress` | 例如 `Tasks 2/4` | 仅预览/显式状态；运行时不猜测 rollout |
| `codex_version` | 例如 `v0.144.0` | session meta CLI version |
| `icon` | 默认 Terminal 标识 `` | 配置；固定在右侧插件版本号之前 |

无法从 rollout 稳定还原的上游 TUI 内存状态不会伪装为已支持，例如 PR、branch changes、rate limits、Enterprise credits/cost、raw output 和 workspace headline。上游原生范围见[Codex 状态栏源码参考](../reference/codex-status-line-items.md)。

## 特殊状态

状态识别只读取官方 rollout 中的结构化字段，不根据对话标题或用户提示词猜测：

| 状态 | 结构化来源 |
| --- | --- |
| `PLAN` | `turn_context.payload.collaboration_mode.mode == "plan"` |
| `GOAL` | `event_msg.payload.type == "thread_goal_updated"` |
| `REVIEW` | legacy `entered_review_mode` / `exited_review_mode`，或分页事件中完成的 review item |

Goal 支持 `active`、`paused`、`blocked`、`usageLimited`、`budgetLimited` 和 `complete` 六种状态。若多个状态同时存在，显示优先级固定为：

```text
REVIEW > PLAN > GOAL
```

退出 Review 或后续 turn 切回 default 会同步清理相应状态。`update_plan` 的检查项进度没有稳定 rollout 来源，因此真实运行时不猜测；网页模拟仍保留 `task_progress`，用于检查布局和配色。

## 响应式布局

布局先按状态 pane 列数选择：

| 列数 | 布局 | 初始显示规则 |
| ---: | --- | --- |
| `< 60` | `tiny` | 保留 label、model、activity、context、右侧图标和插件版本；context 为 `Ctx 72%` |
| `60–89` | `narrow` | 隐藏高级元数据和 Token 明细；保留 `used_tokens` 的机会由宽度裁剪决定 |
| `90–119` | `medium` | 可用字段使用 8 格 context 进度条 |
| `>= 120` | `wide` | 可用字段使用 10 格进度条；provider 显示 `p:<id>` |

若初始结果仍超宽，依次移除：

```text
provider → personality → service_tier → codex_version → thread_id → approval
→ permissions → cached_tokens → reasoning_tokens → input_tokens → output_tokens
→ context_window → context_used → task_progress → project → cwd → cache_rate → cost → used_tokens
→ git → reasoning → model
```

`label`、`activity`、`context` 和 `icon` 不在普通丢弃序列中。右侧优先为插件版本号预留空间，再放置项目图标；其余字段按可用宽度裁剪，空白使用主题背景填充。极窄 pane 会省略放不下的图标，并限制版本文字宽度，避免写出边界。

两行模式不会根据内容自动触发。仅当 `bottom_pane.rows = 2` 时，Token/context、缓存率和费用字段进入第二行，其余元数据、右侧图标与版本号位于第一行。

## Token 口径

Codex `token_count` 事件同时包含累计用量和最近一次用量。本项目保存：

| 内部字段 | 含义 |
| --- | --- |
| `input_raw` | 累计 `input_tokens`，包含 cached input |
| `cached` | 累计 `cached_input_tokens` |
| `input` | `max(input_raw - cached, 0)` |
| `output` | 累计 `output_tokens`，已包含 reasoning output |
| `reasoning` | output 中的 reasoning 子集 |
| `total` | `input + output`，保留为内部有效 Token 总数 |
| `context_tokens` | 最近一次 `last_token_usage.total_tokens` |
| `context_window` | `model_context_window` |

`used_tokens` 保留原配置 ID，显示内容改为 `↑输入 ↓输出`。输入包含缓存，输出已包含 reasoning，均为该线程累计值：

```text
↑ = input_raw
↓ = output
cache_rate = round(cached / input_raw × 100, 1)
cost = ((input_raw - cached) × 输入单价 + cached × 缓存单价 + output × 输出单价) / 1,000,000
```

缓存数量限制在总输入范围内；零输入时没有可计算的比例，显示 `Cache —`，无缓存命中显示 `Cache 0%`。最近一次请求的上下文占用仍由 `context` / `context_used` 表示。

`reasoning_output_tokens` 已包含在 output 中，不能再次加入 total。`total_token_usage.total_tokens` 是线程累计消耗，也不能代替当前 context 大小。

数字使用 `K/M/B/T` 紧凑格式，例如 `999`、`1.23K`、`533K`、`4.2M`。边界会向上提升单位，例如 `999950` 显示为 `1M`，不会显示成 `1000K`。有用量数据时零输入输出显示 `↑0 ↓0`；cached 或 reasoning 为 0 时对应明细字段省略。

费用使用当前模型单价估算整段会话，显示两位小数；大于 0 且不足一美分时显示 `Cost <$0.01`，未找到价格或输入/输出数据不完整时显示 `Cost —`。内置价格、覆盖方式和估算范围见[费用与自定义模型价格](./configuration.md#费用与自定义模型价格)。

## Context 剩余百分比

计算使用 Codex 的 12,000-token baseline：

```text
effective_window = context_window - 12,000
used             = max(last_total_tokens - 12,000, 0)
remaining        = round((effective_window - used) / effective_window × 100)
```

结果限制在 `0–100`。context window 未知时优先显示紧凑的当前 context token 数；两者都不可用时显示等待状态。`context_window <= 12,000` 时直接返回 `0%`，避免除以非正数。

## 字形与纯文本

`render.powerline = true` 使用 Powerline 分隔符以及 Git/目录 glyph。模块无法检测当前字体是否包含这些字形。字体不兼容时明确关闭：

```powershell
npx --yes wezterm-codex-status-line@latest configure --no-powerline
```

此时 `render.plain_fallback = true` 使用双空格分隔的纯文本。若字体也不支持默认项目图标，可将 `icon.text` 改为 ASCII 回退 `>_`。

## 等待、刷新与缓存

| 显示 | 含义 |
| --- | --- |
| `waiting` | 尚未取得可用 mapping 或 rollout |
| `tokens: waiting` | rollout 已绑定，但尚无首个 token 用量事件 |

启用 `debug = true` 后，可在 WezTerm 日志中查看 `bridge_wait_reason`、`bridge_fallback_reason`、候选数量与 rollout 来源。

默认进程树缓存为 1 秒、rollout tail 间隔为 1 秒、Git 缓存为 5 秒。实际更新频率还受 `config.status_update_interval` 控制；快速开始建议设置为 500 ms。
