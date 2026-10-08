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

Never merge, close, approve, or resolve threads, never pull or rebase
others' commits, and never tick CodeRabbit's "Run on-demand review"
checkbox — it bills.

## Before you start

The watch is GitHub only. Run `gh auth status`. If it fails, or the forge
is not GitHub, say so in one line and skip the watch. The PR is already
open; nothing else changes.

## Reading the PR

Get `<owner>/<repo>` from `gh repo view --json nameWithOwner`.

```bash
# HEAD, the PR's branch name, and the PR author's login
gh pr view <n> --json headRefOid,headRefName,author
# Issue comments (CodeRabbit's summary comment lives here)
gh api repos/<owner>/<repo>/issues/<n>/comments --paginate
# Reviews, each with its commit_id and body
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

To reply in a thread, write the reply to a temp file with your harness's
file-write tool (quotes and apostrophes then survive), and run
`gh api repos/<owner>/<repo>/pulls/<n>/comments/<databaseId>/replies -F body=@<file>`,
using the `databaseId` of the thread's first comment.

## Known reviewers

| Reviewer | Recognize by | States | Re-trigger | Severity rule |
|---|---|---|---|---|
| CodeRabbit | author `coderabbitai[bot]` (REST) / `coderabbitai` (GraphQL) | reviewing / rate limited / clean / reviewed with findings (markers below). A rate limit counts for HEAD only when its `headCommitId` matches HEAD. | `@coderabbitai review`, after the wait. **Never** tick "Run on-demand review". | Every thread and outside-diff finding needs an answer, whatever its label. |
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

**Outside-diff findings.** CodeRabbit puts findings it cannot place on
the diff in its latest review's body, under "Outside diff range comments
(N)". Each is a finding for the next fix round, handled once and recorded
as Fixed or Rejected in the report (it has no thread to reply to).
"Nitpick comments" there are not acted on; list them in the report.

**Grok PR Reviewer** has no severity labels. Start from the review body's
overall verdict ("Nada bloqueante", "não vi nada bloqueante"), then read
each thread's prose: "Opcional:" or "não bloqueia este PR" marks Minor;
"Ponto anterior ao PR" or "pré-existente" marks pre-existing.

## Answered threads

A thread is answered when it is resolved, or when a reply of ours comes
after the reviewer's last comment. Ours are the replies you posted in
this watch (note the `id` each reply returns: the comment's
`databaseId`). In a thread someone else opened, Grok included, a reply
from the PR author's account that
does not end with `by Grok PR Reviewer` is ours too. Every other comment
is the reviewer's, so a thread the PR author opened on their own PR is
answered only by your replies.

If the reviewer comments again after your reply, read it. An
acknowledgement ("thanks, that resolves it") keeps the thread answered. A
new point makes it pending; handle it in the next round.

## The loop

```
1. WAIT      until every check on HEAD has finished, and every known
             reviewer that is present has left "reviewing"
2. EVALUATE  collect failing checks, pending threads, and unhandled
             outside-diff findings
