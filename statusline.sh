#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────
#  Claude Code status line — lualine-inspired, kanagawa wave themed.
# ─────────────────────────────────────────────────────────────────────────
#  Single-line, two-cluster (left + right) statusline rendered with
#  Powerline glyphs and a violet → blue → sumi-ink → orange palette.
#
#  LEFT CLUSTER  (priority anchors)
#    [ ctx % ] → [ model (effort) ] → [ cwd basename ] → [  branch ] → [ ◈ logos ]
#       violet         blue            dark-blue        sumi-ink5      boatYellow
#
#  RIGHT CLUSTER (lang gradient + warm exit)
#    [ langs… (dark → light gray gradient) ] → [ cli version ] → [ caveman ]
#                                              muted orange     bright orange
#
#  REQUIREMENTS
#    - bash 4+   (uses arrays, [[ ]] regex, printf %q)
#    - jq        (JSON parsing)
#    - python3   (visible_len — width of nerd-font glyphs)
#    - Nerd Font + 256-color terminal (truecolor optional)
#
#  USAGE — wire up in ~/.claude/settings.json:
#      {
#        "statusLine": {
#          "type": "command",
#          "command": "bash ~/.claude/statusline-command.sh"
#        }
#      }
#
#  CONFIGURATION — tunable constants below in this file:
#    CTX_BG / A_BG / B_BG / C_BG     left cluster colors
#    D_BG / D_FG / DU_FG / DX_FG     logos anchor (project / user / unknown;
#                                    DX_FG tracks D_FG, raise it to escalate)
#    GRAD_MIN / GRAD_MAX             lang gradient endpoints
#    Y_BG / Z_BG / X_BG              style / cli / caveman colors
#    drop_order                      lang priority for graceful degradation
#    cols=$(( cols - N ))            chrome buffer (right-edge alignment)
#    KANAGAWA_COLS=<n>               force render width (wins over stty/tput;
#                                    for surfaces that are not this terminal)
#    STATUSLINE_DEMO=1               env flag — preview all 7 langs
#    KANAGAWA_VARIANT=<base>-lean    muted monochromatic variant of base
#                                    (wave-lean / dragon-lean / lotus-lean)
#    KANAGAWA_LOGOS=0|1              hide or show the logos anchor
#    KANAGAWA_LOGOS_TTL=<seconds>    anchor refresh cadence (default 20)
#
#  FEATURES
#    • Per-project runtime version detection (node/bun/py/go/rust/zig/odin),
#      cached for 5 min in $TMPDIR keyed by project path hash.
#    • Dynamic gray gradient: N visible langs map to N evenly-spaced stops
#      between GRAD_MIN..GRAD_MAX so the spread always looks balanced.
#    • Graceful degradation: if right cluster overruns the line, langs are
#      dropped one at a time (lowest priority first per drop_order) until
#      content fits. Caveman + cli always preserved.
#    • Caveman badge read directly from $CLAUDE_CONFIG_DIR/.caveman-active
#      (defaults to ~/.claude/.caveman-active). Always shows current level
#      (e.g. "caveman full"). Segment is skipped if flag file is absent or
#      mode is "off". Symlinks rejected; mode whitelisted to block escape
#      injection via the flag contents.
#    • Update check: non-blocking, daily-cached probe of /VERSION on the
#      repo. Renders an "update vX.Y.Z" segment when a newer release is
#      available; run `kanagawa-statusline update` to self-update. Disable
#      with KANAGAWA_NO_UPDATE_CHECK=1; tune cadence via KANAGAWA_UPDATE_TTL
#      (seconds, default 86400).
#    • Logos anchor: where work stands in the project's own plan, as
#      `◈ feature (done/total) › ticket` while a ticket is building,
#      `› none` between tickets, and a count instead of a pick when
#      several are in flight. The glyph carries the adoption mode: ◈ for
#      a state root inside the repo, ◇ for one outside it (segment tinted
#      to the palette's aqua), ◌ when the read did not say, rather than
#      defaulting and claiming a mode on no evidence. Read via
#      `logos status` on a background refresh cached per project
#      (KANAGAWA_LOGOS_TTL, default 20s); never on the render path.
#      Silent in projects without logos. Toggle with KANAGAWA_LOGOS=0|1
#      or the LOGOS= config key. The only left-cluster segment that
#      yields to width, shedding count, then ticket, then feature, then
#      itself.
#    • Right-edge alignment via stty terminal width (independent of
#      $COLUMNS being passed by Claude Code).
#
#  DEPENDENCIES (optional)
#    logos — provides `logos status` for the anchor segment; safe to omit,
#    the segment is skipped when the binary or the project's state is absent.
#    Caveman plugin — https://github.com/JuliusBrussee/caveman  (writes the
#    flag file consumed for the badge; safe to omit, the segment is skipped).
# ─────────────────────────────────────────────────────────────────────────

# Kept in sync with /VERSION at the repo root. Update both together — the
# remote check fetches /VERSION (cheap, ~10 bytes) and compares to this
# constant. `kanagawa-statusline update` rewrites the whole script so this
# value moves with each release.
KANAGAWA_STATUSLINE_VERSION="0.0.21"

input=$(cat)

model=$(printf '%s' "$input" | jq -r '.model.display_name // ""')
# Strip a trailing "(… context)" parenthetical (e.g. "Opus 4.7 (1M context)").
# The context window size is already rendered in the left anchor, so the
# suffix would just duplicate it inside the model segment.
model="${model% *\(*context\)}"
effort=$(printf '%s' "$input" | jq -r '.effort.level // ""')
# Fallback: Claude Code only emits .effort.level for models that support the
# reasoning-effort parameter (notably absent on long-context variants like
# claude-opus-4-7[1m]). When stdin omits it, surface the user's configured
# preference from settings.json instead. Note this reflects the saved setting,
# not the live session — `/effort` changes mid-session won't show until the
# config is rewritten or stdin starts emitting the field.
if [ -z "$effort" ]; then
  cc_settings="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"
  [ -f "$cc_settings" ] && effort=$(jq -r '.effortLevel // ""' "$cc_settings" 2>/dev/null)
fi
[ -n "$effort" ] && model="$model 󱐋 $effort"
# ── parse JSON from Claude Code (piped via stdin) ──────────────────────
# Field schema: https://docs.claude.com/en/docs/claude-code/statusline
proj=$(printf '%s' "$input" | jq -r '.workspace.project_dir // .cwd // ""')
ver=$(printf '%s'  "$input" | jq -r '.version // ""')
style=$(printf '%s' "$input" | jq -r '(.output_style.name // .output_style // "") | if type=="string" then . else "" end' | tr -d '\n\r')
# Empty, not 0, when the host omits it. Claude Code always sends this field,
# so an absent value means the caller genuinely has no context figure (the
# Codex adapter, when transcript token accounting comes up empty). Rendering
# "0%" there would assert a fresh context window rather than an unknown one;
# the segment skips instead, matching how caveman and logos degrade.
ctx_pct=$(printf '%s' "$input" | jq -r '.context_window.used_percentage // ""')
ctx_size_raw=$(printf '%s' "$input" | jq -r '.context_window.context_window_size // 0')

