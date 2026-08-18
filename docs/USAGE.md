# Usage

## Variants

| variant  | mood                       | best for                                         |
|----------|----------------------------|--------------------------------------------------|
| `wave`         | night, cool, violet+blue            | dark terminals                                |
| `dragon`       | night, warm, earthy                 | dark terminals, warmer/desaturated tones     |
| `lotus`        | day, light                          | light terminal backgrounds                   |
| `wave-lean`    | muted sumiInk mono + wave fgs       | dark terminals, stealth aesthetic            |
| `dragon-lean`  | muted dragonBlack mono + dragon fgs | dark terminals, warm stealth aesthetic       |
| `lotus-lean`   | muted lotusWhite mono + lotus fgs   | light terminals, low-saturation aesthetic    |
| `wave-xlean`   | text-only, wave fg accents          | minimalists; segments split by ` │ ` divider (default) |
| `dragon-xlean` | text-only, dragon fg accents        | minimalists; segments split by ` │ ` divider |
| `lotus-xlean`  | text-only, lotus fg accents         | minimalists on light terminals               |
| `off`          | disabled                            | hide the statusline entirely (empty output)  |

Each `*-lean` palette uses a single-family monochromatic ramp for backgrounds (sumiInk for wave/dragon, lotusWhite for lotus) with low-contrast accent foregrounds; powerline structure (bg fills + arrow separators) is preserved.

Each `*-xlean` palette runs in text mode: no bg fills, no powerline arrows. Segments render as fg-only colored text glued by ` │ ` (vertical bar in muted gray for dark bases, muted tan for `lotus-xlean`).

## CLI

```bash
kanagawa-statusline wave            # set variant (cool night)
kanagawa-statusline dragon          # set variant (warm earthy night)
kanagawa-statusline lotus           # set variant (light theme)
kanagawa-statusline wave-lean       # set variant (wave, muted dark mono)
kanagawa-statusline dragon-lean     # set variant (dragon, muted dark mono)
kanagawa-statusline lotus-lean      # set variant (lotus, muted light mono)
kanagawa-statusline wave-xlean      # set variant (wave, text-only + divider, default)
kanagawa-statusline dragon-xlean    # set variant (dragon, text-only + divider)
kanagawa-statusline lotus-xlean     # set variant (lotus, text-only + divider)
kanagawa-statusline off             # disable styling
kanagawa-statusline logos on|off    # show or hide the logos anchor segment
kanagawa-statusline status          # show current setting + installed version
kanagawa-statusline version         # print installed version
kanagawa-statusline check           # synchronously probe for a new release
kanagawa-statusline update          # self-update statusline + this CLI
kanagawa-statusline update -f       # reinstall even when already at the latest
kanagawa-statusline uninstall       # remove all installed files (prompts)
kanagawa-statusline uninstall -y    # remove without prompt
kanagawa-statusline -h              # help
```

> [!TIP]
> The change applies on the next statusline render. Press Enter at the prompt to refresh immediately.

### Drive it from Claude Code

Because the CLI is just a shell command, you can ask Claude Code to switch variants for you mid-session:

> "switch the statusline to dragon"

The agent runs `kanagawa-statusline dragon`, the config updates, and the next render picks up the new variant.

## Config file

The CLI writes `$XDG_CONFIG_HOME/kanagawa-statusline/config` (defaults to `~/.config/kanagawa-statusline/config`):

```
VARIANT=wave
```

The statusline reads this on every render.

## Env override

`KANAGAWA_VARIANT` env var takes precedence over the config file:

```bash
export KANAGAWA_VARIANT=dragon  # one-shell override
```

**Resolution order:** `KANAGAWA_VARIANT` env → config file `VARIANT=` → `wave-xlean` default.

## Updates

The statusline runs a non-blocking, daily-cached probe of `/VERSION` on the repo (~10 bytes of HTTP). When the remote version is strictly newer than the installed one, an `update vX.Y.Z` segment renders at the right edge in the variant's red/warm tone.

| Action                              | Command                          |
|-------------------------------------|----------------------------------|
| Apply the update                    | `kanagawa-statusline update`     |
| Force a reinstall at the same version | `kanagawa-statusline update -f`  |
| Synchronous "is there an update?"   | `kanagawa-statusline check`      |
| Print the installed version         | `kanagawa-statusline version`    |

`update` re-fetches `statusline.sh` and the CLI from `raw.githubusercontent.com`, runs `bash -n` and asserts the version constant before atomically swapping the installed copy in. The local cache is refreshed so the indicator clears on the next render.

### Tunables

| env var                          | effect                                                        | default                                                                  |
|----------------------------------|---------------------------------------------------------------|--------------------------------------------------------------------------|
| `KANAGAWA_NO_UPDATE_CHECK=1`     | Skip the background probe entirely                            | unset                                                                    |
| `KANAGAWA_UPDATE_TTL=<seconds>`  | Probe cadence — cache lifetime before re-fetch                | `86400` (24h)                                                            |
| `KANAGAWA_LOGOS=<0\|1>` | Hide or show the logos anchor; overrides the `LOGOS=` config key | `1`
| `KANAGAWA_LOGOS_TTL=<seconds>` | Logos anchor cache lifetime before a background refresh | `20`
| `KANAGAWA_VERSION_URL=<url>`     | Override the URL the statusline polls                         | `https://raw.githubusercontent.com/securacore/kanagawa-statusline/main/VERSION` |
| `KANAGAWA_STATUSLINE_REPO_RAW=<url>` | Override the base URL `update`/`check` fetch from         | `https://raw.githubusercontent.com/securacore/kanagawa-statusline/main`   |


