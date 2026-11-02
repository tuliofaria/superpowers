# Pre-PR Checks from pstack Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Before every PR that finishing opens, run pstack's blast-radius and the project's `verify-<app>` skill, fix confirmed failures, and record both in the PR body.

**Architecture:** Three pstack skills copied and adapted into `skills/`. Two config keys, `blastRadius` and `verify`. A new procedure file, `finishing-a-development-branch/pre-pr-checks.md`, that finishing calls before the cross-provider review. Everything is Markdown skill text, plus one read-only Bash script. Tests are structural `grep` checks in the existing project-config test script.

**Tech Stack:** Markdown skills, Bash 3.2-compatible scripts (macOS `/bin/bash`), `git`, `gh`.

**Spec:** `docs/superpowers/specs/2026-11-02-pstack-pre-pr-checks-design.md`

## Global Constraints

- Upstream source: `https://github.com/cursor/plugins`, path `harness/pstack/claude-code/skills/`, pinned SHA `ae5650febf4320793844c12c4adaa937f417f8da`.
- License: MIT, "Copyright (c) 2026 Lauren Tan". Copy it verbatim to `docs/vendored/pstack/LICENSE`.
- New config keys: `blastRadius` and `verify`, values `true` | `false`, default `false`.
- Order on the PR path: green suite → blast radius → verify → cross-review → push → PR → watch.
- Fix loop: at most 2 fix rounds, then stop with no PR opened.
- Commit messages (exact): `fix: address pre-PR check findings`, `chore: add verify-<app> skill`, `fix: update verify-<app> skill`.
- Fork version after this work: `6.4.2-tf.2`, set with `scripts/bump-version.sh 6.4.2-tf.2`.
- Do not add the new skills to `.muse-plugin/plugin.json`. The fork's `sp` and `sp-init` skills aren't listed there either.
- Fetch upstream into a fresh `mktemp -d` directory. Never run anything from inside the clone.
- Structural test command: `bash tests/project-config/test-skill-structure.sh`. It passes when it prints `STATUS: PASSED`.
- `shellcheck` and `shfmt` are not installed on this machine. Where a step says to lint a script, run `bash -n <script>`. If `command -v shellcheck` succeeds, also run `scripts/lint-shell.sh <script>`; otherwise, report that ShellCheck was not run.

## Review Focus

1. **The app won't start for an environment reason** (missing secrets, DB down, port taken), not because of drift. Expected: stop and ask "fix the environment, or skip verification for this PR?", and never record a pass. Pinned in Task 5.
2. **The diff includes the freshly generated `verify-<app>` skill itself.** Expected: paths under that skill's directory are excluded from feature selection, so the first run doesn't "verify" its own harness. Pinned in Task 5.
3. **Evidence written inside the repo.** Expected: evidence is never `git add`-ed; a fix commit stages only source and test files. Pinned in Task 5.
4. **Only one key is on** (`verify` without `blastRadius`, or the reverse). Expected: the enabled step runs alone, and feature selection uses the diff only. Pinned in Task 5.
5. **The pinned SHA isn't reachable in a shallow clone.** Expected: `pstack-upstream-diff.sh` fetches the SHA explicitly and fails loudly if it can't, rather than diffing against the wrong base. Pinned in Task 3.

---

### Task 1: Vendor blast-radius + attribution

**Files:**
- Create: `skills/blast-radius/SKILL.md`
- Create: `docs/vendored/pstack/LICENSE`
- Create: `docs/vendored/pstack/README.md`
- Modify: `tests/project-config/test-skill-structure.sh` (new helpers, plus a `# --- vendored pstack ---` block before the final `if [[ "$FAILURES" ...`)

**Interfaces:**
- Produces: skill `superpowers:blast-radius`; helpers `forbid_text <file> <text>` (fails if present) and `require_order <file> <first> <second>` (fails unless the first occurrence of `<first>` is on an earlier line than the first occurrence of `<second>`); `docs/vendored/pstack/README.md` containing a line `Pinned SHA: ae5650febf4320793844c12c4adaa937f417f8da` that Task 3 parses, plus an `## Adaptations` section with one `### <skill>` subsection per vendored skill.

- [ ] **Step 1: Add helpers and failing tests.** Add `forbid_text` and `require_order` next to `require_text`, in the same `pass`/`fail` style. Add these checks:

```bash
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
```

- [ ] **Step 2: Run the tests and confirm they fail.** Run `bash tests/project-config/test-skill-structure.sh`. Expected: `[FAIL] missing: skills/blast-radius/SKILL.md` and `STATUS: FAILED`.

