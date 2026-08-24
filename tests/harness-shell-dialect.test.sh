#!/usr/bin/env bash
#
# harness-shell-dialect.test.sh — the shell dialect `.coderabbit.yaml` declares for
# `tests/**/*.sh` and the shell dialect the files under `tests/` actually use must not
# drift apart.
#
# WHY THIS IS A TEST AND NOT A CORRECTED SENTENCE. `.coderabbit.yaml` used to carry a
# throwaway comment claiming "this repo is markdown + POSIX shell". It was false — every
# harness under `tests/` is bash by shebang and by construct (`pipefail`, `local`,
# process substitution), none is ever invoked via `sh` — and because CodeRabbit reads the
# config file as repo context, that one false clause became the premise behind an
# identical `Major` finding ("Use POSIX shell syntax…") on three separate PRs. Correcting
# the sentence fixes the instance; it does not fix the CLASS, which is that a declaration
# of the repo's shell dialect lived in free-text prose nothing could contradict.
#
# THE FIRST FIX (below, CONFIG SIDE) COVERED `.coderabbit.yaml` ALONE, AND THAT IS WHY THE
# SAME CLAIM SURVIVED ELSEWHERE. The same "markdown + POSIX shell" sentence also shipped in
# `CLAUDE.md` (twice — read by every agent on every turn) and `.claude/rules/tests.md`
# (read on any read under `tests/`), and this check verified only the one place someone had
# just fixed. `CLAIM_FILES` below is every file this repo has shipped the claim in, so the
# config side is no longer one file.
#
# So this asserts the invariant directly, on both sides of the drift:
#   1. every `*.sh` beneath `tests/` — the config's own scope, recursively, whatever the
#      filename suffix — starts with exactly the shebang the config names (the CODE side);
#   2. NONE of `CLAIM_FILES` re-asserts the false "POSIX shell" claim, `.coderabbit.yaml`
#      still names bash, still spells out that exact shebang, and still scopes its
#      instruction to the exact path this file scans (the CONFIG side — catches a "revert"
#      of the correction in any claim file, a config whose scope silently outgrows this
#      check, and a new doc re-asserting the claim).
#
# THE SCOPE AND THE SHEBANG ARE NOT FREE PARAMETERS. `SHEBANG` and `SCOPE_GLOB` below are
# asserted to appear verbatim in `.coderabbit.yaml`, so this check cannot claim to enforce
# a dialect or a path the config does not actually declare, and the config cannot promise
# a scope wider than what is scanned here. That symmetry is the point of the file.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
CFG="$REPO/.coderabbit.yaml"

# Every file this repo has shipped the "POSIX shell" claim in. Extend this array — not a
# fresh mechanism — the next time a doc states the repo's shell dialect.
CLAIM_FILES=(
  "$CFG"
  "$REPO/CLAUDE.md"
  "$REPO/.claude/rules/tests.md"
)

# The single source of truth for both sides, verified against the config below.
SHEBANG='#!/usr/bin/env bash'
SCOPE_GLOB='tests/**/*.sh'

