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
| An existing plan file, or "execute the plan" | If your human partner named an execution method in this conversation (including in the `/sp` arguments), use it — it wins over the config. Otherwise, per the project config's `execution` ([project-config.md](../sp-init/project-config.md)): `subagent` → `superpowers:subagent-driven-development`; `native` → `superpowers:executing-plans`; `ask` → ask which, recommending subagent-driven when you have a subagent tool. `subagent` without a subagent tool → `native`, said out loud. |
| Finishing work: "finish", "open the PR", "wrap up" | `superpowers:finishing-a-development-branch` |

Empty arguments: ask your human partner what they want to do, then route.
A task that fits more than one row: ask one question to decide.

## Step 3: Follow through

Follow the invoked skill's chain to its terminal state, including
`superpowers:finishing-a-development-branch` when the chain reaches it.
Every approval gate in those skills still applies: `/sp` starts the
workflow; it does not pre-approve designs, plans, or integration choices
beyond what the project config already decides.
