#!/usr/bin/env bash
#
# close-project-folder.sh — the folder half of closeout: REMOVE a finished project's
# folder, or, when the project is RETAINED, freeze it and KEEP it.
#
#   Usage: close-project-folder.sh <slug>            # report only
#          close-project-folder.sh <slug> --apply    # do it
#
# WHY THIS IS A SCRIPT AND NOT A PARAGRAPH IN /close-project. Every other closeout step
# is prose an agent executes, and that is fine for editing a log entry. This step
# DELETES FILES, and the difference matters twice over: a deletion improvised from prose
# has no fixed scope (`find … -name '*.png' -delete` one line off is the whole bundle),
# and prose cannot be tested. Here the scope is four explicit paths, the refusals are
# executable, and tests/close-project-folder.test.sh drives the real thing.
#
# THE TWO OUTCOMES.
#
#   retain absent/false  ⇒  `git rm -r` the folder. Unchanged behaviour: git history and
#                           the KB are the record, and there is no `archive/`.
#   retain: true         ⇒  the folder STAYS. It is frozen first:
#                             · `deliverable_paths:` is stamped into project.md, and
#                             · working files are pruned (below).
#
# WHY RETENTION IS SAFE NOW. Removal never was about disk — it was about the /pm-loop
# tick paying context for finished work on every run. write-snapshot.sh (and the PM's own
# project loop) now skip a `status: done` project at its frontmatter, before `tasks/` is
# ever opened, so a retained project costs one frontmatter parse. That is what buys the
# folder its place; see SCHEMA.md, "Project & objective completion".
#
# WHAT THE PRUNE TOUCHES — FOUR EXPLICIT PATHS, NEVER AN EXTENSION SWEEP:
#
#   · `<project>/**/tmp/` and `<project>/**/temp/`  (directory name, case-insensitive)
#   · `<project>/**/.DS_Store`
#   · NON-MARKDOWN files under `<project>/sources/`  (`sources/**/*.md` are KEPT)
#   · nothing else. Ever.
#
# and what it must never touch:
#
#   · `deliverables/` — it legitimately holds .pdf/.html/.png, which is precisely what an
#     extension rule would eat. The whole subtree is pruned OUT of the walk, so not even
#     a `.DS_Store` inside it is removed. One stray 6 KB file is a much better outcome
#     than a rule with an exception in it.
#   · `tasks/`, `log.md`, `index.md`, `project.md` — kept in full. `index.md` links every
#     task AND arrows to its deliverable; delete `tasks/` and half of it dangles, and it
#     is the file that makes a retained project findable.
#   · anything named in `deliverable_paths:`. The stamp is computed BEFORE the prune and
#     used as a keep-set, so a task that declared an artifact somewhere unusual cannot
#     have it deleted by the sources rule two steps later.
#
# WHY `sources/` KEEPS ONLY MARKDOWN. Measured on two real research projects: 23 .jpg vs
# 16 .md, `sources/` 2.0M/3.6M against 104K/40K for `tasks/`. The markdown extracts are
# what `index.md` cites by number ("evidence captured in sources/ 02/03/05"), so they
# stay and the citations keep resolving; the screenshots they were extracted FROM do not.
#
# WHY tmp/ IS REPORTED BY DIRECTORY AND NEVER BY FILENAME. On the project this rule came
# from, `tmp/` held roster and seat exports — employee records. This bundle carries strict
# no-PII rules, and a filename is content: printing `tmp/roster-<person>.csv` puts it in a
# terminal, a transcript, and possibly a log entry. So tmp/ and temp/ are reported as a
# path and an entry COUNT. Their contents are never read, printed, or logged — only
# removed. Files under `sources/` are named, because they are the project's own cited
# evidence and the report has to be checkable.
#
# GIT, AND WHY THE TWO PATHS DIFFER. Removal uses `git rm -r` so the deletion is staged
# and the record survives in history — that is the whole reason removal is acceptable.
# The prune uses a plain `rm`, because the retained folder is being COMMITTED, not
# deleted: /close-project stages the whole project path afterwards, and the pruned
# deletions ride along with the `status: done` roll-up in one commit.
#
# Deterministic, no network, no `jq`, no `python3` — bash + awk, like every other script
# under `scripts/`, so it ships into every instance unchanged.
#
# Verified by tests/close-project-folder.test.sh.
set -euo pipefail