- [ ] **Step 3: Fetch upstream at the pinned SHA.** `SRC=$(mktemp -d)`, then `git clone -q https://github.com/cursor/plugins "$SRC/plugins"`, then `git -C "$SRC/plugins" checkout -q ae5650febf4320793844c12c4adaa937f417f8da`. Later tasks reuse `$SRC`. If it's gone, re-run this step.

- [ ] **Step 4: Write `skills/blast-radius/SKILL.md`** from `$SRC/plugins/harness/pstack/claude-code/skills/blast-radius/SKILL.md`, with exactly these edits:
  - Frontmatter becomes `name: blast-radius` and `description: "Use when a change is about to ship, or when asked what a change could break beyond the diff — finds breakage grep won't show and proves the one fact the change is safe because of by running real code."`. Remove the `disable-model-invocation` line.
  - Delete the paragraph that begins "Companion to `how` and `why`."
  - Step 1: replace "Use `why` step 2 to pull the PR and commits." with "Pull the commits with `git log <base>..HEAD`, and the PR with `gh pr view` when one already exists."
  - Step 4: delete the sentence "Same rules as `why`." and keep the rest.
  - Step 6: replace the whole step with "6. When `crossReview` is on, a second model reviews after this step; do not run another."
  - Closing paragraph: replace "Write it through `unslop`, cite real code" with "Cite real code".
  - Everything else stays verbatim.

- [ ] **Step 5: Write the attribution files.** Copy `$SRC/plugins/harness/pstack/claude-code/LICENSE` verbatim to `docs/vendored/pstack/LICENSE`. Write `docs/vendored/pstack/README.md` with these sections:
  - A title and one sentence saying these skills are adapted from pstack by Lauren Tan, under MIT.
  - `Upstream: https://github.com/cursor/plugins`, then `Path: harness/pstack/claude-code/skills/`, then `Pinned SHA: ae5650febf4320793844c12c4adaa937f417f8da (2026-10-31)`.
  - `## Updating`, saying to run `scripts/pstack-upstream-diff.sh`, port changes by hand, and bump the pinned SHA.
  - `## Adaptations`, with `### blast-radius` listing the Step 4 edits as bullets.

- [ ] **Step 6: Run the tests and confirm they pass.** Run `bash tests/project-config/test-skill-structure.sh`. Expected: `STATUS: PASSED`.

- [ ] **Step 7: Commit**

```bash
git add skills/blast-radius docs/vendored/pstack tests/project-config/test-skill-structure.sh
git commit -m "feat(skills): vendor pstack blast-radius"
```

### Task 2: Vendor the verification skills

**Files:**
- Create: `skills/create-verification-skill/SKILL.md`
- Create: `skills/create-verification-skill/references/feature-map-example/{README.md,create-note.md,search.md}`
- Create: `skills/maintain-verification-skill/SKILL.md`
- Modify: `docs/vendored/pstack/README.md` (two `###` subsections)
- Modify: `tests/project-config/test-skill-structure.sh` (the vendored pstack block)

**Interfaces:**
- Consumes: `forbid_text`, `$SRC` and the README's `## Adaptations` section from Task 1.
- Produces: skills `superpowers:create-verification-skill` (model-invocable) and `superpowers:maintain-verification-skill` (manual only). Generated project skills live at `.claude/skills/verify-<app>/`.

- [ ] **Step 1: Add the failing tests.**

```bash
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
```

- [ ] **Step 2: Run the tests and confirm they fail.** Run `bash tests/project-config/test-skill-structure.sh`. Expected: `[FAIL] missing: skills/create-verification-skill/SKILL.md`.

- [ ] **Step 3: Write `skills/create-verification-skill/`** from upstream:
  - Copy the three reference files verbatim.
  - In `SKILL.md`, remove `disable-model-invocation`.
  - Replace the "In Claude Code, read [the Claude Code adapter]…" paragraph with: "Ask your human partner questions with `AskUserQuestion` (plain text when it is absent). A read-only helper is an `Explore` subagent whose brief says \"do not edit files\"."
  - Replace both `.cursor/skills/verify-<app>/` with `.claude/skills/verify-<app>/`.
  - In step 5, change `/maintain-verification-skill` to `/superpowers:maintain-verification-skill`.

