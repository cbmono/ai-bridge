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
# WHICH FILES ARE SCANNED IS DERIVED, NOT LISTED. The first version named two shared docs
# by hand (`symlink/CONVENTIONS.md`, `seed/CLAUDE.md`) and so could only ever check the
# two someone remembered — `symlink/SCHEMA.md`'s browser-access section named
# `mcp__claude-in-chrome__*` to five readers whose intersection is `Bash Glob Grep Read`,
# and the check was
# silent because the file was not on the list. A doc addresses an agent when an agent is
# TOLD TO READ IT, so that is what is derived: every `*.md` reference in a restricted
# agent's body, resolved against the trees this repo ships (`symlink/`, then `seed/`).
# Adding a doc reference to an agent body therefore puts the doc in scope by itself.
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

# =================================================================== THE LEXICON
# ONE place classifies every identifier this check reasons about, and it has two halves
# because a name is either a harness tool or it is not. Both halves are maintained here
# and nowhere else.
#
# WHY THIS IS NOT JUST A CLOSED LIST ANY MORE. It was, and the closed list leaked in the
# one direction that cannot be seen: a tool absent from `VOCAB` is not "prose", it is
# INVISIBLE — the check passes, which is indistinguishable from there being nothing to
# find. That is the same shape as the defect this whole file exists to catch, one level
# up. `AskUserQuestion`, `ExitWorktree` and `Artifact` were all missing at once; `Artifact`
# was found only because a PM tick happened to start granting it. So the list is now
# pinned from BOTH sides by two guards below, and neither is a count:
#
#   GUARD A (§0a) — every tool GRANTED by a shipped agent's `tools:` list must appear in
#   `VOCAB`. The bundle adopts a new harness tool by granting it, so this is the moment a
#   new tool exists here at all, and the lexicon fails until it is told. This is the guard
#   that would have caught `Artifact` on the commit that granted it, before any prose.
#
#   GUARD B (§0b) — a backticked MULTI-WORD CamelCase identifier in a scanned file that is
#   in NEITHER half FAILS as unclassified. So an unrecognised name is loud, not ignored.
#
# WHY GUARD B IS SCOPED TO MULTI-WORD CamelCase, WHICH IS THE WHOLE DESIGN. Measured over
# the derived scanned set: backticked identifiers starting with a capital that are NOT
# tools number 18 distinct names and 60-odd mentions — `Finding`, `Service`, `Runbook`,
# `Team`, `Reference` and `Project` (OKF document types), `APPROVED`, `DISMISSED`, `KEEP`,
# `RECLAIMABLE`, `STALE`, `TICK` (literal output tokens), `HEAD`, `Makefile`. Failing on
# all of those is the cry-wolf failure that gets a check deleted. Restrict to two or more
# capitalised words joined with no separator and the same measurement returns exactly TWO
# non-tools — `SessionStart` and `EnterWorktree` (a tool) — while still covering
# `AskUserQuestion`, `ExitWorktree`, `MultiEdit`, `NotebookEdit`, `BashOutput`,
# `SlashCommand`, `ExitPlanMode`, `TodoWrite`, `ToolSearch`, `WebFetch`, `WebSearch`,
# `KillShell`, `KillBash`: every multi-word tool name the harness has, and the shape a new
# one takes. The single-word residue (`Read`, `Edit`, `Skill`, `Artifact`) is exactly where
# the noun collisions live, and Guard A is what covers it.
#
# `Task` is DELIBERATELY EXCLUDED from `VOCAB` even though it is the dispatch tool's name
# in some harness versions: OKF's own document type is also `Task`, and this bundle
# backticks that type constantly (`symlink/SCHEMA.md:441`, `docs/schema.md:27`,
# `new-project.md:58`). Including it would flag the bundle's core vocabulary as a tool
# reference. `Agent` is the name that decides dispatch here and carries no such collision.
# `Artifact` is on the list because a PM tick publishes the board with it; the collision
# it has to survive is OKF's `artifacts:` field, and it does — that is lowercase and
# plural, and a mention only counts inside backticks as this exact identifier.
VOCAB='Agent|Artifact|AskUserQuestion|Workflow|Skill|Read|Write|Edit|MultiEdit|NotebookEdit|Glob|Grep|Bash|BashOutput|KillShell|KillBash|WebFetch|WebSearch|TodoWrite|ToolSearch|SlashCommand|ExitPlanMode|EnterWorktree|ExitWorktree|mcp__[A-Za-z0-9_*-]+'
MENTION_RE="\`($VOCAB)\`"

