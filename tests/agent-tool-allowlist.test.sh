#!/usr/bin/env bash
#
# agent-tool-allowlist.test.sh — an agent file, or a shared conventions doc an agent
# reads, must not name a tool that is absent from the addressed agent's `tools:` list.
#
# WHY THIS IS A TEST AND NOT A CONVENTION. A `tools:` allowlist is invisible from the
# prose it governs: `software-engineer.md` reads perfectly until you notice the agent
# holds no `Agent` tool, at which point "dispatch `code-architect` if it's installed in
# `~/.claude/agents/`" turns out to test the wrong thing entirely — installation, when
# what decides the outcome is tool possession. `code-architect` IS installed, so the
# condition evaluated TRUE and the instruction was still unexecutable. That is the worst
# shape a defect can take: it reads as satisfied. Three more instances existed at
# 178c16f (`Workflow` in `auditor.md`, `qa-reviewer.md`, `software-engineer.md`, plus
# `EnterWorktree` in `CONVENTIONS.md`), and a fifth will appear the next time the harness
# moves a capability into a tool. So the class is asserted here rather than trusted to
# whoever next edits an agent body.
#
# THE RULE, AND WHY IT IS THIS ONE. False positives are the whole difficulty: the first
# manual sweep for this class was fooled by ordinary English — "never *write* to the
# bundle", "the *agent* roster", "*workflow* structure", "the *task* document". A check
# that cries wolf gets deleted, so:
#
#   A mention counts ONLY as a BACKTICKED IDENTIFIER from a closed vocabulary of
#   harness tool names — `Workflow`, `Agent`, `Skill`, ... plus `mcp__*`.
#
# Backticks are what this codebase already uses to mean "the identifier, not the word"
# (`Read`/`Glob`/`Grep` in `advisor.md:22-23` are exactly that), and the vocabulary is
# closed so a new prose word can never become a violation. Both halves are asserted
# below against fixtures, including the four prose words above.
#
# WHO IS "THE ADDRESSED AGENT" FOR A SHARED DOC. `CONVENTIONS.md` is read by
# `software-engineer`, `devops-engineer`, `qa-reviewer` and `oncall-guide` at once, and
# their allowlists differ. This check takes the conservative reading: an instruction in a
# shared doc must be executable by EVERY agent that reads it, so the doc's effective
# allowlist is the INTERSECTION of its readers'. The reader set is derived mechanically
# (which agent bodies reference the doc), not hardcoded, so adding a reader tightens the
# constraint automatically.
#
# THE ESCAPE HATCH, AND WHY THERE HAS TO BE ONE. Naming an absent tool is sometimes the
# correct thing to write — `oncall-guide.md:28-30` names `Skill` precisely to record that
# it must not be reinstated, and the fix for the defects above states the absence rather
# than hiding it. So a file may declare a mention as deliberate:
#
#   <!-- tool-mention: Workflow, Agent — why this file names a tool a reader lacks -->
#
# The reason is mandatory (an empty one fails), and a declaration is flagged when it is
# stale (the tool is no longer mentioned) or redundant (the tool IS in the allowlist), so
# it cannot rot into a rubber stamp. RESIDUAL GAP, stated honestly: a declaration is
# per-(file, tool), so once a file declares `Workflow`, a NEW unconditional `Workflow`
# instruction in that same file would not be flagged. Per-mention markers were rejected
# as too brittle for reflowing prose; the stale/redundant assertions are the mitigation.
#
# OUT OF REACH FROM THIS REPO: a live instance's own `CLAUDE.md`. It is a real file in
# each bundle, not a symlink to anything here, so a copy of a rule that drifts into it
# cannot be checked from here — `seed/CLAUDE.md` (the template every new instance is
# stamped from) is covered instead, and `upgrade.sh` is the route for existing ones.
#
# Agents that declare NO `tools:` key inherit the full tool set and are therefore
# unconstrained — `config/required/agents/` and `config/opinionated/agents/`. They are
# skipped, and that skip is asserted rather than assumed: if one of them ever grows a
# `tools:` key, the assertion below fails and points here.
#
# ok() follows this directory's convention: it compares actual to expected.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
pass=0; fail=0
ok() { # <name> <actual> <expected>
  if [ "$2" = "$3" ]; then printf '  PASS  %-58s (%s)\n' "$1" "$2"; pass=$((pass+1))
  else printf '  FAIL  %-58s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}

# ------------------------------------------------------------------ the vocabulary
# Closed list of harness tool names, plus a pattern for MCP tools (which cannot be
# enumerated). A name absent from here is prose, by construction.
# `Task` is DELIBERATELY EXCLUDED even though it is the dispatch tool's name in some
# harness versions: OKF's own document type is also `Task`, and this bundle backticks that
# type constantly (`symlink/SCHEMA.md:441`, `docs/schema.md:27`, `new-project.md:58`).
# Including it would flag the bundle's core vocabulary as a tool reference — the exact
# cry-wolf failure that gets a check deleted. `Agent` is the name that decides dispatch
# here and it carries no such collision.
VOCAB='Agent|Workflow|Skill|Read|Write|Edit|MultiEdit|NotebookEdit|Glob|Grep|Bash|BashOutput|KillShell|KillBash|WebFetch|WebSearch|TodoWrite|ToolSearch|SlashCommand|ExitPlanMode|EnterWorktree|mcp__[A-Za-z0-9_*-]+'
MENTION_RE="\`($VOCAB)\`"

# ------------------------------------------------------------------ the primitives
body() { # <file> — everything after the closing frontmatter delimiter
  awk 'NR==1 && $0=="---" {fm=1; next} fm==1 && $0=="---" {fm=2; next} fm!=1 {print}' "$1"
}

tools_of() { # <file> — the tools: values, one per line; empty output means "no key"
  awk 'NR==1 && $0=="---" {fm=1; next} fm==1 && $0=="---" {exit} fm==1 && /^tools:[[:space:]]*/ {
         sub(/^tools:[[:space:]]*/, ""); gsub(/,/, "\n"); print }' "$1" \
    | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | grep -v '^$'
}

