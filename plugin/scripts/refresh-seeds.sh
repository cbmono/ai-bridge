#!/usr/bin/env bash
#
# refresh-seeds.sh — port this repo's SEED changes into an already-stamped bundle.
#
#   Usage: refresh-seeds.sh <bundle-dir>              # report what has drifted (default)
#          refresh-seeds.sh <bundle-dir> --apply      # 3-way merge the safe ones
#          refresh-seeds.sh <bundle-dir> --no-deepen  # never fetch, even a shallow source
#
# WHY THIS EXISTS, AND WHY IT IS A MERGE RATHER THAN A COPY.
# `init-bundle.sh` copies `seed/` into a bundle **only if absent**, and that asymmetry is
# deliberate: seed files are the ones a bundle then OWNS and edits (`instance.config.json`
# gets the group's org and reposRoot, `CLAUDE.md` gets house rules, `log.md` and `index.md`
# grow content). The cost is that a later seed edit never reaches a bundle already
# stamped. Copying the new seed over the bundle's copy would deliver it — and destroy
# whatever the bundle wrote. So neither "copy" nor "leave it" is right, and the answer
# has to be per-file evidence:
#
#   · The seed file has only ever held its CURRENT content ⇒ there is no seed change to
#     deliver, so whatever the bundle holds is entirely its own. Quiet. This is the normal
#     state of `log.md` and `index.md`, and naming them every run is how a report teaches
#     people to stop reading it.
#   · The bundle's copy is byte-identical to a PRIOR version of that seed file in this
#     repo's git history ⇒ nothing was ever hand-edited. That old seed IS the merge base,
#     provably, and the merge result is exactly the new seed. Measured: on 2026-08-22,
#     `_ai-bridge-private/CLAUDE.md` was the pre-v2 seed verbatim, and all three bundles'
#     `README.md` were.
#   · It matches no prior version ⇒ it was hand-edited. The closest prior version by diff
#     size is used as a best-effort merge base and the seed's own change is applied ON TOP
#     of the bundle's edits (`git merge-file`, i.e. a real 3-way merge, never a copy).
#     Clean ⇒ portable, and the hand edits survive by construction. Conflicting ⇒ reported
#     with the diff, the file is NOT touched, and under `--apply` the conflicted merge is
#     saved beside it as `<file>.bak.<epoch>` so the markers are there to read.
#   · `instance.config.json` / `instance.config.local.json` ⇒ NEVER merged, only reported.
#     Config is the one seed file whose purpose is to diverge, and a value in it is
#     routinely a decision somebody made minutes ago. Same reason `/ai-bridge:welcome` has
#     no fixer for its `config-uncommitted` row.
#   · No git history at all for the seed file (no repo, shallow clone, an uncommitted seed
#     file) ⇒ no merge base, no evidence, no action. Reported for a human.
#     A PATH MOVE IS NOT ONE OF THOSE CASES, AND KEEPING IT OUT IS WHAT `git log --follow`
#     BUYS: when #125 did `git mv seed plugin/seed`, a by-path lookup saw only the commits
#     at the NEW path — for six seed docs, the rename alone, whose blob IS the current seed
#     — so the base every bundle was stamped from became unreachable and the drift read as
#     UNKNOWN where there was no history to fall back on and, worse, as a silent "in sync"
#     where there was. Follow renames, or the next move repeats it.
#
# WHERE THE HISTORY COMES FROM WHEN THE PLUGIN IS INSTALLED RATHER THAN CHECKED OUT.
# `--follow` fixed the lookup; it could not fix having nothing to look at. An installed
# plugin lives in `~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/`, a plain
# copy with NO `.git` — so on a real machine every seed file a bundle had edited came back
# UNKNOWN (measured 2026-09-06: 8 of 12 on `_ai-bridge-private`, 7 on alteos) and the
# script was useless exactly where people run it. Three sources are tried, in this order,
# and the run SAYS which one it got on its `history:` line:
#
#   1. THIS CHECKOUT — the plugin root is inside a git work tree (a developer running
#      from the repo). Unchanged behaviour, and still the best source.
#   2. THE MARKETPLACE CLONE — `~/.claude/plugins/marketplaces/<marketplace>/`, derived
#      from the cache path's own `<marketplace>` segment rather than searched for, is a
#      real git clone of the repo the plugin was built from. It is accepted ONLY if its
#      `seed` tree at HEAD is byte-for-byte the seed this plugin ships (same paths, same
#      blobs): a clone that has moved on, or belongs to another plugin, is a stranger's
#      history and would compute merge bases for content this copy never had. Rejected
#      with the reason printed, never silently.
#   3. THE BUNDLE'S OWN STAMPED-SEED RECORD — `.ai-bridge/seed-base/`, pristine copies
#      `init-bundle.sh` writes of every seed file IT stamped. That is the merge base by
#      construction (it is what the bundle's copy was made from), it needs no git at all,
#      and it is the only source that still works offline on a machine with no clone.
#      A bundle stamped before this existed has no record — hence source 2.
#   4. Nothing ⇒ UNKNOWN, and the message names both fixes rather than just the symptom.
#
# A SHALLOW CLONE IS NOT A HISTORY SOURCE UNTIL IT IS DEEPENED. `claude` clones a
# marketplace shallow (measured: 26 commits, `.git/shallow` present), and a truncated walk
# is the dangerous shape rather than the loud one — the seed's older versions are simply
# absent, so "the seed has only ever held its current content" reads TRUE and the drift
# goes silently unreported, which is the #125 failure by a second route. So: detect it,
# `git fetch --unshallow` once, and say so; and if that cannot be done (`--no-deepen`, or
# no network) treat the truncated history as evidence for what it DOES contain — a
# verbatim match is still proof — while refusing to infer ABSENCE from it.
#
# "PRIOR" is doing real work in those rules. The current content's own blob is in the history
# too, and for a file the bundle grew past it is often the blob CLOSEST to what the bundle
# holds — pick it as the base and the base→seed diff is empty, the merge is a no-op, and real
# drift reports as "nothing to port". The fixture caught exactly that: a hand-diverged
# `CLAUDE.md` read as in sync.
#
# A CONFLICT IS NEVER RESOLVED BY FORCE. That is the whole point of the report: a bundle's
# hand edits are the only copy of a decision somebody made, and this script cannot know
# whether the seed's new wording supersedes it.
#
# EVERY CLAIMED MUTATION IS READ BACK. `migrate-bundle.sh` once printed FIXED for a write
# that never landed, which is worse than the error it claimed to fix. So the PORTED label
# is printed only after the file on disk has been compared against the merge result and
# checked for conflict markers; otherwise it says FAILED, on stderr, and the run exits 1.
#
# THIS WAS `upgrade.sh`, AND IT LOST THREE OF ITS FOUR STAGES ON THE WAY HERE. Stage 1 was
# `install.sh` — machinery symlinks, which a bundle no longer has. Stages 2 and 3 ran the
# bundle's own `validate-bundle.sh` and `migrate-bundle.sh` through symlinks that are also
# gone; both ship in the plugin now and are reachable directly, and `/ai-bridge:welcome
# check` is the one command that surveys a bundle. What was left is the stage nothing else
# can do, which is this one.
#
# REPORT-ONLY BY DEFAULT, like `migrate-bundle.sh` and `prune-worktrees.sh`. A default run
# writes nothing at all. Read the report, then re-run with --apply — or reach it as
# `/ai-bridge:welcome fix`, or `/ai-bridge:init <dir> --refresh-seeds`.
#
# Idempotent: a second run finds nothing to do. Refuses a directory that is not already a
# bundle root — creating a NEW bundle is `init-bundle.sh`'s job, not a refresh.
#
# Bash + awk + git only — no jq, no python.
# Verified by tests/upgrade.test.sh.
set -euo pipefail

