# Project Config, Manual Mode, and Cross-Provider Review Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a layered per-project config (`mode`, `finish`, `crossReview`) to this fork, a `/sp` manual-mode entry point plus `/sp-init` setup, and a cross-provider (Codex ↔ Claude) review loop before PRs.

**Architecture:** The SessionStart hook resolves only `mode` with a pure-bash regex and swaps the bootstrap for a short notice when manual. Everything else is skill prose: one shared reference file defines the config schema and lookup order; `sp`, `sp-init`, and `finishing-a-development-branch` read it; a new procedure file under `requesting-code-review` runs the reviewer CLI of the other provider.

**Tech Stack:** bash (hook + tests, node only inside existing test assertions), Markdown skills, `codex` CLI ≥ 0.160, `claude` CLI.

**Spec:** `docs/superpowers/specs/2026-10-03-project-config-and-cross-review-design.md`

## Global Constraints

- Fork only (`tuliofaria/superpowers`); no upstream PR.
- Hook stays pure bash: no `node`, `jq`, or `python` at hook runtime.
- Config files, precedence local > project > global > default:
  - `<repo>/.superpowers/config.local.json`, then `<main-worktree-root>/.superpowers/config.local.json`
  - `<repo>/.superpowers/config.json`
  - `~/.config/superpowers/config.json`
- Keys and defaults: `mode` (`"auto"` | `"manual"`, default `"auto"`), `finish` (`"ask"` | `"pr"`, default `"ask"`), `crossReview` (`true` | `false`, default `false`). Unknown keys ignored; unknown values fall back to the key's default.
- Manual mode is Claude Code only; Codex honors `finish` and `crossReview` only.
- Cross-review: `codex review --base <base>` (this CLI rejects `--base` combined with a custom prompt — verified on 0.160.0) / `claude -p`. Max 2 rounds. Failures stop and ask; never skip silently.
- macOS has no `timeout` command — never use it in procedures; use the harness's background/timeout facilities.
- `/sp-init` never commits; asks before touching `.gitignore`.
- Skill prose uses "your human partner", matching the repo's voice.

## Review Focus

1. **Linked worktree with `config.local.json` only in the main checkout** — manual mode must still apply inside `.worktrees/<branch>`; pinned in Task 1 (worktree test).
2. **Outside a git repo** (`CLAUDE_PROJECT_DIR` is a plain directory) — the hook must not fail and must read `<dir>/.superpowers/config.json`; pinned in Task 1.
3. **Value with wrong case or an unquoted value** (`"Manual"`, `manual` without quotes) — must resolve to auto, never to an error or an empty context; pinned in Task 1.
4. **The official superpowers plugin is installed alongside the fork** — its own hook still injects the full bootstrap, silently defeating manual mode; Task 6 disables it for the behavioral run and the README warns about it.
5. **Codex loading `sp`/`sp-init` with the Claude-only `disable-model-invocation` frontmatter key** — Codex must still load the skill set; checked in Task 6 step 6.

Known limitation (documented, not tested): the hook does not validate JSON structure. A truncated file whose `"mode": "manual"` pair is intact still resolves to manual.

---

## File Structure

| File | Responsibility |
|---|---|
| `hooks/session-start` (modify) | `read_mode_from` + `resolve_mode`; choose bootstrap vs manual notice |
| `tests/hooks/test-session-start.sh` (modify) | Mode resolution and output-shape tests |
| `skills/sp-init/project-config.md` (create) | Single source for schema, lookup order, merge rules — read by `sp-init` and `finishing` |
| `skills/sp-init/SKILL.md` (create) | Interactive config writer |
| `skills/sp/SKILL.md` (create) | `/sp` router |
| `skills/requesting-code-review/cross-provider-review.md` (create) | Cross-provider review loop procedure |
| `skills/finishing-a-development-branch/SKILL.md` (modify) | Load config step, `finish: pr`, cross-review call, rationalization row |
| `tests/project-config/test-skill-structure.sh` (create) | Structural checks for the new/changed skill files |
| `README.md` (modify) | Fork section |

`skills/sp-init/project-config.md` exists so the lookup order is written once instead of duplicated in `sp-init` and `finishing`.

---

### Task 1: Hook resolves `mode` and injects the manual notice

**Files:**
- Modify: `hooks/session-start`
- Test: `tests/hooks/test-session-start.sh`

**Interfaces:**
- Produces: in manual mode the injected context contains the literal phrase `manual mode` and does **not** contain `IF A SKILL APPLIES TO YOUR TASK`; in auto mode it is byte-identical to today's output.

- [ ] **Step 1: Write the failing tests**

In `tests/hooks/test-session-start.sh`, insert after the `make_home` function:

