#!/usr/bin/env bash
#
# readme-brand-mark.test.sh — the README's loopd mark is COPIED, and the command slugs are
# NOT renamed yet.
#
# WHY THE MARK IS PINNED AS BYTES. The three rows are box-drawing glyphs (▄ ▐ ▌ ▝ ◀ ━),
# not ASCII, and nothing else in this repo holds a copy to compare against. A row retyped
# by eye renders plausibly and is still wrong — one glyph or one space of drift and the
# loop no longer closes in a terminal. So the owner's `assets/ascii-logo.txt` rows are the
# fixture below, and the README is diffed against them (loopd/task-001).
#
# AND THE HALF THAT IS EASY TO SHIP EARLY. Every command is still `/ai-bridge:*` until the
# rename lands (loopd/task-007): a README that renames them first documents instructions
# nobody can run, and the marketplace lines must keep resolving to what is published today.
# The zero-mention assertion therefore runs over the whole shipped surface rather than over
# this one file — the control panel's
# knowledge/findings/a-zero-mention-assertion-scoped-to-the-renamed-file-is-not-a-sweep.md
# is the measured cost of the narrower version (104 surviving mentions behind a green check).
#
# NON-VACUOUS BY CONSTRUCTION. Each predicate also runs on a mutant carrying exactly the
# drift it exists to catch, and the mutant must go red.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
README="$REPO/README.md"
[ -f "$README" ] || { echo "readme-brand-mark.test: missing $README" >&2; exit 2; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/readme-brand-mark.XXXXXX")" \
  || { echo "readme-brand-mark.test: could not create a temp dir" >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
ok() { # <name> <actual> <expected>
  if [ "$2" = "$3" ]; then printf '  PASS  %-56s (%s)\n' "$1" "$2"; pass=$((pass+1))
  else printf '  FAIL  %-56s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}
count() { grep -cF -- "$2" "$1" | tr -d ' '; }

# The mark, byte for byte, from projects/loopd/sources/loopd-design/assets/ascii-logo.txt.
cat > "$TMP/mark.txt" <<'MARK'
   ▄▄▄▄
◀━▐    ▌   loopd — the loop, running
  ▝▄▄▄▄▘
MARK

# The fenced rows of a README: lines 2-4, which is where the mark is required to be.
rows() { sed -n '2,4p' "$1"; }
mark_matches() { diff -q "$TMP/mark.txt" <(rows "$1") >/dev/null 2>&1 && echo yes || echo no; }

# Every tracked path a reader is shipped, same scope as install-era-wording.test.sh.
shipped_surface() { ( cd "$REPO" && git ls-files -- README.md docs plugin .claude 2>/dev/null ); }

echo
echo "== 1. the README opens with the mark, copied =="
ok "line 1 opens a fenced block"      "$(head -1 "$README")" '```text'
ok "line 5 closes it"                 "$(sed -n '5p' "$README")" '```'
ok "rows 2-4 are the mark, byte for byte" "$(mark_matches "$README")" yes

echo
echo "== 2. the name, the line and the two-colour rule =="
ok "the tagline appears once"         "$(count "$README" 'loopd — the loop, running')" 1
ok "the motto appears once"           "$(count "$README" 'You steer. They build. Two gates stay yours.')" 1
ok "blue is stated once"              "$(count "$README" '#5ea2ff')" 1
ok "pink is stated once"              "$(count "$README" '#ff7ac2')" 1
ok "blue is the machine's"            "$(count "$README" "Blue \`#5ea2ff\` is the machine's")" 1
ok "pink is the human's"              "$(count "$README" 'Pink `#ff7ac2` is yours')" 1

echo
echo "== 3. the slugs are untouched until task-007 =="
ok "no /loopd: slug in the README"    "$(count "$README" '/loopd:')" 0
ok "…nor anywhere on the shipped surface" \
   "$(shipped_surface | tr '\n' '\0' | (cd "$REPO" && xargs -0 grep -lF -- '/loopd:' 2>/dev/null) | wc -l | tr -d ' ')" 0
ok "the README still documents /ai-bridge: commands" \
   "$([ "$(count "$README" '/ai-bridge:')" -gt 0 ] && echo yes || echo no)" yes
ok "the marketplace line resolves today" \
   "$([ "$(count "$README" '/plugin marketplace add cbmono/ai-bridge')" -gt 0 ] && echo yes || echo no)" yes
ok "the install line resolves today" \
   "$([ "$(count "$README" '/plugin install ai-bridge@ai-bridge')" -gt 0 ] && echo yes || echo no)" yes

echo
echo "== 4. three mutants go RED — the checks discriminate =="
sed '3s/▐/|/' "$README" > "$TMP/redrawn.md"
ok "mutant A: one retyped glyph fails the byte check" "$(mark_matches "$TMP/redrawn.md")" no

sed 's|/ai-bridge:dispatch|/loopd:dispatch|' "$README" > "$TMP/renamed.md"
ok "mutant B: an early slug rename is reported" \
   "$([ "$(count "$TMP/renamed.md" '/loopd:')" -gt 0 ] && echo yes || echo no)" yes

sed 's|ai-bridge@ai-bridge|loopd@loopd|' "$README" > "$TMP/unresolvable.md"
ok "mutant C: a renamed install line is reported" \
   "$(count "$TMP/unresolvable.md" '/plugin install ai-bridge@ai-bridge')" 0

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
