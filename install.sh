#!/usr/bin/env bash
#
# install.sh — provision (or refresh) an ai-bridge INSTANCE, or link the CONFIG LAYER.
#
#   Usage:
#     install.sh [TARGET]              # install/refresh an instance at TARGET (default: cwd)
#     install.sh --instance [TARGET]   # the same thing, stated explicitly
#     install.sh --config              # link config/ into ~/.claude (CLAUDE_CONFIG_DIR wins)
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
# CONFIG mode links the two tiers of `config/` into the Claude Code config dir, one
# FILE at a time — never a whole directory (see the CONFIG LAYER block below):
#   · config/required/     — the agents ai-bridge's own role agents probe for.
#   · config/opinionated/  — one human's commands, output style, hooks and scripts.
# Either tier may be deleted; absence is safe. An instance never needs either, and the
# config layer never needs an instance.
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
      sed -n '3,38p' "$0" | sed 's/^# \{0,1\}//'
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
# THE ARROW IS ONE-WAY. `symlink/` must never *require* `config/`. The role agents keep
# probing with `test -f`, so an instance stamped on a machine that never ran `--config`
# works — it loses a second opinion, not a feature. `tests/config-layer.test.sh` asserts
# a config-less stamp. Both tiers are deletable: `rm -rf config/opinionated` (or
# `config/required`) must break nothing and error nowhere.
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
CONFIG_TIERS="required opinionated"
# Honour CLAUDE_CONFIG_DIR: when it is set, Claude Code reads settings, agents and hooks
# from there instead of ~/.claude, so installing into $HOME would put the layer somewhere
# nothing loads it from. It is also the same expression config/opinionated/settings.json
# uses to reference its hooks, so the installer and the hook command cannot disagree.
CONFIG_DEST="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

# Every linkable file, as "<tier><TAB><relative path>".
#
# Three kinds of file are never linked, at any depth: `README.md` (a repo doc — and in
# commands/ Claude Code would register it as the command `/README`), `*.example.json`
# (copy-from templates: a linked one is clutter that dangles if this checkout moves), and
# settings.json, which is linked by its own block below because it is the one file that
# can already hold permissions and plugins a human tuned by hand.
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

# Top-level entries the config layer manages — the roots of the dangling-link sweep.
# Roots to sweep for retired links. Deliberately NOT just the roots present in the
# current source tree: if the last file under `config/opinionated/commands/` is removed,
# that root disappears from `config_entries`, the sweep stops searching
# `$CONFIG_DEST/commands`, and its dangling links stay registered — a retired command that
# still shows up, or a retired hook that exits 127 on every startup. The whole point of the
# sweep is the case where a source file is GONE, so it cannot be driven by what remains.
#
# The fixed list is the set this installer has ever managed. Add to it when a new root
# ships; never prune it, for the same reason RETIRED is never pruned — an install from
# years ago still has the directory.
CONFIG_MANAGED_TOPS="agents commands hooks output-styles scripts skills rules claude-defaults.md MEMORY.md settings.json"
config_tops() { { config_entries | cut -f2 | sed 's#/.*##'; printf '%s\n' $CONFIG_MANAGED_TOPS; } | sort -u; }

