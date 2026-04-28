#!/usr/bin/env bash
# kanagawa-statusline installer
#
# Downloads statusline.sh into ~/.claude/ and prints the settings.json
# snippet you need to add. Idempotent — safe to re-run for upgrades.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/<user>/kanagawa-statusline/main/install.sh | bash
#   # or, after cloning:
#   bash install.sh

set -euo pipefail

REPO_RAW="${KANAGAWA_STATUSLINE_REPO_RAW:-https://raw.githubusercontent.com/<your-username>/kanagawa-statusline/main}"
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
SNIPPET='{
  "statusLine": {
    "type": "command",
    "command": "bash ~/.claude/statusline-command.sh"
  }
}'

if [ -f "$SETTINGS" ]; then
  if jq -e '.statusLine.command // ""' "$SETTINGS" 2>/dev/null \
        | grep -q "statusline-command.sh"; then
    info "settings.json already wired"
  else
    warn "settings.json exists but does not reference statusline-command.sh"
    warn "merge this snippet manually:"
    printf '\n%s\n\n' "$SNIPPET"
  fi
else
  printf '%s\n' "$SNIPPET" > "$SETTINGS"
  info "wrote $SETTINGS with statusLine config"
fi

# ── variant prompt ──────────────────────────────────────────────────────
bold "Choose a Kanagawa variant"
echo "  1) wave   (default — cool night)"
echo "  2) dragon (warm earthy night)"
echo "  3) lotus  (light theme)"
echo "  Set KANAGAWA_VARIANT=<wave|dragon|lotus> in your shell rc."

bold "Done. Reload Claude Code (or press Enter at the prompt)."
