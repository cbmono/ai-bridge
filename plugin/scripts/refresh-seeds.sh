#!/usr/bin/env bash
#
# refresh-seeds.sh — port this repo's SEED changes into an already-stamped bundle.
#
#   Usage: refresh-seeds.sh <bundle-dir>            # report what has drifted (default)
#          refresh-seeds.sh <bundle-dir> --apply    # 3-way merge the safe ones
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
#     file, a rename this script does not follow) ⇒ no merge base, no evidence, no action.
#     Reported for a human.
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

# The template root — two directories up from this script and then verified. See
# init-bundle.sh for why it is derived from the fixed plugin layout and not searched for.
BIN_DIR="$(cd "$(dirname "$0")" && pwd)"
SELF="$BIN_DIR/$(basename "$0")"
TEMPLATE_DIR="$(cd "$BIN_DIR/../.." 2>/dev/null && pwd || true)"
[ -n "$TEMPLATE_DIR" ] && [ -f "$TEMPLATE_DIR/VERSION" ] || {
  echo "refresh-seeds: cannot locate the ai-bridge template root from $BIN_DIR" >&2; exit 2; }
SEED_SRC="$TEMPLATE_DIR/seed"
DIFF_CAP="${UPGRADE_DIFF_LINES:-40}"   # lines of a conflicting diff to print inline

APPLY=0
TARGET=""
for arg in "$@"; do
  case "$arg" in
    --apply) APPLY=1 ;;
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

echo "ai-bridge seed refresh — $TARGET"
echo "template: $TEMPLATE_DIR"
if [ "$APPLY" -eq 1 ]; then
  echo "mode:     APPLY — the mergeable changes below WILL be written."
else
  echo "mode:     REPORT ONLY — nothing is written."
fi

# ---------------------------------------------------------------- seed drift
echo
echo "== seed drift (a seed edit never reaches a stamped bundle by itself) =="

# Every git query below runs from the REPO ROOT with root-relative paths. `git -C <dir>`
# makes a pathspec relative to <dir>, so querying from the template dir with the path
# git reports for it ("seed/…") silently matched nothing — and "no history"
# is indistinguishable from "no evidence", which downgraded every drifted file to
# UNKNOWN. Resolve the root once, and prefix paths with the template's own prefix.
GIT_OK=1
REPO_ROOT=""; PREFIX=""
if git -C "$TEMPLATE_DIR" rev-parse --show-toplevel >/dev/null 2>&1; then
  REPO_ROOT="$(git -C "$TEMPLATE_DIR" rev-parse --show-toplevel)"
  PREFIX="$(git -C "$TEMPLATE_DIR" rev-parse --show-prefix)"
else
  GIT_OK=0
fi
[ "$GIT_OK" -eq 1 ] || echo "  note: the template is not a git checkout, so no merge base can be"
[ "$GIT_OK" -eq 1 ] || echo "        established — differing files can only be reported, never ported."

# Every historical blob of a seed path, newest first, deduplicated. Renames are NOT
# followed: a renamed seed file simply has less history, which degrades to "no base"
# (reported) rather than to a wrong base (ported).
hist_blobs() { # <repo-relative path>
  [ "$GIT_OK" -eq 1 ] || return 0
  git -C "$REPO_ROOT" log --format=%H -- "$1" 2>/dev/null | while IFS= read -r c; do
    git -C "$REPO_ROOT" ls-tree "$c" -- "$1" 2>/dev/null | awk '{print $3}'
  done | awk 'NF && !seen[$0]++'
}

blob_of() { git -C "$TEMPLATE_DIR" hash-object --no-filters -- "$1"; }

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
$(hist_blobs "${PREFIX}seed/$rel")
EOF

  if [ ! -s "$TMPD/prior" ]; then
    if [ "$any_history" -eq 1 ]; then
      # The seed file has only ever held its current content, so there is no seed change
      # to deliver: the difference is entirely the instance's own. Quiet on purpose — this
      # is the normal state of `log.md`, `index.md` and a managed `.gitignore`, and naming
      # them every run is how a report teaches people to stop reading it.
      insync=$((insync+1)); continue
    fi
    unknown=$((unknown+1))
    report "UNKNOWN" "$rel"
    detail "differs from the seed, and this template has no git history for it — so"
    detail "there is no merge base and no evidence. Compare by hand:"
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
      git -C "$REPO_ROOT" cat-file blob "$b" > "$TMPD/cand" 2>/dev/null || continue
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

  git -C "$REPO_ROOT" cat-file blob "$base_blob" > "$TMPD/base"
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
    if [ "$APPLY" -eq 1 ]; then
      cbak="$inst_f.bak.$(date +%s)"
      if cp "$TMPD/merged" "$cbak" 2>/dev/null; then
        detail "the conflicted merge (with markers) is saved as $(basename "$cbak")"
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
