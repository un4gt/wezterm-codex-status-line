---
sidebar_position: 2
title: Local files and data
description: Find configuration files, data access boundaries, and files kept after uninstall.
---

# Local files and data

The status line uses local Codex session records and WezTerm pane information. It sends no runtime network requests and collects no telemetry.

npx and uvx need network access to download packages from npm and PyPI. uv may also download Python and dependencies.

## File locations

`~` is the user home directory. When `$CODEX_HOME` is unset, it defaults to `~/.codex`.

| Path | Purpose |
| --- | --- |
| `~/.config/wezterm/codex_statusline.lua` | WezTerm entry point |
| `~/.config/wezterm/codex_statusline_core.lua` | Status line module |
| `~/.config/wezterm/codex_statusline/` | Status line submodules |
| `~/.config/wezterm/codex_statusline_config.json` | Display configuration created by `configure` |
| `$CODEX_HOME/hooks.json` | Codex hook configuration |
| `$CODEX_HOME/config.toml` | Codex configuration; changed when the terminal title is enabled |
| `$CODEX_HOME/wezterm-statusline/bin/` | Session-start scripts |
| `$CODEX_HOME/wezterm-statusline/bridge.json` | Installed version, paths, checksums, and title-restore record |
| `$CODEX_HOME/wezterm-statusline/panes/` | Pane-to-session mappings |

Use `--codex-home`, `--wezterm-module-dir`, or `--config-file` to change paths. Run `doctor --json` to see the effective paths.

## Command changes

| Command | Changes |
| --- | --- |
| `install`, `update` | Install status line files and add or update the session hook |
| `configure` | Save display configuration |
| `preview`, `doctor` | Read configuration and print results |
| `uninstall` | Remove files and this project's hook, then restore the terminal title |

You must load the module from your WezTerm configuration and reload it after installation.

## Hook backups

Before changing `hooks.json`, the installer creates a `.bak-*` backup. Other hooks and configuration fields are preserved. The session-start script can be called by Codex in another terminal; it exits when no valid WezTerm pane ID is available.

## Terminal title

`--title-bridge` changes `tui.terminal_title` in the Codex configuration and saves the old value. Uninstall restores it only when the current value is still the installer value; manual changes are preserved. Conflicting configuration versions abort the operation.

## Data read

The status line reads the current pane process, working directory, title, WezTerm user vars, relevant Codex configuration, and session records. Git branch and project name come from local Git queries.

Debug logs and diagnostics may contain usernames, paths, session IDs, and hook commands. Remove private information before sharing them.

## Files kept after uninstall

`codex_statusline_config.json` is kept by default. `uninstall --purge-config` removes it too. Session mappings and backups may remain under `$CODEX_HOME`; inspect them before sharing.
