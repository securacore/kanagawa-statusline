# Internals

## Layout

```mermaid
flowchart LR
  subgraph LEFT["LEFT — anchors"]
    direction LR
    ctx["ctx %"] --> model["model (effort)"] --> branch["git branch"] --> cwd["cwd basename"]
  end
  subgraph RIGHT["RIGHT — gradient + warm exit"]
    direction LR
    langs["langs (dark to light)"] --> style["style"] --> cli["cli version"] --> caveman["caveman"] --> update["update vX.Y.Z"]
  end
  LEFT -.pad.- RIGHT
```

- **Protrude transition** — the boundary between ctx % and model uses a left-pointing Powerline arrow (instead of the standard right-pointing one), making the model bg appear to push leftward into ctx. Visually anchors the left edge.
- **Cap glyphs** — leading left cap on the ctx anchor, trailing right cap after caveman. Both colored to match the adjacent segment.

## Dynamic gradient

The right cluster's lang segments don't have hardcoded colors. `build_right_data()` recomputes per-segment grays each render based on how many lang segments are currently active (after degradation):

```
N visible langs  →  N evenly-spaced stops between GRAD_MIN and GRAD_MAX
```

So 2 langs span the full gradient just like 7 langs would, only with bigger gaps. Defaults: `GRAD_MIN=232` (sumiInk0), `GRAD_MAX=250` (near fujiWhite).

The fg picks darker text for lighter backgrounds via a threshold check.

## Graceful degradation

When the right cluster overruns the line, language segments are dropped one at a time until content fits.

```mermaid
flowchart TD
  build[build_right_data with active_langs] --> measure["pad = cols - lvis - rvis"]
  measure --> check{"pad >= 1?"}
  check -->|yes| render[Render]
  check -->|no| any{"droppable lang remaining?"}
  any -->|yes| drop[drop_one: pop next from drop_order]
  drop --> build
  any -->|no| render
```

```
drop_order=(odin zig rust go node bun py)
```

Cli, caveman, and style segments are never dropped (kept off the order list).

## Right-edge alignment

True terminal width comes from `stty size </dev/tty` (works inside Claude Code's spawned subshell where `$COLUMNS` is unset). A small chrome buffer (`cols - $KANAGAWA_CHROME`, default `4` — covers Claude Code's left+right TUI margins). Tunable per-terminal if your renderer is different.

Visible widths use a python helper that respects East Asian Width *and* maps Private Use Area glyphs (nerd-font icons) to `$KANAGAWA_PUA_WIDTH` cells (default `1`, suits Mono nerd-font variants). Set `KANAGAWA_PUA_WIDTH=2` if your font renders icons double-wide.

> [!NOTE]
> Defaults are calibrated for Mono nerd-font variants in Ghostty/iTerm2/etc. If alignment is off, tune `KANAGAWA_CHROME` (TUI padding) and `KANAGAWA_PUA_WIDTH` (glyph width) until the right cluster sits flush against the right edge.

## Variant palettes

Each Kanagawa variant defines its own color tokens via `apply_palette()`. Hex values mapped to nearest ANSI 256:

| token       | wave              | dragon              | lotus              |
|-------------|-------------------|---------------------|--------------------|
| ctx anchor  | 60 (deep violet)  | 96 (dragonViolet)   | 60 (lotusViolet4)  |
| model       | 110 (crystalBlue) | 109 (dragonBlue2)   | 24 (lotusBlue4)    |
| branch      | 24 (waveBlue2)    | 66 (dragonAqua-ish) | 152 (lotusBlue3)   |
| cwd         | 237 (sumiInk5)    | 235 (dragonBlack4)  | 187 (lotusWhite)   |
| GRAD_MIN    | 232               | 234                 | 250                |
| GRAD_MAX    | 250               | 247                 | 255                |
| style       | 179 (boatYellow2) | 144 (dragonYellow)  | 178 (lotusYellow3) |
| cli         | 173 (muted orange)| 180 (dragonOrange2) | 208 (lotusOrange2) |
| caveman     | 215 (surimiOrange)| 173 (dragonOrange)  | 166 (lotusOrange)  |
| update      | 167 (samuraiRed)  | 167 (dragonRed)     | 124 (lotusRed)     |