```bash
make_repo() {
    local dir="$TEST_ROOT/$1/repo"
    mkdir -p "$dir"
    git -C "$dir" init -q
    git -C "$dir" -c user.email=test@example.com -c user.name=test \
        commit -q --allow-empty -m init
    printf '%s\n' "$dir"
}

write_file() {
    mkdir -p "$(dirname "$1")"
    printf '%s\n' "$2" > "$1"
}

BOOTSTRAP_MARKER="IF A SKILL APPLIES TO YOUR TASK"
MANUAL_MARKER="manual mode"
```

Insert before the final `if [[ "$FAILURES" -gt 0 ]]` block:

```bash
echo "Project config mode tests"

home="$(make_home mode-none)"; repo="$(make_repo mode-none)"
assert_command_output \
    "no config anywhere injects the full bootstrap" \
    "nested" "$BOOTSTRAP_MARKER" "$MANUAL_MARKER" "$home" \
    CLAUDE_PLUGIN_ROOT="$REPO_ROOT" CLAUDE_PROJECT_DIR="$repo" \
    bash "$HOOK_UNDER_TEST"

home="$(make_home mode-global)"; repo="$(make_repo mode-global)"
write_file "$home/.config/superpowers/config.json" '{"mode": "manual"}'
assert_command_output \
    "global mode manual injects the manual notice" \
    "nested" "$MANUAL_MARKER" "$BOOTSTRAP_MARKER" "$home" \
    CLAUDE_PLUGIN_ROOT="$REPO_ROOT" CLAUDE_PROJECT_DIR="$repo" \
    bash "$HOOK_UNDER_TEST"

home="$(make_home mode-project)"; repo="$(make_repo mode-project)"
write_file "$repo/.superpowers/config.json" '{ "finish": "pr", "mode": "manual" }'
assert_command_output \
    "project mode manual injects the manual notice" \
    "nested" "$MANUAL_MARKER" "$BOOTSTRAP_MARKER" "$home" \
    CLAUDE_PLUGIN_ROOT="$REPO_ROOT" CLAUDE_PROJECT_DIR="$repo" \
    bash "$HOOK_UNDER_TEST"

home="$(make_home mode-local)"; repo="$(make_repo mode-local)"
write_file "$repo/.superpowers/config.local.json" '{"mode":"manual"}'
assert_command_output \
    "local mode manual injects the manual notice" \
    "nested" "$MANUAL_MARKER" "$BOOTSTRAP_MARKER" "$home" \
    CLAUDE_PLUGIN_ROOT="$REPO_ROOT" CLAUDE_PROJECT_DIR="$repo" \
    bash "$HOOK_UNDER_TEST"

home="$(make_home mode-local-wins)"; repo="$(make_repo mode-local-wins)"
write_file "$repo/.superpowers/config.json" '{"mode": "manual"}'
write_file "$repo/.superpowers/config.local.json" '{"mode": "auto"}'
assert_command_output \
    "local auto overrides project manual" \
    "nested" "$BOOTSTRAP_MARKER" "$MANUAL_MARKER" "$home" \
    CLAUDE_PLUGIN_ROOT="$REPO_ROOT" CLAUDE_PROJECT_DIR="$repo" \
    bash "$HOOK_UNDER_TEST"

home="$(make_home mode-project-wins)"; repo="$(make_repo mode-project-wins)"
write_file "$home/.config/superpowers/config.json" '{"mode": "auto"}'
write_file "$repo/.superpowers/config.json" '{"mode": "manual"}'
assert_command_output \
    "project manual overrides global auto" \
    "nested" "$MANUAL_MARKER" "$BOOTSTRAP_MARKER" "$home" \
    CLAUDE_PLUGIN_ROOT="$REPO_ROOT" CLAUDE_PROJECT_DIR="$repo" \
    bash "$HOOK_UNDER_TEST"

home="$(make_home mode-worktree)"; repo="$(make_repo mode-worktree)"
write_file "$repo/.superpowers/config.local.json" '{"mode": "manual"}'
worktree="$TEST_ROOT/mode-worktree/wt"
git -C "$repo" worktree add -q -b feature "$worktree"
assert_command_output \
    "local config in the main checkout applies inside a linked worktree" \
    "nested" "$MANUAL_MARKER" "$BOOTSTRAP_MARKER" "$home" \
    CLAUDE_PLUGIN_ROOT="$REPO_ROOT" CLAUDE_PROJECT_DIR="$worktree" \
    bash "$HOOK_UNDER_TEST"

home="$(make_home mode-no-git)"
plain="$TEST_ROOT/mode-no-git/plain"
write_file "$plain/.superpowers/config.json" '{"mode": "manual"}'
assert_command_output \
    "outside a git repo the project dir config still applies" \
    "nested" "$MANUAL_MARKER" "$BOOTSTRAP_MARKER" "$home" \
    CLAUDE_PLUGIN_ROOT="$REPO_ROOT" CLAUDE_PROJECT_DIR="$plain" \
    bash "$HOOK_UNDER_TEST"

home="$(make_home mode-unquoted)"; repo="$(make_repo mode-unquoted)"
write_file "$repo/.superpowers/config.json" '{"mode": manual}'
assert_command_output \
    "unquoted mode value resolves to auto" \
    "nested" "$BOOTSTRAP_MARKER" "$MANUAL_MARKER" "$home" \
    CLAUDE_PLUGIN_ROOT="$REPO_ROOT" CLAUDE_PROJECT_DIR="$repo" \
    bash "$HOOK_UNDER_TEST"

home="$(make_home mode-case)"; repo="$(make_repo mode-case)"
write_file "$repo/.superpowers/config.json" '{"mode": "Manual"}'
assert_command_output \
    "wrong-case mode value resolves to auto" \
    "nested" "$BOOTSTRAP_MARKER" "$MANUAL_MARKER" "$home" \
    CLAUDE_PLUGIN_ROOT="$REPO_ROOT" CLAUDE_PROJECT_DIR="$repo" \
    bash "$HOOK_UNDER_TEST"

home="$(make_home mode-cursor)"; repo="$(make_repo mode-cursor)"
write_file "$repo/.superpowers/config.json" '{"mode": "manual"}'
assert_command_output \
    "manual notice uses the Cursor output shape" \
    "cursor" "$MANUAL_MARKER" "$BOOTSTRAP_MARKER" "$home" \
    CURSOR_PLUGIN_ROOT="$REPO_ROOT" CLAUDE_PLUGIN_ROOT="$REPO_ROOT" \
    CLAUDE_PROJECT_DIR="$repo" bash "$HOOK_UNDER_TEST"

home="$(make_home mode-sdk)"; repo="$(make_repo mode-sdk)"
write_file "$repo/.superpowers/config.json" '{"mode": "manual"}'
assert_command_output \
    "manual notice uses the SDK output shape" \
    "sdk" "$MANUAL_MARKER" "$BOOTSTRAP_MARKER" "$home" \
    COPILOT_CLI=1 CLAUDE_PLUGIN_ROOT="$REPO_ROOT" \
    CLAUDE_PROJECT_DIR="$repo" bash "$HOOK_UNDER_TEST"
```

