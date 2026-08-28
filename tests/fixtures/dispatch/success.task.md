---
type: Task
title: The shape a finished dispatch actually has
description: A build task whose agent finished the way the loop expects — status advanced to in-review, and `pr:` naming a pull request that exists.
kind: build
status: in-review
assignee: software-engineer
target_repo: acme/widgets
objective: /objectives/example.md
acceptance_criteria:
  - "The thing the task asked for."
open_questions: []
worktree: /tmp/example-worktree/widgets-task-101
branch: feat/example
pr: ["https://github.com/acme/widgets/pull/42"]
timestamp: 2026-08-28T15:46:43Z
---

# Context

The control shape. Nothing here is wrong, and `check-dispatch.sh` must say so — a checker
that refuses everything catches the parked agent too, and is worthless.

# Result

Opened https://github.com/acme/widgets/pull/42.