# Render token count compactly: 1000000→1M, 1500000→1.5M, 200000→200K.
# Integer math only — bash has no floats; we slice off the residue manually.
fmt_ctx_size() {
  local n=$1
  (( n <= 0 )) && return
  if (( n >= 1000000 )); then
    if (( n % 1000000 == 0 )); then
      printf '%dM' $(( n / 1000000 ))
    else
      printf '%d.%dM' $(( n / 1000000 )) $(( (n % 1000000) / 100000 ))
    fi
  elif (( n >= 1000 )); then
    if (( n % 1000 == 0 )); then
      printf '%dK' $(( n / 1000 ))
    else
      printf '%d.%dK' $(( n / 1000 )) $(( (n % 1000) / 100 ))
    fi
  else
    printf '%d' "$n"
  fi
}
ctx_size=$(fmt_ctx_size "$ctx_size_raw")

basename=""
[ -n "$proj" ] && basename=$(basename "$proj")

branch=""
git_staged=0 git_modified=0 git_untracked=0
git_ahead=0 git_behind=0
if [ -n "$proj" ] && git -C "$proj" rev-parse --git-dir >/dev/null 2>&1; then
  branch=$(git -C "$proj" symbolic-ref --short HEAD 2>/dev/null \
        || git -C "$proj" rev-parse --short HEAD 2>/dev/null)
  # Parse porcelain v1 XY columns:
  #   X = index (staged), Y = worktree (unstaged), "??" = untracked.
  # Single git call; counts files, not hunks.
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    if [ "${line:0:2}" = "??" ]; then
      (( git_untracked++ ))
    else
      [ "${line:0:1}" != " " ] && (( git_staged++ ))
      [ "${line:1:1}" != " " ] && (( git_modified++ ))
    fi
  done < <(git -C "$proj" status --porcelain 2>/dev/null)
  # Ahead/behind vs upstream. NOTE: reflects state of last `git fetch` —
  # remote commits pushed since then will not show as "behind" until the
  # user fetches. Auto-fetching from a render hook would be invasive, so
  # we surface only what's already in local refs.
  ab=$(git -C "$proj" rev-list --left-right --count '@{upstream}...HEAD' 2>/dev/null)
  if [[ "$ab" =~ ^([0-9]+)[[:space:]]+([0-9]+)$ ]]; then
    git_behind=${BASH_REMATCH[1]}
    git_ahead=${BASH_REMATCH[2]}
  fi
fi

# ── project runtime detection ──────────────────────────────────────────
# Detect which languages the project uses (marker files in root + common
# subdirs), then look up the SYSTEM-INSTALLED runtime version for each.
# Cached per-project to avoid spawning runtimes on every render.
uses_node=0 uses_bun=0 uses_py=0 uses_go=0 uses_rust=0 uses_zig=0 uses_odin=0
scan_markers() {
  local d=$1
  # bun lockfile takes precedence over node for the JS runtime label
  if [ -f "$d/bun.lockb" ] || [ -f "$d/bun.lock" ]; then
    uses_bun=1
  elif [ -f "$d/package.json" ]; then
    uses_node=1
  fi
  [ -f "$d/pyproject.toml" ] || [ -f "$d/requirements.txt" ] || [ -f "$d/setup.py" ] && uses_py=1
  [ -f "$d/go.mod" ]    && uses_go=1
  [ -f "$d/Cargo.toml" ] && uses_rust=1
  [ -f "$d/build.zig" ] && uses_zig=1
  compgen -G "$d/*.zig"  >/dev/null 2>&1 && uses_zig=1
  compgen -G "$d/*.odin" >/dev/null 2>&1 && uses_odin=1
}

if [ -n "$proj" ]; then
  scan_markers "$proj"
  for sub in app services client server backend frontend api web cli pkg src; do
    [ -d "$proj/$sub" ] && scan_markers "$proj/$sub"
  done
fi

# Modification time as a unix epoch, portable across the two stat dialects.
# Order matters and is not arbitrary: GNU coreutils `stat -f` means "file
# system", not "format", so on a machine whose PATH finds coreutils before
# BSD stat the historical `stat -f %m ... || stat -c %Y ...` chain SUCCEEDS
# with filesystem prose and the fallback never fires, poisoning every age
# check that consumes it. Try the GNU spelling first, and validate that what
# came back is actually a number rather than trusting the exit status.
file_mtime() { # <path> -> epoch seconds, 0 when unknown
  local m
  m=$(stat -c %Y "$1" 2>/dev/null)
  [[ "$m" =~ ^[0-9]+$ ]] || m=$(stat -f %m "$1" 2>/dev/null)
  [[ "$m" =~ ^[0-9]+$ ]] || m=0
  printf '%s' "$m"
}

# Cache runtime version output (5 min TTL) keyed by project path.
proj_hash=$(printf '%s' "$proj" | md5 2>/dev/null || printf '%s' "$proj" | md5sum 2>/dev/null | awk '{print $1}')
proj_hash=${proj_hash:0:12}
cache_file="${TMPDIR:-/tmp}/cc-statusline-rt-${proj_hash:-default}"
cache_age=999999
if [ -f "$cache_file" ]; then
  mtime=$(file_mtime "$cache_file")
  cache_age=$(( $(date +%s) - mtime ))
fi

node_v="" bun_v="" py_v="" go_v="" rust_v="" zig_v="" odin_v=""

if [ "${STATUSLINE_DEMO:-0}" = 1 ]; then
  node_v="22.0.0"; bun_v="1.3.3"; py_v="3.14.4"
  go_v="1.23.0";   rust_v="1.75.0"
  zig_v="0.13.0";  odin_v="dev-2024"
elif [ "$cache_age" -lt 300 ]; then
  # shellcheck source=/dev/null
  . "$cache_file"
else
  [ "$uses_node" = 1 ] && command -v node    >/dev/null 2>&1 && node_v=$(node --version 2>/dev/null | tr -d 'v\n')
  [ "$uses_bun"  = 1 ] && command -v bun     >/dev/null 2>&1 && bun_v=$(bun --version 2>/dev/null | tr -d '\n')
  [ "$uses_py"   = 1 ] && command -v python3 >/dev/null 2>&1 && py_v=$(python3 -V 2>&1 | awk '{print $2}')
  [ "$uses_go"   = 1 ] && command -v go      >/dev/null 2>&1 && go_v=$(go version 2>/dev/null | awk '{print $3}' | sed 's/^go//')
  [ "$uses_rust" = 1 ] && command -v rustc   >/dev/null 2>&1 && rust_v=$(rustc --version 2>/dev/null | awk '{print $2}')
  [ "$uses_zig"  = 1 ] && command -v zig     >/dev/null 2>&1 && zig_v=$(zig version 2>/dev/null)
  [ "$uses_odin" = 1 ] && command -v odin    >/dev/null 2>&1 && odin_v=$(odin version 2>/dev/null | awk '{print $3}')
  {
    printf 'node_v=%q\n' "$node_v"
    printf 'bun_v=%q\n'  "$bun_v"
    printf 'py_v=%q\n'   "$py_v"
    printf 'go_v=%q\n'   "$go_v"
    printf 'rust_v=%q\n' "$rust_v"
    printf 'zig_v=%q\n'  "$zig_v"
    printf 'odin_v=%q\n' "$odin_v"
  } > "$cache_file" 2>/dev/null