- [ ] **Step 4: Write `skills/maintain-verification-skill/SKILL.md`** from upstream:
  - Keep `disable-model-invocation: true`.
  - Delete the adapter paragraph.
  - Change `.cursor/skills/verify-*/` to `.claude/skills/verify-*/`.
  - In step 2, change "One read-only subagent per feature file" to "One `Explore` subagent per feature file, briefed \"do not edit files\"; check `git status` afterward".

- [ ] **Step 5: Document the adaptations.** Add `### create-verification-skill` and `### maintain-verification-skill` to the vendored README, listing the Step 3 and Step 4 edits.

- [ ] **Step 6: Run the tests and confirm they pass.** Expected: `STATUS: PASSED`.

- [ ] **Step 7: Commit**

```bash
git add skills/create-verification-skill skills/maintain-verification-skill docs/vendored/pstack tests/project-config/test-skill-structure.sh
git commit -m "feat(skills): vendor pstack verification skills"
```

### Task 3: Upstream diff script

**Files:**
- Create: `scripts/pstack-upstream-diff.sh` (executable)
- Modify: `tests/project-config/test-skill-structure.sh`

**Interfaces:**
- Consumes: the `Pinned SHA: <sha>` line in `docs/vendored/pstack/README.md`.
- Produces: `scripts/pstack-upstream-diff.sh [ref]` (default `ref` is `origin/main`). It prints `git diff <pinned>..<ref> -- <the three skill dirs>` and exits 0. It exits non-zero with a message on stderr when the README has no pinned SHA or the SHA can't be fetched.

- [ ] **Step 1: Add the failing tests.** Check that the file exists and is executable (`[ -x ... ]` with `pass`/`fail`). Add `require_text` for `mktemp -d`, `Pinned SHA:`, and `trap`. Then add this behavioral check, which runs the script against a temp README with no SHA and expects a non-zero exit:

```bash
tmp_readme=$(mktemp)
echo "no sha here" > "$tmp_readme"
if PSTACK_README="$tmp_readme" "$REPO_ROOT/scripts/pstack-upstream-diff.sh" >/dev/null 2>&1; then
    fail "pstack-upstream-diff.sh exits non-zero without a pinned SHA"
else
    pass "pstack-upstream-diff.sh exits non-zero without a pinned SHA"
fi
rm -f "$tmp_readme"
```

- [ ] **Step 2: Run the tests and confirm they fail.** Expected: `[FAIL] missing: scripts/pstack-upstream-diff.sh`.

- [ ] **Step 3: Implement the script.**
  - Use `set -euo pipefail`, and keep it Bash 3.2-compatible.
  - The README path defaults to `$REPO_ROOT/docs/vendored/pstack/README.md` and can be overridden with `PSTACK_README`.
  - Parse and validate the SHA **before** any network call, so the no-SHA test runs offline.
  - Parse the SHA with `sed -n 's/^Pinned SHA: \([0-9a-f]\{40\}\).*/\1/p'`.
  - Clone with `git clone -q --filter=blob:none https://github.com/cursor/plugins "$tmp/plugins"` into `tmp=$(mktemp -d)`, with `trap 'rm -rf "$tmp"' EXIT`.
  - Fail loudly if `git -C ... cat-file -e "$sha^{commit}"` fails. That covers Review Focus #5.
  - Diff these three paths: `harness/pstack/claude-code/skills/{blast-radius,create-verification-skill,maintain-verification-skill}`.
  - Write nothing outside `$tmp`.

- [ ] **Step 4: Run the tests and lint.** Run `chmod +x`, then the structural tests (expected `STATUS: PASSED`), then `bash -n scripts/pstack-upstream-diff.sh` (and lint per Global Constraints). Then run `scripts/pstack-upstream-diff.sh` once for real. Expected: exit 0. The output is either empty or shows upstream changes since the pinned SHA.

- [ ] **Step 5: Commit**

```bash
git add scripts/pstack-upstream-diff.sh tests/project-config/test-skill-structure.sh
git commit -m "feat(scripts): show pstack upstream changes since the pinned SHA"
```

### Task 4: Config keys

**Files:**
- Modify: `skills/sp-init/project-config.md` (JSON example at lines 7-13, plus the key table after line 22)
- Modify: `skills/sp-init/SKILL.md` (the Step 2 list, lines 19-24)
- Modify: `tests/project-config/test-skill-structure.sh`

**Interfaces:**
- Produces: config keys `blastRadius` and `verify`, which Task 5 reads via "Resolve the effective config".

- [ ] **Step 1: Add the failing tests.**