# Print the first DIRECTORY component of $1 that is a symlink under the config dir.
#
# This guard is what keeps the per-file fix honest. A whole-directory symlink left over
# from another setup (this machine's ~/.claude/agents pointed into the parent config repo
# for a year) turns "$CONFIG_DEST/agents/x.md" into a write INSIDE that other checkout —
# modifying a repo nobody asked us to touch, silently, and leaving the config dir with no
# file of its own. So refuse the entry and say what to do about it.
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
config_sweep() {
  local t roots="" rel was
  while IFS= read -r t; do
    [ -n "$t" ] || continue
    if [ -d "$CONFIG_DEST/$t" ] && [ ! -L "$CONFIG_DEST/$t" ]; then roots="$roots $CONFIG_DEST/$t"; fi
  done <<EOF
$(config_tops)
EOF
  {
    find "$CONFIG_DEST" -maxdepth 1 -type l -print 2>/dev/null || true
    # shellcheck disable=SC2086
    if [ -n "$roots" ]; then find $roots -type l -print 2>/dev/null || true; fi
  } | sort -u | while IFS= read -r l; do
    [ -n "$l" ] || continue
    rel="${l#"$CONFIG_DEST"/}"
    case "$(readlink "$l")" in
      "$CONFIG_SRC"/*)
        if [ ! -e "$l" ]; then rm -f "$l"; echo "  retire $rel (no longer shipped by the config layer)"; fi
        continue ;;
    esac
    # Not ours by target, so the branch above cannot see it — but it may be OUR OWN dead
    # backup of a link we relinked a moment ago. See dead_backup() for why that is the one
    # thing safe to delete here. The config layer accumulates this debris exactly as the
    # instance half does: 24 links dangled in ~/.claude when the checkout moved.
    if dead_backup config_ours "$rel" "$l"; then
      was="$(readlink "$l")"; rm -f "$l"
      echo "  sweep  $rel (dead backup of a relinked file, was -> $was)"
    fi
  done
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
  local tier rel src dst bak off tgt n_link=0 n_ok=0 n_moved=0 n_refused=0 reported=" " dups
  config_require_src

  # Refuse BEFORE any write when both tiers claim the same relative path: whichever ran
  # second would move the first aside as a .bak and shadow it, and a shadowed default is
  # exactly the silent failure this whole layer exists to remove.
  dups="$(config_entries | cut -f2 | sort | uniq -d)"
  if [ -n "$dups" ]; then
    echo "error: config/required and config/opinionated both declare:" >&2
    while IFS= read -r rel; do [ -n "$rel" ] && echo "         $rel" >&2; done <<EOF
$dups
EOF
    echo "       Each path must live in exactly one tier. Nothing was linked." >&2
    exit 2
  fi

  mkdir -p "$CONFIG_DEST"
  echo "Linking the ai-bridge config layer into $CONFIG_DEST"
  while IFS=$'\t' read -r tier rel; do
    [ -n "$rel" ] || continue
    src="$CONFIG_SRC/$tier/$rel"; dst="$CONFIG_DEST/$rel"
    off="$(config_link_parent "$rel" || true)"
    if [ -n "$off" ]; then
      n_refused=$((n_refused+1))
      case "$reported" in
        *" $off "*) ;;
        *)
          reported="$reported$off "
          echo "  skip  ${rel%/*}/ — $off is a symlink -> $(readlink "$off")" >&2
          echo "        Linking through it would write into that other checkout. Replace it" >&2
          echo "        with a real directory first, keeping whatever it holds:" >&2
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
      case "$tgt" in "$CONFIG_SRC"/*) rm "$dst" ;; esac
    fi
    mkdir -p "$(dirname "$dst")"
    if [ -e "$dst" ] || [ -L "$dst" ]; then
      bak="$dst.bak.$(date +%s)"; mv "$dst" "$bak"
      echo "  moved $rel -> ${bak##*/}"; n_moved=$((n_moved+1))
    fi
    ln -s "$src" "$dst"
    echo "  link  $rel"; n_link=$((n_link+1))
  done <<EOF
