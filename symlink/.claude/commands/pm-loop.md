---
description: Start the Project Manager loop as a SERIAL, completion-driven loop (one tick at a time) in this control-panel instance repo
argument-hint: "[gap]  pause between ticks, default 10m  (e.g. 0m for back-to-back, 30m)"
allowed-tools: Bash(pwd), Bash(ls:*), Bash(scripts/tick-lock.sh:*), Agent, ScheduleWakeup, CronList, CronDelete
---

Start the **Project Manager loop** — but as a **SERIAL, completion-driven** loop:
**exactly one tick runs at a time.**

## Why this shape, and not `/goal` (v2 audit, 2026-08)

The looping **mechanism here is already first-party**: `ScheduleWakeup` is the same
primitive `/loop`'s dynamic mode uses. This command is a policy layer over it — the
serial guarantee, the instance-root preconditions, the in-flight check, and what a
tick may do — not a hand-rolled loop engine.

`/goal` was considered and does **not** fit. It terminates on a condition, while this
loop runs until a human stops it; its evaluator judges only what is in the transcript
and **calls no tools**, so it cannot see whether a PR merged; and it defers evaluation
while background work runs, which is the normal state of a tick that has dispatched
role agents. Wrong shape on all three counts — so the mechanism stays as it is.

## Why serial (do not revert to a fixed interval)

A LIVE tick can take a long time because it dispatches real role agents that
build/test/push, and those agents may share **one clone + one package store**. A
fixed-interval loop shorter than a tick (e.g. a naive `/loop 15m`) makes ticks
**overlap** → concurrent PMs double-dispatch the same task (two PRs for one slice)
and a sibling's package install corrupts an in-flight worktree. So this loop is
gated on **completion**, never on a clock.

