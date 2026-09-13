#!/usr/bin/env bash
# kb-sync.sh — mount, read and write a knowledge base held in another repository.
#
#   kb-sync.sh [--instance DIR] mount | pull | status
#   kb-sync.sh [--instance DIR] commit --message <m> [--role <r>] -- <path>...
#
# `commit` is ONE bounded transaction and the only writer: rebase, regenerate the
# index, commit, push, one retry, then stop and report. Every network call carries
# the bound named by --timeout, so no command here can hang a tick or a session.
# Exit: 0 done · 1 refused or failed (reported) · 2 usage · 3 no `knowledge` key.
# Reasoning, and why the mount is a nested clone: ai-bridge-v3/task-021.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)"
inst="."; cmd=""; message=""; role=""; paths=(); TIMEOUT="${AI_BRIDGE_KB_TIMEOUT:-20}"
need2() { [ "$1" -ge 2 ] || { echo "kb-sync: $2 needs a value" >&2; exit 2; }; }
seen_dashdash=0
while [ $# -gt 0 ]; do
  if [ "$seen_dashdash" -eq 1 ]; then paths+=("$1"); shift; continue; fi
  case "$1" in
    --instance) need2 $# "$1"; inst="$2"; shift 2 ;;
    --message)  need2 $# "$1"; message="$2"; shift 2 ;;
    --role)     need2 $# "$1"; role="$2"; shift 2 ;;
    --timeout)  need2 $# "$1"; TIMEOUT="$2"; shift 2 ;;
    --)         seen_dashdash=1; shift ;;
    -h|--help)  sed -n '2,10p' "$0" >&2; exit 2 ;;
    -*) echo "kb-sync: unknown flag $1" >&2; exit 2 ;;
    *)  [ -z "$cmd" ] || { echo "kb-sync: unexpected argument '$1'" >&2; exit 2; }
        cmd="$1"; shift ;;
  esac
done
case "$TIMEOUT" in ""|*[!0-9]*) echo "kb-sync: --timeout wants seconds" >&2; exit 2 ;; esac
[ -d "$inst" ] || { echo "kb-sync: no such instance directory: $inst" >&2; exit 2; }
INST="$(cd "$inst" && pwd)"

say()   { printf 'kb-sync: %s\n' "$1"; }
warn()  { printf 'kb-sync: %s\n' "$1" >&2; }
die()   { printf 'kb-sync: %s\n' "$1" >&2; exit "${2:-1}"; }

cfg() { bash "$HERE/resolve-config.sh" --instance "$INST" "$@" 2>/dev/null; }

# A bound that holds without coreutils `timeout`, which stock macOS does not ship:
# the watchdog is a SIBLING, so it still fires if this shell is killed first.
bounded() {
  if command -v timeout >/dev/null 2>&1; then timeout "$TIMEOUT" "$@"; return $?; fi
  "$@" & local child=$! rc=0
  ( sleep "$TIMEOUT"; kill "$child" 2>/dev/null ) >/dev/null 2>&1 &
  local dog=$!
  wait "$child"; rc=$?
  kill "$dog" 2>/dev/null
  return $rc
}

