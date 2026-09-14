# Step 5 — Reflect merges

**Loaded on demand.** The tick reads this file only when `tick-delta.sh digest` names
it on its `steps:` line (`project-manager.md` → "Step files"). Every rule in the core
prompt still binds here — both authority gates, the ownership gate, the UNKNOWN rule.

5. **Reflect merges.** For `in-review` tasks, check the PR(s): when **all** of a
   task's PRs are **merged** → `status: done`, then **reclaim that task's worktree**:
   `${CLAUDE_PLUGIN_ROOT}/scripts/reclaim-worktree.sh <task-path>`. It refuses unless every guard passes,
   and a refusal is **normal, not an error to work around**: report it and move on.
   Never pass a force flag, never remove the path by hand, never widen the search
   beyond the one path the task recorded (`docs/pm-design.md#step-5` has the incident
   that made deletion record-driven). Then re-evaluate dependents. If review
   **requests changes** → back to `in-progress`. If a PR is **closed unmerged** and
   abandoned → `cancelled` (or `blocked`) with a note. A multi-PR task stays
   `in-review` until all merge. **`done` and `cancelled` are the two writes a task's
   `open_caveats:` holds** (step 0): a non-empty list means clear it with evidence first,
   in its own edit, or leave the status alone and report it.

   **Never merge unless the project delegates it.** By default surface each verified,
   green PR as a 🔴 *merge* item. **Only** where the owning project's `autonomy`
   delegates merging **and** `AUTONOMY.md` defines that mode may you merge, and then
   strictly on the deterministic preconditions that file lists — including its
   **preflight**. Never merge on your reading of PR prose. `AUTONOMY.md` absent ⇒
   surface, don't merge.

   **A preview approval is a human decision, so it is stamped like one.** Where a task's
   deliverable is something a human LOOKS at, the agent opens a draft PR, records a
   `preview: <url>` line under `# Notes` and stops at `in-review`; a draft is never
   merge-eligible, so report the URL in the tick summary and never queue it as a merge.
   When the human approves it — in-session, or by marking the draft ready for review —
   append one
   `# Notes` line, `preview approved <ISO 8601> by <login>` from
   `${CLAUDE_PLUGIN_ROOT}/scripts/decision-stamp.sh --self`, then let the PR through the
   ordinary gate unchanged. **The same form and the same resolver as every other stamp**
   (`SCHEMA.md` → "Decisions name the human"): the approval before the review is the one
   decision that otherwise leaves no record anywhere, because marking a draft ready
   touches no bundle file.

   **Report the worktree, never remove it.** `${CLAUDE_PLUGIN_ROOT}/scripts/prune-worktrees.sh` is
   report-only: it classifies every worktree and prints the exact
   `git worktree remove` commands. Surface its `REMOVABLE` and `RECLAIMABLE` sets as
   a human job; never run the printed commands yourself. **Run it at most once per
   tick, and only when you have no role agents in flight** — its
   `PRUNE_ACTIVE_MINUTES` mtime veto (default 120) is a backstop, not the guard; your
   in-flight count is the guard.

   **Sum what that task cost, against the PR(s) that merged.** For each task you move to
   `done`, once:

   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/agent-usage.sh total <task-path> --pr <merged-pr-url> [--pr …]
   ```

   It adds up that task's own `* DISPATCH` lines and appends one `* TOTAL` line to
   `# Notes`. **A task with no dispatch lines records `usage UNKNOWN`, never zero** — an
   unmeasured task and a free one are not the same fact. Exit 1 means a `* TOTAL` line is
   already there; leave it alone.

   **Check the citations you are reflecting.** For each task you move to `done`, run
   `${CLAUDE_PLUGIN_ROOT}/scripts/cite-check.sh --text-file <f> --brief <slugs>` over its
   `# Result` section and over each merged PR body, with the slugs that task's brief
   carried. Anything dropped (exit 3, or exit 1 where a citing line lost every id) is
   **recorded as a `# Notes` line** naming the id and its verdict — `UNREAD` (a real doc
   nobody read) or `FABRICATED` (no such doc) — and exit 1 also goes in the tick report.
   It never changes the reflect verdict: a merged PR is merged. `CONVENTIONS.md` → cite
   knowledge as `[[finding-slug]]`.


<!-- end of step 5 -->
