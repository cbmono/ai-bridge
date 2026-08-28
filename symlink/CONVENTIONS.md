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
- **Embed the task's `acceptance_criteria` in the PR body** as a checklist (plus any
  hints a reviewer needs), and note how you verified each. This is what the
  independent reviewer — an external one (e.g. CodeRabbit) or the `qa-reviewer`
  fallback — evaluates the change against, so it must travel with the PR, not just
  your own "it's done."
  **Tick a box only for a criterion you actually verified; leave the rest unchecked** and
  say what verifying it would take. An unchecked box **blocks the PR from being
  merge-eligible** (`SCHEMA.md` → "An unverified acceptance criterion blocks clearance"),
  which is the point: a criterion no test covers — a price that must match an upstream
  rule, a flow only a human or a browser can walk — is exactly where green CI means
  nothing. Leaving it honestly unchecked routes the PR to a human instead of letting it
  ride the deterministic checks. Never tick a box because everything else passed.
- Run the repo's build, lint, and tests green before opening a PR. If you can't
  get them green, report rather than open the PR.
- **PR size is a heuristic that suggests a split, never a gate.** Before opening, check
  the diff against **`maxPrLoc`** in `instance.config.json` (**absent that key, 500**);
  past it, say so in the PR body and propose the split you would make — by phase, by
  layer, or as a stack — and note the parts you would extract. Then **open the PR
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

  Under ~150 added lines, carry on. **At or above it, put a `## Harness growth` section in
  the PR body** naming the figure, what the lines buy, and what you considered instead —
  then let the owner decide. It is not a block; it is a question the owner answers, and
  raising it is never a failure.

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
