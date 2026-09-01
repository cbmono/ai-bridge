---
name: dispatch
description: Start the gated background loop for this bundle — one PM tick at a time, dependencies respected, up to the bundle's in-flight cap
argument-hint: "[gap]  pause between ticks, default 10m"
disable-model-invocation: true
---

Start the serial, completion-driven PM loop for this bundle: refine drafts, dispatch
`ready` tasks to the right role agents (dependencies respected, at most this bundle's
`maxAgentsInFlight` in flight), verify PRs, reflect merges — with both human gates
held: **the loop never promotes `draft → ready` and never merges.**

## During the migration, this delegates — deliberately

The loop's proven contract lives in this bundle as the `/pm-loop` skill (the tick
lock, the exit-code table, the resume rules, the release discipline — all pinned by
the template's test suite). **Invoke the `pm-loop` skill with `$ARGUMENTS` as the
gap and add nothing of your own**: no extra preconditions, no state reads, no second
lock. A delegation that "improves" on a pinned contract is how two copies drift.

- `/pm-loop` not available in this session (not a bundle root, or an instance whose
  commands never registered)? Say exactly that — from a bundle root, restart the
  session so the instance's commands load, or run `install.sh` if the machinery was
  never stamped — and stop. **Do not re-implement the loop from memory**; a
  hand-rolled tick is the double-dispatch class the lock exists to prevent.

When the loop machinery is absorbed into this plugin, this file becomes the contract
itself and the instance command retires — one migration slice, both sides in one
change, per the AI Bridge 2.0 strategy.

## Stopping

"Stop the loop" is `/pm-loop`'s own step 5 — relay the request to that contract
(release only a lock this session took and whose tick has finished; a pending tick's
lock is left to age out where a human sees it).
