# Conventions for role agents working in target repos

**This is the single source of truth for shared role-agent behaviour.** The
symlinked role agents (`software-engineer`, `devops-engineer`, `qa-reviewer`,
`oncall-guide`) reference this file instead of restating it — **keep them in
sync**: change a rule here, not in each agent.

**Read this before your first write in a target repo.** It lives here rather
than in the instance `CLAUDE.md` because it governs work in the **target
repos**, which are outside this bundle — so it cannot be a `paths:`-scoped
rule (globs are matched relative to this directory and never match a file under
`reposRoot`), and as always-loaded text it sat in every session's context
including the majority that dispatch no role agent. The `CLAUDE.md` section of
the same name keeps the handful of invariants that must hold whether or not you
got here.

**One rule about this file's own wording, because four agents with differing `tools:`
lists read it:** an instruction here must be executable by **every** one of them, so where
a rule depends on a tool only some of you hold, it says **which list decides** and what the
others do instead. Never the other way round — a condition on what is *installed* reads as
satisfied while still being unexecutable for an agent that lacks the tool, which is exactly
how the `code-architect` clause below went unnoticed. `tests/agent-tool-allowlist.test.sh`
in `cbmono/ai-bridge` enforces this.

<!-- tool-mention: Workflow(2), Agent(2), EnterWorktree(1), mcp__claude-in-chrome__*(1) — named below to state their ABSENCE for some readers, never to instruct: no role agent holds Workflow; only qa-reviewer holds Agent; EnterWorktree may be missing for a subagent; oncall-guide holds no browser tools. Every mention gives the route for an agent that lacks it. Enforced by tests/agent-tool-allowlist.test.sh. -->

- Read `instance.config.json` for `reposRoot` (where target repos are cloned).
  Honor this `CLAUDE.md` for data-handling, units, and commit-attribution.
- **Detect the default branch** (`git symbolic-ref --short refs/remotes/origin/HEAD`
  / `git remote show origin`) — never assume `main`. Never work on it.
- Create a feature branch (or a git worktree under the instance's `worktreeRoot` —
  absent that key, `<reposRoot>/_wt`) per task.