```bash
require_text "skills/sp-init/project-config.md" '"blastRadius": false'
require_text "skills/sp-init/project-config.md" '"verify": false'
require_text "skills/sp-init/project-config.md" '| `blastRadius` |'
require_text "skills/sp-init/project-config.md" '| `verify` |'
require_text "skills/sp-init/SKILL.md" '`blastRadius` — run blast-radius before every PR?'
require_text "skills/sp-init/SKILL.md" "\`verify\` — verify the real app (the project's \`verify-<app>\` skill) before every PR?"
require_order "skills/sp-init/SKILL.md" '`crossReview` —' '`blastRadius` —'
require_order "skills/sp-init/SKILL.md" '`verify` —' '`execution` —'
```

- [ ] **Step 2: Run the tests and confirm they fail.** Expected: `[FAIL] ... lacks: "blastRadius": false`.

- [ ] **Step 3: Edit `project-config.md`.**
  - Add `"blastRadius": false` and `"verify": false` to the JSON example.
  - Add the two table rows using the spec's wording, Component 2:
    - `blastRadius`: "`true`: before any PR push, finishing runs `superpowers:blast-radius` on `<base>..HEAD`."
    - `verify`: "`true`: before any PR push, finishing runs the project's `verify-<app>` skill on the features the diff touches; asks whether to generate one when none exists."
  - Both rows link to `[pre-pr-checks.md](../finishing-a-development-branch/pre-pr-checks.md)`.

- [ ] **Step 4: Edit `sp-init/SKILL.md`.** Insert the two questions as items 4 and 5 (text exactly as in the test) and renumber `execution`, `watchPr` and Destination to 6–8. Step 3 ("Check the tools") gets no new check.

- [ ] **Step 5: Run the tests and confirm they pass.** Expected: `STATUS: PASSED`.

- [ ] **Step 6: Commit**

```bash
git add skills/sp-init tests/project-config/test-skill-structure.sh
git commit -m "feat(config): blastRadius and verify keys and /sp-init questions"
```

### Task 5: Pre-PR checks in finishing

**Files:**
- Create: `skills/finishing-a-development-branch/pre-pr-checks.md`
- Modify: `skills/finishing-a-development-branch/SKILL.md` (Step 2b; Option 2 at line 141, before the cross-review paragraph at line 143; Common Rationalizations table ending at line 266)
- Modify: `tests/project-config/test-skill-structure.sh`

**Interfaces:**
- Consumes: `superpowers:blast-radius` (Task 1); `superpowers:create-verification-skill` and `.claude/skills/verify-<app>/` (Task 2); `blastRadius`/`verify` (Task 4).
- Produces: `pre-pr-checks.md`, with input `<base-branch>` and output PR-body sections `## Blast radius` and `## Verification (verify-<app>)`.

- [ ] **Step 1: Add the failing tests.**

```bash
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
```

- [ ] **Step 2: Run the tests and confirm they fail.** Expected: `[FAIL] missing: .../pre-pr-checks.md`.

