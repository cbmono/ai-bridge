#!/usr/bin/env bash
#
# build-awaiting.sh — render AWAITING.md. The SCRIPT owns the page's structure; the model
# owns only each row's trailing sentence.
#
#   Usage: build-awaiting.sh [--instance DIR] [--out FILE]
#                            [--trailer <task-path>=<sentence>]...
#                            [--merge   <task-path>=<pr markdown link>]...
#
# Exit: 0 rendered (or no AWAITING.md, which is the off switch) · 2 usage · 3 a path it
# could not read. Why the structure is not prose: docs/pm-design.md#step-8.
#
# GENERIC PLUGIN FILE — no org, repo or path literals.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
usage() { echo "Usage: $(basename "$0") [--instance DIR] [--out FILE] [--trailer PATH=TEXT]... [--merge PATH=LINK]..." >&2; exit 2; }
fail3() { echo "build-awaiting: $1" >&2; exit 3; }

inst="$PWD"; out=""
trailer_paths=(); trailer_texts=(); merge_paths=(); merge_links=()
while [ $# -gt 0 ]; do
  case "$1" in
    --instance) [ $# -ge 2 ] || usage; inst="$2"; shift 2 ;;
    --out)      [ $# -ge 2 ] || usage; out="$2";  shift 2 ;;
    --trailer)  [ $# -ge 2 ] || usage
                case "$2" in *=*) ;; *) usage ;; esac
                trailer_paths+=("${2%%=*}"); trailer_texts+=("${2#*=}"); shift 2 ;;
    --merge)    [ $# -ge 2 ] || usage
                case "$2" in *=*) ;; *) usage ;; esac
                merge_paths+=("${2%%=*}");   merge_links+=("${2#*=}");   shift 2 ;;
    -h|--help)  usage ;;
    *) usage ;;
  esac
done
inst="$(cd "$inst" 2>/dev/null && pwd)" || fail3 "no such instance directory"
[ -n "$out" ] || out="$inst/AWAITING.md"

# ABSENCE IS THE OFF SWITCH, and it is the script's rule rather than the caller's — the
# same shape write-snapshot.sh uses for SNAPSHOT.json. Never create the file.
[ -f "$out" ] || exit 0

fmfirst() { sed -n "s/^$2:[[:space:]]*\([^[:space:]].*\)/\1/p" "$1" | head -n1; }

# Entries of a `key: [ ... ]` flow list, one per line. Delegated rather than re-implemented:
# these lists carry backticks, commas, ` --- ` and square brackets, and a second parser is a
# second place for them to be cut in half. fold-answers.sh owns the one that round-trips.
entries() { # <file> <key>
  bash "$HERE/fold-answers.sh" --list "$1" "$2" 2>/dev/null || true
}

title_of() { # <file>
  local t; t="$(fmfirst "$1" title)"
  t="${t%\"}"; t="${t#\"}"
  [ -n "$t" ] && printf '%s' "$t" || basename "$1" .md
}

# THE GLYPH IS NEVER THE MODEL'S. A question asking for a tool, an install, a credential or
# an access grant is a `grant`; everything else is an `answer`. Classified from the entry
# itself so the two asks cannot drift apart across ticks.
is_grant() { # <entry text>
  printf '%s' "$1" | grep -qiE '\b(install|grant|credential|token|access|api key|permission|enable the|tool)\b'
}

# On a shared instance the queue narrows to what THIS clone's human can decide. Exit 0 is
# the only clearance, exactly as the dispatch gate reads it; a missing script is a
# single-human instance and clears.
mine() { # <task-path>
  [ -f "$HERE/task-owner.sh" ] || return 0
  # From the instance root: task-owner.sh refuses anywhere else (exit 2), and a refusal
  # caused by the caller's cwd would silently empty the queue.
  ( cd "$inst" && bash "$HERE/task-owner.sh" "$1" ) >/dev/null 2>&1
}

