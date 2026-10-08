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

1. `mode` — "auto" (superpowers triggers on its own) or "manual" (only via `/sp`; applies in harnesses that run the SessionStart hook, not Codex)?
2. `finish` — "ask" (menu at the end) or "pr" (always open a PR)?
3. `crossReview` — review with the other provider (Claude Code → Codex, Codex → Claude) before every PR?
4. `execution` — how to run approved plans: "ask" each time, "subagent" (subagent-driven, a reviewer per task), or "native" (in-session, one review at the end)?
5. `watchPr` — after opening a PR, keep watching it (CI, CodeRabbit, review threads) until it is ready to merge?
6. Destination — project committed (`.superpowers.json`), project local (`.superpowers/config.local.json`, written to `<main>/.superpowers/config.local.json` in a linked worktree), or global (`~/.config/superpowers/config.json`)?

Offer the current effective value as the default answer for each.

## Step 3: Check the tools

**When `crossReview` is true:**

- In Claude Code: run `codex login status`. Expect "Logged in".
- In Codex: run `claude --version`.

If the check fails, tell your human partner what is missing (install with
`npm install -g @openai/codex` and `codex login`, or install Claude Code)
and continue — the setting is saved anyway.

**When `watchPr` is true:** run `gh auth status`; expect it to report a
logged-in account. If it fails, tell your human partner to run
`gh auth login`, and continue — the setting is saved anyway.

## Step 4: Write the file

- Create the destination's parent directory if needed.
- If the destination already exists and is valid JSON, keep its other
  keys. If it exists but is not valid JSON, show your human partner the
  current content and ask "Replace this with config?" On yes, start from
  `{}`; on no, stop without writing.
- For each answered key, compute the value the layers *below* the
  destination would produce (lower-precedence files, then the default;
  precedence order: local > project > global > default — see
  project-config.md). If the answer equals that value, remove the key from
  the destination; otherwise set it explicitly.
- Write pretty-printed JSON with a trailing newline. If the result is
  `{}`, still write it.

## Step 5: `.gitignore`

**Project local destination:** run
`git check-ignore -q .superpowers/config.local.json` from `<main>` (the
main checkout; see project-config.md, `<main>`).
- Exit 0 (already ignored, e.g. by a `.superpowers/` rule): say so; do
  not ask.
- Otherwise ask: "Add `.superpowers/config.local.json` to this repo's
  `.gitignore`?" On yes, append that line to `<main>/.gitignore`. On no,
  change nothing.

**Project committed destination:** run `git check-ignore -q .superpowers.json`.
Exit 0 means a rule ignores it: warn your human partner that the file will
not be committed as-is and show the matching rule
(`git check-ignore -v .superpowers.json`). Do not edit `.gitignore`.

## Step 6: Report

Show the written file's path and contents. Never commit — your human
partner decides whether and when the committed config goes into git.
