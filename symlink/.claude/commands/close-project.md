---
description: Close a completed project — final KB consolidation, log the closeout, roll up status, then remove the project folder (git history + KB are the record; no archive) — or, with `retain: true`, freeze and keep it. Human-gated; run once a project's tasks are all done/cancelled.
argument-hint: <project-slug>  [--dry-run] [--force]
allowed-tools: Bash(date:*), Bash(scripts/commit-as.sh:*), Bash(scripts/close-project-folder.sh:*), Bash(scripts/prune-worktrees.sh:*), Bash(scripts/validate-bundle.sh:*), Bash(grep:*), Bash(git rm:*), Bash(git add:*), Bash(git log:*), Bash(ls:*), Read, Write, Edit, Glob, Agent
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

> **Generic template file** (symlinked from the `ai-bridge` template). Reads the
> bundle's own `SCHEMA.md` (see "Project & objective completion") and
> `instance.config.json` — never hardcode org/repo/path literals here.

## Inputs
`$ARGUMENTS` = the project slug (the `projects/<slug>/` directory name), plus:
- `--dry-run` — report what closeout *would* do; change nothing.
- `--force` — proceed even if some tasks are **not** terminal (records which). Use
  sparingly — normally every task should be `done`/`cancelled` first.

If no slug is given, list projects whose tasks are all terminal (the close
candidates) and ask which to close.

## Steps

> **`--dry-run` short-circuits every mutation.** Do step 1 (read-only checks),
> then for steps 2–7 *report exactly what you would do* — do **not** dispatch the
> cataloguer, edit `log.md`/`index.md`/`project.md`/objective, prune worktrees, or
> commit/remove anything. Only a run without the flag actually changes state. Step 7's
> `scripts/close-project-folder.sh <slug>` **without `--apply`** is the one thing you
> may run: it is report-only by design and prints the exact removal or prune it would
> perform, which is a better dry-run report than a description of one.

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

2. **Consolidate knowledge.** Dispatch the `cataloguer` (subagent) for a final pass:
   capture/link any remaining durable `Finding`s from this project, refresh the
   `Service`/`Runbook` docs it touched, and cross-link them. For a **research**
   project, decide with the user which `deliverables` graduate into `knowledge/` and
   have the cataloguer fold them in. Skip only if the project produced nothing
   durable (trivial/superseded) — say so.

3. **Record the closeout.** Get a timestamp (`date -u +%Y-%m-%dT%H:%M:%SZ`). Prepend
   a dated **Project closed** entry to the root `log.md` (newest-first) naming the
   project, its merged PR(s) as `[<repo>#<n>](url)`, the `Finding`(s) it produced
   (KB links), and a one-line outcome. (The removing commit SHA is added by step 6's
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
   objective's projects are now terminal, **ask** whether to set the objective
   `status: achieved` (don't flip it silently).

5. **Report leftover worktrees** — **only when no role agents are in flight.** Run
   `scripts/prune-worktrees.sh`; it classifies and prints `git worktree remove`
   commands but never deletes. Include its `REMOVABLE`/`RECLAIMABLE` lines for this
   project's worktrees in the closing summary so the human can reclaim them; don't
   run the commands yourself. If agents are still working (a `--force` closeout can
   reach this step while they are), **skip this step** and say so — a report that
   races a live dispatch recommends deleting it.

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
   * **Source task is `cancelled`, or anything other than `done`** → **stop and ask
     the human.** The dependent work may no longer be viable. Either set the dependent
     task `blocked` with the reason in `# Notes`, or record an explicit replacement
     dependency. Never drop it silently.

7. **Remove — or retain — then validate, then commit.** Unless `--dry-run`, run

   ```bash
   scripts/close-project-folder.sh <slug> --apply
   ```

   **Do not `git rm` or `rm` the folder by hand.** That one command is the whole
   folder step, and it reads `retain:` from `project.md` to decide which of the two
   outcomes it is. It deletes files, so its scope is fixed in a tested script rather
   than improvised here: without `retain:` it `git rm -r`s the folder as before; with
   `retain: true` it stamps `deliverable_paths:` into `project.md` (each task's
   `artifacts:`, verified on disk) and prunes only `tmp/`/`temp/`, `.DS_Store` and
   **non-markdown** files under `sources/` — never `deliverables/`, never `tasks/`,
   never `sources/**/*.md`. Run it **without** `--apply` first under `--dry-run`; it
   reports and changes nothing. Keep its `log.md fragment` line for step 3's entry.

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

   Commit via `scripts/commit-as.sh human "chore: close <slug> project" -- <path>...`.
   **Run `scripts/validate-bundle.sh` after the folder step and before committing** —
   validating beforehand cannot see a reference that only dangles once the folder is
   gone, which is the whole failure class step 6 exists to prevent. Zero errors is the
   gate. Print the closing commit SHA and the `log.md` entry. For a removal, remind the
   user the full record stays recoverable via `git log -- projects/<slug>/`; for a
   retention, that the folder is deliberately partial and the log entry says how.

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