# The plugin root — ONE directory up from this script and then verified. Same rule as
# init-bundle.sh, and see the long comment there for why: `source: ./plugin` means an
# INSTALLED plugin is the contents of `plugin/`, so `<cache>/scripts` and
# `<root>/plugin/scripts` both resolve to the directory that carries `seed/` and `VERSION`.
BIN_DIR="$(cd "$(dirname "$0")" && pwd)"
SELF="$BIN_DIR/$(basename "$0")"
PLUGIN_ROOT="$(cd "$BIN_DIR/.." 2>/dev/null && pwd || true)"
[ -n "$PLUGIN_ROOT" ] && [ -f "$PLUGIN_ROOT/VERSION" ] || {
  echo "refresh-seeds: cannot locate the ai-bridge plugin root from $BIN_DIR" >&2; exit 2; }
SEED_SRC="$PLUGIN_ROOT/seed"
DIFF_CAP="${UPGRADE_DIFF_LINES:-40}"   # lines of a conflicting diff to print inline

APPLY=0
DEEPEN=1
TARGET=""
for arg in "$@"; do
  case "$arg" in
    --apply) APPLY=1 ;;
    --no-deepen) DEEPEN=0 ;;
    -h|--help)
      # Range covers the whole header block above. Extend it when you add lines
      # there, or --help truncates silently.
      sed -n '2,/^set -euo/p' "$0" | sed 's/^# \{0,1\}//; $d'
      exit 0 ;;
    -*) echo "error: unknown flag '$arg'" >&2; exit 2 ;;
    *)
      [ -z "$TARGET" ] || { echo "error: multiple target directories given" >&2; exit 2; }
      TARGET="$arg" ;;
  esac
done
TARGET="$(cd "${TARGET:-$PWD}" 2>/dev/null && pwd || true)"
[ -n "$TARGET" ] || { echo "refresh-seeds: target directory does not exist" >&2; exit 2; }
[ -d "$SEED_SRC" ] || {
  echo "refresh-seeds: template is incomplete (expected $SEED_SRC)" >&2; exit 2; }

