# PR Watch

After the PR is open, keep watching it until it is ready to merge: wait for
checks, fix failures, answer review threads, get CodeRabbit past its rate
limit, and record the outcome in the PR body. Called by
`finishing-a-development-branch` when the project config sets
`watchPr: true`. Input: the PR number `<n>` and `<base-branch>`.

`watchPr: true` is your human partner's standing authorization. Without
asking, you may:

- push fix commits with a normal push; never force-push;
- reply to review threads;
- comment `@coderabbitai review`;
- run `gh run rerun <id> --failed`, once per run;
- edit the PR body once, at the end.

Never merge, close, approve, or resolve threads, and never tick
CodeRabbit's "Run on-demand review" checkbox — it bills.

## Before you start

The watch is GitHub only. Run `gh auth status`. If it fails, or the forge
is not GitHub, say so in one line and skip the watch. The PR is already
open; nothing else changes.

## Reading the PR

Get `<owner>/<repo>` from `gh repo view --json nameWithOwner`.

```bash
# HEAD and the PR author's login
gh pr view <n> --json headRefOid,author
# Issue comments (CodeRabbit's summary comment lives here)
gh api repos/<owner>/<repo>/issues/<n>/comments --paginate
# Reviews, each with its commit_id
gh api repos/<owner>/<repo>/pulls/<n>/reviews --paginate
# Review threads
gh api graphql -F owner=<owner> -F repo=<repo> -F n=<n> -f query='
query($owner: String!, $repo: String!, $n: Int!) {
  repository(owner: $owner, name: $repo) { pullRequest(number: $n) {
    reviewThreads(first:100) { nodes { isResolved isOutdated
      comments(first:50) { nodes { databaseId author { login } body createdAt } } } }
  } }
}'
```

Reply in a thread with
`gh api repos/<owner>/<repo>/pulls/<n>/comments/<databaseId>/replies -f body='<reply>'`,
using the `databaseId` of the thread's first comment.

## Known reviewers

