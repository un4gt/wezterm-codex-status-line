---
sidebar_position: 1
title: 配置参考
description: 使用交互预览或 Schema 1 JSON 管理全部状态栏配置。
---

# 配置参考

项目提供两种配置入口：

1. [交互预览](/preview)：编辑全部 Schema 1 选项、模拟状态栏数据，并导出 JSON。
2. `require("codex_statusline").setup({...})`：在 WezTerm 配置中覆盖相同的运行时选项。

合并顺序固定为：内置默认值 → `codex_statusline_config.json` → `setup({...})`。后加载的值优先，嵌套对象补全默认值；数组整体替换，因此 `disabled_segments = {}` 可以真正清空禁用列表。

## 启动文档与预览

在仓库根目录执行：

```powershell
cd website
npm install
npm run start
```

开发服务器默认位于 `http://localhost:3000/wezterm-codex-status-line/`，配置器位于 `http://localhost:3000/wezterm-codex-status-line/preview`。如果依赖已经安装，可以跳过 `npm install`。

预览页上方用于调整终端列数；“恢复全部默认值”会同时恢复配置、模拟数据、120 列宽度，并移除 URL 中的分享参数。高级配置默认折叠，展开后可以编辑会话缓存、进程检测和 user vars。

## 推荐工作流

也可以通过安装包启动终端配置向导：

```powershell
npx --yes --package=https://github.com/un4gt/wezterm-codex-status-line/releases/download/v0.1.0/wezterm-codex-status-line-0.1.0.tgz wezterm-codex-status-line configure
```

```bash
uvx --from https://github.com/un4gt/wezterm-codex-status-line/releases/download/v0.1.0/wezterm_codex_status_line-0.1.0-py3-none-any.whl wezterm-codex-status-line configure
```

从网页下载 JSON 后导入：

```powershell
npx --yes --package=https://github.com/un4gt/wezterm-codex-status-line/releases/download/v0.1.0/wezterm-codex-status-line-0.1.0.tgz wezterm-codex-status-line configure --from .\codex_statusline_config.json
```

