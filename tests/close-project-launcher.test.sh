#!/usr/bin/env bash
#
# close-project-launcher.test.sh — `/ai-bridge:close-project` does its two preconditions
# and dispatches; steps 1-7 belong to one background agent, and the two human-gated
# branches stay in the main thread.
#
# WHY THIS IS A TEST AND NOT ONLY A CONVENTION — the same reason as its sibling
# pm-loop-launcher.test.sh, measured one command over. Owner-reported 2026-09-08, mid
# command: the closeout "takes way too long and it blocks the main thread". The
# `ai-bridge-2x` closeout that day took roughly a dozen main-thread tool calls before the
# folder step, and `prune-worktrees.sh` alone returned 29 REMOVABLE lines the main session
# had no use for — every byte of it in the context the human works in for the rest of the
# day, while an agent's context is discarded when it ends.
#
# The regression is invisible from reading either half alone, so both are asserted with
# the cross-reference each way: a reader deleting the launcher's steps can take the
# closeout with them, and a reader restoring "just the quick bit" to the launcher undoes
# the fix while the file still reads correctly. The mechanical form of that pair is at the
# bottom — the launcher half may run none of the closeout's commands and the brief half
# must run all of them.
#
# THE RULE IS AN ALLOWLIST, AND THAT IS WHAT THIS FILE COUNTS. An enumeration of forbidden
# nouns is the shape that already failed on the other launcher: it said it was closed, it
# was, and the next day's reads were a category it had never named. So the section is two
# allowed operations, everything else is the agent by category, and the assertion that
# fix lacked is here — the count fails when the list grows.
#
# WHAT IT DOES NOT ASSERT: the frontmatter. `allowed-tools` is documentation, not
# enforcement (measured twice, 2026-08-23 and 2026-09-08), and the closeout's own grants
# are unchanged by the split — so what is pinned is that the set did not GROW.
#
# ok() follows this directory's convention: it compares actual to expected.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SKILL="$REPO/plugin/skills/close-project/SKILL.md"
DISPATCH="$REPO/plugin/skills/dispatch/SKILL.md"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/closelaunch.XXXXXX")" || {
  echo "close-project-launcher.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp} — create that directory first." >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
ok() { # <name> <actual> <expected>
  if [ "$2" = "$3" ]; then printf '  PASS  %-62s (%s)\n' "$1" "$2"; pass=$((pass+1))
  else printf '  FAIL  %-62s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}
has() { grep -qF -- "$2" "$1" && echo yes || echo no; }

ok "the skill exists" "$([ -f "$SKILL" ] && echo yes || echo no)" yes

# --- the two halves, split at the brief's heading ---------------------------------
# LAUNCHER = everything the main session acts on; BRIEF = what the agent is handed.
# The frontmatter is NOT the launcher body: its grants are the closeout's and are
# asserted separately, so a script named there is not a step the launcher runs.
launcher() {
  awk 'NR==1 && $0=="---"{fm=1; next} fm && $0=="---"{fm=0; next} fm{next}
       /^## The closeout agent.s brief/{exit} {print}' "$SKILL"
}
brief()    { awk '/^## The closeout agent.s brief/{p=1} p' "$SKILL"; }
in_launcher() { launcher | grep -qF -- "$1" && echo yes || echo no; }
in_brief()    { brief    | grep -qF -- "$1" && echo yes || echo no; }
ok "both halves are present" \
  "$([ -n "$(launcher)" ] && [ -n "$(brief)" ] && echo yes || echo no)" yes

# --- the launcher's preconditions are a closed list of two ------------------------
count_preconditions() { # <file>
  awk '/^## Preconditions/{p=1;next} p&&/^#/{p=0} p&&/^[0-9]+\. /{n++} END{print n+0}' "$1"
}
ok "preconditions listed" "$(count_preconditions "$SKILL")" 2
ok "…1 is the slug"       "$(in_launcher '**A slug.**')" yes
ok "…2 is the folder"     "$(in_launcher '**The folder exists.**')" yes
# Listing the CLOSE CANDIDATES was the old behaviour and it is a state read: it opens
# every task document to judge terminality, which is step 1's job, in the agent.
ok "…and the slug prompt reads names, not documents" \
  "$(in_launcher 'never open one to judge')" yes

# --- allowed-tools did not GROW ---------------------------------------------------
grants() { # <file> -> one grant per line
  awk '/^---$/{d++; next} d==1 && /^allowed-tools:/{sub(/^allowed-tools:[[:space:]]*/,""); print}' "$1" \
    | tr ',' '\n' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | grep -v '^$'
}
# The closeout's own grants, verbatim as they stood before the split. The criterion is
# "no NEW grant ships", so this is an equality and a widening is what fails it.
EXPECTED_GRANTS='Bash(date:*)
Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/commit-as.sh:*)
Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/close-project-folder.sh:*)
Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/decision-stamp.sh:*)
Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/prune-worktrees.sh:*)
Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/validate-bundle.sh:*)
Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/build-kb-index.sh:*)
Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/papercuts.sh:*)
Bash(grep:*)
Bash(git rm:*)
Bash(git add:*)
Bash(git log:*)
Bash(ls:*)
Read
Write
Edit
Glob
Agent'
ok "allowed-tools is unchanged by the split" "$(grants "$SKILL")" "$EXPECTED_GRANTS"
ok "…and Agent was already among them, so no new grant ships" \
  "$(grants "$SKILL" | grep -cx 'Agent' | tr -d ' ')" 1
