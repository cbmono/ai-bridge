#!/usr/bin/env bash
#
# harness-temp-safety.test.sh — no harness in this directory may `rm -rf` a path it did
# not create.
#
# WHY THIS IS A TEST AND NOT A FIXED LINE IN TWO FILES. On 2026-08-23 two of the 28
# harnesses here DELETED THE CHECKOUT THEY WERE TESTING, twice, on a machine where
# TMPDIR named a directory that did not exist:
#
#   TMP="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/x.XXXXXX")" && pwd)"   <- the destructive form
#   trap 'rm -rf "$TMP"' EXIT
#
#   1. `mktemp -d` fails, so the inner substitution is the EMPTY STRING;
#   2. `cd ""` SUCCEEDS AND DOES NOT MOVE — a documented bash no-op, not an error, so
#      `&& pwd` runs;
#   3. `pwd` therefore prints the harness's own cwd: the repository root;
#   4. TMP is the repo root, and the EXIT trap runs `rm -rf` over it.
#
# No harness here uses `set -e` (a failed assertion must not abort the file), so nothing
# stops it. The other harnesses use the plain `TMP="$(mktemp -d …)"` form: they get an
# empty TMP, `rm -rf ""` is harmless, and they merely fail loudly. ONLY THE FORM THAT
# CD-s INTO A SUBSTITUTION IS DESTRUCTIVE — and the `cd` cannot simply be deleted, since
# it is what normalises the `/var/…` path with a `//` in it that macOS hands back, against
# assertions that compare `pwd` output.
#
# So the fix is a CLASS, not two lines: the substitution that creates the directory must
# be guarded, and the canonicalising `cd` must be handed a variable already known good.
# This file asserts that shape over every harness in the directory, so the next one that
# reaches for `cd "$(mktemp …)"` fails here rather than on somebody's uncommitted work.
#
# The two static classes, per harness, for every path an EXIT trap deletes:
#   NESTED-CD  the path is produced by cd-ing INTO a command substitution.
#   UNGUARDED  the path is canonicalised through `cd`, but the `mktemp` that created it
#              carries no `||` abort, so a failed mktemp reaches the `cd` empty.
#
# TWO LIMITS, STATED RATHER THAN GUESSED AT. The scanner reads one line at a time, so
# (a) the `||` abort must sit on the `mktemp` assignment line — chasing a guard onto a
# following line would mean deciding which nearby test counts, which is guessing; and
# (b) the trap must name the path inline (`trap 'rm -rf "$TMP"' EXIT`), because a trap
# that calls a cleanup function hides the path from a line-wise read. Every harness in
# this directory does both today, and the corpus assertions below fail loudly if the
# scanner ever stops finding traps at all — which is the failure mode that would let a
# blind spot pass as clean.
#
# Both are asserted NON-VACUOUSLY, over synthetic harnesses that do and do not carry each
# shape: a static check that passes on everything is indistinguishable from no check. The
# fixtures are emitted through `printf` rather than a heredoc on purpose — a heredoc puts
# its body at line start, where this file's own scanner would read the deliberately broken
# fixture lines as this file's own code.
#
# The two once-destructive harnesses are then exercised FOR REAL, in a throwaway copy of
# the checkout: run with a TMPDIR that does not exist, each must abort AND the copy must
# still be there afterwards. That is the actual regression, and it is why the copy is
# entered with `cd` first — an unfixed harness deletes its own cwd, so the blast radius
# has to be the copy.
#
# ok() follows this directory's convention: it compares actual to expected.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
TESTS="$REPO/tests"

