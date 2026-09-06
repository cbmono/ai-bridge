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
