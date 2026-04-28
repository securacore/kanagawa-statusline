#!/usr/bin/env bash
# scripts/release.sh — bump version, commit, tag.
#
# Maintainer-only helper. Not shipped to end users (lives outside bin/, which
# install.sh fetches verbatim).
#
# usage:
#   scripts/release.sh 0.1.0          # bump + commit + tag (no push)
#   scripts/release.sh 0.1.0 --push   # also push branch + tag
#
# The release workflow (.github/workflows/release.yml) fires on the pushed
# tag, validates the bump matches VERSION + the embedded constant, and
# publishes the GitHub Release.

set -euo pipefail

[ $# -ge 1 ] || { echo "usage: $0 <version> [--push]" >&2; exit 2; }
new=$1
push=0
[ "${2:-}" = "--push" ] && push=1

# Reject leading 'v' so callers don't accidentally tag "vv0.1.0".
[[ "$new" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
  || { echo "version must be plain semver (e.g. 0.1.0), got: $new" >&2; exit 2; }

repo_root=$(cd "$(dirname "$0")/.." && pwd)
cd "$repo_root"

# Refuse to release with a dirty tree — easy way to ship the wrong contents.
if [ -n "$(git status --porcelain)" ]; then
  echo "working tree is dirty; commit or stash first" >&2
  exit 1
fi

cur_file=$(tr -cd '0-9.' < VERSION)
cur_script=$(grep -E '^KANAGAWA_STATUSLINE_VERSION=' statusline.sh \
           | head -1 \
           | sed -E 's/^[^=]+="?([^"]*)"?[[:space:]]*$/\1/' \
           | tr -cd '0-9.')

echo "current: VERSION=$cur_file  script=$cur_script  →  $new"

if [ "$new" = "$cur_file" ] && [ "$new" = "$cur_script" ]; then
  echo "no change" >&2
  exit 0
fi

# Reject downgrades — guards against a typo undoing a release.
newest=$(printf '%s\n%s\n' "$cur_file" "$new" | sort -V | tail -1)
[ "$newest" = "$new" ] || { echo "$new is older than current $cur_file" >&2; exit 1; }

printf '%s\n' "$new" > VERSION

# In-place bump of the embedded constant. macOS sed needs `-i ''`; GNU sed
# accepts `-i` alone — use a portable two-step.
tmp=$(mktemp)
sed -E "s/^(KANAGAWA_STATUSLINE_VERSION=)\"[^\"]*\"/\1\"$new\"/" statusline.sh > "$tmp"
mv "$tmp" statusline.sh
chmod +x statusline.sh

# Verify the constant landed where we expect.
got=$(grep -E '^KANAGAWA_STATUSLINE_VERSION=' statusline.sh \
    | head -1 \
    | sed -E 's/^[^=]+="?([^"]*)"?[[:space:]]*$/\1/')
[ "$got" = "$new" ] || { echo "failed to update KANAGAWA_STATUSLINE_VERSION (got: $got)" >&2; exit 1; }

git add VERSION statusline.sh
git commit -m "Release v$new"
git tag -a "v$new" -m "v$new"

if [ "$push" -eq 1 ]; then
  git push
  git push origin "v$new"
  echo "pushed v$new — release workflow should publish the GitHub Release shortly"
else
  echo "tagged v$new locally; push with: git push && git push origin v$new"
fi
