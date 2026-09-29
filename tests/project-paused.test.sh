#!/usr/bin/env bash
#
# project-paused.test.sh — the one predicate that answers "is this task's project paused?".
# Exit 1 is the only skip; exit 2 (cannot answer) must stay distinct, because the display
# callers treat it as NOT paused and must never hide work on it.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$REPO/plugin/scripts/project-paused.sh"
. "$REPO/plugin/scripts/bundle-paths.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/project-paused.XXXXXX")" || exit 2
trap 'chmod -R u+rw "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT
pass=0; fail=0
check() { # <label> <expected rc> <actual rc>
  if [ "$2" = "$3" ]; then printf '  PASS  %s\n' "$1"; pass=$((pass+1))
  else printf '  FAIL  %s (want %s, got %s)\n' "$1" "$2" "$3"; fail=$((fail+1)); fi; }

INST="$TMP/inst"
mkdir -p "$INST/$AB_DIR" "$INST/projects/on/tasks" "$INST/projects/off/tasks" "$INST/projects/none/tasks"
printf '{ "org": "o" }\n' > "$INST/instance.config.json"
printf 'stub\n' > "$INST/$AB_SCHEMA"
printf -- '---\ntype: Project\nstatus: active\n---\n' > "$INST/projects/on/project.md"
printf -- '---\ntype: Project\nstatus: "paused"  # resume after launch\n---\n' > "$INST/projects/off/project.md"
for p in on off none; do printf -- '---\ntype: Task\nstatus: ready\n---\n' > "$INST/projects/$p/tasks/t1.md"; done
rc() { ( cd "${2:-$INST}" && bash "$SCRIPT" "$1" >/dev/null 2>&1 ); echo $?; }

echo "== the three exits =="
check "active project → 0"                       0 "$(rc projects/on/tasks/t1.md)"
check "paused project → 1"                       1 "$(rc projects/off/tasks/t1.md)"
check "absolute task path resolves the same"     1 "$(rc "$INST/projects/off/tasks/t1.md")"
check "project.md itself is a valid path"        1 "$(rc projects/off/project.md)"
check "absent project.md → 2"                    2 "$(rc projects/none/tasks/t1.md)"
check "outside the instance root → 2"            2 "$(rc "$INST/projects/off/tasks/t1.md" "$TMP")"
check "no argument → 2"                          2 "$( (cd "$INST" && bash "$SCRIPT" >/dev/null 2>&1); echo $?)"
check "a path outside projects/<slug>/ → 2"      2 "$(rc instance.config.json)"

printf -- '---\ntype: Project\nstatus: paused\n' > "$INST/projects/none/project.md"
check "unterminated frontmatter → 2, not 1"      2 "$(rc projects/none/tasks/t1.md)"
printf 'status: paused\n' > "$INST/projects/none/project.md"
check "no frontmatter at all → 2"                2 "$(rc projects/none/tasks/t1.md)"
printf -- '---\ntype: Project\nstatus: active\n---\n\nstatus: paused\n' > "$INST/projects/none/project.md"
check "a body 'status: paused' is not frontmatter" 0 "$(rc projects/none/tasks/t1.md)"

if [ "$(id -u)" != 0 ]; then
  printf -- '---\nstatus: paused\n---\n' > "$INST/projects/none/project.md"; chmod 000 "$INST/projects/none/project.md"
  check "unreadable project.md → 2"              2 "$(rc projects/none/tasks/t1.md)"
  chmod 644 "$INST/projects/none/project.md"
fi

mv "$INST/$AB_SCHEMA" "$INST/$AB_SCHEMA.gone"
check "no SCHEMA.md → 2"                         2 "$(rc projects/off/tasks/t1.md)"

echo
printf 'pass=%d fail=%d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
