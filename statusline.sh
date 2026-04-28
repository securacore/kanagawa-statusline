#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────
#  Claude Code status line — lualine-inspired, kanagawa wave themed.
# ─────────────────────────────────────────────────────────────────────────
#  Single-line, two-cluster (left + right) statusline rendered with
#  Powerline glyphs and a violet → blue → sumi-ink → orange palette.
#
#  LEFT CLUSTER  (priority anchors)
#    [ ctx % ] → [ model (effort) ] → [ git branch ] → [ cwd basename ]
#       violet         blue           dark-blue        sumi-ink5
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
#    GRAD_MIN / GRAD_MAX             lang gradient endpoints
#    Y_BG / Z_BG / X_BG              style / cli / caveman colors
#    drop_order                      lang priority for graceful degradation
#    cols=$(( cols - N ))            chrome buffer (right-edge alignment)
#    STATUSLINE_DEMO=1               env flag — preview all 7 langs
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
#    • Right-edge alignment via stty terminal width (independent of
#      $COLUMNS being passed by Claude Code).
#
#  DEPENDENCIES (optional)
#    Caveman plugin — https://github.com/JuliusBrussee/caveman  (writes the
#    flag file consumed for the badge; safe to omit, the segment is skipped).
# ─────────────────────────────────────────────────────────────────────────

input=$(cat)

model=$(printf '%s' "$input" | jq -r '.model.display_name // ""')
effort=$(printf '%s' "$input" | jq -r '.effort.level // ""')
[ -n "$effort" ] && model="$model ($effort)"
proj=$(printf '%s' "$input" | jq -r '.workspace.project_dir // .cwd // ""')
# ── parse JSON from Claude Code (piped via stdin) ──────────────────────
# Field schema: https://docs.claude.com/en/docs/claude-code/statusline
cwd=$(printf '%s'  "$input" | jq -r '.workspace.current_dir // .cwd // ""')
ver=$(printf '%s'  "$input" | jq -r '.version // ""')
style=$(printf '%s' "$input" | jq -r '(.output_style.name // .output_style // "") | if type=="string" then . else "" end' | tr -d '\n\r')
ctx_pct=$(printf '%s' "$input" | jq -r '.context_window.used_percentage // 0')

basename=""
[ -n "$proj" ] && basename=$(basename "$proj")

branch=""
if [ -n "$proj" ] && git -C "$proj" rev-parse --git-dir >/dev/null 2>&1; then
  branch=$(git -C "$proj" symbolic-ref --short HEAD 2>/dev/null \
        || git -C "$proj" rev-parse --short HEAD 2>/dev/null)
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

# Cache runtime version output (5 min TTL) keyed by project path.
proj_hash=$(printf '%s' "$proj" | md5 2>/dev/null || printf '%s' "$proj" | md5sum 2>/dev/null | awk '{print $1}')
proj_hash=${proj_hash:0:12}
cache_file="${TMPDIR:-/tmp}/cc-statusline-rt-${proj_hash:-default}"
cache_age=999999
if [ -f "$cache_file" ]; then
  mtime=$(stat -f %m "$cache_file" 2>/dev/null || stat -c %Y "$cache_file" 2>/dev/null || echo 0)
  cache_age=$(( $(date +%s) - mtime ))
fi

node_v="" bun_v="" py_v="" go_v="" rust_v="" zig_v="" odin_v=""

if [ "${STATUSLINE_DEMO:-0}" = 1 ]; then
  node_v="22.0.0"; bun_v="1.3.3"; py_v="3.14.4"
  go_v="1.23.0";   rust_v="1.75.0"
  zig_v="0.13.0";  odin_v="dev-2024"
elif [ "$cache_age" -lt 300 ]; then
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
# Three variants supported via KANAGAWA_VARIANT env var:
#   wave   — default night/cool   (violet → crystal blue → sumi-ink → orange)
#   dragon — warm earthy night    (dragonViolet → dragonBlue2 → dragonBlack
#                                  → dragonOrange)
#   lotus  — light theme          (lotusViolet → lotusBlue → lotusGray
#                                  → lotusOrange)
# Hex values mapped to nearest ANSI 256.

