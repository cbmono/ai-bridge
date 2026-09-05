#!/usr/bin/env bash
#
# install-era-wording.test.sh — every surviving mention of `install.sh`, `upgrade.sh` or
# `symlink/` in the shipped surface is DECLARED, nothing may tell a reader to run either
# retired script, and the retired `/pm-loop` command name appears nowhere at all.
#
# WHY THIS IS A TEST AND NOT A ONE-OFF SWEEP. `install.sh` and `upgrade.sh` are refusal
# stubs that exit 2, and `symlink/` is a directory that no longer exists — so a sentence
# naming one of them is either HISTORY, which is fine and often load-bearing, or a stale
# instruction, which is a defect. The two look identical to a grep, and they read
# identically to a reviewer who already knows which is which. That is exactly the class
# that rots: ai-bridge-v2/task-025 found eight files carrying the wording months after the
# replatform, and two of them were not history at all — `docs/pm-design.md` pointed a
# reader at `symlink/.claude/commands/pm-loop.md` in the present tense for a file that had
# moved into `plugin/`, and `docs/conventions.md`'s own table of contents linked to
# `#…letting-installsh-sweep-the-links` for a heading that had been renamed out from under
# it. Finding those cost a hunt across 56 mentions. THE POINT OF THIS FILE IS THAT THE
# NEXT SWEEP IS A DIFF INSTEAD.
#
# THE THREE PROPERTIES, AND WHY EACH IS SHAPED THE WAY IT IS. The third is stated at its
# own section below, because what makes it different is that it has no allowlist.
#
#   1. THE INVENTORY EQUALS THE ALLOWLIST, EXACTLY — a new mention fails, and so does a
#      new FILE. `ALLOWED` below is the declared set: one row per file, the number of
#      matching LINES it may carry, and the reason that file is allowed to carry them.
#      Equality is asserted in BOTH directions. An unknown file or a raised count is the
#      new mention this file exists to catch; a count that DROPPED, or a file that went
#      quiet, is also a failure, because a stale allowlist entry is an allowance nobody
#      re-read — it silently re-opens the budget it was meant to spend.
#
#      COUNTS, NOT LINE NUMBERS. A line number churns on every edit above it, which would
#      turn this into a file everyone re-baselines without reading; a count moves only
#      when a mention is genuinely added or removed. The trade is stated rather than
#      hidden: deleting one historical mention and adding one stale mention in the SAME
#      file passes here. The reason cells are what a reviewer reads to close that gap, and
#      property 2 catches the worst version of it outright.
#
#   2. NOTHING IN SCOPE INSTRUCTS A READER TO RUN EITHER RETIRED SCRIPT. This is the half
#      that does not depend on anyone maintaining a number. `./install.sh`, `bash
#      upgrade.sh`, "run install.sh" and friends are matched wherever they appear in
#      scope, and there is no allowlist for them at all — a bundle installed today has
#      `/ai-bridge:init` and `/ai-bridge:welcome fix`, and any surviving imperative for
#      the old pair sends its reader to a script that exits 2.
#
# SCOPE IS THE TRACKED SHIPPED SURFACE: `README.md`, `docs/` and `plugin/`. Two
# exclusions, both deliberate and both the task's: `docs/migrating.md` is the conversion
# guide, whose entire job is to name the old commands, and `docs/releases/` is a frozen
# record of what shipped. The repo ROOT `install.sh` / `upgrade.sh` stubs are out of scope
# too — they are the retirement, not a mention of it. `tests/` is out of scope, which is
# what lets this file quote the tokens it looks for.
#
# BOTH PROPERTIES ARE PROVEN CAPABLE OF FAILING against a fixture copy of the tree that
# plants exactly the defect each one checks. A check that can only pass is not a check.
#
# ok() follows this directory's convention: it compares actual to expected.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/install-era-wording.XXXXXX")" || {
  echo "install-era-wording.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp} — create that directory first." >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
