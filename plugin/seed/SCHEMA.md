---
type: Reference
title: OKF Producer Types & Status Reference
description: Custom concept types and the task lifecycle used by this control panel.
timestamp: 2026-06-18T00:00:00Z
---

OKF defines no task/project/objective/agent constructs — they are
producer-defined extensions. This document is the contract for the custom
`type`s and frontmatter fields used in this bundle. All consumers must tolerate
missing optional fields and unknown keys (per the OKF spec).

> **Seed file — copied once, then yours.** `/ai-bridge:init` copied this file into the
> bundle from the `ai-bridge` plugin; the bundle owns it from then on, so your edits stay
> and this copy drifts from the template until `/ai-bridge:init` 3-way merges a
> later template change onto them. Instance-specific values (`<org>`, the clone root, the
> author identity, team routing) live in `instance.config.json` and this instance's
> `CLAUDE.md` — never hardcode them here.

# Validation

`scripts/validate-bundle.sh` enforces this document. Run it after any structural
edit, and always before closing a project:

* every concept document carries `type`, and a `status` from its type's closed enum,
  and a `timestamp`;
* every **frontmatter** reference (`objective:`, `project:`, `phase:`, `depends_on:`)
  resolves. Body prose is not checked — a body may cite a closed project as history;
* `artifacts:` may name a deliverable that is not written yet, so it warns.

Two fields the v2 plan asked for and the data rejected: **`id`** (the file path is
already the identifier, so a second one can only drift from it) and renaming
`timestamp` to **`updated`** (OKF names the field `timestamp`; renaming diverges from
the spec this bundle follows). Neither exists in any instance and neither is required.

**Concept documents live only in the schema-defined locations** — `objectives/*.md`
(the directory is optional; a bundle with none is valid),
`projects/*/project.md`, `projects/*/phases/*.md`, `projects/*/tasks/*.md`,
`knowledge/<kind>/*.md`. `index.md`, `log.md`, `knowledge/vocab.md`, `sources/` and
`deliverables/` are navigation and content, and carry no frontmatter by design. (`knowledge/<kind>/` is
a shape, not a list of names — a fifth kind directory is validated the moment it
exists, which is how `knowledge/references/` was already covered.)

# Schema

## type: Objective  (`objectives/<slug>.md`) — an OPTIONAL layer

**Most projects need no objective.** A project is normally self-contained and carries its
own `success_criteria` (below); the next iteration is the next project. An `Objective` is
for a goal that **outlives one project** — several projects serving one measurable end. A
bundle that has no such goal ships **no `objectives/` directory at all**, and nothing
requires one: `/ai-bridge:init <dir> --with-objectives` creates it the day you want the
layer, and an existing `objectives/` is never touched.

```yaml
---
type: Objective
title: <short goal>
description: <one line>
status: active | paused | achieved | dropped
success_criteria: [ "<measurable signal>", ... ]   # optional but expected for `active` objectives — the anchor /audit grounds progress against; the audit flags an active objective that lacks it. MEASURABLE: name the command and today's number, never "faster" or "better"
timestamp: <ISO 8601>
---
```

## type: Project  (`projects/<slug>/project.md`)

```yaml
---
type: Project
title: <project name>
description: <one line>
kind: build | research                # build = ships code via PRs (default); research = produces in-bundle deliverables
objective: /objectives/<slug>.md      # optional: link up to the objective it serves, WHEN one exists. Omit it and this project's own `success_criteria` are its anchor — see "Where a project's success is measured" below
success_criteria: [ "<measurable signal>", ... ]   # optional: this project's own measurable success. Same rule as an objective's — name the command and today's number. What /audit grounds against when there is no `objective:`
target_repo: <org>/<repo>             # BUILD only: default repo for this project's tasks (<org> from instance.config.json). Omit for research.
deliverables: [ "<artifact>", ... ]   # RESEARCH only: what this project produces, e.g. "tech landscape per domain (md)", "exec summary deck (marp)"
autonomy: gated | <mode>              # optional (default gated). gated = the human promotes `ready` AND merges — both gates absolute. Any other value names a delegated-authority mode defined in `AUTONOMY.md`, and is INERT unless that file exists (absent ⇒ gated). See "Delegated authority" below.
clis: [ <name>, ... ]                 # optional: external CLIs/integrations this project's agents may use (e.g. render, supabase). A declaration — agents still verify a CLI works before relying on it. BUILD-SHAPED: research projects dispatch no agents, so `/new-project` never asks for it there (an explicit clis= flag is still recorded).
browser: off | claude-for-chrome      # optional (default off). claude-for-chrome = agents may drive the browser via the claude-in-chrome tools when present — background role agents included, each with its OWN tab group (not the human's tabs), so navigate explicitly. Absent tools = degrade, don't fail. Writes follow the project's autonomy: ask-first by default, permitted where a delegated mode says so (AUTONOMY.md). See "Browser access" below.
owner: <github-username>              # optional: which human's work this project is, on an instance shared by more than one. A GitHub USERNAME, never an email. Absent ⇒ nobody in particular, so it is this clone's — see "Ownership on a shared instance" below. Gates DISPATCH only, never promotion.
retain: true                          # optional (default absent = false). Closeout KEEPS this project's folder instead of `git rm -r`-ing it. Governs the FOLDER ONLY — not the tasks, not the status: a retained project still ends `status: done` with every task terminal. See "Project & objective completion" below.
deliverable_paths: [ /projects/<slug>/deliverables/<file>, ... ]   # WRITTEN BY CLOSEOUT, not by hand. Bundle-relative paths, resolved once from each task's `artifacts:` and verified on disk at closeout. `[ ]` means closeout looked and found none.
status: active | paused | done
timestamp: <ISO 8601>
---
```

**Two kinds of project.** `kind: build` (default) ships changes to a product repo
as PRs, executed by role agents — the full `draft → ready → dispatch → PR → merge`
loop. `kind: research` produces **deliverables inside this bundle** (markdown,
marp/pptx decks, assets) — strategic/discovery work that has no `target_repo` and
opens no PRs, and is often the **entry point** whose conclusions graduate into
`knowledge/` and spawn new objectives and build projects. Research artifacts live
under `projects/<slug>/deliverables/` (one file per chunk — e.g. per domain/team).
Research tasks are **human-driven**: the PM refines and tracks them but never
dispatches them to role agents (see the lifecycle note).

**Retention (`retain: true`) is research-shaped, for a structural reason.** A build
project's real output is merged PRs, which live in the *product repo's* history and
are already linked from `log.md` — the folder is scaffolding around work that lives
elsewhere, so build stays remove-by-default. A research project's output **is** the
folder. The rule is "retain where the artifact actually lives," and the field is the
switch. It governs the folder only: a retained project is still `status: done` with
every task terminal, and it is not reopenable — new work starts as a new project
seeded from the deliverables.

**Where a project's success is measured.** `success_criteria` **on the project** is the
default: self-contained work, measured against itself. `objective:` is the opt-in for a
goal that outlives this project, and a project may carry both. `/audit` grounds against
the **objective's** criteria where there is an `objective:`, against the **project's own**
where there is not, and reports **"no criteria"** for a project carrying neither — never a
silent pass, because a project with no anchor cannot be honestly audited. Same bar for the
lines either way: **measurable — name the command and today's number.**

## type: Phase  (`projects/<slug>/phases/<n>-<slug>.md`)

For large projects sliced into sequential stages.

```yaml
---
type: Phase
title: <phase name>
description: <one line>
project: /projects/<slug>/project.md
order: 1                              # sequence within the project
status: not-started | active | done
depends_on: [ /projects/<slug>/phases/<prev>.md ]   # optional
exit_criteria: [ "<what must be true to close the phase>", ... ]
timestamp: <ISO 8601>
---
```

## type: Task  (`projects/<slug>/tasks/<id>.md`)

