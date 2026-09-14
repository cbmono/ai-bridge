#!/usr/bin/env bash
# covers: docs/spikes/worktree-remove-veto.sh
#
# worktree-remove-veto.test.sh — drives docs/spikes/worktree-remove-veto.sh.
#
# The veto is the safeguard on the one event that can delete an agent's work, and the
# 2026-08-04 incident (docs/pm-design.md, step 5) was a remover that GUESSED. So the
# property under test is not "it deletes the right trees" but its inverse: EVERY state
# it cannot establish — no bundle, no task document, two task documents, no frontmatter,
# an unreadable file, a `pr:` that is missing, duplicated or not a list — exits 1 and keeps
# the tree. Removal is the narrow case, and the tests below outnumber it deliberately.
#
# It also pins that the veto reads the DOCUMENT: no `gh`, no `curl`, no scan of the
# worktree root. A veto that asks the network is wrong whenever the network is, and a
# veto that scans is the incident again.
set -uo pipefail

VETO="$(cd "$(dirname "$0")/.." && pwd)/docs/spikes/worktree-remove-veto.sh"
LAB="$(mktemp -d "${TMPDIR:-/tmp}/worktree-remove-veto.XXXXXX")" || {
  echo "worktree-remove-veto.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp}." >&2; exit 2; }
[ -d "$LAB" ] || { echo "worktree-remove-veto.test: mktemp -d returned no usable directory." >&2; exit 2; }
trap 'chmod -R u+rwX "$LAB" 2>/dev/null; rm -rf "$LAB"' EXIT
pass=0; fail=0
ok() { # <name> <actual> <expected>
  if [ "$2" = "$3" ]; then printf '  PASS  %-58s (%s)\n' "$1" "$2"; pass=$((pass+1))
  else printf '  FAIL  %-58s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}
veto() { bash "$VETO" "$@" >/dev/null 2>&1; printf '%s' "$?"; }

B="$LAB/bundle"; mkdir -p "$B/projects/p/tasks" "$LAB/wt"
task() { # <file> <status> <pr-block>
  { printf -- '---\ntype: Task\nstatus: %s\n%s\n---\n\n# Context\n' "$2" "$3"; } > "$B/projects/p/tasks/$1"
}

echo "docs/spikes/worktree-remove-veto.sh"

# --- what it cannot establish, it keeps --------------------------------------
ok "no arguments at all"            "$(veto)" 1
ok "no bundle directory"            "$(veto "$LAB/wt/task-001-x")" 1
ok "bundle path does not exist"     "$(veto "$LAB/wt/task-001-x" --bundle "$LAB/nope")" 1
ok "basename carries no task id"    "$(veto "$LAB/wt/scratch" --bundle "$B")" 1
ok "no task document for the id"    "$(veto "$LAB/wt/task-001-x" --bundle "$B")" 1

task "task-002-a.md" "done" "pr: [ ]"
task "task-002-b.md" "done" "pr: [ ]"
ok "two task documents for one id"  "$(veto "$LAB/wt/task-002-a" --bundle "$B")" 1
rm "$B/projects/p/tasks/task-002-b.md"

printf '# no frontmatter\n' > "$B/projects/p/tasks/task-003-x.md"
ok "task document has no frontmatter" "$(veto "$LAB/wt/task-003-x" --bundle "$B")" 1

task "task-004-x.md" "done" "pr: [ ]"
chmod 000 "$B/projects/p/tasks/task-004-x.md"
ok "task document is unreadable"    "$(veto "$LAB/wt/task-004-x" --bundle "$B")" 1
chmod 644 "$B/projects/p/tasks/task-004-x.md"

# --- a live PR keeps the tree, in either YAML shape --------------------------
task "task-005-x.md" in-review 'pr: [ https://github.com/o/r/pull/9 ]'
ok "inline pr: with a URL"          "$(veto "$LAB/wt/task-005-x" --bundle "$B")" 1
task "task-006-x.md" "done" 'pr:
  - https://github.com/o/r/pull/9'
ok "block-list pr: with a URL"      "$(veto "$LAB/wt/task-006-x" --bundle "$B")" 1
task "task-007-x.md" "done" 'pr: [ https://github.com/o/r/pull/9, https://github.com/o/r/pull/10 ]'
ok "a merged-looking pair still keeps" "$(veto "$LAB/wt/task-007-x" --bundle "$B")" 1

# --- an empty pr: is not enough on its own -----------------------------------
task "task-008-x.md" in-progress "pr: [ ]"
ok "empty pr: but still in-progress" "$(veto "$LAB/wt/task-008-x" --bundle "$B")" 1
task "task-009-x.md" blocked "pr: [ ]"
ok "empty pr: but blocked"          "$(veto "$LAB/wt/task-009-x" --bundle "$B")" 1
task "task-011-x.md" cancelled "pr: [ ]"
ok "cancelled is NOT terminal here" "$(veto "$LAB/wt/task-011-x" --bundle "$B")" 1

# --- a pr: field that establishes nothing is not an empty one ----------------
task "task-012-x.md" "done" "target_repo: o/r"
ok "no pr: field at all"            "$(veto "$LAB/wt/task-012-x" --bundle "$B")" 1
task "task-013-x.md" "done" 'pr: [ ]
pr: [ ]'
ok "duplicate pr: fields"           "$(veto "$LAB/wt/task-013-x" --bundle "$B")" 1
task "task-014-x.md" "done" "pr: [ pending ]"
ok "placeholder pr: with no URL"    "$(veto "$LAB/wt/task-014-x" --bundle "$B")" 1
task "task-015-x.md" "done" 'pr:
  - TBD'
ok "block-list pr: with a non-URL"  "$(veto "$LAB/wt/task-015-x" --bundle "$B")" 1

# --- the one state that permits removal --------------------------------------
task "task-010-x.md" "done" "pr: [ ]"
ok "done, empty pr: -> remove"      "$(veto "$LAB/wt/task-010-x" --bundle "$B")" 0
task "task-016-x.md" "done" 'pr:'
ok "done, empty block pr: -> remove" "$(veto "$LAB/wt/task-016-x" --bundle "$B")" 0
ok "…and CLAUDE_PROJECT_DIR is the same route" \
  "$(CLAUDE_PROJECT_DIR="$B" bash "$VETO" "$LAB/wt/task-010-x" >/dev/null 2>&1; printf '%s' $?)" 0

# --- offline and non-scanning by construction --------------------------------
ok "names no network client"        "$(grep -cE '\b(gh|curl|wget|nc)\b' "$VETO" | tr -d ' ')" 0
ok "removes nothing itself"         "$(grep -cE '\brm\b|worktree remove' "$VETO" | tr -d ' ')" 0
ok "never lists the worktree root"  "$(grep -cE 'worktree list|find .*wtroot|ls .*worktreeRoot' "$VETO" | tr -d ' ')" 0
ok "…and the spike names the incident" \
  "$(grep -q '2026-08-04' "$(dirname "$VETO")/native-worktrees.md" && echo yes || echo no)" yes

echo
printf '%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
