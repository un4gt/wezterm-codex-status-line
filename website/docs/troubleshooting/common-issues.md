---
sidebar_position: 1
title: 常见问题
description: 从 doctor 开始排查安装、模块、Hook、等待状态、字形和 pane 生命周期。
---

# 常见问题

## 先运行 `doctor`

```powershell
npx --yes wezterm-codex-status-line@latest doctor
```

```bash
uvx --refresh wezterm-codex-status-line doctor
```

`MISSING` 表示对应检查未通过，不一定表示文件真的不存在。例如 `config` 也会在 JSON 无效时显示 `MISSING`。使用全局 `--json` 可获得检查名、警告与实际路径：

```bash
uvx --refresh wezterm-codex-status-line --json doctor
```

## `module 'codex_statusline' not found`

确认入口文件位于：

```text
~/.config/wezterm/codex_statusline.lua
```

并使用标准模块名：

```lua
require("codex_statusline").setup()
```

如果安装时使用了 `--wezterm-module-dir`，诊断时应传入同一路径。不要 require clone 目录或临时下载目录的绝对路径。

## `module 'codex_statusline_core' not found`

入口存在但同目录 core 或 `codex_statusline/` 子模块缺失、损坏或版本不一致。不要单独下载 Lua 入口；运行 `update` 会从同一个包版本完整暂存，先安装全部依赖，最后替换入口。

```powershell
npx --yes wezterm-codex-status-line@latest update
```

更新后再次运行 `doctor`，确认 `lua_entry`、`lua_core` 与 `asset_integrity` 都为 `OK`。

## `SessionStart hook (failed)`

1. 运行 `doctor`，检查 `hooks` 与 `asset_integrity`。
2. 确认诊断输出中的 `codex_home` 是当前 Codex 实际使用的目录。
3. 检查 `$CODEX_HOME/hooks.json` 中的 handler 是否仍指向已移动或删除的旧路径。
4. 重新运行 `update`，让 CLI 结构化替换本项目 handler。

非 WezTerm 启动时，bridge 缺少有效 `WEZTERM_PANE` 应以退出码 0 返回。若其他终端仍报告失败，优先检查 Hook 是否残留旧版 clone 路径。

## 同一个 Codex 下方出现两条相同状态栏

这是重复创建了状态 pane。旧版在配置重新加载时可能丢失已有 pane 的绑定，尤其是将新版 WezTerm 的 `GLOBAL` 共享对象误判为空状态时。

完整更新插件并重新加载 WezTerm 配置。当前实现保留共享状态，并使用 pane 所属标记恢复绑定。历史版本遗留且没有所属标记的重复 pane 不会被猜测关闭；确认其中只运行状态栏占位进程后，可手动关闭多余的状态 pane。

最右端的 `v…` 是正在运行的插件版本；加载日志的 `module_id` 同时标明版本，`searchpath` 标明实际加载的文件。如果没有右端版本号，请检查是否仍在加载旧版资源。

## Codex 已运行但没有状态 pane

- 确认 WezTerm 配置已调用一次 `setup()`，并已新开窗口或手动 reload。
- 建议设置 `config.status_update_interval = 500`；已有其他正数刷新间隔也可工作。
- 在 WezTerm 中新建 Codex 会话，避免测试安装前已经运行的进程。
- 运行 `doctor`，确认 Hook、Lua 文件和 `wezterm_require`。
- 临时启用 `debug = true`，查看 `tree state`、前台 PID 与未创建 pane 的原因。
- 只有旧 WezTerm 未触发 `update-status` 时，才尝试 `compat = {update_right_status = true}`。

`doctor` 不检查正在运行的 pane，因此全部 `OK` 仍可能是 WezTerm API、进程识别或配置尚未 reload 的问题。

## 持续显示 `waiting`

这表示尚无通过校验的 mapping 或 rollout。重点检查 debug 日志中的：

- `bridge_wait_reason`
- `bridge_fallback_reason`
- `bridge_fallback_candidates`
- 最终选择的 `rollout_path` 与 `source`

常见原因包括 Hook 尚未触发、pane CWD 与 mapping CWD 不一致、rollout 不在当前 `$CODEX_HOME` 内，以及同一目录存在多个活跃候选。

## 持续显示 `tokens: waiting`

mapping 与 rollout 已经绑定，但尚未解析到 token 用量事件。新会话需要先发送一条消息并等待 Codex 返回；仅打开会话选择器不会产生用量数据。

## `codex resume` 后暂时等待

resume 的新 `SessionStart` mapping 可能在第一次 turn 开始时才写入。`auto` 模式仅在同 CWD、当前进程启动后有新活动且候选唯一时临时读取 rollout；无法唯一判断时会保持等待。

