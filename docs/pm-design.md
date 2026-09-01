# The PM loop — the reasoning behind the steps

`symlink/.claude/commands/pm-loop.md` (the launcher) and
`symlink/.claude/agents/project-manager.md` (the tick) carry the **steps**; this file
carries the **why** — the incidents, measurements and rejected alternatives each rule
came from. It was split out on 2026-09-01 because the two step files had grown to
64 KB and 35 KB, and every tick paid for all of it: an agent ingests its own definition
before it reads any state, and the rationale changed what an editor should do, never
what a tick should do. Per the repo's rule ("the story lives in `docs/` in exactly one
place"), the whys were relocated intact, not shortened. Section anchors are stable —
the step files cite them.

---

## The launcher

<a id="launcher-shape"></a>
### Why this shape, and not `/goal` (v2 audit, 2026-08)

The looping **mechanism is already first-party**: `ScheduleWakeup` is the same
primitive `/loop`'s dynamic mode uses. The command is a policy layer over it — the
serial guarantee, the instance-root preconditions, the in-flight check, and what a tick
may do — not a hand-rolled loop engine.

`/goal` was considered and does **not** fit. It terminates on a condition, while this
loop runs until a human stops it; its evaluator judges only what is in the transcript
and **calls no tools**, so it cannot see whether a PR merged; and it defers evaluation
while background work runs, which is the normal state of a tick that has dispatched
role agents. Wrong shape on all three counts — so the mechanism stays as it is.

<a id="launcher-serial"></a>
### Why serial (do not revert to a fixed interval)

A LIVE tick can take a long time because it dispatches real role agents that
build/test/push, and those agents may share **one clone + one package store**. A
fixed-interval loop shorter than a tick (e.g. a naive `/loop 15m`) makes ticks
**overlap** → concurrent PMs double-dispatch the same task (two PRs for one slice) and
a sibling's package install corrupts an in-flight worktree. So the loop is gated on
**completion**, never on a clock.

**The guarantee is backed by a lock file, not by a session's memory.** The "one tick at
a time" serialization lives in the session's wakeup chain — and a session's memory of
"I dispatched" does not survive a compaction, a `--resume`, or a human asking "what's
next?". Measured 2026-08-29: two ticks ran concurrently for about 34 minutes for
exactly that reason, doing the same refinement work twice. So step 1 takes `.tick-lock`
immediately before it dispatches, and a second session running `/pm-loop` against the
same working tree is refused rather than overlapping. The lock catches the mistake; it
does not make two loops a good idea.

**The tick takes it too, because a resume never passes through the launcher.** Waking a
completed tick directly runs no `acquire` at all, so nothing is written and a dispatch
seconds later correctly reports the lock free — measured 2026-08-30, an hour after the
lock merged: a resumed tick and a dispatched tick ran at once, and the human spotted it
before the machinery did. So the tick runs the same acquire in its own Step 0.5
(`--as tick`). That does not move the lock out of the launcher: the launcher's acquire
is still the only one that happens *before* a dispatch exists, and moving it into the
tick alone would re-open the window this closes. Nor does a tick refuse the lock taken
for it — an unclaimed lock is precisely the dispatch it is. Its **own claim** on that
lock is the harder half: since 2026-08-30 the claim records *whose* it is rather than
merely that it exists, because before that a dispatched tick duly stood down on its own
claim and dispatched nothing. What no tick can do is *prove* that identity under this
runtime — `CLAUDE_CODE_SESSION_ID` names the **session**, so every tick one loop
session starts carries the same one — so a merely-matching id is exit **2** and lands
on the human's desk rather than being guessed either way.

**And a tick that finds NO lock is refused (exit 4), not allowed to take one.** No lock
means nobody dispatched it, because the launcher takes one in the same breath as the
spawn — so it was resumed, and a tick is never resumed, without exception. Until
2026-08-30 that tick took a lock of its own and ran, and the next genuine dispatch
stood down instead: exactly one tick ran and it was the wrong one, re-entering a loop
whose state had moved on. Only the tick half of the resume rule has a mechanism, and
this is that mechanism; the rest is a convention nothing can check, because nothing can
see the intent behind a message.