## Customization knobs

All tunables sit near the top of `statusline.sh`.

| Knob                          | Effect                                                                         |
|-------------------------------|--------------------------------------------------------------------------------|
| `KANAGAWA_VARIANT`            | env override — wave / dragon / lotus / off                                     |
| `apply_palette()` cases       | Per-variant color tokens (CTX_BG, A_BG, B_BG, C_BG, GRAD_MIN/MAX, Y/Z/X/U)     |
| `drop_order`                  | Lang priority for graceful degradation (first dropped first)                   |
| `KANAGAWA_CHROME`             | Chrome buffer for right-edge alignment (default `4`)                           |
| `KANAGAWA_PUA_WIDTH`          | Cell width for nerd-font PUA glyphs (default `1`; set `2` for non-Mono fonts)  |
| `STATUSLINE_DEMO=1`           | Env flag — preview all 7 lang segments with placeholder versions               |
| `KANAGAWA_NO_UPDATE_CHECK`    | Set to `1` to skip the background update probe                                 |
| `KANAGAWA_UPDATE_TTL`         | Update-probe cache lifetime in seconds (default `86400` — 24h)                 |
| `KANAGAWA_VERSION_URL`        | URL the probe fetches (default points at `main` branch `/VERSION`)             |

## JSON fields consumed

The script reads these fields from the JSON Claude Code pipes via stdin:

- `model.display_name`, `effort.level` — left model segment
- `workspace.project_dir`, `workspace.current_dir`, `cwd` — paths
- `version` — cli version segment
- `output_style.name` — style segment (rendered when not `default`)
- `context_window.used_percentage` — ctx anchor

Schema reference: [Claude Code statusline docs](https://docs.claude.com/en/docs/claude-code/statusline).

## Caching

Per-project runtime versions (node/bun/py/...) are cached for 5 minutes in `$TMPDIR/cc-statusline-rt-<hash>`. The cache key is an md5 of the project path. Subsequent renders within the TTL skip the runtime lookups.

The update-check probe caches the latest remote version in `$XDG_CACHE_HOME/kanagawa-statusline/latest-version` (defaults to `~/.cache/kanagawa-statusline/latest-version`). Default TTL `86400`s; mtime is age. When stale, the statusline forks a detached `curl` (lock dir prevents concurrent fetches stacking up; stale lock >60s is auto-cleared) and the current render uses the prior cache — fresher value lands on the next render.

## Update flow

```mermaid
flowchart LR
  render[render] --> stale{cache stale?}
  stale -->|no| compare
  stale -->|yes| bg[detached curl /VERSION] --> cache[(latest-version)]
  cache --> compare{remote > installed?}
  compare -->|yes| seg[render update segment]
  compare -->|no| done[no segment]
```

Source of truth for the **installed** version: the `KANAGAWA_STATUSLINE_VERSION` constant near the top of `statusline.sh`. Source of truth for the **remote** version: `/VERSION` at the repo root. The release pipeline asserts `git tag` ↔ `VERSION` ↔ constant agree before publishing — anything missed produces a workflow failure rather than a silent bad release.

## Security guards

A few attacker-write scenarios are explicitly defended:

- **Caveman flag file** — symlinks are rejected (so an attacker can't point the flag at `~/.ssh/id_rsa` and have its bytes rendered to the terminal every keystroke), the read is hard-capped at 64 bytes, and the mode is whitelisted before being included in the badge string. Anything outside the allowlist renders nothing.
- **Update-check VERSION** — the response is run through `tr -cd '0-9.'` before being cached or compared, defeating an MITM-tampered VERSION file that tries to leak escape sequences into a future render.
- **Self-update** — downloads land in a tempdir, are syntax-checked with `bash -n`, must contain a `KANAGAWA_STATUSLINE_VERSION=` line, and only then atomically replace the installed copy.
