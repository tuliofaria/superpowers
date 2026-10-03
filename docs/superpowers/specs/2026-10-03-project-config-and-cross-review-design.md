# Project Config, Manual Mode, and Cross-Provider Review — Design

Date: 2026-10-03
Status: approved by Tulio (in-session); spec pending review
Branch: `feat/project-config-cross-review` off `main` (fork: `tuliofaria/superpowers`)

## Goal

Three fork-only changes:

1. **Per-project defaults.** A small JSON config, resolvable globally and
   per project, that sets how superpowers behaves in that project.
2. **Manual mode (`/sp`).** In projects configured as manual, superpowers
   stays quiet until the human partner runs `/sp <task>`. `/sp` then
   classifies the task, invokes the right skill, and follows the chain to
   the end. `/sp-init` writes the config interactively.
3. **Cross-provider review before a PR.** Before pushing a PR, the agent
   gets a local review from the *other* provider (Claude Code → Codex,
   Codex → Claude), fixes verified findings in a bounded loop, and
   records the outcome in the PR body.

## Scope decisions (settled with Tulio)

- **Fork only.** Not proposed upstream: AGENTS.md rejects third-party
  dependencies and per-project/personal configuration in core. Changes are
  kept localized to ease merging upstream releases.
- **Config: fixed JSON keys, three layers.** Global
  `~/.config/superpowers/config.json`, project-committed
  `<repo>/.superpowers/config.json`, project-local
  `<repo>/.superpowers/config.local.json`. Precedence per key:
  local > project > global > default.
- **Config resolution: hook reads only `mode`; skills read the rest.**
  The hook stays pure bash (no node/jq/python). Skills tell the agent to
  read and merge the files, which works identically in Codex.
- **Manual mode is Claude Code only.** Codex has no SessionStart hook in
  this plugin (`.codex-plugin/plugin.json` has `"hooks": {}`) and
  discovers skills by description. In Codex, `finish` and `crossReview`
  are honored; `mode` is ignored.
- **Cross-review calls CLIs directly**, not `openai/codex-plugin-cc`:
  `codex review --base <base>` (Codex CLI ≥ 0.160 has it natively) and
  `claude -p`. Symmetric, works in both harnesses, no plugin dependency.
- **Findings: automatic bounded loop.** Max 2 rounds, then PR with a
  summary of fixed / rejected / open findings.
- **`/sp` activation lasts for the rest of the session.**

## Config schema

```json
{
  "mode": "auto",
  "finish": "ask",
  "crossReview": false
}
```

| Key | Values | Default | Effect |
|---|---|---|---|
| `mode` | `"auto"` \| `"manual"` | `"auto"` | `manual`: hook injects a short notice instead of the bootstrap; skills only via `/sp`. Claude Code only. |
| `finish` | `"ask"` \| `"pr"` | `"ask"` | `pr`: `finishing-a-development-branch` skips the menu and goes straight to the PR option. |
| `crossReview` | `true` \| `false` | `false` | `true`: before any PR push, run the cross-provider review loop. |

Unknown keys are ignored. Unknown values for a known key fall back to the
default for that key.

### File lookup

`<repo>` is `git rev-parse --show-toplevel` from the working directory
(`$CLAUDE_PROJECT_DIR` in the hook, falling back to `$PWD`). Outside a git
repo, `<repo>` is the working directory.

`config.local.json` is untracked, so it does not exist inside worktrees.
Both the hook and the skills therefore look for it in two places, first
match wins:

1. `<repo>/.superpowers/config.local.json`
2. `<main-worktree-root>/.superpowers/config.local.json`, where the main
   worktree root is the parent of `git rev-parse --git-common-dir`
   (resolved to an absolute path). Skipped when it equals `<repo>`.

Full order for any key: local (repo, then main worktree root) → project
(`<repo>/.superpowers/config.json`) → global → default.

## Component 1: `hooks/session-start` — manual mode

New function `resolve_mode`:

- Walks the file order above. For each existing file, extracts the value
  with a bash regex equivalent to `"mode"[[:space:]]*:[[:space:]]*"([a-z]+)"`.
  The first file that defines `mode` wins.
