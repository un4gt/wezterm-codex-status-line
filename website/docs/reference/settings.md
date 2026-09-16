---
sidebar_position: 1
title: 配置选项
description: 查询状态栏配置选项、默认值和取值范围。
---

# 配置选项

本文列出状态栏的配置键、默认值和取值范围。首次配置请从[配置状态栏](../guides/configuration.md)开始。

在 JSON 中，这些选项位于 `options` 对象内；使用 Lua 时，直接传给 `setup({...})`。完整 JSON 结构见 [配置 schema](https://un4gt.github.io/wezterm-codex-status-line/config.schema.json)。

时间单位由键名给出：`_seconds` 为秒，`_ms` 为毫秒，`_bytes` 为字节。

## 基础与日志

| 选项 | 默认值 | 作用 |
| --- | --- | --- |
| `debug` | `false` | 记录进程识别、会话匹配和状态栏创建或关闭的详情 |
| `label` | `CODEX` | 状态栏固定标识，长度 1–24 |
| `codex_home` | `""` | 覆盖 `$CODEX_HOME`；空值使用环境变量或 `~/.codex` |
| `log.enabled` | `true` | 写入模块加载日志 |
| `log.marker` | `CODEX_STATUSLINE_LOADED` | 加载日志标记 |
| `compat.update_right_status` | `false` | 兼容使用 `update-right-status` 事件的 WezTerm 版本 |
| `codex_config.enabled` | `true` | 从 Codex 配置读取模型、推理强度和服务等级的默认值 |
| `codex_config.path` | `""` | 自定义 Codex `config.toml` 路径 |
| `codex_config.cache_ttl_seconds` | `5` | Codex 配置缓存时间 |

## 底部窗格、Git 与标题

| 选项 | 默认值 | 作用 |
| --- | --- | --- |
| `bottom_pane.enabled` | `true` | 是否创建独立底部状态栏窗格 |
| `bottom_pane.rows` | `1` | 新建时 1 或 2 行；拖动后遵从实际高度，Token 类字段可进入第二行 |
| `bottom_pane.layout_debounce_ms` | `1000` | 布局稳定等待，整数 250–5000 ms |
| `bottom_pane.close_grace_seconds` | `2` | 确认 Codex 退出后，关闭状态栏前的等待时间（秒） |
| `bottom_pane.prevent_focus` | `true` | 创建或点击状态栏后，将焦点返回 Codex 窗格 |
| `git.enabled` | `true` | 查询 Git 根目录和当前分支 |
| `git.cache_ttl_seconds` | `5` | Git 信息缓存时间 |
| `title_bridge.enabled` | `true` | 从窗格标题读取推理强度 |
| `title_bridge.app_name` | `codex` | 终端标题中的应用名 |

`title_bridge.enabled` 控制是否读取标题。要让 Codex 生成对应标题，先按[安装指南](../getting-started/installation.md#启用终端标题)启用终端标题。

`layout_debounce_ms` 只影响布局调整，数据仍按正常间隔刷新。分屏与焦点行为见[会话与分屏](../guides/how-it-works.md)。

手动关闭状态栏后，可用 `codex-statusline-show` 事件恢复，见[隐藏与恢复](../guides/how-it-works.md#隐藏与恢复)。

## 会话绑定

| 选项 | 默认值 | 作用 |
| --- | --- | --- |
| `sessions.enabled` | `true` | 读取窗格与会话的映射及会话记录 |
| `sessions.binding_mode` | `auto` | `auto`、`hook` 或 `heuristic` |
| `sessions.bridge_dir` | `""` | 覆盖 `$CODEX_HOME/wezterm-statusline` |
| `sessions.allow_fallback_latest` | `false` | 工作目录未知时，允许选择最近的会话记录 |
| `sessions.resume_fallback_enabled` | `true` | `auto` 模式恢复会话时，允许临时使用唯一匹配的记录 |
| `sessions.resume_fallback_max_age_seconds` | `30` | 候选相对进程启动时间的最大活动窗口，范围 1–300 |
| `sessions.resume_fallback_clock_skew_seconds` | `5` | 允许的时间戳偏差，范围 0–30 |
| `sessions.resume_fallback_scan_ttl_seconds` | `2` | 恢复会话时的候选扫描缓存 |
| `sessions.cache_ttl_seconds` | `5` | 会话映射与记录路径缓存 |
| `sessions.full_scan_ttl_seconds` | `300` | 完整会话记录扫描的缓存时间 |
| `sessions.tail_ttl_seconds` | `1` | 会话记录新增内容的读取间隔 |
| `sessions.open_fail_clear_seconds` | `30` | 会话记录持续无法读取时，保留原有显示数据的时间 |
| `sessions.initial_seek_bytes` | `131072` | 首次从文件尾部读取的字节数 |
| `sessions.activity_seek_bytes` | `65536` | 活动状态增量扫描的初始字节数 |
| `sessions.activity_max_seek_bytes` | `8388608` | 活动状态回溯扫描的最大字节数 |
| `sessions.max_meta_lines` | `40` | 首次元数据扫描最大行数 |
| `sessions.max_tail_lines` | `200` | 每轮尾部扫描最大行数 |

绑定模式行为：

| 模式 | 行为 |
| --- | --- |
| `auto` | 安装 hook 后使用精确映射；恢复会话时可临时使用唯一匹配的记录 |
| `hook` | 等待 hook 提供精确映射 |
| `heuristic` | 按工作目录和活动时间匹配会话 |

多个会话并行运行时，建议保留 `allow_fallback_latest = false`，避免将其他会话的数据用于当前窗格。

## 进程检测与 user vars

| 选项 | 默认值 | 作用 |
| --- | --- | --- |
| `process_match.enabled` | `true` | 检查当前窗格是否运行 Codex |
| `process_match.names` | `codex`, `codex.exe` | 可识别的 Codex 进程名 |
| `process_match.argv_markers` | `/@openai/codex/bin/codex.js` | Node.js 启动方式的命令行标记 |
| `process_match.terminal_names` | WezTerm 进程名列表 | 遍历进程树时停止在终端边界 |
| `process_match.grace_seconds` | `5` | 进程信号的缓存时间（秒） |
| `process_match.tree_cache_ttl_seconds` | `1` | 进程树缓存时间 |
| `user_vars.model` | `codex_model`, `CODEX_MODEL` | 模型变量候选名 |
| `user_vars.thinking` | thinking/reasoning 候选名 | 推理强度变量候选名 |
| `user_vars.provider` | provider 候选名 | 服务商变量候选名 |
| `user_vars.active` | `codex_active`, `CODEX_ACTIVE` | 活跃状态变量候选名 |

这些匹配项只应在确认本机 Codex 启动方式不同后调整。过于宽泛的匹配条件可能将其他程序识别为 Codex。

## 特殊状态文字

`activity.labels` 提供八个标签：

| 选项 | 默认值 |
| --- | --- |
| `plan` | `PLAN` |
| `review` | `REVIEW` |
| `goal_active` | `GOAL` |
| `goal_paused` | `GOAL PAUSED` |
| `goal_blocked` | `GOAL BLOCKED` |
| `goal_usage_limited` | `GOAL LIMITED` |
| `goal_budget_limited` | `GOAL BUDGET` |
| `goal_complete` | `GOAL DONE` |

同时存在多个状态时只显示一个，优先级固定为 `REVIEW > PLAN > GOAL`。状态含义见[显示内容](../guides/display-and-data.md#特殊状态)。

## 渲染与图标

| 选项 | 默认值 | 作用 |
| --- | --- | --- |
| `icon.text` | `` | 项目的 Terminal 标识；固定在右侧插件版本号之前，字号不大于其他字段 |
| `render.powerline` | `true` | 使用彩色 Powerline 分隔符 |
| `render.plain_fallback` | `true` | 关闭 Powerline 时使用纯文本分隔 |
| `render.model_display` | `name` | 模型段显示方式：`name` 仅名称、`icon_name` 图标＋名称、`icon` 仅图标 |
| `render.segment_order` | 26 个 ID | 字段顺序；`icon` 始终作为右侧锚点，不参与移动 |
| `render.disabled_segments` | 14 个高级字段 | 隐藏的字段；空数组表示全部启用 |

模型图标自动对应 `✦ Astra`、`☀ Sol`、`⊕ Terra`、`☾ Luna`。例如 `gpt-6-astra` 在 `icon_name` 模式显示为 `✦ gpt-6-astra`，在 `icon` 模式显示为 `✦`。匹配不区分大小写，支持模型简称和带版本或 provider 前缀的模型 ID；其他模型继续显示原名称。

在[交互预览](/preview)的「显示与主题 → 模型显示」中选择显示方式，右侧模拟模型按钮可快速预览四种图标。导出的 JSON 会保留这个选项；Lua 配置可使用 `render = { model_display = "icon_name" }`。

`theme.bg`、`theme.fg`、`theme.dim` 和每个 `theme.segments.<id>.bg/fg` 都使用 6 位十六进制颜色。`theme.glyphs` 可配置 `sep`、`branch` 和 `folder`。Lua 主题还接受 `thinking` 和 `tokens`，分别作为推理强度与 Token 字段的备用配色。

完整字段说明见[显示内容](../guides/display-and-data.md#全部-26-个字段)。

## 费用与自定义模型价格

`used_tokens` 显示 `↑输入 ↓输出`；`cache_rate` 与 `cost` 默认启用，可在字段列表中单独隐藏、排序和改色。

内置单价来自 [OpenAI 官方价格](https://developers.openai.com/api/docs/pricing)，核对日期为 **2026-09-14**，采用标准短上下文 API 价格，单位统一为 **USD / 百万 Token**：

| 模型 | 输入 | 缓存输入 | 输出 |
| --- | ---: | ---: | ---: |
| Astra | 10 | 1 | 50 |
| Sol | 4 | 0.4 | 20 |
| Terra | 2 | 0.2 | 12 |
| Luna | 0.2 | 0.02 | 1.2 |

同时内置 GPT-5.5、GPT-5.4、GPT-5.4 mini/nano、GPT-5.3 Codex、GPT-5.2、GPT-5.1 和 GPT-5 的标准价格。

在预览页展开「费用与模型单价」，可以直接修改内置模型的三项价格，也可以添加自定义模型。自定义价格随 JSON 导出；「恢复内置」移除对应覆盖。Lua 示例：

```lua
require("codex_statusline").setup({
  pricing = {
    models = {
      ["gpt-5.6-sol"] = { input = 3, cached_input = 0.3, output = 15 },
      ["my-model"] = { input = 1, cached_input = 0, output = 2 },
    },
  },
})
```

`pricing` 为可选项，默认 `models = {}`，最多 64 个覆盖；每项必须包含 `input`、`cached_input`、`output` 三个有限非负数，允许 0，上限为 1,000,000。模型 ID 使用小写字母、数字、点、下划线、冒号、斜线或连字符。完整 ID 的自定义价格优先，其次查找去除 provider 前缀、日期后缀或展开简称后的价格，再回退到内置价格。未配置价格的模型显示 `Cost —`。

费用按当前模型价格重新估算累计输入、缓存输入及输出。它不是实际账单，不包含按请求计价的长上下文、加速、缓存写入和工具费用；混用模型时也不会还原每次请求的历史价格。需要其他计价口径时可自行覆盖单价。