**The guarantee is backed by a lock file, not by a session's memory.** The "one
tick at a time" serialization lives in *this* session's wakeup chain — and a
session's memory of "I dispatched" does not survive a compaction, a `--resume`, or a
human asking "what's next?". Measured 2026-08-29: two ticks ran concurrently for
about 34 minutes for exactly that reason, doing the same refinement work twice. So
**step 1 takes `.tick-lock` immediately before it dispatches**
(`scripts/tick-lock.sh acquire`), and a second session running `/pm-loop` against the
**same working tree** is refused rather than overlapping (double-dispatch,
shared-store corruption, racing pushes to the control panel's `main`). **Still run at
most one active `/pm-loop` per clone** — the lock catches the mistake; it does not
make two loops a good idea.

**The tick takes it too, because a resume never passes through this launcher.** Waking a
completed tick directly runs no `acquire` at all, so nothing is written and a dispatch
seconds later correctly reports the lock free — measured 2026-08-30, an hour after the
lock merged: a resumed tick and a dispatched tick ran at once, and the human spotted it
before the machinery did. So the tick takes the lock as well, in its own step 0.5
(`scripts/tick-lock.sh acquire --as tick`). **That does not move the lock out of here**:
your acquire is still the only one that happens *before* a dispatch exists, and moving it
into the tick alone would re-open the window this closes. Nor does a tick refuse the lock
you took for it — an unclaimed lock is precisely the dispatch it is — so nothing about
step 1 changes.

**It is a PER-CLONE lock and it is not a cross-machine one.** `.tick-lock` is a single
gitignored file in a single working tree, so it says nothing about the other human's
clone of a shared bundle — and it must not be read as if it did. Two loops from two
clones is the *design*, not the bug (next paragraph); what stops those two dispatching
the same TASK is `scripts/task-owner.sh`, never this file. The lock also bounds **PM
ticks only**: `maxAgentsInFlight` (`scripts/resolve-max-agents.sh`) is the other
concurrency limit and is untouched, so a held lock never blocks the role agents a tick
dispatches.

**A bundle shared by two humans is different, and is supported.** Each human has
their own clone on their own machine, with their own `reposRoot` and
`worktreeRoot`, so two of the three failure modes cannot arise: there is no shared
package store and no shared working tree. The third — double-dispatch — is what
`owner` prevents, since each loop dispatches only its own human's tasks
(`scripts/task-owner.sh`; see the guardrails below). What remains is racing pushes
to the bundle's `main`, which is an ordinary git conflict on ordinary git files,
not corruption: pull before you push. **The tick now does that itself, not as a
human habit** — step 0 pulls `--rebase` (never `--autostash`) before it re-derives anything, deferring that pull to step 8 when tracked files are dirty
from disk, and step 8 pushes right after it commits, both conditioned on the
bundle having a remote at all; a pull conflict stops the tick and reports the
contested paths rather than resolving them, and nothing here ever force-pushes.
See the guardrails below. **Two loops against one clone is still the
bug; two loops against one bundle from two clones is the design.**

**Diagnosing it: suspect your own second tick first.** Interleaved writers on one
control panel read like another session in the bundle, and usually aren't — a tick
dispatched after misreading step 2's signal produces the same symptoms from inside
one session. Two things that look like evidence and are not: **author names**
(`commit-as.sh` sets the role per commit, so one process batching commits leaves
three roles at the same second), and a **tick's own account of a collision it is
part of** — check `git reflog show main`, which is per-clone and therefore answers
whether `main` actually moved backwards, before reporting corruption.

## Preconditions

**Three checks, and the list is closed** — see "The launcher reads nothing else".

1. Must run from a **control-panel instance root**, so the `.claude/agents` role
   agents, the target-repo clones, and `gh` load. **Detect** the instance root by
   confirming `SCHEMA.md` + `.claude/agents` + `instance.config.json` exist in the cwd; if
   not, tell the user to `cd` into the instance and stop. (Do not hardcode a path —
   instances live under different group folders.)
2. **Kill any fixed-interval PM cron** from an older approach: `CronList`, and if a
   job's prompt is `run the project-manager agent for one LIVE tick`, `CronDelete`
   it — that job is the overlap bug. Do **not** create a cron here.

### The launcher reads nothing else

**`instance.config.json` is not an exception, and this section used to imply it was.** An
earlier draft of this trim kept a precondition telling the launcher to read `reposRoot`
and `org` — values the launcher never uses. The TICK uses them, and the tick reads the
config itself. A precondition the tool contract forbids is worse than a missing one: it
reads as licence to widen `allowed-tools`, which is the whole thing this trim exists to
prevent.

Do **not** read task documents, `log.md`, the tick ledger, `AWAITING.md`,
`SNAPSHOT.json`, a worktree listing, `git status`, `git log`, `gh repo view` or
`gh pr list` here — not the whole thing, not a summary, not "just to orient". **The
tick does every one of them** (`.claude/agents/project-manager.md`, steps 0–1), which
is why `allowed-tools` above lists no reader beyond `pwd`/`ls` and the one exception
named at the end of this section.

Two reasons, and the second is the one that matters. The human ran a command, not a
briefing, so nothing should scroll before "tick dispatched". And every byte read here
lands in the **main session's** context — the one context this loop has to survive on
for hours across many ticks — while the tick is a backgrounded agent with its own
context, where a full state read is free and is discarded when it ends. The
launcher's answer is thrown away the moment it dispatches either way, so a state read
here buys nothing and is paid for twice.

**This is not "print less".** Collapsing, quieting or redirecting the output would
keep every token and lose the trail. The work does not belong here at all.

**The one exception, named on purpose: the tick lock.** `scripts/tick-lock.sh acquire`
reads `.tick-lock` and writes it in the same create, and step 1 runs it immediately
before it dispatches. It is an **exception, not a relaxation**, and it earns the
carve-out on this section's own argument rather than in spite of it: the cost that
matters here is what lands in the main session's context, and on the normal path this
lands **nothing** — `acquire` prints not one byte when it takes the lock, and speaks
only when it refuses, which is the one case worth the tokens. The economy argument is
untouched.

**No other reader may be added by analogy, and this is not a precedent.** `log.md`,
the tick ledger, task documents, `AWAITING.md`, `SNAPSHOT.json`, a worktree listing,
`git status`, `git log`, `gh repo view` and `gh pr list` all stay forbidden here; the
list above is still closed and the tick still does every one of them. Two things make
this exception different from all of them: it is a **write** the launcher is the only
one able to make (only the launcher knows "I am dispatching right now" — the tick
learns it seconds later, which is the window that let two ticks overlap), and it
returns an exit code rather than content. Nor does `allowed-tools` grant a reader: it
grew by exactly `Bash(scripts/tick-lock.sh:*)`, one script that touches one gitignored
file. And **never call `scripts/tick-lock.sh status` before `acquire`** — the check and
the write are deliberately one operation, and looking first would rebuild the very race
this closes.

### Why there is no publish grant, and no publish step

`allowed-tools` above is now nothing but the preconditions, and it used to carry one more
grant: the publishing tool, added so a tick could push the board to a hosted page, plus a
**step 2c** that finished the job whenever the tick could not. **The grant and the step
are both deleted**, and the reason is worth keeping, because it is not "we simplified".

Publishing was **account-scoped**. Exactly one account could ever update a given page, no
share level granted a second human write access, and the page vanished from under its own
owner the moment they switched Claude accounts — which is what actually happened. So the
mechanism could not deliver the one thing it existed for, and a grant that buys a step
that cannot work is a widened tool contract bought for nothing.

**The board is now a local file**, rendered by the tick with `scripts/build-board.sh
--standalone` into the gitignored `.board-live/board.html` — see
`.claude/agents/project-manager.md` step 8, which renders as its last act and reports the
path in one `BOARD: rendered <path>` line — surfaced to the human with the rest of the
tick's report, and printed again at the start of every session by the
`show-board-link.sh` hook. Rendering needs `Bash`, which the tick already holds and this
launcher deliberately does not, so there is nothing left for the launcher to do about the
board at all: no grant, no step, and no page body landing in **this** session's context,
which is the one thing the section above exists to protect.

## How the serial loop works

Parse `$ARGUMENTS` as the inter-tick **gap** (default **10m**). Then:

1. **Take the lock, then dispatch — in that order, with nothing in between.**
   Resolve the tick's model first (below), then run

       scripts/tick-lock.sh acquire --agent project-manager

   and act on its exit code. **The check and the write are that one call**, which is
   the whole point: the tick's own ledger check (`project-manager.md` step 0.5) runs
   *inside* the tick, after step 0's `git pull` and its re-derivation, so between your
   dispatch and its ledger entry there is a window of seconds to minutes in which the
   ledger truthfully reports nothing running. A second tick dispatched anywhere in that
   window is exactly the 34-minute overlap of 2026-08-29. `acquire` closes it by
   creating the file with `O_EXCL`, so there is no read-then-write for anything to
   interleave with — and **nothing may sit between the acquire and the spawn either**:
   no `git pull`, no state read, no other tool call.

   - **0** — the lock is yours, and it printed nothing. **Spawn the tick now**, as the
     very next thing you do.
   - **1** — HELD: a tick is in flight. Do **not** dispatch. Schedule the gap
     (step 3, `noop: true`) and skip, exactly as step 4 does.
   - **2** — the lock is stale, dated in the future, or unreadable, and the script has
     already printed its timestamp and the agent it names. Do **not** dispatch, and do
     **not** delete it: put what it printed in front of the human and stop until they
     answer. Both silent options are excluded on purpose — silently deleting it
     re-opens the double-dispatch, and silently treating it as live is the pressure
     that makes a stalled loop tempting to override. `scripts/tick-lock.sh release` is
     the human's answer, not yours.
   - **3** — it could not write the lock at all. Report that and stop; a guarantee
     nothing can keep is the failure this replaces, not a reason to dispatch anyway.

   If the spawn itself fails to start, run `scripts/tick-lock.sh release` before you
   report — a lock with no tick behind it is the stale case, arriving hours early.

   The tick itself: spawn the `project-manager` agent
   (`subagent_type: project-manager`) for ONE LIVE tick (background), with the
   standing guardrails below. **Brief it with the gap and the guardrails, not with
   state** — it reads the bundle, `git` and `gh` itself, so there is nothing for you
   to look up first. **Run the tick on the orchestrator's configured model:**
   resolve it with `scripts/resolve-model.sh project-manager`, which applies
   `roleTiers` (default `deep`) → an alias via `models`
   (default `deep` → `opus`), and pass that as the tick's model. If `models`/`roleTiers`
   are absent, inherit the session model. (The top `apex`/`fable` tier is reserved for
   the rarest, deepest reasoning — the `plan-architect` critique — not the routine tick.) A LIVE tick refines drafts, dispatches `ready` tasks,
   advances/reflects PRs, reports finished worktrees, proposes closing completed
   projects (all tasks terminal), and — **after reflecting merges** — may dispatch
   the `cataloguer` to refresh `knowledge/` from the merged work (throttled to one
   per tick; skipped on idle/trivial ticks).
2. **Wait for it to finish.** Do **not** start another tick while one is in
   flight. **That tick's `<task-notification>` is the only valid "finished"
   signal** — no tool listing and no amount of elapsed time substitutes for it. A
   tick that reads as complete or idle in a status listing may still be running:
   the agent resumes and the same task-id notifies again, so one that has looked
   done for *hours* is not done until its notification arrives. Don't poll for a
   verdict; a quiet repo proves nothing either (a tick holding for its own
   subagents is quiet by definition).

   **When that notification arrives, release the lock** — run
   `scripts/tick-lock.sh release` before you schedule the gap. That is the only place it
   is released in the normal path, and releasing it on anything weaker than the
   notification (a status listing, elapsed time, a quiet repo) hands the next tick a
   dispatch the running one has not finished. A loop that dies before it releases leaves the lock to age out
   into step 1's case 2, where a human sees it — which is the intended failure, not a
   leak.

   **After a compaction, that memory is gone — and the answer is still not yours to
   look up.** This loop is long-lived and its context gets summarised; the in-flight
   set is answered from session history, which is exactly what compaction discards.
   That is what `.tick-lock` is for, and you consult it in exactly one way: **by taking
   it in step 1**, never as a separate look. **Do not go read the disk here to
   reconstruct anything else.** Dispatch a tick and let it
   answer: re-deriving the in-flight set from disk is one of the tick's opening steps
   — right after it syncs the bundle — which it takes whether or not you ask — the
   root `log.md` tick ledger (whose open-with-no-close entry is the only thing on
   disk that distinguishes "dispatched, waiting" from "never ran"), then the task
   documents' own `status:`, then `git log` / `gh pr list`, each outranking anything
   anyone remembers. See `.claude/agents/project-manager.md` step 0.5, which owns
   that property in full (step 0 is the bundle sync that now runs ahead of it).
   A tick that finds an open entry **reports it and holds** rather than
   re-dispatching, so the failure this protects against — re-dispatching a task
   sequence that already finished, the most expensive failure observed in loops of
   this shape — is caught one context deeper, where the read is free. Such a tick is
   a finished tick: schedule the gap as usual (step 3) and surface what it says.
2b. **Ask the advisor, if this instance has one.** Two conditions, both from
   `instance.config.json`, and **absence of either means skip this step silently** —
   no message, no warning, the tick is over. Never treat absence as an error.

   - `"advisor"` must appear in `roles`. Not listed ⇒ the instance does not want one.
   - `.claude/agents/advisor.md` must exist. Deleted ⇒ same answer, and the file is
     the off switch that works even on an instance whose config you cannot edit.

   Its model comes from `scripts/resolve-model.sh advisor` (`roleTiers.advisor` through `models`), exactly like
   every other role. **Absent ⇒ `light`**, the cheapest tier — an observer that costs
   as much as the work it observes is not worth running.

   Dispatch it once, read-only, with the tick's summary: what it promoted, what it
   dispatched to whom, what it closed, and the task documents it touched. It replies
   `ADVISOR: clear` (the normal case — say nothing, move on) or `ADVISOR: concern`
   followed by one line of `<task-path> --- <question>`.

   **YOU ADJUDICATE IT, AND THE HUMAN IS THE LAST RESORT — not the first.** The
   advisor runs on the cheapest tier; you run on `deep`. Read the documents it cites
   and decide:

   - **It does not hold** ⇒ drop it silently. No fold-in, no report, no arguing with
     it in the log.
   - **It holds and you can act on it** ⇒ act, and record it in `answered_questions`
     prefixed `advisor:` so the provenance survives. **The human is not involved.**
   - **It holds and you genuinely cannot decide** — a trade-off only the owner can
     make, a missing fact no document contains ⇒ *then* escalate: copy it into that
     task's `open_questions` prefixed `advisor:`. That is the one path to a human.

   A concern you have not triaged yet goes in `advisor_notes` (see `SCHEMA.md`), which
   is **deliberately not a gate**: it does not block promotion, does not put a row in
   `AWAITING.md`, and no validator checks it. Triage the list on the next tick.

   **Why the asymmetry matters.** The owner is one person and the loop parallelises
   across tasks, so a mechanism that routes every concern to a human makes the human
   the bottleneck and the advisor a net loss. Escalating is the exception you must
   justify to yourself, not the default. If you find yourself escalating most
   concerns, the advisor is miscalibrated — say so in the tick report rather than
   forwarding the noise.

   Two consequences worth being explicit about, because the shape is easy to get
   backwards. **A cheap model never steers an expensive one**: the advisor has no
   channel to `software-engineer` or anyone else, so nothing it says can redirect work
   in flight — its only possible outcome is a question a human answers. And **the
   filter is a deep model reviewing a light one**, not the reverse, so a false
   positive costs one cheap dispatch and none of the human's attention.

   **It never blocks.** A verified concern does not undo the dispatch, reverse a
   promotion, or delay the next tick. If the advisor errors, times out, or answers in
   any other shape, ignore it and continue — an observer that can stall the loop is
   worse than no observer.

3. **On completion**, schedule the next tick after the gap: call `ScheduleWakeup`
   with `delaySeconds` = the gap, and `prompt` = `/pm-loop <gap>` so this skill
   re-enters and dispatches the next tick. (If gap is `0m`, dispatch the next
   tick immediately instead of scheduling.)
   **Always pass `noop` and `reason`.** `noop: true` when the tick changed nothing
   (no dispatch, no status change, no `AWAITING.md` edit); `noop: false` when it did.
   **A board refresh or a render is not a change.** The snapshot and the page are
   derived from documents that did not move, so a tick whose only act was re-rendering
   them is still `noop: true`. Every tick refreshes the board, so counting it would pin
   `noop` to `false` forever, retire the streak line below, and hand the human back the
   scrolling idle loop the streak exists to prevent.
   Consecutive `noop: true` ticks collapse into one streak line in the human's
   terminal instead of one wakeup line each — an idle loop should be nearly silent,
   and this is the whole difference between a loop you leave running and one you
   turn off because it scrolls. `reason` is one specific sentence about what this
   tick is waiting on ("holding for qa-reviewer on #214"), not "waiting".
4. **When `/pm-loop` re-fires from that wakeup:** "still in flight" means **this
   session dispatched a tick and has not yet seen its notification** — answered from
   this session's own history, which is the cheap answer and usually the right one.
   **It is no longer the only answer, and that is what the lock changed**: session
   history is precisely what a compaction discards, so step 1's `acquire` is what
   actually decides. If memory says one is still in flight, reschedule the gap and
   skip (never overlap); otherwise go to step 1, whose `acquire` refuses the dispatch
   by itself if a live tick is holding the lock. Query nothing else here — the lock is
   the launcher's one disk read, and it makes it by taking it.
5. **Stop** when the user says so (e.g. "stop the PM loop"): dispatch no further
   ticks and cancel any pending wakeup. There is no cron to delete. **Release the lock
   only if THIS session took it and its tick has since finished** — otherwise leave it
   exactly where it is. `release` is unconditional by design (it is the human's
   override), so it cannot tell your lock from a sibling's: a session that skipped at
   step 1 because another loop held the lock would delete a **live** holder's lock and
   re-open the double-dispatch. And if you dispatched but are stopping before the
   notification arrives, say so and leave the lock — it ages out into step 1's case 2,
   where a human sees it, which is the intended failure.

This guarantees **at most one PM tick at any moment**, with a `gap` pause between
ticks, regardless of how long a tick runs.

## Standing guardrails for each tick dispatch

- Honor the human gates **per the owning project's `autonomy`** (default `gated`): never
  promote `draft → ready` and never merge. A project may delegate a gate **only** where
  `AUTONOMY.md` exists at the bundle root and defines the mode — then follow that file
  exactly, including its preflight. **No `AUTONOMY.md` ⇒ every project is `gated`** and
  the field is inert. See the PM agent's "Authority boundaries". When `autonomy` is unset,
  act as `gated`.
- Reconcile doc `status:` against live `gh`/`git` before acting; act only on deltas.
- **Dispatch only this clone's human's work.** On an instance shared by more than one
  human, `scripts/task-owner.sh <task-path>` decides, and **exit 0 is the only
  clearance** — exit 1 (someone else's) and exit 2 (cannot answer) both refuse.
  It is **two operations**: **resolve** the task's owner — task `owner:` → project
  `owner:` → **tracked `defaultOwner`** → nobody (unowned) — then **compare** that
  owner against this clone's `ownerGithubUser`, which answers "who am I?" and is never
  itself a source of ownership. `defaultOwner` lives in `instance.config.json` and is
  **not** locally overridable: both clones must agree on it, or an unowned task is
  dispatched twice. `ownerGithubUser` comes from `instance.config.local.json`
  (gitignored, per-machine) else `instance.config.json`.
  **With none of them set, every task is this clone's**, so a single-human instance
  behaves exactly as before and absence is never an error. It gates
  **dispatch only** — never promotion (`draft → ready` stays the human's, either
  human's), never a commit, never the KB. And it is **not a lock**: it stops two
  loops dispatching the same task, not two loops running at once. `AWAITING.md` is
  the one artifact that narrows to this human's decisions; the tick report still
  names the other human's work. See `SCHEMA.md` → "Ownership on a shared instance".
- **The tick syncs the bundle around its own work — when there is a remote to sync
  with.** It pulls `--rebase` — never `--autostash`, which can exit 0 with a conflicted tree — before it re-derives anything from disk, and defers that pull to step 8 rather than halting when a sibling agent has the tree dirty
  (step 0) and pushes right after it commits (step 8); a bundle with no `origin`
  does neither, silently, which is the single-machine case behaving exactly as it
  always has. A pull conflict **stops the tick**: it aborts the rebase, writes
  nothing, and reports the conflicting paths — a tick never resolves contested
  state between two humans on its own. And nothing here ever force-pushes a shared
  bundle.
- **An answered question is MOVED, never deleted.** Folding an answer in shifts that
  `open_questions` entry into the task's `answered_questions` list — one flat line,
  `<ISO 8601> · <the entry verbatim>` (see `SCHEMA.md`). `open_questions` must still
  **empty**, because that is the signal promotion keys on; an entry left in both lists
  blocks the draft forever. `answered_questions` is a human audit record — nothing reads
  it — and it carries **no customer PII**, since it persists for the life of the repo.
- Concurrency cap: **at most `maxAgentsInFlight` role agents in flight** — resolve it with
  `scripts/resolve-max-agents.sh`, which reads `instance.config.local.json` first and the
  tracked `instance.config.json` second because the cap is **this machine's** capacity
  (`SCHEMA.md`, "Per-machine config overrides"); it prints nothing and exits 1 when
  neither file sets the key, and you fall back to 5 then. Each agent must use its own
  worktree under the instance's `worktreeRoot` (from `instance.config.json`, never
  inside the synced `reposRoot`; if the key is absent, `<reposRoot>/_wt`)
  + a **private package store** (e.g.
  `pnpm install --store-dir <worktree>/.pnpm-store`) and **push early** — never two
  installs against the shared store at once (see `.claude/agents/project-manager.md`).
- A LIVE tick may also dispatch the **`cataloguer`** to refresh the KB after
  reflecting merges — read-only on product repos, writes only to `knowledge/`. It
  **counts toward the `maxAgentsInFlight` cap**, is **throttled to one per tick**, and (like every
  tick action) **never promotes or merges**. Skipped on idle/docs-only/trivial ticks.
- Commit hygiene in this repo: stage only your own changed files by explicit path
  (never `git add -A`); commit via
  `scripts/commit-as.sh project-manager "<msg>" -- <path>...` — naming the paths is
  required for agent roles, so a sibling agent's staged files can't land under yours;
  never `--no-verify` in target repos.
- **Worktree hygiene.** `scripts/prune-worktrees.sh` (≤ once per tick) **reports
  only — it never deletes anything.** It scans `worktreeRoot` plus the legacy
  `<reposRoot>/_wt` and classifies each worktree, printing `git worktree remove`
  commands for a human. Surface its `REMOVABLE` and `RECLAIMABLE` sets on the board
  rather than acting on them yourself. **Run it only when your in-flight count is
  zero** — a report that races a live dispatch misclassifies it.
  The script's `PRUNE_ACTIVE_MINUTES` mtime veto (default 120) is a backstop, not a
  substitute: an agent that writes nothing for longer than the window looks idle, so
  your in-flight count stays the primary guard.
- **Project close is human-gated.** The PM only *proposes* closing a project (all
  tasks terminal) via the 🔴 board; the human confirms (or runs `/close-project`).
  Closeout removes the folder (`git rm -r`) — git history + KB are the record, there
  is no archive — **unless `project.md` carries `retain: true`**, which keeps the
  folder, frozen and pruned, as the record (`SCHEMA.md`). Either way the folder step is
  `scripts/close-project-folder.sh <slug> --apply`, never a hand-written `rm`. Never
  close autonomously.
- Return a tight summary: live-vs-docs deltas, dispatched/reflected, in-flight
  count, and what awaits the human (approvals / answers / merges).

## Notes
- One serial loop per session — and **one active loop per clone** (see "Why
  serial"): don't start a second session looping the same working tree. Two humans
  sharing one bundle from two clones is a different case and is supported — see
  there. To change the gap: stop, then `/pm-loop <gap>`.
- **The dispatch lock is `.tick-lock` at the instance root** — gitignored, per clone,
  written by step 1 and released in step 2 by the session that took it. The tick takes it
  as well (its step 0.5, `--as tick`) and records that it is running under it in
  `.tick-lock.claim` beside it, which is how a dispatched tick tells your lock from
  another tick's; a tick releases only a lock it created itself.
  `scripts/tick-lock.sh status` reads it
  without touching it (for a human, never for this launcher), `release` clears it, and
  `TICK_LOCK_STALE_MINUTES` (default 120) sets how old a lock has to be before step 1
  stops waiting on it and asks. A missing lock is never an error: the loop dispatches
  exactly as it always did.
- **Starting the loop prints a handful of lines, not a screen**: the preconditions
  when one fails, one line naming the gap, and that the tick is dispatched. If a
  start scrolls the terminal, the launcher did work that belonged in the tick — move
  it there (see "The launcher reads nothing else"); do not quiet it in place.
- A tick with nothing to do is a fast no-op — the gap keeps idle cycles cheap.
- Each tick refreshes `AWAITING.md` — the queue of what a human decision unblocks —
  **only when that file already exists**; a `SessionStart` hook surfaces its
  "🔴 Awaiting you" items at startup. Deleting the file turns the queue off for
  good (the loop never recreates it); `touch AWAITING.md` turns it back on.
- Each tick also refreshes `SNAPSHOT.json` (via `scripts/write-snapshot.sh --quiet`,
  at the end of the tick) — the derived, gitignored feed for the cross-instance board
  that `scripts/build-board.sh` renders as a page, `scripts/print-board.sh` prints in a
  terminal, and `scripts/watch-board.sh` keeps live locally. Same rule and same off
  switch for all three: the writer
  rewrites the file **only when it already exists** and never creates it, so
  `rm SNAPSHOT.json` takes this instance off the board for good and
  `touch SNAPSHOT.json` puts it back. Which instances a board shows comes from
  `boardInstances` in `instance.config.json`; **if that key is absent or empty, the
  board is just this instance.**
- **The board page is re-rendered by the same tick, to a local file** —
  `scripts/build-board.sh --standalone --out .board-live/board.html`, the gitignored path
  `scripts/watch-board.sh` also writes. It is **per machine, not per account**: nothing is
  published anywhere, and the other owners' projects appear on it as a section read from
  the tracked task documents at this clone's git `HEAD`. `board: false` in
  `instance.config.json` ⇒ **no render and no mention**; absent or `true` ⇒ it renders and
  the tick reports the path. That is the same key `install.sh` reads at stamp time to
  decide whether `SNAPSHOT.json` exists at all, read again at tick time — one switch, two
  readers. The page is only as fresh as the last tick, which its masthead timestamp
  states; `scripts/watch-board.sh` is the live view.
