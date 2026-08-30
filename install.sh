#!/usr/bin/env bash
#
# install.sh — provision (or refresh) an ai-bridge INSTANCE, or link the CONFIG LAYER.
#
#   Usage:
#     install.sh [TARGET]              # install/refresh an instance at TARGET (default: cwd)
#     install.sh --instance [TARGET]   # the same thing, stated explicitly
#     install.sh --config              # link config/required/ into ~/.claude (CLAUDE_CONFIG_DIR wins)
#     install.sh --uninstall [TARGET]  # remove only the instance symlinks this created
#     install.sh --config --uninstall  # remove only the config-layer symlinks this created
#     install.sh --help
#
# INSTANCE mode does three things:
#   1. SYMLINKS the generic machinery in `symlink/` into TARGET (file granularity,
#      absolute targets). Updates to the template propagate to every instance.
#      These paths are gitignored in the instance (managed block in .gitignore).
#   2. COPIES the `seed/` content into TARGET *only if absent* — never clobbering
#      instance data (objectives/projects/knowledge/log/config/CLAUDE.md).
#   3. LINKS the group's product repos into TARGET/repos/ — one symlink each, via
#      scripts/link-repos.sh — so the peer repos are reachable from inside the
#      instance without ever being nested in it. Gitignored, and skipped while
#      reposRoot is still the seeded placeholder. Re-run that script on its own
#      after cloning a repo; you don't need a full refresh for it.
#   4. On a FIRST stamp, at a terminal, OFFERS to collect the team's GitHub logins and
#      commit emails into `people` + `defaultOwner`, and writes this clone's
#      `instance.config.local.json`. One batched prompt; nothing is written until you
#      confirm it. Skipped (with the instruction printed) when stdin is not a terminal,
#      never asked on a refresh, and it never overwrites a value already there.
#
# CONFIG mode links `config/required/` into the Claude Code config dir, one FILE at a
# time — never a whole directory (see the CONFIG LAYER block below). That is the WHOLE
# set: three agents this repo's own role agents probe for by absolute path
# (`code-architect`, `deep-bug-scan`, `plan-architect`). Everything else under
# `~/.claude` belongs to `cbmono/ai-setup` and is installed from there — see
# docs/claude-config-ownership.md for why, and for what not to re-add here.
# Absence is safe in the direction that matters: an instance stamp never needs `config/`,
# and the config layer never needs an instance. Deleting `config/required/` leaves
# `--config` linking nothing, exit 0; deleting `config/` itself makes `--config` exit 2
# saying there is nothing to link, which is a refusal to do nothing, not a breakage.
#
# Idempotent: re-running relinks cleanly and reports already-linked entries.
# Backs up any conflicting real file as <name>.bak.<epoch> before linking.
set -euo pipefail

TEMPLATE_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_DIR_FOR_GUARD="$TEMPLATE_DIR"
# Refuse to install from a git WORKTREE.
#
# This installer derives its source from `dirname $0` and then creates symlinks that
# point AT that path — an instance's whole machinery set. (`ai-setup`'s own installer
# carries the same guard for `~/.claude/*`.) A linked worktree is temporary by design: `ExitWorktree` or
# `git worktree remove` deletes it, and every symlink created from it dangles the moment
# it goes. That failure is silent — nothing errors at install time, and it surfaces later
# as commands and hooks that have simply vanished.
#
# Not hypothetical: this project's own convention is to work on a branch in a worktree,
# which puts a checkout of this very script one `cd` away from the wrong answer. It was
# recorded as a structural hazard during a plan review and went unfixed until now.
#
# The test is `--git-dir` vs `--git-common-dir`: equal in the main working tree, different
# in a linked one (the former becomes <main>/.git/worktrees/<name>). Both are asked for in
# absolute form, because one side is otherwise relative and the comparison would always
# differ. A plain `git init` repo — what the test fixtures build — is a MAIN tree, so this
# never fires there; outside git entirely it cannot fire at all.
#
# The message deliberately does NOT compute the main checkout's path. Both obvious
# derivations are wrong once the git metadata lives apart from the working tree
# (`git init --separate-git-dir`, or a `.git` file pointing elsewhere): `dirname` of the
# common dir yields the metadata's parent, and even `git worktree list` reports the git
# dir rather than the main tree in that setup — measured both. Printing a confidently
# wrong path to paste is worse than printing none, so it names the command that always
# knows instead of guessing. Don't "improve" this by deriving it.
if command -v git >/dev/null 2>&1; then
  _gd="$(git -C "$SRC_DIR_FOR_GUARD" rev-parse --absolute-git-dir 2>/dev/null || true)"
  _gc="$(git -C "$SRC_DIR_FOR_GUARD" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
  if [ -n "$_gd" ] && [ -n "$_gc" ] && [ "$_gd" != "$_gc" ]; then
    cat >&2 <<GUARDEOF
error: refusing to install from a git worktree.

  source:      $SRC_DIR_FOR_GUARD
  git dir:     $_gd

Every symlink this creates would point into the worktree, and deleting the worktree
(ExitWorktree, or git worktree remove) would silently break all of them — nothing
fails now, the commands and hooks just disappear later.

Run it from the repository's MAIN working tree instead. To find it:
  git -C $SRC_DIR_FOR_GUARD worktree list      # the first entry is the main tree
GUARDEOF
    exit 2
  fi
fi

SYMLINK_SRC="$TEMPLATE_DIR/symlink"
SEED_SRC="$TEMPLATE_DIR/seed"
BEGIN_MARK="# >>> ai-bridge machinery (symlinked) >>>"
END_MARK="# <<< ai-bridge machinery <<<"

MODE="install"
# Which half of the repo this run is about. `instance` is the default because a BARE
# directory argument has always meant "stamp an instance here" — three live instances and
# upgrade.sh call it that way, so `--instance` is only the explicit spelling of the
# existing behaviour, never a new requirement.
LAYER="instance"
LAYER_FLAG=""
TARGET=""
for arg in "$@"; do
  case "$arg" in
    --uninstall) MODE="uninstall" ;;
    --config|--instance)
      # Mutually exclusive, and said so rather than letting the last flag win: the two
      # write to completely different places, so a run that meant one and did the other
      # is not something to guess at.
      if [ -n "$LAYER_FLAG" ] && [ "$LAYER_FLAG" != "$arg" ]; then
        echo "error: --config and --instance are mutually exclusive" >&2; exit 2
      fi
      LAYER_FLAG="$arg"; LAYER="${arg#--}" ;;
    --help|-h)
      # Range must cover the whole header block above (through the "Backs up…"
      # line) — extend it when you add lines there, or --help truncates silently.
      # tests/config-layer.test.sh asserts the flags appear in the output, which is
      # what notices a stale range instead of leaving --help quietly truncated.
      sed -n '3,42p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    -*) echo "error: unknown flag '$arg'" >&2; exit 2 ;;
    *)
      [ -z "$TARGET" ] || { echo "error: multiple target directories given" >&2; exit 2; }
      TARGET="$arg" ;;
  esac
done
if [ "$LAYER" = "config" ] && [ -n "$TARGET" ]; then
  echo "error: --config takes no target directory (it links into" >&2
  echo "       \${CLAUDE_CONFIG_DIR:-\$HOME/.claude}); got '$TARGET'" >&2
  exit 2
fi

# ===========================================================================
# CONFIG LAYER (--config) — link config/ into the Claude Code config dir.
# ===========================================================================
#
# WHY IT IS HERE AT ALL. ai-bridge used to depend on a *separate* config repo for four
# things, and all four failed SILENTLY: the `@~/.claude/claude-defaults.md` import every
# instance inherited from seed/CLAUDE.md (now inlined there, so nothing can dangle), and
# three probed-for agents — `code-architect`, `deep-bug-scan`, `plan-architect`. A fresh
# laptop is now one clone and one install.
#
# AND WHY IT IS NOW ONLY THREE FILES. Closing those four dependencies by forking the
# whole of `cbmono/ai-setup`'s `.claude/` tree bought a second problem: two installers
# claiming `${CLAUDE_CONFIG_DIR:-~/.claude}`, 24 entries shipped by both, 14 diverged, and
# ownership decided by whichever ran last. ai-setup owns that directory now. This layer
# keeps exactly the paths ai-bridge itself PROBES for and nothing else — the smallest set
# that makes a fresh laptop work without cloning another repo. Re-adding anything here
# re-creates the collision; `tests/config-ownership.test.sh` fails if you do.
# Full reasoning: docs/claude-config-ownership.md.
#
# THE ARROW IS ONE-WAY. `symlink/` must never *require* `config/`. The role agents keep
# probing with `test -f`, so an instance stamped on a machine that never ran `--config`
# works — it loses a second opinion, not a feature. `tests/config-layer.test.sh` asserts
# a config-less stamp. `rm -rf config/required` must leave `--config` at exit 0 with
# nothing linked; `rm -rf config` must leave an INSTANCE stamp completely unaffected.
#
# EVERY LINK IS PER FILE, NEVER PER DIRECTORY. agents/, commands/, hooks/, scripts/ and
# skills/ are DROP-IN directories — a skill or plugin installer can write a new
# subdirectory into ~/.claude/skills at any moment. Linking such a directory as a unit
# aims it at this repo's working tree, so every drop-in lands INSIDE a public git repo.
# That is not hypothetical: it is how four uninvited skills got committed to the parent
# repo on 2026-08-22, three of them dangling symlinks its installer would then have
# pushed into every consumer's ~/.claude. Per-file linking leaves ~/.claude/<dir> a real
# directory that owns its own contents, so a drop-in can never reach this checkout and
# no .gitignore allow-list is needed to keep it out. Do not "simplify" this to whole-dir
# links — `tests/config-layer.test.sh` asserts a fresh drop-in stays outside the repo.
CONFIG_SRC="$TEMPLATE_DIR/config"
CONFIG_TIERS="required"
# Honour CLAUDE_CONFIG_DIR: when it is set, Claude Code reads settings, agents and hooks
# from there instead of ~/.claude, so installing into $HOME would put the layer somewhere
# nothing loads it from. It is the same expression ai-setup's settings.json uses to
# reference its hooks, so the two installers cannot disagree about where the config dir is.
CONFIG_DEST="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

# Every linkable file, as "<tier><TAB><relative path>".
#
# Three kinds of file are never linked, at any depth: `README.md` (a repo doc — and in
# commands/ Claude Code would register it as the command `/README`), `*.example.json`
# (copy-from templates: a linked one is clutter that dangles if this checkout moves), and
# `settings.json`. This layer no longer ships a settings.json at all — it is ai-setup's,
# and it is the one file that can already hold permissions and plugins a human tuned by
# hand, so a second installer must never touch it. The exclusion stays because it is
# cheap and because a settings.json appearing under `config/` would otherwise be linked
# silently; a stale link from when this layer DID ship one is retired by config_sweep.
#
# ITS STATUS CANNOT TRAVEL OUT OF HERE, and that is a property of the interface, not an
# oversight left to fix later. Its stdout IS the payload, every caller consumes it as
# `$(config_entries)` inside a here-doc, and the `cd`/`find` statuses vanish into a
# pipeline whose status is `sort`'s. So no caller can ask "did discovery succeed?" — which
# is why the destructive consumer does not ask. `config_src_probe` names the cause once
# per run, and `config_sweep`'s refusal is stated over the RESULT instead. See both.
config_entries() {
  local tier
  for tier in $CONFIG_TIERS; do
    [ -d "$CONFIG_SRC/$tier" ] || continue
    ( cd "$CONFIG_SRC/$tier" && find . -type f -print ) | sed 's#^\./##' | sort \
    | while IFS= read -r rel; do
        [ -n "$rel" ] || continue
        # Parameter expansion, not basename: this scan runs a few times per invocation
        # and one fork per file per pass is a measurable cost on a loaded machine.
        case "${rel##*/}" in
          README.md|settings.json|*.example.json|.DS_Store) continue ;;
        esac
        printf '%s\t%s\n' "$tier" "$rel"
      done
  done
}

# Can this run LOOK at its own source tree? Named per directory, once per run, before
# anything is counted — the mirror of the probe config_sweep runs over the DESTINATION,
# and for the same reason: "nothing is shipped" and "I could not read the shipment" must
# never print the same thing.
#
# This is the cheap half of the repair, not the fix. It reports the CAUSE where the cause
# is a permission on a directory, which is every mode measured — but it is a cause-based
# check, so it can only ever cover the causes someone thought of. The guard that does not
# depend on that is in config_sweep, stated over the result.
CONFIG_SRC_FAIL=0
config_src_probe() {
  local tier d
  CONFIG_SRC_FAIL=0
  for tier in $CONFIG_TIERS; do
    [ -d "$CONFIG_SRC/$tier" ] || continue
    while IFS= read -r d; do
      [ -n "$d" ] || continue
      { [ -r "$d" ] && [ -x "$d" ]; } && continue
      echo "  fail  ${d#"$TEMPLATE_DIR"/} — cannot list this source directory; the files" >&2
      echo "        under it were NOT discovered, so nothing here can act on their absence." >&2
      CONFIG_SRC_FAIL=$((CONFIG_SRC_FAIL+1))
    done <<EOF
$( printf '%s\n' "$CONFIG_SRC/$tier"
   find "$CONFIG_SRC/$tier" -type d -print 2>/dev/null || true )
EOF
    # `find`'s own status, kept rather than discarded — the backstop for a traversal that
    # fails some way a per-directory probe cannot predict. Reported only when the probe
    # found nothing, so one cause is never counted twice.
    if [ "$CONFIG_SRC_FAIL" -eq 0 ] \
       && ! find "$CONFIG_SRC/$tier" -type f -print >/dev/null 2>&1; then
      echo "  fail  config/$tier — could not be traversed; its file list is INCOMPLETE." >&2
      CONFIG_SRC_FAIL=$((CONFIG_SRC_FAIL+1))
    fi
  done
  [ "$CONFIG_SRC_FAIL" -eq 0 ]
}