发送第一条消息通常会触发正式 mapping。`binding_mode = "hook"` 是严格模式，不启用该回退。

## Powerline 显示方块或乱码

模块不检测字体 glyph。选择以下一种处理方式：

- 在 WezTerm 中使用包含 Powerline/Nerd Font glyph 的字体。
- 关闭 Powerline，使用纯文本：

```powershell
npx --yes wezterm-codex-status-line@latest configure --no-powerline
```

`plain_fallback = true` 只有在 `powerline = false` 时生效，不会自动识别缺字形。

## Codex 退出后状态 pane 未关闭

- 确认 WezTerm 支持 `wezterm cli kill-pane --pane-id <id>`。
- 检查 debug 日志中的进程树结果；Codex 子进程仍存活时，pane 会继续保留。
- 确认 `bottom_pane.close_grace_seconds` 未被设为过大的值。
- 更新全部 Lua 文件与子模块并 reload WezTerm，避免依赖版本不一致。

源码 checkout 中可以先跑确定性的生命周期场景，再分析一次真实复现日志：

```powershell
python scripts/run_lifecycle_tests.py
python scripts/analyze_lifecycle_log.py
```

分析器按 owner ID 跟踪新日志，报告 `CLOSE_TIMEOUT`、`OVERLAPPING_STATUS_GENERATIONS` 等异常，不把正常延期或手动隐藏误报为未重建。旧日志保留 `SLOW_EXIT`、`STATUS_NOT_RECREATED`、`STALE_PANE_LOOKUP_LOOP` 检查。默认读取最新 GUI 日志并从最近一次模块加载开始；可传入指定路径，或用 `--all-loads` 检查完整历史。公开日志前仍需脱敏。

当前实现只对记录的状态 pane ID 发起关闭。定向 API 不可用、目标 ID 无法确认或与主 pane ID 冲突时，会保留状态 pane 并记录错误。

## MCP 启动时 tab 或主 pane 被关闭

这是旧实现使用当前 pane 关闭动作时可能出现的高风险症状。当前源码的状态 pane 回收命令必须包含明确的 `kill-pane --pane-id`，且不使用 `CloseCurrentPane`。

如果仍遇到该症状，先注释 `setup()`，reload WezTerm，再通过包管理器更新全部 Lua 文件与子模块。不要继续在来源或版本不明的单文件安装上复现。

## 分屏后状态栏横跨了其他 pane

新建使用局部分屏。若状态栏创建后又切分 owner，WezTerm 的分屏树可能让旧栏成为多个窗格的共同底部。复杂布局不会被自动重排，这是保护用户尺寸的保守策略。先完成左右分屏再启动 Codex，可直接得到对齐的局部栏；当 tab 只剩 owner 和它的状态栏时，模块才会自动归位。

拖大状态栏后不会强制改回配置行数。连续拖动、zoom 或布局 API 暂不可用期间暂停布局操作，稳定后重新计时。手动关闭状态栏会隐藏当前 Codex 批次；重启 Codex 或自定义绑定 `wezterm.action.EmitEvent("codex-statusline-show")` 可恢复。

日志 `layout deferred` 表示布局被保留，不等于故障。`unknown` 表示无法确认进程退出；`close timed out` 表示 10 秒内未确认旧 pane 消失，此时暂停关闭重试和重建。恢复事件可以显式重试，但不会强行重排复杂布局。

## 字体缩放或 reflow 后内容消失

当前渲染缓存键包含 pane ID、列数、行数和字体大小。确认入口与 core 来自同一包版本，并由你主动 reload 或新开 WezTerm。若仍复现，启用 debug 并记录缩放前后的 pane dimensions。

## 配置 JSON 无效

使用 CLI 校验完整文件，不直接覆盖现有配置：

```powershell
npx --yes wezterm-codex-status-line@latest configure --from .\candidate.json --dry-run
```

常见错误包括缺少必需对象、未知键、颜色不是 `#RRGGBB`、segment 重复，以及 `segment_order` 为空。

## 收集调试信息

```lua
require("codex_statusline").setup({debug = true})
```

问题报告至少包含：

- `doctor --json` 输出（检查路径后再公开）。
- `CODEX_STATUSLINE_LOADED` 的 module ID 与搜索路径。
- `update` 日志中的 pane ID、前台进程、tree state 与 reason。
- mapping 等待原因或 `SessionStart` 错误文本。
- WezTerm、Codex CLI 与本项目包版本。

日志和 JSON 可能包含用户名、本机路径、thread ID 与 Hook 命令。发布到公开 issue 前应先脱敏；排查完成后关闭 `debug`。
