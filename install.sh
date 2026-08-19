#!/usr/bin/env bash
# kanagawa-statusline installer
#
# Downloads statusline.sh into ~/.claude/ and prints the settings.json
# snippet you need to add. Idempotent — safe to re-run for upgrades.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/securacore/kanagawa-statusline/main/install.sh | bash
#   # or, after cloning:
#   bash install.sh

set -euo pipefail

REPO_RAW="${KANAGAWA_STATUSLINE_REPO_RAW:-https://raw.githubusercontent.com/securacore/kanagawa-statusline/main}"
DEST_DIR="$HOME/.claude"
DEST_FILE="$DEST_DIR/statusline-command.sh"
BIN_DIR="${KANAGAWA_STATUSLINE_BIN:-$HOME/.local/bin}"
BIN_FILE="$BIN_DIR/kanagawa-statusline"

bold()  { printf '\033[1m%s\033[0m\n' "$*"; }
info()  { printf '  • %s\n' "$*"; }
warn()  { printf '\033[33m  ! %s\033[0m\n' "$*"; }
fail()  { printf '\033[31m  ✗ %s\033[0m\n' "$*"; exit 1; }

bold "kanagawa-statusline installer"

# ── deps ────────────────────────────────────────────────────────────────
for cmd in jq python3 bash; do
  command -v "$cmd" >/dev/null 2>&1 || fail "missing required tool: $cmd"
done
info "deps ok (jq, python3, bash)"

# ── fetch ───────────────────────────────────────────────────────────────
mkdir -p "$DEST_DIR"

SRC_DIR="$(dirname "$0")"

# Fetch helper — either copy from local clone or download from REPO_RAW.
fetch_to() { # <relative-path-in-repo> <dest>
  local src=$1 dst=$2
  if [ -f "$SRC_DIR/$src" ]; then
    install -m 0755 "$SRC_DIR/$src" "$dst"
  elif command -v curl >/dev/null 2>&1; then
    curl -fsSL "$REPO_RAW/$src" -o "$dst.tmp"
    chmod 0755 "$dst.tmp" && mv "$dst.tmp" "$dst"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "$dst.tmp" "$REPO_RAW/$src"
    chmod 0755 "$dst.tmp" && mv "$dst.tmp" "$dst"
  else
    fail "neither curl nor wget available"
  fi
}

fetch_to statusline.sh "$DEST_FILE"
info "installed statusline → $DEST_FILE"

mkdir -p "$BIN_DIR"
fetch_to bin/kanagawa-statusline "$BIN_FILE"
info "installed CLI       → $BIN_FILE"

# PATH check
case ":$PATH:" in
  *":$BIN_DIR:"*) : ;;
  *) warn "$BIN_DIR is not on PATH — add it to your shell rc to run \`kanagawa-statusline\`" ;;
esac

# ── settings.json wiring ────────────────────────────────────────────────
SETTINGS="$DEST_DIR/settings.json"
STATUSLINE_CMD="bash $HOME/.claude/statusline-command.sh"

if [ -f "$SETTINGS" ]; then
  if jq -e '(.statusLine.command // "") | tostring | test("statusline-command\\.sh")' \
        "$SETTINGS" >/dev/null 2>&1; then
    info "settings.json already wired"
  elif jq empty "$SETTINGS" >/dev/null 2>&1; then
    tmp=$(mktemp)
    jq --arg cmd "$STATUSLINE_CMD" \
       '.statusLine = {type: "command", command: $cmd}' \
       "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
    info "merged statusLine block into $SETTINGS"
  else
    warn "$SETTINGS is not valid JSON — refusing to overwrite"
    warn "merge this snippet manually:"
    printf '\n{\n  "statusLine": {\n    "type": "command",\n    "command": "%s"\n  }\n}\n\n' "$STATUSLINE_CMD"
  fi
else
  jq -n --arg cmd "$STATUSLINE_CMD" \
        '{statusLine: {type: "command", command: $cmd}}' > "$SETTINGS"
  info "wrote $SETTINGS with statusLine config"
fi

# ── variant prompt ──────────────────────────────────────────────────────
bold "Choose a Kanagawa variant"
echo "  1) wave-xlean (default — text-only, cool fg accents)"
echo "  2) wave   (cool night, full powerline)"
echo "  3) dragon (warm earthy night)"
echo "  4) lotus  (light theme)"
echo "  Set KANAGAWA_VARIANT=<variant> in your shell rc; see \`kanagawa-statusline --help\` for full list."

bold "Done. Reload Claude Code (or press Enter at the prompt)."