has_tools_key() { # <file>
  awk 'NR==1 && $0=="---" {fm=1; next} fm==1 && $0=="---" {exit} fm==1 && /^tools:/ {found=1}
       END {print (found ? "yes" : "no")}' "$1"
}

mentions_of() { # <file> — unique backticked tool identifiers in the body
  body "$1" | grep -oE "$MENTION_RE" | tr -d '`' | sort -u
}

mention_lines() { # <file> <tool> — line numbers (of the body) naming <tool>
  body "$1" | grep -nF "\`$2\`" | cut -d: -f1 | paste -sd, - 2>/dev/null
}

mention_count() { # <file> <tool> — how many times the body names <tool>
  body "$1" | grep -oF "\`$2\`" | grep -c .
}

# A declaration is `<!-- tool-mention: <Tool>(<N>), ... — <reason> -->`, where N is how
# many mentions of that tool the file is declaring. Parse it ONCE, here, and emit
# `ok|<names>` or `bad|<names>` so "which tools are declared" and "is this malformed" can
# never disagree. The separator before the reason is an em-dash or a spaced hyphen.
#
# THE BUDGET `(N)` IS WHAT KEEPS A DECLARATION FROM BECOMING A BLANKET WAIVER, and it
# exists because the first version of this check was measurably too weak: with a bare
# `<!-- tool-mention: Agent -->` on `CONVENTIONS.md`, re-introducing the exact defect this
# whole file was written for ("dispatch code-architect ... using the `Agent` tool") still
# passed. Pinning the count means a NEW mention of an already-declared tool fails until
# someone folds it into the reason deliberately. A declaration with no reason, or with a
# name carrying no `(N)`, is not a declaration and exempts nothing.
parse_declarations() { # <file>
  grep -oE '<!--[[:space:]]*tool-mention:[^>]*-->' "$1" 2>/dev/null | while IFS= read -r d; do
    inner="$(printf '%s' "$d" | sed -E 's/^<!--[[:space:]]*tool-mention:[[:space:]]*//; s/[[:space:]]*-->[[:space:]]*$//')"
    case "$inner" in
      *—*|*" - "*) names="$(printf '%s' "$inner" | sed -E 's/(—| - ).*$//')"
                   reason="$(printf '%s' "$inner" | sed -E 's/^[^—]*—//; s/^.* - //' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')" ;;
      *)           names="$inner"; reason="" ;;
    esac
    # Every name must carry a `(N)` budget, or the whole declaration is malformed.
    budgeted=yes
    for n in $(printf '%s' "$names" | tr ',' ' '); do
      case "$n" in *\(*\)) ;; *) budgeted=no ;; esac
    done
    if [ -n "$reason" ] && [ "$budgeted" = yes ]; then printf 'ok|%s\n' "$names"
    else printf 'bad|%s\n' "$names"; fi
  done
}