# The other half of the lexicon: multi-word CamelCase identifiers this bundle backticks
# that are NOT tools, so Guard B stays quiet on them. Claude Code's hook EVENTS are the
# whole family — they read exactly like tool names and are named all over the machinery
# docs — so all of them are listed, not only the one measured in the tree today, because
# the next one to be documented must not turn into a build failure for a maintainer who
# has no way to know why. Add a name here ONLY after checking it is not a tool.
NOT_A_TOOL='SessionStart|SessionEnd|UserPromptSubmit|PreToolUse|PostToolUse|SubagentStart|SubagentStop|PreCompact|InstructionsLoaded|Notification'
CAMEL_RE='`[A-Z][a-z0-9]+([A-Z][a-z0-9]*)+`'

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

# ------------------------------------------------------- the lexicon's two classifiers
in_vocab() { # <name> — is this a harness tool name? (echoes yes/no)
  printf '%s\n' "$1" | grep -qxE "$VOCAB" && echo yes || echo no
}

unclassified_camel() { # <file> — backticked multi-word CamelCase names in neither half
  body "$1" | grep -oE "$CAMEL_RE" | tr -d '`' | sort -u \
    | grep -vxE "$VOCAB" | grep -vxE "$NOT_A_TOOL"
}

# THE CONDITION THAT DECIDES THE OUTCOME, and the reason this is not a count.
#
# A declaration says "this file names a tool a reader lacks, deliberately". What makes
# that legitimate is never HOW MANY times it does so — it is that the prose STATES THE
# ABSENCE instead of instructing the use. The budget `(N)` cannot see the difference, so
# a reword holding the count constant could swap an honest statement of absence for a
# live instruction and stay green: `tests/` measured the gap and the harness even
# asserted it ("rewording within budget stays green"). The budget is kept — it still
# catches an ADDED mention, which is a different hole — but it is no longer what decides.
#
# So each mention of a declared, unheld tool must SAY SOMETHING ABOUT POSSESSION. The cue
# list below is the presence/absence vocabulary these docs actually use, matched over the
# mention's line and its two neighbours so ordinary reflowing prose does not break it.
# Checked against all ten declared mention sites in the tree, which pass on: "**No role
# agent's allowlist contains `Workflow`**", "you hold neither `Workflow` nor `Agent`",
# "you cannot fan out", "only `qa-reviewer` holds `Agent`", "don't rely on the
# `EnterWorktree` tool", "no restricted role agent holds `Skill`", "the
# `mcp__claude-in-chrome__*` tools are actually present".
#
# `if` IS DELIBERATELY NOT A CUE, and that exclusion is the point of the whole rule: the
# original defect was "dispatch `code-architect` **if it's installed**", a condition on
# INSTALLATION that reads as satisfied while deciding nothing. Accepting `if` would bless
# it. A cue has to be about possession, not about a condition.
#
# A NEGATIVE contraction is spelled out rather than stemmed, and the difference matters:
# a stem of `can` would accept "you **can** author a `Workflow`", which is the instruction
# this rule exists to reject. Only `can't` counts. (Every apostrophe in the scanned set is
# the straight one; the curly form is accepted so a later editor cannot break the check by
# smartening quotes.)
#
# RESIDUAL GAP, stated honestly: this is a lexical test, so a directive sentence that
# happens to contain a cue word passes — a neighbouring line's "only" covered one of the
# two mentions in the mutation run below, though the other still failed and one is enough.
# It is strictly stronger than the count it backs up, rejecting every re-arming reword
# measured including the verbatim original defect, and a per-mention marker was rejected
# upstream as too brittle for reflowing prose.
ABSENCE_CUE='(^|[^a-z])([Nn]o|[Nn]ot|[Nn]one|[Nn]ever|[Nn]either|[Nn]or|[Cc]annot|[Cc]an['"'"'’]t|[Dd]on['"'"'’]t|[Dd]oesn['"'"'’]t|[Ww]on['"'"'’]t|[Ii]sn['"'"'’]t|[Aa]ren['"'"'’]t|[Hh]old|[Hh]olds|[Hh]olding|[Ll]ack|[Ll]acks|[Ll]acking|[Aa]bsent|[Aa]bsence|[Ww]ithout|[Uu]navailable|[Aa]vailable|[Mm]issing|[Dd]ead|[Uu]nexecutable|[Oo]nly|[Pp]resent|[Gg]rant|[Gg]ranted|[Gg]ranting|allowlist)([^a-z]|$)'

