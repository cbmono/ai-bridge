#!/usr/bin/env bash
#
# review-route.test.sh — the CodeRabbit-less second opinion must stay CHEAP BY DEFAULT,
# and getting it must never widen a role agent's `tools:` allowlist.
#
# WHY THIS EXISTS. A PR that CodeRabbit did not review used to fan out to `code-architect`
# and `deep-bug-scan` unconditionally. Both declare `model: opus` in their OWN frontmatter,
# so that fan-out is two Opus agents regardless of what model the dispatcher is running —
# on top of an Opus `qa-reviewer`. The cheap substitute for the *external* signal is the
# harness's built-in `/code-review low`, and the expensive pair is now an ESCALATION: it
# runs when the cheap review found something, not as the opening move.
#
# Three things about that arrangement rot silently, which is why they are asserted here
# rather than trusted to prose:
#
#   1. THE ALLOWLIST INVARIANT. No role agent holds `Skill`; the route works because an
#      agent you DISPATCH declares no `tools:` key and so inherits it (rung 2 of
#      knowledge/findings/role-agents-cannot-invoke-skills.md). The tempting "fix" the
#      next time a skill is wanted is to add `Skill` to an allowlist — which injects a
#      mandatory "invoke skills before ANY action" preamble into every dispatch and widens
#      what that agent may do everywhere. That regression is invisible in a diff of prose,
#      so it is a test.
#   2. THE ORDER. Cheap-then-escalate only saves anything if the cheap review runs FIRST.
#      Swap the order back and the saving is gone while every sentence still reads fine.
#   3. THE PRICE OF THE ESCALATION. The whole design rests on `code-architect` and
#      `deep-bug-scan` being expensive. If either quietly becomes a cheaper model, the
#      escalation gate is guarding nothing and should be reconsidered rather than kept as
#      cargo — so a model change here fails and points at this comment.
#
# WHAT THIS DELIBERATELY DOES NOT DO. It does not try to judge whether the prose is any
# good, and it does not assert on wording it cannot anchor. Where a property is only
# expressible as text, the check is an ORDERING or a PRESENCE over a literal that carries
# meaning on its own (`/code-review low` — the effort level is the cheap part), never a
# sentence someone will legitimately reflow. Every such check is paired with a fixture in
# section 5 proving the matcher can actually fail; a text check that has never rejected
# anything is a comment with a `PASS` next to it.
#
# ok() follows this directory's convention: it compares actual to expected.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
pass=0; fail=0
ok() { # <name> <actual> <expected>
  if [ "$2" = "$3" ]; then printf '  PASS  %-58s (%s)\n' "$1" "$2"; pass=$((pass+1))
  else printf '  FAIL  %-58s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}
yn() { if "$@" >/dev/null 2>&1; then echo yes; else echo no; fi; }

QA="$REPO/symlink/.claude/agents/qa-reviewer.md"

# Everything after the closing frontmatter delimiter. The frontmatter `description:`
# legitimately names agents and routes, so a body-only view keeps the ordering checks
# below from being satisfied by a one-line summary.
body() { awk 'NR==1 && $0=="---" {fm=1; next} fm==1 && $0=="---" {fm=2; next} fm!=1 {print}' "$1"; }

tools_of() { # <file> — the tools: values, one per line; empty means "no key"
  awk 'NR==1 && $0=="---" {fm=1; next} fm==1 && $0=="---" {exit} fm==1 && /^tools:[[:space:]]*/ {
         sub(/^tools:[[:space:]]*/, ""); gsub(/,/, "\n"); print }' "$1" \
    | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | grep -v '^$'
}

# First body line number matching a FIXED string, or 0 when absent. Fixed-string, because
# every needle here contains `/`, `.` or `-`.
first_line() { body "$1" | grep -nF -- "$2" | head -1 | cut -d: -f1; }
first_line_or0() { local n; n="$(first_line "$1" "$2")"; echo "${n:-0}"; }

# Is <needle-b> within <window> body lines of some occurrence of <needle-a>? Used for the
# degrade clause, where what matters is that the unavailability case sits WITH the route it
# guards — a mention of each at opposite ends of the file is not a degrade path.
near() { # <file> <needle-a> <regex-b> <window>
  local f="$1" a="$2" b="$3" w="$4" ln
  body "$f" > "$TMP/body"
  while IFS= read -r ln; do
    [ -n "$ln" ] || continue
    awk -v c="$ln" -v w="$w" 'NR>=c-w && NR<=c+w' "$TMP/body" | grep -qiE -- "$b" && return 0
  done < <(grep -nF -- "$a" "$TMP/body" | cut -d: -f1)
  return 1
}