declared_of() { # <file> — tool names from well-formed declarations, one per line
  parse_declarations "$1" | grep '^ok|' | cut -d'|' -f2- \
    | tr ',' '\n' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' \
    | sed -E 's/\([0-9]+\)$//' | grep -v '^$' | sort -u
}

declared_budget() { # <file> <tool> — the N this file declared for <tool> (0 if none)
  parse_declarations "$1" | grep '^ok|' | cut -d'|' -f2- | tr ',' '\n' \
    | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' \
    | awk -v t="$2" 'index($0, t"(") == 1 { sub(/^.*\(/, ""); sub(/\).*$/, ""); s+=$0 } END {print s+0}'
}

malformed_declarations() { # <file> — count of declarations with no reason or no budget
  parse_declarations "$1" | grep -c '^bad|'
}

covered() { # <tool> <allowlist-file> — is <tool> granted? honors a trailing `*`
  local tool="$1" entry
  while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    case "$entry" in
      *\*) case "$tool" in "${entry%\*}"*) return 0 ;; esac ;;
      *)   [ "$tool" = "$entry" ] && return 0 ;;
    esac
  done < "$2"
  return 1
}

# audit <file> <allowlist-file> <label> — echoes counts as "violations declared stale
# redundant" and APPENDS its findings to the file named by $FINDINGS. It runs inside a
# command substitution, so a shell variable would be discarded with the subshell; a file
# is the only channel that survives, and a lost finding would make the count unreadable.
# A budget mismatch counts as a VIOLATION, not a separate class: an extra undeclared
# mention is the defect this file exists to catch, however it got there.
FINDINGS=""
note() { [ -n "$FINDINGS" ] && printf '%s\n' "$1" >> "$FINDINGS"; }
audit() {
  local file="$1" allow="$2" label="$3"
  local v=0 d=0 s=0 r=0 tool budget actual
  local -a mentioned=() declared=()
  while IFS= read -r tool; do [ -n "$tool" ] && mentioned+=("$tool"); done < <(mentions_of "$file")
  while IFS= read -r tool; do [ -n "$tool" ] && declared+=("$tool"); done < <(declared_of "$file")

  for tool in "${mentioned[@]-}"; do
    [ -n "$tool" ] || continue
    covered "$tool" "$allow" && continue
    if printf '%s\n' "${declared[@]-}" | grep -qxF "$tool"; then
      d=$((d+1))
      budget="$(declared_budget "$file" "$tool")"
      actual="$(mention_count "$file" "$tool")"
      if [ "$actual" != "$budget" ]; then
        v=$((v+1))
        note "        OVER BUDGET  ${label} names \`${tool}\` ${actual}x (body line(s) $(mention_lines "$file" "$tool")) but declares ${budget} — fold the new mention into the reason, or make it executable"
      fi
    else
      v=$((v+1))
      note "        UNAVAILABLE  ${label} names \`${tool}\` (body line(s) $(mention_lines "$file" "$tool")) — not in the allowlist, not declared"
    fi
  done
  for tool in "${declared[@]-}"; do
    [ -n "$tool" ] || continue
    if covered "$tool" "$allow"; then
      r=$((r+1))
      note "        REDUNDANT    ${label} declares \`${tool}\`, which IS in its allowlist"
    elif ! printf '%s\n' "${mentioned[@]-}" | grep -qxF "$tool"; then
      s=$((s+1))
      note "        STALE        ${label} declares \`${tool}\`, which it no longer names"
    fi
  done
  echo "$v $d $s $r"
}

TMP="$(mktemp -d "${TMPDIR:-/tmp}/toolallow.XXXXXX")"; trap 'rm -rf "$TMP"' EXIT
FINDINGS="$TMP/findings"; : > "$FINDINGS"

