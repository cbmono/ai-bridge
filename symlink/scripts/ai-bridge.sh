#!/usr/bin/env bash
#
# ai-bridge.sh — the `/ai-bridge` command, in three forms.
#
#   ai-bridge.sh                      reprint the SessionStart banner
#   ai-bridge.sh check  [flags]       report the state of this instance
#   ai-bridge.sh fix    [flags]       act on the idempotent tier ONLY, print the rest
#
# WHAT THIS IS NOT, because the rejected shape is the one that keeps getting proposed. It
# does NOT load rules into context. `CLAUDE.md` is injected into every turn and the banner
# already fires unprompted, and of the failures this file was written from, not one was
# caused by a rule not being loaded — every one was invisible STATE (a stamp taken from a
# stale template clone that printed `already linked` and changed nothing; config keys left
# uncommitted; an instance configured to call a hook it did not have) or a missing READER.
# Reciting rules costs context every session and enforces nothing.
#
# So the rule for every line this file prints: it is a FACT THAT CAN BE FALSE, with its
# evidence. Never a reminder, never a convention, never "always use the loop". If a line
# would read the same on a healthy instance and a broken one, it does not belong here.
#
# ---------------------------------------------------------------------------------------
# THE ONE LIST, AND WHY IT IS ONE
# ---------------------------------------------------------------------------------------
# `check` and `fix` read `CHECKS` below and nothing else. Two lists drift — the checker
# learns about seven things, the fixer about five, and the gap is silent — so `fix` does
# not know the name of a single check: it walks the same rows, reads the TIER each row
# declares, and dispatches on that. Adding a check is one edit in one place (a row here
# plus its `check_<id>` function), and `assert_no_rogue_fixers` below turns the invariant
# into a refusal rather than a convention.
#
# THE THREE TIERS ARE A RISK CLASSIFICATION, NOT A PRIORITY. Collapsing them is how this
# command becomes dangerous:
#
#   idempotent  re-running the repair on an already-correct instance changes nothing, and
#               the repair has exactly one right answer. `fix` ACTS.
#   ambiguous   whether it is even wrong is a judgement only the human can make. `fix`
#               PRINTS. Measured 2026-08-30: an instance carried an uncommitted
#               `maxPrLoc: 2000 -> 500` that was a deliberate decision by its owner, made
#               minutes earlier and indistinguishable to a checker from drift. A `fix`
#               that "helpfully" reverted it would have destroyed that choice.
#               UNCOMMITTED CONFIG IS A QUESTION, NEVER A DEFECT.
#   human       acting is unsafe even when the diagnosis is right. `fix` PRINTS. The live
#               case is `.tick-lock`: `scripts/tick-lock.sh release` is documented as the
#               human's override (`/pm-loop`, `SCHEMA.md`), and a `fix` that cleared a
#               lock it judged stale re-opens the double-dispatch that ran two ticks
#               concurrently for 34 minutes on 2026-08-29. A long tick is not a dead one.
#
# The two SHIP-BLOCKERS are structural, not a promise: there is no `fix_config_uncommitted`
# and no `fix_tick_lock` in this file, the dispatcher calls `fix_<id>` only for a row whose
# declared tier is `idempotent`, and `check` and `fix` both REFUSE TO RUN if either function
# is ever defined (the banner form `exec`s before that point, deliberately — it dispatches
# no repair, and nothing may come between it and the hook). `tests/ai-bridge-command.test.sh` asserts the non-action against a modified
# config and a stale lock — the two files come out byte-identical, unstaged and unremoved.
#
# ---------------------------------------------------------------------------------------
# NEVER WRITES OUTSIDE `fix`, AND NEVER FAILS LOUDLY
# ---------------------------------------------------------------------------------------
# `check` reads. Every unknown — no git, no remote-tracking ref, no python3, no template,
# an instance that is not a checkout — is reported AS a fact ("cannot compare, because X")
# and never as an error and never as a warning. A false alarm trains the human to ignore
# the true one, which is the failure mode this whole file exists to prevent; `check` exits
# 0 on every path except a usage error, because its caller can be a SessionStart hook and a
# non-zero exit there is a failed hook, not a message.
#
# WHICH EMPHASIS SURVIVES DEPENDS ON WHO IS READING, AND IT WAS MEASURED. `check` output is
# read three ways and two of them render different things — Claude Code 2.1.251, probed
# 2026-08-30 by emitting candidates and reading the bytes the terminal received:
#
#   relayed by the model (`/ai-bridge check` in a session)   markdown renders; ANSI DOES NOT.
#       0 of 4 ESC bytes survived the relay and the human was left reading a literal `[1m`.
#       Single newlines and leading indent survive, so the block keeps its shape.
#   a human's terminal (`bash scripts/ai-bridge.sh check`)   ANSI renders; markdown does not.
#   inlined into the SessionStart banner (`--banner`)        NEITHER, here. That channel does
#       render ANSI — but `session-banner.sh` owns the weight of every line it prints, so
#       this side stays plain and the banner colours it. Two writers on one line is how a
#       column drifts.
#
# Hence `--style`, resolved below. The SIGIL IS NEVER INSIDE THE EMPHASIS: `⚠ **text**`, not
# `**⚠ text**`, so `^⚠` keeps matching for the banner's filter and for the harness whatever
# the style is.
#
# GENERIC TEMPLATE FILE — symlinked from the template; it reads no org, repo or path
# literal. Verified by tests/ai-bridge-command.test.sh.
#
# EVERY `check_*` AND `fix_*` FUNCTION IS INVOKED INDIRECTLY, by a name built from the row
# in `CHECKS` — which is the whole design, and is exactly what shellcheck cannot see. The
# disable is file-scoped rather than repeated eleven times, and the wiring the linter is
# thereby stopped from checking is checked properly instead, at runtime, by
# `assert_list_is_wired`: a row with no function makes the command refuse to start.
# shellcheck disable=SC2329
set -uo pipefail

# =========================================================================================
# THE LIST. `id|tier|banner`
# =========================================================================================
# `banner` says whether the row is allowed to speak on the SessionStart path. It is a
# COLUMN HERE rather than a second list in the hook, for the same reason `tier` is: the
# hook must not carry the name of a check. Two rows say `no` and both for the banner's own
# "only fire what is true, and never twice" rule —
#
#   template-behind    the banner already prints the VERSION drift line, from the same
#                      helper this row delegates to; the commits-behind fact is the
#                      on-demand half and would otherwise print a second line about the
#                      same clone at every session start.
#   config-layers      the banner's settings table already carries the FROM column, which
#                      IS this fact, laid out better.
#
# Order is execution order, and it is load-bearing for `fix`: pulling the template clone
# must happen before re-stamping from it, or the stamp is taken from the stale tree — the
# exact failure that produced this file.
CHECKS='template-behind|idempotent|no
unstamped-machinery|idempotent|yes
config-uncommitted|ambiguous|yes
config-layers|ambiguous|no
tick-lock|human|yes
orphan-processes|human|yes'

