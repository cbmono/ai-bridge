#!/usr/bin/env bash
#
# moved-template.test.sh — moving the template must be DETECTED, and repairing it must not
# leave 122 dead backups behind.
#
# WHY. On 2026-08-23 this checkout was moved with a plain `mv`. 185 symlinks dangled across
# three instances plus the ~/.claude config layer — every script, every role agent, every
# command, SCHEMA.md, settings.json — and nothing noticed. A dangling symlink is invisible
# until something executes it, which for a /pm-loop tick means mid-dispatch with agents
# already briefed. install.sh already refuses to install FROM a worktree for exactly this
# reason (installer-worktree-guard.test.sh pins that), so the hazard was known; what was
# missing was any signal that links which USED to resolve had stopped.
#
# Two halves, and the negative properties are most of the file:
#
#   session-banner.sh (SessionStart hook — the MACHINERY section of it)
#     · names the dead links, where they pointed, and the exact repair command;
#     · that section is ABSENT and exit 0 in a healthy instance; in a non-bridge project
#       that inherits the hook the whole banner is silent, which is the reason it is safe
#       to ship. (This hook was `check-machinery.sh` until the three SessionStart hooks
#       were consolidated. A healthy INSTANCE is no longer wholly silent — the banner
#       always prints an identity line and a settings block, on purpose — so the healthy
#       case asserts the absence of the WARNING rather than of all output. The rest of
#       the banner is tests/session-banner.test.sh's.);
#     · does not identify an instance by SCHEMA.md. That is the trap: SCHEMA.md is itself
#       machinery, `[ -f ]` on a dangling symlink is FALSE, and the obvious guard
#       (push-state.sh's triple) would therefore silence the hook in exactly the case it
#       exists for. Asserted directly, because it is invisible in review;
#     · an ABSENT probe path, and a REAL FILE at one, are both left alone.
#
#   install.sh (the .bak.* sweep)
#     · a dangling `.bak.*` SYMLINK whose original has just been relinked is swept;
#     · a `.bak.*` REGULAR FILE is never touched — it is a human's content the installer
#       moved aside, and that distinction is the whole safety property;
#     · a dangling `.bak.*` symlink whose original is NOT ours survives;
#     · a `.bak.*` symlink that still resolves survives;
#     · the epoch suffix must be ALL digits, not merely start with one — `.bak.<epoch>` is
#       swept, but `.bak.<epoch>.manual`, `.bak.notdigits` and `.bak.` (empty suffix) are
#       someone else's name and must survive even when the original is ours again;
#     · an uninstall sweeps nothing, so "backups were left untouched" stays true.
#
# assert(): 0 is a PASS, matching the other harnesses here.
set -uo pipefail

TPLSRC="$(cd "$(dirname "$0")/.." && pwd)"
# GUARDED, because the canonicalisation below is destructive over an empty TMP: when
# $TMPDIR names a directory that does not exist, `mktemp -d` fails, this substitution is
# EMPTY, `cd ""` SUCCEEDS WITHOUT MOVING, `pwd -P` returns this script's own cwd — the
# checkout — and the EXIT trap below deletes it. tests/harness-temp-safety.test.sh fails
# on that shape anywhere in tests/, and it is what caught this file.
TMP="$(mktemp -d "${TMPDIR:-/tmp}/moved-tpl.XXXXXX")" || {
  echo "moved-template.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp} — create that directory first." >&2; exit 2; }
# PHYSICAL path, before anything is built under it. On macOS $TMPDIR lives under /var,
# which is a symlink to /private/var, and install.sh derives its own location with
# cd+pwd — so the link it writes records the RESOLVED path. The hook then prints that
# path back, and an assertion built from the unresolved $TMPDIR would compare
# "/private/var/…" against "/var/…" and fail for a reason that has nothing to do with the
# behaviour. retire-machinery.test.sh hit the same edge from the other direction.
TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
assert() { if [[ "$2" == 0 ]]; then printf '  PASS  %s\n' "$1"; pass=$((pass+1));
           else printf '  FAIL  %s\n' "$1"; fail=$((fail+1)); fi; }
yes_if() { if "$@" >/dev/null 2>&1; then echo 0; else echo 1; fi; }
no_if()  { if "$@" >/dev/null 2>&1; then echo 1; else echo 0; fi; }
has()    { printf '%s\n' "$2" | grep -qF -- "$1" && echo 0 || echo 1; }
hasnt()  { printf '%s\n' "$2" | grep -qF -- "$1" && echo 1 || echo 0; }

HOOK_SRC="$TPLSRC/plugin/hooks/session-banner.sh"
# The one string that only the machinery section ever prints.
WARN="ai-bridge machinery is DANGLING"