- [ ] **Step 2: Run tests to verify the new ones fail**

Run: `bash tests/hooks/test-session-start.sh`
Expected: the existing tests and "no config anywhere", "local auto overrides project manual", "unquoted…", "wrong-case…" PASS; every test expecting the manual notice FAILS with `context did not contain expected text: manual mode`. `STATUS: FAILED`.

- [ ] **Step 3: Implement mode resolution in the hook**

In `hooks/session-start`, replace these lines:

```bash
# Read using-superpowers content
using_superpowers_content=$(cat "${PLUGIN_ROOT}/skills/using-superpowers/SKILL.md" 2>&1 || echo "Error reading using-superpowers skill")
```

with only the function definitions (the content read moves below `escape_for_json`):

```bash
# Print the "mode" value defined in a config file. Fails when the file is
# missing or does not define a quoted mode. A regex, not a JSON parser:
# the hook stays pure bash.
read_mode_from() {
    local file="$1" content
    [ -f "$file" ] || return 1
    content=$(cat "$file" 2>/dev/null) || return 1
    if [[ "$content" =~ \"mode\"[[:space:]]*:[[:space:]]*\"([A-Za-z]*)\" ]]; then
        printf '%s' "${BASH_REMATCH[1]}"
        return 0
    fi
    return 1
}

# Resolve the project's superpowers mode: "manual" or "auto".
# The first file that defines mode wins, in this order:
#   <repo>/.superpowers/config.local.json
#   <main worktree root>/.superpowers/config.local.json  (untracked, so absent in linked worktrees)
#   <repo>/.superpowers/config.json
#   ~/.config/superpowers/config.json
resolve_mode() {
    local start_dir="${CLAUDE_PROJECT_DIR:-$PWD}"
    local repo common_dir main_root value file
    repo=$(git -C "$start_dir" rev-parse --show-toplevel 2>/dev/null) || repo="$start_dir"
    common_dir=$(git -C "$start_dir" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || common_dir=""

    local candidates=("$repo/.superpowers/config.local.json")
    if [ -n "$common_dir" ]; then
        main_root=$(dirname "$common_dir")
        if [ "$main_root" != "$repo" ]; then
            candidates+=("$main_root/.superpowers/config.local.json")
        fi
    fi
    candidates+=("$repo/.superpowers/config.json" "${HOME:-}/.config/superpowers/config.json")

    for file in "${candidates[@]}"; do
        if value=$(read_mode_from "$file"); then
            if [ "$value" = "manual" ]; then
                printf 'manual'
            else
                printf 'auto'
            fi
            return 0
        fi
    done
    printf 'auto'
}
```

Then replace these two lines:

