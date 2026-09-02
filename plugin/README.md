# AI Bridge — the plugin

The OKF control panel, delivered as a Claude Code plugin instead of a symlink farm.
This is the AI Bridge 2.0 migration surface: skills land here one by one, reading and
writing the **same bundles** (`projects/`, `knowledge/`, `instance.config.json`) the
existing machinery uses — nothing about a bundle moves.

## Install

```
/plugin marketplace add cbmono/ai-bridge
/plugin install ai-bridge-v2@ai-bridge
```

Updates ship by version bump (no ambient auto-update): `/plugin` → Marketplaces.

## Skills today

| Skill | What it does |
|---|---|
| `/brief-me [project]` | Read-only. No argument: the board brief — what needs you, what's in flight, what moved since the last full tick. With a project slug: a meeting-ready brief with questions quoted by number and a "decide today" list. |
| `/capture <notes>` | Intake. Turns a decision or meeting notes into `draft` projects/tasks with provenance, fitted into existing projects where they belong. Never promotes; refinement stays the loop's job, promotion stays yours. |
| `/work <task>` | Work one `ready` task in the current session — the solo alternative to a background dispatch, leaving the same record (worktree/branch on the task, PR in `pr:`, `in-review` at the end). The gates still hold: no merging, review still independent. |
| `/dispatch [gap]` | The gated background loop. During the migration it delegates to the bundle's proven `/pm-loop` contract verbatim — no second implementation to drift. |
| `/handoff <path> <login>` | Ownership transfer with the context that makes it real: `owner:` set, a dated handoff note, and a paste-ready summary (open questions, PRs, linked Findings) for the new owner. Dispatch-gating only — never a promotion. |
| `/welcome` | The welcome screen: instance, owner, config layers, tier→model routing, board path, what awaits you. Relays the bundle's renderer verbatim. |

Both also answer to their namespaced forms (`/ai-bridge-v2:brief-me`, `/ai-bridge-v2:capture`).
Run them from a bundle root (where `SCHEMA.md` and `instance.config.json` live).

## Hooks

Registered by `hooks/hooks.json`. Unlike the skills these are **not invoked** — they fire
on their own at every `PreToolUse` boundary, in every session, which is the point: a
guarantee that depends on someone remembering to run it is not a guarantee.

| Hook | What it does |
|---|---|
| `hooks/deny-destructive.sh` | The destructive-action deny baseline. Refuses `terraform destroy`, irreversible `kubectl delete`s, destructive DDL against a remote host, `rm -rf` at a repo root, a force-push to a protected branch, secret exfiltration, and a dispatched agent merging a PR or pushing a product repo's default branch. Narrow on purpose, and the escape hatch is a human running the command in their own terminal. |
| `hooks/agent-control.sh` | The live kill switch. `gate`, `steer` and `halt` against ONE dispatched agent, keyed on `agent_id` so it can never take the human's own session down with it. The operator side is the bundle's `scripts/control.sh`, which is still instance machinery — arming an instance whose plugin is not installed writes directives nothing reads. |

**Both no-op SILENTLY outside an instance root.** A plugin is installed once per user, so
these fire in every project on the machine. Each resolves `$CLAUDE_PROJECT_DIR` (never the
payload's `cwd` — a dispatched agent's cwd is a worktree of a target repo) and exits 0 with
no stdout, no stderr and nothing written unless `instance.config.json` is there. Zero noise
in any other folder is the requirement, not a side effect.

**`permissions.deny` stays in the instance's `settings.json`.** It is the second,
unconditional layer behind the deny baseline, and a plugin manifest has no permissions
block to carry it.

## During the transition — what stays an instance command, and why

A plugin skill **shadows** a same-named project command, so the battle-tested
one instance command is deliberately *not* duplicated here yet: `/pm-loop`, the live
loop, keeps running from the bundle's machinery until its absorption slice.
(`/ai-bridge` migrated first — its whole contract lives in this plugin's `/welcome` —
then `/audit`, `/answer`, `/fanout`, `/pr-review-request`, `/new-project` and
`/close-project` followed verbatim.) Each migrates in a
slice that moves the contract and retires the instance copy **in one change**, with the
template's test suite as the spec. The **enforcement hooks** have made that move (above);
`session-banner.sh` and `push-state.sh` are still instance hooks and carry the same
instance-root guard when they follow. The final slice swaps `ai-bridge-v2` to the bare
name.

**Agents are the one surface with the REVERSE precedence:** a same-named project agent
shadows the plugin copy (plugins are the lowest agent scope), so the eight role agents
ship here in byte-parity with the instance copies — instances win until their links are
retired, and `tests/plugin-agents.test.sh` is what keeps the two copies one.