fi


# ── update check ───────────────────────────────────────────────────────
# Probe the repo for a newer release. Cheap and non-blocking:
#   - cached result lives at $XDG_CACHE_HOME/kanagawa-statusline/latest-version
#   - mtime of cache = age (default TTL 24h, override via KANAGAWA_UPDATE_TTL)
#   - when stale, spawn a detached background curl that fetches /VERSION
#     (~10 bytes) and rewrites the cache file. The current render uses the
#     prior cache; the fresher value lands on the next render.
#   - lock dir prevents concurrent fetches stacking up.
#   - opt out entirely with KANAGAWA_NO_UPDATE_CHECK=1.
# When the cached remote version is strictly newer than the embedded one,
# `update_available` is set to the remote string and the right cluster
# gains an "update vX.Y.Z" segment.
update_available=""
if [ "${KANAGAWA_NO_UPDATE_CHECK:-0}" != "1" ]; then
  uc_dir="${XDG_CACHE_HOME:-$HOME/.cache}/kanagawa-statusline"
  uc_file="$uc_dir/latest-version"
  uc_lock="$uc_dir/check.lock"
  uc_ttl="${KANAGAWA_UPDATE_TTL:-86400}"
  uc_age=999999999
  if [ -f "$uc_file" ]; then
    uc_mtime=$(file_mtime "$uc_file")
    uc_age=$(( $(date +%s) - uc_mtime ))
  fi
  if (( uc_age >= uc_ttl )) && command -v curl >/dev/null 2>&1; then
    mkdir -p "$uc_dir" 2>/dev/null
    # mkdir is atomic — first writer wins, others bail. Stale lock is
    # cleared by the (mtime > 60s) guard so a crashed fetch doesn't wedge
    # checks forever.
    if [ -d "$uc_lock" ]; then
      lock_mtime=$(file_mtime "$uc_lock")
      (( $(date +%s) - lock_mtime > 60 )) && rmdir "$uc_lock" 2>/dev/null
    fi
    if mkdir "$uc_lock" 2>/dev/null; then
      uc_url="${KANAGAWA_VERSION_URL:-https://raw.githubusercontent.com/securacore/kanagawa-statusline/main/VERSION}"
      (
        trap 'rmdir "$uc_lock" 2>/dev/null' EXIT
        # tr -cd to whitelist semver chars defends against an MITM-tampered
        # VERSION file leaking escape sequences into the next render.
        remote=$(curl -fsSL --max-time 5 "$uc_url" 2>/dev/null \
               | head -c 32 | tr -cd '0-9.')
        if [ -n "$remote" ]; then
          printf '%s' "$remote" > "$uc_file.tmp" \
            && mv "$uc_file.tmp" "$uc_file"
        else
          # touch the file so we don't retry every render on persistent
          # failure (no network, GitHub down, etc.) — wait out the TTL.
          touch "$uc_file" 2>/dev/null
        fi
      ) >/dev/null 2>&1 </dev/null &
      disown 2>/dev/null || true
    fi
  fi
  if [ -f "$uc_file" ]; then
    remote_ver=$(head -c 32 "$uc_file" 2>/dev/null | tr -cd '0-9.')
    if [ -n "$remote_ver" ] && [ "$remote_ver" != "$KANAGAWA_STATUSLINE_VERSION" ]; then
      newest=$(printf '%s\n%s\n' "$remote_ver" "$KANAGAWA_STATUSLINE_VERSION" \
             | sort -V | tail -1)
      [ "$newest" = "$remote_ver" ] && update_available="$remote_ver"
    fi
  fi
fi

# Caveman badge — read flag file directly so the badge always reflects the
# CURRENT session state (level included), independent of any upstream plugin
# script that may omit the suffix for default levels.
#
# Source of truth: $CLAUDE_CONFIG_DIR/.caveman-active (single line, mode name).
# Security: refuse symlinks, cap at 64 bytes, whitelist mode against a fixed
# allowlist — prevents an attacker who can write the flag file from injecting
# terminal escapes or OSC hyperlinks into every render.
CAVEMAN_FLAG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.caveman-active"
badge=""
if [ -f "$CAVEMAN_FLAG" ] && [ ! -L "$CAVEMAN_FLAG" ]; then
  cm_mode=$(head -c 64 "$CAVEMAN_FLAG" 2>/dev/null \
          | tr -d '\n\r' \
          | tr '[:upper:]' '[:lower:]' \
          | tr -cd 'a-z0-9-')
  case "$cm_mode" in
    lite|full|ultra|wenyan-lite|wenyan|wenyan-full|wenyan-ultra|commit|review|compress)
      badge="caveman $cm_mode"
      ;;
    off|"") ;;
    *) ;;  # unknown mode → render nothing rather than echo attacker bytes
  esac
fi

# ── palette (tokyonight-ish) ────────────────────────────────────────────
ESC=$'\e'
RESET="${ESC}[0m"
# ── Kanagawa palette (rebelot/kanagawa) ──────────────────────────────────
# Variants supported via KANAGAWA_VARIANT env var:
#   wave   — default night/cool   (violet → crystal blue → sumi-ink → orange)
#   dragon — warm earthy night    (dragonViolet → dragonBlue2 → dragonBlack
#                                  → dragonOrange)
#   lotus  — light theme          (lotusViolet → lotusBlue → lotusGray
#                                  → lotusOrange)
# Each base also has two reduced forms:
#   `*-lean`   muted monochromatic bgs (single-family ramp), full powerline
#   `*-xlean`  pure text + ` │ ` divider, no bg fills, no powerline arrows
# (so wave-lean / dragon-lean / lotus-lean / wave-xlean / dragon-xlean /
#  lotus-xlean.) The xlean palettes set fg accents only — bg values are
# unused at render time because seg() emits foreground only.
# Hex values mapped to nearest ANSI 256.

# Variant resolution order:
#   1. KANAGAWA_VARIANT env var
#   2. VARIANT key in $XDG_CONFIG_HOME/kanagawa-statusline/config
#   3. "wave-xlean" (default)
KANAGAWA_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/kanagawa-statusline/config"
# Sourced whether or not KANAGAWA_VARIANT is set. It used to be read only
# when the variant was unset, which silently shadowed every other config
# key the moment someone exported a variant. The file defines VARIANT and
# LOGOS, never the KANAGAWA_* names, so an explicit env var still wins in
# the resolutions below.
if [ -f "$KANAGAWA_CONFIG" ]; then
  # shellcheck disable=SC1090
  . "$KANAGAWA_CONFIG"
fi
KANAGAWA_VARIANT="${KANAGAWA_VARIANT:-${VARIANT:-}}"
KANAGAWA_VARIANT="${KANAGAWA_VARIANT:-wave-xlean}"

