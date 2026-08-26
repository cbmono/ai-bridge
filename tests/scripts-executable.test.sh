#!/usr/bin/env bash
#
# scripts-executable.test.sh — every symlink/scripts/*.sh must be committed executable,
# because install.sh symlinks it straight into an instance and nothing else grants +x.
#
# WHY THE INDEX, NOT THE WORKING TREE. `close-project-folder.sh` shipped in ai-bridge#30
# at mode 100644 — the only 644 among what are now 15 scripts here — and the defect was
# invisible on every developer machine because `install.sh` runs `chmod +x` on every
# script it stamps. After that stamp, `test -x` on the working-tree copy is TRUE and
# `git status` shows the file as locally modified (a mode change), while `origin/main`
# still carries 644 and a fresh clone still cannot run it. A check that asks the working
# tree "is this executable" therefore passes on every machine that has ever run
# install.sh and never once observes the actual defect. The only place the true mode
# lives is the git INDEX, read here with `git ls-files -s` — the same tool a fresh clone
# or `git archive` would report, and the only one that is not laundered by the installer.
#
# assert(): 0 is a PASS, matching the other harnesses here.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
TPL="$(cd "$HERE/.." && pwd)"

pass=0; fail=0
assert() { if [[ "$2" == 0 ]]; then printf '  PASS  %s\n' "$1"; pass=$((pass+1));
           else printf '  FAIL  %s\n' "$1"; fail=$((fail+1)); fi; }

cd "$TPL" || { echo "scripts-executable.test: cannot cd to $TPL" >&2; exit 2; }

FILES="$(git ls-files symlink/scripts/*.sh)"
assert "there is at least one script to check" "$([ -n "$FILES" ] && echo 0 || echo 1)"

COUNT=0
while IFS= read -r f; do
  [ -n "$f" ] || continue
  COUNT=$((COUNT+1))
  # `git ls-files -s <path>` prints "<mode> <sha> <stage>\t<path>" for exactly that one
  # path — the mode git actually committed, independent of the working-tree permission
  # bits install.sh may since have changed.
  MODE="$(git ls-files -s -- "$f" | awk '{print $1}')"
  assert "$f is committed 100755 (index mode is $MODE)" \
    "$([ "$MODE" = 100755 ] && echo 0 || echo 1)"
done <<EOF
$FILES
EOF
assert "…and every symlink/scripts/*.sh was actually checked (15 or more)" \
  "$([ "$COUNT" -ge 15 ] && echo 0 || echo 1)"

echo
printf 'pass=%d fail=%d\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
