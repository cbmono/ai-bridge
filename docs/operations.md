# Operating an instance

Upgrading after a pull, the retire sweep, the worktree report, and the cross-instance
board. Procedures here; the reasoning behind each one is linked.

---

## 1. Upgrading an instance after you pull this repo

A `git pull` here updates the template. What that means for an existing instance depends
on *what* changed — and only two of the four cases need you to do anything.

| What changed in the pull | Reaches an instance how | You must |
|---|---|---|
| An **edited** `symlink/` file (script, agent, command, `SCHEMA.md`, `CONVENTIONS.md`, a `.claude/rules/` file) | Instantly, through the existing symlink | nothing |
| A **new** `symlink/` file | Not at all until its symlink exists | `install.sh <instance>` — once per instance |
| A **`seed/`** file (`CLAUDE.md`, `README.md`, `index.md`, …) | Never — seed is copied only when absent, so instance data is never clobbered | port the change by hand, per instance |
| A **schema** change | The machinery updates, the *data* does not | `scripts/validate-bundle.sh`, then `scripts/migrate-bundle.sh` (report), then `--apply` |

### One command walks all four rows

```bash
./upgrade.sh ~/workspace/<group>/_ai-bridge-<group>            # report — changes nothing but symlinks
./upgrade.sh ~/workspace/<group>/_ai-bridge-<group> --apply    # write the safe changes
```

It runs `install.sh` (row 2), then the instance's `validate-bundle.sh` (row 4) and
`migrate-bundle.sh`, then works out row 3 — and ends with a numbered list of what is left
for **you**, with the exact commands. Report-only by default. Re-run it any time; a second
run finds nothing to do.

**Row 4 is the one that bites, and it is why the order inside the script is fixed:** the
validator ships instantly through its symlink and starts reporting errors against
documents written under the old rules (working as intended — the errors were already
there), but nothing repairs them until the migration runs, and on an instance older than
those scripts it takes `install.sh` to make them exist at all.

### Row 3: the five seed verdicts

Row 3 is the one you cannot automate blindly, so the script judges each seed file on
evidence from this repo's git history.

| Verdict | What it means | What `--apply` does |
|---|---|---|
| prior version of the seed, **verbatim** | nothing was hand-edited | ports it exactly |
| **hand-edited**, change lands elsewhere in the file | your edits and the seed's don't overlap | 3-way merges on top of your edits (backing the file up first) and verifies the result on disk |
| **`CONFLICT`** | your edits and the seed's collide | **nothing.** Your wording is the only copy of a decision somebody made — port it by hand |
| seed file **never changed** since your instance was stamped | nothing to deliver | stays quiet even though your copy has grown (`log.md`, `index.md`, a `.gitignore` with the machinery block) |
| **`UNKNOWN`** | no usable history to judge against | **nothing.** `diff` the two paths it names and port by hand |

Two ways to reach `UNKNOWN`: the template you are running from has no git history for
that seed file (a shallow clone, a downloaded archive, a file added but never committed),
or the instance path is not a regular file any more (a seeded file replaced by a directory
or a symlink). Either way the script cannot tell an edit from a divergence, so it refuses
to guess.

### Then

1. **Restart Claude Code** in the instance (`/exit`, then `claude`) so new agents and commands register.
2. **Verify.** Invoke a changed command or agent (e.g. `/audit`, or a `/pm-loop` dry run) and confirm it registers (no `skills:` prefix) **and** that model routing resolves as configured. If a command reports "Unknown command", re-check the install and the restart.
3. If `instance.config.json` lacks the model-routing block, add it — otherwise model routing stays off and everything runs on the session model:

```json
"maxAgentsInFlight": 10,
"models":    { "light": "haiku", "standard": "sonnet", "deep": "opus", "apex": "fable" },
"roleTiers": { "project-manager": "deep", "software-engineer": "standard",
               "devops-engineer": "standard", "qa-reviewer": "deep",
               "cataloguer": "light", "auditor": "deep", "plan-architect": "apex" }
```

`maxPrLoc` is optional in the same file — absent, the PR-size heuristic uses **500** — so
add it only to move the threshold.