# Logos anchor toggle, same resolution order as the variant:
#   1. KANAGAWA_LOGOS env var (0/off/false/no disables, anything else on)
#   2. LOGOS key in the config file
#   3. on
# One tri-state name rather than a KANAGAWA_NO_LOGOS boolean, because the
# NO_ idiom can only express off and two booleans could contradict.
kanagawa_logos="${KANAGAWA_LOGOS:-${LOGOS:-on}}"
case "$(printf '%s' "$kanagawa_logos" | tr '[:upper:]' '[:lower:]')" in
  0|off|false|no|disabled) kanagawa_logos=0 ;;
  *)                       kanagawa_logos=1 ;;
esac

# "off" — print nothing and exit. Disables theming entirely.
if [ "$KANAGAWA_VARIANT" = "off" ]; then
  exit 0
fi

# Style derives from the variant suffix:
#   *-xlean  → text mode (no bg fills, ` │ ` divider, no powerline arrows)
#   else     → powerline mode (bg fills + arrow separators)
KANAGAWA_STYLE=powerline
case "$KANAGAWA_VARIANT" in
  *-xlean) KANAGAWA_STYLE=text ;;
esac

apply_palette() {
  # Foreground tokens shared across variants (overridden per variant).
  case "$KANAGAWA_VARIANT" in
    wave)
      # Wave — night, cool. Reference colors:
      #   oniViolet #957FB8, crystalBlue #7E9CD8, waveBlue2 #2D4F67,
      #   sumiInk0..6 #16161D..#54546D, surimiOrange #FFA066,
      #   boatYellow2 #C0A36E, fujiWhite #DCD7BA, oldWhite #C8C093.
      FUJI_WHITE=187; OLD_WHITE=144; SUMI_FG=235
      CTX_BG=60;   CTX_FG=$FUJI_WHITE   # deep violet anchor
      A_BG=110;    A_FG=$SUMI_FG        # crystalBlue — model
      B_BG=24;     B_FG=$FUJI_WHITE     # waveBlue2 — cwd
      C_BG=237;    C_FG=$OLD_WHITE      # sumiInk5 — branch dimmed
      D_BG=235;     D_FG=179              # sumiInk3 + boatYellow2 — logos anchor
      DU_FG=109;                         # waveAqua2 #7AA89F — user mode
      DX_FG=179;                         # unknown mode: full weight, not dimmed
      GRAD_MIN=232; GRAD_MAX=250        # sumi-ink dark→light
      Y_BG=179;    Y_FG=$SUMI_FG        # boatYellow2 — style
      Z_BG=173;    Z_FG=$SUMI_FG        # muted dusty orange — cli
      X_BG=215;    X_FG=$SUMI_FG        # surimiOrange — caveman
      U_BG=167;    U_FG=$FUJI_WHITE     # samuraiRed — update available
      ;;
    dragon)
      # Dragon — warm earthy night. Reference colors:
      #   dragonViolet #8992A7, dragonBlue2 #8BA4B0, dragonAqua #8EA4A2,
      #   dragonBlack3..6 #181616..#625E5A, dragonOrange #B6927B,
      #   dragonOrange2 #B98D7B, dragonYellow #C4B28A, dragonGray #A6A69C,
      #   dragonWhite #C5C9C5, dragonAsh #737C73, dragonRed #C4746E.
      FUJI_WHITE=187; OLD_WHITE=144; SUMI_FG=234
      CTX_BG=96;   CTX_FG=$FUJI_WHITE   # dragonViolet (#8992A7) — anchor
      A_BG=109;    A_FG=$SUMI_FG        # dragonBlue2 (#8BA4B0) — model
      B_BG=66;     B_FG=$FUJI_WHITE     # dragonAqua-ish — cwd
      C_BG=235;    C_FG=$OLD_WHITE      # dragonBlack4 — branch dimmed
      D_BG=234;     D_FG=180              # dragonBlack3 + dragonOrange2 — logos anchor
      DU_FG=109;                         # dragonAqua #8EA4A2 — user mode
      DX_FG=180;                         # unknown mode: full weight, not dimmed
      GRAD_MIN=234; GRAD_MAX=247        # dragonBlack3 → dragonGray
      Y_BG=144;    Y_FG=$SUMI_FG        # dragonYellow — style
      Z_BG=180;    Z_FG=$SUMI_FG        # dragonOrange2 (#B98D7B) — cli
      X_BG=173;    X_FG=$SUMI_FG        # dragonOrange (#B6927B) — caveman
      U_BG=167;    U_FG=$FUJI_WHITE     # dragonRed (#C4746E) — update available
      ;;
    lotus)
      # Lotus — light/day. Reference colors:
      #   lotusViolet4 #624C83, lotusBlue4 #4D699B, lotusBlue3 #9FB5C9,
      #   lotusWhite0..5 #D5CEA3..#E4D794, lotusGray2 #716E61,
      #   lotusOrange #CC6D00, lotusOrange2 #E98A00, lotusYellow3 #DE9800,
      #   lotusRed #C84053.
      FUJI_WHITE=234; OLD_WHITE=236; SUMI_FG=234
      CTX_BG=60;   CTX_FG=255           # lotusViolet4 — anchor
      A_BG=24;     A_FG=255             # lotusBlue4 — model
      B_BG=152;    B_FG=$SUMI_FG        # lotusBlue3 (#9FB5C9) — cwd
      C_BG=187;    C_FG=$SUMI_FG        # lotusWhite-ish — branch
      D_BG=180;     D_FG=$SUMI_FG         # muted tan + dark sumi — logos anchor
      DU_FG=66;                          # lotusAqua #597B75 — user mode
      DX_FG=$SUMI_FG;                     # unknown mode: full weight, not dimmed
      GRAD_MIN=250; GRAD_MAX=255        # narrow light-gray band (stays in grayscale)
      Y_BG=178;    Y_FG=$SUMI_FG        # lotusYellow3 — style
      Z_BG=208;    Z_FG=$SUMI_FG        # lotusOrange2 — cli
      X_BG=166;    X_FG=255             # lotusOrange (#CC6D00) — caveman
      U_BG=124;    U_FG=255             # lotusRed (#C84053) — update available
      ;;
    wave-lean)
      # Wave Lean — sumiInk dark monochromatic bgs + wave accent fgs.
      # All bgs sit on the sumiInk ramp (#16161D..#363646); fgs use
      # crystalBlue/springGreen/fujiWhite at low contrast. Powerline
      # structure preserved.
      FUJI_WHITE=187; OLD_WHITE=144; SUMI_FG=235
      CTX_BG=238;  CTX_FG=110           # sumiInk6 + crystalBlue — context %
      A_BG=236;    A_FG=$FUJI_WHITE     # sumiInk4 + fujiWhite — model
      B_BG=234;    B_FG=107             # sumiInk2 + springGreen — cwd
      C_BG=232;    C_FG=$OLD_WHITE      # sumiInk0 + oldWhite — branch
      D_BG=233;     D_FG=179              # sumiInk1 + boatYellow2 — logos anchor
      DU_FG=109;                         # waveAqua2 — user mode
      DX_FG=179;                         # unknown mode: full weight, not dimmed
      GRAD_MIN=234; GRAD_MAX=240        # narrow dark-gray band
      Y_BG=236;    Y_FG=179             # sumiInk4 + boatYellow2 — style
      Z_BG=233;    Z_FG=110             # darker + crystalBlue — cli
      X_BG=237;    X_FG=215             # sumiInk5 + surimiOrange — caveman
      U_BG=234;    U_FG=167             # sumiInk2 + samuraiRed — update
      ;;
    dragon-lean)
      # Dragon Lean — dragonBlack ramp bgs + dragon accent fgs.
      # Bgs use dragonBlack3..6 (#181616..#625E5A); fgs are dragonBlue2,
      # dragonAqua, dragonGray, dragonRed at low contrast.
      FUJI_WHITE=187; OLD_WHITE=144; SUMI_FG=234
      CTX_BG=240;  CTX_FG=109           # dragonBlack6-ish + dragonBlue2
      A_BG=237;    A_FG=$FUJI_WHITE     # dragonBlack5 + fujiWhite
      B_BG=235;    B_FG=66              # dragonBlack4 + dragonAqua-ish
      C_BG=233;    C_FG=$OLD_WHITE      # dragonBlack3 + oldWhite
      D_BG=234;     D_FG=180              # dragonBlack3 + dragonOrange2 — logos anchor
      DU_FG=109;                         # dragonAqua — user mode
      DX_FG=180;                         # unknown mode: full weight, not dimmed
      GRAD_MIN=234; GRAD_MAX=240        # narrow dragon-dark band
      Y_BG=236;    Y_FG=144             # dragonBlack + dragonYellow
      Z_BG=233;    Z_FG=109             # darker + dragonBlue2 — cli
      X_BG=237;    X_FG=180             # dragonBlack5 + dragonOrange2 — caveman
      U_BG=234;    U_FG=167             # dragonBlack3 + dragonRed — update
      ;;
    lotus-lean)
      # Lotus Lean — light cream/tan monochromatic bgs + lotus accent fgs.
      # Inverted from wave/dragon-lean — bgs are light (lotusWhite tones),
      # fgs are dark/saturated lotus accents (lotusViolet, lotusBlue4).
      FUJI_WHITE=234; OLD_WHITE=236; SUMI_FG=234
      CTX_BG=230;  CTX_FG=60            # very light cream + lotusViolet4
      A_BG=187;    A_FG=24              # lotusWhite + lotusBlue4 — model
      B_BG=144;    B_FG=234             # muted tan + dark sumi — cwd
      C_BG=137;    C_FG=230             # darker tan + light cream — branch
      D_BG=180;     D_FG=234              # muted tan + dark sumi — logos anchor
      DU_FG=66;                          # lotusAqua — user mode
      DX_FG=234;                         # unknown mode: full weight, not dimmed
      GRAD_MIN=247; GRAD_MAX=253        # narrow light-gray band
      Y_BG=186;    Y_FG=234             # lotusWhite5 + dark — style
      Z_BG=144;    Z_FG=24              # muted tan + lotusBlue4 — cli
      X_BG=187;    X_FG=166             # lotusWhite + lotusOrange — caveman
      U_BG=186;    U_FG=124             # lotusWhite5 + lotusRed — update
      ;;
    wave-xlean)
      # Wave xLean — text mode. No bg fills; segments are colored fg
      # text separated by ` │ `. Fg accents follow the wave palette.
      FUJI_WHITE=187; OLD_WHITE=144; SUMI_FG=235
      CTX_BG=0;    CTX_FG=110           # crystalBlue — context %
      A_BG=0;      A_FG=$FUJI_WHITE     # fujiWhite — model
      B_BG=0;      B_FG=107             # springGreen — cwd
      C_BG=0;      C_FG=$OLD_WHITE      # oldWhite — branch
      D_BG=0;       D_FG=179              # boatYellow2 — logos anchor
      DU_FG=109;                         # waveAqua2 — user mode
      DX_FG=179;                         # unknown mode: full weight, not dimmed
      GRAD_MIN=144; GRAD_MAX=144        # uniform muted lang fg
      Y_BG=0;      Y_FG=179             # boatYellow2 — style
      Z_BG=0;      Z_FG=110             # crystalBlue — cli
      X_BG=0;      X_FG=215             # surimiOrange — caveman
      U_BG=0;      U_FG=167             # samuraiRed — update
      DIV_FG=240                        # dark gray ` │ ` separator
      ;;
    dragon-xlean)
      # Dragon xLean — text mode, dragon palette accents on terminal bg.
      FUJI_WHITE=187; OLD_WHITE=144; SUMI_FG=234
      CTX_BG=0;    CTX_FG=109           # dragonBlue2 — context %
      A_BG=0;      A_FG=$FUJI_WHITE     # fujiWhite — model
      B_BG=0;      B_FG=66              # dragonAqua-ish — cwd
      C_BG=0;      C_FG=$OLD_WHITE      # oldWhite — branch
      D_BG=0;       D_FG=180              # dragonOrange2 — logos anchor
      DU_FG=109;                         # dragonAqua — user mode
      DX_FG=180;                         # unknown mode: full weight, not dimmed
      GRAD_MIN=144; GRAD_MAX=144        # uniform muted lang fg
      Y_BG=0;      Y_FG=144             # dragonYellow — style
      Z_BG=0;      Z_FG=109             # dragonBlue2 — cli
      X_BG=0;      X_FG=180             # dragonOrange2 — caveman
      U_BG=0;      U_FG=167             # dragonRed — update
      DIV_FG=240                        # dark gray separator
      ;;
    lotus-xlean)
      # Lotus xLean — text mode for light terminals. Dark/saturated
      # accents (lotusViolet, lotusBlue4) on terminal default bg.
      FUJI_WHITE=234; OLD_WHITE=236; SUMI_FG=234
      CTX_BG=0;    CTX_FG=60            # lotusViolet4 — context %
      A_BG=0;      A_FG=24              # lotusBlue4 — model
      B_BG=0;      B_FG=22              # dark green — cwd
      C_BG=0;      C_FG=234             # dark sumi — branch
      D_BG=0;       D_FG=130              # dark tan — logos anchor
      DU_FG=66;                          # lotusAqua — user mode
      DX_FG=130;                         # unknown mode: full weight, not dimmed
      GRAD_MIN=137; GRAD_MAX=137        # uniform dark-tan lang fg
      Y_BG=0;      Y_FG=178             # lotusYellow3 — style
      Z_BG=0;      Z_FG=24              # lotusBlue4 — cli
      X_BG=0;      X_FG=166             # lotusOrange — caveman
      U_BG=0;      U_FG=124             # lotusRed — update
      DIV_FG=137                        # muted tan separator (visible on light bg)
      ;;
    *)
      printf 'statusline: unknown KANAGAWA_VARIANT=%s\n' "$KANAGAWA_VARIANT" >&2
      printf '  valid: wave | dragon | lotus\n' >&2
      printf '       | wave-lean | dragon-lean | lotus-lean\n' >&2
      printf '       | wave-xlean | dragon-xlean | lotus-xlean | off\n' >&2
      KANAGAWA_VARIANT=wave-xlean
      KANAGAWA_STYLE=text
      apply_palette
      return
      ;;
  esac
}
apply_palette