# What the source probe could not do, said out loud. Separate from config_sweep_warn
# because the two failures have opposite remedies: that one asks you to fix the CONFIG
# DIR, this one asks you to fix the CHECKOUT.
config_src_warn() {
  [ "$CONFIG_SRC_FAIL" -gt 0 ] || return 0
  echo "warn  $CONFIG_SRC_FAIL source directory/ies could not be listed (named above), so the" >&2
  echo "      set of files this layer ships was discovered INCOMPLETE. Nothing was retired" >&2
  echo "      on the strength of it. Make $CONFIG_SRC readable and listable (r-x)," >&2
  echo "      then re-run." >&2
  return 1
}

# Top-level entries the config layer manages — the roots of the dangling-link sweep.
# Roots to sweep for retired links. Deliberately NOT just the roots present in the
# current source tree: if the last file under `config/required/commands/` is removed,
# that root disappears from `config_entries`, the sweep stops searching
# `$CONFIG_DEST/commands`, and its dangling links stay registered — a retired command that
# still shows up, or a retired hook that exits 127 on every startup. The whole point of the
# sweep is the case where a source file is GONE, so it cannot be driven by what remains.
#
# The fixed list is the set this installer has ever managed. Add to it when a new root
# ships; never prune it, for the same reason RETIRED is never pruned — an install from
# years ago still has the directory.
# It is ALSO what performs the handover to ai-setup: this layer used to ship commands/,
# hooks/, output-styles/, scripts/, skills/, MEMORY.md and settings.json, so the roots
# stay listed and `--config` retires those now-dangling links on the next run. Pruning
# them would strand a retired command that still registers and a retired hook that exits
# 127 on every launch.
CONFIG_MANAGED_TOPS="agents commands hooks output-styles scripts skills rules claude-defaults.md MEMORY.md settings.json"
config_tops() { { config_entries | cut -f2 | sed 's#/.*##'; printf '%s\n' $CONFIG_MANAGED_TOPS; } | sort -u; }

