# kanagawa-statusline — maintainer recipes.
#
# Install just: https://github.com/casey/just  (`brew install just`)
#
# usage:
#   just                  # list recipes
#   just version          # show currently-checked-in version
#   just lint             # shellcheck + bash -n
#   just link             # symlink installed paths at this repo (live edits)
#   just unlink           # reverse `just link`, restore prior install
#   just release          # +1 patch (default)
#   just release patch    # +1 patch
#   just release minor    # +1 minor, reset patch
#   just release major    # +1 major, reset minor + patch
#   just release-dry      # preview the patch bump
#   just release-dry minor

set shell := ["bash", "-euo", "pipefail", "-c"]

# Default recipe — list everything.
default:
    @just --list

# Print the version embedded in statusline.sh and the VERSION file.
version:
    @printf 'VERSION file: %s\n' "$(tr -cd '0-9.' < VERSION)"
    @printf 'script:       %s\n' \
        "$(grep -E '^KANAGAWA_STATUSLINE_VERSION=' statusline.sh \
           | head -1 \
           | sed -E 's/^[^=]+=\"?([^\"]*)\"?[[:space:]]*$/\1/' \
           | tr -cd '0-9.')"

# Shell lint + syntax check on every shipped script.
lint:
    @command -v shellcheck >/dev/null 2>&1 \
        || { echo "shellcheck not installed (brew install shellcheck)"; exit 1; }
    shellcheck -S warning statusline.sh install.sh bin/kanagawa-statusline
    bash -n statusline.sh
    bash -n install.sh
    bash -n bin/kanagawa-statusline
    @echo "lint ok"

# Symlink the installed paths at this repo so edits land in Claude Code live.
link:
    #!/usr/bin/env bash
    set -euo pipefail
    repo=$(cd "$(dirname "{{justfile()}}")" && pwd)
    state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/kanagawa-statusline"
    state_file="$state_dir/dev-link.state"
    settings="$HOME/.claude/settings.json"
    info() { printf '  • %s\n' "$*"; }
    warn() { printf '\033[33m  ! %s\033[0m\n' "$*"; }

    mkdir -p "$HOME/.claude" "$HOME/.local/bin"

    was_installed=0
    link_one() { # <dst> <src>
      local dst=$1 src=$2
      if [ -L "$dst" ]; then
        local cur
        cur=$(readlink "$dst")
        if [ "$cur" = "$src" ]; then
          info "already linked: $dst"
          return
        fi
        info "removing stale symlink: $dst -> $cur"
        rm "$dst"
      elif [ -e "$dst" ]; then
        info "real install at $dst — backing up flag, replacing with symlink"
        was_installed=1
        rm "$dst"
      fi
      ln -s "$src" "$dst"
      info "linked: $dst -> $src"
    }
    link_one "$HOME/.claude/statusline-command.sh"   "$repo/statusline.sh"
    link_one "$HOME/.local/bin/kanagawa-statusline"  "$repo/bin/kanagawa-statusline"

    # Restore / create the .statusLine block in settings.json so Claude
    # Code actually picks the symlinked script up.
    if command -v jq >/dev/null 2>&1; then
      if [ -f "$settings" ]; then
        if jq -e '(.statusLine.command // "") | tostring | test("statusline-command\\.sh")' "$settings" >/dev/null 2>&1; then
          info "$settings .statusLine already references the install path"
        else
          tmp=$(mktemp)
          jq --arg cmd "bash $HOME/.claude/statusline-command.sh" \
             '.statusLine = {type: "command", command: $cmd}' \
             "$settings" > "$tmp" && mv "$tmp" "$settings"
          info "wrote .statusLine block into $settings"
        fi
      else
        cat > "$settings" <<JSON
    {
      "statusLine": {
        "type": "command",
        "command": "bash $HOME/.claude/statusline-command.sh"
      }
    }
    JSON
        info "created $settings with .statusLine block"
      fi
    else
      warn "jq missing — could not auto-wire .statusLine in $settings"
    fi

    if [ "$was_installed" = "1" ]; then
      mkdir -p "$state_dir"
      printf 'restore-on-unlink\n' > "$state_file"
      info "saved restore flag at $state_file"
    fi

    echo
    info "linked. Edits to statusline.sh / bin/kanagawa-statusline are live."

