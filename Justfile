# kanagawa-statusline — maintainer recipes.
#
# Install just: https://github.com/casey/just  (`brew install just`)
#
# usage:
#   just                       # list recipes
#   just version               # show current version
#   just lint                  # shellcheck + bash -n
#   just release 0.1.0         # bump → commit → tag → push (kicks GHA)
#   just release-dry 0.1.0     # preview the bump without touching anything

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

# Show what `just release <version>` would change, without touching anything.
release-dry VERSION:
    @just _release-validate "{{VERSION}}"
    @cur_file=$(tr -cd '0-9.' < VERSION); \
     cur_script=$(grep -E '^KANAGAWA_STATUSLINE_VERSION=' statusline.sh \
                | head -1 \
                | sed -E 's/^[^=]+=\"?([^\"]*)\"?[[:space:]]*$/\1/' \
                | tr -cd '0-9.'); \
     printf 'would bump:\n  VERSION:        %s -> %s\n  statusline.sh:  %s -> %s\n  commit:         "Release v%s"\n  tag:            v%s\n  then push branch + tag (kicks .github/workflows/release.yml)\n' \
       "$cur_file" "{{VERSION}}" "$cur_script" "{{VERSION}}" "{{VERSION}}" "{{VERSION}}"

# Bump version, commit, tag, push — tag push fires the GHA release workflow.
release VERSION:
    @just _release-validate "{{VERSION}}"
    @just _release-clean-tree
    @just _release-bump "{{VERSION}}"
    git add VERSION statusline.sh
    git commit -m "Release v{{VERSION}}"
    git tag -a "v{{VERSION}}" -m "v{{VERSION}}"
    git push
    git push origin "v{{VERSION}}"
    @echo
    @echo "pushed v{{VERSION}} — release workflow:"
    @echo "  https://github.com/securacore/kanagawa-statusline/actions/workflows/release.yml"

# ── private helpers (underscore-prefixed → hidden from `just --list`) ──

_release-validate VERSION:
    @if ! [[ "{{VERSION}}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then \
        echo "version must be plain semver (e.g. 0.1.0), got: {{VERSION}}" >&2; \
        exit 2; \
    fi
    @cur=$(tr -cd '0-9.' < VERSION); \
     newest=$(printf '%s\n%s\n' "$cur" "{{VERSION}}" | sort -V | tail -1); \
     if [ "$newest" != "{{VERSION}}" ] && [ "$cur" != "{{VERSION}}" ]; then \
        echo "{{VERSION}} is older than current $cur" >&2; \
        exit 1; \
     fi; \
     if [ "$cur" = "{{VERSION}}" ]; then \
        echo "{{VERSION}} matches current VERSION — nothing to bump" >&2; \
        exit 1; \
     fi

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

_release-bump VERSION:
    printf '%s\n' "{{VERSION}}" > VERSION
    @# Portable in-place edit — macOS sed and GNU sed disagree on -i.
    tmp=$(mktemp); \
    sed -E 's/^(KANAGAWA_STATUSLINE_VERSION=)"[^"]*"/\1"{{VERSION}}"/' statusline.sh > "$tmp"; \
    mv "$tmp" statusline.sh; \
    chmod +x statusline.sh
    @# Verify both bumps landed.
    @got=$(grep -E '^KANAGAWA_STATUSLINE_VERSION=' statusline.sh \
         | head -1 \
         | sed -E 's/^[^=]+="?([^"]*)"?[[:space:]]*$/\1/'); \
     if [ "$got" != "{{VERSION}}" ]; then \
        echo "failed to update KANAGAWA_STATUSLINE_VERSION (got: $got)" >&2; \
        exit 1; \
     fi