# Print the first DIRECTORY component of $1 that is a symlink under the config dir.
#
# This guard is what keeps the per-file fix honest. A whole-directory symlink left over
# from another setup turns "$CONFIG_DEST/agents/x.md" into a write INSIDE that other
# checkout — modifying a repo nobody asked us to touch, silently, and leaving the config
# dir with no file of its own. So this layer NEVER writes through one.
#
# It is not hypothetical and it is not rare: ai-setup — which owns this directory — links
# `~/.claude/agents` as a whole directory. So on any machine that ran its installer, every
# entry here has a symlinked parent, by design rather than by accident. That is why
# "refuse" is no longer the only answer; see config_install.
config_link_parent() {
  local rel="$1" dir cur part
  case "$rel" in */*) dir="${rel%/*}" ;; *) return 1 ;; esac
  cur="$CONFIG_DEST"
  local IFS=/
  for part in $dir; do
    cur="$cur/$part"
    if [ -L "$cur" ]; then printf '%s' "$cur"; return 0; fi
  done
  return 1
}

# Is a `.bak.<epoch>` entry a superseded copy of a link this run has just recreated?
#
# WHY IT IS NEEDED. Both halves of this installer move a conflicting entry aside as
# `<name>.bak.<epoch>` before linking. When the conflict was itself a symlink of OURS
# pointing into a template that has MOVED, the backup is a dangling symlink whose entire
# content is the old, wrong path — and neither retire sweep can remove it, because
# `ours`/`config_ours` test the target against the template's CURRENT location and a moved
# link fails that test by construction. Measured: one plain `mv` of the checkout followed
# by one repair install left 38 dead `.bak.*` links in a single fixture instance, and the
# real move left 122 across two. Each one is noise that makes the next dangling-link
# report unreadable, which is how this class of failure stays invisible.
#
# THE THREE CONDITIONS ARE THE WHOLE SAFETY PROPERTY, and the middle one most of all:
#   · the NAME is one this installer writes — `.bak.<digits>` — and nothing else;
#   · it is a dangling SYMLINK, never a regular file. A `.bak.*` FILE is a human's own
#     content that this installer moved aside, and deleting that would spend the property
#     the whole script rests on. A dangling symlink holds no content at all, only a path
#     string — which is printed as it goes rather than dropped;
#   · the entry it backs up EXISTS AGAIN as a link of ours, i.e. this run has already
#     recreated the thing the backup is a copy of. That is what makes it *superseded*
#     rather than merely dead, and it is why an uninstall — which removes the link instead
#     of recreating it — sweeps nothing and leaves every backup where it is.
#
# Takes the ownership predicate as an argument so the instance and config halves share one
# rule: the debris is identical because the backup path that creates it is.
dead_backup() { # <ownership-predicate> <relative path> <absolute path>
  case "$2" in *.bak.[0-9]*) ;; *) return 1 ;; esac
  # The glob above only requires the FIRST character after ".bak." to be a digit, so
  # "SCHEMA.md.bak.1700000000.manual" — not this installer's format at all — would
  # otherwise pass. Require the WHOLE suffix after the last ".bak." to be digits only;
  # anything else (letters, punctuation, a further extension, or nothing) is somebody
  # else's name, not ours to remove.
  case "${2##*.bak.}" in ''|*[!0-9]*) return 1 ;; esac
  [ -L "$3" ] && [ ! -e "$3" ] || return 1
  "$1" "${2%.bak.*}"
}

# True only when CONFIG_DEST/$1 is a symlink we created (points into this checkout's
# config/), decided by the target rather than by name — the same `ours` test the instance
# half uses, and the reason an uninstall can never remove somebody else's link.
config_ours() {
  local dst="$CONFIG_DEST/$1"
  [ -L "$dst" ] || return 1
  case "$(readlink "$dst")" in "$CONFIG_SRC"/*) return 0 ;; esac
  return 1
}

# Remove links into this checkout's config/ whose target is gone.
#
# Same reasoning as the instance half's step 2b, and the same narrowness: the link must
# point INTO $CONFIG_SRC *and* its target must be missing. A dangling entry is worse than
# an absent one — Claude Code registers a command whose file has vanished, and a hook
# whose script is gone exits 127 on every launch — so retiring a config file has to sweep
# too. Scoped to the entries this layer manages, never the whole config dir: ~/.claude
# also holds plugins/, projects/ and sessions/, none of it ours to walk.
#
# THE ROOT LIST IS AN ARRAY, AND THAT IS LOAD-BEARING. It used to be a space-separated
# string expanded as `find $roots`, with a `# shellcheck disable=SC2086` above it so lint
# could not object. `CLAUDE_CONFIG_DIR` is a path a human chooses — `~/Library/Application
# Support/claude` is an ordinary thing to pick — and one space in it split every root into
# fragments that exist nowhere. `find` then printed its errors to the /dev/null this
# function already redirects, returned non-zero into the `|| true`, and the sweep reported
# NOTHING while exiting 0. Measured on the handover fixture: 21 retired / 0 dangling
# without a space in the path, 2 retired / 19 dangling with one — the two survivors being
# the top-level entries, whose `find` was already quoted. Everything under `commands/`,
# `hooks/`, `scripts/`, `output-styles/` and `agents/` stayed registered and dangling,
# which is precisely the "retired command still shows up, retired hook exits 127" failure
# the comment above describes. Pinned by a fixture whose config dir has a space in it.
#
# THE ROOTS INCLUDE WHAT ai-setup MOVED ASIDE, and this one needs no unusual permissions at
# all — it is the order this repo recommends. ai-setup links each top-level entry as a whole
# unit, renaming the real directory to `<root>.bak.<epoch>` first. After it runs,
# `$CONFIG_DEST/commands` is a SYMLINK, so the `[ ! -L … ]` test below drops it, and the 11
# links this layer must retire sit in `commands.bak.<epoch>/` — a directory, so the
# top-level `-maxdepth 1` scan does not see them either. Measured on the real in-place
# upgrade in the recommended order: `--config` retired **2 of 21** and reported "Those 2
# path(s) … they moved", leaving 19 dangling, un-retired and unreported; `--config
# --uninstall` exited **0** with three links STILL LIVE into the checkout the user had just
# detached from. The same failure as the unquoted `find $roots`, reached by a third route.
# So a moved-aside copy of a managed root is itself a sweep root — restricted to
# `.bak.<digits>`, the name both installers write, and to real directories, because a `.bak`
# FILE is a human's own content that an installer moved and never ours to walk into.
#
# `find` CANNOT ANSWER "NOTHING TO RETIRE" WHEN IT COULD NOT LOOK, and both calls used to
# end `2>/dev/null || true`, discarding precisely that distinction. A config dir whose
# `commands/` is mode 0300 — writable but not readable, which is what a `chmod` typo or an
# odd umask leaves behind — measured **exit 0, 11 `retire` lines, "Those 11 path(s) … they
# moved", 0 fail, 0 warn, and ten dangling commands still registered**: the identical
# failure the checked `rm` below was added for, in the DISCOVERY half rather than the
# REMOVAL half. Unreadable is the worse of the two because it is silent — mode 500 at least
# made `rm` fail. So every directory the sweep must list is probed first and NAMED if it
# cannot be listed, and `find`'s own status is kept as a backstop for whatever a probe
# cannot predict.
#
# THE LOOP RUNS IN THIS SHELL, not down a pipe, so $CONFIG_RETIRED survives it. The count
# is what lets the caller point at cbmono/ai-setup: a user whose 19 links just vanished is
# owed the name of the repo that ships them now.
#
# EVERY `rm` HERE IS CHECKED, and $CONFIG_SWEEP_FAIL is why. The same defect that made
# `config_install` print "3 linked" having linked nothing lived in this function for one
# more round: `rm -f` ran unchecked while the counter and the `retire` line ran regardless,
# and errexit is suspended for the whole call by `config_install || config_rc=$?`. A config
# dir whose `commands/` is not writable — mode 500, or root-owned after a `sudo` install —
# measured **21 `retire` lines and "Those 21 path(s) … moved" for 11 actual removals, exit
# 0, ten dangling commands still registered**, and on `--uninstall` three links still LIVE
# into the checkout the user had just detached from. The only signal was `rm:` on stderr,
# under a success epilogue. This function IS the handover for ~21 paths, so a count printed
# regardless of what it did is the worst possible thing for it to print: the user is told
# the migration completed and given a repo to re-install from, while a dangling command
# stays registered. The counter now moves only after the write succeeded, and the caller
# turns any failure into a non-zero exit through config_sweep_warn.
CONFIG_RETIRED=0
CONFIG_DETACHED=0
CONFIG_SWEEP_FAIL=0
# Absolute paths the CALLER's own loop owns and has already reported on, newline-delimited
# and newline-terminated. Only `detach` mode reads it, and only so one unremovable link is
# not counted and named twice — once by config_uninstall's entries loop and once here.
CONFIG_SWEEP_SKIP=""
config_sweep() { # [retire|detach]
  local mode="${1:-retire}" t b d l rel was n_roots=0 blind=0 find_rc=0 scan="" part="" sorted=""
  local roots=()
  CONFIG_RETIRED=0
  CONFIG_DETACHED=0
  CONFIG_SWEEP_FAIL=0
  while IFS= read -r t; do
    [ -n "$t" ] || continue
    if [ -d "$CONFIG_DEST/$t" ] && [ ! -L "$CONFIG_DEST/$t" ]; then
      roots+=("$CONFIG_DEST/$t"); n_roots=$((n_roots+1))
    fi
    # …and the copy another installer moved aside, which is where this layer's links go when
    # ai-setup takes the root over. An unmatched glob stays literal, and `-d` rejects it.
    for b in "$CONFIG_DEST/$t".bak.*; do
      [ -d "$b" ] && [ ! -L "$b" ] || continue
      case "${b##*.bak.}" in ''|*[!0-9]*) continue ;; esac
      roots+=("$b"); n_roots=$((n_roots+1))
    done
  done <<EOF
$(config_tops)
EOF
  # CAN WE LOOK? Probed per directory so the answer names the path, and before anything is
  # counted, because "0 to retire" and "could not read the directory" must never print the
  # same. `find` lists an unreadable directory (its parent supplies the name) and only fails
  # to descend, so this sees the one it is about to be blind inside.
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    { [ -r "$d" ] && [ -x "$d" ]; } && continue
    case "$d" in
      "$CONFIG_DEST") rel="." ;;
      *) rel="${d#"$CONFIG_DEST"/}" ;;
    esac
    echo "  fail   $rel — cannot list this directory; links under it were NOT examined" >&2
    CONFIG_SWEEP_FAIL=$((CONFIG_SWEEP_FAIL+1)); blind=$((blind+1))
  done <<EOF
$( printf '%s\n' "$CONFIG_DEST"
   if [ "$n_roots" -gt 0 ]; then find "${roots[@]}" -type d -print 2>/dev/null || true; fi )
EOF
  # The status of each `find`, kept rather than discarded into `|| true`. The probe above is
  # more precise when it fires; this is the backstop for a traversal that fails some other
  # way, and it reports only when the probe found nothing, so one cause is not counted twice.
  if ! part="$(find "$CONFIG_DEST" -maxdepth 1 -type l -print 2>/dev/null)"; then find_rc=1; fi
  scan="$part"
  if [ "$n_roots" -gt 0 ]; then
    if ! part="$(find "${roots[@]}" -type l -print 2>/dev/null)"; then find_rc=1; fi
    scan="$scan
$part"
  fi
  if [ "$find_rc" -ne 0 ] && [ "$blind" -eq 0 ]; then
    echo "  fail   . — could not fully traverse $CONFIG_DEST; this sweep is INCOMPLETE" >&2
    CONFIG_SWEEP_FAIL=$((CONFIG_SWEEP_FAIL+1))
  fi

  # AN EMPTY SOURCE SET IS NOT A LICENCE TO DELETE, and this is the guard that says so.
  #
  # `config_sweep` decides what to retire by asking "is this link's target still in the
  # source set?". An empty source set therefore does not mean "the source is gone, retire
  # everything" — it can equally mean "I could not look", and until this guard existed the
  # function took the destructive reading of both. Measured on a real in-place upgrade,
  # three ways — `config/required` at 0400, `config/required/agents` at 0000, and
  # `config/required/agents` at 0400 — each identical: exit 0, a `retire` line for every
  # link including the three this layer still ships, ZERO left, and no warning. The 0400
  # subdirectory case produced no stderr at all. `retire` is a success word printed for a
  # data loss.
  #
  # WHY THIS IS NOT A STATUS CHECK. `find . -type f` in a directory that is unreadable but
  # executable exits 0 and prints nothing. There is no error to propagate, so `pipefail`,
  # keeping `find`'s status, or checking the subshell would every one of them pass cleanly
  # on the exact input that empties the layer. config_src_probe above catches the causes we
  # know; this catches the consequence, whatever caused it.
  #
  # WHAT IT ASSERTS, over two sets rather than over an exit code:
  #     discovery returned NO entries, while links into $CONFIG_SRC still exist
  #     => a refusal, not a retirement.
  # The one state where an empty source set really does mean "nothing is shipped" is a
  # tier directory that is GONE — `rm -rf config/required`, the AUTONOMY.md contract this
  # file documents, where retiring those links is exactly right. So a tier that is still
  # PRESENT and yielded nothing is the discriminator, and it is checked here rather than
  # inferred from a status. A tier deliberately emptied but left in place lands on the
  # refusing side: it is the rarer intent, the message says how to express it, and being
  # wrong in that direction costs a re-run instead of a layer.
  #
  # TWO REFUSALS, AND NEITHER SUBSUMES THE OTHER. The probe's fires on an INCOMPLETE list
  # even when it is non-empty — one unreadable subdirectory among several readable ones
  # still yields files, so the set-emptiness test below is structurally blind to it while
  # the links under that directory read as dangling and get retired. The set test fires on
  # an EMPTY list whatever the cause, including causes no probe was written for. Each
  # covers the other's blind spot; both are pinned by mutation in config-layer.test.sh.
  # It is also what makes config_src_warn's "nothing was retired on the strength of it"
  # true rather than merely likely — a warning that overstates is the same defect again.
  #
  # RETIRE MODE ONLY, both of them. On `--uninstall` the removals are what the user asked
  # for, not an inference from the source set, so a blind read must not stop them.
  if [ "$mode" != detach ] && [ "${CONFIG_SRC_FAIL:-0}" -gt 0 ]; then
    echo "  fail   . — REFUSING to retire: the source list is INCOMPLETE (the directory it" >&2
    echo "         could not read is named above). This sweep retires whatever is MISSING" >&2
    echo "         from that list, so acting on it would retire files that are present and" >&2
    echo "         merely unlisted. Nothing was retired." >&2
    CONFIG_SWEEP_FAIL=$((CONFIG_SWEEP_FAIL+1))
    return 0
  fi
  if [ "$mode" != detach ]; then
    local n_src=0 n_ours=0 tier src_present=0
    for tier in $CONFIG_TIERS; do
      [ -d "$CONFIG_SRC/$tier" ] && src_present=1
    done
    while IFS= read -r l; do [ -n "$l" ] && n_src=$((n_src+1)); done <<EOF
$(config_entries)
EOF
    if [ "$n_src" -eq 0 ] && [ "$src_present" -eq 1 ]; then
      while IFS= read -r l; do
        [ -n "$l" ] || continue
        case "$(readlink "$l")" in "$CONFIG_SRC"/*) n_ours=$((n_ours+1)) ;; esac
      done <<EOF
$scan
EOF
      if [ "$n_ours" -gt 0 ]; then
        echo "  fail   . — REFUSING to retire: this run discovered no files under" >&2
        echo "         $CONFIG_SRC, yet $n_ours link(s) here still point into it." >&2
        echo "         A source directory that exists and lists nothing is 'I could not" >&2
        echo "         look', not 'nothing is shipped', and only the second one licenses a" >&2
        echo "         delete. Nothing was retired. Make $CONFIG_SRC" >&2
        echo "         readable and listable (r-x) and re-run; if you really meant to drop" >&2
        echo "         the layer, remove the tier directory or run --config --uninstall." >&2
        CONFIG_SWEEP_FAIL=$((CONFIG_SWEEP_FAIL+1))
        return 0
      fi
    fi
  fi

  # De-duplicated into a variable first, so `sort`'s status is looked at rather than
  # discarded into the here-doc that consumes it. A failed `sort` leaves `$sorted` empty
  # and the loop below therefore removes nothing, which is the safe direction — but it
  # used to do that silently, and silence is the whole defect class this function keeps
  # meeting. Cheap and correct; it is not the guard above, which does not need a status.
  if ! sorted="$(printf '%s\n' "$scan" | sort -u)"; then
    echo "  fail   . — could not de-duplicate the link scan; this sweep is INCOMPLETE" >&2
    CONFIG_SWEEP_FAIL=$((CONFIG_SWEEP_FAIL+1))
    sorted=""
  fi
  while IFS= read -r l; do
    [ -n "$l" ] || continue
    rel="${l#"$CONFIG_DEST"/}"
    case "$(readlink "$l")" in
      "$CONFIG_SRC"/*)
        if [ ! -e "$l" ]; then
          if ! rm -f "$l" 2>/dev/null; then
            echo "  fail   $rel — cannot retire this dangling link" >&2
            CONFIG_SWEEP_FAIL=$((CONFIG_SWEEP_FAIL+1)); continue
          fi
          CONFIG_RETIRED=$((CONFIG_RETIRED+1))
          echo "  retire $rel (no longer shipped by the config layer)"
          continue
        fi
        # LIVE, and ours. On an install that is nothing to act on — it is a link to a file
        # this layer still ships. On an UNINSTALL it is the opposite: a link still pointing
        # into the checkout the user is detaching from. config_uninstall's own loop walks
        # `config_entries`, i.e. paths spelled as they are shipped, so it cannot see one
        # stranded inside a `<root>.bak.<epoch>` directory that ai-setup moved aside — which
        # is exactly where the three that survived the measured uninstall were.
        [ "$mode" = detach ] || continue
        case "$CONFIG_SWEEP_SKIP" in
          *"
$l
"*) continue ;;
        esac
        if ! rm -f "$l" 2>/dev/null; then
          echo "  fail   $rel — cannot remove this link; it is STILL pointing into this checkout" >&2
          CONFIG_SWEEP_FAIL=$((CONFIG_SWEEP_FAIL+1)); continue
        fi
        CONFIG_DETACHED=$((CONFIG_DETACHED+1))
        echo "  detach $rel (was still linked into this checkout)"
        continue ;;
    esac
    # Not ours by target, so the branch above cannot see it — but it may be OUR OWN dead
    # backup of a link we relinked a moment ago. See dead_backup() for why that is the one
    # thing safe to delete here. The config layer accumulates this debris exactly as the
    # instance half does: 24 links dangled in ~/.claude when the checkout moved.
    if dead_backup config_ours "$rel" "$l"; then
      was="$(readlink "$l")"
      if ! rm -f "$l" 2>/dev/null; then
        echo "  fail   $rel — cannot remove this dead backup (was -> $was)" >&2
        CONFIG_SWEEP_FAIL=$((CONFIG_SWEEP_FAIL+1)); continue
      fi
      echo "  sweep  $rel (dead backup of a relinked file, was -> $was)"
    fi
  done <<EOF
$sorted
EOF
}

# Where the paths this layer just retired went. Printed only when something WAS retired, so
# a steady-state run stays quiet. Without it the handover tells a user what vanished and
# not where it went: on the machine this split was measured on, one `--config` run retired
# 19 live links and named `cbmono/ai-setup` zero times in anything it printed.
config_handover_note() {
  [ "$CONFIG_RETIRED" -gt 0 ] || return 0
  echo "      Those $CONFIG_RETIRED path(s) are not gone from your setup — they moved."
  echo "      cbmono/ai-setup owns $CONFIG_DEST now and installs them: clone it and run"
  echo "      its install.sh to get them back. Why, and what not to re-add here:"
  echo "        docs/claude-config-ownership.md"
}

# What the sweep could NOT do, said out loud, and non-zero so a script can see it.
#
# Called by both halves — `config_install` and `config_uninstall` share the sweep, and the
# earlier fix for this defect class landed on `config_install`'s own writes only, leaving
# its sibling to report a full retirement it had not performed. A partial handover is worse
# than a refused one: the paths that survived are dangling links Claude Code still
# registers, and the epilogue has already pointed the user at another repo to install from.
# It counts what the sweep could not LOOK AT as well as what it could not remove, because a
# directory it cannot list is not "nothing to retire" — that was blocker B3, measured as
# exit 0 with ten dangling commands still registered.
config_sweep_warn() {
  [ "$CONFIG_SWEEP_FAIL" -gt 0 ] || return 0
  echo "warn  $CONFIG_SWEEP_FAIL path(s) the sweep could not finish (named above). A link it" >&2
  echo "      could not remove is still registered and still dangling, and a directory it" >&2
  echo "      could not list may hold more. The counts above exclude them. Make" >&2
  echo "      $CONFIG_DEST and its subdirectories readable and writable, then re-run." >&2
  return 1
}

config_require_src() {
  if [ ! -d "$CONFIG_SRC" ]; then
    echo "error: this checkout has no config layer ($CONFIG_SRC)." >&2
    echo "       Nothing to link. An instance install (install.sh [TARGET]) never needs it." >&2
    exit 2
  fi
  if [ -L "$CONFIG_DEST" ]; then
    echo "error: $CONFIG_DEST is itself a symlink ($(readlink "$CONFIG_DEST"))." >&2
    echo "       This expects a real directory that owns your runtime state (plugins/," >&2
    echo "       projects/, history). Replace the symlink with a real directory first." >&2
    exit 2
  fi
}

config_install() {
  local tier rel src dst dstdir bak off tgt n_link=0 n_ok=0 n_moved=0 n_refused=0 n_else=0 n_fail=0 reported=" "
  config_require_src
  # BEFORE the link loop and before the sweep, so a source tree this run cannot read is
  # named while the run still has everything it needs to name it — and so the two writes
  # that follow are already known to be acting on a partial list.
  config_src_probe || true

  # NO two-tier duplicate refusal any more. It guarded the case where `required` and
  # `opinionated` both declared one path — whichever ran second would move the first aside
  # as a .bak and shadow it. There is one tier now, so the check could not fire, and an
  # unreachable guard is one no test can cover. What replaced it is stronger and does fire:
  # `tests/config-ownership.test.sh` derives the whole shippable set from the `test -f`
  # probes in `symlink/`, so a second tier cannot appear here unnoticed in the first place.
  # The LAST unchecked write in this half, and it is checked for the reason blocker A
  # existed: fixing the writes one loop noticed and leaving the sibling it did not is how a
  # false success survives a round of review. Its failure is currently reported per file by
  # the `mkdir -p "$dstdir"` guard below, but only because every shipped entry happens to
  # live in a subdirectory — an incidental guarantee, not a stated one. A config dir that
  # cannot be created is a refusal, not a run with nothing to do.
  if ! mkdir -p "$CONFIG_DEST" 2>/dev/null; then
    echo "error: cannot create $CONFIG_DEST." >&2
    echo "       Nothing was written. Check the permissions on its parent directory." >&2
    return 1
  fi
  echo "Linking the ai-bridge config layer into $CONFIG_DEST"
  while IFS=$'\t' read -r tier rel; do
    [ -n "$rel" ] || continue
    src="$CONFIG_SRC/$tier/$rel"; dst="$CONFIG_DEST/$rel"
    off="$(config_link_parent "$rel" || true)"
    # A symlinked parent means another config provider owns this directory. Two cases, and
    # only one of them is a problem:
    #
    #   · THE ENTRY ALREADY RESOLVES THROUGH IT. That provider ships this path — which is
    #     ai-setup, shipping the same three probed-for agents. Our contract for the
    #     required tier is that the file EXISTS on this machine, not that our copy is the
    #     one used, so the guarantee is already met: report it and write nothing. Without
    #     this, `--config` would exit non-zero on every machine that ran ai-setup's
    #     installer — the normal configuration, not an edge case — and the order the two
    #     installers ran in would change the outcome.
    #   · IT DOES NOT RESOLVE. Nobody ships it, and we cannot write it without writing
    #     into someone else's checkout. Refuse, name the directory, print the fix.
    #
    # `-f`, NOT `-e`. `-e` is true for a DIRECTORY, so a directory named `code-architect.md`
    # inside the provider's tree would count as "provided": this run would write nothing,
    # exit 0, and the `test -f ~/.claude/agents/code-architect.md` probe in
    # `symlink/.claude/agents/qa-reviewer.md` would still fail — silently, in a session. The
    # contract is "a FILE exists at this path", so the test has to be the same one the
    # consumer makes. This line is the whole content of its own commit; the fixture that
    # pins it is in `tests/config-layer.test.sh` (a directory in the provider's slot).
    if [ -n "$off" ] && [ -f "$CONFIG_DEST/$rel" ]; then
      echo "  ok    $rel (provided by $off -> $(readlink "$off"))"; n_else=$((n_else+1)); continue
    fi
    if [ -n "$off" ]; then
      n_refused=$((n_refused+1))
      case "$reported" in
        *" $off "*) ;;
        *)
          reported="$reported$off "
          # THE FIRST OPTION IS THE PROVIDER'S OWN INSTALLER, and it is printed first
          # because the `mv` used to be printed alone — actively harmful advice on the
          # normal machine. cbmono/ai-setup owns this config dir and links these roots as
          # whole directories BY DESIGN, so following a bare `mv` there deactivates every
          # agent, command and hook it ships, and its next run moves the replacement aside
          # again: the two installers ping-pong. The `mv` is right only for a link that is
          # nobody's design — some other tool's leftover — so it is offered second, and it
          # says which case it is for.
          echo "  skip  ${rel%/*}/ — $off is a symlink -> $(readlink "$off")" >&2
          echo "        Linking through it would write into that other checkout, so nothing" >&2
          echo "        was written. If that link is cbmono/ai-setup's — it owns" >&2
          echo "        $CONFIG_DEST and links these directories as units — run ITS" >&2
          echo "        install.sh; it ships this file and the requirement is then met." >&2
          echo "        Only if the link belongs to no installer, replace it with a real" >&2
          echo "        directory, keeping whatever it holds:" >&2
          echo "          mv $(printf '%q' "$off") $(printf '%q' "$off").bak.\$(date +%s) && mkdir -p $(printf '%q' "$off")" >&2
          ;;
      esac
      continue
    fi
    if [ -L "$dst" ]; then
      tgt="$(readlink "$dst")"
      if [ "$tgt" = "$src" ]; then
        echo "  ok    $rel (already linked)"; n_ok=$((n_ok+1)); continue
      fi
      # Ours, but aimed at the other tier: the file changed tier between two runs. Our
      # own link is not worth preserving, so relink rather than leave a .bak symlink
      # behind — the backup path below is for a REAL file, which is never ours to lose.
      #
      # The one `rm` here that does not report, and deliberately so: a failure FALLS
      # THROUGH to the `mv`-aside below, which is checked, names the file and counts a
      # failure — so the outcome is already reported, once, by the write that actually
      # matters. Silencing the duplicate `rm:` line is the only change; with one tier the
      # branch is unreachable anyway ($tgt can only be $src). Flagged in review as an
      # unchecked write, kept explicit here so the next reader does not have to re-derive
      # that it is the one place where falling through IS the check.
      case "$tgt" in "$CONFIG_SRC"/*) rm -f "$dst" 2>/dev/null || true ;; esac
    fi
    # EVERY WRITE IS CHECKED, and the reason is that none of them used to be. `mkdir -p`,
    # `mv` and `ln -s` all ran unchecked while the `link`/counter lines ran regardless — and
    # `set -e` cannot catch it, because the only caller is `config_install || config_rc=$?`,
    # which suspends errexit for the whole function by construction. Measured with `agents/`
    # at mode 500: three `Permission denied` on stderr, `Done. 3 linked`, exit 0, and zero
    # links created. The consumers of this layer are `test -f` probes, so a false "3 linked"
    # is invisible for the rest of the session — the role agent simply skips its fan-out.
    # A failure is now named per file, counted separately from success, and returns 1.
    dstdir="$(dirname "$dst")"
    if ! mkdir -p "$dstdir" 2>/dev/null; then
      echo "  fail  $rel — cannot create $dstdir" >&2
      n_fail=$((n_fail+1)); continue
    fi
    if [ -e "$dst" ] || [ -L "$dst" ]; then
      bak="$dst.bak.$(date +%s)"
      if ! mv "$dst" "$bak" 2>/dev/null; then
        echo "  fail  $rel — cannot move the entry in the way aside" >&2
        n_fail=$((n_fail+1)); continue
      fi
      echo "  moved $rel -> ${bak##*/}"; n_moved=$((n_moved+1))
    fi
    if ! ln -s "$src" "$dst" 2>/dev/null; then
      echo "  fail  $rel — cannot create the symlink" >&2
      n_fail=$((n_fail+1)); continue
    fi
    echo "  link  $rel"; n_link=$((n_link+1))
  done <<EOF
