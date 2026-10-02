#!/usr/bin/env bash
# kb-apply.sh — the human half of the reflector: it APPLIES one report. From a bundle root.
#
#   kb-apply.sh [--instance DIR] --by <login> <report>
#
# Applies exactly the `P<n> · …` lines of <report> and nothing else: one frontmatter field
# per proposal, one ledger entry per item, the derived knowledge/index.md, the report's own
# `status: done`, and ONE commit. Every proposal is checked before any is written, so a
# stale, hand-authored or missing item refuses the whole report.
# Exit: 0 applied · 1 refused (reported) · 2 usage. Grammar: SCHEMA.md "The reflection report".
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/bundle-paths.sh" || exit 2

KINDS="status edit merge rename supersede"
ROLES="project-manager software-engineer devops-engineer qa-reviewer cataloguer human"
ORIGPWD="$PWD"; INST="$PWD"; BY=""; REPORT=""
die() { echo "kb-apply: $2" >&2; exit "$1"; }
need2() { [ "$1" -ge 2 ] || die 2 "$2 needs a value"; }
while [ $# -gt 0 ]; do
  case "$1" in
    --instance) need2 $# "$1"; INST="$2"; shift 2 ;;
    --by)       need2 $# "$1"; BY="$2";   shift 2 ;;
    -h|--help) sed -n '2,9p' "$0" >&2; exit 2 ;;
    -*) die 2 "unknown argument '$1'" ;;
    *) [ -z "$REPORT" ] || die 2 "one report at a time"; REPORT="$1"; shift ;;
  esac
done
[ -n "$REPORT" ] || die 2 "usage: kb-apply.sh [--instance DIR] --by <login> <report>"
[[ "$BY" =~ ^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?$ ]] || die 2 "--by wants the GitHub login of the human applying it"
# Checked here and not left to ledger.sh: there it fails after the first field is written.
case " $ROLES " in *" $BY "*) die 2 "--by '$BY' is a role, not the human who applied it" ;; esac
rd="$(cd "$ORIGPWD" && cd "$(dirname "$REPORT")" 2>/dev/null && pwd)" || die 1 "no such report: $REPORT"
REPORT="$rd/$(basename "$REPORT")"
INST="$(cd "$INST" 2>/dev/null && pwd)" || die 2 "no such instance directory"
cd "$INST" || exit 2
[ -d knowledge ] || die 2 "run from a bundle root (no knowledge/ here)"
[ -f "$REPORT" ] || die 1 "no such report: $REPORT"
REPORT="${REPORT#"$INST"/}"
case "$REPORT" in projects/*/tasks/*.md) ;; *) die 1 "$REPORT is not a task document under projects/*/tasks/" ;; esac

fm() { sed -n '2,/^---$/p' "$1"; }
fmfield() { fm "$1" | sed -n "s/^$2:[[:space:]]*\([^[:space:]].*\)/\1/p" | head -n1; }
fingerprint() { cksum <"$1" | awk '{print $1 "-" $2}'; }
split7() { # <line> -> G1..G6 and G7, which keeps any ` · ` the reason carries
  local s="$1" i
  for i in 1 2 3 4 5 6; do
    printf -v "G$i" '%s' "${s%%" · "*}"; s="${s#*" · "}"
  done
  G7="$s"
}
# One field write, verified: every other line of the file must come through byte-identical.
set_field() { # <file> <key> <value>
  local f="$1" k="$2" v="$3" t
  t="$(mktemp "$f.XXXXXX")" || return 1
  awk -v k="$k" -v v="$v" '
    NR==1 && $0=="---" { print; fm=1; next }
    fm && $0=="---" { if (!done) print k ": " v; fm=0; done=1; print; next }
    fm && index($0, k ":")==1 { print k ": " v; done=1; next }
    { print }' "$f" >"$t" || { rm -f "$t"; return 1; }
  if ! diff <(grep -v "^$k:" "$f") <(grep -v "^$k:" "$t") >/dev/null; then rm -f "$t"; return 1; fi
  mv "$t" "$f"
}

