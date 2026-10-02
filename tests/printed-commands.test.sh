#!/usr/bin/env bash
#
# printed-commands.test.sh — every command an operator-facing notice prints is ACCEPTED by
# the script it names. A printed command nobody ever executes is a defect class this repo
# had no guard for: bundle-paths.sh told operators to run `migrate-bundle.sh --layout
# --apply`, which that script's own parser refuses.
#
# DISCOVERY IS A CONVENTION, NOT A REGEX OVER PROSE. A notice emits through
# `ab_say_run <lead> <script> [arg...]` (plugin/scripts/bundle-paths.sh), so the call sites
# ARE the inventory and the flags arrive as separate literal words. Scraping English finds
# ~50 echo lines naming a `.sh`, nearly all of them sentences ABOUT a script.
# It also reaches a SOURCED LIBRARY FUNCTION, which running scripts and reading stderr
# does not: the defective notice belongs to no script's output.
#
# ACCEPTED = the named script's own usage / unknown-flag line is absent from stderr. Exit
# codes cannot define it — `migrate-bundle.sh --apply` from a non-bundle directory and
# `migrate-bundle.sh --layout --apply` BOTH exit 2, because the bundle guard sits after
# the parser.
#
# PARSING NEVER RUNS THE DESTRUCTIVE HALF, and that same guard order is why: every probe
# runs from a throwaway directory that is NOT a bundle, under a temp HOME and
# CLAUDE_CONFIG_DIR, so the parser is reached and the guard stops the script before it
# writes. Section 3 proves it rather than asserting it. `--help` is never passed: it exits
# before the later arguments are read, so it would pass anything.
#
# OUT OF SCOPE, explicitly: a first word that is not a `.sh` — `git`, `mkdir`, and the
# derived `/${PLUGIN_NAME}:init` slash target at plugin/scripts/ai-bridge.sh:1230.
#
# Exit codes: 0 clean, 1 an assertion failed, 2 the tree is not readable.
# Reasoning: seed-gaps-and-worktree-cleanup/task-003.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPTS="$REPO/plugin/scripts"
[ -d "$SCRIPTS" ] || { echo "printed-commands.test: no $SCRIPTS" >&2; exit 2; }

# The checked-in inventory. It is the criterion-5 absence detector AND what makes
# `tests/run.sh --changed` select this file: run.sh matches literal path strings, never a
# bare basename, so every script probed is spelled in full here.
EXPECTED="plugin/scripts/bundle-paths.sh|migrate-bundle.sh --apply
plugin/scripts/migrate-bundle.sh|kb-sync.sh commit
plugin/scripts/migrate-bundle.sh|validate-bundle.sh"
# plugin/scripts/kb-sync.sh and plugin/scripts/validate-bundle.sh are probed as the targets
# above; named here so a move of either selects this harness too.