```bash
using_superpowers_escaped=$(escape_for_json "$using_superpowers_content")
session_context="<EXTREMELY_IMPORTANT>\nYou have superpowers.\n\n**Below is the full content of your 'superpowers:using-superpowers' skill - your introduction to using skills. For all other skills, use the 'Skill' tool:**\n\n${using_superpowers_escaped}\n</EXTREMELY_IMPORTANT>"
```

with:

```bash
if [ "$(resolve_mode)" = "manual" ]; then
    manual_notice="Superpowers is installed in **manual mode** for this project. Do not invoke superpowers skills on your own initiative. They become active only when your human partner runs \`/sp\` (or \`/superpowers:sp\`), or if \`/sp\` was already run earlier in this session - in that case keep following superpowers as activated."
    session_context="<EXTREMELY_IMPORTANT>\n$(escape_for_json "$manual_notice")\n</EXTREMELY_IMPORTANT>"
else
    # Read using-superpowers content
    using_superpowers_content=$(cat "${PLUGIN_ROOT}/skills/using-superpowers/SKILL.md" 2>&1 || echo "Error reading using-superpowers skill")
    using_superpowers_escaped=$(escape_for_json "$using_superpowers_content")
    session_context="<EXTREMELY_IMPORTANT>\nYou have superpowers.\n\n**Below is the full content of your 'superpowers:using-superpowers' skill - your introduction to using skills. For all other skills, use the 'Skill' tool:**\n\n${using_superpowers_escaped}\n</EXTREMELY_IMPORTANT>"
fi
```

The auto branch keeps the original two lines verbatim, so auto output is unchanged.

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash tests/hooks/test-session-start.sh`
Expected: every line `[PASS]`, final line `STATUS: PASSED`.

- [ ] **Step 5: Lint**

Run: `scripts/lint-shell.sh hooks/session-start tests/hooks/test-session-start.sh`
Expected: no findings. If it reports that `shellcheck` is not installed, run `bash -n hooks/session-start && bash -n tests/hooks/test-session-start.sh` instead and note the skipped lint in the task report.

- [ ] **Step 6: Commit**

```bash
git add hooks/session-start tests/hooks/test-session-start.sh
git commit -m "feat(hook): manual mode from project config"
```

---

### Task 2: Config reference and `/sp-init`

**Files:**
- Create: `skills/sp-init/project-config.md`
- Create: `skills/sp-init/SKILL.md`
- Test: `tests/project-config/test-skill-structure.sh`

**Interfaces:**
- Produces: `skills/sp-init/project-config.md` — the single reference other skills link to (from `skills/<name>/SKILL.md` the relative path is `../sp-init/project-config.md`). It defines the "effective config" procedure that Tasks 3 and 5 rely on by name: **"Resolve the effective config"**.
- Produces: `tests/project-config/test-skill-structure.sh` with helpers `require_file <path>` and `require_text <path> <literal>`; Tasks 3–5 append checks to it.

- [ ] **Step 1: Write the failing structure test**

Create `tests/project-config/test-skill-structure.sh`:

```bash
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
require_text "skills/sp-init/SKILL.md" ".gitignore"
require_text "skills/sp-init/SKILL.md" "Never commit"

if [[ "$FAILURES" -gt 0 ]]; then
    echo "STATUS: FAILED ($FAILURES failure(s))"
    exit 1
