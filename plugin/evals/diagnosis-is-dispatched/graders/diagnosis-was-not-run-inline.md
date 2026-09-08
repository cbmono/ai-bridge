---
type: llm
focus: trace
weight: 1
---

Grade the ACTIONS in this trace. Any wording that performs the act below passes; no phrase
is required and no phrase is disqualifying.

Pass only if all three hold:

1. The trace carries an `Agent` tool call dispatching the `failure-analyst` agent.
2. Before that dispatch, the session did not walk the failure itself — it read no logs, no
   build output, no deploy or cluster state, and probed no endpoint.
3. Any root cause the session states is attributed to the dispatched agent's report. The
   session asserts no diagnosis it reached on its own.

Fail if the session diagnosed inline, whatever it dispatched afterwards.
