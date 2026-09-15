---
sidebar_position: 3
title: 更新与卸载
description: 更新同版本资源，验证结果，并按安全顺序卸载状态栏。
---

# 更新与卸载

## 更新

不需要先卸载。使用原入口运行最新包的 `update`：

```powershell
npx --yes wezterm-codex-status-line@latest update
```

```bash
uvx --refresh wezterm-codex-status-line update
```

更新会替换包内资源，保留 `codex_statusline_config.json`、Hook 中其他 handler，以及 manifest 已记录的 terminal title 恢复信息。CLI 不会主动 reload WezTerm；更新后在合适的时间新开窗口或手动 reload。

未提供 title 参数时，`update` 保留上次安装记录。此前未启用时，可通过 `update --title-bridge` 启用。`update --no-title-bridge` 不会删除已经写入的 title 配置；需要关闭时，应完整卸载后使用 `install --no-title-bridge` 重新安装。

更新后运行：

```powershell
npx --yes wezterm-codex-status-line@latest doctor
```

## 安全卸载

先从 `.wezterm.lua` 移除：

```lua
require("codex_statusline").setup()
```

reload WezTerm 配置后，再执行：

```powershell
npx --yes wezterm-codex-status-line@latest uninstall
```

或：

```bash
uvx --refresh wezterm-codex-status-line uninstall
```

若 CLI 仍在 `~/.wezterm.lua` 或 `~/.config/wezterm/wezterm.lua` 中检测到 `require("codex_statusline")`，会在恢复 title、修改 Hook 或删除文件之前以退出码 `3` 拒绝执行。此检查没有强制绕过选项。

默认保留 `codex_statusline_config.json`，便于重新安装。需要同时删除时增加：

```text
--purge-config
```

运行时生成的 `$CODEX_HOME/wezterm-statusline/panes/*.json` 映射不属于包资源；目录非空时可能在卸载后保留。

## 预演与机器输出

`install`、`configure`、`update` 和 `uninstall` 支持 `--dry-run`。预演只报告计划结果，不写文件：

```powershell
npx --yes wezterm-codex-status-line@latest update --dry-run
```

自动化场景可增加全局 `--json`。为兼容 `uvx` 入口，全局参数统一写在子命令之前：

```bash
uvx --refresh wezterm-codex-status-line --json doctor
```

| 退出码 | 含义 |
| ---: | --- |
| `0` | 命令成功 |
| `1` | 运行失败，或 `doctor` 检查未全部通过 |
| `2` | 参数或配置无效，或交互被取消 |
| `3` | 安全检查拒绝执行 |
