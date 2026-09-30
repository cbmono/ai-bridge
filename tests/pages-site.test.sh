#!/usr/bin/env bash
#
# pages-site.test.sh — the GitHub Pages site under docs/ stays on-palette, self-contained
# and on slugs spelled under the plugin's manifest name (loopd/task-006, task-007).
#
# Every check is a function over a site directory, run once against docs/ (must pass) and
# once against a mutant copy carrying the exact regression it exists for (must fail) — a
# check that only ever passes cannot tell a clean page from an unread one.
#
# The palette allowlist is COPIED from the handoff's tokens.css, which lives in the
# control panel rather than this repo, so it is typed here. The three rgba() values are
# the only ones the handoff specifies; cli-theme.json's #a9b1c2 is terminal-only.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
. "$HERE/tools/plugin-name.sh"
SITE="$REPO/docs"
for f in "$SITE/index.html" "$SITE/assets/loopd-mark-color.svg"; do
  [ -f "$f" ] || { echo "pages-site.test: missing $f" >&2; exit 2; }
done
command -v python3 >/dev/null 2>&1 || { echo "pages-site.test: python3 builds the mutants" >&2; exit 2; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/pages-site.XXXXXX")" || {
  echo "pages-site.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp}" >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
ok() { if [ "$1" = "$2" ]; then printf '  PASS  %s\n' "$3"; pass=$((pass+1));
       else printf '  FAIL  %s (got %s, want %s)\n' "$3" "$1" "$2"; fail=$((fail+1)); fi; }
rc() { "$@" >/dev/null 2>&1 && echo pass || echo fail; }

TOKEN_HEXES='#101318 #171b22 #1c212b #14171c #262c37 #33405a #e9edf4 #9aa4b5 #6c7488
#5ea2ff #8dbdff #2a5090 #ff7ac2 #ffa3d4 #c9548f #9cc4ff #3f77c9 #2a4f88 #ff9ed3'
RGBAS='rgba(233,237,244,.045) rgba(255,122,194,.08) rgba(94,162,255,.09)'

check_hex() {
  local h bad=0
  for h in $(grep -oE '#[0-9a-fA-F]{6}' "$1/index.html" | tr 'A-F' 'a-f' | sort -u); do
    case " $(echo $TOKEN_HEXES) " in *" $h "*) ;; *) echo "off-palette $h"; bad=1 ;; esac
  done
  return "$bad"
}

check_rgba() {
  local v bad=0
  for v in $(grep -oE 'rgba\([^)]*\)' "$1/index.html" | tr -d ' ' | sort -u); do
    case " $RGBAS " in *" $v "*) ;; *) echo "unlisted $v"; bad=1 ;; esac
  done
  return "$bad"
}

check_slugs() {
  local cmds; cmds="$(ls "$REPO/plugin/skills" | tr '\n' '|' | sed 's/|$//')"
  [ "$(grep -oE "/[a-z][a-z0-9-]*:(${cmds})([^a-z-]|\$)" "$1/index.html" | grep -vc "^/${PN}:")" = 0 ] \
    && grep -qF "${PN}@${PMK}" "$1/index.html"
}

