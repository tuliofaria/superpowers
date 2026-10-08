# PR Watch — Design

Date: 2026-10-08
Status: approved by Tulio (in-session); spec pending review
Branch: `feat/pr-watch` off `main` (fork: `tuliofaria/superpowers`)

## Goal

After `finishing-a-development-branch` opens a PR, the agent keeps
watching it until the PR is ready to merge, instead of stopping at the URL.
It waits for GitHub checks, fixes failures, answers review threads, gets
CodeRabbit past its rate limit, and records the outcome in the PR body.

## Scope decisions (settled with Tulio)

- **Fork only**, like the project config and cross-review work.
- **Activation: new config key `watchPr: true | false`** (default
  `false`). It applies to every PR the finishing skill opens, whether
  through the menu, the detached-HEAD option, or `finish: "pr"`.
- **Standing authorization.** `watchPr: true` authorizes these actions
  without asking:
  - push fix commits (normal push only, never a force-push);
  - reply to review threads;
  - comment `@coderabbitai review`;
  - rerun failed CI jobs once;
  - edit the PR body once at the end.

  It never authorizes merging, closing, approving, resolving threads,
  or ticking CodeRabbit's billed "Run on-demand review" checkbox.
- **Grok PR Reviewer is handled only if it shows up.** The loop never
  waits for it.
- **Budget:** 3 fix rounds (a CI fix counts as a round) and 2 CodeRabbit
  re-triggers.
- **Report:** in chat, plus a `## PR watch` section in the PR body,
  written once at the end.
- **Structure:** a procedure file
  `skills/finishing-a-development-branch/pr-watch.md` called by finishing.
  This follows the same pattern as `cross-provider-review.md`, so no new
  skill is added.

## Observed reviewer behavior (id49/atende.vc PRs #339, #340, #343)

Everything below was verified against real PRs, including comment edit
history read through GraphQL `userContentEdits`.

**CodeRabbit** (`coderabbitai[bot]`) keeps one summary comment per PR and
edits it in place:

- **Reviewing.** The comment contains the marker
  `<!-- This is an auto-generated comment: review in progress by coderabbit.ai -->`
  and the text "Currently processing new changes in this PR…". The #339
  review took about 6 minutes.
- **Rate limited.** The block sits between
  `<!-- This is an auto-generated comment: rate limited by coderabbit.ai -->`
  and `<!-- end of auto-generated comment: rate limited by coderabbit.ai -->`.
  - It is headed `## Review limit reached`.
  - The wait time appears as "Or wait N minutes for your next included
    review."
  - A checkbox JSON carries `"headCommitId"`.
  - The block also offers a "Run on-demand review" checkbox, which bills
    ("costs up to $1.50").
  - The allowance observed was about 1 review per hour. In #340 and
    #343, the fix push after the first review hit the limit.
- **Clean.** The `<!-- recent_review_start -->` section reads "No
  actionable comments were generated in the recent review." Its
  "📥 Commits" details name the reviewed head SHA. No GitHub review
  object is created in this case.
- **Reviewed with findings.** A GitHub review from the bot with
  `commit_id` set to the head, plus inline threads. Each thread finding
  carries a severity label such as `🟡 Minor`.