echo "== the hook is wired up at all =="
assert "session-banner.sh ships"         "$(yes_if test -f "$HOOK_SRC")"
assert "…and is executable"              "$(yes_if test -x "$HOOK_SRC")"
assert "…and parses"                     "$(yes_if bash -n "$HOOK_SRC")"
# A hook nothing registers is a file. settings.json is the only thing that runs it.
SET="$TPLSRC/seed/.claude/settings.json"
assert "settings.json registers it at SessionStart" \
  "$(yes_if bash -c "awk '/\"SessionStart\"/,0' '$SET' | grep -q 'session-banner.sh'")"
# The consolidation, stated from this side too: the hook it replaced must not still be
# registered beside it. A settings.json naming both would run the machinery probe twice.
assert "…and check-machinery.sh is NOT registered any more" \
  "$(no_if grep -q 'check-machinery.sh' "$SET")"

echo "== every probe path is still real machinery =="
# The probe list is four literal paths. It fails CLOSED — a path the template stops
# shipping stops being a symlink in the instance, so a stale entry costs a missed report
# rather than a false alarm, which means nothing else would ever notice it going stale.
# This is what notices.
PROBES="$(sed -n 's/^PROBES="\(.*\)"$/\1/p' "$HOOK_SRC")"
assert "the probe list is readable from the hook"  "$([ -n "$PROBES" ] && echo 0 || echo 1)"
for rel in $PROBES; do
  assert "probe exists in the template: $rel" "$(yes_if test -f "$TPLSRC/symlink/$rel")"
done

# A copy of the template, so moving or mutilating it cannot touch the real one. Same
# git-ls-files shape as retire-machinery.test.sh (which is why this harness needs a git
# checkout and not a `git archive` export).
TPL="$TMP/here/tpl"; mkdir -p "$TPL"
( cd "$TPLSRC" && git ls-files . ) | while IFS= read -r f; do
  [ -n "$f" ] || continue
  mkdir -p "$TPL/$(dirname "$f")"; cp "$TPLSRC/$f" "$TPL/$f" 2>/dev/null || true