die() { printf 'harness-temp-safety.test: %s\n' "$*" >&2; exit 2; }
[ -d "$TESTS" ] || die "no tests directory at $TESTS"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/harness-temp-safety.XXXXXX")" || die "mktemp -d failed under TMPDIR=${TMPDIR:-/tmp} — create that directory first."
# This file eats its own cooking, and it had to: the real macOS $TMPDIR ends in a slash,
# so the raw mktemp result above is `/var/folders/…/T//harness-temp-safety.xxxxxx`, while a
# path built from it and then normalised downstream comes back with one slash — and the
# "path is under TMPDIR" assertion below compared the two and failed. `pwd`, not `pwd -P`:
# the fixtures normalise logically too, and a physical path here would put /private/var
# against their /var. That is the same class of mismatch the two harnesses' `cd` exists to
# avoid, which is why criterion 3 forbids deleting it.
TMP="$(cd "$TMP" && pwd)"
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
ok() { # <name> <actual> <expected>
  if [ "$2" = "$3" ]; then printf '  PASS  %-62s (%s)\n' "$1" "$2"; pass=$((pass+1))
  else printf '  FAIL  %-62s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}

# --- the scanner --------------------------------------------------------------
# scan <file> — prints one line per offence, class first, and nothing when clean.
# Comments are skipped throughout: a comment explaining this very hazard would
# otherwise read as the hazard.
scan() {
  local f="$1" body vars v asg
  body="$(grep -v '^[[:space:]]*#' "$f")"
  # Which paths does a trap delete? Names only, both $V and ${V} spellings.
  vars="$(printf '%s\n' "$body" | grep 'trap' | grep -F 'rm -rf' \
          | grep -oE '\$\{?[A-Za-z_][A-Za-z_0-9]*\}?' | tr -d '${}' | sort -u)"
  for v in $vars; do
    asg="$(printf '%s\n' "$body" | grep -nE "^[[:space:]]*$v=")"
    [ -n "$asg" ] || continue
    # (1) the destructive shape. The leading class keeps `cd` a word: without it,
    #     a variable or function ending in "cd" would read as the builtin.
    printf '%s\n' "$asg" | grep -E '(^|[^[:alnum:]_])cd[[:space:]]+"?\$\(' \
      | sed "s|^|NESTED-CD ${f##*/}:\$$v:|"
    # (2) a `cd` canonicalisation is only safe over a guarded mktemp.
    if printf '%s\n' "$asg" | grep -qE '(^|[^[:alnum:]_])cd[[:space:]]'; then
      printf '%s\n' "$asg" | grep -F 'mktemp' | grep -vF '||' \
        | sed "s|^|UNGUARDED ${f##*/}:\$$v:|"
    fi
  done
}

# --- the corpus ---------------------------------------------------------------
HARNESSES="$(find "$TESTS" -maxdepth 1 -type f -name '*.test.sh' | sort)"
n_harness="$(printf '%s\n' "$HARNESSES" | grep -c '.')"
ok "harnesses found to scan" "$([ "$n_harness" -ge 20 ] && echo "yes ($n_harness)" || echo "no ($n_harness)")" "yes ($n_harness)"

offences=""; trapped=0
while IFS= read -r f; do
  [ -n "$f" ] || continue
  # Non-vacuity of the extractor itself: at least one harness must be seen to trap a
  # path, or every scan below is trivially clean because nothing was ever looked at.
  grep -v '^[[:space:]]*#' "$f" | grep 'trap' | grep -qF 'rm -rf' && trapped=$((trapped+1))
  out="$(scan "$f")"
  [ -n "$out" ] && offences="${offences}${out}
"
done <<EOF
$HARNESSES
EOF

ok "harnesses seen to trap-delete a path" "$([ "$trapped" -ge 10 ] && echo "yes ($trapped)" || echo "no ($trapped)")" "yes ($trapped)"

n_off="$(printf '%s' "$offences" | grep -c '.' || true)"
[ -n "$(printf '%s' "$offences" | tr -d '[:space:]')" ] && printf '%s' "$offences" | sed 's/^/        /'
ok "no trap-deleted path built by cd-ing into a substitution" \
   "$(printf '%s' "$offences" | grep -c '^NESTED-CD' || true)" 0
ok "no cd-canonicalised trap path from an unguarded mktemp" \
   "$(printf '%s' "$offences" | grep -c '^UNGUARDED' || true)" 0
ok "no offence of any class under tests/" "$n_off" 0

# --- non-vacuity: the scanner must reject what it is for ----------------------
# Every fixture line goes out through printf. `FTMP` rather than `TMP` so a reader can
# tell fixture text from this file's own temp handling at a glance.
FX="$TMP/fx"; mkdir -p "$FX"

fx_head() { printf '%s\n' '#!/usr/bin/env bash' 'set -uo pipefail'; }
fx_trap() { printf 'trap %s EXIT\n' "'rm -rf \"\$FTMP\"'"; }

# (a) the destructive form, exactly as it stood in the two harnesses.
{ fx_head
  printf 'FTMP="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/fx.XXXXXX")" && pwd)"\n'
  fx_trap; } > "$FX/bad-nested.test.sh"

# (b) two steps, but the mktemp is unguarded — a failed mktemp still reaches the cd.
{ fx_head
  printf 'FTMP="$(mktemp -d "${TMPDIR:-/tmp}/fx.XXXXXX")"\n'
  printf 'FTMP="$(cd "$FTMP" && pwd)"\n'
  fx_trap; } > "$FX/bad-unguarded.test.sh"

# (c) the idiom this repo already uses in prune-worktrees.test.sh and
#     reclaim-worktree.test.sh: guard first, canonicalise second.
{ fx_head
  printf 'FTMP="$(mktemp -d "${TMPDIR:-/tmp}/fx.XXXXXX")" || { echo "fx: mktemp -d failed" >&2; exit 2; }\n'
  printf 'FTMP="$(cd "$FTMP" && pwd)"\n'
  fx_trap
  printf 'printf %s "$FTMP"\n' "'%s\\n'"; } > "$FX/good-twostep.test.sh"

# (d) the plain form the other harnesses use: no cd, so nothing to guard against.
{ fx_head
  printf 'FTMP="$(mktemp -d)"\n'
  fx_trap; } > "$FX/good-plain.test.sh"

for k in bad-nested bad-unguarded good-twostep good-plain; do
  o="$(scan "$FX/$k.test.sh")"
  case "$k" in
    bad-nested)
      ok "fixture $k is flagged NESTED-CD"  "$(printf '%s' "$o" | grep -c '^NESTED-CD' || true)" 1 ;;
    bad-unguarded)
      ok "fixture $k is flagged UNGUARDED"  "$(printf '%s' "$o" | grep -c '^UNGUARDED' || true)" 1
      ok "fixture $k is not flagged NESTED-CD" "$(printf '%s' "$o" | grep -c '^NESTED-CD' || true)" 0 ;;
    good-*)
      ok "fixture $k is clean" "$(printf '%s' "$o" | grep -c '.' || true)" 0 ;;
  esac