$(config_entries)
EOF

  # NO settings.json BLOCK, deliberately. This layer used to link its own baseline here.
  # It is ai-setup's file now, and it is the one file in the config dir that can already
  # hold permissions and plugins a human tuned by hand — the only place where replacing a
  # value could widen what Claude is allowed to *do*. Two installers writing it is exactly
  # the collision this split removes, so ai-bridge does not write, merge, or even report on
  # it. A link left over from when this layer DID ship one dangles the moment
  # config/opinionated/settings.json goes, and config_sweep below retires it.

  config_sweep

  echo "Done. $n_link linked, $n_ok already in place, $n_moved moved aside."
  # Counted and reported separately from "already in place": those are OUR links, these are
  # another layer's, and conflating them would hide the fact that this run wrote nothing.
  [ "$n_else" -eq 0 ] || echo "      $n_else already provided by another config layer — nothing written for those."
  config_handover_note
  # ACCUMULATED, not returned from the first branch that fires. An unwritable config dir
  # produces link failures AND sweep failures at once, and returning on the first would
  # hide the second — leaving the "still registered and still dangling" line unprinted in
  # exactly the run where it matters most.
  local rc=0
  if [ "$n_fail" -gt 0 ]; then
    echo "warn  $n_fail file(s) could not be written (above) — the config dir is not writable" >&2
    echo "      for them. Nothing here is partially applied: each failure is per file." >&2
    rc=1
  fi
  if [ "$n_refused" -gt 0 ]; then
    echo "warn  $n_refused file(s) NOT linked: a directory in the way is a symlink (above)." >&2
    echo "      Fix those directories and re-run; nothing was written through them." >&2
    rc=1
  fi
  config_sweep_warn || rc=1
  config_src_warn || rc=1
  [ "$rc" -eq 0 ] || return "$rc"
  echo "Next: restart Claude Code (/exit, then \`claude\`) so it re-scans agents and commands."
  return 0
}

config_uninstall() {
  config_require_src
  config_src_probe || true
  echo "Removing ai-bridge config-layer symlinks from $CONFIG_DEST"
  # `rm` IS CHECKED HERE for the same reason it is in config_install: `rm` failing on an
  # unwritable directory printed "  rm  <path>" anyway, because errexit is suspended by
  # `config_uninstall || config_rc=$?` and nothing looked at the status. Measured with
  # `commands/` and `agents/` at mode 500: three `rm` lines, 21 `retire` lines, 8 removals,
  # exit 0 — and THREE LINKS STILL LIVE into the checkout the user had just detached from.
  # An uninstall that says it detached and did not is worse than one that refuses.
  local tier rel n_fail=0 handled=""
  while IFS=$'\t' read -r tier rel; do
    [ -n "$rel" ] || continue
    # Recorded whether or not the `rm` below runs, so the sweep's detach pass never counts
    # or names a path this loop already owns. Without it, an unwritable `agents/` reports
    # each of its three links twice.
    handled="$handled
$CONFIG_DEST/$rel"
    if config_ours "$rel"; then
      if rm "$CONFIG_DEST/$rel" 2>/dev/null; then
        echo "  rm    $rel"
      else
        echo "  fail  $rel — cannot remove this link; it is STILL pointing into this checkout" >&2
        n_fail=$((n_fail+1))
      fi
    fi
  done <<EOF
$(config_entries)
EOF
  # No explicit settings.json removal: this layer does not ship one, and a link left from
  # when it did is dangling — config_sweep retires it by target, along with every other
  # link into this checkout whose file is gone.
  #
  # DETACH, not just retire. The loop above walks `config_entries`, i.e. paths spelled the
  # way this layer ships them, so it cannot see a LIVE link of ours that is no longer
  # spelled that way — the three in `agents.bak.<epoch>/` after ai-setup took the root over,
  # which a measured `--config --uninstall` left resolving into the just-detached checkout
  # while exiting 0. An uninstall that reports success and did not detach is worse than one
  # that refuses, so the sweep removes live links into this checkout too on this path only.
  CONFIG_SWEEP_SKIP="$handled
"
  config_sweep detach
  CONFIG_SWEEP_SKIP=""
  # It no longer says "*.bak.* backups were left untouched" without qualification, because
  # the detach pass above removes links into THIS checkout wherever it finds them — including
  # inside a `<root>.bak.<epoch>` directory another installer moved aside, which is where the
  # three that survived a measured uninstall were. A `.bak.*` regular FILE is still never
  # touched: that is a human's content.
  echo "Done. Your runtime state and your own real files were left untouched, backups"
  echo "      included — apart from links into this checkout, which is what you asked to remove."
  [ "$CONFIG_DETACHED" -eq 0 ] || \
    echo "      $CONFIG_DETACHED further link(s) into this checkout were detached (above)."
  config_handover_note
  local rc=0
  if [ "$n_fail" -gt 0 ]; then
    echo "warn  $n_fail link(s) into this checkout could NOT be removed (named above) — this" >&2
    echo "      uninstall is INCOMPLETE and those paths still resolve into it. Make" >&2
    echo "      $CONFIG_DEST and its subdirectories writable and re-run." >&2
    rc=1
  fi
  config_sweep_warn || rc=1
  config_src_warn || rc=1
  return "$rc"
}

if [ "$LAYER" = "config" ]; then
  config_rc=0
  if [ "$MODE" = "uninstall" ]; then config_uninstall || config_rc=$?
  else config_install || config_rc=$?; fi
  exit "$config_rc"
fi

TARGET="$(cd "${TARGET:-$PWD}" 2>/dev/null && pwd || true)"
[ -n "$TARGET" ] || { echo "error: target directory does not exist" >&2; exit 2; }
[ -d "$SYMLINK_SRC" ] || { echo "error: template missing $SYMLINK_SRC" >&2; exit 2; }

# Name the seeded workspace file after the group so an open editor window is
# identifiable (VS Code shows the .code-workspace *filename* — there's no top-level
# name field). Group = instance dir name minus the _ai-bridge- prefix.
WS_GROUP="$(basename "$TARGET")"; WS_GROUP="${WS_GROUP#_ai-bridge-}"
WS_NAME="${WS_GROUP}.code-workspace"

# Relative paths of every machinery file to symlink.
machinery_paths() {
  ( cd "$SYMLINK_SRC" && find . -type f | sed 's#^\./##' | sort )
}

