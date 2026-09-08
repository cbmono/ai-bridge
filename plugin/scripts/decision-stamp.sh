#!/usr/bin/env bash
#
# decision-stamp.sh — which GitHub LOGIN made a decision a document records.
#
#   --self               this clone's human — a decision taken in this session
#   --author <path>      the login behind the git author of <path>'s last commit
#   --promotion <path>   that, as the ready-made `promoted <ISO 8601> by <login>` line
#
# A LOGIN, never an address: `people` maps the two, and an email in a task document is a
# data-handling breach. Unattributable prints `<unknown>` and exits 1 rather than nothing,
# because a stamp that is omitted is the defect this exists to fix — and `<` cannot occur
# in a GitHub login, so the token can never be read back as one. Config comes from
# `resolve-config.sh`, the one precedence reader. Verified by tests/decision-stamp.test.sh.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
RC="$HERE/resolve-config.sh"
UNKNOWN="<unknown>"

inst="."; mode=""; target=""

usage() { sed -n '3,7p' "$0" >&2; exit 2; }

while [ $# -gt 0 ]; do
  case "$1" in
    # `[ $# -ge 2 ]` before every `shift 2`: a bare trailing flag otherwise fails to
    # shift and spins the loop forever, the bug resolve-model.sh hit.
    --instance) [ $# -ge 2 ] || usage; inst="$2"; shift 2 ;;
    --self) mode="self"; shift ;;
    --author|--promotion) [ $# -ge 2 ] || usage; mode="${1#--}"; target="$2"; shift 2 ;;
    -h|--help) sed -n '3,12p' "$0"; exit 0 ;;
    *) usage ;;
  esac
done

[ -n "$mode" ] || usage
[ -x "$RC" ] || { echo "decision-stamp: no executable resolve-config.sh beside me" >&2; exit 2; }

cfg() { "$RC" --instance "$inst" "$@" 2>/dev/null; }
lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

# The same GitHub-username rule task-owner.sh applies, for the same fail-closed reason: a
# value we cannot read is not a value we may stamp into a document.
valid_user() {
  [ ${#1} -ge 1 ] && [ ${#1} -le 39 ] || return 1
  printf '%s' "$1" | grep -qE '^[A-Za-z0-9]+(-[A-Za-z0-9]+)*$'
}

self_login() {
  local u; u="$(cfg ownerGithubUser)"
  [ -n "$u" ] && valid_user "$u" || return 1
  printf '%s' "$u"
}

# `people` is login -> commit email, so the REVERSE lookup is the only route by which a
# commit authored on another clone resolves to a login instead of to an address.
login_for_email() {
  [ -n "$1" ] || return 0
  cfg --dump | awk -F'\t' -v e="$(lower "$1")" \
    '$2 == "people" && tolower($4) == e { print $3; exit }'
}

if [ "$mode" = "self" ]; then
  if login="$(self_login)"; then printf '%s\n' "$login"; exit 0; fi
  printf '%s\n' "$UNKNOWN"; exit 1
fi

[ -e "$target" ] || { echo "decision-stamp: no such path: $target" >&2; exit 2; }
tdir="$(cd "$(dirname "$target")" && pwd)" || exit 2
tfile="$(basename "$target")"
git -C "$tdir" rev-parse --git-dir >/dev/null 2>&1 || {
  echo "decision-stamp: $target is not inside a git working tree" >&2; exit 2; }

# `git log -1` on the file, exactly as the criterion names it. At the tick that FOLLOWS a
# promotion this is the promoting commit, whoever made it — which is what attributes a
# hand-promotion as readily as one the loop made.
row="$(cd "$tdir" && TZ=UTC git log -1 \
        --format='%ad%x09%an%x09%ae' --date=format-local:%Y-%m-%dT%H:%M:%SZ \
        -- "./$tfile" 2>/dev/null)"
when="${row%%	*}"
rest="${row#*	}"
who="${rest%%	*}"
mail="${rest##*	}"
[ -n "$row" ] || { when=""; who=""; mail=""; }

login="$(login_for_email "$mail")"
# Route 2: a plain `git commit` whose user.name IS the login. Only honoured when `people`
# knows the name, or any string in a git config would become an attribution.
if [ -z "$login" ] && valid_user "$who" && [ -n "$(cfg people "$who")" ]; then
  login="$who"
fi
# Route 3: this clone's own address, for a human in no `people` map.
if [ -z "$login" ] && [ -n "$mail" ] && [ "$(lower "$mail")" = "$(lower "$(cfg authorEmail)")" ]; then
  login="$(self_login)" || login=""
fi

rc=0
[ -n "$login" ] || { login="$UNKNOWN"; rc=1; }

case "$mode" in
  author)    printf '%s\n' "$login" ;;
  promotion) printf 'promoted %s by %s\n' "${when:-$UNKNOWN}" "$login" ;;
esac
exit "$rc"
