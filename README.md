# kanagawa-statusline

A [Claude Code](https://docs.claude.com/en/docs/claude-code) statusline themed after [rebelot/kanagawa.nvim](https://github.com/rebelot/kanagawa.nvim). Lualine-inspired Powerline rendering with three Kanagawa variants, dynamic per-project runtime detection, and graceful degradation on narrow terminals.

![Kanagawa Wave theme — preview](docs/preview.png)
*Kanagawa **Wave** variant — `kanagawa-statusline wave`. (Dragon and Lotus also available — see [docs/USAGE.md](docs/USAGE.md).)*

## Highlights

- **Three Kanagawa variants** — `wave`, `dragon`, `lotus`
- **Per-project runtime detection** — node, bun, python, go, rust, zig, odin
- **Dynamic gradient** — N visible language segments map to N evenly-spaced gray stops
- **Graceful degradation** — drops lower-priority segments when the line gets narrow
- **CLI variant switcher** — `kanagawa-statusline <wave|dragon|lotus|off>`

## Requirements

- bash 4+, `jq`, `python3`
- Nerd-font patched mono font + 256-color terminal

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/securacore/kanagawa-statusline/main/install.sh | bash
```

The installer drops the script into `~/.claude/`, the CLI into `~/.local/bin/`, and merges a `statusLine` block into `~/.claude/settings.json`.

> [!TIP]
> Press Enter at the Claude Code prompt after install to refresh the statusline immediately.

## Quick start

```bash
kanagawa-statusline wave        # cool night (default)
kanagawa-statusline dragon      # warm earthy night
kanagawa-statusline lotus       # light theme
kanagawa-statusline off         # disable styling
kanagawa-statusline status      # show current variant
kanagawa-statusline uninstall   # remove all installed files
```

## Documentation

- [docs/USAGE.md](docs/USAGE.md) — CLI commands, config file, env vars, variant gallery
- [docs/INTERNALS.md](docs/INTERNALS.md) — architecture, palette knobs, customization

## Optional dependencies

- [JuliusBrussee/caveman](https://github.com/JuliusBrussee/caveman) — provides the orange caveman badge. Statusline reads the plugin's hook if installed; segment is silently skipped if absent.

## License

[MIT](LICENSE)
