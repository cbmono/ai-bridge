#!/usr/bin/env bash
#
# tick-delta.test.sh — the idle-tick fast-path probe: `plugin/scripts/tick-delta.sh`.
#
# THE ONE PROPERTY THAT MATTERS, asserted from both sides everywhere: a false DELTA
# costs one full tick — the price that was always paid — but a false IDLE skips owed
# work, so ONLY a byte-for-byte fingerprint match may print IDLE, and every doubt
# (no record, no `gh`, a poisoned PR read, a live dispatch, a dirty tree) must resolve
# to a full tick (exit 1 or 2), never to 0. "It detects the delta" alone would pass a
# probe that says DELTA always, so the idle direction is pinned first and re-pinned
# after every delta case is healed.
#
# `gh` IS A PATH STUB reading canned per-URL answers from a control directory — no
# network, nothing real is fetched, and the stub can be made to fail on demand, which
# is how the poisoned-fingerprint direction is exercised. Fixtures live under mktemp;
# no real instance is touched. ok() compares actual to expected, this directory's
# convention.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$REPO/plugin/scripts/tick-delta.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/tickdelta.XXXXXX")" || {
  echo "tick-delta.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp} — create that directory first." >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then printf '  PASS  %-62s (%s)\n' "$1" "$2"; pass=$((pass+1))
       else printf '  FAIL  %-62s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi; }

GIT() { env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE git \
          -c user.email=t@example.com -c user.name=Test -c commit.gpgsign=false \
          -c core.hooksPath=/dev/null "$@"; }

# ------------------------------------------------------------------- the fixture
INST="$TMP/inst"
mkdir -p "$INST/projects/proj-a/tasks" "$INST/scripts"
cp "$SRC" "$INST/scripts/tick-delta.sh"; chmod +x "$INST/scripts/tick-delta.sh"
SH="$INST/scripts/tick-delta.sh"

