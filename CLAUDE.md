# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A bash statusline script for Claude Code (the CLI), themed after `rebelot/kanagawa.nvim`. Three shipped artifacts:

- `statusline.sh` — the statusline renderer Claude Code pipes JSON into via stdin (installed to `~/.claude/statusline-command.sh`).
- `bin/kanagawa-statusline` — user-facing CLI for variant switching, version/check/update, and uninstall (installed to `~/.local/bin/kanagawa-statusline`).
- `install.sh` — idempotent installer; also re-used as the upgrade path.

Pure shell. No build step. Runtime deps: `bash 4+`, `jq`, `python3`, a Nerd Font.

## Common commands

```bash
just lint             # shellcheck -S warning + bash -n on all three scripts
just version          # show VERSION file vs embedded constant
just link             # symlink installed paths to this repo for live edits
just unlink           # reverse `just link`; restores prior install if any
just release [patch|minor|major]   # bump, commit "Release vX.Y.Z", tag, push (default patch)
just release-dry [level]           # preview the bump without touching anything
```

`just lint` is the only test surface. There is no unit-test suite.

To exercise the renderer locally without installing, pipe a fake stdin payload through it (the README's "Preview all variants" snippet in `docs/USAGE.md` is the canonical example). `STATUSLINE_DEMO=1` forces all 7 lang segments to render with placeholders.

## Release flow — three-way version sync

The release pipeline asserts three things agree before publishing:

1. `VERSION` file at repo root
2. `KANAGAWA_STATUSLINE_VERSION="X.Y.Z"` constant near the top of `statusline.sh`
3. The pushed `vX.Y.Z` git tag

`just release` rewrites (1) and (2) in lockstep, commits, tags, and pushes both branch + tag. The tag push fires `.github/workflows/release.yml`, which re-validates the three-way sync, runs `just lint`, and publishes a GitHub Release with `statusline.sh`, `install.sh`, and `bin/kanagawa-statusline` attached.

If you edit the version constant by hand, update `VERSION` to match — anything missed produces a workflow failure rather than a silent bad release.

## Architecture — `statusline.sh`

Single-file, top-to-bottom render pipeline. Every render is a fresh process spawn from Claude Code, so all state lives in caches under `$TMPDIR` and `$XDG_CACHE_HOME`.

Two clusters:

- **Left** (priority anchors, never dropped): ctx % → model+effort → branch → cwd basename
- **Right** (gradient + warm exit): lang segments (node/bun/py/go/rust/zig/odin) → style → cli version → caveman → update

Key mechanics, all in `statusline.sh`:

- **`apply_palette()`** — per-variant color tokens (`CTX_BG`, `A_BG`, `B_BG`, `C_BG`, `GRAD_MIN/MAX`, `Y_BG`, `Z_BG`, `X_BG`, `U_BG`, plus `DIV_FG` for xlean). Each base palette (`wave`, `dragon`, `lotus`) ships in three forms: full powerline, `-lean` (muted monochromatic), and `-xlean` (text-only with ` │ ` divider). Plus `off`. The `*-lean` variants use a single-family bg ramp (sumiInk for wave/dragon, lotusWhite for lotus) with low-contrast accent fgs and full powerline structure. The `*-xlean` variants render fg-only on the terminal default bg, separated by a divider in `DIV_FG` — no bg fills, no powerline arrows.
- **Style flag** — `KANAGAWA_STYLE` is derived from the variant suffix (`*-xlean` → `text`, else `powerline`) and gates `seg`/`ltrans`/`rtrans` plus the leading/trailing caps in `build_left`/`build_right`.
- **Dynamic gradient** — `build_right_data()` recomputes per-segment grays each render: N visible langs map to N evenly-spaced stops between `GRAD_MIN` and `GRAD_MAX`, so 2 langs span the full gradient like 7 would.
- **Graceful degradation** — if right cluster overruns the line, lang segments are dropped one at a time per `drop_order=(odin zig rust go node bun py)` until content fits. CLI / caveman / style are never dropped.
- **Right-edge alignment** — true terminal width via `stty size </dev/tty` (Claude Code's spawned subshell doesn't pass `$COLUMNS`); minus `KANAGAWA_CHROME` (default 4) for TUI margins. Visible width uses a Python helper that respects East Asian Width and maps Private Use Area glyphs (nerd-font icons) to `KANAGAWA_PUA_WIDTH` cells (default 1, suits Mono nerd-font variants).
- **Variant resolution** — `KANAGAWA_VARIANT` env → `$XDG_CONFIG_HOME/kanagawa-statusline/config` (`VARIANT=`) → `wave-xlean` default.

### Caches

- Per-project runtime versions cached 5 min in `$TMPDIR/cc-statusline-rt-<md5(project_path)>`.
- Update probe caches latest remote version in `$XDG_CACHE_HOME/kanagawa-statusline/latest-version`, default TTL 86400s. When stale, statusline forks a detached `curl` (lockdir prevents stacking; stale lock >60s auto-cleared) and the current render uses prior cache — fresher value lands next render.

### JSON fields consumed from stdin

`model.display_name`, `effort.level`, `workspace.project_dir`, `workspace.current_dir`, `cwd`, `version`, `output_style.name`, `context_window.used_percentage`, `context_window.context_window_size`. Schema: https://docs.claude.com/en/docs/claude-code/statusline.

### Security guards (don't regress these)

- **Caveman flag file** (`$CLAUDE_CONFIG_DIR/.caveman-active`): symlinks rejected, read hard-capped at 64 bytes, mode whitelisted before being included in the badge string. Prevents an attacker pointing the flag at `~/.ssh/id_rsa` and rendering its bytes to the terminal.
- **Update-check VERSION**: response run through `tr -cd '0-9.'` before being cached or compared — defeats MITM-tampered VERSION trying to leak escape sequences into a future render.
- **Self-update**: downloads land in tempdir, are syntax-checked with `bash -n`, must contain a `KANAGAWA_STATUSLINE_VERSION=` line, only then atomically replace the installed copy.

## Where docs live

- `README.md` — install + headline feature list
- `docs/USAGE.md` — CLI commands, config file, env vars
- `docs/INTERNALS.md` — architecture deep-dive, palette tables, mermaid flow diagrams. Authoritative reference when touching layout / gradient / degradation logic.