# A bundle root, or refuse. `-L` is still tested for SCHEMA.md because a bundle that has
# not been converted yet carries it as a symlink into a template checkout — possibly a
# BROKEN one, which is exactly a bundle that needs this, not a stranger.
if [ ! -e "$TARGET/instance.config.json" ] || { [ ! -e "$TARGET/SCHEMA.md" ] && [ ! -L "$TARGET/SCHEMA.md" ]; }; then
  cat >&2 <<EOF
refresh-seeds: $TARGET is not an ai-bridge bundle root (expected SCHEMA.md + instance.config.json).
               To create a NEW bundle, run /ai-bridge:init $TARGET
EOF
  exit 2
fi

TMPD="$(mktemp -d "${TMPDIR:-/tmp}/ai-bridge-refresh-seeds.XXXXXX")"
trap 'rm -rf "$TMPD"' EXIT

failed=0

LEFT_N=0
left() { LEFT_N=$((LEFT_N+1)); printf '%2d. %s\n' "$LEFT_N" "$1" >> "$TMPD/left"; }
left_more() { printf '    %s\n' "$1" >> "$TMPD/left"; }
: > "$TMPD/left"
: > "$TMPD/conflicts"

blob_of() { git -C "$PLUGIN_ROOT" hash-object --no-filters -- "$1"; }

# ------------------------------------------------------ where the merge base comes from
#
# Every git query below runs from the REPO ROOT with root-relative paths. `git -C <dir>`
# makes a pathspec relative to <dir>, so querying from the plugin dir with the path
# git reports for it ("seed/…") silently matched nothing — and "no history"
# is indistinguishable from "no evidence", which downgraded every drifted file to
# UNKNOWN. Resolve the root once, and prefix paths with the template's own prefix.
HIST_KIND=none        # git | record | none — which shape the per-file lookup takes
HIST_LABEL=""         # what the `history:` line says
HIST_SHALLOW=0        # the source's history is truncated; absence proves nothing
REPO_ROOT=""; PREFIX=""
BASE_DIR="$TARGET/.ai-bridge/seed-base"
MKT_DIR=""            # the marketplace clone we derived, whether or not we accepted it
MKT_WHY=""            # why it was rejected, so the report can say

# The marketplace clone for THIS plugin, derived from the install path's own shape:
# `<…>/plugins/cache/<marketplace>/<plugin>/<version>` ⇒ `<…>/plugins/marketplaces/<marketplace>`.
# Derived, never searched for: `~/.claude/plugins/marketplaces/` holds every marketplace
# the machine has ever added, and picking the wrong one gives a stranger's history.
marketplace_clone() {
  local mkt cache plugins
  mkt="$(cd "$PLUGIN_ROOT/../.." 2>/dev/null && pwd)" || return 0
  [ -n "$mkt" ] || return 0
  cache="$(dirname "$mkt")"; plugins="$(dirname "$cache")"
  [ "$(basename "$cache")" = "cache" ] || return 0
  [ "$(basename "$plugins")" = "plugins" ] || return 0
  printf '%s\n' "$plugins/marketplaces/$(basename "$mkt")"
}

# The seed tree a repo carries at HEAD under <prefix>, as "<blob> <path-under-seed>" lines.
# `ls-tree`'s own output is "<mode> <type> <blob>\t<path>"; --format is git ≥2.36 only.
tree_seed_list() { # <repo> <prefix>
  git -C "$1" -c core.quotePath=false ls-tree -r HEAD -- "${2}seed" 2>/dev/null \
    | awk -v pre="${2}seed/" '{ sha=$3; sub(/^[^\t]*\t/, ""); p=$0;
                                if (index(p, pre) == 1) { print sha " " substr(p, length(pre)+1) } }' \
    | sort
}

# The same shape for the seed this plugin actually ships. Compared as a WHOLE TREE — every
# path and every blob — because a clone that has moved even one seed file on has content
# this copy never carried, and a merge base taken from it is a base for somebody else's
# plugin. Cheap: the seed is 20 files.
plugin_seed_list() {
  # `.DS_Store` is excluded because the Finder writes one into any directory it visits and
  # a cache copy is a directory like any other; it is in `seed/.gitignore`, so it can never
  # be on the git side of this comparison and would reject a clone that is in fact correct.
  ( cd "$SEED_SRC" && find . -type f ! -name .DS_Store | sed 's#^\./##' | sort ) \
    | while IFS= read -r f; do [ -n "$f" ] && printf '%s %s\n' "$(blob_of "$SEED_SRC/$f")" "$f"; done \
    | sort
}

