# WezTerm Codex Status Line

English | [简体中文](https://github.com/un4gt/wezterm-codex-status-line/blob/main/README_zh_CN.md)

Add a bottom status bar for Codex CLI in WezTerm, showing the model, reasoning effort, working directory, Git branch, and token usage.

[Documentation](https://un4gt.github.io/wezterm-codex-status-line/) · [Interactive preview](https://un4gt.github.io/wezterm-codex-status-line/preview/) · [Configuration guide](https://un4gt.github.io/wezterm-codex-status-line/docs/guides/configuration/) · [Troubleshooting](https://un4gt.github.io/wezterm-codex-status-line/docs/troubleshooting/common-issues/)

- Show session information for each Codex pane, with support for multiple concurrent sessions.
- Customize fields, colors, icons, and one- or two-row layouts.
- Track cumulative input, output, cache hit rate, and estimated cost.
- Preview your configuration in the browser, download JSON, and import it locally.
- Read local Codex session logs without making additional model requests.

```text
CODEX | gpt-5.6-sol | high | ~/src/app | main | Ctx 72% left | ↑10M ↓204K | Cache 60% | Cost ~$22.48 |  v0.1.2
```

## Installation

With Node.js 20 or later:

```sh
npx --yes wezterm-codex-status-line@latest install --no-title-bridge
```

Or with uv:

```sh
uvx wezterm-codex-status-line install --no-title-bridge
```

Choose either command: npx installs from npm, and uvx installs from PyPI. Windows requires PowerShell 5.1 or later. macOS has not yet been verified on physical hardware; Linux has not yet been verified in a Wayland/X11 desktop environment. See the [installation guide](https://un4gt.github.io/wezterm-codex-status-line/docs/getting-started/installation/) for other requirements.

Add the following before `return config` in your WezTerm configuration:

```lua
config.status_update_interval = 500
require("codex_statusline").setup()
```

Reload your WezTerm configuration, start `codex` in a pane, and send a message. Session information will appear below that pane.

## Configuration

Customize the display in the [interactive preview](https://un4gt.github.io/wezterm-codex-status-line/preview/), download the JSON file, and import it:

```sh
npx --yes wezterm-codex-status-line@latest configure --from ./codex_statusline_config.json
```

Reload your WezTerm configuration to apply changes. Settings are saved to `~/.config/wezterm/codex_statusline_config.json` by default. You can also pass options to `setup({...})`. See the [configuration guide](https://un4gt.github.io/wezterm-codex-status-line/docs/guides/configuration/) for details.

## Commands

| Command | Purpose |
| --- | --- |
| `install` | Install the status bar |
| `configure` | Edit or import configuration |
| `preview` | Preview the current configuration in your terminal |
| `doctor` | Check installation and configuration |
| `update` | Update the status bar while preserving configuration |
| `uninstall` | Uninstall the status bar |

To update an existing installation with the latest package:

```sh
npx --yes wezterm-codex-status-line@latest update
# Or:
uvx --refresh wezterm-codex-status-line update
```

See the [CLI reference](https://un4gt.github.io/wezterm-codex-status-line/docs/guides/cli-reference/) for command options. Before uninstalling, remove the `setup()` call from your WezTerm configuration and reload it. See [updating and uninstalling](https://un4gt.github.io/wezterm-codex-status-line/docs/getting-started/update-uninstall/) for details.

## Contributing

See [CONTRIBUTING.md](https://github.com/un4gt/wezterm-codex-status-line/blob/main/CONTRIBUTING.md) for build and test instructions.

## Acknowledgments

The configuration and preview features were inspired by [ccstatusline](https://github.com/sirmalloc/ccstatusline) and [CCometixLine](https://github.com/Haleclipse/CCometixLine).

## License

[MIT](https://github.com/un4gt/wezterm-codex-status-line/blob/main/LICENSE)
