#!/usr/bin/env bash
#
# harness-read-paths.test.sh — a harness assertion whose literal path does not resolve is
# a FAILURE, not a datum.
#
# THE CLASS. `grep -q PAT "$HERE/../seed/.claude/settings.json"` exits 2 when the file is
# gone, the `|| echo 0` arm runs, and 0 is exactly what the assertion expects. The read
# failing and the property holding produce the SAME observation, so a path move silently
# converts a test into a certificate. `seed/` moved to `plugin/seed/` in #125 and left two
# such assertions behind (tests/push-state.test.sh, tests/derived-indexes.test.sh); both
# were confirmed by mutation — plant the exact regression the assertion exists for, suite
# stays green. See ai-bridge-v2/task-029 and the control panel's
# knowledge/findings/a-test-that-has-never-failed-is-not-a-test.md.
#
# ============================ WHAT THIS SCANNER REACHES ============================
#
# Stated up front and honestly, because the tempting claim — "it catches the class" — is
# false, and a scanner believed to cover more than it does is the same failure one level up.
#
#   REACHED NATIVELY. Every literal path rooted at $TPL (the checked-in template root) or
#   $HERE (this tests/ directory) on a non-comment line, in a file where those two
#   variables PROVABLY bind to those roots. That is a SUPERSET of the `grep`/`cat`/`test -f`
#   read targets task-029 asked for: no command classifier is attempted, because $TPL and
#   $HERE address the checked-in tree, harnesses never write to it, and "a literal
#   reference to a tracked path resolves" is a cleaner invariant than any list of read
#   commands. Deliberate references to an ABSENT path opt OUT, one call site at a time,
#   with `# path-scan: absent — <reason>`.
#
#   REACHED ONLY BY OPT-IN. `git check-ignore --no-index <path>`. That flag is DESIGNED to
#   answer for a path that does not exist — it is the whole reason `--no-index` exists — so
#   a blanket must-resolve rule over check-ignore targets would be WRONG, and would fail
#   every legitimate probe of a would-be path. The rule is therefore opt-in per call site:
#   `# path-scan: must-resolve` above the statement. tests/derived-indexes.test.sh carries
#   exactly one.
#
#   NOT REACHED AT ALL, and this is the important line. An assertion aimed at a file that
#   EXISTS but cannot act. #122 reduced install.sh to a 37-line stub that prints a message
#   and exits 2, and `grep -qF "$KEY" "$TPL/install.sh"` went on certifying that a script
#   writing nothing at all does not write that key. The path resolves, so no
#   path-resolution scanner can ever see it. That class needs the OTHER guard: assert the
#   non-action against a run that provably WAS able to act, and assert that too — see
#   tests/banner-board-line.test.sh's produced-config assertion and the planted-key
#   non-vacuity scan beside it. The fixture below pins this limit as an assertion rather
#   than leaving it as prose, so nobody later reads the scanner as covering it.
#
#   NOT REACHED: a printf FORMAT string that looks like a path. `printf '... "$TPL/%s/x"'`
#   is a template, not a read. Rare enough that it is handled the same way any other
#   deliberate non-path is — `# path-scan: absent` at the call site — and this file is the
#   only harness that does it.
#
#   NOT REACHED: files that rebind TPL. Eight harnesses set `TPL="$TMP/tpl"` — a fixture
#   template, not the checkout — so their `$TPL/...` literals are runtime paths this
#   scanner cannot resolve. Those files are SKIPPED for $TPL and the skip list is PRINTED,
#   because a silent skip is the failure mode this whole file is about.
#
# ============================ NON-VACUITY ============================
#
# The scanner is proven by removal against a planted fixture tree, in this file, on every
# run: a synthetic harness carrying the item-1 shape, the item-2 shape, an UNMARKED
# check-ignore (must not fire — the opt-in has to be real), a resolving path (must not
# fire), an opted-out absence assertion (must not fire), an install.sh-shaped inert-file
# read (must not fire — the stated limit), and a rebound-TPL file (must be skipped, and
# said so). A scanner asserted only against a clean tree reports "no findings" identically
# whether it works or does nothing at all.
#
# assert() follows the convention of the other harnesses here: 0 is a PASS.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
TPL="$(cd "$HERE/.." && pwd)"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/harness-read-paths.XXXXXX")" || {
  echo "harness-read-paths.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp} — create that directory first." >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
assert() { if [[ "$2" == 0 ]]; then printf '  PASS  %s\n' "$1"; pass=$((pass+1));
           else printf '  FAIL  %s\n' "$1"; fail=$((fail+1)); fi; }
eq()     { [ "$1" = "$2" ] && echo 0 || echo 1; }

# ---------------------------------------------------------------------------------------
# The scanner.
#
# candidates() emits one `<file>|<line>|<kind>|<relative-path>` record per literal it can
# resolve the ROOT of; the caller does the filesystem test, because awk cannot.
#
# Marker semantics, kept deliberately small so a reader can predict them: a
# `# path-scan: …` comment arms the STATEMENT that begins on the next non-blank,
# non-comment line, where a statement continues while its lines end in a backslash. A
# blank line disarms a pending marker.
# ---------------------------------------------------------------------------------------
CANDIDATES_AWK='
{
  line = $0
  if (line ~ /^[ \t]*#/) {
    if (line ~ /path-scan:[ \t]*absent/)       pend_absent  = 1
    if (line ~ /path-scan:[ \t]*must-resolve/) pend_resolve = 1
    next
  }
  if (line ~ /^[ \t]*$/) { pend_absent = 0; pend_resolve = 0; next }

  if (!in_stmt) {
    cur_absent = pend_absent; cur_resolve = pend_resolve
    pend_absent = 0; pend_resolve = 0
  }
  nxt = (line ~ /\\[ \t]*$/) ? 1 : 0

  if (!cur_absent) {
    rest = line
    # The terminator set matters for the UNQUOTED tail form (`"$TPL"/a/b`): shell
    # metacharacters end the word, and leaving `;` out of it once produced a candidate
    # path of `tests/*.test.sh;` from the `for … ; do` loop below. The quoted form
    # (`"$TPL/a/b"`) is ended by its own closing quote and never reaches them.
    while (match(rest, /"\$(TPL|HERE)"?\/[^"$ \t;()&|<>`]*/)) {
      tok  = substr(rest, RSTART, RLENGTH)
      rest = substr(rest, RSTART + RLENGTH)
      if (tok ~ /^"\$TPL/)  { root = "TPL";  sub(/^"\$TPL"?\//,  "", tok) }
      else                  { root = "HERE"; sub(/^"\$HERE"?\//, "", tok) }
      if (root == "TPL"  && !tpl_ok)  { continue }
      if (root == "HERE" && !here_ok) { continue }
      if (tok == "") { continue }
      print FILENAME "|" FNR "|" root "|" tok
    }
  }

  # OPT-IN ONLY. `--no-index` legitimately answers for a path that does not exist, so this
  # never fires without a marker at the call site.
  if (cur_resolve) {
    i = index(line, "check-ignore")
    if (i > 0 && tpl_ok) {
      tail = substr(line, i + 12)
      n = split(tail, a, /[ \t]+/)
      for (k = 1; k <= n; k++) {
        t = a[k]
        gsub(/[")]+$/, "", t)
        if (t == "")                continue
        if (substr(t, 1, 1) == "-") continue
        if (t ~ /\$/)               continue   # not a literal — out of reach, and silent
        print FILENAME "|" FNR "|CHECKIGNORE|" t
      }
    }
  }

  in_stmt = nxt
}
'

# root_binding_ok <file> <VAR> — is $VAR provably the checked-in root in this file?
# Trust is per file and per variable: EVERY assignment must be the canonical idiom, and
# there must be at least one, or the variable is a runtime value and its literals are
# out of reach. This is what keeps the eight fixture-template harnesses out.
root_binding_ok() {
  local f="$1" var="$2" seen=0 ok=1 l
  while IFS= read -r l; do
    seen=1
    case "$var" in
      TPL)
        case "$l" in
          *'cd "$HERE/.." && pwd'*|*'cd "$(dirname "$0")/.." && pwd'*) ;;
          *) ok=0 ;;
        esac ;;
      HERE)
        case "$l" in
          *'cd "$(dirname "$0")" && pwd'*) ;;
          *) ok=0 ;;
        esac ;;
    esac
  done < <(grep -E "^[[:space:]]*${var}=" "$f" 2>/dev/null || true)
  [ "$seen" = 1 ] || ok=0
  [ "$ok" = 1 ]
}

# resolves <path> — plain existence, or, for a path carrying a glob metacharacter, at
# least one match. `tests/*.test.sh` and `plugin/scripts/*.sh` are read targets like any
# other and an empty expansion is exactly the silent-nothing this file exists to catch.
resolves() {
  local p="$1" m
  [ -e "$p" ] && return 0
  case "$p" in
    *'*'*|*'?'*|*'['*)
      # Unquoted on purpose. No match leaves the pattern itself, which -e then rejects.
      # shellcheck disable=SC2086
      for m in $p; do [ -e "$m" ] && return 0; done ;;
  esac
  return 1
}

# scan <root> <tests-dir> — prints one human-readable finding per unresolved literal on
# stdout, and the per-file skip list on fd 3 when the caller opens one.
scan() {
  local root="$1" tdir="$2" f base tpl_ok here_ok rel kind ln
  for f in "$tdir"/*.test.sh; do
    [ -e "$f" ] || continue
    base="${f##*/}"
    tpl_ok=0;  root_binding_ok "$f" TPL  && tpl_ok=1
    here_ok=0; root_binding_ok "$f" HERE && here_ok=1
    if [ "$tpl_ok" = 0 ] && grep -qE '^[[:space:]]*TPL=' "$f"; then
      printf 'SKIP %s ($TPL is rebound to a runtime fixture path)\n' "$base" >&3 2>/dev/null || true
    fi
    while IFS='|' read -r _file ln kind rel; do
      [ -n "${rel:-}" ] || continue
      case "$kind" in
        TPL|CHECKIGNORE) resolves "$root/$rel"  && continue ;;
        HERE)            resolves "$tdir/$rel"  && continue ;;
      esac
      printf '%s:%s  [%s]  %s\n' "$base" "$ln" "$kind" "$rel"
    done < <(awk -v tpl_ok="$tpl_ok" -v here_ok="$here_ok" "$CANDIDATES_AWK" "$f")
  done
}

