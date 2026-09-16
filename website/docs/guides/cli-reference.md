---
sidebar_position: 2
title: 命令行参考
description: 查看 npx 与 uvx 入口的命令、参数、输出和退出码。
---

# 命令行参考

npx 和 uvx 入口提供相同的六个命令：`install`、`configure`、`preview`、`doctor`、`update` 与 `uninstall`。

## 调用格式

```text
wezterm-codex-status-line [全局选项] <命令> [命令选项]
```

全局选项放在子命令之前。例如，输出 JSON 格式的检查结果：

```bash
uvx --from https://github.com/un4gt/wezterm-codex-status-line/releases/download/v0.1.0/wezterm_codex_status_line-0.1.0-py3-none-any.whl wezterm-codex-status-line --json doctor
```

使用 npx 时，第一个 `--yes` 属于 npx，用于跳过包执行确认：

```powershell
npx --yes --package=https://github.com/un4gt/wezterm-codex-status-line/releases/download/v0.1.0/wezterm-codex-status-line-0.1.0.tgz wezterm-codex-status-line doctor
```

## 全局选项

| 选项 | 作用 |
| --- | --- |
| `--codex-home <path>` | 覆盖 `$CODEX_HOME` 或 `~/.codex` |
| `--wezterm-module-dir <path>` | 覆盖 `~/.config/wezterm` 模块目录 |
| `--config-file <path>` | 指定 CLI 读写的配置文件 |
| `--json` | 以 JSON 输出命令结果 |
| `--no-color` | 关闭终端预览颜色 |
| `--yes` | 跳过 CLI 交互确认；`install` 时等价于选择启用 title bridge |
| `--version` | 输出包版本 |

npx 如需把 `--yes` 传给本项目 CLI，需要在包名之后再写一次：

```powershell
npx --yes --package=https://github.com/un4gt/wezterm-codex-status-line/releases/download/v0.1.0/wezterm-codex-status-line-0.1.0.tgz wezterm-codex-status-line --yes install
```

自动化安装更推荐直接使用 `install --title-bridge` 或 `install --no-title-bridge`。

## `install`

安装状态栏文件并添加 Codex 会话启动 hook。安装步骤见[安装指南](../getting-started/installation.md)。

| 选项 | 作用 |
| --- | --- |
| `--title-bridge` | 配置 Codex terminal title |
| `--no-title-bridge` | 不配置 terminal title |
| `--dry-run` | 显示操作结果，不写入文件 |

脚本中运行安装命令时，使用 `--title-bridge` 或 `--no-title-bridge` 指定标题设置。macOS 和 Linux 使用 `--no-title-bridge`。

## `configure`

修改显示配置并输出预览。不带选项时，在交互式终端中打开配置向导；使用 `--from` 导入完整 JSON。

| 选项 | 作用 |
| --- | --- |
| `--from <path>` | 导入完整配置 JSON |
| `--label <text>` | 设置 1–24 字符标签 |
| `--rows 1\|2` | 设置状态栏行数 |
| `--binding-mode auto\|hook\|heuristic` | 设置会话绑定模式 |
| `--segments <ids>` | 设置字段顺序，以逗号分隔 |
| `--disable <ids>` | 设置逗号分隔的隐藏列表；空字符串清空列表 |
| `--powerline` / `--no-powerline` | 开关 Powerline 渲染 |
| `--theme-bg <#RRGGBB>` | 设置默认背景色 |
| `--theme-fg <#RRGGBB>` | 设置默认前景色 |
| `--theme-dim <#RRGGBB>` | 设置弱化文字色 |
| `--color <id:bg:fg>` | 设置一个字段的背景色与前景色，可重复 |
| `--width <columns>` | 设置 CLI 预览宽度，默认 120 |
| `--dry-run` | 校验并预览，但不写配置 |

`--segments` 只调整顺序，不隐藏遗漏的合法 ID；隐藏字段应使用 `--disable`。

## `preview`

使用当前配置和模拟数据输出状态栏，不写文件。

| 选项 | 作用 |
| --- | --- |
| `--width <columns>` | 模拟终端列数；默认使用输出终端宽度或 120 |
| `--state <path>` | 读取自定义预览数据 JSON |

## `doctor`

检查安装与配置，输出每项结果：

| 检查项 | 内容 |
| --- | --- |
| `manifest` | `bridge.json` 是否存在 |
| `lua_entry` / `lua_core` | 状态栏模块是否存在 |
| `asset_integrity` | 安装文件是否缺失或被修改 |
| `hooks` | `hooks.json` 是否包含本项目的会话启动 hook |
| `wezterm_require` | WezTerm 配置是否调用 `require("codex_statusline")` |
| `config` | 显示配置是否有效 |

`doctor` 检查本地文件。正在运行的会话是否显示正常，需要在 WezTerm 中确认。

## `update`

使用当前包版本重新安装资源并保留用户配置。

| 选项 | 作用 |
| --- | --- |
| `--title-bridge` | 此前未启用时，配置 terminal title |
| `--no-title-bridge` | 本次不启用；不会移除已有 title 配置 |
| `--dry-run` | 显示操作结果，不写入文件 |

## `uninstall`

移除状态栏文件和会话启动 hook，并按安装记录恢复终端标题。

| 选项 | 作用 |
| --- | --- |
| `--purge-config` | 同时删除 `codex_statusline_config.json` |
| `--dry-run` | 检查操作条件，不写入文件 |

卸载前，先从 WezTerm 配置中移除模块引用并重新加载配置。检测到引用时，命令返回退出码 `3`。详见[卸载步骤](../getting-started/update-uninstall.md#卸载)。

## JSON 输出与退出码

JSON 结果包含 `schema`、`command`、`version`、`status`、`changes`、`warnings` 与解析后的关键路径。`preview` 还包含渲染文本。

| 退出码 | 含义 |
| ---: | --- |
| `0` | 成功 |
| `1` | 执行失败，或 `doctor` 未全部通过 |
| `2` | 参数/配置无效，或取消交互 |
| `3` | 未满足操作条件，例如 WezTerm 配置仍引用模块 |