task() { # <file> <status> [pr-url]
  { printf 'type: Task\nkind: build\nstatus: %s\n' "$2"
    [ $# -ge 3 ] && printf 'pr: ["%s"]\n' "$3" || printf 'pr: []\n'
  } > "$1"
}
printf 'type: Project\nstatus: active\nautonomy: gated\n' > "$INST/projects/proj-a/project.md"
task "$INST/projects/proj-a/tasks/t1.md" ready
task "$INST/projects/proj-a/tasks/t2.md" in-review "https://github.com/example-org/example-repo/pull/7"
# The real instance gitignores the fingerprint (install.sh's guard block); without this,
# `git add -A` below would COMMIT .tick-state and every later record would dirty the tree.
printf '/.tick-state\n' > "$INST/.gitignore"
GIT -C "$INST" init -q
GIT -C "$INST" add -A && GIT -C "$INST" commit -qm init

# The gh stub: `gh pr view <url> --json ... --jq ...` prints the canned line for the
# URL's PR number from $GHDIR/<n>, or fails when $GHDIR/<n>.fail exists.
GHDIR="$TMP/gh"; mkdir -p "$GHDIR"
BIN="$TMP/bin"; mkdir -p "$BIN"
cat > "$BIN/gh" <<'EOS'
#!/usr/bin/env bash
url="$3"
n="${url##*/}"
[ -e "$GHDIR/$n.fail" ] && exit 1
[ -f "$GHDIR/$n" ] || exit 1
cat "$GHDIR/$n"
EOS
chmod +x "$BIN/gh"
printf 'OPEN abc1234 NONE\n' > "$GHDIR/7"
WITH() { PATH="$BIN:$PATH" GHDIR="$GHDIR" "$SH" "$@" --instance "$INST"; }

run() { # <check|record> -> "rc:<n> first-line"
  local out rc
  out="$(WITH "$1" 2>&1)"; rc=$?
  printf 'rc:%s %s' "$rc" "$(printf '%s\n' "$out" | head -1 | cut -c1-12)"
}

echo "== no record yet: doubt resolves to the full tick, never to IDLE =="
ok "check before any record is exit 2"          "$(run check)" "rc:2 CANNOT ANSWE"
WITH record; ok "record writes the state file"  "$([ -f "$INST/.tick-state" ] && echo yes || echo no)" yes

echo "== the idle direction: only a byte-for-byte match says IDLE =="
ok "record then check is IDLE (exit 0)"          "$(run check)" "rc:0 IDLE: finger"
ok "…and idle twice in a row stays idle"        "$(run check)" "rc:0 IDLE: finger"

echo "== every delta class flips it — and healing each restores IDLE =="
GIT -C "$INST" commit -q --allow-empty -m tick
ok "a new bundle commit is a DELTA"              "$(run check)" "rc:1 DELTA: the f"
WITH record; ok "…healed by re-record"          "$(run check)" "rc:0 IDLE: finger"

printf 'edited\n' >> "$INST/projects/proj-a/tasks/t1.md"
ok "a dirty tracked file is a DELTA"             "$(run check)" "rc:1 DELTA: track"
GIT -C "$INST" checkout -q -- .
ok "…healed by a clean tree"                    "$(run check)" "rc:0 IDLE: finger"

printf 'draft\n' > "$INST/projects/proj-a/tasks/new-draft.md"
ok "an untracked file under projects/ is a DELTA" "$(run check)" "rc:1 DELTA: untra"
rm -f "$INST/projects/proj-a/tasks/new-draft.md"

task "$INST/projects/proj-a/tasks/t1.md" in-progress
GIT -C "$INST" add -A && GIT -C "$INST" commit -qm dispatch
WITH record
ok "an in-progress task is a DELTA even against its own record" "$(run check)" "rc:1 DELTA: task("
task "$INST/projects/proj-a/tasks/t1.md" ready
GIT -C "$INST" add -A && GIT -C "$INST" commit -qm undo
WITH record; ok "…and clears when nothing is in flight"        "$(run check)" "rc:0 IDLE: finger"

printf 'OPEN def5678 NONE\n' > "$GHDIR/7"
ok "a moved PR head is a DELTA"                  "$(run check)" "rc:1 DELTA: the f"
printf 'MERGED def5678 NONE\n' > "$GHDIR/7"
ok "…so is a state change"                      "$(run check)" "rc:1 DELTA: the f"
printf 'OPEN abc1234 CHANGES_REQUESTED\n' > "$GHDIR/7"
ok "…so is a review decision"                   "$(run check)" "rc:1 DELTA: the f"
printf 'OPEN abc1234 NONE\n' > "$GHDIR/7"
ok "…and the original PR facts restore IDLE"    "$(run check)" "rc:0 IDLE: finger"

touch "$INST/AWAITING.md"
ok "a touched AWAITING.md (queue re-enable) is a DELTA" "$(run check)" "rc:1 DELTA: the f"
rm -f "$INST/AWAITING.md"

echo "== a poisoned fingerprint is no answer at all — and record refuses to write it =="
touch "$GHDIR/7.fail"
ok "an unreadable PR makes check exit 2"         "$(run check)" "rc:2 CANNOT ANSWE"
before="$(cat "$INST/.tick-state")"
WITH record 2>/dev/null; rc=$?
ok "…and record refuses (exit 2)"               "$rc" 2
ok "…leaving the previous record untouched"     "$([ "$(cat "$INST/.tick-state")" = "$before" ] && echo yes || echo no)" yes
rm -f "$GHDIR/7.fail"

# HERMETIC: a bin dir holding every tool the script needs and NOTHING else — a bare
# system PATH could still carry a real gh (and would let this test touch the network).
NOGH="$TMP/nogh"; mkdir -p "$NOGH"
for t in bash sh git sed grep sort date mv rm diff head cut env; do
  tp="$(command -v "$t" 2>/dev/null)" && ln -s "$tp" "$NOGH/$t"
done
ok "no gh on PATH is exit 2, never IDLE"         "$(PATH="$NOGH" "$SH" check --instance "$INST" >/dev/null 2>&1; echo "rc:$? ")" "rc:2 "

# In `check`, an unreadable tracked file trips the dirty branch first (git reports it
# modified) — fail-closed either way. The load-bearing path is RECORD, which has no dirty
# pre-check: a record built over the unreadable file would be the hole a later check
# "matches".
chmod 000 "$INST/projects/proj-a/tasks/t1.md"
before2="$(cat "$INST/.tick-state")"
WITH record 2>/dev/null; rc2=$?
ok "record over an unreadable task file refuses (exit 2)"       "$rc2" 2
ok "…leaving the record untouched"              "$([ "$(cat "$INST/.tick-state")" = "$before2" ] && echo yes || echo no)" yes
chmod 644 "$INST/projects/proj-a/tasks/t1.md"
ok "…and readable again restores IDLE"          "$(run check)" "rc:0 IDLE: finger"

echo "== the digest: the same walk, enriched, for the tick that must orient =="
D="$(WITH digest)"; drc=$?
ok "digest exits 0 and prints the enumeration"   "$drc" 0
ok "…a project line with status and autonomy"   "$(printf '%s\n' "$D" | grep -c 'project proj-a status=active autonomy=gated')" 1
ok "…a task line with the orienting fields"     "$(printf '%s\n' "$D" | grep -c 'tasks/t2.md status=in-review kind=build assignee=- deps=0 q=0 crit=no wt=no')" 1
ok "…and the PR facts fetched once"             "$(printf '%s\n' "$D" | grep -c 'pr https://github.com/example-org/example-repo/pull/7 OPEN abc1234 NONE')" 1

mkdir -p "$INST/projects/done-proj/tasks"
printf 'type: Project\nstatus: done\n' > "$INST/projects/done-proj/project.md"
task "$INST/projects/done-proj/tasks/old.md" done
GIT -C "$INST" add -A && GIT -C "$INST" commit -qm done-proj
ok "a done project is skipped at its frontmatter in the digest" \
   "$(WITH digest | grep -c 'done-proj/tasks')" 0
ok "…and in the probe walk too"                 "$(WITH record; grep -c 'done-proj/tasks' "$INST/.tick-state")" 0
ok "…while its project line still shows in the digest" "$(WITH digest | grep -c 'project done-proj status=done')" 1

mkdir -p "$INST/projects/broken/tasks"
task "$INST/projects/broken/tasks/orphan.md" ready
ok "a tasks/ dir with no project.md poisons the walk (exit 2, not a silent hole)" \
   "$(WITH digest >/dev/null 2>&1; echo $?)" 2
rm -rf "$INST/projects/broken"; GIT -C "$INST" checkout -q -- . 2>/dev/null

echo "== plumbing =="
ok "not a git repo is exit 2"    "$(mkdir -p "$TMP/plain"; "$SH" check --instance "$TMP/plain" >/dev/null 2>&1; echo $?)" 2
ok "a bad mode is usage (3)"     "$("$SH" frobnicate >/dev/null 2>&1; echo $?)" 3
ok "the shipped file is executable in the index" \
   "$(cd "$REPO" && git ls-files -s plugin/scripts/tick-delta.sh | awk '{print $1}')" 100755

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