- **Re-trigger (#340).** About 29 minutes after a "wait 13 minutes"
  block, the comment `@coderabbitai review` worked:
  - after about 9 seconds, a reply containing
    `<!-- CodeRabbit review command invocation … -->`;
  - after about 20 seconds, the rate-limit block was removed;
  - after about 4.5 minutes, the review was posted;
  - the reply was then edited to "✅ Action performed — Review finished."
- **Thread follow-up (#340).** After our reply ("Corrigido em
  7c870d8: …"), the bot confirmed in-thread and the thread ended up
  resolved.

**Grok PR Reviewer** posts from the PR author's own account. Every review
body and inline thread ends with `by Grok PR Reviewer`. It has no
severity labels. Severity is expressed in prose ("Opcional:",
"não bloqueia este PR", "Ponto anterior ao PR", "pré-existente"), and
the review body gives an overall verdict ("Nada bloqueante",
"não vi nada bloqueante").

## Component 1: `skills/finishing-a-development-branch/pr-watch.md`

Input: PR number and `<base-branch>`. Written in the same voice and
format as `cross-provider-review.md`. The file is the source of truth;
this section summarizes it.

### Forge check

GitHub only: the procedure needs `gh` to be authenticated. On any other
forge, or if `gh auth status` fails, the agent says so in one line and
skips the watch. The PR is already open, so nothing else changes.

### The loop

```
1. WAIT      until every check on HEAD has finished, and every known
             reviewer that is present has left "reviewing"
2. EVALUATE  collect failing checks, pending threads, and unhandled
             outside-diff findings
3. STOP?     if the stop conditions hold: report and end
4. ACT       re-trigger CodeRabbit, or run a fix round; go back to 1
```

**Register first.** Every WAIT starts by waiting, polling about every
30 seconds, for the last action to register. `gh pr checks` answers
"no checks reported on the '<branch>' branch" (exit 1) until a check
registers; that is pending, never green.

- **After the PR is created:** up to 5 minutes, until a check is
  registered (if the repo has CI: `.github/workflows/` exists or the base
  branch's head has checks) and until CodeRabbit's summary comment
  appears (if `.coderabbit.yaml` exists or CodeRabbit commented on one of
  the last 5 PRs). Whatever is still missing after 5 minutes is skipped
  and listed under **Open**.
- **After a push:** up to 5 minutes, until every check name recorded
  before the push (the fix round records them just before `git push`,
  because afterwards `gh pr checks` reports the new HEAD) is registered
  on the new HEAD (CodeRabbit's own commit status,
  always green, is not enough) and CodeRabbit, if present, reacts to the
  new HEAD. Then the agent watches what is registered.
- **After `gh run rerun`:** up to 5 minutes, until that check leaves the
  failed state; otherwise stop and report under **Open**.
- **After `@coderabbitai review`:** CodeRabbit counts as reviewing, and is
  never re-triggered, until a review or "No actionable comments" for HEAD
  appears, a rate-limit block appears whose `updated_at` is after the
  comment, or the invocation reply reads "Review finished". After 20
  minutes without any of these: stop and report under **Open**.

**Outside-diff findings.** CodeRabbit puts findings it cannot place on
the diff in its review body under "Outside diff range comments (N)",
not in threads. EVALUATE reads the latest CodeRabbit review body; each
such comment is a finding for the fix round, recorded as Fixed or
Rejected in the report (no thread to reply to). "Nitpick comments" in the
body are listed in the report, not acted on.

**Stop conditions (all must hold):**

1. Every check on HEAD has completed and none failed.
2. CodeRabbit has "No actionable comments" for HEAD, **or** it has
   reviewed this PR at least once (a review on any commit, or "No
   actionable comments" for any commit), every CodeRabbit thread is
   answered, and every outside-diff finding is handled. If CodeRabbit is
   not on the PR at all, this condition holds trivially.
3. No unanswered thread exists from a human or an unknown reviewer, and
   no unanswered Grok thread exists that is above Minor and not
   pre-existing.

**ACT, in priority order:**

1. **CodeRabbit is rate-limited for HEAD and has never reviewed this
   PR.** Only a block whose `updated_at` is newer than the last
   `@coderabbitai review` counts. Wait until `updated_at` plus N minutes
   plus 1 minute of slack, then comment `@coderabbitai review`. This uses
   one of the 2 re-triggers. When the budget is spent, stop and report.
   If CodeRabbit has reviewed before and only the post-fix re-review is
   limited, do not re-trigger: stop condition 2 is met once its threads
   and outside-diff findings are handled.
2. **Fix round.** This uses one of the 3 rounds; when the budget is
   spent, stop and report.
   - Gather the failing checks, pending threads, and unhandled
     outside-diff findings, and apply `superpowers:receiving-code-review`
     to each. Verify it, then mark it accepted or rejected with a reason.
   - For a failing check, read `gh run view <id> --log-failed` and apply
     `superpowers:systematic-debugging`. If the PR caused the failure,
     fix it. If it is flaky or infrastructure, run
     `gh run rerun <id> --failed` once per run; this does not use a round.
   - If the round changed code, run the full local suite. If it is red
     and cannot be fixed, stop: no push on a red suite.
   - Then make **one** commit (`fix: address PR review and CI`), record
     the PR's check names (`gh pr checks <n> --json name`), and push it
     with `git push origin HEAD:<headRefName>` (works from a detached
     HEAD). If the push is rejected, stop and report under **Open**: no
     "Fixed in" replies, and never pull, rebase, or force. A round where
     every finding is rejected changes no code: replies only, no commit.
   - Only after a successful push (or when nothing was committed), reply
     in each handled thread, either "Fixed in `<sha>`: …" or the reason
     for rejecting it, in the language of the thread.
3. **Otherwise, stop.** If neither applies, or a round would change
   nothing, stop and report the blocker under **Open** (e.g. CodeRabbit
   is present, never reviewed, and is not rate-limited; a check not
   caused by the PR fails again after its one rerun).

**Waiting.** Use the harness's background execution and timeout, as
cross-review does:

- **CI:** `gh pr checks <n> --watch`, once checks are registered, for up
  to 60 minutes (harness timeout set to match); if checks are still
  pending, stop and report them under **Open**.
- **Reviewers:** poll the comments and threads every 2 minutes, for up
  to 20 minutes per wait. If CodeRabbit stays in "reviewing" past that
  limit, report it instead of waiting forever.
- **Rate-limit waits:** a background `sleep`, with the harness timeout
  set above the sleep. In Claude Code, the background command re-invokes
  the session when it exits. In Codex, run it in the foreground. On
  waking, compare the clock with the target before commenting.

### Reading the PR

- HEAD and branch: `gh pr view <n> --json headRefOid,headRefName,author`.
- Issue comments: `gh api repos/<owner>/<repo>/issues/<n>/comments --paginate`.
- Reviews: `gh api repos/<owner>/<repo>/pulls/<n>/reviews` (`commit_id`, body).
- Threads: GraphQL `pullRequest.reviewThreads { isResolved isOutdated
  comments { databaseId author { login } body createdAt } }`.
- Replies: the reply text is written to a file and sent with
  `gh api .../pulls/<n>/comments/<databaseId>/replies -F body=@<file>`.

### Known reviewers (table in the file)

| Reviewer | Recognize by | States | Re-trigger | Severity rule |
|---|---|---|---|---|
| CodeRabbit | author `coderabbitai[bot]` (REST) / `coderabbitai` (GraphQL) | The markers above: reviewing / rate limited / clean / reviewed with findings. A rate limit counts for HEAD only when `headCommitId` matches HEAD. | `@coderabbitai review`, after the wait. **Never** tick "Run on-demand review". | Every thread and outside-diff finding needs an answer, whatever its label. |
| Grok PR Reviewer | body ends with `by Grok PR Reviewer` (the author is the PR author's account) | Present or absent. Never waited for. | None. | The agent classifies each thread from its content, using the review-body verdict as the starting point. Minor and pre-existing threads do not block and need no reply; they go into the report. Anything else is handled like any finding. |
| Anyone else (humans, unknown bots) | any other thread | Not waited for; existing threads are handled. | None. | Every thread needs an answer. |

### "Answered"

A thread is answered when it is resolved, or when a reply of ours comes
after the reviewer's last comment. Ours are the replies the agent posted
in this watch, and, in a thread someone else opened (Grok included), a
reply from the PR author's account that does not end with
`by Grok PR Reviewer`. Every other comment is the reviewer's, so a thread
the PR author opened on their own PR is answered only by the agent's
replies from this watch.

If the reviewer comments again after our reply, the agent reads the
comment. An acknowledgement ("thanks, that resolves it") keeps the
thread answered. A new point makes it pending, and it is handled in the
next round.

### Report

Every stop, clean or not, ends in the report. Write it in chat. Then
write it into the PR body once, at the end, with
`gh pr edit <n> --body-file <file>`. If a `## PR watch` section already
exists, replace it; leave the rest of the body untouched.

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

Write "none" for an empty list. The worktree stays in place.

## Component 2: `finishing-a-development-branch/SKILL.md`

- **Step 2b** lists a third key: `watchPr` — `false` (default) or `true`.
- **Option 2** (including the detached-HEAD PR option and the
  `finish: "pr"` shortcut): after the PR is created and its URL reported,
  if `watchPr: true`, follow [pr-watch.md](pr-watch.md) with the PR
  number and `<base-branch>`.
- **New row in Common Rationalizations:**

| Excuse | Reality |
|---|---|
| "Checks are still running — I'll report the URL and stop" | With `watchPr`, the work ends when the PR is ready, not when it is opened. Follow pr-watch.md. |

## Component 3: config and `/sp-init`

- `skills/sp-init/project-config.md`: add `watchPr` to the schema
  example and to the key table (`true` | `false`, default `false`; effect:
  after opening a PR, finishing watches it until checks and reviews
  settle).
- `skills/sp-init/SKILL.md`: add a question for `watchPr`. When the
  answer is `true`, check `gh auth status` in the same way `crossReview`
  checks the Codex login.

## Component 4: README (fork section)

Add one bullet for `watchPr` to the fork section, and add the key to its
JSON example.

## Files touched

| File | Change |
|---|---|
| `skills/finishing-a-development-branch/pr-watch.md` | new |
| `skills/finishing-a-development-branch/SKILL.md` | Step 2b key, Option 2 call, rationalization row |
| `skills/sp-init/project-config.md` | `watchPr` key |
| `skills/sp-init/SKILL.md` | `watchPr` question and `gh auth status` check |
| `tests/project-config/test-skill-structure.sh` | new assertions |
| `README.md` | fork section bullet |

## Testing

**Structural tests** (`tests/project-config/test-skill-structure.sh`,
using the existing `require_file` / `require_text` helpers):

- `pr-watch.md` exists and contains:
  - `rate limited by coderabbit.ai`
  - `review in progress by coderabbit.ai`
  - `No actionable comments`
  - `@coderabbitai review`
  - `Run on-demand review`
  - `by Grok PR Reviewer`
  - `superpowers:receiving-code-review`
  - `superpowers:systematic-debugging`
  - `## PR watch`
  - the register-wait, outside-diff, CI-cap, push and reply phrases
    (`**Register first.**`, `no checks reported`,
    `Outside diff range comments`, `60 minutes`,
    `git push origin HEAD:<headRefName>`, `-F body=@<file>`,
    `**Otherwise, stop.**`)
- finishing references `pr-watch.md` and `watchPr`.
- `project-config.md` and `sp-init/SKILL.md` mention `watchPr`.

**Live check.** In atende.vc, with `watchPr: true` in
`.superpowers/config.local.json`, finish a real branch through
`finish: "pr"` and confirm:

- CI is watched;
- the CodeRabbit state is read correctly (including a rate-limit wait
  and re-trigger, if one happens);
- threads are answered;
- Grok minors land in the report;
- the `## PR watch` section is written once.

No Quorum eval: this change is fork-only.

## Out of scope

- `/sp watch <PR>`, to use the loop on PRs that finishing did not open.
- Auto-merge.
- GitLab and other forges.
- Waiting for human reviewers or for Grok to appear.
- Re-triggering CodeRabbit just to re-review fixes once its threads are
  answered.
- Upstream PR.
