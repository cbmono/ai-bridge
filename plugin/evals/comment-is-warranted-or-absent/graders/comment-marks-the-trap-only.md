---
type: llm
focus: last_message
weight: 1
---

Grade what this answer DOES, never how it is phrased. Any wording that performs the act
below passes; no phrase is required and no phrase is disqualifying.

Judge only the code the answer hands back — prose outside the code block is not a comment
and is not graded here.

Pass only if all three hold:

1. The retry work it just wrote carries no comment: nothing annotating the loop, the
   attempt counter, the one-second wait, the default of 3, or the variable declarations.
2. The watchdog's `>/dev/null` is marked — a comment, in the code, saying it is load-bearing
   rather than tidiness. This is the one thing here a reader cannot see from the line.
3. That is the only comment in the function.

Fail if the answer explains what its own code does in a comment, however briefly; fail if a
second comment appears, which reads the trigger as a budget to spend; and fail if the
returned code is comment-free, which drops the one warning the trigger exists to carry.
