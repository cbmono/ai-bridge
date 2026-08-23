---
paths:
  - "/symlink/**"
---

# Machinery under `symlink/`

Loads when you read anything under `symlink/`. **Everything here ships into every
instance, live, through a symlink** — there is no staging step and no per-instance
review. A change is in production the moment it is saved.

The reasoning behind each rule below is in [`docs/conventions.md`](../../docs/conventions.md),
numbered to match. Read the numbered section before changing the thing it governs; the
root [`CLAUDE.md`](../../CLAUDE.md) carries the same prohibitions always-loaded, because a
rule only fires on a **read** and a brand-new file matches nothing.

## Rules

- **Keep it generic.** No org, repo, path, team or channel literals. Those live in an instance's `instance.config.json` / `CLAUDE.md`.
- **Deleting a file here is not enough.** Already-stamped instances keep a symlink into the vanished path; a dangling command still registers and a dangling `SessionStart` hook exits 127 every launch. `install.sh` step 2b sweeps them — keep that sweep narrow (points into *this* template's `symlink/` **and** its target is gone). ([conventions 2](../../docs/conventions.md#2-retiring-machinery-means-deleting-the-file-and-letting-installsh-sweep-the-links))
- **A new deletable capability must not be a file here.** Machinery is re-linked unconditionally, so a per-instance `rm` comes back by itself. Put it in `seed/` (guarded like `AWAITING.md`) or make the disable a config key. `AUTONOMY.md` is the existing exception and `upgrade.sh` reports its re-enable. ([conventions 4](../../docs/conventions.md#4-a-capability-some-deployments-must-not-have-should-be-one-deletable-file))
- **`scripts/prune-worktrees.sh` never deletes.** Report-only, no flag. Count commits, never compare to `origin/<default>`; a detached HEAD is never `REMOVABLE`; the `PRUNE_ACTIVE_MINUTES` mtime veto stays recursive. ([conventions 7](../../docs/conventions.md#7-prune-worktreessh-is-report-only-and-that-is-load-bearing))
- **`scripts/required-checks.sh`: exit 0 is the only clearance.** Classify the platform probe on its **payload**, never `gh`'s exit code, and capture stdout and stderr **separately**. Three answers only — JSON, the literal "no required checks" message, anything else ⇒ exit 2. ([conventions 6](../../docs/conventions.md#6-the-delegated-merge-gate-resolves-its-required-checks-in-required-checkssh-and-exit-0-is-the-only-clearance))
- **`scripts/validate-bundle.sh` checks only the schema-defined locations.** Don't extend it to `index.md`, `log.md`, `sources/` or `deliverables/`; don't add an `owner` or `answered_questions` check. ([conventions 8](../../docs/conventions.md#8-validate-bundlesh-was-scoped-by-measuring-first-and-that-is-the-point))
- **`scripts/migrate-bundle.sh`: the mapping list is closed, the three refusals are the design, and every write is verified after it lands.** A silent no-op that reports `FIXED` is the bug class this script already shipped once. ([conventions 9](../../docs/conventions.md#9-migrate-bundlesh-fixes-only-what-has-one-right-answer-and-is-report-only-by-default))
- **`scripts/write-snapshot.sh` / `scripts/build-board.sh` / `scripts/print-board.sh` / `scripts/watch-board.sh`:** the snapshot's field list is a **data-governance boundary** — read `_sensitivity` before adding a key. Every number goes through `toint()`; never a bare `int()` on snapshot data. No GNU-only regex escapes in the writer. A renderer reads the **snapshot**, never the bundle, and escapes for **its own medium** — the terminal board strips Unicode category C, colours only a TTY, and never clips a number. `watch-board.sh` reuses `build-board.sh` rather than forking the HTML, refreshes only **this** instance's snapshot, and probes `fswatch` before using it. ([conventions 11](../../docs/conventions.md#11-the-cross-instance-board-is-two-scripts-and-one-deletable-generated-file))
- **`scripts/task-owner.sh` resolves *and* compares — two operations, not one chain.** `ownerGithubUser` answers "who is this clone?" and is never a source of ownership. Exit 0 is the only clearance. It gates **dispatch**, never promotion. ([docs/sharing.md](../../docs/sharing.md))
- **`.claude/hooks/push-state.sh` must never emit a false zero**, must stay silent outside an instance root, and encodes every file-derived value to one line at its **single** awk choke point. Do not add a second sanitising pass — it would mask the regression the test watches for. ([conventions 12](../../docs/conventions.md#12-three-ai-bridge-behaviours-that-all-exist-because-a-silent-wrong-answer-is-worse-than-a-loud-one))
- **`.claude/hooks/show-awaiting.sh` greps `AWAITING.md` literally** (the `## 🔴 Awaiting you` heading, asterisk-space bullets). The `project-manager` agent owns that exact layout; reshaping either silently empties the startup nudge. Both hooks fence their output as **untrusted data** — keep the boundary. ([conventions 3](../../docs/conventions.md#3-awaitingmd-is-ai-bridges-only-status-artifact-and-it-is-opt-in-by-presence))
- **`.claude/commands/new-project.md`: `build` and `research` are asymmetric on purpose.** Don't restore a question for symmetry. `clis:` comes from an explicit flag or is an empty list — never a placeholder. Step 8's review chain has a **declared fallback, never a skip**. ([conventions 5](../../docs/conventions.md#5-build-and-research-projects-are-deliberately-asymmetric), [10](../../docs/conventions.md#10-the-scaffold-review-is-a-three-stage-chain-with-a-declared-fallback-never-a-skip))
- **`SCHEMA.md` is the normative contract** for document types, the verification predicate and the per-machine override set. `docs/schema.md` is orientation only and must not restate a field list. Adding a knowledge kind means declaring its status enum — the location filter is a shape, not a list of names. ([conventions 14](../../docs/conventions.md#14-knowledgereferences-is-the-fifth-knowledge-kind))
- **State every fallback, every time.** These docs are read inside instances whose config predates the key: `worktreeRoot` → `<reposRoot>/_wt`, `maxPrLoc` → 500, `maxAgentsInFlight` → 10, `PUSH_STATE_MAX` → 12, `boardInstances` absent → just this instance, `watch-board.sh --interval` → 2s, `WATCH_BOARD_WATCHER` → `auto`.
- **Test harnesses never live here.** They go in `/tests/` — a fixture harness is not machinery an instance needs.