# Shallow by the file the criterion names, and by git's own answer — a linked work tree
# keeps `shallow` in the common git dir, which the literal `$1/.git/shallow` would miss.
is_shallow() { # <repo>
  local gd
  gd="$(git -C "$1" rev-parse --git-common-dir 2>/dev/null)" || return 1
  case "$gd" in /*) ;; *) gd="$1/$gd" ;; esac
  [ -f "$gd/shallow" ] && return 0
  [ "$(git -C "$1" rev-parse --is-shallow-repository 2>/dev/null)" = "true" ]
}

# Bounded, non-interactive, and it never asks for a credential: a refresh must not hang on
# a password prompt in a background tick. `timeout` is coreutils and absent from a stock
# macOS, so the transport's own deadlines are the fallback bound rather than nothing.
deepen() { # <repo>
  local t=""
  command -v timeout  >/dev/null 2>&1 && t=timeout
  [ -n "$t" ] || { command -v gtimeout >/dev/null 2>&1 && t=gtimeout; }
  ${t:+$t 180} env GIT_TERMINAL_PROMPT=0 GIT_ASKPASS=/bin/echo \
      GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh -o BatchMode=yes -o ConnectTimeout=15}" \
      GIT_HTTP_LOW_SPEED_LIMIT=1000 GIT_HTTP_LOW_SPEED_TIME=30 \
      git -C "$1" fetch --quiet --unshallow >/dev/null 2>&1
}

use_git_source() { # <repo> <prefix> <label>
  REPO_ROOT="$1"; PREFIX="$2"; HIST_KIND=git; HIST_LABEL="$3"
}

resolve_history() {
  # 1. This checkout.
  if git -C "$PLUGIN_ROOT" rev-parse --show-toplevel >/dev/null 2>&1; then
    use_git_source "$(git -C "$PLUGIN_ROOT" rev-parse --show-toplevel)" \
                   "$(git -C "$PLUGIN_ROOT" rev-parse --show-prefix)" \
                   "this checkout — $(git -C "$PLUGIN_ROOT" rev-parse --show-toplevel)"
    return 0
  fi

  # 2. The marketplace clone this install came from.
  MKT_DIR="$(marketplace_clone)"
  if [ -z "$MKT_DIR" ]; then
    MKT_WHY="the install path is not a plugin cache, so no marketplace clone can be derived"
  elif [ ! -d "$MKT_DIR" ]; then
    MKT_WHY="no marketplace clone at $MKT_DIR"
  elif ! git -C "$MKT_DIR" rev-parse --verify -q HEAD >/dev/null 2>&1; then
    MKT_WHY="$MKT_DIR is not a git repository with a commit"
  else
    plugin_seed_list > "$TMPD/seed.mine"
    local p found=""
    for p in "plugin/" ""; do
      git -C "$MKT_DIR" rev-parse --verify -q "HEAD:${p}seed" >/dev/null 2>&1 || continue
      tree_seed_list "$MKT_DIR" "$p" > "$TMPD/seed.theirs"
      if cmp -s "$TMPD/seed.mine" "$TMPD/seed.theirs"; then found="$p"; break; fi
    done
    if [ -z "$found" ]; then
      MKT_WHY="$MKT_DIR carries a different seed tree at HEAD than this plugin copy"
    else
      use_git_source "$MKT_DIR" "$found" "marketplace clone — $MKT_DIR @ $(git -C "$MKT_DIR" rev-parse --short HEAD)"
      is_shallow "$MKT_DIR" && HIST_SHALLOW=1
      return 0
    fi
  fi

  # 3. The bundle's own record of what it was stamped from.
  if [ -d "$BASE_DIR" ]; then
    HIST_KIND=record
    HIST_LABEL="this bundle's stamped-seed record — $BASE_DIR"
    return 0
  fi
  HIST_KIND=none
  HIST_LABEL="none — an installed plugin is a plain copy and carries no git history"
}

echo "ai-bridge seed refresh — $TARGET"
echo "plugin:   $PLUGIN_ROOT"
if [ "$APPLY" -eq 1 ]; then
  echo "mode:     APPLY — the mergeable changes below WILL be written."
else
  echo "mode:     REPORT ONLY — nothing is written."
fi
resolve_history
echo "history:  $HIST_LABEL"

# A SHALLOW CLONE IS NEVER TREATED AS A FULL HISTORY. Deepening is a fetch into the
# plugin manager's own clone — it adds objects and touches no bundle and no working tree —
# so it runs in report mode too; `--no-deepen` declines it. Whichever way it goes, the
# run says so, and an un-deepened source stops proving ABSENCE (see the loop below).
if [ "$HIST_SHALLOW" -eq 1 ]; then
  if [ "$DEEPEN" -eq 1 ] && deepen "$REPO_ROOT" && ! is_shallow "$REPO_ROOT"; then
    HIST_SHALLOW=0
    echo "          (it was a shallow clone — deepened with git fetch --unshallow)"
  else
    echo "          SHALLOW clone: its history is truncated, so a seed file with no older"
    echo "          version found is reported rather than assumed unchanged. Deepen it with:"
    echo "            git -C '$REPO_ROOT' fetch --unshallow"
  fi
fi

# ---------------------------------------------------------------- seed drift
echo
echo "== seed drift (a seed edit never reaches a stamped bundle by itself) =="
[ "$HIST_KIND" != none ] || echo "  note: no merge base source is reachable, so differing files can only be"
[ "$HIST_KIND" != none ] || echo "        reported, never ported. The fix is under \"what's left for you\" below."

# Every historical blob of a seed path, newest first, deduplicated — ACROSS RENAMES.
#
# `--follow` is the whole of this function's correctness, not a nicety. Without it the walk
# stops at the commit that created the current path, and a seed directory that moves takes
# every bundle's merge base with it: #125's `git mv seed plugin/seed` left six seed docs
# with exactly one commit at the new path, the rename, whose blob is the seed's CURRENT
# content — so "prior" came back empty and the drift was read as the bundle's own.
#
# `--name-only` is what makes it usable: under `--follow` it prints the path AS IT WAS in
# each commit, so the blob is read from the tree with the name that commit actually had.
# `ls-tree`ing the new path against a pre-rename commit finds nothing, which is the same
# empty answer by a longer route. A 40-hex line is the commit, anything else is the path —
# a seed path can never look like a SHA. `core.quotePath=false` keeps a non-ASCII name
# readable; a name with a newline in it is still beyond this parse, and is not a seed path.
#
# THE RECORD SOURCE ANSWERS THE SAME QUESTION WITH ONE CANDIDATE. `.ai-bridge/seed-base/`
# holds the seed file the stamp actually copied, so it is not a candidate base — it IS the
# base, with no history to search. Both shapes hand back blob ids so the loop below is one
# piece of code; `cat_base` is what knows where the bytes come from.
hist_blobs() { # <seed-relative path>
  case "$HIST_KIND" in
    git)
      git -C "$REPO_ROOT" -c core.quotePath=false \
          log --follow --format=%H --name-only -- "${PREFIX}seed/$1" 2>/dev/null \
      | awk '/^[0-9a-f]+$/ && length($0) == 40 { c = $0; next }
             NF && c != "" { print c " " $0 }' \
      | while IFS=' ' read -r c p; do
          git -C "$REPO_ROOT" ls-tree "$c" -- "$p" 2>/dev/null | awk '{print $3}'
        done | awk 'NF && !seen[$0]++' ;;
    record)
      [ -f "$BASE_DIR/$1" ] && blob_of "$BASE_DIR/$1"
      return 0 ;;
    *) return 0 ;;
  esac
}

cat_base() { # <blob> <seed-relative path> <dest>
  case "$HIST_KIND" in
    git)    git -C "$REPO_ROOT" cat-file blob "$1" > "$3" 2>/dev/null ;;
    record) cat "$BASE_DIR/$2" > "$3" 2>/dev/null ;;
    *) return 1 ;;
  esac
}

# Changed-line count between two files. awk rather than `grep -c`, because grep exits 1
# on zero matches and `set -o pipefail` would turn "identical" into a script failure.
diffcount() { # <a> <b>
  diff "$1" "$2" > "$TMPD/dc" 2>/dev/null || true
  awk '/^[<>]/{n++} END{print n+0}' "$TMPD/dc"
}

# Write the merged content, keeping the target's mode, via a rename inside the target's
# own directory: `mktemp` in $TMPDIR is mode 0600 and possibly on another filesystem, so
# moving from there would silently re-permission the file and make the write non-atomic.
# (Same reasoning as migrate-bundle.sh's temp_beside.)
write_beside() { # <merged> <target-file>
  local src="$1" f="$2" d t m
  d="$(dirname "$f")"
  t="$(mktemp "$d/.upgrade.XXXXXX" 2>/dev/null)" || return 1
  m="$(stat -f '%Lp' "$f" 2>/dev/null || stat -c '%a' "$f" 2>/dev/null || echo 644)"
  chmod "$m" "$t" 2>/dev/null || true
  cat "$src" > "$t" && mv "$t" "$f"
}

report() { printf '  %-9s %s\n' "$1" "$2"; }
detail() { printf '            %s\n' "$1"; }

# `bridge.code-workspace` is seeded under a group-specific NAME with this instance's
# absolute path stamped into it (see install.sh), so its instance copy can never match a
# seed blob and a "port" would rewrite a machine-local path. `.gitkeep` files are empty
# placeholders install.sh already skips once a directory has real content. Neither is
# seed drift; both are excluded rather than reported as permanent conflicts.
seed_paths() {
  ( cd "$SEED_SRC" && find . -type f | sed 's#^\./##' | sort ) \
    | grep -v '^bridge\.code-workspace$' | grep -v '\.gitkeep$'
}

insync=0; portable=0; ported=0; conflict=0; unknown=0
while IFS= read -r rel; do
  [ -n "$rel" ] || continue
  seed_f="$SEED_SRC/$rel"; inst_f="$TARGET/$rel"

  # THE CONFIG FILES ARE NEVER MERGED, AND THAT IS A SHIP-BLOCKER, NOT AN OMISSION.
  # `instance.config.json` is the one seed file whose entire purpose is to diverge — it
  # carries the group's org, its reposRoot, its roster and its spend — and a value in it is
  # routinely a decision somebody made minutes ago. `/ai-bridge:welcome` already refuses to
  # repair an uncommitted config for exactly that reason (its `config-uncommitted` row is
  # `ambiguous` and has no fixer at all), so a merge here would be the same write arriving
  # by another door. It is REPORTED, with the diff to run, and never touched.
  case "$rel" in
    instance.config.json|instance.config.local.json)
      if [ -e "$inst_f" ] && ! cmp -s "$seed_f" "$inst_f"; then
        report "CONFIG" "$rel"
        detail "config is yours to own, so it is never merged. Compare by hand:"
        detail "  diff -u '$inst_f' '$seed_f'"
      fi
      continue ;;
  esac

  if [ ! -e "$inst_f" ]; then
    report "absent" "$rel"
    detail "the stamp did not place it (a populated directory needs no placeholder)."
    continue
  fi
  # `-e` is true for a directory, a symlink to one, a fifo. Everything below assumes a
  # regular file: `git hash-object` and `cp` both fail on a directory, and since the hash
  # is taken in an assignment's command substitution, `set -e` would abort the WHOLE
  # upgrade there — losing the report for every remaining file instead of flagging this
  # one. A seeded path replaced by a directory is a real instance shape (someone made
  # `log.md/` a folder), so classify it and keep going.
  if [ ! -f "$inst_f" ] || [ -L "$inst_f" ]; then
    unknown=$((unknown+1))
    report "UNKNOWN" "$rel"
    detail "instance path is not a regular file — left untouched; compare it with $seed_f by hand."
    continue
  fi
  if cmp -s "$seed_f" "$inst_f"; then
    insync=$((insync+1)); continue   # identical to the current seed: quiet by design
  fi

  # Candidate merge bases: the seed file's PRIOR versions — every historical blob except
  # the content the seed has right now.
  #
  # Excluding the current content is load-bearing, not tidiness. The latest commit's blob
  # is in the history too, and for a file the instance has grown past (`log.md`, a
  # `.gitignore` with the machinery block appended) it is often the *closest* blob to what
  # the instance holds. Chosen as the base, the base→seed diff is empty, the merge is a
  # no-op, and real drift is silently reported as "nothing to port". The fixture caught
  # exactly that: a hand-diverged CLAUDE.md read as in sync.
  inst_hash="$(blob_of "$inst_f")"
  seed_hash="$(blob_of "$seed_f")"
  # The heredoc feeds this loop in the CURRENT shell (no pipe), so `any_history` survives
  # it — the difference between "the seed never changed" and "there is no history at all".
  : > "$TMPD/prior"
  any_history=0
  while IFS= read -r b; do
    [ -n "$b" ] || continue
    any_history=1
    [ "$b" = "$seed_hash" ] || printf '%s\n' "$b" >> "$TMPD/prior"
  done <<EOF
$(hist_blobs "$rel")
EOF

  if [ ! -s "$TMPD/prior" ]; then
    if [ "$any_history" -eq 1 ] && [ "$HIST_SHALLOW" -eq 0 ]; then
      # The seed file has only ever held its current content, so there is no seed change
      # to deliver: the difference is entirely the instance's own. Quiet on purpose — this
      # is the normal state of `log.md`, `index.md` and a managed `.gitignore`, and naming
      # them every run is how a report teaches people to stop reading it.
      # THAT INFERENCE IS ONLY AS GOOD AS `hist_blobs`. Read a partial history — the walk
      # stopping at a rename, as it did after #125, or a shallow clone's graft point — and
      # "the seed never changed" is false while looking identical here, which is why this
      # is the quietest branch in the script and the one a truncated history breaks first.
      # Hence the `$HIST_SHALLOW` guard: an un-deepened clone may prove a match, never an
      # absence, so it falls through to UNKNOWN instead of to silence.
      insync=$((insync+1)); continue
    fi
    unknown=$((unknown+1))
    report "UNKNOWN" "$rel"
    if [ "$any_history" -eq 1 ]; then
      detail "differs from the seed, and the only history available is a SHALLOW clone —"
      detail "which cannot show that the seed never changed. Deepen it and re-run:"
      detail "  git -C '$REPO_ROOT' fetch --unshallow"
    else
      detail "differs from the seed, and no merge base is reachable for it. Fix: give the"
      detail "refresh a history source — the marketplace clone, or a re-stamp that records"
      detail "the stamped seed (both spelled out under \"what's left for you\" below)."
    fi
    detail "Compare by hand:"
    detail "  diff '$inst_f' '$seed_f'"
    continue
  fi

  # The prior version the instance copy IS, if any — that is provable provenance, so it
  # wins. Otherwise the closest prior version by diff size, as a best effort.
  base_blob=""; base_kind=""
  while IFS= read -r b; do
    if [ "$b" = "$inst_hash" ]; then base_blob="$b"; base_kind="verbatim"; break; fi
  done < "$TMPD/prior"

  if [ "$base_kind" != "verbatim" ]; then
    best=""; bestn=""
    while IFS= read -r b; do
      cat_base "$b" "$rel" "$TMPD/cand" || continue
      n="$(diffcount "$TMPD/cand" "$inst_f")"
      if [ -z "$bestn" ] || [ "$n" -lt "$bestn" ]; then bestn="$n"; best="$b"; fi
    done < "$TMPD/prior"
    [ -z "$best" ] || { base_blob="$best"; base_kind="closest"; }
  fi

  if [ -z "$base_blob" ]; then
    unknown=$((unknown+1))
    report "UNKNOWN" "$rel"
    detail "differs from the seed, and no prior seed version could be read — so there is"
    detail "no merge base and no evidence. Compare by hand:"
    detail "  diff '$inst_f' '$seed_f'"
    continue
  fi

  cat_base "$base_blob" "$rel" "$TMPD/base"
  cp "$inst_f" "$TMPD/ours"
  merge_rc=0
  git merge-file -q -p \
    -L "$rel (this instance)" -L "seed @ ${base_blob}" -L "seed (new)" \
    "$TMPD/ours" "$TMPD/base" "$seed_f" > "$TMPD/merged" 2>/dev/null || merge_rc=$?

  short="$(printf '%s' "$base_blob" | cut -c1-8)"
  if [ "$merge_rc" -ge 255 ]; then
    unknown=$((unknown+1))
    report "UNKNOWN" "$rel"
    detail "git merge-file could not merge it (exit $merge_rc). Compare by hand:"
    detail "  diff '$inst_f' '$seed_f'"
    continue
  fi

  if [ "$merge_rc" -gt 0 ]; then
    conflict=$((conflict+1))
    report "CONFLICT" "$rel"
    detail "hand-diverged from the seed ($merge_rc conflicting hunk(s)) — NOT touched."
    detail "the seed change to port, relative to base $short:"
    # The ---/+++ header names temp paths, which tells the reader nothing; the hunks are
    # the message. Header lines are dropped rather than relabelled.
    diff -u "$TMPD/base" "$seed_f" > "$TMPD/sd" 2>/dev/null || true
    awk -v cap="$DIFF_CAP" '
      NR<=2 && /^(---|\+\+\+) / { next }
      { n++; if (n<=cap) print "              " $0 }
      END { if (n>cap) printf "              … %d more diff line(s)\n", n-cap }
    ' "$TMPD/sd"
    detail "port it by hand, then re-run. Full diff of what you have vs the seed:"
    detail "  diff -u '$inst_f' '$seed_f'"
    # UNDER --apply, THE CONFLICTED MERGE IS SAVED BESIDE THE FILE — never over it.
    # The live file stays exactly as the human left it (that is the never-clobber
    # guarantee), and the markers they would otherwise have to reproduce by hand are
    # there to read. Written only under --apply, because a report-only run writes
    # nothing at all, and named with the same `.bak.<epoch>` convention every other
    # backup in this machinery uses.
    # IDEMPOTENT: written once, not once per run. A conflict is not repaired by running
    # this again, so a second --apply would otherwise drop a second identical backup
    # beside the first, and a tenth a tenth — which is how a directory of `.bak.<epoch>`
    # files nobody can tell apart gets built.
    if [ "$APPLY" -eq 1 ]; then
      have_bak=0
      for cb in "$inst_f".bak.*; do
        [ -f "$cb" ] || continue
        if cmp -s "$TMPD/merged" "$cb"; then have_bak=1; break; fi
      done
      if [ "$have_bak" -eq 1 ]; then
        detail "the conflicted merge is already saved beside it (an earlier run wrote it)"
      else
        cbak="$inst_f.bak.$(date +%s)"
        if cp "$TMPD/merged" "$cbak" 2>/dev/null; then
          detail "the conflicted merge (with markers) is saved as $(basename "$cbak")"
        fi
      fi
    fi
    printf '%s\n' "$rel" >> "$TMPD/conflicts"
    continue
  fi

  if cmp -s "$TMPD/merged" "$inst_f"; then
    insync=$((insync+1)); continue   # the seed has no change this instance lacks
  fi

  if [ "$APPLY" -eq 0 ]; then
    portable=$((portable+1))
    report "PORTABLE" "$rel"
    if [ "$base_kind" = "verbatim" ]; then
      detail "the instance copy is the seed verbatim as of $short — porting is exact."
    else
      detail "the seed change merges cleanly onto this instance's edits (base $short)."
    fi
    continue
  fi

  # --apply: write the MERGE RESULT, never a copy of the seed, then read it back.
  # A hand-edited file is backed up first; a verbatim old seed is not, because its
  # content is recoverable from this template's git history and the backup would be
  # clutter a later run has to explain.
  bak=""
  if [ "$base_kind" != "verbatim" ]; then
    bak="$inst_f.bak.$(date +%s)"
    cp "$inst_f" "$bak"
  fi
  if write_beside "$TMPD/merged" "$inst_f" \
     && cmp -s "$TMPD/merged" "$inst_f" \
     && ! grep -qE '^(<<<<<<< |>>>>>>> )' "$inst_f"; then
    ported=$((ported+1))
    # The bundle's stamped-seed record, if it has one, now has a stale base: the copy on
    # disk is the merge result, and the version it should next be judged against is the
    # seed we just merged in. Updated, never CREATED — `init-bundle.sh` owns writing the
    # record, so a bundle without one keeps a predictable --apply footprint.
    if [ -f "$BASE_DIR/$rel" ]; then cp "$seed_f" "$BASE_DIR/$rel" 2>/dev/null || true; fi
    report "PORTED" "$rel"
    if [ "$base_kind" = "verbatim" ]; then
      detail "was the seed verbatim as of $short; now the current seed (verified)."
    else
      detail "seed change merged onto this instance's edits (base $short, verified)."
      detail "backup: $(basename "$bak")"
    fi
  else
    failed=$((failed+1))
    report "FAILED" "$rel" >&2
    printf '            %s\n' "the port did not land — the file was left as it was." >&2
    [ -z "$bak" ] || printf '            %s\n' "backup: $bak" >&2
  fi
done <<EOF
$(seed_paths)
EOF

printf '  summary: %d in sync or with nothing to port, %d portable, %d ported, %d conflicting, %d unknown.\n' \
  "$insync" "$portable" "$ported" "$conflict" "$unknown"
[ "$APPLY" -eq 1 ] || [ "$portable" -eq 0 ] || echo "  (report only — nothing was written)"

# ------------------------------------------------------------ what's left for you
#
# Assembled here rather than as the section runs, so the list reads in the order a
# human would act: re-run with --apply first, then the decisions only they can make,
# then the commit.
if [ "$APPLY" -eq 0 ] && [ "$portable" -gt 0 ]; then
  left "re-run with --apply to write the $portable mergeable seed file(s):"
  left_more "$SELF '$TARGET' --apply"
fi
if [ -s "$TMPD/conflicts" ]; then
  while IFS= read -r c; do
    [ -n "$c" ] || continue
    left "port the seed change into $c by hand — it is hand-diverged, so nothing was"
    left_more "written. What you have vs the seed:"
    left_more "diff -u '$TARGET/$c' '$SEED_SRC/$c'"
  done < "$TMPD/conflicts"
fi
if [ "$unknown" -gt 0 ]; then
  left "$unknown seed file(s) differ with no merge base to judge them by — compare by"
  left_more "hand using the commands printed under UNKNOWN above."
fi
# NAME THE FIX, NOT JUST THE SYMPTOM. "no git history" is a true sentence a reader can do
# nothing with; both of these are one command each.
if [ "$HIST_KIND" != git ] && [ "$unknown" -gt 0 ]; then
  left "give the refresh a history source — either one is enough:"
  left_more "· the marketplace clone this plugin came from (a git checkout of the same"
  left_more "  content). ${MKT_WHY:-not derivable from this install path}."
  [ -z "$MKT_DIR" ] || left_more "  claude plugin marketplace add <the marketplace> re-creates it at $MKT_DIR"
  left_more "· or record the base in the bundle itself, so no clone is needed at all:"
  left_more "  /ai-bridge:init '$TARGET'  — a stamp writes .ai-bridge/seed-base/ for every"
  left_more "  seed file IT copies, which is the merge base by construction."
fi
if [ "$HIST_SHALLOW" -eq 1 ]; then
  left "deepen the marketplace clone — its history is truncated, so this run could not"
  left_more "tell an unchanged seed from an unreachable one:"
  left_more "git -C '$REPO_ROOT' fetch --unshallow"
fi
if [ "$ported" -gt 0 ]; then
  left "review and commit what changed — the bundle is its own git repo:"
  left_more "cd '$TARGET' && git status && git diff"
fi

echo
echo "== what's left for you ==============================================="
if [ "$LEFT_N" -eq 0 ]; then
  echo "  Nothing. This bundle is up to date with the template seed."
else
  cat "$TMPD/left"
fi

[ "$failed" -eq 0 ] || {
  echo
  echo "refresh-seeds: $failed claimed change(s) did not land — see the FAILED lines above." >&2
  exit 1
}
exit 0