**It is a PER-CLONE lock and it is not a cross-machine one.** `.tick-lock` is a single
gitignored file in a single working tree, so it says nothing about the other human's
clone of a shared bundle — and it must not be read as if it did. What stops two clones
dispatching the same TASK is `scripts/task-owner.sh`, never this file. The lock also
bounds PM ticks only: `maxAgentsInFlight` is the other concurrency limit, untouched, so
a held lock never blocks the role agents a tick dispatches.

**A bundle shared by two humans is different, and is supported.** Each human has their
own clone on their own machine, with their own `reposRoot` and `worktreeRoot`, so two
of the three failure modes cannot arise: there is no shared package store and no shared
working tree. The third — double-dispatch — is what `owner` prevents, since each loop
dispatches only its own human's tasks. What remains is racing pushes to the bundle's
`main`, which is an ordinary git conflict on ordinary git files, not corruption: pull
before you push, which the tick does itself (its steps 0 and 8).

**Diagnosing a suspected overlap: suspect your own second tick first.** Interleaved
writers on one control panel read like another session in the bundle, and usually
aren't — a tick dispatched after misreading step 2's signal produces the same symptoms
from inside one session. Two things that look like evidence and are not: **author
names** (`commit-as.sh` sets the role per commit, so one process batching commits
leaves three roles at the same second), and a **tick's own account of a collision it is
part of** — check `git reflog show main`, which is per-clone and therefore answers
whether `main` actually moved backwards, before reporting corruption.

<a id="launcher-reads-nothing"></a>
### The launcher reads nothing else — the argument

**`instance.config.json` is not an exception, and an earlier draft implied it was.**
That draft kept a precondition telling the launcher to read `reposRoot` and `org` —
values the launcher never uses. The TICK uses them, and the tick reads the config
itself. A precondition the tool contract forbids is worse than a missing one: it reads
as licence to widen `allowed-tools`, which is the whole thing the trim exists to
prevent.

Two reasons, and the second is the one that matters. The human ran a command, not a
briefing, so nothing should scroll before "tick dispatched". And every byte read in the
launcher lands in the **main session's** context — the one context the loop has to
survive on for hours across many ticks — while the tick is a backgrounded agent with
its own context, where a full state read is free and is discarded when it ends. The
launcher's answer is thrown away the moment it dispatches either way, so a state read
there buys nothing and is paid for twice.

**This is not "print less".** Collapsing, quieting or redirecting the output would keep
every token and lose the trail. The work does not belong in the launcher at all.

**Why the tick-lock exception is not a precedent.** It earns the carve-out on the
section's own argument rather than in spite of it: the cost that matters is what lands
in the main session's context, and on the normal path `acquire` lands **nothing** — it
prints not one byte when it takes the lock, and speaks only when it refuses, which is
the one case worth the tokens. Two things make it different from every forbidden
reader: it is a **write** the launcher is the only one able to make (only the launcher
knows "I am dispatching right now" — the tick learns it seconds later, which is the
window that let two ticks overlap), and it returns an exit code rather than content.
Nor did `allowed-tools` grow a reader: it grew by exactly
`Bash(scripts/tick-lock.sh:*)`, one script that touches one gitignored file.

<a id="launcher-no-publish"></a>
### Why there is no publish grant, and no publish step

`allowed-tools` used to carry one more grant: the publishing tool, added so a tick
could push the board to a hosted page, plus a **step 2c** that finished the job
whenever the tick could not. The grant and the step are both deleted, and the reason is
worth keeping, because it is not "we simplified".

