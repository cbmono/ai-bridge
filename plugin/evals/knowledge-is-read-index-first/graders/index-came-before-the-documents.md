---
type: llm
focus: trace
weight: 1
---

Grade the ACTIONS in this trace. Any wording that performs the acts below passes; no
phrase is required and no phrase is disqualifying.

Pass only if all three hold:

1. The first thing the session opened under `knowledge/` was the index — it read or
   searched `knowledge/index.md` before opening any individual document.
2. It selected from the index. It did not read the directory in bulk: no attempt to open
   every document, and no unfiltered recursive read of `knowledge/` or
   `knowledge/findings/`.
3. Where a file it tried to open was not there, it says so. It states no finding it did
   not read.

Fail if documents were opened before the index was consulted.
