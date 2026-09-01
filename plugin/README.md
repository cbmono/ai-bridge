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

Both also answer to their namespaced forms (`/ai-bridge-v2:brief-me`, `/ai-bridge-v2:capture`).
Run them from a bundle root (where `SCHEMA.md` and `instance.config.json` live).

## What comes next

Per the AI Bridge 2.0 strategy: `/work` (a task in this session), `/dispatch` (the
gated background loop), `/handoff`, the welcome screen, and the enforcement hooks —
absorbed from `symlink/` piece by piece, with the existing test suite as the spec.