# Variant resolution order:
#   1. KANAGAWA_VARIANT env var
#   2. VARIANT key in $XDG_CONFIG_HOME/kanagawa-statusline/config
#   3. "wave" (default)
KANAGAWA_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/kanagawa-statusline/config"
if [ -z "${KANAGAWA_VARIANT:-}" ] && [ -f "$KANAGAWA_CONFIG" ]; then
  # shellcheck disable=SC1090
  . "$KANAGAWA_CONFIG"
  KANAGAWA_VARIANT="${VARIANT:-}"
fi
KANAGAWA_VARIANT="${KANAGAWA_VARIANT:-wave}"

# "off" — print nothing and exit. Disables theming entirely.
if [ "$KANAGAWA_VARIANT" = "off" ]; then
  exit 0
fi

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
      B_BG=24;     B_FG=$FUJI_WHITE     # waveBlue2 — branch
      C_BG=237;    C_FG=$OLD_WHITE      # sumiInk5 — cwd dimmed
      GRAD_MIN=232; GRAD_MAX=250        # sumi-ink dark→light
      Y_BG=179;    Y_FG=$SUMI_FG        # boatYellow2 — style
      Z_BG=173;    Z_FG=$SUMI_FG        # muted dusty orange — cli
      X_BG=215;    X_FG=$SUMI_FG        # surimiOrange — caveman
      ;;
    dragon)
      # Dragon — warm earthy night. Reference colors:
      #   dragonViolet #8992A7, dragonBlue2 #8BA4B0, dragonAqua #8EA4A2,
      #   dragonBlack3..6 #181616..#625E5A, dragonOrange #B6927B,
      #   dragonOrange2 #B98D7B, dragonYellow #C4B28A, dragonGray #A6A69C,
      #   dragonWhite #C5C9C5, dragonAsh #737C73.
      FUJI_WHITE=187; OLD_WHITE=144; SUMI_FG=234
      CTX_BG=96;   CTX_FG=$FUJI_WHITE   # dragonViolet (#8992A7) — anchor
      A_BG=109;    A_FG=$SUMI_FG        # dragonBlue2 (#8BA4B0) — model
      B_BG=66;     B_FG=$FUJI_WHITE     # dragonAqua-ish — branch
      C_BG=235;    C_FG=$OLD_WHITE      # dragonBlack4 — cwd dimmed
      GRAD_MIN=234; GRAD_MAX=247        # dragonBlack3 → dragonGray
      Y_BG=144;    Y_FG=$SUMI_FG        # dragonYellow — style
      Z_BG=180;    Z_FG=$SUMI_FG        # dragonOrange2 (#B98D7B) — cli
      X_BG=173;    X_FG=$SUMI_FG        # dragonOrange (#B6927B) — caveman
      ;;
    lotus)
      # Lotus — light/day. Reference colors:
      #   lotusViolet4 #624C83, lotusBlue4 #4D699B, lotusBlue3 #9FB5C9,
      #   lotusWhite0..5 #D5CEA3..#E4D794, lotusGray2 #716E61,
      #   lotusOrange #CC6D00, lotusOrange2 #E98A00, lotusYellow3 #DE9800.
      FUJI_WHITE=234; OLD_WHITE=236; SUMI_FG=234
      CTX_BG=60;   CTX_FG=255           # lotusViolet4 — anchor
      A_BG=24;     A_FG=255             # lotusBlue4 — model
      B_BG=152;    B_FG=$SUMI_FG        # lotusBlue3 (#9FB5C9) — branch
      C_BG=187;    C_FG=$SUMI_FG        # lotusWhite-ish — cwd
      GRAD_MIN=250; GRAD_MAX=255        # narrow light-gray band (stays in grayscale)
      Y_BG=178;    Y_FG=$SUMI_FG        # lotusYellow3 — style
      Z_BG=208;    Z_FG=$SUMI_FG        # lotusOrange2 — cli
      X_BG=166;    X_FG=255             # lotusOrange (#CC6D00) — caveman
      ;;
    *)
      printf 'statusline: unknown KANAGAWA_VARIANT=%s (use: wave|dragon|lotus)\n' \
        "$KANAGAWA_VARIANT" >&2
      KANAGAWA_VARIANT=wave
      apply_palette
      return
      ;;
  esac
}
apply_palette

