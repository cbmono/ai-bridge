# AI Bridge — the plugin

The OKF control panel, delivered as a Claude Code plugin instead of a symlink farm.
Skills, agents, hooks **and the machinery itself** ship here, reading and writing bundles
(`projects/`, `knowledge/`, `instance.config.json`) that hold data and nothing else. A
bundle carries no machinery and no link into any checkout: `/ai-bridge:init` stamps one,
and converts one stamped by the retired `install.sh`.

## Install

```
/plugin marketplace add cbmono/ai-bridge
/plugin install ai-bridge@ai-bridge
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
| `/welcome` | The welcome screen: bundle, owner, config layers, tier→model routing, board path, what awaits you. `check` reports state that could be wrong; `fix` repairs only the idempotent tier. |
| `/init <dir>` | Create a bundle, refresh one, or convert one stamped by the retired `install.sh` — data only, and the only symlinks it leaves are under `repos/`. |

Both also answer to their namespaced forms (`/ai-bridge:brief-me`, `/ai-bridge:capture`).
**`ai-bridge-v2` was the transition name** — it ships for one more version as a
deprecation stub (`plugin-deprecated/`) that carries a single skill pointing here.
Run them from a bundle root (where `SCHEMA.md` and `instance.config.json` live).

## Hooks

Registered by `hooks/hooks.json`. Unlike the skills these are **not invoked** — they fire
on their own at every `PreToolUse` boundary, in every session, which is the point: a
guarantee that depends on someone remembering to run it is not a guarantee.

| Hook | What it does |
|---|---|
| `hooks/deny-destructive.sh` | The destructive-action deny baseline. Refuses `terraform destroy`, irreversible `kubectl delete`s, destructive DDL against a remote host, `rm -rf` at a repo root, a force-push to a protected branch, secret exfiltration, and a dispatched agent merging a PR or pushing a product repo's default branch. Narrow on purpose, and the escape hatch is a human running the command in their own terminal. |
| `hooks/agent-control.sh` | The live kill switch. `gate`, `steer` and `halt` against ONE dispatched agent, keyed on `agent_id` so it can never take the human's own session down with it. The operator side is `scripts/control.sh`, beside it in this plugin — arming a bundle on a machine whose plugin is not installed writes directives nothing reads. |
| `hooks/session-banner.sh` | The `SessionStart` banner: which bundle this is, what it is configured to do, where the board is, what awaits the human — and, above all of it, an alarm if the bundle still carries machinery symlinks into a template checkout. Every line is a fact that can be false; none of it is a rules recital. |
| `hooks/push-state.sh` | `UserPromptSubmit`. Encodes the bundle's live state — projects, tasks in flight, what is awaiting a human — into the turn's context, at one awk choke point so a filename cannot forge the fence's markers. |

**All four no-op SILENTLY outside a bundle root.** A plugin is installed once per user, so
these fire in every project on the machine. Each resolves `$CLAUDE_PROJECT_DIR` (never the
payload's `cwd` — a dispatched agent's cwd is a worktree of a target repo) and exits 0 with
no stdout, no stderr and nothing written unless `instance.config.json` is there. Zero noise
in any other folder is the requirement, not a side effect.

**The banner and push-state moved here in ai-bridge-v2/task-013**, from a bundle's own
`.claude/settings.json` — itself a symlink into a template checkout, so they reached only
the bundles somebody had re-stamped, and a template that moved took the registration with
it. A detector made of symlinks cannot see its own failure; a plugin hook is a real file
the plugin manager replaces whole.

**`permissions.deny` stays in the bundle's `settings.json`**, which `/ai-bridge:init`
seeds. It is the second, unconditional layer behind the deny baseline, and a plugin
manifest has no permissions block to carry it.

## During the transition — what stays an instance command, and why

A plugin skill **shadows** a same-named project command, so each command migrated in a
slice that moved the contract and retired the instance copy **in one change**, with the
template's test suite as the spec — `/ai-bridge` first (its whole contract is this
plugin's `/welcome`), then `/audit`, `/answer`, `/fanout`, `/pr-review-request`,
`/new-project`, `/close-project` and finally `/pm-loop`, which is `/dispatch` here. The
**enforcement hooks** have made that move (above); `session-banner.sh` and
`push-state.sh` are still instance hooks and carry the same instance-root guard when
they follow.

**Agents had the REVERSE precedence, and that is why they moved last:** a same-named
project agent shadows the plugin copy (plugins are the lowest agent scope). So the eight
role agents shipped here in byte-parity with the instance copies first, and the name swap
retired those copies — the plugin is the only place they ship from now.
**Dispatch them namespaced, `ai-bridge:<role>`.** A bare agent name does NOT resolve
(measured 2026-09-02), which is why the strings changed exactly once, here.