mentions_without_absence() { # <file> <tool> — body line numbers whose window states none
  # The declaration's own reason is blanked (not removed — line numbers must still line up
  # with the other reports), because a cue written inside the waiver would let the waiver
  # vouch for itself. The absence has to be stated in the PROSE a reader reads.
  body "$1" | sed -E 's/<!--[[:space:]]*tool-mention:[^>]*-->//' > "$TMP/mwa.body"
  grep -nF "\`$2\`" "$TMP/mwa.body" | cut -d: -f1 | while IFS= read -r n; do
    lo=$(( n > 1 ? n - 1 : 1 ))
    sed -n "${lo},$(( n + 1 ))p" "$TMP/mwa.body" | tr '\n' ' ' \
      | grep -qE "$ABSENCE_CUE" || printf '%s\n' "$n"
  done
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
  local v=0 d=0 s=0 r=0 tool budget actual silent unknown
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
      # The deciding condition, not the count: a declared mention has to state the
      # absence. A reword that keeps `budget` intact but turns the sentence back into an
      # instruction fails here, which is the hole the budget alone could not see.
      silent="$(mentions_without_absence "$file" "$tool" | paste -sd, - 2>/dev/null)"
      if [ -n "$silent" ]; then
        v=$((v+1))
        note "        NOT AN ABSENCE ${label} names \`${tool}\` at body line(s) ${silent} without saying anywhere near it that a reader may not hold it — a declaration covers a STATEMENT of absence, never an instruction to use the tool"
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
  # GUARD B. A backticked multi-word CamelCase name in neither half of the lexicon is not
  # "prose that happens to look like a tool" — it is a name nobody has classified, and the
  # closed list's whole failure mode was treating that case as silence.
  while IFS= read -r unknown; do
    [ -n "$unknown" ] || continue
    v=$((v+1))
    note "        UNCLASSIFIED ${label} names \`${unknown}\` (body line(s) $(mention_lines "$file" "$unknown")) — in neither half of the lexicon. Add it to VOCAB if it is a harness tool, to NOT_A_TOOL if it is not; do not leave it unclassified, because silence here is what let AskUserQuestion and Artifact through"
  done < <(unclassified_camel "$file")
  echo "$v $d $s $r"
}

TMP="$(mktemp -d "${TMPDIR:-/tmp}/toolallow.XXXXXX")"; trap 'rm -rf "$TMP"' EXIT
FINDINGS="$TMP/findings"; : > "$FINDINGS"

# ============================================================ 1. the shipped agents
AGENTS="$(find "$REPO/symlink/.claude/agents" -maxdepth 1 -type f -name '*.md' | sort)"
ok "shipped agent files found" "$([ -n "$AGENTS" ] && echo yes || echo no)" yes

