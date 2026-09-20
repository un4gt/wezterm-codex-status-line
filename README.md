# WezTerm Codex Status Line

为 WezTerm 中的 Codex CLI 添加底部状态栏，显示模型、推理强度、工作目录、Git 分支和 Token 用量。

[文档](https://un4gt.github.io/wezterm-codex-status-line/) · [交互预览](https://un4gt.github.io/wezterm-codex-status-line/preview/) · [配置指南](https://un4gt.github.io/wezterm-codex-status-line/docs/guides/configuration/) · [故障排查](https://un4gt.github.io/wezterm-codex-status-line/docs/troubleshooting/common-issues/)

- 每个 Codex 窗格显示独立的会话信息，支持同时运行多个会话。
- 自定义字段、颜色、图标和一行或两行布局。
- 显示累计输入、输出、缓存率和估算费用。
- 在浏览器中预览配置，下载 JSON 后导入。
- 从本地 Codex 会话记录读取数据，无需额外调用模型。

```text
CODEX | gpt-5.6-sol | high | ~/src/app | main | Ctx 72% left | ↑10M ↓204K | Cache 60% | Cost ~$22.48 |  v0.1.1
```

## 安装

使用 Node.js 20 或更高版本运行：

```sh
npx --yes --package=https://github.com/un4gt/wezterm-codex-status-line/releases/download/v0.1.1/wezterm-codex-status-line-0.1.1.tgz wezterm-codex-status-line install --no-title-bridge
```

或使用 uv：

```sh
uvx wezterm-codex-status-line install --no-title-bridge
```

uvx 从 PyPI 安装，npx 暂时从 [GitHub Releases](https://github.com/un4gt/wezterm-codex-status-line/releases/tag/v0.1.1) 安装，任选一个即可。Windows 安装需要 PowerShell 5.1 或更高版本。macOS 暂未完成实机验证；Linux 暂未完成 Wayland/X11 桌面验证。其他要求见[安装指南](https://un4gt.github.io/wezterm-codex-status-line/docs/getting-started/installation/)。

在 WezTerm 配置的 `return config` 之前加入：

```lua
config.status_update_interval = 500
require("codex_statusline").setup()
```

重新加载 WezTerm 配置，在窗格中启动 `codex` 并发送一条消息。状态栏会在该窗格下方显示会话信息。

## 配置

在[交互预览](https://un4gt.github.io/wezterm-codex-status-line/preview/)中调整显示内容，点击“下载 JSON”，然后导入文件：

```sh
npx --yes --package=https://github.com/un4gt/wezterm-codex-status-line/releases/download/v0.1.1/wezterm-codex-status-line-0.1.1.tgz wezterm-codex-status-line configure --from ./codex_statusline_config.json
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

## 参与开发

构建和测试步骤见 [CONTRIBUTING.md](CONTRIBUTING.md)。

## 致谢

配置和预览功能参考了 [ccstatusline](https://github.com/sirmalloc/ccstatusline) 与 [CCometixLine](https://github.com/Haleclipse/CCometixLine)。

## 许可证

[MIT](LICENSE)
