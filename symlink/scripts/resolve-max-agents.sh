#!/usr/bin/env bash
#
# resolve-max-agents.sh — print the concurrency cap this MACHINE should honour.
#
#   Usage: scripts/resolve-max-agents.sh [--instance DIR]
#
# WHY THIS EXISTS AS A SCRIPT AND NOT A SENTENCE — the same reason resolve-model.sh does.
# `maxAgentsInFlight` lived only as prose in pm-loop.md and project-manager.md, so the cap
# was honoured wherever somebody remembered to read the file. Worse, it was TRACKED, which
# forces one number on every clone of a shared bundle.
#
# Measured 2026-08-29: the key read 4 / 6 / 10 across three instances on ONE 11-core Mac —
# up to 20 concurrent agents against a measured ceiling near 4. The cap is per instance and
# the CPU is per machine (SCHEMA.md records that hole), so the number is a statement about
# THIS machine's capacity, not about the group's policy. That makes it a per-machine key:
# two clones disagreeing about it breaks nothing, while one tracked number is wrong on
# every machine but the author's.
#
# RESOLUTION ORDER, and absence is never an error:
#   instance.config.local.json : maxAgentsInFlight   (this machine)
#   instance.config.json       : maxAgentsInFlight   (the tracked default)
#
# WHY IT INVENTS NO DEFAULT. Absent from both, this prints nothing and exits 1, exactly as
# resolve-model.sh does for an agent with no tier — the CALLER then applies the fallback
# its own document states. A default baked in here would be a third number competing with
# the ones already written down, and a resolver that guesses is worse than one that says it
# does not know. Same for a value that is not a positive integer: refused, not rounded.
set -uo pipefail

inst="."
while [ $# -gt 0 ]; do
  case "$1" in
    # `[ $# -ge 2 ]` first: a bare trailing `--instance` leaves one argument, and
    # `shift 2` then FAILS WITHOUT SHIFTING. With no `set -e` that returns to the top of
    # the loop with the same argv and spins forever (the bug resolve-model.sh hit).
    --instance)
      [ $# -ge 2 ] || { echo "resolve-max-agents: --instance needs a directory" >&2; exit 2; }
      inst="$2"; shift 2 ;;
    -h|--help) sed -n '3,5p' "$0"; exit 0 ;;
    *) echo "resolve-max-agents: unexpected argument $1" >&2; exit 2 ;;
  esac
done

# Local override first, then the tracked file — the precedence every overridable key uses
# (SCHEMA.md, "Per-machine config overrides"). The per-key merge matches resolve-model.sh
# so a local file naming ONE key never blanks the rest of the config.
python3 - "$inst" <<'PY'
import json, sys, os
inst = sys.argv[1]
cfg = {}
for name in ("instance.config.json", "instance.config.local.json"):
    p = os.path.join(inst, name)
    try:
        with open(p) as fh:
            layer = json.load(fh)
    except Exception:
        continue
    if not isinstance(layer, dict):
        continue
    for k, v in layer.items():
        if isinstance(v, dict) and isinstance(cfg.get(k), dict):
            cfg[k] = {**cfg[k], **v}
        else:
            cfg[k] = v
cap = cfg.get("maxAgentsInFlight")
# `isinstance(True, int)` is True in Python, so booleans are excluded explicitly: a
# `"maxAgentsInFlight": true` would otherwise resolve to a cap of 1 and look deliberate.
if isinstance(cap, bool) or not isinstance(cap, int) or cap < 1:
    sys.exit(1)
print(cap)
PY
