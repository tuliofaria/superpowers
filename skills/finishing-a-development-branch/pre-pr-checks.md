# Pre-PR Checks

Before a PR is pushed, find what the change could break, prove the
features it touches still work in the running app, fix what is proven
broken, and record the outcome in the PR body. Called by
`finishing-a-development-branch` when the project config sets
`blastRadius: true` or `verify: true`. Input: `<base-branch>`.

Run Step A if `blastRadius` is `true`, then Step B if `verify` is `true`.
When only one of the two keys is `true`, run only that step; feature
selection then uses the diff alone. Any blocking finding goes to Step C.
Finish with Step D.

## Step A: Blast radius

Follow `superpowers:blast-radius` on `<base-branch>..HEAD`.

- **Blocking:** a risk *confirmed* at step 4 or 5 of its "How sure are
  you" ladder — a script, test, or repro shows the breakage. Go to Step C.
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

     Generate → follow `superpowers:create-verification-skill`, then
     commit its output alone: `chore: add verify-<app> skill`. If it
     cannot produce a skill that runs, treat that as an Environment
     failure (item 4). Skip → the PR section reads
     `Not run — no verification skill; skipped by <human partner>.`
2. **Select features.** From the skill's `features/` map, take every
   feature whose source paths or entry points the diff
   (`git diff --name-only <base-branch>...HEAD`) touches, plus those
   Step A named. Exclude the verification skill's own directory from
   feature selection. Nothing selected (docs- or test-only diff): skip
   the run, and the PR section reads `Not run — <reason>.`
3. **Run.** Follow the project skill: Launch, Doctor, Drive each selected
   feature, Evidence, Cleanup. Drive each journey as its feature file
   writes it; never weaken one to make it pass. After Cleanup, confirm the
   evidence still exists at the location the skill names. Missing evidence
   is drift.
4. **Classify each failure.**
   - **Drift** — the harness is out of date (selector, launch command,
     map entry, a cleanup that eats evidence). Fix only the verification
     skill's own directory, commit it alone
     (`fix: update verify-<app> skill`), re-run that feature, and classify
     the result again. Never edit product code for drift.
   - **Product failure** — the app behaves wrong. Blocking. Go to Step C.
   - **Environment** — Launch or Doctor fails for a reason that is
     neither drift nor product: missing secrets, a dependency service
     that is down, a port in use. Stop and ask —

     > Verification can't start (<reason>) — fix the environment, or skip verification for this PR?

     Never record a pass. Fixed → re-run Step B. Skip → the PR section
     reads `Not run — <reason>; skipped by <human partner>.`

## Step C: Fix loop

- For each blocking finding from A or B: fix it (follow
  `superpowers:test-driven-development` when there is a cheap local test
  target), run the full test suite, and commit
  `fix: address pre-PR check findings`. Then re-run every enabled step —
  the diff changed.
- Never `git add` evidence; stage only the source and test files the fix
  touched.
- At most 2 fix rounds. Still blocked after round 2: stop. Report the
  finding, its proof, and what was tried to your human partner.
  No PR is opened.
- Suite red after a fix and you cannot make it pass: stop and report. No
  PR on a red suite.

## Step D: PR body

Add the section for each enabled step:

```markdown
## Blast radius
- **Safe because:** <fact> — proven at step <N> (<how>) | unproven
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
