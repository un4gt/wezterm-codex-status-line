---
sidebar_position: 1
title: 文件与安全边界
description: 查看各命令和运行时读取、修改、备份与保留的本地数据。
---

# 文件与安全边界

## 命令会修改什么

| 命令 | 主要写入 |
| --- | --- |
| `install` / `update` | 两个根 Lua 文件与全部子模块、bridge 资源、`hooks.json` handler、schema 4 manifest；可选 Codex terminal title |
| `configure` | schema 1 的 `codex_statusline_config.json` |
| `preview` / `doctor` | 不写项目配置；只读取并输出结果 |
| `uninstall` | 恢复受管 title 值、移除本项目 Hook 与已知包资源；可选删除 schema 1 配置 |

安装器不会修改 `.wezterm.lua`，不会主动 reload WezTerm，也不会删除其他 Hook handler。

## 文件清单

| 路径 | 所有者与用途 |
| --- | --- |
| `~/.config/wezterm/codex_statusline.lua` | 包资源；WezTerm 入口模块 |
| `~/.config/wezterm/codex_statusline_core.lua` | 包资源；纯算法兼容导出 |
| `~/.config/wezterm/codex_statusline/**/*.lua` | 包资源；数据源、布局、生命周期、渲染与适配层 |
| `~/.config/wezterm/codex_statusline_config.json` | 用户配置；仅由 `configure` 创建或更新 |
| `$CODEX_HOME/wezterm-statusline/bin/*` | 包资源；各平台 SessionStart bridge |
| `$CODEX_HOME/wezterm-statusline/bridge.json` | 安装 manifest、路径、runner、版本、哈希与 title 恢复记录 |
| `$CODEX_HOME/hooks.json` | Codex Hook 配置；结构化合并本项目 handler |
| `$CODEX_HOME/config.toml` | 用户配置；仅启用 title bridge 时通过 Codex app-server 修改一个键 |
| `$CODEX_HOME/wezterm-statusline/panes/*.json` | 运行时 mapping；包含 pane/thread、CWD 与 rollout 路径 |

使用 `--codex-home`、`--wezterm-module-dir` 或 `--config-file` 时，实际路径会变化。`doctor --json` 会返回解析后的关键路径。

## 包资源与原子替换

npm 与 Python 包携带同版本的 Lua、bridge 和 contract 资源。安装过程不会再从 GitHub `main` 下载代码。

更新前先把全部资源复制到目标目录中的临时文件；完整暂存成功后，按 bridge、core 与子模块、Lua 入口的顺序替换。manifest 记录每个已安装资源的 SHA-256，`doctor` 用它检查缺失或被修改的文件。

配置 JSON 与 Hook 也通过同目录临时文件写入后 rename，降低中途终止留下部分 JSON 的概率。

## Hook 合并与备份

CLI 使用 JSON 解析合并 `$CODEX_HOME/hooks.json`：

- 保留文档中的其他顶层字段和 Hook 类型。
- 只移除旧的 `codex_statusline_bridge.*` handler，再添加当前包的 handler。
- 在实际重写前创建带时间戳的 `.bak-*` 副本。
- 卸载时只移除本项目 handler，空 group 才会一并移除。

备份可能包含其他工具的本地命令和路径，应按 Codex 配置文件同等保护。

## Terminal title 写入与恢复

启用 title bridge 时，CLI 启动本地 `codex app-server --stdio`，通过 `config/read` 与 `config/batchWrite` 更新：

```text
tui.terminal_title
```

manifest 保存该键原先是否存在、原值、安装值、目标文件和配置版本。卸载时：

- 当前值仍等于安装值：恢复原值，或删除安装器新增的值。
- 当前值已被用户或其他工具修改：保留当前值，不覆盖新配置。
- 配置版本在读写之间变化：停止并报告冲突。

写入请求使用 `reloadUserConfig = false`，不会要求 Codex 或 WezTerm 自动 reload。

## 运行时读取范围

Lua 模块读取：

- 当前 pane 的进程信息、CWD、title、dimensions 与 user vars。
- Codex 配置中的模型和 reasoning 默认值。
- 与当前 pane mapping 匹配的 rollout JSONL。
- 当前 CWD 的本地 Git 分支。
- bridge manifest 与当前 pane mapping。

运行时不发起网络请求，也不包含遥测。包管理器在获取 npm/Python 包时仍会访问其配置的软件源，这与插件运行时网络行为是两个边界。

## 非 WezTerm 环境

Hook 是 Codex 用户级配置，可能在其他终端中触发。bridge 首先验证 `WEZTERM_PANE` 是否为数字；无效时在读取 hook payload 前成功退出，不创建 mapping。

## 卸载边界

卸载先检查 WezTerm 配置是否仍 require 模块，命中时在任何恢复或删除操作之前退出。通过检查后，它只删除包清单中的根 Lua 文件、子模块、三个 bridge 文件和 manifest；不递归删除用户模块目录。

默认保留用户的 `codex_statusline_config.json`；`--purge-config` 才会删除。运行时 pane mapping 也不会逐个删除，因此 `$CODEX_HOME/wezterm-statusline/panes/` 非空时目录可能保留。mapping 含本机路径和 thread ID，对外分享或归档前应检查内容。
