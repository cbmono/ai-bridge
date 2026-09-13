#!/usr/bin/env bash
#
# status-line.test.sh — `plugin/scripts/status-line.sh`, the bundle's `statusLine`.
#
# THE PROPERTIES:
#   * ONE LINE, FROM THE FILES THAT ACTUALLY CARRY THE FACTS. Task frontmatter for
#     in-flight, AWAITING.md for need-you, `.tick-lock` for the lock, `log.md`'s last
#     `* TICK` for the time — and NOT `SNAPSHOT.json` or `.tick-state`, both of which are
#     wrong or absent exactly when the line matters.
#   * IT DEGRADES INSTEAD OF LYING. Every absent-file path renders `?` and never `0`, and
#     `0` is still printed when zero is what the files say. Outside a bundle: nothing.
#   * COLOUR SURVIVES A BARE NON-TTY, because a statusLine's stdout is always a pipe into
#     Claude Code. `NO_COLOR` and `--color never` are the only opt-outs; 3/4-bit only.
#   * OFFLINE AND MODEL-FREE, PROVEN: `gh`/`git`/`jq` are PATH stubs that leave a sentinel.
#   * UNDER 100 ms per invocation, measured here rather than asserted.
# Fixtures live under mktemp; no real bundle is touched.
# Exit: 0 all assertions pass, 1 one failed, 2 the fixture could not be built.
# Reasoning: ai-bridge-v3/task-025.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SL="$REPO/plugin/scripts/status-line.sh"
[ -f "$SL" ] || { echo "status-line.test: missing $SL" >&2; exit 2; }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/statusline.XXXXXX")" || {
  echo "status-line.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp}." >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then printf '  PASS  %-62s (%s)\n' "$1" "$2"; pass=$((pass+1))
       else printf '  FAIL  %-62s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi; }

# The offline proof: three commands that can only ever be caught. SENTINEL survives the
# call, so "it printed the right line" and "it never asked the network" are two assertions.
BIN="$TMP/bin"; mkdir -p "$BIN"
for t in gh jq git curl; do
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$0" >> "$SENTINEL"\nexit 99\n' > "$BIN/$t"
  chmod +x "$BIN/$t"
done
SENTINEL="$TMP/network-was-touched"

run() { SENTINEL="$SENTINEL" PATH="$BIN:$PATH" bash "$SL" "$@" </dev/null 2>/dev/null; }
plain() { run --instance "$1" --color never; }

# ------------------------------------------------------------------- the fixture bundle
mk() { # <dir> — a bundle with 2 in-flight tasks, 3 awaiting items, a closed tick, no lock
  local d="$1"
  mkdir -p "$d/projects/proj-a/tasks" || return 1
  printf '{ "org": "acme" }\n' > "$d/instance.config.json"
  local i
  for i in 1 2; do
    printf -- '---\ntitle: "t%s"\nstatus: in-progress\n---\n\nstatus: done\n' "$i" \
      > "$d/projects/proj-a/tasks/task-00$i.md"
  done
  printf -- '---\nstatus: ready\n---\n'  > "$d/projects/proj-a/tasks/task-003.md"
  printf -- '---\nstatus: done\n---\n'   > "$d/projects/proj-a/tasks/task-004.md"
  cat > "$d/AWAITING.md" <<'EOF'
# Awaiting you

*Derived and gitignored.*

## 🔴 Awaiting you (3)
* 🔀 **merge** — [a](/projects/proj-a/tasks/task-001.md)
* ✅ **approve** — [b](/projects/proj-a/tasks/task-003.md)
* ❓ **answer** — [c](/projects/proj-a/tasks/task-004.md)

## Something else
* not an awaiting item
EOF
  cat > "$d/log.md" <<'EOF'
# Log

* TICK 2026-09-12T07:00:00Z by cbmono close: an older tick
* TICK 2026-09-13T16:41:05Z by cbmono open: the one this line reports
EOF
}
INST="$TMP/inst"; mk "$INST" || { echo "status-line.test: could not build the fixture" >&2; exit 2; }

# The expected clock reading, derived the same two ways the script tries, so this file
# asserts a real local time rather than re-implementing the conversion once and agreeing
# with itself about a wrong one.
EP="$(date -j -u -f '%Y-%m-%dT%H:%M:%SZ' 2026-09-13T16:41:05Z '+%s' 2>/dev/null)" || EP=""
if [ -n "$EP" ]; then HM="$(date -r "$EP" '+%H:%M')"
else                  HM="$(date -d 2026-09-13T16:41:05Z '+%H:%M' 2>/dev/null)"; fi
[ -n "$HM" ] || { echo "status-line.test: no date(1) this file knows how to drive" >&2; exit 2; }

echo
echo "== 1. the whole line, character for character =="
ok "the healthy bundle" "$(plain "$INST")" \
   "AI Bridge · 2 in flight · 3 need you · lock free · last tick $HM"
: > "$INST/.tick-lock"
ok "…and with a tick holding the lock" "$(plain "$INST")" \
   "AI Bridge · 2 in flight · 3 need you · lock held · last tick $HM"
rm -f "$INST/.tick-lock"
ok "exactly one line of output" "$(plain "$INST" | wc -l | tr -d ' ')" 1

echo
echo "== 2. it read the files that carry the facts, and no others =="
ok 'an `open:` TICK is still the last tick (it is the newest)' \
   "$(printf '%s' "$(plain "$INST")" | grep -c "last tick $HM")" 1
printf '{"counts":{"awaiting":99}}\n' > "$INST/SNAPSHOT.json"
printf 'recorded: 2001-01-01T00:00:00Z\n'    > "$INST/.tick-state"
ok "SNAPSHOT.json and .tick-state change nothing" "$(plain "$INST")" \
   "AI Bridge · 2 in flight · 3 need you · lock free · last tick $HM"
ok "…and neither is named in the source" \
   "$(grep -c 'SNAPSHOT\.json\|\.tick-state' "$SL" | tr -d ' ')" 2
ok "…which is twice, in comments saying why not" \
   "$(grep -v '^[[:space:]]*#' "$SL" | grep -c 'SNAPSHOT\.json\|\.tick-state' | tr -d ' ')" 0
rm -f "$INST/SNAPSHOT.json" "$INST/.tick-state"

echo
echo "== 3. every absent input renders \`?\`, never \`0\` =="
D="$TMP/d1"; mk "$D"; rm -f "$D/AWAITING.md"
ok "no AWAITING.md ⇒ the queue is unknown" "$(plain "$D" | sed 's/.*· \([^·]*need you\) ·.*/\1/')" "? need you"
D="$TMP/d2"; mk "$D"; rm -f "$D/log.md"
ok "no log.md ⇒ the time is unknown"       "$(plain "$D" | sed 's/.*· //')" "last tick ?"
D="$TMP/d3"; mk "$D"; printf '# Log\n\nnothing yet\n' > "$D/log.md"
ok "a log with no TICK line ⇒ unknown"     "$(plain "$D" | sed 's/.*· //')" "last tick ?"
D="$TMP/d4"; mk "$D"; rm -rf "$D/projects"
ok "no projects/ ⇒ in-flight is unknown"   "$(plain "$D" | sed 's/.*Bridge · \([^·]*in flight\) ·.*/\1/')" "? in flight"

echo
echo "== 4. …and zero is still printed when zero is what the files SAY =="
D="$TMP/d5"; mk "$D"
for f in "$D"/projects/proj-a/tasks/*.md; do printf -- '---\nstatus: ready\n---\n' > "$f"; done
ok "no task in progress ⇒ 0, not ?" "$(plain "$D" | sed 's/.*Bridge · \([^·]*in flight\) ·.*/\1/')" "0 in flight"
D="$TMP/d6"; mk "$D"
printf '# Awaiting you\n\n## 🔴 Awaiting you (0)\n\n*nothing waits*\n' > "$D/AWAITING.md"
ok "an empty queue ⇒ 0, not ?"      "$(plain "$D" | sed 's/.*· \([^·]*need you\) ·.*/\1/')" "0 need you"
D="$TMP/d7"; mk "$D"; rm -f "$D"/projects/proj-a/tasks/*.md
ok "a project with no tasks ⇒ 0"    "$(plain "$D" | sed 's/.*Bridge · \([^·]*in flight\) ·.*/\1/')" "0 in flight"

D="$TMP/d9"; mk "$D"; chmod 000 "$D/projects/proj-a/tasks/task-001.md"
ok "an UNREADABLE task doc ⇒ ?, never a quiet undercount" \
   "$(plain "$D" | sed 's/.*Bridge · \([^·]*in flight\) ·.*/\1/')" "? in flight"
chmod 644 "$D/projects/proj-a/tasks/task-001.md"
D="$TMP/d10"; mk "$D"; chmod 000 "$D/AWAITING.md"
ok "…and an unreadable AWAITING.md too" \
   "$(plain "$D" | sed 's/.*· \([^·]*need you\) ·.*/\1/')" "? need you"
chmod 644 "$D/AWAITING.md"

echo
echo "== 5. a \`status:\` in the BODY is not frontmatter =="
D="$TMP/d8"; mk "$D"
printf -- '---\nstatus: done\n---\n\nstatus: in-progress\n' > "$D/projects/proj-a/tasks/task-001.md"
printf -- '---\nstatus: done\n---\n'                        > "$D/projects/proj-a/tasks/task-002.md"
ok "only the first frontmatter block counts" \
   "$(plain "$D" | sed 's/.*Bridge · \([^·]*in flight\) ·.*/\1/')" "0 in flight"

echo
echo "== 6. outside a bundle it prints NOTHING, and it is not an error =="
OUT="$(run --instance "$TMP/bin" --color never; echo "rc=$?")"
ok "no instance.config.json anywhere above ⇒ no output" "${OUT%rc=*}" ""
ok "…and exit 0, because a status line never fails a session" "${OUT##*rc=}" 0
mkdir -p "$INST/projects/proj-a/tasks/deep/deeper"
ok "…while a SUBDIRECTORY of a bundle still finds it" \
   "$(plain "$INST/projects/proj-a/tasks/deep/deeper" | cut -d' ' -f1-2)" "AI Bridge"

echo
echo "== 7. colour: a bare non-TTY keeps it; NO_COLOR and --color never do not =="
esc="$(printf '\033')"
esc_count() { printf '%s' "$1" | tr -cd "$esc" | wc -c | tr -d ' '; }
DEF="$(run --instance "$INST")"
ok "a pipe is still coloured — the whole point"  "$([ "$(esc_count "$DEF")" -gt 0 ] && echo yes || echo no)" yes
ok "--color never strips every escape"           "$(esc_count "$(plain "$INST")")" 0
ok "NO_COLOR strips every escape"                "$(esc_count "$(NO_COLOR=1 run --instance "$INST")")" 0
ok "--color always keeps them"                   "$([ "$(esc_count "$(run --instance "$INST" --color always)")" -gt 0 ] && echo yes || echo no)" yes
ok "…and NO_COLOR= (empty) is NOT set, so colour stays" \
   "$([ "$(esc_count "$(NO_COLOR= run --instance "$INST")")" -gt 0 ] && echo yes || echo no)" yes
ok "the coloured line is the plain one plus SGR" \
   "$(printf '%s' "$DEF" | sed "s/$esc\[[0-9;]*m//g")" "$(plain "$INST")"


# COLOURED BY STATE, which is the half of criterion 1 the plain line cannot show. Read off
# the SGR the segment is wrapped in, not off the words.
sgr_of() { # <output> <segment text> -> the code that opens it
  printf '%s' "$1" | tr '\033' '\n' | grep -F "$2" | sed -n 's/^\[\([0-9;]*\)m.*/\1/p' | head -n1
}
C="$(run --instance "$INST" --color always)"
ok "work in flight is cyan"                "$(sgr_of "$C" '2 in flight')" 36
ok "a queue that needs you is yellow"       "$(sgr_of "$C" '3 need you')" 33
ok "a free lock is dim, not shouting"       "$(sgr_of "$C" 'lock free')" 2
: > "$INST/.tick-lock"
ok "…and a held one is yellow"              "$(sgr_of "$(run --instance "$INST" --color always)" 'lock held')" 33
rm -f "$INST/.tick-lock"
Z="$(run --instance "$TMP/d5" --color always)"
ok "zero in flight goes dim, not cyan"      "$(sgr_of "$Z" '0 in flight')" 2
U="$(run --instance "$TMP/d1" --color always)"
ok "an unknown number is red"               "$(sgr_of "$U" '? need you')" 31

echo
echo "== 8. 3/4-bit ONLY — no 256-colour, no truecolor, no terminfo probe =="
ok "no \`38;5;\` (256-colour) anywhere"  "$(grep -c '38;5;' "$SL" | tr -d ' ')" 0
ok "no \`38;2;\` (truecolor) anywhere"   "$(grep -c '38;2;' "$SL" | tr -d ' ')" 0
ok "COLORTERM is never asked"            "$(grep -v '^[[:space:]]*#' "$SL" | grep -c 'COLORTERM' | tr -d ' ')" 0
ok "tput is never called"                "$(grep -v '^[[:space:]]*#' "$SL" | grep -c 'tput' | tr -d ' ')" 0
ok "…and \`[ -t 1 ]\` is never the colour question" \
   "$(grep -v '^[[:space:]]*#' "$SL" | grep -c -- '-t 1' | tr -d ' ')" 0

echo
echo "== 9. offline, jq-free, model-free =="
ok "nothing reached for gh/jq/git/curl"  "$([ -e "$SENTINEL" ] && cat "$SENTINEL" || echo none)" none
ok "…and none is named in the source"   "$(grep -v '^[[:space:]]*#' "$SL" | grep -cE '(^|[^a-z])(gh|jq|curl) ' | tr -d ' ')" 0

echo
echo "== 10. the session JSON on stdin: drained, and read only for a directory =="
SJ="$(printf '{"session_id":"x","workspace":{"current_dir":"%s"},"cost":{"total_cost_usd":1.5}}' "$INST")"
ok "\`current_dir\` locates the bundle" \
   "$(printf '%s' "$SJ" | SENTINEL="$SENTINEL" PATH="$BIN:$PATH" bash "$SL" --color never 2>/dev/null)" \
   "AI Bridge · 2 in flight · 3 need you · lock free · last tick $HM"
ok "…and --instance wins over it" \
   "$(printf '%s' "$SJ" | SENTINEL="$SENTINEL" PATH="$BIN:$PATH" bash "$SL" --instance "$TMP/d5" --color never 2>/dev/null \
      | sed 's/.*Bridge · \([^·]*in flight\) ·.*/\1/')" "0 in flight"
ok "no dollar figure is ever echoed back" \
   "$(printf '%s' "$SJ" | SENTINEL="$SENTINEL" PATH="$BIN:$PATH" bash "$SL" --color never 2>/dev/null | grep -c '1\.5\|usd' | tr -d ' ')" 0

echo
echo "== 11. it is a SCRIPT, and a fast one =="
ok "ships executable" "$(cd "$REPO" && git ls-files -s plugin/scripts/status-line.sh | awk '{print $1}')" 100755
ok "bash -n clean"    "$(bash -n "$SL" 2>&1 | wc -l | tr -d ' ')" 0
# 100 invocations, wall-clock over the lot — `date +%s` is whole seconds, so a smaller
# sample cannot resolve a 50 ms call at all. Reported whatever it says; only a gross
# regression fails, because a loaded CI box is not the machine the 100 ms budget is about.
T0="$(date +%s)"; i=0
while [ "$i" -lt 100 ]; do plain "$INST" >/dev/null; i=$((i + 1)); done
T1="$(date +%s)"
ELAPSED_MS=$(( (T1 - T0) * 1000 / 100 ))
printf '  INFO  %-62s (%s ms/call over 100)\n' "measured invocation cost" "$ELAPSED_MS"
ok "…and it is nowhere near a second per call" "$([ "$ELAPSED_MS" -lt 1000 ] && echo yes || echo no)" yes

echo
echo "== 12. the mutants — these assertions discriminate =="
D="$TMP/m1"; mk "$D"; printf -- '---\nstatus: in-progress\n---\n' > "$D/projects/proj-a/tasks/task-003.md"
ok "a third in-progress task moves the number" \
   "$(plain "$D" | sed 's/.*Bridge · \([^·]*in flight\) ·.*/\1/')" "3 in flight"
D="$TMP/m2"; mk "$D"
printf '%s\n' '* ❓ **answer** — [d](/projects/proj-a/tasks/task-002.md)' >> "$D/AWAITING.md"
ok "…and an item outside the block does NOT" \
   "$(plain "$D" | sed 's/.*· \([^·]*need you\) ·.*/\1/')" "3 need you"
D="$TMP/m3"; mk "$D"
printf '* TICK 2026-09-13T18:00:00Z by cbmono open: newer\n' >> "$D/log.md"
ok "a newer TICK line moves the clock" \
   "$([ "$(plain "$D" | sed 's/.*· //')" != "last tick $HM" ] && echo yes || echo no)" yes

printf '\npass=%d fail=%d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