# =======================================================================================
echo "== NON-VACUITY FIRST: the scanner is proven by removal against a planted tree =="
# =======================================================================================
# Built by printf with the stale directory name in a VARIABLE, never spelled literally, so
# this file's own source carries no unresolvable literal and the scanner holds to its own
# rule when it scans itself below.
FX="$TMP/fixture"
GONE=seed          # the pre-#125 directory the item-1 and item-2 probes still named
mkdir -p "$FX/plugin/seed/.claude" "$FX/tests"
printf '{}\n'                   > "$FX/plugin/seed/.claude/settings.json"
printf '# derived\n'            > "$FX/plugin/seed/.gitignore"
printf 'seed index\n'           > "$FX/plugin/seed/index.md"
printf 'exit 2\n'               > "$FX/install.sh"   # exists, and can do nothing — item 3

{
  printf '#!/usr/bin/env bash\n'
  printf 'HERE="$(cd "$(dirname "$0")" && pwd)"\n'
  printf 'TPL="$(cd "$HERE/.." && pwd)"\n'
  printf '\n'
  printf '# A. the item-1 shape: a read of a path the seed move deleted.\n'
  # path-scan: absent — a printf FORMAT, not a path — %s is the fixture's stale dir
  printf 'grep -q hooks "$HERE/../%s/.claude/settings.json"\n' "$GONE"
  printf '\n'
  printf '# B. the item-2 shape, OPTED IN.\n'
  printf '# path-scan: must-resolve\n'
  # path-scan: absent — a printf FORMAT, not a path
  printf 'git -C "$TPL" check-ignore --no-index -q %s/index.md\n' "$GONE"
  printf '\n'
  printf '# C. the same stale check-ignore with NO marker: the opt-in has to be real.\n'
  # path-scan: absent — a printf FORMAT, not a path
  printf 'git -C "$TPL" check-ignore --no-index -q %s/other.md\n' "$GONE"
  printf '\n'
  printf '# D. a path that resolves: never a finding.\n'
  printf 'grep -q derived "$TPL/plugin/seed/.gitignore"\n'
  printf '\n'
  printf '# E. a deliberate absence, opted out at the call site.\n'
  printf '# path-scan: absent — this asserts the file is GONE\n'
  # path-scan: absent — a printf FORMAT, not a path
  printf 'test -e "$TPL/%s/index.md" && echo no || echo yes\n' "$GONE"
  printf '\n'
  printf '# F. the item-3 shape: a real path to a file that cannot act. OUT OF REACH.\n'
  printf 'grep -qF boardArtifactUrl "$TPL/install.sh"\n'
} > "$FX/tests/planted.test.sh"

