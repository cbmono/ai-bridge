---
name: capture
disable-model-invocation: true
description: Turn meeting notes or a decision into drafted OKF projects/tasks — with provenance, never promoted
argument-hint: "<notes, a decision, or nothing to use what was just pasted>"
---

Capture work at its source: a business decision, meeting notes, a Slack thread the
human pastes — into **`draft`** OKF documents this bundle's normal loop then refines.
This is intake, not execution: you create drafts and stop.

## Preconditions

Run from a control-panel instance root (`SCHEMA.md` + `instance.config.json` in the
cwd); otherwise say so and stop. The input is `$ARGUMENTS`, or — when empty — the
notes/decision content most recently provided in this conversation. If there is
neither, ask for the notes; do not invent work.

## How to capture

1. **Extract the workstreams.** One decision can carry several; a status remark carries
   none. Capture only what someone decided or asked for — never spec work the notes
   merely discussed. When the notes are ambiguous about whether something was decided,
   capture it as a task whose `open_questions` asks exactly that.
2. **Fit before creating.** Scan the existing `projects/` (frontmatter only — the
   digest via `scripts/tick-delta.sh digest` is the cheap way): a workstream that
   belongs to a live project becomes a **task in that project**, not a new project.
   Only a genuinely new initiative gets a new project folder.
3. **Create per `SCHEMA.md`, minimal and honest.** New project: a `project.md` with
   `status: active`, `kind` (`build` or `research` — decks/docs/analyses are
   `research`), and a plain-language goal. Tasks: `status: draft`, a short scoped
   title, `acceptance_criteria: [ ]` left **empty** (refinement is the loop's job),
   and numbered `open_questions` for every ambiguity the notes left open.
4. **Provenance, always.** Each captured document's `# Context` opens with one line:
   `Captured from <meeting/source>, <ISO date>: "<the decisive sentence, quoted>"` —
   so the task can always answer "who asked for this and why". **No customer PII** in
   any of it: titles reach the board, answers persist for the life of the repo.
5. **Never promote.** Everything stays `draft` with an empty criteria list — the PM
   refines it, the human promotes it. You do not set `ready`, do not dispatch, do not
   edit `AWAITING.md` (it is derived).
6. **Commit** the new files by explicit path:
   `scripts/commit-as.sh human "chore: capture <slug> from <source>" -- <paths...>`
   (this is the human's own intake, so the `human` role is correct). If the script is
   missing, a plain `git add <paths> && git commit` is the fallback — never `git add -A`.

## Report

End with: what was created (paths, one line each), which existing projects absorbed a
task, and the open questions awaiting answers — so the human can answer inline
(` --- <answer>`) or promote when ready. If the notes contained decisions you
deliberately did **not** capture (pure status, out-of-scope musings), say so in one
line; a silent drop erodes trust in the funnel.