- [ ] **Step 3: Write `pre-pr-checks.md`.**
  - **Structure.** Use the spec's Component 3 Step A–D and "Interaction with pr-watch" content under the tested headings. The question, the commit messages, the PR-body template and the `Not run — <reason>.` form go in verbatim from the spec.
  - **Opening.** One line explaining the file: it's called by finishing when `blastRadius` or `verify` is `true`, and its input is `<base-branch>`.
  - **Single key** (Review Focus #4). Add: "When only one of the two keys is `true`, run only that step; feature selection then uses the diff alone."
  - **Environment failures** (Review Focus #1). In Step B "Classify", add a third class, **Environment**: launch or doctor fails for a reason that is neither drift nor product, such as missing secrets, a dependency service that is down, or a port in use. Stop and ask "Verification can't start (<reason>) — fix the environment, or skip verification for this PR?". Never record a pass. A skip reads `Not run — <reason>; skipped by <human partner>.`
  - **Excluded paths** (Review Focus #2). In "Select features", add: "Exclude the verification skill's own directory from feature selection."
  - **Evidence** (Review Focus #3). In Step C, add: "Never `git add` evidence; stage only the source and test files the fix touched."

- [ ] **Step 4: Edit finishing `SKILL.md`.**
  - In Step 2b, change "Three keys matter here" to "Five keys matter here" and add bullets for `blastRadius` and `verify`.
  - In Option 2, before the `crossReview` paragraph, add: "**If the project config sets `blastRadius: true` or `verify: true`:** first follow [pre-pr-checks.md](pre-pr-checks.md) with `<base-branch>`, and include its sections in the PR body. This applies to the detached-HEAD PR option too, and whether you got here from the menu or from `finish: \"pr\"`."
  - Append three rows to Common Rationalizations:
    - "The tests pass, so verification is redundant" → "Tests prove functions; verification proves the app does what a user expects. With `verify`, run it."
    - "This risk is probably fine" → "An unproven risk goes into the PR body as unproven. Never list it as cleared."
    - "The seed data lacks this case — I'll simplify the journey so it passes" → "Never weaken a journey to make it pass. Report the failure; the reason goes in that feature's Gotchas."

- [ ] **Step 5: Run the tests and confirm they pass.** Run `bash tests/project-config/test-skill-structure.sh`. Expected: `STATUS: PASSED`.

- [ ] **Step 6: Commit**

```bash
git add skills/finishing-a-development-branch tests/project-config/test-skill-structure.sh
git commit -m "feat(finishing): run blast-radius and verify before the PR"
```

### Task 6: README, version, global config

**Files:**
- Modify: `README.md` (fork section, lines 308-342)
- Modify: the 11 manifest files, via `scripts/bump-version.sh`
- Modify (outside the repo, not committed): `~/.config/superpowers/config.json`

**Interfaces:**
- Consumes: everything above.

- [ ] **Step 0: Add the failing tests.** Add `require_text "README.md" "blastRadius"`, `require_text "README.md" "verify-<app>"` and `require_text "README.md" "docs/vendored/pstack/"`. Run the suite. Expected: `[FAIL] README.md lacks: blastRadius`.

- [ ] **Step 1: Edit the README.**
  - Retitle the section `## Fork: Project Config, /sp, Cross-Provider Review, and Pre-PR Checks` and update the matching TOC link at line 26.
  - Add `"blastRadius": true, "verify": true` to the example JSON.
  - Add two bullets:
    - **`blastRadius: true`**: before every PR, finds what the change could break beyond the diff and proves the fact it's safe because of.
    - **`verify: true`**: before every PR, drives the real app through the project's `verify-<app>` skill, offers to generate one with `/superpowers:create-verification-skill`, and maintains it with `/superpowers:maintain-verification-skill`.
  - Add one credit line: "blast-radius and the verification skills are adapted from [pstack](https://github.com/cursor/plugins/tree/main/pstack) by Lauren Tan (MIT) — see `docs/vendored/pstack/`."

- [ ] **Step 2: Bump the version.** Run `scripts/bump-version.sh 6.4.2-tf.2`, then `scripts/bump-version.sh --check`. Expected: every declared file reports `6.4.2-tf.2`, with no drift.

- [ ] **Step 3: Run the full structural suite.** Run `bash tests/project-config/test-skill-structure.sh`. Expected: `STATUS: PASSED`.

- [ ] **Step 4: Commit**

```bash
git add README.md .claude-plugin .codex-plugin .cursor-plugin .devin-plugin .hermes-plugin .kimi-plugin .muse-plugin gemini-extension.json package.json
git commit -m "chore: fork version 6.4.2-tf.2"
```

(Commit only the files `bump-version.sh` changed. Check with `git status` first.)

- [ ] **Step 5: Update the global config** (outside the repo, no commit). Add `"blastRadius": true` and `"verify": true` to `~/.config/superpowers/config.json`, keeping the existing keys. Validate it with `python3 -c "import json,os;print(json.load(open(os.path.expanduser('~/.config/superpowers/config.json'))))"`.

### Task 7: Live acceptance (manual, coordinator only)

Not a subagent task. It needs Tulio's choice of project and real PRs.

- [ ] **Step 1: Pick the project.** Ask Tulio which project to use: one with an app to launch and no `verify-<app>` skill yet. The fork must be installed at `6.4.2-tf.2` (`claude plugin update`), and the session must be fresh in that project.
- [ ] **Step 2: Run a small real change there through `/sp`** up to finishing. Expected: the "Generate one now … or skip verification for this PR?" question appears.
- [ ] **Step 3: Check the opened PR.** Expected: `## Blast radius` (a safety fact with a proof level) and `## Verification (verify-<app>)` (features and local evidence paths), both with real content. The watch phase also runs; this is the first live `watchPr` run, so note anything that misbehaves.
- [ ] **Step 4: Report** to Tulio what passed and failed, with the PR URL. File fixes as follow-up tasks on this branch, not silently.
