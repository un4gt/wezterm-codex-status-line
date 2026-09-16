# 上游 Codex CLI 状态栏

:::warning[版本快照]

本文只记录官方 Codex CLI 固定提交 `d167a3604c404e4ee4bc5b5d0b7923e24e0f54f8` 的源码行为，不是本项目配置参考。当前插件公开 26 个 segment，见[配置参考](https://un4gt.github.io/wezterm-codex-status-line/docs/reference/settings/#渲染与图标)。

:::

源码快照于 2026-08-14 获取：

- 官方仓库：`openai/codex`
- commit：`d167a3604c404e4ee4bc5b5d0b7923e24e0f54f8`
- 枚举定义：[`status_line_setup.rs`](https://github.com/openai/codex/blob/d167a3604c404e4ee4bc5b5d0b7923e24e0f54f8/codex-rs/tui/src/bottom_pane/status_line_setup.rs)
- 实际取值：[`status_surfaces.rs`](https://github.com/openai/codex/blob/d167a3604c404e4ee4bc5b5d0b7923e24e0f54f8/codex-rs/tui/src/chatwidget/status_surfaces.rs)

## 配置方式

可以在 Codex TUI 中执行 `/statusline`，通过选择器启用、禁用和排序；也可以直接编辑 `$CODEX_HOME/config.toml`：

```toml
[tui]
status_line = [
  "model-with-reasoning",
  "current-dir",
  "git-branch",
  "context-remaining",
  "used-tokens",
]
status_line_use_colors = true
```

- 未配置 `status_line` 时，默认使用 `model-with-reasoning`、`current-dir`。
- 配置为 `status_line = []` 时，隐藏 Codex status line。
- 数组顺序就是显示顺序。
- 暂时无数据的项目会被跳过，不会显示空占位符。
- 无效 ID 会被忽略，并在 thread 启动后警告一次。
- `/statusline` 中的 `Use theme colors` 是设置开关，不是可写入数组的项目 ID。

## 全部 28 项

| 配置 ID | 实际显示内容 | 无数据或关闭时 |
| --- | --- | --- |
| `model` | 当前模型显示名，例如 `gpt-5.2-codex` | 始终显示 |
| `model-with-reasoning` | 模型、effective reasoning effort，以及 ChatGPT 账户可用时的 service tier，例如 `gpt-5.2-codex high Fast` | 始终显示；reasoning 未设置时显示 `default` |
| `reasoning` | 当前 effective reasoning effort，例如 `low`、`medium`、`high`、`xhigh` | 未设置或 `none` 时显示 `default` |
| `current-dir` | 当前工作目录；用户主目录会缩写成 `~` | 始终显示 |
| `project-name` | Git 根目录名；非 Git 项目则尝试使用项目级 `.codex` 配置层的根目录名 | 无法推断项目根目录时省略 |
| `git-branch` | 当前 Git 分支名 | 非 Git 仓库或分支查询尚不可用时省略 |
| `pull-request-number` | 当前分支的开放 PR，例如 `PR #123`；存在 URL 时带下划线和超链接 | 没有开放 PR 或查询失败时省略 |
| `branch-changes` | 当前分支相对默认分支的已提交变更统计，例如 `+120 -35`；零差异显示 `No changes` | 无法计算时省略 |
| `run-state` | 紧凑运行状态：`Starting`、`Ready`、`Working`、`Waiting` 或 `Thinking` | 始终显示 |
| `permissions` | 活跃 permission profile ID，或归纳为 `Read Only`、`Workspace`、`Full Access`、`Custom permissions` | 始终显示 |
| `approval-mode` | `Ask for approval`、`Approve for me`，或当前 approval policy 字符串 | 始终显示 |
| `context-remaining` | `Context N% left` | context window 未知时当前实现回退为 `Context 100% left` |
| `context-used` | `Context N% used` | context window 未知时当前实现回退为 `Context 0% used` |
| `five-hour-limit` | primary/non-weekly rate-limit window 的剩余额度，例如 `5h 73% left`；标签按实际窗口变化 | 没有 rate-limit 数据时省略 |
| `weekly-limit` | weekly/secondary rate-limit window 的剩余额度，例如 `weekly 82% left` | 没有相应窗口时省略 |
| `codex-version` | Codex CLI 版本，例如 `0.144.0` | 始终显示 |
| `context-window-size` | 模型 context window，紧凑格式，例如 `272K window` | runtime 和配置都没有 window 时省略 |
| `used-tokens` | 累计非缓存 input 加 output，例如 `4.2M used` | 结果为 0 时省略 |
| `total-input-tokens` | 累计 raw input，包含 cached input，例如 `82.3M in` | 无数据时显示 `0 in` |
| `total-output-tokens` | 累计 output，例如 `297K out` | 无数据时显示 `0 out` |
| `thread-credits` | Enterprise 当前线程估算 credits，例如 `1.25 credits` | 非 Enterprise 或尚无估算时省略 |
| `estimated-thread-cost` | Enterprise 当前线程估算美元成本 | 非 Enterprise、无 USD 估算或无法格式化时省略 |
| `thread-id` | 完整 thread UUID | thread 尚未创建时省略 |
| `fast-mode` | `Fast on` 或 `Fast off` | 始终显示 |
| `raw-output` | raw scrollback mode 开启时显示 `raw output` | 关闭时省略 |
| `thread-title` | 用户设置的 thread title；没有有效标题时回退到完整 thread UUID | title 和 thread ID 都不可用时省略 |
| `workspace-headline` | Enterprise workspace notification headline | 非 Enterprise、请求失败或无消息时省略 |
| `task-progress` | 最近一次 `update_plan` 的完成进度，例如 `Tasks 2/4` | 没有 plan 或总任务数为 0 时省略 |

## 历史别名

建议新配置使用左侧规范 ID；右侧旧 ID 仍能解析。

| 规范 ID | 可接受别名 |
| --- | --- |
| `model` | `model-name` |
| `project-name` | `project`、`project-root` |
| `run-state` | `status` |
| `approval-mode` | `approval` |
| `context-used` | `context-usage` |
| `thread-id` | `session-id` |

其他 ID 只接受表格中的 kebab-case 拼写；例如 `model_name` 不是有效 ID。

## Token 与 Context 口径

`used-tokens` 使用 `total_token_usage` 的 blended total：

```text
used = max(input_tokens - cached_input_tokens, 0) + max(output_tokens, 0)
```

因此它不把 cached input 加入总量，也不会把 reasoning output 在 output 之外重复计算。

`total-input-tokens` 直接显示累计 `input_tokens`，所以包含 cached input。`total-output-tokens` 直接显示累计 `output_tokens`。Codex status line 没有独立的 cached-input 或 reasoning-output 配置项。

`context-remaining` 和 `context-used` 使用最近一次 `last_token_usage`，并按 Codex 的 12,000 token baseline 计算用户可控上下文比例：

```text
effective_window = context_window - 12,000
used             = max(last_total_tokens - 12,000, 0)
remaining        = round((effective_window - used) / effective_window * 100)
```

token 数字使用紧凑单位 `K`、`M`、`B`、`T`；小于 10 保留最多两位小数，小于 100 保留最多一位，其余取整，并去掉尾随零。

## 渲染规则

- 可用项目用 ` · ` 分隔，顺序与配置数组一致。
- `status_line_use_colors = true` 时，按 active syntax theme 为模型、路径、Git、状态、用量、限额等类别取色。
- `status_line_use_colors = false` 时，所有内容使用 dim 样式。
- `pull-request-number` 在两种颜色模式下都会使用下划线；有 URL 时可点击。
- status line 过长时，由 footer 在右侧 mode/context 指示器之前截断。

## 与当前 WezTerm 插件的映射

| 上游源码项 | 本项目 segment | 说明 |
| --- | --- | --- |
| `model` | `model` | 显示模型名 |
| `reasoning` | `reasoning` | 本项目单独显示 effort |
| `model-with-reasoning` | `model` + `reasoning` + `service_tier` | 本项目使用独立 ID |
| `current-dir` | `cwd` | 名称不同 |
| `project-name` | `project` | 本项目只使用 Git 根目录名，不猜项目级配置根目录 |
| `git-branch` | `git` | 名称不同 |
| `permissions` | `permissions` | 来源为 rollout thread settings / turn context |
| `approval-mode` | `approval` | 来源为 rollout thread settings / turn context |
| `context-remaining` | `context` | 本项目按宽度选择进度条或百分比 |
| `context-used` | `context_used` | 名称使用下划线 |
| `context-window-size` | `context_window` | 名称使用下划线 |
| `used-tokens` | `used_tokens` | 本项目保留 ID，改为显示 ↑输入 ↓输出 |
| `total-input-tokens` | `input_tokens` | 本项目也可单列 `cached_tokens` |
| `total-output-tokens` | `output_tokens` | 本项目也可单列 `reasoning_tokens` |
| `thread-id` | `thread_id` | 本项目默认只显示前 8 位 |
| `codex-version` | `codex_version` | 本项目增加 `v` 前缀 |
| `task-progress` | `task_progress` | 仅预览/显式状态；真实 rollout 不猜测 |

本项目另外提供 `label`、`activity`、`provider`、`personality`、`service_tier`、`cached_tokens`、`reasoning_tokens` 与 `icon`。其中 `activity` 从 rollout 结构化事件识别 Review、Plan 和 Goal，不等同于上游 TUI 内存中的 `run-state`。

`pull-request-number`、`branch-changes`、`run-state`、rate limits、`thread-credits`、`estimated-thread-cost`、`fast-mode`、`raw-output`、`thread-title` 和 `workspace-headline` 依赖 TUI 内存、网络或 Enterprise 状态，无法从 rollout 稳定恢复，当前不实现。请勿把上游 kebab-case ID 直接写入本项目的 `render.segment_order`。