LSEP=$''   #
RSEP=$''   #

if [ "$KANAGAWA_STYLE" = "text" ]; then
  # Text mode (xlean): foreground only, ` │ ` divider in DIV_FG. The bg
  # arg to seg() and the prev/new_bg args to transitions are ignored.
  # seg <bg-ignored> <fg> <text>
  seg() { printf '%s[38;5;%sm%s%s' "$ESC" "$2" "$3" "$RESET"; }
  # Both transitions render the same divider — no protrusion/arrow
  # geometry exists in text mode.
  ltrans() { printf '%s[38;5;%sm │%s' "$ESC" "$DIV_FG" "$RESET"; }
  rtrans() { printf '%s[38;5;%sm │%s' "$ESC" "$DIV_FG" "$RESET"; }
else
  # Powerline mode: bg fills + arrow separators.
  # seg <bg> <fg> <text>
  seg() { printf '%s[48;5;%sm%s[38;5;%sm%s %s' "$ESC" "$1" "$ESC" "$2" "$3" "$RESET"; }
  # left transition: prev_bg -> new_bg using LSEP
  ltrans() { printf '%s[48;5;%sm%s[38;5;%sm%s%s' "$ESC" "$2" "$ESC" "$1" "$LSEP" "$RESET"; }
  # right transition: new_bg shows RSEP whose fg is new_bg, bg is prev_bg
  rtrans() { printf '%s[48;5;%sm%s[38;5;%sm%s%s' "$ESC" "$1" "$ESC" "$2" "$RSEP" "$RESET"; }