ours() {  # is TARGET/$1 a symlink we created (points into this template)?
  local dst="$TARGET/$1"
  [ -L "$dst" ] && case "$(readlink "$dst")" in "$SYMLINK_SRC"/*) return 0 ;; esac
  return 1
}

if [ "$MODE" = "uninstall" ]; then
  echo "Removing ai-bridge machinery symlinks from $TARGET"
  # The repos/ view first, and via the TEMPLATE's copy of the script rather than
  # the installed symlink — the loop below is about to delete that symlink, and
  # running the template copy also works if it was already removed by hand.
  ( cd "$TARGET" && bash "$SYMLINK_SRC/scripts/link-repos.sh" --remove ) || true
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    if ours "$rel"; then rm "$TARGET/$rel"; echo "  unlinked $rel"; fi
  done <<EOF
$(machinery_paths)
EOF
  echo "Done. Seed content, instance data, and backups were left untouched."
  exit 0
fi

echo "Installing ai-bridge instance at $TARGET"

# Is this the first stamp, or a refresh of an existing instance? Decided BEFORE
# seeding, since seeding is what creates instance.config.json. Only the awaiting
# queue below needs to know, and it needs to badly: see there for why.
# Read a boolean from instance.config.json without requiring jq. Absent key, absent
# file, or an unreadable file all yield the DEFAULT — absence must never flip a
# behaviour to the unsafe side, and here the default is the caller's business.
cfg_bool() { # <key> <default> <config-path>
  # No jq dependency, and NO BRE ALTERNATION. `\(true\|false\)` is a GNU sed extension:
  # BSD sed matches nothing and this function silently returned the default forever, so
  # `board: false` was ignored. Measured — it is the third time today that `\|` outside
  # ERE has produced a silent wrong answer in this codebase. Two fixed-string greps
  # instead; `false` is checked FIRST so a malformed file cannot turn an opt-out into an
  # opt-in.
  _k="$1"; _d="$2"; _f="$3"
  [ -f "$_f" ] || { printf '%s' "$_d"; return 0; }
  if grep -q "\"$_k\"[[:space:]]*:[[:space:]]*false" "$_f" 2>/dev/null; then printf 'false'
  elif grep -q "\"$_k\"[[:space:]]*:[[:space:]]*true" "$_f" 2>/dev/null; then printf 'true'
  else printf '%s' "$_d"; fi
}

FIRST_STAMP=no
[ -e "$TARGET/instance.config.json" ] || FIRST_STAMP=yes

# 1. Seed content — copy only what's absent (never clobber instance data).
if [ -d "$SEED_SRC" ]; then
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    # The workspace file is seeded under a group-specific name (see WS_NAME above).
    if [ "$rel" = "bridge.code-workspace" ]; then
      existing="$(find "$TARGET" -maxdepth 1 -name '*.code-workspace' 2>/dev/null | head -1)"
      if [ -n "$existing" ]; then
        echo "  keep  $(basename "$existing") (workspace exists)"
      else
        # The seed ships terminal.integrated.cwd commented out with a __BRIDGE_DIR__
        # placeholder; uncomment it with this instance's absolute path so every new
        # terminal in the workspace starts in the instance rather than the group
        # root — see the comment in seed/bridge.code-workspace for why the wrong
        # cwd silently hides /pm-loop and /new-project. Whole-line
        # replacement, so a marker that ever stops matching degrades to "no pin"
        # rather than to a broken workspace file. Escaped for sed's replacement
        # side ('&' means "the match", '\' escapes, '|' is our delimiter) so a path
        # containing any of them can't corrupt the file. JSON-escaped first (a
        # literal '\' or '"' in a path would otherwise emit an invalid string).
        ws_dir="$(printf '%s' "$TARGET" | sed 's/["\\]/\\&/g; s/[\\&|]/\\&/g')"
        sed "s|^ *// \"terminal.integrated.cwd\": \"__BRIDGE_DIR__\",|    \"terminal.integrated.cwd\": \"$ws_dir\",|" \
          "$SEED_SRC/$rel" > "$TARGET/$WS_NAME"
        echo "  seed  $WS_NAME"
        # No live setting line means the marker stopped matching the seed; say so
        # rather than leaving a silently unpinned workspace. (Checking for a
        # leftover placeholder wouldn't work — a drifted line is still a comment.)
        if ! grep -q '^ *"terminal\.integrated\.cwd":' "$TARGET/$WS_NAME"; then
          echo "  warn  $WS_NAME: terminal cwd not stamped; set terminal.integrated.cwd to $TARGET by hand" >&2
        fi
      fi
      continue
    fi
    src="$SEED_SRC/$rel"; dst="$TARGET/$rel"
    dstdir="$(dirname "$dst")"
    if [ -e "$dst" ]; then
      echo "  keep  $rel (exists)"
    elif [ "$(basename "$rel")" = ".gitkeep" ] && [ -d "$dstdir" ] && [ -n "$(ls -A "$dstdir" 2>/dev/null)" ]; then
      # The dir already has real content — a placeholder .gitkeep would just be clutter.
      echo "  skip  $rel (dir already populated)"
    else
      mkdir -p "$dstdir"
      cp "$src" "$dst"
      echo "  seed  $rel"
    fi
  done <<EOF
$(cd "$SEED_SRC" && find . -type f | sed 's#^\./##' | sort)
EOF
fi

# 1b. The awaiting-you queue, created ONLY on the first stamp.
#
# AWAITING.md is opt-in by presence: the project-manager refreshes it only when
# it exists and never creates it, so deleting it turns the startup nudge off for
# good. That switch is the whole design — but it also means a brand-new instance
# would start with the queue OFF, and the SessionStart nudge would never fire
# until someone happened to read the docs and touch the file. So the installer
# provides the initial file, exactly once.
#
# It must NOT run on a refresh: re-creating the file would silently undo a
# deliberate `rm`, which is the one thing the off switch has to survive. That's
# what FIRST_STAMP guards. It's also gitignored, so this never becomes tracked
# state. Content is a valid empty queue, so session-banner.sh stays silent until
# the first tick fills it in.
if [ "$FIRST_STAMP" = yes ] && [ ! -e "$TARGET/AWAITING.md" ]; then
  cat > "$TARGET/AWAITING.md" <<'AWAITING'
# Awaiting you

Derived and gitignored — **do not hand-edit**. Rewritten each `/pm-loop` tick
from `projects/*/tasks/*.md`. Delete this file to turn the queue off for good;
the loop never recreates it. Last refreshed: never (no tick has run yet).

## 🔴 Awaiting you (0)
_None._
AWAITING
  echo "  seed  AWAITING.md (queue on; delete it to turn the startup nudge off)"
elif [ "$FIRST_STAMP" = no ] && [ ! -e "$TARGET/AWAITING.md" ]; then
  echo "  skip  AWAITING.md (absent by choice — run 'touch AWAITING.md' to re-enable)"
fi

# 1c. The board snapshot, created ONLY on the first stamp — same contract, same
# reason, same guard as AWAITING.md above.
#
# SNAPSHOT.json is ON BY DEFAULT, and `board` in instance.config.json is the off switch.
#
# It used to be opt-in by presence, with FIRST_STAMP making `rm SNAPSHOT.json`
# permanent. That inverted the common case: every instance stamped before the board
# existed silently stayed off it, and putting one back on meant knowing to `touch` a file
# nothing mentioned. Three of three instances here were in that state.
#
# So the decision moved to config, where it is visible and survives a re-stamp:
#
#   · `board` absent or true  => create SNAPSHOT.json when missing, on ANY stamp.
#   · `board: false`          => never create it, and say so.
#
# `rm SNAPSHOT.json` still takes the instance off the board immediately — the writer
# never resurrects it (see write-snapshot.sh) — but it is no longer PERMANENT: the next
# stamp brings it back unless config says otherwise. That is the trade, and it is the
# right way round: a deletion is a moment's decision, a config key is a durable one.
#
# WHAT THIS DOES NOT CHANGE, and the distinction matters for a no-PII instance:
# SNAPSHOT.json is a LOCAL, gitignored file, and so is the page rendered from it. Having
# one puts an instance on the TERMINAL board and makes a page renderable — and since the
# account-scoped publish path was deleted, nothing this repo ships sends any of it
# anywhere. Question TEXT still needs SNAPSHOT_QUESTION_TEXT=1 on top of that.
# On-by-default is therefore safe even for an instance whose board must not leave the
# machine.
#
# THIS IS NO LONGER THE ONLY READER OF `board`, AND THAT IS THE POINT. The key is read
# here at STAMP time, deciding whether the file below is created at all; each /pm-loop
# tick and the SessionStart board hook read it again at TICK time, deciding whether the
# page is rendered and surfaced. Until 2026-08-29 nothing re-read it, so `board: false`
# stopped the seed and stopped nothing afterwards. Every reader takes it from THIS
# tracked config — never from a per-machine override — so one key cannot become two
# switches that disagree.
#
# NO SCRIPT IS NAMED HERE, ON PURPOSE. This comment used to name the renderer it meant,
# and when that renderer was folded into another the name went stale — install.sh never
# calls it, so nothing noticed until retire-machinery.test.sh (which asserts install.sh
# carries no machinery name at all) went red. Name the capability; leave the entry point
# to docs/operations.md, which is checked against the tree.
#
# It is deliberately generated ROOT content and not a file under symlink/: machinery is
# re-linked unconditionally on every run, so a deletable capability built out of a
# machinery file comes back by itself. A gitignored root file has no such hole.
#
# Seeded content is a VALID EMPTY snapshot rather than an empty file: build-board.sh
# parses this as JSON, and a zero-byte file would render an "unreadable snapshot" note
# on a brand-new instance that has done nothing wrong.
BOARD_OPT="$(cfg_bool board true "$TARGET/instance.config.json")"
if [ "$BOARD_OPT" = false ]; then
  echo "  skip  SNAPSHOT.json (board: false in instance.config.json)"
elif [ ! -e "$TARGET/SNAPSHOT.json" ]; then
  cat > "$TARGET/SNAPSHOT.json" <<'SNAPSHOT'
{
  "_schema": "ai-bridge board snapshot v1",
  "_sensitivity": "Derived and gitignored. Rewritten by scripts/write-snapshot.sh each /pm-loop tick. Delete this file to drop off the board until the next stamp; set \"board\": false in instance.config.json to stay off.",
  "group": "",
  "generated_at": "",
  "counts": {"projects": 0, "tasks": 0, "awaiting": 0},
  "projects": []
}
SNAPSHOT
  echo "  seed  SNAPSHOT.json (on the board; set \"board\": false to opt out)"
fi

# 2. Machinery — symlink each file (absolute target), backing up real conflicts.
chmod +x "$SYMLINK_SRC"/scripts/*.sh 2>/dev/null || true
while IFS= read -r rel; do
  [ -n "$rel" ] || continue
  src="$SYMLINK_SRC/$rel"; dst="$TARGET/$rel"
  if ours "$rel"; then echo "  ok    $rel (already linked)"; continue; fi
  mkdir -p "$(dirname "$dst")"
  if [ -e "$dst" ] || [ -L "$dst" ]; then
    bak="$dst.bak.$(date +%s)"; mv "$dst" "$bak"
    echo "  moved $rel -> $(basename "$bak")"
  fi
  ln -s "$src" "$dst"
  echo "  link  $rel"
done <<EOF
$(machinery_paths)
EOF

# 2b/2c. Retire machinery the template no longer ships, and sweep the dead backups
# step 2 above has just made.
#
# When a capability is removed from symlink/, an instance stamped earlier keeps a symlink
# pointing at a path that no longer exists. A dangling command or hook is worse than an
# absent one: Claude Code registers the file that isn't there, and a SessionStart hook
# whose script has vanished exits 127 on every launch.
#
# The test is deliberately narrow, and both halves are load-bearing: the link must point
# INTO this template's symlink/ (so it is unambiguously one we created — `ours` decides
# that, not a name match), AND its target must be gone.
#
# The SCAN is deliberately wide, though — the whole instance, not just .claude/ and
# scripts/. `machinery_paths()` also places files at the instance ROOT (SCHEMA.md,
# AUTONOMY.md, CONVENTIONS.md) and under agents/, so a narrower scan would miss exactly
# the most load-bearing files. `ours` is what makes a wide scan safe: `repos/<name>`
# links point at reposRoot, not into symlink/, so they are never candidates. `find` does
# not follow symlinks, so it cannot descend into a linked repo; .git is pruned for speed. A link we made whose target we
# deleted has exactly one possible meaning. Anything else — a real file, a link to
# somewhere else, a link that still resolves — is left alone.
#
# Only removes the link. Never touches seed content or instance data: a `todos.md` left
# behind by a retired feature is the human's own writing, so it is reported, not deleted.
while IFS= read -r dst; do
  [ -n "$dst" ] || continue
  # "$TARGET" must be QUOTED inside the prefix operator: unquoted it is matched as a
  # GLOB, so an instance path containing [ ] * or ? strips nothing, `rel` stays absolute,
  # `ours` then tests "$TARGET/$TARGET/..." and returns false — silently skipping a
  # genuinely dead link instead of retiring it. (SC2295.)
  rel="${dst#"$TARGET"/}"
  if ours "$rel" && [ ! -e "$dst" ]; then
    rm -f "$dst"
    echo "  retire $rel (no longer shipped by the template)"
  elif dead_backup ours "$rel" "$dst"; then
    # 2c. The backups step 2 itself just made. A moved template dangles every link, so
    # step 2 moves each one aside and relinks — leaving one dead `.bak.*` symlink per
    # machinery file, invisible to the retire test above because it points at the OLD
    # template. dead_backup() carries the reasoning and the three conditions.
    was="$(readlink "$dst")"; rm -f "$dst"
    echo "  sweep  $rel (dead backup of a relinked file, was -> $was)"
  fi
done <<EOF
$(find "$TARGET" -name .git -prune -o -type l -print 2>/dev/null | sort)
EOF

# 3. Rewrite the managed machinery block in the instance .gitignore.
gi="$TARGET/.gitignore"
[ -f "$gi" ] || printf '%s\n%s\n' "$BEGIN_MARK" "$END_MARK" > "$gi"
grep -qF "$BEGIN_MARK" "$gi" || printf '\n%s\n%s\n' "$BEGIN_MARK" "$END_MARK" >> "$gi"
mlist="$(mktemp)"; machinery_paths > "$mlist"
tmp="$gi.tmp.$$"
awk -v b="$BEGIN_MARK" -v e="$END_MARK" -v mlist="$mlist" '
  $0==b { print; while ((getline line < mlist) > 0) print "/" line; close(mlist); inblock=1; next }
  $0==e { print; inblock=0; next }
  !inblock { print }
' "$gi" > "$tmp" && mv "$tmp" "$gi"
rm -f "$mlist"

# The repos/ view is derived, so it must be ignored too — but OUTSIDE the managed
# block, which is regenerated from the machinery file list and would drop any line
# that isn't a machinery path. Appended once; a hand-written `repos/` also counts.
if ! grep -qE '^/?repos/?$' "$gi"; then
  cat >> "$gi" <<'GI'

# Derived view of the group's product repos (scripts/link-repos.sh) — symlinks
# into reposRoot, never content, and machine-local like the rest. Delete it
# freely; the next install or `scripts/link-repos.sh` run recreates it.
/repos/
GI
fi

# The local live board (scripts/watch-board.sh) writes its page here. Appended for the
# same reason as /repos/ and instance.config.local.json below: seed content is copied
# only when ABSENT, so an instance stamped before this directory existed — which is
# every instance in existence — would otherwise commit a generated HTML page.
if ! grep -qE '^/?\.board-live/?$' "$gi"; then
  cat >> "$gi" <<'GI'

# The local live board page (scripts/watch-board.sh). Derived output, regenerated on
# every task-document change, and per-machine. Delete it freely.
/.board-live/
GI
fi

# The board's other-owners cache (scripts/build-board.sh), appended for exactly the same
# reason: every instance in existence was stamped before this file existed, and a derived
# cache of committed state has no business being committed back.
if ! grep -qE '^/?\.board-others\.json$' "$gi"; then
  cat >> "$gi" <<'GI'

# The board's other-owners cache (scripts/build-board.sh) — the second half of the page,
# read from the tracked documents at HEAD and stored against the SHA it was computed for.
# Derived and per-machine. Delete it freely; the next render rebuilds it.
/.board-others.json
GI
fi

# The PM dispatch lock (scripts/tick-lock.sh), appended for the third time for exactly the
# same reason: every instance in existence was stamped before this file existed, and a lock
# that got committed would stop being per-clone — which is the one property it has.
if ! grep -qE '^/?\.tick-lock$' "$gi"; then
  cat >> "$gi" <<'GI'

# The PM dispatch lock (scripts/tick-lock.sh) — written by /pm-loop immediately before it
# dispatches a tick and released when that tick reports, so the one-tick-at-a-time
# guarantee survives a compaction instead of resting on a session's memory. PER CLONE and
# never committed: two humans sharing one bundle work from two clones and each dispatches
# independently, which a shared lock would break. Derived and safe to delete when no tick
# is running.
/.tick-lock
GI
fi

# The tick's claim on that lock — the second half of the same mechanism, appended under its
# OWN guard rather than inside the block above. That is the whole point: every instance
# stamped since the lock shipped already carries `/.tick-lock`, so the guard above is
# satisfied and would never append a line added to its heredoc. A second file needs a second
# guard, or the ignore silently reaches nobody who has the first one.
if ! grep -qE '^/?\.tick-lock\.claim$' "$gi"; then
  cat >> "$gi" <<'GI'

# The tick's claim on the dispatch lock (scripts/tick-lock.sh) — the tick takes the lock
# too, because a resumed tick never passes through the launcher, and this file is what tells
# "held by the launcher that dispatched me" from "held by another tick". Per clone and
# derived exactly like the lock beside it, and removed with it by
# `scripts/tick-lock.sh release`.
/.tick-lock.claim
GI
fi

# 3b. Two more ignores, appended once each if missing — OUTSIDE the managed block,
# for the same reason as /repos/ above.
#
# Why appended here at all: the seed is copied only if ABSENT, so an instance stamped
# before these lines existed would never receive them, and both are load-bearing.
# `instance.config.local.json` holds per-machine IDENTITY (authorEmail,
# ownerGithubUser) — committing it would push one human's identity into a bundle the
# other reads, which is the exact failure the file exists to prevent. The derived
# indexes are rewritten every tick, so on a shared bundle they conflict on every push.
#
# And why the INDEX lines live ONLY here, never in seed/.gitignore: that file is an
# active .gitignore inside the template's own `seed/` directory, so a `/index.md`
# line in it matches `seed/index.md` and silently stops the template from
# tracking its own seed file. Measured — it broke the upgrade.sh fixture, which
# re-inits a repo over a copy of seed/. `instance.config.local.json` has no such
# collision (no seed file is named that), so it is in both places, harmlessly.
if ! grep -qxF 'instance.config.local.json' "$gi"; then
  cat >> "$gi" <<'GI'

# Per-machine identity overrides (authorEmail, ownerGithubUser), winning over the
# TRACKED instance.config.json for those keys only. Never commit it: a shared bundle
# would otherwise author both humans' commits as one person.
instance.config.local.json
GI
fi
# The derived-index ignore block, behind its own marker pair — the same mechanism the
# machinery block above uses (BEGIN_MARK/END_MARK), and for the same reason. This used
# to be guarded by "append only if the two literal rule lines are missing"
# (`grep -qxF '/index.md' ... || ! grep -qxF '/projects/*/index.md' ...`), which is a
# short-circuit, not a safeguard: once an instance is stamped once, both rule lines exist
# forever, so the whole block is skipped on every later run — a corrected comment, or a
# new rule line added here in the future, would reach only fresh installs. Measured
# twice in one hour against real instances: ai-bridge-v4/task-009.
#
# The fix mirrors the machinery block: fully rewrite the region between two markers on
# every run, and touch nothing outside them. That is also what keeps a RETAINED
# project's escape hatch safe. A negation line (`!projects/<slug>/index.md`, task-008 /
# #29) must be added by hand AFTER the two blanket lines this block emits — i.e. after
# its END marker, never inside the block, since everything between the markers is
# unconditionally replaced on every stamp. Git applies .gitignore patterns in file
# order, so a line after the END marker is a line after the two blanket rules, which is
# the only thing that makes the negation win.
IDX_BEGIN_MARK="# >>> ai-bridge index ignore >>>"
IDX_END_MARK="# <<< ai-bridge index ignore <<<"
idxbody="$(mktemp)"
cat > "$idxbody" <<'GI'
# Derived navigation indexes — the root one and each project's, rewritten by every
# /pm-loop tick from the documents they summarise. A view, not source: on a bundle
# shared by more than one human it would otherwise conflict on every push.
# `knowledge/index.md` is deliberately NOT ignored: it is the KB's curated lookup
# surface, changes only when the KB changes, and a fresh clone needs it present.
#
# The one exception is a RETAINED project (`status: done`, kept instead of closed):
# the tick stops touching a retained project at all, so its index.md becomes a
# permanent, hand-committed front door instead of a rewritten view. To retain one,
# add a negation line AFTER the two blanket lines below (i.e. after this block's END
# marker, never inside it — install.sh rewrites everything between the markers on
# every run), then `git add -f` the file once — e.g. `!projects/<slug>/index.md`.
# Git applies .gitignore patterns in file order, so a LATER negation overrides an
# earlier blanket pattern; putting the override before the two blanket lines below,
# or inside this block, does not survive the next `install.sh` run.
/index.md
/projects/*/index.md
GI

# `|| true` throughout this section: under `set -o pipefail`, a `grep` that matches
# nothing makes the whole pipeline (and a bare assignment built from it) exit non-zero
# even though `head`/`cut` succeed, and a bare non-zero assignment — unlike one used
# directly as an `if`/`elif` condition — is NOT exempt from `set -e`. Without it, the
# ordinary "no such line" case aborts the whole install.sh run right here instead of
# falling through to the next branch. See knowledge/findings/a-bare-pipeline-assignment-
# aborts-under-set-e-even-when-a-sibling-guard-is-fine.md in the control-panel bundle.
idx_begin_line="$(grep -nxF "$IDX_BEGIN_MARK" "$gi" | head -1 | cut -d: -f1)" || true
if [ -n "$idx_begin_line" ]; then
  # Already migrated to the marker pair by an earlier run of this (fixed) install.sh —
  # rewrite in place, exactly like the machinery block above. EXACT line match
  # (`-qxF`), not a substring one: a comment that merely mentions or resembles this
  # marker text (e.g. quoting it while explaining the mechanism) must not be mistaken
  # for the real marker line, matching the exact-match awk below.
  #
  # BEGIN alone is not enough to rewrite: this awk's `!inblock { print }` only resumes
  # printing once it sees an EXACT END line, so a file with BEGIN and no (or a
  # preceding) END would have every line from BEGIN to EOF silently dropped by the
  # rewrite below — an interrupted stamp or a hand-edit that removed the END line reaches
  # exactly this state. Verify END exists AFTER BEGIN before touching the file at all;
  # if it does not, leave the file untouched and report the problem instead of writing.
  idx_end_line="$(grep -nxF "$IDX_END_MARK" "$gi" | head -1 | cut -d: -f1)" || true
  if [ -z "$idx_end_line" ] || [ "$idx_end_line" -lt "$idx_begin_line" ]; then
    echo "warn  $gi carries an index-ignore BEGIN marker ('$IDX_BEGIN_MARK') with no" >&2
    echo "      matching END marker after it. Left UNCHANGED rather than risk dropping" >&2
    echo "      everything after the BEGIN line. Fix by hand: add '$IDX_END_MARK' right" >&2
    echo "      after the two blanket rule lines (/index.md, /projects/*/index.md), or" >&2
    echo "      remove the stray BEGIN line — then re-run." >&2
  else
    tmp="$gi.tmp.$$"
    awk -v b="$IDX_BEGIN_MARK" -v e="$IDX_END_MARK" -v body="$idxbody" '
      $0==b { print; while ((getline line < body) > 0) print line; close(body); inblock=1; next }
      $0==e { print; inblock=0; next }
      !inblock { print }
    ' "$gi" > "$tmp" && mv "$tmp" "$gi"
  fi
