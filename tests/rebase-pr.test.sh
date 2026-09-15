#!/usr/bin/env bash
#
# rebase-pr.test.sh — `plugin/scripts/rebase-pr.sh` over a bare-repo fixture with a LOCAL
# `origin`. No `gh`, no network: the stub on PATH is the host, and the bare repo is the
# remote, so every push this file makes is a push into a directory under `mktemp -d`.
#
# THE ONE THING IT HAS TO PIN IS THE FINDING'S FAILURE MODE, NOT "THE SCRIPT RUNS".
# `knowledge/findings/a-running-counter-annotated-by-a-comment-history-is-a-merge-magnet`
# describes a resolution that keeps both sides' annotations, drops the single assignment,
# is `bash -n` clean and fails only at execution. So the counter case asserts the VALUE
# (10 + (12-10) + (11-10) = 13 — the three-way sum, which is neither side's number and is
# what a resolver picking a side always gets wrong) and the assertion-count guard is
# driven to red by a fixture that leaves two assignments behind.
#
# AND THE OTHER HALF: what the script must NOT do. A real code conflict, a delete/modify,
# a fork head, a closed PR and a stale lease each leave the branch AND the remote byte-for-
# byte as they were — asserted by comparing origin's ref before and after every refusal.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$REPO/plugin/scripts/rebase-pr.sh"

pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then printf '  PASS  %-62s (%s)\n' "$1" "$2"; pass=$((pass+1))
       else printf '  FAIL  %-62s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/rebase-pr-test.XXXXXX")" || exit 1
