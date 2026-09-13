#!/usr/bin/env bash
#
# headless-tick-probe.sh — re-measures docs/spikes/headless-tick.md.
# Builds a throwaway probe plugin and fixture cwd under a temp root, then prints
# one line per probe. Probes 1-2 are argument parsing and need no auth; probes
# 3-9 each spend one cheap turn, need auth, and are skipped without --live.
# Nothing here touches a real bundle, and no probe takes a .tick-lock.
# Exit 0 always: this reports, it never gates.
set -uo pipefail

LAB="$(mktemp -d)"; LIVE="${1:-}"
trap 'rm -rf "$LAB"' EXIT
say() { printf '%-46s %s\n' "$1" "$2"; }
res() { python3 -c 'import json,sys
try: d=json.load(open(sys.argv[1]))
except Exception: print("<no json>"); raise SystemExit
print(json.dumps({k:d.get(k) for k in ("subtype","result") if k in d})[:200])' "$1"; }

printf 'claude %s\n\n' "$(claude --version 2>/dev/null)"

SCHEMA='{"type":"object","additionalProperties":false,"required":["status"],"properties":{"status":{"enum":["committed","idle","blocked"]}}}'
printf '%s\n' "$SCHEMA" > "$LAB/schema.json"
# shellcheck disable=SC2016  # a literal "$schema" KEY, which is what probe 2 measures
DRAFT_KEYED='{"$schema":"https://json-schema.org/draft/2020-12/schema","type":"object"}'

say "1 --json-schema takes a file path" \
  "$(claude -p --json-schema "$LAB/schema.json" hi </dev/null 2>&1 | head -1)"
say "2 --json-schema keeps a \$schema draft key" \
  "$(claude -p --json-schema "$DRAFT_KEYED" hi </dev/null 2>&1 | head -1)"

[ "$LIVE" = "--live" ] || { printf '\n(probes 3-9 need auth and a turn each: re-run with --live)\n'; exit 0; }

PP="$LAB/probe-plugin"
mkdir -p "$PP/.claude-plugin" "$PP/hooks" "$PP/skills/slash-only"
printf '{"name":"spikeprobe","version":"0.0.1","description":"throwaway probe plugin"}\n' > "$PP/.claude-plugin/plugin.json"
printf -- '---\nname: slash-only\ndisable-model-invocation: true\ndescription: probe skill, slash-invocable only\n---\nReply with the literal token SLASH_OK.\n' > "$PP/skills/slash-only/SKILL.md"
cat > "$PP/hooks/mark.sh" <<'HOOK'
#!/usr/bin/env bash
printf '%s\n' "${1:-?}" >> "$SPIKE_HOOK_LOG"
exit 0
HOOK
chmod +x "$PP/hooks/mark.sh"
cat > "$PP/hooks/hooks.json" <<'HOOK'
{"hooks":{
"SessionStart":[{"hooks":[{"type":"command","command":"${CLAUDE_PLUGIN_ROOT}/hooks/mark.sh SessionStart"}]}],
"UserPromptSubmit":[{"hooks":[{"type":"command","command":"${CLAUDE_PLUGIN_ROOT}/hooks/mark.sh UserPromptSubmit"}]}],
"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"${CLAUDE_PLUGIN_ROOT}/hooks/mark.sh PreToolUse"}]}],
"Stop":[{"hooks":[{"type":"command","command":"${CLAUDE_PLUGIN_ROOT}/hooks/mark.sh Stop"}]}]}}
HOOK

export SPIKE_HOOK_LOG="$LAB/hooks.log"
cd "$LAB" || exit
C=(claude -p --model haiku --output-format json --permission-prompts none --max-budget-usd 0.5)

"${C[@]}" --plugin-dir "$PP" -- '/spikeprobe:slash-only' </dev/null > "$LAB/p3.json" 2>/dev/null
say "3 a disable-model-invocation skill, as the -p prompt" "$(res "$LAB/p3.json")"
say "4 plugin hooks that fired" "$(sort -u "$LAB/hooks.log" 2>/dev/null | tr '\n' ' ')"

"${C[@]}" --safe-mode --plugin-dir "$PP" -- '/spikeprobe:slash-only' </dev/null > "$LAB/p5.json" 2>/dev/null
say "5 CONTROL: the same under --safe-mode" "$(res "$LAB/p5.json")"

W='Use the Write tool to create ./probe.txt containing OK. Reply WROTE or DENIED.'
"${C[@]}" --setting-sources project -- "$W" </dev/null > "$LAB/p6.json" 2>/dev/null
say "6 Write, no allowlist" "$(res "$LAB/p6.json")"
rm -f "$LAB/probe.txt"
"${C[@]}" --setting-sources project --allowedTools Write -- "$W" </dev/null > "$LAB/p7.json" 2>/dev/null
say "7 Write, --allowedTools Write" "$(res "$LAB/p7.json")"

Q='Report an idle tick as structured output: status idle.'
"${C[@]}" --json-schema "$SCHEMA" --agents '{"tiny":{"description":"probe","prompt":"You are terse."}}' --agent tiny -- "$Q" </dev/null > "$LAB/p8.json" 2>/dev/null
say "8 --json-schema under an inline --agents agent" "$(res "$LAB/p8.json")"
"${C[@]}" --json-schema "$SCHEMA" --agent ai-bridge:project-manager -- "$Q" </dev/null > "$LAB/p9.json" 2>/dev/null
say "9 --json-schema under a PLUGIN --agent" "$(res "$LAB/p9.json")"

"${C[@]}" --max-budget-usd 0.0001 -- "$Q" </dev/null > "$LAB/p10.json" 2>/dev/null
say "10 budget breach: exit $?" "$(res "$LAB/p10.json")"