fi
echo "STATUS: PASSED"
```

Run: `chmod +x tests/project-config/test-skill-structure.sh`

- [ ] **Step 2: Run it to verify it fails**

Run: `tests/project-config/test-skill-structure.sh`
Expected: `[FAIL] missing: skills/sp-init/project-config.md` (and the rest), `STATUS: FAILED`.

- [ ] **Step 3: Write `skills/sp-init/project-config.md`**

````markdown
# Superpowers Project Config

Per-project defaults for this fork of superpowers. Three optional JSON
files, all with the same flat shape:

```json
{
  "mode": "auto",
  "finish": "ask",
  "crossReview": false
}
```

| Key | Values | Default | Effect |
|---|---|---|---|
| `mode` | `"auto"` \| `"manual"` | `"auto"` | `manual`: superpowers stays quiet until your human partner runs `/sp`. Claude Code only — the SessionStart hook reads it. |
| `finish` | `"ask"` \| `"pr"` | `"ask"` | `pr`: `finishing-a-development-branch` skips its menu and opens a PR. |
| `crossReview` | `true` \| `false` | `false` | `true`: before any PR push, run the cross-provider review loop. |

Unknown keys are ignored. An unknown value for a known key means that
key's default.

## Files

From the working directory, `<repo>` is `git rev-parse --show-toplevel`
(outside a git repo: the working directory itself). `<main>` is the parent
directory of `git rev-parse --path-format=absolute --git-common-dir` — the
main checkout, which differs from `<repo>` inside a linked worktree.

| Layer | Path |
|---|---|
| local (untracked, personal) | `<repo>/.superpowers/config.local.json`, else `<main>/.superpowers/config.local.json` |
| project (committed, shared) | `<repo>/.superpowers/config.json` |
| global | `~/.config/superpowers/config.json` |

`config.local.json` is untracked, so it never exists inside a linked
worktree — that is why `<main>` is checked.

## Resolve the effective config

1. Read each file that exists, in this order: local (`<repo>` first, then
   `<main>`; use the first one found), project, global.
2. A file that exists but is not valid JSON: tell your human partner once
   ("ignoring <path>: not valid JSON") and skip it.
3. For each key, take the value from the first layer that defines it with a
   valid value; otherwise the default.
4. Missing files are normal. Config never blocks work.
````

- [ ] **Step 4: Write `skills/sp-init/SKILL.md`**

````markdown
---
name: sp-init
description: Use only when your human partner explicitly runs /sp-init - writes this fork's superpowers project config interactively
disable-model-invocation: true
---

# /sp-init — Configure Superpowers for This Project

Schema, file locations, and precedence: [project-config.md](project-config.md).

## Step 1: Show the current state

Resolve the effective config (project-config.md, "Resolve the effective
config") and show each key with its value and the file it came from
(or "default").

## Step 2: Ask, one question at a time

1. `mode` — "auto" (superpowers triggers on its own) or "manual" (only via `/sp`; Claude Code only)?
2. `finish` — "ask" (menu at the end) or "pr" (always open a PR)?
3. `crossReview` — review with the other provider (Claude Code → Codex, Codex → Claude) before every PR?
4. Destination — project committed (`.superpowers/config.json`), project local (`.superpowers/config.local.json`), or global (`~/.config/superpowers/config.json`)?

Offer the current effective value as the default answer for each.

## Step 3: Check the reviewer (only when `crossReview` is true)

- In Claude Code: run `codex login status`. Expect "Logged in".
- In Codex: run `claude --version`.

If the check fails, tell your human partner what is missing (install with
`npm install -g @openai/codex` and `codex login`, or install Claude Code)
and continue — the setting is saved anyway.

## Step 4: Write the file

- Create the destination's parent directory if needed.
- If the destination already exists and is valid JSON, keep its other
  keys; otherwise start from `{}`.
- Set each answered key **only if it differs from the default**; remove
  it from the file if it equals the default.
- Write pretty-printed JSON with a trailing newline. If the result is
  `{}`, still write it.

## Step 5: `.gitignore` (project local destination only)

Ask: "Add `.superpowers/config.local.json` to this repo's `.gitignore`?"
On yes, append that line to `<repo>/.gitignore` unless an identical line
is already there. On no, change nothing.

## Step 6: Report

Show the written file's path and contents. Never commit — your human
partner decides whether and when the committed config goes into git.
````

- [ ] **Step 5: Run the structure test**

Run: `tests/project-config/test-skill-structure.sh`
Expected: all `[PASS]`, `STATUS: PASSED`.

- [ ] **Step 6: Commit**

```bash
git add skills/sp-init tests/project-config/test-skill-structure.sh
git commit -m "feat(skills): project config reference and /sp-init"
```

---

### Task 3: `/sp` router skill

**Files:**
- Create: `skills/sp/SKILL.md`
- Test: `tests/project-config/test-skill-structure.sh` (append)

**Interfaces:**
- Consumes: hook notice from Task 1 tells the agent `/sp` activates superpowers.

- [ ] **Step 1: Append failing checks**

In `tests/project-config/test-skill-structure.sh`, insert before the final `if [[ "$FAILURES" -gt 0 ]]` block:

```bash
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
require_text "skills/sp/SKILL.md" "superpowers:finishing-a-development-branch"
require_text "skills/sp/SKILL.md" "rest of this session"
```

- [ ] **Step 2: Run to verify failure**

Run: `tests/project-config/test-skill-structure.sh`
Expected: `[FAIL] missing: skills/sp/SKILL.md` and the related lacks, `STATUS: FAILED`.

- [ ] **Step 3: Write `skills/sp/SKILL.md`**

````markdown
---
name: sp
description: Use only when your human partner explicitly runs /sp - activates superpowers for the rest of the session and routes the task to the right workflow skill
argument-hint: <task description>
disable-model-invocation: true
---

# /sp — Start Superpowers

Your human partner ran `/sp` with: $ARGUMENTS

**Announce:** "Superpowers is active for the rest of this session."

From here on, superpowers is fully active in this session, even when the
project config sets `mode: "manual"`. Later skill transitions
(brainstorming → writing-plans → execution → finishing) need no second
`/sp`.

## Step 1: Load the bootstrap

Invoke `superpowers:using-superpowers` and follow it for the rest of the
session.

## Step 2: Route the task

| The task is... | Invoke |
|---|---|
| A bug, failure, broken test, or unexpected behavior | `superpowers:systematic-debugging` |
| A new feature, a change, or anything to build, add, or make | `superpowers:brainstorming` |
| An existing plan file, or "execute the plan" | `superpowers:subagent-driven-development` if you have a subagent tool, otherwise `superpowers:executing-plans` |
| Finishing work: "finish", "open the PR", "wrap up" | `superpowers:finishing-a-development-branch` |

Empty arguments: ask your human partner what they want to do, then route.
A task that fits more than one row: ask one question to decide.

## Step 3: Follow through

Follow the invoked skill's chain to its terminal state, including
`superpowers:finishing-a-development-branch` when the chain reaches it.
Every approval gate in those skills still applies: `/sp` starts the
workflow; it does not pre-approve designs, plans, or integration choices
beyond what the project config already decides.
````

- [ ] **Step 4: Run to verify pass**

Run: `tests/project-config/test-skill-structure.sh`
Expected: `STATUS: PASSED`.

- [ ] **Step 5: Commit**

```bash
git add skills/sp tests/project-config/test-skill-structure.sh
git commit -m "feat(skills): /sp router for manual mode"
```

---

### Task 4: Cross-provider review procedure

**Files:**
- Create: `skills/requesting-code-review/cross-provider-review.md`
- Test: `tests/project-config/test-skill-structure.sh` (append)

**Interfaces:**
- Consumes: `skills/requesting-code-review/code-reviewer.md` placeholders `{DESCRIPTION}`, `{PLAN_OR_REQUIREMENTS}`, `{BASE_SHA}`, `{HEAD_SHA}` (existing file).
- Produces: a procedure Task 5 calls as "run [cross-provider-review.md](../requesting-code-review/cross-provider-review.md) with `<base-branch>`"; its output is the PR body section titled `## Cross-provider review (Codex)` or `## Cross-provider review (Claude)`.

