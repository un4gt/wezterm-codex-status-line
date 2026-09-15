---
sidebar_position: 2
title: CLI 命令参考
description: 查看 npx 与 uvx 入口的命令、参数、输出和退出码。
---

# CLI 命令参考

两个包入口暴露相同的六个命令：`install`、`configure`、`preview`、`doctor`、`update` 与 `uninstall`。

## 调用格式

```text
wezterm-codex-status-line [全局选项] <命令> [命令选项]
```

为兼容 Python/Typer 入口，全局选项统一放在命令之前：

```bash
uvx --refresh wezterm-codex-status-line --json doctor
```

使用 npx 时，第一个 `--yes` 属于 npx，用于跳过包执行确认：

```powershell
npx --yes wezterm-codex-status-line@latest doctor
```

## 全局选项

| 选项 | 作用 |
| --- | --- |
| `--codex-home <path>` | 覆盖 `$CODEX_HOME` 或 `~/.codex` |
| `--wezterm-module-dir <path>` | 覆盖 `~/.config/wezterm` 模块目录 |
| `--config-file <path>` | 覆盖 CLI 读写的 schema 1 配置路径 |
| `--json` | 输出 schema 1 的机器可读命令结果 |
| `--no-color` | 关闭 CLI 预览中的 ANSI 色彩 |
| `--yes` | 跳过 CLI 交互确认；`install` 时等价于选择启用 title bridge |
| `--version` | 输出包版本 |

npx 如需把 `--yes` 传给本项目 CLI，需要在包名之后再写一次：

```powershell
npx --yes wezterm-codex-status-line@latest --yes install
```

自动化安装更推荐直接使用 `install --title-bridge` 或 `install --no-title-bridge`。

## `install`

安装 Lua 模块、bridge、Hook 与 manifest。

| 选项 | 作用 |
| --- | --- |
| `--title-bridge` | 配置 Codex terminal title |
| `--no-title-bridge` | 不配置 terminal title |
| `--dry-run` | 不写文件，只返回预演结果 |

非交互运行必须提供 title 选择，或使用全局 `--yes`。

## `configure`

读取现有配置或默认配置，应用参数，校验 schema，显示预览并原子写入 JSON。

| 选项 | 作用 |
| --- | --- |
| `--from <path>` | 导入完整 schema 1 JSON |
| `--label <text>` | 设置 1–24 字符标签 |
| `--rows 1\|2` | 设置状态 pane 行数 |
| `--binding-mode auto\|hook\|heuristic` | 设置 thread 绑定模式 |
| `--segments <ids>` | 设置逗号分隔的 segment 顺序 |
| `--disable <ids>` | 设置逗号分隔的隐藏列表；空字符串清空列表 |
| `--powerline` / `--no-powerline` | 开关 Powerline 渲染 |
| `--theme-bg <#RRGGBB>` | 设置默认背景色 |
| `--theme-fg <#RRGGBB>` | 设置默认前景色 |
| `--theme-dim <#RRGGBB>` | 设置弱化文字色 |
| `--color <id:bg:fg>` | 设置一个 segment 的背景色与前景色，可重复 |
| `--width <columns>` | 设置 CLI 预览宽度，默认 120 |
| `--dry-run` | 校验并预览，但不写配置 |

`--segments` 只调整顺序，不隐藏遗漏的合法 ID；隐藏字段应使用 `--disable`。

## `preview`

使用当前配置和模拟数据输出状态栏，不写文件。

| 选项 | 作用 |
| --- | --- |
| `--width <columns>` | 模拟终端列数；默认使用输出终端宽度或 120 |
| `--state <path>` | 读取自定义模拟状态 JSON，主要用于开发与测试 |

## `doctor`

只读检查以下项目：

| 检查项 | 内容 |
| --- | --- |
| `manifest` | `bridge.json` 是否存在 |
| `lua_entry` / `lua_core` | 两个 Lua 模块是否存在 |
| `asset_integrity` | 已安装资源是否与 manifest SHA-256 一致 |
| `hooks` | `hooks.json` 是否包含本项目 bridge handler |
| `wezterm_require` | WezTerm 配置是否调用 `require("codex_statusline")` |
| `config` | 可选 schema 1 配置是否有效 |

`doctor` 不启动 WezTerm，不读取正在运行的 pane，也不验证 Codex 是否会触发 Hook。

## `update`

使用当前包版本重新安装资源并保留用户配置。

| 选项 | 作用 |
| --- | --- |
| `--title-bridge` | 此前未启用时，配置 terminal title |
| `--no-title-bridge` | 本次不启用；不会移除已有 title 配置 |
| `--dry-run` | 不写文件，只返回预演结果 |

## `uninstall`

恢复受管 title 配置、移除本项目 Hook 与包资源。

| 选项 | 作用 |
| --- | --- |
| `--purge-config` | 同时删除 `codex_statusline_config.json` |
| `--dry-run` | 执行安全前置检查，但不写文件 |

只要 WezTerm 配置仍调用模块，卸载就会以退出码 `3` 拒绝；没有强制绕过选项。

## JSON 输出与退出码

JSON 结果包含 `schema`、`command`、`version`、`status`、`changes`、`warnings` 与解析后的关键路径。`preview` 还包含渲染文本。

| 退出码 | 含义 |
| ---: | --- |
| `0` | 成功 |
| `1` | 执行失败，或 `doctor` 未全部通过 |
| `2` | 参数/配置无效，或取消交互 |
| `3` | 安全策略拒绝操作 |
