# Design invariants, and why each one exists

This is the reasoning behind ai-bridge's design. Every bullet here exists because
something went wrong once, and the "why" is the record of what went wrong — so
preserve it when you edit a rule rather than summarising it away.

**Audiences.** This file is for a human reading deliberately. The root
[`CLAUDE.md`](../CLAUDE.md) carries a one-line headline for each invariant below,
because a prohibition has to be in context *before* you consider the change it
forbids; and [`.claude/rules/`](../.claude/rules) carries the same prohibitions
path-scoped, so they load when an agent reads a file they govern. Neither of those
repeats the story — this file is the single home for it. If you shorten a "why",
move it here intact instead.

> **History.** These paragraphs were relocated verbatim from `ai-setup`'s root
> `CLAUDE.md`, then from `ai-setup/.claude/rules/ai-bridge.md`, and finally into this
> repo when ai-bridge was split out of `ai-setup`. Paths were rewritten for this repo's
> root (`ai-bridge/symlink/…` → `symlink/…`, `ai-bridge/tests/…` → `tests/…`); nothing
> else was changed.

## Contents

| # | Invariant | Governs |
|---|---|---|
| 0 | [Layout](#layout) | the whole repo |
| 1 | [Retiring seed content is only reported](#1-retiring-content-is-asymmetric) | `install.sh`, `upgrade.sh`, `RETIRED`, `seed/` |
| 2 | [Retiring machinery sweeps the links](#2-retiring-machinery-means-deleting-the-file-and-letting-installsh-sweep-the-links) | `install.sh`, `symlink/` |
| 3 | [`AWAITING.md` is opt-in by presence](#3-awaitingmd-is-ai-bridges-only-status-artifact-and-it-is-opt-in-by-presence) | `install.sh`, the PM agent, `session-banner.sh` |
| 4 | [A deletable capability is one file](#4-a-capability-some-deployments-must-not-have-should-be-one-deletable-file) | `symlink/AUTONOMY.md`, `commit-as.sh`, `upgrade.sh` |
| 5 | [`build` and `research` are asymmetric](#5-build-and-research-projects-are-deliberately-asymmetric) | `/new-project` |
| 6 | [The merge gate: exit 0 is the only clearance](#6-the-delegated-merge-gate-resolves-its-required-checks-in-required-checkssh-and-exit-0-is-the-only-clearance) | `required-checks.sh`, `review-clearance.sh` |
| 7 | [`prune-worktrees.sh` is report-only](#7-prune-worktreessh-is-report-only-and-that-is-load-bearing) | `prune-worktrees.sh` |
| 8 | [`validate-bundle.sh` was scoped by measuring](#8-validate-bundlesh-was-scoped-by-measuring-first-and-that-is-the-point) | `validate-bundle.sh` |
| 9 | [`migrate-bundle.sh` fixes only what has one right answer](#9-migrate-bundlesh-fixes-only-what-has-one-right-answer-and-is-report-only-by-default) | `migrate-bundle.sh` |
| 10 | [The scaffold review is a three-stage chain](#10-the-scaffold-review-is-a-three-stage-chain-with-a-declared-fallback-never-a-skip) | `/new-project` step 8 |
| 11 | [The board's five invariants](#11-the-cross-instance-board-is-a-writer-three-renderers-and-one-deletable-generated-file) | `write-snapshot.sh`, `build-board.sh`, `print-board.sh`, `watch-board.sh` |
| 12 | [Three behaviours against a silent wrong answer](#12-three-ai-bridge-behaviours-that-all-exist-because-a-silent-wrong-answer-is-worse-than-a-loud-one) | `push-state.sh`, `answered_questions`, `maxPrLoc` |
| 13 | [A shared instance is three no-ops and one gate](sharing.md) | `task-owner.sh`, config split, derived indexes |
| 14 | [`knowledge/references/` is the fifth knowledge kind](#14-knowledgereferences-is-the-fifth-knowledge-kind) | `validate-bundle.sh`, `SCHEMA.md` |
| 15 | [The config layer is one tier, and the arrow stays one-way](#15-the-config-layer-is-one-tier-and-the-arrow-stays-one-way) | `install.sh --config`, `config/` |
| 16 | [The kill switch is one hook, and it fails open](#16-the-kill-switch-is-one-hook-and-it-fails-open) | `agent-control.sh`, `control.sh` |
| 17 | [An instruction is executable only if the agent *holds* the tool](#17-an-instruction-addressed-to-an-agent-is-executable-only-if-that-agent-holds-the-tool) | every agent body, `symlink/CONVENTIONS.md`, `seed/CLAUDE.md` |
| 18 | [The allowlist check is pinned from both sides](#18-the-tool-allowlist-check-is-pinned-from-both-sides-and-silence-is-a-failure) | `agent-tool-allowlist.test.sh` |
| 19 | [The destructive-action baseline is a hook, and it is narrow on purpose](#19-the-destructive-action-baseline-is-a-hook-and-it-is-narrow-on-purpose) | `deny-destructive.sh`, `permissions.deny` |

---

## Layout

- **This repo** — a **reusable OKF control-panel template**. `symlink/` holds generic machinery (SCHEMA, `AUTONOMY.md` — the deletable delegated-autonomy capability, `CONVENTIONS.md` — the shared role-agent conventions, read on dispatch because they govern the target repos, which no `paths:` glob can reach, role agents, `/pm-loop`, `/new-project`, `/close-project`, `/pr-review-request`, `/answer`, `/fanout`, `/audit`, `commit-as.sh`, `required-checks.sh`, `task-owner.sh`, `prune-worktrees.sh`, `close-project-folder.sh`, `validate-bundle.sh`, `migrate-bundle.sh`, `write-snapshot.sh`, `build-board.sh`, `print-board.sh`, `watch-board.sh`, `index-kb.sh`, `link-repos.sh`, a `SessionStart` hook for tasks-awaiting-you, a `UserPromptSubmit` hook pushing current instance state) symlinked into per-group **instances**; `seed/` holds starting content copied once; `install.sh` stamps out / refreshes an instance and manages its gitignore; `RETIRED` declares seed paths the template has stopped shipping, which are reported and never deleted. Each instance is its own repo under `~/workspace/<group>/_ai-bridge-<group>/` (leading underscore, named distinctly from this template dir). Keep machinery generic — org/repo/path/team/channel literals live in an instance's `instance.config.json` / `CLAUDE.md`, never in `symlink/`. <!-- This bullet was duplicated three times by conflict resolutions; it is now ONE line carrying the union of all three. If you resolve a conflict here, merge into this line — never append a second copy. -->
- **Not part of the `~/.claude` config layer.** ai-bridge used to live as an `ai-bridge/` subtree inside the [`ai-setup`](https://github.com/cbmono/ai-setup) repo, whose own root `install.sh` is scoped to `.claude` and never touched it. That separation is now physical: **this repo is the canonical copy**, an instance's machinery is symlinked from *this* checkout, and `ai-setup`'s installer has nothing to do with it. **`ai-setup` no longer carries that subtree at all** — [`ai-setup#69`](https://github.com/cbmono/ai-setup/pull/69) removed it, and its last state is in git history only (`git -C ai-setup show f8b09a4:ai-bridge/`), so a path under `ai-setup/ai-bridge/` does not exist rather than being stale. This sentence used to say the subtree was still there and frozen — which contradicted `README.md` and pointed maintainers at a checkout path that is gone. That is the same "documentation describes a deleted thing as live" defect that removing the subtree was meant to end, and the third instance of it corrected in this PR. `ai-setup`'s *config* layer briefly lived here too — forked wholesale under `config/` behind a second install target (`install.sh --config`) — but that fork is what caused 24 colliding `~/.claude` paths with 14 diverged, so it has since been handed back: `config/` now ships only the three agents ai-bridge itself probes for, and `~/.claude` is `ai-setup`'s alone again — see [15](#15-the-config-layer-is-one-tier-and-the-arrow-stays-one-way). The two halves share the worktree guard and nothing else.

---

## Conventions when editing

## 1. Retiring content is asymmetric

**Retiring content is asymmetric: machinery is swept, seed content is only reported.** A dangling symlink pointing into this template has exactly one possible meaning, so `install.sh` step 2b deletes it. A **seed** file does not — it was copied in once and has been the human's to edit ever since, and `todos.md` was literally their notes. `install.sh`'s safety property is that it only links and seeds-if-absent, never removing instance content, which is what makes it safe to run blindly on a repo full of someone's work; spending that to save one `rm` would be a bad trade. So retired seed paths are declared in `RETIRED` (`<path>\t<reason>`, tab-separated) and **reported with the exact `rm`**, and `upgrade.sh` puts them in the numbered "what's left for you" list — which is the whole point, since that list is what a collaborator actually reads. **Add the entry in the same commit that deletes the seed file, and never prune the manifest**: an instance stamped years ago still has the file, so a pruned entry stops answering for exactly the instances that need it. Absence of the file, an empty one, a comment, a blank line, or an entry naming a path an instance doesn't have are all silence, never an error. A **symlink** at a manifested path is step 2b's business, not this list's. Covered by `tests/retire-machinery.test.sh`.

## 2. Retiring machinery means deleting the file *and* letting `install.sh` sweep the links

Removing a capability from `symlink/` leaves every already-stamped instance with a symlink into a path that no longer exists, and the link loop never notices because it only iterates files that *do* exist. A dangling command still registers with Claude Code, and a `SessionStart` hook whose script has vanished exits 127 on every launch — so absence here is **not** safe, unlike the `AUTONOMY.md` pattern. `install.sh` step 2b sweeps them, and its test is narrow on purpose: a link is removed only when it points **into this template's `symlink/`** (decided by `ours`, not by name) **and** its target is gone — that combination has exactly one possible meaning. A real file, a link elsewhere, or a link that still resolves is left alone, and **seed content is never removed**: a `todos.md` outliving the retired `/todo` feature is the human's own writing, so it is reported, not deleted. Covered by `tests/retire-machinery.test.sh`.

## 3. `AWAITING.md` is ai-bridge's only status artifact, and it is opt-in by presence

There is deliberately **no `/status` command** (deleted in favour of this) and no full board — the file lists only what a human decision unblocks (✅ approve · ❓ answer · 🔀 merge · ⛔ unblock · 🏁 close), because in-flight and upcoming work needs no decision and a board people scroll past is a board they stop reading. **`install.sh` creates it on the first stamp only** (gated by `FIRST_STAMP`, computed before seeding), and the `project-manager` rewrites it each tick **only if it already exists, never creating it** — so `rm AWAITING.md` disables it permanently and an installer re-run must not resurrect it. That's the `AUTONOMY.md` absence-is-safe pattern with the default flipped: a new instance ships with the nudge working, rather than silently off until someone reads the docs. If you ever move creation out of the first-stamp guard, you break the off switch. `session-banner.sh` greps for the literal `## 🔴 Awaiting you` heading and asterisk-space bullets, so **the PM agent owns that exact layout** and reshaping either silently empties the startup nudge. The hook fences the items as **untrusted data** before they enter session context — the text comes from task docs carrying human questions, tool output, and PR metadata, and sits beside the hook's own instruction, so keep the boundary if you touch that output. Don't reintroduce a status command or the 🟡/🟢/⛔ sections.

## 4. A capability some deployments must not have should be *one deletable file*

…not a flag threaded through the machinery. `symlink/AUTONOMY.md` is the pattern: it holds every delegated-autonomy mode, and every other doc says only "…unless `AUTONOMY.md` exists — absent, every project is `gated`". Removing the file disables the capability with **no edits** to the eight documents that reference it, and `commit-as.sh` gates its promotion guard on the same presence check (fail-closed). When you add machinery like this, (a) make absence mean the safe behaviour, never an error; and (b) add a test case proving the capability is off when the file is gone (see `tests/commit-as-guard.test.sh`, and `tests/awaiting-queue.test.sh` for the same pattern applied to `AWAITING.md`). Don't reintroduce a partial variant of a mode that was deliberately collapsed into one all-out setting.

**One caveat the pattern does not cover.** `AUTONOMY.md` lives under `symlink/`, so it is *machinery*, and `install.sh` re-links every machinery file unconditionally — by design, since repairing broken links is what a refresh is for. The two collide: `rm AUTONOMY.md` disables autonomy for one instance, and the next `install.sh`/`upgrade.sh` run silently switches it back on. That is fail-**open** on the one capability that lets agents merge without asking, so `upgrade.sh` samples the file's presence *before* calling `install.sh` and reports the re-enable in its "what's left for you" list with the `rm` to undo it (covered by `tests/upgrade.test.sh`). Reporting was chosen over suppressing the re-link because a per-file exception in the machinery loop is exactly the threaded flag this bullet forbids. **A deletable capability made out of a file under `symlink/` inherits this hazard** — either put it in `seed/` (where seeds-if-absent still resurrects it, so guard it the way `AWAITING.md` is guarded by `FIRST_STAMP`) or make the disable a config key rather than an absence.

## 5. `build` and `research` projects are deliberately asymmetric

**Don't restore a question for symmetry.** `/new-project` asks a research project for *less*: no `target_repo`, no `clis` prompt (`clis` declares what a project's **agents** may use, and research dispatches none — the PM tracks, the human works in-session), and no step-8 scaffold review (the whole three-stage chain, not just its CodeRabbit stage). Each was removed because it describes machinery a research project never runs, so asking it makes the human authorise tools nothing will use; the CodeRabbit skip is the sharper case, since a code reviewer's real teeth (authorization holes, injection) find nothing in a markdown scaffold and the one check that matters — PII/secrets — has only `sources/README.md` to read at creation time. `browser` **is** still asked (web research is its clearest case). Be exact about what gets written, so nobody "restores" the prompt or invents a value: `/new-project` writes `clis:` **from the explicit `clis=` flag if one was passed, and otherwise as an empty list** — it neither asks nor probes, and it never substitutes a placeholder such as `none`, which would read as a declared capability named "none". `kind` must therefore be settled *before* the batched capability question, not inside it. Versioning needs no GitHub MCP: the bundle is itself a git repo and deliverables are committed via `commit-as.sh`.

## 6. The delegated merge gate resolves its required checks in `required-checks.sh`, and exit 0 is the only clearance

It prefers **branch protection** and falls back to `.github/required-checks.txt` on the PR's base branch, because a private GitHub repo on a free plan returns 403 from both the branch-protection and rulesets APIs — without a fallback, `yolo` merges are unexercisable by construction there. Keep the ordering (platform wins, so upgrading a plan is a no-op switchover that also binds human merges) and keep every ambiguity refusing: only `pass` clears, a declared name no check reports is drift not absence, and a PR editing the list is a human decision. Classify the platform probe on its **payload**, never its exit code, and recognise exactly **three** answers — JSON (protection spoke; an empty array legitimately falls through), the literal "no required checks" message (no protection; the fallback may answer), and **anything else ⇒ exit 2**. `gh pr checks --required` exits non-zero both when a required check *fails* and when no protection exists, so an exit-code test downgrades the gate; and a transient 5xx or expired token must never read as "nothing is required", which would swap protection-we-failed-to-read for a possibly weaker list. Note the message goes to **stderr** while JSON goes to stdout, so capture the two streams separately — never merged, or a stray `gh` warning prefixes the payload and a good answer classifies as garbage. Covered by `tests/required-checks.test.sh`; the stub there mirrors real `gh` quirks (a 404 body goes to **stdout**), so extend the stub rather than working around them in the script.

**The same clearance discipline, one layer over: a green check from a reviewer that DECLINED to review is not verification.** A hosted reviewer that hits its quota exits *successfully*, so its status check publishes `pass` — identical to the check on a PR it actually read. Three PRs went out in one tick on 2026-08-26: one was reviewed, two carried "Review limit reached. Next included review available in 44 minutes", all three were green, and both refusals merged — one shipping a shell script at mode `100644` that no caller can execute. So `review-clearance.sh` asserts a review **artifact that evidences a completed review**, and `required-checks.sh` asks it for one on **every** PR it is about to clear rather than deciding from a check's *name* whether a reviewer is involved. **Detect the refusal by LANGUAGE, never by the commit range it quotes** — the refusal comment carries the same `between <base> and <head>` line a real review carries, and on the PR that merged unreviewed that head was the PR head exactly, so a range-keyed detector reads a refusal as a review. Classify against the refusal table first and consider clearance only for what survives; reversing the two re-opens the hole, and `tests/review-clearance.test.sh` pins that exact false positive against the two recorded comment bodies in `tests/fixtures/reviewer/`. Every vendor fact lives in that script's tables, so switching reviewers is a row rather than a rewrite — and a missing or wrong row now costs a **refusal**, never a clearance. A missing `review-clearance.sh` makes `required-checks.sh` exit 2: without it the reviewer state is unknown, and unknown fails closed.

**Fail-closed is a property of the *caller*, and it has four edges — all four were open in the first cut.** (1) A **present-but-broken** sibling is worse than a missing one: `[ -x ]` tests a mode bit, so a dead shebang, a syntax error, a zero-byte file or a copy truncated mid-install all pass it and then fail every call — which used to read as "no required check is a reviewer's", consult no clearance, and report `ok: N required check(s) pass` on an unreviewed PR. The gate does not fail; it disappears. So the sibling must **prove it runs** (`--self-test`: two table-driven controls plus a sentinel string agreed between the two files, spelled out in both rather than sourced — sourcing the suspect file is the thing being tested for), and `--match-check` answers outside `{0,1}` are unknown state, never "no reviewer owns it". (2) **A check's NAME never settles whether anybody looked.** This used to be a table of vendor names and review phrasings, and `Codex Review` — or bare `Cursor` / `Copilot` / `Devin` / `PR Agent` — matched no row, read as plain CI and settled on its green bucket with zero artifacts read: the original incident with a 2026 vendor's name on it. A name table cannot be finished, so the table is **deleted** and clearance is asked for on every PR whatever its checks are called. (3) Clear each reviewer-owned name **against the reviewer that owns it** (`--for-check`), or on a two-reviewer repo one vendor's review clears the other vendor's refusing check; where no vendor owns any required name, one unscoped call still has to clear. (4) **Unbalanced code fences fail closed.** The fence stripper is a toggle, so one prepended ``` inverted it, blanked the rest of the body, and left the head test reading raw text — the recorded refusal cleared, from one character typed into a comment. An odd count now hands the **raw** body to refusal detection (where reading too much is safe) while the **clearing** side gets a strict rendering that is empty, so an unreadable body evidences nothing.

**And the fifth edge was the classifier's own default — five more routes, found by a second round of review.** (1) **Positive evidence is now REQUIRED**, because asking only "is this a refusal" and clearing everything else is default-allow: the reviewer's *"Currently processing new changes in this PR…"* placeholder, published on nearly every PR before it reads anything, exited 0. An artifact that evidences nothing is exit 4, and a placeholder is exit 1. (2) The **`okf-verdict` trailer is parsed, not grepped** — the marker alone on its line, a closing `-->`, and `verdict`/`reviewer`/`head_sha` present with the SHA equal to the head being cleared — and it is honoured only for an account named with `--reviewer` that is **not** a vendor in the table, because naming the vendor re-armed the highest tier in the file against that vendor's own refusal. It is parsed from a rendering with **indented** blocks stripped as well as fenced ones, and a block nested in an outer HTML comment (which GitHub renders blank) or left unclosed is discarded. (3) **`--self-test` proves the file RUNS, not that it is COMPLETE**: it sits near the top, so a copy truncated below it still passed while its tables were gone — 112 of 606 truncation points passed, 109 of those then cleared an unreviewed PR. The last line of the script is now a completeness sentinel the self-test asserts. (4) **A table that will not compile matches NOTHING**, which for a refusal table reads every refusal as a review; `grep` says 1 for "no match" and 2 for "bad pattern", so every row is compiled up front and every match checks the status. (5) **The reviewer logins are exact**, not `greptile.*` and `(qodo|codium).*` — a whole-string match ending in `.*` let `greptile-evil` and `qodo-attacker` pass as the vendor.

**Evidence and pinning come from the API; text matching only ever detects a refusal.** A review object's `state` (exactly `APPROVED`, `CHANGES_REQUESTED` or `COMMENTED`, compared case-sensitively against the API's own spellings) and its `commit_id`, read from `/repos/{o}/{r}/pulls/{n}/reviews`, are what clear it — not whether its body happens to mention the head SHA, which is precisely the property the *refusal* also has. A **comment** can still clear, because this repo's reviewer publishes a clean review as an issue comment and files no review object for it, but only on the vendor's own machine-emitted `<!-- … -->` review marker plus the head named as a bare token; every row of prose evidence (`i (have )?reviewed`, `lgtm`, `changes requested`) is **deleted**, since unanchored prose cleared quoted approvals and matched negated sentences like `Unreviewed <sha>`. The refusal table stays over-broad on purpose — a false refusal costs a human glance, a missed one costs an unreviewed merge — and it is outranked only by that machine marker, so `Review skipped — Auto incremental reviews are disabled` (above the walkthrough on **10 of this repo's 22 reviewed PRs**, because `.coderabbit.yaml` sets `auto_incremental_review: false` deliberately) does not unmake the review it sits in, while the reviewer's machine-readable rate-limit sentinel loses to nothing. **Expect exit 4 to be the common answer** — **18 of this repo's 35 PRs** carry a CodeRabbit review object and exactly **one** was made at that PR's final head — and read it as *stale, not absent*. Most PRs will need a review requested at the final head before they can clear. That is a real operating cost of the gate, not a threshold to tune away.

**Three things the move to the API cost or left open, and each is a rule rather than a patch.** (1) **A review object that says NOTHING is not evidence on its own.** The old body-SHA pin was wrong for every reason above, but in this one respect it failed closed — an empty body cannot name a head — so once `commit_id` became the pin, an **empty-bodied `COMMENTED` object at the head cleared over the reviewer's own verbatim rate-limit refusal at that same head**. `COMMENTED` is not a claim: the host mints one for any inline comment or thread reply (twelve empty ones sit in this repo's corpus), so an empty one evidences nothing (exit 4). An empty `APPROVED` / `CHANGES_REQUESTED` **is** a claim — the state is the verdict — but it is decided only after every artifact has been read, so a refusal **naming this head** still wins; an older refusal at another commit does not, because a PR that was skipped once has to be able to recover. **No corpus rescore can see this class**: it needs a PR carrying both shapes, and none does. Construct the case. (2) **The two body renderings must agree on what a fence is**, and they must agree with the *host's renderer*. The refusal side stripped leading whitespace before testing for a fence while the clearing side treated a ≥4-space or tab line as an indented code block, so an **indented fence hid the unconditional refusal sentinel** while a review marker outside it cleared — inverting the file's own invariant, which is that the strict rendering is a **subset** of the stripped one. One shared fence state machine serves both. (3) **A missing field silently switches a rule off.** An absent or empty PR-author login left both author comparisons testing against `""`, which no login equals, so SCHEMA.md clause 8 stopped applying and a reviewer could clear its own PR. Every PR has an author: not being told who it is is unknown state, exit 2.

**And making the two renderings agree with each other is not making them agree with the host — the round that claimed both had only done the first.** Three disagreements with CommonMark, each failing open, and all three reproduced against the recorded refusal: **blockquote containment was discarded**, so a fence opened at quote depth 1 was closed by a line at depth 0 and the refusal inside it vanished (that is the reviewer's *native idiom* — its notices arrive inside a `> [!WARNING]` blockquote, so this was reachable with no construction at all); **tabs were never expanded to four-column stops**, so `1–3 spaces + TAB` was markup here and literal code on the page, which let a comment merely *quoting* the `okf-verdict` trailer validate as a real verdict; and a closing fence's **run length and info string were ignored**, so a ```` ```` ```` opener closed by ``` ``` ``` paired — which also turns an odd number of markers even and defeats the unbalanced-fence net. The rule now measures containers and indentation in **columns** and carries the opener's quote depth, run length and info string. Two more of the same shape: **"content" must mean what RENDERS** (any non-whitespace byte counted a zero-width space or an empty `<!-- -->` as a claim, restoring (1) exactly), and **a refusal must be weighed before anything can be dropped** — one that names *no* commit is of unknown scope rather than an old one, a non-submitted review state can still carry a refusal, and an artifact whose author the host reports as `null` is unreadable state (exit 2), not an irrelevant one. **Nothing clears inside the classifier loop**, so the answer cannot depend on the order the host streamed the artifacts in.

**Enumerating what to remove is the defect; deciding what renders is the fix — and it made the file SMALLER.** Six rounds had each answered a route by adding a row, a character or a case, and the seventh's three routes were all the same shape again. (1) **The block machine models no containers**, so a construct that changes what ``` *means* put the refusal back behind a fence the host does not see: inside a raw-HTML block the content is HTML, and `<details>`/`<summary>` is the shape the recorded fixture is itself built from, so `<details>`, `<pre>`, `<div>` and `<table>` each cleared with the recorded refusal on the page — as did a fence that the host closes at the end of the **list item** holding it. The fix is not a list of block-level tag names: the machine is **read twice** — reading A is fences and blockquotes, reading B adds raw-HTML blocks and list items — and the **refusal side takes the union of the two readings while the clearing side takes the intersection**. A refusal must be code under *every* reading to disappear and a clearance must be markup under *every* one to count; `strict ⊆ stripped` becomes structural rather than tested; a reading may be crude in either direction; and the next construct is a **third reading**, not another case. (2) **"What renders" was a list of invisible characters**, and thirteen more code points went through it, along with `&#8203;`, `[//]: # ()` and `<div></div>`, which no character list reaches. Inverted: markup is removed *because it is markup* (HTML comments, tags, character references) and what must be **left** is an ASCII letter or digit. `print-board.sh` reaches the same conclusion from the terminal end — drop every code point in Unicode general category C, "one rule rather than a blocklist of known-bad sequences" — and its implementation is deliberately **not** reused, because it needs python3 and because category C would not cover U+115F, U+3164 or U+FE0F anyway. The cost, stated: a body with no ASCII alphanumeric at all is read as saying nothing, which is a refusal and a human glance. (3) **A header claim the code does not keep is a defect in itself.** "Prose cannot reach the evidence half" was false — the vendor's marker spelled inside an inline code span is visible text and matched anyway — so the evidence rows are now anchored to a **whole line** and the strict rendering drops multi-line code spans; and **issue comments are fetched paginated from the REST endpoint**, because `gh pr view --json comments` answers one page and the artifact that must never be lost is a *refusal*.

**Two models of a renderer cannot bound the distance from either to the renderer — so the oracle is the renderer.** The construction above says the refusal side keeps a line either reading keeps, and that was argued to make a crude reading cost at most a false refusal. It does not. **A union removes a line only when EVERY reading removes it** — it is an AND-gate over the readings, and a mistake they *share* is inherited by their union. Measured: a refusal spelled as three sibling list items (` - ``` ` / the words / ` - ``` `) was hidden by reading A, which models no list items, *and* by reading B, which ended an item only on a dedent — so the union hid it, while GitHub renders the middle line as an ordinary bullet. **A false clearance is reachable through the refusal side**, which is the one thing the construction existed to rule out. `strict ⊆ stripped` is still true and still structural; it was never the property that mattered. What replaces the argument is a measurement: `tests/fixtures/reviewer/host-rendering.txt` holds **154 bodies answered by github.com's own Markdown endpoint**, recorded by a script checked in beside it, and the suite asserts the two directions that cost something — *the host renders it as readable prose ⇒ the gate refuses*, and *the host puts the characters on the page ⇒ the gate does not clear*. Adding a reading is still how a construct is covered; "we added a reading, so it is safe" is not an argument.

**A test that cannot go red is worse than no test, because it is counted.** The property the previous round proved over 400 generated bodies — strict ⊆ stripped — is true of *any* intersection and union, so the sweep confirmed a shape rather than a behaviour and stayed green through every destructive mutant aimed at it, including on the day the union was hiding a refusal. The 22-row invisible-character battery beside it was the character list the fix had just deleted, kept as a test. Both are gone; the recorded host answers replaced them, and the suite got faster. **The same class caught the author too:** an over-escaped quote in a new test section left an unterminated string that swallowed nine assertions, and the suite reported them as absent rather than failing — found by a *surviving mutant*, not by reading the diff.

**A closed set is a decision; a growing set is an enumeration.** `renders_content` had been inverted to "remove markup, require a letter left", but it knew two markup *shapes* — an HTML comment and a tag — and eleven constructs github.com renders blank walked through it (`[//]: # (a comment)`, `[x]: /y`, `[](url)`, `![](/x.png)`, `<a href="1>2"></a>`, `<!DOCTYPE html>`, `<?php ?>`, `<!ENTITY x "y">` …), each one a review object with an empty page counting as a claim. The fix is not a longer list: CommonMark defines **exactly six** raw-HTML productions and there is no seventh, so all of them are implemented, alongside the two other places the source carries bytes the page never shows — a **link reference definition** and a link or image **destination**. And where the specification and the host disagree, **the host wins and it is recorded**: asked for `<![CDATA[a > b]]>` github.com answers ` b]]&gt;`, ending the construct at the first `>` exactly as it ends a declaration, so the CDATA production is *not* implemented and the case is in the fixture saying why.

**A hash is a whole token.** Matching a 7–40 character run of hex finds one inside every UUID — the reviewer stamps its own refusals with `Run ID: f4981ca2-…`, whose fields are runs of 8 and 12 — and that fed the one place the answer is used in the opening direction, where "it names some commit, and not this one" demotes a refusal to an older one. Cut the body into tokens on everything a hash cannot contain *first*, and a UUID field is joined to the rest by `-`, so the token is not hex. Both callers get safer: a pin is lost (no clearance) and a refusal keeps its weight.

**The residual, stated rather than glossed:** a refusal at this head **loses** to an artifact carrying evidence at this head. That is deliberate — the reviewer is rate-limited and then reviews the same commit — and the only way to tell it from "posted a reply with words in it" would be to read the reviewer's *prose*, which is the primitive this file exists to stop using. The operator is told on stderr when it happens.

**A corpus rescore is a change detector, not a correctness proof.** All 37 PRs, both versions, the same live GitHub state re-read from the API on each invocation (never a snapshot), **0 of 37 exit codes changed** — for five rounds running. That is a null result about *reachability*: every behavioural change in the last three rounds is unreachable in this corpus, so the rescore gives **zero coverage of the new logic**. It shows the gate was not widened; the evidence that a route is closed is the constructed case and its passing control.

## 7. `prune-worktrees.sh` is report-only, and that is load-bearing

It classifies worktrees and prints `git worktree remove` commands; it never deletes. The removal path was deleted in ai-bridge v2 because it had destroyed three running agents' worktrees, and because no first-party mechanism covers this root: native worktree isolation and its retention sweep only reach worktrees the harness itself created, of the **session** repo — measured, see the `worktree-isolation-spike` finding — while ai-bridge's live under `<reposRoot>/_wt` and are created by agents calling `git worktree add`. **Do not reintroduce a delete, not even behind a flag**; the auto-mode permission classifier independently refuses bulk worktree deletion, which is the same conclusion reached from the other side. The accepted cost is that the worktree root grows and draining it is a periodic human job.

**The classification guards still matter, because the labels are the product.**

- (a) A branch with **no commits of its own** is always `KEEP`: `git merge-base --is-ancestor HEAD origin/<default>` is true exactly when `rev-list --count origin/<default>..HEAD` is 0, so "already merged" and "fresh dispatch that hasn't committed" are the *same* set with no discriminator — the tie goes to KEEP, and the `branch-recycled-name` fixture is the only thing that sees a regression here (`gh pr list --head` matches by branch **name**, so a recycled name carries an old merged PR). In a repo on GitHub's default merge-commit strategy a *successfully merged* branch is an ancestor and so never reaches `REMOVABLE`; squash-merging repos are unaffected. Note the script treats a **closed** PR as finished too, so a clean branch whose PR was closed unmerged can still be `REMOVABLE` anywhere — the merge-strategy caveat is about merged branches only.
- (b) **Count, never compare** — `HEAD == origin/<default>` is the trap two independent implementations fell into ten days apart, and it breaks the moment anything merges.
- (c) A **detached-HEAD** worktree is never labelled `REMOVABLE`: it has no branch ref, so removing it destroys its only reachability (HEAD + the per-worktree reflog). It reports `RECLAIMABLE` for a human to judge.
- (d) The `PRUNE_ACTIVE_MINUTES` mtime veto must stay **recursive** (an agent editing `src/**` never touches the root's mtime; measured 39 ms on a 664 MB repo), and the caller-side rule survives beside it: the PM reports only when its in-flight count is zero.

Also: `worktreeRoot` is optional, and **every doc naming it must state the fallback** (`<reposRoot>/_wt`), since the docs are symlinked into instances whose config predates the key. Covered by `tests/prune-worktrees.test.sh` (43 assertions), which lives outside `symlink/` deliberately — everything under `symlink/` ships into every instance, and a fixture harness is not machinery an instance needs.

## 8. `validate-bundle.sh` was scoped by measuring first, and that is the point

Before it was written, three live instances (~570 documents) were checked by hand. That measurement was **partly wrong, and the script found the error**: the hand pass sampled only Objective/Project/Phase/Task and reported **0** enum violations, while `knowledge/` — Finding and Service, never sampled — holds **23** (Findings marked `open`/`active` against `current|superseded`; six Services marked `current`, the Finding enum applied to a Service). It also found **16** documents with no `timestamp`, and **15 of 115** frontmatter cross-references dangling. So both halves earn their place: **referential integrity was the motivating rot, and enum drift turned out to be real too — concentrated exactly where the sample did not look.** The lesson is about sampling, not about enums — `/close-project` removes a project folder by design, and one closure had left 38 dangling `depends_on:` refs across two surviving projects. Two things the v2 plan asked for were dropped on the same evidence: a required **`id`** (the path is already the identifier, so a second one can only drift) and renaming `timestamp` to **`updated`** (OKF names it `timestamp`). Validate only the schema-defined locations — the first version also checked `index.md`, `log.md`, `sources/` and `deliverables/`, and buried 6 real errors under 77 warnings, which is how a validator teaches people to ignore it. `artifacts:` warns rather than fails, because a research task legitimately declares a deliverable before writing it. Covered by `tests/validate-bundle.test.sh` (40 assertions), including the ignored-files property.

## 9. `migrate-bundle.sh` fixes only what has one right answer, and is report-only by default

It repairs the mechanical `validate-bundle.sh` errors — a `Finding` status of exactly `open` or `active` (both mean "still applies") → `current`, a `Service` status of exactly `current` (the Finding enum applied to a Service) → `active`, and a missing `timestamp`, filled from **git**: the author date of the commit that added the file. **The mapping list is closed**, and that matters: an unrecognised value — a typo, or a lifecycle state nobody has seen — carries a meaning the script cannot read, so normalising it to a fixed value would destroy that meaning while looking like a repair. Held for a human instead.

**Three refusals are the design.** A file git cannot date is skipped, not given an invented date — a wrong timestamp is indistinguishable from a right one, which is worse than the error it replaces. And a **dangling reference is never rewritten**: whether to drop a `depends_on:` depends on whether the task it pointed at finished, and once that project folder is gone the state is unknowable from the bundle — so it belongs in `/close-project` step 6, while the source task is still readable. Default is a report; `--apply` writes. Same reasoning as `prune-worktrees.sh`: a script that edits many files should not be one keystroke from doing it.

Writes through a temp file **beside** the target carrying the target's mode, never `$TMPDIR`: `mktemp` creates 0600, so a rename from there would silently make every repaired document 0600, and a cross-filesystem `mv` degrades to copy-and-remove, where an interruption leaves a half-written file. **Every write is verified after it lands, and a claimed-but-absent write prints FAILED and exits 1.** That guard is there because the script once printed `FIXED` for a write it never made, on a real bundle: `add_field` inserts before the *second* `---`, and a document whose frontmatter never closes has only one, so the insert silently no-opped while the counter incremented. Such a document is now skipped up front — it is malformed, which is a content decision, and `validate-bundle.sh` names it precisely. **A false success is worse than the error it claims to fix**, so treat any silent no-op path here as a bug. Idempotent, and covered by `tests/migrate-bundle.test.sh` (46 assertions, most of them about the refusals).

## 10. The scaffold review is a three-stage chain with a declared fallback, never a skip

`/new-project` step 8 runs `validate-bundle.sh` first (deterministic, free, and the consistency class is exactly what a fresh scaffold gets wrong — an external reviewer re-deriving a dangling path from prose spends a whole session reaching a conclusion `grep` already had), then an **external reviewer** (CodeRabbit or equivalent), then **`qa-reviewer` mode C** when no *usable* external reviewer is available — absent, unauthenticated or erroring alike. Step 8 used to skip to nothing there, which contradicted `SCHEMA.md`'s merge-time gate — that has always read "an external one when the repo configures it, **else the `qa-reviewer` agent**" — and left a project scaffolded on a CLI-less machine with no second opinion at all. **Mode C is not mode B with the PR removed:** there is no PR, no CI and no target repo, so it reads `git diff <pre-commit-sha>..HEAD -- projects/<slug>` and writes its verdict into the project's `log.md`. Because it reads `SCHEMA.md`, it must **not** raise step 8c's by-design findings (empty `acceptance_criteria`, `draft` status, empty `pr:`, committing to `main`) — one of those appearing is a bug in the agent, not a finding to triage. Keep every stage advisory: none of them gates project creation. One environment trap worth keeping documented: CodeRabbit needs a base branch, and a remote-less instance has no `origin/HEAD` to infer one from, so it fails with "Unable to determine base branch" until `git config coderabbit.baseBranch` is set — and falls back to the free CLI allowance regardless.

## 11. The cross-instance board is a writer, three renderers and one deletable, generated file

**…and every piece of that is deliberate.** `write-snapshot.sh` derives `SNAPSHOT.json` at the bundle root from the schema-defined locations; three renderers turn one or more snapshots into a page or a table. Five invariants.

- **(a) Absence is the off switch, and the file is generated ROOT content — never a file under `symlink/`.** The writer rewrites it only when it already exists, `install.sh` creates it on the **first stamp only** (`FIRST_STAMP`), and the renderer leaves a snapshot-less instance off the page entirely, with no placeholder. That is the `AWAITING.md` pattern, and putting the file under `symlink/` instead would inherit the `AUTONOMY.md` hazard directly above — machinery is re-linked unconditionally, so a per-instance `rm` comes back by itself.
- **(b) The field list is a data-governance boundary, not a format.** The board's HTML can be *published*, while `AWAITING.md` never leaves the instance, so the snapshot carries strictly less: titles, statuses, an assignee **role**, an awaiting **verb**, an open-question **count**, PR links — never a task `description:`, never a document body, never the **text** of a question or a blocker, never `authorEmail`, never a path outside the bundle (the page names an instance by its directory **name**, not its path). Titles are carried because a board without them is unreadable, which is exactly why the JSON states in its own `_sensitivity` key that it is as sensitive as the task documents it derives from. Read that header before adding a field; `tests/snapshot.test.sh` asserts that no key outside the documented set is emitted, so a field added without reading it fails there rather than on a published page. **One identity field crosses that line by decision rather than by drift**: a project's `owner`, a GitHub *username*. It was on the excluded side until 2026-08-26, when artifact publishing turned out to be **account-scoped** — each human publishes their own board, and a board that cannot say whose project is whose cannot do the one thing it is now for. The reversal is written into `write-snapshot.sh`'s own header instead of being made quietly, because a rule and a behaviour that contradict each other leave the next reader no way to tell which is current; `authorEmail` stays excluded beside it, and the collapse on the other owners' section is ergonomics — their names are in the published HTML either way, and the page says so.
- **(c) Untrusted text, published sink.** Every snapshot string is HTML-escaped at one point, a PR URL becomes a link only on an http/https scheme, the page's only external request is one declared webfont, and its single `<script>` (a clipboard helper) receives nothing from a snapshot — collapsing is `<details>`, not JavaScript. That last clause used to read "zero external requests and no `<script>` at all", which described the kanban `columns` page; that page was rejected by the owner as unreadable and **deleted** on 2026-08-24, so the invariant now names what the published board actually does. Discovery is explicit — named dirs, else `boardInstances` in `instance.config.json`, and **if that key is absent or empty, just this instance** — never a glob, because the script is symlinked into instances whose workspace layout it cannot know. `build-board.sh` is the one script here that uses `python3` (stdlib), justified in its header: a hand-rolled awk JSON reader mis-handling a quote inside a title is precisely the bug that turns an untrusted title into markup on a published page.
- **(d) A snapshot's TYPES are untrusted too, not just its text, and one drifted instance must not blank the board for the rest.** "Malformed" splits in two and only one half is a parse error: unparseable JSON — or a top level that is not an object, which raises `AttributeError` rather than `ValueError` and so needs its own `isinstance` check — becomes a named "Unreadable snapshot" note, but **valid JSON carrying wrong types** (`"tasks": "many"`, an `"order"` of `"first"`, a non-string `group`) parses cleanly and only surfaces later at an `int()` or a sort comparison, where an uncaught `ValueError`/`TypeError` means **no output file is written at all** — every healthy instance goes down with the drifted one. So every number goes through one `toint()` helper and `group` is forced to `str()`: the bad field degrades to `0` and everything else still renders. Don't reintroduce a bare `int()` on snapshot data, and note that the same reasoning makes portability a correctness issue in the writer — a GNU-only regex escape like `\b` is a wrong *answer* on a grep that lacks it, not an error, so the test keeps a static check that none has come back.

- **(e) The renderers are presentation over a settled contract, and that is what makes each one after the first cheap.** Three now read the same snapshot: `build-board.sh` (an HTML page you may publish), `print-board.sh` (columns in a terminal) and `watch-board.sh` (a local page kept fresh, which reuses `build-board.sh` rather than forking its markup — two pages to keep escaping correctly is one page too many). None of them reads the bundle, so (a)–(d) hold for all of them without being re-implemented. Three things follow. **Escaping is per-MEDIUM, not one shared routine:** a terminal's metacharacters are worse than HTML's, because ESC repaints what the reader has already read and a newline forges a ROW — a board reporting work nobody has — so `print-board.sh` drops every code point in Unicode general category C rather than blocklisting known-bad sequences. **Colour is a TTY property**: piped output carries no escape byte (`NO_COLOR` honoured), or every board redirected into a file or a ticket is corrupted. **A number is never truncated** — narrowing drops whole all-zero columns, naming them, and clips names; a clipped count is a *wrong* number and indistinguishable from a right one. And the watcher's cost is stated in the docs where someone chooses a renderer, not buried: it needs a resident process, which ai-bridge deliberately does not have, which is the same constraint that made munder-difflin's live telemetry unreachable. `fswatch` is probed and never assumed, degrading to a polling loop (`--interval`, default **2** seconds) with `WATCH_BOARD_WATCHER` (`auto` when absent) overriding the probe. The watcher refreshes only **this** instance's snapshot: an earlier version ran the writer in every watched directory, so a watcher started in one group rewrote another group's file every two seconds.

Covered by `tests/snapshot.test.sh` (146 assertions, mostly negative) for the writer and the HTML board, and `tests/board-renderers.test.sh` (155) for the terminal board and the watcher.

## 12. Three ai-bridge behaviours that all exist because a *silent* wrong answer is worse than a loud one

**(a) `push-state.sh`** (a `UserPromptSubmit` hook) restates current instance state every turn, because "told to read `fleet.json`" is not "always knows" — `/pm-loop` is a long-lived session whose context still describes tick one after five ticks, and a stale roster is corrected only by a **newer statement** of the truth, so the injection says out loud that it supersedes any earlier count. It must stay **self-detecting** (silent outside an instance root — it ships in `symlink/.claude/settings.json`, so a version that printed elsewhere would fire on every turn of every unrelated project) and it must **always print inside one, zeros included**, because an absent line is indistinguishable from a broken hook and `in-flight 0` is exactly the correction a session remembering three live dispatches needs. It emits **slugs and task ids only, never task `title:` prose** — that would multiply the per-turn cost for no correlation value — fences them as untrusted data, and caps each list at `PUSH_STATE_MAX` (default 12) while reporting what it dropped.

The sharpest guard in `tests/push-state.test.sh` (84 assertions) is a regression test for a real bug: awk is fatal on a file it cannot open and its stdout is a block-buffered pipe, so **one unreadable task document lost the output for every file already scanned** and the hook printed an authoritative `in-flight 0` — three lines above its own claim to supersede the true count. `collect()` therefore drops unreadable files; treat any path that can emit a **false zero** here as the same class of bug as `migrate-bundle.sh`'s false `FIXED`.

Three later fixes are the same lesson from a different direction, and all three are about values the bundle's own **filenames** carry.

- (i) Every file-derived value is **encoded to one line** in `FM_PROG` — a slug, task id and phase stem are filenames, and both macOS and Linux permit a newline, a carriage return and a tab inside one. Raw, a CR let a directory print `--- END INSTANCE STATE ---` as its **own line**, putting everything after it — this hook's own closing instruction included — **outside** the untrusted-data fence; an LF split an awk record so `mmm<LF>qqq` was reported as `qqq` and, when the surviving fragment began with `-`, `basename` option-parsed it and the whole injection became three lines of usage text; and a TAB collided with the field separator so the project **and** its in-flight tasks vanished from the counts. awk is the **single choke point** for that encoding, because it is the only place file-derived text enters — do **not** add a second sanitising pass over the assembled line, which would mask the very regression the test watches for, and keep the item **surfaced** rather than filtered (the `awaiting-queue.test.sh` rule: a slug you cannot see is a slug you cannot fix). The accepted cost is that such a path no longer resolves on disk, so that project's phase is not looked up.
- (ii) Only the **first** frontmatter `status:` counts, via a per-file flag: printing every match let a document with a repeated key be listed twice, counted twice, and classified from the **later** value.
- (iii) `PUSH_STATE_MAX` is normalised with `$((10#…))` before any arithmetic — the digit check accepts a leading zero and the two uses then disagree, since `[ n -le 08 ]` reads decimal while `$((n-08))` reads octal, so the list was capped correctly while the `(+N not listed)` notice died on an invalid octal digit (and `010` quietly reported four dropped when it dropped two).

**(b) An answered question is moved, never deleted**: it goes from `open_questions` into `answered_questions` as one flat line, `<ISO 8601> · <the entry verbatim>`. Flat, not a nested `{q, a, askedAt}` mapping, because `open_questions` already carries question and answer on one line either side of the ` --- ` delimiter, so *moving* the line preserves both with **zero new parsing** — and the bundle's tooling is bash + awk by contract, which cannot read nested YAML. It is **not machine-read**: `open_questions` emptying stays the only promotion signal (an entry left in both lists blocks the draft forever), and `validate-bundle.sh` deliberately gains **no check** — a free-text list is neither an enum nor a reference, and a "missing delimiter" warning is precisely the noise that file's own scoping rule says buries real errors. `validate-bundle.test.sh` instead asserts the validator stays **silent** on a task carrying the key, so a later noisy check fails there. Because these are human answers that now persist for the life of the repo, every doc documenting the convention carries the **no-customer-PII** caution.

**(c) `maxPrLoc`** (`instance.config.json`, **500** when the key is absent — state that fallback in *every* doc naming it, the `worktreeRoot` rule, since the docs are symlinked into instances whose config predates the key) makes a PR-opening role agent **propose** a split and open the PR anyway; generated boilerplate, codemods and dense logic all move the real number, so it is never a block and never a review finding.

## 13. A shared instance is three no-ops and one gate

The gate is on the wrong verb if you get it backwards. The full reasoning — ownership resolution vs. comparison, why `defaultOwner` must stay tracked-only, the per-instance `people` map, the per-machine override set, and the derived-index split — lives in **[docs/sharing.md](sharing.md)**, because it is one topic and splitting it would leave half the argument on each side.

## 14. `knowledge/references/` is the fifth knowledge kind

**…and promoting it was a two-line change because the location filter was never a list of four names.** `validate-bundle.sh` collects `knowledge/<kind>/*.md` as a *shape*, so the one live instance's 7 `type: Reference` documents were already being checked for `type`, `timestamp` and dangling refs — measured, 0 findings. The only gap was `status`, unchecked because `Reference` had no enum, which left invisible exactly the drift class the script was built for (one type's enum applied to another: `open` on a Reference reads as a Finding). So the fix is `Reference) echo "current superseded"` plus the `SCHEMA.md` section — all 7 already carry `current`, so it is a no-op on live data and a real check on the next edit. Declaring the enum also makes `status` **required** there; root documents typed `Reference` (`SCHEMA.md`, `AUTONOMY.md`) carry none and are unaffected, because they sit outside every schema-defined location. Relocating those documents into `findings/` was rejected: they are specs and contracts, not one decision each, and moving someone's content to satisfy a validator that already reads it is the wrong direction.

## 15. The config layer is one tier, and the arrow stays one-way

**ai-bridge depended on a separate repo for four things, and all four failed silently.**
The measurement that forced this: **nine** top-level entries of the live `~/.claude` were
symlinks into that other checkout, so "it will never be used again" was false on the very
machine running ai-bridge — it was the parent config layer of every session, instances
included. Four of those entries were load-bearing here: the `@~/.claude/claude-defaults.md`
import in `seed/CLAUDE.md` (the hard one — every new instance inherited it), and probed
lookups for `code-architect`, `deep-bug-scan` and `plan-architect`. A missing `@import` is
a **no-op** and a failed `test -f` merely skips a fan-out, so on a machine that never ran
that installer an instance lost its session defaults, `qa-reviewer` lost its second opinion
and the PM lost its plan critic — and nobody could tell. **Silent degradation is the worst
shape a failure can take**, which is the whole argument for folding the layer in.

**The import is INLINED, not re-pointed.** An `@import` is loaded at launch anyway, so a
separate file bought organisation rather than context — and it bought one more thing that
could dangle. The section now lives in `seed/CLAUDE.md` itself. Seed content is copied only
when absent, though, so an instance stamped earlier keeps the dead import forever:
`install.sh` reports it with the exact replacement and **never edits `CLAUDE.md`**, which
is instance data the human owns and has very likely edited around. Report-only, the same
contract as `RETIRED`.

**One tier now, and it ships only what ai-bridge itself needs.** `config/required/` — the
three agents (`code-architect`, `deep-bug-scan`, `plan-architect`) ai-bridge's own role
agents probe for with `test -f` — is the entire config layer. `config/opinionated/`, the
second tier this section used to describe (one person's commands, output style, hooks and
scripts, the only place in this repo a company's internal tool could be named — `/dave`),
is **gone**: it was a fork of `ai-setup`'s `.claude/` tree, 24 of its 26 installable
entries collided with ai-setup's own, 14 had diverged in both directions, and ownership was
decided by whichever installer ran last. `ai-setup` now owns
`${CLAUDE_CONFIG_DIR:-~/.claude}` outright and received every fix the fork had made that it
lacked; see [`docs/claude-config-ownership.md`](claude-config-ownership.md) for the full
accounting. **Deleting the tier is still safe** — the `AUTONOMY.md` pattern applied to the
one directory that is left, with `--config` linking whatever files remain and erroring
nowhere. (Deleting `config/` *itself* is a different thing and exits 2: a refusal to do
nothing, not a breakage.)

**"Deleting the tier" means removing the DIRECTORY, and the distinction is now load-bearing
rather than pedantic.** `--config` retires a link by asking whether its target is still in
the discovered source set, so an *empty* set reads as "retire everything" — and a source
directory that cannot be listed produces exactly the same empty set as one that is gone.
Measured on a real upgrade fixture, three permission modes, all identical: **exit 0, every
link retired including the ones this layer still ships, none left, no warning**, and the
quietest mode printed nothing on stderr at all. Keeping `find`'s exit status does not close
that: `find . -type f` in a directory that is unreadable but executable exits **0** with no
output. So the guard is stated over the two sets instead — *discovery returned nothing while
links into `config/` still exist* ⇒ **refuse, name it, exit non-zero, retire nothing** — and
a tier directory that is **absent** is what distinguishes the legitimate `rm -rf
config/required` from a tier we merely could not read. A tier emptied but left in place
therefore lands on the refusing side, and says so: remove the directory, or run
`--config --uninstall`, if that is what you meant. A second refusal covers the case the set
statement structurally cannot see — one unreadable subdirectory among several readable ones
still yields files, so the set is not empty while the links beneath it read as dangling.

**The arrow stays one-way, and that is what makes this modular rather than merely
bundled.** `symlink/` must never *require* `config/`: the role agents keep probing with
`test -f`, so an instance stamped on a machine that never ran `--config` still works — it
loses `qa-reviewer`'s Opus **escalation** (the cheap `/code-review low` second opinion needs
nothing installed) and the PM's plan critic, not a feature. The bare `install.sh <dir>` interface is unchanged
for the same reason: three live instances and `upgrade.sh` call it that way, so
`--instance` is only its explicit spelling and never a new requirement.

**No drop-in directory is ever linked as a directory.** `agents/`, `commands/` and
`skills/` receive new subdirectories from skill and plugin installers at any time, so a
whole-directory symlink aims them at this checkout and every drop-in lands inside a public
git repo. Not hypothetical: it is how four uninvited skills got committed to `ai-setup` on
2026-08-22, three of them symlinks to a path that existed under `~/.claude` but not in the
repo — dead links its installer would then have pushed into every consumer's config dir.
Two fixes were available: carry that repo's `.gitignore` allow-list (`.claude/skills/*`
denied, one `!` per shipped skill) plus its test, or link per **file**. **Per-file linking
was chosen because it removes the hazard instead of policing it** — nothing this installer
creates is a directory link, so a drop-in cannot reach *this* checkout at all and no
allow-list has to be maintained as skills come and go. It does not make every directory in
the config dir real: `ai-setup` links `~/.claude/agents` as a unit, so on a machine that ran
its installer the parent of our three agents is a symlink, which is why (a) below is a
conditional refusal rather than a flat one. It also
gives back the slot the allow-list approach costs: a personal global command can live in
`~/.claude/commands/` beside the linked ones, which a whole-dir link makes impossible.

**A conditional refusal, a retired guard, and an abstention complete it.** (a) `--config`
never writes *through* a symlinked directory — if `~/.claude/agents` is a link into another
checkout, writing `agents/x.md` would create a file **inside that other repo**, silently,
and leave the config dir with nothing of its own. The answer depends on whether the entry
already resolves through that link, and both halves matter: `ai-setup` links
`~/.claude/agents` as a whole directory, so a symlinked parent is **the normal
configuration** on any machine that ran its installer, not an error. When the path resolves,
that provider is shipping it — the required tier's contract is that the file EXISTS on this
machine, not that our copy is the one used — so it is **reported and nothing is written**,
exit 0. When it does not resolve, nobody ships it and we cannot write it: refuse, name the
directory, print the `mv` that fixes it, exit non-zero. Refusing in *both* cases would make
`--config` fail on the normal setup and make the two installers order-dependent, which is
the whole thing this split removes. (b) The old refusal for two tiers declaring the same
relative path — whichever ran second would move the first aside as a `.bak` and shadow
it — is **gone**, not because the risk went away but because it cannot fire any more: there
is one tier. What holds the invariant now is `tests/config-ownership.test.sh`, which derives
the whole shippable set from the `test -f` probes in `symlink/` and cannot name the tier
directories it scans, with the tier names pinned separately against `install.sh`'s own
`CONFIG_TIERS` in both directions — so a second tier could not reappear here unnoticed, under
its old name or a new one. (c) **`settings.json` is not this layer's file at all.** It is not
shipped, not linked, not backed up, not merged, and not reported on; `tests/config-layer.test.sh`
asserts a real one is left untouched and **not even mentioned**. It is the one path in the
config dir that can already hold permissions, env vars and plugin choices somebody tuned by
hand — the only place where writing a value could widen what Claude is allowed to *do* rather
than how it reports — so two installers writing it is exactly the collision the ownership
split removes. `ai-setup` owns it, including the display-only merge into an established real
one, and — from [`ai-setup#71`](https://github.com/cbmono/ai-setup/pull/71), which lands
before this change for exactly this reason — it **adopts a `settings.json` that is a symlink
into some other checkout**: a symlink holds a path rather than a file, so there is nothing
of the human's there to protect, and declining left the path installed by nobody once this
layer retired its own link. Stated with the source because the tense matters: *before* that
change ai-setup declined, and this is the sentence a reader would otherwise use to conclude
the loss cannot happen. `tests/config-ownership.test.sh`'s cross-repo group runs ai-setup's
own installer from that starting state and fails if it declines, so the claim is checked
against the code rather than asserted here. `--config` therefore stays purely additive — every write it makes is a symlink it
created itself — and the paths it retires are not left unexplained: it names `cbmono/ai-setup`
as where they went.

The worktree guard covers both halves, because it runs before the flags are parsed — a
config install from a worktree fails identically, every link pointing into a checkout that
is about to be deleted. Covered by `tests/config-layer.test.sh`.


## 16. The kill switch is one hook, and it fails open

ai-bridge could dispatch a role agent but not **redirect or cleanly stop** one. A bad
dispatch ran to completion or was killed, and a kill mid-worktree leaves the worktree and
its index in whatever state the agent had reached — which nothing then cleans up, because
`prune-worktrees.sh` is report-only ([7](#7-prune-worktreessh-is-report-only-and-that-is-load-bearing)).
With `AUTONOMY.md` present an agent commits, pushes and merges without asking, and the
only counter-metric is `/audit`, which is retrospective and slow-cadence. So the missing
piece was a **live** one: `.claude/hooks/agent-control.sh` (a `PreToolUse` hook) plus
`scripts/control.sh` (the operator side), supporting `gate`, `steer` and `halt` against
one agent.

**It is keyed on `agent_id`, and that was measured rather than assumed.** A spike proved
two things: `PreToolUse` *does* fire for a dispatched subagent's own tool calls, and the
payload carries `agent_id` / `agent_type` on the subagent's event while the parent's
`Agent` call carries neither. The trap it closed is the important half — **`session_id`
and `transcript_path` are IDENTICAL for parent and subagent**, so a design keyed on
either would silently have been all-or-nothing: halt one agent, lose the human's own
session with it. Two properties follow and both are load-bearing: the *presence* of
`agent_id` is the parent-vs-subagent test with no heuristic, and an absent `agent_id`
therefore means **exit 0 immediately** — this hook can never gate the parent. There is
deliberately **no all-agents wildcard**, because it would reintroduce exactly the failure
the measurement exists to have avoided. This is the third scoping assumption in the
project to have been wrong (native worktree isolation, `paths:` globs, nearly this one),
so treat "does this identifier distinguish what I think it does?" as always needing a
measurement.

**Absence is the safe default, and the state deliberately lives nowhere in `symlink/`.**
No `.claude/control/` directory ⇒ the hook is a strict no-op: no read, no write, no
output, exit 0. That is the `AUTONOMY.md` idiom
([4](#4-a-capability-some-deployments-must-not-have-should-be-one-deletable-file)), but it
could **not** be a file under `symlink/`, because machinery is re-linked unconditionally
and a per-instance `rm` would come back by itself. The directory is runtime state that
`control.sh arm` creates and `disarm` removes. It carries a `.gitignore` holding a single
`*`, which ignores every file in the directory **including itself**, so git sees the
directory as empty and tracks none of it — and that is not cosmetic: committed, this state
would travel to another clone of a shared bundle and gate that human's agents from a file
they never wrote. Doing it that way also keeps the whole feature out of `install.sh` and
out of `seed/.gitignore`, so it behaves identically on an instance stamped today and one
stamped a year ago, with no installer run and no seed delivery.

**Fail open, loudly — this is the one place where a refusal is the worse error.** The hook
sits in front of *every* tool call in *every* session of the instance. No `jq`, an
unparseable payload, an unreadable or malformed control file, a verb it does not
recognise: all of them log and **let the call through**. A hook that blocks work because
its own state file is corrupt is worse than no hook. The exit code is never used to signal
a refusal (exit 2 would block); a refusal is JSON on stdout and the script's only exit
status is 0. `set -e` is deliberately absent — with it, an unexpected non-zero becomes a
"non-blocking error" printed on every single tool call for no gain. An unrecognised verb
is the sharpest case: it carries a meaning the hook cannot read, so honouring it as a
denial would be inventing one, exactly the closed-mapping reasoning
[9](#9-migrate-bundlesh-fixes-only-what-has-one-right-answer-and-is-report-only-by-default)
records.

**`jq` is a hard requirement, and the reason is spoofing.** `tool_input` is arbitrary
nested JSON, so a grep/sed parser hunting for `"agent_id"` can be fooled by that string
appearing *inside* a tool argument — a Bash command containing
`"agent_id": "some-other-id"` would let a halted agent walk past its own halt. jq reads
the top-level key and cannot be fooled that way. Since the hook must fail *open* without
jq, the refusal is moved to `control.sh arm`, which is the one moment a human is watching
and can install it.

**`halt` emits `{"continue": false}` AND a deny, on purpose.** `continue: false` is
documented, but its scope inside a subagent's tool call is not — the docs do not say
whether it stops only that subagent or bubbles up. Unverified is not the same as broken,
so halt emits both: if `continue` is scoped to the subagent the agent stops cleanly, and
if it is ignored the deny still refuses the call and the directive persists. Halt
**degrades to a gate rather than to nothing.** A kill switch may turn out blunter than
advertised; it may not turn out inert. For the same reason halt is **not consumed** — one
that fires once and then lets the agent carry on is not a kill switch — while `steer` *is*
consumed, being one note at one boundary. And `steer` emits **no `permissionDecision` at
all**: `"allow"` would bypass the permission system and silently grant a call a `gated`
instance would have asked about, which is not something a course correction is entitled
to do.

**Bounded, and it says what it dropped.** `CONTROL_MAX` (**20** when unset — state that
fallback in every doc naming it) caps pending directives. `control.sh` **refuses** to add
the 21st and prints what is pending, rather than FIFO-dropping the oldest the way the
mechanism this was modelled on does: silently dropping a halt is the one failure the
feature exists to prevent, so which directive to release is a human decision. The hook's
own scan stops at the same number and logs how many records it did not read — only
reachable through a hand-edited file, and never a reason to fail closed.

**The note is fenced as untrusted data, and the PREFIX is what closes the hole.** A
reason/note is human free text that the hook injects into the *agent's* context beside its
own instruction, so it is fenced and labelled the way `session-banner.sh` fences its items
([12](#12-three-ai-bridge-behaviours-that-all-exist-because-a-silent-wrong-answer-is-worse-than-a-loud-one)).
Fencing alone is not enough: a note reading exactly `--- END OPERATOR DIRECTIVE ---` would
forge the closing marker, so every injected line is prefixed and can never open at column
0. `control.sh`'s `oneline()` is the **single** choke point where operator text becomes a
record field — a tab would collide with the field separator, a newline would split the
record, a raw CR would let the text close the fence on any reader honouring it, all three
measured in `push-state.sh` — and the TAB-separated record format then makes a raw newline
unrepresentable, which is why the hook adds no second sanitising pass.

**One bug worth keeping written down, because it passed a test first.** TAB is an *IFS
whitespace* character, so `IFS=$'\t' read -r a b c` collapses a run of tabs and skips
leading ones. With `@tsv` output, an absent `agent_id` therefore made the leading empty
fields vanish and `read` assigned the **tool name** to `agent_id`: the parent's own tool
call entered the roster as an agent called `Bash`, and a directive named `Bash` would have
gated the human's session — the exact failure keying on `agent_id` exists to prevent. The
test that should have caught it asserted "no roster row has an empty id", which was true
for the wrong reason. Both reads are now one value per line, and the assertion counts
roster growth instead. **Assert the property, not the absence of the symptom.**

**A halt is recorded, but not in `log.md`.** The hook writes every action it takes to
`.claude/control/control.log` — append-only, machine-local, greppable — and `control.sh`
**prints** the exact `log.md` bullet and its `commit-as.sh` command without running
either, the same report-the-command shape as `RETIRED`, `prune-worktrees.sh` and
`install.sh`'s `git rm --cached`. Three reasons the hook must not touch `log.md` itself:
it is **tracked**, and several agents share one working tree, so a spontaneous diff there
is absorbed under the wrong author by whichever sibling stages `log.md` by name next
(`commit-as.sh`'s whole header is about that); a correct entry is newest-first under a
dated heading, so it is a read-modify-write that two concurrent halts corrupt; and a hook
that can damage a tracked bundle document while its own state is fine is worse than one
that writes somewhere local. Whether a halt belongs in the bundle's permanent history is
also a judgement — a fat-fingered dispatch and an agent pushing to the wrong repo are not
the same event.

**Two honest limits.** A halt takes effect at the agent's **next tool call**: it does not
interrupt a command already running, and an agent making no tool calls is not reached.
And the roster only fills while armed, so an agent dispatched on a disarmed instance has
its id recorded nowhere — which is why arming is a separate act worth doing before you
need it. **No circuit breaker was built**: the cost-velocity / no-progress escalation
ladder needs a resident process to run its beat, and ai-bridge has none.

Covered by `tests/agent-control.test.sh` (133 assertions, most of them refusals).

## 17. An instruction addressed to an agent is executable only if that agent *holds* the tool

**Possession, not installation — and the difference is invisible in the prose.** A `tools:`
allowlist lives in frontmatter the instruction never mentions, so `CONVENTIONS.md` read
perfectly for months while telling `software-engineer` to "dispatch `code-architect` **if
it's installed in `~/.claude/agents/`**". `code-architect` *is* installed, so the condition
evaluated **true** — and `software-engineer` holds no `Agent` tool, so the branch it chose
could not run. That is the worst shape a defect can take: **it reads as satisfied.** Three
more sat beside it (`Workflow` in `auditor.md`, `qa-reviewer.md`, `software-engineer.md`;
`EnterWorktree` in `CONVENTIONS.md`), and a condition on *installation* can never detect
the thing that decides the outcome. So: **never write an instruction that depends on a
tool absent from the addressed agent's `tools:` list, and never condition on what is
installed when what decides is what is held.** Three consequences worth keeping. **For a
shared doc the addressed agent is a SET, and the constraint is the intersection** — an
instruction in a doc read by four agents must be executable by all four, or the same
sentence silently means two different things. **Stating an absence beats deleting the
mention**: deleting is cheaper but loses the reason and the clause comes back, so name the
missing tool *and* the route to take instead — which is also what makes it checkable.
**Widening an allowlist is a standalone decision**, never something a convenience clause
settles; `Workflow` is in no role agent's list and stayed out, with the honest statement of
absence written in its place. Enforced by [18](#18-the-tool-allowlist-check-is-pinned-from-both-sides-and-silence-is-a-failure).

## 18. The tool-allowlist check is pinned from both sides, and silence is a failure

**…because the first version of it failed in exactly the shape it was built to catch.**
`tests/agent-tool-allowlist.test.sh` matches a **backticked identifier** from a tool
vocabulary — backticks are already how this codebase means "the identifier, not the word",
and without that restriction ordinary English ("never *write* to the bundle", "the *agent*
roster", "*workflow* structure", "the *task* document") fools the sweep. `Task` stays out
of the vocabulary on purpose: OKF's own document type is `Task` and the bundle backticks it
constantly, so including it would flag the core vocabulary and earn the check a deletion.
Four things then make it hold, and each exists because the version without it was measurably
weaker.

- **(a) The vocabulary is pinned from BOTH sides, because a closed list leaks silently.** A
  tool missing from it is not treated as prose — it is **invisible**, and the check passes,
  which is indistinguishable from there being nothing to find. `AskUserQuestion`,
  `ExitWorktree` and `Artifact` were all missing at once, and `Artifact` surfaced only
  because a PM tick happened to start granting it. So: every tool a shipped agent
  **grants** must appear in the vocabulary (a new harness tool becomes real here at the
  moment it is granted, which is the one event that cannot be missed), **and** a backticked
  capitalised name that no classification rule recognises **fails as unclassified**. That
  second guard first shipped scoped to *multi-word* CamelCase, on the argument that the
  grant guard covered the single-word residue — and **that argument is false for the case
  that matters most**, which was reproduced rather than debated: `` Use the `Deploy` tool ``
  in an agent body left the harness at 62 passed, 0 failed. The grant guard only ever covers
  a tool some agent **actually grants**, never a hallucinated name granted nowhere, which is
  precisely what a prose-vs-allowlist check exists to catch. So the guard now fires on every
  backticked capitalised identifier, and the 61 legitimate non-tool mentions in the scanned
  set are kept quiet **by rule, not by list** — of FOUR rules, two are derived or
  shape-based: OKF's document types come from `symlink/SCHEMA.md`'s own `type:` headings, so
  a new type classifies itself (43 mentions); an all-capitals name is a literal output token,
  which is a shape and needs no upkeep (17); and a fourth, hand-maintained residual list
  (`NOT_A_TOOL`) covers what neither derivation nor shape reaches. **A hand-maintained list
  of non-tools is the same closed-list problem one level over — except for the direction it
  leaks:** an unclassified name here produces a **build failure** naming the file, the line
  and the routes to classify it, where the closed vocabulary produced **silence**. Noise a
  maintainer fixes is not the same defect as silence nobody can see, and that asymmetry is
  the whole argument for accepting this direction and not the other. Residual, stated because
  it is real: no harness tool has ever been named in all capitals, which is what the shape
  rule rests on and is asserted — so `` `DEPLOY` `` would still be missed where `` `Deploy` ``
  is now caught. **The fourth rule is a recognition route too, and it is not exempt from its
  own asymmetry:** a hand-maintained list can rot silently the same way `VOCAB` did if an
  entry is added before anything actually names it — which happened. The whole Claude Code
  hook-event family was pre-populated into `NOT_A_TOOL` (11 names) on the argument that "the
  next one documented must not break the build", and a live check against the real tree
  found **9 of the 11 had zero backticked mentions anywhere in `symlink/`, `.claude/` or
  `CLAUDE.md`** — each a silent classification route for exactly the shape this file exists
  to catch (`` `Notification` ``, `` `PreToolUse` ``, `` `PreCompact` `` and
  `` `SubagentStop` `` were reproduced as invisible against a live head). So the fourth rule
  now asserts what it grants: every `NOT_A_TOOL` entry must be **JUSTIFIED BY A REAL
  MENTION** in that same tree, or the build fails naming the dead entry. The 9 un-earned
  names are gone; two remain, each backed by a mention — `SessionStart` (a real hook event)
  and `Makefile` — and a name can only be added back in the same commit as the mention that
  justifies it.
- **(b) The scanned set is DERIVED, never listed.** Two paths were hardcoded, so the check
  could only ever look at the two someone remembered — and `symlink/SCHEMA.md`'s
  browser-access section named `mcp__claude-in-chrome__*` to five readers whose allowlist
  intersection is `Bash Glob Grep Read`, unseen. A doc addresses an agent when an agent is
  **told to read it**, so that is what is derived: the `*.md` references in restricted agent
  bodies, resolved against `symlink/` then `seed/`. Adding a doc reference to an agent body
  puts the doc in scope by itself. `seed/CLAUDE.md` keeps an explicit override — it loads
  into every session whether an agent names it or not, so every restricted agent is a
  reader and deriving a smaller set would *widen* the intersection.
- **(c) A waiver carries a budget AND has to state the absence — the count is not what
  decides.** Naming an absent tool is often correct (`oncall-guide.md` names `Skill`
  precisely to record that the invocation must not come back), so a file may declare
  `<!-- tool-mention: Workflow(2), Agent(2) — why -->`. A **bare** declaration was measured
  too weak: re-introducing the original defect verbatim still passed, because a per-file
  waiver covers every future mention. The `(N)` budget fixed that. But a budget is a
  **count**, and a count is exactly what a reword holds constant — swap one honest statement
  of absence for a live instruction and it stays green. So the deciding condition is the
  prose, and it is **two-sided**, because requiring a possession cue alone tests only half of
  what the rule says — "states the absence **instead of instructing the use**". The half that
  was missing was defeated **0-for-2** by ordinary prose: "You can author a `Workflow` for
  wide work — the `Workflow` idiom is available … deliberately not written here … granting it
  is a standalone decision" clears on *available*, *not* and *granting* while telling the
  reader to do the forbidden thing. A declared mention must therefore state the absence
  **and** not be governed by a non-negated directive verb in the five words before it. A
  **negated** directive is a statement of absence, not an instruction ("don't rely on the
  `EnterWorktree` tool"), and a verb two clauses away governs something else, so both stay
  green. `only` and `available` were **deleted** from the cue list on the same evidence:
  neither is about possession, both were the masking word in a reproduced counter-example,
  and no real mention needs them. The budget is kept for the different hole it catches (an
  *added* mention) and is no longer what decides. **`if` is deliberately not an absence
  cue** — accepting it would bless the original installation-conditioned defect. A
  declaration with no reason, or a name with no `(N)`, exempts nothing; stale (tool no longer
  named) and redundant (tool actually granted) declarations are flagged so a waiver cannot
  rot into a rubber stamp. Per-mention markers were rejected as too brittle for reflowing
  prose. **Residual, measured not argued:** the directive verb list is a deny list, so a
  mention carrying a possession cue and governed by no listed verb can still read as an
  instruction — "a `Workflow` fan-out is the route for wide work, since nothing else is
  granted" is not caught. It is a second requirement layered on the first, never the sole
  decider, and the task's acceptance criterion was narrowed to exactly that promise.
- **(d) Assert the quiet cases, not only the loud ones.** The four prose words, a backticked
  `Task`, the OKF types, the SCREAMING tokens, the hook-event names, an MCP wildcard covering
  its own prefix and nothing else, a same-count reword that *still* states the absence, a
  negated directive verb — all are fixtures. A checker for this class is only trustworthy if
  "it stays quiet on ordinary English" is a test rather than a claim, and every new guard is
  paired with the input it must reject. **Demonstrate by mutation on real prose, and on more
  than one shape.** One successful mutation proves a mechanism *can* fail loud; it does not
  prove every equivalent mutation does, which is how "one is enough to fail" and "the grant
  guard covers the residue" both got into a PR body and both turned out to be properties of
  the single example that had been tried. Three structurally different rewords of the same
  real `CONVENTIONS.md` sentences are run against this check, each failing, alongside a
  same-count control that must stay green.

**Out of reach from this repo, and stated rather than hidden:** a live instance's own
`CLAUDE.md` is a real file per bundle, not a symlink, so a rule that drifts into it cannot
be checked from here. `seed/CLAUDE.md` is covered instead and `upgrade.sh` is the route for
existing instances — which is exactly how one instance kept the defective wording after the
template had already been fixed. Any rule duplicated between `CONVENTIONS.md` and an
instance `CLAUDE.md` needs **both** edits, and only the template side is testable. Agents
declaring no `tools:` key (`config/*/agents/`) inherit everything and are skipped — and
that skip is asserted, not assumed, so one of them growing a `tools:` key fails here.
Covered by `tests/agent-tool-allowlist.test.sh` (86 assertions).


## 19. The destructive-action baseline is a hook, and it is narrow on purpose

`permissions.deny` was **empty in all three live instances** while one of them ran 13
projects on `yolo` autonomy holding live production credentials. The gap was never that
nobody had written the rule down — it was that the rule was written as prose, and prose is
a request an agent may decline. `symlink/.claude/hooks/deny-destructive.sh` refuses the
tool call at the `PreToolUse` boundary, before it runs: the same category as branch
protection, and categorically unlike a `CONVENTIONS.md` line.

**Why a hook and not `permissions.deny` patterns.** A `permissions.deny` entry matches a
command **prefix**, and every shape worth denying is conditional on something a prefix
cannot see — `DROP TABLE` against a remote host versus a test container, `kubectl delete
pod` versus `kubectl delete namespace`, `rm -rf node_modules` versus `rm -rf` at the repo
root (which depends on the session's cwd), a force-push to a feature branch versus to the
default branch. Written as prefixes each rule is either **too broad**, and gets switched
off — the failure mode of every over-strict lint, and a baseline nobody keeps protects
nothing — or **too narrow**, which is *false comfort*, and false comfort is worse than an
empty list because the instance now believes it is covered. A hook sees the whole command,
the cwd and the repo, so a rule can be narrow enough to keep.

**And it is the only form that can be proven.** A prefix pattern's matching is the
harness's business, so a harness assertion about it would be a re-implementation of the
matcher passing for its own reasons. The hook is a pure function from a payload to a
decision, so `tests/deny-baseline.test.sh` feeds it real payloads and reads the verdict.
`permissions.deny` still carries a short block for the handful of shapes that **are**
unconditional (`rm -rf /`, `terraform destroy`), and every entry in it is deliberately
duplicated by a hook rule, so **nothing depends on the layer that cannot be proven**. An
entry there must be an exact command or a true prefix: `Bash(rm -rf /*)` is a *wildcard*,
and would refuse every absolute-path delete on the machine.

**Both directions, per rule, always.** A rule is only tested when the harness shows the
shape it refuses **and** a neighbouring command — same tool, same verb, one condition
different — that it must still allow. "It denies `kubectl delete namespace`" alone passes
a hook that denies every `kubectl` call, which is the version that gets deleted. The allow
half is the load-bearing half: `psql` against a test container, `rm -rf node_modules`,
`rm -rf "$TMP"`, `terraform plan -destroy`, `git push --force-with-lease` to a feature
branch are what agents here run every day.

**The escape hatch is the human's own terminal, and it is what keeps the rules narrow.**
Every refusal is satisfiable by a human running the command outside the harness, so no
rule ever has to be widened for a legitimate emergency and no instance has a reason to
disable the baseline. The deny message says so, and tells the agent **not** to re-issue a
variant that evades the pattern — without that sentence a guard just teaches rewording.

**Fail open on plumbing, never on a match.** No `jq`, an unparseable payload: log to stderr
and let the call through, for the same reason `agent-control.sh` does ([16](#16-the-kill-switch-is-one-hook-and-it-fails-open)) — a
guard that blocks all work because its own plumbing broke is a guard that gets removed. A
rule that *matches* always denies. A refusal is JSON on stdout and the script's only exit
status is 0.

**Two limits, stated rather than papered over.** (i) This is pattern matching over a
command string. It stops the named shapes, not every route to the same outcome — a path
built from a variable, SQL read from a file, a wrapper script, a language runtime. It
raises the floor; it is not a proof. (ii) **Credentials are the real boundary.** An agent
that cannot reach production cannot harm it whatever it decides, and that audit is
separate, stronger, and not replaced by this list.

**It is machinery, so it is not deletable per instance** ([4](#4-a-capability-some-deployments-must-not-have-should-be-one-deletable-file) is the *opposite* case) — `install.sh`
re-links it unconditionally. That is the point: a safety floor an instance can `rm` is not
a floor. The cost is that a **new** file under `symlink/` is *absent* rather than dangling
in an already-stamped instance, which `session-banner.sh` deliberately cannot see, so the
guard only starts enforcing after `install.sh <instance>` runs once. `settings.json`
registers it behind an `[ -x ]` test so the interval is a quiet no-op rather than a 127 on
every tool call.

Covered by `tests/deny-baseline.test.sh` (102 assertions), and mutation-checked in both
directions: neutering one rule fails 7 assertions, making one unconditional fails 6, and
adding a rule to `RULES` with no test here fails by name.

---

## Repo conventions that are not invariants

- **Test harnesses live in `tests/`, never under `symlink/`.** Everything under `symlink/` ships into every instance, and a fixture harness is not machinery an instance needs.
- **CI runs the whole suite as one required check named `harness suite`.** [`.github/workflows/tests.yml`](../.github/workflows/tests.yml) runs every `tests/*.test.sh` on each PR against `main` and each push that lands on it, on `macos-latest` — the platform this suite's baseline was actually measured on (a first Linux run failed four harnesses for environment-specific reasons; fixing those is its own task, not something to absorb silently). **The job name is a merge-gate contract**: `main`'s branch protection requires that exact check and is **strict** (a branch must be up to date with `main` before it merges, so expect a rebase when a sibling PR lands first), and [`.github/required-checks.txt`](../.github/required-checks.txt) declares the same name for the fallback `required-checks.sh` uses only when the platform reports no required set at all ([invariant 6](#6-the-delegated-merge-gate-resolves-its-required-checks-in-required-checkssh-and-exit-0-is-the-only-clearance)). Renaming the job means editing that file and the branch-protection rule in the same commit. The workflow does not trust the suite's own tally either: a harness with a broken `TMPDIR` guard can delete its own checkout and still print `fail=0`, so it re-verifies the checkout after every harness and stops at the first that damages it.
- **A harness must give the same answer from a linked git worktree.** Every role agent works in one, and `install.sh` refuses to run from one by design — so harnesses that handed it `$TPL/install.sh` unconditionally stamped nothing and then failed downstream for reasons unrelated to the change under test (six of them, across `ai-bridge-v4` tasks 029-031). `tests/worktree-suite-parity.test.sh` pins **both halves at once**: those harnesses report `fail=0` from a fresh linked worktree of this checkout, **and** `install.sh` still refuses there — so the guard cannot be weakened to make the parity pass. Teach a harness to route around the guard; never loosen the guard.
- **Harness growth is a threshold you measure against your own diff, not a test.** `git diff --numstat origin/main -- 'symlink/**/*.sh' | awk '{a+=$1} END{print a+0}'` — at or above ~150 added lines, name the figure in the PR body as one `⚠️` line and let the owner decide ([`symlink/CONVENTIONS.md`](../symlink/CONVENTIONS.md) carries the rule and the scale behind the number). This replaced `tests/machinery-ceiling.test.sh` (944 lines, retired in [#45](https://github.com/cbmono/ai-bridge/pull/45)): pinning integers on `main` made every PR touching `symlink/` re-measure and collide with PRs it had nothing to do with, while a threshold checked against your own diff cannot collide with anyone else's. Same measurement, none of the coupling.
- **`paths:` globs are only root-anchored with a leading slash.** Write `/symlink/**`, not `symlink/**`: a bare pattern matches that basename in *any* directory, and a trailing `/**` is not anchored either. Measured against Claude Code v2.1.239 with an `InstructionsLoaded` hook — and the official docs table says the opposite, which is why `tests/rule-globs-anchored.test.sh` asserts it rather than leaving it a convention the next reader "corrects".
- **Placeholders in tracked files must be verified unclaimed.** This repo is public. `example-user-007` / `example-user-008` are 404 on github.com and `example.com` is RFC 2606 reserved. `alice`, `bob` and `jane-doe` are all real accounts, so a plausible-looking example names a stranger — and an example is the thing people copy verbatim. `tests/commit-as-identity.test.sh` asserts the seed carries no live-account name and no address outside `example.com`.
- **One review per PR.** `.coderabbit.yaml` pins `auto_incremental_review: false` and `chat.auto_reply: false` (both default `true`). Fix findings, push, reply once — never ask for a re-review of the same diff.
- **PR bodies, review replies and progress reports have a required short shape** (`CONVENTIONS.md`; `seed/CLAUDE.md` → "Reporting progress"): **each surface has its own shape**, not one shared template — a PR body is a one-sentence TL;DR, the `acceptance_criteria` as a `✓`/`✗` table with the evidence per row, and threshold questions as one `⚠️` line each; a **review reply** is one line per finding fixed or skipped with its reason, and no criteria table; a **progress report** leads with the outcome, prefers tables to paragraphs, and puts what needs a decision last. **The length was never required** — the rules only ever asked for the criteria and the threshold note; the "Why" narratives and rejected-alternatives essays accumulated because each PR was also arguing a decision to the owner, and nobody separated *what a reviewer must check* from *what the owner might like to know*. Reasoning moves to the commit message and the task doc, which already carry it. The one thing terseness must not cost is **auditability**, and it doesn't: `` `foo.test.sh` 40/0 `` is both shorter than a paragraph and more checkable than one, since a reader can re-run it. `tests/pr-body-shape.test.sh` asserts the required elements are still named as required, so "be brief" can never quietly delete the merge gate.
