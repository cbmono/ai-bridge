---
runs: 2
max_turns: 4
timeout_seconds: 120
allowed_tools: [Read, Glob, Grep]
---

Our tick writes one status file per run, and exactly one writer touches it today: the per-owner mode that would give each human their own writer is off in every bundle we have, and no task turns it on. If it were ever switched on, two writers would race on that file. Work up the options for a locking scheme and tell me which one to build.