# NON-VACUITY: a widened list must fail the equality above.
printf -- '---\nallowed-tools: Bash(ls:*), Agent, Bash(curl:*)\n---\nbody\n' > "$TMP/wide.md"
ok "…and a widened list is NOT equal to it" \
  "$([ "$(grants "$TMP/wide.md")" != "$EXPECTED_GRANTS" ] && echo yes || echo no)" yes

# --- the launcher says, in the file, that it reads nothing else -------------------
ok "launcher carries the closed-list rule" "$(has "$SKILL" 'The launcher reads nothing else')" yes
section() { awk '/^### The launcher reads nothing else/{p=1;next} p&&/^#/{p=0} p' "$1"; }
in_section() { section "$SKILL" | grep -qF -- "$1" && echo yes || echo no; }

count_allowed_ops() { section "$1" | grep -c -E '^[0-9]+\. ' | tr -d ' '; }
ok "the allowlist is exactly two operations" "$(count_allowed_ops "$SKILL")" 2
ok "…op 1 is the slug"          "$(in_section '**The slug**')" yes
ok "…op 2 is the folder probe"  "$(in_section '**The folder probe**')" yes
# NON-VACUITY, and it IS the property: a THIRD allowed operation must fail this check.
printf -- '### The launcher reads nothing else — an ALLOWLIST of two\n\n1. slug\n2. folder\n3. just a quick orient\n\n## Next\n' > "$TMP/third.md"
ok "…and a THIRD allowed operation fails it" \
  "$( [ "$(count_allowed_ops "$TMP/third.md")" -ne 2 ] && echo yes || echo no )" yes
printf -- '### The launcher reads nothing else — an ALLOWLIST of two\n\n1. slug\n2. folder\n\n## Next\n' > "$TMP/two.md"
ok "…while exactly two still passes" "$(count_allowed_ops "$TMP/two.md")" 2

# THE CATEGORY, not an enumeration — this is the durable half. A list of forbidden nouns
# closes over the nouns it named and nothing else, which is how the sibling launcher's
# closed list rotted; this one closes over "existence, never state".
ok "…stated as a category, not a list" "$(in_section 'is the CLOSEOUT AGENT or a SUBAGENT')" yes
ok "…naming the category itself"       "$(in_section 'A directory name is existence')" yes
ok "…and that it is a category"        "$(in_section 'it is a **category**')" yes
ok "…naming the agent as the disposal" "$(in_section 'dispatch the agent and let it read')" yes
ok "…and the subagent as the other"    "$(in_section '**background subagent**')" yes
ok "…closing the list against analogy" "$(in_section 'No other reader may be added by analogy')" yes
ok "…keeping the cost argument"        "$(in_section "main session's context")" yes
ok "…and saying the frontmatter is not the enforcement" \
  "$(in_section 'documentation, not enforcement')" yes