| Reviewer | Recognize by | States | Re-trigger | Severity rule |
|---|---|---|---|---|
| CodeRabbit | author `coderabbitai[bot]` | reviewing / rate limited / clean / reviewed with findings (markers below). A rate limit counts for HEAD only when its `headCommitId` matches HEAD. | `@coderabbitai review`, after the wait. **Never** tick "Run on-demand review". | Every thread needs an answer, whatever its label. |
| Grok PR Reviewer | body ends with `by Grok PR Reviewer` (posted from the PR author's account) | Present or absent. Never waited for. | None. | Classify each thread from its content (below). Minor and pre-existing threads do not block and need no reply; they go into the report. Anything else is handled like any finding. |
| Anyone else (humans, unknown bots) | any other thread | Not waited for; existing threads are handled. | None. | Every thread needs an answer. |

**CodeRabbit** keeps one summary comment per PR and edits it in place. Read
its current body and its `updated_at`:

- **Reviewing:** contains
  `<!-- This is an auto-generated comment: review in progress by coderabbit.ai -->`
  and "Currently processing new changes in this PR".
- **Rate limited:** a block between
  `<!-- This is an auto-generated comment: rate limited by coderabbit.ai -->`
  and `<!-- end of auto-generated comment: rate limited by coderabbit.ai -->`,
  headed `## Review limit reached`. It says "Or wait N minutes for your next
  included review." and carries a checkbox JSON with `"headCommitId"`. It
  also offers the billed "Run on-demand review" checkbox — leave it alone.
- **Clean:** the `<!-- recent_review_start -->` section reads "No
  actionable comments were generated in the recent review." Its
  "📥 Commits" details name the reviewed head SHA; it is clean for HEAD
  only when that SHA is HEAD. No GitHub review is created in this case.
- **Reviewed with findings:** a review from `coderabbitai[bot]` whose
  `commit_id` is the head, plus inline threads carrying severity labels
  such as `🟡 Minor`.

CodeRabbit **has reviewed this PR** if it left a review on any commit, or
"No actionable comments" for any commit.

**Grok PR Reviewer** has no severity labels. Start from the review body's
overall verdict ("Nada bloqueante", "não vi nada bloqueante"), then read
each thread's prose: "Opcional:" or "não bloqueia este PR" marks Minor;
"Ponto anterior ao PR" or "pré-existente" marks pre-existing.

## Answered threads

A thread is answered when either holds:

- it is resolved; or
- after the reviewer's last comment, there is a reply from the PR author's
  account that does not end with `by Grok PR Reviewer`.

If the reviewer comments again after your reply, read it. An
acknowledgement ("thanks, that resolves it") keeps the thread answered. A
new point makes it pending; handle it in the next round.

## The loop

```
1. WAIT      until every check on HEAD has finished, and every known
             reviewer that is present has left "reviewing"
2. EVALUATE  collect what is pending
3. STOP?     if the stop conditions hold: report and end
4. ACT       re-trigger CodeRabbit, or run a fix round; go back to 1
```

**Budget:** at most 3 rounds of fixes (a CI fix counts as a round) and
2 re-triggers of CodeRabbit.

**Stop conditions — all must hold:**

1. Every check on HEAD has completed and none failed.
2. CodeRabbit shows "No actionable comments" for HEAD, **or** it has
   reviewed this PR and every CodeRabbit thread is answered. If CodeRabbit
   is not on the PR at all, this holds.
3. No unanswered thread from a human or an unknown reviewer, and no
   unanswered Grok thread above Minor that is not pre-existing.

**ACT, in priority order:**

1. **CodeRabbit is rate-limited and has never reviewed this PR.** Wait
   until the comment's `updated_at` + N minutes + 1 minute, then comment
   `@coderabbitai review` (`gh pr comment <n> --body '@coderabbitai review'`).
   This uses one of the 2 re-triggers; when they are spent, stop and
   report. If CodeRabbit has reviewed before and only the post-fix
   re-review is limited, do not re-trigger: condition 2 is met once its
   threads are answered.
2. **Fix round.** This uses one of the 3 rounds; when they are spent,
   stop and report.
   - Gather the failing checks and pending threads. Apply
     `superpowers:receiving-code-review` to each thread: verify it against
     the code, then mark it *accepted* or *rejected* with a reason.
   - For a failing check, read `gh run view <id> --log-failed` and apply
     `superpowers:systematic-debugging`. If the PR caused the failure, fix
     it. If it is flaky or infrastructure, run `gh run rerun <id> --failed`
     once per run; a rerun alone does not use a round.
   - Run the full local suite. If it is red and you cannot fix it, stop
     and report to your human partner: no push on a red suite.
   - Make **one** commit (`fix: address PR review and CI`) and **one**
     normal push.
   - Reply in each handled thread: "Fixed in `<sha>`: …" or the reason
     for rejecting it. Reply in the language of the thread.

**Waiting.** Use your harness's background execution and timeout, as
cross-review does:

- **CI:** `gh pr checks <n> --watch`. Find each failing run's `<id>` in
  the link from `gh pr checks <n> --json name,bucket,link`.
- **Reviewers:** poll the comments and threads every 2 minutes, for up to
  20 minutes per wait. If CodeRabbit is still "reviewing" after 20 minutes,
  stop and report it instead of waiting forever.
- **Rate-limit waits:** a background `sleep <seconds>`. In Claude Code,
  the background command re-invokes the session when it exits. In Codex,
  run it in the foreground.

## Report

Write the report in chat:

```markdown
## PR watch
Checks: green · CodeRabbit: no actionable comments (<sha>) · Rounds: 1/3
- **Fixed:** <finding> — <sha>
- **Rejected:** <finding> — <reason>
- **Minor (Grok):** <point>
- **Pre-existing:** <point>
- **Open:** <what is left when the budget ran out>
```

Write "none" for an empty list. Then write it into the PR body once. Read
the current body (`gh pr view <n> --json body -q .body`). With your
harness's file-write tool, write the new body to a temp file: replace an
existing `## PR watch` section or append one, and
leave the rest of the body untouched. Apply it with
`gh pr edit <n> --body-file <file>`.

The worktree stays in place.