CLI 与网页会拒绝缺少必需字段、未知字段、重复或未知 segment，以及不符合 `#RRGGBB` 的颜色。机器可读定义见 [config.schema.json](https://un4gt.github.io/wezterm-codex-status-line/config.schema.json)。

:::warning[完整文档，不是 patch]

Schema 1 JSON 是完整配置文档。请从默认配置、现有配置或网页下载结果开始修改，再通过 `configure --from` 校验。

:::

## 配置文件位置

默认路径：

```text
~/.config/wezterm/codex_statusline_config.json
```

`--config-file <path>` 可以更改 CLI 读写位置，但 Lua 模块默认只加载与 `codex_statusline.lua` 同目录的 `codex_statusline_config.json`。自定义路径时需确保 CLI 与 Lua 最终使用同一个文件。

## 基础与日志

| 选项 | 默认值 | 作用 |
| --- | --- | --- |
| `debug` | `false` | 输出进程判断、mapping、rollout 选择和回收日志 |
| `label` | `CODEX` | 状态栏固定标识，长度 1–24 |
| `codex_home` | `""` | 覆盖 `$CODEX_HOME`；空值使用环境变量或 `~/.codex` |
| `log.enabled` | `true` | 写入模块加载日志 |
| `log.marker` | `CODEX_STATUSLINE_LOADED` | 加载日志标记 |
| `compat.update_right_status` | `false` | 同时注册旧版 `update-right-status` 事件 |
| `codex_config.enabled` | `true` | 读取 Codex 配置中的模型、reasoning 与 service tier 回退值 |
| `codex_config.path` | `""` | 自定义 Codex `config.toml` 路径 |
| `codex_config.cache_ttl_seconds` | `5` | Codex 配置缓存时间 |

## 底部 pane、Git 与标题

| 选项 | 默认值 | 作用 |
| --- | --- | --- |
| `bottom_pane.enabled` | `true` | 是否创建独立底部状态 pane |
| `bottom_pane.rows` | `1` | 新建时 1 或 2 行；拖动后遵从实际高度，Token 类字段可进入第二行 |
| `bottom_pane.layout_debounce_ms` | `1000` | 布局稳定等待，整数 250–5000 ms；至少两次采样，旧配置可省略 |
| `bottom_pane.close_grace_seconds` | `2` | Codex 不再活跃后等待多久再定向关闭状态 pane |
| `bottom_pane.prevent_focus` | `true` | 创建或点击状态 pane 后把焦点交还主 pane |
| `git.enabled` | `true` | 查询 Git 根目录和当前分支 |
| `git.cache_ttl_seconds` | `5` | Git 信息缓存时间 |
| `title_bridge.enabled` | `true` | 读取并解析 pane title |
| `title_bridge.app_name` | `codex` | title bridge 识别的应用名 |

`title_bridge.enabled` 不会修改 `$CODEX_HOME/config.toml`。Codex terminal title 的安装、记录与恢复由 `install --title-bridge` 和 `uninstall` 负责。

状态栏按 owner pane 管理，不随焦点切换回收。复杂分屏错位时保留原位，不自动修改相邻窗格；只有 owner 和它的状态栏独占 tab 时才归位。防抖只影响布局操作，不延迟数据重绘，实际等待还受 `status_update_interval` 采样间隔影响。

`layout_debounce_ms` 可在完整 JSON 或 `setup()` 中设置，网页和 CLI 导入导出会保留该字段；不增加专用控件。手动关闭后可自行绑定 `wezterm.action.EmitEvent("codex-statusline-show")` 来恢复当前 owner 的状态栏。

## 会话绑定

| 选项 | 默认值 | 作用 |
| --- | --- | --- |
| `sessions.enabled` | `true` | 读取 pane/thread mapping 与 rollout |
| `sessions.binding_mode` | `auto` | `auto`、`hook` 或 `heuristic` |
| `sessions.bridge_dir` | `""` | 覆盖 `$CODEX_HOME/wezterm-statusline` |
| `sessions.allow_fallback_latest` | `false` | CWD 不可用时是否允许选择最近 rollout |
| `sessions.resume_fallback_enabled` | `true` | `auto` 模式等待 resume mapping 时允许受限回退 |
| `sessions.resume_fallback_max_age_seconds` | `30` | 候选相对进程启动时间的最大活动窗口，范围 1–300 |
| `sessions.resume_fallback_clock_skew_seconds` | `5` | 允许的时间戳偏差，范围 0–30 |
| `sessions.resume_fallback_scan_ttl_seconds` | `2` | resume 候选扫描缓存 |
| `sessions.cache_ttl_seconds` | `5` | mapping 和 rollout 路径缓存 |
| `sessions.full_scan_ttl_seconds` | `300` | 完整 rollout 扫描缓存 |
| `sessions.tail_ttl_seconds` | `1` | rollout 尾部增量读取间隔 |
| `sessions.open_fail_clear_seconds` | `30` | rollout 持续无法读取后清理旧状态的等待时间 |
| `sessions.initial_seek_bytes` | `131072` | 首次从文件尾部读取的字节数 |
| `sessions.activity_seek_bytes` | `65536` | 活动状态增量扫描的初始字节数 |
| `sessions.activity_max_seek_bytes` | `8388608` | 活动状态回溯扫描的最大字节数 |
| `sessions.max_meta_lines` | `40` | 首次元数据扫描最大行数 |
| `sessions.max_tail_lines` | `200` | 每轮尾部扫描最大行数 |

绑定模式行为：

| 模式 | 行为 |
| --- | --- |
| `auto` | 安装 bridge 后要求精确 mapping；仅 resume 等待窗口允许唯一候选回退 |
| `hook` | 始终要求 bridge mapping，不启用 resume 或最近 rollout 回退 |
| `heuristic` | 忽略 bridge，按 CWD 与 rollout 活动时间匹配 |

保持 `allow_fallback_latest = false` 可以降低多个并发会话之间串线的风险。

## 进程检测与 user vars

| 选项 | 默认值 | 作用 |
| --- | --- | --- |
| `process_match.enabled` | `true` | 使用进程树确认主 pane 是否运行 Codex |
| `process_match.names` | `codex`, `codex.exe` | 可识别的 Codex 进程名 |
| `process_match.argv_markers` | `/<...>/@openai/codex/bin/codex.js` | Node 启动方式的命令行标记 |
| `process_match.terminal_names` | WezTerm 进程名列表 | 遍历进程树时停止在终端边界 |
| `process_match.grace_seconds` | `5` | 进程信号的短期兼容缓存；生命周期的 unknown 不因到期而回收 |
| `process_match.tree_cache_ttl_seconds` | `1` | 进程树缓存时间 |
| `user_vars.model` | `codex_model`, `CODEX_MODEL` | 模型 user var 候选名 |
| `user_vars.thinking` | thinking/reasoning 候选名 | reasoning user var 候选名 |
| `user_vars.provider` | provider 候选名 | provider user var 候选名 |
| `user_vars.active` | `codex_active`, `CODEX_ACTIVE` | 活跃状态 user var 候选名 |

这些匹配项只应在确认本机 Codex 启动方式不同后调整。过度放宽会把非 Codex pane 识别为活跃会话。

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

同时存在多个状态时只显示一个，优先级固定为 `REVIEW > PLAN > GOAL`。具体结构化事件来源见[显示与数据口径](./display-and-data.md#特殊状态)。

## 渲染与图标

| 选项 | 默认值 | 作用 |
| --- | --- | --- |
| `icon.text` | `` | 项目的 Terminal 标识；固定在右侧插件版本号之前，字号不大于其他字段 |
| `render.powerline` | `true` | 使用彩色 Powerline segment |
| `render.plain_fallback` | `true` | 关闭 Powerline 时使用纯文本分隔 |
| `render.model_display` | `name` | 模型段显示方式：`name` 仅名称、`icon_name` 图标＋名称、`icon` 仅图标 |
| `render.segment_order` | 26 个 ID | 字段顺序；`icon` 始终作为右侧锚点，不参与移动 |
| `render.disabled_segments` | 14 个高级字段 | 明确隐藏字段；空数组表示全部启用 |

模型图标自动对应 `✦ Astra`、`☀ Sol`、`⊕ Terra`、`☾ Luna`。例如 `gpt-6-astra` 在 `icon_name` 模式显示为 `✦ gpt-6-astra`，在 `icon` 模式显示为 `✦`。匹配不区分大小写，支持模型简称和带版本或 provider 前缀的模型 ID；其他模型继续显示原名称。旧配置省略此选项时使用 `name`。

在[交互预览](/preview)的「显示与主题 → 模型显示」中选择显示方式，右侧模拟模型按钮可快速预览四种图标。导出的 JSON 会保留这个选项；Lua 配置可使用 `render = { model_display = "icon_name" }`。

旧版仅含 8 个字段的顺序仍受支持，运行时只自动追加 `activity` 与 `icon`，避免升级后突然显示大量高级字段。新版配置器会列出全部 26 个字段供显式启用。

`theme.bg`、`theme.fg`、`theme.dim` 和每个 `theme.segments.<id>.bg/fg` 都使用 6 位十六进制颜色。`theme.glyphs` 可配置 `sep`、`branch` 和 `folder`。旧 Lua 主题键 `thinking` 与 `tokens` 仍分别作为 reasoning 和 Token 字段的兼容回退。

完整 26 个字段及其数据来源见[显示与数据口径](./display-and-data.md#全部-26-个字段)。

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

## 非交互 CLI 示例

```powershell
npx --yes --package=https://github.com/un4gt/wezterm-codex-status-line/releases/download/v0.1.0/wezterm-codex-status-line-0.1.0.tgz wezterm-codex-status-line configure `
  --label "CODEX" `
  --rows 1 `
  --binding-mode auto `
  --segments "label,model,reasoning,activity,cwd,git,context,used_tokens,icon" `
  --disable "provider" `
  --theme-bg "#11151a" `
  --theme-fg "#d5dbe3" `
  --theme-dim "#82909f" `
  --color "label:#1d4ed8:#ffffff" `
  --color "icon:#11151a:#58d6c5"
```

`--color` 可重复，格式为 `segment:#RRGGBB:#RRGGBB`。`--dry-run` 只校验并预览；全局 `--no-color` 关闭 CLI ANSI 色彩。完整参数见 [CLI 命令参考](./cli-reference.md)。
