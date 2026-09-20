---
sidebar_position: 1
title: 故障排查
description: 检查安装并解决状态栏、会话数据和显示问题。
---

import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';

# 故障排查

## 检查安装

先运行 `doctor`：

<Tabs groupId="installer">
<TabItem value="npx" label="npx">

```sh
npx --yes --package=https://github.com/un4gt/wezterm-codex-status-line/releases/download/v0.1.0/wezterm-codex-status-line-0.1.0.tgz wezterm-codex-status-line doctor
```

</TabItem>
<TabItem value="uvx" label="uvx">

```sh
uvx --from https://github.com/un4gt/wezterm-codex-status-line/releases/download/v0.1.0/wezterm_codex_status_line-0.1.0-py3-none-any.whl wezterm-codex-status-line doctor
```

</TabItem>
</Tabs>

`OK` 表示检查通过，`MISSING` 表示检查未通过。后者也可能表示配置内容无效。添加全局选项 `--json` 可查看详细结果：

```sh
npx --yes --package=https://github.com/un4gt/wezterm-codex-status-line/releases/download/v0.1.0/wezterm-codex-status-line-0.1.0.tgz wezterm-codex-status-line --json doctor
```

自定义安装目录需要继续传入相同的 `--codex-home` 或 `--wezterm-module-dir`。

## 找不到状态栏模块

出现 `module 'codex_statusline' not found` 时，检查安装目录是否存在 `codex_statusline.lua`，并在 WezTerm 配置中使用：

```lua
require("codex_statusline").setup()
```

默认目录为 `~/.config/wezterm`。自定义目录需要位于 WezTerm 的模块搜索路径中。

如果缺少 `codex_statusline_core` 或其他子模块，运行完整更新：

```sh
npx --yes --package=https://github.com/un4gt/wezterm-codex-status-line/releases/download/v0.1.0/wezterm-codex-status-line-0.1.0.tgz wezterm-codex-status-line update
```

完成后重新加载 WezTerm 配置，再运行 `doctor`。

## 会话启动 hook 失败

出现 `SessionStart hook (failed)` 时：

1. 运行 `doctor`，检查 `hooks` 和 `asset_integrity`。
2. 确认诊断输出中的 `codex_home` 与当前 Codex 使用的目录一致。
3. 运行 `update`，更新 hook 中的脚本路径。
4. 启动新的 Codex 会话。

在其他终端中也出现该错误时，检查 `hooks.json` 是否仍指向已移动或删除的安装目录。

## Codex 已运行，但没有状态栏

1. 确认 WezTerm 配置调用了 `setup()`，并已重新加载配置。
2. 设置 `config.status_update_interval = 500`，或保留已有的正数刷新间隔。
3. 在 WezTerm 中启动新的 Codex 会话并发送一条消息。
4. 运行 `doctor`，确认模块和 hook 检查通过。