# Reverse `just link`; restore the prior install if there was one.
unlink:
    #!/usr/bin/env bash
    set -euo pipefail
    repo=$(cd "$(dirname "{{justfile()}}")" && pwd)
    state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/kanagawa-statusline"
    state_file="$state_dir/dev-link.state"
    settings="$HOME/.claude/settings.json"
    info() { printf '  • %s\n' "$*"; }
    warn() { printf '\033[33m  ! %s\033[0m\n' "$*"; }

    unlink_one() { # <dst> <expected_src>
      local dst=$1 expected=$2
      if [ -L "$dst" ]; then
        local cur
        cur=$(readlink "$dst")
        if [ "$cur" = "$expected" ]; then
          rm "$dst"
          info "removed symlink: $dst"
        else
          info "not our symlink, leaving alone: $dst -> $cur"
        fi
      elif [ -e "$dst" ]; then
        info "not a symlink, leaving alone: $dst"
      else
        info "not present: $dst"
      fi
    }
    unlink_one "$HOME/.claude/statusline-command.sh"   "$repo/statusline.sh"
    unlink_one "$HOME/.local/bin/kanagawa-statusline"  "$repo/bin/kanagawa-statusline"

    if [ -f "$state_file" ]; then
      echo
      info "restore flag found — re-running install.sh from main"
      if command -v curl >/dev/null 2>&1; then
        if curl -fsSL https://raw.githubusercontent.com/securacore/kanagawa-statusline/main/install.sh | bash; then
          rm -f "$state_file"
          rmdir "$state_dir" 2>/dev/null || true
          echo
          warn "install.sh fetched whatever is on main right now, which may"
          warn "differ from what you had installed before linking. Run:"
          warn "    kanagawa-statusline update"
          warn "if a newer release exists."
        else
          warn "install failed — state flag kept at $state_file; rerun later"
        fi
      else
        warn "curl missing — cannot auto-restore. State flag kept at $state_file"
      fi
    else
      echo
      info "no prior install on record — symlinks removed, nothing to restore."
      # Strip the .statusLine block we (probably) added during link, but
      # only if it still references our install path. Match `uninstall`'s
      # behavior so we don't leave a dangling reference.
      if command -v jq >/dev/null 2>&1 && [ -f "$settings" ]; then
        if jq -e '(.statusLine.command // "") | tostring | test("statusline-command\\.sh")' "$settings" >/dev/null 2>&1; then
          tmp=$(mktemp)
          jq 'del(.statusLine)' "$settings" > "$tmp" && mv "$tmp" "$settings"
          info "stripped .statusLine block from $settings"
        fi
      fi
    fi

    # Tidy up — drop the state dir if it ended up empty (covers both
    # branches: flag-restore success above, and no-flag with a stale
    # empty dir left over from earlier versions of this recipe).
    rmdir "$state_dir" 2>/dev/null || true

# Show what `just release <level>` would change, without touching anything.
release-dry LEVEL="patch":
    @new=$(just _next-version "{{LEVEL}}"); \
     cur_file=$(tr -cd '0-9.' < VERSION); \
     cur_script=$(grep -E '^KANAGAWA_STATUSLINE_VERSION=' statusline.sh \
                | head -1 \
                | sed -E 's/^[^=]+=\"?([^\"]*)\"?[[:space:]]*$/\1/' \
                | tr -cd '0-9.'); \
     printf 'would bump (%s):\n  VERSION:        %s -> %s\n  statusline.sh:  %s -> %s\n  commit:         "Release v%s"\n  tag:            v%s\n  then push branch + tag (kicks .github/workflows/release.yml)\n' \
       "{{LEVEL}}" "$cur_file" "$new" "$cur_script" "$new" "$new" "$new"

# Bump VERSION + the embedded constant, commit, tag, push — tag push fires the GHA release workflow.
release LEVEL="patch":
    @just _release-clean-tree
    @new=$(just _next-version "{{LEVEL}}"); \
     printf 'bumping (%s) → %s\n' "{{LEVEL}}" "$new"; \
     just _release-bump "$new"; \
     git add VERSION statusline.sh; \
     git commit -m "Release v$new"; \
     git tag -a "v$new" -m "v$new"; \
     git push; \
     git push origin "v$new"; \
     printf '\npushed v%s — release workflow:\n  https://github.com/securacore/kanagawa-statusline/actions/workflows/release.yml\n' "$new"

# ── private helpers (underscore-prefixed → hidden from `just --list`) ──

# Compute the next version from the current VERSION file + a bump level.
# Echoes the bumped version (e.g. "0.2.0"). Exits non-zero on bad input.
[private]
_next-version LEVEL:
    @cur=$(tr -cd '0-9.' < VERSION); \
     if ! [[ "$cur" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then \
        echo "VERSION file is not plain semver: '$cur'" >&2; \
        exit 1; \
     fi; \
     IFS=. read -r MAJ MIN PATCH <<< "$cur"; \
     case "{{LEVEL}}" in \
       patch) PATCH=$((PATCH + 1)) ;; \
       minor) MIN=$((MIN + 1)); PATCH=0 ;; \
       major) MAJ=$((MAJ + 1)); MIN=0; PATCH=0 ;; \
       *) echo "level must be patch|minor|major (got: {{LEVEL}})" >&2; exit 2 ;; \
     esac; \
     printf '%s.%s.%s\n' "$MAJ" "$MIN" "$PATCH"

[private]
_release-clean-tree:
    @if [ -n "$(git status --porcelain)" ]; then \
        echo "working tree is dirty; commit or stash first" >&2; \
        git status --short >&2; \
        exit 1; \
    fi
    @branch=$(git symbolic-ref --short HEAD); \
     if [ "$branch" != "main" ]; then \
        echo "warning: releasing from branch '$branch' (not main)" >&2; \
     fi

# Rewrite VERSION + the embedded constant in statusline.sh, then verify.
[private]
_release-bump VERSION:
    printf '%s\n' "{{VERSION}}" > VERSION
    @# Portable in-place edit — macOS sed and GNU sed disagree on -i.
    tmp=$(mktemp); \
    sed -E 's/^(KANAGAWA_STATUSLINE_VERSION=)"[^"]*"/\1"{{VERSION}}"/' statusline.sh > "$tmp"; \
    mv "$tmp" statusline.sh; \
    chmod +x statusline.sh
    @got=$(grep -E '^KANAGAWA_STATUSLINE_VERSION=' statusline.sh \
         | head -1 \
         | sed -E 's/^[^=]+="?([^"]*)"?[[:space:]]*$/\1/'); \
     if [ "$got" != "{{VERSION}}" ]; then \
        echo "failed to update KANAGAWA_STATUSLINE_VERSION (got: $got)" >&2; \
        exit 1; \
     fi