- [ ] **Step 1: Append failing checks**

Insert before the final `if [[ "$FAILURES" -gt 0 ]]` block:

```bash
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
```

- [ ] **Step 2: Run to verify failure**

Run: `tests/project-config/test-skill-structure.sh`
Expected: `[FAIL] missing: skills/requesting-code-review/cross-provider-review.md`, `STATUS: FAILED`.

- [ ] **Step 3: Write `skills/requesting-code-review/cross-provider-review.md`**

````markdown
# Cross-Provider Review

Before a PR is pushed, get a local review from the *other* provider, fix
what holds up, and record the outcome in the PR body. Called by
`finishing-a-development-branch` when the project config sets
`crossReview: true`. Input: `<base-branch>`.

## Pick the reviewer

You know which harness you are running in. The reviewer is the other one:

| You are in | Reviewer | Section title |
|---|---|---|
| Claude Code | Codex CLI | `## Cross-provider review (Codex)` |
| Codex | Claude Code CLI | `## Cross-provider review (Claude)` |

## Run a round

Write output to a fresh temp file per round
(`REVIEW_OUT=$(mktemp -t cross-review.XXXXXX)`). Allow up to 15 minutes;
use your harness's background execution and timeout, not the `timeout`
command (absent on macOS).

**Codex reviewer** (from the repo root):

```bash
codex review --base <base-branch> > "$REVIEW_OUT" 2>&1
```

`codex review` refuses custom instructions together with `--base`; run it
with `--base` only.

**Claude reviewer:** fill [code-reviewer.md](code-reviewer.md) —
`{DESCRIPTION}` (what was built), `{PLAN_OR_REQUIREMENTS}` (plan or spec
path), `{BASE_SHA}` (`git merge-base <base-branch> HEAD`), `{HEAD_SHA}`
(`git rev-parse HEAD`) — save it to a temp file `$PROMPT_FILE`, then:

```bash
claude -p "$(cat "$PROMPT_FILE")" \
  --allowedTools "Read,Grep,Glob,Bash(git diff:*),Bash(git log:*),Bash(git show:*)" \
  > "$REVIEW_OUT" 2>&1
```

`claude -p` needs network access and writes under `~/.claude`; the
default Codex sandbox blocks both. Request escalated permissions for this
one command.

## The loop (at most 2 rounds)

1. **Round 1.** Run a round. Apply `superpowers:receiving-code-review` to
   every finding: verify it against the code, then mark it *accepted* or
   *rejected* with a one-line reason.
2. Fix the accepted findings. Run the full test suite. Commit:
   `fix: address cross-review findings`.
3. **Round 2** — only if round 1 changed code. Run a round. Fix only
   findings that are Critical or Important *and* verified; run the suite;
   commit with the same message. No round 3.
4. Everything still unresolved is *open*.

If the suite fails after a fix and you cannot make it pass, stop: no PR
on a red suite. Report to your human partner.

## Record the outcome in the PR body

```markdown
## Cross-provider review (Codex)
- **Fixed:** <finding> — <commit sha>
- **Rejected:** <finding> — <reason>
- **Open:** <finding>
```

