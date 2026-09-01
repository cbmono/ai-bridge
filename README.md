# ai-bridge

**A control panel for running a small team of AI agents on your repositories.**

You describe the work. A project-manager agent breaks it into tasks. You approve. Engineer
agents build it **in the background**, open pull requests, and get reviewed. You merge.

You act like an engineering manager, not a pair programmer.

This repo is the **template**. You stamp out one **instance** per group of repos (work, a
side project, a client). Each instance is its own small git repo that sits beside those
repos and holds only the state of the work — never application code.

| | |
|---|---|
| **Needs** | [Claude Code](https://claude.com/claude-code), `git`, `gh`, bash. `python3` only for the optional board (all three renderers). |
| **Time to first loop** | about 10 minutes |
| **Storage format** | plain markdown ([OKF Knowledge Bundle](https://github.com/GoogleCloudPlatform/knowledge-catalog/blob/main/okf/SPEC.md)) — the commands write the files for you |
| **License** | [MIT](LICENSE) |
| **Version** | [`VERSION`](VERSION) — one line, no extension, the only copy. A core change proposes the bump in its PR; the owner approves it by merging ([versioning](#versioning-and-drift)) |

---

## Contents

| Doc | Read it when |
|---|---|
| **This page** | setting up, or looking up a command or a config key |
| [docs/schema.md](docs/schema.md) | you need to know what a document type holds |
| [docs/autonomy.md](docs/autonomy.md) | you want the loop to promote or merge without you |
| [docs/operations.md](docs/operations.md) | upgrading an instance, the board's three renderers, worktrees, editor setup |
| [docs/sharing.md](docs/sharing.md) | two humans will share one instance |
| [docs/conventions.md](docs/conventions.md) | **you are changing this repo** — every design invariant and why it exists |
| [The config layer](#the-config-layer) | you want this repo's agents, commands and hooks in `~/.claude` too |

Normative contracts live in the machinery itself: [`symlink/SCHEMA.md`](symlink/SCHEMA.md)
(document types, the verification predicate) and
[`symlink/AUTONOMY.md`](symlink/AUTONOMY.md) (the delegated-autonomy modes).

---

## Install

### 1. Clone this repo

```bash
git clone git@github.com:cbmono/ai-bridge.git ~/workspace/ai-bridge
```

Keep it somewhere permanent. Instances symlink into it by absolute path.

> **Do not run the installer from a git worktree.** Every symlink it creates would point
> into the worktree, and removing that worktree breaks all of them — silently, later. The
> installer refuses and exits 2.

### 2. Make the instance directory

Name it **`_ai-bridge-<group>`**, inside the group folder, beside that group's repos.

```bash
mkdir -p ~/workspace/<group>/_ai-bridge-<group>
```

- The leading underscore pins it to the top of the group folder and keeps it visible (unlike a dotfile).
- The `-<group>` suffix distinguishes it from this template dir and from other groups' instances.
- The group folder itself is **not** a repo — just a plain directory holding this instance plus the group's repos, side by side, each its own repo.

### 3. Stamp it

```bash
~/workspace/ai-bridge/install.sh ~/workspace/<group>/_ai-bridge-<group>
```

The installer does three things:

| # | Action | Detail |
|---|---|---|
| 1 | **Symlinks** the machinery from `symlink/` | file granularity, absolute targets; gitignored in the instance via a managed block |
| 2 | **Copies** `seed/` content — only if absent | never clobbers instance data |
| 3 | **Links** the group's repos into `<instance>/repos/` | via `scripts/link-repos.sh`; skipped while `reposRoot` is the seeded placeholder |

It is idempotent. It backs up any conflicting real file as `<name>.bak.<epoch>`.
`install.sh --uninstall <dir>` removes only the symlinks it created.

#### It also asks who the team is — once

On a **first** stamp, at a terminal, it offers to collect the roster: one line per person,
`<github-login> <commit-email>`, **yourself first**. That fills in the tracked `people`
map and `defaultOwner`, plus this clone's gitignored `instance.config.local.json` — the
three values a shared bundle needs, which used to be hand-edited afterwards. See
[docs/sharing.md](docs/sharing.md#the-installer-asks-once).

- **Nothing is written until you confirm it.** ctrl-C, ctrl-D and an empty first line all
  write nothing at all, and say so — a half-answered roster is never left behind.
- **It never asks on a refresh, and never when stdin is not a terminal** (a script,
  `upgrade.sh`, a background agent). It prints what to edit by hand instead.
- **It never overwrites a value that is already there.**
- Skipping costs nothing: fill the same three values in by hand whenever you like.

### 4. Configure it

```bash
cd ~/workspace/<group>/_ai-bridge-<group>
$EDITOR instance.config.json      # org, reposRoot, worktreeRoot, authorEmail
```

### 5. Give it a remote

```bash
git init && git add -A && git commit -m "chore: bootstrap control panel"
gh repo create <user>/_ai-bridge-<group> --private --source=. --push
```

Keep the leading underscore in the repo name, so a fresh `git clone` lands a
`_ai-bridge-<group>/` directory that matches the convention.

### 6. Run your first loop

```bash
cd ~/workspace/<group>/_ai-bridge-<group>   # this matters — see below
claude
```

Then, inside the session:

```
/new-project add rate limiting to the public API
```

Answer its questions. Review the draft tasks. Promote the ones you want (`draft → ready`).
Then:

```
/pm-loop 10m
```

**Always launch Claude from inside the instance directory.** The role agents and commands
load from the instance's `.claude/`, and that is chosen by the working directory — not by
what your editor has open.

---

## The core loop

```
/new-project  →  you promote draft → ready  →  /pm-loop  →  you merge the PR
```

`/pm-loop` is serial and completion-gated — one tick at a time. Run **one `/pm-loop` per
instance**. The launcher takes a per-clone lock (`.tick-lock`) immediately before each
dispatch, and the tick runs the same check on entry — a resumed tick never passes through
the launcher, so one that finds no lock is refused rather than allowed to run. That
guarantee survives a compaction instead of resting on the session remembering it
dispatched — [→](docs/operations.md#one-tick-at-a-time-the-dispatch-lock).

Two gates stay yours by default:

1. **Promote** a task from `draft` to `ready`.
2. **Merge** the PR (build projects) or **approve** the deliverable (research projects).

The idea is to **steer, not watch**. Role agents run in the background and bubble up
results and questions, not every step.

Both gates can be delegated — see [docs/autonomy.md](docs/autonomy.md). That capability is
**off unless installed**: it lives entirely in [`symlink/AUTONOMY.md`](symlink/AUTONOMY.md),
and deleting that one file makes every project `gated` again with no other edits.

### Who runs what, end to end

One `kind: build` project, from `/new-project` to merge. Every step links to the document
that **owns** its rule; nothing here restates one. Tiers are the **seed defaults** — each
instance sets its own in `roleTiers`/`models`
([model routing](docs/operations.md#model-routing)).

| # | Step | Who runs it |
|---|---|---|
| 1 | **Scaffold** — slug, objective, phases, seed `draft` tasks | you and the main session, interactively [→](symlink/.claude/commands/new-project.md) |
| 2 | **Commit** the scaffold and its registration as one change | main session, via `commit-as.sh` |
| 3 | **Scaffold review**, three stages: `validate-bundle.sh`, then an external reviewer, then the `qa-reviewer` fallback. Stage 1 gates the rest; stages 2 and 3 are advisory, and stage 2 is *dispatched* rather than waited on | main session; `qa-reviewer` (`deep`) on the fallback [→ step 8](symlink/.claude/commands/new-project.md) |
| 4 | **Refine** each `draft` — fill `acceptance_criteria`, raise `open_questions` | `project-manager` (`deep`) [→](symlink/.claude/agents/project-manager.md) |
| 5 | **Approach critique** — **mandatory on its trigger** (a complex or heavily-inferred `kind: build` draft), advisory in what it may decide; its concerns land in `advisor_notes` and gate nothing | `plan-architect` (`apex`), dispatched by the PM [→](symlink/.claude/agents/project-manager.md) |

> ### HUMAN GATE 1 — you promote the task `draft → ready`
>
> **Nothing is dispatched until you do.** The PM refines and critiques a draft but never
> sets `ready` ([two human authorities](symlink/SCHEMA.md)).

| # | Step | Who runs it |
|---|---|---|
| 6 | **Dispatch** the `ready` task — its own worktree and branch, both recorded on the task before the agent spawns | `project-manager` → the assignee [→](symlink/.claude/agents/project-manager.md) |
| 7 | **Build it**, then **self-review your own diff** — a pre-filter, never the gate | `software-engineer` / `devops-engineer` (`deep`) [→](symlink/CONVENTIONS.md) |
| 8 | **Open the PR** carrying the task's `acceptance_criteria` as a ✓/✗ table — the artifact `pr-body-clearance.sh` reads. The agent never merges | the same agent |
| 9 | **Independent review** at the PR's current head: the external reviewer where one is configured, else the `qa-reviewer` fallback. The PM reads that verdict with `review-clearance.sh`, and `review-rounds.sh` stops it at two rounds | external reviewer, else `qa-reviewer` (`deep`) [→](symlink/SCHEMA.md) |

> ### HUMAN GATE 2 — you merge the PR
>
> **One `✗` in that criteria table blocks it, however green CI is**
> ([SCHEMA.md](symlink/SCHEMA.md)).

The next tick reflects the merge — `status: done`, and the task's worktree is reclaimed.

## Commands

Run these inside an instance.

| Command | What it does |
|---|---|
| `/new-project <description>` | scaffolds a project: phases, draft tasks, acceptance criteria. Asks for the capability flags you didn't pass |
| `/pm-loop [interval]` | the serial background loop: dispatch, track, report. `/pm-loop 10m` ticks every ten minutes |
| `/answer` | answer the PM's open questions from inside the session |
| `/pr-review-request <pr>` | ask for an independent review of a PR |
| `/audit` | the slow counter-metric — is the throughput moving the real goals? Read-only, never acts |
| `/fanout <task>` | parallel work across several repos |
| `/close-project <slug>` | close a project and fold its conclusions into `knowledge/`, then remove its folder — or freeze and keep it, on `retain: true`. [→](docs/schema.md#closing-a-project) |
| `/ai-bridge [check\|fix]` | reprint the SessionStart banner; `check` reports state that could be wrong, `fix` repairs only the idempotent tier. [→](docs/conventions.md#21-ai-bridge-reports-facts-that-can-be-false-and-fix-is-tiered-in-code) |

Flags `/new-project` accepts: `kind=research`, `autonomy=<mode>`, `clis="…"`,
`browser=claude-for-chrome`, `/yolo`, `/cli …`, `/claudeforchrome`, `--no-commit`.

## The team

| Role | Does |
|---|---|
| `project-manager` | runs the loop: refines drafts, dispatches, tracks, reports |
| `software-engineer` | writes code in a target repo and opens the PR |
| `devops-engineer` | infrastructure, CI, deploys |
| `qa-reviewer` | the **independent** verification gate — fresh context, real signals |
| `cataloguer` | folds conclusions into `knowledge/` |
| `auditor` | read-only drift check for `/audit` |
| `failure-analyst` | diagnoses a failing check or a broken build |

Role dispatches are routed to a cost-appropriate model per tier
([docs/operations.md § model routing](docs/operations.md#model-routing)).

## Where the work lives

```
_ai-bridge-<group>/
├── objectives/        what you're trying to achieve
├── projects/<slug>/
│   ├── project.md     kind, status, autonomy, owner, target_repo
│   ├── phases/        ordered stages
│   ├── tasks/         the unit an agent is dispatched on
│   └── deliverables/  research output (no repo, no PR)
├── knowledge/         services, findings, teams, runbooks, references
├── repos/             symlinks to the group's repos (gitignored)
├── AWAITING.md        what needs you (derived, gitignored)
├── SNAPSHOT.json      board input (derived, gitignored)
└── instance.config.json
```

Document types and their fields: [docs/schema.md](docs/schema.md).

## Two kinds of project

| | `build` (default) | `research` |
|---|---|---|
| Output | PRs to a `target_repo` | deliverables inside the bundle (`projects/<slug>/deliverables/`) |
| Who executes | dispatched role agents | **the human**, in-session — the PM tracks but never dispatches |
| `target_repo` | required | not asked |
| `clis` prompt | asked, pre-filled from detected CLIs/MCPs | **not asked** (recorded if you pass `clis=`) |
| `browser` | asked | asked — web research is its clearest case |
| Scaffold review | three-stage chain | skipped |
| Gate | you merge the PR | you approve the deliverable |

A research project is asked **less on purpose**. Each dropped question describes machinery
a research project never runs, so offering it would ask you to authorise tools nothing will
use. **Don't restore a question for symmetry** —
[docs/conventions.md invariant 5](docs/conventions.md#5-build-and-research-projects-are-deliberately-asymmetric).

## Answering the PM's questions

When a `draft` is blocked it lists numbered `open_questions` (`Q1:`, `Q2:`, …).

1. Open the task doc.
2. Append ` --- <answer>` to the question line:
   ```
   Q1: which region should we default to? --- eu-central-1
   ```
3. The next tick treats everything after the ` --- ` as your answer, folds it into the
   task, and clears the question.
4. The `draft` becomes promotable once the list empties.

Answering in chat during a session works too (`/answer`).

The cleared entry is **moved, not deleted** — it lands in `answered_questions` as one flat
line, `<ISO 8601> · <the entry verbatim>`. It is a human audit record: nothing reads it and
no gate consults it. **No customer PII in an answer** — unlike the question you clear, this
list persists for the life of the repo.

## What needs you

`AWAITING.md` is the instance's **one** status artifact: a queue of just the items a human
decision unblocks.

| Marker | Means |
|---|---|
| ✅ | approve |
| ❓ | answer |
| 🔀 | merge |
| ⛔ | unblock |
| 🏁 | close |

Each item carries a real link. Every `/pm-loop` tick rewrites the file, and a `SessionStart`
hook injects its items at launch.

In-flight and upcoming work is deliberately **excluded** — it needs no decision, and a
queue you scroll past is a queue you stop reading. **There is no `/status` command and no
full board; don't reintroduce one.**

**On by default, off by deletion.**

| Action | Effect |
|---|---|
| `rm AWAITING.md` | the queue is off **for good** — an installer re-run will not resurrect it |
| `touch AWAITING.md` | back on |

Derived and gitignored; never hand-edit it. Reasoning:
[docs/conventions.md invariant 3](docs/conventions.md#3-awaitingmd-is-ai-bridges-only-status-artifact-and-it-is-opt-in-by-presence).

A cross-instance board is available too, on the same off-by-deletion rule
([docs/operations.md § the board](docs/operations.md#5-the-cross-instance-board-optional)).
**Read the field list before you carry one off the machine** — nothing publishes it, but a rendered file is still a file.

## Three ways to see the board

One snapshot, three renderers. `scripts/write-snapshot.sh` derives each instance's
`SNAPSHOT.json`; all three read it and none of them reads the bundle. Pick by what you
are doing, not by which is newest.

| You want | Run | Costs |
|---|---|---|
| a look right now, in the terminal you are in | `scripts/print-board.sh` | nothing |
| a page to open locally — the one each tick renders | `scripts/build-board.sh --standalone` | a re-run, or a looping instance |
| a page that updates itself as you work | `scripts/watch-board.sh` | **a process you keep running** |

```bash
scripts/print-board.sh                      # columns: instance, project, phases, tasks, awaiting
scripts/build-board.sh --standalone         # ./board.html, openable in a browser
scripts/build-board.sh                      # the same page as a BODY — no <html> wrapper, for embedding
scripts/watch-board.sh                      # ./.board-live/board.html, re-rendered on every change
```

**The page keeps itself current, locally.** Every `/pm-loop` tick re-renders it to
`.board-live/board.html` — gitignored, on this machine — and reports the path; a
`SessionStart` hook prints the same path when a session starts. `board: false` in
`instance.config.json` turns that off; absent or `true` leaves it on, which is the seeded
default ([docs/operations.md § rendering it from each
tick](docs/operations.md#rendering-it-from-each-tick)). Nothing is published anywhere. It
is only as fresh as the last tick — the page's masthead says when that was, and
`watch-board.sh` is the view that follows your work in between.

**The board is per installation, and it still shows everybody.** Your own projects come
from your `SNAPSHOT.json`; every other owner's is a collapsed, **named** section below
them, read from the tracked task documents at your current git `HEAD` (the one thing both
clones share) and cached against that SHA. That is why the local board loses nothing on a
shared bundle: the cross-owner half never came from a shared page, it came from git.

**The watcher's cost is the real one, so read it before you pick it.** It needs a
resident process, and ai-bridge deliberately has none — its agents are ephemeral
subagents inside one session, and nothing here runs between sessions. So the live page
is a terminal tab you keep open: it stops when you close it, sleep the machine, or lose
the session, and it gives you nothing to share and no phone access. If any of that
matters, the other two renderers cost nothing and you re-run them.

Three properties are shared by all three, because they belong to the snapshot rather
than to any renderer:

1. **No `SNAPSHOT.json`, no appearance.** That instance is absent — no placeholder, no
   warning — and no renderer ever creates the file.
2. **One broken instance cannot blank the board.** An unreadable snapshot becomes a
   visible note; a snapshot carrying wrong *types* degrades to zero for that field and
   everything else still renders.
3. **Every title is escaped for its output medium** — HTML for the page, control
   characters and ANSI sequences for the terminal. Task titles are human prose.

`print-board.sh` colours only a terminal and honours `NO_COLOR`, so a board piped into a
file, a ticket or a PR body carries no escape codes. On a narrow terminal it drops
columns that are zero in every row (and says which), clips **names** with `…`, and never
clips a **number** — a wrong count is worse than a missing column. Below the width where
a table still fits, it prints one short block per project instead of wrapping.

`watch-board.sh` uses `fswatch` when it is installed and a polling loop (default 2s) when
it is not; either way it is stopped with Ctrl-C and leaves nothing behind.

## Safety rails

The short version. Each line links to the full reasoning; **none of them is decoration.**

| Rail | Rule |
|---|---|
| **Independent review** | every PR is cleared by a reviewer with fresh context, never the implementing agent's self-report. [→](docs/autonomy.md#the-verification-gate) |
| **Merge gate** | `required-checks.sh` — **exit 0 is the only clearance.** Missing, pending, skipped and unreadable all refuse. [→](docs/autonomy.md#required-checks--exit-0-is-the-only-clearance) |
| **Review gate** | `review-clearance.sh` — a **green check from a reviewer that declined to review is not verification.** It reads the reviewer's artifacts, takes evidence and pinning from the reviews **API** (`state` + `commit_id`), leaves text matching only the job of spotting a refusal, and refuses on unknown state. `required-checks.sh` asks it on **every** PR, so a check's name never settles whether anybody looked. [→](docs/autonomy.md#the-verification-gate) |
| **Review rounds** | `review-rounds.sh` — **two rounds, then the human decides**, as a number a dispatcher reads rather than a rule it must remember. Exits non-zero at or past two, so a third verifier is refused. [→](docs/autonomy.md#two-rounds-then-the-human-decides) |
| **Dispatch check** | `check-dispatch.sh` — an agent's "done" is not evidence that a PR exists. Did `status:` move, does `pr:` name a URL, does that PR resolve. **Report-only.** [→](docs/autonomy.md#did-the-dispatch-produce-its-pr) |
| **Delegated autonomy** | one deletable file. `rm symlink/AUTONOMY.md` and every project is `gated`. [→](docs/conventions.md#4-a-capability-some-deployments-must-not-have-should-be-one-deletable-file) |
| **Dispatch lock** | `tick-lock.sh` — one PM tick at a time, taken by the launcher in the same operation that checks it, **and checked again by the tick itself**, since a resumed tick never passes through the launcher. A dispatched tick does not refuse its own lock: unclaimed means it is that dispatch. A tick that finds **no** lock was not dispatched at all — it is refused (exit 4), because **a tick is never resumed**. The claim on a lock records **whose** it is and from **which source**, and the trust is asymmetric — a runtime-derived id (`CLAUDE_CODE_SESSION_ID` names the *session*, not the tick) may refuse a claim but never clears one, so a merely-matching identity is exit 2 rather than a guess in either direction. Stale, or unattributable, means **ask the human**, never silently delete and never silently adopt. Per clone, not cross-machine. [→](docs/operations.md#one-tick-at-a-time-the-dispatch-lock) |
| **Worktrees** | `prune-worktrees.sh` **reports, never deletes.** Do not add a delete, not even behind a flag — it destroyed three running agents' worktrees once. [→](docs/conventions.md#7-prune-worktreessh-is-report-only-and-that-is-load-bearing) |
| **Bundle repair** | `migrate-bundle.sh` is report-only by default and fixes only what has one right answer. **A false success is worse than the error it claims to fix.** [→](docs/conventions.md#9-migrate-bundlesh-fixes-only-what-has-one-right-answer-and-is-report-only-by-default) |
| **Retiring content** | machinery symlinks are swept; **seed content is only ever reported**, never deleted. [→](docs/operations.md#2-retiring-content-swept-vs-reported) |
| **Board data** | the board's field list is a data-governance boundary — no question text, no document bodies, no author identity, no out-of-bundle paths. Nothing publishes it now, and a rendered file is still copyable. [→](docs/operations.md#before-it-leaves-the-machine-know-what-it-carries) |
| **Untrusted text** | `AWAITING.md` items and the per-turn state injection are fenced as data before they enter session context. Keep the boundary. [→](docs/conventions.md#12-three-ai-bridge-behaviours-that-all-exist-because-a-silent-wrong-answer-is-worse-than-a-loud-one) |
| **No customer PII** | not in a task title, not in an answer, not in a `Finding`. Titles reach the board; answers persist for the life of the repo. |
| **Drift check** | `/audit` is read-only and advisory. It catches an autonomous loop gaming itself; it is not a merge-blocking guarantee. [→](docs/autonomy.md#the-audit-counter-metric) |

## Configuration reference

`instance.config.json` (tracked) and `instance.config.local.json` (gitignored, per
machine). The **one** authoritative list of which keys are locally overridable is
[`SCHEMA.md` → "Per-machine config overrides"](symlink/SCHEMA.md).

| Key | Absent means | Overridable per machine |
|---|---|---|
| `org` | — | yes |
| `reposRoot` | required for dispatch | yes |
| `worktreeRoot` | **`<reposRoot>/_wt`** | yes |
| `authorEmail` | fall through to `git config user.email` | yes |
| `people` (login → commit email) | fall through to `authorEmail` | **no** — both clones must agree |
| `defaultOwner` | unowned work is dispatched by **every** clone | **no** |
| `ownerGithubUser` | this clone has no configured human | **local file only** |
| `maxAgentsInFlight` | **4** | yes |
| `maxPrLoc` | **500** | yes |
| `models` / `roleTiers` | everything inherits the session model | yes |
| `externalReviewer` | the CodeRabbit CLI | yes |
| `boardInstances` | the board is just this instance | yes |
| `board` | **on** — `SNAPSHOT.json` is seeded, and each tick renders `.board-live/board.html` | **no** — one instance, one answer |
| `codegraphSkip` | index every product repo | yes |

Environment knobs: `PUSH_STATE_MAX` (default **12**), `PRUNE_ACTIVE_MINUTES`,
`CODEGRAPH_SKIP`, `CONTROL_PLANE_AUTHOR_EMAIL`, `NO_COLOR` (honoured by
`print-board.sh`), `WATCH_BOARD_WATCHER` (`auto` when absent — `poll` or `fswatch`
override the watcher's probe).

## Scripts

Run from an instance root unless noted.

| Script | Does | Writes? |
|---|---|---|
| `validate-bundle.sh` | schema errors + dangling frontmatter references | no |
| `migrate-bundle.sh` | mechanical schema repairs | only with `--apply` |
| `prune-worktrees.sh` | classifies worktrees, prints the `remove` commands | **never** |
| `reclaim-worktree.sh` | removes **one** task's worktree, named by the task itself; refuses unless every guard passes | yes, that one path |
| `commit-as.sh` | commits as the right agent identity | yes |
| `required-checks.sh` | resolves a PR's required checks | no |
| `review-clearance.sh` | asserts an artifact **evidencing a completed review** exists on a PR (never a green check) | no |
| `review-rounds.sh` | counts a PR's completed verification **rounds**; exit non-zero at or past **two** | no |
| `pr-body-clearance.sh` | asserts a PR **body** carries the required shape — the TL;DR heading, a `Verified:` line that cites something, and a criteria table whose heading tally matches its rows. `--body-file` decides on a draft before you open it | no |
| `pr-comment-clearance.sh` | asserts a **reply to review findings** carries a verdict per finding, and that no element exceeds the measured ceiling. `--comment-file` decides before you post | no |
| `check-dispatch.sh` | `<task-doc>` — did the dispatch actually produce the PR it promised | **never** |
| `control.sh` | the live kill switch for one dispatched agent — `agents`, then `halt`, `gate` or `steer` it | yes, `.claude/control/` |
| `resolve-model.sh` | `<agent>` — prints the model alias it should run on, from `roleTiers`/`models` (local file first; `install.sh` seeds both there). No entry ⇒ nothing on stdout, exit 1, and **a line on stderr** saying the caller would otherwise inherit the session model | no |
| `tick-lock.sh` | `acquire [--as launcher\|tick]`/`release`/`status` — the per-clone PM dispatch lock; exit 0 is the only clearance to dispatch or to run a tick | `acquire`/`release` only, `.tick-lock` + `.tick-lock.claim` (gitignored) |
| `task-owner.sh` | resolves and compares a task's owner | no |
| `check-template-version.sh` | is the template this instance links older than the remote's default branch — prints a line **only when behind**, silence on every failure | not the instance — `--fetch` (opt-in) updates the template checkout's remote-tracking refs, nothing else |
| `close-project-folder.sh` | closeout's folder step — `git rm -r` the project, or freeze and keep it on `retain: true` | only with `--apply` |
| `write-snapshot.sh` | refreshes `SNAPSHOT.json` | only if it already exists |
| `build-board.sh` | renders the HTML board (anywhere; needs `python3`) | yes, the output file |
| `print-board.sh` | prints the board in the terminal | no |
| `watch-board.sh` | renders the board into `.board-live/` and re-renders on every change | yes, the page (gitignored) |
| `link-repos.sh` | refreshes `<instance>/repos/` | yes |
| `index-kb.sh` | builds local CodeGraph indexes for the group's repos | yes |

**Internal helpers** — the machinery calls these; you normally don't. They are listed so
the table above accounts for **every** script in `symlink/scripts/`, which
`tests/readme-scripts-table.test.sh` asserts.

| Script | Does | Writes? |
|---|---|---|
| `ai-bridge.sh` | backs `/ai-bridge`: reprints the SessionStart banner, `check` reports state that could be wrong, `fix` repairs only the idempotent tier | only under `fix` |
| `resolve-config.sh` | the one implementation of the two-file config precedence — `instance.config.local.json` first, `instance.config.json` second, dicts merged entry by entry | no |
| `resolve-max-agents.sh` | prints the concurrency cap **this machine** should honour, from the same two files | no |

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `/pm-loop` reports "Unknown command" | Claude was launched outside the instance dir, or new machinery isn't linked | `cd` into the instance and relaunch; then `install.sh <instance>` |
| A command or agent is missing after a pull | it is a **new** `symlink/` file, so no symlink exists yet | `install.sh <instance>` |
| A seed change from a pull never arrived | seed is copied only when absent, by design | `./upgrade.sh <instance>` and port what it reports |
| Commands and hooks vanished later, having worked | the installer was run from a git **worktree** | re-run `install.sh` from the main working tree |
| Installer exits 2, "refusing to install from a git worktree" | working as designed | `git -C <src> worktree list` — the first entry is the main tree |
| The startup nudge is empty | `AWAITING.md` was deleted, or the PM reshaped its layout | `touch AWAITING.md`; `session-banner.sh` greps the heading and bullets **literally** |
| An instance is missing from the board | it has no `SNAPSHOT.json`, or `boardInstances` doesn't name it | `touch SNAPSHOT.json` in it |
| `print-board.sh` printed nothing at all | it was not run from an instance root — that is silence by design, not an error | `cd` into the instance |
| The terminal board is missing a status column | every row was zero there, so it was dropped to fit the width; the footer names which | widen the terminal, or `--width 0` |
| The live page never updates | the watcher was stopped, or the change was outside `projects/` | restart `scripts/watch-board.sh`; it prints a line per render |
| A `yolo` project never merges anything | preflight failed: one `gh` identity, no external reviewer, or no required checks | the loop says which; fix that, or merge by hand |
| `required-checks.sh` exits 2 | the platform probe returned something it cannot classify | that is a refusal by design — read the message, don't loosen the script |
| A PR is all-green but not merge-eligible | the reviewer published "Review limit reached" behind a green check — `review-clearance.sh` exit 1 | wait for the reopen time it quotes, then ask for a **first** review; nothing re-reviews a skipped PR by itself |
| `required-checks.sh` exits 2, "review-clearance.sh not found" | the instance predates the review gate, so the new machinery isn't linked yet | `install.sh <instance>` — until then it refuses rather than clear a reviewer check it cannot interpret |
| `required-checks.sh` exits 1, "no independent review clears" | every required check is green but no review artifact clears the head — the gate no longer decides from a check's *name* whether a reviewer is involved | ask for a review at the current head; if the repo genuinely has no reviewer, that is the thing to fix, not the gate |
| `required-checks.sh` exits 2, "present but does not run" | the linked sibling is broken, or predates its `--self-test` contract; a mode bit is not proof a file executes | `install.sh <instance>` to relink — a sibling that fails every call looks exactly like "no reviewer is required", so this refuses |
| `review-rounds.sh` exits 1 | the PR has already had its two verification rounds — this is the cap doing its job, not a fault | stop reviewing: put both positions (reviewer / implementer / what the criterion asks) in front of the human and let them decide |
| An agent reported "done" but no PR ever appeared | it parked before opening one — `check-dispatch.sh` exit 1, the parked signature | one message to that agent: open the PR on what it already committed. Never re-dispatch the task |
| `review-clearance.sh` exits 4 on a PR that *was* reviewed | the reviewer read an earlier push and does not re-review (`auto_incremental_review: false`) — the review is **stale**, not absent | ask for a review at the current head; this is the common case here, not a bug |
| `review-clearance.sh` exits 4, "carries no evidence that a review was COMPLETED" | the only artifact is the reviewer's *"currently processing"* placeholder or similar — it names the head but nothing says anybody read it | wait for the real review, or ask for one; not-a-refusal is not a review, and clearing on it was a live false pass |
| CodeRabbit: "Unable to determine base branch" | a remote-less instance has no `origin/HEAD` to infer one from | `git config coderabbit.baseBranch <branch>` |
| Validator errors right after an upgrade | the machinery updated, the data didn't | `./upgrade.sh <instance>` runs validate → migrate in the right order |
| Two loops dispatched the same task | `defaultOwner` is not set on a shared bundle | [docs/sharing.md](docs/sharing.md) |
| Machinery symlinks all dangle on a second machine | intentional — machinery is machine-local | re-run `install.sh` there |

---

## Why template + instance

Only `CLAUDE.md` cascades through parent directories in Claude Code — subagents, commands,
skills and `settings.json` load only from `~/.claude` or a **project root** `.claude/`. So
a group-level overlay can't exist. Instead each group gets a project-root control panel
whose role agents load **only** when you launch Claude inside it, never polluting
`~/.claude`. The generic machinery stays DRY via symlinks; each instance keeps its own git
history, so work and personal stay separate.

## Versioning and drift

The version lives in one place — [`VERSION`](VERSION) at this root, one line, no extension.
`cat VERSION` reads it; nothing parses prose for it and there is no `package.json`, no tag
and no changelog. **There is no release process here and none is wanted.**

**A change to `core` proposes the bump; you approve it by merging.** `core` is a closed
list — `symlink/`, `seed/`, `config/`, `install.sh`, `upgrade.sh`, `RETIRED` — and it is
exactly what the two path-scoped rule files ([`.claude/rules/machinery.md`](.claude/rules/machinery.md),
[`.claude/rules/installer.md`](.claude/rules/installer.md)) already govern, so an agent
editing one of those paths meets the rule as it opens the file. A PR touching only `docs/`,
`tests/`, `.claude/`, `.github/` or the root `scripts/` proposes nothing. The bump arrives
as its own commit with a line in the PR body saying `old → new` and why, so rejecting it is
dropping one commit rather than unpicking a release.

Rough scale, enough to act on without a policy document: **patch** for a fix inside
behaviour that already shipped, **minor** for a new capability or a new file under
`symlink/`, **major** for anything an instance has to be repaired by hand to survive.

**Why the number matters more than a label.** An instance consumes this template through
per-file symlinks, so most merges reach it live — but a **new** file under `symlink/` does
not arrive until `install.sh` runs again, and `seed/` content is copied once, ever. That
gap has cost real time: two hooks merged and sat inert in every instance for a week.

So the session banner prints one line — and only one, and only sometimes. The two numbers
below are an example, not this repo's current pair; the only place the current one is
written down is [`VERSION`](VERSION):

```text
⬆️  TEMPLATE UPDATE (ai-bridge) — this instance links 0.9.1, origin/main has 0.11.0
```

`scripts/check-template-version.sh` decides it, and **silence is its normal answer**. Equal
or ahead prints nothing; so do offline, unauthenticated, no checkout, no remote-tracking
ref, a missing `VERSION` on either side, and a version it cannot parse — a false "you are
behind" would train you to ignore the true one. It makes **no network call** at session
start: it compares against the `origin/HEAD` ref already on disk, and only fetches when you
run it by hand with `--fetch`.

```bash
scripts/check-template-version.sh          # from an instance root; prints only if behind
scripts/check-template-version.sh --fetch  # refresh from the remote first
```

What it cannot see: a template checkout parked on an old commit whose `VERSION` happens to
match the remote's. The number moves when the bump convention says it moves, so this
catches drift **across a bump** and nothing finer.

## Changing this repo

Read [docs/conventions.md](docs/conventions.md) first. It records the design invariants and
what went wrong to produce each one — the reasoning is the asset, so relocate it rather
than shortening it.

- Machinery goes in `symlink/`. Keep it **generic**: no org, repo, path, team or channel literals — those belong in an instance's `instance.config.json` / `CLAUDE.md`.
- Starting content goes in `seed/`. Retiring a seed file needs an entry in [`RETIRED`](RETIRED) in the same commit.
- Tests live in `tests/`, never under `symlink/` — everything there ships into every instance.
- Run the suite before pushing: `for f in tests/*.test.sh; do bash "$f" || echo "FAILED: $f"; done`. CI runs the same full suite as the required check **`harness suite`**, which `main`'s branch protection requires and is strict about — so be up to date with `main`. [→](docs/conventions.md#repo-conventions-that-are-not-invariants)
- Adding to the harness itself? Measure what your diff adds under `symlink/**/*.sh`, and at or above ~150 lines ask in the PR body instead of assuming. [→](docs/conventions.md#repo-conventions-that-are-not-invariants)
- This repo is **public**. Placeholders must be verified unclaimed: `example-user-007` / `example-user-008` and `example.com`.

Agent-facing rules are in [`CLAUDE.md`](CLAUDE.md) and [`.claude/rules/`](.claude/rules).

## Relationship to `ai-setup`

ai-bridge used to live as an `ai-bridge/` subtree inside
[`ai-setup`](https://github.com/cbmono/ai-setup), the Claude Code defaults repo. **This
repo is now the canonical copy** — every instance's machinery is symlinked from *this*
checkout, and `install.sh` and `upgrade.sh` here are the ones to run.

`ai-setup` **no longer carries the subtree** — [`ai-setup#69`](https://github.com/cbmono/ai-setup/pull/69)
removed it, because a stale second copy that documentation still described as live was
inviting edits that would reach nobody. The pre-split version is therefore in git history,
not in any checkout: `git -C ai-setup show f8b09a4:ai-bridge/` is the last state it had
(`ai-setup` commit `f8b09a4`, "fix: refuse to install from a git worktree (#68)").

Nothing here needs it. That measurement is why it went: `diff -rq` found **nothing** that
existed only in the subtree, while this repo was ahead by 4 scripts, 1 hook, 9 tests and
22 changed files.

The two repos are independent by design: `ai-setup`'s user-wide installer is scoped to
`.claude` and never touched this template.

**`~/.claude` belongs to that repo**, not this one — see
[The config layer](#the-config-layer) below and
[docs/claude-config-ownership.md](docs/claude-config-ownership.md) for why. This repo
installs only the three agents its own role agents probe for. The
`@~/.claude/claude-defaults.md` import that every instance used to inherit is gone: that
section is inlined in `seed/CLAUDE.md`, so nothing can dangle.

---

## The config layer

**`${CLAUDE_CONFIG_DIR:-~/.claude}` is owned by
[`cbmono/ai-setup`](https://github.com/cbmono/ai-setup)** — the commands, hooks, output
style, skills and `settings.json` all install from there. Run *that* repo's `install.sh`
for those.

ai-bridge installs into that directory too, but only the paths **it probes for**: three
agents (`code-architect`, `deep-bug-scan`, `plan-architect`), so a fresh laptop works after
one clone and one install without needing a second repo.

It used to install 21 more, as a fork of ai-setup's tree — two installers claiming the same
paths, 14 of them diverged, ownership decided by whichever ran last. Two of the fixes that
existed only in the fork closed *secret-exposure* paths the public repo was still shipping.
[docs/claude-config-ownership.md](docs/claude-config-ownership.md) is the full record, and
`tests/config-ownership.test.sh` fails if the fork starts growing back.

```bash
~/workspace/ai-bridge/install.sh --config
```

It links **one file at a time** into `${CLAUDE_CONFIG_DIR:-~/.claude}`. A real file in the
way is backed up as `<name>.bak.<epoch>`. It **never touches `settings.json`** — that is
ai-setup's file, it holds your permissions, and an installer that replaced it could widen
what agents are allowed to do. Restart Claude Code afterwards so it re-scans agents and
commands.

### What it ships

| Path | Holds | Why it is here and not in ai-setup |
|---|---|---|
| **`config/required/`** | `code-architect`, `deep-bug-scan`, `plan-architect` | the only three agents this repo's own role agents look for. Without them `qa-reviewer` loses the escalation behind its cheap second opinion and the PM loses its plan critic — **silently**. ai-setup ships them too, so on a machine that installed both, either copy satisfies the probe; this copy is what makes ai-setup optional |

That is the whole list, and it is enforced rather than documented:
`tests/config-ownership.test.sh` derives the expected set from the `test -f` probes in
`symlink/` and fails on anything else under `config/`. Delete `config/required/` and
`--config` links nothing and exits 0; delete `config/` itself and an **instance** stamp is
completely unaffected (`--config` then exits 2 saying there is nothing to link).

### Five rules it follows

1. **Never a whole-directory symlink.** `agents/`, `commands/` and `skills/` are *drop-in* directories — any skill or plugin installer can write a new subdirectory into them at any moment. Linking one as a unit aims it at this checkout, so every drop-in lands inside a public git repo. That is how four uninvited skills once got committed to the parent repo, three of them dead links. Per-file links keep `~/.claude/<dir>` a real directory that owns its own contents.
2. **It never writes *through* a symlinked directory.** ai-setup links `~/.claude/agents` as a whole directory, so on a machine that ran its installer every entry here has a symlinked parent. When the file already resolves through it, the requirement — *this agent exists on this machine* — is met, so `--config` reports `provided by …` and writes nothing. When it does **not** resolve, nobody ships it and writing would land inside the other checkout: `--config` skips it, names it, prints the `mv` that fixes it, and exits non-zero. Either way the two installers compose in any order.
3. **`settings.json` is not ours at all.** This layer does not ship one, does not link one, and does not report on one. A link left over from when it did is retired by the sweep in rule 4.
4. **A retired file's link is swept — and it says where the file went.** Delete something from `config/` and the next `--config` removes the dangling link. Delete or hide *everything* and it does the opposite: an empty source list is refused rather than acted on, loudly and non-zero, because "nothing is shipped" and "I could not read the checkout" produce the same empty list and only the first licenses a delete. Removing the tier **directory** is the way to mean the first. A dangling command still registers with Claude Code; a dangling hook exits 127 every launch. The sweep is also what performs the **handover**: this layer used to ship ~21 more paths, so an existing machine's first run on the new layer retires them all at once, and it prints that they moved to [`cbmono/ai-setup`](https://github.com/cbmono/ai-setup) rather than leaving a user told only what vanished. Steady-state runs stay quiet.
5. **Nothing here is required.** An instance never needs the config layer, and the config layer never needs an instance. `install.sh <dir>` behaves exactly as it always did.

### Uninstall

```bash
~/workspace/ai-bridge/install.sh --config --uninstall
```

Removes only the symlinks it created — everywhere it created them, which includes a
`<root>.bak.<epoch>` directory another installer moved aside (ai-setup does that when it
takes `~/.claude/agents` over as a whole directory, and three links used to survive there,
still resolving into the checkout you had just detached from). Real files, `*.bak.*` backup
*files*, and your runtime state (`plugins/`, `projects/`, history) are left alone.

### Coming from the separate `ai-setup` repo

An instance stamped before this existed carries one line in its `CLAUDE.md`:
`@~/.claude/claude-defaults.md`. That file is no longer shipped, and a missing `@import`
fails **silently**. `install.sh <instance>` now reports it. Replace that line with the
`## Session defaults` section from [`seed/CLAUDE.md`](seed/CLAUDE.md).
