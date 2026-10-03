#!/usr/bin/env bash
# Structural checks for the fork's project-config skills.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
FAILURES=0

pass() { echo "  [PASS] $1"; }
fail() { echo "  [FAIL] $1"; FAILURES=$((FAILURES + 1)); }

require_file() {
    if [ -f "$REPO_ROOT/$1" ]; then pass "exists: $1"; else fail "missing: $1"; fi
}

require_text() {
    if [ -f "$REPO_ROOT/$1" ] && grep -qF -- "$2" "$REPO_ROOT/$1"; then
        pass "$1 contains: $2"
    else
        fail "$1 lacks: $2"
    fi
}

echo "Project config skill structure"

# --- sp-init + project-config reference ---
require_file "skills/sp-init/project-config.md"
require_text "skills/sp-init/project-config.md" "## Resolve the effective config"
require_text "skills/sp-init/project-config.md" ".superpowers/config.local.json"
require_text "skills/sp-init/project-config.md" "--git-common-dir"
require_text "skills/sp-init/project-config.md" "~/.config/superpowers/config.json"
require_file "skills/sp-init/SKILL.md"
require_text "skills/sp-init/SKILL.md" "name: sp-init"
require_text "skills/sp-init/SKILL.md" "disable-model-invocation: true"
require_text "skills/sp-init/SKILL.md" "project-config.md"
require_text "skills/sp-init/SKILL.md" "codex login status"
require_text "skills/sp-init/SKILL.md" "\`execution\`"
require_text "skills/sp-init/project-config.md" '"execution": "ask"'
require_text "skills/sp-init/SKILL.md" ".gitignore"
require_text "skills/sp-init/SKILL.md" "git check-ignore -q .superpowers/config.local.json"
require_text "skills/sp-init/SKILL.md" "git check-ignore -q .superpowers.json"
require_text "skills/sp-init/SKILL.md" "Never commit"

if [[ "$FAILURES" -gt 0 ]]; then
    echo "STATUS: FAILED ($FAILURES failure(s))"
    exit 1
fi
echo "STATUS: PASSED"