else
  # No marker pair yet. An instance stamped by the OLD guard-based install.sh carries
  # the two literal rule lines, adjacent, with no markers — every version of that guard
  # ever emitted them in exactly that shape. Find them and splice the marker pair in
  # where the old comment + two rule lines were, so a negation a human already added
  # right after the old two rule lines ends up right after the new END marker — still
  # after the two blanket rules, which is the only ordering that matters.
  #
  # The old comment is walked off by scanning upward from `/index.md` while lines are
  # comments (`^#`), never by matching its exact text — the whole point of this fix is
  # that the comment has drifted across template versions and instances, so there is no
  # one string to match.
  #
  # Scan EVERY standalone `/index.md` line, not just the first: an earlier, unrelated
  # `/index.md` line (rare, but not impossible — nothing stops a human from ignoring
  # some other file with that exact name) must not steal the adjacency match away from
  # the real index-ignore pair sitting later in the file. Stopping at the first
  # candidate that ISN'T followed by `/projects/*/index.md` would fall through to the
  # fresh-instance append path below and append the blanket block at EOF — after an
  # existing retained-project negation, silently reversing it (criterion 4).
  idxline=""
  while IFS= read -r candidate; do
    [ -n "$candidate" ] || continue
    if [ "$(sed -n "$((candidate+1))p" "$gi")" = "/projects/*/index.md" ]; then
      idxline="$candidate"
      break
    fi
  done <<EOF
$(grep -nxF '/index.md' "$gi" | cut -d: -f1)
EOF
  if [ -n "$idxline" ]; then
    start="$idxline"
    while [ "$start" -gt 1 ] && sed -n "$((start-1))p" "$gi" | grep -q '^#'; do
      start=$((start-1))
    done
    tmp="$gi.tmp.$$"
    {
      if [ "$start" -gt 1 ]; then
        sed -n "1,$((start-1))p" "$gi"
      fi
      printf '%s\n' "$IDX_BEGIN_MARK"
      cat "$idxbody"
      printf '%s\n' "$IDX_END_MARK"
      sed -n "$((idxline+2)),\$p" "$gi"
    } > "$tmp"
    mv "$tmp" "$gi"
  else
    # Genuinely fresh: no marker pair, and no legacy two-line block in the expected,
    # adjacent shape (or one reordered enough that guessing at it risks a bad splice —
    # left alone rather than guessed at). Append a new marker-wrapped block.
    {
      printf '\n%s\n' "$IDX_BEGIN_MARK"
      cat "$idxbody"
      printf '%s\n' "$IDX_END_MARK"
    } >> "$gi"
  fi
fi
rm -f "$idxbody"

# A .gitignore line is INERT for a file git already tracks, so on an instance whose
# index.md files are committed this change would silently do nothing. Report the exact
# command instead of running it: untracking a file is a commit the human makes and the
# other clone then pulls (which deletes their copy until the next tick or install
# re-creates it). Report-only, like RETIRED and prune-worktrees.sh.
if [ -d "$TARGET/.git" ] || [ -f "$TARGET/.git" ]; then
  tracked_idx="$( ( cd "$TARGET" && git ls-files -- index.md 'projects/*/index.md' 2>/dev/null ) || true )"
  if [ -n "$tracked_idx" ]; then
    echo "Derived indexes are still tracked here (now gitignored, so the ignore is inert):"
    while IFS= read -r ti; do
      [ -n "$ti" ] || continue
      echo "  tracked $ti"
    done <<EOF
$tracked_idx
EOF
    echo "        To untrack them (keeps the files on disk), from $TARGET:"
    echo "          git rm --cached -- index.md 'projects/*/index.md'"
    echo "        …then commit. Needed only if this bundle is shared by more than one human."
  fi
fi

# 4. Product-repo view — one symlink per repo under TARGET/repos/, so the peer
# repos are reachable from inside the instance without being nested in it.
# Best-effort by design: a fresh instance still has the placeholder reposRoot, and
# the script exits 0 with an explanation in that case rather than failing the
# install. Template copy, for the same reason as in --uninstall.
( cd "$TARGET" && bash "$SYMLINK_SRC/scripts/link-repos.sh" ) \
  || echo "  warn  repos/ view not refreshed; run scripts/link-repos.sh by hand" >&2

