# Spike: the dispatch tick as a headless `claude -p` process

**Measured 2026-09-13, Claude Code 2.1.270, macOS (Darwin 25.5.0).** Fixture bundle
stamped by `init-bundle.sh` under a temp root, throwaway probe plugin, one scratch
project. No production bundle was read or written and no production `.tick-lock` was
touched. Reproduce the capability half: `bash docs/spikes/headless-tick-probe.sh --live`.

**Verdict: adoptable, with one flag change nobody would have guessed.** The tick runs
headless, returns one typed JSON object per tick, and carries its own cost and duration —
**but only if the `project-manager` prompt is inlined via `--agents`.** Under
`--agent ai-bridge:project-manager` the `--json-schema` flag is silently dropped and the
tick answers in prose.

## Q1 — do this plugin's agents, skills and hooks load under `-p`? Yes, all three

| Probe | Answer |
|---|---|
| subagent types | all 8 `ai-bridge:*` agents |
| model-invocable skills | `ai-bridge:brief-me`, `ai-bridge:welcome` — and only those, which is exactly the 2 of 15 `SKILL.md` without `disable-model-invocation: true` |
| a slash-only skill as the `-p` prompt | runs — so `/ai-bridge:dispatch` itself is invocable headless |
| plugin hooks | `SessionStart`, `UserPromptSubmit`, `PreToolUse:Bash`, `Stop` all fired |
| `CLAUDE.md` | loaded (marker string present) |
| **control** — the same slash-only skill under `--safe-mode` | `Unknown command` |

## The permission model, and the failure mode it hides

| Under `--permission-prompts none` | Outcome |
|---|---|
| `Bash(echo …)` | runs — built-in safe set, no settings needed |
| `Write`, `Bash(curl …)`, `Bash(git push …)` with no allowlist | denied; one entry each in `permission_denials[]` |
| the same with `--allowedTools Write` or `--permission-mode acceptEdits` | runs |
| **every denied run** | `subtype: "success"`, `is_error: false`, **exit 0** |

**A gagged tick and an idle tick are the same exit code.** The launcher's only signal is
`permission_denials[]`, and it must read it.

Three things defeat a prefix allowlist for a real tick, all measured on the live PM prompt:

1. **`${CLAUDE_PLUGIN_ROOT}` is not exported into the Bash tool**, so the agent's own
   `bash ${CLAUDE_PLUGIN_ROOT}/scripts/tick-lock.sh …` does not resolve.
2. **The PM composes compound commands** — `ls … ; "$X/tick-lock.sh" acquire … ; echo …` —
   and a prefix rule matches none of them.
3. **An untrusted workspace silently drops `permissions.allow` entries** from the bundle's
   own `.claude/settings.json` (stderr says so; `-p` skips the trust dialog).

All 3 ticks run under a prefix allowlist had their own `acquire --as tick` denied, and each
still exited 0. The route that worked is `--permission-mode bypassPermissions` **with
the plugin's `deny-destructive.sh` hook as the guardrail** — under bypass, headless, that
hook still refused a bare force push and the refusal still landed in
`permission_denials[]`.

## Flags: the gotchas, one run each to find

| Flag | Behaviour on 2.1.270 |
|---|---|
| `--json-schema` | **inline JSON only** — a file path is parsed as JSON and refused |
| `--json-schema` | a `"$schema": "…/draft/2020-12/schema"` key is refused (`no schema with key or ref`) |
| `--json-schema` | **silently dropped under a plugin `--agent`**; kept under an inline `--agents` agent, and kept across a 5-turn tool loop with no agent |
| `--allowedTools` | variadic, so a positional prompt after it is swallowed — pass the prompt after `--` |
| stdin | not redirecting `< /dev/null` costs a 3-second warning per run |

The `--json-schema` row is the one that decides the design. Same schema, same prompt, same
settings: `--agent tiny` (inline, via `--agents`) returned the object; `--agent
ai-bridge:project-manager` returned prose — twice, including once with an explicit output
contract in the brief, and once from a real 20-turn tick that did honest work.

