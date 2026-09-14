#!/usr/bin/env bash
#
# worktree-create-hook.test.sh — drives plugin/hooks/worktree-create.sh.
#
# The hook is now the only thing that creates a role agent's worktree, so the property
# under test is that it either places the tree the TASK names or places none at all.
# A name it cannot key to exactly one task document is a pass-through (exit 0, silent),
# and a task id it cannot resolve ABORTS creation rather than inventing a path — the
# 2026-08-04 incident (docs/pm-design.md, step 5) was a worktree mechanism that guessed.
set -uo pipefail

HOOK="$(cd "$(dirname "$0")/.." && pwd)/plugin/hooks/worktree-create.sh"
LAB="$(mktemp -d "${TMPDIR:-/tmp}/worktree-create-hook.XXXXXX")" || {
  echo "worktree-create-hook.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp}." >&2; exit 2; }
[ -d "$LAB" ] || { echo "worktree-create-hook.test: mktemp -d returned no usable directory." >&2; exit 2; }
cleanup() {
  local w
  git -C "$LAB/repos/product" worktree list --porcelain 2>/dev/null |
    awk '/^worktree /{print $2}' | tail -n +2 |
    while read -r w; do git -C "$LAB/repos/product" worktree remove -f -f "$w" 2>/dev/null; done
  chmod -R u+rwX "$LAB" 2>/dev/null; rm -rf "$LAB"
}
trap cleanup EXIT
pass=0; fail=0
ok() { # <name> <actual> <expected>
  if [ "$2" = "$3" ]; then printf '  PASS  %-56s (%s)\n' "$1" "$2"; pass=$((pass+1))
  else printf '  FAIL  %-56s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}

B="$LAB/bundle"; WT="$LAB/wt"
mkdir -p "$B/projects/p/tasks" "$WT" "$LAB/repos"
git init -q -b trunk --bare "$LAB/origin.git"
git clone -q "$LAB/origin.git" "$LAB/repos/product" 2>/dev/null
git -C "$LAB/repos/product" -c user.email=f@f -c user.name=f commit -q --allow-empty -m init
git -C "$LAB/repos/product" push -q origin trunk
git -C "$LAB/repos/product" remote set-head origin trunk
cfg() { printf '{ "reposRoot": "%s", "worktreeRoot": "%s" }\n' "$LAB/repos" "$1" > "$B/instance.config.json"; }
cfg "$WT"

task() { # <file> <body-lines>
  { printf -- '---\ntype: Task\nstatus: in-progress\n%s\n---\n\n# Context\n' "$2"; } > "$B/projects/p/tasks/$1"
}
# The hook reads ONE JSON object on stdin; `cwd` is the route when CLAUDE_PROJECT_DIR is unset.
hook() { # <name> [<cwd>] -> "<exit> <stdout>"
  local out rc
  out="$(printf '{"session_id":"s","cwd":"%s","hook_event_name":"WorktreeCreate","name":"%s"}' \
    "${2-$B}" "$1" | bash "$HOOK" 2>/dev/null)"; rc=$?
  printf '%s %s' "$rc" "$out"
}

echo "plugin/hooks/worktree-create.sh"

# --- a name that is not a task id is not this hook's business ----------------
ok "subagent name passes through"    "$(hook 'agent-a6d376a8ba2cd81fa')" "0 "
ok "an arbitrary session name"       "$(hook 'scratch')" "0 "
ok "no name key at all"              "$(printf '{"cwd":"%s"}' "$B" | bash "$HOOK" >/dev/null 2>&1; printf '%s' $?)" 0
ok "a name that merely contains one" "$(hook 'notes-task-001')" "0 "

# --- a task id it cannot resolve ABORTS, it never guesses a path -------------
ok "cwd is not an instance root"     "$(hook 'task-001' "$LAB")" "1 "
ok "no task document for the id"     "$(hook 'task-001')" "1 "
task "task-002-a.md" "target_repo: o/product"
task "task-002-b.md" "target_repo: o/product"
ok "two task documents for one id"   "$(hook 'task-002')" "1 "
rm "$B/projects/p/tasks/task-002-b.md"
printf '# no frontmatter\n' > "$B/projects/p/tasks/task-003-x.md"
ok "task document has no frontmatter" "$(hook 'task-003')" "1 "
task "task-004-x.md" "branch: task-004"
ok "no target_repo recorded"         "$(hook 'task-004')" "1 "
task "task-005-x.md" "target_repo: o/not-cloned"
ok "target_repo is not cloned"       "$(hook 'task-005')" "1 "

# --- a recorded worktree: is honoured only inside a configured root ----------
task "task-006-x.md" "target_repo: o/product
worktree: $LAB/elsewhere/task-006"
ok "worktree: outside worktreeRoot"  "$(hook 'task-006')" "1 "
task "task-007-x.md" "target_repo: o/product
worktree: relative/task-007"
ok "worktree: is relative"           "$(hook 'task-007')" "1 "
task "task-008-x.md" "target_repo: o/product
worktree: $WT/../escape/task-008"
ok "worktree: contains .."           "$(hook 'task-008')" "1 "

# --- the happy path ----------------------------------------------------------
task "task-010-x.md" "target_repo: o/product
branch: task-010-do-the-thing"
ok "places the tree the task names"  "$(hook 'task-010')" "0 $WT/task-010"
ok "…on the task's branch"           "$(git -C "$WT/task-010" rev-parse --abbrev-ref HEAD)" "task-010-do-the-thing"
ok "…from origin/<default>, not main" \
  "$(git -C "$WT/task-010" rev-parse HEAD)" "$(git -C "$LAB/repos/product" rev-parse origin/trunk)"
ok "a second call is idempotent"     "$(hook 'task-010')" "0 $WT/task-010"
ok "…and the name may carry a slug"  "$(hook 'task-010-do-the-thing')" "0 $WT/task-010"

task "task-011-x.md" "target_repo: o/product"
ok "no branch: recorded -> the id"   "$(hook 'task-011')" "0 $WT/task-011"
ok "…branch is the task id"          "$(git -C "$WT/task-011" rev-parse --abbrev-ref HEAD)" "task-011"

git -C "$LAB/repos/product" branch -q task-012-existing origin/trunk
task "task-012-x.md" "target_repo: o/product
branch: task-012-existing"
ok "an existing branch is reused"    "$(hook 'task-012')" "0 $WT/task-012"
ok "…and not recreated"              "$(git -C "$WT/task-012" rev-parse --abbrev-ref HEAD)" "task-012-existing"

task "task-013-x.md" "target_repo: o/product
worktree: $WT/task-013-explicit
branch: task-013"
ok "an in-root worktree: is honoured" "$(hook 'task-013')" "0 $WT/task-013-explicit"

# --- a pre-existing dirty tree is reused, never cleaned ----------------------
echo scratch > "$WT/task-010/uncommitted.txt"
ok "a dirty tree is reused"          "$(hook 'task-010')" "0 $WT/task-010"
ok "…and its uncommitted file lives" "$(cat "$WT/task-010/uncommitted.txt")" scratch

# --- the legacy root, and CLAUDE_PROJECT_DIR ---------------------------------
printf '{ "reposRoot": "%s" }\n' "$LAB/repos" > "$B/instance.config.json"
task "task-014-x.md" "target_repo: o/product"
ok "absent worktreeRoot -> _wt"      "$(hook 'task-014')" "0 $LAB/repos/_wt/task-014"
cfg "$WT"
ok "CLAUDE_PROJECT_DIR is the route" \
  "$(printf '{"cwd":"/nowhere","name":"task-010"}' | CLAUDE_PROJECT_DIR="$B" bash "$HOOK" 2>/dev/null)" "$WT/task-010"

# --- non-negotiables, by construction ----------------------------------------
ok "never scans a worktree root"     "$(grep -cE 'worktree list|worktree prune|find .*WT_ROOT' "$HOOK" | tr -d ' ')" 0
ok "removes nothing, ever"           "$(grep -cE '\brm\b|worktree remove|--force' "$HOOK" | tr -d ' ')" 0
ok "asks no network for the verdict" "$(grep -cE '\b(gh|curl|wget)\b' "$HOOK" | tr -d ' ')" 0
ok "registered in hooks.json"        \
  "$(grep -c 'hooks/worktree-create.sh' "$(dirname "$HOOK")/hooks.json" | tr -d ' ')" 1

echo
printf '%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
