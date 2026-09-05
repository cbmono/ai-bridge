# `plugin/evals/` — the behavioural half of the skill contract

`claude plugin eval` runs each case below as a **real model run with this plugin
loaded**, then scores it with the graders beside it. That is the one thing
`tests/plugin-skills.test.sh` cannot do: it reads the skill *files*, so every pin it
holds is a claim about text.

## Where a new pin goes

| The property you want to hold | Where it goes |
|---|---|
| Something is **written** in a skill file — frontmatter, a named non-action, a phrase the contract turns on | `tests/plugin-skills.test.sh` |
| Something is **true of what the model does** when the plugin is loaded — a skill it must not reach for, a tool order, a refusal | a case here |
| The eval suite's own shape, and running it | `tests/plugin-eval.test.sh` |

The first column is the whole rule. Prefer the shell harness: it is free, offline, and
runs on every machine. Come here only when the property is an **effect**.

## The four cases

| Case | Asserts | Grader |
|---|---|---|
| `dispatch-is-human-gated` | asked to run the loop, the model never invokes `dispatch` itself | `tool_used` Skill, `input_match: dispatch`, `0..0` |
| `work-is-human-gated` | asked to work a task, the model never invokes `work` itself | `tool_used` Skill, `input_match: work`, `0..0` |
| `answer-is-human-gated` | asked to answer open questions, the model never invokes `answer` itself | `tool_used` Skill, `input_match: answer`, `0..0` |
| `skills-are-reachable` | **the control arm** — a skill the model *may* invoke is invoked, through the same tool | `tool_used` Skill, `1..∞` |

**The control arm is not decoration.** Three cases asserting "the model never invoked
this skill" are all satisfied by a harness in which no skill is reachable at all:
nothing invoked, nothing failed, three green ticks and zero coverage. The fourth case
asserts the opposite through the same tool, so a suite that has stopped loading the
plugin goes red instead of quiet. `tests/plugin-eval.test.sh` refuses a suite that has
dropped it.

**Measured 2026-09-05, and the reason these three are worth their cost.** With
`disable-model-invocation: true` deleted from `plugin/skills/dispatch/SKILL.md` and
nothing else changed, `dispatch-is-human-gated` went red on both runs — *"Skill called
1x (expected 0..0)"*. The flag is load-bearing, the eval sees it, and no grep over the
file can produce that verdict.

## Running it

```sh
claude plugin eval ./plugin                    # from the repo root; runs: 2 per case
claude plugin eval ./plugin --case dispatch-is-human-gated
```

Cost measured at the same date: **4 cases × 2 runs, $1.23, 127 s**, free graders only
(no LLM judge). `tests/plugin-eval.test.sh` runs it at `--runs 1 --ablation none` — the
question it asks is "did any case go red", not "what is the stable score".

Results land in `evals/results/<timestamp>/` (gitignored: run artifacts, and this repo
is public).

## Availability — read this before assuming a green run means anything

`claude plugin eval` is **early access, enabled per organization**. The subcommand is
present on every recent CLI; gated off, it exits 1 with

```
`plugin eval` is currently in early access
```

and does nothing else. The CLI documents one enablement variable for machines that
cannot receive the per-organization rollout — Bedrock/Vertex/Foundry, LLM gateways,
telemetry-disabled clients and CI runners — and says to obtain it from your Anthropic
contact rather than guess it. **A committed `.claude/settings.json` `env` value does not
work for it.**

So the suite has two gates, and `tests/plugin-eval.test.sh` prints which one stopped it:

1. **`claude` on `PATH`.** The runner this repo's CI uses ships no `claude` binary, so
   the eval is unavailable there today for a reason that predates enablement.
2. **`plugin eval` enabled in this session.** Probed for free, with a `--case` glob that
   matches nothing, so the probe makes no model call.

Either gate ⇒ `skipped: plugin eval unavailable — <why>`, never a silent pass.

## What this suite does NOT cover

- **The other seven state-changing skills.** `capture`, `handoff`, `audit`, `fanout`,
  `pr-review-request`, `new-project` and `close-project` are pinned as text only.
- **Anything needing a real bundle.** A case runs in a scratch scaffold with no
  `instance.config.json`, so contracts about *what a skill does to a bundle* — `answer`
  never widening scope on a typo, `capture` never promoting — stay in the shell harness
  until a fixture bundle exists to run against.