TMP="$(mktemp -d "${TMPDIR:-/tmp}/printedcmd.XXXXXX")" || {
  echo "printed-commands.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp} — create that directory first." >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT
OUTSIDE="$TMP/outside"; HOME_T="$TMP/home"; CFG_T="$TMP/cfg"; BUNDLE="$TMP/bundle"; CAP="$TMP/cap"
mkdir -p "$OUTSIDE" "$HOME_T" "$CFG_T" "$BUNDLE/.ai-bridge" "$CAP"
: > "$BUNDLE/instance.config.json"; : > "$BUNDLE/SCHEMA.md"   # a fake un-migrated bundle

pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then printf '  PASS  %-58s (%s)\n' "$1" "$2"; pass=$((pass+1))
       else printf '  FAIL  %-58s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi; }

snap() { # <dir> — one checksum over a content manifest: equal means byte-identical
  ( cd "$1" 2>/dev/null || return 0
    find . | LC_ALL=C sort | while IFS= read -r p; do
      if [ -f "$p" ]; then printf '%s %s\n' "$p" "$(cksum <"$p")"; else printf '%s/\n' "$p"; fi
    done ) | cksum
}

echo
echo "== 1. the inventory the convention yields =="
found=""
while IFS= read -r hit; do
  [ -n "$hit" ] || continue
  f="${hit%%:*}"; rest="${hit#*:}"; n="${rest%%:*}"; code="${rest#*:}"
  cmd="$(printf '%s' "$code" | sed -E 's/^[[:space:]]*ab_say_run[[:space:]]+"[^"]*"[[:space:]]*//; s/[[:space:]]*>&2[[:space:]]*$//')"
  found="$found$f|$cmd"$'\n'
  printf '  notice  %s:%s  ->  %s\n' "$f" "$n" "$cmd"
done <<<"$(grep -rn --include='*.sh' -E '^[[:space:]]*ab_say_run[[:space:]]+"' "$REPO/plugin" 2>/dev/null | sed "s|^$REPO/||" | LC_ALL=C sort)"
ok "the inventory is the checked-in one" "$(printf '%s' "$found" | grep -v '^$' | LC_ALL=C sort | tr '\n' ';')" "$(printf '%s\n' "$EXPECTED" | LC_ALL=C sort | tr '\n' ';')"

echo
echo "== 2. every printed command is accepted by the script it names =="
before_git="$(git -C "$REPO" status --porcelain 2>/dev/null)"
b_outside="$(snap "$OUTSIDE")"; b_home="$(snap "$HOME_T")"; b_cfg="$(snap "$CFG_T")"; b_bundle="$(snap "$BUNDLE")"
probed=0
while IFS='|' read -r f cmd; do
  [ -n "${cmd:-}" ] || continue
  set -- $cmd; s="$1"; shift
  case "$cmd" in
    *'<'*|*'$'*) printf '  UNCOVERED  %s -> %s (placeholder: no stated dummy value)\n' "$f" "$cmd"; continue ;;
  esac
  case "$s" in
    *.sh) ;;
    *) printf '  OUT OF SCOPE  %s -> %s (not a plugin script)\n' "$f" "$cmd"; continue ;;
  esac
  if [ ! -r "$SCRIPTS/$s" ]; then ok "$cmd names a script that exists" no yes; continue; fi
  # PYTHONDONTWRITEBYTECODE: resolve-config.sh reaches python3, which caches .pyc under
  # $HOME and would fail section 3 for a write no probed script made.
  ( cd "$OUTSIDE" && HOME="$HOME_T" CLAUDE_CONFIG_DIR="$CFG_T" PYTHONDONTWRITEBYTECODE=1 \
      bash "$SCRIPTS/$s" "$@" ) >"$CAP/out" 2>"$CAP/err"
  marker="$(grep -cE 'usage:|unknown (option|argument|flag)|no such key' "$CAP/err" 2>/dev/null)"
  ok "$cmd is accepted by $s" "${marker:-0}" 0
  [ "${marker:-0}" = 0 ] || sed 's/^/           stderr: /' "$CAP/err" | head -2
  probed=$((probed+1))
done <<<"$(printf '%s' "$found")"
ok "the harness probed something" "$([ "$probed" -gt 0 ] && echo yes || echo no)" yes

echo
echo "== 3. the probes wrote nothing anywhere =="
ok "the throwaway cwd is unchanged"      "$(snap "$OUTSIDE")" "$b_outside"
ok "the temp HOME is unchanged"          "$(snap "$HOME_T")"  "$b_home"
ok "the temp CLAUDE_CONFIG_DIR is same"  "$(snap "$CFG_T")"   "$b_cfg"
ok "the fake bundle is unchanged"        "$(snap "$BUNDLE")"  "$b_bundle"
ok "the repo checkout is unchanged"      "$(git -C "$REPO" status --porcelain 2>/dev/null)" "$before_git"

echo
printf 'pass=%d fail=%d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
