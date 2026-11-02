#!/usr/bin/env bash
#
# pstack-upstream-diff.sh — show what changed upstream in the vendored pstack
# skills since the pinned SHA, so the changes can be ported by hand.
# Read-only: clones into a temp dir and writes nothing else.
#
# Usage:
#   pstack-upstream-diff.sh [ref]   Diff pinned SHA..ref (default: origin/main)
#
# Environment:
#   PSTACK_README   Override the README holding the "Pinned SHA:" line
#                   (default: docs/vendored/pstack/README.md)
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
README="${PSTACK_README:-$REPO_ROOT/docs/vendored/pstack/README.md}"
UPSTREAM_URL="https://github.com/cursor/plugins"
REF="${1:-origin/main}"
SKILL_PATHS=(
  harness/pstack/claude-code/skills/blast-radius
  harness/pstack/claude-code/skills/create-verification-skill
  harness/pstack/claude-code/skills/maintain-verification-skill
)

if [[ ! -f "$README" ]]; then
  echo "error: README not found at $README" >&2
  exit 1
fi

# Parse and validate the pinned SHA before touching the network.
sha=$(sed -n 's/^Pinned SHA: \([0-9a-f]\{40\}\).*/\1/p' "$README" | head -n 1)
if [[ -z "$sha" ]]; then
  echo "error: no 'Pinned SHA: <40-hex>' line found in $README" >&2
  exit 1
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

git clone -q --filter=blob:none "$UPSTREAM_URL" "$tmp/plugins"

# A shallow/filtered clone may not have the pinned commit reachable; try once.
if ! git -C "$tmp/plugins" cat-file -e "$sha^{commit}" 2>/dev/null; then
  git -C "$tmp/plugins" fetch -q origin "$sha" 2>/dev/null || true
fi
if ! git -C "$tmp/plugins" cat-file -e "$sha^{commit}" 2>/dev/null; then
  echo "error: pinned SHA $sha is not available from $UPSTREAM_URL" >&2
  exit 1
fi

if ! git -C "$tmp/plugins" rev-parse --verify -q "$REF^{commit}" >/dev/null; then
  echo "error: ref '$REF' not found in $UPSTREAM_URL" >&2
  exit 1
fi

git -C "$tmp/plugins" --no-pager diff "$sha..$REF" -- "${SKILL_PATHS[@]}"
