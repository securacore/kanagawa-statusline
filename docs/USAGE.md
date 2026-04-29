# Usage

## Variants

| variant  | mood                       | best for                                         |
|----------|----------------------------|--------------------------------------------------|
| `wave`         | night, cool, violet+blue            | dark terminals (most users — default)        |
| `dragon`       | night, warm, earthy                 | dark terminals, warmer/desaturated tones     |
| `lotus`        | day, light                          | light terminal backgrounds                   |
| `wave-lean`    | muted sumiInk mono + wave fgs       | dark terminals, stealth aesthetic            |
| `dragon-lean`  | muted dragonBlack mono + dragon fgs | dark terminals, warm stealth aesthetic       |
| `lotus-lean`   | muted lotusWhite mono + lotus fgs   | light terminals, low-saturation aesthetic    |
| `wave-xlean`   | text-only, wave fg accents          | minimalists; segments split by ` │ ` divider |
| `dragon-xlean` | text-only, dragon fg accents        | minimalists; segments split by ` │ ` divider |
| `lotus-xlean`  | text-only, lotus fg accents         | minimalists on light terminals               |
| `off`          | disabled                            | hide the statusline entirely (empty output)  |

Each `*-lean` palette uses a single-family monochromatic ramp for backgrounds (sumiInk for wave/dragon, lotusWhite for lotus) with low-contrast accent foregrounds; powerline structure (bg fills + arrow separators) is preserved.

Each `*-xlean` palette runs in text mode: no bg fills, no powerline arrows. Segments render as fg-only colored text glued by ` │ ` (vertical bar in muted gray for dark bases, muted tan for `lotus-xlean`).

## CLI

```bash
kanagawa-statusline wave            # set variant (cool night, default)
kanagawa-statusline dragon          # set variant (warm earthy night)
kanagawa-statusline lotus           # set variant (light theme)
kanagawa-statusline wave-lean       # set variant (wave, muted dark mono)
kanagawa-statusline dragon-lean     # set variant (dragon, muted dark mono)
kanagawa-statusline lotus-lean      # set variant (lotus, muted light mono)
kanagawa-statusline wave-xlean      # set variant (wave, text-only + divider)
kanagawa-statusline dragon-xlean    # set variant (dragon, text-only + divider)
kanagawa-statusline lotus-xlean     # set variant (lotus, text-only + divider)
kanagawa-statusline off             # disable styling
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

**Resolution order:** `KANAGAWA_VARIANT` env → config file `VARIANT=` → `wave` default.

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
| `KANAGAWA_VERSION_URL=<url>`     | Override the URL the statusline polls                         | `https://raw.githubusercontent.com/securacore/kanagawa-statusline/main/VERSION` |
| `KANAGAWA_STATUSLINE_REPO_RAW=<url>` | Override the base URL `update`/`check` fetch from         | `https://raw.githubusercontent.com/securacore/kanagawa-statusline/main`   |

## Preview all variants

```bash
for v in wave dragon lotus wave-lean dragon-lean lotus-lean wave-xlean dragon-xlean lotus-xlean; do
  printf '\n--- %s ---\n' "$v"
  printf '{"model":{"display_name":"Opus 4.7"},"workspace":{"project_dir":"."},"effort":{"level":"xhigh"},"version":"2.1.121","context_window":{"used_percentage":42}}' \
    | KANAGAWA_VARIANT=$v STATUSLINE_DEMO=1 bash ~/.claude/statusline-command.sh
done
echo
```

`STATUSLINE_DEMO=1` forces all 7 lang segments to render with placeholder versions, useful for previewing palettes.

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

> [!IMPORTANT]
> `~/.claude/settings.json` is **not** auto-edited. Remove the `statusLine` block manually if you want the slot empty.
