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
instance**.

Two gates stay yours by default:

1. **Promote** a task from `draft` to `ready`.
2. **Merge** the PR (build projects) or **approve** the deliverable (research projects).

The idea is to **steer, not watch**. Role agents run in the background and bubble up
results and questions, not every step.

Both gates can be delegated — see [docs/autonomy.md](docs/autonomy.md). That capability is
**off unless installed**: it lives entirely in [`symlink/AUTONOMY.md`](symlink/AUTONOMY.md),
and deleting that one file makes every project `gated` again with no other edits.

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
| `/close-project <slug>` | close a project and fold its conclusions into `knowledge/` |

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
| `oncall-guide` | diagnoses a failing check or a broken build |

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
**Read the field list before you publish one** — the page can leave the machine.

## Three ways to see the board

One snapshot, three renderers. `scripts/write-snapshot.sh` derives each instance's
`SNAPSHOT.json`; all three read it and none of them reads the bundle. Pick by what you
are doing, not by which is newest.

| You want | Run | Costs |
|---|---|---|
| a look right now, in the terminal you are in | `scripts/print-board.sh` | nothing |
| a page to share, publish, or read on a phone | `scripts/build-board.sh` | a re-run to refresh |
| a page that updates itself as you work | `scripts/watch-board.sh` | **a process you keep running** |

