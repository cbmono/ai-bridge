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

<!-- tool-mention: Workflow(2), Agent(2), EnterWorktree(1), mcp__claude-in-chrome__*(1), AskUserQuestion(1) — named below to state their ABSENCE for some readers, never to instruct: no role agent holds Workflow; only qa-reviewer holds Agent; EnterWorktree may be missing for a subagent; oncall-guide holds no browser tools; no role agent holds AskUserQuestion, which is why a tool request goes into open_questions instead of a live prompt. Every mention gives the route for an agent that lacks it. Enforced by tests/agent-tool-allowlist.test.sh. -->

- **Exhaust your own tools before you hand work back — three rungs, in order.** The default
  when you cannot do something is **not** to report it back:

  1. **Do it yourself**, with the tools you hold — a CLI, an MCP server, a browser, a
     script you write. That a step is fiddly, or is a browser step, or is the kind of thing
     a human usually does, is not a reason to pass it up.
  2. **Else ask for access to the tool that would let you.** Record the request and carry
     on — the next bullet is the whole of how, and it never stops your work. Asking fixes
     the gap once; reporting it fixes nothing, and the same gap blocks the next task and
     the one after.
  3. **Only then hand back exact instructions** — the commands, the paths, the output to
     expect — for a human to run, and only when no tool could have let you do it.

  **THE LADDER COVERS CAPABILITY GAPS ONLY. AN AUTHORITY GAP STAYS HUMAN REGARDLESS OF
  WHAT TOOL IS AVAILABLE.** "I can't" has two meanings and only one of them is yours:

  | | Meaning | Whose |
  |---|---|---|
  | **Capability gap** | no tool, no access, no CLI, not authenticated | **Yours.** The three rungs apply exactly as written. |
  | **Authority gap** | you *can* act, and must not | **The human's, always.** No rung applies. |

  The authority class, non-exhaustively: promoting a task `draft → ready`; merging a pull
  request; **any destructive or irreversible action**; **anything outward-facing** —
  publishing, sending, posting, deploying. **And its principle, so a case not on that list
  still resolves correctly: tool availability was never what made these human.** They are
  the human's because the *decision* is the human's, so acquiring the tool, finding a
  token, or being handed a wider allowlist changes nothing about any of them. A case you
  cannot place is an authority gap until a human says otherwise.

  **Nothing in this bullet is licence over the authority class.** Rung 1 is not "do it if
  you can" — **it never reaches an authority gap at all**, because those were never yours
  to be capable of. An agent reading this rule as permission to merge, promote, publish or
  delete has read it exactly backwards, and would be reversing the deny baseline this
  bundle runs on (`.claude/settings.json`, `AUTONOMY.md`, `SCHEMA.md` → "Two human
  authorities"). That misreading is most dangerous exactly where this rule has most
  effect — a background `/pm-loop` dispatch, hours from anyone watching — which is why it
  is stated here as a prohibition rather than left to be inferred from the table.
- **The middle rung NEVER BLOCKS: record the tool request, then carry on.** `blocked` is
  not the response to a missing tool, and an agent that halts at the first gap turns a
  missing CLI into a stalled task. On a capability gap: **write the request into the task's
  `open_questions`**, **continue**, finish everything that does not depend on the missing
  tool, and **report exactly what you could not reach** — named, so a reviewer can see it.
  You do not get to quietly take a worse route and call it done; the naming is what makes
  "continue" reviewable instead of silent.
  **Use the mechanism that already exists — nothing new is built for this.**
  `open_questions` → the tick surfaces it in `AWAITING.md` as a `🧰 **grant**` item (its own
  verb, distinct from `❓ **answer**`, because installing a thing is not typing an answer)
  → the human appends ` --- <answer>` to the entry → the next tick folds it in and
  re-dispatches the task **with** the tool. That is the entire path.
  **There is no live channel, and here is why, so nobody proposes one.** No role agent
  holds `AskUserQuestion`, and none is granted a message-sending tool, so a subagent's only
  upward channel is its final message on termination — bubbling up mid-run means dying and
  losing its context. A live grant would not help even if one existed: a subagent's tool
  list is fixed at dispatch and MCP servers connect at session start, so access granted
  mid-flight never reaches the running agent. It has to be re-dispatched either way, which
  is exactly what a live prompt was meant to avoid.
  **The contradiction this has a reader for:** reporting `blocked` for a reason that names
  a tool your **own** `tools:` list contains. `check-dispatch.sh` — the dispatch-artifact
  bullet below gives its path — reports that as exit 4, the record contradicting itself,
  and `tests/blocked-vs-own-tools.test.sh` in `cbmono/ai-bridge` pins it. Re-read your
  allowlist before you write a blocker reason.
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
- **Write for a human who will not read it.** They scan. Say the thing, then stop —
  a reader who wants depth will ask, and asking is cheap where re-reading to find the
  point is not. **One house style, for every surface below:**
  - **Short sentences.** One idea each.
  - **Bullets, tables and icons over paragraphs.** More than two of a thing is a table.
  - **Lead with the outcome** — what happened and what it means, before how you got there.

  **Trim the transmission, never the record.** This split decides every length question
  in this document, and getting it backwards deletes the reasoning the work runs on:

  | Surface | Rule |
  |---|---|
  | PR bodies, review comments and replies, status reports, code comments | **concise** — a reader is deciding something, now |
  | Task docs, commit messages, `Finding`s | **as long as the reasoning needs** — these are the durable record |

  **Brevity is never an excuse to drop evidence, a criterion or a caveat.** It is licence
  to drop *narration* — the story of how you got there — because that story is already
  carried by the commit message and the task doc, both of which travel with the change and
  neither of which has a length limit. **So there is nowhere for reasoning to be lost:**
  every rule below that says "short" is telling you where to put it, not to delete it.
- **The PR body has a required shape, and it is short.** Its reader is a **human deciding
  whether to merge** — not an agent reconstructing how you worked. **It opens with the
  literal heading `## Description (TL;DR)`.** Three required parts, in this order, plus an
  optional `## Notes` section (below) and nothing else:

  ```md
  ## Description (TL;DR)

  One sentence: what changes, and why it is safe to merge.

  | Criterion | ✓ | Verified by |
  |---|---|---|
  | the retry backs off on 429     | ✓ | `foo.test.sh` 40/0 |
  | works with two host accounts   | ✗ | needs two accounts — see task doc |

  ⚠️ Needs your call: harness growth 414 lines.
  ```

  1. **The heading `## Description (TL;DR)`, first**, then **a one-sentence TL;DR** under
     it. **That exact string, character for character** — it is the shape's only greppable
     anchor, which is why the rule names a fixed heading rather than "open with a
     sentence". `symlink/scripts/pr-body-clearance.sh` looks for it at the clearance gate,
     so a body that opens some other way is refused there rather than merged.
  2. **The task's `acceptance_criteria` as a table** — one row per criterion, its text
     verbatim, a `✓`/`✗`, and the evidence. **Required, always** (next bullet).
  3. **A short flagged line per threshold question** the owner must answer — harness
     growth, PR size, a wide change you could not split. One line each, `⚠️`-prefixed,
     last. Not a section, not an essay. **Each `⚠️` stays one line — the figure, and the
     call you need from the owner.** A `⚠️` that runs to a paragraph has stopped being a
     flag and become the essay it replaced; when the reasoning does not fit on the line it
     belongs in the task doc, and the line points at it.

  **Reasoning goes in the commit message and the task doc.** Why you chose this design,
  what you rejected, the incident that motivated it, what you tried first — all of it is
  already carried by those two, both travel with the change, and **none of it is needed to
  decide a merge.** A reader who wants the story has `git log` and the task document; a
  reader deciding a merge has thirty seconds. Add a `## Notes` section only for something a
  *reviewer* cannot see from the diff (a hint about where to look, a deliberate omission)
  — **one line per note, bounded exactly as the `⚠️` lines are.** "Judgement calls for the
  reviewer" is the heading this section grows under once it is unbounded, and that is the
  same essay arriving by another name.
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
  **This rule has a reader, and it reads the body — not this document.**
  `scripts/pr-body-clearance.sh <pr>` fetches the actual PR body from the host and
  refuses one that is missing the TL;DR line or the criteria table;
  `scripts/required-checks.sh` asks it for every PR it is about to clear, and
  `AUTONOMY.md` precondition 3 names it. **It refuses on missing STRUCTURE, never on
  length**: this bullet bounds the body's SHAPE and never its size, so a long body
  carrying both elements clears and the character count is reported as information only.
  A change that honestly needs more words is exactly the one that most needs explaining. Run it on your draft before you open the PR
  (`scripts/pr-body-clearance.sh --body-file <file>`); it is the cheapest check you have.
  **Short and auditable are the same thing here, which is why brevity costs nothing.**
  `` `foo.test.sh` 40/0 `` is *shorter* than a paragraph and *more* checkable than one: it
  names an artifact the reader can re-run, and a claim a reader can re-run is the only
  kind that counts. So the short form is licence to drop the narration, **never** licence
  to assert without evidence — "verified, works as expected" is a long way of saying
  nothing. Name the command, the test file and its tally, the CI run, or the URL you
  loaded.
  **A row carries what a reviewer needs to CHECK THE CLAIM, and stops** — a command and
  its result wherever that suffices: `` `foo.test.sh` 40/0 ``, `` `shellcheck -x run.sh`
  clean ``, `CI run 1234 green`, the URL you loaded. **Narration is not wanted** — not what
  you tried first, not why the approach is right, not the criterion restated in your own
  words, not the incident behind it. Every one of those is already in the commit message
  and the task doc, and repeating it in the row costs the reviewer the one thing the table
  exists to give them.
  **The floor is readability, and it binds exactly as hard as the ceiling: a person reading
  a row can check the claim from it.** `` `foo.test.sh` 40/0 `` clears the floor — a reader
  knows what to run and what they should see. `ok`, `done`, `see above` and a bare commit
  SHA do not: none tells a reader what to do next. **Short is the goal; cryptic is a
  failure**, and cutting past the point a human can act on the row fails this rule as
  surely as a paragraph does.
  **That two-sided bar is the rule's own test, and it settles a question already asked and
  answered — do not re-open it.** Asked 2026-08-30: is any of this verbosity required for
  CodeRabbit or another external reviewer? **No.** Treat the reviewer as an **AI agent**
  reading the table to review code — give it enough to check the claim and no more — **and
  keep every row human-understandable.** **Both halves bind**: a row an AI could parse but
  no person can act on fails just as surely as a paragraph neither of them needed. The
  answer is the owner's, so settle a row against the bar above rather than surveying past
  reviewer behaviour to re-derive it.
  **That bar has a reader, and the reader is the same one that reads the shape.** The
  ceiling and the floor shipped as prose on 2026-08-29 with nothing checking them, and a
  day later a PR landed three criteria rows of 500–600 characters carrying shell
  one-liners and their own reasoning — so `pr-body-clearance.sh` now measures **each
  criteria row's EVIDENCE cell**, refuses at **exit 3**, and names every offending row by
  index, length and criterion text. **Floor 13 bytes, ceiling 400 bytes.**
  **Evidence goes in the LAST column** — `| Criterion | ✓ | Verified by |` — which is
  where a reader looks for it and the only cell the bound reads.
  **The bound is on ONE CELL, never on the body.** That is not a compromise between the
  two, it is the opposite of a body cap: a body grows because the change is large, which
  is honest; a row grows because its author put the reasoning in the table instead of the
  task doc. Bounding the body would refuse the first. The criterion text does not count
  against the bound either — you copy it verbatim, so it is not yours to shorten.
  **Both numbers are measured, not round.** Over 34 criteria rows of three real PRs at
  2026-08-30T16:24Z (bytes, `LC_ALL=C`): #67 **92–377**, #70 **19–189**, #71 **160–341**
  plus **422, 462, 487**. 400 is the midpoint of the empty band 378–421 — 23 clear of the
  largest honest cell, 22 short of the smallest offending one — and it fails exactly those
  three rows and no other of the 34. 13 is the midpoint of `see above` (9), the longest
  floor failure named above, and `CI run 1234 green` (17), the shortest evidence named
  above. **Moving either number means re-measuring**; the harness pins all four boundary
  values as fixtures, so a change made without the measurement goes red.
  **A body written to this style clears it with room to spare** — #70's round-2 body,
  rewritten to these rules and complete on all 11 criteria, has a longest row of **264
  bytes** and a longest evidence cell of **189**, under half the ceiling that catches #71.
  The bound refuses bloat, not thoroughness.
- **Get the repo's build and lint green before opening a PR, and its tests green for what
  you touched** — the tests being **the ones your change touches, not the whole suite**
  (next bullet, which is where the scope of "tests" is settled). If you can't get that
  green, report rather than open the PR.
- **The full suite belongs to CI — locally, run the tests your change touches.** The
  required check on the PR runs everything on a clean machine anyway, so a full local run
  buys the same answer twice and the second copy is the expensive one. Concretely:
  **run the tests your change touches, plus anything that exercises the file you edited**,
  and **do not run the full suite locally as a matter of course**.
  **This is a rule about RE-RUNNING, not about testing.** Follow it literally and you still
  test before every push — that is the point of it, not a loophole in it.
  **Keep the per-branch signal, and this is why:** an agent needs a result **for its own
  branch, before it pushes**, because batching several agents' work tells you *the batch*
  is broken without telling you *whose change* broke it. Delete that sentence and the rule
  reads as "stop testing locally", which is the one thing it does not say.
  **The escape hatch exists and is bounded.** A full local run is legitimate when your
  change touches **shared machinery every test loads** — a common fixture, a helper each
  file sources, a config every test reads — and in that case **the PR body must state why
  the full run was needed**. It is an exception carrying a stated cost, not a free choice.
  **Do not poll a long-running local run.** This is its own prohibition, not a restatement
  of the one above: you can obey "don't run the full suite" and still burn an hour
  watching some *other* long job. A run you started and are now checking every minute is
  the **parked-watcher failure `check-dispatch.sh` exists for, with a pulse** — a
  40-minute poll and a parked watcher cost the same and look equally busy. Start a long
  job only if you will leave it alone; otherwise stop it.
  **The trade, with the measured numbers, so you can tell when it stops applying.** One CI
  round-trip costs **about 9 minutes of wall clock and no tokens** (8-10 minutes on a
  clean runner, measured across `cbmono/ai-bridge`'s recent runs); the local full run
  measured **2026-08-29** cost **39m 47s and 269.4k tokens** on a machine that was also
  running a `/pm-loop` tick. Same answer, several times the wall clock, and tokens on top.
  This is a **proportion argument, not a ban**: a *red* local run would have saved a CI
  round-trip, and the day a repo's CI is slower than its local suite, this rule inverts.
  **The local run never was the gate.** In `cbmono/ai-bridge`, the `harness suite` job is a
  **required check** on every PR
  ([ai-bridge#42](https://github.com/cbmono/ai-bridge/pull/42)), and branch protection sets
  **`strict=true`**, which forces that check to run **against the merged base** before the
  PR can land. Your machine cannot produce that verdict, so skipping the local full run
  asks nobody to trust **less** verification — it moves the verification to the only place
  the merge gate actually reads. `tests/local-vs-ci-testing.test.sh` in `cbmono/ai-bridge`
  pins the clauses above by name.
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
- **A repo with a `VERSION` file at its root: PROPOSE the bump, never make it silently and
  never skip it.** If the repo you are changing keeps its version in one file at the root
  (a plain `VERSION`, one line, no extension is the shape to expect) and your change
  touches what that repo's **consumers actually consume** — the paths other people or
  other systems install, link, copy or run, as opposed to its docs, tests and CI — then
  the change arrives with the new number already in the diff, in **its own commit** so it
  can be dropped, plus **one `⚠️` line in the PR body** naming the proposed
  `old → new` and which part of the version moved — it is a threshold question the owner
  answers, so it is bounded like every other one, and the *why* lives in the task doc and
  the commit message. **The human approves it by merging and rejects it by asking
  for that commit to go** — you are proposing, not releasing. Two things that are not
  yours to add: a **silent** bump (a number that moves with no line in the body is a
  number nobody agreed to), and a **release process** — no changelog, no tag, no publish
  step, unless the task's `acceptance_criteria` asks for one. The repo names its own
  consumed paths in its `CLAUDE.md` or its rule files; if it names none and the boundary
  is genuinely unclear, say so in the PR body rather than guessing a number.
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
- **A GitHub comment is about 280 characters — roughly a tweet.** This covers the two
  surfaces the shapes above never reached: an **inline code comment** and a **PR thread
  comment**, whoever writes them. Longer only when the finding genuinely needs it — a race
  whose trigger takes three sentences to state — and **never by default**.
  **The shape is: what is wrong, where, and what to do.**

  ```md
  `run.sh:42` — `$dir` is unquoted, so a path with a space splits into two arguments.
  Quote it: `rm -rf "$dir"`.

  Evidence: `harness-temp-safety.test.sh` 12/1 · `shellcheck` SC2086.
  ```

  Nothing else. **Never restate the diff back at the reader** — the host prints the lines
  you are commenting on directly above your comment, so summarising them is pure length.
  **No incident history, no rejected alternatives**, no essay on why the class of bug
  matters: that reasoning belongs in the commit message and the task doc, exactly as it
  does for the PR body. **Evidence as a short list, not prose.**
  **The verbosity is not needed for the agent readers either** — that was the open
  question, and the answer is no. A reviewing agent reads the **diff** and the **criteria
  table**, not our narration, and no clearance predicate in `SCHEMA.md` reads a comment
  body at all. So **brevity costs nothing on either side**: the human gets a comment they
  can act on, and the agent gets exactly what it was already reading.
  **Measured, so the target is grounded rather than a taste.** On `monorepo#3244`, our
  agents averaged **2,027 characters** across 6 inline comments; the two human reviewers on
  the same pull request averaged **120** across 2 — **17x the humans**, and 7x a tweet. The
  short form landed for PR bodies, review replies and progress reports while comments kept
  the old habit, because nothing named them as a surface. They are named here, and
  `tests/pr-body-shape.test.sh` keeps them named.
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
  The script prints the alias, or prints nothing and exits 1 when the agent has no entry.
  **It is not quiet about that: it prints why on stderr — report that line to the human,
  then inherit the session model and do not guess.** Exiting silently was the failure
  shape rather than the fallback: an unresolved role looks exactly like a resolved one at
  the call site, so every role can run on the wrong tier with nothing anywhere saying so.
  `install.sh` seeds `models`/`roleTiers` into `instance.config.local.json`, which is where
  the fix goes. This applies to **every**
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
- **A subagent works ONE task, and is resumed only for that task's next round.** Waking a
  completed agent with a message reuses its context, and reuse is right exactly while that
  context is about *this* work. **This is the one statement of the rule.** Everywhere else
  cites it and carries at most its one line, word for word, so the copies cannot drift:

  > same task and same PR ⇒ resume; anything else ⇒ dispatch fresh; a tick ⇒ never

  In full:

  | What you would hand it | |
  |---|---|
  | The **same task**, the **same PR**, the next round — review findings, a re-rebase, "open the PR on what you already have" | **RESUME.** It knows this repo squash-merges and which `--onto` base to use; a cold agent re-derives that at real cost. |
  | A **different task**, a **different PR**, or an unrelated ad-hoc job | **DISPATCH FRESH.** |
  | A `project-manager` **tick** | **NEVER RESUME — no exception, no "unless".** |

  Measured 2026-08-30: one `software-engineer` resumed three times — two rebases and then
  a round of review findings — ended carrying 163k tokens; a resumed tick produced two
  concurrent ticks. The tick case is absolute because a resume never passes through the
  launcher that takes the dispatch lock, and because it re-enters a loop whose state has
  moved on.

  **Which half of this has a reader, said plainly rather than left to sound enforced.**
  The tick half is CHECKED, and the reader is named so you can go and look: the control
  panel's `scripts/tick-lock.sh` refuses a tick acquire that finds no lock (exit 4) — no
  lock means no launcher, and no launcher means nobody dispatched that tick. Nothing on
  your path reads that file; only the loop and the tick do. The same-task half, by
  contrast, is NOT checked and cannot be, because nothing can see the intent behind a
  message; it is held by whoever dispatches, which is why it is written here and in the
  dispatchers' own instructions instead of being asserted somewhere no one reads. **Most readers of this file dispatch nothing** (see the
  wide-work bullet above), so for you it is the rule your dispatcher follows, and it
  cashes out as one thing: a message picking up **your own task's** next round is
  legitimate work; anything else should have been a fresh agent, and saying so is better
  than quietly absorbing it.

  **No "delete the agent" primitive exists and none is wanted** — agents complete on their
  own, so resumption is the only lever there is. That is why this rule is about resumption
  and not about how long an agent lives.
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
  claude-for-chrome` **and** the `mcp__claude-in-chrome__*` tools are actually present,
  **rung 1 above applies to the browser like any other tool**: verify the change in the
  real page, read the logged-in view, take the screenshot. This paragraph used to state
  that as a browser-only rule; it is the general one now, stated once, so the two cannot
  drift. You get your **own tab group**, not the human's tabs, so always navigate from an
  explicit URL. Tools absent (e.g. a headless tick) → **that is a capability gap, so take
  the non-browser route, say so, and carry on** — never report blocked *only* for a missing
  browser. **Browser writes follow the project's
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
