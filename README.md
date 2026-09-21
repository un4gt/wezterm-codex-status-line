<p align="center">
    <a href="https://linux.do" alt="LINUX DO">
        <img
            src="https://img.shields.io/badge/LINUX-DO-FFB003.svg?logo=data:image/svg%2bxml;base64,DQo8c3ZnIHhtbG5zPSJodHRwOi8vd3d3LnczLm9yZy8yMDAwL3N2ZyIgd2lkdGg9IjEwMCIgaGVpZ2h0PSIxMDAiPjxwYXRoIGQ9Ik00Ni44Mi0uMDU1aDYuMjVxMjMuOTY5IDIuMDYyIDM4IDIxLjQyNmM1LjI1OCA3LjY3NiA4LjIxNSAxNi4xNTYgOC44NzUgMjUuNDV2Ni4yNXEtMi4wNjQgMjMuOTY4LTIxLjQzIDM4LTExLjUxMiA3Ljg4NS0yNS40NDUgOC44NzRoLTYuMjVxLTIzLjk3LTIuMDY0LTM4LjAwNC0yMS40M1EuOTcxIDY3LjA1Ni0uMDU0IDUzLjE4di02LjQ3M0MxLjM2MiAzMC43ODEgOC41MDMgMTguMTQ4IDIxLjM3IDguODE3IDI5LjA0NyAzLjU2MiAzNy41MjcuNjA0IDQ2LjgyMS0uMDU2IiBzdHlsZT0ic3Ryb2tlOm5vbmU7ZmlsbC1ydWxlOmV2ZW5vZGQ7ZmlsbDojZWNlY2VjO2ZpbGwtb3BhY2l0eToxIi8+PHBhdGggZD0iTTQ3LjI2NiAyLjk1N3EyMi41My0uNjUgMzcuNzc3IDE1LjczOGE0OS43IDQ5LjcgMCAwIDEgNi44NjcgMTAuMTU3cS00MS45NjQuMjIyLTgzLjkzIDAgOS43NS0xOC42MTYgMzAuMDI0LTI0LjM4N2E2MSA2MSAwIDAgMSA5LjI2Mi0xLjUwOCIgc3R5bGU9InN0cm9rZTpub25lO2ZpbGwtcnVsZTpldmVub2RkO2ZpbGw6IzE5MTkxOTtmaWxsLW9wYWNpdHk6MSIvPjxwYXRoIGQ9Ik03Ljk4IDcwLjkyNmMyNy45NzctLjAzNSA1NS45NTQgMCA4My45My4xMTNRODMuNDI2IDg3LjQ3MyA2Ni4xMyA5NC4wODZxLTE4LjgxIDYuNTQ0LTM2LjgzMi0xLjg5OC0xNC4yMDMtNy4wOS0yMS4zMTctMjEuMjYyIiBzdHlsZT0ic3Ryb2tlOm5vbmU7ZmlsbC1ydWxlOmV2ZW5vZGQ7ZmlsbDojZjlhZjAwO2ZpbGwtb3BhY2l0eToxIi8+PC9zdmc+" /></a>
</p>

# WezTerm Codex Status Line

English | [简体中文](README_zh_CN.md)

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

See [CONTRIBUTING.md](CONTRIBUTING.md) for build and test instructions.

## Acknowledgments

The configuration and preview features were inspired by [ccstatusline](https://github.com/sirmalloc/ccstatusline) and [CCometixLine](https://github.com/Haleclipse/CCometixLine).

## License

[MIT](LICENSE)
