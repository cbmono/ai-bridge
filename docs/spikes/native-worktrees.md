# Spike: native worktrees for the dispatch flow

**Measured 2026-09-06, Claude Code 2.1.263, macOS.** Fixture bundle + fixture product
repo (default branch `trunk`, deliberately not `main`), throwaway `CLAUDE_CONFIG_DIR`.
No production bundle touched. Reproduce: `bash docs/spikes/native-worktrees-probe.sh`.

**Verdict: not adoptable yet — but not for the reason on record.** The 2026-09-05
blocker ("`EnterWorktree` worktrees the CURRENT repo") is **overturned**: a
`WorktreeCreate` hook places the worktree in *any* repo, from *any* cwd. The blocker
is now **identity** — the hook cannot tell which task it is serving.

## Route (a) — `claude -p --worktree` / agent isolation, cwd = the product repo

| Probe | Result |
|---|---|
| `--worktree` in a git repo | `<repo>/.claude/worktrees/<name>`, branch `worktree-<name>`, `locked` |
| `--worktree <name>` | path and branch deterministic, but the `worktree-` prefix is not removable |
| is `.claude/` excluded from the product repo? | **no** — `git status` reports `?? .claude/` |
| worktree vs. auth order | created **before** the auth check: a `Not logged in` run still left a locked worktree |
| lifecycle | `git worktree remove --force` refuses (`-f -f` required); 3 aborted runs stranded 3 locked worktrees inside the product clone |
| `worktree.baseRef` | default `fresh` = `origin/<default-branch>` — matches `CONVENTIONS.md` |
| subagent `cwd` | not in the Agent tool schema; settable only by a JS plugin `agent.spawn` hook, and *"cwd and isolation: 'worktree' are mutually exclusive"* |

**Cost of the route as written.** The session's cwd must *be* the product repo, so the
agent loses the bundle — `CLAUDE.md`, the task documents, `plugin/scripts/`. And the
worktrees land inside the product clone, untracked and locked, where neither
`prune-worktrees.sh` nor `reclaim-worktree.sh` looks.

## Route (b) — plugin-registered `WorktreeCreate` / `WorktreeRemove`

| Probe | Result |
|---|---|
| precedence when cwd **is** a git repo | **the hook wins** — `.claude/worktrees/` is not used at all |
| cwd = bundle, hook emits a worktree of the **product** repo | **accepted**; the live session ran with cwd = that worktree, on a branch of our choosing |
| same for a subagent `isolation: "worktree"` | **works** — the agent landed in the product-repo worktree |
| bad hook output | refused, with a named reason, before the auth gate |
| `WorktreeRemove` | **never fired** — not on subagent completion, not on session exit; 6 hook worktrees survived |

**Payload — the whole of what the hook is told:**

```json
{"session_id":"…","transcript_path":"…","cwd":"…","prompt_id":"…",
 "hook_event_name":"WorktreeCreate","name":"agent-a6d376a8ba2cd81fa"}
```

## The blocker, exactly

`name` is `agent-<opaque-id>`. There is no `agent_type`, no task, no branch, no base
ref, and `session_id` is the **parent** session's — identical for every subagent in one
tick, so two concurrent dispatches are indistinguishable to the hook. The PM writes
`branch:` into the task file *before* dispatch; native offers no channel to carry it in.
A hook could only guess, and `reclaim-worktree.sh` exists because guessing at worktrees
destroyed three running agents' work on 2026-08-04.

## Diff proposal — deferred until the payload names the agent

Written out so the migration is a diff and not a re-run of this spike. **Do not apply
it yet.**

| | Today | With native |
|---|---|---|
| where the worktree lands | `worktreeRoot/<task-slug>`, `git worktree add` by the agent | same path, created by a `WorktreeCreate` hook — measured to work |
| `worktree:` / `branch:` in the task file | PM writes both before dispatch | hook cannot know either ⇒ **blocked** |
| `prune-worktrees.sh` | report-only classifier over two roots | unchanged — `WorktreeRemove` never fires, so nothing is reaped for it |
| `reclaim-worktree.sh` | task-driven removal | unchanged — it is the only task-aware reaper either way |
| an existing `_wt` tree | drained by hand | untouched; the hook writes to the same root |

**The one change that unblocks it**: `WorktreeCreate` carrying the spawning agent's
`agent_type` and id (as `PreToolUse` already does — see `[[pretooluse-fires-for-subagents]]`).
Then the hook reads the dispatch record, creates `worktreeRoot/<task-slug>` on the task's
`branch:`, and `git worktree add` leaves the agent contract. Until then the current
discipline is strictly better: it is deterministic, task-keyed, and already tested.

