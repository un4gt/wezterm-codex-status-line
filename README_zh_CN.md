<p align="center">
    <a href="https://linux.do" alt="LINUX DO">
        <img
            src="https://img.shields.io/badge/LINUX-DO-FFB003.svg?logo=data:image/svg%2bxml;base64,DQo8c3ZnIHhtbG5zPSJodHRwOi8vd3d3LnczLm9yZy8yMDAwL3N2ZyIgd2lkdGg9IjEwMCIgaGVpZ2h0PSIxMDAiPjxwYXRoIGQ9Ik00Ni44Mi0uMDU1aDYuMjVxMjMuOTY5IDIuMDYyIDM4IDIxLjQyNmM1LjI1OCA3LjY3NiA4LjIxNSAxNi4xNTYgOC44NzUgMjUuNDV2Ni4yNXEtMi4wNjQgMjMuOTY4LTIxLjQzIDM4LTExLjUxMiA3Ljg4NS0yNS40NDUgOC44NzRoLTYuMjVxLTIzLjk3LTIuMDY0LTM4LjAwNC0yMS40M1EuOTcxIDY3LjA1Ni0uMDU0IDUzLjE4di02LjQ3M0MxLjM2MiAzMC43ODEgOC41MDMgMTguMTQ4IDIxLjM3IDguODE3IDI5LjA0NyAzLjU2MiAzNy41MjcuNjA0IDQ2LjgyMS0uMDU2IiBzdHlsZT0ic3Ryb2tlOm5vbmU7ZmlsbC1ydWxlOmV2ZW5vZGQ7ZmlsbDojZWNlY2VjO2ZpbGwtb3BhY2l0eToxIi8+PHBhdGggZD0iTTQ3LjI2NiAyLjk1N3EyMi41My0uNjUgMzcuNzc3IDE1LjczOGE0OS43IDQ5LjcgMCAwIDEgNi44NjcgMTAuMTU3cS00MS45NjQuMjIyLTgzLjkzIDAgOS43NS0xOC42MTYgMzAuMDI0LTI0LjM4N2E2MSA2MSAwIDAgMSA5LjI2Mi0xLjUwOCIgc3R5bGU9InN0cm9rZTpub25lO2ZpbGwtcnVsZTpldmVub2RkO2ZpbGw6IzE5MTkxOTtmaWxsLW9wYWNpdHk6MSIvPjxwYXRoIGQ9Ik03Ljk4IDcwLjkyNmMyNy45NzctLjAzNSA1NS45NTQgMCA4My45My4xMTNRODMuNDI2IDg3LjQ3MyA2Ni4xMyA5NC4wODZxLTE4LjgxIDYuNTQ0LTM2LjgzMi0xLjg5OC0xNC4yMDMtNy4wOS0yMS4zMTctMjEuMjYyIiBzdHlsZT0ic3Ryb2tlOm5vbmU7ZmlsbC1ydWxlOmV2ZW5vZGQ7ZmlsbDojZjlhZjAwO2ZpbGwtb3BhY2l0eToxIi8+PC9zdmc+" /></a>
</p>

# WezTerm Codex Status Line

[English](README.md) | 简体中文

为 WezTerm 中的 Codex CLI 添加底部状态栏，显示模型、推理强度、工作目录、Git 分支和 Token 用量。

[文档](https://un4gt.github.io/wezterm-codex-status-line/) · [交互预览](https://un4gt.github.io/wezterm-codex-status-line/preview/) · [配置指南](https://un4gt.github.io/wezterm-codex-status-line/docs/guides/configuration/) · [故障排查](https://un4gt.github.io/wezterm-codex-status-line/docs/troubleshooting/common-issues/)

- 每个 Codex 窗格显示独立的会话信息，支持同时运行多个会话。
- 自定义字段、颜色、图标和一行或两行布局。
- 显示累计输入、输出、缓存率和估算费用。
- 在浏览器中预览配置，下载 JSON 后导入。
- 从本地 Codex 会话记录读取数据，无需额外调用模型。

```text
CODEX | gpt-5.6-sol | high | ~/src/app | main | Ctx 72% left | ↑10M ↓204K | Cache 60% | Cost ~$22.48 |  v0.1.2
```

## 安装

使用 Node.js 20 或更高版本运行：

```sh
npx --yes wezterm-codex-status-line@latest install --no-title-bridge
```

或使用 uv：

```sh
uvx wezterm-codex-status-line install --no-title-bridge
```

uvx 从 PyPI 安装，npx 从 npm 安装，任选一个即可。Windows 安装需要 PowerShell 5.1 或更高版本。macOS 暂未完成实机验证；Linux 暂未完成 Wayland/X11 桌面验证。其他要求见[安装指南](https://un4gt.github.io/wezterm-codex-status-line/docs/getting-started/installation/)。

在 WezTerm 配置的 `return config` 之前加入：

```lua
config.status_update_interval = 500
require("codex_statusline").setup()
```

重新加载 WezTerm 配置，在窗格中启动 `codex` 并发送一条消息。状态栏会在该窗格下方显示会话信息。

## 配置

在[交互预览](https://un4gt.github.io/wezterm-codex-status-line/preview/)中调整显示内容，点击“下载 JSON”，然后导入文件：

```sh
npx --yes wezterm-codex-status-line@latest configure --from ./codex_statusline_config.json
```

重新加载 WezTerm 配置以应用修改。配置默认保存在 `~/.config/wezterm/codex_statusline_config.json`，也可以通过 `setup({...})` 设置选项。完整步骤见[配置指南](https://un4gt.github.io/wezterm-codex-status-line/docs/guides/configuration/)。

## 命令

| 命令 | 用途 |
| --- | --- |
| `install` | 安装状态栏 |
| `configure` | 修改或导入配置 |
| `preview` | 在终端预览当前配置 |
| `doctor` | 检查安装和配置 |
| `update` | 更新状态栏并保留配置 |
| `uninstall` | 卸载状态栏 |

命令参数见[命令行参考](https://un4gt.github.io/wezterm-codex-status-line/docs/guides/cli-reference/)。卸载前请先从 WezTerm 配置中移除 `setup()` 调用并重新加载配置，详见[更新与卸载](https://un4gt.github.io/wezterm-codex-status-line/docs/getting-started/update-uninstall/)。

更新已有安装：

```sh
npx --yes wezterm-codex-status-line@latest update
# 或：
uvx --refresh wezterm-codex-status-line update
```

## 参与开发

构建和测试步骤见 [CONTRIBUTING.md](CONTRIBUTING.md)。

## 致谢

配置和预览功能参考了 [ccstatusline](https://github.com/sirmalloc/ccstatusline) 与 [CCometixLine](https://github.com/Haleclipse/CCometixLine)。

## 许可证

[MIT](LICENSE)
