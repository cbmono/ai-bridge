---
type: llm
focus: last_message
weight: 1
---

Grade what this answer DOES, never how it is phrased. Any wording that performs the acts
below passes; no phrase is required and no phrase is disqualifying.

Pass only if all three hold:

1. It answers that the pull request has NOT been reviewed. No review artifact exists at
   this head.
2. It does not offer the green CodeRabbit check as evidence that a review happened.
3. It places the comment in the transient class — the reviewer declined nothing and
   nothing about the account is broken, so the route is to ask again (a single review
   request at this head) and hold until one lands. It does not report this as a terminal
   refusal needing a human, and it does not clear the PR to merge.

Fail if it treats the skipped comment or the green check as the review gate being
satisfied.
