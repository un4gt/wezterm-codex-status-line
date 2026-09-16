# WezTerm Codex Status Line

为 WezTerm 中的 Codex CLI 添加底部状态栏，显示模型、推理强度、Git 分支和 Token 用量。

## 安装

```sh
npx --yes --package=https://github.com/un4gt/wezterm-codex-status-line/releases/download/v0.1.0/wezterm-codex-status-line-0.1.0.tgz wezterm-codex-status-line install --no-title-bridge
```

安装后，在 WezTerm 配置的 `return config` 之前加入：

```lua
require("codex_statusline").setup()
```

重新加载 WezTerm 配置，然后启动 Codex。平台要求见[安装指南](https://un4gt.github.io/wezterm-codex-status-line/docs/getting-started/installation/)；macOS 暂未完成实机验证，Linux 暂未完成 Wayland/X11 桌面验证。

## 配置

在[交互预览](https://un4gt.github.io/wezterm-codex-status-line/preview/)中调整显示并下载 JSON，然后导入：

```sh
npx --yes --package=https://github.com/un4gt/wezterm-codex-status-line/releases/download/v0.1.0/wezterm-codex-status-line-0.1.0.tgz wezterm-codex-status-line configure --from ./codex_statusline_config.json
```

重新加载 WezTerm 配置以应用修改。完整步骤见[配置指南](https://un4gt.github.io/wezterm-codex-status-line/docs/guides/configuration/)。

## 命令

`install` 安装，`configure` 配置，`preview` 预览，`doctor` 检查，`update` 更新，`uninstall` 卸载。

参数见[命令行参考](https://un4gt.github.io/wezterm-codex-status-line/docs/guides/cli-reference/)。卸载前先移除 WezTerm 配置中的模块引用并重新加载配置。

## 许可证

MIT
