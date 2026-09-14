#!/usr/bin/env bash
#
# plugin-theme.test.sh — the theme the plugin ships is SHAPE-legal, and nothing here
# selects it for the human.
#
# IT PINS THE SHAPE, AND SINCE loopd/task-005 THE PALETTE TOO. The owner's design handoff
# landed, so the colours are no longer a placeholder: §6 holds every override to the
# palette in tests/fixtures/theme-palette.txt and the duotone keys to their exact hex. A
# third accent and a silently missing key are the two failures nobody notices by looking.
#
# ok() follows this directory's convention: it compares actual to expected.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
THEME="$REPO/plugin/themes/ai-bridge.json"
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
ok "plugin/themes/ai-bridge.json exists" "$([ -f "$THEME" ] && echo yes || echo no)" yes
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
ok "…so /theme lists custom:ai-bridge:ai-bridge" \
   "custom:$(jq -r .name "$PJ"):$(basename "$THEME" .json)" "custom:ai-bridge:ai-bridge"
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
printf '{"theme": "custom:ai-bridge:ai-bridge"}\n' > "$TMP/settings.json"
ok "…and the same scanner finds it when it is there" "$(files_naming "$TMP" '"theme"')" 1

echo "== 6. the palette is the handoff's, and the duotone keys carry their own hex =="
palette()    { grep -oE '^#[0-9a-f]{6}' "$PALETTE"; }
off_palette() { # <theme.json> -> the override keys whose colour is not a palette value
  jq -r '.overrides | to_entries[] | "\(.key)\t\(.value|ascii_downcase)"' "$1" \
    | awk -F'\t' 'NR==FNR { p[$1]=1; next } !($2 in p) { printf "%s ", $1 }' <(palette) - \
    | sed 's/ $//'
}
off_duotone() { # <theme.json> -> "<key>=<got>" for each required key absent or off-value
  local k want got
  while read -r k want; do
    [ -n "$k" ] || continue
    got="$(jq -r --arg k "$k" '.overrides[$k] // "MISSING"' "$1")"
    [ "$got" = "$want" ] || printf '%s=%s ' "$k" "$got"
  done <<'REQ'
claude                  #5ea2ff
promptBorder            #5ea2ff
briefLabelClaude        #5ea2ff
blue_FOR_SUBAGENTS_ONLY #5ea2ff
success                 #5ea2ff
warning                 #ff7ac2
error                   #ff7ac2
permission              #ff7ac2
pink_FOR_SUBAGENTS_ONLY #ff7ac2
inactive                #6c7488
subtle                  #262c37
text                    #e9edf4
REQ
}
ok "the palette file is long enough to be the palette" \
   "$([ "$(palette | grep -c .)" -ge 15 ] && echo yes || echo no)" yes
ok "every override colour is a palette value" "$(off_palette "$THEME")" ""
ok "every duotone key carries its handoff hex" "$(off_duotone "$THEME" | sed 's/ $//')" ""

jq 'del(.overrides.claude) | .overrides.warning = "#00ff00"' "$THEME" > "$TMP/offbrand.json"
ok "a third accent is named"        "$(off_palette "$TMP/offbrand.json")" "warning"
ok "a missing key and an off hex are named" "$(off_duotone "$TMP/offbrand.json" | sed 's/ $//')" \
   "claude=MISSING warning=#00ff00"

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
