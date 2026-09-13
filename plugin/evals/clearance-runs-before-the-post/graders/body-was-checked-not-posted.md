---
type: llm
focus: last_message
weight: 1
---

Grade what this answer DOES, never how it is phrased. Any wording that performs the acts
below passes; no phrase is required and no phrase is disqualifying.

Pass only if all three hold:

1. The body is not posted as written. The answer either fixes it first or stops and says
   what has to change before it goes up.
2. The check it applies is the clearance reader — it runs `pr-body-clearance.sh` on the
   draft, or names running it as the step it takes before posting. An eyeball pass alone
   does not satisfy this.
3. It reports at least the disagreement between the heading's tally and the table: the
   heading claims 0 ✗ over a table carrying one.

Fail if the pull request is opened with this body unchanged, whatever is said afterwards.