```yaml
---
type: Task
title: <imperative summary>
description: <one line>
kind: build | research                # inherits the project's kind if omitted
status: draft                         # initial state; see lifecycle below
assignee:                             # BUILD: role slug set by PM (software-engineer | devops-engineer | qa-reviewer). RESEARCH: usually empty (human-driven)
owner: <github-username>              # optional: overrides the project's `owner` for this one task, on a shared instance. Absent ⇒ the project's owner; absent there too ⇒ this clone's. See "Ownership on a shared instance". Gates DISPATCH only, never promotion. Omit the key entirely when the project's owner is right — an empty value reads as absent, and a placeholder would read as a declared owner.
model:                                # optional: override model routing — a tier (light|standard|deep) or any raw model alias (e.g. haiku|sonnet|opus). PM resolves tiers via instance.config.json and passes aliases verbatim.
target_repo: <org>/<repo>             # BUILD only: inherits project default if omitted
objective: /objectives/<slug>.md
phase: /projects/<slug>/phases/<n>-<slug>.md          # optional, links task to its phase
depends_on: [ /projects/<slug>/tasks/<id>.md, ... ]   # optional
acceptance_criteria: [ "<testable outcome>", ... ]    # PM fills/expands during refine
worktree: /abs/path/to/worktree        # optional, BUILD only. MACHINE-READ by scripts/reclaim-worktree.sh.
branch:   <branch-name>                # optional, BUILD only. MACHINE-READ. Required whenever `worktree:` is set.
# Both are written by the project-manager AT DISPATCH, and read only when the task
# reaches `done`, to reclaim that one worktree. They are machine-read — unlike
# `interfaces:` below — so keep them exact: an absolute path and the literal branch name.
#
# Why they exist at all: reclaiming a worktree by SCANNING a directory destroyed three
# running agents' work, because a scan cannot tell a fresh dispatch that has not committed
# from an already-merged branch — in git they are identical. The task record can, because
# it was written at dispatch by the thing doing the dispatching. So the reclaim is driven
# by these two fields or it does not happen: no `worktree:`, no removal, ever.
#
# `worktree:` set while `branch:` is absent is a REFUSAL, not a licence to skip the check
# — a recorded path with no recorded branch cannot be proven to still be the worktree this
# task created, and a worktree path can be recycled.
interfaces:                           # optional, BUILD-shaped. NOT machine-read.
  consumes: [ "<exact name/signature this task depends on>", ... ]
  produces: [ "<exact name/signature this task exposes>", ... ]
# Why this exists: a dispatched agent sees ONLY its own task file, so `depends_on`
# tells it the ORDER but never the NAMES. Two sibling tasks then invent two
# spellings of the same function, route or column, and the mismatch surfaces at
# review. Write exact identifiers, never prose. Omit the key entirely when a task
# shares no surface with its siblings — an empty block is noise.
open_questions: [ "Q1: <blocking question for the human>", "Q2: ...", ... ]   # PM-managed; ONLY still-unanswered questions. Number every entry (Q1, Q2, …). The human answers an entry by appending ` --- <answer>` to it on the same line (e.g. "Q1: Which region should we default to? --- eu-central-1"); the PM treats any text after the ` --- ` delimiter as the answer, folds it into the task (Context / acceptance_criteria / Notes) and MOVES that entry to `answered_questions`, stamped `by <login>` with the human who answered ("Decisions name the human" below) — this list still EMPTIES, because that is the signal promotion keys on. (Answering in-session works too.)
advisor_notes: [ "<ISO 8601> · <the concern, as a question>", ... ]   # optional, PM-managed. Concerns raised by an ADVISORY agent — the tick `advisor`, or the `plan-architect` approach critique the PM runs at refine time — that the PM has NOT yet triaged. DELIBERATELY NOT A GATE: unlike `open_questions` this does NOT block promotion, does NOT put a row in AWAITING.md, and `validate-bundle.sh` adds no check for it — a concern is the loop's problem first, not the human's. On the next tick the PM triages each entry and it leaves this list one of two ways: RESOLVED, moving to `answered_questions` prefixed `advisor:` so the provenance survives; or ESCALATED, copied into `open_questions` prefixed `advisor:` because the PM genuinely cannot decide — and only then does it reach the human and the board. Absent means no concern is outstanding, which is the normal state. **No customer PII**, same rule as every other document field.
answered_questions: [ "<ISO 8601> by <login> · Q1: Which region should we default to? --- eu-central-1", ... ]   # PM-managed answer history: one FLAT LINE per answered entry — the timestamp it was folded in, `by <login>` naming the human whose answer it was ("Decisions name the human" below; an entry the LOOP wrote, an `advisor:` receipt, carries no `by` because no human decided it), then the `open_questions` entry VERBATIM. Question and answer already sit on one line either side of the ` --- ` delimiter, so MOVING the line preserves both with zero new parsing and no nested mapping. A question that became moot moves here too, with the reason as its answer (no second mechanism for "dismissed"). NOT MACHINE-READ: no script parses it and no gate consults it — the PM reads its own `advisor:` lines as the receipt that an approach critique already ran, which is a receipt and not a gate — and `validate-bundle.sh` deliberately adds no check for it — a free-text list is neither an enum nor a reference, and a "missing ` --- `" warning is exactly the noise that buries real errors. Absent means no question has been answered yet — the PM creates the key on the first move, so a scaffold needs no placeholder. It never substitutes for `open_questions` emptying. **No customer PII**: these are human answers that now persist for the life of the repo, under the same rule that governs all task/project/log/deliverable text.
open_caveats: [ "<ISO 8601> · <the conclusion this contradicts, and the evidence against it>", ... ]   # optional, TICK-WRITTEN. A caveat a tick recorded against a CONCLUSION about this task — "the rollout has not fixed what this is about to be cancelled for". It outranks anything an actor was told (`project-manager.md` step 0), and it is **cleared only by evidence**, never by the actor whose conclusion it contradicts wanting to proceed. NOT A PROMOTION GATE: unlike `open_questions` it does NOT block `draft → ready` and puts no row in `AWAITING.md` — a caveat raised on an in-progress task must not stop the human promoting a sibling. It is a **TERMINAL-WRITE** gate instead: `validate-bundle.sh` ERRORS on a task that is `done` or `cancelled` while this list is non-empty, and quotes the caveat text so the reader knows what is being held. Absent ⇒ nothing outstanding, which is the normal state. Clear it in its OWN edit, before the status write, so the record shows the evidence and the conclusion in that order. **No customer PII**, same rule as every other document field.
# `open_caveats` is deliberately read by `validate-bundle.sh` ONLY. `build-board.sh` and
# `write-snapshot.sh` do NOT read it, and that is a scope decision rather than an oversight
# — a fully wired task field reaches ~30 files (`open_questions` is read by 4 scripts, 3
# agents, 5 skills, 4 spec docs and ~10 harnesses), so the gate ships first and the
# surfacing follows if the field earns it.
#
# REJECTED, so it is not re-proposed: reusing `open_questions` with a `caveat:` prefix,
# matching the existing `advisor:` convention, at zero new frontmatter surface. Declined
# because a non-empty `open_questions` already blocks `draft → ready`, so a caveat raised
# on an in-progress task would block promotion as a side effect — conflating "a question
# for the human" with "a warning that outranks you".
pr: [ ]                               # BUILD only: PR URL(s) set by the role agent(s) — a task may fan out to several
stall_count: 0                        # PM-OWNED, NEVER HAND-EDITED. Consecutive rounds this task ended on the SAME blocker; absent ⇒ 0. The tick maintains it with `scripts/stall-counter.sh record` after every round, and it resets on progress: a changed blocker, a new commit or review thread on the PR (`--progress`), or a human edit — a task the human puts back in the queue (`draft`/`ready`) at or past the cap starts over.
last_blocker: "<what the last round ended on>"   # PM-OWNED, NEVER HAND-EDITED. The blocker text or failing check the counter is counting, whitespace folded to one line. Absent ⇒ none. It is read by a human here and in `AWAITING.md` and persists for the life of the repo: **no customer PII, and never a secret or an environment value** — the failing check, not the output that failed.
# At `stall_count >= maxStallRounds` (`instance.config.json`, **absent ⇒ 2**) the PM stops
# re-dispatching: `stall-counter.sh escalate` sets `status: blocked`, records the blocker under
# `# Notes`, and emits the one `⛔ **unblock**` line for `AWAITING.md`. Same blocker twice ⇒ the
# human decides, never a fresh agent at the same wall.
do_not_repeat: [ "<approach> — <evidence it failed on>", ... ]   # AGENT-OWNED, one line per approach an earlier round of THIS task already tried, at most 200 chars each and capped at 10. Written by the role agent with `scripts/do-not-repeat.sh append` whenever its round ends without a green PR (`CONVENTIONS.md`), and read at the NEXT dispatch: `do-not-repeat.sh brief` prints the block the PM pastes into the dispatch brief verbatim, under a fixed heading. Absent ⇒ nothing has failed yet, which is every first dispatch. The counterpart of `stall_count`: that says how MANY rounds, this says what not to try again. At the cap the script refuses and the PM folds the oldest entries into `# Notes`. It is read by a human here and pasted into a brief: **no customer PII, and never a secret or an environment value** — the failing check, not the output that failed.
artifacts: [ /projects/<slug>/deliverables/<file>, ... ]   # RESEARCH only: the deliverable file(s) this task produces
timestamp: <ISO 8601>
---
```

The task **body** uses these conventional headings: `# Context`, `# Notes`
(PM refinement notes), `# Result` (role agent summary, or — for research — a
pointer to the finished deliverable(s) on completion).