```bash
scripts/print-board.sh                      # columns: instance, project, phases, tasks, awaiting
scripts/build-board.sh --standalone         # ./board.html, openable in a browser
scripts/watch-board.sh                      # ./.board-live/board.html, re-rendered on every change
```

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
| **Delegated autonomy** | one deletable file. `rm symlink/AUTONOMY.md` and every project is `gated`. [→](docs/conventions.md#4-a-capability-some-deployments-must-not-have-should-be-one-deletable-file) |
| **Worktrees** | `prune-worktrees.sh` **reports, never deletes.** Do not add a delete, not even behind a flag — it destroyed three running agents' worktrees once. [→](docs/conventions.md#7-prune-worktreessh-is-report-only-and-that-is-load-bearing) |
| **Bundle repair** | `migrate-bundle.sh` is report-only by default and fixes only what has one right answer. **A false success is worse than the error it claims to fix.** [→](docs/conventions.md#9-migrate-bundlesh-fixes-only-what-has-one-right-answer-and-is-report-only-by-default) |
| **Retiring content** | machinery symlinks are swept; **seed content is only ever reported**, never deleted. [→](docs/operations.md#2-retiring-content-swept-vs-reported) |
| **Published data** | the board's field list is a data-governance boundary — no question text, no document bodies, no author identity, no out-of-bundle paths. [→](docs/operations.md#before-you-publish-it-know-what-it-carries) |
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
| `maxAgentsInFlight` | **10** | yes |
| `maxPrLoc` | **500** | yes |
| `models` / `roleTiers` | everything inherits the session model | yes |
| `externalReviewer` | the CodeRabbit CLI | yes |
| `boardInstances` | the board is just this instance | yes |
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
| `commit-as.sh` | commits as the right agent identity | yes |
| `required-checks.sh` | resolves a PR's required checks | no |
| `task-owner.sh` | resolves and compares a task's owner | no |
| `write-snapshot.sh` | refreshes `SNAPSHOT.json` | only if it already exists |
| `build-board.sh` | renders the HTML board (anywhere; needs `python3`) | yes, the output file |
| `print-board.sh` | prints the board in the terminal | no |
| `watch-board.sh` | renders the board into `.board-live/` and re-renders on every change | yes, the page (gitignored) |
| `link-repos.sh` | refreshes `<instance>/repos/` | yes |
| `index-kb.sh` | builds local CodeGraph indexes for the group's repos | yes |

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `/pm-loop` reports "Unknown command" | Claude was launched outside the instance dir, or new machinery isn't linked | `cd` into the instance and relaunch; then `install.sh <instance>` |
| A command or agent is missing after a pull | it is a **new** `symlink/` file, so no symlink exists yet | `install.sh <instance>` |
| A seed change from a pull never arrived | seed is copied only when absent, by design | `./upgrade.sh <instance>` and port what it reports |
| Commands and hooks vanished later, having worked | the installer was run from a git **worktree** | re-run `install.sh` from the main working tree |
| Installer exits 2, "refusing to install from a git worktree" | working as designed | `git -C <src> worktree list` — the first entry is the main tree |
| The startup nudge is empty | `AWAITING.md` was deleted, or the PM reshaped its layout | `touch AWAITING.md`; `show-awaiting.sh` greps the heading and bullets **literally** |
| An instance is missing from the board | it has no `SNAPSHOT.json`, or `boardInstances` doesn't name it | `touch SNAPSHOT.json` in it |
| `print-board.sh` printed nothing at all | it was not run from an instance root — that is silence by design, not an error | `cd` into the instance |
| The terminal board is missing a status column | every row was zero there, so it was dropped to fit the width; the footer names which | widen the terminal, or `--width 0` |
| The live page never updates | the watcher was stopped, or the change was outside `projects/` | restart `scripts/watch-board.sh`; it prints a line per render |
| A `yolo` project never merges anything | preflight failed: one `gh` identity, no external reviewer, or no required checks | the loop says which; fix that, or merge by hand |
| `required-checks.sh` exits 2 | the platform probe returned something it cannot classify | that is a refusal by design — read the message, don't loosen the script |
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

## Changing this repo

Read [docs/conventions.md](docs/conventions.md) first. It records the design invariants and
what went wrong to produce each one — the reasoning is the asset, so relocate it rather
than shortening it.

- Machinery goes in `symlink/`. Keep it **generic**: no org, repo, path, team or channel literals — those belong in an instance's `instance.config.json` / `CLAUDE.md`.
- Starting content goes in `seed/`. Retiring a seed file needs an entry in [`RETIRED`](RETIRED) in the same commit.
- Tests live in `tests/`, never under `symlink/` — everything there ships into every instance.
- Run the suite before pushing: `for f in tests/*.test.sh; do bash "$f" || echo "FAILED: $f"; done`
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

**Its config layer now lives here**, under `config/` — see [The config layer](#the-config-layer)
below. The `@~/.claude/claude-defaults.md` import that every instance used to inherit is
gone: that section is inlined in `seed/CLAUDE.md`, so nothing can dangle.

---

## The config layer

ai-bridge can also install the **`~/.claude` layer**: the agents, commands, output style,
hooks and scripts a Claude Code session loads *outside* any instance. A fresh laptop is
one clone and one install.

```bash
~/workspace/ai-bridge/install.sh --config
```

It links **one file at a time** into `${CLAUDE_CONFIG_DIR:-~/.claude}`. A real file in the
way is backed up as `<name>.bak.<epoch>` — **except `settings.json`, which is left exactly
as it is.** That one holds your permissions, so it is never moved aside: an installer that
replaced it could widen what agents are allowed to do, and no convenience is worth that. Restart Claude Code afterwards so it re-scans
agents and commands.

### Two tiers

| Tier | Holds | Why it is its own tier |
|---|---|---|
| **`config/required/`** | `code-architect`, `deep-bug-scan`, `plan-architect` | the only three agents this repo's own role agents look for. Without them `qa-reviewer` loses its second opinion and the PM loses its plan critic — **silently**, which is why they ship here now |
| **`config/opinionated/`** | 10 commands (`/plan`, `/grill`, `/verify`, `/acp`, `/scan`, `/stack`, `/techdebt`, `/rabbit`, `/dave`, `/codex-handoff`), 3 more agents (`build-validator`, `oncall-guide`, `stack-navigator`), the `Brief` output style, 2 hooks (status line, format-on-write), 2 scripts, `MEMORY.md`, `settings.json`, two `*.example.json` | one person's setup. Take it, fork it, or delete the directory. `/dave` calls one company's internal tool — that is exactly the kind of thing this tier is for |

Delete either directory and `--config` still works: it links whatever is there, and errors
nowhere.

### Five rules it follows

1. **Never a whole-directory symlink.** `agents/`, `commands/` and `skills/` are *drop-in* directories — any skill or plugin installer can write a new subdirectory into them at any moment. Linking one as a unit aims it at this checkout, so every drop-in lands inside a public git repo. That is how four uninvited skills once got committed to the parent repo, three of them dead links. Per-file links keep `~/.claude/<dir>` a real directory that owns its own contents.
2. **It refuses to write *through* a symlinked directory.** If `~/.claude/agents` is itself a link into some other checkout, `--config` skips it, names it, prints the `mv` that fixes it, and exits non-zero. It never writes into the other repo.
3. **`settings.json` stays yours.** It is linked only when you have none. Otherwise the installer prints the two commands to adopt the baseline and stops — it never edits your file, not even to merge one key.
4. **A retired file's link is swept.** Delete something from `config/` and the next `--config` removes the dangling link. A dangling command still registers with Claude Code; a dangling hook exits 127 every launch.
5. **Nothing here is required.** An instance never needs the config layer, and the config layer never needs an instance. `install.sh <dir>` behaves exactly as it always did.

### Uninstall

```bash
~/workspace/ai-bridge/install.sh --config --uninstall
```

Removes only the symlinks it created. Real files, `*.bak.*` backups and your runtime state
(`plugins/`, `projects/`, history) are left alone.

### Coming from the separate `ai-setup` repo

An instance stamped before this existed carries one line in its `CLAUDE.md`:
`@~/.claude/claude-defaults.md`. That file is no longer shipped, and a missing `@import`
fails **silently**. `install.sh <instance>` now reports it. Replace that line with the
`## Session defaults` section from [`seed/CLAUDE.md`](seed/CLAUDE.md).
