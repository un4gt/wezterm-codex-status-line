# WezTerm Codex Status Line

在 WezTerm 中为 Codex CLI 创建独立的底部状态 pane，显示模型、reasoning effort、工作目录、Git 分支以及 token/context 用量。

**文档站点：<https://un4gt.github.io/wezterm-codex-status-line/>**

[安装指南](https://un4gt.github.io/wezterm-codex-status-line/docs/getting-started/installation) · [交互预览](https://un4gt.github.io/wezterm-codex-status-line/preview) · [配置参考](https://un4gt.github.io/wezterm-codex-status-line/docs/guides/configuration) · [故障排查](https://un4gt.github.io/wezterm-codex-status-line/docs/troubleshooting/common-issues)

## 功能

- 按 Codex pane ID 独立绑定局部状态栏，同一 tab 可同时管理多个 Codex；切换到普通终端不会回收其他 pane 的状态栏。
- 通过 `SessionStart` bridge 精确绑定 WezTerm pane 与 Codex thread。
- `codex resume` 等待新 mapping 时，只在同 CWD 存在唯一活跃 rollout 时安全回退。
- 增量读取 rollout JSONL，并按 pane 宽度逐级缩短显示。
- 独立查询并缓存当前工作目录的 Git 分支。
- 可选 terminal title bridge，实时刷新 Plan/Default reasoning effort。
- 状态 pane 只按明确 pane ID 回收，不对当前活动 pane 使用 `CloseCurrentPane`。
- `npx` 与 `uvx` 提供等价的安装、配置、预览、检查、更新和卸载命令。

## 安装

macOS：因缺乏设备，没有在 macOS 实机中测试。Linux：目前缺少 Wayland/X11 桌面环境，尚未完成真实 GUI 验证。

使用 Node.js：

```powershell
npx --yes wezterm-codex-status-line@latest install
```

使用 uv：

```bash
uvx --refresh wezterm-codex-status-line install
```

交互安装会询问是否启用 terminal title bridge。脚本或 CI 中必须明确传入 `--title-bridge` 或 `--no-title-bridge`。

| 命令 | 作用 |
| --- | --- |
| `install` | 安装固定版本的 Lua 模块、bridge 和 Codex Hook |
| `configure` | 写入经过 schema 校验的配置 JSON，并显示 ANSI 预览 |
| `preview` | 使用模拟 Codex 数据预览当前配置 |
| `doctor` | 检查模块、Hook、manifest、WezTerm 引入和配置 |
| `update` | 事务更新资源并保留用户配置 |
| `uninstall` | 安全恢复配置并移除本项目文件 |

两个包入口都不会编辑 `.wezterm.lua`，也不会调用 WezTerm reload。随后手动保留一次：

```lua
local wezterm = require("wezterm")
local config = wezterm.config_builder()

config.status_update_interval = 500
require("codex_statusline").setup()

return config
```

配置向导写入 `~/.config/wezterm/codex_statusline_config.json`。合并优先级为内置默认值、配置 JSON、最后是 `setup({...})` 中的显式选项。

向导可调整布局、segment 顺序、显示项和每个 segment 的颜色；脚本环境可使用等价 flags：

```powershell
npx --yes wezterm-codex-status-line@latest configure `
  --theme-bg "#11151a" `
  --color "label:#1d4ed8:#ffffff" `
  --color "git:#11151a:#4ade80"
```

`uvx --refresh wezterm-codex-status-line configure` 接受相同的 `configure` flags。`--color` 可重复，格式固定为 `segment:#RRGGBB:#RRGGBB`。

## 默认显示

```text
CODEX | gpt-5.6-sol | high | ~/src/app | main | Ctx ███████░░░ 72% left | ↑10M ↓204K | Cache 60% | Cost ~$22.48 |  v0.1.0
```

在 60、90、120 列阈值处会逐级缩短或隐藏低优先级 segment，插件版本号始终锚定在状态 pane 右边缘，项目图标位于它之前。版本号来自已安装的插件资源，关闭图标后仍会显示；双行布局只显示一次。可选的 `codex_version` 字段显示 Codex CLI 版本，与此插件版本独立。默认 Powerline 和项目图标使用 Nerd Font 字形；字体不兼容时可关闭 Powerline，并将 `icon.text` 改为 `>_`。

模型段可在交互预览的「模型显示」中选择仅名称、图标＋名称或仅图标，对应 `✦ Astra`、`☀ Sol`、`⊕ Terra`、`☾ Luna`。Lua 中设置 `render = { model_display = "icon_name" }` 即可显示图标＋原模型名；使用 `"icon"` 仅显示图标，默认 `"name"` 仅显示名称。其他模型保留原名称。

Token 段显示 `↑输入 ↓输出`，输入包含缓存；`Cache` 为缓存输入占总输入的比例。`Cost` 按当前模型的标准短上下文 API 单价估算整段会话的 Token 费用。内置价格及核对日期见 [model-pricing.json](contract/model-pricing.json)，可在预览页「费用与模型单价」覆盖或添加价格，也可配置 `pricing.models["模型 ID"] = { input = 4, cached_input = 0.4, output = 20 }`（USD / 百万 Token）。

## 安全边界

- 包内携带与 CLI 同版本的资源，不从 GitHub `main` 下载漂移文件。
- 安装前完整暂存资源，依赖先写、Lua 入口最后替换。
- Hook 通过结构化 JSON 合并并保留其他 handler，实际修改前创建备份。
- 完整卸载若发现 `.wezterm.lua` 仍有 `require("codex_statusline")`，会在删除任何文件前拒绝执行。
- 无法安全定向关闭状态 pane 时宁可保留，不触碰 Codex 主 pane。

## 分屏与生命周期

新状态栏在所属 Codex pane 下方局部分屏（`top_level = false`），初始为 1 或 2 行，另占一行分隔线，至少为 Codex 保留 5 行。布局连续稳定至少两次采样、默认 1000 ms 后才执行创建或归位；内容刷新不受防抖限制。

用户布局优先：拖动后的实际状态栏高度会保留。再次分屏造成状态栏与 owner 错位时，复杂布局保持原位，不改变相邻普通 pane；只有 tab 内恰好剩下 owner 和它的状态栏时才自动归位。建议先完成左右分屏，再启动 Codex。

```lua
require("codex_statusline").setup({
  bottom_pane = { layout_debounce_ms = 1000 }, -- integer: 250..5000
})
```

只有明确退出或 owner 消失才回收；进程状态未知时保留绑定和最后数据。后台 tab 每 2 秒检查已管理 owner，不在后台创建或归位。owner 移到其他 tab 时，先确认旧状态栏关闭，再在前台创建新的状态栏。异步关闭 10 秒未确认会暂停重试和重建。

手动关闭状态栏会隐藏当前 Codex 批次的状态栏，重启 Codex 或触发 `codex-statusline-show` 可恢复；不添加默认快捷键。可自行给已有按键绑定使用 `wezterm.action.EmitEvent("codex-statusline-show")`。

SSH 中的 WezTerm pane 使用相同布局策略，但本次不扩展远程进程识别或 tmux 内部分屏检测。配置 schema 仍为 1，省略防抖字段的旧配置继续有效。

## 代码分层

- `codex_statusline.lua`：兼容入口与事件注册；`codex_statusline_core.lua`：纯算法兼容导出。
- `codex_statusline/domain/`：进程、会话与渲染计划纯算法。
- `config.lua`、`session_index.lua`、`rollout.lua`、`git.lua`、`process.lua`：配置与数据源。
- `formatting.lua`、`renderer.lua`、`legacy_renderer.lua`：格式化、渲染及兼容回退。
- `layout.lua`、`state.lua`、`lifecycle.lua`、`wezterm_adapter.lua`：布局决策、owner 状态、生命周期与 WezTerm 操作。

上述子模块均位于 `codex_statusline/`，必须与两个根 Lua 文件一并安装；安装器和包资源清单已包含全部模块。

## 致谢与灵感

本项目认真参考并赞赏以下两个优秀的 Claude Code 状态栏项目：

- [sirmalloc/ccstatusline](https://github.com/sirmalloc/ccstatusline)：交互式配置流程、真实渲染器驱动的实时预览，以及清晰的安装体验给了本项目重要启发。
- [Haleclipse/CCometixLine](https://github.com/Haleclipse/CCometixLine)：结构化 segment/theme 配置、配置校验和跨平台分发设计为本项目提供了很有价值的借鉴。

本项目是面向 Codex CLI 与 WezTerm 的独立实现，与上述项目不存在隶属或官方关联。

## 开发验证

```powershell
python -m unittest tests.test_bridge -v
python -m unittest tests.test_lifecycle_log -v
npx --yes --package=fengari-node-cli fengari tests/core_test.lua
npx --yes --package=fengari-node-cli fengari tests/statusline_lifecycle_test.lua
npx --yes --package=fengari-node-cli fengari tests/statusline_scenario_test.lua
npx --yes --package=fengari-node-cli fengari tests/statusline_resume_test.lua

cd packages/npm
npm ci
npm run typecheck
npm test

cd ../python
uv sync
uv run wezterm-codex-status-line --help

cd ../../website
npm ci
npm run typecheck
npm run build
```

现场生命周期问题可直接分析最新的 WezTerm debug 日志：

```powershell
python scripts/run_lifecycle_tests.py
python scripts/analyze_lifecycle_log.py
```

Windows PowerShell 7 中可运行独立 GUI 验证，不加载个人配置、不调用模型，结束后只关闭测试进程：

```powershell
pwsh -NoProfile -File scripts/run_wezterm_live_test.ps1
```

该测试执行 50 次局部创建与回收，核对总行数、右侧普通 pane 和焦点，并检查再次分屏后的保守策略。真实布局及渲染使用 WezTerm API，进程活跃信号为测试桩。

## License

[MIT](LICENSE)
