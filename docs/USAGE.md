# Usage

## Variants

| variant  | mood                       | best for                                         |
|----------|----------------------------|--------------------------------------------------|
| `wave`   | night, cool, violet+blue   | dark terminals (most users — default)            |
| `dragon` | night, warm, earthy        | dark terminals, warmer/desaturated tones         |
| `lotus`  | day, light                 | light terminal backgrounds                       |
| `off`    | disabled                   | hide the statusline entirely (empty output)      |

## CLI

```bash
kanagawa-statusline wave            # set variant (cool night, default)
kanagawa-statusline dragon          # set variant (warm earthy night)
kanagawa-statusline lotus           # set variant (light theme)
kanagawa-statusline off             # disable styling
kanagawa-statusline status          # show current setting
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

## Preview all variants

```bash
for v in wave dragon lotus; do
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
- statusline runtime caches in `$TMPDIR`

> [!IMPORTANT]
> `~/.claude/settings.json` is **not** auto-edited. Remove the `statusLine` block manually if you want the slot empty.
