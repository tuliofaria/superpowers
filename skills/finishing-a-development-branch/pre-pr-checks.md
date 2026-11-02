# Pre-PR Checks

Before a PR is pushed, find what the change could break, prove the
features it touches still work in the running app, fix what is proven
broken, and record the outcome in the PR body. Called by
`finishing-a-development-branch` when the project config sets
`blastRadius: true` or `verify: true`. Input: `<base-branch>`.

Run Step A if `blastRadius` is `true`, then Step B if `verify` is `true`.
When only one of the two keys is `true`, run only that step; feature
selection then uses the diff alone. Run every enabled step to completion
before fixing anything: record blocking findings as you go. Then go to
Step C if any finding is blocking, otherwise to Step D.

A skip your human partner chose holds for the rest of this run: when a
later pass re-runs Step B, do not ask about that feature or environment
problem again, and do not retry a drift fix for it.

**Commits.** This file makes three kinds of commit:
`chore: add verify-<app> skill`, `fix: update verify-<app> skill`, and
`fix: address pre-PR check findings`. Never `git add` evidence in any of
them, even when it lives inside the skill directory. Stage by explicit
path only the files the commit is about: the generated or fixed skill
files, or the source and test files the fix touched.

## Step A: Blast radius

Follow `superpowers:blast-radius` on `<base-branch>..HEAD`.

- **Blocking:** a risk *confirmed* at step 4 or 5 of its "How sure are
  you" ladder — a script, test, or repro shows the breakage. Record it
  and continue to Step B; Step C fixes it.
- **Not blocking:** risks not proven, and an unproven safety fact. They
  go into the PR body as unproven. Never list them as cleared.
- Note every feature the writeup names as possibly affected; Step B runs
  those too.

## Step B: Verify

1. **Locate.** Look for `verify-*` directories in `.claude/skills/`,
   `.agents/skills/`, and `.cursor/skills/` at the repo root.
   - More than one: ask your human partner which to use.
   - None: ask —

     > This repo has no verification skill. Generate one now (create-verification-skill, once per repo) or skip verification for this PR?

     Generate → follow `superpowers:create-verification-skill`. During
     this run it edits only `.claude/skills/verify-<app>/`; anything else
     that fails is classified under item 4 (Environment or Product
     failure), never fixed by the generator. Then commit its output
     alone: `chore: add verify-<app> skill`. If `git add` refuses because
     the repo ignores `.claude/`, report it and ask your human partner —
     `git add -f` the skill directory, or skip verification for this PR.
     If it cannot produce a skill that runs, treat that as an Environment
     failure (item 4). Skip → the PR section reads
     `Not run — no verification skill; skipped by <human partner>.`
2. **Select features.** The map lists user entry points, not file
   paths, so trace from source. List the changed files
   (`git diff --name-only <base-branch>...HEAD`).
   Exclude the verification skill's own directory from feature
   selection, and skip docs and tests. For each remaining file, read
   the source to find which features' user entry points (each feature
   file's "How to get to it" section) reach it; an `Explore` subagent
   (brief: "do not edit files") is fine for this. Take every feature
   reached, plus those Step A named. When unsure, include the feature.
   Changed user-facing code that no feature reaches is a map gap: say so
   in the `## Verification` section. Skip the run as "nothing selected" only
   when every changed file is docs, tests, or the verification skill's
   own directory; the PR section then reads `Not run — <reason>.`
3. **Run.** Follow the project skill: Launch, Doctor, Drive each selected
   feature, Evidence, Cleanup. Drive each journey as its feature file
   writes it; never weaken one to make it pass. After Cleanup, confirm the
   evidence still exists at the location the skill names. Missing evidence
   is drift.
4. **Classify each failure.**
   - **Drift** — the harness is out of date (selector, launch command,
     map entry, a cleanup that eats evidence). Fix only the verification
     skill's own directory, commit it alone
     (`fix: update verify-<app> skill`), and
     re-run that feature once. Never edit product code for drift. If it
     fails again, it is no longer drift: stop and ask —

     > Verification of <feature> still fails after a harness fix — investigate as a product failure, or skip verification for this PR?

     Investigate → treat it as a product failure. Skip → the PR section
     reads `Not run — <reason>; skipped by <human partner>.` for that
     feature.
   - **Product failure** — the app behaves wrong. Blocking. Record it and
     go on to the next feature; Step C fixes it.
   - **Environment** — Launch, Doctor, or a drive fails for an
     environment reason, neither drift nor product: missing secrets, a
     dependency service that is down, a port in use. Stop and ask —

     > Verification can't start (<reason>) — fix the environment, or skip verification for this PR?

     Never record a pass. Fixed → re-run Step B. Skip → the PR section
     reads `Not run — <reason>; skipped by <human partner>.`

## Step C: Fix loop

- **A round:** take the pass that just finished (every enabled step run
  to completion), fix all blocking findings from that pass (follow
  `superpowers:test-driven-development` when there is a cheap local test
  target), run the full test suite, and commit once:
  `fix: address pre-PR check findings`. Then re-run every enabled step to
  completion — the diff changed. That re-run is the next pass.
- Next pass clean → Step D. Still blocking → another round.
- At most 2 fix rounds. Still blocked on the pass after round 2: stop.
  Report each finding, its proof, and what was tried to your human
  partner.
  No PR is opened.
- Suite red after a fix and you cannot make it pass: stop and report. No
  PR on a red suite.

## Step D: PR body

Add the section for each enabled step:

```markdown
## Blast radius
- **Safe because:** <fact> — proven at ladder step <N> (<how>) | unproven
- **Risks:** <how it breaks> — `file:line` — <likelihood/cost> — <check>
- **Cleared:** <what was checked and why it is fine>
- **Proof:** <script or command, and its output>

## Verification (verify-<app>)
- **<feature>:** pass | fail → fixed in <sha> — evidence: <local path>
```

- Evidence stays local; the PR lists the paths and does not upload
  artifacts.
- A step that did not run reads `Not run — <reason>.`
- Write "none" for an empty list.

## Interaction with pr-watch

- Fix commits pushed by the PR watch do not re-run pre-PR checks, as with
  cross-review.
- When a watch fix touches a user-facing feature, the thread reply or the
  final `## PR watch` section says verification was not re-run.