lookup() { # <path> <"trailer"|"merge">  -> prints the value, or nothing
  local p="$1" kind="$2" i n
  if [ "$kind" = trailer ]; then
    n=${#trailer_paths[@]}
    for ((i = 0; i < n; i++)); do
      [ "${trailer_paths[$i]}" = "$p" ] && { printf '%s' "${trailer_texts[$i]}"; return; }
    done
  else
    n=${#merge_paths[@]}
    for ((i = 0; i < n; i++)); do
      [ "${merge_paths[$i]}" = "$p" ] && { printf '%s' "${merge_links[$i]}"; return; }
    done
  fi
}

# A row is `* <glyph> **<verb>** — [<title>](<link>) · <trailer>` and nothing else. One
# writer for every row, so a new verb cannot arrive with a new marker: session-banner.sh
# greps the `* ` literally.
row() { printf '* %s **%s** — [%s](%s) · %s\n' "$1" "$2" "$3" "$4" "$5"; }

rows=""
add() { rows="$rows$(row "$@")
"; }

# The default trailers, assigned rather than inlined: a backtick or an apostrophe inside a
# `${x:-…}` default is re-parsed by the shell and the script will not even load.
DEF_APPROVE='refined & clean, promote `draft → ready`'
DEF_UNBLOCK='blocked — see the task’s `# Notes`'
DEF_CLOSE='all tasks terminal → `/close-project '

for pm in "$inst"/projects/*/project.md; do
  [ -f "$pm" ] || continue
  [ -r "$pm" ] || fail3 "cannot read $pm"
  [ "$(fmfirst "$pm" status)" = done ] && continue
  slug="$(basename "$(dirname "$pm")")"
  ntask=0; nterm=0

  for f in "$(dirname "$pm")"/tasks/*.md; do
    [ -f "$f" ] || continue
    [ -r "$f" ] || fail3 "cannot read $f"
    rel="${f#"$inst"}"
    st="$(fmfirst "$f" status)"; st="${st%% *}"
    ntask=$((ntask + 1))
    case "$st" in done|cancelled) nterm=$((nterm + 1)); continue ;; esac
    mine "$f" || continue
    t="$(title_of "$f")"
    trail="$(lookup "$f" trailer)"; [ -n "$trail" ] || trail="$(lookup "$rel" trailer)"

    # UNANSWERED questions only: an entry carrying ` --- ` is answered and belongs to
    # step 2's fold, not to the human's queue.
    qs=""; qn=0
    while IFS= read -r e; do
      [ -n "$e" ] || continue
      case "$e" in *' --- '*) continue ;; esac
      qn=$((qn + 1))
      is_grant "$e" && { add "🧰" grant "$t" "$rel" "${trail:-$e}"; continue; }
      qs="${qs:+$qs; }$e"
    done <<EOF
$(entries "$f" open_questions)
EOF
    [ -n "$qs" ] && add "❓" answer "$t" "$rel" "${trail:-$qs}"

    mlink="$(lookup "$f" merge)"; [ -n "$mlink" ] || mlink="$(lookup "$rel" merge)"
    [ -n "$mlink" ] && add "🔀" merge "$t" "$rel" "${trail:-$mlink}"

    case "$st" in
      draft)
        # A draft with questions is already queued above as answer/grant; only a CLEAN
        # refined draft is the human's promote.
        if [ "$qn" = 0 ] && [ -n "$(entries "$f" acceptance_criteria)" ]; then
          add "✅" approve "$t" "$rel" "${trail:-$DEF_APPROVE}"
        fi ;;
      blocked)
        add "⛔" unblock "$t" "$rel" "${trail:-$DEF_UNBLOCK}" ;;
    esac
  done

  if [ "$ntask" -gt 0 ] && [ "$ntask" = "$nterm" ]; then
    pt="$(title_of "$pm")"; ptrail="$(lookup "$pm" trailer)"
    add "🏁" close "$pt" "${pm#"$inst"}" "${ptrail:-$DEF_CLOSE$slug\`}"
  fi
done

n="$(printf '%s' "$rows" | grep -c '^\* ' || true)"
body="$rows"
[ "$n" -gt 0 ] || body="_None._
"

tmp="$out.tmp.$$"
{
  printf '# Awaiting you\n\n'
  printf 'Derived and gitignored — **do not hand-edit**. Rewritten from `projects/*/tasks/*.md`\n'
  printf 'by each `/ai-bridge:dispatch` tick that changed something. Delete this file to turn the queue off for good.\n'
  printf 'Last refreshed: %s.\n\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '## 🔴 Awaiting you (%s)\n' "$n"
  printf '%s' "$body"
} > "$tmp" || { rm -f "$tmp"; fail3 "cannot write beside $out"; }
mv "$tmp" "$out" || { rm -f "$tmp"; fail3 "cannot replace $out"; }
echo "awaiting: $n item(s) -> $out"
