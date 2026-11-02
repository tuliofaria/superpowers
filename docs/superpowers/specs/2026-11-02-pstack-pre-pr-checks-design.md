# Pre-PR Checks from pstack (Blast Radius + Verification) — Design

Date: 2026-11-02
Status: approved by Tulio (in-session); spec pending review
Branch: `feat/pstack-pre-pr-checks` off `main` (fork: `tuliofaria/superpowers`)

## Goal

Raise confidence in every PR that `/sp` opens. Before the push, the
finishing skill finds what the change could break beyond the diff and
proves the fact it is safe because of (`blast-radius`), then drives the
real app the way a user does and captures evidence (`verify-<app>`). Both
results go into the PR body.

Success: a PR opened by `/sp` carries a `## Blast radius` section (the
safety fact, proven at step N or marked unproven) and a `## Verification`
section with real evidence, or an explicit "Not run — <reason>".

## Scope decisions (settled with Tulio)

- **Fork only.** Everything lives in this fork, not in a separate plugin
  and not upstream.
- **Source:** three skills from pstack (`cursor/plugins`, MIT, Lauren
  Tan), pinned at commit `ae5650febf4320793844c12c4adaa937f417f8da`
  (2026-10-31): `blast-radius`, `create-verification-skill`,
  `maintain-verification-skill`.
- **Approach A — adapted copies.** The skills are copied into `skills/`
  and edited for Claude Code and superpowers. Upstream updates are ported
  by hand from a diff; nothing auto-updates.
- **When:** in finishing, on the PR path, before the cross-provider
  review: green suite → blast radius → verify → cross-review → push → PR
  → watch.
- **No `verify-<app>` skill in the repo:** ask whether to generate it now
  or skip verification for this PR.
- **On a confirmed failure:** fix and repeat, at most 2 rounds, then stop
  and report.
- **Activation:** two new config keys, `blastRadius` and `verify`, both
  default `false`.
- **Out of scope:** the rest of pstack (`interrogate`, `correct`,
  `principle-*`, ...); Quorum evals (this is a personal fork and does not
  go upstream).

## Component 1: the copied skills

### `skills/blast-radius/SKILL.md` — model-invocable

- Frontmatter: `name: blast-radius`; `description` in superpowers style:
  "Use when a change is about to ship, or when asked what a change could
  break beyond the diff". No `disable-model-invocation`.
- Kept as upstream: the "Don't trust your own writeup" section, the
  five-step "How sure are you" ladder, the six steps' substance, and
  "What to hand back".
- Adaptations:
  - Drop the "Companion to `how` and `why`" paragraph.
  - Step 1: "Use `why` step 2 to pull the PR and commits" becomes
    `git log <base>..HEAD` and `gh pr view` when a PR already exists.
  - Step 4: drop "Same rules as `why`."; keep the rules themselves
    (cite a real `file:line`, an empty search is an answer, never invent
    a caller or an API).
  - Step 6 (`arena`) becomes: "When `crossReview` is on, a second model
    reviews after this step; do not run another."
  - Closing line: drop "through `unslop`"; keep "cite real code, and
    strip anything private before it goes anywhere public".

### `skills/create-verification-skill/` — model-invocable

- `SKILL.md` adapted; `references/feature-map-example/` (README.md,
  create-note.md, search.md) copied unchanged.
- No `disable-model-invocation`: finishing invokes it after your human
  partner answers "generate now".
- Adaptations:
  - `.cursor/skills/verify-<app>/` → `.claude/skills/verify-<app>/`
    (both occurrences).
  - Drop the "read the Claude Code adapter" line. Inline the only
    mappings the skill needs: ask questions with `AskUserQuestion` (plain
    text when absent); a read-only helper is an `Explore` subagent whose
    brief says "do not edit files".
  - Step 5 points at `/superpowers:maintain-verification-skill`.

### `skills/maintain-verification-skill/SKILL.md` — manual only

- Keeps `disable-model-invocation: true`.
- Adaptations: same adapter-line removal and path change
  (`.cursor/skills/verify-*/` → `.claude/skills/verify-*/`); "one
  read-only subagent per feature file" becomes one `Explore` subagent per
  feature file, briefed "do not edit files", with `git status` checked
  afterward.

### Attribution and sync

- `docs/vendored/pstack/LICENSE` — the upstream MIT license text,
  verbatim.
- `docs/vendored/pstack/README.md` — upstream repo and path
  (`harness/pstack/claude-code/skills/`), the pinned SHA, and the list of
  adaptations per file (the bullets above).
- `scripts/pstack-upstream-diff.sh` — shallow-clones `cursor/plugins`
  into a `mktemp -d` directory, reads the pinned SHA from the README,
  fetches it, and prints `git diff <pinned>..origin/main` limited to the
  three skill directories. Read-only: it changes nothing in the fork and
  deletes its temp directory. Porting and bumping the SHA are manual.

## Component 2: config

Two keys in [project-config.md](../../../skills/sp-init/project-config.md),
same flat shape:

| Key | Values | Default | Effect |
|---|---|---|---|
| `blastRadius` | `true` \| `false` | `false` | `true`: before any PR push, finishing runs `superpowers:blast-radius` on `<base>..HEAD`. |
| `verify` | `true` \| `false` | `false` | `true`: before any PR push, finishing runs the project's `verify-<app>` skill on the features the diff touches; asks whether to generate one when none exists. |