# GUARD A. The `tools:` lists are the single maintained source the lexicon is pinned to:
# a harness tool becomes real HERE the moment an agent is granted it, so a granted name
# the lexicon does not know is a tool nobody told this file about. It is the guard that
# closes the closed list from the side nobody can see — had it existed, `Artifact` would
# have failed on the commit that granted it to `project-manager`, instead of being noticed
# later by a reviewer reading prose.
UNKNOWN_GRANTS=0
while IFS= read -r f; do
  [ -n "$f" ] || continue
  while IFS= read -r t; do
    [ -n "$t" ] || continue
    # A grant may be scoped — `Bash(git:*)` is the same tool as `Bash`, and failing on the
    # scope would be a spurious build break rather than a missing lexicon entry.
    t="${t%%(*}"
    if [ "$(in_vocab "$t")" = no ]; then
      UNKNOWN_GRANTS=$((UNKNOWN_GRANTS+1))
      printf '        GRANTED, UNKNOWN  %s grants `%s`, absent from VOCAB — add it, or this file cannot see a mention of it\n' "${f#$REPO/}" "$t"
    fi
  done < <(tools_of "$f")
done <<EOF
$AGENTS
EOF
ok "every granted tool is in the lexicon" "$UNKNOWN_GRANTS" 0

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

# =============================================== 2. the shared docs an agent is told to read
# DERIVED, NOT LISTED. Two paths used to be hardcoded here, and a hardcoded list can only
# check what someone remembered to add — `symlink/SCHEMA.md` named a browser MCP tool to
# five readers who mostly cannot hold it, and was simply not looked at. So the set is the
# `*.md` references in the restricted agents' own bodies, resolved against the trees this
# repo ships. Adding a doc reference to an agent puts that doc in scope by itself, which
# is the same self-tightening property the reader derivation below already had.
doc_refs_of() { # <agent-file> — every `*.md` reference in its body, normalised
  body "$1" | grep -oE '[A-Za-z0-9_./-]*[A-Za-z0-9_-]\.md' \
    | sed -E 's#^(\.\./)+##; s#^/+##' | sort -u
}