# ============================================================ 1. the shipped agents
AGENTS="$(find "$REPO/symlink/.claude/agents" -maxdepth 1 -type f -name '*.md' | sort)"
ok "shipped agent files found" "$([ -n "$AGENTS" ] && echo yes || echo no)" yes

V=0; D=0; S=0; R=0; SCANNED=0; SKIPPED=0
while IFS= read -r f; do
  [ -n "$f" ] || continue
  rel="${f#$REPO/}"
  if [ "$(has_tools_key "$f")" = no ]; then SKIPPED=$((SKIPPED+1)); continue; fi
  tools_of "$f" > "$TMP/allow"
  read -r v d s r <<<"$(audit "$f" "$TMP/allow" "$rel")"
  V=$((V+v)); D=$((D+d)); S=$((S+s)); R=$((R+r)); SCANNED=$((SCANNED+1))
  M=$(( $(malformed_declarations "$f") ))
  if [ "$M" -gt 0 ]; then
    note "        NO REASON    ${rel} has ${M} tool-mention declaration(s) without a reason"
    V=$((V+M))
  fi
done <<EOF
$AGENTS
EOF
ok "every shipped agent declares tools:" "$SKIPPED" 0
ok "shipped agents scanned"              "$([ "$SCANNED" -ge 8 ] && echo yes || echo no)" yes

# ====================================================== 2. the shared conventions docs
# `symlink/CONVENTIONS.md` — readers derived from the agent bodies that reference it.
# `seed/CLAUDE.md` — the instance-wide contract, so every restricted agent is a reader.
readers_of() { # <shared-doc-relpath> — agent files that read it
  case "$1" in
    symlink/CONVENTIONS.md)
      while IFS= read -r f; do
        [ -n "$f" ] || continue
        [ "$(has_tools_key "$f")" = yes ] || continue
        body "$f" | grep -q 'CONVENTIONS\.md' && echo "$f"
      done <<EOF
$AGENTS
EOF
      ;;
    seed/CLAUDE.md)
      while IFS= read -r f; do
        [ -n "$f" ] || continue
        [ "$(has_tools_key "$f")" = yes ] && echo "$f"
      done <<EOF
$AGENTS
EOF
      ;;
  esac
}

intersect_tools() { # <agent-file>... — the tools EVERY reader holds, one per line
  local first=1 f
  : > "$TMP/isect"
  for f in "$@"; do
    tools_of "$f" > "$TMP/one"
    if [ "$first" = 1 ]; then cp "$TMP/one" "$TMP/isect"; first=0
    else comm -12 <(sort "$TMP/isect") <(sort "$TMP/one") > "$TMP/isect.new"; mv "$TMP/isect.new" "$TMP/isect"; fi
  done
  cat "$TMP/isect"
}

