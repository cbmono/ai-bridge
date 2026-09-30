#!/usr/bin/env bash
#
# permission-mode.sh — PreToolUse hook (Bash). For the one Bash call that runs
# spawn-preflight.sh, records the payload's `permission_mode` under this session's id,
# so the preflight reads the mode as of that call and not as of the last prompt.
# Writes nothing on any other call. Never a decision; exit 0 always. Every failure is
# silent, and the preflight then answers could-not-read — the honest answer.
# Reasoning: dispatch-reporting-defects/task-005. Verified by tests/spawn-preflight.test.sh.
set -u

root="${CLAUDE_PROJECT_DIR:-$PWD}"
root="$(cd "$root" 2>/dev/null && pwd -P || printf '%s' "$root")"
[ -f "$root/instance.config.json" ] || exit 0

payload="$(cat 2>/dev/null || true)"
case "$payload" in *spawn-preflight.sh*) ;; *) exit 0 ;; esac
command -v jq >/dev/null 2>&1 || exit 0

_self="${BASH_SOURCE[0]:-$0}"; case "$_self" in /*) ;; *) _self="$PWD/$_self" ;; esac
# shellcheck source=../scripts/bundle-paths.sh
. "${CLAUDE_PLUGIN_ROOT:-${_self%/hooks/*}}/scripts/bundle-paths.sh" 2>/dev/null || exit 0

# The command must name the preflight in `tool_input`, not merely anywhere in the payload.
fields="$(printf '%s' "$payload" | jq -r '
  if ((.tool_input.command // "") | test("spawn-preflight[.]sh")) | not then empty
  else (.session_id // ""), (.permission_mode // "") end' 2>/dev/null)" || exit 0
[ -n "$fields" ] || exit 0
sid="$(printf '%s\n' "$fields" | sed -n 1p)"
mode="$(printf '%s\n' "$fields" | sed -n 2p)"
# The id becomes a filename, so anything but an id's characters is refused outright.
case "$sid" in ''|*[!A-Za-z0-9_-]*) exit 0 ;; esac
case "$mode" in '') mode="-" ;; *[!A-Za-z]*) mode="?" ;; esac

dir="$root/$AB_MODE_DIR"
mkdir -p "$dir" 2>/dev/null || exit 0
# Self-ignoring, so every bundle already stamped keeps the record out of git with no
# re-stamp — an ignore line added by /ai-bridge:init reaches only bundles stamped after it.
[ -e "$dir/.gitignore" ] || printf '*\n' > "$dir/.gitignore" 2>/dev/null || true
tmp="$dir/.$sid.$$"
printf '%s %s\n' "$(date +%s)" "$mode" > "$tmp" 2>/dev/null && mv -f "$tmp" "$dir/$sid" 2>/dev/null \
  || rm -f "$tmp" 2>/dev/null
find "$dir" -type f ! -name .gitignore -mmin +1440 -delete 2>/dev/null || true
exit 0
