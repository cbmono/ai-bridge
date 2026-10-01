#!/usr/bin/env bash
# ledger.sh — the append-only record of why a knowledge/ item changed, kept in the item's own
# frontmatter as one `ledger:` line. From a bundle root.
#
#   ledger.sh [--kb DIR] append <path|slug> --kind <k> --by <login> --why <text> [--with <slug,...>]
#   ledger.sh [--kb DIR] show <path|slug>
#
# There is no verb that edits or removes an entry. Ids are `L<n>`, global and monotonic:
# max(<kb>/.ledger-floor, every id in the KB) + 1, never reused.
# Exit: 0 done · 1 refused (reported) · 2 usage. Shape and reasoning: SCHEMA.md "The ledger".
set -uo pipefail

KINDS="create edit status merge rename supersede"
ROLES="project-manager software-engineer devops-engineer qa-reviewer cataloguer human"
KB=knowledge

die() { echo "ledger: $2" >&2; exit "$1"; }

[ "${1:-}" = --kb ] && { [ -n "${2:-}" ] || die 2 "--kb needs a directory"; KB="$2"; shift 2; }
VERB="${1:-}"; ITEM="${2:-}"
case "$VERB" in append|show) ;; *) die 2 "usage: ledger.sh [--kb DIR] append|show <path|slug> …" ;; esac
[ -n "$ITEM" ] || die 2 "$VERB needs a <path|slug>"
shift 2
[ -d "$KB" ] || die 2 "no knowledge directory at $KB"

case "$ITEM" in
  */*|*.md) FILE="$ITEM" ;;
  *) MATCH=( "$KB"/*/"$ITEM".md )
     [ -f "${MATCH[0]}" ] || die 1 "no item named $ITEM under $KB/*/"
     [ "${#MATCH[@]}" -eq 1 ] || die 1 "$ITEM names ${#MATCH[@]} items — pass the path"
     FILE="${MATCH[0]}" ;;
esac
[ -f "$FILE" ] || die 1 "$FILE does not exist"

frontmatter() { awk 'NR==1 && $0!="---" {exit} NR>1 && $0=="---" {exit} NR>1' "$1"; }
entries() {
  frontmatter "$1" | awk '/^ledger:/ { s = $0
    while (match(s, /"[^"]*"/)) { print substr(s, RSTART + 1, RLENGTH - 2); s = substr(s, RSTART + RLENGTH) } }'
}

FM="$(frontmatter "$FILE")"
grep -q '^type:[[:space:]]*[A-Za-z]' <<<"$FM" || die 1 "$FILE has no typed frontmatter — not a ledgered item"
[ "$(grep -c '^ledger:' <<<"$FM")" -le 1 ] || die 1 "$FILE carries more than one ledger: line"

check_order() { # <file> — ids strictly increasing, or the ledger was edited by hand
  entries "$1" | awk -F' · ' '
    $1 !~ /^L[0-9]+$/ { print "malformed entry: " $0; bad=1; exit }
    { n = substr($1, 2) + 0; if (n <= last) { print "id " $1 " does not rise"; bad=1; exit }; last = n }
    END { exit bad }'
}
bad="$(check_order "$FILE")" || die 1 "$FILE: $bad — refusing to append to a rewritten ledger"

if [ "$VERB" = show ]; then entries "$FILE"; exit 0; fi

KIND=""; BY=""; WHY=""; WITH=""
while [ $# -gt 0 ]; do
  case "$1" in
    --kind|--by|--why|--with) [ $# -ge 2 ] || die 2 "$1 needs a value" ;;
    *) die 2 "unknown argument: $1" ;;
  esac
  case "$1" in --kind) KIND="$2" ;; --by) BY="$2" ;; --why) WHY="$2" ;; --with) WITH="$2" ;; esac
  shift 2
done

[[ " $KINDS " == *" $KIND "* && -n "$KIND" ]] || die 2 "--kind must be one of: $KINDS"
[[ "$BY" =~ ^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?$ ]] || die 1 "--by must be a GitHub login, got '$BY'"
case " $ROLES " in *" $BY "*) die 1 "--by '$BY' is a role, not the human who applied it" ;; esac
[[ "$WHY" =~ [^[:space:]] ]] || die 1 "--why is required: the reason it was approved, not the diff"
case "$WHY$WITH" in *'"'*|*\\*|*$'\n'*) die 1 'a field may not carry a double quote, a backslash or a newline' ;; esac

SELF="$(basename "$FILE" .md)"
ITEMS="$SELF"
IFS=',' read -r -a OTHERS <<<"$WITH"
for s in ${OTHERS[@]+"${OTHERS[@]}"}; do
  [[ "$s" =~ ^[A-Za-z0-9._-]+$ ]] || die 1 "--with: '$s' is not a slug"
  [ "$s" != "$SELF" ] || die 1 "--with names the item itself"
  ITEMS="$ITEMS,$s"
done
case "$KIND" in merge|rename|supersede)
  [ "$ITEMS" != "$SELF" ] || die 1 "a $KIND must name the other item(s) with --with, so this item leads to them" ;;
esac

FLOOR_FILE="$KB/.ledger-floor"
floor="$(tr -cd '0-9' 2>/dev/null <"$FLOOR_FILE")"
seen="$(grep -rh --include='*.md' '^ledger:' "$KB" 2>/dev/null | grep -o '"L[0-9]* · ' | tr -cd '0-9\n' | sort -n | tail -1 || true)"
next=$(( ${floor:-0} > ${seen:-0} ? ${floor:-0} + 1 : ${seen:-0} + 1 ))

ENTRY="L$next · $(date -u +%Y-%m-%dT%H:%M:%SZ) · $KIND · by $BY · items $ITEMS · $WHY"
LINE="ledger: ["
first=1
while IFS= read -r e; do
  [ -n "$e" ] || continue
  if [ $first = 1 ]; then LINE="$LINE \"$e\""; first=0; else LINE="$LINE, \"$e\""; fi
done < <(entries "$FILE"; printf '%s\n' "$ENTRY")
LINE="$LINE ]"

TMPF="$(mktemp "$FILE.XXXXXX")" || die 1 "cannot create a temp file beside $FILE"
trap 'rm -f "$TMPF"' EXIT
awk -v line="$LINE" '
  NR==1 { print; next }
  fm && /^ledger:/ { print line; done=1; next }
  fm && $0=="---" { if (!done) print line; fm=0; print; next }
  NR==2 { fm=1 }
  { print }' fm=1 "$FILE" >"$TMPF" || die 1 "could not write $FILE"

# Verify before it lands: every other line byte-identical, old entries an exact prefix.
diff <(grep -v '^ledger:' "$FILE") <(grep -v '^ledger:' "$TMPF") >/dev/null \
  || die 1 "refused: the write would change $FILE outside its ledger: line"
[ "$(entries "$TMPF")" = "$(entries "$FILE"; printf '%s' "$ENTRY")" ] \
  || die 1 "refused: the write would not preserve the existing entries of $FILE"

mv "$TMPF" "$FILE" || die 1 "could not replace $FILE"
printf '%s\n' "$next" >"$FLOOR_FILE" || die 1 "wrote $FILE but not $FLOOR_FILE — the next id still rises from the scan"
printf '%s\n' "$ENTRY"
