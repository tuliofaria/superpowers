# Vendored pstack skills

These skills are adapted from pstack by Lauren Tan, used under the MIT license (see `LICENSE` in this directory; each vendored skill directory carries a copy, because Codex packaging ships `skills/` but not `docs/`).

Upstream: https://github.com/cursor/plugins
Path: harness/pstack/claude-code/skills/
Pinned SHA: ae5650febf4320793844c12c4adaa937f417f8da (2026-10-31)

## Updating

Run `scripts/pstack-upstream-diff.sh` to see what changed upstream since the pinned SHA. Port the changes by hand, then bump the pinned SHA above.

## Adaptations

### blast-radius

- Frontmatter: `description` rewritten as a "Use when..." trigger, and `disable-model-invocation` removed so the skill can be invoked by the model.
- Removed the paragraph that positioned it as a companion to the upstream `how` and `why` skills.
- Step 1: the pointer to `why` step 2 became `git log <base>..HEAD` and `gh pr view`.
- Step 4: removed the "Same rules as `why`." sentence.
- Step 6: the `arena` instruction became "When `crossReview` is on, a second model reviews after this step; do not run another."
- Closing paragraph: dropped the `unslop` reference.

### create-verification-skill

- Frontmatter: removed `disable-model-invocation` so the skill can be invoked by the model.
- Replaced the "In Claude Code, read the Claude Code adapter" paragraph with a note to ask questions with `AskUserQuestion` and to use an `Explore` subagent (brief: "do not edit files") for read-only help.
- Generated skills live at `.claude/skills/verify-<app>/` instead of `.cursor/skills/verify-<app>/` (all three mentions).
- Step 5: `/maintain-verification-skill` became `/superpowers:maintain-verification-skill`.
- `references/feature-map-example/` is copied unchanged.

### maintain-verification-skill

- Kept `disable-model-invocation: true`; the skill stays manual-only.
- Deleted the "In Claude Code, read the Claude Code adapter" paragraph.
- Step 0: `.cursor/skills/verify-*/` became `.claude/skills/verify-*/`.
- Step 0 and the intro paragraph: `/create-verification-skill` became `/superpowers:create-verification-skill`.
- Step 2: "One read-only subagent per feature file" became "One `Explore` subagent per feature file, launched concurrently and briefed "do not edit files"; check `git status` afterward".