LSEP=$''   #
RSEP=$''   #

# seg <bg> <fg> <text>
seg() { printf '%s[48;5;%sm%s[38;5;%sm%s %s' "$ESC" "$1" "$ESC" "$2" "$3" "$RESET"; }
# left transition: prev_bg -> new_bg using LSEP
ltrans() { printf '%s[48;5;%sm%s[38;5;%sm%s%s' "$ESC" "$2" "$ESC" "$1" "$LSEP" "$RESET"; }
# right transition: new_bg shows RSEP whose fg is new_bg, bg is prev_bg
rtrans() { printf '%s[48;5;%sm%s[38;5;%sm%s%s' "$ESC" "$1" "$ESC" "$2" "$RSEP" "$RESET"; }

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
  fi
  left+=$(seg "$bg" "$fg" "$txt")
  prev_bg=$bg
}

first_bg=""
[ -n "$ctx_pct" ]  && { add_left "$CTX_BG" "$CTX_FG" " ${ctx_pct}%"; first_bg=$CTX_BG; }
[ -n "$model" ]    && { add_left "$A_BG" "$A_FG" " $model"; [ -z "$first_bg" ] && first_bg=$A_BG; }
[ -n "$branch" ]   && add_left "$B_BG" "$B_FG" " $branch"
[ -n "$basename" ] && add_left "$C_BG" "$C_FG" " $basename"
# leading cap (left-pointing angle in first segment's bg on default bg) + trailing arrow off last segment
if [ -n "$prev_bg" ]; then
  left_cap=$(printf '%s[38;5;%sm%s%s' "$ESC" "$first_bg" "$RSEP" "$RESET")
  left="${left_cap}${left}"
  left+=$(printf '%s[38;5;%sm%s%s' "$ESC" "$prev_bg" "$LSEP" "$RESET")
fi

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
    text=$(lang_text "$key")
    seg_keys+=("$key")
    seg_data+=("$bg|$fg|$text")
    ((i++))
  done
  [ -n "$style" ] && [ "$style" != "default" ] && {
    seg_keys+=(style); seg_data+=("$Y_BG|$Y_FG| $style"); }
  [ -n "$ver" ]   && { seg_keys+=(cli);   seg_data+=("$Z_BG|$Z_FG| cli v$ver"); }
  [ -n "$badge" ] && { seg_keys+=(badge); seg_data+=("$X_BG|$X_FG| $badge"); }
}

build_right() {
  right=""
  local last_bg="" i bg fg txt
  for i in "${!seg_keys[@]}"; do
    IFS='|' read -r bg fg txt <<< "${seg_data[$i]}"
    if [ -z "$last_bg" ]; then
      right+=$(printf '%s[38;5;%sm%s%s' "$ESC" "$bg" "$RSEP" "$RESET")
    else
      right+=$(rtrans "$last_bg" "$bg")
    fi
    right+=$(seg "$bg" "$fg" "$txt")
    last_bg=$bg
  done
  if [ -n "$last_bg" ]; then
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

cols=$( { stty size </dev/tty | awk '{print $2}'; } 2>/dev/null )
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
  drop_one || break
  build_right_data
  build_right
done
(( pad < 1 )) && pad=1

printf '%s%*s%s' "$left" "$pad" "" "$right"