APPLY=0
SLUG=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply) APPLY=1 ;;
    -h|--help) sed -n '2,/^set -euo/p' "$0" | sed 's/^# \{0,1\}//; $d'; exit 0 ;;
    -*) echo "usage: $0 <slug> [--apply]" >&2; exit 2 ;;
    *) [[ -z "$SLUG" ]] || { echo "usage: $0 <slug> [--apply]" >&2; exit 2; }; SLUG="$1" ;;
  esac
  shift
done

[[ -f SCHEMA.md && -f instance.config.json ]] || {
  echo "close-project-folder: run from a control-panel instance root (SCHEMA.md + instance.config.json)." >&2
  exit 2
}
[[ -n "$SLUG" ]] || { echo "usage: $0 <slug> [--apply]" >&2; exit 2; }

# The slug becomes an argument to `rm -rf` and `git rm -r`, so it is validated as a
# single directory NAME rather than trusted as a path: no separators, no `..`, no
# leading dash. A closeout run from a stale note is the realistic way a wrong string
# gets here, and this is the one refusal that has to hold unconditionally.
case "$SLUG" in
  *[!A-Za-z0-9._-]*|.|..|-*|"")
    echo "close-project-folder: '$SLUG' is not a project slug (a single directory name: letters, digits, . _ -)." >&2
    exit 2 ;;
esac

PROJ="projects/$SLUG"
[[ -f "$PROJ/project.md" ]] || {
  echo "close-project-folder: no $PROJ/project.md — nothing to close." >&2
  exit 2
}

