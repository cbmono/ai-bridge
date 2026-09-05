#!/usr/bin/env bash
#
# resolve-config.sh — the ONE implementation of the two-file config precedence.
#
#   Usage: resolve-config.sh [--instance DIR] <key> [<entry>]
#          resolve-config.sh [--instance DIR] --source <key> [<entry>]
#          resolve-config.sh [--instance DIR] --json <key> [<entry>]
#          resolve-config.sh [--instance DIR] --dump
#
# WHY IT EXISTS, AND WHY IT IS NOT A FOURTH READER. `instance.config.local.json` is read
# first and `instance.config.json` second, per KEY, with a dict value present in both
# merged ENTRY BY ENTRY (SCHEMA.md → "Per-machine config overrides"). That rule was
# written out twice — once inside `resolve-model.sh`, once inside `resolve-max-agents.sh`
# — as two identical inline python programs. The session banner needs a third thing those
# two cannot answer, WHICH FILE WON, and a third copy of the merge is exactly how the
# banner would come to disagree with the resolvers it is supposed to be reporting on: the
# copy that drifts is silent, and a `FROM` column that lies is worse than no column.
#
# So the merge moved here and both resolvers now delegate. They keep their own contracts
# (which key, what counts as a usable value, what a caller does with absence); this file
# owns precedence and nothing else.
#
# WHAT `--source` ANSWERS is per LEAF, not per file: with `roleTiers` merged entry by
# entry, "which file won" has a different answer for each agent in the map, and reporting
# it per file would be wrong for precisely the partial override the merge exists to
# support. `tracked` and `local` are the only two words it prints.
#
# ABSENCE IS NEVER AN ERROR AND NEVER A GUESS: a key in neither file prints nothing and
# exits 1, the same shape `resolve-model.sh` and `resolve-max-agents.sh` already had. The
# CALLER applies the fallback its own document states. An unreadable or non-object layer
# is skipped rather than fatal — a half-typed local file must not blank the tracked
# answer, which is the same direction `build-board.sh` takes for the same reason.
#
# JSON `null` IS ABSENCE, and that is a correctness rule rather than a nicety. Rendered, it
# would print the four letters `null`, and `resolve-model.sh` would hand those back AS A
# MODEL ALIAS: with `"models": {"deep": null}`, `resolve-model.sh project-manager` printed
# `null` and exited 0, so a dispatcher would ask for a model named "null" instead of
# falling back to the session model. So a key or entry resolving to null exits 1 with no
# output — byte for byte what an absent key does — and `--dump` omits null leaves entirely.
# It follows that a LOCAL null MASKS a tracked value: `"maxAgentsInFlight": null` in the
# per-machine file is how you UNSET an inherited key, which is the only reading under which
# "null is absent" holds at every layer rather than only at the last one.
#
# REQUIRES python3, as both resolvers already did. A caller that must survive its absence
# (the SessionStart banner does — a hook that prints a stack trace at every session start
# is worse than one that omits a block) tests for it first and omits the section.
#
# GENERIC TEMPLATE FILE — symlinked from the `ai-bridge` template; do not edit per
# instance. It reads no org, repo or path literal.
#
# Verified by tests/config-override.test.sh and tests/session-banner.test.sh.
set -uo pipefail

inst="."; mode="value"; key=""; entry=""; nargs=0
while [ $# -gt 0 ]; do
  case "$1" in
    # `[ $# -ge 2 ]` first: a bare trailing `--instance` leaves one argument, and
    # `shift 2` then FAILS WITHOUT SHIFTING. With no `set -e` that returns to the top of
    # the loop with the same argv and spins forever (the bug resolve-model.sh hit).
    --instance)
      [ $# -ge 2 ] || { echo "resolve-config: --instance needs a directory" >&2; exit 2; }
      inst="$2"; shift 2 ;;
    --source) mode="source"; shift ;;
    # `--json` exists so a SHELL caller can still see the JSON TYPE. Plain mode prints a
    # string bare, which is right for a banner and wrong for a validator: `"4"` and `4`
    # come out identical, and `resolve-max-agents.sh` refuses a cap that is not an
    # unquoted integer. json.dumps keeps the quotes, so the distinction survives the pipe.
    --json)   mode="json";   shift ;;
    --dump)   mode="dump";   shift ;;
    -h|--help) sed -n '3,8p' "$0"; exit 0 ;;
    -*) echo "resolve-config: unknown flag $1" >&2; exit 2 ;;
    *)
      case "$nargs" in
        0) key="$1" ;;
        1) entry="$1" ;;
        *) echo "resolve-config: unexpected argument $1" >&2; exit 2 ;;
      esac
      nargs=$((nargs+1)); shift ;;
  esac
