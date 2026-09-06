#!/usr/bin/env bash
#
# banner-logo.test.sh — the ship above the banner's header: three lines of DATA, coloured
# by GLYPH CLASS, and adding nothing else to the banner.
#
# The four claims, and each is here because a content grep passes without it: the three
# lines are byte-exact; a `~` is water and a block is hull or bridge in all three colour
# tiers; the opt-outs leave the lines with no SGR at all; and the header and its rule are
# the same bytes they were before the logo existed — proved against a mutant of the hook
# with the `logo` call removed, so "nothing else changed" is measured, not asserted.
#
# assert(): 0 is a PASS, matching the banner harnesses next door.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
TPL="$(cd "$HERE/.." && pwd)"
HOOK="$TPL/plugin/hooks/session-banner.sh"
DOC="$TPL/docs/operations.md"
for f in "$HOOK" "$DOC"; do
  [ -f "$f" ] || { echo "banner-logo.test: missing $f" >&2; exit 2; }
done
command -v python3 >/dev/null 2>&1 || {
  echo "banner-logo.test: python3 is required to parse the hook's JSON" >&2; exit 2; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/banner-logo.XXXXXX")" || {
  echo "banner-logo.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp} — create that directory first." >&2
  exit 2; }
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
assert() { if [ "$2" -eq 0 ]; then printf '  PASS  %s\n' "$1"; pass=$((pass+1));
           else printf '  FAIL  %s\n' "$1"; fail=$((fail+1)); fi; }
eq()    { [ "$1" = "$2" ] && echo 0 || echo 1; }
has()   { grep -qF -- "$1" <<<"$2" && echo 0 || echo 1; }

# Named once. A literal ESC is invisible in a diff and in a grep, which is why nothing in
# this repo types one.
ESC="$(printf '\033')"
no_esc()    { LC_ALL=C grep -q "$ESC" <<<"$1" && echo 1 || echo 0; }
strip_sgr() { printf '%s' "$1" | LC_ALL=C sed "s/$ESC\[[0-9;]*m//g"; }
nth()       { printf '%s\n' "$1" | sed -n "$2p"; }
head_no()   { printf '%s\n' "$1" | awk '$0 != "" { print NR; f = 1; exit } END { if (!f) print 0 }'; }

# THE THREE LINES, TYPED HERE AND NOWHERE ELSE IN THIS FILE. The hook keeps its own copy as
# data; that these two agree byte for byte is the first assertion below.
L1=' █▀█'
L2='▄███▄▄▄▄▄▄'
L3='~▀▀▀▀▀▀▀~~'

# --- the fixture instance ----------------------------------------------------------------
INST="$TMP/_ai-bridge-fixture"
mkdir -p "$INST/.claude/agents"
printf 'stub\n' > "$INST/SCHEMA.md"
printf '{ "org": "example-org" }\n' > "$INST/instance.config.json"

run() { # <hook> [args…] -> the plain-text banner
  CLAUDE_PROJECT_DIR="$INST" bash "$1" "${@:2}" 2>/dev/null
}
runenv() { # <env assignment…> -- <hook> [args…]
  local env=(); while [ "$1" != -- ]; do env+=("$1"); shift; done; shift
  env "${env[@]}" CLAUDE_PROJECT_DIR="$INST" bash "$@" 2>/dev/null
}

# =======================================================================================
echo "== 1. the three lines, verbatim, above the header =="
# =======================================================================================
OUT="$(run "$HOOK")"
n="$(head_no "$OUT")"
assert "line 1 is the bridge, byte for byte"  "$(eq "$(nth "$OUT" "$n")" "$L1")"
assert "line 2 is the hull, byte for byte"    "$(eq "$(nth "$OUT" "$((n+1))")" "$L2")"
assert "line 3 is the waterline, byte for byte" "$(eq "$(nth "$OUT" "$((n+2))")" "$L3")"
assert "…and the identity line is directly under them" \
  "$(eq "$(nth "$OUT" "$((n+3))" | cut -c1-9)" 'AI-Bridge')"
# KEPT ONCE, AS DATA. Three inline printf fragments would satisfy every assertion above and
# be three places to edit; the hook holds one array and this counts it.
for l in "$L1" "$L2" "$L3"; do
  assert "the hook carries that line exactly once" "$(eq "$(grep -cF -- "$l" "$HOOK")" 1)"
done
assert "…on one line, as an array rather than three printfs" \
  "$(eq "$(grep -cF -- "LOGO_LINES=(" "$HOOK")" 1)"
# THE DOCS SAMPLE IS A SAMPLE OF THIS OUTPUT, so it carries the same three lines.
SAMPLE="$(cat "$DOC")"
for l in "$L1" "$L2" "$L3"; do
  assert "the operations.md banner sample shows it too" "$(has "$l" "$SAMPLE")"
done

# =======================================================================================
echo "== 2. colour is by GLYPH CLASS, in all three tiers =="
# =======================================================================================
# The claim is not "the lines are coloured" — it is that `~` is water WHEREVER it appears
# and a block is hull or bridge, which line 3 is the only line that can prove: it must come
# back as water, hull, water, in three separately-reset runs.
OFF="${ESC}[0m"   # the reset the rest of the banner already uses, not a second one
tier() { # <tier name> <water> <hull> <bridge> <env…>
  local name="$1" w="$2" h="$3" b="$4"; shift 4
  local out l1 l2 l3 m
  out="$(runenv "$@" -- "$HOOK" --color always)"; m="$(head_no "$out")"
  l1="$(nth "$out" "$m")"; l2="$(nth "$out" "$((m+1))")"; l3="$(nth "$out" "$((m+2))")"
  assert "$name: line 1 is bridge $b"  "$(eq "$l1" "${ESC}[${b}m${L1}${OFF}")"
  assert "$name: line 2 is hull $h"    "$(eq "$l2" "${ESC}[${h}m${L2}${OFF}")"
  assert "$name: line 3 is water, hull, water — by glyph, not by line" \
    "$(eq "$l3" "${ESC}[${w}m~${OFF}${ESC}[${h}m▀▀▀▀▀▀▀${OFF}${ESC}[${w}m~~${OFF}")"
  assert "$name: …and stripping the SGR gives the three lines back" \
    "$(eq "$(strip_sgr "$l1")$(strip_sgr "$l2")$(strip_sgr "$l3")" "$L1$L2$L3")"
}
tier truecolor '38;2;95;168;211' '38;2;239;163;165' '38;2;245;215;110' COLORTERM=truecolor
tier 24bit     '38;2;95;168;211' '38;2;239;163;165' '38;2;245;215;110' COLORTERM=24bit
tier 256       '38;5;74' '38;5;217' '38;5;222'      COLORTERM= TERM=xterm-256color
tier 16        '94' '95' '93'                       COLORTERM= TERM=dumb

# =======================================================================================
echo "== 3. the opt-outs leave the three lines with NO SGR at all =="
# =======================================================================================
plain_logo() { # <banner> -> 0 when the three lines are present and carry no escape
  local out="$1" m; m="$(head_no "$out")"
  [ "$(nth "$out" "$m")" = "$L1" ] && [ "$(nth "$out" "$((m+1))")" = "$L2" ] \
    && [ "$(nth "$out" "$((m+2))")" = "$L3" ] \
    && [ "$(no_esc "$(nth "$out" "$m")$(nth "$out" "$((m+1))")$(nth "$out" "$((m+2))")")" = 0 ] \
    && echo 0 || echo 1
}
# ON THE JSON PATH, where the field is drawn by the client and the logo is coloured by
# default — the only channel on which "the opt-out turned it off" is a real observation.
sm() { printf '%s' "$1" | python3 -c 'import json,sys; sys.stdout.write(json.load(sys.stdin)["systemMessage"])'; }
assert "NO_COLOR=1 prints them plain on the channel that renders SGR" \
  "$(plain_logo "$(sm "$(runenv NO_COLOR=1 -- "$HOOK" --format json)")")"
assert "--color never prints them plain there too" \
  "$(plain_logo "$(sm "$(run "$HOOK" --format json --color never)")")"
assert "a pipe with no flags prints them plain"  "$(plain_logo "$OUT")"
# NON-VACUITY: the same path DOES colour them when nothing is opting out, so the assertions
# above are about the opt-out and not about a logo that is never coloured at all.
assert "…while the same json run without it colours them" \
  "$(eq "$(plain_logo "$(sm "$(run "$HOOK" --format json)")")" 1)"
# THE `/welcome` RELAY. Markdown renders there and SGR does not, so that rendering carries
# the same three lines and no escape — colour is not promised on that channel.
MD="$(run "$HOOK" --format md)"
assert "the md rendering /welcome relays shows the same three lines" "$(plain_logo "$MD")"
# AND THE EQUALITY THE TWO CHANNELS RUN ON: strip_sgr(systemMessage) is the text banner.
JSON="$(run "$HOOK" --format json --color always)"
SM="$(printf '%s' "$JSON" | python3 -c 'import json,sys; sys.stdout.write(json.load(sys.stdin)["systemMessage"])')"
assert "strip_sgr(systemMessage) still equals the text banner" "$(eq "$(strip_sgr "$SM")" "$OUT")"

# =======================================================================================
echo "== 4. the header and its rule are the bytes they were BEFORE the logo =="
# =======================================================================================
# Against a mutant of the hook with the `logo` call removed — the banner as it shipped. The
# intact banner minus its three logo lines must equal that mutant's banner byte for byte, so
# "the banner gains the logo and nothing else" is measured rather than eyeballed.
# IN A FAKE TEMPLATE BESIDE A CONTROL COPY, because the hook derives its VERSION and its
# scripts/ dir from its own resolved path — a copy run from elsewhere differs in more than
# the mutation, which is how the first draft of this section compared two unlike banners.
MUTTPL="$TMP/muttpl"
mkdir -p "$MUTTPL/plugin/hooks"
ln -s "$TPL/plugin/scripts" "$MUTTPL/plugin/scripts"
cp "$TPL/VERSION" "$MUTTPL/VERSION"
cp "$HOOK" "$MUTTPL/plugin/hooks/control.sh"
grep -v '^logo$' "$HOOK" > "$MUTTPL/plugin/hooks/no-logo.sh"
MUT="$MUTTPL/plugin/hooks/no-logo.sh"
assert "the mutant really lost the call"   "$(eq "$(grep -c '^logo$' "$MUT")" 0)"
OUT="$(run "$MUTTPL/plugin/hooks/control.sh")"; n="$(head_no "$OUT")"
NOLOGO="$(run "$MUT")"
assert "…and still prints a banner"        "$(has 'AI-Bridge' "$NOLOGO")"
assert "…which carries no logo line"       "$(eq "$(has "$L2" "$NOLOGO")" 1)"
assert "the intact banner, minus the three logo lines, IS that banner" \
  "$(eq "$(printf '%s\n' "$OUT" | sed "$n,$((n+2))d")" "$NOLOGO")"
assert "…so the identity line is unchanged" \
  "$(eq "$(nth "$OUT" "$((n+3))")" "$(nth "$NOLOGO" "$(head_no "$NOLOGO")")")"
assert "…and so is the rule under it"      \
  "$(eq "$(nth "$OUT" "$((n+4))")" "$(nth "$NOLOGO" "$(( $(head_no "$NOLOGO") + 1 ))")")"

echo
printf 'pass=%d fail=%d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