[ "$(fmfield "$REPORT" type)" = Task ] || die 1 "$REPORT carries no 'type: Task'"
st="$(fmfield "$REPORT" status)"
[ "$st" = draft ] || die 1 "$REPORT is '$st', not 'draft' — a report is applied once"

N=0; FILES=(); KINDS_OF=(); WITHS=(); WHYS=(); KEYS=(); VALS=()
while IFS= read -r line; do
  [ -n "$line" ] || continue
  split7 "$line"
  case " $KINDS " in *" $G2 "*) ;; *) die 1 "$G1: kind '$G2' is not one of: $KINDS" ;; esac
  case "$G3" in ""|*[!A-Za-z0-9._-]*) die 1 "$G1: '$G3' is not a slug" ;; esac
  MATCH=( knowledge/*/"$G3".md )
  { [ -f "${MATCH[0]}" ] && [ "${#MATCH[@]}" -eq 1 ]; } || die 1 "$G1: $G3 names no single item under knowledge/*/"
  [ "$(fmfield "${MATCH[0]}" provenance)" = machine ] \
    || die 1 "$G1: $G3 is not 'provenance: machine' — the machinery never rewrites what a person wrote"
  [ "$(fingerprint "${MATCH[0]}")" = "$G6" ] \
    || die 1 "$G1: $G3 has changed since the report was written — re-run kb-propose.sh"
  [[ "$G4" =~ ^[a-z][a-z0-9_]*=[^[:space:]] ]] || die 1 "$G1: '$G4' is not field=value"
  case "$G4$G5$G7" in *'"'*|*\\*) die 1 "$G1: a field carries a quote or a backslash" ;; esac
  case "$G2" in merge|rename|supersede)
    [ "$G5" != - ] || die 1 "$G1: a $G2 must name the other item(s), so this one leads to them" ;;
  esac
  FILES+=("${MATCH[0]}"); KINDS_OF+=("$G2"); WITHS+=("$G5"); WHYS+=("$G7")
  KEYS+=("${G4%%=*}"); VALS+=("${G4#*=}"); N=$((N + 1))
done <<EOF
$(grep '^P[0-9][0-9]* · ' "$REPORT")
EOF
[ "$N" -gt 0 ] || die 1 "$REPORT names no proposals"

PATHS=(); i=0
while [ "$i" -lt "$N" ]; do
  set_field "${FILES[$i]}" "${KEYS[$i]}" "${VALS[$i]}" \
    || die 1 "could not write ${KEYS[$i]} to ${FILES[$i]} — part of the report is applied and NOTHING is committed"
  args=(append "${FILES[$i]}" --kind "${KINDS_OF[$i]}" --by "$BY" --why "${WHYS[$i]}")
  [ "${WITHS[$i]}" = - ] || args+=(--with "${WITHS[$i]}")
  bash "$HERE/ledger.sh" "${args[@]}" >/dev/null \
    || die 1 "could not append the ledger entry for ${FILES[$i]} — NOTHING is committed"
  PATHS+=("${FILES[$i]}"); i=$((i + 1))
done

set_field "$REPORT" status done || die 1 "applied $N proposal(s) but could not close $REPORT — NOTHING is committed"
PATHS+=("$REPORT")
[ ! -f knowledge/.ledger-floor ] || PATHS+=(knowledge/.ledger-floor)

# commit-as.sh regenerates and stages the derived knowledge/index.md for any knowledge/ path.
bash "$HERE/commit-as.sh" human "knowledge: apply $N proposal(s) from $(basename "$REPORT" .md)" \
  --stage -- "${PATHS[@]}" || die 1 "the changes are written but the commit failed — commit them yourself"

printf 'KB APPLIED: %s proposal(s) from %s, in one commit.\n' "$N" "$REPORT"
exit 0