Write "none" for an empty list.

## When the reviewer fails

CLI missing, not logged in, timeout, sandbox denial, or output you cannot
read as a review: stop and ask in one line —

> Cross-review failed (<reason>). Open the PR without it, or fix it and retry?

Never skip the review silently. If your human partner says to proceed,
the PR body section reads: `## Cross-provider review (<Reviewer>)` then
`Not run — <reason>.`
````

- [ ] **Step 4: Run to verify pass**

Run: `tests/project-config/test-skill-structure.sh`
Expected: `STATUS: PASSED`.

- [ ] **Step 5: Commit**

```bash
git add skills/requesting-code-review/cross-provider-review.md tests/project-config/test-skill-structure.sh
git commit -m "feat(skills): cross-provider review procedure"
```

---

### Task 5: `finishing-a-development-branch` honors the config

**Files:**
- Modify: `skills/finishing-a-development-branch/SKILL.md`
- Test: `tests/project-config/test-skill-structure.sh` (append)

**Interfaces:**
- Consumes: `../sp-init/project-config.md` "Resolve the effective config" (Task 2); `../requesting-code-review/cross-provider-review.md` (Task 4).

- [ ] **Step 1: Append failing checks**

Insert before the final `if [[ "$FAILURES" -gt 0 ]]` block:

```bash
# --- finishing honors config ---
F="skills/finishing-a-development-branch/SKILL.md"
require_text "$F" "## Step 2b: Load Project Config"
require_text "$F" "../sp-init/project-config.md"
require_text "$F" 'finish: "pr"'
require_text "$F" "../requesting-code-review/cross-provider-review.md"
require_text "$F" "Config says \`pr\`, but this one feels like a local merge"
```

- [ ] **Step 2: Run to verify failure**

Run: `tests/project-config/test-skill-structure.sh`
Expected: five `[FAIL] … lacks: …` lines for the finishing skill, `STATUS: FAILED`.

- [ ] **Step 3: Add Step 2b**

In `skills/finishing-a-development-branch/SKILL.md`, insert immediately before the line `## Step 3: Determine Base Branch`:

```markdown
## Step 2b: Load Project Config

Resolve the effective config as described in
[project-config.md](../sp-init/project-config.md) ("Resolve the effective
config"). Two keys matter here:

- `finish` — `"ask"` (default) or `"pr"`
- `crossReview` — `false` (default) or `true`

Config never blocks: missing files mean defaults.

```

- [ ] **Step 4: Add the `finish: "pr"` shortcut**

Insert immediately after the line `## Step 4: Present Options`:

```markdown

**If the project config sets `finish: "pr"`:** skip the menu. Announce
"Project config sets `finish: pr` — opening a PR." and go to Option 2
(detached HEAD: "Push as new branch and create a Pull Request"). Step 1's
green suite and Step 3's base branch still apply; discard is never
automatic.

**Otherwise (`finish: "ask"`):**
```

- [ ] **Step 5: Call the cross-review from Option 2**

Replace these three lines (heading, blank line, opening fence):

~~~markdown
### Option 2: Push and Create PR

```bash
~~~

with:

~~~markdown
### Option 2: Push and Create PR

**If the project config sets `crossReview: true`:** first run
[cross-provider-review.md](../requesting-code-review/cross-provider-review.md)
with `<base-branch>`, and include its section in the PR body. This applies
to the detached-HEAD PR option too, and whether you got here from the menu
or from `finish: "pr"`.

```bash
~~~

Everything after the opening fence (`git push -u origin <feature-branch>`, the detached-HEAD comment lines, the closing fence) stays as it is.

- [ ] **Step 6: Add the rationalization row**

In the `## Common Rationalizations` table, append after the last row (`"The push was rejected — force-push will fix it"`):

```markdown
| "Config says `pr`, but this one feels like a local merge" | The config is your human partner's standing decision. Follow it; mention the doubt in the report, don't override it. |
```

- [ ] **Step 7: Run to verify pass**

Run: `tests/project-config/test-skill-structure.sh && bash tests/hooks/test-session-start.sh`
Expected: both `STATUS: PASSED`.

- [ ] **Step 8: Read the edited skill top to bottom**

Run: `sed -n '/## Step 2b/,/## Step 5/p' skills/finishing-a-development-branch/SKILL.md`
Expected: Step 2b sits between Step 2 and Step 3; in Step 4 the `finish: "pr"` paragraph comes before both menus; fences are balanced (the menus still render as code blocks).

- [ ] **Step 9: Commit**

```bash
git add skills/finishing-a-development-branch/SKILL.md tests/project-config/test-skill-structure.sh
git commit -m "feat(finishing): honor finish and crossReview project config"
```

---

### Task 6: README fork section and behavioral verification

**Files:**
- Modify: `README.md`

**Interfaces:**
- Consumes: everything above.

