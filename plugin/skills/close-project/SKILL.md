---
name: close-project
disable-model-invocation: true
description: Close a completed project — final KB consolidation, log the closeout, roll up status, then remove the project folder (git history + KB are the record; no archive) — or, with `retain: true`, freeze and keep it. Human-gated; run once a project's tasks are all done/cancelled.
argument-hint: <project-slug>  [--dry-run] [--force]
allowed-tools: Bash(date:*), Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/commit-as.sh:*), Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/close-project-folder.sh:*), Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/decision-stamp.sh:*), Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/prune-worktrees.sh:*), Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/validate-bundle.sh:*), Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/build-kb-index.sh:*), Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/papercuts.sh:*), Bash(grep:*), Bash(git rm:*), Bash(git add:*), Bash(git log:*), Bash(ls:*), Read, Write, Edit, Glob, Agent
---

**Close a completed Project.** This is the human-triggered form of the closeout the
PM only ever *proposes* (it never closes a project autonomously). Use it when a
project's work is finished: it consolidates any remaining knowledge into
`knowledge/`, records the closeout in the log, rolls up status, and **removes the
project folder**. The bundle's `git` history and the KB are the durable record —
there is **no `archive/`**.

**Unless the project carries `retain: true`** (`project.md`), in which case the folder
is **kept** — frozen, pruned of working files, and committed. Retention is
research-shaped: a build project's output is merged PRs that live in the product
repo's history, while a research project's output *is* the folder. Everything else
about closeout is identical, and the project still ends `status: done`. See
`SCHEMA.md` → "Project & objective completion" for the full contract.

**This file is a LAUNCHER and a BRIEF, and the split is the point.** You establish two
preconditions and dispatch; one background agent does steps 1–7 in a context that is
thrown away. Two decisions never leave this thread, and they are named below.

> **Generic plugin file** (ships inside the `ai-bridge` plugin, never copied into a bundle). Reads the
> bundle's own `SCHEMA.md` (see "Project & objective completion") and
> `instance.config.json` — never hardcode org/repo/path literals here.

## Inputs
`$ARGUMENTS` = the project slug (the `projects/<slug>/` directory name), plus:
- `--dry-run` — report what closeout *would* do; change nothing.
- `--force` — proceed even if some tasks are **not** terminal (records which). Use
  sparingly — normally every task should be `done`/`cancelled` first.

Pass both flags on to the agent verbatim; neither changes what you may look at.

## Preconditions

**Two checks. What the launcher may look at is an ALLOWLIST of two** — see "The launcher
reads nothing else"; anything not on it belongs to the closeout agent. Both checks below
are on it.

1. **A slug.** Take it from `$ARGUMENTS`. If none was given, `ls projects/` for the
   **directory names**, offer them, and ask which to close — never open one to judge
   whether it is closeable. That judgement is the agent's step 1, which refuses a project
   whose tasks are still live.
2. **The folder exists.** Confirm `projects/<slug>/` is there; if it is not, stop and
   report. Nothing inside it is read here.

### The launcher reads nothing else — an ALLOWLIST of two, and everything else is the closeout agent

**Everything the launcher may look at — this bundle, git, the GitHub API, the network,
the machine — is exactly these operations:**

1. **The slug** — `$ARGUMENTS`, or `ls projects/` for the directory names when it is
   absent: precondition 1 above, and nothing wider.
2. **The folder probe** — that `projects/<slug>/` exists, which is precondition 2 and
   the whole of it.

**Anything that is not one of those is the CLOSEOUT AGENT or a SUBAGENT.** That is the
whole rule, and it is a **category**: a launcher may establish that the thing it is about
to dispatch on **exists**, and nothing about what it *is*. A directory name is existence;
anything a document, the history or the host would have to answer is state, and state is
the agent's. So there is no list to keep current and nothing to add to when the world
grows a new kind of source. **And here is the disposal, so you are told what to do and
not only what to stop:** dispatch the agent and let it read — the brief below is every
one of those reads, in a context that is discarded when it ends — or, when a question is
genuinely not the closeout's, hand it to a **background subagent** and let that context
pay. Never here, and never before the agent or instead of it: not the whole thing, not a
summary, not "just to orient".

**A further entry is the regression, not an exception** — the list closes over a
**category** and not over a count of nouns. **No other reader may be added by analogy.**
An enumeration of forbidden sources is the shape that already failed: it said it was
closed, it was, and it rotted the day the expensive reads were a category it had never
named.

**One contract, two launchers.** `/ai-bridge:dispatch` states the same rule under the
same heading (`skills/dispatch/SKILL.md` → "The launcher reads nothing else"). They are
one contract in two places; change the shape here and change it there, or a reader learns
two different rules from two commands that do the same thing. Note what the rule does
**not** rest on: `allowed-tools` is documentation, not enforcement — this launcher's
grants are the closeout's, unchanged by the split, and what closes it is the allowlist
above plus the harness that counts it.

