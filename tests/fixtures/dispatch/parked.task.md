---
type: Task
title: The parked agent — work committed, no PR, and it reported as completed
description: Recorded from the 2026-08-28 incident. The agent did the work, committed it in its worktree, then ended its turn waiting for a background job's notification that nothing was left running to send. The task document still reads exactly like this.
kind: build
status: in-progress
assignee: software-engineer
target_repo: acme/widgets
objective: /objectives/example.md
acceptance_criteria:
  - "The thing the task asked for."
open_questions: []
worktree: /tmp/example-worktree/widgets-task-102
branch: fix/example
pr: [ ]
timestamp: 2026-08-28T15:46:43Z
---

# Context

**This is the fixture the whole check exists for.** The agent's final message was

> *"I'll pause here and wait for the background job notification before proceeding to open
> the PR."*

and the coordinator received an ordinary completion notification. The commit exists; in the
sibling case it had already been pushed. `status:` never moved off `in-progress` and `pr:`
is still empty, which is the entire signature — no judgement of the work is involved, and
none is wanted.

Every other guard in the bundle passes this document: the wall-clock rule (it parked at 16
minutes), the two-round review cap (it never reached review), and the completion notice
(that is what it sent). `check-dispatch.sh` must exit **non-zero** here, or it is decoration.