---

## 2. Retiring content: swept vs. reported

| What you retired | What happens to an already-stamped instance |
|---|---|
| a **machinery** file under `symlink/` | `install.sh` step 2b **deletes** the now-dangling symlink |
| a **seed** file | **reported**, never deleted — with the exact `rm`, in `upgrade.sh`'s "what's left for you" list |

The asymmetry is deliberate: a dangling symlink into this template has exactly one
possible meaning; a seed file has been the human's to edit since the day it was copied in.
`install.sh` never removes instance content, which is what makes it safe to run blindly on
a repo full of somebody's work.

**When you retire a seed file, declare it in [`RETIRED`](../RETIRED)** (`<path>` TAB
`<reason>`) **in the same commit that deletes it, and never prune the manifest** — an
instance stamped years ago still has the file.

Step 2b's sweep is narrow on purpose: a link is removed only when it points **into this
template's `symlink/`** *and* its target is gone. Full reasoning:
[conventions.md invariants 1 and 2](conventions.md#1-retiring-content-is-asymmetric).

---

## 3. Machinery is machine-local

The symlinks point at absolute paths into this checkout and are gitignored in the
instance, so a clone on another machine has the committed instance data but **dangling**
machinery until you re-run `install.sh` there. That is intentional — the machinery is
sourced from this repo, not vendored into each instance.

To change the machinery: edit files under `symlink/` and commit. Every instance picks the
change up immediately. Re-run `install.sh` on an instance only when you **add** new
machinery files (to refresh its symlink set and `.gitignore` block). Keep machinery
generic: no org, repo, path, team or channel literals — those belong in each instance's
`instance.config.json` / `CLAUDE.md`.

### Moving this checkout: 185 dangling symlinks, and nothing noticed

Measured 2026-08-23. `~/workspace/ai-bridge` was moved with a plain `mv`. Every symlink is
absolute, so everything broke at once:

| where | dangling symlinks |
|---|---|
| three instances | 39 + 64 + 58 |
| `~/.claude` (the `--config` layer) | 24 |

**185 broken links, and all three instances looked fine from the outside.** A dangling
symlink is invisible until something executes it — which for a `/pm-loop` tick means
mid-dispatch, with agents already briefed.

The repair is one idempotent command per instance, from the checkout's **new** location:

```bash
bash /new/path/to/ai-bridge/install.sh ~/workspace/_ai-bridge-<group>   # per instance
bash /new/path/to/ai-bridge/install.sh --config                         # once, for ~/.claude
```

`install.sh` relinks every machinery file and, in the same run, **sweeps the dead
`<name>.bak.<epoch>` symlinks it makes on the way** — step 2 moves each dangling link aside
before relinking, so without the sweep one repair left 38 dead backups in a test instance
and 122 across two real ones. The sweep only ever removes a **dangling symlink** whose
original now exists again as a link of ours; a `.bak.*` **regular file** is content a human
owns and is never touched, and neither is a dangling `.bak.*` link that was not ours.
`tests/moved-template.test.sh` pins all four negatives.

**Detection.** `.claude/hooks/check-machinery.sh` runs at `SessionStart`, resolves four
machinery links (a root document, a script, a role agent, a hook) and — if any dangle —
names them, names where they pointed, and prints the exact `install.sh` line that repairs
this instance. It never repairs anything itself. In a healthy instance, and in any
non-bridge project that inherits the hook, it prints nothing and exits 0.

> **The hole this leaves, stated rather than implied.** `.claude/settings.json` is itself
> one of the machinery symlinks, so when the **whole** checkout moves it dangles too —
> Claude Code then has no project settings, the hook is never registered, and it cannot
> run. The hook therefore catches the partial cases (a file renamed or retired inside a
> template that is still where the instance thinks it is; a half-repaired instance) and
> **not** the wholesale move that motivated it. A detector built out of the machinery it
> checks does not survive the total failure of that machinery.
>
> Closing it needs one real, non-symlinked file the harness reads unconditionally. The
> obvious candidate — make `.claude/settings.json` the one machinery file `install.sh`
> **copies** instead of links, with the check inlined in the hook command so no script file
> can dangle — costs the property every other machinery file has: edits under `symlink/`
> would stop reaching already-stamped instances, and `install.sh` would have to start
> editing a settings file it currently promises never to touch. That is a deliberate trade,
> not a bug fix, so it is recorded here for a decision rather than made in a hook.

---

## 4. Worktrees: reported, never deleted

```bash
scripts/prune-worktrees.sh                       # report
PRUNE_ACTIVE_MINUTES=30 scripts/prune-worktrees.sh
```

**It never deletes.** It classifies and prints the `git worktree remove` commands for a
human to run.

| Label | Meaning |
|---|---|
| `KEEP` | in use, or a branch with **no commits of its own** (a fresh dispatch and an already-merged branch are the same set — the tie goes to KEEP) |
| `REMOVABLE` | its PR is merged or closed, and it has commits of its own |
| `RECLAIMABLE` | a **detached-HEAD** worktree — no branch ref, so a human judges it |

The removal path was deleted in v2 because it had destroyed three running agents'
worktrees. **Do not reintroduce a delete, not even behind a flag.** The accepted cost is
that the worktree root grows and draining it is a periodic human job. `worktreeRoot` is
optional; absent it is **`<reposRoot>/_wt`**. Full reasoning, including all four
classification guards:
[conventions.md invariant 7](conventions.md#7-prune-worktreessh-is-report-only-and-that-is-load-bearing).

---

## 5. The cross-instance board (optional)

`AWAITING.md` answers "what needs me *here*". The board answers "where does everything
stand, across every instance" — instance → project → phase progress → a column per task
status, with the same 🔴 awaiting-you queue on top.

**One snapshot, three scripts, four ways to look at it.** `scripts/write-snapshot.sh`
derives each instance's `SNAPSHOT.json`; every renderer reads that file and none of them
reads the bundle. That separation is the whole reason each renderer after the first was
cheap — see
[conventions.md invariant 11](conventions.md#11-the-cross-instance-board-is-a-writer-three-renderers-and-one-deletable-generated-file).
There is **one** HTML page, not two behind a flag: projects collapsed to a summary line,
expandable to their task table. The kanban `columns` layout was rejected by the owner as
unreadable and deleted — `build-board.sh` refuses `--layout` by name, so a caller written
against the old flag fails loudly rather than rendering a different page.

```bash
scripts/write-snapshot.sh                                    # in an instance: refresh its SNAPSHOT.json
scripts/print-board.sh                                       # the terminal board
scripts/build-board.sh                                       # an Artifact page BODY, for publishing
scripts/build-board.sh --standalone --out /tmp/board.html    # ...the same page, to open in a browser
scripts/watch-board.sh                                       # a local page, re-rendered on every change
```

Each `/pm-loop` tick refreshes the snapshot at the end of the tick, so on a looping
instance you never run the writer by hand — and where `boardArtifactUrl` is set, the same
tick re-renders and republishes the page ([below](#publishing-it-from-each-tick)).

### Which renderer to reach for

| | `print-board.sh` | `build-board.sh --standalone` | `build-board.sh` | `watch-board.sh` |
|---|---|---|---|---|
| Output | columns in your terminal | one HTML **file**, openable in a browser | the same page as a **body**, for publishing | the same page, kept fresh |
| Freshness | the moment you ran it | the moment you ran it | the moment you ran it — or every tick, once published | live, to the second |
| Shareable | paste the text | you publish it yourself | **yes** — publish it, read it on a phone | no, local only |
| Costs | nothing | a re-run to refresh | a re-run, or a looping instance | **a resident process** |
| Reach for it | by default, when you are already in a terminal | you want to look at it locally | someone else needs to see it | while actively working a queue |

**The watcher needs a process you keep alive, and that is a real cost, not a detail.**
ai-bridge deliberately has no resident process: its agents are ephemeral subagents inside
one Claude Code session, nothing runs between sessions, and no daemon is installed or
supervised. It is the same constraint that made munder-difflin's live telemetry
unreachable for us. So the live page is a terminal tab you keep open — it stops when you
close it, sleep the machine, or lose the session, it gives you nothing to share and no
phone access, and it is per-machine. If any of that matters, the other two cost nothing
and you re-run them.

Details worth knowing before you pick one:

1. **`print-board.sh` degrades rather than wrapping.** On a narrow terminal it drops the
   status columns that are zero in *every* row (naming them under the table), clips
   **names** with `…`, and never clips a **number** — a wrong count is worse than a
   missing column. Below the width where a table still fits, it prints one short block
   per project. Piped output is never clipped at all, because narrowness is a property of
   a terminal, not of a pipe.
2. **It colours only a TTY, and honours `NO_COLOR`.** A board redirected into a file, a
   ticket or a PR body carries no escape codes. `--color always` forces colour anyway;
   `--width N` pins the layout, which is what makes the output reproducible.
3. **`watch-board.sh` writes into `.board-live/`, which is gitignored** (`install.sh`
   appends the line, so instances stamped before it existed get it too). It re-renders on
   any change to this instance's task documents, and on any watched instance's snapshot
   being rewritten.
4. **It watches with `fswatch` if you have it, and polls if you do not** (`--interval`,
   default **2** seconds). `fswatch` is never assumed — the probe reports which mechanism
   it picked. `WATCH_BOARD_WATCHER=poll` or `=fswatch` overrides the probe (`auto` when
   absent).
5. **It refreshes only *this* instance's snapshot.** A sibling instance on the board is
   rendered from whatever snapshot it currently has, refreshed by its own `/pm-loop`. A
   watcher started in one group does not write files in another group's directory.
6. **Ctrl-C stops it cleanly and leaves nothing behind** — no stamp file, no orphaned
   child. The page it produced stays where it is.
7. **`--once` renders and exits**, which is the way to get a local standalone page
   without keeping anything running.

**On by default, off by `board: false`.** (Changed 2026-08-23: it used to be opt-in by presence, with `rm` permanent. That inverted the common case — every instance stamped before the board existed silently stayed off it, and three of three real instances were in that state. The decision now lives in `board` in `instance.config.json`, where it is visible and survives a re-stamp. A `rm` still drops an instance off immediately, but the next stamp restores it unless config says otherwise. A snapshot is a LOCAL gitignored file — having one does not publish anything.)

**Historic note.** `install.sh` creates `SNAPSHOT.json` on the **first
stamp only**; the writer rewrites it just when it already exists and never creates it;
`build-board.sh` leaves a snapshot-less instance off the page entirely, with no
placeholder. So `rm SNAPSHOT.json` takes that instance off the board for good, and
`touch SNAPSHOT.json` puts it back. An instance stamped **before** the board existed is in
the same position as one that deleted the file — opt in with `touch SNAPSHOT.json`.

**Which instances appear is explicit, never a glob.**

| You ran | Renders |
|---|---|
| `build-board.sh <dir> <dir>` | the directories you named |
| `build-board.sh` with `boardInstances` set | those instances |
| `build-board.sh` with `boardInstances` absent or empty | **just this instance** |

```jsonc
// instance.config.json
"boardInstances": [".", "~/workspace/other-group/_ai-bridge-other-group"]
```

### Before you publish it, know what it carries

The board's HTML can leave the machine, so the snapshot deliberately carries *less* than
`AWAITING.md` does.

| Carried | Never carried |
|---|---|
| project title / description / kind / status / autonomy | a task `description:` |
| project `owner` — a GitHub **username** (see below) | phase or task `owner:` overrides |
| phase title / order / status | any document body |
| task id / title / kind / status | the **text** of an open question or a blocker reason |
| assignee **role**, in-flight flag | any author **email** (`authorEmail`) |
| awaiting **verb**, open-question **count** | any path outside the bundle |
| PR links | — |

**One identity field is carried, and it was a decision.** `owner` used to be on the right
of that table, for the obvious reason: on a shared bundle it names a person, and this page
gets published. It moved because publishing is **account-scoped** — each human publishes
their own board — so a board that cannot say whose project is whose cannot separate your
work from theirs, which is the only thing the second section is for. The concession is
kept narrow: a GitHub username (public, stable — never an email), copied verbatim from the
project document, project-level only. **The other owners are named in the published HTML
whether their section is expanded or collapsed** — the collapse is reading comfort, not
redaction, and the page's own footer says so.

Titles *are* carried, because a board without them is unreadable — which makes the file
**as sensitive as the task documents it comes from**. That sentence travels inside the
JSON in its own `_sensitivity` key. **No customer PII belongs in a task title in the first
place.** Read that header before adding a field: `tests/snapshot.test.sh` fails on any key
outside the documented set.

The page's only external request is **one declared webfont** (two `<link>`s to Google's
font hosts, asserted verbatim in `tests/snapshot.test.sh`) — no CDN, no `src=`, no
`url()` in the stylesheet. It carries **one `<script>`**, a clipboard helper, and nothing
from a snapshot ever reaches it: collapsing is `<details>`, not JavaScript. (Until
2026-08-24 this paragraph said "zero external requests, no `<script>` at all". That was
true of the kanban `columns` page and never of the one that got published; `columns` has
since been deleted, so the promise is now stated against the page that ships.) The page
is theme-aware, and the default output is an Artifact page body; `--standalone` gives you a file to open yourself. `build-board.sh` needs `python3`
(stdlib only) — JSON parsing and HTML-escaping are the two things a hand-rolled awk reader
gets wrong on exactly this input. `print-board.sh` needs it for the same two reasons with
a different sink: a terminal's metacharacters are ANSI escapes and newlines, and a title
carrying one must not repaint the screen or forge a row.

**Escaping is per-medium, and all three renderers do it.** A title is human prose, so the
HTML board escapes for markup and the terminal board strips every code point in Unicode
category C (ESC and the other controls, the bidi overrides). Nothing from a snapshot ever
sets a colour.

Full reasoning, including why one drifted instance must not blank the board for the rest:
[conventions.md invariant 11](conventions.md#11-the-cross-instance-board-is-a-writer-three-renderers-and-one-deletable-generated-file).

---

## 6. Other operational knobs

| Knob | File | Default when the key is absent |
|---|---|---|
| `maxAgentsInFlight` | `instance.config.json` | **10** — a throughput/cost throttle, not a safety lock |
| `maxPrLoc` | `instance.config.json` | **500** — the agent **proposes** a split and opens the PR anyway; never a gate, never a review criterion |
| `PUSH_STATE_MAX` | env | **12** items per list in the per-turn state injection |
| `PRUNE_ACTIVE_MINUTES` | env | the recursive mtime veto in the worktree report |
| `worktreeRoot` | `instance.config.json` | **`<reposRoot>/_wt`** |
| `boardInstances` | `instance.config.json` | just this instance |
| `boardArtifactUrl` | `instance.config.local.json`, else `instance.config.json` | **a tick never publishes** — render and publish by hand, or not at all |
| `codegraphSkip` | `instance.config.json` | index every product repo |

One hard rule holds regardless of `maxAgentsInFlight`: never two package installs against
the **same repo's store** at once (the PM staggers deps-touching tasks across ticks).

### Local code intelligence (codegraph, optional)

Role agents navigate product repos faster with a local CodeGraph index than with blind
grep. Opt-in, 100% local — no code leaves the machine.

1. `npm i -g @colbymchenry/codegraph`
2. `codegraph install` — wires the codegraph MCP into Claude Code (`-y` for non-interactive, `--print-config <id>` to inspect first)
3. From the instance root: `scripts/index-kb.sh` — reads `reposRoot`, indexes every product repo (incremental on re-run), skips worktrees (`_wt`), instance dirs (`_ai-bridge-*`) and non-git dirs. `--with-serena` also warms a Serena LSP cache.

Add infra/assets repos with no useful call graph via `codegraphSkip` (space-separated) or
`$CODEGRAPH_SKIP`. With no index present, agents just grep as before.

### Model routing

Two knobs in `instance.config.json`:

| Key | What it does |
|---|---|
| `models` | maps tiers to model aliases: `{ "light": "haiku", "standard": "sonnet", "deep": "opus", "apex": "fable" }`. Aliases track the latest model in each tier, so you retune per instance without editing agents |
| `roleTiers` | each role's default tier (e.g. `project-manager` → `deep`, `qa-reviewer` → `deep`, `cataloguer` → `light`, engineers → `standard`) |

The top **`apex`** tier (`fable`) is reserved for the **deepest, rarest reasoning** — the
`plan-architect` critique the PM dispatches on genuinely complex tasks — where a frontier
model earns its cost. The orchestrator itself runs on `deep` (opus): plenty for routing,
and it ticks often. Retune per instance as cost dictates.

Per tick the PM starts from the role's default tier, **bumps a complex build task up**
(multi-file/service, or heavily-inferred `acceptance_criteria`) and **drops a trivial one
down**, then resolves the tier via `models` and passes that model on dispatch. A task can
force a specific model with a `model:` field (a tier or a raw alias) — the PM honors it
verbatim. Omit both maps and everything just inherits the session model.

**Resolve it with `scripts/resolve-model.sh <agent>`, never from memory.** It prints the
one alias for that agent (`roleTiers[<agent>]` → `models[<tier>]`), and for an agent with
no entry prints nothing and exits 1 — the caller then inherits the session model rather
than guessing. This applies to **every** dispatch, including an ad-hoc one from a main
session, which is the path the prose version of this rule never reached.

### Concurrency

`maxAgentsInFlight` (default **10**) caps how many role agents the PM runs at once. With
worktree isolation + private package stores the old corruption risk is gone, so this is a
**throughput/cost throttle**, not a safety lock — tune it to the machine and account:
raise it on a well-resourced box with mostly-independent tasks, lower it (e.g. 5) on a
laptop. **No role agent's allowlist contains `Workflow`**, and of the role agents only
`qa-reviewer` holds `Agent` — so the only fan-out that can happen inside a task is
`qa-reviewer` dispatching several agents in parallel, and this same cap bounds it. Read a
fan-out instruction against the agent's `tools:` list, never against what is installed:
[invariant 17](conventions.md#17-an-instruction-addressed-to-an-agent-is-executable-only-if-that-agent-holds-the-tool).

### PR size

`maxPrLoc` (**500** when the key is absent) is the diff size past which a PR-opening role
agent proposes a split. It is a **heuristic that suggests, never a gate**: the agent says
in the PR body which parts it would extract and then opens the PR anyway, because
generated boilerplate, codemods, lockfiles and dense logic all move the real number and a
line count cannot decide reviewability on its own. It is not a review criterion — no
reviewer withholds clearance over it. An existing instance whose config predates the key
needs no edit.

### Per-instance settings

`.claude/settings.json` is **shared machinery** (symlinked) — editing it changes every
instance. For permissions or env an instance needs on its own (e.g. allow `Bash` in that
group's repos), put them in `.claude/settings.local.json` **in the instance**: it's local,
gitignored, layered on top, and never touches the template.

---

## 7. Editor view (control panel + repos in one tree)

The product repos stay **physical peers** of the instance, never nested inside it —
nesting would drag the instance's control-panel `CLAUDE.md` into the cascade of every
product-repo session (telling them they're a control panel that commits to `main`). To
still see everything in one tree:

| Editor | What to open | Notes |
|---|---|---|
| VS Code / Cursor / Antigravity | the seeded **`<group>.code-workspace`** (*Open Workspace from File…*) | multi-root view, control panel pinned on top, group repos below |
| Zed (no workspace-file support) | the **group folder** | the instance's `_`-prefix already sorts it to the top |
| any editor, and the terminal | **`repos/`** inside the instance | one symlink per repo, so `ls repos/` and `cd repos/<name>` work from inside the instance |

**The workspace file.** A generic `files.exclude` glob (`_ai-bridge-*`) hides the instance
from the repos pane so it isn't shown twice, and `terminal.integrated.cwd` — uncommented
and stamped with the instance's absolute path at install time — pins **new terminals** to
the instance. Without it a multi-root workspace picks the terminal's folder separately from
the editor's and can land in the group root, where the instance's `.claude/commands`
doesn't exist, so `/pm-loop` and `/new-project` are silently absent. Right-clicking a
repo > *Open in Integrated Terminal* still overrides it, so per-repo terminals work. The
setting ships **commented out** in `seed/bridge.code-workspace`, so an unstamped copy just
loses the pin rather than pointing terminals at a directory that doesn't exist (which
blocks terminal launch outright).

**`repos/`.** Created and refreshed by **`scripts/link-repos.sh`** (run by `install.sh`;
run it again on its own after cloning a repo — no full refresh needed). It links every
directory under `reposRoot` that has a `.git` and whose name doesn't start with `_`, which
skips sibling instances and the `_wt/` worktree root, and it never links the instance
holding the view — that would recurse. Stale links are pruned, real files there are never
touched, and `--remove` tears the view down (as `install.sh --uninstall` does). It's
**gitignored**: symlinks into a machine-local path, so committing them would dangle on
every other machine. The seeded workspace file sets `search.followSymlinks: false` so
editor search doesn't report every hit twice, once per route.

None of this moves a repo: the workspace file only changes the display, and `repos/` adds
symlinks beside the instance's own files. **Regardless of editor, launch Claude by
`cd`-ing into the instance dir and running `claude` there** — the editor's open folder
doesn't affect which `.claude/` loads; the working directory does. Instances created
before the `terminal.integrated.cwd` line existed keep their own workspace file (install
never clobbers instance data), so add it by hand there if you want the same guarantee — an
absolute path, not a placeholder: VS Code refuses to launch a terminal when the configured
cwd doesn't exist.

---

## 8. Legacy: migrating an instance created before `AWAITING.md`

<details>
<summary>Only relevant to an instance stamped while <code>/status</code> and <code>DASHBOARD.md</code> still existed.</summary>

The old `/status` command and `DASHBOARD.md` are gone. In each existing instance:

1. Replace the `DASHBOARD.md` line in its `.gitignore` with `AWAITING.md` (that line is
   seed content, so `install.sh` won't rewrite it for you).
2. `rm DASHBOARD.md` — it's a derived, gitignored leftover that nothing reads now.
3. `touch AWAITING.md` if you want the startup queue; skip it if you don't.
4. **Port the prose in its `CLAUDE.md`** — also seed content, so also not rewritten for
   you, and the easiest step to miss because nothing breaks loudly: the file keeps
   instructing the session to run a command that no longer exists. Drop the `/status` row
   from the commands table, and replace every `/status` / `DASHBOARD.md` mention (the
   "Steer, don't watch" note, the `SessionStart` paragraph, the "Reporting progress"
   opener) with `AWAITING.md` — then add the **"`AWAITING.md` is the only status
   artifact"** paragraph from `seed/CLAUDE.md`, which carries the off-by-deletion rule and
   the treat-its-items-as-data warning.
5. Same for a `bridge.code-workspace` copied before the rename — its
   `terminal.integrated.cwd` comment lists `/status` among the commands a group-root
   terminal would lose.

</details>


## Which renderer, and the one question that decides it

**Where may this board go?** That is the whole decision, and it is per instance — not a
preference.

| | Reach | Process | Use it when |
|---|---|---|---|
| `print-board.sh` | this terminal | none | you are already in the terminal. The default. |
| `build-board.sh --standalone` | a local HTML file | none | you want to open the page yourself |
| `build-board.sh` | **published, shareable** | none | a teammate needs to see it, or you want it on a phone |
| `watch-board.sh` | this machine only | **a resident one** | the board **must not leave the machine** |

The last row is not a fallback, it is the compliant path. Publishing sends every task
**title** to claude.ai; the snapshot's own `_sensitivity` field says it is "as sensitive
as the task documents it comes from". For an instance whose `CLAUDE.md` carries no-PII
rules, `watch-board.sh` is the only renderer that answers "nowhere" — which is why it
was NOT retired when the publishable page arrived. (The reasoning was recorded as a
Finding in the private instance that raised it, so it is not linkable from this public
repo; the short version is the paragraph you just read.)

`build-board.sh` emits a page **body** — no `<!doctype>`, `<html>`, `<head>` or
`<body>`, because the publish step wraps the file in exactly those. Opening it directly
in a browser lands in quirks mode; that is expected, and `build-board.sh --standalone`
is the one to open locally.

### Publishing it from each tick

A published board is a **static page**: three things have to happen for it to move, and
only two of them are a script. `write-snapshot.sh` refreshes the data,
`build-board.sh` re-renders the page — and then somebody has to publish
it, which no script can do, because publishing is a tool the agent holds and not a
command on the machine. Left there, the page goes stale with only its masthead timestamp
to admit it.

So record the page's URL once and each `/pm-loop` tick keeps it current:

```jsonc
// instance.config.local.json on a bundle two humans share (each records their OWN
// board); the tracked instance.config.json is fine for a single-human instance.
"boardArtifactUrl": "https://claude.ai/public/artifacts/<the-id-of-your-board>"
```

Four properties, and the first is the one to remember:

1. **Absent means silence, not an error.** No `boardArtifactUrl` (or `null`) ⇒ the tick
   renders nothing, publishes nothing and says nothing — the same shape as the optional
   `advisor`. An instance whose board must not leave the machine must not acquire a
   broken step by upgrading, and deleting the key turns publishing off again. A key that
   is *present* but not an `https://` URL is the one case that gets a line: a typo is not
   a decision, and silence would hide it. (The off switch is a **config key**, not a
   deletable file under `symlink/` — which is the caveat
   [conventions.md invariant 4](conventions.md#4-a-capability-some-deployments-must-not-have-should-be-one-deletable-file)
   ends on: machinery is re-linked unconditionally, so a file-shaped switch gets switched
   back on by the next `install.sh`.)
2. **The URL is read, never invented.** Publishing without it forks a *second* artifact
   rather than updating the first, so the URL a team bookmarked would freeze while a new
   page appeared every gap. A tick that publishes to a fresh URL is a bug, not an
   outcome; if the recorded one stops resolving, the tick says so in one line and
   recording a replacement stays yours.
3. **It IS per-machine, and that reverses an earlier rule.** It used to be tracked-only,
   on the ground that one URL means one page a whole team shares. That assumed two clones
   could publish to one artifact, and **they cannot**: publishing is **account-scoped** —
   the update path needs an artifact the account owns, and no share level grants it, so
   exactly one account can ever update a given URL. Verified live: listing with
   `scope: all` did not include the other human's board, and reading it directly returned
   *artifact not found — it may have been deleted, or it has not been shared with you*. A
   tracked URL therefore never produced one shared board; it produced one working board
   and one publish step that failed silently on the other clone forever. So
   `boardArtifactUrl` is in the `instance.config.local.json` override set and **each human
   publishes their own page** ([SCHEMA.md → Per-machine config
   overrides](../symlink/SCHEMA.md)).
4. **A republish is not a change.** The tick still reports `noop: true` when the
   documents did not move — a board refresh alone must not wake anybody, or an idle loop
   starts scrolling and gets switched off.

Publishing is still a **decision**, not a default: it sends every task title to
claude.ai. Read [what the snapshot carries](#before-you-publish-it-know-what-it-carries)
before you set the key, and note that `board: true` (a local, gitignored snapshot)
publishes nothing on its own — the two switches are independent.

**A `SessionStart` hook surfaces the link too.** `.claude/hooks/show-board-link.sh`
reads this same `boardArtifactUrl` — never a second copy of it — and, if it is set,
prints it once when a session starts, so the human can open the page instead of
digging for the URL. Same off switch as everything else here: absent, empty, or `null`
means exit 0 in silence, and so does a non-bridge project that happens to inherit the
hook. It reads nothing else — no task document, no `AWAITING.md` — so it is not a
second, unvalidated copy of `show-awaiting.sh`'s field discipline; it prints the link
and nothing more.