Why: every byte read here lands in the **main session's context** — the one this human is
working in for the rest of the day — while the agent's is disposable.

### What the split buys, measured rather than claimed

**On this bundle, 2026-09-08:** the `ai-bridge-2x` closeout took roughly
**a dozen main-thread tool calls** before the folder step, and `prune-worktrees.sh`
alone returned **29 `REMOVABLE` lines** the main session had no use for. That is what
moves into a context that is thrown away.

## Dispatch the closeout — one background agent for steps 1–7

Spawn **one fresh `ai-bridge:project-manager`**, in the background, briefed with "The
closeout agent's brief" below verbatim, the slug, and any `--dry-run`/`--force` flag.
Namespace it — a bare agent name does not resolve. Resolve its model with
`${CLAUDE_PLUGIN_ROOT}/scripts/resolve-model.sh project-manager`. **Never wake a completed
closeout agent with a message** — dispatch a fresh one.

**A closeout is NOT a tick, and the brief must say so.** It runs once, it is not
idempotent, and it takes **no tick lock** — the tick's entry-time ledger/lock dance is
skipped, because a closeout that adopted the tick's re-entry logic would either deadlock
behind a live tick or re-run a removal that already happened. For the same reason, do not
start a closeout while a tick is in flight: both write `log.md`, the KB and task
documents in one working tree. Wait for the loop's notification, or stop the loop first.

**Two decisions never leave this thread.** They are the agent's escalation path and never
its call:

- **Step 4** — *all of this objective's projects are terminal — set it `achieved`?*
- **Step 6** — *the source task is `cancelled`, not `done` — is the dependent work still
  viable?*

**Both are settled BEFORE the agent writes anything.** The brief's **pre-flight** tests for them
first and, if either fires with no answer in the brief, the agent reports and stops
having written nothing. Answer here, then dispatch a **fresh** agent carrying the answers
— an escalation from the middle of a closeout would strand a half-written tree that the
next tick reads as real work.