TMP="$(mktemp -d "${TMPDIR:-/tmp}/reviewroute.XXXXXX")"; trap 'rm -rf "$TMP"' EXIT

ok "qa-reviewer.md exists" "$(yn test -f "$QA")" yes

# ================================================ 1. no allowlist was widened to get here
# The invariant criterion 4 of ai-bridge-v3/task-020 states directly. `Skill` is the tool
# the route wants; `SlashCommand` is the other way to reach a slash command and would buy
# the same capability by a different name, so both are barred. A future grant is allowed —
# rung 4 of the Finding — but it has to come here and delete an assertion, in the same
# commit, where a reviewer sees it.
echo "== the allowlists stay narrow =="
AGENTS="$(find "$REPO/symlink/.claude/agents" -maxdepth 1 -type f -name '*.md' | sort)"
ok "shipped agent files found" "$([ -n "$AGENTS" ] && echo yes || echo no)" yes
granted=0; scanned=0
while IFS= read -r f; do
  [ -n "$f" ] || continue
  tools_of "$f" > "$TMP/allow"
  [ -s "$TMP/allow" ] || continue          # no tools: key ⇒ unrestricted by design
  scanned=$((scanned+1))
  for t in Skill SlashCommand; do
    if grep -qxF "$t" "$TMP/allow"; then
      granted=$((granted+1))
      printf '        WIDENED  %s grants %s — see this file\x27s header\n' "${f#"$REPO"/}" "$t"
    fi
  done
done <<EOF
$AGENTS
EOF
ok "restricted agents scanned"                "$([ "$scanned" -ge 8 ] && echo yes || echo no)" yes
ok "no shipped agent grants Skill/SlashCommand" "$granted" 0

# ============================================================ 2. the cheap route is there
echo "== the cheap route =="
# The effort level is the whole point — `/code-review` at a high level is not the cheap
# substitute — so the literal includes it.
ok "qa-reviewer names /code-review low"       "$(yn grep -qF -- '/code-review low' "$QA")" yes
# And it must say how a restricted agent reaches a skill at all, or the next reader
# "fixes" it by granting the tool.
ok "…and points at the dispatch route"        "$(yn grep -qF -- 'role-agents-cannot-invoke-skills' "$QA")" yes

# ==================================================== 3. cheap first, expensive on demand
echo "== the order (cheap before the Opus pair) =="
CR="$(first_line_or0 "$QA" '/code-review')"
CA="$(first_line_or0 "$QA" 'code-architect')"
DB="$(first_line_or0 "$QA" 'deep-bug-scan')"
RAB="$(first_line_or0 "$QA" '.coderabbit.yaml')"
printf '  ..... body lines: /code-review=%s code-architect=%s deep-bug-scan=%s .coderabbit.yaml=%s\n' \
  "$CR" "$CA" "$DB" "$RAB"
ok "both escalation agents are still named"   "$([ "$CA" -gt 0 ] && [ "$DB" -gt 0 ] && echo yes || echo no)" yes
ok "the cheap review precedes code-architect" "$([ "$CR" -gt 0 ] && [ "$CR" -lt "$CA" ] && echo yes || echo no)" yes
ok "…and precedes deep-bug-scan"              "$([ "$CR" -gt 0 ] && [ "$CR" -lt "$DB" ] && echo yes || echo no)" yes
# The external reviewer decides WHETHER any of this runs, so it is resolved first. Reading
# CodeRabbit after choosing a route is how a PR gets reviewed twice over one diff.
ok "the external reviewer is resolved first"  "$([ "$RAB" -gt 0 ] && [ "$RAB" -lt "$CR" ] && echo yes || echo no)" yes

# The probes are what make a config-less machine work, and tests/config-layer.test.sh
# derives its "every probed agent ships" check from these exact strings. Escalation that
# stops probing would take that check down with it.
ok "still probes for code-architect"          "$(yn grep -qF -- 'test -f ~/.claude/agents/code-architect.md' "$QA")" yes
ok "still probes for deep-bug-scan"           "$(yn grep -qF -- 'test -f ~/.claude/agents/deep-bug-scan.md' "$QA")" yes

