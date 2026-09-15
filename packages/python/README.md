# WezTerm Codex Status Line CLI

macOS：因缺乏设备，没有在 macOS 实机中测试。Linux：目前缺少 Wayland/X11 桌面环境，尚未完成真实 GUI 验证。

```bash
uvx --from https://github.com/un4gt/wezterm-codex-status-line/releases/download/v0.1.0/wezterm_codex_status_line-0.1.0-py3-none-any.whl wezterm-codex-status-line install --no-title-bridge
```

Commands: `install`, `configure`, `preview`, `doctor`, `update`, `uninstall`.
The CLI never edits or reloads `.wezterm.lua`.

Documentation: https://un4gt.github.io/wezterm-codex-status-line/