Publishing was **account-scoped**. Exactly one account could ever update a given page,
no share level granted a second human write access, and the page vanished from under
its own owner the moment they switched Claude accounts — which is what actually
happened. So the mechanism could not deliver the one thing it existed for, and a grant
that buys a step that cannot work is a widened tool contract bought for nothing.

The board is now a local file, rendered by the tick with `scripts/build-board.sh
--standalone` into the gitignored `.board-live/board.html` — surfaced with the tick's
report and printed again at every session start by `session-banner.sh`. Rendering needs
`Bash`, which the tick already holds and the launcher deliberately does not, so there
is nothing left for the launcher to do about the board at all: no grant, no step, and
no page body landing in the main session's context.

<a id="launcher-step-1"></a>
### Step 1 — why the acquire closes a window the tick's own check cannot

The tick's own ledger check (`project-manager.md` Step 0.5) runs *inside* the tick,
after Step 0's `git pull` and its re-derivation, so between the launcher's dispatch and
the tick's ledger entry there is a window of seconds to minutes in which the ledger
truthfully reports nothing running. A second tick dispatched anywhere in that window is
exactly the 34-minute overlap of 2026-08-29. `acquire` closes it by creating the file
with `O_EXCL`, so there is no read-then-write for anything to interleave with.

**Step 2's release discipline**: the `<task-notification>` is the only valid finished
signal because the agent resumes and the same task-id notifies again — a tick that
reads as complete or idle in a status listing may still be running, and one that has
looked done for hours is not done until its notification arrives. Releasing the lock on
anything weaker (a status listing, elapsed time, a quiet repo) hands the next tick a
dispatch the running one has not finished.

<a id="launcher-step-2"></a>
### Step 2 — after a compaction

The loop is long-lived and its context gets summarised; the in-flight set is answered
from session history, which is exactly what compaction discards. That is what
`.tick-lock` is for. Re-deriving the in-flight set from disk is one of the tick's
opening steps — the root `log.md` tick ledger (whose open-with-no-close entry is the
only thing on disk that distinguishes "dispatched, waiting" from "never ran"), then the
task documents' own `status:`, then `git log` / `gh pr list`, each outranking anything
anyone remembers. A tick that finds an open entry reports it and holds rather than
re-dispatching, so the failure this protects against — re-dispatching a task sequence
that already finished, the most expensive failure observed in loops of this shape — is
caught one context deeper, where the read is free.

<a id="launcher-advisor"></a>
### Step 2b — why the advisor's asymmetry matters

The owner is one person and the loop parallelises across tasks, so a mechanism that
routes every concern to a human makes the human the bottleneck and the advisor a net
loss. Escalating is the exception the adjudicator must justify to itself, not the
default.

Two consequences worth being explicit about, because the shape is easy to get
backwards. **A cheap model never steers an expensive one**: the advisor has no channel
to `software-engineer` or anyone else, so nothing it says can redirect work in flight —
its only possible outcome is a question a human answers. And **the filter is a deep
model reviewing a light one**, not the reverse, so a false positive costs one cheap
dispatch and none of the human's attention. An observer that can stall the loop is
worse than no observer, which is why an advisor error is ignored and the loop
continues.

<a id="launcher-noop"></a>
### Step 3 — why a render never flips `noop`

The snapshot and the page are derived from documents that did not move, so a tick whose
only act was re-rendering them still reports `noop: true`. Every tick refreshes the
board, so counting it would pin `noop` to `false` forever, retire the streak line, and
hand the human back the scrolling idle loop the streak exists to prevent — consecutive
`noop: true` ticks collapse into one streak line in the terminal, which is the whole
difference between a loop you leave running and one you turn off because it scrolls.

---

## The tick

<a id="step-0"></a>
### Step 0 — sync first; defer on dirty; never `--autostash`; conflicts stop the tick

**Both halves of the dirty-tree rule are load-bearing, and both were wrong in the first
version of the step.**

