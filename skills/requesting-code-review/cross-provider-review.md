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

Allow up to 15 minutes; use your harness's background execution and
timeout, not the `timeout` command (absent on macOS).

**Codex reviewer** (from the repo root):

```bash
REVIEW_OUT=$(mktemp -t cross-review.XXXXXX) && echo "$REVIEW_OUT" && \
  codex review --base <base-branch> > "$REVIEW_OUT" 2>&1; echo "exit=$?"
```

`codex review` refuses custom instructions together with `--base`; run it
with `--base` only. Note the printed path, then read that file — its
contents are the round's findings.

**Claude reviewer:** [code-reviewer.md](code-reviewer.md) is a dispatch
template. Take only the body under `prompt: |`, remove the 4-space indent,
fill the placeholders `[DESCRIPTION]` (what was built),
`[PLAN_OR_REQUIREMENTS]` (plan or spec path), `[BASE_SHA]`
(`git merge-base <base-branch> HEAD`), `[HEAD_SHA]` (`git rev-parse HEAD`).
Write the filled prompt to a temp file with your harness's file-write tool
(not echo/printf), e.g. `/tmp/cross-review-prompt-$(date +%s).md`, and note
its literal path. Then:

```bash
REVIEW_OUT=$(mktemp -t cross-review.XXXXXX) && echo "$REVIEW_OUT" && \
  claude -p "$(cat <prompt-file>)" \
    --allowedTools "Read,Grep,Glob,Bash(git diff:*),Bash(git log:*),Bash(git show:*)" \
    > "$REVIEW_OUT" 2>&1; echo "exit=$?"
```

where `<prompt-file>` is the literal path you noted. The single path the
command prints is the output file; read that file — its contents are the
round's findings. `claude -p` needs network access and writes under
`~/.claude`; the default Codex sandbox blocks both. Request escalated
permissions for this one command.

## The loop (at most 2 rounds)

1. **Round 1.** Run a round. Apply `superpowers:receiving-code-review` to
   every finding: verify it against the code, then mark it *accepted* or
   *rejected* with a one-line reason. Codex output carries no severity
   labels; assign Critical / Important / Minor yourself while verifying.
2. Fix the accepted findings. Run the full test suite. Commit:
   `fix: address cross-review findings`.
3. **Round 2** — only if round 1 changed code. Run a round. Fix only
   findings that are Critical or Important *and* verified; run the suite;
   commit with the same message. No round 3. A round-2 finding that
   repeats one you rejected in round 1 stays rejected — do not
   re-litigate it.
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

CLI missing, not logged in, timeout, sandbox denial, non-zero exit, or
output you cannot read as a review: stop and ask in one line —

> Cross-review failed (<reason>). Open the PR without it, or fix it and retry?

Never skip the review silently. If your human partner says to proceed,
the PR body section reads: `## Cross-provider review (<Reviewer>)` then
`Not run — <reason>.`