# ---------------------------------------------------------------- frontmatter
# Same contract as validate-bundle.sh and write-snapshot.sh: read only the block
# between the first two `---` lines, and never guess at a malformed document.
field() { # <file> <key>
  awk -v key="$2" '
    NR==1 && $0!="---" { exit }
    /^---$/ { n++; if (n==2) exit; next }
    n==1 && $0 ~ "^" key ":" { sub("^" key ":[[:space:]]*", ""); sub(/[[:space:]]*#.*/, ""); print; exit }
  ' "$1" | sed -e 's/[[:space:]]*$//' -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'\$//"
}

# The path references in a list field, in BOTH YAML forms (inline `k: [ a, b ]` and a
# block sequence of `- ` lines) — the shape validate-bundle.sh's refs_for uses, for the
# same reason: no instance writes block style today and nothing forbids it. The regex
# carries no `[.]md` anchor, because a deliverable is legitimately a .pdf/.html/.pptx.
refs_for() { # <file> <key>
  awk -v key="$2" '
    NR==1 && $0!="---" { exit }
    /^---$/ { n++; if (n==2) exit; next }
    n==1 && $0 ~ "^" key ":" { inblock=1; rest=$0; sub(/^[^:]*:/, "", rest); print rest; next }
    n==1 && inblock && /^[[:space:]]+-[[:space:]]*/ { print; next }
    n==1 && inblock && /^[[:space:]]*$/ { next }
    n==1 && /^[^[:space:]]/ { inblock=0 }
  ' "$1" | grep -oE '/projects/[A-Za-z0-9._/-]+' || true
}

# A temp file BESIDE the target, carrying the target's mode — migrate-bundle.sh's
# reasoning, unchanged: `mktemp` creates 0600 and renaming that over a document would
# silently re-mode it, and a cross-filesystem `mv` degrades to copy-and-remove, where an
# interruption leaves half a document.
temp_beside() { # <file>
  local f="$1" d t m
  d="$(dirname "$f")"
  t="$(mktemp "$d/.close-project-folder.XXXXXX" 2>/dev/null)" || return 1
  m="$(stat -f '%Lp' "$f" 2>/dev/null || stat -c '%a' "$f" 2>/dev/null || echo 644)"
  chmod "$m" "$t" 2>/dev/null || true
  printf '%s\n' "$t"
}

# Replace (or insert) a frontmatter LIST field, dropping any block-sequence lines the
# old value carried. Only inside the frontmatter, and only the first occurrence — a
# `deliverable_paths:` in the body is prose about the key, not the key.
set_list_field() { # <file> <key> <inline-value>
  local f="$1" k="$2" v="$3" tmp
  tmp="$(temp_beside "$f")" || return 1
  awk -v key="$k" -v val="$v" '
    BEGIN { n=0; written=0; drop=0 }
    /^---$/ {
      n++
      if (n==2 && !written) { print key ": " val; written=1 }
      drop=0; print; next
    }
    n==1 && drop && /^[[:space:]]+-[[:space:]]*/ { next }
    n==1 && drop && /^[[:space:]]*$/ { next }
    n==1 && !written && $0 ~ "^" key ":" { print key ": " val; written=1; drop=1; next }
    n==1 && /^[^[:space:]]/ { drop=0 }
    { print }
  ' "$f" > "$tmp" && mv "$tmp" "$f"
}

# ---------------------------------------------------------------- report helpers
stamped=0; missing=0; pruned_files=0; pruned_dirs=0
LOG_BITS=""
note()  { printf '  %-6s %s\n' "$1" "$2"; }
logbit() { LOG_BITS="$LOG_BITS${LOG_BITS:+, }$1"; }

RETAIN="$(field "$PROJ/project.md" retain | tr '[:upper:]' '[:lower:]')"

# ---------------------------------------------------------------- removal (no retain)
if [[ "$RETAIN" != "true" ]]; then
  echo "close-project-folder: $SLUG — not retained (no \`retain: true\` on project.md)."
  note "REMOVE" "$PROJ/ (git rm -r)"
  if [[ $APPLY -eq 1 ]]; then
    git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
      echo "close-project-folder: not inside a git work tree — refusing to delete $PROJ/ unversioned." >&2
      exit 2
    }
    # -f because closeout has just written `status: done` into a file that is about to
    # stop existing; that edit is deliberately discarded with the folder. Untracked
    # files are a different matter: `git rm` leaves them, and this script does NOT
    # delete them behind a human's back — it reports that they are there.
    git rm -r -q -f -- "$PROJ"
    if [[ -e "$PROJ" ]]; then
      left="$(find "$PROJ" -type f 2>/dev/null | grep -c . || true)"
      note "LEFT" "$PROJ/ still holds $left untracked file(s) — inspect and remove by hand."
    fi
    echo "---"
    echo "close-project-folder: $SLUG removed (staged). Commit it with the roll-up edits."
  else
    echo "---"
    echo "close-project-folder: report only — nothing changed. Re-run with --apply."
  fi
  exit 0
fi

# ---------------------------------------------------------------- retained
echo "close-project-folder: $SLUG — RETAINED (retain: true). The folder stays."

# ---- 1. stamp deliverable_paths, from each task's `artifacts:`, verified on disk.
#
# Resolved ONCE, here, rather than at render time: the board must be able to list a
# retained project's deliverables without walking `tasks/`, which is exactly what the
# done-project skip removed. Verification happens now, while a human is watching.
KEEP=""
STAMP=""
while IFS= read -r ref; do
  [[ -n "$ref" ]] || continue
  case "$STAMP" in *"[$ref]"*) continue ;; esac   # first-seen order, no duplicates
  if [[ -e ".$ref" ]]; then
    STAMP="$STAMP[$ref]"
    # Stored in `find`'s output form (no leading `./`), because that is what the prune
    # loops below compare against. A keep-set spelled differently from the candidates
    # it protects protects nothing, and does so silently.
    KEEP="$KEEP${KEEP:+$'\n'}${ref#/}"
    stamped=$((stamped+1))
  else
    # Same call validate-bundle.sh makes for `artifacts:`: a declared deliverable that
    # was never written is a WARNING, not a refusal. It is left out of the stamp — a
    # stamped path that resolves to nothing would put a dead button on the board.
    note "WARN" "declared artifact does not exist, not stamped: $ref"
    missing=$((missing+1))
  fi
done <<EOF
$(find "$PROJ/tasks" -maxdepth 1 -name '*.md' 2>/dev/null | grep -vE '/(index|log)\.md$' | sort \
  | while IFS= read -r t; do [[ -n "$t" ]] && refs_for "$t" artifacts; done)
EOF

# `[ /a, /b ]` — inline flow, the form `artifacts:` and `pr:` already use, and one line
# so a reader of project.md sees the whole set at once. Bundle-relative, always: an
# absolute path would leak the publisher's directory layout onto a published board.
LIST="$(printf '%s' "$STAMP" | sed -e 's/\]\[/, /g' -e 's/^\[//' -e 's/\]$//')"
if [[ -n "$LIST" ]]; then VALUE="[ $LIST ]"; else VALUE="[ ]"; fi
note "STAMP" "deliverable_paths: $stamped path(s) verified on disk${missing:+, $missing missing}"
if [[ $APPLY -eq 1 ]]; then
  set_list_field "$PROJ/project.md" deliverable_paths "$VALUE" || {
    echo "close-project-folder: could not write deliverable_paths into $PROJ/project.md." >&2
    exit 1
  }
  grep -q '^deliverable_paths:' "$PROJ/project.md" || {
    echo "close-project-folder: FAILED — deliverable_paths is not in $PROJ/project.md after the write." >&2
    exit 1
  }