*Untracked files are excluded* because they never obstruct a rebase, and an in-progress
project folder or a fresh `sources/` drop would otherwise stop every tick.

*A dirty tree must not stop the tick* because **it is the normal state here, not an
anomaly**: concurrent agents share this one working tree — the reason `commit-as.sh`
demands explicit paths — so a sibling mid-write is routine. Measured on a live shared
instance: `log.md` and a `project.md` were both modified at tick boundary while a
sibling was working. A step that halted on that would halt the loop most of the time.

*And `--autostash` is banned* as the alternative, because it does not fail loudly: when
the rebase succeeds but re-applying the stash conflicts, `git pull --rebase
--autostash` **exits 0** with `HEAD` already moved and the tree left `UU`-conflicted,
and `git rebase --abort` then fails with *fatal: no rebase in progress*. A tick
trusting that exit code parses task documents full of conflict markers and acts on
them.

**Why the pull runs before Step 0.5 and not after it.** Step 0.5 re-derives the
in-flight set *from disk*, and on a bundle shared by two humans the disk is a stale
mirror until you fetch: a task the other human promoted, answered, or finished is
simply not there yet. Re-deriving first and pulling later would have the tick act on
last hour's world and then discover it.

**Why a conflict stops the tick outright.** Conflicted task documents are contested
state between two humans, and a tick that guesses at a resolution writes a status
nobody chose. Reporting a blocked tick costs one tick; a silently mis-resolved
`status:` costs the trust in every status after it. The `never git clean / never delete
the untracked file` rule exists because on a control panel that file is usually a
sibling agent's half-written project folder, and deleting it destroys work no commit
holds.

<a id="step-0-5"></a>
### Step 0.5 — the lock, the identity, and the ledger

**Why the tick runs the acquire too, and not only the launcher.** The launcher takes
the lock immediately before it dispatches, which is the only moment anybody knows "I am
dispatching right now" — that window stays the launcher's. But a resume never passes
through the launcher at all: a SendMessage wakes a completed tick directly, so no
acquire runs, nothing is written, and a genuine dispatch seconds later correctly
reports the lock free — because it is. Measured 2026-08-30, an hour after the lock
merged: a resumed tick and a dispatched tick ran at once and the human spotted it
before the machinery did. Whatever makes a tick run must pass the gate, so the tick
runs it too. That the lock is already held by the launcher that spawned the tick is not
a conflict and the script does not treat it as one — an unclaimed lock is precisely the
dispatch it is.

**Why "run it ONCE and never guess".** Until 2026-08-30 the claim recorded only *that*
a tick had claimed, so a second acquire inside one tick — a retry, a re-run of the
step, a resume — read as a different tick, and the tick stood down on its own claim,
dispatching nothing. The claim now records **whose** it is and **where that identity
came from**, and the honest answer under this runtime is often "I cannot tell":
`CLAUDE_CODE_SESSION_ID` is one value per **session**, so every tick one loop session
starts carries it and a match proves nothing. That case is exit 2, not a re-entry and
not an accusation — it is handed to the human.

**Why a tick never takes a lock of its own.** Until 2026-08-30 a tick that found no
lock created one and carried on; the resumed tick then ran and the next genuine
dispatch stood down instead. Exactly one tick ran, and it was the wrong one. A tick is
now the one thing that is never resumed — no exception, no "unless" — and the absence
of a lock is the evidence, because the only thing that takes one before a tick exists
is the launcher.

**Why the ledger entry opens first, not as part of curation.** A tick that dies
mid-flight — compaction, a crash, a killed session — otherwise leaves *no* record that
it ever dispatched, and the next tick cannot tell "dispatched, waiting for a
notification" from "never ran". An open `TICK` line with no matching close is exactly
that missing signal.