- Returns `manual` only for the exact value `manual`; anything else
  (missing, unreadable, malformed, other values) returns `auto`.
- Never fails the hook: all errors resolve to `auto`.
- Known limitation: a regex, not a JSON parser. A structurally broken file
  whose `"mode": "manual"` pair is intact still resolves to manual.

Behavior:

- `auto`: output identical to today (full `using-superpowers` bootstrap).
- `manual`: `session_context` is replaced with a short notice, emitted
  through the same per-platform JSON branches:

  > Superpowers is installed in **manual mode** for this project. Do not
  > invoke superpowers skills on your own initiative. They become active
  > only when your human partner runs `/sp` (or `/superpowers:sp`), or
  > if `/sp` was already run earlier in this session — in that case keep
  > following superpowers as activated.

  The last clause covers re-injection after `compact`/`clear`.

## Component 2: `skills/sp/SKILL.md` — the router

Frontmatter: `name: sp`, `disable-model-invocation: true`, description
stating it runs only when the human partner invokes `/sp` explicitly.

Body:

1. Announce that superpowers is active for the rest of this session.
2. Invoke `superpowers:using-superpowers`.
3. Classify `$ARGUMENTS`:
   - bug, failure, broken test, unexpected behavior → `systematic-debugging`
   - new feature, change, "build/add/make" → `brainstorming`
   - an existing plan file or "execute the plan" →
     `subagent-driven-development` when a subagent tool is available,
     otherwise `executing-plans`
   - "finish", "open the PR", "wrap up" → `finishing-a-development-branch`
   - ambiguous → ask one question to classify
4. Follow the chain the invoked skill defines through to its terminal
   state (including `finishing-a-development-branch`), without requiring
   `/sp` again.

No arguments: ask what the human partner wants to do, then classify.

## Component 3: `skills/sp-init/SKILL.md` — config setup

Frontmatter: `name: sp-init`, `disable-model-invocation: true`.

Flow:

1. Show the effective config and which file each value comes from.
2. Ask, one question at a time: `mode`, `finish`, `crossReview`, and the
   destination (project committed / project local / global).
3. If `crossReview: true`, check the other side's reviewer: in Claude Code
   `codex login status`; in Codex `claude --version`. On failure, explain
   how to fix it and save anyway.
4. Write only keys that differ from the defaults, merged into the existing
   destination file (other keys in that file are preserved).
5. If the destination is project local, ask whether to add
   `.superpowers/config.local.json` to the repo's `.gitignore`. Add it
   only on yes, and only if not already present.
6. Never commit.

## Component 4: `finishing-a-development-branch` changes

**New step after Step 2, "Load Project Config":** read the files in the
order defined above and merge per key. Missing files are normal. A file
that exists but is not valid JSON: warn once, ignore that file, continue.
Never block on config.

**Step 4:**

- `finish: "ask"`: unchanged menu.
- `finish: "pr"`: skip the menu. Announce "Project config sets
  `finish: pr` — opening a PR." Go to Option 2 (detached HEAD: "push as
  new branch and create a PR").

**Unchanged under `finish: "pr"`:** Step 1 (green suite required), Step 3
(ask about the base branch if not known from plan / conversation /
upstream), discard never automatic, worktree preserved.

**Option 2 (and the detached-HEAD PR option):** if `crossReview: true`,
run the cross-provider review procedure *before* `git push`. Applies
whether Option 2 was reached through the menu or through `finish: "pr"`.

**Common Rationalizations — new row:**

| Excuse | Reality |
|---|---|
| "Config says `pr`, but this one feels like a local merge" | The config is your human partner's standing decision. Follow it; mention the doubt in the report, don't override it. |

## Component 5: `skills/requesting-code-review/cross-provider-review.md`

**Reviewer selection.** The agent knows its harness; the reviewer is the
other one:

- **In Claude Code → Codex:**
  `codex review --base <base-branch>` from the repo root, output
  redirected to a temp file, run in the background (multi-file reviews
  are slow). Timeout 15 minutes. `--base` only: Codex CLI 0.160.0 rejects
  custom instructions combined with `--base` (verified).
