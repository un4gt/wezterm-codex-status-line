---
sidebar_position: 3
title: 会话与分屏
description: 了解多个 Codex 会话、恢复会话和分屏布局下的状态栏行为。
---

# 会话与分屏

每个运行 Codex 的 WezTerm 窗格都有独立的状态栏。同一个标签页中可以同时运行多个 Codex 会话。

## 关联会话

安装器添加的 `SessionStart` hook 会记录 Codex 会话与 WezTerm 窗格的对应关系。状态栏据此读取本地会话记录，显示模型、推理强度和用量。

默认使用 `auto` 模式。恢复会话后，新映射可能要到发送第一条消息时才出现。在此期间，如果同一工作目录下只有一个符合条件的活跃会话，状态栏会临时读取它；无法确定时显示 `waiting`。

如果希望始终等待 hook 提供精确映射，设置：

```lua
require("codex_statusline").setup({
  sessions = { binding_mode = "hook" },
})
```

其他绑定选项见[配置选项](../reference/settings.md#会话绑定)。

## 调整布局

状态栏在 Codex 窗格下方创建一行或两行区域，另外占用一行分隔线，并至少为 Codex 保留五行。

```lua
require("codex_statusline").setup({
  bottom_pane = { rows = 2 },
})
```

拖动分隔线后，状态栏保留你调整的高度。窗口正在缩放或分屏时，会等待布局稳定再调整位置，默认等待一秒。

建议先完成分屏，再启动 Codex。状态栏创建后再次拆分上方窗格，可能让它横跨多个窗格；插件会保留现有布局。当标签页只剩一个 Codex 窗格及其状态栏时，会自动重新对齐。

## 切换标签页

切换焦点或标签页后，已有状态栏会保留。将 Codex 窗格移到另一个标签页时，插件会先关闭原位置的状态栏，再在新位置创建。

## 隐藏与恢复

手动关闭状态栏会将它隐藏到下一次 Codex 会话。要立即恢复，可以绑定 `codex-statusline-show` 事件。例如，将以下项目加入现有的 `config.keys`：

```lua
{
  key = "S",
  mods = "CTRL|SHIFT",
  action = wezterm.action.EmitEvent("codex-statusline-show"),
}
```

该快捷键为示例，插件没有默认恢复快捷键。

## Codex 退出后

确认 Codex 退出后，状态栏默认等待两秒再关闭。无法确认进程状态时，已有内容会保留。

若退出后状态栏持续存在，见[故障排查](../troubleshooting/common-issues.md#codex-退出后状态栏仍然存在)。

## SSH 与 tmux

远程 Codex 进程识别和 tmux 内部分屏识别暂不受支持。状态栏需要能读取当前窗格的进程信息及对应的本地 Codex 会话记录。
