#!/usr/bin/env bash
#
# shared-bundle-sync.test.sh — a tick pulls before it reads and pushes after it
# commits, on a bundle that HAS a remote; a bundle with none does neither, silently;
# a pull conflict STOPS the tick rather than resolving it; and nothing here ever
# force-pushes. Pinned across both files that carry the behaviour: the TICK
# (`project-manager.md`, step 0's pull / step 8's push paragraph) and the LAUNCHER
# (`pm-loop.md`'s standing guardrails), because a reader who edits one without the
# other silently drops half the guarantee.
#
# WHY THIS IS A TEST AND NOT A CONVENTION. `git push` and `git pull` appeared
# NOWHERE in the shipped machinery before this change — not the PM agent, not
# `/pm-loop`, not any of the 14 `symlink/scripts/*.sh`, not a hook. A tick committed
# locally via `commit-as.sh` and stopped. That was harmless while every instance had
# one human; it stopped being harmless the day a second clone started sharing one
# bundle, because the two clones now diverge silently until somebody pushes by hand
# — and the ownership gate (`task-owner.sh`) cannot help, since it reads task
# documents the other clone has not fetched yet.
#
# FOUR PROPERTIES, EACH INDEPENDENTLY DROPPABLE. A future edit that "simplifies" the
# step can keep some of the words and lose the behaviour: "pull" surviving in a
# sentence that no longer runs before the read, or "conflict" surviving in a
# sentence that now resolves one instead of refusing to. So each property below is
# pinned by its OPERATIVE text — the actual git command or the actual refusal — not
# by an incidental noun, and every extraction is proven capable of failing against a
# synthetic fixture that drops exactly that property (a check that can only pass is
# not a check).
#
# ok() follows this directory's convention: it compares actual to expected.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
TICK="$REPO/symlink/.claude/agents/project-manager.md"
LAUNCHER="$REPO/symlink/.claude/commands/pm-loop.md"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/sync.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
ok() { # <name> <actual> <expected>
  if [ "$2" = "$3" ]; then printf '  PASS  %-58s (%s)\n' "$1" "$2"; pass=$((pass+1))
  else printf '  FAIL  %-58s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}
has() { # <file> <fixed-string> -> yes|no
  grep -qF -- "$2" "$1" && echo yes || echo no
}

ok "tick exists"     "$([ -f "$TICK" ] && echo yes || echo no)" yes
ok "launcher exists" "$([ -f "$LAUNCHER" ] && echo yes || echo no)" yes

# --- extraction: the tick's step 0 (sync), its step-8 push paragraph, and the ------
# --- launcher's sync guardrail bullet — the three places the behaviour lives -------
step0_of() { # <file> -> the sync step's body only, stopping at step 0.5
  awk '/^0\. \*\*Sync the bundle first/{p=1;next} /^0\.5\. /{p=0} p' "$1"
}
push_para_of() { # <file> -> the step-8 push paragraph only
  awk '/\*\*Then push, if this bundle has a remote\.\*\*/{p=1} p&&/\*\*Refresh the awaiting-you queue/{p=0} p' "$1"
}
guardrail_of() { # <file> -> the launcher's standing-guardrail bullet only
  awk '/- \*\*The tick syncs the bundle around its own work/{p=1} p&&/- \*\*An answered question is MOVED/{p=0} p' "$1"
}

S0="$(step0_of "$TICK")"
PUSH="$(push_para_of "$TICK")"
G="$(guardrail_of "$LAUNCHER")"
ok "tick has a step 0 sync section"       "$([ -n "$S0" ]   && echo yes || echo no)" yes
ok "tick has a step 8 push paragraph"     "$([ -n "$PUSH" ] && echo yes || echo no)" yes
ok "launcher has the sync guardrail bullet" "$([ -n "$G" ]  && echo yes || echo no)" yes

in_str() { printf '%s' "$1" | grep -qF -- "$2" && echo yes || echo no; } # <text> <needle>

# =================================================================================
# Property 1 — a bundle WITH a remote pulls --rebase before re-deriving state
# =================================================================================
ok "step 0: pulls with rebase"             "$(in_str "$S0" 'git pull --rebase origin')" yes
ok "step 0: pull precedes the re-derive"     "$(in_str "$S0" 'Why before step 0.5 and not after it')" yes
ok "guardrail: names the pull"               "$(in_str "$G" '--rebase')" yes
ok "guardrail: pull precedes the read"       "$(in_str "$G" 'before it re-derives anything from disk')" yes

# =================================================================================
# Property 2 — the tick pushes after it commits
# =================================================================================
ok "step 8: pushes to origin"                "$(in_str "$PUSH" 'git push origin')" yes
ok "guardrail: names the push"                "$(in_str "$G" 'pushes right after it commits')" yes
# The push paragraph also retries once on rejection, then stops like step 0 does.
ok "step 8: retries once on rejection"        "$(in_str "$PUSH" 'push once more')" yes
ok "step 8: a second conflict stops it too"   "$(in_str "$PUSH" 'stop and report exactly')" yes

# =================================================================================
# Property 3 — a bundle with NO remote does neither, silently (never an error)
# =================================================================================
ok "step 0: gated on a remote existing"           "$(in_str "$S0" 'git remote get-url origin')" yes
ok "step 0: absence is never an error"            "$(in_str "$S0" 'never an error')" yes
ok "step 8: shares step 0's no-remote condition"  "$(in_str "$PUSH" 'Same condition as step 0')" yes
ok "guardrail: no remote -> neither, silently"    "$(in_str "$G" 'does neither, silently')" yes

# =================================================================================
# Property 4 — a pull conflict STOPS the tick; it is never auto-resolved
# =================================================================================
ok "step 0: a conflict STOPS the tick"       "$(in_str "$S0" 'A conflict STOPS the tick')" yes
ok "step 0: aborts rather than resolving"    "$(in_str "$S0" 'git rebase --abort')" yes
ok "step 0: names what a tick must not do"   "$(in_str "$S0" 'Do not resolve it')" yes
ok "guardrail: conflict stops the tick"      "$(in_str "$G" 'stops the tick')" yes
ok "guardrail: reports, never resolves"      "$(in_str "$G" 'a tick never resolves contested')" yes

# =================================================================================
# Property 5 — nothing here ever force-pushes
# =================================================================================
ok "step 8: never force-push"                "$(in_str "$PUSH" 'Never force-push a shared bundle')" yes
ok "guardrail: never force-pushes"           "$(in_str "$G" 'nothing here ever force-pushes')" yes

# =================================================================================
# NON-VACUITY. Each extraction above must be able to FAIL — demonstrated by mutating
# a synthetic copy of the real section and dropping exactly one property, then
# re-running the same extraction + grep over the mutation. A checker that cannot
# fail on any input proves nothing (the whole lesson of "don't grep one word").
# =================================================================================
good_step0() {
  cat <<'EOF'
0. **Sync the bundle first — pull before you read anything.**

   **Only when this bundle has a remote.** `git remote get-url origin` failing means a
   local-only instance: skip this silently and skip the push in step 8 too. Absence is
   the single-machine case behaving exactly as it always has, never an error.

   ```
   git pull --rebase origin <default-branch>
   ```

   **Why before step 0.5 and not after it.** re-derives from disk.

   **A conflict STOPS the tick. Do not resolve it.** Abort (`git rebase --abort`),
   change nothing, and report the conflicting paths for the human.

0.5. next step
EOF
}
ok "fixture: good step 0 passes every check" \
   "$(g="$(good_step0 | awk '/^0\. \*\*Sync the bundle first/{p=1;next} /^0\.5\. /{p=0} p')"; \
      a=$(in_str "$g" 'git pull --rebase origin'); \
      b=$(in_str "$g" 'git remote get-url origin'); \
      c=$(in_str "$g" 'never an error'); \
      d=$(in_str "$g" 'A conflict STOPS the tick'); \
      e=$(in_str "$g" 'git rebase --abort'); \
      [ "$a$b$c$d$e" = "yesyesyesyesyes" ] && echo yes || echo no)" yes

mut_check() { # <mutated-step0-text> <needle-that-should-now-be-absent>
  local body; body="$(printf '%s\n' "$1" | awk '/^0\. \*\*Sync the bundle first/{p=1;next} /^0\.5\. /{p=0} p')"
  in_str "$body" "$2"
}

no_pull="$(good_step0 | grep -v 'git pull --rebase origin')"
ok "…and FAILS when the pull command is dropped" "$(mut_check "$no_pull" 'git pull --rebase origin')" no

no_remote_gate="$(good_step0 | grep -v 'git remote get-url origin')"
ok "…and FAILS when the no-remote gate is dropped" "$(mut_check "$no_remote_gate" 'git remote get-url origin')" no

resolves_conflict="$(good_step0 | sed 's/A conflict STOPS the tick\. Do not resolve it\./A conflict is resolved automatically./')"
ok "…and FAILS when the refusal is replaced by auto-resolving" \
   "$(mut_check "$resolves_conflict" 'A conflict STOPS the tick')" no

good_push_para() {
  cat <<'EOF'
   **Then push, if this bundle has a remote.** `git push origin <default-branch>`.
   Same condition as step 0: no remote => no push, silently. If the push is
   rejected because the remote moved while you worked, `git pull --rebase
   origin <default-branch>` and push once more; if THAT conflicts, stop and report exactly
   as in step 0. **Never force-push a shared bundle.**

   **Refresh the awaiting-you queue**
EOF
}
ok "fixture: good push paragraph passes every check" \
   "$(p="$(good_push_para | awk '/\*\*Then push, if this bundle has a remote\.\*\*/{p=1} p&&/\*\*Refresh the awaiting-you queue/{p=0} p')"; \
      a=$(in_str "$p" 'git push origin'); \
      b=$(in_str "$p" 'Same condition as step 0'); \
      c=$(in_str "$p" 'Never force-push a shared bundle'); \
      [ "$a$b$c" = "yesyesyes" ] && echo yes || echo no)" yes

no_force_push_rule="$(good_push_para | grep -v 'Never force-push a shared bundle')"
mut_push_check() { # <mutated-push-text> <needle>
  local body; body="$(printf '%s\n' "$1" | awk '/\*\*Then push, if this bundle has a remote\.\*\*/{p=1} p&&/\*\*Refresh the awaiting-you queue/{p=0} p')"
  in_str "$body" "$2"
}
ok "…and FAILS when the never-force-push rule is dropped" \
   "$(mut_push_check "$no_force_push_rule" 'Never force-push a shared bundle')" no

no_push_cmd="$(good_push_para | grep -v 'git push origin')"
ok "…and FAILS when the push command is dropped" \
   "$(mut_push_check "$no_push_cmd" 'git push origin')" no

# =================================================================================
# Acceptance criterion 5 — the step renumbering left no stale "step 0" cross-
# reference anywhere in the repo. Old step 0 (re-derive the in-flight set) became
# step 0.5; the literal string "step 0" must now appear ONLY in the tick (naming
# its own new sync step) and the launcher (which must cite 0.5 for the property
# that moved there, never a bare "step 0").
# =================================================================================
step0_mentioning_files() {
  grep -rl "step 0" --include="*.md" "$REPO" 2>/dev/null | grep -v "/\.git/" | sed "s#^$REPO/##" | sort
}
S0FILES="$(step0_mentioning_files)"
ok "'step 0' is named in exactly two files" "$(printf '%s\n' "$S0FILES" | grep -c .)" 2
ok "…the tick…"     "$(printf '%s\n' "$S0FILES" | grep -qx 'symlink/.claude/agents/project-manager.md' && echo yes || echo no)" yes
ok "…and the launcher, nowhere else"  "$(printf '%s\n' "$S0FILES" | grep -qx 'symlink/.claude/commands/pm-loop.md' && echo yes || echo no)" yes

# The launcher's citation of the re-derivation property must point at 0.5, the step
# it actually lives in now — not the bare "step 0" that would silently mean the new
# sync step instead.
ok "launcher cites step 0.5 for the re-derive property" \
   "$(has "$LAUNCHER" "project-manager.md\` step 0.5")" yes
# And the old, now-false claim that re-derivation is the tick's literal first step
# must not have survived the renumbering.
ok "launcher no longer claims re-derive is the tick's own first step" \
   "$(has "$LAUNCHER" "is the tick's own first step")" no


# --- REGRESSION: --autostash must never come back -------------------------------
# Measured 2026-08-24: with the rebase clean but the stash re-apply conflicting,
# `git pull --rebase --autostash` EXITS 0 with HEAD already moved and the tree left
# UU-conflicted, and `git rebase --abort` then fails "no rebase in progress". A tick
# trusting that exit code parses task documents full of conflict markers and acts on
# them. So the flag is banned as a COMMAND, the dirty-tree refusal that replaces it is
# required, and the exit code is explicitly not trusted.
# Ban it as a COMMAND, not as a word: step 0's prose names the flag on purpose to
# explain why it is absent, so a bare substring check would fail on its own warning.
S0_CMDS="$(printf '%s\n' "$S0" | grep -E '^\s{3,}git ' || true)"
ok "step 0: no --autostash in any command it tells you to run" \
   "$(in_str "$S0_CMDS" '--autostash')" no
ok "push retry: does NOT pull with --autostash" \
   "$(in_str "$PUSH" '--rebase --autostash')" no
ok "launcher: does NOT describe an --autostash pull" \
   "$(in_str "$G$LAUNCHER" 'pulls `--rebase --autostash`')" no
ok "step 0: refuses a dirty tree before pulling" \
   "$(in_str "$S0" 'git status --porcelain')" yes
ok "step 0: says why --autostash is absent (so nobody re-adds it)" \
   "$(in_str "$S0" 'exits 0')" yes
ok "step 0: does not trust the pull exit code" \
   "$(in_str "$S0" 'Do not trust the pull')" yes
# Non-vacuity: each check above must be able to fail.
bad_cmds="$(printf '%s\n' "$S0_CMDS" | sed 's/git pull --rebase origin/git pull --rebase --autostash origin/')"
ok "…and the --autostash ban FAILS on a reintroduced flag" \
   "$(in_str "$bad_cmds" '--autostash')" yes
no_dirty="$(printf '%s\n' "$S0" | grep -v 'git status --porcelain')"
ok "…and the dirty-tree check FAILS when the guard is dropped" \
   "$(in_str "$no_dirty" 'git status --porcelain')" no

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
