---
sidebar_position: 2
title: CLI reference
description: Commands, options, output, and exit codes for the npx and uvx entry points.
---

# CLI reference

The npx and uvx entry points provide six commands: `install`, `configure`, `preview`, `doctor`, `update`, and `uninstall`.

## Invocation

```text
wezterm-codex-status-line [global options] <command> [command options]
```

Global options come before the subcommand:

```bash
uvx wezterm-codex-status-line --json doctor
npx --yes wezterm-codex-status-line@0.1.2 doctor
```

With npx, the first `--yes` belongs to npx. To pass `--yes` to this CLI, write it after the package name:

```powershell
npx --yes wezterm-codex-status-line@0.1.2 --yes install
```

## Global options

| Option | Purpose |
| --- | --- |
| `--codex-home <path>` | Override `$CODEX_HOME` or `~/.codex` |
| `--wezterm-module-dir <path>` | Override the `~/.config/wezterm` module directory |
| `--config-file <path>` | Choose the CLI configuration file |
| `--json` | Print command results as JSON |
| `--no-color` | Disable terminal preview colors |
| `--yes` | Skip CLI confirmation; for `install`, selects the title-bridge setting |
| `--version` | Print the package version |

## `install`

Installs status line files and adds the Codex session-start hook.

| Option | Purpose |
| --- | --- |
| `--title-bridge` | Configure the Codex terminal title |
| `--no-title-bridge` | Do not configure the terminal title |
| `--dry-run` | Show changes without writing files |

Use an explicit title-bridge option in automation. macOS and Linux should use `--no-title-bridge`.

## `configure`

Edits the display configuration. Without options it opens the interactive wizard; `--from` imports a complete JSON file.

| Option | Purpose |
| --- | --- |
| `--from <path>` | Import a complete configuration JSON |
| `--label <text>` | Set a 1–24 character label |
| `--rows 1\|2` | Set the number of status rows |
| `--binding-mode auto\|hook\|heuristic` | Set the session binding mode |
| `--segments <ids>` | Set field order, comma separated |
| `--disable <ids>` | Set the hidden-field list; an empty string clears it |
| `--powerline` / `--no-powerline` | Enable or disable Powerline rendering |
| `--theme-bg <#RRGGBB>` | Set the default background |
| `--theme-fg <#RRGGBB>` | Set the default foreground |
| `--theme-dim <#RRGGBB>` | Set the muted text color |
| `--color <id:bg:fg>` | Set a field's colors; repeatable |
| `--width <columns>` | Set CLI preview width; default 120 |
| `--dry-run` | Validate and preview without saving |

`--segments` changes order only. Use `--disable` to hide valid fields.

## `preview`

Renders the current configuration with sample data without writing files.

| Option | Purpose |
| --- | --- |
| `--width <columns>` | Simulated terminal width; defaults to terminal width or 120 |
| `--state <path>` | Read custom preview state JSON |

## `doctor`

Checks the installation and configuration:

| Check | What it verifies |
| --- | --- |
| `manifest` | `bridge.json` exists |
| `lua_entry` / `lua_core` | Status line modules exist |
| `asset_integrity` | Installed files are present and unchanged |
| `hooks` | `hooks.json` contains this project's session hook |
| `wezterm_require` | WezTerm configuration calls `require("codex_statusline")` |
| `config` | Display configuration is valid |

`doctor` checks local files. Confirm a running session in WezTerm itself.

## `update`

Reinstalls assets from the current package while preserving user configuration.

| Option | Purpose |
| --- | --- |
| `--title-bridge` | Configure the terminal title if it was not enabled |
| `--no-title-bridge` | Do not enable it this time; existing title settings remain |
| `--dry-run` | Show changes without writing files |

## `uninstall`

Removes status line files and the session hook, and restores the terminal title from the installation record.

| Option | Purpose |
| --- | --- |
| `--purge-config` | Also delete `codex_statusline_config.json` |
| `--dry-run` | Check conditions without writing files |

Remove the module reference from WezTerm and reload it first. If it is still referenced, the command returns exit code `3`.

## JSON output and exit codes

JSON results include `schema`, `command`, `version`, `status`, `changes`, `warnings`, and resolved paths. `preview` also includes rendered text.

| Exit code | Meaning |
| ---: | --- |
| `0` | Success |
| `1` | Execution failure, or `doctor` did not pass all checks |
| `2` | Invalid arguments/configuration, or cancelled interaction |
| `3` | An operation precondition was not met, such as a remaining WezTerm reference |