# THE ENUMERATION OF FORBIDDEN NOUNS IS NOT KEPT BESIDE THE ALLOWLIST. Keeping both is
# how the list nobody can complete survives the inversion that replaced it.
nouns_named() { # <file> -> count of blocklist-shaped nouns in that section
  section "$1" \
    | grep -o -E 'log\.md|project\.md|tasks/\*\.md|depends_on|prune-worktrees\.sh|validate-bundle\.sh|git rm|git log|gh pr list|worktree listing' \
    | sort -u | wc -l | tr -d ' '
}
ok "the blocklist of nouns is gone" "$(nouns_named "$SKILL")" 0
printf -- '### The launcher reads nothing else\n\nDo not read `log.md` or run `gh pr list`.\n\n## Next\n' > "$TMP/nouns.md"
ok "…and the check sees nouns that ARE there" \
  "$( [ "$(nouns_named "$TMP/nouns.md")" -ge 1 ] && echo yes || echo no )" yes

# ONE CONTRACT, TWO LAUNCHERS. The two must not diverge into two rules, so each names the
# same heading and this file asserts the pointer as well as the shape.
ok "…pointing at the other launcher" "$(in_section 'skills/dispatch/SKILL.md')" yes
ok "the other launcher still carries the same heading" \
  "$(has "$DISPATCH" 'The launcher reads nothing else')" yes
ok "…and states its own list as an ALLOWLIST" "$(has "$DISPATCH" 'is an ALLOWLIST of')" yes

# --- the saving is a MEASUREMENT, not a claim ------------------------------------
ok "the measurement ships: the main-thread calls" "$(in_launcher 'dozen main-thread tool calls')" yes
ok "…and the 29 REMOVABLE lines"                  "$(in_launcher '29 `REMOVABLE` lines')" yes
ok "…dated"                                       "$(in_launcher '2026-09-08')" yes

# --- ONE background agent runs steps 1-7 -----------------------------------------
ok "it dispatches one fresh agent"     "$(in_launcher 'one fresh `ai-bridge:project-manager`')" yes
ok "…namespaced, because a bare name does not resolve" \
  "$(in_launcher 'a bare agent name does not resolve')" yes
ok "…in the background"                "$(in_launcher 'in the background')" yes
ok "…for steps 1-7"                    "$(in_launcher 'one background agent for steps 1–7')" yes
ok "…never resumed"                    "$(in_launcher 'Never wake a completed')" yes
ok "…on its resolved model"            "$(in_launcher 'scripts/resolve-model.sh project-manager')" yes
# A closeout is not a tick: it runs once, is not idempotent, and takes no tick lock.
ok "…briefed that a closeout is NOT a tick" "$(in_launcher 'A closeout is NOT a tick')" yes
ok "…taking no tick lock"                   "$(in_launcher 'takes **no tick lock**')" yes

# --- the two human-gated branches stay in the MAIN thread ------------------------
ok "both decisions are named as the thread's" \
  "$(in_launcher 'Two decisions never leave this thread')" yes
ok "…step 4's objective question"  "$(in_launcher 'set it `achieved`?')" yes
ok "…step 6's cancelled-source question" "$(in_launcher 'is the dependent work still')" yes
# The hazard the ordering closes: an escalation from the middle of a closeout strands a
# half-written tree the next tick reads as real work. So both are settled BEFORE any write.
ok "…settled before any write"     "$(in_launcher 'BEFORE the agent writes anything')" yes
ok "…and the agent stops having written nothing" \
  "$(in_brief 'write nothing —')" yes