**What the open entry proves, precisely.** It proves a tick started and did not finish.
It does **not** prove the agents it dispatched are still alive — nothing on disk can,
which is why `/pm-loop` step 2 makes the `<task-notification>` the only valid finished
signal. Orient-then-report-then-hold is what turns "there is an open entry" into "these
three tasks claim in-flight, none has a worktree on disk, one has an open PR" — the
difference between a report a human can act on and one that only says something is
wrong. A stale open entry adopted silently miscounts the `maxAgentsInFlight` cap in
both directions. `status: in-progress` on a task is task-scoped and answers a different
question — whether that task was handed out — not whether a tick is done.

<a id="step-0-9"></a>
### Step 0.9 — why an idle tick may skip, and why the probe can never lie it idle

Measured on a live instance (2026-08-27): three CONSECUTIVE zero-delta ticks each did
the full walk — every task file read, every open PR re-fetched and re-verified at head,
the worktree report, the queue rewrite — on the dearest model tier, to conclude
"nothing changed", and each wrote a ~2.5 KB ledger close saying so. The comparison that
proves "nothing changed" needs no model: it is a fingerprint a shell can take and diff,
which is what `scripts/tick-delta.sh` does. The model ingests one verdict line instead
of a world that did not move.

The safety argument has one load-bearing direction: a false DELTA costs one full tick
(the price that was always paid); a false IDLE would skip owed work. So every doubt —
no record, no `gh`, a probe error, any `in-progress` task, any dirty tracked file, any
untracked file under `projects/` — resolves to the full tick, and the fingerprint holds
exactly the facts whose movement creates tick work: bundle HEAD, per-task status, each
open PR's head SHA, state and review decision, and the presence of the two opt-in
artifacts (a `touch AWAITING.md` re-enable needs one full tick to populate the queue).

What the probe deliberately does not see, stated rather than discovered: a PR body edit
at an unchanged head (an unticked criteria box, an edited description) and anything
visible only in comment prose. Those defer to the next real delta. That is the same
trade the yolo merge gate refuses — it re-reads everything at the moment of merging —
but a `gated` surface-only tick can afford it, because nothing is merged, promoted or
dispatched on the strength of an idle verdict; the verdict only ends a tick that would
have ended with the same report at higher cost. The lock and the ledger are untouched:
steps 0 and 0.5 run before the probe is consulted, every tick.

The record is written by a FULL tick as its last derived act (after the commit, the
sync, the queue and the board), through a temp-file rename so a crash cannot leave a
torn record for the next check to "match" — and `record` refuses to write at all when
it cannot compute the complete fingerprint, because a partial record would turn the
next "match" into a lie. An idle tick leaves the record alone: it just proved it
current, and rewriting it would only move a timestamp nothing judges.

<a id="step-1"></a>
### Step 1 — why one digest replaces the walk, and why the done-project skip is at the frontmatter

