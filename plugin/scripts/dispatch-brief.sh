#!/usr/bin/env bash
# dispatch-brief.sh — the two fixed grounding/effort sections the PM pastes into a
# dispatch brief verbatim: `## Grounding (<repo>)`, the target repo's Service-doc entry
# points capped at 15 lines (or one line telling the agent to draft the missing doc), and
# `## Effort`, the files/LOC/turns budget derived from the task and the instance config.
# Usage: dispatch-brief.sh <task-doc> [--instance <bundle>]. Exit: 0 printed, 2 cannot
# answer (no task doc, unreadable frontmatter). Never fails a dispatch — an absent config
# key falls back to the documented default. Reasoning and the band measurement:
# ai-bridge-next/task-017.
set -uo pipefail

GROUNDING_MAX_LINES=15
# THE ONE COPY OF EACH HEADING. project-manager.md quotes both and
# tests/dispatch-brief.test.sh pins them against this file, so a rename cannot land in one
# place only.
GROUNDING_HEADING='## Grounding'
EFFORT_HEADING='## Effort'

usage() { sed -n '2,9p' "$0" >&2; exit 2; }

fm_block() { # <file> — the frontmatter, or exit 3/4 for a shape we will not read
  awk '
    NR==1 && $0!="---" { bad=3; exit }
    /^---$/ { n++; if (n==2) { closed=1; exit } ; next }
    n==1 { print }
    END { if (bad) exit bad; if (!closed) exit 4 }
  ' "$1"
}

field() { # <key> <frontmatter> — only the FIRST occurrence counts
  printf '%s\n' "$2" | awk -v key="$1" '
    !got && index($0, key ":") == 1 {
      v = $0; sub(/^[^:]*:[[:space:]]*/, "", v); sub(/[[:space:]]+$/, "", v)
      print v; got = 1
    }'
}

count_entries() { # <`[ "a", "b" ]` value> — always a number, so an absent field bands as 0
  printf '%s\n' "$1" | awk '
    { n = split($0, a, "\""); c = (n > 1) ? int(n / 2) : 0 }
    END { print c + 0 }'
}

cfg() { # <key> <default>
  local v=""
  [ -n "$INSTANCE" ] && [ -x "$(command -v python3 || true)" ] &&
    v="$(bash "$BIN/resolve-config.sh" --instance "$INSTANCE" "$1" 2>/dev/null)"
  printf '%s' "${v:-$2}"
}

TASK=""; INSTANCE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --instance) [ $# -ge 2 ] || usage; INSTANCE="$2"; shift 2 ;;
    -h|--help) usage ;;
    -*) echo "dispatch-brief: unexpected option '$1'" >&2; usage ;;
    *) [ -z "$TASK" ] || { echo "dispatch-brief: one task document, not two" >&2; usage; }
       TASK="$1"; shift ;;
  esac
done
[ -n "$TASK" ] || usage
[ -f "$TASK" ] || { echo "dispatch-brief: no such task document: $TASK" >&2; exit 2; }
BIN="$(cd "$(dirname "$0")" && pwd)"

# The bundle is the nearest ancestor of the task document holding instance.config.json —
# the same anchor `/ai-bridge:init` writes, so nothing has to be passed in.
if [ -z "$INSTANCE" ]; then
  d="$(cd "$(dirname "$TASK")" && pwd)"
  while [ "$d" != "/" ]; do
    [ -f "$d/instance.config.json" ] && { INSTANCE="$d"; break; }
    d="$(dirname "$d")"
  done
fi

FM=""; fm_rc=0
FM="$(fm_block "$TASK")" || fm_rc=$?
[ "$fm_rc" -eq 0 ] || {
  echo "dispatch-brief: $TASK has no readable YAML frontmatter — refusing rather than" >&2
  echo "                printing a brief whose target repo is a guess." >&2
  exit 2
}

REPO="$(field target_repo "$FM")"
CRITERIA="$(count_entries "$(field acceptance_criteria "$FM")")"
SERVICE=""
[ -n "$REPO" ] && [ -n "$INSTANCE" ] && SERVICE="$INSTANCE/knowledge/services/${REPO##*/}.md"
[ -n "$REPO" ] || REPO="(no target_repo on the task)"

printf '%s (%s)\n\n' "$GROUNDING_HEADING" "$REPO"

if [ -n "$SERVICE" ] && [ -f "$SERVICE" ]; then
  {
    printf 'Service doc: %s — read it before you read code.\n' "$SERVICE"
    # An explicit `# Entry points` section wins; absent one, the doc's identity plus its
    # section list is what a cold agent needs to know where to start.
    entry="$(awk '/^#+ *Entry points/{f=1;next} f&&/^#+ /{exit} f' "$SERVICE" | sed '/^$/d')"
    if [ -n "$entry" ]; then
      printf '%s\n' "$entry"
    else
      SFM="$(fm_block "$SERVICE" 2>/dev/null)" || SFM=""
      for k in path stack runtime; do
        v="$(field "$k" "$SFM")"; [ -n "$v" ] && printf '%s: %s\n' "$k" "$v"
      done
      # `paste -d` takes a single BYTE, so the separator is joined as ASCII and widened after.
      printf 'Sections: %s\n' "$(grep '^##* ' "$SERVICE" | sed 's/^#* *//' | paste -sd '|' - | sed 's/|/ · /g')"
    fi
  } | awk -v max="$GROUNDING_MAX_LINES" '
      NR < max { print; next }
      NR == max { print "… truncated at " max " lines — open the Service doc for the rest"; exit }'
else
  # shellcheck disable=SC2016  # backticks are markdown, not a subshell
  printf 'No Service doc for %s. Draft `knowledge/services/%s.md` in the bundle alongside this task, for the `cataloguer` to review.\n' \
    "$REPO" "${REPO##*/}"
fi

# Bands measured over 47 merged cbmono/ai-bridge PRs paired with their task's criteria
# count (2026-09-06): 0-3 → 6 files/142 lines, 4-6 → 14/306, 7+ → 20/597.
if   [ "$CRITERIA" -le 3 ]; then BAND=small;    FILES=6;  TURNS=3
elif [ "$CRITERIA" -le 6 ]; then BAND=standard; FILES=14; TURNS=5
else                             BAND=large;    FILES=20; TURNS=8
fi

printf '\n%s\n\n' "$EFFORT_HEADING"
printf 'Files expected: ~%s (band %s — %s acceptance criteria). A wildly different number is a signal, not a rule.\n' \
  "$FILES" "$BAND" "$CRITERIA"
printf 'LOC ceiling: %s (maxPrLoc), %s files (maxPrFiles) — past either, propose a split in the PR body.\n' \
  "$(cfg maxPrLoc 500)" "$(cfg maxPrFiles 100)"
printf 'Turns: be making your first edit by turn ~%s. Still only reading past ~%s ⇒ say so in your report.\n' \
  "$TURNS" "$((TURNS * 2))"
