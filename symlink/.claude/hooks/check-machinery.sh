#!/usr/bin/env bash
#
# check-machinery.sh — SessionStart hook (ai-bridge machinery).
#
# Says, at the top of a session, that this instance's machinery symlinks point at a path
# that no longer exists — and names the one command that repairs it.
#
# WHY. On 2026-08-23 an ai-bridge checkout was moved with a plain `mv`. That dangled 185
# symlinks across three instances and the ~/.claude config layer: every script, every role
# agent, every command, SCHEMA.md, settings.json. Nothing noticed. The instances looked
# fine from the outside, because a dangling symlink is invisible until something tries to
# execute it — which for a /pm-loop tick means mid-dispatch, with agents already briefed.
# install.sh already refuses to install FROM a git worktree for exactly this reason ("every
# symlink it creates would point into the worktree, and removing that worktree breaks all
# of them — silently, later"), so the hazard was known and half-guarded: what was missing
# was any signal that links which USED to resolve had stopped.
#
# WHAT IT CANNOT COVER, which is a hole and not a caveat. `.claude/settings.json` is itself
# one of these symlinks — machinery, like everything else here — so when the whole template
# moves it dangles too. Claude Code then has no project settings, this hook is never
# registered, and it cannot run. A detector built out of the machinery it checks does not
# survive the total failure of that machinery. So this catches the case where SOME links
# are dead while the settings that register hooks still resolve — a file renamed or retired
# inside a template that is still where the instance thinks it is, a partially repaired
# instance, a single relinked file — and it does not catch a template that moved wholesale.
# Closing that needs one real, non-symlinked file the harness reads unconditionally, which
# is a design trade (a copied settings.json stops receiving template updates) recorded in
# docs/operations.md rather than decided in a hook.
#
# SILENT, AND EXIT 0, UNLESS SOMETHING IS ACTUALLY BROKEN — in a healthy instance and in
# any non-bridge project that inherits this hook. It never repairs anything: the repair
# rewrites every machinery link in the instance and is the human's to run. A hook that
# silently rebuilt an instance's machinery at session start would be worse than the problem
# it fixes, because then a move would leave no trace at all.
#
# Verified by tests/moved-template.test.sh.

# DELIBERATELY NOT `set -e`. Every test below is allowed to be false, and a hook that dies
# on the first failed test is a hook that has stopped reporting without saying so.
set -uo pipefail

root="${CLAUDE_PROJECT_DIR:-$PWD}"

# THE "IS THIS AN INSTANCE" TEST MUST NOT ITSELF BE A SYMLINK. push-state.sh identifies an
# instance by the triple SCHEMA.md + instance.config.json + .claude/agents — but SCHEMA.md
# IS machinery, and `[ -f ]` on a dangling symlink is false, so that triple would silence
# this hook in precisely the case it exists for. These two are the parts of an instance a
# moved template cannot touch: instance.config.json is COPIED seed content, and
# .claude/agents is a real directory install.sh mkdir -p's. A non-bridge project has
# neither, so it prints nothing.
[ -f "$root/instance.config.json" ] && [ -d "$root/.claude/agents" ] || exit 0

# A handful of probes, not a walk. Resolving every link in the bundle on every session
# start costs more and says the same thing: these four are one per class of machinery
# (root document, script, role agent, hook), and anything that breaks the template's path
# breaks all four at once. The list FAILS CLOSED — a path this template stops shipping
# simply stops being a symlink in the instance, so a stale entry can cost a missed report
# but can never raise a false alarm. tests/moved-template.test.sh asserts every entry is
# still a real file under symlink/, which is what notices the staleness.
PROBES="SCHEMA.md scripts/commit-as.sh .claude/agents/project-manager.md .claude/hooks/push-state.sh"

dead=""; n=0; gone=""
for rel in $PROBES; do
  p="$root/$rel"
  # A symlink whose target is missing — both halves load-bearing, the same test step 2b of
  # install.sh uses. A file the instance never had is absent, not broken; a real file is
  # never ours to complain about.
  if [ -L "$p" ] && [ ! -e "$p" ]; then
    n=$((n+1)); dead="${dead:+$dead, }$rel"
    if [ -z "$gone" ]; then
      gone="$(readlink "$p" 2>/dev/null || true)"
      gone="${gone%/symlink/*}"
    fi
  fi
done
# Counted, never written twice: a hardcoded "of 4" drifts the moment a probe is added.
# shellcheck disable=SC2086  # unquoted on purpose — the split into words IS the count.
total="$(set -- $PROBES; echo $#)"
[ "$n" -gt 0 ] || exit 0

# Where this template lives NOW, read from this script's own path — the one machinery path
# known to resolve, because it is executing. That is what turns the message below into a
# command the human can paste instead of an instruction to go and find a directory. If the
# hook is running from somewhere unexpected, say less rather than print a wrong path.
self="${BASH_SOURCE[0]:-$0}"
[ -L "$self" ] && self="$(readlink "$self" 2>/dev/null || printf '%s' "$self")"
tmpl="${self%/symlink/.claude/hooks/*}"
[ "$tmpl" != "$self" ] || tmpl=""

# NOT FENCED AS UNTRUSTED DATA, unlike show-awaiting.sh and push-state.sh, and the reason
# is that nothing here is bundle-authored: the names come from PROBES (literals in this
# file), and the paths are this instance's own root and this template's own location. No
# task document, project slug or filename from the bundle reaches this output.
echo "⚠️  ai-bridge machinery is DANGLING in this instance — ${n} of ${total} probed symlinks"
echo "    point at a path that no longer exists."
echo "    dead: $dead"
[ -n "$gone" ] && echo "    pointing into: $gone (no longer there)"
echo "    Assume every other machinery link is dead too — scripts, role agents, commands,"
echo "    SCHEMA.md. Nothing has been changed here."
if [ -n "$tmpl" ]; then
  echo "    REPAIR (idempotent, safe to re-run, once per instance):"
  # %q shell-quotes only what needs it — a plain path (the common case) still prints
  # bare and copy-pastes as-is; a path with whitespace or a shell metacharacter comes
  # out quoted instead of pasting into a different, wrong command.
  printf '        bash %q %q\n' "$tmpl/install.sh" "$root"
else
  echo "    REPAIR: re-run install.sh from wherever the ai-bridge template now lives:"
  printf '        bash <ai-bridge>/install.sh %q\n' "$root"
fi
echo "    Report this and the repair command to the human before doing anything else. A"
echo "    /pm-loop tick started now fails mid-dispatch, with agents already briefed."
exit 0