SHARED_SCANNED=0
for rel in symlink/CONVENTIONS.md seed/CLAUDE.md; do
  f="$REPO/$rel"
  [ -f "$f" ] || { note "        MISSING      ${rel} not found"; V=$((V+1)); continue; }
  readers=(); while IFS= read -r r; do [ -n "$r" ] && readers+=("$r"); done < <(readers_of "$rel")
  if [ "${#readers[@]}" -eq 0 ]; then
    note "        NO READERS   ${rel} has no derived reader — the derivation broke"
    V=$((V+1)); continue
  fi
  intersect_tools "${readers[@]}" > "$TMP/allow.shared"
  read -r v d s r <<<"$(audit "$f" "$TMP/allow.shared" "$rel [∩ of ${#readers[@]} readers]")"
  V=$((V+v)); D=$((D+d)); S=$((S+s)); R=$((R+r)); SHARED_SCANNED=$((SHARED_SCANNED+1))
  M=$(( $(malformed_declarations "$f") ))
  if [ "$M" -gt 0 ]; then
    note "        NO REASON    ${rel} has ${M} tool-mention declaration(s) without a reason"
    V=$((V+M))
  fi
done
ok "shared conventions docs scanned" "$SHARED_SCANNED" 2

# The reader derivation must find the real set, or the intersection is meaningless.
CONV_READERS="$(readers_of symlink/CONVENTIONS.md | wc -l | tr -d ' ')"
ok "CONVENTIONS.md readers derived"  "$([ "$CONV_READERS" -ge 3 ] && echo yes || echo no)" yes

[ -s "$FINDINGS" ] && cat "$FINDINGS"
ok "no unavailable tool named"        "$V" 0
ok "no stale tool-mention"            "$S" 0
ok "no redundant tool-mention"        "$R" 0

# ================================================ 3. rung 2 still holds (the skip is safe)
# The shared review agents must keep declaring NO `tools:` key — that is what makes
# skill- and workflow-shaped capability reachable BY DISPATCH without widening any
# restricted allowlist (knowledge/findings/role-agents-cannot-invoke-skills.md, rung 2).
UNRESTRICTED="$(find "$REPO/config" -type f -path '*/agents/*.md' | sort)"
ok "shared review agents found" "$([ -n "$UNRESTRICTED" ] && echo yes || echo no)" yes
restricted=0
while IFS= read -r f; do
  [ -n "$f" ] || continue
  if [ "$(has_tools_key "$f")" = yes ]; then
    restricted=$((restricted+1)); printf '        NOW RESTRICTED %s grew a tools: key — it is no longer unconstrained\n' "${f#$REPO/}"
  fi
done <<EOF
$UNRESTRICTED
EOF
ok "shared review agents stay unrestricted" "$restricted" 0

# ==================================================== 4. non-vacuity: the checker bites
# Every case runs against synthetic fixtures under mktemp. A checker that only passes on
# good input would pass here too, so each guard is paired with the input it must reject.
FX="$TMP/fx"; mkdir -p "$FX"

fixture() { # <name> <tools-line-or-empty> <body>
  { printf -- '---\nname: %s\n' "$1"
    [ -n "$2" ] && printf 'tools: %s\n' "$2"
    printf -- '---\n%s\n' "$3"; } > "$FX/$1.md"
}
run_fx() { # <name> — echoes "violations declared stale redundant"
  : > "$FINDINGS"; tools_of "$FX/$1.md" > "$TMP/allow"; audit "$FX/$1.md" "$TMP/allow" "fx/$1"
}

# 4a. an undeclared mention of an absent tool is a violation.
fixture bad 'Read, Grep' 'For wide work, author a `Workflow` fan-out.'
read -r v d s r <<<"$(run_fx bad)"
ok "checker flags an absent tool"            "$v" 1

# 4b. the four prose words that fooled the first manual sweep must stay green — and so
# must a BACKTICKED `Task`, which is an OKF document type in this bundle, not a tool.
fixture prose 'Read, Grep' 'Never write to the bundle. The agent roster lists each agent.
Keep the workflow structure. Read the task document first, then edit the task file.
A skill is not a tool here; bash it out if you must.
Set the `Task` frontmatter, per the `Task` type in `SCHEMA.md`.'
read -r v d s r <<<"$(run_fx prose)"
ok "checker ignores prose (write/agent/workflow/task)" "$v" 0
ok "checker ignores the OKF \`Task\` type"     "$(printf '%s\n' "$(mentions_of "$FX/prose.md")" | grep -c '^Task$')" 0

# 4c. a backticked tool the agent DOES hold is green — the rule is possession, not the word.
fixture granted 'Read, Grep, Bash' 'Use `Bash` and `Read`; never `Grep` a whole repo blindly.'
read -r v d s r <<<"$(run_fx granted)"
ok "checker allows a granted tool"           "$v" 0

# 4d. a declaration with a reason AND a matching budget exempts the mention.
fixture declared 'Read, Grep' '<!-- tool-mention: Workflow(1) — named to record that it is absent; the route is sequential -->
You hold no `Workflow`, so wide work is sequential.'
read -r v d s r <<<"$(run_fx declared)"
ok "declaration exempts the mention"         "$v" 0
ok "declaration is counted"                  "$d" 1
ok "budget is parsed"                        "$(declared_budget "$FX/declared.md" Workflow)" 1

# 4e. THE BUDGET IS THE TEETH: one more mention than declared fails, so a declaration can
# never become a blanket waiver for the next author. This is the case the first version of
# this check got wrong — it passed while the original defect was re-introduced verbatim.
fixture overbudget 'Read, Grep' '<!-- tool-mention: Workflow(1) — one mention, deliberately -->
You hold no `Workflow`. But for wide work, author a `Workflow` fan-out anyway.'
read -r v d s r <<<"$(run_fx overbudget)"
ok "an extra mention breaks the budget"      "$v" 1
ok "...and is still counted as declared"     "$d" 1
# ...while a reworded file with the same number of mentions stays green.
fixture rewordedok 'Read, Grep' '<!-- tool-mention: Workflow(1) — one mention, deliberately -->
Completely different prose, still exactly one `Workflow`.'
read -r v d s r <<<"$(run_fx rewordedok)"
ok "rewording within budget stays green"     "$v" 0

# 4f. a declaration missing its reason, or missing its budget, is not a declaration.
fixture noreason 'Read, Grep' '<!-- tool-mention: Workflow(1) -->
You hold no `Workflow`.'
read -r v d s r <<<"$(run_fx noreason)"
ok "reasonless declaration does not exempt"  "$v" 1
ok "reasonless declaration is malformed"     "$(malformed_declarations "$FX/noreason.md")" 1
fixture nobudget 'Read, Grep' '<!-- tool-mention: Workflow — a reason, but no count to pin it to -->
You hold no `Workflow`.'
read -r v d s r <<<"$(run_fx nobudget)"
ok "budgetless declaration does not exempt"  "$v" 1
ok "budgetless declaration is malformed"     "$(malformed_declarations "$FX/nobudget.md")" 1

# 4g. a declaration for a tool no longer named is stale; one for a granted tool is redundant.
fixture stale 'Read, Grep' '<!-- tool-mention: Workflow(1) — the instruction it guarded was deleted -->
Nothing here names a tool.'
read -r v d s r <<<"$(run_fx stale)"
ok "checker flags a stale declaration"       "$s" 1
fixture redundant 'Read, Grep, Bash' '<!-- tool-mention: Bash(1) — pointless, Bash is granted -->
Use `Bash`.'
read -r v d s r <<<"$(run_fx redundant)"
ok "checker flags a redundant declaration"   "$r" 1

# 4h. MCP wildcards: a trailing `*` in the allowlist covers the whole prefix, nothing more.
fixture mcpok 'Read, mcp__claude-in-chrome__*' 'Call `mcp__claude-in-chrome__navigate`, then `mcp__claude-in-chrome__*` as needed.'
read -r v d s r <<<"$(run_fx mcpok)"
ok "wildcard covers its prefix"              "$v" 0
fixture mcpbad 'Read, mcp__claude-in-chrome__*' 'Call `mcp__other__thing`.'
read -r v d s r <<<"$(run_fx mcpbad)"
ok "wildcard does not cover another server"  "$v" 1

# 4i. no `tools:` key ⇒ unconstrained ⇒ nothing to flag, however it is phrased.
fixture inherits '' 'Invoke the `Skill` tool and author a `Workflow`.'
ok "no tools: key means no constraint"       "$(has_tools_key "$FX/inherits.md")" no

# 4j. the shared-doc rule: the intersection binds, so one reader lacking a tool is enough.
fixture reader_with_agent    'Agent, Read, Grep' 'x'
fixture reader_without_agent 'Read, Grep'        'x'
printf 'Dispatch `code-architect` with the `Agent` tool.\n' > "$FX/shared.md"
intersect_tools "$FX/reader_with_agent.md" "$FX/reader_without_agent.md" > "$TMP/allow.fx"
ok "intersection drops the unshared tool"    "$(grep -c '^Agent$' "$TMP/allow.fx")" 0
: > "$FINDINGS"; read -r v d s r <<<"$(audit "$FX/shared.md" "$TMP/allow.fx" "fx/shared")"
ok "shared doc flags a tool one reader lacks" "$v" 1
# ...and stays green once every reader holds it.
intersect_tools "$FX/reader_with_agent.md" "$FX/reader_with_agent.md" > "$TMP/allow.fx2"
: > "$FINDINGS"; read -r v d s r <<<"$(audit "$FX/shared.md" "$TMP/allow.fx2" "fx/shared")"
ok "shared doc green when all readers hold it" "$v" 0

printf '\n%s passed, %s failed  (%s agent file(s) + %s shared doc(s); %s declared mention(s))\n' \
  "$pass" "$fail" "$SCANNED" "$SHARED_SCANNED" "$D"
[ "$fail" -eq 0 ]
