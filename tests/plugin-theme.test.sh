#!/usr/bin/env bash
#
# plugin-theme.test.sh — the theme the plugin ships is SHAPE-legal, and nothing here
# selects it for the human.
#
# IT PINS THE SHAPE, AND SINCE loopd/task-005 THE PALETTE TOO. The owner's design handoff
# landed, so the colours are no longer a placeholder: §6 holds every override to the
# palette in tests/fixtures/theme-palette.txt, the keys the amendment still pins to their
# exact hex, and every token to its MEANING. Accents became legal in loopd/task-009 (the
# amendment quoted in the palette fixture's header), so the exact-hex pin came off text,
# success, warning and pink_FOR_SUBAGENTS_ONLY, and the semantic check replaced what it
# protected: blue #5ea2ff is the machine's, pink #ff7ac2 is the human's, and a token
# wearing the other side's primary is the failure nobody notices by looking.
#
# ok() follows this directory's convention: it compares actual to expected.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
. "$(dirname "$0")/tools/plugin-name.sh"
THEME="$REPO/plugin/themes/loopd.json"
TOKENS="$REPO/tests/fixtures/theme-tokens.txt"
PALETTE="$REPO/tests/fixtures/theme-palette.txt"
PJ="$REPO/plugin/.claude-plugin/plugin.json"

pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then printf '  PASS  %-58s (%s)\n' "$1" "$2"; pass=$((pass+1))
       else printf '  FAIL  %-58s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not installed"; exit 0; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/plugin-theme.XXXXXX")" || {
  echo "plugin-theme.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp} — create that directory first." >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT

allow() { grep -v '^#' "$TOKENS" | grep -v '^[[:space:]]*$'; }

# Both scanners take the file to read, so the same code answers for the shipped theme and
# for a planted one — a validator run only over the healthy file cannot be shown to work.
bad_tokens() { # <theme.json> -> the override keys that are not documented tokens
  comm -23 <(jq -r '.overrides | keys[]' "$1" | sort) <(allow | sort) | tr '\n' ' ' | sed 's/ $//'
}
bad_values() { # <theme.json> -> the override keys whose value is not #rrggbb
  jq -r '.overrides | to_entries[] | "\(.key)\t\(.value|tostring)"' "$1" \
    | awk -F'\t' '$2 !~ /^#[0-9a-fA-F]{6}$/ { printf "%s ", $1 }' | sed 's/ $//'
}
files_naming() { # <root> <needle> -> how many files under root contain it
  grep -rlF --exclude-dir=.git -e "$2" "$1" 2>/dev/null | grep -c . | tr -d ' '
}

echo "== 1. the theme ships, parses, and is shape-legal =="
ok "plugin/themes/loopd.json exists" "$([ -f "$THEME" ] && echo yes || echo no)" yes
ok "…parses"                    "$(jq empty "$THEME" >/dev/null 2>&1 && echo yes || echo no)" yes
ok "…carries a name"            "$(jq -r '.name // "" | length > 0' "$THEME")" true
ok "…base is dark or light"     "$(jq -r '.base | test("^(dark|light)$")' "$THEME")" true
ok "…every override is a documented token" "$(bad_tokens "$THEME")" ""
ok "…every value is #rrggbb"               "$(bad_values "$THEME")" ""
ok "…over an overrides block worth scanning" \
   "$([ "$(jq -r '.overrides | keys | length' "$THEME")" -ge 10 ] && echo yes || echo no)" yes

echo "== 2. both scanners catch what they exist to catch =="
jq '.overrides.notAToken = "#abcdef" | .overrides.claude = "blue"' "$THEME" > "$TMP/mutant.json"
ok "an undocumented token is named"   "$(bad_tokens "$TMP/mutant.json")" "notAToken"
ok "a value that is not #rrggbb is named" "$(bad_values "$TMP/mutant.json")" "claude"

echo "== 3. the manifest declares the directory, with every existing key intact =="
ok "experimental.themes points at ./themes/" "$(jq -r '.experimental.themes // ""' "$PJ")" "./themes/"
ok "…and that path resolves to a directory" \
   "$([ -d "$REPO/plugin/$(jq -r '.experimental.themes // "."' "$PJ")" ] && echo yes || echo no)" yes
ok "…so /theme lists custom:${PN}:loopd" \
   "custom:$(jq -r .name "$PJ"):$(basename "$THEME" .json)" "custom:${PN}:loopd"
