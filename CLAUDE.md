# CLAUDE.md

Guidance for Claude Code when working in **this repo** — the ai-bridge template.

## What this repo is

A reusable **OKF control-panel template** for orchestrating background agents against a
group's product repositories. You stamp out one **instance** per group; each instance is
its own git repo under `~/workspace/<group>/_ai-bridge-<group>/`.

- `symlink/` — generic machinery, symlinked into every instance. A change here reaches every instance **immediately**.
- `seed/` — starting content, copied into an instance **once, only if absent**. A change here reaches nothing automatically.
- `install.sh` — stamps out / refreshes an instance. `upgrade.sh` — walks a pull's four cases and reports what's left for the human.
- `RETIRED` — seed paths the template has stopped shipping; reported, never deleted.
- `tests/` — POSIX shell harnesses. **There is a test suite and it must pass**: `for f in tests/*.test.sh; do bash "$f" || echo "FAILED: $f"; done`. No build step, no lint.
- `docs/` — human-facing depth. `.claude/rules/` — the same prohibitions, path-scoped for agents.

**Keep machinery generic.** No org, repo, path, team or channel literals under `symlink/` —
those live in an instance's `instance.config.json` / `CLAUDE.md`.

**This repo is public.** Tracked placeholders must be verified unclaimed:
`example-user-007` / `example-user-008` (both 404 on github.com) and `example.com`
(RFC 2606). `alice`, `bob` and `jane-doe` are real accounts.

## Load-bearing invariants

**No count is given, deliberately** — the number drifted three times in one day. Every one
of these is a prohibition, and a prohibition has to be in context *before* you consider the
change it forbids. The reasoning behind each — what went wrong to produce it — is in
[`docs/conventions.md`](docs/conventions.md), numbered to match. Read that file before
editing the thing it governs; don't re-derive a decision it already records, and don't
shorten a "why" — relocate it intact.