[ -n "$TMP" ] && [ -d "$TMP" ] || { echo "rebase-pr.test: mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "$TMP"' EXIT INT TERM

ORIGIN="$TMP/origin.git"; WORK="$TMP/work"; FIX="$TMP/fix"
mkdir -p "$TMP/bin" "$FIX" "$TMP/home"
export HOME="$TMP/home" GIT_CONFIG_NOSYSTEM=1

cat > "$TMP/bin/gh" <<STUB
#!/usr/bin/env bash
FIX="$FIX"
STUB
cat >> "$TMP/bin/gh" <<'STUB'
[ "${1:-} ${2:-}" = "pr view" ] || { echo "stub gh: unexpected $*" >&2; exit 1; }
cat "$FIX/pr_json"
STUB
chmod +x "$TMP/bin/gh"
export PATH="$TMP/bin:$PATH"

g() { git -C "$WORK" "$@"; }

counter_file() { # <value> <history-tail> — the magnet shape, with room for a second hunk
  printf '#!/usr/bin/env bash\n# 1 -> 2: seeded\n'
  [ "$2" = seeded ] || printf '# 2 -> %s: %s\n' "$1" "$2"
  printf 'EXPECTED_ASSERTIONS=%s\n:\n:\n:\n:\n:\n:\n' "$1"
}

table_file() { # <a.sh row> <b.sh row> — b.sh is a MIDDLE row, as a real conflict is
  printf "#!/usr/bin/env bash\nTABLE='%s a.sh\n%s b.sh\n500 c.sh\n500 d.sh'\n" "$1" "$2"
}
oref() { git -C "$ORIGIN" rev-parse refs/heads/feat 2>/dev/null || echo none; }
oshow() { git -C "$ORIGIN" show "refs/heads/feat:$1" 2>/dev/null || true; }

pr_json() { # <state> <head-oid> <fork?> [mergeable] [mergeStateStatus]
  printf '{"state":"%s","baseRefName":"main","headRefName":"feat","headRefOid":"%s","isCrossRepository":%s,"mergeable":"%s","mergeStateStatus":"%s"}\n' \
    "$1" "$2" "$3" "${4:-CONFLICTING}" "${5:-DIRTY}" > "$FIX/pr_json"
}

seed() {
  rm -rf "$ORIGIN" "$WORK"
  git init -q --bare -b main "$ORIGIN"
  git init -q -b main "$WORK"
  g config user.email t@example.invalid; g config user.name Tester
  g config commit.gpgsign false
  printf '#!/usr/bin/env bash\n# one comment\n:\n:\n:\n' > "$WORK/a.sh"
  printf '#!/usr/bin/env bash\n# one comment\n:\n:\n' > "$WORK/b.sh"
  counter_file 10 seeded > "$WORK/counter.sh"
  table_file 500 500 > "$WORK/table.sh"
  printf '#!/usr/bin/env bash\n# 1 -> 2: seeded\n:\n' > "$WORK/hist.sh"
  printf '#!/usr/bin/env bash\nf() { echo base; }\n' > "$WORK/code.sh"
  g add -A >/dev/null; g commit -qm base
  g remote add origin "$ORIGIN"; g push -q -u origin main
  g checkout -q -b feat
}

# <feat-edit-fn> <main-edit-fn> — one commit each side, both pushed, PR 1 pointed at feat.
scenario() {
  seed
  "$1"; g add -A >/dev/null; g commit -qm "feat"; g push -q -u origin feat
  g checkout -q main
  "$2"; g add -A >/dev/null; g commit -qm "main"; g push -q origin main
  pr_json OPEN "$(g rev-parse refs/heads/feat)" false
}

run() { OUT="$("$SCRIPT" 1 --repo acme/demo --dir "$WORK" "$@" 2>&1)"; RC=$?; }

echo "== the script answers about itself before any host is involved =="
"$SCRIPT" --self-test >/dev/null 2>&1; ok "--self-test exits 0" "$?" 0
"$SCRIPT" notanumber >/dev/null 2>&1; ok "a non-numeric PR is usage (exit 1)" "$?" 1
BASH="$(command -v bash)"
PATH="$TMP/nothing" "$BASH" "$SCRIPT" 1 >/dev/null 2>&1
ok "no gh on PATH is 'cannot answer' (exit 2)" "$?" 2

echo "== the EXPECTED_ASSERTIONS counter: the three-way sum, and both histories kept =="
feat_counter() { counter_file 12 feat > "$WORK/counter.sh"; }
main_counter() { counter_file 11 main > "$WORK/counter.sh"; }
scenario feat_counter main_counter
BEFORE="$(oref)"; run
ok "it rebases and pushes (exit 0)" "$RC" 0
ok "…moving the branch on origin" "$([ "$(oref)" != "$BEFORE" ] && echo yes || echo no)" yes
ok "…to 10 + (12-10) + (11-10) = 13, which is neither side's number" \
   "$(oshow counter.sh | sed -n 's/^EXPECTED_ASSERTIONS=//p')" 13
ok "…with exactly one assignment left (the Finding's failure mode)" \
   "$(oshow counter.sh | grep -c '^EXPECTED_ASSERTIONS=')" 1
ok "…and BOTH sides' history lines" \
   "$(oshow counter.sh | grep -c '^# 2 -> ')" 2
ok "…and the rebase really happened: main's commit is an ancestor of feat" \
   "$(git -C "$ORIGIN" merge-base --is-ancestor refs/heads/main refs/heads/feat && echo yes || echo no)" yes

echo "== an ADD/ADD counter has no base value, so the sum would collapse to one side =="
# `ours + theirs - ours` is theirs: the OURS delta vanishes while the answer still looks
# three-way. No base assignment ⇒ not the shape ⇒ an agent round, not a plausible number.
feat_addadd() { printf '#!/usr/bin/env bash\n# 1 -> 12: feat\nEXPECTED_ASSERTIONS=12\n' > "$WORK/addadd.sh"; }
main_addadd() { printf '#!/usr/bin/env bash\n# 1 -> 11: main\nEXPECTED_ASSERTIONS=11\n' > "$WORK/addadd.sh"; }
scenario feat_addadd main_addadd
BEFORE="$(oref)"; run
ok "an add/add counter conflict exits 3" "$RC" 3
ok "…naming the file" "$(printf '%s' "$OUT" | grep -c 'addadd\.sh')" 1
ok "…leaving origin's branch exactly where it was" "$(oref)" "$BEFORE"

echo "== a comment history conflicting with itself: keep both, in order =="
feat_hist() { printf '#!/usr/bin/env bash\n# 1 -> 2: seeded\n# 2 -> 3: feat\n:\n' > "$WORK/hist.sh"; }
main_hist() { printf '#!/usr/bin/env bash\n# 1 -> 2: seeded\n# 2 -> 3: main\n:\n' > "$WORK/hist.sh"; }
scenario feat_hist main_hist
run
ok "a comment-history conflict rebases clean" "$RC" 0
ok "…keeping both annotations" "$(oshow hist.sh | grep -c '^# 2 -> 3: ')" 2

echo "== a ratchet row both sides lowered: recomputed, not picked =="
feat_table() { table_file 500 400 > "$WORK/table.sh"; }
main_table() { table_file 500 300 > "$WORK/table.sh"; }
scenario feat_table main_table
run
ok "a contested ratchet row rebases clean" "$RC" 0
# b.sh is 4 counted lines carrying 1 comment => 250 tenths. Neither 400 nor 300.
ok "…at the merged file's MEASURED share, not either side's row" \
   "$(oshow table.sh | sed -n 's/^\([0-9]*\) b\.sh$/\1/p')" 250
ok "…and the untouched rows survive" "$(oshow table.sh | grep -c '500 [cd]\.sh')" 2

echo "== a ratchet row one side RAISED is not the shape: recomputing would undo it =="
feat_table_low() { table_file 500 400 > "$WORK/table.sh"; }
main_table_up()  { table_file 500 600 > "$WORK/table.sh"; }
scenario feat_table_low main_table_up
BEFORE="$(oref)"; run
ok "a row raised above its base exits 3" "$RC" 3
ok "…leaving origin's branch exactly where it was" "$(oref)" "$BEFORE"

echo "== what it must NOT resolve: a real code conflict is an agent round =="
feat_code() { printf '#!/usr/bin/env bash\nf() { echo feat; }\n' > "$WORK/code.sh"; }
main_code() { printf '#!/usr/bin/env bash\nf() { echo main; }\n' > "$WORK/code.sh"; }
scenario feat_code main_code
BEFORE="$(oref)"; run
ok "an unclassified conflict exits 3" "$RC" 3
ok "…naming the file" "$(printf '%s' "$OUT" | grep -c 'code\.sh')" 1
ok "…leaving origin's branch exactly where it was" "$(oref)" "$BEFORE"

echo "== a delete/modify conflict has no block to classify, so it is an agent round too =="
feat_del() { rm -f "$WORK/code.sh"; }
main_del() { printf '#!/usr/bin/env bash\nf() { echo main; }\n' > "$WORK/code.sh"; }
scenario feat_del main_del
BEFORE="$(oref)"; run
ok "a delete/modify conflict exits 3" "$RC" 3
ok "…leaving origin's branch exactly where it was" "$(oref)" "$BEFORE"

echo "== the resolution is checked before it is pushed =="
main_dup() { counter_file 11 main > "$WORK/counter.sh"; printf 'EXPECTED_ASSERTIONS=7\n' >> "$WORK/counter.sh"; }
scenario feat_counter main_dup
BEFORE="$(oref)"; run
ok "two assignments after resolution is refused (exit 4)" "$RC" 4
ok "…and nothing is pushed" "$(oref)" "$BEFORE"

echo "== --dry-run resolves and stops =="
scenario feat_counter main_counter
BEFORE="$(oref)"; run --dry-run
ok "--dry-run exits 0" "$RC" 0
ok "…and leaves origin untouched" "$(oref)" "$BEFORE"

echo "== refusals, each leaving the remote alone =="
scenario feat_counter main_counter
BEFORE="$(oref)"
pr_json OPEN "$(g rev-parse refs/heads/feat)" true; run
ok "a fork head is refused (exit 5)" "$RC" 5
pr_json CLOSED "$(g rev-parse refs/heads/feat)" false; run
ok "a closed PR is refused (exit 5)" "$RC" 5
pr_json OPEN 0000000000000000000000000000000000000000 false; run
ok "a lease the host and origin disagree on is exit 6" "$RC" 6
# ONLY a conflicting PR. Rebasing a clean one rewrites its head, which spends its review
# and its green CI for nothing; UNKNOWN is the host still computing, so it is a hold.
pr_json OPEN "$(g rev-parse refs/heads/feat)" false MERGEABLE CLEAN; run
ok "a PR that does not conflict is refused (exit 5)" "$RC" 5
pr_json OPEN "$(g rev-parse refs/heads/feat)" false UNKNOWN UNKNOWN; run
ok "an UNKNOWN mergeability is a hold (exit 2)" "$RC" 2
ok "…and all five left origin's branch alone" "$(oref)" "$BEFORE"

echo "== an already-rebased PR is a no-op, not a push =="
seed
feat_counter; g add -A >/dev/null; g commit -qm feat; g push -q -u origin feat
pr_json OPEN "$(g rev-parse refs/heads/feat)" false
BEFORE="$(oref)"; run
ok "a PR already on top of its base exits 0" "$RC" 0
ok "…without moving the branch" "$(oref)" "$BEFORE"

echo
printf 'rebase-pr.test.sh: pass=%d fail=%d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
