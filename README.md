# kanagawa-statusline

![Kanagawa Wave theme — preview](docs/preview.png)

A simple [Claude Code](https://docs.claude.com/en/docs/claude-code) CLI statusline themed after [rebelot/kanagawa.nvim](https://github.com/rebelot/kanagawa.nvim). Lualine-inspired Powerline rendering with three Kanagawa variants, dynamic per-project runtime detection, and graceful degradation on narrow terminals.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/securacore/kanagawa-statusline/main/install.sh | bash
```

## Basic Usage

```bash
kanagawa-statusline wave        # cool night (default)
kanagawa-statusline dragon      # warm earthy night
kanagawa-statusline lotus       # light theme
kanagawa-statusline off         # disable styling
kanagawa-statusline status      # show current variant + installed version
kanagawa-statusline version     # print installed version
kanagawa-statusline check       # check for a new release (synchronous)
kanagawa-statusline update      # self-update statusline + CLI to latest
kanagawa-statusline uninstall   # remove all installed files
```

## Highlights

- **Three Kanagawa variants** — `wave`, `dragon`, `lotus`
- **Per-project runtime detection** — node, bun, python, go, rust, zig, odin
- **Dynamic gradient** — N visible language segments map to N evenly-spaced gray stops
- **Graceful degradation** — drops lower-priority segments when the line gets narrow
- **CLI variant switcher** — `kanagawa-statusline <wave|dragon|lotus|off>`
- **Update check + self-update** — daily background probe of the repo; renders an `update vX.Y.Z` segment when a new release lands. `kanagawa-statusline update` swaps in the latest version.

## Documentation

- [docs/USAGE.md](docs/USAGE.md) — CLI commands, config file, env vars, variant gallery
- [docs/INTERNALS.md](docs/INTERNALS.md) — architecture, palette knobs, customization

## Optional dependencies

- [JuliusBrussee/caveman](https://github.com/JuliusBrussee/caveman)

## Development

Releases are driven by a `Justfile`:

```bash
just release          # +1 patch (default)
just release patch    # +1 patch
just release minor    # +1 minor, reset patch
just release major    # +1 major, reset minor + patch
just release-dry      # preview the bump (accepts the same levels)
just lint             # shellcheck + bash -n
```

Each `just release <level>` bumps `VERSION` and the embedded `KANAGAWA_STATUSLINE_VERSION` constant in lockstep, commits `Release vX.Y.Z`, tags `vX.Y.Z`, and pushes the branch + tag. The tag push fires `.github/workflows/release.yml`, which validates the three-way version sync (tag ↔ `VERSION` ↔ constant), lints, and publishes a GitHub Release with assets attached.

## Documentation

- [docs/USAGE.md](docs/USAGE.md) — CLI commands, config file, env vars, variant gallery
- [docs/INTERNALS.md](docs/INTERNALS.md) — architecture, palette knobs, customization
