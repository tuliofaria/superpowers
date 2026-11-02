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

forbid_text() {
    if [ -f "$REPO_ROOT/$1" ] && ! grep -qF -- "$2" "$REPO_ROOT/$1"; then
        pass "$1 omits: $2"
    else
        fail "$1 has or is missing: $2"
    fi
}

require_order() {
    local a b
    a=$(grep -nF -- "$2" "$REPO_ROOT/$1" 2>/dev/null | head -1 | cut -d: -f1 || true)
    b=$(grep -nF -- "$3" "$REPO_ROOT/$1" 2>/dev/null | head -1 | cut -d: -f1 || true)
    if [ -n "$a" ] && [ -n "$b" ] && [ "$a" -lt "$b" ]; then
        pass "$1 orders: $2 before $3"
    else
        fail "$1 order wrong or missing: $2 before $3"
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
require_text "skills/sp-init/project-config.md" '"watchPr": false'
require_text "skills/sp-init/project-config.md" '| `watchPr` |'
require_text "skills/sp-init/SKILL.md" '`watchPr`'
require_text "skills/sp-init/SKILL.md" "gh auth status"
require_text "skills/sp-init/SKILL.md" ".gitignore"
require_text "skills/sp-init/SKILL.md" "git check-ignore -q .superpowers/config.local.json"
require_text "skills/sp-init/SKILL.md" "git check-ignore -q .superpowers.json"
require_text "skills/sp-init/SKILL.md" "Never commit"
require_text "skills/sp-init/project-config.md" '"blastRadius": false'
require_text "skills/sp-init/project-config.md" '"verify": false'
require_text "skills/sp-init/project-config.md" '| `blastRadius` |'
require_text "skills/sp-init/project-config.md" '| `verify` |'
require_text "skills/sp-init/SKILL.md" '`blastRadius` — run blast-radius before every PR?'
require_text "skills/sp-init/SKILL.md" "\`verify\` — verify the real app (the project's \`verify-<app>\` skill) before every PR?"
require_order "skills/sp-init/SKILL.md" '`crossReview` —' '`blastRadius` —'
require_order "skills/sp-init/SKILL.md" '`verify` —' '`execution` —'

# --- sp router ---
require_file "skills/sp/SKILL.md"
require_text "skills/sp/SKILL.md" "name: sp"
require_text "skills/sp/SKILL.md" "disable-model-invocation: true"
require_text "skills/sp/SKILL.md" '$ARGUMENTS'
require_text "skills/sp/SKILL.md" "superpowers:using-superpowers"
require_text "skills/sp/SKILL.md" "superpowers:systematic-debugging"
require_text "skills/sp/SKILL.md" "superpowers:brainstorming"
require_text "skills/sp/SKILL.md" "superpowers:subagent-driven-development"
require_text "skills/sp/SKILL.md" "superpowers:executing-plans"
require_text "skills/sp/SKILL.md" "../sp-init/project-config.md"
require_text "skills/sp/SKILL.md" "superpowers:finishing-a-development-branch"
require_text "skills/sp/SKILL.md" "rest of this session"
require_text "skills/sp/SKILL.md" "it wins over the config"

# --- cross-provider review ---
F="skills/requesting-code-review/cross-provider-review.md"
require_file "$F"
require_text "$F" "codex review --base"
require_text "$F" "claude -p"
require_text "$F" "code-reviewer.md"
require_text "$F" "superpowers:receiving-code-review"
require_text "$F" "No round 3"
require_text "$F" "## Cross-provider review ("
require_text "$F" "Never skip the review silently"
require_text "$F" "escalated"
require_text "$F" "[BASE_SHA]"
require_text "$F" "exit="

# --- finishing honors config ---
F="skills/finishing-a-development-branch/SKILL.md"
require_text "$F" "## Step 2b: Load Project Config"
require_text "$F" "../sp-init/project-config.md"
require_text "$F" 'finish: "pr"'
require_text "$F" "../requesting-code-review/cross-provider-review.md"
require_text "$F" "Config says \`pr\`, but this one feels like a local merge"
require_text "$F" "\`watchPr\`"
require_text "$F" "[pr-watch.md](pr-watch.md)"
require_text "$F" "Checks are still running — I'll report the URL and stop"
require_text "README.md" "watchPr"

# --- writing-plans honors execution ---
F="skills/writing-plans/SKILL.md"
require_text "$F" "../sp-init/project-config.md"
require_text "$F" "Project config sets \`execution: <value>\`"
require_text "$F" "stated explicitly in the conversation wins over the config"

# --- PR watch ---
F="skills/finishing-a-development-branch/pr-watch.md"
require_file "$F"
require_text "$F" "gh auth status"
require_text "$F" "Before the push, record the check names on the PR"
require_text "$F" "each name you recorded before the push"
require_text "$F" "gh pr checks"
require_text "$F" "rate limited by coderabbit.ai"
require_text "$F" "review in progress by coderabbit.ai"
require_text "$F" "No actionable comments"
require_text "$F" "headCommitId"
require_text "$F" "@coderabbitai review"
require_text "$F" "Run on-demand review"
require_text "$F" "by Grok PR Reviewer"
require_text "$F" "does not end with \`by Grok PR Reviewer\`"
require_text "$F" "superpowers:receiving-code-review"
require_text "$F" "superpowers:systematic-debugging"
require_text "$F" "gh run rerun"
require_text "$F" "3 rounds"
require_text "$F" "2 re-triggers"
require_text "$F" "20 minutes"
require_text "$F" "no push on a red suite"
require_text "$F" "## PR watch"
require_text "$F" "leave the rest of the body untouched"
require_text "$F" "never force-push"
# fix round and final-review wave
require_text "$F" "**Register first.**"
require_text "$F" "no checks reported"
require_text "$F" "CodeRabbit's own status, always green, is"
require_text "$F" "until that check is no longer"
require_text "$F" "reads \"Review finished\""
require_text "$F" "Act only on a block whose \`updated_at\` is after your last"
require_text "$F" "**Otherwise, stop.**"
require_text "$F" "Outside diff range comments"
require_text "$F" "\"Nitpick comments\""
require_text "$F" "60 minutes"
require_text "$F" "headRefName"
require_text "$F" "git push origin HEAD:<headRefName>"
require_text "$F" "post no \"Fixed in\" reply"
require_text "$F" "Only after the push succeeds"
require_text "$F" "\`coderabbitai\` (GraphQL)"
require_text "$F" "-F body=@<file>"
require_text "$F" "Ours are the replies you posted in"
require_text "$F" "compare \`date -u\` with the target time"
require_text "$F" "<what is left, and why>"

# --- vendored pstack ---
F="skills/blast-radius/SKILL.md"
require_file "$F"
require_text "$F" "name: blast-radius"
require_text "$F" "### How sure are you"
require_text "$F" "git log <base>..HEAD"
require_text "$F" "When \`crossReview\` is on, a second model reviews after this step; do not run another."
forbid_text "$F" "disable-model-invocation"
for t in ".cursor/skills" "\`how\`" "\`why\`" "unslop" "arena"; do forbid_text "$F" "$t"; done
require_file "docs/vendored/pstack/LICENSE"
require_text "docs/vendored/pstack/LICENSE" "Lauren Tan"
require_text "docs/vendored/pstack/README.md" "Pinned SHA: ae5650febf4320793844c12c4adaa937f417f8da"
require_text "docs/vendored/pstack/README.md" "### blast-radius"
F="skills/create-verification-skill/SKILL.md"
require_file "$F"
require_text "$F" "name: create-verification-skill"
require_text "$F" ".claude/skills/verify-<app>/"
require_text "$F" "AskUserQuestion"
require_text "$F" "/superpowers:maintain-verification-skill"
forbid_text "$F" "disable-model-invocation"
for r in README.md create-note.md search.md; do
    require_file "skills/create-verification-skill/references/feature-map-example/$r"
done
F="skills/maintain-verification-skill/SKILL.md"
require_file "$F"
require_text "$F" "disable-model-invocation: true"
require_text "$F" ".claude/skills/verify-*/"
require_text "$F" "\`Explore\` subagent"
for F in skills/create-verification-skill/SKILL.md skills/maintain-verification-skill/SKILL.md; do
    for t in ".cursor/skills" "Claude Code adapter" "docs/harness"; do forbid_text "$F" "$t"; done
done
require_text "docs/vendored/pstack/README.md" "### create-verification-skill"
require_text "docs/vendored/pstack/README.md" "### maintain-verification-skill"
F="scripts/pstack-upstream-diff.sh"
require_file "$F"
if [[ -x "$REPO_ROOT/$F" ]]; then
    pass "$F is executable"
else
    fail "$F is not executable"
fi
require_text "$F" "mktemp -d"
require_text "$F" "Pinned SHA:"
require_text "$F" "trap"
tmp_readme=$(mktemp)
echo "no sha here" > "$tmp_readme"
if PSTACK_README="$tmp_readme" "$REPO_ROOT/scripts/pstack-upstream-diff.sh" >/dev/null 2>&1; then
    fail "pstack-upstream-diff.sh exits non-zero without a pinned SHA"
else
    pass "pstack-upstream-diff.sh exits non-zero without a pinned SHA"
fi
rm -f "$tmp_readme"

# --- pre-PR checks ---
F="skills/finishing-a-development-branch/pre-pr-checks.md"
require_file "$F"
for t in "## Step A: Blast radius" "## Step B: Verify" "## Step C: Fix loop" "## Step D: PR body" \
         "## Interaction with pr-watch" "superpowers:blast-radius" "superpowers:create-verification-skill" \
         ".claude/skills/" ".agents/skills/" ".cursor/skills/" \
         "Generate one now (create-verification-skill, once per repo) or skip verification for this PR?" \
         "chore: add verify-<app> skill" "fix: update verify-<app> skill" "fix: address pre-PR check findings" \
         "At most 2 fix rounds" "No PR is opened" "Never edit product code for drift" \
         "fix the environment, or skip verification for this PR?" \
         "Exclude the verification skill's own directory" "Never \`git add\` evidence" \
         "When only one of the two keys is \`true\`" \
         "## Verification (verify-<app>)" "Not run — " "do not re-run pre-PR checks"; do
    require_text "$F" "$t"
done
F="skills/finishing-a-development-branch/SKILL.md"
require_text "$F" "[pre-pr-checks.md](pre-pr-checks.md)"
require_text "$F" "\`blastRadius\`"
require_order "$F" "[pre-pr-checks.md](pre-pr-checks.md)" "../requesting-code-review/cross-provider-review.md"
require_text "$F" "The tests pass, so verification is redundant"
require_text "$F" "This risk is probably fine"
require_text "$F" "I'll simplify the journey so it passes"

if [[ "$FAILURES" -gt 0 ]]; then
    echo "STATUS: FAILED ($FAILURES failure(s))"
    exit 1
fi
echo "STATUS: PASSED"
