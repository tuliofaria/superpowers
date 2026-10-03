# Superpowers Project Config

Per-project defaults for this fork of superpowers. Three optional JSON
files, all with the same flat shape:

```json
{
  "mode": "auto",
  "finish": "ask",
  "crossReview": false,
  "execution": "ask"
}
```

| Key | Values | Default | Effect |
|---|---|---|---|
| `mode` | `"auto"` \| `"manual"` | `"auto"` | `manual`: superpowers stays quiet until your human partner runs `/sp`. Applies in harnesses that run the SessionStart hook (not Codex) — the hook reads it. |
| `finish` | `"ask"` \| `"pr"` | `"ask"` | `pr`: `finishing-a-development-branch` skips its menu and opens a PR. |
| `crossReview` | `true` \| `false` | `false` | `true`: before any PR push, run the cross-provider review loop. |
| `execution` | `"ask"` \| `"subagent"` \| `"native"` | `"ask"` | How an approved plan is executed: `subagent` → `superpowers:subagent-driven-development`, `native` → `superpowers:executing-plans`, `ask` → ask each time. `subagent` without a subagent tool runs as `native`, said out loud. Never skips plan review. A method your human partner states explicitly in the conversation wins over this setting. |

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
| project (committed, shared) | `<repo>/.superpowers.json` |
| global | `~/.config/superpowers/config.json` |

The committed file lives at the repo root, not inside `.superpowers/`:
projects commonly gitignore `.superpowers/` (superpowers' own scratch
space), and git cannot re-include a file under an ignored directory.

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