# Every src/href/url() that is not a remote URL or a fragment is relative and resolves.
check_refs() {
  local ref path bad=0 n=0
  while IFS= read -r ref; do
    case "$ref" in https://*|http://*|mailto:*|'#'*) continue ;; esac
    n=$((n+1))
    case "$ref" in /*|//*) echo "root-absolute $ref"; bad=1; continue ;; esac
    path="$1/${ref%%[#?]*}"
    [ -e "$path" ] || { echo "unresolved $ref"; bad=1; }
  done < <(grep -oE '(src|href)="[^"]*"|url\("[^"]*"\)' "$1/index.html" \
             | sed -E 's/^(src|href)="//; s/^url\("//; s/"\)?$//')
  [ "$n" -gt 0 ] || { echo "no local refs found"; bad=1; }
  return "$bad"
}

check_nojekyll() { [ -f "$1/.nojekyll" ]; }

check_fonts() {
  local d
  ! grep -qiE 'fonts\.(googleapis|gstatic)\.com' "$1/index.html" || return 1
  grep -qE "font-family:'Inter';" "$1/index.html" || return 1
  grep -qE "font-family:'JetBrains Mono';" "$1/index.html" || return 1
  for d in "$1/assets/fonts/inter" "$1/assets/fonts/jetbrains-mono"; do
    ls "$d"/*.woff2 >/dev/null 2>&1 || return 1
    grep -lqi 'SIL Open Font License' "$d"/*.txt 2>/dev/null || return 1
  done
}

# Both renderings of the loop diagram (wide and tall) carry a dashed blue retry edge.
check_retry() {
  [ "$(grep -E 'stroke="#5ea2ff"' "$1/index.html" | grep -c 'stroke-dasharray')" -ge 2 ]
}

check_c2pa() {
  local f
  for f in "$1"/assets/*.svg; do grep -q '<c2pa:manifest>' "$f" || return 1; done
}

CHECKS="hex rgba slugs refs nojekyll fonts retry c2pa"

echo "== the published site passes every check"
for c in $CHECKS; do ok "$(rc "check_$c" "$SITE")" pass "docs/ — $c"; done
check_refs "$SITE" >/dev/null || check_refs "$SITE"
check_hex "$SITE" >/dev/null || check_hex "$SITE"

echo "== each check fails on the regression it exists for"
mutant() { rm -rf "$TMP/site"; mkdir -p "$TMP/site"; cp -R "$SITE/index.html" "$SITE/.nojekyll" "$SITE/assets" "$TMP/site/"; }
edit() { python3 - "$TMP/site/index.html" "$1" "$2" <<'PY'
import sys
p,a,b=sys.argv[1:]; s=open(p,encoding='utf-8').read()
assert a in s, "mutation anchor missing: "+a
open(p,'w',encoding='utf-8').write(s.replace(a,b,1))
PY
}
M="$TMP/site"

mutant; edit '</style>' '.x{color:#a9b1c2}</style>'
ok "$(rc check_hex "$M")" fail "hex — cli-theme.json's terminal-only #a9b1c2 is refused"
mutant; edit '</style>' '.x{box-shadow:0 24px 80px rgba(0,0,0,.5)}</style>'
ok "$(rc check_rgba "$M")" fail "rgba — a fourth rgba() is refused"
mutant; edit '</main>' "<code>/not-${PN}:dispatch</code></main>"
ok "$(rc check_slugs "$M")" fail "slugs — a slug under another name is refused"
mutant; edit "${PN}@${PMK}" "not-${PN}@not-${PMK}"
ok "$(rc check_slugs "$M")" fail "slugs — losing ${PN}@${PMK} is refused"
mutant; edit 'src="assets/loopd-icon.png"' 'src="/assets/loopd-icon.png"'
ok "$(rc check_refs "$M")" fail "refs — a root-absolute src is refused"
mutant; edit 'src="assets/loopd-icon.png"' 'src="assets/loopd-hero.png"'
ok "$(rc check_refs "$M")" fail "refs — a relative src to a missing file is refused"
mutant; rm -f "$M/.nojekyll"
ok "$(rc check_nojekyll "$M")" fail "nojekyll — a missing docs/.nojekyll is refused"
mutant; edit '<style>' '<link href="https://fonts.googleapis.com/css2?family=Inter" rel="stylesheet"><style>'
ok "$(rc check_fonts "$M")" fail "fonts — linking Google Fonts is refused"
mutant; rm -f "$M"/assets/fonts/jetbrains-mono/*.txt
ok "$(rc check_fonts "$M")" fail "fonts — a font directory without its OFL is refused"
mutant; python3 - "$M/index.html" <<'PY'
import re,sys
p=sys.argv[1]; s=open(p,encoding='utf-8').read()
open(p,'w',encoding='utf-8').write(re.sub(r' stroke-dasharray="[^"]*"','',s))
PY
ok "$(rc check_retry "$M")" fail "retry — a diagram with no dashed edge is refused"
mutant; sed -E 's#<metadata>.*</metadata>##' "$SITE/assets/loopd-mark-color.svg" > "$M/assets/loopd-mark-color.svg"
ok "$(rc check_c2pa "$M")" fail "c2pa — an SVG stripped of its manifest is refused"

echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