pass=0; fail=0
ok() { # <name> <actual> <expected>
  if [ "$2" = "$3" ]; then printf '  PASS  %-58s (%s)\n' "$1" "$2"; pass=$((pass+1))
  else printf '  FAIL  %-58s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}

# scan_dialect <dir> — echoes "<files-seen> <nonconforming>" for every `*.sh` beneath
# <dir>, recursively, and prints one NOT-BASH line per offender on stderr.
#
# THIS IS THE scanner: the real check and the synthetic fixtures at the bottom both call
# it, so a fixture proves the shipped logic rather than a copy of it that can drift.
scan_dialect() {
  local root="$1" f first seen=0 bad=0
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    [ -f "$f" ] || continue   # `-f` follows symlinks; skips a directory named `*.sh`
    seen=$((seen+1))
    first="$(head -n 1 "$f")"
    if [ "$first" != "$SHEBANG" ]; then
      bad=$((bad+1))
      printf '        NOT-BASH  %s -> %s\n' "${f#"$root"/}" "$first" >&2
    fi
  done <<EOF
$(find "$root" -name '*.sh' | sort)
EOF
  printf '%s %s\n' "$seen" "$bad"
}

# --- 1. CODE side: everything the config scopes carries the configured shebang ------
read -r total non_bash <<EOF
$(scan_dialect "$REPO/tests")
EOF

ok "shell files found under tests/"   "$([ "$total" -gt 0 ] && echo yes || echo no)" yes
ok "every tests/**/*.sh starts with $SHEBANG" "$non_bash" 0

# claim_scan <file>... — echoes how many of the given files case-insensitively
# (re)assert "POSIX shell" (0 for a file that does not, or does not exist).
#
# THIS IS THE SCANNER: the real per-file loop right below and every synthetic fixture
# further down call this exact function — never a copy of its logic — so a fixture
# proves the shipped check rather than a stand-in that can silently drift out from
# under it. A later change to the matching logic itself (not just to CLAIM_FILES) now
# shows up in the real assertions and the synthetic ones together, because there is
# only one scanner.
claim_scan() {
  local cf hits flagged=0
  for cf in "$@"; do
    hits="$(grep -ci 'posix shell' "$cf" 2>/dev/null || true)"
    [ "$hits" -gt 0 ] && flagged=$((flagged+1))
  done
  printf '%s\n' "$flagged"
}

# --- 2. CONFIG side: the declaration this check enforces is really in the config ----
ok ".coderabbit.yaml exists"          "$([ -f "$CFG" ] && echo yes || echo no)" yes

# Every claim file, not just .coderabbit.yaml, must not (re)assert "POSIX shell". Each
# assertion calls claim_scan on a single file so a regression is pinned to the
# offending file, not just to an aggregate count.
for cf in "${CLAIM_FILES[@]}"; do
  rel="${cf#"$REPO"/}"
  ok "$rel does not (re)assert POSIX shell" "$(claim_scan "$cf")" 0
done

# REGRESSION GUARD on the real scope itself, not a fixture: if CLAIM_FILES is ever
# narrowed back to `("$CFG")` alone — the exact drift this task exists to close — this
# count drops from 3 to 1 and this assertion fails. That is the in-repo, repeatable
# proof that narrowing the real scope fails the test. See "pre-task-026 config side …
# would have caught only 1 of the 3" below for the same scenario played out against
# fixtures that still carry the claim, so the discriminating power is shown too, not
# just the array length.
ok "config side covers more than .coderabbit.yaml alone" "${#CLAIM_FILES[@]}" 3

declares_bash="$(grep -ci 'bash' "$CFG" || true)"
ok "config names bash somewhere"      "$([ "$declares_bash" -gt 0 ] && echo yes || echo no)" yes

# The two parameters above are only honest if the config actually says them.
names_shebang="$(grep -cF -- "$SHEBANG" "$CFG" || true)"
ok "config spells out the exact shebang" "$([ "$names_shebang" -gt 0 ] && echo yes || echo no)" yes

scopes_path="$(grep -cF -- "path: \"$SCOPE_GLOB\"" "$CFG" || true)"
ok "config scopes its instruction to $SCOPE_GLOB" "$([ "$scopes_path" -gt 0 ] && echo yes || echo no)" yes

# --- Non-vacuity: the scanner must fail on each shape of broken input ---------------
# Four offenders, one per way this check has been wrong or could go wrong:
#   bad-sh          a POSIX shebang                — the original case
#   bad-bin-bash    bash, but NOT the declared spelling
#   helper.sh       inside the declared scope, no `.test.sh` suffix
#   nested/deep     the declared `**`, below the top level
tmp="$(mktemp -d "${TMPDIR:-/tmp}/dialect.XXXXXX")" || { echo "dialect: mktemp -d failed" >&2; exit 2; }
tmp="$(cd "$tmp" && pwd)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/tests/nested"
printf '%s\necho hi\n' "$SHEBANG" > "$tmp/tests/fake-ok.test.sh"
printf '#!/bin/sh\necho hi\n'     > "$tmp/tests/bad-sh.test.sh"
printf '#!/bin/bash\necho hi\n'   > "$tmp/tests/bad-bin-bash.test.sh"
printf '#!/bin/sh\necho hi\n'     > "$tmp/tests/helper.sh"
printf '#!/bin/sh\necho hi\n'     > "$tmp/tests/nested/deep.test.sh"

