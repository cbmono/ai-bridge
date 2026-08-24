#!/usr/bin/env bash
#
# harness-shell-dialect.test.sh — the shell dialect `.coderabbit.yaml` declares for
# `tests/**` and the shell dialect the harnesses actually use must not drift apart.
#
# WHY THIS IS A TEST AND NOT A CORRECTED SENTENCE. `.coderabbit.yaml` used to carry a
# throwaway comment claiming "this repo is markdown + POSIX shell" next to
# `sequence_diagrams: false`. It was false — every harness under `tests/` is bash by
# shebang and by construct (`pipefail`, `local`, process substitution), none is ever
# invoked via `sh` — and because CodeRabbit reads the config file as repo context, that
# one false clause became the premise behind an identical `Major` finding
# ("Use POSIX shell syntax…") on three separate PRs. Correcting the sentence fixes the
# instance; it does not fix the CLASS, which is that a declaration of the repo's shell
# dialect lived in free-text prose nothing could contradict.
#
# So this asserts the invariant directly, on both sides of the drift:
#   1. every `tests/*.test.sh` harness carries a bash shebang (the CODE side —
#      catches the day a harness lands with `#!/bin/sh` and stays bash-only inside);
#   2. `.coderabbit.yaml` does not re-assert the false "POSIX shell" claim, and still
#      names bash as the standard somewhere a reviewer reads as fact (the CONFIG side —
#      catches the day someone "reverts" the correction).
# Either side drifting independently is exactly the failure mode task-024 fixes; this
# file is the thing that keeps it fixed.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
pass=0; fail=0
ok() { # <name> <actual> <expected>
  if [ "$2" = "$3" ]; then printf '  PASS  %-58s (%s)\n' "$1" "$2"; pass=$((pass+1))
  else printf '  FAIL  %-58s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}

# --- 1. CODE side: every harness is bash by shebang -------------------------------
total=0; non_bash=0
while IFS= read -r f; do
  [ -n "$f" ] || continue
  total=$((total+1))
  first_line="$(head -n 1 "$f")"
  case "$first_line" in
    '#!/usr/bin/env bash'|'#!/bin/bash') ;;
    *) non_bash=$((non_bash+1)); printf '        NOT-BASH  %s -> %s\n' "${f#$REPO/}" "$first_line" ;;
  esac
done <<EOF
$(find "$REPO/tests" -maxdepth 1 -name '*.test.sh' | sort)
EOF

ok "harnesses found"                 "$([ "$total" -gt 0 ] && echo yes || echo no)" yes
ok "every harness carries a bash shebang" "$non_bash" 0

# --- 2. CONFIG side: .coderabbit.yaml doesn't reassert the false claim ------------
CFG="$REPO/.coderabbit.yaml"
ok ".coderabbit.yaml exists"         "$([ -f "$CFG" ] && echo yes || echo no)" yes

reasserted="$(grep -ci 'posix shell' "$CFG" || true)"
ok "config no longer claims POSIX shell" "$reasserted" 0

declares_bash="$(grep -ci 'bash' "$CFG" || true)"
ok "config names bash somewhere"     "$([ "$declares_bash" -gt 0 ] && echo yes || echo no)" yes

# --- Non-vacuity: the checker must actually fail on broken input -----------------
tmp="$(mktemp -d "${TMPDIR:-/tmp}/dialect.XXXXXX")"
tmp="$(cd "$tmp" && pwd)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/tests"
printf '#!/bin/sh\necho hi\n' > "$tmp/tests/fake.test.sh"
printf '#!/usr/bin/env bash\necho hi\n' > "$tmp/tests/fake-ok.test.sh"
bad=0
while IFS= read -r f; do
  [ -n "$f" ] || continue
  fl="$(head -n 1 "$f")"
  case "$fl" in
    '#!/usr/bin/env bash'|'#!/bin/bash') ;;
    *) bad=$((bad+1)) ;;
  esac
done <<EOF
$(find "$tmp/tests" -maxdepth 1 -name '*.test.sh' | sort)
EOF
ok "checker flags a synthetic #!/bin/sh harness" "$bad" 1

printf 'placeholder posix shell claim\n' > "$tmp/fake.coderabbit.yaml"
fake_reasserted="$(grep -ci 'posix shell' "$tmp/fake.coderabbit.yaml" || true)"
ok "checker flags a reasserted POSIX-shell config claim" "$([ "$fake_reasserted" -gt 0 ] && echo yes || echo no)" yes

printf '\n%s passed, %s failed  (%s harness(es) checked)\n' "$pass" "$fail" "$total"
[ "$fail" -eq 0 ]