# `org/name` is the documented form; anything carrying a scheme or a slash-prefix is
# taken verbatim, which is what lets the harness point a mount at a local bare repo.
remote_url() {
  case "$1" in
    *://*|/*|./*|../*|*@*:*) printf '%s' "$1" ;;
    */*) printf 'https://github.com/%s.git' "$1" ;;
    *) printf '%s' "$1" ;;
  esac
}

KBGIT="$INST/.ai-bridge/kb.git"
SRCROOT="$INST/.ai-bridge/kb-src"

# The mount is a real directory, never a symlink, so `find knowledge -type f` behaves
# exactly as it does over a bundle's own folder. Git cannot re-root a checkout, so the
# repo-relative folder decides where it lands: `/` is cloned straight into knowledge/,
# and a named folder is checked out sparsely against the bundle root.
mount_layout() { # <path> -> "<worktree>\t<sparse>\t<prefix>"
  case "$1" in
    /|""|.) printf '%s\t\t' "$INST/knowledge" ;;
    knowledge|knowledge/|/knowledge|/knowledge/) printf '%s\tknowledge\tknowledge/' "$INST" ;;
    *) return 1 ;;
  esac
}

kb_read() { # <key> -> value or empty
  cfg knowledge "$1"
}

kb_configured() { [ -n "$(kb_read repo)" ]; }

kb_vars() {
  KB_REPO="$(kb_read repo)"
  KB_PATH="$(kb_read path)"; [ -n "$KB_PATH" ] || KB_PATH="/"
  KB_REF="$(kb_read ref)"; [ -n "$KB_REF" ] || KB_REF="main"
  KB_URL="$(remote_url "$KB_REPO")"
  local layout
  layout="$(mount_layout "$KB_PATH")" || die "knowledge.path is '$KB_PATH'. Only '/' (the repo
       root) and 'knowledge' (a top-level folder of that name) can be mounted at
       knowledge/ as a real directory — git cannot re-root a checkout, and a symlink
       mount regenerates an empty index. Move the folder or set path: /."
  KB_WT="${layout%%$'\t'*}"; layout="${layout#*$'\t'}"
  KB_SPARSE="${layout%%$'\t'*}"; KB_PREFIX="${layout#*$'\t'}"
  KB_MOUNT="$INST/knowledge"
}

# Always from the worktree: with `--git-dir` alone git resolves a pathspec against the
# current directory, which for this mount is usually somewhere else entirely.
kbg() { ( cd "$KB_WT" && git --git-dir="$KBGIT" "$@" ); }

# `ref` names a BRANCH. A tag or a SHA checks out a detached HEAD, and the write path
# below has nothing to push it to — so it is refused here, by name, not at push time.
check_ref() { # <url> <ref>
  local url="$1" ref="$2"
  if [ "${#ref}" -eq 40 ] && printf '%s' "$ref" | grep -qE '^[0-9a-fA-F]{40}$'; then
    die "knowledge.ref '$ref' is a commit SHA. A detached HEAD cannot be pushed — name a BRANCH."
  fi
  local heads tags
  heads="$(bounded git ls-remote --heads "$url" "$ref" 2>/dev/null)"
  [ -z "$heads" ] || return 0
  tags="$(bounded git ls-remote --tags "$url" "$ref" 2>/dev/null)"
  [ -z "$tags" ] || die "knowledge.ref '$ref' is a TAG. A detached HEAD cannot be pushed — name a BRANCH."
  return 0
}

clone_mount() { # <gitdir> <worktree> <url> <ref> <sparse>
  local gd="$1" wt="$2" url="$3" ref="$4" sparse="$5"
  mkdir -p "$(dirname "$gd")" "$wt" || return 1
  git init --bare --quiet "$gd" || return 1
  git --git-dir="$gd" config core.bare false || return 1
  git --git-dir="$gd" config core.worktree "$wt" || return 1
  git --git-dir="$gd" config core.logAllRefUpdates true || return 1
  git --git-dir="$gd" remote add origin "$url" || return 1
  if [ -n "$sparse" ]; then
    git --git-dir="$gd" config core.sparseCheckout true || return 1
    printf '/%s/\n' "$sparse" > "$gd/info/sparse-checkout" || return 1
  fi
  if ! bounded git --git-dir="$gd" fetch --quiet origin "$ref" 2>/dev/null; then
    git --git-dir="$gd" symbolic-ref HEAD "refs/heads/$ref"
    return 0
  fi
  ( cd "$wt" && git --git-dir="$gd" checkout --quiet -B "$ref" FETCH_HEAD )
}

# A leftover real knowledge/ is a bundle that has not been migrated. Cloning over it
# would bury ~200 tracked Findings under a half-copy, so the mount refuses instead.
refuse_stale_folder() {
  [ -d "$KB_MOUNT" ] || return 0
  [ -z "$(ls -A "$KB_MOUNT" 2>/dev/null)" ] && return 0
  die "knowledge/ is already a real folder of this bundle, with content in it.
       Move it into $KB_REPO first, in one recorded commit:
         $HERE/kb-migrate.sh --instance $inst
       then re-run 'kb-sync.sh mount'."
}

mount_writable() {
  kb_vars
  if [ -d "$KBGIT" ]; then return 0; fi
  refuse_stale_folder
  check_ref "$KB_URL" "$KB_REF"
  clone_mount "$KBGIT" "$KB_WT" "$KB_URL" "$KB_REF" "$KB_SPARSE" \
    || { rm -rf "$KBGIT"; die "could not mount $KB_REPO at knowledge/ — nothing was written."; }
  say "mounted $KB_REPO ($KB_PATH @ $KB_REF) at knowledge/"
}

# Read-only mounts (`knowledgeSources[]`) use this same scheme and are never written,
# never pushed and never index-regenerated.
sources_json() { cfg --json knowledgeSources; }

each_source() { # -> "<index>\t<repo>\t<path>\t<ref>\t<name>"
  local js; js="$(sources_json)" || return 0
  [ -n "$js" ] || return 0
  printf '%s' "$js" | python3 -c '
import json,sys
try: v=json.load(sys.stdin)
except Exception: sys.exit(0)
if not isinstance(v,list): sys.exit(0)
for i,e in enumerate(v):
    if not isinstance(e,dict) or not e.get("repo"): continue
    repo=str(e["repo"]); name=repo.rstrip("/").split("/")[-1].replace(".git","")
    print("\t".join([str(i),repo,str(e.get("path") or "/"),str(e.get("ref") or "main"),name]))
' 2>/dev/null
}

mount_sources() {
  local i repo path ref name gd wt
  while IFS=$'\t' read -r i repo path ref name; do
    [ -n "${repo:-}" ] || continue
    gd="$SRCROOT/$name.git"; wt="$INST/knowledge-sources/$name"
    [ -d "$gd" ] && continue
    if clone_mount "$gd" "$wt" "$(remote_url "$repo")" "$ref" ""; then
      say "mounted read-only $repo at knowledge-sources/$name"
    else
      rm -rf "$gd"; warn "could not mount read-only source $repo — skipped, not fatal"
    fi
  done <<EOF
$(each_source)
EOF
}

pull_one() { # <gitdir> <ref> <label>
  local gd="$1" ref="$2" label="$3"
  [ -d "$gd" ] || return 0
  if ! bounded git --git-dir="$gd" fetch --quiet origin "$ref" 2>/dev/null; then
    warn "could not fetch $label within ${TIMEOUT}s — using the local copy (not fatal)"
    return 0
  fi
  git --git-dir="$gd" merge --ff-only --quiet FETCH_HEAD 2>/dev/null \
    || warn "$label is not fast-forwardable — left untouched (not fatal)"
}

# --- the write transaction ---------------------------------------------------
rebase_in_progress() { [ -d "$KBGIT/rebase-merge" ] || [ -d "$KBGIT/rebase-apply" ]; }
abort_rebase() { rebase_in_progress && kbg rebase --abort >/dev/null 2>&1; return 0; }

regenerate_index() {
  bash "$HERE/build-kb-index.sh" >/dev/null 2>&1 || return 1
  kbg add -- "${KB_PREFIX}index.md" >/dev/null 2>&1
}

conflicted() { kbg diff --name-only --diff-filter=U 2>/dev/null; }

# index.md is DERIVED, so a conflict in it is resolved by taking neither side and
# rerunning the generator. Any other conflicted path — a same-slug Finding from two
# clones — is a real collision and stops here for a human.
resolve_conflicts() {
  local files; files="$(conflicted)"
  [ -n "$files" ] || return 0
  if [ "$files" != "${KB_PREFIX}index.md" ]; then
    warn "the KB rebase conflicts outside the derived index:"
    while IFS= read -r f; do [ -n "$f" ] && printf '         %s\n' "$f" >&2; done <<EOF
$files
EOF
    warn "that is a real collision (two clones, one slug) — resolve it by hand in $KB_MOUNT."
    return 1
  fi
  ( cd "$INST" && regenerate_index ) || return 1
  GIT_EDITOR=true kbg rebase --continue >/dev/null 2>&1
}

kb_author() { # -> "<name>\t<email>"
  local pair where val who email
  pair="$(cfg --source authorEmail)"; where="${pair%%$'\t'*}"; val="${pair#*$'\t'}"
  who="$(cfg ownerGithubUser)"
  if [ "$where" = local ] && [ -n "$val" ]; then email="$val"
  else
    email="$(cfg people "$who")"
    [ -n "$email" ] || email="$val"
  fi
  [ -n "$email" ] || email="$(git -C "$INST" config user.email 2>/dev/null)"
  [ -n "$who" ] || who="$(git -C "$INST" config user.name 2>/dev/null)"
  printf '%s\t%s' "$who" "$email"
}

do_commit() {
  kb_configured || exit 3
  kb_vars
  [ -d "$KBGIT" ] || die "no knowledge mount here — run 'kb-sync.sh mount' first."
  [ -n "$message" ] || die "commit wants --message" 2
  [ "${#paths[@]}" -gt 0 ] || die "commit wants '-- <path>...' (bundle-relative, under knowledge/)" 2

  local rel p
  for p in "${paths[@]}"; do
    p="${p#./}"; p="${p#"$INST"/}"
    case "$p" in
      knowledge|knowledge/*) ;;
      *) die "'$p' is outside knowledge/ — kb-sync commits the mounted KB and nothing else." ;;
    esac
    case "$KB_SPARSE" in "") rel="${p#knowledge/}"; [ "$rel" = knowledge ] && rel="." ;; *) rel="$p" ;; esac
    kbg add -- "$rel" || die "could not stage '$p' in the KB mount."
  done

  local who name email
  who="$(kb_author)"; name="${who%%$'\t'*}"; email="${who#*$'\t'}"
  [ -n "$email" ] || die "no author email for the KB commit — add this clone's login to
       \"people\" in instance.config.json and \"ownerGithubUser\" to instance.config.local.json."
  [ -n "$name" ] || name="$email"

  ( cd "$INST" && regenerate_index ) || die "could not regenerate knowledge/index.md — refusing to commit."

  if kbg diff --cached --quiet 2>/dev/null; then
    say "nothing to commit in the KB mount."
    return 0
  fi

  local trailer body
  trailer="Co-Authored-By: ai-bridge ${role:-agent} (Claude) <noreply@anthropic.com>"
  body="$message

$trailer"
  kbg -c "user.name=$name" -c "user.email=$email" \
      commit --quiet --author="$name <$email>" -m "$body" \
    || die "the KB commit failed — nothing was pushed."

  push_with_one_retry
}

push_with_one_retry() {
  local attempt=0
  trap 'abort_rebase' EXIT
  while [ "$attempt" -lt 2 ]; do
    attempt=$((attempt+1))
    if ! bounded git --git-dir="$KBGIT" fetch --quiet origin "$KB_REF" 2>/dev/null; then
      warn "could not fetch $KB_REPO within ${TIMEOUT}s on attempt $attempt."
    elif ! kbg rebase --quiet FETCH_HEAD >/dev/null 2>&1; then
      if ! resolve_conflicts; then
        abort_rebase
        die "the KB transaction stopped on attempt $attempt and left no rebase behind.
       Your commit is local in $KB_MOUNT; resolve and re-run 'kb-sync.sh commit'."
      fi
    fi
    if bounded git --git-dir="$KBGIT" push --quiet origin "HEAD:refs/heads/$KB_REF" 2>/dev/null; then
      trap - EXIT
      say "pushed $(kbg rev-parse --short HEAD) to $KB_REPO ($KB_REF)."
      return 0
    fi
    warn "push rejected on attempt $attempt of 2."
  done
  abort_rebase; trap - EXIT
  die "the KB push failed twice — stopping rather than forcing.
       The commit is local in $KB_MOUNT and unpushed; re-run 'kb-sync.sh commit' once
       the remote settles. Nothing was force-pushed and no rebase was left behind."
}

# --- commands ----------------------------------------------------------------
case "$cmd" in
  mount)
    kb_configured || { say "no 'knowledge' key in instance.config.json — knowledge/ is this bundle's own folder."; exit 3; }
    mount_writable
    mount_sources
    ;;
  pull)
    kb_configured || exit 3
    kb_vars
    pull_one "$KBGIT" "$KB_REF" "$KB_REPO"
    while IFS=$'\t' read -r i repo path ref name; do
      [ -n "${repo:-}" ] || continue
      pull_one "$SRCROOT/$name.git" "$ref" "$repo"
    done <<EOF
$(each_source)
EOF
    exit 0
    ;;
  status)
    kb_configured || exit 3
    kb_vars
    [ -d "$KBGIT" ] || { warn "knowledge is configured but not mounted — run 'kb-sync.sh mount'."; exit 1; }
    ahead="$(kbg rev-list --count "origin/$KB_REF..HEAD" 2>/dev/null)" || ahead=""
    # No tracking ref means the branch has never been pushed, so EVERY local commit is
    # unpushed — the case that read as "clean" while holding a day of Findings.
    [ -n "$ahead" ] || ahead="$(kbg rev-list --count HEAD 2>/dev/null)" || ahead=""
    if [ -n "$ahead" ] && [ "$ahead" -gt 0 ]; then
      warn "$ahead KB commit(s) are local and UNPUSHED in $KB_MOUNT — run 'kb-sync.sh commit' or push by hand."
      exit 1
    fi
    say "KB mount is clean and pushed."
    ;;
  commit) do_commit ;;
  "") echo "kb-sync: no command. One of: mount, pull, status, commit." >&2; exit 2 ;;
  *) echo "kb-sync: unknown command '$cmd'" >&2; exit 2 ;;
esac