仍未显示时，按[收集调试信息](#收集调试信息)开启日志。`doctor` 只检查文件，不能判断正在运行的窗格是否正常。

## 持续显示 `waiting`

状态栏还未找到当前窗格对应的会话记录。先发送一条消息，再检查：

- 会话启动 hook 是否报错。
- `$CODEX_HOME` 是否指向当前会话使用的目录。
- Codex 是否运行在本地 WezTerm 窗格中。
- 同一工作目录是否存在多个活跃 Codex 会话。

恢复会话后，新映射可能稍后才出现。`auto` 模式无法确定对应会话时会保持等待，行为见[会话与分屏](../guides/how-it-works.md#关联会话)。

## 持续显示 `tokens: waiting`

会话已关联，但还未收到 Token 用量。发送一条消息并等待 Codex 返回。仅打开会话选择器不会产生用量数据。

## `/model` 切换后仍显示旧模型

启用[终端标题桥](../getting-started/installation.md#启用终端标题)，让状态栏在发送下一条消息之前读取新模型。仅依赖会话记录时，需要等待 Codex 将变化写入日志。

已启用标题桥的 Windows 用户运行 `update --title-bridge`，重新加载 WezTerm 配置，再启动或恢复 Codex 会话。标题应类似 `codex | gpt-5.6-sol | high | app`；旧的三段标题只能实时提供推理强度。

## 配置导入后没有变化

先确认已经用 `configure --from <文件路径>` 将下载的 JSON 导入本机，并重新加载 WezTerm 配置。

如果只在网页中点击“导入 JSON”，更改仅用于网页预览。另需检查 `setup({...})` 是否设置了同名选项；Lua 中的值会覆盖 JSON。详见[配置优先级](../guides/configuration.md#配置优先级)。

## JSON 配置无效

使用 `--dry-run` 检查文件：

```sh
npx --yes --package=https://github.com/un4gt/wezterm-codex-status-line/releases/download/v0.1.0/wezterm-codex-status-line-0.1.0.tgz wezterm-codex-status-line configure --from ./codex_statusline_config.json --dry-run
```

从网页导出完整配置后修改。常见错误包括缺少字段、未知键、颜色格式不为 `#RRGGBB`、字段重复或顺序列表为空。

## 图标显示方块或乱码

选择包含 Nerd Font 图标的 WezTerm 字体，或关闭 Powerline：

```sh
npx --yes --package=https://github.com/un4gt/wezterm-codex-status-line/releases/download/v0.1.0/wezterm-codex-status-line-0.1.0.tgz wezterm-codex-status-line configure --no-powerline
```

项目图标仍显示异常时，将 `icon.text` 改为 `>_`。修改后重新加载 WezTerm 配置。

## 出现重复状态栏

更新插件并重新加载 WezTerm 配置。确认多余窗格只显示状态栏后，可以手动关闭它。

状态栏右侧的版本号用于确认实际运行版本。仍有重复时，请附上布局和版本信息[提交问题](https://github.com/un4gt/wezterm-codex-status-line/issues)。

## 分屏后状态栏位置不对

先完成分屏，再启动 Codex，可以使状态栏与对应窗格对齐。已有状态栏上方再次分屏时，它可能横跨多个窗格，插件会保留现有布局。

手动关闭状态栏后，可以重新启动 Codex，或使用 `codex-statusline-show` 事件恢复。具体行为见[会话与分屏](../guides/how-it-works.md#调整布局)。

## Codex 退出后状态栏仍然存在

插件确认 Codex 退出后，默认等待两秒再关闭状态栏。如果子进程仍存活或无法确认进程状态，会保留状态栏。

运行 `update` 并重新加载 WezTerm 配置。若仍存在，检查是否修改了 `bottom_pane.close_grace_seconds`，并收集调试日志。

## Codex 主窗格意外关闭

暂时移除 WezTerm 配置中的 `setup()` 调用并重新加载配置，再更新插件。提交问题时附上关闭发生前的操作和日志。

## 调整字体后显示异常

重新加载 WezTerm 配置。如果仍未恢复，运行 `update` 检查是否存在混用版本的文件。反馈时附上字体名称、字号和窗口大小。

## 下载附件失败

安装命令需要访问 `github.com` 和 `release-assets.githubusercontent.com`。遇到连接重置或超时时，检查终端的网络和代理配置。

npm 使用其代理设置；uv 使用 `HTTP_PROXY`、`HTTPS_PROXY` 等环境变量。能打开 GitHub 仓库页面并不一定表示可以下载附件。

## 收集调试信息

在 WezTerm 配置中启用日志：

```lua
require("codex_statusline").setup({ debug = true })
```

重新加载配置并复现问题。提交 [Issue](https://github.com/un4gt/wezterm-codex-status-line/issues) 时，提供：

- 操作系统、WezTerm、Codex CLI 和插件版本。
- 复现步骤及预期结果。
- `--json doctor` 的输出。
- `CODEX_STATUSLINE_LOADED` 加载记录和问题发生时的日志。

日志可能包含用户名、目录、会话 ID 和本地命令，提交前请移除私人信息。排查完成后关闭 `debug`。