# G. a harness that rebinds TPL to a fixture: every $TPL literal in it is out of reach,
# and the scanner must SAY so rather than pass over it quietly.
{
  printf '#!/usr/bin/env bash\n'
  printf 'TPL="$TMP/tpl"\n'
  # path-scan: absent — a printf FORMAT, not a path
  printf 'grep -q x "$TPL/%s/nowhere.md"\n' "$GONE"
} > "$FX/tests/rebound.test.sh"

FOUND="$(scan "$FX" "$FX/tests" 3>"$TMP/skips.txt")"
printf '%s\n' "$FOUND" | sed 's/^/    scanner said: /'

assert "A — flags the stale \$HERE-rooted read (the item-1 shape)" \
  "$(printf '%s\n' "$FOUND" | grep -q "planted.test.sh:6  \[HERE\]  ../$GONE/.claude/settings.json" && echo 0 || echo 1)"
assert "B — flags the MARKED stale check-ignore target (the item-2 shape)" \
  "$(printf '%s\n' "$FOUND" | grep -q "\[CHECKIGNORE\]  $GONE/index.md" && echo 0 || echo 1)"
assert "C — does NOT flag the UNMARKED one: the check-ignore rule is genuinely opt-in" \
  "$(printf '%s\n' "$FOUND" | grep -q "$GONE/other.md" && echo 1 || echo 0)"