ok "the brief tests both in its pre-flight" \
  "$(in_brief '**Both escalations, before any write — the pre-flight.**')" yes
ok "…and never decides either"      "$(in_brief 'Neither is ever yours to decide')" yes
ok "step 4 defers the objective to the human" "$(in_brief 'the objective question is the human')" yes
ok "step 6 defers the cancelled source too"   "$(in_brief 'never decide it yourself')" yes

# --- the cataloguer nests under the CLOSEOUT AGENT, not the main session ---------
ok "the cataloguer is dispatched from the brief" "$(in_brief 'Dispatch the `cataloguer`')" yes
ok "…and is said to nest under the agent"        "$(in_brief 'It nests under YOU, not under the main session')" yes
ok "…so the main thread carries neither the pass nor its reads" \
  "$(in_brief 'thrown away with yours')" yes
ok "the launcher dispatches no cataloguer itself" \
  "$(launcher | grep -c 'cataloguer' | tr -d ' ')" 0

# --- the authority boundaries hold, and are SHIPPED TEXT -------------------------
ok "the agent never promotes and never merges" \
  "$(in_launcher 'draft → ready` and never merges a pull request')" yes
ok "…citing the two human authorities" "$(in_launcher 'Two human')" yes
ok "…and repeated where the agent reads it" "$(in_brief 'never merged a pull request')" yes
# The one hole every guard exempts: `commit-as.sh human` skips the promotion-authority
# check and the explicit-path requirement, so an agent must not commit under it.
ok "…and it never commits as the human" "$(in_launcher 'never commits as the')" yes
ok "the closing commit is authored project-manager" \
  "$(in_brief 'commit-as.sh project-manager "chore: close <slug> project"')" yes
ok "…and says why the human role is not available to it" "$(in_brief 'every guard trusts')" yes
ok "…while the log entry still names the human" "$(in_brief 'The login is the human')" yes

# --- the cross-reference each way, and the mechanical split ----------------------
ok "launcher points at the brief" "$(in_launcher 'The closeout agent')" yes
ok "brief points back at the launcher's rule" \
  "$(in_brief 'The launcher reads nothing else')" yes

# THE PAIR, MECHANICALLY. Every command the closeout runs must be in the BRIEF and in
# none of the launcher. Matching the RUNNABLE form (`${CLAUDE_PLUGIN_ROOT}/scripts/...`)
# and not the bare name is deliberate: the measurement above names `prune-worktrees.sh`
# as prose, which is a citation and not a step.
for s in close-project-folder prune-worktrees validate-bundle build-kb-index papercuts commit-as decision-stamp; do
  ok "the brief runs $s.sh" \
    "$(brief | grep -qF "\${CLAUDE_PLUGIN_ROOT}/scripts/$s.sh" && echo yes || echo no)" yes
  ok "…and the launcher does not" \
    "$(launcher | grep -cF "\${CLAUDE_PLUGIN_ROOT}/scripts/$s.sh" | tr -d ' ')" 0
done
# …and the folder step itself, the one irreversible line, is nowhere near the launcher.
ok "the launcher never applies the folder step" "$(in_launcher '--apply')" no
ok "…while the brief does"                      "$(in_brief '<slug> --apply')" yes
# NON-VACUITY for the two absence checks: each must FIND what it looks for when it is there.
printf -- '## Launcher\n\nrun ${CLAUDE_PLUGIN_ROOT}/scripts/validate-bundle.sh --apply\n\n## The closeout agent'"'"'s brief\n\nbody\n' \
  > "$TMP/leaky.md"
ok "the split checker sees a leaked command" \
  "$(awk '/^## The closeout agent.s brief/{exit} {print}' "$TMP/leaky.md" \
     | grep -cF '${CLAUDE_PLUGIN_ROOT}/scripts/validate-bundle.sh' | tr -d ' ')" 1

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