# ===========================================================================
# 4b. THE TEAM ROSTER — offered once, on a first stamp, only at a terminal.
# ===========================================================================
#
# WHAT IT WRITES, AND WHY IT IS WORTH ASKING. Three values, all of them already
# specified in docs/sharing.md and SCHEMA.md → "Per-machine config overrides": the
# TRACKED `people` map (GitHub login → commit email, so scripts/commit-as.sh can author
# each clone's commits as the human running it), the TRACKED `defaultOwner` (so two
# clones of one bundle agree who *unowned* work belongs to instead of both dispatching
# it), and this clone's own gitignored `instance.config.local.json`, naming which login
# this clone IS. Hand-editing all three after the stamp was exactly the "several manual
# steps" shape that produced upgrade.sh: fine for whoever wrote it, an eight-step
# checklist for the next person. Nothing here redesigns that model — this is only the
# collection step it was missing.
#
# THREE GUARDS, each protecting a flow that already works:
#
#   1. FIRST_STAMP ONLY. upgrade.sh calls this installer on EVERY run, including its
#      non-interactive report-only mode, so an unguarded prompt would block every
#      upgrade. It reuses the FIRST_STAMP computed before seeding for AWAITING.md rather
#      than inventing a second notion of "new" — two notions are two things to get out
#      of step.
#   2. A TTY ONLY. Otherwise skip, leave the placeholder, and print the instruction.
#      This script has to stay safe to run from a script, from upgrade.sh, and from a
#      background agent with no terminal: a prompt nobody can see is a hang, and a hang
#      in a background agent is invisible.
#   3. NEVER OVERWRITE. Only the SEEDED placeholder is ever rewritten — the awk pass
#      below recognises the exact placeholder lines and refuses when it does not find
#      them — and the local file is written only when absent. That seeds-if-absent
#      contract is what makes this installer safe to re-run on a repo full of somebody's
#      work, so it is checked against the FILE rather than merely inferred from
#      FIRST_STAMP.
#
# And a fourth, which is really the verification rule: NO VERIFIER, NO WRITE. A broken
# instance.config.json breaks every later script in the instance, so the result is parsed
# back — before the temp file lands and again after it lands — and if neither jq nor
# python3 is on this machine the prompt is not offered at all. This codebase has a
# recorded incident of a script printing FIXED for a write that never landed
# (migrate-bundle.sh); verify-after-write is the standing answer, and a write we cannot
# verify is one we do not make.
#
# ONE BATCHED PROMPT, NOT N SERIAL ONES, and the reason is the failure mode rather than
# the keystrokes. Asked person-by-person, a roster accumulates state across reads: enter
# one pair, hit ctrl-C, and the instance is left with a map that resolves for one human
# and silently falls through for the other. Here the whole roster arrives as ONE block
# and nothing is written until a separate confirmation, so a partial answer cannot become
# a partial file — EOF, an interrupt, an unreadable line and a declined confirmation all
# take the same exit: write nothing, and say which happened. It is also two reads
# regardless of team size, which is the reasoning /new-project already uses to batch its
# capability questions.
#
# VALIDATION IS ALSO THE ESCAPING. Every login must match the GitHub-username rule
# task-owner.sh and commit-as.sh already apply (1-39 alphanumerics, single hyphens
# between them), and every address a deliberately conservative mail shape. Both reject
# quotes, backslashes, whitespace and control characters, so no ACCEPTED value can carry
# a character that would need JSON escaping: the file cannot be broken by its content,
# only by a bug in this block — which is what the parse-back catches.
TEAM_CFG="$TARGET/instance.config.json"
TEAM_LCFG="$TARGET/instance.config.local.json"

# How to do it by hand. Printed on every path that decides not to write, so a skip is
# never a dead end — the same "say the exact thing to do" contract as RETIRED.
team_manual_note() {
  echo "        Set it by hand instead (the full order is in $TEMPLATE_DIR/docs/sharing.md):"
  echo "          instance.config.json        \"people\": { \"<login>\": \"<commit-email>\" }"
  echo "          instance.config.json        \"defaultOwner\": \"<login>\""
  echo "          instance.config.local.json  { \"ownerGithubUser\": \"<your-login>\" }"
}

# A GitHub username, by the same rule task-owner.sh's valid_user uses. Deliberately not a
# looser one: the value is compared against `owner:` in task documents and interpolated
# into a grep there, so a shape those readers refuse must be refused here too.
team_valid_login() { # <value>
  [ ${#1} -ge 1 ] && [ ${#1} -le 39 ] || return 1
  printf '%s' "$1" | grep -qE '^[A-Za-z0-9]+(-[A-Za-z0-9]+)*$'
}
# A conservative address shape. It rejects plenty of technically-legal addresses, and
# that is the trade: an address nobody can type here can still be written by hand,
# whereas a quote or a backslash accepted here would land inside a JSON string.
team_valid_email() { # <value>
  [ ${#1} -ge 3 ] && [ ${#1} -le 254 ] || return 1
  printf '%s' "$1" | grep -qE '^[A-Za-z0-9._%+-]+@[A-Za-z0-9][A-Za-z0-9.-]*\.[A-Za-z]{2,}$'
}

# Does this file parse as JSON?  0 = yes, 1 = NO, 2 = no parser on this machine.
# The three answers are distinguished on purpose: "we could not check" must never be
# reported as "it is fine" — the required-checks.sh discipline, applied to a write.
team_json_ok() { # <file>
  if command -v jq >/dev/null 2>&1; then
    jq -e . "$1" >/dev/null 2>&1 && return 0
    return 1
  fi
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import json,sys; json.load(sys.stdin)' >/dev/null 2>&1 <"$1" && return 0
    return 1
  fi
  return 2
}

# The inner text of the `people` object, flattened onto one line. Same problem
# commit-as.sh's people_email() solves, and awk for the same reason it uses awk: this is
# a nested object, so a same-named key elsewhere in the file must not answer.
team_people_segment() { # <file>
  [ -f "$1" ] || return 0
  awk '
    !inb {
      i = index($0, "\"people\""); if (i == 0) next
      $0 = substr($0, i + 8)
      i = index($0, "{"); if (i == 0) next
      $0 = substr($0, i + 1); inb = 1
    }
    {
      e = index($0, "}")
      if (e) { printf "%s ", substr($0, 1, e - 1); exit }
      printf "%s ", $0
    }
  ' "$1"
}

# Read `defaultOwner` back out, with the same portable extractor the machinery uses.
team_read_owner() { # <file>
  [ -f "$1" ] || return 0
  sed -n 's/.*"defaultOwner"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$1" | head -n1
}

# Everything this claims to have written, checked by reading the file back. Structural
# validity is not enough: a JSON file can parse perfectly and still be missing the pair
# we said we added, which is the false-success shape this repo has already been bitten by.
team_verify() { # <file> <owner> <roster-file>
  local f="$1" who="$2" rf="$3" seg pair l e
  team_json_ok "$f" || return 1
  [ "$(team_read_owner "$f")" = "$who" ] || return 1
  seg="$(team_people_segment "$f")"
  # Exactly as many pairs as the roster has, so a placeholder that SURVIVED the rewrite
  # fails here: the object must have been replaced, not added to, and a stranger's login
  # left in a real roster is worse than a missing one. Counting colons is enough because
  # a validated login and address contain none.
  [ "$(printf '%s' "$seg" | tr -cd ':' | wc -c | tr -d ' ')" = "$(grep -c . "$rf")" ] || return 1
  while read -r l e; do
    [ -n "$l" ] || continue
    pair="\"$l\": \"$e\""
    printf '%s' "$seg" | grep -qF -- "$pair" || return 1
  done < "$rf"
  return 0
}

# ---------------------------------------------------------------- the three guards
team_ask=yes
[ "$FIRST_STAMP" = yes ] || team_ask=no
[ -f "$TEAM_CFG" ] || team_ask=no
# Guard 2. TEAM_SETUP_STDIN=1 is the ONE way past the TTY test, and it exists so the
# refusals here can be tested at all — the role SNAPSHOT_NOW plays for write-snapshot.sh.
# It must be set deliberately (nothing in upgrade.sh, in a role agent, or in a background
# agent's environment sets it), and even then it cannot hang: every read in forced mode
# carries a timeout.
TEAM_FORCED="${TEAM_SETUP_STDIN:-}"
if [ "$team_ask" = yes ] && [ ! -t 0 ] && [ "$TEAM_FORCED" != 1 ]; then
  team_ask=no
  echo "  skip  team roster (stdin is not a terminal, so nothing was asked)."
  team_manual_note
fi
# Guard 3, asked of the FILE. On a first stamp this is the seed verbatim, but
# seeds-if-absent is a property of the file rather than of FIRST_STAMP, and a value
# somebody already put there is never ours to replace — so this is checked, not inferred.
#
# What counts as "still the placeholder" is deliberately name-INDEPENDENT: an entry whose
# login equals the local part of its address at example.com (`"x": "x@example.com"`),
# which is the shape seed/instance.config.json ships and a shape no real roster has. A
# hard-coded `example-user-007` would stop recognising the placeholder the day somebody
# renames it — silently, since the failure is "the prompt is never offered again". The
# back-reference is why this is sed rather than awk (awk regexes have none).
if [ "$team_ask" = yes ]; then
  team_seg="$(team_people_segment "$TEAM_CFG")"
  team_rest="$(printf '%s' "$team_seg" | sed 's/"\([A-Za-z0-9-]\{1,\}\)"[[:space:]]*:[[:space:]]*"\1@example\.com"//g')"
  if [ -n "$(team_read_owner "$TEAM_CFG")" ] || printf '%s' "$team_rest" | grep -q '"'; then
    team_ask=no
    echo "  keep  team roster in instance.config.json (already set — left alone)"
  fi
fi
# Guard 4: no verifier, no write.
if [ "$team_ask" = yes ]; then
  team_vrc=0
  team_json_ok "$TEAM_CFG" || team_vrc=$?
  if [ "$team_vrc" = 2 ]; then
    team_ask=no
    echo "  skip  team roster (neither jq nor python3 here, so a write could not be verified)."
    team_manual_note
  elif [ "$team_vrc" != 0 ]; then
    team_ask=no
    echo "  skip  team roster (instance.config.json does not parse as JSON — fix that first)."
    team_manual_note
  fi
fi

# ---------------------------------------------------------------- the prompt
if [ "$team_ask" = yes ]; then
  # The prompt goes to STDERR and the result lines to stdout with the rest of the install
  # report. Two reasons: upgrade.sh filters this script's stdout line by line, and stderr
  # is unbuffered, so an interrupted prompt is still on screen where it happened.
  TEAM_ABORT=0
  team_on_int() { TEAM_ABORT=1; printf '\n' >&2; }
  trap team_on_int INT
  # One line into REPLY_LINE; non-zero on EOF, timeout or interrupt. The TRAP FLAG is
  # what distinguishes an interrupt from EOF, and it has to be: bash 3.2 (what macOS
  # ships) returns plain 1 from an interrupted `read`, exactly as it does at EOF —
  # measured — so an exit-status test would report ctrl-C as "input ended" and take the
  # wrong branch. Same status, different meaning: read the flag, not the code.
  team_read() {
    REPLY_LINE=""
    local rc=0
    if [ "$TEAM_FORCED" = 1 ]; then
      IFS= read -r -t 10 REPLY_LINE || rc=$?
    else
      IFS= read -r REPLY_LINE || rc=$?
    fi
    [ "$rc" = 0 ] || return 1
    [ "$TEAM_ABORT" = 0 ] || return 1
    return 0
  }

  TEAM_ROSTER="$(mktemp "${TMPDIR:-/tmp}/ai-bridge-roster.XXXXXX")"
  team_state=ask   # ask → write, or one of: eof, interrupt, declined, unreadable
  team_tries=0
  while [ "$team_state" = ask ]; do
    team_tries=$((team_tries+1))
    : > "$TEAM_ROSTER"
    team_n=0
    {
      echo ""
      echo "Team roster for this instance — asked once, on a first stamp."
      echo "  One person per line:  <github-login> <commit-email>"
      echo "  YOURSELF FIRST: your login becomes this instance's defaultOwner and this"
      echo "  clone's identity in instance.config.local.json."
      echo "  An empty line ends the list. Nothing is written until you confirm it, and"
      echo "  ctrl-C, ctrl-D or an empty first line all write nothing at all."
    } >&2
    while :; do
      printf '  %d> ' "$((team_n+1))" >&2
      if ! team_read; then
        if [ "$TEAM_ABORT" = 0 ]; then team_state=eof; else team_state=interrupt; fi
        break
      fi
      # Surrounding whitespace is a typo, not an answer — stripped before deciding whether
      # the line is empty, or a stray space would end the list without meaning to.
      team_line="$(printf '%s' "$REPLY_LINE" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
      [ -n "$team_line" ] || break
      team_login="$(printf '%s' "$team_line" | awk '{print $1}')"
      team_email="$(printf '%s' "$team_line" | awk '{print $2}')"
      team_extra="$(printf '%s' "$team_line" | awk '{print $3}')"
      if [ -n "$team_extra" ] || [ -z "$team_email" ]; then
        echo "        ✗ expected exactly two fields: <github-login> <commit-email>" >&2
        team_state=unreadable; break
      fi
      if ! team_valid_login "$team_login"; then
        echo "        ✗ '$team_login' is not a GitHub username (1-39 alphanumerics, single hyphens between them)" >&2
        team_state=unreadable; break
      fi
      if ! team_valid_email "$team_email"; then
        echo "        ✗ '$team_email' is not an address this can write safely" >&2
        team_state=unreadable; break
      fi
      if grep -q "^$team_login " "$TEAM_ROSTER"; then
        echo "        ✗ '$team_login' is already in this roster" >&2
        team_state=unreadable; break
      fi
      printf '%s %s\n' "$team_login" "$team_email" >> "$TEAM_ROSTER"
      team_n=$((team_n+1))
    done
    if [ "$team_state" = unreadable ]; then
      # Re-ask the whole block rather than patching the one line: the block is the unit
      # that gets confirmed, so a half-corrected block is the state this design avoids.
      if [ "$team_tries" -lt 3 ]; then
        echo "        Let's take the list again from the top." >&2
        team_state=ask
        continue
      fi
      break
    fi
    [ "$team_state" = ask ] || break
    if [ "$team_n" -eq 0 ]; then team_state=declined; break; fi

    TEAM_OWNER="$(head -n1 "$TEAM_ROSTER" | awk '{print $1}')"
    {
      echo ""
      echo "  About to write:"
      echo "    instance.config.json        defaultOwner = $TEAM_OWNER"
      while read -r team_l team_e; do
        [ -n "$team_l" ] && echo "                                people[$team_l] = $team_e"
      done < "$TEAM_ROSTER"
      echo "    instance.config.local.json  ownerGithubUser = $TEAM_OWNER  (gitignored)"
      printf '  Write it? [y/N] '
    } >&2
    if ! team_read; then
      if [ "$TEAM_ABORT" = 0 ]; then team_state=eof; else team_state=interrupt; fi
      break
    fi
    case "$(printf '%s' "$REPLY_LINE" | tr '[:upper:]' '[:lower:]')" in
      y|yes) team_state=write ;;
      *)     team_state=declined ;;
    esac
  done
  trap - INT

  case "$team_state" in
    write) ;;
    interrupt)
      rm -f "$TEAM_ROSTER"
      echo "  roster: nothing written (interrupted). No partial map was left behind."
      team_manual_note
      # The install itself is complete — only the roster was skipped — but ctrl-C should
      # still feel like it stopped something, so this exits with the conventional SIGINT
      # code rather than pretending nothing happened. Everything below on a FIRST stamp is
      # a no-op anyway: nothing is retired, and a fresh seed validates clean.
      exit 130 ;;
    *)
      rm -f "$TEAM_ROSTER"
      case "$team_state" in
        eof)        echo "  roster: nothing written (input ended)." ;;
        unreadable) echo "  roster: nothing written (could not read the list)." ;;
        *)          echo "  roster: nothing written (declined)." ;;
      esac
      team_manual_note ;;
  esac