assert "D — does NOT flag a path that resolves" \
  "$(printf '%s\n' "$FOUND" | grep -q 'plugin/seed/.gitignore' && echo 1 || echo 0)"
# Narrowed to the [TPL] kind on purpose: finding B is a [CHECKIGNORE] on the same
# spelling, and an assertion that matched the path alone would have been satisfied by B —
# a vacuity of exactly the kind this file exists to refuse.
assert "E — does NOT flag a deliberate absence carrying 'path-scan: absent'" \
  "$(printf '%s\n' "$FOUND" | grep -q "\[TPL\]  $GONE/index.md" && echo 1 || echo 0)"
assert "F — does NOT flag install.sh: the stated limit, pinned so nobody assumes otherwise" \
  "$(printf '%s\n' "$FOUND" | grep -q 'install.sh' && echo 1 || echo 0)"
assert "G — reports the rebound-\$TPL harness as SKIPPED rather than passing it silently" \
  "$(grep -q 'SKIP rebound.test.sh' "$TMP/skips.txt" && echo 0 || echo 1)"
assert "…and finds exactly the two it claims and no third thing" \
  "$(eq "$(printf '%s\n' "$FOUND" | grep -c .)" 2)"

# The other half of proof-by-removal: repair the fixture and the same scanner must go
# quiet. A scanner that fires on everything is as useless as one that fires on nothing.
mkdir -p "$FX/$GONE/.claude"
printf '{}\n'     > "$FX/$GONE/.claude/settings.json"
printf 'stale\n'  > "$FX/$GONE/index.md"
assert "…and goes SILENT once the planted paths are made to resolve" \
  "$(eq "$(scan "$FX" "$FX/tests" 3>/dev/null | grep -c .)" 0)"

echo
# =======================================================================================
echo "== THE REAL TREE: every literal path a harness reads resolves =="
# =======================================================================================
REAL="$(scan "$TPL" "$TPL/tests" 3>"$TMP/real-skips.txt")"
n_files=0; for _h in "$TPL"/tests/*.test.sh; do [ -e "$_h" ] && n_files=$((n_files+1)); done
n_skip="$(grep -c . "$TMP/real-skips.txt" 2>/dev/null || echo 0)"
echo "  scanned $n_files harnesses; \$TPL out of reach in $n_skip of them:"
sed 's/^/    /' "$TMP/real-skips.txt"
if [ -n "$REAL" ]; then printf '%s\n' "$REAL" | sed 's/^/    UNRESOLVED: /'; fi
assert "no harness reads a literal \$TPL/\$HERE path that does not resolve" \
  "$(eq "$(printf '%s' "$REAL" | grep -c .)" 0)"

echo
printf 'pass=%d fail=%d\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