- The example JSON block gains both keys with `false`.
- Precedence, invalid values, and missing files behave as for the
  existing keys.
- `/sp-init` gains two questions between `crossReview` and `execution`:
  "Run blast-radius before every PR?" and "Verify the real app (the
  project's `verify-<app>` skill) before every PR?". No tool check.
- After implementation, Tulio's global config
  (`~/.config/superpowers/config.json`, outside the repo) gets
  `"blastRadius": true` and `"verify": true`.

## Component 3: finishing

New procedure file
`skills/finishing-a-development-branch/pre-pr-checks.md`, same pattern
as `pr-watch.md` and `cross-provider-review.md`. Input: `<base-branch>`.

### Hook in `SKILL.md`

- Step 2b lists the two new keys.
- Option 2 gains a paragraph *before* the cross-review paragraph: if
  `blastRadius` or `verify` is `true`, first follow
  [pre-pr-checks.md](pre-pr-checks.md) with `<base-branch>` and include
  its sections in the PR body. Applies to the detached-HEAD PR option
  and to `finish: "pr"`, exactly like `crossReview`.
- Option 1 (merge locally) is unchanged.
- Common Rationalizations gains rows for: skipping verification because
  "the tests pass", calling an unproven risk "fine", and weakening a
  journey to make it pass.

### Step A: blast radius (when `blastRadius: true`)

Follow `superpowers:blast-radius` on `<base>..HEAD`.

- **Blocking:** a risk *confirmed* at ladder step 4 or 5 — a script,
  test, or repro shows the breakage.
- **Not blocking:** risks not proven, and an unproven safety fact. They
  go to the PR body.
- Features the writeup names as possibly affected are passed to Step B.

### Step B: verify (when `verify: true`)

1. **Locate.** Look for `verify-*` directories in `.claude/skills/`,
   `.agents/skills/`, and `.cursor/skills/` at the repo root.
   - More than one: ask which.
   - None: ask "This repo has no verification skill. Generate one now
     (create-verification-skill, once per repo) or skip verification for
     this PR?" Generate → follow `superpowers:create-verification-skill`,
     then commit its output alone: `chore: add verify-<app> skill`.
     Skip → the PR section reads "Not run — no verification skill;
     skipped by <human partner>".
2. **Select features.** From the skill's `features/` map: every feature
   whose source paths or entry points the diff touches, plus those Step A
   named. None touched (docs- or test-only diff): skip, and say why in
   the PR section.
3. **Run.** Follow the project skill: Launch, Doctor, Drive each
   selected feature, Evidence, Cleanup. Confirm the evidence survives
   cleanup at the location the skill names.
4. **Classify each failure.**
   - **Drift** — the harness is out of date (selector, launch command,
     map entry). Fix only the verification skill's own directory, commit
     it alone (`fix: update verify-<app> skill`), re-run that feature.
     Never edit product code for drift.
   - **Product failure** — the app behaves wrong. Blocking.

### Step C: fix loop (shared)

- A blocking finding from A or B → fix it (TDD when there is a cheap
  local test target), run the full suite, commit
  `fix: address pre-PR check findings`, then re-run every enabled step,
  since the diff changed.
- At most 2 fix rounds. Still blocked after round 2: stop. Report the
  finding, its proof, and what was tried. No PR is opened.
- Suite red after a fix and not fixable: stop. No PR on a red suite.

### Step D: PR body

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

### Interaction with pr-watch

- Fix commits pushed by the PR watch do not re-run pre-PR checks, as
  with cross-review today.
- When a watch fix touches a user-facing feature, the thread reply or
  final `## PR watch` section says verification was not re-run.

## Component 4: tests, docs, version

### Structural tests

Extend `tests/project-config/test-skill-structure.sh`
(`require_file` / `require_text`, plus a negative helper for "must not
contain"):

- The three skills and the three reference files exist.
- None of the three `SKILL.md` files contains `.cursor/skills`,
  `` `how` ``, `` `why` ``, `unslop`, or `arena`.
- `blast-radius` and `create-verification-skill` lack
  `disable-model-invocation`; `maintain-verification-skill` has it.
- `docs/vendored/pstack/LICENSE` contains "Lauren Tan"; the vendored
  README contains `ae5650febf4320793844c12c4adaa937f417f8da`.
- `project-config.md` has the `blastRadius` and `verify` table rows and
  JSON lines; `sp-init/SKILL.md` has both questions.
- Finishing `SKILL.md` references `pre-pr-checks.md`, and that reference
  appears before `cross-provider-review.md`.
- `pre-pr-checks.md` has the Step A–D headings and the 2-round limit.
- `scripts/pstack-upstream-diff.sh` passes `scripts/lint-shell.sh`
  (the repo's shell linter; `tests/shell-lint` tests the linter itself).

### Live acceptance (manual, once, before declaring done)

With `blastRadius` and `verify` on, run finishing on a real project of
Tulio's that has an app to launch (chosen at plan time):

1. In a repo without `verify-<app>`, the "generate now / skip" question
   appears.
2. The PR has `## Blast radius` and `## Verification` sections filled
   with real proof, not generic text.

This doubles as the first live run of `watchPr`.

### Docs and version

- `README.md`: the fork section lists both keys and credits pstack.
- Bump the fork version to `6.4.2-tf.2` so `claude plugin update` picks
  it up.
