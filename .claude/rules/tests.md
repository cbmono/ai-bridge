---
paths:
  - "/tests/**"
---

# Test conventions

Loads when you read anything under `tests/`. bash harnesses, no framework, no
build step.

**Run the harnesses your change touches before pushing — not all of them:**

```bash
bash tests/<the-one-you-touched>.test.sh
```

The full suite is CI's job: `harness suite` is a required check with `strict=true`, and it
runs everything against the merged base. Locally the same loop measured **39m 47s and
269.4k tokens** (2026-08-29) against ~9 minutes and no tokens in CI. So run it only when
your change touches shared machinery every harness loads, and say why in the PR body —
`plugin/seed/CONVENTIONS.md` → "The full suite belongs to CI" is the rule this defers to.

The full loop, for that exception only — and never polled:

```bash
for f in tests/*.test.sh; do bash "$f" || echo "FAILED: $f"; done
```

## Rules

- **`ok()` compares actual to expected, in that argument order**, and every harness prints its own `pass=/fail=` (or `N passed, N failed`) line and exits non-zero on any failure. Keep both.
- **Harnesses live here, never under `/plugin/`.** Everything under `plugin/` ships into every instance, and a fixture harness is not machinery an instance needs.
- **A test that only asserts the refusal is vacuous.** Assert **both directions** — that the guard fires *and* that the normal path still works. `installer-worktree-guard.test.sh` says so in its header: "It refuses in a worktree" alone would pass a script that refuses everywhere.
- **Assert the property, not the implementation text.** `derived-indexes.test.sh` checks `git check-ignore --no-index` rather than the pattern string; `snapshot.test.sh` asserts no key outside the documented allowlist is emitted.
- **Every capability that can be turned off needs a test proving it is off when the file is gone** — `commit-as-guard.test.sh` for `AUTONOMY.md`, `awaiting-queue.test.sh` for `AWAITING.md`. ([conventions 4](../../docs/conventions.md#4-a-capability-some-deployments-must-not-have-should-be-one-deletable-file))
- **A path that can emit a *false zero* or a false success is the highest-value thing to test here.** `push-state.test.sh` guards an authoritative `in-flight 0` produced by an unreadable file; `migrate-bundle.test.sh` guards a `FIXED` printed for a write that never landed.
- **Extend a `gh` stub to mirror real quirks rather than working around them in the script** — a 404 body goes to **stdout**, the "no required checks" message to **stderr**. `required-checks.test.sh` owns that stub.
- **Compare resolved paths.** `mktemp` hands back `/var/...` while git reports `/private/var/...` on macOS, so an unresolved grep fails on a correct message. This trap has appeared three times in this codebase.
- **`rule-globs-anchored.test.sh` asserts a measured fact the official docs contradict** — a `paths:` pattern is only root-anchored with a leading `/`. It is a test rather than a convention precisely because a convention that contradicts the documentation gets "corrected" back.
- **Fixtures must not touch the user's real `~/.claude` or a real instance.** Build a throwaway repo under `mktemp -d` and copy the script under test into it.

## Run the suite from the MAIN checkout, never a worktree

Four harnesses — `derived-indexes`, `link-repos`, `snapshot` and `board-renderers` —
invoke this repo's own `init-bundle.sh --config`, which **refuses to run from a git worktree**
by design (it would create symlinks into a directory that `git worktree remove` later
deletes). So running the suite inside a worktree fails those four, well over a hundred
assertions, for a reason that has nothing to do with the code under test.

That is the guard working, not a bug — but it reads exactly like a regression, so: run the
suite from the main working tree, or from a fresh clone. If you are working in a worktree,
clone to a temp directory to verify.