- [ ] **Step 1: Add the README section**

In `README.md`, insert immediately before the first `## ` heading that follows the installation sections (run `grep -n '^## ' README.md` and pick the heading right after the install list), this section:

````markdown
## Fork: Project Config, `/sp`, and Cross-Provider Review

This fork adds per-project defaults. Run `/sp-init` to write them, or edit
the JSON by hand — details in
[`skills/sp-init/project-config.md`](skills/sp-init/project-config.md).

```json
{ "mode": "manual", "finish": "pr", "crossReview": true }
```

- **`mode: "manual"`** (Claude Code only) — superpowers stays quiet until
  you run `/sp <task>`; `/sp` routes the task (bug → debugging, feature →
  brainstorming, plan → execution, "finish" → finishing) and stays active
  for the rest of the session.
- **`finish: "pr"`** — finishing skips its menu and opens a PR.
- **`crossReview: true`** — before every PR, the other provider reviews the
  branch (Claude Code → `codex review`, Codex → `claude -p`), verified
  findings are fixed in at most two rounds, and the PR body lists fixed /
  rejected / open findings.

Files, highest precedence first: `.superpowers/config.local.json`
(personal — add it to `.gitignore`), `.superpowers/config.json`
(committed), `~/.config/superpowers/config.json` (global).

**Install the fork instead of, not alongside, the official plugin.** The
official plugin's SessionStart hook injects the full bootstrap regardless
of this config, so manual mode has no effect while both are enabled.
````

- [ ] **Step 2: Run all automated tests**

Run: `bash tests/hooks/test-session-start.sh && tests/project-config/test-skill-structure.sh`
Expected: both `STATUS: PASSED`.

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: fork section for project config, /sp, and cross-review"
```

- [ ] **Step 4: Behavioral setup**

```bash
SANDBOX=$(mktemp -d) && cd "$SANDBOX" && git init -q && git commit -q --allow-empty -m init
mkdir -p .superpowers && printf '{"mode": "manual"}\n' > .superpowers/config.json
claude plugin disable superpowers@claude-plugins-official
```

Record that the official plugin was disabled; re-enable it in Step 8.

- [ ] **Step 5: Manual mode checks (Claude Code)**

Run each in `$SANDBOX`, with `FORK=/Users/tulio/Projects/superpowers`:

```bash
claude -p --plugin-dir "$FORK" --output-format stream-json --verbose \
  "Let's make a react todo list" > manual.jsonl
claude -p --plugin-dir "$FORK" --output-format stream-json --verbose \
  "/sp let's make a react todo list" > sp.jsonl
printf '{"mode": "auto"}\n' > .superpowers/config.json
claude -p --plugin-dir "$FORK" --output-format stream-json --verbose \
  "Let's make a react todo list" > auto.jsonl
grep -c '"skill":"superpowers:brainstorming"' manual.jsonl sp.jsonl auto.jsonl
```

Expected: `manual.jsonl:0`, `sp.jsonl` ≥ 1, `auto.jsonl` ≥ 1. If the grep pattern finds nothing in `auto.jsonl`, inspect one `Skill` tool_use line (`grep -m1 '"name":"Skill"' auto.jsonl`) and adjust the pattern to the actual JSON shape before judging.

- [ ] **Step 6: `/sp-init` and Codex loading**

1. In an interactive `claude --plugin-dir "$FORK"` session in `$SANDBOX`, run `/sp-init`; choose `mode: manual`, `finish: pr`, `crossReview: true`, destination project local, answer yes to `.gitignore`. Expect `.superpowers/config.local.json` = `{"mode": "manual", "finish": "pr", "crossReview": true}` (pretty-printed), `.gitignore` containing `.superpowers/config.local.json`, `codex login status` run, nothing committed (`git status` shows them untracked/modified).
2. Run `codex` in a repo where the fork's skills are installed and check `sp` and `sp-init` appear in its skills list with no load error about `disable-model-invocation`. If Codex rejects the key, report it to your human partner — do not remove the key without their decision.

- [ ] **Step 7: Cross-review end to end**

Ask your human partner for a scratch GitHub repo they are happy to open a PR in. In it, with `.superpowers/config.local.json` = `{"finish": "pr", "crossReview": true}`, make a small change on a branch and, in Claude Code with `--plugin-dir "$FORK"`, ask to finish the branch. Expect: no menu, `codex review --base main` runs, findings handled, PR body contains `## Cross-provider review (Codex)`. Repeat from Codex; expect `claude -p` and `## Cross-provider review (Claude)`.

- [ ] **Step 8: Restore**

```bash
claude plugin enable superpowers@claude-plugins-official
```

Unless your human partner has switched to the fork as their installed plugin — ask before re-enabling.

- [ ] **Step 9: Report**

Report each behavioral check's result with the evidence (counts, file contents, PR URL). Any failure is reported as a failure, not worked around.
