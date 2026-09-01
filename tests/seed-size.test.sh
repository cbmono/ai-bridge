#!/usr/bin/env bash
#
# seed-size.test.sh — the per-turn instruction cost of `seed/CLAUDE.md`, finally pinned.
#
# The harness-native objective has carried this criterion since 2026-08-23: "the
# per-turn instruction cost stops growing and then falls … Tracked by: that command, at
# each re-audit — not yet by a test, which is the next thing to fix about this
# criterion." Unmeasured, the file grew 17,018 → 22,136 bytes in nine days. This is
# that test.
#
# THE CEILING IS A RATCHET, NOT AN ASPIRATION — the machinery-ceiling lesson applied at
# the size where it works: ONE constant in ONE file that no other PR re-measures, so it
# cannot collide across branches the way the retired 944-line ceiling test did.
# Lowering it is always free. Raising it is a deliberate act: change the number in the
# same commit as the growth and say why in the PR body. The objective's stated target
# is 8,000 bytes; the distance from this ceiling to that target is pinned rules the
# owner has so far chosen to keep always-loaded (pr-body-shape.test.sh and
# session-banner.test.sh name them), so closing it is the owner's call, not a diet's.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SEED="$REPO/seed/CLAUDE.md"
CEILING=12800

pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then printf '  PASS  %-58s (%s)\n' "$1" "$2"; pass=$((pass+1))
       else printf '  FAIL  %-58s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi; }

size="$(wc -c < "$SEED" | tr -d ' ')"
ok "seed/CLAUDE.md exists"                     "$([ -f "$SEED" ] && echo yes || echo no)" yes
ok "…and is under the ${CEILING}-byte ceiling (is: ${size})" \
   "$([ "$size" -le "$CEILING" ] && echo yes || echo no)" yes

# Non-vacuity: the same comparison, fed a fixture past the ceiling, must FAIL — a check
# that can only pass is not a check.
TMP="$(mktemp -d "${TMPDIR:-/tmp}/seedsize.XXXXXX")" || exit 2
trap 'rm -rf "$TMP"' EXIT
head -c "$((CEILING + 1))" /dev/zero | tr '\0' 'x' > "$TMP/oversized.md"
over="$(wc -c < "$TMP/oversized.md" | tr -d ' ')"
ok "a fixture one byte past the ceiling FAILS the identical check" \
   "$([ "$over" -le "$CEILING" ] && echo yes || echo no)" no

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