# =========================================================================================
# ARGUMENTS
# =========================================================================================
FORM=""; ROOT=""; TEMPLATE=""; ONLY_PROBLEMS=0; BANNER_ONLY=0; FETCH=0; SINCE=""
LIST=0; STYLE=auto

# usage — the three forms and their flags, on stderr so `--help` never pollutes a pipeline.
usage() {
  cat >&2 <<'USAGE'
Usage: ai-bridge.sh [banner]                       reprint the SessionStart banner
       ai-bridge.sh check [--instance DIR] [--template DIR] [--fetch]
                          [--since <ref>] [--only-problems] [--banner] [--list]
                          [--style auto|markdown|ansi|plain]
       ai-bridge.sh fix   [--instance DIR] [--template DIR] [--fetch]
                          [--style auto|markdown|ansi|plain]
USAGE
}

# The form is the FIRST argument or nothing. Anything else is a flag, and an unrecognised
# flag is fatal here (unlike the banner, which is a hook and must start anyway): this is an
# interactive command, and silently ignoring `--intsance` would report on the wrong root.
case "${1:-}" in
  check|fix)   FORM="$1"; shift ;;
  banner)      FORM=banner; shift ;;
  -h|--help)   usage; exit 0 ;;
  "")          FORM=banner ;;
  -*)          FORM=banner ;;   # `ai-bridge.sh --color=never` — flags belong to the banner
  *)           usage; exit 2 ;;
esac

# Everything left over on the banner path stays in `$@` untouched, including flags this
# file has never heard of: it is the one form that must not grow a second opinion about its
# own options. `"$@"` is also the one array expansion that is safe under `set -u` when it is
# empty, on the bash 3.2 macOS still ships.
if [ "$FORM" != banner ]; then
  while [ $# -gt 0 ]; do
    case "$1" in
      --instance)    [ $# -ge 2 ] || { echo "ai-bridge: --instance needs a directory" >&2; exit 2; }; ROOT="$2"; shift 2 ;;
      --instance=*)  ROOT="${1#--instance=}"; shift ;;
      --template)    [ $# -ge 2 ] || { echo "ai-bridge: --template needs a directory" >&2; exit 2; }; TEMPLATE="$2"; shift 2 ;;
      --template=*)  TEMPLATE="${1#--template=}"; shift ;;
      --since)       [ $# -ge 2 ] || { echo "ai-bridge: --since needs a git ref" >&2; exit 2; }; SINCE="$2"; shift 2 ;;
      --since=*)     SINCE="${1#--since=}"; shift ;;
      --only-problems) ONLY_PROBLEMS=1; shift ;;
      --banner)      BANNER_ONLY=1; shift ;;
      --list)        LIST=1; shift ;;
      --style)       [ $# -ge 2 ] || { echo "ai-bridge: --style needs a value" >&2; exit 2; }; STYLE="$2"; shift 2 ;;
      --style=*)     STYLE="${1#--style=}"; shift ;;
      --fetch)       FETCH=1; shift ;;
      -h|--help)     usage; exit 0 ;;
      *)             echo "ai-bridge: unknown argument: $1" >&2; usage; exit 2 ;;
    esac
  done
fi

[ -n "$ROOT" ] || ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"

