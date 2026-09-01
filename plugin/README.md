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

## During the transition — what stays an instance command, and why

A plugin skill **shadows** a same-named project command, so the battle-tested
instance commands are deliberately *not* duplicated here yet: `/new-project`,
`/close-project`, `/pm-loop`, `/ai-bridge`, `/answer`, `/audit`, `/fanout`,
`/pr-review-request` keep running from the bundle's machinery. Each migrates in a
slice that moves the contract and retires the instance copy **in one change** — the
loop and the enforcement hooks are next, with the template's test suite as the spec.
The final slice swaps `ai-bridge-v2` to the bare name.
