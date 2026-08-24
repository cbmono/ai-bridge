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
# So this asserts the invariant directly, on both sides of the drift:
#   1. every `*.sh` beneath `tests/` — the config's own scope, recursively, whatever the
#      filename suffix — starts with exactly the shebang the config names (the CODE side);
#   2. `.coderabbit.yaml` does not re-assert the false "POSIX shell" claim, still names
#      bash, still spells out that exact shebang, and still scopes its instruction to the
#      exact path this file scans (the CONFIG side — catches both a "revert" of the
#      correction and a config whose scope silently outgrows this check).
#
# THE SCOPE AND THE SHEBANG ARE NOT FREE PARAMETERS. `SHEBANG` and `SCOPE_GLOB` below are
# asserted to appear verbatim in `.coderabbit.yaml`, so this check cannot claim to enforce
# a dialect or a path the config does not actually declare, and the config cannot promise
# a scope wider than what is scanned here. That symmetry is the point of the file.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
CFG="$REPO/.coderabbit.yaml"

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

# --- 2. CONFIG side: the declaration this check enforces is really in the config ----
ok ".coderabbit.yaml exists"          "$([ -f "$CFG" ] && echo yes || echo no)" yes

reasserted="$(grep -ci 'posix shell' "$CFG" || true)"
ok "config no longer claims POSIX shell" "$reasserted" 0

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

printf '\n%s passed, %s failed  (%s shell file(s) checked under tests/)\n' "$pass" "$fail" "$total"
[ "$fail" -eq 0 ]
