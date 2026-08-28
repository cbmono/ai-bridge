---
type: Task
title: The parked agent whose PR URL is sitting in a YAML comment
description: The same parked dispatch as parked.task.md, one comment away from clearing. The `pr:` list is empty; a URL was written after a `#` — the most natural way for that line to end up, whether as a note, a plan, or a value commented out during an edit.
kind: build
status: in-progress
assignee: software-engineer
target_repo: acme/widgets
objective: /objectives/example.md
acceptance_criteria:
  - "The thing the task asked for."
open_questions: []
worktree: /tmp/example-worktree/widgets-task-104
branch: fix/example-commented
pr: [] # https://github.com/acme/widgets/pull/42
timestamp: 2026-08-28T15:46:43Z
---

# Context

**A false clearance inside the false-clearance checker.** `pr:` records nothing, so this
task is parked exactly like `parked.task.md` — but a reader that takes the raw line and
greps it for a URL finds one, resolves it against the host, and reports **exit 0** on a
dispatch that produced no pull request at all. That is the one outcome this script exists
to prevent, arrived at through its own reader.

The URL in the comment is deliberately the one `success.task.md` uses, so the `gh` stub
**does** resolve it: the fixture only proves anything while the URL is real to the host.
A fixture whose commented URL 404s would pass for the wrong reason.

Third appearance of this defect in this repository — ai-bridge#44 fixed a trailing YAML
comment flipping an `awaiting:approve` verb and fabricating a `depends_on` edge in
`write-snapshot.sh`, and recorded there that the strip belongs at the consumer, never in
the shared region reader (a blanket strip had twice eaten real `open_questions` entries).
