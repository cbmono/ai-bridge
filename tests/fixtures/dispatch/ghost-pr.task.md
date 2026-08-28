---
type: Task
title: The task whose `pr:` names a pull request that does not exist
description: Status advanced and a URL is recorded, so every field-shaped check is satisfied — but nothing is there. A branch deleted before the PR was opened, a URL typed from memory, or a PR raised against the wrong repository all land here.
kind: build
status: in-review
assignee: software-engineer
target_repo: acme/widgets
objective: /objectives/example.md
acceptance_criteria:
  - "The thing the task asked for."
open_questions: []
worktree: /tmp/example-worktree/widgets-task-103
branch: feat/example-ghost
pr: [ https://github.com/acme/widgets/pull/9999 ]
timestamp: 2026-08-28T15:46:43Z
---

# Context

The reason the check asks the host rather than the document. Reading `status:` and `pr:`
alone clears this task: both fields have the right shape. Only *resolving* the URL says
that the artifact the report claims is not there.

Written unquoted and space-padded on purpose — task documents in the wild carry `pr:` in
every one of `["url"]`, `[ url ]` and `[ "url" ]`, so the reader must not depend on quoting.