## type: Agent  (`agents/index.md` lists the roster)

Executable definitions ship in the **`ai-bridge` plugin** (`/plugin install
ai-bridge@ai-bridge`), one per machine — not in the bundle. Dispatch them by their
**namespaced** name, `ai-bridge:<role>`: a bare agent name does NOT resolve (measured
2026-09-02). The roster doc is a human-readable routing reference.

**`roles` vs `roleTiers` in `instance.config.json`.** The two lists look like they
should share membership and deliberately do not. `roles` is the roster the PM may
dispatch a task to — every agent that can ever be a task's `assignee`. `roleTiers`
is broader: it maps a model tier to ANY agent this instance dispatches, including
ones no task is ever assigned to. `plan-architect` is the worked example — it is
in `roleTiers` and absent from `roles`, because `/plan` and the PM's approach
critique dispatch it directly and no task is ever assigned to it. The consequence:
`models.apex` today affects exactly one agent, `plan-architect`, and that agent
appears in no `roles` list, so "what does `apex` cost me?" is unanswerable from
`roles` alone — read `roleTiers`. This asymmetry is intentional, not a bug to fix
by adding `plan-architect` to `roles` or deleting its `roleTiers` row; see
`tests/roles-roletiers-asymmetry.test.sh`, which pins it.

## Knowledge base types  (`knowledge/`)

OKF's native use: curated knowledge about systems and decisions. The `knowledge/`
section is part of this bundle, so its docs cross-link freely to/from objectives,
projects, and tasks. **No customer PII** in any knowledge doc; authoritative
*data* questions route to the owning team (see `knowledge/teams/`), not the KB.

### type: Service  (`knowledge/services/<name>.md`)

```yaml
---
type: Service
title: <service name>
description: <one line>
repo: <org>/<repo>                # owning repo (or monorepo)
path: services/<name>             # path within a monorepo, if applicable
owner:                            # team / person, optional. FREE TEXT and read by nothing — unrelated to the `owner` that gates dispatch on a Project/Task (see "Ownership on a shared instance").
stack: [ <framework>, <orm>, ... ]
runtime: node-<major>
status: active | deprecated
timestamp: <ISO 8601>
---
```
Body headings: `# Overview`, `# Stack & data`, `# Dependencies`, `# Notes`.

### type: Finding  (`knowledge/findings/<slug>.md`)

A durable learning or architecture decision (ADR-style).

```yaml
---
type: Finding
title: <the statement / decision>
description: <one line>
lesson: <one line — the takeaway the next agent needs; required, and it becomes the index row's summary VERBATIM>
category: decision | learning | gotcha
tags: [ <tag>, ... ]              # from /knowledge/vocab.md ONLY — never a new word
status: current | superseded | corrected
supersedes: [ <slug>, ... ]       # Findings this one replaces
superseded_by: <slug>             # set together with status: superseded
source:                           # where it came from, e.g. /projects/.../tasks/<id>.md or a PR URL
timestamp: <ISO 8601>
---
```
Body headings: `# Context`, `# Finding` (or `# Decision`), `# Rationale`,
`# Implications`. Link to the Services/tasks it concerns. **40 lines, whole file**
(`CONVENTIONS.md` → "Write less"); the history that produced it lives in the task doc.

**`lesson:` is the index row.** `build-kb-index.sh` copies it into `knowledge/index.md`
verbatim, so a hand-written summary can no longer drift from the document. Without one the
row falls back to `description:` and `--check` warns.

**Tags are a closed set.** `/knowledge/vocab.md` lists every allowed tag with its aliases;
ground a lookup by **longest match** over both columns and use the canonical tag.
`build-kb-index.sh --check` refuses a tag that is in neither column — extending the
vocabulary is an edit to that file, in the same change.

#### Superseding a Finding

The move when a Finding stops being true. **Never delete one** — a decision nobody can
find the reversal of gets re-made.

1. On the old Finding: `status: superseded`, `superseded_by: <new-slug>`, and a dated
   section naming the replacement (`## Superseded 2026-09-06 — replaced by [[new-slug]]`,
   one line saying what changed).
2. On the new Finding: `supersedes: [ <old-slug> ]`.
3. Rebuild: `build-kb-index.sh`. Superseded rows render in their own section **below** the
   current ones, so the index-first read skips them.

**A superseded Finding is history and is never citable.** `cite-check.sh` reports a
`[[slug]]` naming one as `SUPERSEDED` and drops it, exactly as it drops an unread id — cite
the replacement instead. Both directions of the edge must resolve to a real Finding, and
`--check` counts them and fails on one that dangles.

Who runs it: the `cataloguer`'s closeout pass, and `/close-project` step 2.

### type: Team  (`knowledge/teams/<slug>.md`)

Who owns what. Used to route questions and clarify responsibility boundaries.

```yaml
---
type: Team
title: <team name>
description: <one line>
owns: [ <system/area>, ... ]          # what this team is the authority for
contact:                              # lead / channel, optional — no PII beyond work contact
timestamp: <ISO 8601>
---
```
Body headings: `# Responsibilities`, `# Owns`, `# Contact`, `# Notes`.

### type: Runbook  (`knowledge/runbooks/<slug>.md`)

```yaml
---
type: Runbook
title: <procedure>
description: <one line>
applies_to: [ <service or area>, ... ]
timestamp: <ISO 8601>
---
```
Body headings: `# When to use`, `# Steps`, `# Verification`, `# References`.

### type: Reference  (`knowledge/references/<slug>.md`)

A durable specification or contract the bundle keeps as reference material —
longer-lived than a `Finding` (which states one decision or learning) and not a
procedure (`Runbook`) or a system description (`Service`).

```yaml
---
type: Reference
title: <what this specifies>
description: <one line>
status: current | superseded
timestamp: <ISO 8601>
---
```

This is the fifth knowledge kind, and it is deliberately the **thinnest**: the
`Reference` type already existed for the bundle's own root documents (`SCHEMA.md`,
`AUTONOMY.md`), which sit outside every schema-defined location and are therefore
never validated. `knowledge/references/*.md` **is** a schema-defined location, so
those documents were already being checked for `type`, `timestamp` and dangling
frontmatter references — the one gap was the `status` enum, because `Reference` had
none. Declaring the kind closes exactly that gap and adds no field the live
documents do not already carry. Root documents are unaffected: they are not in a
schema-defined location, so no enum reaches them.

# Task lifecycle

```
draft ──│ HUMAN promotes │──► ready ──► in-progress ⇄ in-review ──► done
                                            └─ changes requested ─┘

  · `HUMAN promotes` is the default — and the only behaviour unless `AUTONOMY.md`
    delegates a gate to the loop (see "Delegated authority")
  · a `draft` with non-empty open_questions is blocked on a human answer
  · any active state ⇄ blocked     (returns to its prior status when cleared)
  · any state ──► cancelled        (terminal: abandoned / superseded / decided-against)
```