done
chmod +x "$TPL/plugin/scripts/init-bundle.sh" "$TPL"/plugin/scripts/*.sh "$TPL"/plugin/hooks/*.sh 2>/dev/null || true

INST="$TMP/group/_ai-bridge-group"; mkdir -p "$INST"
bash "$TPL/plugin/scripts/init-bundle.sh" "$INST" >"$TMP/stamp" 2>&1
assert "a fresh instance stamps"         "$(yes_if test -f "$INST/instance.config.json")"

echo "== healthy instance: silent, exit 0 =="
RC=0; OUT="$(CLAUDE_PROJECT_DIR="$INST" bash "$INST/.claude/hooks/session-banner.sh" 2>&1)" || RC=$?
assert "exit 0"                          "$([[ $RC -eq 0 ]] && echo 0 || echo 1)"
assert "…and raises no machinery warning" "$(hasnt "$WARN" "$OUT")"

echo "== a non-bridge project that inherits the hook: silent, exit 0 =="
# The realistic shape of the accident: someone copies .claude/ around, or the config layer
# ends up in a plain repo. It must not print, and it must not care that it is not an
# instance — including when a .claude/agents directory happens to exist.
PLAIN="$TMP/plain-repo"; mkdir -p "$PLAIN/.claude/agents"
RC=0; OUT="$(CLAUDE_PROJECT_DIR="$PLAIN" bash "$HOOK_SRC" 2>&1)" || RC=$?
assert "exit 0"                          "$([[ $RC -eq 0 ]] && echo 0 || echo 1)"
assert "…and prints NOTHING"             "$([ -z "$OUT" ] && echo 0 || echo 1)"
# The guard is ONE marker now. `.claude/agents` was its second half until the name swap
# retired that directory — the eight role agents ship in the `ai-bridge` plugin — so a
# config file with no agents directory beside it is an ORDINARY instance, and the banner
# is required to print in it. Requiring silence here would be requiring silence
# everywhere, one re-stamp from now.
BARE="$TMP/bare-repo"; mkdir -p "$BARE"; printf '{}\n' > "$BARE/instance.config.json"
OUT="$(CLAUDE_PROJECT_DIR="$BARE" bash "$HOOK_SRC" 2>&1)"
assert "config file, no .claude/agents: prints" "$([ -n "$OUT" ] && echo 0 || echo 1)"

echo "== an absent, or real, probe path is not a broken one =="
# Absent means the instance never had it. A real file is never ours to complain about.
# Both must be distinguished from a dangling link, or the hook cries wolf on every start.
rm -f "$INST/SCHEMA.md"
OUT="$(CLAUDE_PROJECT_DIR="$INST" bash "$INST/.claude/hooks/session-banner.sh" 2>&1)"
assert "an absent probe path says nothing"  "$(hasnt "$WARN" "$OUT")"
printf 'my own SCHEMA\n' > "$INST/SCHEMA.md"
OUT="$(CLAUDE_PROJECT_DIR="$INST" bash "$INST/.claude/hooks/session-banner.sh" 2>&1)"
assert "a REAL file at a probe path too"    "$(hasnt "$WARN" "$OUT")"
rm -f "$INST/SCHEMA.md"

echo "== one dead link is enough, and SCHEMA.md dangling must not silence the hook =="
# The trap this asserts: push-state.sh's instance test includes `[ -f SCHEMA.md ]`, which
# is FALSE for a dangling symlink. Reusing that triple here would have made the hook mute
# in the one situation it is for. Reproduced with a single link, not a whole move, so the
# assertion is about the guard and nothing else.
ln -s "$TPL/seed/SCHEMA.md" "$INST/SCHEMA.md"
mv "$TPL/seed/SCHEMA.md" "$TPL/seed/SCHEMA.md.hidden"
OUT="$(CLAUDE_PROJECT_DIR="$INST" bash "$INST/.claude/hooks/session-banner.sh" 2>&1)"
assert "a dangling SCHEMA.md is reported"   "$(has 'SCHEMA.md' "$OUT")"
assert "…and counted as 1 of 4"             "$(has '1 of 4' "$OUT")"
assert "…and the repair is named"           "$(has "bash $TPL/plugin/scripts/init-bundle.sh $INST" "$OUT")"
mv "$TPL/seed/SCHEMA.md.hidden" "$TPL/seed/SCHEMA.md"

echo "== the whole template moves =="
# The real incident. Everything dangles at once; the hook still resolves because it is
# invoked from the template's NEW location, which is also how it knows the path to print.
mv "$TMP/here" "$TMP/there"
TPL2="$TMP/there/tpl"
RC=0; OUT="$(CLAUDE_PROJECT_DIR="$INST" bash "$TPL2/plugin/hooks/session-banner.sh" 2>&1)" || RC=$?
assert "exit 0 even when reporting"      "$([[ $RC -eq 0 ]] && echo 0 || echo 1)"
assert "all four probes are named"       "$(has '4 of 4' "$OUT")"
assert "…the dead paths are listed"      "$(has 'scripts/commit-as.sh' "$OUT")"
assert "…the OLD location is named"      "$(has "$TPL" "$OUT")"
assert "…and the repair uses the NEW one" "$(has "bash $TPL2/plugin/scripts/init-bundle.sh $INST" "$OUT")"
# It names the repair; it must not BE the repair. A hook that silently relinked an
# instance's machinery at session start would leave a move with no trace at all.
assert "nothing was repaired"            "$(no_if test -e "$INST/SCHEMA.md")"

echo "== the repair sweeps its own dead backups =="
# Decoys planted BEFORE the repair, so the sweep meets them in the same run it creates
# its own debris.
printf 'content a human wants back\n' > "$INST/CONVENTIONS.md.bak.1700000000"  # a real FILE
ln -s "$TMP/nowhere-ever" "$INST/stranger.bak.1700000001"   # dangles, original not ours
ln -s "$INST/instance.config.json" "$INST/live.bak.1700000002"  # a backup that RESOLVES
RC=0; bash "$TPL2/plugin/scripts/init-bundle.sh" "$INST" >"$TMP/repair" 2>&1 || RC=$?
assert "the repair exits 0"              "$([[ $RC -eq 0 ]] && echo 0 || echo 1)"
assert "…and relinks the machinery"      "$(yes_if test -e "$INST/SCHEMA.md")"
assert "…moving the dead links aside"    "$(yes_if grep -q '^  moved ' "$TMP/repair")"
assert "…then sweeping those backups"    "$(yes_if grep -q '^  sweep ' "$TMP/repair")"
assert "…and saying where each pointed"  "$(yes_if grep -q 'sweep .*was -> .*here/tpl' "$TMP/repair")"
LEFT="$(find "$INST" -name '*.bak.*' -type l ! -exec test -e {} \; -print | wc -l | tr -d ' ')"
assert "exactly one dead .bak link is left (the stranger)" \
  "$([ "$LEFT" = 1 ] && echo 0 || echo 1)"
assert "a .bak REGULAR FILE survives"    "$(yes_if grep -q 'content a human wants back' "$INST/CONVENTIONS.md.bak.1700000000")"
assert "a stranger's dead .bak link survives" "$(yes_if test -L "$INST/stranger.bak.1700000001")"
assert "a .bak link that resolves survives"   "$(yes_if test -e "$INST/live.bak.1700000002")"
assert "the instance is healthy again"   "$(hasnt "$WARN" "$(CLAUDE_PROJECT_DIR="$INST" bash "$INST/.claude/hooks/session-banner.sh" 2>&1)")"

echo "== idempotent =="
bash "$TPL2/plugin/scripts/init-bundle.sh" "$INST" >"$TMP/again" 2>&1
assert "a second run sweeps nothing"     "$(no_if grep -q '^  sweep ' "$TMP/again")"
assert "…and retires nothing"            "$(no_if grep -q '^  retire ' "$TMP/again")"

echo "== a name that is not ours is not a backup =="
# `.bak.<digits>` is the shape this installer writes. Anything else is somebody's file.
ln -s "$TMP/nowhere-ever" "$INST/SCHEMA.md.backup"
ln -s "$TMP/nowhere-ever" "$INST/SCHEMA.md.bak"
ln -s "$TMP/nowhere-ever" "$INST/SCHEMA.md.bak.old"
bash "$TPL2/plugin/scripts/init-bundle.sh" "$INST" >/dev/null 2>&1
assert "'.backup' is left alone"         "$(yes_if test -L "$INST/SCHEMA.md.backup")"
assert "'.bak' with no epoch is too"     "$(yes_if test -L "$INST/SCHEMA.md.bak")"
assert "'.bak.old' likewise"             "$(yes_if test -L "$INST/SCHEMA.md.bak.old")"

echo "== the epoch suffix must be ALL digits, not merely start with one =="
# The regression this pins: the shape check alone (*.bak.[0-9]*) only requires the FIRST
# character after ".bak." to be a digit, so "…bak.1700000000.manual" passes it — a name
# this installer never writes. Each decoy below starts with a digit (so the OLD, unfixed
# check would have accepted it) but is rejected once the whole suffix must be digits-only.
# SCHEMA.md is already ours-and-resolved at this point (relinked earlier in this file), so
# if any of these were mistaken for a real backup, the sweep below would remove it.
ln -s "$TMP/nowhere-ever" "$INST/SCHEMA.md.bak.1700000004.manual"  # digit start, trailing ext
ln -s "$TMP/nowhere-ever" "$INST/SCHEMA.md.bak.notdigits"          # no leading digit at all
ln -s "$TMP/nowhere-ever" "$INST/SCHEMA.md.bak."                   # empty suffix
bash "$TPL2/plugin/scripts/init-bundle.sh" "$INST" >"$TMP/epoch-guard" 2>&1
assert "'.bak.<epoch>.manual' is left alone" "$(yes_if test -L "$INST/SCHEMA.md.bak.1700000004.manual")"
assert "'.bak.notdigits' is left alone"      "$(yes_if test -L "$INST/SCHEMA.md.bak.notdigits")"
assert "'.bak.' (empty suffix) is too"       "$(yes_if test -L "$INST/SCHEMA.md.bak.")"
assert "…none of the three was swept"        "$(no_if grep -q '^  sweep ' "$TMP/epoch-guard")"

echo "== …while a genuine all-digit .bak.<epoch> is still swept =="
# The positive control for the assertion above: prove the guard rejects the malformed
# names on their shape, not by accident sweeping nothing at all this run.
ln -s "$TMP/nowhere-ever" "$INST/SCHEMA.md.bak.1700000005"
bash "$TPL2/plugin/scripts/init-bundle.sh" "$INST" >"$TMP/real-bak" 2>&1
assert "a real .bak.<epoch> backup is swept" "$(no_if test -L "$INST/SCHEMA.md.bak.1700000005")"
assert "…and the sweep is logged"            "$(yes_if grep -q '^  sweep ' "$TMP/real-bak")"
# The three malformed decoys from the block above must still be untouched by this run too.
assert "…the manual-suffixed decoy still survives" "$(yes_if test -L "$INST/SCHEMA.md.bak.1700000004.manual")"
assert "…the notdigits decoy still survives"       "$(yes_if test -L "$INST/SCHEMA.md.bak.notdigits")"
assert "…the empty-suffix decoy still survives"    "$(yes_if test -L "$INST/SCHEMA.md.bak.")"

echo "== uninstall sweeps nothing, so its promise stays true =="
# The sweep requires the original to exist again as a link of OURS. An uninstall removes
# the link instead of recreating it, so every backup survives — which is what
# "your runtime state, real files, and *.bak.* backups were left untouched" claims.
ln -s "$TMP/nowhere-ever" "$INST/SCHEMA.md.bak.1700000003"
bash "$TPL2/plugin/scripts/init-bundle.sh" --uninstall "$INST" >"$TMP/uninst" 2>&1
assert "uninstall sweeps no backups"     "$(no_if grep -q '^  sweep ' "$TMP/uninst")"
assert "…and the dead backup is still there" "$(yes_if test -L "$INST/SCHEMA.md.bak.1700000003")"

echo
printf 'pass=%d fail=%d\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