# WHERE THE TEMPLATE IS, read from this script's own resolved path — the one machinery path
# known to resolve, because it is executing. The instance's copy of this file IS a symlink
# into the template and `install.sh` writes absolute targets, so this cannot be wrong; the
# same derivation `check-template-version.sh` and the banner use, for the same reason.
if [ -z "$TEMPLATE" ]; then
  self="${BASH_SOURCE[0]:-$0}"
  # Absolute first: the marker below is `/symlink/scripts/`, so `bash symlink/scripts/…`
  # would match nothing and silently answer "no template", and a symlink is allowed to
  # carry a relative target that only means anything beside the link itself.
  case "$self" in /*) ;; *) self="$PWD/$self" ;; esac
  if [ -L "$self" ]; then
    target="$(readlink "$self" 2>/dev/null || printf '%s' "$self")"
    case "$target" in /*) self="$target" ;; *) self="$(dirname "$self")/$target" ;; esac
  fi
  guess="${self%/symlink/scripts/*}"
  [ "$guess" != "$self" ] && TEMPLATE="$guess"
fi
[ -n "$TEMPLATE" ] && [ -d "$TEMPLATE" ] || TEMPLATE=""

# WHICH COPY OF THE SIBLING SCRIPTS TO RUN. The template's, when this is running from one —
# an instance stamped before a helper shipped has no link to it, and answering "that check
# does not exist here" about a template that plainly ships it would be a lie about the
# wrong thing. Falls back to the instance's own `scripts/`, which is what a hand-copied
# deployment has. Mirrors the banner's `bin` resolution exactly.
if [ -n "$TEMPLATE" ] && [ -d "$TEMPLATE/symlink/scripts" ]; then
  BIN="$TEMPLATE/symlink/scripts"
  HOOKS="$TEMPLATE/symlink/.claude/hooks"
else
  BIN="$ROOT/scripts"
  HOOKS="$ROOT/.claude/hooks"
fi

# =========================================================================================
# FORM 1 — THE BANNER. One `exec`, no output of its own, ever.
# =========================================================================================
# IT INVOKES THE HOOK, IT DOES NOT REPRODUCE IT. The banner is `session-banner.sh` and this
# form exists for one reason: a long session scrolls it out of view. Any line printed here
# — a header, a "reprinting…", a blank line — is a way for the two to differ, and the
# moment they differ this form is wrong. `exec` rather than a call so even the exit status
# is the hook's own. `tests/ai-bridge-command.test.sh` asserts the two are BYTE-IDENTICAL.
#
# `CLAUDE_PROJECT_DIR` is exported because it is the only thing the hook reads to decide
# which instance it is describing. This form takes none of our own flags — `--instance` is a
# `check`/`fix` option — so the value is whatever the environment already said, or this
# directory; setting it explicitly is what makes `bash scripts/ai-bridge.sh` from an
# instance root print the same thing the hook prints at session start.
if [ "$FORM" = banner ]; then
  hook="$HOOKS/session-banner.sh"
  if [ ! -f "$hook" ]; then
    echo "ai-bridge: the session banner is not installed here ($hook)." >&2
    echo "           Re-stamp this instance to link it: bash <template>/install.sh $ROOT" >&2
    exit 2
  fi
  export CLAUDE_PROJECT_DIR="$ROOT"
  exec bash "$hook" "$@"
fi

# =========================================================================================
# SHARED PLUMBING FOR THE CHECKS
# =========================================================================================
# A check function prints its lines and RETURNS 1 when it found a problem, 0 otherwise. The
# return code is the only channel that survives the command substitution the runner wraps
# it in, which is why `warn` sets a flag the function returns rather than a global.
#
# THREE LINE KINDS, AND THE DIFFERENCE IS NOT COSMETIC. `--only-problems` — the
# SessionStart path — keeps `warn` and `hint` lines and drops everything else, so the
# banner gains AT MOST TWO LINES PER FAILING CHECK: what is wrong, and the one command
# that addresses it. That bound is the whole reason `hint` exists as its own helper rather
# than as a `note` someone remembered to keep short: the banner has a measured line budget
# (tests/session-banner.test.sh), and a section that can grow with the number of affected
# files would blow it the first time an instance is badly out of date — which is precisely
# when the banner most needs to stay readable. Emit ONE `hint` per check.
# ---------------------------------------------------------------------------------------
# STYLE — which emphasis this run's reader can actually see.
# ---------------------------------------------------------------------------------------
# RESOLVED ONCE, HERE, AND THE ORDER OF THE TESTS IS THE WHOLE OF IT:
#
#   NO_COLOR set and non-empty  -> plain.    The template's one opt-out (print-board.sh,
#                                            session-banner.sh state the same contract), and
#                                            it covers markdown too: bold is not "not colour"
#                                            when the client renders it AS colour, and one
#                                            switch a reader already knows beats a second one.
#   --style markdown|ansi|plain -> as asked. A caller that knows its reader.
#   --banner                    -> plain.    session-banner.sh inlines this block and colours
#                                            it; see the header.
#   stdout is a terminal        -> ansi.     A human ran it by hand.
#   otherwise                   -> markdown. A pipe here is the Bash tool, and what comes out
#                                            of it is relayed into an assistant message. That
#                                            was measured rendering markdown and DESTROYING
#                                            ANSI, so this is the branch `/ai-bridge check`
#                                            actually takes.
#
# `NO_COLOR` IS TESTED BEFORE `--style`, AND THAT ORDER IS THE WHOLE OF THE CONTRACT. It is
# the READER's opt-out, set in their environment; `--style` is the CALLER's guess about that
# reader. A caller cannot consent on the reader's behalf, so `--style ansi` under `NO_COLOR=1`
# is the one combination that has to lose — the alternative is an opt-out that holds only for
# the paths which happen not to pass a style, i.e. one that works until something uses the
# flag. `markdown` loses to it for the same reason `auto` does: the client renders bold AS
# emphasis, so it is not "not colour" (see the first entry above).
#
# AN UNRECOGNISED VALUE IS `auto`, not fatal: `check` can be called from a SessionStart hook,
# and exiting 2 over a spelling mistake in a style name would cost the whole banner.
if [ -n "${NO_COLOR:-}" ]; then STYLE=plain
else
  case "$STYLE" in
    markdown|ansi|plain) ;;
    *) if   [ "$BANNER_ONLY" -eq 1 ]; then STYLE=plain
       elif [ -t 1 ];                 then STYLE=ansi
       else                                STYLE=markdown
       fi ;;
  esac
fi
# Spelled out with `printf` rather than typed: an ESC in a string literal is invisible in a
# diff and in a grep, and `${_esc}[` is braced because `"$_esc[1m"` is bash's array-subscript
# spelling (shellcheck SC1087).
_B_ON=""; _B_OFF=""
case "$STYLE" in
  markdown) _B_ON='**'; _B_OFF='**' ;;
  ansi)     _esc="$(printf '\033')"; _B_ON="${_esc}[1;33m"; _B_OFF="${_esc}[0m" ;;
esac

_warned=0
# warn <text> — a fact that is FALSE here, and the only kind that sets the found-a-problem
# flag its check returns. Survives `--only-problems`.
#
# THE ONE LINE IN THIS FILE THAT CARRIES EMPHASIS, AND THAT IS DELIBERATE. `good` is left
# plain, `note` and `hint` are left plain: a reader scanning `check` is looking for the row
# that is WRONG, and a page where every kind of line has its own decoration gives them
# nothing to find. Emphasis here tracks significance, so it goes on exactly the lines that
# set the found-a-problem flag.
#
# THE SIGIL STAYS OUTSIDE IT. `⚠ **text**`, never `**⚠ text**` — `session-banner.sh` filters
# this block with `grep -e '^⚠'` and the harness pins the same anchor, so the line must start
# with the sigil in every style.
warn() { _warned=1; printf '%s\n' "⚠ ${_B_ON}$*${_B_OFF}"; }
# good <text> — the same fact, true. Dropped by `--only-problems`; never silent otherwise.
good() { printf '%s\n' "✓ $*"; }
# note <text> — indented evidence under the line above it. Dropped by `--only-problems`.
note() { printf '%s\n' "    $*"; }
# hint <text> — the ONE command that addresses the warning above it. Survives
# `--only-problems`; emit at most one per check, which is what bounds the banner section.
hint() { printf '%s\n' "    ↳ $*"; }

# tier_note <tier> — what `fix` does with a row of this tier, said in `fix`'s own output so
# the human is never left to infer why something was reported and not repaired.
tier_note() {
  case "$1" in
    idempotent) printf '%s' "idempotent — repairing it has one right answer and re-running changes nothing" ;;
    ambiguous)  printf '%s' "ambiguous — whether this is even wrong is your call, so fix printed it and did nothing" ;;
    human)      printf '%s' "yours — acting on this is unsafe even when the diagnosis is right, so fix did nothing" ;;
    *)          printf '%s' "unknown tier — treated as print-only" ;;
  esac
}

# fn_of <id> / fixfn_of <id> — the ONLY place a row's id becomes a function name. Both
# forms build the name the same way, which is what makes the one list one list.
fn_of() { printf 'check_%s' "$(printf '%s' "$1" | tr '-' '_')"; }
fixfn_of() { printf 'fix_%s' "$(printf '%s' "$1" | tr '-' '_')"; }

# git_ok <dir> — is this a git checkout we may ask questions of? Every caller treats "no"
# as a reportable fact, never an error.
git_ok() {
  command -v git >/dev/null 2>&1 || return 1
  git -C "$1" rev-parse --git-dir >/dev/null 2>&1
}

# =========================================================================================
# CHECK 1 — template-behind (idempotent)
# =========================================================================================
# THE FACT: a stamp taken from this template clone would deliver what `origin` has.
#
# TWO EVIDENCE LINES, BECAUSE THE VERSION ALONE CANNOT SEE THIS. `check-template-version.sh`
# compares the `VERSION` file and is deliberately coarse — it detects drift across a bump
# and nothing finer, and its own header says a checkout parked on an old commit whose
# VERSION happens to equal the remote's is invisible to it. That invisible case is exactly
# what was measured twice in one day: stamping at `61535c9` while the default branch was
# three merges ahead reported `ok … (already linked)` for everything and changed nothing —
# output indistinguishable from a real stamp. So this row asks the commit graph too.
#
# THE VERSION VERDICT IS NOT RECOMPUTED HERE. It is delegated verbatim to the shipped
# helper, so there is no second reader of that question to drift from the first.
#
# NO NETWORK UNLESS ASKED. Without `--fetch` the comparison reads the remote-tracking ref
# already on disk, which can only ever UNDER-report — never a false alarm, and never a
# command that waits on a socket.
check_template_behind() {
  _warned=0
  if [ -z "$TEMPLATE" ]; then
    good "template clone: not locatable from here, so a stamp cannot be judged"
    note "this script was not run through a symlink into a template checkout"
    return 0
  fi
  if ! git_ok "$TEMPLATE"; then
    good "template clone at $TEMPLATE is not a git checkout — nothing to compare it to"
    return 0
  fi

  if [ "$FETCH" -eq 1 ]; then
    # A failed fetch is never a verdict. `GIT_TERMINAL_PROMPT=0` because the failure that
    # must not happen here is not an error, it is a HANG: an expired credential otherwise
    # asks for a username on the human's terminal.
    GIT_TERMINAL_PROMPT=0 git -C "$TEMPLATE" fetch --quiet origin >/dev/null 2>&1 || \
      note "(--fetch could not reach origin; comparing against the ref already on disk)"
  fi

  local ref behind version
  ref="$(git -C "$TEMPLATE" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null)"
  if [ -z "$ref" ]; then
    good "template clone: no origin/HEAD to compare against, so being behind cannot be seen"
    note "git -C $TEMPLATE remote set-head origin --auto   teaches it the default branch"
  else
    behind="$(git -C "$TEMPLATE" rev-list --count "HEAD..$ref" 2>/dev/null)"
    case "$behind" in
      ''|*[!0-9]*) good "template clone: cannot count commits against $ref, so it is not judged" ;;
      0)           good "template clone is level with $ref — a stamp from here delivers what origin has" ;;
      *)           warn "template clone is $behind commit(s) behind $ref — a stamp from here would be inert"
                   note "it would print 'already linked' for everything and change nothing"
                   hint "git -C $TEMPLATE pull --ff-only" ;;
    esac
  fi

  # The version half, delegated. Its output is multi-line and already written for a human.
  # `--fetch` is NOT passed on even when we were given it: the fetch above already updated
  # the remote-tracking ref this helper reads, so passing it would be a second network
  # round-trip for an answer that is already on disk.
  #
  # AND ITS ABSENCE IS ITSELF REPORTED. Silence here would let a level commit graph print a
  # clean row while the VERSION half of the same question went unasked — the one shape this
  # file exists to prevent, since "no line" and "nothing wrong" would then look identical.
  # A `note`, not a `warn`: a helper this instance never received is not a defect, and the
  # SessionStart path (`--only-problems`) drops it.
  if [ -f "$BIN/check-template-version.sh" ]; then
    version="$(bash "$BIN/check-template-version.sh" --template "$TEMPLATE" --instance "$ROOT" 2>/dev/null)"
    if [ -n "$version" ]; then
      _warned=1
      printf '%s\n' "$version" | sed 's/^/    /'
    fi
  else
    note "cannot compare VERSION drift: no check-template-version.sh at $BIN"
  fi
  return "$_warned"
}

# fix_template_behind — `git pull --ff-only`, and nothing else, ever.
#
# `--ff-only` IS THE IDEMPOTENCE. A merge or a rebase can conflict, and a conflicted
# template clone is a worse state than a stale one: it is stale AND now has a half-written
# working tree that a stamp would ship into every instance at once. Fast-forward or refuse.
# A dirty working tree refuses before the network call for the same reason.
fix_template_behind() {
  [ -n "$TEMPLATE" ] || { note "nothing to pull: no template checkout located"; return 0; }
  git_ok "$TEMPLATE" || { note "nothing to pull: $TEMPLATE is not a git checkout"; return 0; }
  if [ -n "$(git -C "$TEMPLATE" status --porcelain 2>/dev/null)" ]; then
    note "NOT pulled: the template checkout has uncommitted changes."
    note "A pull here is only safe when it is a fast-forward onto a clean tree. Deal with"
    note "those changes first: git -C $TEMPLATE status"
    return 0
  fi
  note "running: git -C $TEMPLATE pull --ff-only"
  if GIT_TERMINAL_PROMPT=0 git -C "$TEMPLATE" pull --ff-only 2>&1 | sed 's/^/      /'; then
    return 0
  fi
  note "the pull did not fast-forward — the checkout is unchanged. Resolve it by hand."
  return 0
}

# =========================================================================================
# CHECK 2 — unstamped-machinery (idempotent)
# =========================================================================================
# THE FACT: every file this template ships under `symlink/` is linked into this instance.
#
# THIS IS THE READER for the trap in the KB Finding "pulling the template half-upgrades
# every unstamped instance". An edit to an ALREADY-linked file reaches an instance the
# moment the template clone is pulled — `settings.json` included, because it is itself a
# symlink — while a NEW file stays unlinked until `install.sh` runs. So an instance ends up
# configured to call machinery it does not have, with no error to say so: measured, a
# SessionStart hook pointing at a file that did not exist. Until now that trap was prose in
# a knowledge base that a human had to remember to apply.
#
# WHY THE ON-DISK INVENTORY AND NOT ONLY THE GIT DIFF. After a merge the question is asked
# as `git diff --name-status <old>..<new> -- symlink/ | grep '^A'`, and `--since` below runs
# exactly that. But NO INSTANCE RECORDS `<old>`: there is no stamp receipt anywhere in this
# machinery, so from inside an instance that range cannot be constructed. The equivalent
# question that can always be answered is the one this asks by default — which of the files
# a stamp WOULD link are not linked here — and it is strictly stronger, because it also
# catches a file missed by an interrupted stamp or removed by hand. The enumeration is
# `find . -type f` under `symlink/`, byte for byte the one `install.sh` walks, so the two
# cannot come to disagree about what a stamp covers.
#
# EMPTY IS AN ANSWER, NOT SILENCE. "Nothing is unstamped" is the useful half of this check
# on most days and it is printed as a `✓` line with its count.
check_unstamped_machinery() {
  _warned=0
  if [ -z "$TEMPLATE" ] || [ ! -d "$TEMPLATE/symlink" ]; then
    good "unstamped machinery: no template checkout located, so nothing to compare"
    return 0
  fi

  local rel total=0 n=0 missing=""
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    total=$((total + 1))
    # A LINK, OR IT IS NOT STAMPED — and a REGULAR FILE HERE IS NOT STAMPED. `install.sh`
    # only ever symlinks a `symlink/` path (it moves anything else aside to `.bak.<ts>`
    # first), so a real file at one of these paths is a copy that no template pull will
    # ever reach again: it reads as present, the instance keeps calling it, and it silently
    # stops tracking the template. That is this row's whole subject, so it counts.
    # `-L` and not `-e`: `-e` is false for a DANGLING link, which is a different defect
    # (the banner's machinery probes own it) and must not be reported as unstamped here.
    if [ ! -L "$ROOT/$rel" ]; then
      n=$((n + 1))
      [ "$n" -le 12 ] && missing="${missing:+$missing
}    $rel"
    fi
  done <<EOF
$(cd "$TEMPLATE/symlink" 2>/dev/null && find . -type f | sed 's#^\./##' | sort)
EOF

  if [ "$total" -eq 0 ]; then
    good "unstamped machinery: the template ships no symlink/ files to compare"
    return 0
  fi
  if [ "$n" -eq 0 ]; then
    good "every one of the template's $total symlink/ files is linked here — nothing to stamp"
  else
    warn "$n of the template's $total symlink/ files are NOT linked in this instance"
    printf '%s\n' "$missing"
    [ "$n" -gt 12 ] && note "… and $((n - 12)) more"
    note "a merge alone never delivers a NEW file; only a stamp does:"
    hint "bash $TEMPLATE/install.sh $ROOT"
  fi

  # THE LITERAL POST-MERGE FORM, on request. `<old>..<new>` is `<--since>..HEAD` in the
  # template checkout, and EMPTY OUTPUT IS REPORTED — "this merge added no new files, so
  # nobody has homework" is precisely the answer worth having.
  if [ -n "$SINCE" ]; then
    if ! git_ok "$TEMPLATE"; then
      note "--since $SINCE: the template is not a git checkout, so the range cannot be read"
    elif ! git -C "$TEMPLATE" rev-parse --verify -q "$SINCE" >/dev/null 2>&1; then
      note "--since $SINCE: no such ref in $TEMPLATE"
    else
      local added
      added="$(git -C "$TEMPLATE" diff --name-status "$SINCE..HEAD" -- symlink/ 2>/dev/null | grep '^A' || true)"
      if [ -z "$added" ]; then
        note "$SINCE..HEAD added no symlink/ files — that range needs no stamp"
      else
        note "$SINCE..HEAD added these symlink/ files (a stamp is what delivers them):"
        printf '%s\n' "$added" | sed 's/^/      /'
      fi
    fi
  fi
  return "$_warned"
}

# fix_unstamped_machinery — re-stamp, by running the installer this template ships.
#
# `install.sh` only links, seeds-if-absent and sweeps dangling machinery links; it never
# removes instance content. That is what makes re-running it the idempotent repair rather
# than a risk, and it is why this is the only writing operation in the file besides the
# fast-forward pull above.
fix_unstamped_machinery() {
  [ -n "$TEMPLATE" ] || { note "nothing to stamp: no template checkout located"; return 0; }
  if [ ! -f "$TEMPLATE/install.sh" ]; then
    note "NOT stamped: $TEMPLATE/install.sh is missing"
    return 0
  fi
  note "running: bash $TEMPLATE/install.sh $ROOT"
  bash "$TEMPLATE/install.sh" "$ROOT" 2>&1 | sed 's/^/      /'
  return 0
}

# =========================================================================================
# CHECK 3 — config-uncommitted (AMBIGUOUS — SHIP-BLOCKER: never repaired)
# =========================================================================================
# THE FACT: `instance.config.json` / `instance.config.local.json` carry changes git has not
# recorded. That is ALL this says. It is a QUESTION, never a defect.
#
# On 2026-08-30 an instance carried an uncommitted `maxPrLoc: 2000 -> 500` that was a
# deliberate decision by the owner, taken minutes earlier, and completely indistinguishable
# from drift to anything that reads only the file. There is no `fix_config_uncommitted` in
# this file and there must never be one: reverting, staging or rewriting either file would
# have destroyed that choice, silently, while printing a success line.
#
# WHY ONLY TOP-LEVEL KEY NAMES ARE NAMED, AND NO VALUES. This output can land in session
# context. `people` maps humans to commit ADDRESSES — the banner's settings table excludes
# it for exactly this reason — so nothing nested is named and no value is ever printed. The
# scope test is indentation: a top-level key in these files sits at two spaces, `people`
# and `roleTiers` entries at four. It is a heuristic on a file this machinery itself
# writes, and it fails in the safe direction (a reformatted file names fewer keys, never
# more). The exact `git diff` command is printed instead, for a human, in their terminal.
check_config_uncommitted() {
  _warned=0
  if ! git_ok "$ROOT"; then
    good "config changes: this instance is not a git checkout, so nothing can be compared"
    return 0
  fi

  local f st keys n
  for f in instance.config.json instance.config.local.json; do
    if [ ! -f "$ROOT/$f" ]; then
      continue
    fi
    # TRACKED FIRST, AND THAT ORDER IS THE WHOLE CORRECTNESS OF THIS CHECK. `git status
    # --porcelain -- <path>` prints NOTHING for an ignored file no matter how heavily it
    # has been edited, and `instance.config.local.json` is gitignored in every stamped
    # instance — so reading emptiness as "matches git" published a confident, false "no
    # uncommitted change" about the one file most likely to have been hand-edited. Measured
    # on a real instance before this branch existed. Ask git what it TRACKS, then ask what
    # changed; never infer the first from the second.
    if ! git -C "$ROOT" ls-files --error-unmatch -- "$f" >/dev/null 2>&1; then
      if git -C "$ROOT" check-ignore -q -- "$f" 2>/dev/null; then
        good "$f is git-ignored here — per-machine by design, so there is nothing to commit"
      else
        good "$f is untracked — git holds no version of it to differ from"
      fi
      continue
    fi
    st="$(git -C "$ROOT" status --porcelain -- "$f" 2>/dev/null)"
    if [ -z "$st" ]; then
      good "$f matches git — no uncommitted change"
      continue
    fi

    keys="$(git -C "$ROOT" diff HEAD -- "$f" 2>/dev/null \
            | sed -n 's/^[+-]  \("[A-Za-z_$][A-Za-z0-9_$]*"\).*/\1/p' \
            | tr -d '"' | sort -u | tr '\n' ' ' | sed 's/ $//')"
    n="$(printf '%s' "$st" | sed -n '1s/^\(..\).*/\1/p')"
    warn "$f has uncommitted changes${keys:+ (${keys})}"
    note "git status code: '$n' (XY from git status --porcelain)"
    note "THIS IS A QUESTION, NOT A DEFECT — a value here can be a decision somebody made"
    note "minutes ago, and fix will not write, revert or stage this file. You decide:"
    hint "yours, not fix's: git -C $ROOT diff -- $f"
  done
  return "$_warned"
}

