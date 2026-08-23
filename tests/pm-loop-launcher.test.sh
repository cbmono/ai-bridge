#!/usr/bin/env bash
#
# pm-loop-launcher.test.sh — the `/pm-loop` launcher does its three preconditions and
# nothing else, and the crash-recovery property it used to carry lives in the tick.
#
# WHY THIS IS A TEST AND NOT ONLY A CONVENTION. Measured on a real first tick,
# 2026-08-23: `pm-loop.md` documented three cheap preconditions, and what actually ran
# in the MAIN session before "Dispatching the tick" was roughly ten wide `bash` calls —
# every task's frontmatter, 120 lines of `log.md`, a tick-ledger grep, a worktree
# listing, `gh repo view`, `gh pr list`, and two `git status`/`git log` pairs. Two costs:
# a screen of noise before anything useful, and — the one that matters — all of it in the
# context the loop has to survive on for hours across many ticks, when the tick itself is
# a backgrounded agent whose context is free and discarded.
#
# The regression is invisible from reading either file alone, because it is a *pair*: a
# reader deleting the launcher's reads can silently take the crash-recovery property with
# them (the loop is long-lived, compaction discards session history, so the in-flight set
# must be re-derived FROM DISK), and a reader restoring "just a quick orient" to the
# launcher undoes the fix while every doc still reads correctly. So both halves are
# asserted together: the launcher stays closed, and the property has a home.
#
# It is deliberately NOT a check that the launcher prints few lines — that is behaviour of
# a model, not of a file. What is checkable is the instruction it reads, which is this.
#
# IT ALSO OWNS THE ONE GRANT THAT IS NOT A PRECONDITION. `Artifact` was added so a tick can
# republish the board, and a widened tool contract is exactly the thing this file was
# written to keep honest — so the grant, the step that uses it, and the two rules that keep
# it harmless (never a new URL, never a `noop: false`) are asserted together at the bottom.
#
# ok() follows this directory's convention: it compares actual to expected.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
LAUNCHER="$REPO/symlink/.claude/commands/pm-loop.md"
TICK="$REPO/symlink/.claude/agents/project-manager.md"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/pmloop.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
ok() { # <name> <actual> <expected>
  if [ "$2" = "$3" ]; then printf '  PASS  %-58s (%s)\n' "$1" "$2"; pass=$((pass+1))
  else printf '  FAIL  %-58s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}
has() { # <file> <fixed-string> -> yes|no
  grep -qF -- "$2" "$1" && echo yes || echo no
}

ok "launcher exists" "$([ -f "$LAUNCHER" ] && echo yes || echo no)" yes
ok "tick agent exists" "$([ -f "$TICK" ] && echo yes || echo no)" yes

# --- the launcher's preconditions are a closed list of three ---------------------
# Numbered items inside `## Preconditions`, stopping at the next heading of any depth.
# `/^#/` and not an interval like `{2,}`: not every awk supports interval expressions,
# and one that doesn't would silently run the scan on into the next section.
count_preconditions() { # <file>
  awk '/^## Preconditions/{p=1;next} p&&/^#/{p=0} p&&/^[0-9]+\. /{n++} END{print n+0}' "$1"
}
# TWO, not three. The third — "read instance.config.json for reposRoot and org" — was
# removed: the launcher never used those values, the TICK does and reads config itself,
# and a precondition the tool contract forbids reads as licence to widen allowed-tools.
ok "preconditions listed" "$(count_preconditions "$LAUNCHER")" 2

# --- allowed-tools grants the launcher no reader ---------------------------------
# `pwd` and `ls` are the instance-root probe and are fine. Anything that can read a
# document, the git history or the GitHub API is the regression — including a bare
# `Bash`, which grants all of them at once.
readers_granted() { # <file> -> count of grants that are NOT on the approved list
  # AN ALLOWLIST, NOT A DENYLIST. The first version grepped for a fixed set of readers
  # — Read|Grep|Glob|WebFetch and a handful of Bash commands — so `Bash(curl:*)`,
  # `Bash(python:*)` and `Bash(node:*)` all returned 0 and this check PASSED while the
  # launcher could read anything on the machine or the network. A denylist over an open
  # set cannot be completed, which is why this repo's own permission guidance prefers
  # the simple allowlist shapes. So: extract every grant, subtract the approved forms,
  # and count what is left.
  #
  # `Artifact` is approved and is NOT a reader: it publishes a page and cannot open a
  # task document, the git history or the GitHub API — the class this check exists to
  # keep out. It is also the only grant here that is not a precondition, so the launcher
  # states its reason beside the list (asserted further down), which is what keeps the
  # next addition a line in a diff rather than a habit.
  awk '/^---$/{d++; next} d==1 && /^allowed-tools:/{sub(/^allowed-tools:[[:space:]]*/,""); print}' "$1" \
    | tr ',' '\n' \
    | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' \
    | grep -v '^$' \
    | grep -v -x -e 'Bash(pwd)' -e 'Bash(ls:\*)' -e 'Agent' -e 'Artifact' \
                 -e 'ScheduleWakeup' -e 'CronList' -e 'CronDelete' \
    | wc -l | tr -d ' '
}

granted() { # <file> <tool> -> yes|no — is <tool> an exact grant in allowed-tools?
  awk '/^---$/{d++; next} d==1 && /^allowed-tools:/{sub(/^allowed-tools:[[:space:]]*/,""); print}' "$1" \
    | tr ',' '\n' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' \
    | grep -qx -- "$2" && echo yes || echo no
}

ok "no reader in allowed-tools" "$(readers_granted "$LAUNCHER")" 0

# NON-VACUITY. A check that cannot fail proves nothing, and the previous one could not
# fail on these three — each was outside its fixed denylist. Every fixture is a real
# reader: curl reaches the network, python and node read any file on the machine.
for probe in 'Bash(curl:*)' 'Bash(python:*)' 'Bash(node:*)' 'Read' 'Bash'; do
  printf -- '---\nallowed-tools: Bash(pwd), Bash(ls:*), Agent, %s\n---\nbody\n' "$probe" \
    > "$TMP/probe.md"
  ok "…and it FAILS on a $probe grant" "$( [ "$(readers_granted "$TMP/probe.md")" -ge 1 ] && echo yes || echo no )" yes
done
# …while the real launcher's exact grant list still passes, so the allowlist is not
# simply rejecting everything.
printf -- '---\nallowed-tools: Bash(pwd), Bash(ls:*), Agent, Artifact, ScheduleWakeup, CronList, CronDelete\n---\nbody\n' \
  > "$TMP/probe.md"
ok "…and PASSES on the approved set alone" "$(readers_granted "$TMP/probe.md")" 0

# --- the launcher says, in the file, that it reads nothing else -------------------
# `The launcher reads nothing else` is an anchor both files cite, so it is grepped
# literally — the same reason `awaiting-queue.test.sh` greps a heading.
ok "launcher carries the closed-list rule" "$(has "$LAUNCHER" 'The launcher reads nothing else')" yes
# The rule must still name what it forbids; a heading over an empty list is no rule.
forbidden_named() { # <file> -> count of the four costly sources named in that section
  awk '/^### The launcher reads nothing else/{p=1;next} p&&/^#/{p=0} p' "$1" \
    | grep -o -E 'log\.md|tick ledger|git log|gh pr list' | sort -u | wc -l | tr -d ' '
}
ok "the rule names what it forbids" "$(forbidden_named "$LAUNCHER")" 4
# And the launcher must not carry the old imperative that made it do the re-derivation.
ok "old launcher imperative gone" \
  "$(grep -c -E '^[[:space:]]*Re-derive it from the root' "$LAUNCHER" | tr -d ' ')" 0
# The pair is only safe while each half points at the other: a reader who deletes the
# launcher's reads must land on the tick that now owns them, and vice versa.
ok "launcher points at the tick's step 0"  "$(has "$LAUNCHER" 'project-manager.md` step 0')" yes
ok "tick points back at the launcher rule" "$(has "$TICK" 'The launcher reads nothing else')" yes

# --- the property is not lost: it lives in the tick, naming all four disk sources --
step0() { awk '/^0\. /{p=1} p&&/^1\. /{p=0} p' "$TICK"; }
S0="$(step0)"
ok "tick has a step 0" "$([ -n "$S0" ] && echo yes || echo no)" yes
in_step0() { printf '%s' "$S0" | grep -qF -- "$1" && echo yes || echo no; }
ok "step 0: from disk, not the brief"  "$(in_step0 'never from your brief')" yes
ok "step 0: reads the tick ledger"     "$(in_step0 'tick ledger')" yes
ok "step 0: reads task status:"        "$(in_step0 'own `status:`')" yes
ok "step 0: reads git log"             "$(in_step0 'git log')" yes
ok "step 0: reads gh pr list"          "$(in_step0 'gh pr list')" yes
ok "step 0: task doc outranks ledger"  "$(in_step0 'the task document wins')" yes
ok "step 0: names the duplicate-PR failure" "$(in_step0 'duplicate PRs')" yes

# --- the republish: a grant, a step, and the two rules that keep it harmless -------
#
# WHY THESE ARE ASSERTED HERE. The board is a static page and nothing moved it, so a
# tick now re-renders and republishes it. Three of that step's properties are the kind
# that read as satisfied while being wrong, which is this file's whole subject:
#
#   · THE GRANT AND THE STEP MUST BOTH EXIST. `Artifact` in the launcher's allowed-tools
#     with no step is a widened contract buying nothing; the step with no grant anywhere
#     is an instruction that cannot run. The grant that matters is on the TICK, which is
#     what actually publishes (it holds `Bash`, so it is the only one of the two that can
#     render), and that is exactly the class agent-tool-allowlist.test.sh was written for:
#     an instruction naming a tool its agent does not hold reads perfectly and never runs.
#   · A NEW URL EACH TICK IS THE BUG. Publishing without the recorded URL forks a SECOND
#     artifact instead of updating the first, so the page a team bookmarked freezes while
#     a fresh one appears every gap — and nothing about that looks broken from inside the
#     loop, because a publish did succeed. Hence "read from config, never invented".
#   · A REPUBLISH IS NOT A CHANGE. Every tick refreshes the board, so counting it as a
#     change pins `noop` to false forever and retires the streak line that makes an idle
#     loop quiet. That is the difference between a loop a human leaves running and one
#     they turn off, so the rule is pinned rather than left to whoever edits step 3.
#
# As everywhere in this file: these check the INSTRUCTION, not a model's behaviour.
ok "launcher grants Artifact"            "$(granted "$LAUNCHER" 'Artifact')" yes
ok "…with the reason beside the list"    "$(has "$LAUNCHER" 'Why `Artifact` is in `allowed-tools`')" yes
ok "…naming what no script can do"      "$(has "$LAUNCHER" 'publishing is the one board step no script can do')" yes
ok "…and that the tick is what publishes" "$(has "$LAUNCHER" '**The publish happens in the TICK, not here**')" yes

# The step itself, and its absence rule. `2c` matches 2b's shape: one condition, and
# absence is silence — the same property awaiting-queue/snapshot absence rules carry.
step2c() { awk '/^2c\. /{p=1; next} p&&/^3\. /{p=0} p' "$LAUNCHER"; }
S2C="$(step2c)"
ok "launcher has a step 2c"              "$([ -n "$S2C" ] && echo yes || echo no)" yes
in_2c() { printf '%s' "$S2C" | grep -qF -- "$1" && echo yes || echo no; }
ok "2c: absence is silence, not an error" "$(in_2c 'absence means skip in silence')" yes
ok "2c: it does not read the config here" "$(in_2c '**You do not read the config here.**')" yes
ok "2c: a fresh URL is a bug"             "$(in_2c 'A new URL each tick is a bug, not an outcome')" yes
ok "2c: …and says what goes wrong"        "$(in_2c 'forks a *second* artifact')" yes
ok "2c: the URL is never invented"        "$(in_2c 'never invented')" yes
ok "2c: it never blocks the loop"         "$(in_2c 'It never blocks')" yes

# The noop rule lives in step 3, where `noop` is defined — not in a note beside it.
step3() { awk '/^3\. \*\*On completion/{p=1; next} p&&/^4\. /{p=0} p' "$LAUNCHER"; }
ok "step 3: a republish is not a change" \
  "$(step3 | grep -qF 'A board refresh or a republish is not a change' && echo yes || echo no)" yes

# The tick's half: it holds the grant, renders with the publishable layout, reads the URL
# from config, and repeats the noop rule where the work happens.
ok "tick holds the Artifact tool" \
  "$(awk '/^---$/{d++; next} d==1 && /^tools:/{print}' "$TICK" | tr ',' '\n' \
     | sed -e 's/^tools:[[:space:]]*//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' \
     | grep -qx 'Artifact' && echo yes || echo no)" yes
ok "tick names the config key"           "$(has "$TICK" 'boardArtifactUrl')" yes
ok "tick renders the publishable layout" "$(has "$TICK" 'build-board.sh --layout table')" yes
ok "tick skips in silence when unset"    "$(has "$TICK" 'skip the rest of this step in silence')" yes
ok "tick: publishing without the URL forks" "$(has "$TICK" 'forks a second artifact')" yes
ok "tick: a republish is not a change"   "$(has "$TICK" 'A republish is not a state change')" yes
# The retired renderer must not come back as the thing the tick runs.
ok "tick names no retired renderer"      "$(has "$TICK" 'build-artifact-board')" no
ok "launcher names no retired renderer"  "$(has "$LAUNCHER" 'build-artifact-board')" no

# NON-VACUITY for the two greps above: they must fail on a launcher that lost the step.
printf -- '---\nallowed-tools: Bash(pwd), Agent\n---\n\n2c. no rule here\n\n3. **On completion**, schedule\n' \
  > "$TMP/nostep.md"
ok "checker flags a launcher with no grant" "$(granted "$TMP/nostep.md" 'Artifact')" no
ok "checker flags a 2c with no absence rule" \
  "$(awk '/^2c\. /{p=1; next} p&&/^3\. /{p=0} p' "$TMP/nostep.md" \
     | grep -qF 'absence means skip in silence' && echo yes || echo no)" no

# --- non-vacuity: the two mechanical checks must reject a bad file ----------------
tmp="$(mktemp -d "${TMPDIR:-/tmp}/pmloop.XXXXXX")"; trap 'rm -rf "$tmp"' EXIT
{
  printf -- '---\n'
  printf 'description: fixture\n'
  printf 'allowed-tools: Bash(pwd), Bash(ls:*), Read, Bash(gh:*), Agent\n'
  printf -- '---\n\n'
  printf '## Preconditions\n\n1. one\n2. two\n3. three\n4. read every task doc\n\n'
  printf '## Next\n\n5. not a precondition\n'
} > "$tmp/bad.md"
ok "checker counts the fixture's preconditions" "$(count_preconditions "$tmp/bad.md")" 4
ok "checker flags the fixture's readers"        "$(readers_granted "$tmp/bad.md")" 2
# A bare `Bash` grants every one of those readers at once, so it counts too.
printf -- '---\nallowed-tools: Agent, Bash\n---\n' > "$tmp/bare.md"
ok "checker flags a bare Bash grant"           "$(readers_granted "$tmp/bare.md")" 1
# ...and the good line stays clean, or the check would flag everything.
printf -- '---\nallowed-tools: Bash(pwd), Bash(ls:*), Agent\n---\n' > "$tmp/good.md"
ok "checker passes pwd/ls-only grants"         "$(readers_granted "$tmp/good.md")" 0

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
