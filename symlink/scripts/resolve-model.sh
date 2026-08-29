#!/usr/bin/env bash
#
# resolve-model.sh — print the model alias a given agent should run on.
#
#   Usage: scripts/resolve-model.sh <agent-name> [--instance DIR]
#
# WHY THIS EXISTS AS A SCRIPT AND NOT A SENTENCE.
# `roleTiers`/`models` lived only as prose in SCHEMA.md, project-manager.md,
# advisor.md, audit.md and pm-loop.md — five files telling an agent to go and look
# something up, and NO code that read it. So the config governed exactly the dispatch
# paths whose markdown happened to mention it (the /pm-loop tick, the PM's own
# dispatches) and nothing else. Every ad-hoc `Agent` dispatch from a main session — a
# documented, legitimate mode — silently ignored it, because the Agent tool takes its
# model from its own parameter, else the agent's frontmatter, else the parent. Measured
# 2026-08-28: three separate sessions each reported, independently, that they had not
# consulted the file.
#
# A rule in prose is obeyed where somebody remembered to obey it. This makes it
# answerable by one command, so "what model should X run on" has a mechanical answer
# any caller can get without reading five documents.
#
# RESOLUTION ORDER, and absence is never an error:
#   roleTiers[<agent>]  ->  a tier name (light|standard|deep|apex)
#   models[<tier>]      ->  an alias (e.g. sonnet)
# An agent with no roleTiers entry, or a tier with no models entry, prints nothing and
# exits 1 — the caller then inherits the session model, which is the documented
# behaviour when the keys are absent. Never guess an alias.
#
# Both keys are read from `instance.config.local.json` FIRST and the tracked
# `instance.config.json` second, per entry — see the merge comment at the read below.
set -uo pipefail

agent=""; inst="."
while [ $# -gt 0 ]; do
  case "$1" in
    # `[ $# -ge 2 ]` first: a bare trailing `--instance` leaves one argument, and
    # `shift 2` then FAILS WITHOUT SHIFTING. With no `set -e` that returns to the top
    # of the loop with the same argv and spins forever — verified by running it.
    --instance)
      [ $# -ge 2 ] || { echo "resolve-model: --instance needs a directory" >&2; exit 2; }
      inst="$2"; shift 2 ;;
    -h|--help) sed -n '3,5p' "$0"; exit 0 ;;
    -*) echo "resolve-model: unknown flag $1" >&2; exit 2 ;;
    *) agent="$1"; shift ;;
  esac
done
[ -n "$agent" ] || { echo "Usage: resolve-model.sh <agent-name> [--instance DIR]" >&2; exit 2; }

# Local override first, then the tracked file — the same precedence every other
# overridable key uses (SCHEMA.md, "Per-machine config overrides"). `models` and
# `roleTiers` belong to that set because they are SPEND: which model this human pays for,
# agent by agent. Two clones disagreeing about them breaks nothing — each dispatch runs on
# its own machine, and what differs is one person's bill.
#
# THE MERGE IS PER KEY, NOT `dict.update`. `roleTiers` is a map, and the override anyone
# actually writes is a PARTIAL one — a single agent moved to a cheaper tier. A plain
# `cfg.update()` replaces the whole map with that one entry, so every other agent silently
# loses its tier and inherits the session model instead: a one-line local file would change
# seven agents' models, six of them by accident. So a dict value present in BOTH files is
# merged entry by entry (local wins per entry); anything else replaces wholesale, which is
# what a list or a scalar override means.
python3 - "$inst" "$agent" <<'PY'
import json, sys, os
inst, agent = sys.argv[1], sys.argv[2]
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
tier = (cfg.get("roleTiers") or {}).get(agent)
if not tier:
    sys.exit(1)
alias = (cfg.get("models") or {}).get(tier)
if not alias:
    sys.exit(1)
print(alias)
PY