## Ten consecutive ticks, both ways

Arm **H** — a launcher session running `bash tick-once.sh` ten times. Arm **A** — a
launcher session dispatching `ai-bridge:project-manager` ten times with the same brief.
Both launchers are `claude -p --output-format stream-json`, sonnet, same fixture shape.
`cache_read_input_tokens` is read from each launcher's own assistant turns.

| | Arm H — `claude -p` subprocess | Arm A — `Agent` tool |
|---|---|---|
| ticks completed | **10/10**, every one schema-valid | 10/10 |
| launcher turns | 15 | 44 |
| launcher `cache_read_input_tokens`, first → last | 23,948 → **56,835** | 18,551 → **68,178** |
| growth across the ten ticks | **+7,785** | **+19,057** |
| stays under 60k? | **yes** | **no** — crosses at turn 26 of 44 |
| launcher `total_cost_usd` | **$0.29** | **$5.00** |
| per-tick cost the launcher can see | all ten, on their ledger lines ($0.43-$0.66, $5.46 total) | none: *no pid, no cost, no duration* |
| wall clock | 18m 02s | 21m 32s |

**The claim under test holds, and the caveat is in the baseline.** Both launchers start from a
~20k fixture context, not the 440k of the session this spike comes from, so the transferable
figure is the growth and not the ceiling: ten ticks cost the headless launcher 7.8k of context
and the `Agent`-tool launcher 19.1k, 2.4x more. Total spend is a wash ($5.75 against $5.00);
what moves is where it is visible — arm A's $5.00 is the subagents billed into the launcher,
with nothing left on the ledger to audit a single tick by.

**One behaviour to design around: a launcher told to run ten commands one at a time issued
three of them in parallel in one turn.** The dispatch lock is what serialised them — the
runner queues on the lock instead of failing — and arm H's low turn count is partly that
batching.

Every headless tick's ledger line is written by the launcher from the result envelope, so
the run is auditable from `log.md` alone:

```text
- tick-20260913T172020Z-3124 · pid 16746 · exit 0 · subtype success · cost $0.6616 · 136608 ms · denials 0
```

## The budget cap, observed on a deliberate breach

`--max-budget-usd 0.05` against a real tick:

| | |
|---|---|
| exit status | **1** |
| envelope | `subtype: "error_max_budget_usd"`, `is_error: true`, `terminal_reason: "budget_exhausted"` |
| `result` | **`null`** — a breached tick returns no tick summary at all |
| actual spend | **$0.1147 against a $0.05 cap** — the cap is checked between turns, not enforced inside one |
| bundle left holding | working tree clean, no partial commit |
| lock | **still held** — the tick never releases; the launcher does |

## The lock contract, and a killed tick

`tick-lock.sh` needs no change. The launcher mints the literal, `acquire`s, runs the
process, and `release`s — the process id goes on the ledger line, not into the lock, which
is the answer the task's Q2 proposed and this exercised.

`SIGTERM` to a running tick at t=30s: exit **143**, **zero bytes of stdout**, no orphaned
child processes, working tree clean. The lock stayed `HELD` with the tick's claim on it,
and the next launcher `acquire` answered **exit 1 (HELD)** — today's recoverable state,
where the lock ages into the stale case a human clears. **The headless model is strictly
better here**: the launcher holds the pid and sees the status, so it can release at once
instead of waiting the lock out. A killed `Agent`-tool subagent gives the launcher neither.

## Recommendation

Adopt, as `plugin/scripts/tick-run.sh` invoked from one Bash step in
`/ai-bridge:dispatch`, inlining `project-manager.md` through `--agents` so the schema
survives. The lock contract, the `project-manager` agent file and `tick-lock.sh` are all
unchanged. Sized as `task-035` in the control panel; **this PR migrates nothing.**