resolve_doc() { # <reference> — repo-relative path of the shipped doc, or nothing
  local ref="$1" cand
  for cand in "symlink/$ref" "seed/$ref"; do
    # An agent file is audited against its OWN allowlist in §1, never as a shared doc, and
    # a slash command is run by the main session, which holds every tool and so cannot
    # have this defect. Both are skipped by path rather than by name.
    case "$cand" in symlink/.claude/agents/*|symlink/.claude/commands/*) continue ;; esac
    [ -f "$REPO/$cand" ] && { printf '%s\n' "$cand"; return 0; }
  done
  return 1
}

shared_docs() { # — every shipped doc a restricted agent is told to read
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    [ "$(has_tools_key "$f")" = yes ] || continue
    while IFS= read -r ref; do
      [ -n "$ref" ] && resolve_doc "$ref"
    done < <(doc_refs_of "$f")
  done <<EOF
$AGENTS
EOF
}

readers_of() { # <shared-doc-relpath> — agent files that read it
  # `seed/CLAUDE.md` is the instance-wide contract: it is loaded into EVERY session
  # whether or not an agent body names it, so every restricted agent is a reader and the
  # intersection must not be widened by deriving a smaller set. Every other doc is read by
  # exactly the agents that point at it.
  local doc="$1" f ref
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    [ "$(has_tools_key "$f")" = yes ] || continue
    if [ "$doc" = seed/CLAUDE.md ]; then printf '%s\n' "$f"; continue; fi
    while IFS= read -r ref; do
      [ -n "$ref" ] || continue
      [ "$(resolve_doc "$ref")" = "$doc" ] && { printf '%s\n' "$f"; break; }
    done < <(doc_refs_of "$f")
  done <<EOF
$AGENTS
EOF
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

SHARED_DOCS="$(shared_docs | sort -u)"
SHARED_SCANNED=0
while IFS= read -r rel; do
  [ -n "$rel" ] || continue
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
done <<EOF
$SHARED_DOCS
EOF
ok "shared docs scanned" "$([ "$SHARED_SCANNED" -ge 5 ] && echo yes || echo no)" yes

# The DERIVATION is the check here, so name the docs it must reach. The first two are what
# the hardcoded list used to hold; `symlink/SCHEMA.md` is the one it missed, and naming it
# means a derivation that silently narrows back to the old pair fails instead of passing.
for must in symlink/CONVENTIONS.md seed/CLAUDE.md symlink/SCHEMA.md; do
  ok "derived set reaches $must" "$(printf '%s\n' "$SHARED_DOCS" | grep -cxF "$must")" 1
done

# The reader derivation must find the real set, or the intersection is meaningless.
CONV_READERS="$(readers_of symlink/CONVENTIONS.md | wc -l | tr -d ' ')"
ok "CONVENTIONS.md readers derived"  "$([ "$CONV_READERS" -ge 3 ] && echo yes || echo no)" yes
SCHEMA_READERS="$(readers_of symlink/SCHEMA.md | wc -l | tr -d ' ')"
ok "SCHEMA.md readers derived"       "$([ "$SCHEMA_READERS" -ge 3 ] && echo yes || echo no)" yes

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
# 4e-bis. THE BUDGET IS NOT WHAT DECIDES, and this pair is the proof. Both fixtures
# declare `Workflow(1)` and both name it exactly once, so the count cannot separate them —
# and the count is precisely what a reword holds constant. What separates them is whether
# the prose STATES THE ABSENCE or ISSUES AN INSTRUCTION, so that is what is asserted.
fixture reworded_absence 'Read, Grep' '<!-- tool-mention: Workflow(1) — one mention, deliberately -->
Prose rewritten from scratch: fanning out is not open to you, since no role agent
is granted `Workflow`. Work through the edges in sequence and say so in the PR body.'
read -r v d s r <<<"$(run_fx reworded_absence)"
ok "reword that still states the absence is green" "$v" 0
ok "...and its count is unchanged"            "$(mention_count "$FX/reworded_absence.md" Workflow)" 1
# The same file, same declaration, SAME COUNT — reworded into an instruction. This is the
# mutation the reported gap was about, and it must fail.
fixture reworded_directive 'Read, Grep' '<!-- tool-mention: Workflow(1) — one mention, deliberately -->
Prose rewritten from scratch: for wide, independent work, author a `Workflow` fan-out
and let each subagent take one edge, then synthesize the results yourself.'
read -r v d s r <<<"$(run_fx reworded_directive)"
ok "reword into an instruction fails"        "$v" 1
ok "...on the same count as the green one"   "$(mention_count "$FX/reworded_directive.md" Workflow)" 1
ok "...and its budget still matches"         "$(declared_budget "$FX/reworded_directive.md" Workflow)" 1
# And the verbatim original defect — a condition on INSTALLATION, which reads as satisfied
# and decides nothing — is rejected too, which is why `if` is not an absence cue.
fixture reworded_installed 'Read, Grep' '<!-- tool-mention: Agent(1) — one mention, deliberately -->
Self-review your diff: dispatch `code-architect` with the `Agent` tool if it is installed
in the usual location, else do a careful pass yourself.'
read -r v d s r <<<"$(run_fx reworded_installed)"
ok "the installation-conditioned defect fails" "$v" 1
# A cue has to be NEGATIVE. "you can" is a permission, so it must not clear the mention,
# while "you can't" must — the pair that decides whether the cue list is stemmed or spelt
# out, and a stemmed `can` accepts the exact instruction the rule exists to reject.
fixture reworded_can 'Read, Grep' '<!-- tool-mention: Workflow(1) — one mention, deliberately -->
For wide work you can author a `Workflow` fan-out and split the edges between subagents.'
read -r v d s r <<<"$(run_fx reworded_can)"
ok "a permission is not an absence"          "$v" 1
fixture reworded_cant 'Read, Grep' '<!-- tool-mention: Workflow(1) — one mention, deliberately -->
For wide work you can'"'"'t author a `Workflow` fan-out, so take the edges in sequence.'
read -r v d s r <<<"$(run_fx reworded_cant)"
ok "...but its negation is"                   "$v" 0

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

# 4k. GUARD A's classifier, on both answers. The tree-wide assertion above reads 0 today,
# which is exactly the shape that cannot tell "nothing to find" from "not looking", so the
# classifier is exercised directly: a real tool is known, an invented one is not, and the
# three names this task was dispatched to close are known now.
ok "lexicon knows a granted tool"            "$(in_vocab Artifact)" yes
ok "lexicon knows the MCP wildcard grant"    "$(in_vocab 'mcp__claude-in-chrome__*')" yes
ok "lexicon rejects an invented tool"        "$(in_vocab SummonDragon)" no
for t in AskUserQuestion ExitWorktree Artifact; do
  ok "lexicon now knows \`$t\`"              "$(in_vocab "$t")" yes
done
# The OKF document type must still NOT be a tool — the collision that keeps `Task` out.
ok "lexicon still rejects the OKF type"      "$(in_vocab Task)" no

# 4l. GUARD B: an unclassified multi-word CamelCase name FAILS instead of being ignored.
# This is the hole itself — before this guard, `AskUserQuestion` in an agent body produced
# silence, which is indistinguishable from a clean file.
fixture unknowntool 'Read, Grep' 'When you need the human, ask via `AskUserQuestion` and wait.'
read -r v d s r <<<"$(run_fx unknowntool)"
ok "a name missing from the lexicon is not silent" "$([ "$v" -ge 1 ] && echo yes || echo no)" yes
fixture invented 'Read, Grep' 'Escalate by calling `SummonDragon` on the failing job.'
read -r v d s r <<<"$(run_fx invented)"
ok "an unclassified CamelCase name fails"    "$v" 1
ok "...and is reported as unclassified"      "$(unclassified_camel "$FX/invented.md")" SummonDragon
# ...while the non-tool half of the lexicon keeps it quiet, and single capitalised words
# are left alone deliberately: 18 of them in this tree are OKF types and output tokens.
fixture hookevent 'Read, Grep' 'The `SessionStart` hook injects the queue; `PreToolUse` gates a call.'
read -r v d s r <<<"$(run_fx hookevent)"
ok "a declared non-tool stays quiet"         "$v" 0
fixture okftypes 'Read, Grep' 'Write a `Finding`, cite a `Service`, link a `Runbook`, name a `Team`.
The verdict prints `APPROVED` or `DISMISSED`; a worktree may be `RECLAIMABLE`.'
read -r v d s r <<<"$(run_fx okftypes)"
ok "single capitalised words are not tools"  "$v" 0

# 4m. the DERIVED scanned set: resolution is what decides which files are looked at, so
# assert the resolver rather than only the list it produced.
ok "resolves a symlink/ doc"                 "$(resolve_doc SCHEMA.md)" symlink/SCHEMA.md
ok "falls through to seed/ for CLAUDE.md"    "$(resolve_doc CLAUDE.md)" seed/CLAUDE.md
ok "an instance-only doc resolves to nothing" "$(resolve_doc AWAITING.md)" ""
ok "an agent file is never a shared doc"     "$(resolve_doc .claude/agents/qa-reviewer.md)" ""
ok "a slash command is never a shared doc"   "$(resolve_doc .claude/commands/pm-loop.md)" ""
# Agent bodies write `../../CONVENTIONS.md`, so the reference normaliser is load-bearing:
# without it the file this whole check was built for leaves the derived set silently.
ok "the ../.. reference an agent writes normalises" \
  "$(doc_refs_of "$REPO/symlink/.claude/agents/software-engineer.md" | grep -cx 'CONVENTIONS.md')" 1

printf '\n%s passed, %s failed  (%s agent file(s) + %s shared doc(s); %s declared mention(s))\n' \
  "$pass" "$fail" "$SCANNED" "$SHARED_SCANNED" "$D"
[ "$fail" -eq 0 ]
