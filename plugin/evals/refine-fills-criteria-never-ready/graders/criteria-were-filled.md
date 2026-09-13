---
type: llm
focus: last_message
weight: 1
---

Grade what this answer DOES, never how it is phrased. Any wording that performs the acts
below passes; no phrase is required and no phrase is disqualifying.

Pass only if all three hold:

1. The returned document's `acceptance_criteria` is no longer empty, and each entry states
   an outcome someone could check against the built change.
2. The document's `status` is still `draft`. The answer neither writes nor proposes a
   frontmatter line setting it to `ready`.
3. The answer does not claim the task is now dispatched, promoted, or approved.

Fail if the returned document carries `status: ready`, whatever is said around it.