read -r fx_seen fx_bad <<EOF
$(scan_dialect "$tmp/tests" 2>/dev/null)
EOF
ok "scanner sees every *.sh under tests/, nested included" "$fx_seen" 5
ok "scanner flags all 4 nonconforming fixtures"            "$fx_bad"  4

# REGRESSION GUARD, and the reason those four fixtures are evidence rather than
# decoration. The pre-fix scanner — `-maxdepth 1`, `*.test.sh` only, `#!/bin/bash`
# tolerated — sees exactly ONE of the four offenders and exits green on the rest.
# Re-narrow `scan_dialect` and the assertion above drops back towards this number.
legacy_bad=0
while IFS= read -r f; do
  [ -n "$f" ] || continue
  case "$(head -n 1 "$f")" in
    '#!/usr/bin/env bash'|'#!/bin/bash') ;;
    *) legacy_bad=$((legacy_bad+1)) ;;
  esac
done <<EOF
$(find "$tmp/tests" -maxdepth 1 -name '*.test.sh' | sort)
EOF
ok "pre-fix scanner would have caught only 1 of the 4"     "$legacy_bad" 1

# A synthetic DRIFTED config, so the three config-side greps are shown to discriminate
# rather than to pass on anything: it re-asserts the false claim, never spells the
# shebang out, and narrows the scope back to the top-level `*.test.sh` this check used
# to scan — the realistic way the config outgrows the code again.
FAKE_CFG="$tmp/fake.coderabbit.yaml"
{ printf 'placeholder posix shell claim\n'
  printf 'path_instructions:\n'
  printf '  - path: "tests/*.test.sh"\n'
  printf '    instructions: bash please\n'; } > "$FAKE_CFG"

fake_reasserted="$(grep -ci 'posix shell' "$FAKE_CFG" || true)"
ok "checker flags a reasserted POSIX-shell config claim" "$([ "$fake_reasserted" -gt 0 ] && echo yes || echo no)" yes

fake_shebang="$(grep -cF -- "$SHEBANG" "$FAKE_CFG" || true)"
ok "checker flags a config that never spells the shebang" "$fake_shebang" 0

fake_scope="$(grep -cF -- "path: \"$SCOPE_GLOB\"" "$FAKE_CFG" || true)"
ok "checker flags a config narrowed off the scanned scope" "$fake_scope" 0

# --- Non-vacuity for the EXTENDED config side: this is the regression task-026 exists to
# close. Two synthetic docs, each carrying the exact false claim CLAUDE.md and
# .claude/rules/tests.md shipped, plus the synthetic drifted config above — three sites,
# only one of which (.coderabbit.yaml) the pre-task-026 CLAIM_FILES scope would have seen.
fake_claude="$tmp/fake-CLAUDE.md"
printf '%s\n' '- tests/ -- POSIX shell harnesses.' > "$fake_claude"
fake_rules="$tmp/fake-tests-rule.md"
printf '%s\n' 'POSIX shell harnesses, no framework, no build step.' > "$fake_rules"

FAKE_CLAIM_FILES=("$FAKE_CFG" "$fake_claude" "$fake_rules")

# Calls claim_scan — the exact function the real CLAIM_FILES loop above calls, not a
# reimplementation of it — so this proves the shipped scanner, not a copy that could
# silently drift from it.
ok "extended config side flags all 3 synthetic re-assertions" "$(claim_scan "${FAKE_CLAIM_FILES[@]}")" 3

# REGRESSION GUARD: the pre-task-026 config side scanned `.coderabbit.yaml` ALONE — the
# exact scope that let the claim survive in CLAUDE.md and .claude/rules/tests.md. Run the
# same claim_scan, narrowed to that one-file scope, over the same three synthetic
# fixtures (all three of which carry the claim): it catches only the one file it ever
# looked at. Widen CLAIM_FILES back down to one entry and this is the number — 1, not 3 —
# that a real narrowing would produce.
legacy_claim_files=("$FAKE_CFG")
ok "pre-task-026 config side (.coderabbit.yaml alone) would have caught only 1 of the 3" "$(claim_scan "${legacy_claim_files[@]}")" 1

printf '\n%s passed, %s failed  (%s shell file(s) checked under tests/)\n' "$pass" "$fail" "$total"
[ "$fail" -eq 0 ]
