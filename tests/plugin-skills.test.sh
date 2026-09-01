#!/usr/bin/env bash
#
# plugin-skills.test.sh — the six plugin skills: shape, safety split, and the pins that
# keep each skill's contract from drifting away from the machinery it fronts.
#
# THE ONE DESIGN DECISION THIS FILE GUARDS: the model-invocation split. The four skills
# that CHANGE STATE (`capture`, `work`, `dispatch`, `handoff`) carry
# `disable-model-invocation: true` — a human types them; the model never reaches for them
# on its own. The two read-only skills (`brief-me`, `welcome`) stay model-invocable. Both
# directions are asserted, because a `true` added to `brief-me` silently deletes a
# capability and a `true` dropped from `dispatch` silently hands the model the loop.
#
# The per-skill pins assert the PROPERTY each contract exists for (read-only-ness,
# verbatim relay, provenance, the two non-actions), not the prose around it — the wording
# may move; the property may not.
#
# ok() follows this directory's convention: it compares actual to expected.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
TPL="$(cd "$HERE/.." && pwd)"
SK="$TPL/plugin/skills"
[ -d "$SK" ] || { echo "plugin-skills.test: missing $SK" >&2; exit 2; }

pass=0; fail=0
ok() { # <name> <actual> <expected>
  if [ "$2" = "$3" ]; then printf '  PASS  %-64s (%s)\n' "$1" "$2"; pass=$((pass+1))
  else printf '  FAIL  %-64s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}
yn() { if "$@" >/dev/null 2>&1; then echo yes; else echo no; fi; }

# fm <skill> <key> — a frontmatter value, read from between the first `---` pair only,
# so a `key:` in the body can never satisfy an assertion about the header.
fm() {
  awk -v k="$2" 'NR==1 && $0=="---" {infm=1; next}
                 infm && $0=="---" {exit}
                 infm && index($0, k ":")==1 {sub("^" k ":[ ]*", ""); print; exit}' \
    "$SK/$1/SKILL.md"
}
body() { # <skill> — everything after the closing `---`
  awk 'NR==1 && $0=="---" {infm=1; next} infm && $0=="---" {infm=0; inb=1; next} inb' \
    "$SK/$1/SKILL.md"
}

STATE_CHANGING="capture work dispatch handoff"
READ_ONLY="brief-me welcome"
ALL="$STATE_CHANGING $READ_ONLY"

# =======================================================================================
echo "== 1. every skill ships, well-formed, and no seventh skill appears unasserted =="
# =======================================================================================
for s in $ALL; do
  ok "$s/SKILL.md ships"                    "$(yn test -f "$SK/$s/SKILL.md")" yes
  ok "…its name: matches its directory"     "$(fm "$s" name)" "$s"
  ok "…its description is non-empty"        "$([ -n "$(fm "$s" description)" ] && echo yes || echo no)" yes
  ok "…and it has a body, not just a header" "$([ "$(body "$s" | grep -c .)" -ge 3 ] && echo yes || echo no)" yes
done
# A skill added to the directory without being added to this harness is invisible to every
# assertion here — the silence failure mode this repo's checks are written against.
ok "the skill set is exactly the six this file asserts" \
  "$(ls "$SK" | sort | tr '\n' ' ' | sed 's/ $//')" \
  "$(printf '%s\n' $ALL | sort | tr '\n' ' ' | sed 's/ $//')"

# =======================================================================================
echo "== 2. the model-invocation split — both directions =="
# =======================================================================================
for s in $STATE_CHANGING; do
  ok "$s is human-triggered (disable-model-invocation: true)" "$(fm "$s" disable-model-invocation)" true
done
for s in $READ_ONLY; do
  ok "$s stays model-invocable (no disable-model-invocation)"  "$(fm "$s" disable-model-invocation)" ""
done

# =======================================================================================
echo "== 3. plugin content is generic — it installs from a public marketplace =="
# =======================================================================================
# Same rule as symlink/: no org, user path or host literal in what every installer gets.
# (The plugin README legitimately names the marketplace repo; skills never do.)
for s in $ALL; do
  ok "$s carries no org / clone-path / host literal" \
    "$(grep -c -E 'cbmono|/Users/|github\.com' "$SK/$s/SKILL.md" | tr -d ' ')" 0
done

# =======================================================================================
echo "== 4. welcome — the absorbed /ai-bridge contract, property by property =="
# =======================================================================================
W="$SK/welcome/SKILL.md"
ok "welcome relays scripts/ai-bridge.sh verbatim"       "$(grep -c 'relay its output' "$W" | tr -d ' ')" 1
ok "…all three forms are named"                          "$(grep -cE '^\| `/welcome( check| fix)?`' "$W" | tr -d ' ')" 3
ok "…its tools are the one script plus read-only inspection" \
  "$(fm welcome allowed-tools)" "Bash(scripts/ai-bridge.sh:*), Bash(bash scripts/ai-bridge.sh:*), Bash(pwd), Bash(ls:*), Read, Glob"
# The two non-actions are the reason the contract exists (tests/ai-bridge-command.test.sh
# proves the SCRIPT never acts; this pins that the skill never invites the model to).
ok "…never rewrite config files"                         "$(grep -c 'never revert, stage or rewrite `instance.config.json`' "$W" | tr -d ' ')" 1
ok "…never clear a tick lock"                            "$(grep -c 'never remove or rewrite `.tick-lock`' "$W" | tr -d ' ')" 1
ok "…and no rules recital"                               "$(grep -ci 'always use the pm-loop' "$W" | tr -d ' ')" 0
ok "…outside an instance it stops rather than improvises" "$(grep -c 'never improvise a banner' "$W" | tr -d ' ')" 1

# =======================================================================================
echo "== 5. the other five — one load-bearing property each =="
# =======================================================================================
ge1() { if [ "$1" -ge 1 ]; then echo yes; else echo no; fi; }
ok "brief-me declares itself read-only" \
  "$(ge1 "$(grep -c 'never dispatch, promote, merge' "$SK/brief-me/SKILL.md")")" yes
ok "capture drafts, never promotes" \
  "$(ge1 "$(grep -ci 'never promoted\|never promote' "$SK/capture/SKILL.md")")" yes
ok "…and requires provenance" \
  "$(ge1 "$(grep -ci 'provenance' "$SK/capture/SKILL.md")")" yes
ok "work works ONE task" \
  "$(ge1 "$(grep -ci 'one task' "$SK/work/SKILL.md")")" yes
ok "dispatch defers to the pinned loop contract, not a paraphrase" \
  "$(ge1 "$(grep -c 'pm-loop' "$SK/dispatch/SKILL.md")")" yes
ok "handoff asks for the new owner's github login" \
  "$(ge1 "$(grep -ci 'github-login\|github login' "$SK/handoff/SKILL.md")")" yes

# =======================================================================================
echo "== 6. manifest validation, where the CLI exists =="
# =======================================================================================
# CI's runner ships no claude CLI; the skip is REPORTED, never silent, and the structural
# assertions above do not depend on it.
if command -v claude >/dev/null 2>&1; then
  vrc=0; claude plugin validate --strict "$TPL/plugin" >/dev/null 2>&1 || vrc=$?
  ok "claude plugin validate --strict passes"            "$vrc" 0
else
  echo "  SKIP  claude CLI absent — validate --strict not run here (CI runner has no CLI)"
fi

printf '\npass=%s fail=%s\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