done

if [ "$mode" = dump ]; then
  [ "$nargs" -eq 0 ] || { echo "resolve-config: --dump takes no key" >&2; exit 2; }
else
  [ "$nargs" -ge 1 ] || {
    echo "Usage: resolve-config.sh [--instance DIR] [--source|--json] <key> [<entry>]" >&2; exit 2; }
fi

python3 - "$inst" "$mode" "$key" "$entry" <<'PY'
import json, os, sys

inst, mode, key, entry = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]

# The order IS the rule: tracked first so the local layer can overwrite it. Written as
# data rather than as two open() calls so "the same two files in the same order" is one
# line to read and one line to change.
LAYERS = (("tracked", "instance.config.json"), ("local", "instance.config.local.json"))

cfg = {}   # key -> merged value
src = {}   # key -> "tracked"/"local", or {entry: "tracked"/"local"} for a merged dict

for origin, name in LAYERS:
    try:
        with open(os.path.join(inst, name)) as fh:
            layer = json.load(fh)
    except Exception:
        continue                      # missing, unreadable or malformed: skip, never fatal
    if not isinstance(layer, dict):
        continue
    for k, v in layer.items():
        # THE MERGE IS PER KEY, NOT `dict.update`. `roleTiers` is a map and the override
        # anyone actually writes is a PARTIAL one — a single agent moved to a cheaper
        # tier. A wholesale replace would silently drop every other agent's tier, so a
        # one-line local file would change seven agents' models, six of them by accident.
        if isinstance(v, dict) and isinstance(cfg.get(k), dict):
            cfg[k] = {**cfg[k], **v}
            merged = dict(src.get(k) or {})
            merged.update({ek: origin for ek in v})
            src[k] = merged
        else:
            cfg[k] = v
            src[k] = {ek: origin for ek in v} if isinstance(v, dict) else origin

def absent(v):
    """JSON null is ABSENCE, everywhere and at every layer — the one predicate, so the
    dump path and the value path cannot come to disagree about it. `render()` has no null
    branch precisely because nothing may ever render one: the four letters `null` printed
    into a caller's `$(...)` become an alias, a cap or a path that looks like a value and
    is not (see the header)."""
    return v is None

def render(v):
    """One line of plain text for a JSON value. Strings print bare — the banner is
    printing a path or an address for a human, not re-serialising the config. Never
    called with None; `absent()` filters that out first."""
    if isinstance(v, str):
        return v
    if v is True:
        return "true"
    if v is False:
        return "false"
    if isinstance(v, (int, float)):
        return json.dumps(v)
    return json.dumps(v, separators=(",", ":"))

def flat(s):
    """Tabs and newlines are the DUMP's field and record separators, so a value carrying
    one would split into columns that were never a value. Folded to spaces rather than
    escaped: every consumer here is a human-readable line, and an escape nobody unescapes
    is just a second way to print the wrong thing."""
    return " ".join(s.split())

if mode == "dump":
    # `<source> \t <key> \t <entry> \t <value>`, one leaf per line, entry empty for a
    # scalar or a list. Sorted so two runs of the banner cannot reorder themselves.
    out = []
    for k in sorted(cfg):
        v = cfg[k]
        if isinstance(v, dict):
            for ek in sorted(v):
                if absent(v[ek]):
                    continue          # a null entry is one the reader must not see at all
                where = src[k][ek] if isinstance(src.get(k), dict) else src.get(k, "")
                out.append("%s\t%s\t%s\t%s" % (where, k, ek, flat(render(v[ek]))))
        else:
            if absent(v):
                continue
            out.append("%s\t%s\t\t%s" % (src.get(k, ""), k, flat(render(v))))
    sys.stdout.write("".join(line + "\n" for line in out))
    sys.exit(0)

if key not in cfg or absent(cfg[key]):
    sys.exit(1)
val = cfg[key]
where = src.get(key, "")
if entry:
    if not isinstance(val, dict) or entry not in val or absent(val[entry]):
        sys.exit(1)
    where = where[entry] if isinstance(where, dict) else where
    val = val[entry]
elif isinstance(where, dict):
    # A whole map asked for by name has no single winner. Say so rather than pick one.
    where = "merged"

if mode == "source":
    print("%s\t%s" % (where, flat(render(val))))
elif mode == "json":
    print(json.dumps(val, separators=(",", ":")))
else:
    print(render(val))
PY
