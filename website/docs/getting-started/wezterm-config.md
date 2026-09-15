---
sidebar_position: 2
title: 配置 WezTerm
description: 在 .wezterm.lua 中加载状态栏模块，并验证安装结果。
---

# 配置 WezTerm

安装器有意不编辑 `.wezterm.lua`。确认两个根 Lua 文件与 `codex_statusline/` 子模块均已安装后，在现有配置中调用一次 `setup()`。

## 最小配置

```lua title="~/.wezterm.lua"
local wezterm = require("wezterm")
local config = wezterm.config_builder()

-- 建议每 500 ms 刷新一次；也可以使用你现有的刷新间隔。
config.status_update_interval = 500

require("codex_statusline").setup()

return config
```

`setup()` 应在配置构造完成后、最终 `return config` 之前调用。已有的 shell、字体、按键和窗口配置无需改写，例如：

```lua title="~/.wezterm.lua"
local wezterm = require("wezterm")
local config = wezterm.config_builder()

config.default_prog = {"pwsh.exe", "-NoLogo"}
config.enable_scroll_bar = true
config.font_size = 12
config.status_update_interval = 500

require("codex_statusline").setup()

return config
```

## 模块搜索路径

默认安装目录是：

```text
~/.config/wezterm/
```

该目录也是默认的 WezTerm 配置目录，因此通常只需要：

```lua
require("codex_statusline").setup()
```

不要 require 临时 clone 目录的绝对路径。目录移动或删除后，绝对路径会使 WezTerm 配置加载失败。使用自定义配置目录时，应在安装命令中同时传入 `--wezterm-module-dir <path>`。

## 加载并检查

1. 新开 WezTerm 窗口，或在方便时由你主动 reload 配置。
2. 运行安装诊断：

```powershell
npx --yes wezterm-codex-status-line@latest doctor
```

或：

```bash
uvx --refresh wezterm-codex-status-line doctor
```

3. 在 WezTerm pane 中启动新的 `codex` 会话并发送第一条消息。
4. 确认底部状态 pane 出现，并在首个 token 事件后显示 context 和 used tokens。

`doctor` 检查 manifest、Lua 入口与全部子模块资源哈希、Hook、WezTerm 的 `require()` 和可选配置文件。它不会启动 WezTerm，也不会验证某个正在运行的 Codex 会话。

## 配置显示内容

```powershell
npx --yes wezterm-codex-status-line@latest configure
```

```bash
uvx --refresh wezterm-codex-status-line configure
```

也可以在[交互预览](/preview)中调整并下载 JSON，再使用 `configure --from <path>` 导入。所有配置方式见[配置参考](../guides/configuration.md)。

## 调试加载来源

临时启用：

```lua
require("codex_statusline").setup({
  debug = true,
})
```

WezTerm 日志中的 `CODEX_STATUSLINE_LOADED` 会显示 module ID 与实际搜索路径。排查完成后关闭 `debug`，避免持续输出状态更新日志。