done

# --- the guarded idiom, at runtime, across the three TMPDIR states ------------
IDIOM="$FX/good-twostep.test.sh"

out="$(env -u TMPDIR bash "$IDIOM" 2>&1)"; rc=$?
ok "TMPDIR unset: exits 0"            "$rc" 0
ok "TMPDIR unset: prints a temp dir"  "$([[ "$out" == /* ]] && echo yes || echo no)" yes

REAL="$TMP/real-tmpdir"; mkdir -p "$REAL"
# Trailing slash on purpose: it is why the `cd`+`pwd` normalisation exists at all, so the
# criterion "the macOS reason the cd exists is preserved" is asserted, not assumed.
out="$(TMPDIR="$REAL/" bash "$IDIOM" 2>&1)"; rc=$?
ok "TMPDIR real (trailing slash): exits 0"        "$rc" 0
ok "TMPDIR real: path is under it"               "$([[ "$out" == "$REAL"/* ]] && echo yes || echo no)" yes
ok "TMPDIR real: path is normalised (no '//')"   "$([[ "$out" != *//* ]] && echo yes || echo no)" yes

ABSENT="$TMP/no-such-tmpdir"
out="$(TMPDIR="$ABSENT" bash "$IDIOM" 2>&1)"; rc=$?
ok "TMPDIR absent: aborts non-zero"   "$([ "$rc" -ne 0 ] && echo yes || echo no)" yes
ok "TMPDIR absent: says why"          "$(printf '%s' "$out" | grep -qi 'mktemp' && echo yes || echo no)" yes
ok "TMPDIR absent: created nothing"   "$([ -e "$ABSENT" ] && echo no || echo yes)" yes