## Logos anchor

In a project adopted into [logos](https://github.com/securacore/logos), a segment after the branch shows where work stands in the project's own plan:

| Shown | Means |
|-------|-------|
| `◈ cli-coherence (7/9) › statusline-read` | that ticket is being built, under that feature, which has 7 of its 9 tickets validated |
| `◈ cli-coherence (7/9) › none` | the feature is active, no ticket in flight |
| `◈ cli-coherence (7/9) › 2 building` | two tickets building, both under that feature |
| `◈ 3 building` | three tickets building across different features |
| `◈ 3 active` | three features active, none with a ticket in flight |
| `◈` | logos is set up here, nothing active |
| `◌ cli-coherence (7/9) › statusline-read` | same, but the adoption mode is not known |
| *(nothing)* | the project does not use logos, or the segment is switched off |

The count is validated tickets against the feature's total, and appears only where a single feature is named. It counts `validated` and nothing else: a ticket that has landed is code-complete awaiting its scenarios, not done.

The glyph carries which adoption mode the project uses. `◈` means the state root is committed inside the repository; `◇` means it lives outside it, and the whole segment shifts to a cooler tone to match. Warm for state that lives here, cool for state that lives elsewhere.

`◌` means the mode could not be determined — usually a logos older than the field, or a cache written before it existed. It is shown rather than guessed, because defaulting to `◈` would claim your state is committed here when nothing said so. The rest of the segment renders normally: only the mode is unknown, and the work beside it is not.

A ticket never appears without its feature: ticket names describe the change they make, not the arc they serve, so a name alone tells you nothing. When several tickets or features are in play the segment shows a count rather than picking one, because nothing on disk records which is yours.

The read (`logos status`) runs on a background refresh cached for `KANAGAWA_LOGOS_TTL` seconds, never on the render path, and the segment is skipped entirely when logos is not installed or the project is not adopted.

On a narrow line it is the only part of the left cluster that gives way, shedding in this order: the count, then the ticket, then the feature, then the segment itself. The ticket goes before the feature because a ticket name is meaningless without the arc it belongs to, while a feature name still tells you where you are.

Switch it off with `kanagawa-statusline logos off`, or per-shell with `KANAGAWA_LOGOS=0`. Resolution order matches the variant: `KANAGAWA_LOGOS` env, then the `LOGOS=` config key, then on. Switched off, the whole block is skipped: no cache read, no background refresh, no segment.

## Preview all variants

```bash
for v in wave dragon lotus wave-lean dragon-lean lotus-lean wave-xlean dragon-xlean lotus-xlean; do
  printf '\n--- %s ---\n' "$v"
  printf '{"model":{"display_name":"Opus 4.7"},"workspace":{"project_dir":"."},"effort":{"level":"xhigh"},"version":"2.1.121","context_window":{"used_percentage":42,"context_window_size":1000000}}' \
    | KANAGAWA_VARIANT=$v STATUSLINE_DEMO=1 bash ~/.claude/statusline-command.sh
done
echo
```

`STATUSLINE_DEMO=1` forces all 7 lang segments to render with placeholder versions, useful for previewing palettes.

## Codex

The same statusline for [OpenAI Codex](https://developers.openai.com/codex), via `kanagawa-codex`.

Codex has no command-backed status line, so there are two modes and they compose:

```bash
kanagawa-codex native         # order Codex's own footer — no deps, Codex's colors
kanagawa-codex init --tmux    # the full kanagawa line beside the TUI — needs tmux
kanagawa-codex doctor         # verify the wiring end to end
```

`native` needs nothing installed and renders inside Codex. The themed line needs a multiplexer, because a full-screen TUI leaves nowhere else to draw.

```bash
kanagawa-codex line [--pane ID]   cached line, re-rendered when stale (tmux calls this)
kanagawa-codex render [--width N] force one render to stdout
kanagawa-codex watch [-n SECS]    redraw loop for a dedicated pane
kanagawa-codex uninstall [-y]     remove hooks + state
```

Both harnesses read the same config file, so `kanagawa-statusline dragon` re-themes Claude Code and Codex together.

The ctx % segment needs a context window size that Codex does not report. Pin it, or the segment stays hidden:

```
CODEX_CTX_WINDOW=272000
```

Architecture, the full segment mapping and the context-percentage caveat: [CODEX.md](CODEX.md).

## Uninstall

```bash
kanagawa-statusline uninstall
```

Removes:

- `~/.claude/statusline-command.sh`
- `~/.local/bin/kanagawa-statusline`
- `~/.config/kanagawa-statusline/`
- `~/.cache/kanagawa-statusline/` (update-check cache)
- statusline runtime caches in `$TMPDIR`
- `~/.local/bin/kanagawa-codex`, its Codex hook entries and its state (if installed)
- the `statusLine` block in `~/.claude/settings.json`, **only** when it references this script

> [!IMPORTANT]
> A `statusLine` block pointing at something else is left untouched, as is any `~/.codex/hooks.json` entry that is not ours. Your tmux config is never edited — remove the `status-right` line yourself.