ok() { # <name> <actual> <expected>
  if [ "$2" = "$3" ]; then printf '  PASS  %-58s (%s)\n' "$1" "$2"; pass=$((pass+1))
  else printf '  FAIL  %-58s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}

# The pattern, written once. `symlink/` needs no word boundary — the directory is gone, so
# every occurrence of the literal path component is a mention of the retired layout.
ERA_RE='install\.sh|upgrade\.sh|symlink/'

# An IMPERATIVE to run one of the retired scripts, as opposed to naming it. Path-prefixed
# (`./install.sh`, `<clone>/upgrade.sh`), interpreter-prefixed (`bash install.sh`), or
# verb-prefixed ("run install.sh", "re-run upgrade.sh"). Deliberately narrow: the job is to
# catch a surviving instruction, not to police every sentence that contains a verb.
#
# THE `.` (source) FORM IS DELIBERATELY ABSENT. It was in the first cut and matched an
# ordinary sentence-ending period — "AND THAT IS THE WHOLE CHANGE. install.sh stamped 37
# files" — which is prose, and history, and exactly what this half must not flag. Nothing
# in this repo sources either script, so the alternative bought a false positive and no
# coverage.
RUN_RE='(\./|/)(install|upgrade)\.sh|(bash|sh|zsh|exec|source) +(install|upgrade)\.sh|(run|Run|RUN|running|re-run|Re-run) +`?(install|upgrade)\.sh'

# =========================================================================================
# THE DECLARED SET — `<path> <matching-lines> <why this file may carry them>`
#
# Add a row only after reading the mention and deciding it is HISTORY. If it is an
# instruction, or a present-tense claim about how the machinery works today, fix the
# sentence instead; that is what this table is for.
# =========================================================================================
ALLOWED='
docs/conventions.md	2	the relocation History blockquote, and the retired unstamped-machinery row, both past tense
docs/operations.md	2	the /symlink/ target test the conversion sweep STILL applies, and the eight commands that became skills
docs/pm-design.md	1	where the two step files moved FROM, past tense
plugin/README.md	2	names the retired install.sh as the thing /ai-bridge:init converts a bundle from
plugin/RETIRED	2	the plugin-migration audit: sixteen machinery paths, none of them seed content
plugin/hooks/session-banner.sh	3	live legacy-link detection, plus two past-tense incident notes
plugin/scripts/init-bundle.sh	22	the replacement itself — its header is the record of what install.sh and upgrade.sh did
plugin/scripts/refresh-seeds.sh	4	the record of upgrade.sh stage 4, which is what this script is
plugin/scripts/resolve-autonomy.sh	1	what used to stamp AUTONOMY.md, and the note that nothing stamps it now
plugin/scripts/task-owner.sh	1	an SC2295 trap install.sh HAD, cited as precedent
plugin/scripts/write-snapshot.sh	1	why AUTONOMY.md stopped living under the machinery, past tense
plugin/skills/init/SKILL.md	1	names the old install.sh as the thing a Convert run converts a bundle from
'

# scope_files — the tracked shipped surface, minus the two documented exclusions.
scope_files() { # <root>
  ( cd "$1" && git ls-files -- README.md docs plugin 2>/dev/null ) \
    | grep -vx 'docs/migrating\.md' | grep -v '^docs/releases/'
}

# inventory — `<path>\t<matching lines>` for every scoped file with at least one, sorted.
# Counts LINES, which is what `grep -c` gives and what the allowlist above declares.
inventory() { # <root>
  local root="$1" f n
  while IFS= read -r f; do
    [ -f "$root/$f" ] || continue
    n="$(grep -cE "$ERA_RE" "$root/$f" 2>/dev/null)" || n=0
    [ "${n:-0}" -gt 0 ] && printf '%s\t%s\n' "$f" "$n"
  done < <(scope_files "$root") | LC_ALL=C sort
}

# imperatives — `<path>:<line>:<text>` for every surviving instruction to run either stub.
imperatives() { # <root>
  local root="$1" f
  while IFS= read -r f; do
    [ -f "$root/$f" ] || continue
    grep -nE "$RUN_RE" "$root/$f" 2>/dev/null | sed "s|^|$f:|"
  done < <(scope_files "$root")
}

# The allowlist as `<path>\t<count>`, in the same shape and order `inventory` emits.
declared() {
  printf '%s\n' "$ALLOWED" | grep -v '^[[:space:]]*$' \
    | awk -F'\t' '{ printf "%s\t%s\n", $1, $2 }' | LC_ALL=C sort
}

# =======================================================================================
echo "== 1. every mention in scope is declared, and every declaration is still real =="
# =======================================================================================
inventory "$REPO" > "$TMP/actual"
declared              > "$TMP/declared"

ok "the allowlist declares a reason for every file it allows" \
   "$(printf '%s\n' "$ALLOWED" | grep -v '^[[:space:]]*$' | awk -F'\t' 'NF!=3 || $3=="" {n++} END{print n+0}')" 0
ok "…and every count it declares is a number" \
   "$(printf '%s\n' "$ALLOWED" | grep -v '^[[:space:]]*$' | awk -F'\t' '$2 !~ /^[0-9]+$/ {n++} END{print n+0}')" 0

undeclared="$(LC_ALL=C comm -23 "$TMP/actual" "$TMP/declared")"
stale="$(LC_ALL=C comm -13 "$TMP/actual" "$TMP/declared")"

ok "no undeclared mention in README.md, docs/ or plugin/" \
   "$([ -z "$undeclared" ] && echo none || printf '%s' "$undeclared" | tr '\n' ' ')" none
ok "no allowlist row that no longer matches the tree" \
   "$([ -z "$stale" ] && echo none || printf '%s' "$stale" | tr '\n' ' ')" none

# The two exclusions are asserted rather than assumed: if either stops being excluded, the
# counts above become a running battle with a document whose job is to name the old names.
ok "docs/migrating.md is excluded from the scope" \
   "$(scope_files "$REPO" | grep -cx 'docs/migrating\.md' | tr -d ' ')" 0
ok "…and so is docs/releases/" \
   "$(scope_files "$REPO" | grep -c '^docs/releases/' | tr -d ' ')" 0
# …and that the scope is not empty, which would make every check above vacuously true.
ok "the scope is non-empty" \
   "$([ "$(scope_files "$REPO" | wc -l | tr -d ' ')" -gt 50 ] && echo yes || echo no)" yes

# =======================================================================================
echo
echo "== 2. nothing in scope tells a reader to RUN install.sh or upgrade.sh =="
# =======================================================================================
# No allowlist here on purpose. Both scripts exit 2, so an instruction to run either is a
# defect wherever it is, and a reader who has only ever known the plugin cannot tell that
# from the sentence.
found="$(imperatives "$REPO")"
ok "no surviving instruction to run either retired script" \
   "$([ -z "$found" ] && echo none || printf '%s' "$found" | head -3 | tr '\n' ' ')" none

# =======================================================================================
echo
echo "== 3. both checks are capable of failing =="
# =======================================================================================
# A fixture copy of the tracked scope, so the mutants below cannot touch the checkout. It
# is a git repo of its own, because `scope_files` asks git what is tracked.
#
# Copied from the WORKING TREE and not from `git archive HEAD`: this harness has to agree
# with the tree a reviewer is looking at, and a fixture built from HEAD reproduces the last
# commit instead — which makes the equality check below fail on every branch that has done
# any of the sweeping, i.e. exactly the branches this file exists for.
FIX="$TMP/fixture"; mkdir -p "$FIX"
while IFS= read -r f; do
  mkdir -p "$FIX/$(dirname "$f")" && cp "$REPO/$f" "$FIX/$f"
done < <( cd "$REPO" && git ls-files -- README.md docs plugin 2>/dev/null )
( cd "$FIX" && git init -q . && git add -A && \
  git -c user.email=test@example.com -c user.name=Test -c commit.gpgsign=false commit -qm f ) >/dev/null 2>&1

ok "the fixture reproduces the real inventory" \
   "$(diff -q <(inventory "$FIX") <(inventory "$REPO") >/dev/null && echo same || echo differs)" same

# (a) a NEW mention in an already-allowed file raises its count
printf '\n<!-- a fresh mention of symlink/.claude/commands/ -->\n' >> "$FIX/docs/pm-design.md"
mutant="$(LC_ALL=C comm -23 <(inventory "$FIX") "$TMP/declared")"
ok "…a new mention in an allowed file is undeclared" \
   "$(printf '%s' "$mutant" | grep -c '^docs/pm-design\.md' | tr -d ' ')" 1

# (b) a mention in a file the allowlist has never heard of
printf '\n<!-- symlink/.claude/agents/ -->\n' >> "$FIX/docs/onboarding.md"
mutant="$(LC_ALL=C comm -23 <(inventory "$FIX") "$TMP/declared")"
ok "…a mention in an unlisted file is undeclared" \
   "$(printf '%s' "$mutant" | grep -c '^docs/onboarding\.md' | tr -d ' ')" 1

# (c) a surviving instruction to run the retired installer
printf '\nStamp the bundle: `./install.sh ~/workspace/foo/_ai-bridge-foo`\n' >> "$FIX/docs/onboarding.md"
printf '\nThen `bash upgrade.sh` to merge the seeds.\n' >> "$FIX/docs/operations.md"
mut_run="$(imperatives "$FIX")"
ok "…a planted ./install.sh instruction is caught" \
   "$(printf '%s' "$mut_run" | grep -c '^docs/onboarding\.md' | tr -d ' ')" 1
ok "…and a planted bash-upgrade.sh instruction is caught" \
   "$(printf '%s' "$mut_run" | grep -c '^docs/operations\.md' | tr -d ' ')" 1

# (d) the reverse direction: an allowlist row whose file has gone quiet
sed -i.bak -E 's/install\.sh|upgrade\.sh|symlink\//RETIRED-NAME/g' "$FIX/docs/pm-design.md" && rm -f "$FIX/docs/pm-design.md.bak"
ok "…a row whose mentions all disappeared is reported stale" \
   "$(LC_ALL=C comm -13 <(inventory "$FIX") "$TMP/declared" | grep -c '^docs/pm-design\.md' | tr -d ' ')" 1

# =======================================================================================
echo
echo "== 4. the retired /pm-loop command name is gone from the shipped surface =="
# =======================================================================================
# THE SAME REPLATFORM RETIRED A SECOND NAME, and it rots the same way. `/pm-loop` became
# `/ai-bridge:dispatch` in ai-bridge-v2/task-005, and the sweep reached the command file
# and not the strings around it: the first 1.0.0 session on a real bundle printed
# "18 items need you — see the board above, or run /pm-loop" out of `session-banner.sh`,
# a command the installed plugin does not have. `grep` found ~60 more across `plugin/`.
#
# WHY IT NEEDS NO ALLOWLIST, WHICH IS THE DIFFERENCE FROM PROPERTY 1. `install.sh` is a
# refusal stub that still exists, so naming it can be legitimate history; `/pm-loop` is a
# command the runtime cannot resolve at all, so every mention inside the shipped surface
# reads as an instruction whatever the sentence around it intends. The two documents where
# naming it IS the job — `docs/migrating.md`, the conversion guide, and `docs/releases/`,
# the frozen record of what shipped — are already out of `scope_files`, and property 1
# asserts that exclusion above. So the budget here is zero and stays zero.
#
# THE PLUGIN HALF IS ASSERTED IN THE CRITERION'S OWN FORM — `grep -r 'pm-loop' plugin/`,
# on the tree rather than through `git ls-files` — because that is the command the task
# was written against and an untracked file under `plugin/` ships just the same.
PM_RE='pm-loop'

# pm_hits — `<path>:<line>:<text>` for every surviving mention in the tracked scope.
pm_hits() { # <root>
  local root="$1" f
  while IFS= read -r f; do
    [ -f "$root/$f" ] || continue
    grep -nE "$PM_RE" "$root/$f" 2>/dev/null | sed "s|^|$f:|"
  done < <(scope_files "$root")
}

pm_found="$(pm_hits "$REPO")"
ok "no /pm-loop mention in README.md, docs/ or plugin/" \
   "$([ -z "$pm_found" ] && echo none || printf '%s' "$pm_found" | head -3 | tr '\n' ' ')" none
ok "…and plugin/ carries none, counted as the criterion counts it" \
   "$( ( cd "$REPO" && grep -r 'pm-loop' plugin/ 2>/dev/null | wc -l ) | tr -d ' ' )" 0

# CAPABLE OF FAILING, both halves, against the same fixture tree property 3 built. A
# document and a script, because the two halves read the tree by different routes.
printf '\nRun `/pm-loop` when the queue has work.\n' >> "$FIX/docs/sharing.md"
printf '\n# a /pm-loop tick renders it\n'            >> "$FIX/plugin/scripts/build-board.sh"
ok "…a planted mention in a doc is caught" \
   "$(pm_hits "$FIX" | grep -c '^docs/sharing\.md' | tr -d ' ')" 1
ok "…and a planted mention under plugin/ fails the criterion's own grep" \
   "$( ( cd "$FIX" && grep -r 'pm-loop' plugin/ 2>/dev/null | wc -l ) | tr -d ' ' )" 1

echo
printf '%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