- **Retiring machinery means deleting the file *and* letting `install.sh` sweep the links.** A dangling symlink into a vanished `symlink/` path still registers as a command and exits 127 as a hook, so absence here is **not** safe. Seed content is never swept — only reported, with the exact `rm`, via `RETIRED`. ([1](docs/conventions.md#1-retiring-content-is-asymmetric), [2](docs/conventions.md#2-retiring-machinery-means-deleting-the-file-and-letting-installsh-sweep-the-links))
- **`AWAITING.md` is the only status artifact and it is opt-in by presence.** There is deliberately no `/status` command and no full board — don't reintroduce either. Creation is gated on `FIRST_STAMP`; move it out of that guard and you break the off switch. `show-awaiting.sh` greps its heading and bullets **literally**. ([3](docs/conventions.md#3-awaitingmd-is-ai-bridges-only-status-artifact-and-it-is-opt-in-by-presence))
- **A capability some deployments must not have is *one deletable file*, not a flag threaded through the machinery, and absence must mean the safe behaviour — never an error.** `symlink/AUTONOMY.md` is the pattern; a new one under `symlink/` inherits the re-link hazard. ([4](docs/conventions.md#4-a-capability-some-deployments-must-not-have-should-be-one-deletable-file))
- **`build` and `research` projects are deliberately asymmetric — don't restore a question for symmetry.** `clis:` is written from an explicit flag or as an empty list; never a placeholder like `none`. ([5](docs/conventions.md#5-build-and-research-projects-are-deliberately-asymmetric))
- **The delegated merge gate resolves its required checks in `required-checks.sh`, and exit 0 is the only clearance.** Classify the platform probe on its **payload**, never its exit code; capture stdout and stderr separately. ([6](docs/conventions.md#6-the-delegated-merge-gate-resolves-its-required-checks-in-required-checkssh-and-exit-0-is-the-only-clearance))
- **`prune-worktrees.sh` is report-only. Do not reintroduce a delete, not even behind a flag.** Count commits, never compare to `origin/<default>`; a detached HEAD is never `REMOVABLE`; the mtime veto stays recursive. ([7](docs/conventions.md#7-prune-worktreessh-is-report-only-and-that-is-load-bearing))
- **`validate-bundle.sh` was scoped by measuring first**, and validates only the schema-defined locations — a validator that buries 6 real errors under 77 warnings teaches people to ignore it. ([8](docs/conventions.md#8-validate-bundlesh-was-scoped-by-measuring-first-and-that-is-the-point))
- **`migrate-bundle.sh` fixes only what has one right answer, is report-only by default, and a false success is worse than the error it claims to fix.** The mapping list is closed; three refusals are the design; every write is verified after it lands. ([9](docs/conventions.md#9-migrate-bundlesh-fixes-only-what-has-one-right-answer-and-is-report-only-by-default))
- **The scaffold review is a three-stage chain with a declared fallback, never a skip** — validator, then an external reviewer, then `qa-reviewer` mode C. Every stage is advisory. ([10](docs/conventions.md#10-the-scaffold-review-is-a-three-stage-chain-with-a-declared-fallback-never-a-skip))
- **The cross-instance board keeps its off switch by being a *generated root file*, never machinery under `symlink/`**, and its **published-page field allowlist** — no question or blocker text, no document bodies, no author identity, no out-of-bundle paths — is a data-governance boundary you do not add to without reading the reasoning. A snapshot's **types** are untrusted too: one drifted instance must not blank the board for the rest. ([11](docs/conventions.md#11-the-cross-instance-board-is-two-scripts-and-one-deletable-generated-file))
- **Three behaviours exist because a silent wrong answer is worse than a loud one.** `push-state.sh` must stay silent outside an instance yet **never emit a false zero** inside one, encoding every file-derived value to **one line** at its single awk choke point so a filename cannot forge the fence's markers — and never adding a second sanitising pass, which would mask that regression. An answered question is **moved, not deleted**, into a flat, not-machine-read `answered_questions:` list, with `open_questions` still the only promotion signal and no new validator check. `maxPrLoc` (**500** when absent) makes a role agent **propose** a split, never block a PR. ([12](docs/conventions.md#12-three-ai-bridge-behaviours-that-all-exist-because-a-silent-wrong-answer-is-worse-than-a-loud-one))
- **An instance can be shared by two humans.** `owner` gates **dispatch** and never promotion; the tracked **`defaultOwner`** is what stops an *unowned* task being dispatched by both clones, and is the one config key deliberately **not** locally overridable; per-machine values live in a gitignored `instance.config.local.json` whose overridable set is listed in **one** place — `SCHEMA.md` → "Per-machine config overrides"; a tracked `people` map lets each clone author commits as its own human; and the derived `index.md` files (root and per-project, **never** `knowledge/index.md`) are gitignored. ([docs/sharing.md](docs/sharing.md))
- **`knowledge/references/` is the fifth knowledge kind**, promoted by adding the missing status enum rather than by relocating anyone's content — `knowledge/<kind>/` is a shape, not a list of names. ([14](docs/conventions.md#14-knowledgereferences-is-the-fifth-knowledge-kind))

- **The config layer is two tiers, the arrow stays one-way, and no drop-in directory is ever linked as a directory.** `config/required/` (what this repo's own role agents probe for — keep it generic) and `config/opinionated/` (one person's layer, deletable) are linked into `~/.claude` by `install.sh --config`, one **file** at a time: `agents/`, `commands/` and `skills/` are drop-in dirs, and a whole-dir link puts every drop-in inside this public repo. `symlink/` must never *require* `config/` — keep the `test -f` probes and the bare `install.sh <dir>` interface — deleting either tier must error nowhere, and `--config` never edits a real file (a real `settings.json` is reported, a symlinked parent directory refused, a path claimed by both tiers refused before any write). ([15](docs/conventions.md#15-the-config-layer-is-two-tiers-and-the-arrow-stays-one-way))

<!-- ONE bullet list, deliberately: every headline is consolidated here. In ai-setup this
     content was duplicated twice by conflict resolutions. Merge into a line; never append
     a second copy. -->

## Conventions when editing

- **Test harnesses live in `tests/`, never under `symlink/`.** Everything under `symlink/` ships into every instance, and a fixture harness is not machinery an instance needs.
- **A `paths:` glob is only root-anchored with a leading slash.** Write `/symlink/**`, not `symlink/**` — a bare pattern matches that basename in any directory, and a trailing `/**` is not anchored either. The official docs say the opposite; `tests/rule-globs-anchored.test.sh` asserts it so the next reader can't "correct" it back.
- **Don't state a fallback in one doc only.** `worktreeRoot` (`<reposRoot>/_wt`), `maxPrLoc` (500), `maxAgentsInFlight` (10) and `PUSH_STATE_MAX` (12) are documented in files symlinked into instances whose config predates the key — every doc naming one must state it.
- **`docs/` is for humans; `CLAUDE.md` and `.claude/rules/` are for agents.** The story lives in `docs/` in exactly one place. Carry the rule here and point at the doc — don't duplicate the prose into both.
- **Addressing review feedback: fix, push, reply once — never ask for a re-review.** `.coderabbit.yaml` pins one review per PR. Only a rewrite that invalidates the original review justifies an explicit `@coderabbitai review`.
- **After adding or moving a command or agent under `symlink/.claude/`, restart Claude Code in an instance and verify it registers** (no `skills:` prefix). New files aren't picked up mid-session, and a **new** file needs `install.sh` re-run on the instance to be linked at all.
- **Don't run either installer from a git worktree.** Every symlink would point into a temporary checkout. Both refuse, exit 2, and deliberately do **not** compute the main tree's path — every derivation is wrong once the git metadata lives apart from the working tree. Don't "improve" the message by deriving one.
- **No customer PII** in a task title, an answer, or a `Finding`. Titles reach the published board; answers persist for the life of the repo.

## Out of scope

- Don't add CI, a build step, or a `package.json`. This is markdown + POSIX shell.
- Don't vendor the machinery into an instance. It is symlinked from this checkout by design, so a clone on another machine has dangling machinery until `install.sh` runs there.
