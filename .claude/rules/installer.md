---
paths:
  - "/install.sh"
  - "/upgrade.sh"
  - "/RETIRED"
  - "/seed/**"
  - "/config/**"
---

# The installer, the upgrader, and `seed/`

Loads when you read `install.sh`, `upgrade.sh`, `RETIRED`, or anything under `seed/`.
Reasoning: [`docs/conventions.md`](../../docs/conventions.md) and
[`docs/operations.md`](../../docs/operations.md).

## Rules

- **`install.sh` only links, seeds-if-absent, and sweeps dangling machinery links. It never removes instance content.** That is the safety property that makes it safe to run blindly on a repo full of somebody's work — don't spend it to save an `rm`. ([conventions 1](../../docs/conventions.md#1-retiring-content-is-asymmetric))
- **Retired *seed* paths are declared in `RETIRED` and reported with the exact `rm`, never deleted.** Add the entry in the same commit that deletes the seed file, and **never prune the manifest** — an instance stamped years ago still has the file. Absence, an empty file, a comment, a blank line, or a path an instance doesn't have are all silence, never an error. ([conventions 1](../../docs/conventions.md#1-retiring-content-is-asymmetric))
- **Step 2b's sweep must stay narrow:** a link is removed only when it points **into this template's `symlink/`** (decided by `ours`, not by name) **and** its target is gone. A real file, a link elsewhere, or a link that still resolves is left alone. ([conventions 2](../../docs/conventions.md#2-retiring-machinery-means-deleting-the-file-and-letting-installsh-sweep-the-links))
- **`FIRST_STAMP` is the off switch for `AWAITING.md` and `SNAPSHOT.json`.** Both are created on the first stamp **only**, and it is computed *before* seeding. Move creation out of that guard and `rm` stops working. A second clone of a shared bundle is **not** a first stamp — say so, with the `touch`. ([conventions 3](../../docs/conventions.md#3-awaitingmd-is-ai-bridges-only-status-artifact-and-it-is-opt-in-by-presence), [11](../../docs/conventions.md#11-the-cross-instance-board-is-two-scripts-and-one-deletable-generated-file))
- **A `.gitignore` line is inert for a file git already tracks.** Append the line and then *report* the exact `git rm --cached`; never untrack anything yourself. ([docs/sharing.md](../../docs/sharing.md))
- **The derived-index ignore lines must NOT go in `seed/.gitignore`.** That file is an active `.gitignore` over this template's own `seed/` directory, so a `/index.md` line there matches `seed/index.md` and silently stops this repo tracking its own seed file. `tests/derived-indexes.test.sh` holds the trap closed. ([docs/sharing.md](../../docs/sharing.md))
- **Refuse to run from a git worktree, exit 2, before any write** — and do **not** compute the main checkout's path. Both obvious derivations are wrong once the git metadata lives apart from the working tree; name `git worktree list` instead. `tests/installer-worktree-guard.test.sh` asserts both directions and that no path is printed.
- **`upgrade.sh` is report-only by default**, samples `AUTONOMY.md`'s presence *before* calling `install.sh`, and ends with a numbered "what's left for you" list — that list is what a collaborator actually reads. Its `CONFLICT` and `UNKNOWN` verdicts **never** write. ([conventions 4](../../docs/conventions.md#4-a-capability-some-deployments-must-not-have-should-be-one-deletable-file), [operations 1](../../docs/operations.md#1-upgrading-an-instance-after-you-pull-this-repo))
- **Order inside `upgrade.sh` is fixed:** `install.sh` → `validate-bundle.sh` → `migrate-bundle.sh` → seed judgement. The validator ships instantly through its symlink and reports errors nothing repairs until the migration runs.
- **`seed/` placeholders must be verified unclaimed.** This repo is public: `example-user-007` / `example-user-008` (both 404) and `example.com` (RFC 2606). `alice`, `bob` and `jane-doe` are real accounts. `tests/commit-as-identity.test.sh` asserts it. ([docs/sharing.md](../../docs/sharing.md))
- **`--config` links per FILE, never a directory.** `agents/`, `commands/` and `skills/` are drop-in directories; a whole-dir link aims them at this checkout, so anything an installer drops there lands in a public repo. Don't "simplify" it, and don't add a gitignore allow-list to compensate for a link shape you can simply avoid. ([conventions 15](../../docs/conventions.md#15-the-config-layer-is-two-tiers-and-the-arrow-stays-one-way))
- **`config/required/` must stay generic; `config/opinionated/` need not.** Required is what this repo's own role agents probe for, and it ships to everyone. Opinionated is one person's layer and the *only* place a company's internal tool may be named. Deleting either directory must break nothing and error nowhere. ([conventions 15](../../docs/conventions.md#15-the-config-layer-is-two-tiers-and-the-arrow-stays-one-way))
- **`symlink/` must never require `config/`.** Keep the `test -f ~/.claude/agents/…` probes exactly as they are: a stamp on a machine that never ran `--config` has to work. And keep the bare `install.sh <dir>` interface — three live instances and `upgrade.sh` call it that way, so `--instance` is only its explicit spelling. ([conventions 15](../../docs/conventions.md#15-the-config-layer-is-two-tiers-and-the-arrow-stays-one-way))
- **`--config` never edits a real file.** A real `settings.json` is reported, never merged or moved aside; a symlinked parent directory is refused rather than written through; two tiers claiming one path is refused before any write. Every write it makes is a symlink it created itself. ([conventions 15](../../docs/conventions.md#15-the-config-layer-is-two-tiers-and-the-arrow-stays-one-way))
- **The session defaults are INLINED in `seed/CLAUDE.md`** — don't turn them back into an `@import`. The old `@~/.claude/claude-defaults.md` line resolved to nothing on a machine that never installed the parent repo, silently, in every instance. The stale-import nudge is report-only and its grep is line-anchored, because the replacement section quotes the old line to explain itself. ([conventions 15](../../docs/conventions.md#15-the-config-layer-is-two-tiers-and-the-arrow-stays-one-way))
- **If `install.sh` ever *asks* for the `people` map:** prompt only on `FIRST_STAMP`, only when stdin is a TTY, and never overwrite a value already there. ([docs/sharing.md](../../docs/sharing.md))