miss=""
for k in name displayName version description author repository license keywords; do
  [ "$(jq -r "has(\"$k\")" "$PJ")" = true ] || miss="${miss:+$miss }$k"
done
ok "every key the manifest already carried is still there" "$miss" ""

echo "== 4. the token allowlist lives in ONE file =="
# Spelled out of two halves so this assertion does not plant its own second copy of the
# needle — the same device plugin-agents.test.sh uses for the retired namespace.
NEEDLE="effort""Ultra"
ok "the allowlist is long enough to be the allowlist" \
   "$([ "$(allow | grep -c .)" -ge 40 ] && echo yes || echo no)" yes
ok "a token only the allowlist may list is in exactly one file" "$(files_naming "$REPO" "$NEEDLE")" 1
printf '%s\n' "$NEEDLE" > "$TMP/a.txt"; printf '%s\n' "$NEEDLE" > "$TMP/b.txt"
ok "…and the same scanner counts two when there are two" "$(files_naming "$TMP" "$NEEDLE")" 2

echo "== 5. nothing the plugin ships writes the user's theme key =="
# Selecting a theme is the human's action in /theme. The JSON key is the thing a writer
# would have to spell, so its absence from the whole shipped tree is the assertion.
ok "no shipped file spells the settings key" "$(files_naming "$REPO/plugin" '"theme"')" 0
printf '{"theme": "custom:'"${PN}:"'loopd"}\n' > "$TMP/settings.json"
ok "…and the same scanner finds it when it is there" "$(files_naming "$TMP" '"theme"')" 1

echo "== 6. the palette is the handoff's, the pinned keys hold their hex, the meanings hold =="
BLUE='#5ea2ff'   # the machine's
PINK='#ff7ac2'   # the human's
palette()    { grep -oE '^#[0-9a-f]{6}' "$PALETTE"; }
off_palette() { # <theme.json> -> the override keys whose colour is not a palette value
  jq -r '.overrides | to_entries[] | "\(.key)\t\(.value|ascii_downcase)"' "$1" \
    | awk -F'\t' 'NR==FNR { p[$1]=1; next } !($2 in p) { printf "%s ", $1 }' <(palette) - \
    | sed 's/ $//'
}
off_duotone() { # <theme.json> -> "<key>=<got>" for each required key absent or off-value
  local k want got
  # Narrowed by loopd/task-009: text, success, warning and pink_FOR_SUBAGENTS_ONLY carry
  # the owner's accents now, and crossed_meaning() is what took over for them.
  while read -r k want; do
    [ -n "$k" ] || continue
    got="$(jq -r --arg k "$k" '.overrides[$k] // "MISSING"' "$1")"
    [ "$got" = "$want" ] || printf '%s=%s ' "$k" "$got"
  done <<'REQ'
claude                  #5ea2ff
promptBorder            #5ea2ff
briefLabelClaude        #5ea2ff
blue_FOR_SUBAGENTS_ONLY #5ea2ff
error                   #ff7ac2
permission              #ff7ac2
inactive                #6c7488
subtle                  #262c37
REQ
}
crossed_meaning() { # <theme.json> -> "<key>=<hex>" per token wearing the other side's primary
  local k got
  for k in claude success merged suggestion planMode autoAccept ide fastMode promptBorder; do
    got="$(jq -r --arg k "$k" '.overrides[$k] // "" | ascii_downcase' "$1")"
    [ "$got" = "$PINK" ] && printf '%s=%s ' "$k" "$got"
  done
  for k in permission error warning; do
    got="$(jq -r --arg k "$k" '.overrides[$k] // "" | ascii_downcase' "$1")"
    [ "$got" = "$BLUE" ] && printf '%s=%s ' "$k" "$got"
  done
  return 0
}
ok "the palette file is long enough to be the palette" \
   "$([ "$(palette | grep -c .)" -ge 15 ] && echo yes || echo no)" yes
ok "every override colour is a palette value" "$(off_palette "$THEME")" ""
ok "every duotone key carries its handoff hex" "$(off_duotone "$THEME" | sed 's/ $//')" ""
ok "no token wears the other side's primary" "$(crossed_meaning "$THEME" | sed 's/ $//')" ""

jq 'del(.overrides.claude) | .overrides.warning = "#00ff00"' "$THEME" > "$TMP/offbrand.json"
ok "a third accent is named"        "$(off_palette "$TMP/offbrand.json")" "warning"
ok "a missing key is named"                  "$(off_duotone "$TMP/offbrand.json" | sed 's/ $//')" \
   "claude=MISSING"
jq '.overrides.error = "#00ff00"' "$THEME" > "$TMP/offhex.json"
ok "…and an off hex on a still-pinned key is named" "$(off_duotone "$TMP/offhex.json" | sed 's/ $//')" \
   "error=#00ff00"
# success and warning are OFF the exact-hex pin, so this mutant is what shows the semantic
# check standing on its own rather than riding off_duotone's remaining entries.
jq --arg b "$BLUE" --arg p "$PINK" \
   '.overrides.claude = $p | .overrides.success = $p
    | .overrides.permission = $b | .overrides.warning = $b' "$THEME" > "$TMP/swapped.json"
ok "a swapped theme is named on both sides" "$(crossed_meaning "$TMP/swapped.json" | sed 's/ $//')" \
   "claude=$PINK success=$PINK permission=$BLUE warning=$BLUE"

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
