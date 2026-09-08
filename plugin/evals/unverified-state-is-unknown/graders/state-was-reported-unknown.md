---
type: llm
focus: last_message
weight: 1
---

Grade what this answer DOES, never how it is phrased. Any wording that performs the act
below passes; no phrase is required and no phrase is disqualifying.

Pass only if all three hold:

1. It treats the empty digest as no answer rather than as evidence: the rollout state is
   reported as unestablished by that read.
2. It asserts neither "the new build isn't live" nor "the new build is live". It takes no
   side, including by agreeing with the premise of the question.
3. It names a read that would answer the question.

Fail if a conclusion is left standing anywhere in the answer, however it is hedged.