- Conventional commits; **no AI attribution / `Co-Authored-By` lines.** Push to
  `origin` early (don't wait until the end) so an interrupted worktree loses nothing.
- PR title format: `<type>: <subject> [<task-id>]` (OKF task id, e.g.
  `[ci-hardening/task-001]`). Target the default branch. **Never merge.**
- **The PR body has a required shape, and it is short.** Its reader is a **human deciding
  whether to merge** — not an agent reconstructing how you worked. Three parts, in this
  order, and nothing else:

  ```md
  **TL;DR** — one sentence: what changes, and why it is safe to merge.

  | Criterion | ✓ | Verified by |
  |---|---|---|
  | the retry backs off on 429     | ✓ | `foo.test.sh` 40/0 |
  | works with two host accounts   | ✗ | needs two accounts — see task doc |

  ⚠️ Needs your call: harness growth 414 lines.
  ```

  1. **A one-sentence TL;DR**, first.
  2. **The task's `acceptance_criteria` as a table** — one row per criterion, its text
     verbatim, a `✓`/`✗`, and the evidence. **Required, always** (next bullet).
  3. **A short flagged line per threshold question** the owner must answer — harness
     growth, PR size, a wide change you could not split. One line each, `⚠️`-prefixed,
     last. Not a section, not an essay.

  **Reasoning goes in the commit message and the task doc.** Why you chose this design,
  what you rejected, the incident that motivated it, what you tried first — all of it is
  already carried by those two, both travel with the change, and **none of it is needed to
  decide a merge.** A reader who wants the story has `git log` and the task document; a
  reader deciding a merge has thirty seconds. Add a `## Notes` section only for something a
  *reviewer* cannot see from the diff (a hint about where to look, a deliberate omission).
- **The criteria table is the merge gate — so it is required, and terseness never costs
  evidence.** It is what the independent reviewer — an external one (e.g. CodeRabbit) or
  the `qa-reviewer` fallback — evaluates the change against, so it must travel with the
  PR, not just your own "it's done." The `✓`/`✗` column **is** the checkbox state
  `SCHEMA.md` reads (→ "Two structured inputs; prose is never one"): one mark per
  criterion, machine-checkable, and the only place criteria coverage is read from.
  **Mark `✓` only for a criterion you actually verified; mark the rest `✗`** and say in
  the same row what verifying it would take. A `✗` **blocks the PR from being
  merge-eligible** (`SCHEMA.md` → "An unverified acceptance criterion blocks clearance"),
  which is the point: a criterion no test covers — a price that must match an upstream
  rule, a flow only a human or a browser can walk — is exactly where green CI means
  nothing. Leaving it honestly unmarked routes the PR to a human instead of letting it
  ride the deterministic checks. Never mark `✓` because everything else passed.
  **Short and auditable are the same thing here, which is why brevity costs nothing.**
  `` `foo.test.sh` 40/0 `` is *shorter* than a paragraph and *more* checkable than one: it
  names an artifact the reader can re-run, and a claim a reader can re-run is the only
  kind that counts. So the short form is licence to drop the narration, **never** licence
  to assert without evidence — "verified, works as expected" is a long way of saying
  nothing. Name the command, the test file and its tally, the CI run, or the URL you
  loaded.
- Run the repo's build, lint, and tests green before opening a PR. If you can't
  get them green, report rather than open the PR.
- **PR size is a heuristic that suggests a split, never a gate.** Before opening, check
  the diff against **`maxPrLoc`** in `instance.config.json` (**absent that key, 500**);
  past it, say so in the PR body as one `⚠️` line — the figure and the split you would make
  (by phase, by layer, or as a stack) — and put the detail in the commit message and the
  task doc, per the PR-body shape above. Then **open the PR
  anyway**: generated boilerplate, codemods, lockfiles and dense logic all move the real
  number, so a line count cannot decide reviewability on its own, and a task that
  legitimately needs one large change must not be blocked by arithmetic. It is **not** a
  review criterion either — a reviewer never withholds clearance over it, and it never
  appears as a finding. If the split is obviously right and cheap, do it before opening.
- **Self-review before you open the PR (a pre-filter, not the gate).** On your own diff,
  run a review and fix what it flags *first* (correctness, edge cases, security, tests).
  **Which route you take is decided by your own `tools:` list, not by what is installed on
  the machine.** Hold `Agent`? — `qa-reviewer` does — dispatch `code-architect`. Don't hold
  it? — `software-engineer`, `devops-engineer` and `oncall-guide` don't — then **a careful
  pass over your own diff *is* the route**, not a fallback from one, because there is
  nothing to fall back from. Check your allowlist if you are unsure: an installed
  `code-architect` changes nothing for an agent that cannot dispatch, which is why this
  reads on possession rather than on installation.
  **Don't spend a CodeRabbit session here if CodeRabbit reviews the PR
  anyway** — running the same paid reviewer twice per PR is the single easiest cost to
  delete, and the pre-filter's job (catch the cheap stuff) is served just as well by a
  local agent. Reach for `coderabbit review` locally **only** when the repo has *no*
  CodeRabbit integration, i.e. when the `qa-reviewer` fallback would be the gate. This
  pre-filter does **not** replace the independent verifier: you review your own work
  leniently, so the fresh-context reviewer still runs after (see `SCHEMA.md`
  "Independent verification gate").
- **One review per PR — fix findings, don't re-trigger.** Address every review comment,
  push the fix, and reply once stating what changed (or why you disagree). Do **not** ask
  for a re-review to confirm your fixes: a re-review of addressed findings reliably finds
  nothing and costs a full session. Request one (`@coderabbitai review`) only after a
  *substantial rewrite* that invalidates the original review. Repos should pin this with
  `.coderabbit.yaml` (`auto_incremental_review: false`, `chat.auto_reply: false`) so it
  holds by default rather than by everyone's discipline.
  **The reply is a list, not a letter** — same discipline as the PR body, same reason:

  ```md
  - Finding 1 — fixed: `foo.sh` now quotes `$dir` (a1b2c3d).
  - Finding 2 — not taking: the path is `mktemp -d`-owned, never user input.
  - Finding 3 — fixed: added the null case, `foo.test.sh` 41/0.

  Evidence: `foo.test.sh` 41/0 · CI run 1234 green · `shellcheck` clean.
  ```

  One line per finding **fixed** (what changed, and where), one line per finding **not
  taken** (with the reason), and the evidence as a short list at the end. **Never restate
  the finding back at the reviewer** — it wrote the finding, it still has it, and quoting
  it back is the single biggest source of reply length. The reviewer is deciding whether
  each finding is closed, not re-reading its own review. If you disagree, say so once with
  the evidence and move on (the two-round cap below is what ends it, not persistence).
- **TWO ROUNDS, THEN THE HUMAN DECIDES. This is a hard cap.**
  A reviewer's job is to evaluate the diff **against the task's `acceptance_criteria`**.
  It is *not* to re-litigate those criteria, argue the design, or look for a reason the
  change should not land. Grade the work against the bar it was given.
  - **Round 1** — the reviewer reports findings. The implementer fixes them and replies
    once, saying what changed or why it disagrees.
  - **Round 2** — the reviewer checks *only the things it raised in round 1*. New
    findings outside that set are **recorded, not blocking**.
  - **There is no round 3.** Anything still unresolved after round 2 **stops and goes to
    the human**, with both positions stated in one short block: what the reviewer wants,
    what the implementer says, and what the criterion actually asks for. The human
    decides; the agents do not converge on it.
  **Why this is a hard number and not a guideline.** ai-bridge#34 ran **eight rounds**,
  and rounds 3-8 produced adversary-shaped findings against a change that already met its
  criteria — the reviewer kept finding new ground to contest because nothing told it to
  stop. That single PR, and others like it, consumed roughly **70% of a Max account's
  weekly budget**. An unresolved disagreement costs the human one decision; an unbounded
  review costs a week.
  **And the number is countable — `scripts/review-rounds.sh <pr> --repo <org>/<repo>`.**
  It prints how many rounds a PR has already had and **exits non-zero at or past two**, so
  whoever is about to spawn a verifier can be refused instead of trusted to remember. Run
  it *before* dispatching one (the `project-manager`'s verification step) and *before*
  verifying one (`qa-reviewer` mode B, first thing); non-zero means stop and write the
  both-positions block above. It counts **completed verifications of distinct commits**,
  decided by `review-clearance.sh` — so a rate-limited reviewer's refusal, which publishes
  a green check and names the head in its own body, is **not** a round, and an absent
  reviewer adds none. Exit 2 is *unknown*, which is not permission. A missing or broken
  script exits non-zero too, so the failure direction is "ask the human", never "review
  again". This rule spent a week of budget while it was prose; it is not prose now.
  **Corollary — grade against the criteria, not against your own taste.** If you believe
  the criteria themselves are wrong, say so *once*, in the verdict, as a note to the
  human. Do not express it by withholding a pass.
- **Resolve a dispatched agent's model with `scripts/resolve-model.sh <agent>`, never from
  memory.** `roleTiers`/`models` in `instance.config.json` govern which model each agent
  runs on — but they used to exist only as prose in five documents, so they governed the
  dispatch paths whose markdown happened to mention them and nothing else. Measured
  2026-08-28: three separate sessions each reported, independently, that they had
  dispatched agents all day without consulting the file. One of them had passed the right
  alias anyway, by remembering it — which is the same fragility with a luckier outcome.
  The script prints the alias, or prints nothing and exits 1 when the agent has no entry —
  in which case inherit the session model and do not guess. This applies to **every**
  dispatch, including an ad-hoc dispatch from a main session, which is exactly the
  path the prose never reached.
- **Don't grow the harness without a reason — and past ~150 lines, ask.** This machinery
  is a means, not the product. Before you open a PR, measure what you added to it:

  ```sh
  git diff --numstat origin/main -- 'symlink/**/*.sh' | awk '{a+=$1} END{print a+0}'
  ```

  Under ~150 added lines, carry on. **At or above it, flag it in the PR body as one
  `⚠️` line naming the figure** — `⚠️ Needs your call: harness growth 414 lines.` — and put
  what the lines buy and what you considered instead in the **commit message and the task
  doc**, per the PR-body shape above. Then let the owner decide. It is not a block; it is a
  question the owner answers, and raising it is never a failure.

  For scale: ordinary fixes here add 30-55 lines; the two largest features added 360 and
  363. The whole harness is ~8,500 lines, so 150 is roughly a 2% jump in one PR.

  **Why a number in a rule rather than a test.** This used to be `machinery-ceiling.test.sh`
  — 944 lines pinning two integers that every PR touching `symlink/` had to re-measure. The
  measurement was free; the *coupling* was not. It put a placeholder on `main` and turned it
  red (#31, needing #32 purely to undo), it was the single conflict `git merge-tree` found
  across ten PR pairs (#34 x #35), and it forced rebases on PRs that had nothing to do with
  each other. A threshold you check against **your own diff** cannot collide with anyone
  else's, which is the whole point.
- **Kill everything you started before you report.** Any dev server, watcher, file-watch
  probe or other background process you launch must be **stopped before you report back**,
  and your report must say that you stopped it. Measured 2026-08-27: two `pnpm dev`
  servers were found still running after **2 days 16 hours** and **2 days 13 hours**, from
  worktrees whose tasks had merged long before. Nobody noticed until a machine was hot.
  `scripts/prune-worktrees.sh` reports worktrees that still have a live process attached —
  a scan catches what discipline misses — but it only ever reports, so the teardown is
  yours.
- **A dispatch is not finished until its artifact exists — check, don't believe the
  report.** When an agent you dispatched reports back, run `scripts/check-dispatch.sh
  <task-doc>` before you act on what it said. It reads three things and judges nothing
  else: did `status:` advance, does `pr:` name a URL, and does that pull request exist.
  Exit 0 is the only clearance — exit 1 is the parked signature (still `ready`/`in-progress`
  with no PR), 3 a `pr:` the host does not resolve, 4 a record contradicting itself, 2 a
  question it cannot answer. **Exit 0 does not mean "there is a PR":** a task the agent left
  `blocked` or `cancelled` with no PR also clears, because no artifact was due — read the
  stated reason rather than reading a stopped task as a verified artifact. Measured 2026-08-28: two agents finished their work, committed
  it — one had already pushed — then ended their turns waiting on a background job that
  nothing was left running to notify, and **reported as completed** with no PR open. The
  wall-clock rule missed it (one parked at **16 minutes**), the two-round cap missed it
  (neither reached review), and the completion notification *was* the failure. Asking
  whether the PR exists takes two seconds and nothing was doing it. This applies to
  **every** dispatch, including an **ad-hoc** dispatch from a main session — the path with
  no coverage at all today, because no tick ever reads it.
  **It is report-only, and that is the point: a non-zero verdict is never a licence to
  re-dispatch.** Re-running a task sequence that already finished is the most expensive
  failure this loop has (`/pm-loop` step 2), and the usual recovery is one message to the
  parked agent telling it to open the PR on what it already has.
- **Wide work: fan out only if you actually can — most of you can't.** For genuinely wide,
  *independent* work a parallel fan-out beats grinding serially (find the real edges → fan
  out → verify → synthesize), but check your `tools:` list before you plan around one.
  **No role agent's allowlist contains `Workflow`**, so the `Workflow` idiom is dead for
  every one of you and is deliberately not written here as an option — granting it is a
  standalone decision with its own cost, not something a convenience clause settles. Only
  `qa-reviewer` holds `Agent`, so only `qa-reviewer` can fan out at all, and it does so by
  dispatching several agents in parallel. `software-engineer`, `devops-engineer` and
  `oncall-guide` hold neither: **for you, wide work is sequential**, and that is the
  intended behaviour rather than a gap to route around — say so in the PR body and lean on
  the PR-size heuristic above if the result is large. Whoever *does* fan out: **read-only**
  fan-out (review, audit, research, code-navigation) needs **no worktree isolation**
  (nothing writes) but still obeys the instance's concurrency/resource limits (the
  `maxAgentsInFlight` cap) — it does **not** license unlimited dispatches; a **write**
  fan-out must *also* give each subagent its own worktree — never parallel writes to a
  shared clone/worktree (the same collision the per-task isolation rule prevents). Skip it
  for small/sequential work (pure overhead). `/pm-loop` stays serial — a fan-out lives
  *inside* a task, never at the loop level.
- Write the PR URL and a `# Result` summary back into the task document, and set
  the task `status: in-review` (or `blocked`, with why, if you can't proceed).
- **No customer PII** in code, commits, or PR text; **never echo, print, or log
  secrets or environment variables** (rely on existing env / `.npmrc` for auth).
- **Capture knowledge:** if you discover something durable and reusable, write or
  update a `Finding` in `knowledge/findings/` (per `SCHEMA.md`) and link it from
  the task, so the next agent doesn't re-derive it.
- **Parallel-safety:** if the product repos share one clone / one package store,
  each agent uses its own worktree under `worktreeRoot` (from `instance.config.json`
  — outside any synced folder; **never** inside `reposRoot`. Absent that key, fall
  back to `<reposRoot>/_wt`) and a **private package
  store** (e.g. `pnpm install --store-dir <worktree>/.pnpm-store`), and pushes
  early. Create the worktree explicitly with `git worktree add <path> -b <branch>
  origin/<default-branch>` — don't rely on the `EnterWorktree` tool, which may be
  unavailable to you as a subagent. (`settings.json` sets `worktree.bgIsolation:
  none` so the control panel manages worktrees itself; harness isolation would
  only isolate this repo, not the product repos.)
- **Browser (only if the project opts in):** when the task's project sets `browser:
  claude-for-chrome` **and** the `mcp__claude-in-chrome__*` tools are actually present, be
  **browser-first**: verify the change in the real page, read the logged-in view, take the
  screenshot — don't hand a browser step back to the human just because it's a browser
  step. You get your **own tab group**, not the human's tabs, so always navigate from an
  explicit URL. Tools absent (e.g. a headless tick) → take a non-browser route and say so;
  never report blocked *only* for a missing browser. **Browser writes follow the project's
  `autonomy`:** **ask first** — that's the default and the only behaviour unless the project
  delegates writes (`AUTONOMY.md` at the bundle root defines the modes; no such file means
  always ask). Read-only navigation and screenshots never need asking. Scope discipline
  still applies — a write nobody asked for isn't licensed by autonomy. And
  no customer PII from a logged-in page
  ever reaches a task doc, PR text, `log.md`, any log or console output, or the KB.
  Describe the *shape* of what you saw, not the records. Full rules: `SCHEMA.md` →
  "Browser access".
- **Code intelligence (if present):** if a repo has a CodeGraph index (a
  `.codegraph/` dir) or the `codegraph` MCP is available, use it to navigate the
  codebase before bulk-grepping — `codegraph explore "<q>" -p <repo>` for an area,
  `codegraph node <sym>` for one symbol's callers/callees, `codegraph impact <sym>` /
  `codegraph affected <files>` before a change. Skip silently if absent; it's an optional
  local index (see the ai-bridge README).
