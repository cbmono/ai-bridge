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
      sed -n '3,33p' "$0" | sed 's/^# \{0,1\}//'
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
  local t roots=""
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
    case "$(readlink "$l")" in
      "$CONFIG_SRC"/*) if [ ! -e "$l" ]; then rm -f "$l"; echo "  retire ${l#"$CONFIG_DEST"/} (no longer shipped by the config layer)"; fi ;;
    esac
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
# SNAPSHOT.json is opt-in by presence: scripts/write-snapshot.sh rewrites it only when
# it exists and never creates it, and scripts/build-board.sh leaves an instance without
# one off the board entirely. So `rm SNAPSHOT.json` takes this instance off the board
# for good — and FIRST_STAMP is what makes "for good" true, because a refresh that
# re-created the file would silently undo that decision.
#
# It is deliberately generated ROOT content and not a file under symlink/: machinery is
# re-linked unconditionally on every run (see AUTONOMY.md's hazard in
# .claude/rules/ai-bridge.md), so a deletable capability built out of a machinery file
# comes back by itself. A gitignored root file has no such hole.
#
# Seeded content is a VALID EMPTY snapshot rather than an empty file: build-board.sh
# parses this as JSON, and a zero-byte file would render an "unreadable snapshot" note
# on a brand-new instance that has done nothing wrong.
if [ "$FIRST_STAMP" = yes ] && [ ! -e "$TARGET/SNAPSHOT.json" ]; then
  cat > "$TARGET/SNAPSHOT.json" <<'SNAPSHOT'
{
  "_schema": "ai-bridge board snapshot v1",
  "_sensitivity": "Derived and gitignored. Rewritten by scripts/write-snapshot.sh each /pm-loop tick. Delete this file to take this instance off the board for good.",
  "group": "",
  "generated_at": "",
  "counts": {"projects": 0, "tasks": 0, "awaiting": 0},
  "projects": []
}
SNAPSHOT
  echo "  seed  SNAPSHOT.json (on the board; delete it to take this instance off)"
elif [ "$FIRST_STAMP" = no ] && [ ! -e "$TARGET/SNAPSHOT.json" ]; then
  echo "  skip  SNAPSHOT.json (absent by choice — run 'touch SNAPSHOT.json' to re-enable)"
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

# 2b. Retire machinery the template no longer ships.
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