$(config_entries)
EOF

  # settings.json is per-machine sensitive — it can carry permissions, env vars and
  # plugin choices somebody tuned by hand, and it is the one file here where replacing
  # a value could widen what Claude is allowed to *do* rather than how it reports. So:
  # adopt the baseline only when there is nothing to lose, and otherwise print the two
  # commands and stop. This install never edits a real settings.json — deliberately not
  # even to merge a display-only key, which keeps `--config` purely additive: every
  # write it makes is a new named file or a symlink it created itself.
  local sjs="$CONFIG_SRC/opinionated/settings.json" sjd="$CONFIG_DEST/settings.json"
  if [ -f "$sjs" ]; then
    if [ -L "$sjd" ] && [ "$(readlink "$sjd")" = "$sjs" ]; then
      echo "  ok    settings.json (already linked)"
    elif [ -L "$sjd" ] && [ ! -e "$sjd" ]; then
      rm "$sjd"; ln -s "$sjs" "$sjd"; echo "  relink settings.json (was dangling)"
    elif [ -e "$sjd" ] || [ -L "$sjd" ]; then
      echo "  keep  settings.json (yours — permissions and plugins left alone)"
      echo "        To adopt this layer's baseline instead, back yours up and link it:"
      echo "          mv $(printf '%q' "$sjd") $(printf '%q' "$sjd").bak.\$(date +%s)"
      echo "          ln -s $(printf '%q' "$sjs") $(printf '%q' "$sjd")"
      echo "        Or copy just the display-only keys across by hand: statusLine,"
      echo "        outputStyle (\"Brief\"), and the format-on-write PostToolUse hook."
    else
      ln -s "$sjs" "$sjd"; echo "  link  settings.json"
    fi
  fi

  config_sweep

  echo "Done. $n_link linked, $n_ok already in place, $n_moved moved aside."
  if [ "$n_refused" -gt 0 ]; then
    echo "warn  $n_refused file(s) NOT linked: a directory in the way is a symlink (above)." >&2
    echo "      Fix those directories and re-run; nothing was written through them." >&2
    return 1
  fi
  echo "Next: restart Claude Code (/exit, then \`claude\`) so it re-scans agents and commands."
  return 0
}

config_uninstall() {
  config_require_src
  echo "Removing ai-bridge config-layer symlinks from $CONFIG_DEST"
  local tier rel
  while IFS=$'\t' read -r tier rel; do
    [ -n "$rel" ] || continue
    if config_ours "$rel"; then rm "$CONFIG_DEST/$rel"; echo "  rm    $rel"; fi
  done <<EOF
$(config_entries)
EOF
  if config_ours settings.json; then rm "$CONFIG_DEST/settings.json"; echo "  rm    settings.json"; fi
  config_sweep
  echo "Done. Your runtime state, real files, and *.bak.* backups were left untouched."
  return 0
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
# state. Content is a valid empty queue, so show-awaiting.sh stays silent until
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
# SNAPSHOT.json is a LOCAL, gitignored file. Having one puts an instance on the
# TERMINAL board and makes a page renderable — it does not publish anything. Publishing
# is a separate, deliberate act (rendering the board to HTML, then hosting that page at
# an Artifact URL), and question TEXT needs SNAPSHOT_QUESTION_TEXT=1 on top of that.
# On-by-default is therefore safe for an instance that must not publish.
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
# Each line is guarded SEPARATELY. A single guard on the root line would silently
# skip the per-project one whenever only the root line was already present, and the
# two are not interchangeable. The match is EXACT (`-qxF`), not `^/?index\.md$` like
# /repos/ above: a bare `index.md` line is a different pattern that also swallows
# `knowledge/index.md`, so it must not be read as "already handled".
if ! grep -qxF '/index.md' "$gi" || ! grep -qxF '/projects/*/index.md' "$gi"; then
  cat >> "$gi" <<'GI'

# Derived navigation indexes — the root one and each project's, rewritten by every
# /pm-loop tick from the documents they summarise. A view, not source.
# `knowledge/index.md` is deliberately NOT ignored: it is the KB's curated lookup
# surface, changes only when the KB changes, and a fresh clone needs it present.
GI
  grep -qxF '/index.md' "$gi"             || echo '/index.md' >> "$gi"
  grep -qxF '/projects/*/index.md' "$gi"  || echo '/projects/*/index.md' >> "$gi"
fi

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
