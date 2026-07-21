# WezTerm Codex Status Line

在本地 WezTerm pane 运行 Codex CLI 时，自动创建一个只读的底部状态 pane，显示当前 thread 的模型、reasoning effort、provider、工作目录、Git 分支以及 token/context 用量。Codex 退出后，状态 pane 会自动关闭。

插件只在 WezTerm 配置进程中运行，不修改 Codex TUI，也不替换 Codex 自带 footer。

## 功能

- 只检查当前 pane 的进程树，不会把其他 tab 中的 Codex 误认为当前会话
- 通过 `SessionStart` bridge 将 WezTerm pane 精确绑定到 Codex thread
- 增量读取 rollout JSONL，不重复扫描完整 transcript
- Git 分支按 pane 当前目录独立查询并缓存，不依赖 rollout 元数据
- 支持同一目录同时运行多个 Codex thread
- bridge 未安装时，可按 CWD 和最近活动时间启用启发式匹配
- 非 WezTerm 终端触发全局 hook 时静默成功退出
- 状态内容根据 pane 宽度自动缩短
- Codex 退出后自动清理底部状态 pane
- 可选 terminal title bridge：Shift+Tab 切换模式后立即刷新 reasoning effort，并可靠识别 `/exit`
- 字体缩放或窗口 reflow 后自动重绘，保持底部 pane 为配置的行数

## 当前显示格式

宽度足够且数据完整时，状态内容大致为：

```text
CODEX | gpt-5.6-codex | r:high | p:openai | ~/src/app | main | Tok: t=4,203,817 in=3,901,224 +c=81,426,702 out=302,593 r=177,531 ctx=76,384/272,000 left=75%
```

默认使用 Powerline segment 和 Nerd Font glyph。宽度不足时，会逐步缩短 context、移除 token 明细，再隐藏 Git、工作目录和 provider。当前版本仍显示精确整数以及 `ctx=current/window`，尚未使用 `K/M/B` 紧凑数字或 context 进度条。

## 环境要求

- 较新的 WezTerm，需支持 pane 进程信息、split 和 `pane:inject_output()`
- 支持 `SessionStart` hook 与 rollout JSONL 的 Codex CLI
- Windows：Windows PowerShell 5.1 或更高版本
- macOS/Linux：Python 3.10 或更高版本
- Nerd Font 可选；缺失时可使用 plain fallback

当前实现和 token 口径已按 Codex CLI `0.144.0` 验证。

## 安装

### Windows 一键安装

下面的命令会下载并执行仓库 `main` 分支中的 `install.ps1`：

```powershell
& ([scriptblock]::Create((Invoke-RestMethod 'https://raw.githubusercontent.com/un4gt/wezterm-codex-status-line/main/install.ps1'))) -Install
```

若要让 `/exit` 和 Plan 模式 reasoning effort 使用 Codex 的实时 terminal title 信号，显式增加开关：

```powershell
& ([scriptblock]::Create((Invoke-RestMethod 'https://raw.githubusercontent.com/un4gt/wezterm-codex-status-line/main/install.ps1'))) -Install -EnableCodexTitleBridge
```

希望先审查脚本时，clone 仓库后执行本地安装：

```powershell
git clone https://github.com/un4gt/wezterm-codex-status-line.git
cd wezterm-codex-status-line
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -Install -EnableCodexTitleBridge
```

安装器会写入：

```text
~/.config/wezterm/codex_statusline.lua
~/.config/wezterm/codex_statusline_core.lua
$CODEX_HOME/wezterm-statusline/bin/codex_statusline_bridge.ps1
$CODEX_HOME/wezterm-statusline/bin/codex_statusline_bridge.py
```

并结构化合并 `$CODEX_HOME/hooks.json` 中的 `SessionStart` handler。已有 hook 会保留；修改前会创建 `hooks.json.bak-*` 备份。

`-EnableCodexTitleBridge` 会通过 Codex app-server 将用户层配置写为：

```toml
[tui]
terminal_title = ["app-name", "reasoning", "project-name"]
```

安装 manifest 会保存该键原先是否存在及其完整 JSON 值，以便安全卸载。普通 `-Install` 不修改 Codex 配置。

安装器**不会**修改 `.wezterm.lua`，不会调用或 reload WezTerm，也不会热更新正在运行的 Codex。Lua 模块在下次手动 reload 或新开 WezTerm 后生效；terminal title 从下一次 Codex 会话开始生效。