fi

# ── logos anchor ────────────────────────────────────────────────────────
# Where work stands in the project's own plan. `logos status` answers all
# of it in one read and is silent with exit 0 in a project that never
# adopted logos, so the segment simply does not appear elsewhere.
#
# Never called on the render path. The read is milliseconds but it is
# still a process launch per redraw, so a background refresh writes a
# cache and the render only sources it — the same shape as the runtime
# cache above and the update probe.
#
# TTL rather than HEAD-keyed, deliberately. The anchor is a function of
# ticket state files, not of commits: a ticket transitions long before
# anything is committed, so keying on the sha would pin a stale anchor
# through exactly the window where it changes most.
logos_position="" logos_feature="" logos_ticket="" logos_count=0
logos_done=0 logos_total=0 logos_mode=""
if (( kanagawa_logos )) && [ -n "$proj" ] && [ -d "$proj/.logos" ] \
   && command -v logos >/dev/null 2>&1; then
  lg_dir="${XDG_CACHE_HOME:-$HOME/.cache}/kanagawa-statusline"
  lg_file="$lg_dir/logos-${proj_hash:-default}"
  lg_lock="$lg_dir/logos-${proj_hash:-default}.lock"
  lg_ttl="${KANAGAWA_LOGOS_TTL:-20}"
  lg_age=999999999
  [ -f "$lg_file" ] && lg_age=$(( $(date +%s) - $(file_mtime "$lg_file") ))
  if (( lg_age >= lg_ttl )); then
    mkdir -p "$lg_dir" 2>/dev/null
    # mkdir is atomic — first writer wins. The 60s guard clears a lock
    # left by a crashed refresh so checks cannot wedge permanently.
    if [ -d "$lg_lock" ] && (( $(date +%s) - $(file_mtime "$lg_lock") > 60 )); then
      rmdir "$lg_lock" 2>/dev/null
    fi
    if mkdir "$lg_lock" 2>/dev/null; then
      (
        trap 'rmdir "$lg_lock" 2>/dev/null' EXIT
        # stdout only: a non-zero exit or a diagnostic on stderr must read
        # as "nothing to show", never as content. Writing the file either
        # way is what stops a failing project respawning every render.
        lg_json=$(cd "$proj" && logos status 2>/dev/null)
        {
          if [ -n "$lg_json" ]; then
            # Whitelist every field. This cache is sourced, so anything
            # reaching it unfiltered would execute; slugs are [a-z0-9-] by
            # the store's naming rules and the closed sets are closed.
            lg_get() { printf '%s' "$lg_json" | jq -r "$1" 2>/dev/null | tr -cd "$2" | head -c "${3:-40}"; }
            printf 'LG_POSITION=%s\n' "$(lg_get '.anchor.position // ""' 'a-z' 10)"
            printf 'LG_FEATURE=%s\n'  "$(lg_get '.anchor.feature  // ""' 'a-zA-Z0-9._-')"
            printf 'LG_TICKET=%s\n'   "$(lg_get '.anchor.ticket   // ""' 'a-zA-Z0-9._-')"
            printf 'LG_COUNT=%s\n'    "$(lg_get '.anchor.count    // 0'  '0-9' 4)"
            printf 'LG_DONE=%s\n'     "$(lg_get '.anchor.done     // 0'  '0-9' 4)"
            printf 'LG_TOTAL=%s\n'    "$(lg_get '.anchor.total    // 0'  '0-9' 4)"
            printf 'LG_MODE=%s\n'     "$(lg_get '.mode            // ""' 'a-z' 10)"
          fi
        } > "$lg_file.tmp" 2>/dev/null && mv "$lg_file.tmp" "$lg_file" 2>/dev/null
      ) >/dev/null 2>&1 </dev/null &
      disown 2>/dev/null || true
    fi
  fi
  if [ -f "$lg_file" ] && [ ! -L "$lg_file" ]; then
    LG_POSITION="" LG_FEATURE="" LG_TICKET="" LG_COUNT="" LG_DONE="" LG_TOTAL="" LG_MODE=""
    # shellcheck source=/dev/null
    . "$lg_file" 2>/dev/null
    # Re-validate after sourcing: the writer whitelists, and a reader that
    # trusts its own cache file is one tampered file away from injecting
    # escapes into every redraw.
    case "$LG_POSITION" in building|between|idle) logos_position="$LG_POSITION" ;; esac
    case "$LG_MODE"     in project|user)          logos_mode="$LG_MODE" ;; esac
    logos_feature=$(printf '%s' "$LG_FEATURE" | tr -cd 'a-zA-Z0-9._-')
    logos_ticket=$(printf  '%s' "$LG_TICKET"  | tr -cd 'a-zA-Z0-9._-')
    # Spelled out rather than looped through eval: the loop variable list
    # would have contained `done`, which is a shell keyword, and the
    # indirection hid every LG_* read from static analysis.
    logos_count=$(printf '%s' "$LG_COUNT" | tr -cd '0-9')
    logos_done=$(printf  '%s' "$LG_DONE"  | tr -cd '0-9')
    logos_total=$(printf '%s' "$LG_TOTAL" | tr -cd '0-9')
    [ -n "$logos_count" ] || logos_count=0
    [ -n "$logos_done" ]  || logos_done=0
    [ -n "$logos_total" ] || logos_total=0
  fi
fi