# ============================================================== 4. absent ⇒ unchanged
echo "== the degrade path =="
# An older harness has no `code-review` skill. That case must sit next to the route it
# guards and must not read as an error. The needle is the SKILL NAME without a leading
# slash, so it matches both the invocation (`/code-review low`) and the prose that names
# the skill in the fallback clause — the two places the degrade path is described.
ok "unavailability is handled beside the route" \
   "$(yn near "$QA" 'code-review' 'unavailab|not available|older harness|cannot invoke' 14)" yes
ok "…and it is not an error path"             "$(yn near "$QA" 'code-review' 'never as an error|never an error|not an error|silent' 20)" yes

# ============================================== 4b. the gate itself was not delegated away
echo "== the verifier survives the cheaper reviewer =="
# The saving is in the second OPINION. Acceptance-criteria verification and test writing are
# why this agent exists, and a diff review answers neither — so the criteria step must still
# be there AND must still say, next to itself, that the review does not stand in for it.
# Without this, "we already got a review" is the sentence that quietly retires the gate.
ok "the criteria step survives"               "$(yn grep -qF -- 'acceptance_criteria' "$QA")" yes
ok "…and disclaims the diff review"           "$(yn near "$QA" 'acceptance_criteria' 'does not touch it|substitute|never answers|not replaced' 12)" yes

# =========================================================== 5. the escalation is dear
echo "== the escalation still costs what the design assumes =="
# If either of these becomes a cheaper model, the gate in front of them is guarding
# nothing. Fail here and reconsider the design rather than keeping the gate as cargo.
for a in code-architect deep-bug-scan; do
  f="$REPO/config/required/agents/$a.md"
  ok "$a ships"                               "$(yn test -f "$f")" yes
  ok "…and declares model: opus"              "$(awk 'NR==1&&$0=="---"{fm=1;next} fm==1&&$0=="---"{exit} fm==1&&/^model:/{sub(/^model:[[:space:]]*/,"");print}' "$f")" opus
done

# ================================================== 6. non-vacuity: the matchers can fail
# Every text check above is paired here with input it must reject. Without this section a
# reordered file could pass all of section 3 and nobody would know the comparison was
# never exercised.
echo "== the matchers bite =="
FX="$TMP/fx"; mkdir -p "$FX"
mk() { printf -- '---\nname: fx\ntools: %s\n---\n%s\n' "$1" "$2" > "$FX/a.md"; }

# 6a. the allowlist scan finds a widened list.
mk 'Agent, Read, Skill' 'body'
ok "scan flags a granted Skill"               "$(tools_of "$FX/a.md" | grep -cxF Skill)" 1
mk 'Agent, Read' 'body'
ok "…and passes a narrow one"                 "$(tools_of "$FX/a.md" | grep -cxF Skill)" 0

# 6b. the ordering check rejects the pre-change shape (fan-out first, cheap review after).
mk 'Agent' 'Probe for code-architect and deep-bug-scan, then dispatch both.
Afterwards, consider /code-review low.'
BCA="$(first_line_or0 "$FX/a.md" 'code-architect')"; BCR="$(first_line_or0 "$FX/a.md" '/code-review')"
ok "ordering rejects fan-out-first"           "$([ "$BCR" -lt "$BCA" ] && echo yes || echo no)" no
# ...and accepts the intended shape.
mk 'Agent' 'Dispatch /code-review low first.
Escalate to code-architect only on a trigger.'
BCA="$(first_line_or0 "$FX/a.md" 'code-architect')"; BCR="$(first_line_or0 "$FX/a.md" '/code-review')"
ok "…and accepts cheap-first"                 "$([ "$BCR" -lt "$BCA" ] && echo yes || echo no)" yes

# 6c. an absent literal is absent — the presence checks are not matching the frontmatter.
mk 'Agent' 'This body mentions no review command at all.'
ok "presence check rejects a silent body"     "$(yn grep -qF -- '/code-review low' "$FX/a.md")" no

# 6d. `near` is a WINDOW, not a whole-file grep: the same two words far apart must fail.
mk 'Agent' "$(printf 'Dispatch /code-review low.\n%s\nOn an older harness, do something else.\n' "$(yes '  filler' | head -40)")"
ok "near() rejects a distant mention"         "$(yn near "$FX/a.md" '/code-review' 'older harness' 5)" no
ok "…and accepts a nearby one"                "$(yn near "$FX/a.md" '/code-review' 'older harness' 60)" yes

printf '\n%s passed, %s failed  (%s restricted agent file(s) scanned)\n' "$pass" "$fail" "$scanned"
[ "$fail" -eq 0 ]