**Two things worth adopting now, independently of the migration** — `worktree.baseRef:
fresh` already encodes the `origin/<default-branch>` rule, and the `agent.spawn` JS
plugin hook can set a subagent's `cwd`, which would place role agents in their worktrees
without the agent doing it by hand. Both are separate tasks.

---

# Re-test, 2026-09-13, Claude Code 2.1.270

**Same fixtures, one version later.** Reproduce:
`bash docs/spikes/native-worktrees-probe-2.sh [--live]` (probes 1-6 need no auth; 7-9
spend one haiku turn each).

**Verdict: the identity blocker stands for a SUBAGENT and does not exist for a SESSION.**
The hook can place `<worktreeRoot>/<task-id>` on the task's branch and the agent works
there — but only when the task id arrives as the session's own `--worktree <name>`. Under
in-session `Agent` dispatch, which is how role agents run today, `name` is still opaque.

## What the hook can do

| Probe | Result |
|---|---|
| session `--worktree task-029`, cwd = bundle, hook emits a tree of the **product** repo | session cwd = `<wtroot>/task-029`, branch `task-029` — the task named it |
| subagent `isolation: "worktree"` under the same hook | lands in the hook's cross-repo tree, on the hook's branch |
| `git worktree lock` on a hook-created tree | **not held** — its own `git worktree list --porcelain` stanza carries no `locked` line, read from inside the running session and again from outside after it exits |
| the tree after the agent and the session exit | **survives**, on both routes |

## What it cannot

| Probe | Result |
|---|---|
| payload | `{session_id, transcript_path, cwd, prompt_id, hook_event_name, name}` — **no `base_ref`**, and none appears with `worktree.baseRef: fresh` set either |
| `name` for a subagent | `agent-<opaque-id>`; still no `agent_type`, no `agent_id` |
| two subagents dispatched in one turn | one shared `prompt_id`, and the hook order is **not stable**: `pretool pretool create create` in one run, `pretool create pretool create` in the next. Nothing pairs a create with the `Agent` call that caused it, and arrival order is not even consistent, so a hook can only guess |
| `WorktreeRemove` | **never fired** — not on subagent completion, not on session exit, not for a harness-created `--worktree` tree. One probe run is 10 sessions and 2 subagents: 0 events |
| hook prints a path that **does not exist** | refused: *"… does not exist or is not a directory"*. Existence is what is checked, not authorship — the dirty-worktree row below is a tree the hook did not create, and it is accepted |
| hook exits non-zero | refused: *"WorktreeCreate hook failed"* — creation aborts |
| hook prints a **relative** path | refused: *"Refusing to use … git resolves its working tree to …"* (resolved against the cwd, which is the bundle) |
| hook prints a path **containing a space** | accepted |
| hook prints an existing **dirty** worktree | accepted, uncommitted file untouched |
| hookless `--worktree` | still `<product-repo>/.claude/worktrees/<name>`, branch `worktree-<name>`, **`locked`**, created before the auth check |

## Consequences for the migration

**`WorktreeRemove` is not a lifecycle, so nothing here can be built on it.** The veto in
`docs/spikes/worktree-remove-veto.sh` is written and tested
(`tests/worktree-remove-veto.test.sh` 25/0) so the migration inherits a decided shape, and
it is **not wired**: an event that never fires cannot be measured, and its payload shape is
therefore unknown. The veto takes the path from argv and reads the task document —
`pr:` and `status:`, offline — exiting 1 (keep) for **every** state it cannot establish.
It clears removal only on exactly one `pr:` that is an **empty list** and `status: done`:
a missing, duplicated or placeholder `pr:` carries zero URLs while establishing nothing,
and `cancelled` is refused for `reclaim-worktree.sh`'s G2 reason — the PR was closed
unmerged, so that tree may hold the only copy.

**Nothing in this spike removes a worktree by scanning.** Scan-based removal destroyed
three running agents' worktrees on 2026-08-04 (`docs/pm-design.md`, step 5), and that
constraint binds the migration: the probe's own cleanup names the fixture's trees by path
under a `mktemp` root, and the veto never lists a worktree root at all.

**The settled target, for the follow-up task:** `prune-worktrees.sh` survives as a report
over `git worktree list --porcelain` lock reasons and still deletes nothing;
`reclaim-worktree.sh` is retired. Both are **untouched by this PR**. The follow-up is
gated on the tick dispatching each role agent as its own session — the one route where
`name` is the task id — not on a payload change we do not control.
