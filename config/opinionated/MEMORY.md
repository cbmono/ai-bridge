# User-level memory

Durable conventions Claude Code should follow. `install.sh --config` links this file to
`~/.claude/MEMORY.md`, where it is **inert** — nothing loads it by itself. To use it, add
`@~/.claude/MEMORY.md` to a project's `CLAUDE.md`. (An ai-bridge instance does not need it:
its `CLAUDE.md` carries the session defaults inline, and its own commands live in the
bundle.)

## Slash command triggers

When the user phrases a request that maps to one of the config layer's slash commands, invoke the command directly rather than improvising. The command body lives in `~/.claude/commands/<name>.md` and isn't auto-loaded into context — improvising skips load-bearing setup like slug derivation, agent dispatch, file persistence, and cleanup reminders.

| Natural-language phrasing                                                          | Command          |
| ---------------------------------------------------------------------------------- | ---------------- |
| "make/draft/write a plan", "plan out X", "plan this"                               | `/plan`          |
| "grill this", "grill the diff/changes", "be devil's advocate", "find what's wrong" | `/grill`         |
| "verify", "run the checks", "pre-PR check", "is this green"                        | `/verify`        |
| "stage and commit", "commit and push", "ship it"                                   | `/acp`           |
| "ask Dave", "second opinion from Dave", "what does Dave think"                     | `/dave`          |
| "scan for bugs", "deep bug scan", "scan `<dir>`"                                   | `/scan`          |
| any `gh stack` action ("stack view/add/submit/sync/merge/up/down…")                | `/stack <action>` |
| "find tech debt", "techdebt scan", "find duplicated code"                          | `/techdebt`      |
| "run CodeRabbit", "rabbit review"                                                  | `/rabbit`        |
| "hand off to Codex", "switch to Codex", "running low on tokens"                     | `/codex-handoff` |
| "back from Codex", "what did Codex do", "pull Codex's work in"                      | `/codex-handoff back` |

When the request adds constraints the command flow doesn't cover, invoke the command and adapt inside its steps rather than discarding it.