| Status | Meaning | Who sets it |
|---|---|---|
| `draft` | **Initial state.** Refined once `acceptance_criteria` are filled; **awaiting human approval**. Non-empty `open_questions` = blocked on a human answer (don't promote). | Human or PM |
| `ready` | **Approved for execution.** The human sets this — or the loop, on a project whose `autonomy` delegates it (`AUTONOMY.md`). | Human — or the loop where delegated |
| `in-progress` | Dispatched to a role; agent is working (no PR yet, or changes requested). | PM (on dispatch) / role agent |
| `in-review` | PR(s) open, awaiting review/merge. Returns to `in-progress` if review requests changes. | Role agent |
| `blocked` | External / dependency blocker; returns to its prior status when cleared. | Anyone |
| `cancelled` | Abandoned, superseded, or decided-against (terminal). | Human / PM |
| `done` | **All** of the task's PR(s) merged. | PM (reflects merge) / Human |

**Multi-PR tasks.** A task may fan out to several PRs (e.g. one per service); `pr:`
is a list. It stays `in-progress`/`in-review` until **all** its PRs merge, then
`done`. Keep per-PR detail in the `# Result` section.

**Independent verification gate.** Before an `in-review` PR is eligible to merge it
must pass an **independent** reviewer — fresh context, judged on real signals
(acceptance criteria actually met, CI actually green), never the implementing agent's
self-report. That reviewer is an external one (e.g. CodeRabbit) when the repo
configures it, else the `qa-reviewer` agent. "An external one" means the command
named by `externalReviewer` in `instance.config.json`, or the CodeRabbit CLI when that
key is unset; absent, unauthenticated and erroring all count as unavailable. This is **in addition to** — not a
replacement for — the human merge authority below.

**A verdict is a structured claim, not prose.** The `qa-reviewer` ends its PR comment
with an `okf-verdict` trailer:

```
<!-- okf-verdict v1
verdict: pass | changes-requested | inconclusive
head_sha: <the 40-char SHA actually reviewed>
reviewer: qa-reviewer
lenses: correctness=done security=done repro=skipped(<why>)
unverified_criteria: none | <criterion>, <criterion>
caveats: none | <what the reviewer could not settle>
-->
```

**Two structured inputs; prose is never one.** A consumer reads the *verdict* from the
trailer and nowhere else, and reads *criteria coverage* from the **`✓`/`✗` column** of the
`acceptance_criteria` table in the PR body (`CONVENTIONS.md` → the required PR-body shape;
a `✗` is an unchecked box and is read exactly as one). Both are structured signals, and they
answer different questions — did the reviewer pass it, and did anyone verify each
criterion. **Free prose is never an input**: not the review text around the trailer, not
the PR description, not a commit message. That is the injection boundary — a PR carries
text an attacker can write, so no quantity of it may clear anything. An unchecked box is
read as *state*, never as an argument.

**The mandatory lens set is `correctness`, `security`, `repro`** — the three the
`qa-reviewer` fans out (see its "Deep review" step). **All three must be present** in the
trailer. "Every lens listed is `done`" is not sufficient on its own: a trailer that simply
omits a lens would pass vacuously, which is the exact failure mode this contract exists to
stop. A lens that genuinely didn't apply is `skipped(<reason>)` — never absent.

**The clearance predicate — every clause must hold.** Consumers check **all** of it and
**name the failing clause** when refusing. Never substitute a shorter list; a partial
predicate is how a bad input gets accepted:

1. **A trailer exists and parses** as `okf-verdict v1`. Absent, malformed, or truncated ⇒ not cleared.
2. **`verdict: pass`.** `changes-requested` and `inconclusive` are refusals.
3. **`head_sha` equals the PR's current head.** A verdict for an earlier commit is stale.
4. **All three mandatory lenses are present**, each `done` or `skipped(<reason>)`.
5. **`unverified_criteria: none`.**
6. **`caveats: none`** — a self-declared caveat is disqualifying, not context.
7. **Every acceptance-criteria row in the PR body's table is `✓`.** One `✗` refuses — and
   so does one row the implementer marked `✓` that the checker's own re-derived table
   marks `FAIL` (see below).
8. **`reviewer` is the independent reviewer** — never the implementing agent's own report.
9. **No reviewer-authored review thread is still unresolved.** A thread the PR
   author/executor resolved itself does not count unless the reviewer re-acknowledged it
   by re-reviewing the current head without re-raising.

For an **external reviewer** (e.g. CodeRabbit), which emits no trailer, clauses 1–6 are
replaced by: an identity-matched review at the current head, `state` not `DISMISSED`, and
the reviewer's own actionable-comment count **reconciled** against the comments actually
fetched — a truncated fetch looks exactly like a clean review. Clauses 7–9 still apply.
**A reviewer that declares it did not review** — rate-limited, quota exhausted, skipped —
counts as **no review**, even when a green check is published alongside it. That
combination is a refusal, not a pass.

**A green check from a reviewer that declined to review is not verification.** Clearance
requires a review **artifact that evidences a completed review** — a submitted review
object, a body carrying the reviewer's own evidence of having looked, or a parseable
verdict trailer — never a status-check conclusion, which reports only that the integration
ran. **Not-a-refusal is not evidence**, and that distinction is the whole gate: the
reviewer publishes an artifact on nearly every PR *before* it has read anything
("Currently processing new changes in this PR…", quoting the head), so a check that clears
whatever it cannot classify as a refusal clears that too. A refusal is identified by
**language**, never by the commit range it quotes: the refusal comment carries the same
`between <base> and <head>` line a real review carries, at the same head, so the range
cannot tell them apart. Unknown or unreadable reviewer state is **unverified**, never
clearance. `scripts/review-clearance.sh` computes exactly this, and exit 0 is its only
clearance.

**The checker's table is the review artifact when no external reviewer exists, and it is
NOT the implementer's.** The PR body's `✓`/`✗` table is the *worker's* claim; the
`qa-reviewer` posts a second table as a PR comment, re-derived from the task's
`acceptance_criteria` and the diff, one `PASS`/`FAIL` per criterion with one command or
artifact per row and no partial credit. `scripts/pr-verdict-clearance.sh` reads the two
and is the reader for clause 7: **exit 0** they agree, **1** the worker passed a criterion
the checker failed, **3** the checker's table is malformed, **4** the checker posted under
the author's own login, **2** unknown. Only exit 0 is clearance.

**The identity rule is clause 8's, and on a solo bundle it is a KNOWN LIMIT rather than a
gate.** `pr-verdict-clearance.sh` compares the checker's `login` with the PR author's,
exactly as `review-clearance.sh` does — and where every agent shares one `gh` login, those
are equal by construction, so exit 4 is the standing answer and the routing to a human *is*
the gate. It is stated rather than worked around: a second principal needs a second account
(`docs/sharing.md`), and nothing in a comment can evidence one that does not exist.

**A verdict that reports a refusal must carry its trailer, or it classifies as one.** The
fallback reviewer's job on a rate-limited PR is to *say* the hosted reviewer declined —
quoting the words, and the vendor's own sentinel. That prose matches the refusal language
the clearance check looks for, so a verdict read against the reviewer's own account
classifies as a refusal *of itself*: the reviewer disqualified for having reported
accurately. The `okf-verdict v1` trailer above is the guard, and this is its second job —
an artifact carrying a parseable trailer is a review whatever its prose quotes, because a
trailer is a structured claim and prose is never an input (see "Two structured inputs").
Fencing the quoted refusal also works and reads better, but it is not the guarantee:
fences hold only while they stay balanced.

**"Parseable" is load-bearing, and it is not "the string appears somewhere".** A consumer
must require the whole block — the `<!-- okf-verdict v1` marker alone on its line, a `-->`
closing it, and `verdict`, `reviewer` and a `head_sha` **equal to the head being cleared**
— and must accept it only from the account it was told to read. As a substring it is a
nineteen-character bypass that outranks every refusal: this repository's own diffs contain
the string, reviewers quote diffs, and anything that quotes one would otherwise declare
itself reviewed.

**And "not cleared" has more than one shape.** A review that exists but was made at an
*earlier* commit is **stale** by clause 3, not absent and not a refusal — the ordinary
state wherever the reviewer does not re-review every push. Say which one you mean when
you refuse; "the reviewer declined" about a real review of an older head is a false
report that sends the human looking for a quota that was never exhausted.

**One verdict per reviewed head — and a new head needs a new one.** A reviewer posts one
synthesized verdict for the commit it reviewed, never an early `pass` amended later. When
the head advances, clause 3 makes the old verdict stale, so that new head must be
**re-verified** and gets its own trailer (the loop re-dispatches; see the PM's step 4).
This is the normal path out of `changes-requested`: fix, push, get a fresh verdict for the
new commit. **Re-verifying a new head is not the same as the "don't re-review to confirm a
fix" cost rule** — that rule is about paying an *external* reviewer twice for the *same*
diff. A different commit is a different diff, and the merge gate cannot be satisfied by a
verdict for code that is no longer there.

**Why this is a contract and not a convention.** "Approve now, finish the analysis later"
is indistinguishable from a real pass once it is prose: an APPROVE whose own body said two
fanned-out lenses were still outstanding has cleared a money bug here before. Clause 7
carries the same weight for a different reason — role agents mark a row **`✗`**
when they could not actually verify it (the honest state; never mark `✓` for something you
couldn't confirm), because deterministic checks passing is not evidence for a criterion no
deterministic check covers.

**Two human authorities** keep this semi-autonomous. Both are the human's **by default**,
and each is the human's **absolutely** unless a project explicitly delegates it (next
paragraph) — there is no third way for the loop to acquire either:
1. **Promote `draft → ready`** — the only way work enters execution. By default the PM never sets `ready`.
2. **Merge the PR(s)** — by default the PM never merges; it only *reflects* a merge by setting `done`.

**Delegated authority (optional, and off by default).** A project's `autonomy` field
(default `gated`) can hand one or both of these gates to the loop — replacing the human
with a **machine** anchor, never a self-report. The available modes, their anchors, and
their preconditions live in **`AUTONOMY.md`**, which is also the capability's on/off
switch: **if no such file is found, there are no other modes and every project is `gated`
no matter what its `autonomy` field says.** Read it only when a project's `autonomy` is
something other than `gated` — most ticks never need it. Either way the human opts in per
project at creation; no agent escalates it.

**There are exactly TWO places that file can be, and `scripts/resolve-autonomy.sh` is the
one reader of both.** Nothing else may re-derive this; a second reader is a second answer
to "may the loop merge without a human".

| Order | Where | What makes it count |
|---|---|---|
| 1 | **`<bundle>/AUTONOMY.md`** — the bundle root | The file simply being there. **Root wins outright**, so a bundle that carries its own real file keeps working byte for byte, with or without any companion, and no companion can override what it says. |
| 2 | **`<companion plugin root>/companion/AUTONOMY.md`** — an installed companion plugin | The plugin being **INSTALLED**, read from the installed-plugins registry (`installed_plugins.json`), and installed from the **same marketplace core itself came from**. |

**Location 2 is decided by the registry and NEVER by the plugin cache tree, and that
distinction is the whole of "uninstall turns it off".** The cache keeps every version ever
fetched, uninstalled ones included — measured: 11 stale version directories on a machine
with the companion uninstalled, its `companion/AUTONOMY.md` still sitting on disk in each
one. A resolver that answered from the cache would therefore keep answering *installed*
forever, and the human's promotion and merge gates would stay delegated after the human
removed the thing that delegated them, with nothing anywhere saying so. So: **the registry
is the only authority for location 2**, a registry entry naming a directory that is gone
is not a companion (the answer is not "find another cached version"), and **every unknown
resolves to `gated`** — no registry, an unparseable one, a format this reader does not
understand. The safe end of an unknown is the end where the human keeps both gates.
`tests/companion-plugins.test.sh` pins the uninstalled-but-cached case against a fixture
laid out exactly as the real cache is.

**Research tasks (`kind: research`) are human-driven.** Same statuses, but no PRs
and no role-agent dispatch — the human (with Claude in-session) produces the
deliverable. The PM still **refines** them (turns `deliverables` into concrete
`acceptance_criteria`, surfaces `open_questions`) and **tracks/reflects** status,
but **never dispatches** them. The mapping: `ready` = approved to work on now;
`in-progress` = being drafted; `in-review` = a draft deliverable is up for human
review; `done` = the deliverable is **approved** (record paths in `artifacts:` and
point to them from `# Result`). Approval of the deliverable replaces the merge gate.

Everything between `ready` and `done` is the PM's to drive autonomously.

## Decisions name the human

**Every human decision a document records carries `by <login>`, in one form, and it is a
GitHub login — never an address** (`people` maps the two, and an email in a task document
is the no-PII rule broken). Git history knows who authored the bundle commit; the document
a reader opens has to say it too, or a shared bundle's audit trail is a `git log`
archaeology exercise. The four stamps: an `answered_questions` entry reads
`<ISO 8601> by <login> · <the entry verbatim>`; a promotion `draft → ready` is stamped by
the **next tick** as one `# Notes` line, `promoted <ISO 8601> by <login>`; a preview
approval is `preview approved <ISO 8601> by <login>` on the same list; and a project
closeout's `log.md` entry, plus **every tick ledger line**, names the login the decision
or the tick ran as (`* TICK <ISO 8601> by <login> …`). `scripts/decision-stamp.sh` is the
one resolver — `--self` for a decision taken in this session, `--author`/`--promotion` for
one that arrived as a commit, which is how a **hand**-promotion and a reply pushed from the
*other* clone attribute to the other human rather than to whoever's loop noticed. It
resolves the git author's email through `people`, and where it cannot it prints
`<unknown>`: the stamp is written anyway, because an omitted stamp is indistinguishable
from a decision nobody made. **None of this is a gate** — no validator checks it, nothing
blocks on it, and a missing stamp is a later tick's to add.

# Ownership on a shared instance

An instance may be shared by more than one human: each clones the same bundle repo
and runs their own `/ai-bridge:dispatch`, so both see one set of projects and one knowledge base,
and can hand a project or a single task to the other. `owner` is what keeps their two
loops from doing the same work twice — and it is also what lets each clone's **own**
locally rendered board separate their projects from the other's, since every owner but
this one is read from the tracked task documents at this clone's git `HEAD`.

**Two operations, not one chain.** Deciding whether a task is *this clone's* means
first **resolving** who owns it (the four steps below), then **comparing** that owner
against this clone's `ownerGithubUser`. Writing `ownerGithubUser` into the resolution
chain as a third owner source is the mistake to avoid: it reads as though setting it
*assigns* unowned work, when in fact it only answers "who am I?".

**Resolution order — four steps, and every doc naming `owner` states all four:**

1. the task's own `owner:` (`projects/<slug>/tasks/<id>.md`);
2. else the owning project's `owner:` (`projects/<slug>/project.md`) — the normal
   place to set it, since work is usually handed over a project at a time;
3. else **`defaultOwner`** from `instance.config.json` — **tracked**, see below;
4. else nobody: the task is **unowned**, and every clone treats it as its own.

Absence is never an error at any step. With none of the three keys set, step 4 clears
everything, which is exactly how a single-human instance already behaves.

**`defaultOwner` is tracked, and deliberately not overridable per machine.** Step 4 is
a **double-dispatch bug** as soon as a bundle has two clones: an unowned task resolves
to "mine" on clone A *and* "mine" on clone B, so both loops dispatch it — the very
thing ownership exists to prevent. `defaultOwner` closes that by naming, in the file
**both** clones read, who unowned work belongs to; exactly one clone then matches. That
guarantee only holds while both clones agree, so this is the one key here that is read
from the tracked config **only**. A local override would let them disagree and would
reintroduce the bug.

**"This clone's human" is a separate question** — who *you* are, not who owns a task —
and comes from `ownerGithubUser` (`instance.config.local.json`, else
`instance.config.json`). On a shared bundle it belongs in the **local** file: a tracked
value makes both clones claim the same identity, so one would dispatch the other's
work. **Absent from both, this clone has no configured human**: unowned tasks still
clear (step 4), and a task naming an owner is refused, because an unconfigured clone
cannot prove the name is its own.

The value is a **GitHub username**, never an email — public, stable, and it keeps
addresses out of tracked documents, the same no-PII rule that governs every other
field here. Comparison is case-insensitive.

**Not to be confused with `owner:` on a `Service`.** That is a different,
pre-existing field: free text naming the owning *team or person* for a system in the
knowledge base, purely descriptive, and nothing reads it. The dispatch gate reads
`owner` **only** on `Project` and `Task` documents, and a `Service` is neither — so
the two never meet. Don't unify them: one is a routing note about a system, the other
is a machine-compared identity.

**It gates DISPATCH, not promotion.** `scripts/task-owner.sh <task-path>` is the
resolver, and **exit 0 is the only clearance**: the loop dispatches a `ready` build
task only when it exits 0, and leaves anything else alone. It does **not** gate
`draft → ready`: a shared board means either human may promote any task, whoever
owns it, and gating promotion would be gating the wrong verb. Nor does it gate
commits, the KB, or `/close-project`.

**The loop still sees and reports the other human's work** — that is the entire
point of sharing. Only `AWAITING.md` narrows: it queues decisions *this* human can
act on. Someone else's tasks appear in the tick report, not in the queue.

**It is not a lock.** Git is not a lock, and neither is this. It stops two loops
double-dispatching the *same* task. It does not stop two loops acting in the same
tick window on tasks they each own, or two humans pushing the control panel at once
— those stay ordinary git conflicts, resolved the ordinary way. Claiming more than
that would be claiming a guarantee the mechanism cannot make.

**Derived files are not shared.** `index.md` (root and per-project) is regenerated
every tick from the documents, so on a shared instance it is gitignored like
`AWAITING.md` and `SNAPSHOT.json` — a derived file two loops rewrite is a merge
conflict on every push, and the documents it summarises are the source of truth.
`knowledge/index.md` stays **tracked**: it is the KB's lookup surface, it changes only
when the KB changes rather than every tick, and an agent told to scan it needs it to exist
in a fresh clone. It is **derived all the same** — `build-kb-index.sh` rebuilds it from
frontmatter and `--check` fails when the two disagree, so it is regenerated and committed,
never hand-edited.

## Per-machine config overrides

`instance.config.json` is **tracked**, so every value in it is a statement both clones
read. Some values cannot be shared: an absolute path on one machine, or which human a
clone belongs to. Those go in **`instance.config.local.json`** beside it — gitignored
(`/ai-bridge:init` adds the line), read **first**, and **entirely optional: no local file
means the tracked file answers exactly as it always did.**

**JSON `null` is ABSENCE, not a value.** A key or entry set to `null` in either file reads
exactly as one that is not there: `scripts/resolve-config.sh` prints nothing and exits 1,
and the caller applies the fallback its own document states. So a **local `null` unsets an
inherited key** — `{ "maxAgentsInFlight": null }` in the per-machine file drops back to
whatever the *caller's* documented default is, rather than to the tracked number. Without
this rule the readers would hand `null` on as a value: a `"models": {"deep": null}` once
made `resolve-model.sh` print the literal alias `null` and exit 0.

**This is the one place the overridable set is listed. Don't scatter it.**

| Key | Overridable? | Absent ⇒ |
|---|---|---|
| `ownerGithubUser` | **yes** — who this clone is | no configured human: unowned tasks clear, owned ones refuse |
| `authorEmail` | **yes** — this machine's commit address | `people[ownerGithubUser]`, else the tracked `authorEmail`, else `git config user.email` |
| `reposRoot` | **yes** — an absolute path on this machine | the readers report it as unset and skip; nothing is guessed |
| `worktreeRoot` | **yes** — an absolute path on this machine | `<reposRoot>/_wt`, which is also still swept as the legacy root |
| `boardInstances` | **yes** — a list of paths to sibling instances | just this instance |
| `board` | **no** — one instance, one answer, and `/ai-bridge:init` reads it from the tracked file at stamp time | on: `SNAPSHOT.json` is seeded, each tick renders `.board-live/board.html`, and a tick that changed something commits the tracked `/board.html` |
| `boardArtifactUrl` | **local ONLY** — the page **this clone** published with `/ai-bridge:board publish`. Never in the tracked file, and never seeded: publishing is account-scoped, so a shared value is one clone's URL that the other can never write | nothing was published from this machine; the banner prints the `file://` path alone and the tick says nothing about a published page |
| `models` | **yes**, and **seeded** — which model each tier costs **this human**. `/ai-bridge:init` writes this key into the local file on any stamp that finds it missing, so local is normally the layer in force and the banner reads `local` | the tracked map, which stays as the fallback; absent from **both**, `resolve-model.sh` prints nothing on stdout, **says so on stderr**, and exits 1 |
| `roleTiers` | **yes**, and **seeded** on the same terms — the same bill, per agent. **A partial override replaces only the entries it names**, so moving one agent to a cheaper tier leaves every other agent's tier standing, and the installer never tops a partial map up | as `models` above |
| `maxAgentsInFlight` | **yes** — how many agents **this machine** can carry (below) | the tracked value; absent from both, `resolve-max-agents.sh` prints nothing and exits 1, and the caller applies the fallback its own document states |
| `allowSubstituteBackend` | **local ONLY** — whether this machine may launch a session on a substituted LLM backend (the `ai-bridge-llm` companion). Never in the tracked file: which backend an installation runs is a per-machine data-governance call, and a tracked `true` is one clone's decision every other clone reads | not opted in — the launcher refuses and prints its governance warning |
| `defaultOwner` | **no, by design** | step 4 above: unowned, so every clone treats it as its own |
| `people` | **no** — a shared directory of who is who | no lookup; the `authorEmail` chain answers |
| `commitAttribution` | **yes** — the tracked file is where an organisation states its policy; the local file is how one machine departs from it | `claude`: a target-repo commit keeps the `Co-Authored-By: Claude` trailer, because Claude co-authored it. `none` drops the trailer and the session URL |
| `externalReviewer` | **no, by design** — it names **where this code may be sent**. That is policy, not preference: one clone silently routing diffs to a different reviewer is precisely the disagreement that breaks it, and it breaks in the direction nobody notices | the CodeRabbit CLI |
| everything else | no — shared facts (`org`, `maxPrLoc`, `maxPrFiles`, `defaultRepo`, `codegraphSkip`, …) | as documented per key |

**`models`, `roleTiers` and `maxAgentsInFlight` moved into this table on 2026-08-29.** They
are **spend and capacity**, not shared facts: which model a human pays for, and how many
agents one machine can carry. Two clones disagreeing about either breaks nothing, because
each dispatch runs on its own machine against its own worktree — which is this section's
own test for what belongs in the local file. Tracked, they were worse than merely
imprecise: one number was forced on every clone. Measured 2026-08-29, `maxAgentsInFlight`
read **4 / 6 / 10 across three instances on one 11-core machine** — up to 20 concurrent
agents against a measured ceiling near 4.

All three are read by a script rather than by whoever remembered to look:
`scripts/resolve-model.sh <agent>` for the first two, `scripts/resolve-max-agents.sh` for
the cap. Neither script invents a value it cannot find; both print nothing on stdout and
exit 1 instead, and the caller applies its own documented fallback.

**PR size is TWO numbers, because the reviewer counts the one nobody was counting.**
`maxPrLoc` (**500** when the key is absent) bounds the diff in **lines**; `maxPrFiles`
(**100** when the key is absent) bounds it in **files**. Both are shared facts in the
tracked `instance.config.json`, and **both only ever propose** — a role agent past either
one says so in the PR body as one `⚠️` line and opens the PR anyway, and no reviewer ever
withholds clearance over either (`CONVENTIONS.md` → the PR-size heuristic).

**Why the file count earns its own key rather than being inferred from the line count.**
The two disagree in both directions and each direction has cost a real PR: a `git mv`
sweep is one file per rename and almost no lines, while one generated lockfile is
thousands of lines in a single file. And the file count is the one an external reviewer
enforces: CodeRabbit's free plan **refuses a pull request over 100 files outright**,
before any quota question, offering only "split the PR or upgrade" — measured 2026-09-05
on a 147-file PR that got no review at all while its line count was unremarkable. A PR
past `maxPrFiles` therefore does not get a slow review; it gets **none**, and the merge
gate correctly refuses it forever.

**The `project-manager` reads `maxPrFiles` one step earlier than a role agent does.** When
a task's expected diff is already known to exceed it — a rename sweep, a codemod, a
generated-file refresh — the PM **proposes splitting the task** in its refinement, before
dispatch, because that is the only point at which the split is cheap. It proposes; the
human decides, exactly as with every other refinement, and a task the human leaves whole
is dispatched whole.

**`models` and `roleTiers` are SEEDED into the local file, and the tracked pair is the
fallback — both halves are load-bearing.** `/ai-bridge:init` writes them into
`instance.config.local.json` on any stamp that finds the key missing, seeded from the
tracked values when present and from the documented defaults (`light→haiku`,
`standard→sonnet`, `deep→opus`, `apex→fable`) when not. That is what makes spend a
per-machine decision in practice rather than only in principle: a tracked map is one
human's choice charged to everyone, and until the local file exists the banner honestly
reports `tracked`.

The tracked keys were **not** removed in the same change, and that is the design.
`resolve-model.sh` with neither layer resolves to nothing, and a caller that ignores its
exit code inherits the session model — for every role at once, with nothing anywhere
saying so. Removing the tracked pair first would open exactly that window on any instance
the seeding step had not yet reached, and **a merge is not a stamp**: an instance is
re-stamped only when somebody runs `/ai-bridge:init`. With both layers present there is no
ordering in which the pair resolves to nothing.

**`maxAgentsInFlight` is deliberately NOT seeded.** It is overridable and per-machine
exactly as the two above are, so the asymmetry is real and is not an oversight: seeding it
was not asked for, and whether it should follow is the owner's call rather than a
consistency argument's. Don't "fix" it in passing — decide it, then change this line.

**Seeding is per KEY and never reconciles.** A key already in the local file is left
exactly as it is — including one explicitly `null` (the documented unset above), and
including a **partial** map, which is merged entry by entry over the tracked one. Topping
a partial map up to the full set would be reconciling a human's edit, which this installer
does not do anywhere.

**And absence is never silent.** `resolve-model.sh` still prints nothing on stdout and
still exits 1 when a role has no tier or a tier has no alias — every caller captures
stdout, and a word printed there becomes a model alias. But it now writes a line to
**stderr** naming the agent, which lookup failed, both files, and the consequence: a
caller that ignores the exit code dispatches on the session model. A caller must surface
that line rather than dispatch on a guess. `/ai-bridge:init` asks the same resolver after
seeding and warns by name about any role that still resolves to nothing.

### `maxAgentsInFlight` bounds an instance, not a machine — a known hole

The seeded default is **4**, and that number is measured, not chosen: on 2026-08-27, nine
concurrent agents drove an 11-core Mac to **load average 36.5**, three times
oversubscribed, and a typecheck took 20-30x its idle time. The mechanism is that `vitest`
forks a worker **per core**, so three agents running unit tests is ~33 processes on 11
cores however the suites are arranged.

**But the cap is per instance and the CPU is per machine.** Three instances on one laptop,
each honouring a cap of 4, can still put **12 agents on 11 cores** and reproduce that
incident exactly. Nothing here prevents it.

This is an **accepted trade, not an oversight**: a machine-scoped cap needs a lock outside
any single bundle, and the owner chose the simpler per-instance number. It is written down
so the next person meeting load average 36 finds a known limitation rather than a mystery.
If you run several instances on one machine, divide the machine's budget between them by
hand — **in each instance's `instance.config.local.json`**, which is what makes that
division per-machine and stops it being pushed to everyone else's clone.

The rule behind the split: **the tracked file holds facts both clones share; the local
file holds facts about this machine and this human.** A key that must be *the same* on
both clones to be correct — `defaultOwner`, `people`, `externalReviewer` — is never
overridable, because an override is exactly the disagreement that breaks it. Spend and
capacity fail that test in the other direction: `models`, `roleTiers` and
`maxAgentsInFlight` are correct *while the clones differ*, so they are overridable.

**`boardArtifactUrl` was TRACKED from 2026-08-26 until 2026-08-29, and was deleted with
the publish path it served. It is back, and the only thing that changed is which file it
lives in.** The constraint that killed it is unchanged and is not a bug anyone can fix:
artifact publishing is **account-scoped** — the update path requires an artifact the
account owns and no share level grants it — so exactly one account can ever publish to a
given URL. **Tracked**, that produced one working board and one **silently dead publish
step** on whichever clone did not own the artifact, and when the owning account was
switched the recorded page disappeared from under its own owner. **Per machine**, the key
says only what *this* clone published, which is the one thing it can be right about: two
humans on one bundle keep two URLs and each publishes their own, exactly as the
account-scoping requires. `session-banner.sh` reads it through `resolve-config.sh` and then
checks the **source**: a value resolving from `tracked` is dropped rather than printed, so
the old shape cannot come back by someone pasting a URL into the wrong file.

**`board` stays not overridable, and for its own reason** — `/ai-bridge:init` reads that key
from the tracked file at stamp time, and a per-machine override would give one switch two
answers. It gates `boardArtifactUrl` too: `board: false` silences the published row like
every other one.

**Nothing about a shared bundle depends on the published page**, then or now. The
cross-owner view is the *other owners* section that `scripts/build-board.sh` reads from the
tracked task documents at your current git `HEAD`, which is the one thing both clones
genuinely share.

Two constraints survive the override and must be checked against the *effective*
values, not the tracked ones:

* **`worktreeRoot` must never sit inside `reposRoot`** — `reposRoot` is typically a
  synced folder, and sync rewrites files inside a worktree mid-run. If the local file
  sets one, check it against whichever value is actually in force for the other.
* **`reposRoot` must not be the instance directory itself** (`link-repos.sh` refuses
  that, and it reads the override too).

`people` is a map of **GitHub login → commit email**, used by `commit-as.sh` to author
a clone's commits as the human who runs it: `{ "<login>": "<email>", … }`. It exists so
the address is recorded **once**, by whoever knows it, and a second human's local file
is a single line — `{ "ownerGithubUser": "<login>" }`.

**The address is per-instance, not per-person — and that is why the map lives here.**
The same login maps to a *different* address in each group's bundle, because the address
says which entity the work belongs to: one person working three clients commits as a
different address in each of their three instances. That is a business fact about the
instance, not a naming convention, so:

* **never derive it from the login.** No `<login>@<domain>` rule, and specifically not
  `<login>@users.noreply.github.com` — that one was rejected outright, because GitHub
  requires the ID-prefixed `<id>+<login>@…` form for accounts created after 2017-07-18,
  so a derived plain address silently fails to link to the account. Only the instance
  can state its own mapping;
* **never move the address into the local file.** `instance.config.local.json` says
  *which login this clone is*; the address for that login *in this instance* comes from
  the tracked map. Split the other way, two clones of one instance could disagree about
  which entity the work belongs to and git history would silently record both.

Real addresses in a private instance repo are fine — that is where they belong.

# Project & objective completion

A **project** has no lifecycle step of its own until its tasks finish. When
**every** task in a project is terminal (`done` or `cancelled`), the project
becomes a **close candidate**: the PM surfaces it under 🔴 *Awaiting you* and
**proposes** closing it — it **never** closes a project autonomously. Closing
removes work from the queue and deletes the folder, so it is a human call, like
the two task gates.

**Every task that is not terminal at closeout becomes `cancelled`** (a `--force`
closeout is how one gets there), with a one-line reason in the task body. `cancelled`
is the existing terminal status — "abandoned, superseded, or decided-against" — and it
is deliberately reused rather than joined by a "closed-unfinished" sibling: a status
enum that grows a value per closing mode teaches nothing the reason line does not
already say.

On the human's OK (in-session, or via `/close-project <slug>`), **closeout** runs
in this order:

1. **Consolidate knowledge.** A final `cataloguer` pass ensures every durable,
   reusable learning from the project is captured in `knowledge/` (Finding /
   Service / Runbook) and cross-linked. For a **research** project, decide which
   `deliverables` graduate into `knowledge/`. The KB is the distilled record that
   outlives the project.
2. **Record the closeout.** Prepend a dated **Project closed** entry to the root
   `log.md` naming the project, its merged PR(s) as `[<repo>#<n>](url)`, the
   `Finding`(s) it produced (KB links), and — after step 4 — the removing commit
   SHA. This one line is the durable, greppable pointer back into
   `git log -- projects/<slug>/` if the full record is ever needed again.
3. **Roll up.** Set `project.md` `status: done`; drop the project from the active
   `## Projects` list in `index.md` (derived and gitignored — rewritten, never
   committed); update its objective's project list **if it has an `objective:`**
   (a project measured by its own `success_criteria` has nothing to roll up). When
   **all** projects serving an objective are `done`/`cancelled`, likewise
   **propose** the objective `status: achieved` (human-confirmed).
4. **Remove the folder — or keep it, if `retain: true`.** Both outcomes are one
   command, `scripts/close-project-folder.sh <slug> --apply`, so the deletion has a
   fixed, tested scope instead of being improvised from prose.

   **Without `retain:`** — `git rm -r projects/<slug>/`, and the same command appends
   the project's entry to **`projects/CLOSED.md`**, in that same commit. **Git history +
   the KB are the record — there is still no `archive/`; what replaces it is an INDEX,
   not a copy.** The full task→PR→Finding trail stays recoverable via `git`. Reversible
   with `git revert`, but treated as final.

   **`projects/CLOSED.md` is where a closed project's deliverables are found**, and it
   is TRACKED (unlike `index.md` and `SNAPSHOT.json`, which are derived and gitignored):

   * One `## <slug>` stanza per closed project **that had deliverables** — its close
     date, the `pinned:` sha, a one-line outcome, and one `- deliverable:` row per
     declared artifact that existed on disk. A project that shipped nothing adds no
     stanza: this is an index of things to come back to, and `log.md` already records
     every close.
   * **Every link is a GitHub permalink at a commit sha, never a branch path.** The sha
     is the parent of the closing commit — the last commit that still carried the files
     — because the closing commit is the one that removed them, so a `blob/main` link
     404s at exactly the moment it is needed.
   * Each row carries a **one-paste restore command** beside its link, because GitHub
     serves an HTML deliverable as source and `raw.githubusercontent.com` 404s
     unauthenticated on a private repo.
   * **It is written by the closeout, never by hand** — a hand-maintained list rots, and
     that decay is the failure it exists to end. `write-snapshot.sh` parses it into the
     snapshot's top-level `closed` array and the board renders it as a collapsed
     **Closed · N** section, so a closed project stays findable with no folder on disk.

   **With `retain: true`** the folder stays, and is *frozen* first:

   * **`deliverable_paths:` is stamped into `project.md`** — every task's `artifacts:`
     resolved once, each file verified to exist, written back as bundle-relative
     paths. A declared artifact that does not exist is a warning and is left out, the
     same call `validate-bundle.sh` makes. This is what lets the board list a retained
     project's deliverables **without** walking `tasks/`.
   * **Working files are pruned**, by four explicit paths and never by an extension
     sweep: `tmp/` and `temp/` directories (case-insensitive, any depth), `.DS_Store`,
     and **non-markdown** files under `sources/`. `sources/**/*.md` are KEPT, because
     `index.md` cites them by number and those citations must keep resolving.
     `tasks/`, `deliverables/`, `log.md`, `index.md` and `project.md` are kept in
     full — `deliverables/` legitimately holds `.pdf`/`.html`/`.png`, so the walk skips
     that subtree entirely.
   * **The prune is reported**: the command prints what it removed, and the
     **`log.md` closeout entry names the pruned directories**, so a later reader knows
     the folder is deliberately partial rather than damaged. `tmp/`/`temp/` are
     reported as a path and an entry count, never by filename — on the project this
     rule came from they held employee records, and a filename is content.
   * **`index.md` is refreshed as the retained project's front door and COMMITTED.**
     It is the one exception to "the index files are derived, rewritten, never
     staged": the tick now skips done projects, so nothing will ever regenerate it,
     and an uncommitted front door exists on exactly one machine.

   **Why keeping it is affordable.** The reason for removal was never disk — it was
   that a done folder cost context on every PM tick. It no longer does: both readers
   of the tree, `write-snapshot.sh` and the PM's own project loop, stop at a `status:
   done` project's **frontmatter**, before `phases/` or `tasks/` is opened. A retained
   project costs one frontmatter parse.

# Browser access (`browser: claude-for-chrome`)

<!-- tool-mention: mcp__claude-in-chrome__*(1) — five agents are told to read this file and only `qa-reviewer` holds any browser tool, so for most readers the name below states a capability they do not have. It is named once, to explain that the tools are injected rather than configured and that their absence is normal; rule 1 is the route for a reader without them. Enforced by tests/agent-tool-allowlist.test.sh. -->

A project may let its agents **drive a real browser** — read a logged-in page, click
through a flow, screenshot — via **Claude for Chrome**. Opt in per project with
`browser: claude-for-chrome` on `project.md` (default `off`).

**How it's wired: it isn't.** The Chrome extension **injects** the
`mcp__claude-in-chrome__*` tools into a live paired session. There is no `mcpServers`
stanza, no `.mcp.json`, nothing in `settings.json` — `claude mcp list` doesn't even show
it. Opting in at the machine level = **install the extension and grant it per-site
permissions**; opting in per project = this field. Nothing to configure in this bundle.

**Rules for agents:**

1. **Availability is not guaranteed — degrade, never fail.** The tools exist only when a
   browser is paired to the session. A cron/headless tick has none. If they're absent,
   fall back to a non-browser route (CLI, API, `gh`, asking the human) and say so; never
   report a task blocked *solely* because the browser wasn't there.
2. **Background role agents can use it — but each gets its own tab group.** The
   connection is inherited by background subagents; the human's open tabs are **not**.
   So always **navigate explicitly** from a URL rather than assuming a page is already
   open, and never assume you can see (or should touch) what the human is looking at.
3. **Browser-first, escalate if stuck.** On a `browser: claude-for-chrome` project, if a
   step needs a browser, try it yourself before handing it back — that's the point of the
   opt-in. Ask the human only when the browser genuinely can't get there (an MFA prompt,
   a permission the extension lacks, a destructive confirmation).
4. **Writes follow the project's `autonomy`, like every other gate.** **Ask first before
   any browser write** — that is the default and the only behaviour unless the project's
   `autonomy` delegates writes (see `AUTONOMY.md`; absent that file, always ask).
   Read-only navigation and screenshots never need permission.
   Two limits are *not* autonomy-specific and hold in **every** mode: an agent
   **doesn't redefine scope**, so a write nobody asked for is never licensed (the same
   rule that stops it inventing code changes); and irreversible actions well outside the
   task — a payment, deleting an account, mailing a customer — are worth one confirmation
   on cost grounds, not permission grounds. When in genuine doubt about blast radius, say
   what you're about to do and continue unless told otherwise.
5. **The usual data rules still apply.** A logged-in page is the most likely place to
   meet **customer PII** — never copy it into a task doc, `# Result`, PR text, `log.md`,
   any log or console output, or the KB. Describe the shape of what you saw, not the
   records.

**Worktrees.** Build tasks run in git worktrees under the instance's `worktreeRoot`
(`instance.config.json`; absent that key, `<reposRoot>/_wt`, which is also still
swept as the legacy root). It must be outside any synced folder — sync rewrites
files inside a worktree mid-run.

**Nothing reclaims them automatically.** `scripts/prune-worktrees.sh` classifies and
reports; it never removes. It scans `worktreeRoot` and the legacy `<reposRoot>/_wt`,
labels each worktree `REMOVABLE` (real branch, merged/closed PR, fully clean tree),
`RECLAIMABLE` (finished, but needs a human eye — either a detached HEAD, whose
commits are on no branch ref so removal destroys them, or a branch left with
untracked scaffolding), `KEEP`, `STALE` or `UNREGISTERED`, and prints the exact
`git worktree remove` commands for a human to run. A branch with no commits of its
own is always `KEEP`, because "already merged" and "dispatched but hasn't committed
yet" are the same git state.

The removal path was deleted in ai-bridge v2: it had destroyed three running agents'
worktrees, and no first-party mechanism covers this root (native isolation and its
retention sweep only reach worktrees the harness created, of the *session* repo). So
the worktree root does grow, and draining it is a periodic human job — surface the
report, don't automate the delete.