### 配置 WezTerm

在 `~/.wezterm.lua` 中调用模块：

```lua
local wezterm = require("wezterm")
local config = wezterm.config_builder()

config.status_update_interval = 500
require("codex_statusline").setup()

return config
```

`~/.config/wezterm` 是 WezTerm 的默认 Lua 模块搜索目录，因此不要引用 clone 目录的绝对路径。配置会在下次启动 WezTerm 时生效；也可以在方便时由你手动 reload。

Codex 第一次发现新 hook 时可能要求确认信任。已经运行的 Codex 不会补发 `SessionStart`，需要新建或 resume 一次会话。

### macOS/Linux 本地安装

```bash
mkdir -p ~/.config/wezterm
cp codex_statusline.lua codex_statusline_core.lua ~/.config/wezterm/
python3 ./codex_statusline_bridge.py --install
```

Unix bridge handler 会引用当前脚本路径。移动或删除 clone 目录后，应在新位置重新执行 `--install`。

## 工作方式

### 进程检测

插件从 `pane:get_foreground_process_info()` 开始，只检查当前 pane 的进程子树。当前台是 Codex 启动的 Git、shell 或其他工具时，会沿父进程链找到 Codex，但不会扫描父进程的其他后代。

默认识别：

- `codex` / `codex.exe`
- npm wrapper：`node .../@openai/codex/bin/codex.js`

远程 SSH 和 mux pane 通常无法提供可靠的本地进程树，因此默认不显示。已有 shell integration 可以设置 `codex_active` 或 `CODEX_ACTIVE` user var 显式覆盖。

### Terminal title bridge

启用安装开关后，Codex 会生成类似标题：

```text
codex | max | app
```

Lua 每次 `update-status` 读取主 pane 标题。title 中的 reasoning effort 优先于 rollout 中上一轮的 `turn_context`，因此 Shift+Tab 切换 Default/Plan 模式后无需提交消息即可更新。Codex 退出时会清空自己管理的标题；一旦当前会话出现过该信号，标题消失就优先于可能滞后的 Windows 进程快照。

未启用该开关时仍使用进程树检测，但 `/exit` 的关闭速度取决于系统进程信息何时刷新。

### Thread 绑定

bridge 使用 `WEZTERM_PANE` 和 Codex hook payload 写入：

```text
$CODEX_HOME/wezterm-statusline/panes/<pane-id>.json
```

Lua 会校验 pane ID、pane CWD、thread UUID、rollout 路径是否位于 `$CODEX_HOME` 内，以及 rollout 中的 `session_meta` 是否匹配。只有全部通过后才读取 token 数据。

Codex 在普通 Windows Terminal、PowerShell、VS Code Terminal 等非 WezTerm 环境启动时也可能触发全局 hook。bridge 发现没有数字形式的 `WEZTERM_PANE` 后会立即以退出码 0 返回，不解析 stdin，也不创建 pane mapping。

### Token 口径

- `total`：非缓存 input + output
- `input`：`input_tokens - cached_input_tokens`
- `cached`、`output`、`reasoning`：累计 `total_token_usage` 中的对应字段
- 当前 context：最近一次 `last_token_usage.total_tokens`
- context window：`model_context_window`
- context 剩余百分比：Codex 的 12,000-token baseline 公式

`reasoning_output_tokens` 已包含在 output 中，不会再次计入 `total`。`total_token_usage.total_tokens` 是 thread 累计消耗，不是当前 context 大小。

## 配置

```lua
require("codex_statusline").setup({
  debug = false,
  label = "CODEX",
  bottom_pane = {
    enabled = true,
    rows = 1, -- 设为 2 时，元信息和 token 分两行
    close_grace_seconds = 2,
    prevent_focus = true,
  },
  sessions = {
    binding_mode = "auto", -- auto | hook | heuristic
    bridge_dir = nil, -- 默认 $CODEX_HOME/wezterm-statusline
    allow_fallback_latest = false,
  },
  git = {
    enabled = true,
    cache_ttl_seconds = 5,
  },
  title_bridge = {
    enabled = true, -- 只读取标题；是否写 Codex 配置由安装开关决定
    app_name = "codex",
  },
  process_match = {
    names = { "codex", "codex.exe" },
    argv_markers = { "/@openai/codex/bin/codex.js" },
  },
  render = {
    powerline = true,
    plain_fallback = true,
  },
})
```

Thread 绑定模式：

