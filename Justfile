# kanagawa-statusline — maintainer recipes.
#
# Install just: https://github.com/casey/just  (`brew install just`)
#
# usage:
#   just                  # list recipes
#   just version          # show currently-checked-in version
#   just lint             # shellcheck + bash -n
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
