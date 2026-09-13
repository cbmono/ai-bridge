#!/usr/bin/env bash
#
# bundle-paths.sh — the one place a bundle's layout is spelled.
#
#   . "$(dirname "$0")/bundle-paths.sh"   sourced: exports AB_*, each RELATIVE to a
#                                         bundle root, so a caller composes "$root/$AB_X"
#   bundle-paths.sh                       prints KEY=value, one per line
#   bundle-paths.sh AB_SCHEMA             prints one value
#
# Exit: 0 ok, 1 no such key. Reasoning: ai-bridge-v3/task-031.

AB_SCHEMA="SCHEMA.md"
AB_CONVENTIONS="CONVENTIONS.md"
AB_SNAPSHOT="SNAPSHOT.json"
AB_AWAITING="AWAITING.md"
AB_LEDGER="log.md"
AB_INDEX="index.md"
AB_ROSTER="agents/index.md"
# A FILE, not a directory, despite the name — tick-delta.sh writes one fingerprint line
# to it. The key is named in ai-bridge-v3/task-031's criteria, so it is spelled as filed.
AB_STATE_DIR=".tick-state"
AB_BOARD_DIR=".board-live"
AB_BOARD_OTHERS=".board-others.json"
AB_LOCK=".tick-lock"
AB_LOCK_CLAIM=".tick-lock.claim"

export AB_SCHEMA AB_CONVENTIONS AB_SNAPSHOT AB_AWAITING AB_LEDGER AB_INDEX AB_ROSTER
export AB_STATE_DIR AB_BOARD_DIR AB_BOARD_OTHERS AB_LOCK AB_LOCK_CLAIM

AB_KEYS="AB_SCHEMA AB_CONVENTIONS AB_SNAPSHOT AB_AWAITING AB_LEDGER AB_INDEX AB_ROSTER \
AB_STATE_DIR AB_BOARD_DIR AB_BOARD_OTHERS AB_LOCK AB_LOCK_CLAIM"
export AB_KEYS

# Sourced ⇒ stop here. Executed ⇒ answer, so a harness, a doc or a non-bash reader gets
# the same answer as a script does.
(return 0 2>/dev/null) && return 0

if [ "$#" -eq 0 ]; then
  for k in $AB_KEYS; do printf '%s=%s\n' "$k" "${!k}"; done
  exit 0
fi

for k in $AB_KEYS; do
  [ "$k" = "$1" ] || continue
  printf '%s\n' "${!k}"
  exit 0
done

echo "bundle-paths: no such key: $1" >&2
echo "              keys: $AB_KEYS" >&2
exit 1