fi

# ---- 2. prune. Every candidate is produced by an explicit expression below; nothing
# else in the folder is even enumerated.
protected() { # <path> — is this a declared deliverable?
  [[ -n "$KEEP" ]] && printf '%s\n' "$KEEP" | grep -qxF -- "$1"
}

# tmp/ and temp/, any depth, case-insensitive, `deliverables/` pruned out of the walk.
while IFS= read -r d; do
  [[ -n "$d" ]] || continue
  # Belt and braces on a path that is about to be an argument to `rm -rf`: it must be
  # inside this project. The slug is already validated; this catches a `find`
  # expression edited into something wider by a later hand.
  case "$d" in "$PROJ"/*) ;; *) continue ;; esac
  n="$(find "$d" -mindepth 1 2>/dev/null | grep -c . || true)"
  # The path and the COUNT. Never a filename from inside — see the header.
  if [[ "$n" == 1 ]]; then unit="entry"; else unit="entries"; fi
  note "PRUNE" "$d/ ($n $unit, contents not listed)"
  if [[ $APPLY -eq 1 ]]; then rm -rf -- "$d"; fi
  pruned_dirs=$((pruned_dirs+1))
  logbit "$d/"
done <<EOF
$(find "$PROJ" -path "$PROJ/deliverables" -prune -o -type d \( -iname 'tmp' -o -iname 'temp' \) -print 2>/dev/null | sort || true)
EOF

# Non-markdown evidence under sources/. The .md extracts stay: index.md cites them.
src_pruned=0
while IFS= read -r f; do
  [[ -n "$f" ]] || continue
  case "$f" in "$PROJ"/sources/*) ;; *) continue ;; esac
  if protected "$f"; then note "KEEP" "$f (declared deliverable)"; continue; fi
  note "PRUNE" "$f"
  if [[ $APPLY -eq 1 ]]; then rm -f -- "$f"; fi
  src_pruned=$((src_pruned+1)); pruned_files=$((pruned_files+1))
done <<EOF
$(find "$PROJ/sources" -type f ! -iname '*.md' -print 2>/dev/null | sort || true)
EOF
if [[ $src_pruned -gt 0 ]]; then logbit "$src_pruned non-markdown file(s) from $PROJ/sources/"; fi

# .DS_Store, any depth, `deliverables/` pruned out of the walk.
ds=0
while IFS= read -r f; do
  [[ -n "$f" ]] || continue
  case "$f" in "$PROJ"/*) ;; *) continue ;; esac
  if protected "$f"; then continue; fi
  if [[ $APPLY -eq 1 ]]; then rm -f -- "$f"; fi
  ds=$((ds+1)); pruned_files=$((pruned_files+1))
done <<EOF
$(find "$PROJ" -path "$PROJ/deliverables" -prune -o -type f -name '.DS_Store' -print 2>/dev/null | sort || true)
EOF
if [[ $ds -gt 0 ]]; then note "PRUNE" "$ds .DS_Store file(s)"; logbit "$ds .DS_Store"; fi

note "KEEP" "tasks/  deliverables/  sources/**/*.md  index.md  log.md  project.md"

echo "---"
# The line the closeout entry in log.md is built from. A retained folder is DELIBERATELY
# partial, and a reader six months from now has no way to tell that from damage unless
# the log says which directories went.
if [[ -n "$LOG_BITS" ]]; then
  echo "log.md fragment — pruned $LOG_BITS; kept tasks/, deliverables/, sources/*.md, index.md, log.md."
else
  echo "log.md fragment — nothing to prune; the folder is retained in full."
fi
if [[ $APPLY -eq 1 ]]; then
  printf 'close-project-folder: %s retained — %d deliverable path(s) stamped, %d directory/ies and %d file(s) pruned.\n' \
    "$SLUG" "$stamped" "$pruned_dirs" "$pruned_files"
  echo "Now stage the folder: git add -A -- $PROJ"
else
  printf 'close-project-folder: report only — nothing changed. %d path(s) would be stamped, %d directory/ies and %d file(s) would be pruned.\n' \
    "$stamped" "$pruned_dirs" "$pruned_files"
  echo "Re-run with --apply."
fi
exit 0