# Adoption mode rides the glyph rather than a field of its own. Mode is
# nearly static, which argues for shedding it early, but it is also the
# one fact you should never have to guess at, which argues for keeping it
# last — a slot cannot satisfy both. Carried by the icon it costs no
# columns and survives to the final level for free.
#   ◈ project — state root committed inside the repository
#   ◇ user    — state root lives outside it, under the installer's roof
#   ◌ unknown — the read did not say, so neither claim is made
#
# Unknown is its own glyph rather than a fallback to project. A default
# here would assert a mode on no evidence, and the case is reachable
# without anything being broken: a logos predating the mode field, a
# cache written before it existed, or a value this whitelist does not
# recognise because a later logos added one. U+25CC is the standard
# placeholder ring, which is exactly the claim being made.
#
# It renders at full weight. Only the mode is unknown; the work beside
# it is not, and dimming the segment would hide what we know to mark
# what we do not.
logos_glyph() {
  case "$logos_mode" in
    project) printf '◈' ;;
    user)    printf '◇' ;;
    *)       printf '◌' ;;
  esac
}

# Anchor text at a detail level. The ladder sheds by how much each field
# still means on its own, least self-sufficient first:
#
#   4  ◈ feature (2/3) › ticket   everything
#   3  ◈ feature › ticket         count shed: it refines an answer rather
#                                 than giving one, so losing it costs
#                                 precision and not orientation
#   2  ◈ feature                  ticket shed: a ticket slug is a delta
#                                 stated relative to its feature and means
#                                 nothing alone, while a feature is a
#                                 complete referent that stands by itself
#   1  ◈                          feature shed: still says logos is here,
#                                 and in which mode
#   0  (nothing)                  the line does not determine usability,
#                                 so total shedding is acceptable
#
# `idle` renders the bare glyph from level 1 up: it is not "nothing to
# show" but "adopted, nothing active", and those must not look alike.
# Between-tickets fills the ticket's own slot with `none` rather than
# closing the gap, because a bare feature is already what level 2 looks
# like and the two must not be the same pixels.
logos_text() { # <detail-level>
  local lvl=$1 body="" tail=""
  [ -n "$logos_position" ] || return
  (( lvl <= 0 )) && return
  (( lvl >= 1 )) || return
  if (( lvl == 1 )); then
    logos_glyph
    return
  fi
  case "$logos_position" in
    building)
      if [ -n "$logos_feature" ]; then
        body="$logos_feature"
        [ -n "$logos_ticket" ] && tail="$logos_ticket" || tail="${logos_count} building"
      else
        body="${logos_count} building"
      fi
      ;;
    between)
      if [ -n "$logos_feature" ]; then
        body="$logos_feature"; tail="none"
      else
        body="${logos_count} active"
      fi
      ;;
    idle) printf '%s' "$(logos_glyph)"; return ;;
  esac
  (( lvl >= 4 )) && (( logos_total > 0 )) && body+=" (${logos_done}/${logos_total})"
  (( lvl >= 3 )) && [ -n "$tail" ] && body+=" › $tail"
  printf '%s %s' "$(logos_glyph)" "$body"
}

logos_detail=4

# ── build LEFT ──────────────────────────────────────────────────────────
left=""
prev_bg=""
add_left() { # <bg> <fg> <text>
  local bg=$1 fg=$2 txt=$3
  [ -z "$txt" ] && return
  if [ -n "$prev_bg" ]; then
    # Protrusion effect: ctx → model boundary uses left-pointing arrow so
    # the model bg "pushes" leftward into ctx. All other transitions stay ltrans.
    if [ "$prev_bg" = "$CTX_BG" ]; then
      left+=$(rtrans "$prev_bg" "$bg")
    else
      left+=$(ltrans "$prev_bg" "$bg")
    fi
  elif [ "$KANAGAWA_STYLE" = "text" ]; then
    # Text mode has no leading cap, so the first segment's leading space
    # would push content 1 column right. Trim it.
    txt="${txt# }"
  fi
  left+=$(seg "$bg" "$fg" "$txt")
  prev_bg=$bg
}

# Rebuildable, unlike the original straight-line build: the overflow loop
# below re-runs it to shed logos detail once the right cluster has no langs
# left to drop.
build_left() {
left=""
prev_bg=""
first_bg=""
if [ -n "$ctx_pct" ]; then
  ctx_text=" ${ctx_pct}%"
  [ -n "$ctx_size" ] && ctx_text+=" 󰍛 $ctx_size"
  add_left "$CTX_BG" "$CTX_FG" "$ctx_text"
  first_bg=$CTX_BG
fi
[ -n "$model" ]    && { add_left "$A_BG" "$A_FG" " $model"; [ -z "$first_bg" ] && first_bg=$A_BG; }
if [ -n "$basename" ]; then
  cwd_text=" $basename"
  git_parts=()
  (( git_staged    > 0 )) && git_parts+=("+$git_staged")
  (( git_modified  > 0 )) && git_parts+=("!$git_modified")
  (( git_untracked > 0 )) && git_parts+=("?$git_untracked")
  (( ${#git_parts[@]} > 0 )) && cwd_text+=" ${git_parts[*]}"
  add_left "$B_BG" "$B_FG" "$cwd_text"
fi
if [ -n "$branch" ]; then
  branch_text="  $branch"
  (( git_ahead  > 0 )) && branch_text+=" ↑$git_ahead"
  (( git_behind > 0 )) && branch_text+=" ↓$git_behind"
  add_left "$C_BG" "$C_FG" "$branch_text"
fi
# logos anchor, seated after branch: git says where you are in the history,
# this says where you are in the plan. add_left already skips empty text, so
# idle, unadopted, and detail level 0 all fall out as no segment at all.
logos_seg=$(logos_text "$logos_detail")
# Built into a variable first: add_left skips empty text, and a bare " "
# prefix would defeat that and emit an empty coloured segment.
#
# User mode tints the whole segment rather than just the glyph: one
# variable instead of an escape embedded in the text, identical in
# powerline and text modes, and a tone shift reads more clearly than one
# recoloured character while staying as quiet.
if [ -n "$logos_seg" ]; then
  case "$logos_mode" in
    user)    lg_fg=$DU_FG ;;
    project) lg_fg=$D_FG ;;
    # Full weight, matching project. What is unknown is the mode, not
    # the work: the feature, ticket, and progress beside it are all
    # known, and tinting the whole segment on an unknown attribute
    # de-emphasises information we do have. The glyph carries the
    # uncertainty alone. DX_FG stays a separate per-variant knob so
    # unknown can be escalated later without restructuring this.
    *)       lg_fg=$DX_FG ;;
  esac
  add_left "$D_BG" "$lg_fg" " $logos_seg"
fi
# leading cap (left-pointing angle in first segment's bg on default bg) + trailing arrow off last segment
if [ -n "$prev_bg" ] && [ "$KANAGAWA_STYLE" != "text" ]; then
  left_cap=$(printf '%s[38;5;%sm%s%s' "$ESC" "$first_bg" "$RSEP" "$RESET")
  left="${left_cap}${left}"
  left+=$(printf '%s[38;5;%sm%s%s' "$ESC" "$prev_bg" "$LSEP" "$RESET")
fi
}
build_left

# ── build RIGHT (dynamic gradient + graceful degradation) ───────────────
# active_langs holds the lang keys currently visible (in display order).
# build_right_data() recomputes seg_keys/seg_data from active_langs so the
# gray gradient always spans GRAD_MIN..GRAD_MAX evenly, dark→light, no
# matter how many langs are detected or surviving degradation.