# =========================================================================================
# CHECK 4 — config-layers (ambiguous — nothing to repair, by construction)
# =========================================================================================
# THE FACT: which of the two config files won, per resolved key. A key can be set in the
# tracked file, read by everything, and still not be the one in force — `resolve-config.sh`
# merges `instance.config.local.json` over `instance.config.json` PER LEAF, so the answer
# differs entry by entry inside a map and is invisible in either file alone.
#
# DELEGATED, NEVER RE-DERIVED. `resolve-config.sh --dump` is the one implementation of that
# precedence; a second reader here is exactly the drift that would make this line lie.
#
# KEY NAMES ONLY, NEVER VALUES, AND NEVER `people`. Same boundary as the check above: this
# reaches session context, and that map holds commit addresses.
check_config_layers() {
  _warned=0
  if [ ! -f "$BIN/resolve-config.sh" ] || ! command -v python3 >/dev/null 2>&1; then
    good "config layers: not resolvable here (resolve-config.sh or python3 absent)"
    return 0
  fi
  local dump local_keys tracked_keys tracked_n local_n
  dump="$(bash "$BIN/resolve-config.sh" --instance "$ROOT" --dump 2>/dev/null || true)"
  if [ -z "$dump" ]; then
    good "config layers: nothing resolved (no readable config in $ROOT)"
    return 0
  fi
  # `<source> TAB <key> TAB <entry> TAB <value>`; field 4 is never read here.
  tracked_n="$(printf '%s\n' "$dump" | awk -F'\t' '$1=="tracked" && $2!="people"' | wc -l | tr -d ' ')"
  local_n="$(printf '%s\n' "$dump"   | awk -F'\t' '$1=="local"   && $2!="people"' | wc -l | tr -d ' ')"
  local_keys="$(printf '%s\n' "$dump" | awk -F'\t' '$1=="local" && $2!="people" {print ($3=="" ? $2 : $2 "." $3)}' \
                | sort -u | tr '\n' ' ' | sed 's/ $//')"
  tracked_keys="$(printf '%s\n' "$dump" | awk -F'\t' '$1=="tracked" && $2!="people" {print ($3=="" ? $2 : $2 "." $3)}' \
                  | sort -u | tr '\n' ' ' | sed 's/ $//')"
  # Counted per RESOLVED LEAF, not per top-level key, because that is the granularity the
  # precedence actually works at: a one-line local override moves one entry of `roleTiers`
  # and leaves every other entry tracked, and a per-file count would report that as the
  # whole map having been overridden.
  # BOTH SIDES ARE NAMED, not just the surprising one. "which layer won" has to be
  # answerable FOR EACH KEY, and a list of only the local winners leaves the reader
  # inferring the rest from a count — which is the same half-answer as printing the file
  # and letting them work out what is in force.
  if [ "$local_n" -gt 0 ]; then
    good "config resolves: $((local_n + tracked_n)) keys — $local_n from local, $tracked_n from tracked"
    note "local:   $local_keys"
    [ -n "$tracked_keys" ] && note "tracked: $tracked_keys"
  else
    good "config resolves: $tracked_n keys, all from tracked — no local override is in force"
    [ -n "$tracked_keys" ] && note "tracked: $tracked_keys"
  fi
  # NO TRAILING CAVEAT LINE. "values are not shown here" would read the same on a healthy
  # instance and a broken one, which is this command's own test for a line that does not
  # belong. Why values and `people` stay out is stated above, where the next editor reads it.
  return 0
}