fi

# ---------------------------------------------------------------- the write
if [ "${team_state:-}" = write ]; then
  # The tracked half, as ONE awk pass that only ever replaces lines it RECOGNISES:
  # `"defaultOwner": null,`, the `$people` note, and a `people` object holding nothing but
  # placeholder entries. Anything else — a drifted seed, a roster somebody already wrote —
  # makes it exit 3, and then nothing is written at all. That is guard 3 and a seed-drift
  # guard in one mechanism, and it degrades to "print the instruction", never to a
  # half-rewritten file.
  team_lines="$(mktemp "${TMPDIR:-/tmp}/ai-bridge-people.XXXXXX")"
  team_total="$(grep -c . "$TEAM_ROSTER" || true)"
  team_i=0
  while read -r team_l team_e; do
    [ -n "$team_l" ] || continue
    team_i=$((team_i+1))
    if [ "$team_i" -lt "$team_total" ]; then
      printf '    "%s": "%s",\n' "$team_l" "$team_e" >> "$team_lines"
    else
      printf '    "%s": "%s"\n' "$team_l" "$team_e" >> "$team_lines"
    fi
  done < "$TEAM_ROSTER"

  team_note="Collected by install.sh when this instance was stamped: GitHub login -> commit email, for THIS instance. The address is PER-INSTANCE, not per-person -- it says which entity the work belongs to -- so never derive it from the login, and never move it into instance.config.local.json (that file says which login this clone IS). Read by scripts/commit-as.sh via ownerGithubUser; see SCHEMA.md 'Per-machine config overrides' and docs/sharing.md. Edit by hand to add or remove someone."

  # Temp file BESIDE the target, carrying the target's mode: mktemp creates 0600, so a
  # rename from $TMPDIR would silently make this config 0600, and a cross-filesystem mv
  # degrades to copy-and-remove, where an interruption leaves a half-written file. Same
  # rule as migrate-bundle.sh.
  team_tmp="$TEAM_CFG.tmp.$$"
  team_orig="$TEAM_CFG.orig.$$"
  cp -p "$TEAM_CFG" "$team_tmp" 2>/dev/null || cp "$TEAM_CFG" "$team_tmp"
  cp -p "$TEAM_CFG" "$team_orig" 2>/dev/null || cp "$TEAM_CFG" "$team_orig"
  team_rc=0
  awk -v owner="$TEAM_OWNER" -v note="$team_note" -v rf="$team_lines" '
    /^[[:space:]]*"defaultOwner"[[:space:]]*:[[:space:]]*null[[:space:]]*,[[:space:]]*$/ {
      printf "  \"defaultOwner\": \"%s\",\n", owner; dow++; next
    }
    /^[[:space:]]*"\$people"[[:space:]]*:/ { printf "  \"$people\": \"%s\",\n", note; next }
    /^[[:space:]]*"people"[[:space:]]*:[[:space:]]*\{[[:space:]]*$/ {
      print "  \"people\": {"
      while ((getline line < rf) > 0) print line
      close(rf)
      print "  },"
      ppl++; inppl = 1; next
    }
    inppl {
      # Guard 3 above has already established that this object is the untouched
      # placeholder, so these lines are being DISCARDED, not judged: all this has to do
      # is refuse a shape it cannot safely replace. A flat "key": "value" pair is
      # discarded; anything else — a nested object, an array, a comment — sets bad, and
      # then nothing is written at all.
      if ($0 ~ /^[[:space:]]*"[^"]*"[[:space:]]*:[[:space:]]*"[^"]*"[[:space:]]*,?[[:space:]]*$/) next
      if ($0 ~ /^[[:space:]]*\}[[:space:]]*,?[[:space:]]*$/) { inppl = 0; next }
      bad = 1; next
    }
    { print }
    END { if (bad || dow != 1 || ppl != 1) exit 3 }
  ' "$TEAM_CFG" > "$team_tmp" || team_rc=$?

  if [ "$team_rc" != 0 ]; then
    rm -f "$team_tmp" "$team_orig" "$team_lines" "$TEAM_ROSTER"
    echo "  roster: nothing written — instance.config.json does not carry the placeholder" >&2
    echo "          roster this expected to replace, so it was left exactly as it is." >&2
    team_manual_note >&2
  elif ! team_verify "$team_tmp" "$TEAM_OWNER" "$TEAM_ROSTER"; then
    # Verified BEFORE the rename, so an unparseable file never lands at all.
    rm -f "$team_tmp" "$team_orig" "$team_lines" "$TEAM_ROSTER"
    echo "error: the roster this would have written does not verify, so instance.config.json" >&2
    echo "       was left exactly as it is. That is a bug in install.sh, not something you did." >&2
    team_manual_note >&2
    exit 1
  else
    mv "$team_tmp" "$TEAM_CFG"
    # And verified AGAIN once it lands. A write this script only *believes* it made is the
    # failure migrate-bundle.sh recorded: FIXED printed for an insert that silently
    # no-opped. A false success is worse than the error it claims to fix.
    if ! team_verify "$TEAM_CFG" "$TEAM_OWNER" "$TEAM_ROSTER"; then
      mv "$team_orig" "$TEAM_CFG"
      rm -f "$team_lines" "$TEAM_ROSTER"
      echo "error: instance.config.json did not verify after the write, and has been" >&2
      echo "       restored to the file that was there before. Nothing was kept." >&2
      team_manual_note >&2
      exit 1
    fi
    rm -f "$team_orig"
    echo "  wrote instance.config.json (people: $team_total, defaultOwner: $TEAM_OWNER)"
  fi
  rm -f "$team_lines"

  # The local half — this clone's identity. Written only when absent, like every other
  # seeded file, and gitignored (step 3b above appends the line), so it never becomes one
  # human's identity inside the other's clone.
  if [ -e "$TEAM_LCFG" ]; then
    echo "  keep  instance.config.local.json (exists — this clone's identity left alone)"
  else
    team_ltmp="$TEAM_LCFG.tmp.$$"
    {
      echo "{"
      echo "  \"\$schema\": \"Per-machine overrides for THIS clone -- gitignored, never committed. Which GitHub login this clone is, plus any absolute path or address that cannot be right on both machines. See SCHEMA.md, 'Per-machine config overrides'.\","
      printf '  "ownerGithubUser": "%s"\n' "$TEAM_OWNER"
      echo "}"
    } > "$team_ltmp"
    if team_json_ok "$team_ltmp" \
       && [ "$(sed -n 's/.*"ownerGithubUser"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$team_ltmp" | head -n1)" = "$TEAM_OWNER" ]; then
      mv "$team_ltmp" "$TEAM_LCFG"
      echo "  wrote instance.config.local.json (ownerGithubUser: $TEAM_OWNER)"
    else
      rm -f "$team_ltmp"
      echo "error: instance.config.local.json did not verify, so nothing was written." >&2
      echo "       Create it by hand: { \"ownerGithubUser\": \"$TEAM_OWNER\" }" >&2
    fi
  fi
  rm -f "$TEAM_ROSTER"
fi

echo "Done. Machinery symlinked & gitignored; seed content in place."
echo "Next: edit instance.config.json, then run /pm-loop from this directory."
echo "      (Set reposRoot first, then 'scripts/link-repos.sh' fills in repos/.)"

# 5. One nudge, and only a nudge. A pull can bring a stricter SCHEMA.md, whose validator
# reaches the instance instantly through its symlink and starts reporting errors against
# documents written under the old rules — and nothing repairs them until someone runs
# the migration. So say so, once, and point at upgrade.sh.
#
# Deliberately NOT the migration itself: this script is safe to run blindly precisely
# because it only links and seeds-if-absent, and spending that property to save the user
# one command would be a bad trade. Non-fatal, and silent unless the validator says
# exactly "there are errors" (exit 1): absent (an instance older than the validator) or
# clean says nothing, and any other exit code — 2 is "not an instance root" — is not
# something a user can act on from here.
# Retired seed content — REPORT, never remove. See RETIRED for why the
# machinery sweep (step 2b) may delete and this may not: a symlink into this template
# whose target is gone has one possible meaning; a seed file the human has owned since it
# was copied does not. Absence of the manifest, or an empty one, is silence — not an error.
RETIRED_LIST="$TEMPLATE_DIR/RETIRED"
if [ -f "$RETIRED_LIST" ]; then
  retired_found=0
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in ''|'#'*) continue ;; esac
    # <path><TAB><reason>; a line with no tab is all path and no reason.
    rpath="${line%%	*}"
    reason="${line#*	}"
    [ "$reason" = "$rpath" ] && reason="no longer shipped by the template"
    [ -n "$rpath" ] || continue
    # Refuse a path that escapes the instance root. The manifest is our own file, so this
    # is not about a hostile author — it is that `../victim.md` would make the printed
    # `rm` command operate OUTSIDE the instance, and a human pasting a command this script
    # handed them has every reason to trust it. Reject rather than normalise: a path with
    # `..` in it is a mistake in the manifest, and silently rewriting a mistake into a
    # different path is how you delete the wrong file.
    case "$rpath" in
      /*|~*)      echo "  warn  RETIRED entry ignored (not instance-relative): $rpath" >&2; continue ;;
      ..|../*|*/..|*/../*) echo "  warn  RETIRED entry ignored (escapes the instance root): $rpath" >&2; continue ;;
    esac
    # Only ever report something that is actually there, and only a real file — a
    # leftover symlink is step 2b's business, not this list's.
    if [ -f "$TARGET/$rpath" ] && [ ! -L "$TARGET/$rpath" ]; then
      [ "$retired_found" -eq 0 ] && echo "Retired content still present (yours to keep or delete):"
      retired_found=$((retired_found+1))
      echo "  stale $rpath — $reason"
      echo "        rm $(printf '%q' "$TARGET/$rpath")"
    fi
  done < "$RETIRED_LIST"
fi

# One report-only nudge for a stale session-defaults import.
#
# seed/CLAUDE.md used to end with `@~/.claude/claude-defaults.md` — a file only a
# SEPARATE repo's installer ever created, and the one hard dependency this template had
# on it. Every instance inherited the line, and on a machine that never ran that
# installer it resolved to nothing: a missing @import is a silent no-op, which is exactly
# why nobody noticed. The section is inlined in seed/CLAUDE.md now, but seed content is
# copied only when ABSENT, so an instance stamped earlier keeps the dead import forever.
#
# Report it, never rewrite it: CLAUDE.md is instance data the human owns and has very
# likely edited around. Same contract as RETIRED — say the exact thing to do, once.
# The pattern is ANCHORED to the start of a line: seed/CLAUDE.md's replacement section
# explains itself by quoting the old import inside an HTML comment, and an unanchored
# match would nag every freshly-stamped instance about a line it does not have.
if [ -f "$TARGET/CLAUDE.md" ] \
   && grep -qE '^[[:space:]]*@~/\.claude/claude-defaults\.md[[:space:]]*$' "$TARGET/CLAUDE.md"; then
  echo "This instance's CLAUDE.md still imports ~/.claude/claude-defaults.md:"
  echo "      that file is no longer shipped, and a missing @import fails SILENTLY."
  echo "      Replace that one line with the '## Session defaults' section from:"
  echo "        $SEED_SRC/CLAUDE.md"
fi

if [ -e "$TARGET/scripts/validate-bundle.sh" ]; then
  vrc=0
  ( cd "$TARGET" && bash scripts/validate-bundle.sh ) >/dev/null 2>&1 || vrc=$?
  if [ "$vrc" -eq 1 ]; then
    echo "Note: this bundle has schema errors. To see and repair them, run:"
    echo "      $TEMPLATE_DIR/upgrade.sh $TARGET"
  fi
fi
