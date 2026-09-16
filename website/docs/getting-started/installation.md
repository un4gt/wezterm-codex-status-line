---
sidebar_position: 1
title: 安装
description: 检查前置条件，并使用 npx 或 uvx 安装 Lua 模块与 Codex bridge。
---

# 安装

`npx` 与 `uvx` 提供相同的命令、配置 schema 和安装结果。选择一个入口即可，不需要同时安装两套包。

下列命令从 [GitHub Releases](https://github.com/un4gt/wezterm-codex-status-line/releases/tag/v0.1.0) 下载并安装 v0.1.0。安装完成后，按照[配置 WezTerm](./wezterm-config.md)加载状态栏。

## 前置条件

| 组件 | 要求 |
| --- | --- |
| WezTerm | 需要 pane 进程信息、`pane:split()`、`pane:inject_output()` 与 `wezterm cli kill-pane --pane-id` |
| Codex CLI | 需要 `SessionStart` hook；启用 terminal title bridge 时还需要 `codex app-server --stdio` |
| npx 入口 | Node.js 20 或更高版本 |
| uvx 入口 | Python 3.10 或更高版本，以及可用的 `uvx` |
| Windows | 安装与卸载过程需要 Windows PowerShell 5.1 或更高版本 |
| Git | 可选；仅用于刷新 `git` segment |
| 字体 | Powerline 渲染需要包含相应 glyph 的字体；否则使用 `--no-powerline` |

项目未声明具体的 WezTerm 或 Codex 最低版本号。安装后应运行 `doctor`，并在实际会话中验证所需 API 与 Hook 行为。

macOS 暂未完成实机验证；Linux 暂未完成 Wayland/X11 桌面验证。

## 使用 npx

```powershell
npx --yes --package=https://github.com/un4gt/wezterm-codex-status-line/releases/download/v0.1.0/wezterm-codex-status-line-0.1.0.tgz wezterm-codex-status-line install --no-title-bridge
```

## 使用 uvx

```bash
uvx --from https://github.com/un4gt/wezterm-codex-status-line/releases/download/v0.1.0/wezterm_codex_status_line-0.1.0-py3-none-any.whl wezterm-codex-status-line install --no-title-bridge
```

## Terminal title bridge

上面的安装命令使用 `--no-title-bridge`。macOS 和 Linux 请保留此选项，这两个平台暂不支持自动配置 Codex terminal title。

在 Windows 上，可使用 `--title-bridge` 启用 terminal title bridge。省略选择时，交互式安装会询问是否启用，默认选择启用。它会写入以下用户配置，并从新 Codex 会话开始生效：

```toml title="$CODEX_HOME/config.toml"
[tui]
terminal_title = ["app-name", "reasoning", "project-name"]
```

该 bridge 用于及时读取 reasoning effort 的变化。关闭后，插件仍可从 rollout、Codex 配置和进程信息获取其他数据。

脚本或 CI 中应明确选择，避免等待交互输入：

```powershell
npx --yes --package=https://github.com/un4gt/wezterm-codex-status-line/releases/download/v0.1.0/wezterm-codex-status-line-0.1.0.tgz wezterm-codex-status-line install --title-bridge
npx --yes --package=https://github.com/un4gt/wezterm-codex-status-line/releases/download/v0.1.0/wezterm-codex-status-line-0.1.0.tgz wezterm-codex-status-line install --no-title-bridge
```

```bash
uvx --from https://github.com/un4gt/wezterm-codex-status-line/releases/download/v0.1.0/wezterm_codex_status_line-0.1.0-py3-none-any.whl wezterm-codex-status-line install --title-bridge
uvx --from https://github.com/un4gt/wezterm-codex-status-line/releases/download/v0.1.0/wezterm_codex_status_line-0.1.0-py3-none-any.whl wezterm-codex-status-line install --no-title-bridge
```

全局 `--yes` 也会选择启用 title bridge，但自动化场景使用语义明确的 `--title-bridge` 或 `--no-title-bridge` 更易审计。

## 安装器执行的操作

`install` 会：

1. 从当前 npm 或 Python 包读取同版本资源，并在目标目录完整暂存。
2. 先替换 bridge 与 core，最后替换 Lua 入口文件。
3. 以结构化 JSON 合并 `$CODEX_HOME/hooks.json` 中的 `SessionStart` handler。
4. 可选地通过 Codex app-server 配置 terminal title。
5. 写入 schema 4 的 `bridge.json`，记录包版本、runner、安装路径和资源 SHA-256。

`install` 不会创建 `codex_statusline_config.json`，不会编辑 `.wezterm.lua`，也不会 reload WezTerm。

主要安装路径：

```text
~/.config/wezterm/codex_statusline.lua
~/.config/wezterm/codex_statusline_core.lua
~/.config/wezterm/codex_statusline/**/*.lua
$CODEX_HOME/wezterm-statusline/bin/*
$CODEX_HOME/wezterm-statusline/bridge.json
$CODEX_HOME/hooks.json
```

完整的文件读写与恢复规则见[文件与安全边界](../reference/security-and-files.md)。

下一步：[配置 WezTerm](./wezterm-config.md)。