# =========================================================================================
# CHECK 5 — tick-lock (HUMAN — SHIP-BLOCKER: never repaired)
# =========================================================================================
# THE FACT: whether a `/pm-loop` tick lock is held, claimed, or past its staleness
# threshold. The verdict is `tick-lock.sh status`'s, replayed here — this file has no
# opinion about what stale means and must never grow one, or the two would drift about the
# only question that matters.
#
# THERE IS NO `fix_tick_lock`, AND THERE MUST NEVER BE ONE. `scripts/tick-lock.sh release`
# is documented as the HUMAN's override. A tick that dispatched role agents can legitimately
# run long, so "stale" is a threshold, not a death certificate; clearing a lock on that
# evidence re-opens the double-dispatch that ran two ticks concurrently for 34 minutes on
# 2026-08-29, doing the same refinement work twice. Neither `.tick-lock` nor
# `.tick-lock.claim` is written, removed or rewritten anywhere in this file.
#
# `status` IS THE READ-ONLY PROBE and it is the right one to call here — the prohibition in
# `/pm-loop` is on a LAUNCHER calling `status` before `acquire`, which would rebuild the
# check-then-write race `acquire` exists to close. This command dispatches nothing.
check_tick_lock() {
  _warned=0
  local sh out rc
  sh=""
  [ -f "$ROOT/scripts/tick-lock.sh" ] && sh="$ROOT/scripts/tick-lock.sh"
  [ -z "$sh" ] && [ -f "$BIN/tick-lock.sh" ] && sh="$BIN/tick-lock.sh"
  if [ -z "$sh" ]; then
    good "tick lock: tick-lock.sh is not installed here, so no lock is being kept"
    return 0
  fi

  out="$(bash "$sh" status --instance "$ROOT" 2>&1)"; rc=$?
  case "$rc" in
    0) good "no tick lock held — the next /pm-loop dispatch takes it"
       case "$out" in *".tick-lock.claim"*) note "note: a claim file outlived its lock; the next acquire clears it" ;; esac ;;
    1) good "a /pm-loop tick is in flight (this is a live lock, not a fault)"
       printf '%s\n' "$out" | sed -n '1,3p' | sed 's/^/    /'
       case "$out" in *"No tick has claimed it yet"*) note "unclaimed: taken for a dispatch that is starting" ;; esac ;;
    *) warn "the tick lock needs YOUR decision — this is not repaired for you"
       printf '%s\n' "$out" | sed -n '1,4p' | sed 's/^/    /'
       note "a long tick is not a dead one. If you decide it is dead, YOU release it:"
       hint "yours, not fix's: bash $sh release --instance $ROOT" ;;
  esac
  return "$_warned"
}