3. STOP?     if the stop conditions hold: report and end
4. ACT       re-trigger CodeRabbit, or run a fix round; go back to 1
```

**Register first.** Every WAIT starts by waiting for the last action to
register, polling about every 30 seconds. `gh pr checks` answers
"no checks reported on the '<branch>' branch" (exit 1) until a check
registers: that is pending, never green.

- **After the PR is created** (the first WAIT): up to 5 minutes, until a
  check is registered, if the repo has CI (`.github/workflows/` exists,
  or `gh api repos/<owner>/<repo>/commits/<base-branch>/check-runs`
  shows checks), and until CodeRabbit's summary comment appears, if
  `.coderabbit.yaml` exists or CodeRabbit commented on one of the last 5
  PRs (`gh pr list --state all --limit 5 --json comments`). Whatever is
  still missing after 5 minutes: go on without it and list it under
  **Open**.
- **After a push:** up to 5 minutes, until
  each name you recorded before the push is registered on the new HEAD
  (CodeRabbit's own status, always green, is not enough) and CodeRabbit,
  if on the PR, reacts to it: reviewing, a review or "No actionable
  comments" for it, or a rate-limit block with
  its `headCommitId`. Then watch what is registered.
- **After `gh run rerun`:** up to 5 minutes, until that check is no longer
  failed. If it still is, stop and report it under **Open**.
- **After `@coderabbitai review`:** CodeRabbit counts as reviewing, and
  is never re-triggered, until a review or "No actionable comments" for
  HEAD appears, a rate-limit block appears whose `updated_at` is after
  your comment, or its invocation reply (containing
  `<!-- CodeRabbit review command invocation`) reads "Review finished".
  If none of these happens within 20 minutes, stop and report it under
  **Open**.

**Budget:** at most 3 rounds of fixes (a CI fix counts) and 2 re-triggers.

**Stop conditions — all must hold:**

1. Every check on HEAD has completed and none failed.
2. CodeRabbit shows "No actionable comments" for HEAD, **or** it has
   reviewed this PR, every CodeRabbit thread is answered, and every
   outside-diff finding is handled. If CodeRabbit is not on the PR at
   all, this holds.
3. No unanswered thread from a human or an unknown reviewer, and no
   unanswered Grok thread above Minor that is not pre-existing.

**ACT, in priority order:**

1. **CodeRabbit is rate-limited for HEAD and has never reviewed this PR.**
   Act only on a block whose `updated_at` is after your last
   `@coderabbitai review`, if any. Wait until the comment's
   `updated_at` + N minutes + 1 minute, then comment
   `@coderabbitai review` (`gh pr comment <n> --body '@coderabbitai review'`).
   This uses one of the 2 re-triggers; when they are spent, stop and
   report. If CodeRabbit has reviewed before and only the post-fix
   re-review is limited, do not re-trigger: condition 2 is met once its
   threads and outside-diff findings are handled.
2. **Fix round.** This uses one of the 3 rounds; when they are spent,
   stop and report.
   - Gather the failing checks, pending threads, and unhandled
     outside-diff findings. Apply `superpowers:receiving-code-review` to
     each finding: verify it against the code, then mark it *accepted* or
     *rejected* with a reason.
   - For a failing check, read `gh run view <id> --log-failed` and apply
     `superpowers:systematic-debugging`. If the PR caused the failure, fix
     it. If it is flaky or infrastructure, run `gh run rerun <id> --failed`
     once per run; a rerun alone does not use a round.
   - If the round changed code: run the full local suite. If it is red
     and you cannot fix it, stop and report to your human partner:
     no push on a red suite. Then make **one** commit
     (`fix: address PR review and CI`).
     Before the push, record the check names on the PR
     (`gh pr checks <n> --json name`): once pushed, that command reports
     the new HEAD. Push once with
     `git push origin HEAD:<headRefName>` (this works from a detached
     HEAD too). If the push is rejected, stop and report it under
     **Open**: post no "Fixed in" reply, and never pull, rebase, or
     force. A round where every finding is rejected changes no code:
     replies only, no commit.
   - Only after the push succeeds (or when nothing was committed), reply
     in each handled thread: "Fixed in `<sha>`: …" or the reason for
     rejecting it, in the language of the thread. Outside-diff findings
     go into the report as Fixed or Rejected.
3. **Otherwise, stop.** If neither applies, or a round would change
   nothing (no code, no reply, no rerun, no finding to record), stop and
   report the blocker under **Open**. Examples: CodeRabbit is on the PR,
   never reviewed it, and is not rate-limited; a check not caused by the
   PR fails again after its one rerun.

**Waiting.** Use your harness's background execution and timeout, as
cross-review does:

- **CI:** once checks are registered, `gh pr checks <n> --watch`, for up
  to 60 minutes (set the harness timeout to match). If checks are still
  pending, stop and report them under **Open**. Find each failing run's
  `<id>` in the link from `gh pr checks <n> --json name,bucket,link`.
- **Reviewers:** poll the comments and threads every 2 minutes, for up to
  20 minutes per wait. If CodeRabbit is still "reviewing" after 20 minutes,
  stop and report it instead of waiting forever.
- **Rate-limit waits:** a background `sleep <seconds>`, with the harness
  timeout set above the sleep (Claude Code's default is 30 minutes); it
  re-invokes the session when it exits. In Codex, run it in the
  foreground. On waking, compare `date -u` with the target time; if it is
  early, sleep the rest before commenting.

## Report

Every stop, clean or not, ends here. Write the report in chat:

```markdown
## PR watch
Checks: green · CodeRabbit: no actionable comments (<sha>) · Rounds: 1/3
- **Fixed:** <finding> — <sha>
- **Rejected:** <finding> — <reason>
- **Nitpicks (CodeRabbit):** <point>
- **Minor (Grok):** <point>
- **Pre-existing:** <point>
- **Open:** <what is left, and why>
```

Write "none" for an empty list. Then write it into the PR body once. Read
the current body (`gh pr view <n> --json body -q .body`). With your
harness's file-write tool, write the new body to a temp file: replace an
existing `## PR watch` section or append one, and
leave the rest of the body untouched. Apply it with
`gh pr edit <n> --body-file <file>`.

The worktree stays in place.