**Authority — identical whichever agent runs it.** The closeout agent **never promotes a
task `draft → ready` and never merges a pull request** (`SCHEMA.md` → "Two human
authorities"); running in the background changes neither. It also **never commits as the
human**: the closing commit is authored `project-manager`, as the PM's own closeout step
is, while the log entry still names the human who decided.

## The closeout agent's brief — steps 1 to 7

> **You are the closeout agent.** These seven steps are yours; the launcher that spawned
> you did the two checks in "The launcher reads nothing else" above and nothing else, so
> read what you need from disk rather than from your brief.

> **`--dry-run` short-circuits every mutation.** Do step 1 (read-only checks),
> then for steps 2–7 *report exactly what you would do* — do **not** dispatch the
> cataloguer, run `build-kb-index.sh` without `--check`, edit
> `log.md`/`index.md`/`project.md`/objective, prune worktrees, or commit/remove anything.
> Only a run without the flag actually changes state. Step 7's
> `${CLAUDE_PLUGIN_ROOT}/scripts/close-project-folder.sh <slug>` **without `--apply`** is the one thing you
> may run: it is report-only by design and prints the exact removal or prune it would
> perform, which is a better dry-run report than a description of one.

0. **Both escalations, before any write — the pre-flight.** This step is the split's, and steps 1–7 below
   are the closeout as it always was. Read `project.md` and every `tasks/*.md`, the
   project's objective, and — unless the project is `retain: true`, which skips step 6
   entirely — the inbound refs step 6 lists. Then answer two questions: would step 4 ask
   about the objective, and does step 6 find a ref whose source task is not `done`?
   **If either fires and your brief carries no answer to it, write nothing — report the
   question and stop.** The human answers in the main thread and dispatches a fresh
   closeout carrying the answer. Neither is ever yours to decide.

1. **Resolve & check.** Confirm `projects/<slug>/` exists (else stop and report).
   Read its `project.md` — including whether it carries `retain: true`, which decides
   step 7 — and every `tasks/*.md`. Unless `--force`, verify **all** tasks are terminal
   (`done` or `cancelled`); if any are still open, **stop** and list the non-terminal
   ones — the project isn't ready to close.

   **Under `--force`, set every non-terminal task to `cancelled`** with a one-line
   reason in its body (`# Notes`: "cancelled at closeout 2026-08-26 — the project was
   closed with this task unfinished"). Use the **existing** terminal status; there is
   no separate "closed unfinished" value and none is to be invented. A project must
   not close leaving tasks in a live status: the folder either goes away or stays as a
   record, and both are lies if a task still reads `in-progress`.

2. **Consolidate knowledge — including the supersede pass.** Dispatch the `cataloguer`
   (subagent) for a final pass: capture/link any remaining durable `Finding`s from this
   project, refresh the `Service`/`Runbook` docs it touched, and cross-link them. For a
   **research** project, decide with the user which `deliverables` graduate into
   `knowledge/` and have the cataloguer fold them in. Skip only if the project produced
   nothing durable (trivial/superseded) — say so.

   **It nests under YOU, not under the main session** — you dispatch it, you read its
   report, and the consolidation pass plus every read it makes stays in a context that is
   thrown away with yours.

   **Then supersede what this project made untrue** — brief the cataloguer to run it, per
   `SCHEMA.md` → "Superseding a Finding": every `Finding` the project contradicted gets
   `status: superseded`, `superseded_by:`, a dated section naming the replacement, and
   `supersedes:` on the new one. This is the moment the KB would otherwise keep a stale
   `current` row forever — closeout is when someone last knows which findings the work
   overtook.

   **And brief it to run the papercuts pass** (`cataloguer` step 5): closeout is when
   the project's papercuts are still legible. It returns one proposal per surface —
   create each as a `draft` task (never `ready`), then mark the entries processed:

   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/papercuts.sh pass
   ```

   Skip only if `papercuts.sh report` finds nothing; say so if you do.

   Finish with the index, which is derived rather than curated:

   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/build-kb-index.sh
   ${CLAUDE_PLUGIN_ROOT}/scripts/build-kb-index.sh --check
   ```

   Zero errors before step 7 commits, and `knowledge/index.md` goes in that commit by
   explicit path.

3. **Record the closeout.** Get a timestamp (`date -u +%Y-%m-%dT%H:%M:%SZ`) and the
   login closing it (`${CLAUDE_PLUGIN_ROOT}/scripts/decision-stamp.sh --self`). Prepend
   a dated **Project closed** entry to the root `log.md` (newest-first), stamped
   `by <login>`, naming the
   project, its merged PR(s) as `[<repo>#<n>](url)`, the `Finding`(s) it produced
   (KB links), and a one-line outcome. **Closing is a human decision and the entry is the
   only place it is ever written down**, so it names the human the same way a promotion
   and a preview approval do (`SCHEMA.md` → "Decisions name the human"); `<unknown>` goes
   in as-is rather than being left out. The login is the human's, never yours — you are
   recording their decision, not making one. (The closing commit SHA is added by step 7's
   commit — reference it as "removed in the closing commit".)

   **For a retained project, say so and name what was pruned** — step 7's command
   prints a ready-made `log.md fragment` line for exactly this: which directories went
   and what was kept. Without it a reader six months out cannot tell a deliberately
   partial folder from a damaged one. Run step 7 first if you want the fragment in
   hand; the entry is committed in step 7's commit either way.

4. **Roll up status.** Set `project.md` `status: done`. Remove the project's bullet
   from the active `## Projects` list in the ROOT `index.md` (derived and gitignored —
   edit it, but it is not part of step 7's commit). **For a retained project, also
   refresh `projects/<slug>/index.md`** — it is that folder's front door, the file that
   makes a retained project findable, and it IS committed (step 7). That is the one
   exception to "the index files are rewritten, never staged": the tick now skips done
   projects, so nothing will ever regenerate it, and an uncommitted front door exists
   on exactly one machine. Update its objective's
   "Projects serving this objective" list to mark it delivered; if **all** of that
   objective's projects are now terminal, **the objective question is the human's** — it
   is the pre-flight's first escalation, answered in the main thread before you started. Set
   `status: achieved` only where that answer says so; never flip it silently, and never
   decide it yourself.

5. **Report leftover worktrees** — **only when no role agents are in flight.** Run
   `${CLAUDE_PLUGIN_ROOT}/scripts/prune-worktrees.sh`; it classifies and prints `git worktree remove`
   commands but never deletes. Include its `REMOVABLE`/`RECLAIMABLE` lines for this
   project's worktrees in the closing summary so the human can reclaim them; don't
   run the commands yourself. **Report only this project's lines**; the rest of the scan
   is exactly the noise the main thread no longer pays for. If agents are still working (a `--force`
   closeout can reach this step while they are), **skip this step** and say so — a report
   that races a live dispatch recommends deleting it.

6. **Resolve inbound references — before the folder is removed.** **Skip this step
   entirely for a `retain: true` project**: nothing is removed, so nothing dangles, and
   rewriting a `depends_on:` that still resolves would destroy provenance for no
   reason. For every other project:

   Other documents'
   frontmatter may point into this project: a task's or a **phase's** `depends_on:`,
   an `objective:`, a `project:`. Removing the folder leaves those refs dangling, and
   they are machine-read, so the PM can no longer evaluate whether a dependency is
   met. Measured on a live instance: closing one project left **38 dangling
   `depends_on:` refs** across two surviving projects, and nothing noticed until a
   validator was written months later.

   Find every inbound ref — tasks **and** phases:

   ```bash
   grep -rlE '^(depends_on|objective|phase|project):' \
     projects/*/tasks/*.md projects/*/phases/*.md \
     | xargs grep -l "/projects/<slug>/"
   ```

   **Then judge each one on the state of the task it points at — do not assume a
   removed dependency is satisfied.** A project can close with `cancelled` tasks, and
   `--force` closes one with unfinished tasks; silently dropping those refs tells
   downstream automation the work is unblocked when it never completed.

   * **Source task is `done`** → remove the entry from `depends_on:` and record it in
     the dependent task's `# Notes` ("depended on `<slug>/task-007`, completed and
     closed 2026-08-21"). History belongs in prose, where it cannot dangle.
   * **Source task is `cancelled`, or anything other than `done`** → **the human's, and
     you already asked.** The dependent work may no longer be viable, so this is the pre-flight's
     second escalation: act on the answer your brief carries — set the dependent task
     `blocked` with the reason in `# Notes`, or record the explicit replacement
     dependency it names. Never drop it silently, and never decide it yourself.

7. **Remove — or retain — then validate, then commit.** Unless `--dry-run`, run

   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/close-project-folder.sh <slug> --apply
   ```

   **Do not `git rm` or `rm` the folder by hand.** That one command is the whole
   folder step, and it reads `retain:` from `project.md` to decide which of the two
   outcomes it is. It deletes files, so its scope is fixed in a tested script rather
   than improvised here: without `retain:` it `git rm -r`s the folder as before; with
   `retain: true` it stamps `deliverable_paths:` into `project.md` (each task's
   `artifacts:`, verified on disk) and prunes only `tmp/`/`temp/`, `.DS_Store` and
   **non-markdown** files under `sources/` — never `deliverables/`, never `tasks/`,
   never `sources/**/*.md`. It also writes the project's stanza into `projects/CLOSED.md`,
   which is how a closed project's deliverables stay findable. Under `--dry-run`, run it
   **without** `--apply`: it reports the
   exact removal or prune and changes nothing. Keep its `log.md fragment` line for
   step 3's entry.

   Then stage and commit:

   * **removed** — the `git rm` already staged the deletion; add the `log.md` /
     objective / KB edits by explicit path.
   * **retained** — `git add -A -- projects/<slug>` (explicit path), so the prune's
     deletions, `status: done`, the `deliverable_paths:` stamp and the refreshed
     `projects/<slug>/index.md` all land in the one commit. If `git` refuses the index
     because a stale `/projects/*/index.md` line is still in this instance's
     `.gitignore`, force it (`git add -f -- projects/<slug>/index.md`) and tell the
     user to re-stamp: an index the tick will never regenerate and git will never
     carry exists on exactly one machine.

   Commit via `${CLAUDE_PLUGIN_ROOT}/scripts/commit-as.sh project-manager "chore: close <slug> project" -- <path>...`,
   naming every path — including `projects/<slug>` and `projects/CLOSED.md`. **Author it
   as `project-manager`, never as `human`**: `human` is the one role every guard trusts
   (it skips the promotion-authority check and the explicit-path requirement), and an
   agent must not commit under it. Step 3's entry still names the human who decided.
   **Run `${CLAUDE_PLUGIN_ROOT}/scripts/validate-bundle.sh` after the folder step and before committing** —
   validating beforehand cannot see a reference that only dangles once the folder is
   gone, which is the whole failure class step 6 exists to prevent. Zero errors is the
   gate. Print the closing commit SHA and the `log.md` entry. For a removal, remind the
   user the full record stays recoverable via `git log -- projects/<slug>/`; for a
   retention, that the folder is deliberately partial and the log entry says how.

**Report back** — one tight summary: what the cataloguer folded in, the `log.md` entry,
the closing commit SHA, this project's worktree lines, and anything you skipped. You never
promoted a task and you never merged a pull request; say so if either was ever in
question.

## Notes
- **No archive.** Removal is deliberate, and `git` + the KB already hold the record.
  It used to be justified by tick context too — that argument is spent: both readers of
  the tree stop at a `status: done` project's frontmatter, so a retained folder costs
  one parse. What remains is that a build project's record lives in the product repo's
  history, not here. Recover with
  `git revert <sha>` or `git show <sha>:projects/<slug>/...` if ever needed.
- This repo commits straight to `main` (see `CLAUDE.md`) — the human gate here is
  *deciding to close*, not a PR.
- No customer PII in the log or any KB doc written during closeout.