# --- the real regression, in a throwaway copy of the checkout -----------------
# The two harnesses that carried the destructive form, run the way that destroyed a
# verification tree: cwd inside a checkout, TMPDIR naming a directory that is not there.
# An unfixed harness deletes its cwd, so the cwd is a copy and the copy is rebuilt for
# each one.
#
# NEVER copy `.` wholesale here. TMPDIR may legitimately sit INSIDE the repo — this
# instance tells its agents to isolate their scratch space, which is the very habit that
# found this bug — and a copy of `.` that contains its own destination recurses until the
# disk fills. Measured while writing this file: a `tar cf - .` reached 247 levels of
# `checkout/.scratch/tmp/checkout/…` in ten minutes, and the result was too deep for
# `rm -rf` to remove. So each top-level entry is copied by name, and any entry that is
# the fixture root or contains it is skipped.
fresh_copy() { # <dest>
  local dest="$1" e
  rm -rf "$dest"; mkdir -p "$dest" || return 1
  for e in "$REPO"/*; do
    [ -e "$e" ] || continue
    case "$TMP" in "$e"|"$e"/*) continue ;; esac
    cp -R "$e" "$dest/" || return 1
  done
  [ -f "$REPO/.gitignore" ] && cp "$REPO/.gitignore" "$dest/"
  return 0
}

for h in board-renderers snapshot; do
  COPY="$TMP/checkout-$h"
  fresh_copy "$COPY" || die "could not copy the checkout for $h"
  ok "$h: fixture copy is a checkout" \
     "$([ -f "$COPY/tests/$h.test.sh" ] && [ -f "$COPY/install.sh" ] && echo yes || echo no)" yes
  # Capped, because an UNFIXED harness does not abort: it sets TMP to its own cwd and
  # runs its whole suite before the trap deletes it, which is minutes. A test that HANGS
  # is worse than one that fails, so a breach is reported as rc 124 — and the assertion
  # below demands exactly 2 (this directory's refusal status), so a killed run cannot
  # pass by having had its trap skipped.
  LOG="$TMP/run-$h.log"; : > "$LOG"
  ( cd "$COPY" && TMPDIR="$COPY/no-such-tmpdir" bash "tests/$h.test.sh" >"$LOG" 2>&1 ) &
  pid=$!; waited=0
  while kill -0 "$pid" 2>/dev/null && [ "$waited" -lt 60 ]; do sleep 1; waited=$((waited+1)); done
  if kill -0 "$pid" 2>/dev/null; then
    pkill -P "$pid" 2>/dev/null; kill -9 "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; rc=124
  else
    wait "$pid"; rc=$?
  fi
  out="$(cat "$LOG")"
  ok "$h: TMPDIR absent ⇒ exits 2, the refusal status"  "$rc" 2
  ok "$h: TMPDIR absent ⇒ the checkout survives"  "$([ -f "$COPY/tests/$h.test.sh" ] && echo yes || echo no)" yes
  # The harness's OWN refusal line, not mktemp's stderr. A failing `mktemp -d` prints
  # "mktemp: …: No such file or directory" all by itself, so grepping for `mktemp` alone
  # passes just as well on the destructive version — measured, it did.
  ok "$h: TMPDIR absent ⇒ refuses in its own voice" \
     "$(printf '%s\n' "$out" | grep -qE "^$h\.test:.*mktemp" && echo yes || echo no)" yes
  # And the reason the cd exists is still in the file: a "fix" that deleted the
  # canonicalisation would silently break the path assertions these harnesses rest on.
  ok "$h: still canonicalises through cd+pwd" \
     "$(grep -qE 'cd[[:space:]]+"\$TMP"[[:space:]]*&&[[:space:]]*pwd' "$COPY/tests/$h.test.sh" && echo yes || echo no)" yes
  rm -rf "$COPY"
done

printf '\n  %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