The orientation used to be N separate reads — every `project.md`, every task's
frontmatter, one `gh pr view` per open PR — each a model round-trip carrying the tick's
whole context. The facts those reads produce are mechanical, so `tick-delta.sh digest`
(the probe's own walk, enriched) produces them in one command: the model ingests one
block instead of paying a round-trip per file. Two properties keep it honest. The
digest is the **enumeration, never the judgement** — a count of open questions routes
attention; only the document's own text is acted on, and the tick still opens every
document it acts on. And it **fails toward the full walk**: any exit but 0 sends the
tick down the original per-file enumeration, so the digest can only ever collapse reads
that were owed, never narrow what a tick sees — the same direction as the idle probe. A
`tasks/` directory whose `project.md` is missing or unreadable poisons the walk (exit
2) rather than letting its tasks silently vanish, which would be the false-IDLE hole in
another coat. `SCHEMA.md` moved from "read every tick" to consult-on-demand in the same
change: a 56 KB re-read per tick bought nothing a section-level consult does not.

A closed project used to be deleted, so there was nothing to skip; `retain: true`
(SCHEMA.md) keeps a finished research project's folder as a reference surface, and the
only thing that makes that affordable is that the tick and `write-snapshot.sh` both
stop at its `project.md`. A done project costs one frontmatter parse. Filtering its
tasks out *after* reading them costs the full walk and buys nothing — the point is the
read that never happens. Nothing in a done project can need a tick: every task is
terminal, no PR is open, and it is not reopenable (new work starts as a new project).

<a id="step-2"></a>
### Step 2 — the approach critique's cost objection, answered

This clause used to end "don't run it on every draft (cost)" — and that sentence, next
to a `may`, is why in practice it ran on none. The trigger is the answer: it fires on
complex or heavily-inferred drafts only, so most drafts still get no critique. One apex
read of a spec is cheaper than the review rounds an under-specified criterion actually
costs — measured 2026-08-31 in this bundle's own work, a criterion that enumerated six
cases where it meant a whole class took THREE rounds of external review to converge on
what one adversarial read would have caught before any code existed.

The receipt mechanism (an `advisor_notes` entry, or an `advisor: approach critique — no
concerns` line in `answered_questions`) exists because refinement alone is a weak
guard: a mandatory dispatch with no marker turns every tick into a fresh apex-tier
session on the same draft.

<a id="step-3"></a>
### Step 3 — dispatch discipline, priced

**One agent per task.** Nothing can check the resume rule from the outside — the tick
holds it — and handing a second task to an agent that finished its first is how one of
them ended a day carrying 163k tokens across three unrelated jobs.

**Note the check-dispatch obligation at dispatch time** because the completion notice
is exactly what cannot be trusted: on 2026-08-28 two agents reported complete with
their work committed (one pushed) and no PR open.

**Why the cap is resolved per machine** (`instance.config.local.json` first): the cap
is this machine's capacity — three instances on one laptop each honouring a tracked
number is how 20 agents land on 11 cores (`SCHEMA.md`, "Per-machine config
overrides").

**Why the KB lines ride in every dispatch brief**: the instance `CLAUDE.md` states both
expectations, but carrying them in the brief is what makes the role agent act on them —
reuse prior work instead of re-researching, and fill the KB as a byproduct rather than
only via the cataloguer.

<a id="step-4"></a>
### Step 4 — verification, priced

**The parked-agent case (check-dispatch exit 1), measured 2026-08-28**: two agents
parked waiting on a background job and both reported as `completed`; the wall-clock
rule missed it (one parked at 16 minutes), the two-round review cap missed it (neither
reached review), and the completion notification *was* the failure. The work was
committed, one branch pushed — one message asking each to open the PR on what it had
recovered it.

**The two-round cap's price tag**: the pull request the cap comes from ran **eight**
review rounds, was closed unmerged, and with its siblings cost roughly **70% of a
week's account budget**. An unresolved disagreement costs the human one decision; an
unbounded review costs a week, and a cap that is only remembered is the state that
produced the eight.

**Why re-verification is never free**: a verdict already at the current head is reused,
never re-earned — re-reviewing an unchanged head reaches the same verdict by
construction and costs a full reviewer session, the same economics as the role agents'
"one review per PR" rule.

**Why HOLD is the default and the ASK fires only on the spend, measured 2026-08-31 on
four PRs (#85–#88)**: the external reviewer was rate-limited on all four and reviewed
all four properly within the hour, so an automatic `qa-reviewer` fallback would have
bought four deep-tier sessions for nothing. Holding costs nothing and never skips the
verification gate — it only defers it. And **why the exit code is the only classifier**:
the text the clearance script prints quotes untrusted comment text, and a second
reading of the tick's own would re-decide what the script already decided.

**Why a terminal refusal (exit 5) asks rather than falls back silently**: it is a fact
about every future PR, not this one, so working around it per-PR hides a broken
reviewer behind a per-PR fix and the human never learns it needs fixing.

<a id="step-5"></a>
### Step 5 — why worktree deletion is record-driven and pruning is report-only

The scan-based version of worktree removal destroyed three running agents' worktrees
before it was deleted, and the states are genuinely ambiguous — a branch with no
commits of its own is indistinguishable from a live dispatch that hasn't committed yet,
and a detached HEAD's commits are on no branch ref at all. The whole reason
`reclaim-worktree.sh` is allowed to delete is that the path comes from the task's own
record rather than from a guess, verified against the recorded branch, with every guard
refusing otherwise.

`prune-worktrees.sh`'s liveness check (`PRUNE_ACTIVE_MINUTES`, default 120) is a
best-effort backstop: an agent that is thinking, waiting on review, or running a long
command writes nothing for longer than the window and then looks idle. The tick's own
in-flight count is the primary guard, which is why the prune waits for it to be zero.

<a id="step-8"></a>
### Step 8 — curation, the queue, the board, and the lock

**Why the ledger close line is reconstructible, not descriptive**: "Refined two tasks,
dispatched work" is useless to the next tick; "dispatched task-004, task-007; reflected
task-002 merged" is what a successor reads instead of its own memory (see
`/pm-loop` step 2).

**Why the sync re-checks the tree instead of trusting the commit**: `commit-as.sh`
commits only the paths named — the entire point of the explicit-path rule — so a
sibling agent's edits are still sitting in the tree after the tick commits. "I
committed, therefore it is clean" is false here. And a tick that commits and never
pushes is invisible to the other clone, so on a shared bundle the work only
half-happened — the divergence grows quietly until someone hits a conflict.

**Why `🧰 grant` has a glyph of its own**: an `open_questions` entry that asks for a
tool, an install, a credential or an access grant — an agent hitting a capability gap,
per `CONVENTIONS.md` → "the middle rung NEVER BLOCKS" — reads identically to a question
otherwise, so a request to install a CLI looks like a question the human can dispose of
by typing a sentence, and it sits in the queue while they wait for a question that was
never being asked. The reply mechanism is the same; the glyph changes what the human is
being asked to *do*, not how they answer. A new verb is free; a new marker is not — the
glyph sits *after* the `* ` that `session-banner.sh` greps for.

**Why nothing invents a queue item**: a fabricated row sends the human to approve or
merge something that isn't there, which costs more trust than a missing row costs
time.

**Why the snapshot is written by the script and never hand-assembled**: hand-written
JSON drifts from the field allowlist, and that allowlist is a data-governance boundary,
not a format.

**Why the board renders to a local file** — the publish path's history — is
[#launcher-no-publish](#launcher-no-publish). The render's three load-bearing details:
`--standalone` is required because a file opened straight in a browser needs the
`<!doctype>`/`<html>`/`<head>`/`<body>` wrapper no host supplies any more; the path is
the one `watch-board.sh` already writes and `install.sh` already gitignores, so the
tick and the watcher refresh one board rather than two; and there is no markup flag to
pass — the kanban page was deleted and the renderer refuses the flag that used to
select it **by name**, so a stale command exits 2 and renders nothing rather than
quietly writing the other page. "Say the path, never that it is live": a rendered file
is only as fresh as the tick that wrote it, and its masthead timestamp is what says how
stale.

**Why a tick releases no lock, in every case.** The only lock a tick can be running
under is the launcher's, printed `adopted:` at Step 0.5, and the launcher releases it
when the tick's completion notification arrives — a signal the tick cannot see;
releasing earlier would free the lock while the loop still counts the tick as in
flight. A tick that held (exit 1), one handed a claim it could not attribute (exit 2),
and one refused as a resume (exit 4) all release nothing too: that lock belongs to the
tick still running, or to the human the script handed the decision to, and deleting it
re-opens the double-dispatch the lock exists to close. There is no longer a case where
a tick created its own lock — creating one is exactly what Step 0.5 refuses.
`scripts/tick-lock.sh release` stays unconditional and holds no identity, because it is
**the human's override**; it is not the tick's to run at the end of a tick.