| 模式 | 行为 |
| --- | --- |
| `auto` | 检测到 bridge 安装标记后要求精确 mapping，否则使用启发式匹配 |
| `hook` | 始终要求 bridge mapping，不回退 |
| `heuristic` | 忽略 bridge，仅按 CWD 和 rollout 活动时间匹配 |

`allow_fallback_latest` 默认为 `false`。只有 pane CWD 无法获取时，该开关才允许使用最近 rollout；保持关闭可以降低多会话串线风险。

Git 分支通过参数数组执行 `git -C <pane-cwd> branch --show-current`，默认缓存 5 秒。Git 查询不可用时才回退到 rollout 中的启动时元数据。

## 故障排查

### `module 'codex_statusline' not found`

确认下面两个文件存在：

```text
~/.config/wezterm/codex_statusline.lua
~/.config/wezterm/codex_statusline_core.lua
```

并使用 `require("codex_statusline").setup()`，不要 require clone 目录中的绝对路径。

### `SessionStart hook (failed)`

先确认 hook 中的路径指向安装目录，而不是已经移动的 clone 目录：

```text
$CODEX_HOME/wezterm-statusline/bin/
```

重新执行安装会更新旧路径并去重。非 WezTerm 启动不应报错；bridge 在缺少 `WEZTERM_PANE` 时会成功退出。

### Codex 已运行但没有状态 pane

- 新建或 resume 一次 Codex，让它重新触发 `SessionStart`
- 确认 `.wezterm.lua` 已调用 `setup()`
- 临时设置 `debug = true`，查看 WezTerm 日志中的进程判断和 bridge wait reason
- 若使用旧版 WezTerm，可尝试 `compat = { update_right_status = true }`

### `/exit` 后 pane 未关闭或 Plan effort 延迟

- 使用 `-EnableCodexTitleBridge` 重新安装，然后新开 Codex 会话
- 确认 `$CODEX_HOME/config.toml` 中的 `tui.terminal_title` 仍是安装器写入的三个固定项目
- `.wezterm.lua` 中建议保持 `config.status_update_interval = 500`

### Ctrl +/- 后状态内容消失

新版会把实际行数和 `window:effective_config().font_size` 纳入渲染缓存。更新 Lua 模块后，需要在方便时手动 reload 或新开 WezTerm；安装器不会替你执行 reload。

### 状态 pane 显示 waiting

- `Session: waiting for bridge`：当前 pane 尚无 `SessionStart` mapping；新建或 resume 一次 Codex
- `Session: waiting for rollout`：mapping 已失效、属于旧进程或无法校验；不要继续展示旧 thread 数据
- `Token usage: waiting for first response`：rollout 已正确绑定，但尚未出现第一个 `token_count` 事件

Git 分支与这些状态独立；即使 token 仍在等待，只要 pane CWD 是 Git 仓库，分支仍会显示。

## 卸载

在 clone 目录中：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -Uninstall
```

本地仓库已经删除时，可以执行远程完整卸载：

```powershell
& ([scriptblock]::Create((Invoke-RestMethod 'https://raw.githubusercontent.com/un4gt/wezterm-codex-status-line/main/install.ps1'))) -Uninstall
```

直接运行已安装的 `codex_statusline_bridge.ps1 -Uninstall` 只适合单独移除 hook，不会删除 Lua 模块或恢复 Codex terminal title。检测到 title 恢复元数据时，bridge-only 卸载会保留 manifest 并提示使用完整安装器。

Unix：

```bash
python3 ./codex_statusline_bridge.py --uninstall
```

Windows 完整卸载会移除 Lua 模块、bridge 脚本和本插件自己的 `SessionStart` handler，不删除其他 hook、hook 备份或历史 pane mapping。若安装器曾启用 terminal title bridge，只有当前值仍等于插件写入值时才恢复原值；用户后来手动修改过则保留当前值并给出警告。

## 开发验证

无需启动或 reload WezTerm 的检查：

```powershell
python -m unittest tests.test_bridge -v
python -m py_compile codex_statusline_bridge.py tests\test_bridge.py
lua54 tests\core_test.lua
lua54 tests\statusline_lifecycle_test.lua
luac54 -p codex_statusline.lua
luac54 -p codex_statusline_core.lua
```

在方便操作 WezTerm 时，可额外验证配置加载：

```powershell
wezterm --config-file .\tests\wezterm_test_config.lua show-keys --lua
```