- **In Codex → Claude:**
  `claude -p "<prompt>"` where `<prompt>` is `code-reviewer.md` filled
  with `{DESCRIPTION}`, `{PLAN_OR_REQUIREMENTS}`, `{BASE_SHA}`
  (`git merge-base <base> HEAD`), `{HEAD_SHA}`. Tools restricted to
  read-only (`Read`, `Grep`, `Glob`, read-only `git` subcommands). Output
  to a temp file. Timeout 15 minutes. Needs network and writes under
  `~/.claude`, which the default Codex sandbox blocks — request
  escalated permissions for this one command.

**Loop (max 2 rounds):**

1. Round 1: run the reviewer. Apply `receiving-code-review` to every
   finding: verify against the code, classify *accepted* or *rejected*
   with a reason.
2. Fix accepted findings, re-run the full test suite, commit
   (`fix: address cross-review findings`).
3. Round 2, only if round 1 changed code: re-run the reviewer; fix only
   verified Critical/Important findings, re-run tests, commit. No round 3.
4. Anything still unresolved is *open*.
5. The PR body gets a section:

   ```markdown
   ## Cross-provider review (Codex|Claude)
   - **Fixed:** …
   - **Rejected:** … — reason
   - **Open:** …
   ```

**Failures** (CLI missing, not logged in, timeout, sandbox denial,
unparseable output): stop and ask one line — "Cross-review failed
(<reason>). Open the PR without it, or fix it and retry?" Never skip
silently. If the human partner says to proceed, the PR section reads
"Cross-provider review: not run — <reason>".

**Tests failing after a fix:** stop the loop, report, and follow
Step 1's rule (no PR on a red suite).

## Component 6: README (fork section)

Short section: what the three keys do, the file locations and precedence,
`/sp` and `/sp-init`, and a recommendation to gitignore
`.superpowers/config.local.json` (per repo or in the global gitignore).

## Files touched

| File | Change |
|---|---|
| `hooks/session-start` | `resolve_mode` + manual-mode notice |
| `skills/sp/SKILL.md` | new |
| `skills/sp-init/SKILL.md` | new |
| `skills/sp-init/project-config.md` | new — single source for schema, lookup order, merge rules (read by `sp-init` and `finishing`) |
| `skills/finishing-a-development-branch/SKILL.md` | Load Project Config step, `finish: pr` shortcut, cross-review call, rationalization row |
| `skills/requesting-code-review/cross-provider-review.md` | new |
| `tests/hooks/test-session-start.sh` | new cases (below) |
| `README.md` | fork section |

`sp` and `sp-init` ship in the Codex package too: harmless there, usable
as explicit entry points.

## Testing

**Automated — `tests/hooks/test-session-start.sh`:**

- no config anywhere → full bootstrap (regression)
- `mode: manual` in each of: global, project, local → manual notice
- precedence: local `auto` overrides project `manual`; project `manual`
  overrides global `auto`
- `config.local.json` only in the main worktree root, hook run inside a
  linked worktree → manual
- malformed JSON / unknown value → auto
- output parses as valid JSON in both modes, for each platform branch
  (Claude Code, Cursor, Copilot/SDK)

Tests point `HOME` at a temp dir so the user's real global config never
leaks in.

**Behavioral — manual, in a throwaway repo:**

1. `mode: manual` + "Let's make a react todo list" → brainstorming does
   **not** trigger.
2. Same project, `/sp let's make a react todo list` → brainstorming
   triggers.
3. `mode: auto` + same message → brainstorming triggers (the repo's
   standard acceptance test).
4. `/sp-init` choosing local destination → writes
   `.superpowers/config.local.json` with only non-default keys; asks
   about `.gitignore` and respects the answer.
5. `finish: pr` + `crossReview: true` in a scratch GitHub repo, in
   Claude Code → `codex review` runs, loop runs, PR body has the review
   section.
6. Same in Codex → reviewer is `claude -p`.

## Out of scope

- Manual mode in Codex or any harness other than Claude Code.
- `finish` values other than `ask` / `pr`.
- Choosing a specific reviewer/model in config (always "the other one").
- Cross-review before local merges.
- Upstream PR.