active_langs=()
[ -n "$node_v" ] && active_langs+=(node)
[ -n "$bun_v" ]  && active_langs+=(bun)
[ -n "$py_v" ]   && active_langs+=(py)
[ -n "$go_v" ]   && active_langs+=(go)
[ -n "$rust_v" ] && active_langs+=(rust)
[ -n "$zig_v" ]  && active_langs+=(zig)
[ -n "$odin_v" ] && active_langs+=(odin)

# Drop precedence — first key in list is dropped first when overflow detected.
drop_order=(odin zig rust go node bun py)

lang_text() { # <key> -> text
  case $1 in
    node) printf ' node %s' "$node_v" ;;
    bun)  printf ' bun %s' "$bun_v" ;;
    py)   printf ' py %s' "$py_v" ;;
    go)   printf ' go %s' "$go_v" ;;
    rust) printf ' rust %s' "$rust_v" ;;
    zig)  printf ' zig %s' "$zig_v" ;;
    odin) printf ' odin %s' "$odin_v" ;;
  esac
}

# Build seg_keys/seg_data from current active_langs + fixed terminators.
seg_keys=()
seg_data=()
build_right_data() {
  seg_keys=()
  seg_data=()
  local n=${#active_langs[@]} i=0 bg fg key text
  for key in "${active_langs[@]}"; do
    if (( n <= 1 )); then
      bg=$GRAD_MIN
    else
      bg=$(( GRAD_MIN + (GRAD_MAX - GRAD_MIN) * i / (n - 1) ))
    fi
    if (( bg < 244 )); then fg=$FUJI_WHITE; else fg=$SUMI_FG; fi
    # Text mode: gradient value is the fg (no bg fill to contrast against).
    [ "$KANAGAWA_STYLE" = "text" ] && fg=$bg
    text=$(lang_text "$key")
    seg_keys+=("$key")
    seg_data+=("$bg|$fg|$text")
    ((i++))
  done
  [ -n "$style" ] && [ "$style" != "default" ] && {
    seg_keys+=(style); seg_data+=("$Y_BG|$Y_FG| $style"); }
  [ -n "$ver" ]   && { seg_keys+=(cli);   seg_data+=("$Z_BG|$Z_FG| 󰙴 cli v$ver"); }
  [ -n "$badge" ] && { seg_keys+=(badge); seg_data+=("$X_BG|$X_FG| $badge"); }
  [ -n "$update_available" ] && {
    seg_keys+=(update); seg_data+=("$U_BG|$U_FG|  v$update_available"); }
}

build_right() {
  right=""
  local last_bg="" last_key="" i bg fg txt
  for i in "${!seg_keys[@]}"; do
    IFS='|' read -r bg fg txt <<< "${seg_data[$i]}"
    if [ -z "$last_bg" ]; then
      [ "$KANAGAWA_STYLE" != "text" ] \
        && right+=$(printf '%s[38;5;%sm%s%s' "$ESC" "$bg" "$RSEP" "$RESET")
    elif [ "$last_key" = "cli" ]; then
      # Protrusion: mirror the model→ctx leftward protrusion on the left
      # cluster — cli pushes rightward into the next segment.
      right+=$(ltrans "$last_bg" "$bg")
    else
      right+=$(rtrans "$last_bg" "$bg")
    fi
    right+=$(seg "$bg" "$fg" "$txt")
    last_bg=$bg
    last_key="${seg_keys[$i]}"
  done
  if [ -n "$last_bg" ] && [ "$KANAGAWA_STYLE" != "text" ]; then
    right+=$(printf '%s[38;5;%sm%s%s' "$ESC" "$last_bg" "$LSEP" "$RESET")
  fi
}

# Drop next-lowest-priority lang from active_langs (returns 1 if nothing droppable).
drop_one() {
  local k i
  for k in "${drop_order[@]}"; do
    for i in "${!active_langs[@]}"; do
      if [ "${active_langs[$i]}" = "$k" ]; then
        unset 'active_langs[i]'
        active_langs=("${active_langs[@]}")
        return 0
      fi
    done
  done
  return 1
}

build_right_data
build_right

# Right-align: pad between left and right clusters out to terminal width.
strip_ansi() { printf '%s' "$1" | LC_ALL=C sed $'s/\x1b\\[[0-9;]*m//g'; }
visible_len() {
  local s
  s=$(strip_ansi "$1")
  # PUA glyph width: 1 for "Mono" nerd-font variants (default), 2 for non-Mono.
  local pua_w="${KANAGAWA_PUA_WIDTH:-1}"
  PUA_W="$pua_w" python3 -c 'import os, sys, unicodedata
s=sys.argv[1]
pua_w=int(os.environ.get("PUA_W","1"))
n=0
for ch in s:
    cp = ord(ch)
    cat = unicodedata.category(ch)
    # Skip true non-printing categories. Do NOT skip "Co" (Private Use) —
    # those are nerd-font glyphs that render visibly.
    if cat in ("Cc","Cf","Cs","Cn"): continue
    if unicodedata.east_asian_width(ch) in ("W","F"):
        n += 2
    elif cat == "Co" or 0xE000 <= cp <= 0xF8FF or 0xF0000 <= cp <= 0xFFFFD:
        n += pua_w
    else:
        n += 1
print(n)' "$s" 2>/dev/null || printf '%s' "$s" | wc -m
}

# KANAGAWA_COLS wins outright: a caller rendering into a surface that is not
# this process's terminal (tmux status-right, a watch pane, a test harness)
# knows the target width and we cannot discover it. Everything below is
# discovery, and discovery must not override a caller who already knows.
cols="${KANAGAWA_COLS:-}"
[[ "$cols" =~ ^[0-9]+$ ]] || cols=$( { stty size </dev/tty | awk '{print $2}'; } 2>/dev/null )
[[ "$cols" =~ ^[0-9]+$ ]] || cols="${COLUMNS:-}"
[[ "$cols" =~ ^[0-9]+$ ]] || cols=$(tput cols 2>/dev/null || echo 120)
(( cols < 1 )) && cols=120
# Claude Code statusline container chrome (left margin + right margin).
# Override via env if your terminal renders with more/less padding.
cols=$(( cols - ${KANAGAWA_CHROME:-4} ))

lvis=$(visible_len "$left")
while :; do
  rvis=$(visible_len "$right")
  pad=$(( cols - lvis - rvis ))
  (( pad >= 1 )) && break
  if drop_one; then
    build_right_data
    build_right
    continue
  fi
  # Right cluster exhausted. The logos anchor is the only left-cluster
  # segment that may yield, and it yields in order: the ticket first, then
  # the segment. Ticket-before-feature and not the reverse, because a bare
  # ticket slug names the change it makes rather than the arc it serves and
  # orients nobody, while a bare feature still does. ctx, model, cwd, and
  # branch are priority anchors and stay.
  (( logos_detail > 0 )) || break
  logos_detail=$(( logos_detail - 1 ))
  build_left
  lvis=$(visible_len "$left")
done
(( pad < 1 )) && pad=1

printf '%s%*s%s' "$left" "$pad" "" "$right"