# =========================================================================================
# CHECK 6 — orphan-processes (HUMAN — never repaired)
# =========================================================================================
# THE FACT: processes of YOURS whose parent is gone (`ppid 1`) are still running out of a
# directory under `worktreeRoot`. Nothing on this machine will ever reap them.
#
# WHY THIS ROW EXISTS. Measured 2026-08-31: an agent generating CPU load to reproduce a
# flaky suite left 34 orphans across three batches, every one with `ppid 1`, at ~24% of a
# core each — load average 310, 0% idle. The owner found it in Activity Monitor. The
# machinery that manages those very worktrees never noticed: `prune-worktrees.sh` does look
# for live processes, but only when somebody prunes, and it does not ask whose they are.
# This row is the line that would have printed all 34 at the next session start.
#
# `ppid 1` AND YOUR OWN UID ARE THE WHOLE FILTER, and together they are what make this
# narrow enough to print at all. A live process under a worktree is ordinary — an editor, a
# dev server someone is watching, this session. A live process under a worktree WHOSE PARENT
# IS GONE is nobody's by construction: there is no shell left to press Ctrl-C in. Own-uid,
# because another user's daemon is not this instance's business and its cwd is unreadable
# anyway (measured on the machine that produced the incident: 449 `ppid 1` processes, 200 of
# them other users' with no readable cwd; own-uid alone, 248 candidates and 248 cwds read).
#
# IT NEVER REPORTS ZERO ON A QUESTION IT COULD NOT ASK. Four ways it cannot answer, each
# said out loud instead: no config reader, no worktree root to compare against, no `ps`, or
# no readable cwd (neither `lsof` nor `/proc`, or a restricted one). "None found" is printed
# ONLY after a scan that could have found one, and it carries the two counts that make it
# checkable. Reporting zero on an unanswerable question is the failure this row is written
# against — see `CONVENTIONS.md`, "Anything you background must be reaped".
#
# NO COMMAND LINE IS EVER PRINTED, only `comm`. `check` output lands in session context and
# a full argv can carry a token or a path nobody chose to publish; the executable name is
# enough to recognise a spinner, and the human's own `ps -p` is one hint line away.
#
# TIER `human`, AND THERE IS NO `fix_orphan_processes`. A bounded background job is
# legitimate work and an orphan is not always a mistake — a deliberately detached build has
# `ppid 1` too. Killing a process on this evidence is exactly the class of repair this
# command does not perform.
check_orphan_processes() {
  _warned=0

  # WHERE TO LOOK: `worktreeRoot`, then the legacy `<reposRoot>/_wt`. The same two roots
  # `prune-worktrees.sh` scans and the same documented fallback, so the two readers cannot
  # come to disagree about where worktrees live. Delegated to `resolve-config.sh` for the
  # per-machine precedence rather than re-reading the files here.
  if [ ! -f "$BIN/resolve-config.sh" ] || ! command -v python3 >/dev/null 2>&1; then
    good "orphaned processes: the worktree roots are not resolvable here, so this is UNKNOWN"
    note "resolve-config.sh or python3 is absent — that is not a zero, it is an unasked question"
    return 0
  fi
  local wt repos d c roots=""
  wt="$(bash "$BIN/resolve-config.sh" --instance "$ROOT" worktreeRoot 2>/dev/null)" || wt=""
  repos="$(bash "$BIN/resolve-config.sh" --instance "$ROOT" reposRoot 2>/dev/null)" || repos=""
  wt="${wt/#\~/$HOME}"; repos="${repos/#\~/$HOME}"
  local configured=0 unreachable=""
  for d in "$wt" "${repos:+$repos/_wt}"; do
    [ -n "$d" ] || continue
    configured=$((configured + 1))
    # Canonicalised, because `lsof` reports a resolved cwd and macOS symlinks /tmp and
    # /var — an unresolved prefix match misses every process and the scan becomes a
    # silent no-op that looks exactly like a clean machine.
    c="$(cd "$d" 2>/dev/null && pwd -P)" || c=""
    if [ -z "$c" ]; then unreachable="${unreachable:+$unreachable, }$d"; continue; fi
    case "$roots" in *"|$c|"*) continue ;; esac
    roots="${roots}|$c|"
  done
  if [ -z "$roots" ]; then
    if [ "$configured" -eq 0 ]; then
      good "orphaned processes: this instance names no worktree root, so there is nowhere to scan"
      note "neither worktreeRoot nor reposRoot resolves here — nothing was scanned, and nothing is claimed"
    else
      good "orphaned processes: every configured worktree root is unreadable, so this is UNKNOWN"
      note "could not enter: $unreachable"
    fi
    return 0
  fi

  if ! command -v ps >/dev/null 2>&1; then
    good "orphaned processes: no ps on PATH, so no process can be asked about its parent"
    note "UNKNOWN, not zero — nothing was enumerated"
    return 0
  fi

  # POSIX `ps`: `-u <uid>` selects by effective user, `-o <keyword>=` suppresses the header.
  # `pid`, `ppid`, `etime` and `comm` are all in the POSIX keyword set and behave the same on
  # the BSD `ps` macOS ships and the procps one Linux does. `comm` and NOT `args` — see the
  # header. A uid rather than a name: `ps -o user=` truncates a long login name on macOS.
  local uid pslist
  uid="$(id -u 2>/dev/null)" || uid=""
  if [ -z "$uid" ]; then
    good "orphaned processes: cannot read your own uid, so 'whose process is it' is UNKNOWN"
    return 0
  fi
  pslist="$(ps -u "$uid" -o pid=,ppid=,etime=,comm= 2>/dev/null)" || pslist=""
  if [ -z "$pslist" ]; then
    good "orphaned processes: ps returned nothing for uid $uid, so this is UNKNOWN"
    note "an empty process table is not a result — nothing was scanned"
    return 0
  fi

  # THE CANDIDATES: your processes whose parent is gone. `ppid 1` is what "reparented to
  # launchd/init" looks like from outside, and it is the signature every one of the 34 had.
  local cands pidlist n_cand
  cands="$(printf '%s\n' "$pslist" | awk '$2 == 1 && $1 != 1 {print}')"
  n_cand="$(printf '%s' "$cands" | grep -c . || true)"
  if [ "$n_cand" -eq 0 ]; then
    good "no process of yours has ppid 1 — no orphan exists to be in a worktree"
    return 0
  fi
  pidlist="$(printf '%s\n' "$cands" | awk '{printf "%s%s", sep, $1; sep=","}')"

  # CWD, FROM ONE SOURCE, CHOSEN IN A STATED ORDER. `lsof -d cwd` answers for every pid in
  # a single call (0.19s for 449 pids, measured) and is what `prune-worktrees.sh` already
  # uses; `/proc/<pid>/cwd` is the fallback where lsof is absent. Neither present is an
  # UNANSWERABLE question, not a clean scan.
  local cwds="" pid dir line readable=0
  if command -v lsof >/dev/null 2>&1; then
    pid=""
    while IFS= read -r line; do
      case "$line" in
        p*) pid="${line#p}" ;;
        n*) dir="${line#n}"
            [ -n "$pid" ] || continue
            cwds="${cwds}${pid} ${dir}
"
            readable=$((readable + 1)); pid="" ;;
      esac
    done <<EOF
$(lsof -a -d cwd -n -P -Fpn -p "$pidlist" 2>/dev/null)
EOF
  elif [ -d /proc ]; then
    for pid in $(printf '%s\n' "$cands" | awk '{print $1}'); do
      dir="$(readlink "/proc/$pid/cwd" 2>/dev/null)" || dir=""
      [ -n "$dir" ] || continue
      cwds="${cwds}${pid} ${dir}
"
      readable=$((readable + 1))
    done
  else
    good "orphaned processes: $n_cand of yours have ppid 1, and where they run is UNKNOWN"
    note "no lsof and no /proc, so no process cwd is readable on this machine"
    note "that is why this is not reported as none found"
    return 0
  fi
  if [ "$readable" -eq 0 ]; then
    good "orphaned processes: $n_cand of yours have ppid 1, and where they run is UNKNOWN"
    note "not one cwd was readable (a restricted lsof, or every candidate exited mid-scan)"
    return 0
  fi

  # THE MATCH. A prefix test against each canonical root, and the root itself counts: a
  # process sitting in the root directory of a removed worktree is as unreapable as one
  # inside a live worktree. Collected first and printed once, so the warn line carries the
  # TOTAL — the number the reader acts on — rather than a running count.
  local hits=0 pids_hit="" detail="" matched r
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    pid="${line%% *}"; dir="${line#* }"
    matched=0
    while IFS= read -r r; do
      [ -n "$r" ] || continue
      case "$dir" in "$r"|"$r"/*) matched=1; break ;; esac
    done <<EOF
$(printf '%s\n' "$roots" | tr '|' '\n')
EOF
    [ "$matched" -eq 1 ] || continue
    hits=$((hits + 1))
    pids_hit="${pids_hit:+$pids_hit }$pid"
    # `etime` is field 3 and `comm` is everything after it — a path with a space in it is
    # one field to `$4` and would print truncated.
    [ "$hits" -le 12 ] && detail="${detail}    pid $pid  up $(printf '%s\n' "$cands" \
      | awk -v want="$pid" '$1 == want {e=$3; $1=$2=$3=""; sub(/^ +/, ""); print e "  " $0; exit}')  in $dir
"
  done <<EOF
$cwds
EOF

  if [ "$hits" -eq 0 ]; then
    good "no orphan runs out of a worktree root ($n_cand of your processes have ppid 1, $readable cwds read)"
    return 0
  fi
  warn "$hits orphaned process(es) of yours (ppid 1) run out of a worktree — nothing will reap them"
  printf '%s' "$detail"
  [ "$hits" -gt 12 ] && note "… and $((hits - 12)) more not listed"
  note "a bound on the child is what stops this — CONVENTIONS.md, 'Anything you background'"
  hint "yours, not fix's: ps -p ${pids_hit%% *} -o command= ; then kill $pids_hit"
  return 1
}

# =========================================================================================
# THE DRIFT GUARD — a refusal, not a convention
# =========================================================================================
# TWO WAYS THE ONE LIST CAN BE WIRED WRONG, AND BOTH ARE FATAL RATHER THAN NOTED.
#
#   1. A `fix_<id>` defined for a row whose declared tier is NOT `idempotent`. That is the
#      exact shape of the two ship-blockers, and it is invisible in review the day somebody
#      adds one — a function beside four other functions, in a file full of them.
#   2. A row with no `check_<id>` at all. Bash would call a command that does not exist,
#      print `command not found` and hand back 127 — which this file's own convention reads
#      as "a problem was found", so an idempotent row added without its checker would go
#      straight to running its REPAIR on the strength of a typo.
#
# So neither is a rule: `check` and `fix` both REFUSE TO RUN, loudly, exit 2. `check` is
# guarded and not only `fix`, because a command that reports on an instance while carrying a
# fixer it must not have should not be trusted to report either. The banner form is already
# gone by here, by design: it repairs nothing, and its whole contract is that nothing comes
# between it and the hook.
assert_list_is_wired() {
  local id tier rogue="" unwired=""
  while IFS='|' read -r id tier _; do
    [ -n "$id" ] || continue
    declare -F "$(fn_of "$id")" >/dev/null 2>&1 || unwired="${unwired:+$unwired, }$id"
    [ "$tier" = idempotent ] && continue
    if declare -F "$(fixfn_of "$id")" >/dev/null 2>&1; then
      rogue="${rogue:+$rogue, }$(fixfn_of "$id") (tier: $tier)"
    fi
  done <<EOF
$CHECKS
EOF
  [ -z "$rogue" ] && [ -z "$unwired" ] && return 0
  if [ -n "$rogue" ]; then
    echo "ai-bridge: REFUSING TO RUN — a repair exists for a tier that must never be repaired:" >&2
    echo "           $rogue" >&2
    echo "           The tier declared in CHECKS is the only dispatch. Delete the function." >&2
  fi
  if [ -n "$unwired" ]; then
    echo "ai-bridge: REFUSING TO RUN — a row in CHECKS has no check function:" >&2
    echo "           $unwired" >&2
    echo "           Add check_<id>, or remove the row. A missing one reads as a problem." >&2
  fi
  exit 2
}
assert_list_is_wired

# rows_for <mode> — the one list, filtered. `banner` keeps only the rows that declare
# themselves fit for the SessionStart path. Every consumer below reads THIS list: `check`
# through here, `fix` and `--list` straight off `$CHECKS`. There is no second enumeration
# of checks anywhere in this file, which is the property the harness asserts.
rows_for() {
  if [ "$1" = banner ]; then
    printf '%s\n' "$CHECKS" | awk -F'|' '$3=="yes"'
  else
    printf '%s\n' "$CHECKS"
  fi
}

if [ "$LIST" -eq 1 ]; then
  printf '%s\n' "$CHECKS" | awk -F'|' '{printf "%s\t%s\t%s\n", $1, $2, $3}'
  exit 0
fi

# =========================================================================================
# FORM 2 — check
# =========================================================================================
if [ "$FORM" = check ]; then
  mode=all; [ "$BANNER_ONLY" -eq 1 ] && mode=banner
  header_printed=0
  while IFS='|' read -r id tier _; do
    [ -n "$id" ] || continue
    out="$("$(fn_of "$id")")"; rc=$?
    if [ "$ONLY_PROBLEMS" -eq 1 ]; then
      # THE SessionStart CONTRACT: only fire what is true. A clean instance prints
      # BYTE-NOTHING here, because a block that appears every session becomes wallpaper and
      # wallpaper is how the lines that matter come to be skipped.
      [ "$rc" -eq 0 ] && continue
      if [ "$header_printed" -eq 0 ]; then
        printf '%s\n' "⚠️  ai-bridge check — state worth a look (/ai-bridge check for all of it):"
        header_printed=1
      fi
      # The verdict and its one command, nothing else. See `hint` above for the bound.
      printf '%s\n' "$out" | grep -e '^⚠' -e '^    ↳'
      continue
    fi
    printf '%s\n' "$out"
  done <<EOF
$(rows_for "$mode")
EOF
  exit 0
fi

# =========================================================================================
# FORM 3 — fix
# =========================================================================================
# THE SAME LIST, THE SAME ORDER, AND NO NAMES. This loop cannot tell you what
# `config-uncommitted` is; it reads the tier the row declares and dispatches on that alone.
# The two ship-blockers therefore hold by construction rather than by care: there is no
# branch here that could be pointed at a config file or a lock file.
echo "ai-bridge fix — acting ONLY on the idempotent tier."
echo "                Config files and tick locks are NEVER written, reverted, staged,"
echo "                cleared or rewritten by this command. They are reported."
echo
while IFS='|' read -r id tier _; do
  [ -n "$id" ] || continue
  printf '%s\n' "── $id [$tier]"
  out="$("$(fn_of "$id")")"; rc=$?
  printf '%s\n' "$out"
  if [ "$rc" -eq 0 ]; then
    echo
    continue
  fi
  if [ "$tier" = idempotent ]; then
    fixfn="$(fixfn_of "$id")"
    if declare -F "$fixfn" >/dev/null 2>&1; then
      "$fixfn"
    else
      note "no repair is implemented for this row — reported only"
    fi
  else
    note "NOT ACTED ON — $(tier_note "$tier")"
  fi
  echo
done <<EOF
$CHECKS
EOF
exit 0
