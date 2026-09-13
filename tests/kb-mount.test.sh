#!/usr/bin/env bash
#
# kb-mount.test.sh — `knowledge/` mounted from another repository: the absent-key no-op,
# the mount itself, the bounded reads, and the refusals.
#
# TWO HALVES, AND THE FIRST ONE IS THE POINT. Absent a `knowledge` key nothing may change:
# the same fixture bundle is walked by every KB reader with and without the key, and the
# two runs are DIFFED. A mount that is a real directory makes that diff empty; the symlink
# form this design replaced could not, because `find knowledge -type f` does not follow a
# starting-point symlink and would have regenerated an EMPTY index over a populated KB.
#
# OFFLINE BY CONSTRUCTION. The "remote" is a local bare repo, so every clone, fetch, rebase
# and push here is a filesystem operation. Nothing reaches the network, including the
# unroutable-remote case, which is the one that proves the timeout is real.
#
# ok() compares actual to expected, in that order. Seeded ai-bridge-v3/task-021.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SYNC="$REPO/plugin/scripts/kb-sync.sh"
SEED="$REPO/plugin/seed"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/kb-mount.XXXXXX")" || exit 2
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
ok() {
  if [ "$2" = "$3" ]; then printf '  PASS  %-58s (%s)\n' "$1" "$2"; pass=$((pass+1))
  else printf '  FAIL  %-58s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}
has() { grep -qF -- "$2" <<<"$1" && echo yes || echo no; }

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com
export GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com
export AI_BRIDGE_KB_TIMEOUT=3

# --- fixtures ----------------------------------------------------------------
finding() { # <file> <slug> <lesson>
  mkdir -p "$(dirname "$1")"
  cat > "$1" <<EOF
---
type: Finding
title: $2
description: $2
lesson: $3
category: learning
status: current
author: example-user-007
timestamp: 2026-09-13T00:00:00Z
---

# Finding

$3
EOF
}

# A bundle with a real, populated knowledge/ and no `knowledge` key.
make_bundle() { # <dir>
  local d="$1"
  mkdir -p "$d/knowledge/findings" "$d/knowledge/services" "$d/knowledge/runbooks" \
           "$d/knowledge/teams" "$d/knowledge/references" "$d/projects"
  cp "$SEED/SCHEMA.md" "$d/SCHEMA.md"
  printf '{ "org": "acme", "people": { "example-user-007": "e@example.com" } }\n' > "$d/instance.config.json"
  cp "$SEED/knowledge/vocab.md" "$d/knowledge/vocab.md" 2>/dev/null || true
  : > "$d/knowledge/log.md"
  finding "$d/knowledge/findings/alpha.md" alpha "a mount is a real directory"
  finding "$d/knowledge/findings/beta.md"  beta  "the index is derived"
  ( cd "$d" && bash "$REPO/plugin/scripts/build-kb-index.sh" >/dev/null 2>&1 )
}

# The KB "remote": a bare repo seeded with the same two findings.
BARE="$TMP/kb.git"
git init --bare --quiet "$BARE"
SEEDCLONE="$TMP/seedclone"
git init --quiet -b main "$SEEDCLONE"
mkdir -p "$SEEDCLONE/findings"
finding "$SEEDCLONE/findings/alpha.md" alpha "a mount is a real directory"
finding "$SEEDCLONE/findings/beta.md"  beta  "the index is derived"
cp "$SEED/knowledge/vocab.md" "$SEEDCLONE/vocab.md" 2>/dev/null || true
: > "$SEEDCLONE/log.md"
( cd "$SEEDCLONE" && git add -A >/dev/null && git commit -qm seed && git remote add origin "$BARE" \
  && git push -q origin main )

echo "== absent the key, nothing changes =="

PLAIN="$TMP/plain"; make_bundle "$PLAIN"
fingerprint() { ( cd "$1" && find knowledge -type f -exec cksum {} + | LC_ALL=C sort ); }
before="$(fingerprint "$PLAIN")"
for c in mount pull status commit; do
  rc=0; bash "$SYNC" --instance "$PLAIN" "$c" >/dev/null 2>&1 || rc=$?
  ok "'$c' with no knowledge key exits 3" "$rc" 3
done
ok "…and every byte under knowledge/ is unchanged by those four calls" \
  "$([ "$before" = "$(fingerprint "$PLAIN")" ] && echo same || echo differs)" same
ok "…and the fingerprint is non-empty, so that comparison is not two blanks" \
  "$([ -n "$before" ] && echo yes || echo no)" yes
ok "…and knowledge/ is still a real directory, not a link" \
  "$([ -d "$PLAIN/knowledge" ] && [ ! -L "$PLAIN/knowledge" ] && echo yes || echo no)" yes

echo "== the readers produce identical output over a mount and a local KB =="

MOUNTED="$TMP/mounted"
mkdir -p "$MOUNTED/projects"
cp "$SEED/SCHEMA.md" "$MOUNTED/SCHEMA.md"
cat > "$MOUNTED/instance.config.json" <<EOF
{ "org": "acme", "people": { "example-user-007": "e@example.com" },
  "knowledge": { "repo": "$BARE", "path": "/", "ref": "main" } }
EOF
out="$(bash "$SYNC" --instance "$MOUNTED" mount 2>&1)"; rc=$?
ok "mount clones the KB repo" "$rc" 0
ok "…and says where it landed" "$(has "$out" 'at knowledge/')" yes
ok "…as a REAL directory, never a symlink" \
  "$([ -d "$MOUNTED/knowledge" ] && [ ! -L "$MOUNTED/knowledge" ] && echo yes || echo no)" yes
ok "…with no .git inside knowledge/ for a reader to walk into" \
  "$([ -e "$MOUNTED/knowledge/.git" ] && echo yes || echo no)" no
ok "…and the gitdir lives under .ai-bridge/, per bundle" \
  "$([ -d "$MOUNTED/.ai-bridge/kb.git" ] && echo yes || echo no)" yes

# `find knowledge -type f` is the exact call build-kb-index.sh:342 makes; the symlink form
# returned nothing for it, which is the defect this whole design exists to remove.
ok "find knowledge -type f descends the mount" \
  "$(cd "$MOUNTED" && find knowledge -type f -name '*.md' | wc -l | tr -d ' ')" \
  "$(cd "$PLAIN" && find knowledge -type f -name '*.md' | grep -v index.md | wc -l | tr -d ' ')"

( cd "$MOUNTED" && bash "$REPO/plugin/scripts/build-kb-index.sh" >/dev/null 2>&1 )
for reader in "build-kb-index.sh --print" "build-kb-index.sh --check" "cite-check.sh --text-file /dev/null --brief alpha"; do
  a="$(cd "$PLAIN"   && bash "$REPO/plugin/scripts/${reader%% *}" ${reader#* } 2>&1)"
  b="$(cd "$MOUNTED" && bash "$REPO/plugin/scripts/${reader%% *}" ${reader#* } 2>&1)"
  ok "'${reader%% *}' agrees over mount and local KB" "$([ "$a" = "$b" ] && echo same || echo differs)" same
done

echo "== the refusals =="

STALE="$TMP/stale"; make_bundle "$STALE"
cat > "$STALE/instance.config.json" <<EOF
{ "org": "acme", "knowledge": { "repo": "$BARE", "path": "/", "ref": "main" } }
EOF
out="$(bash "$SYNC" --instance "$STALE" mount 2>&1)"; rc=$?
ok "a real knowledge/ already there makes mount REFUSE" "$rc" 1
ok "…and print the migration command" "$(has "$out" 'kb-migrate.sh')" yes
ok "…and leave every file where it was" \
  "$(find "$STALE/knowledge" -name 'alpha.md' | wc -l | tr -d ' ')" 1

BADREF="$TMP/badref"; mkdir -p "$BADREF"
cp "$SEED/SCHEMA.md" "$BADREF/SCHEMA.md"
sha="$(git -C "$SEEDCLONE" rev-parse HEAD)"
printf '{ "knowledge": { "repo": "%s", "path": "/", "ref": "%s" } }\n' "$BARE" "$sha" > "$BADREF/instance.config.json"
out="$(bash "$SYNC" --instance "$BADREF" mount 2>&1)"; rc=$?
ok "a SHA as ref is refused" "$rc" 1
ok "…by name, saying a detached HEAD cannot be pushed" "$(has "$out" 'cannot be pushed')" yes

git -C "$SEEDCLONE" tag -f v1 -m v1 >/dev/null 2>&1; git -C "$SEEDCLONE" push -q -f origin v1
printf '{ "knowledge": { "repo": "%s", "path": "/", "ref": "v1" } }\n' "$BARE" > "$BADREF/instance.config.json"
out="$(bash "$SYNC" --instance "$BADREF" mount 2>&1)"; rc=$?
ok "a TAG as ref is refused" "$rc" 1
ok "…and is named as a TAG, not as a missing branch" "$(has "$out" 'is a TAG')" yes

BADPATH="$TMP/badpath"; mkdir -p "$BADPATH"
printf '{ "knowledge": { "repo": "%s", "path": "docs/kb", "ref": "main" } }\n' "$BARE" > "$BADPATH/instance.config.json"
out="$(bash "$SYNC" --instance "$BADPATH" mount 2>&1)"; rc=$?
ok "an unmountable path is refused by name" "$rc" 1
ok "…naming the two forms that work" "$(has "$out" "Only '/'")" yes

echo "== a path: knowledge mount, the shared-repo case =="

BARE2="$TMP/shared.git"; git init --bare --quiet "$BARE2"
SC2="$TMP/sharedclone"; git init --quiet -b main "$SC2"
mkdir -p "$SC2/knowledge/findings"
finding "$SC2/knowledge/findings/alpha.md" alpha "a folder inside a shared repo mounts too"
printf '# org home\n' > "$SC2/README.md"
( cd "$SC2" && git add -A >/dev/null && git commit -qm seed && git remote add origin "$BARE2" && git push -q origin main )

SHARED="$TMP/shared"; mkdir -p "$SHARED/projects"
cp "$SEED/SCHEMA.md" "$SHARED/SCHEMA.md"
printf '{ "knowledge": { "repo": "%s", "path": "knowledge", "ref": "main" } }\n' "$BARE2" > "$SHARED/instance.config.json"
bash "$SYNC" --instance "$SHARED" mount >/dev/null 2>&1
ok "path: knowledge lands at knowledge/, one level deep" \
  "$([ -f "$SHARED/knowledge/findings/alpha.md" ] && echo yes || echo no)" yes
ok "…and the sparse checkout leaves the repo's own README out" \
  "$([ -e "$SHARED/README.md" ] && echo yes || echo no)" no

echo "== the reads are bounded and never fatal =="

DEAD="$TMP/dead"; mkdir -p "$DEAD"
printf '{ "knowledge": { "repo": "https://10.255.255.1/x/y.git", "path": "/", "ref": "main" } }\n' > "$DEAD/instance.config.json"
mkdir -p "$DEAD/.ai-bridge/kb.git"
git init --bare --quiet "$DEAD/.ai-bridge/kb.git"
git --git-dir="$DEAD/.ai-bridge/kb.git" remote add origin https://10.255.255.1/x/y.git
git --git-dir="$DEAD/.ai-bridge/kb.git" config core.worktree "$DEAD/knowledge"
start=$(date +%s)
out="$(bash "$SYNC" --instance "$DEAD" --timeout 3 pull 2>&1)"; rc=$?
elapsed=$(( $(date +%s) - start ))
ok "an unroutable remote does not hang the pull" "$([ "$elapsed" -le 25 ] && echo yes || echo no)" yes
ok "…and the pull is NOT fatal" "$rc" 0
ok "…and says so, naming the bound" "$(has "$out" 'not fatal')" yes

echo "== read-only knowledgeSources[] use the same scheme =="

RO="$TMP/ro"; mkdir -p "$RO"
cat > "$RO/instance.config.json" <<EOF
{ "knowledge": { "repo": "$BARE", "path": "/", "ref": "main" },
  "knowledgeSources": [ { "repo": "$BARE2", "path": "/", "ref": "main" } ] }
EOF
cp "$SEED/SCHEMA.md" "$RO/SCHEMA.md"
out="$(bash "$SYNC" --instance "$RO" mount 2>&1)"
ok "a knowledgeSources entry is cloned by the same script" \
  "$([ -d "$RO/knowledge-sources/shared" ] && echo yes || echo no)" yes
ok "…and is named as read-only" "$(has "$out" 'read-only')" yes
rc=0; bash "$SYNC" --instance "$RO" commit --message m -- knowledge-sources/shared/x.md >/dev/null 2>&1 || rc=$?
ok "a write against a read-only mount is refused" "$rc" 1

ROP="$TMP/rop"; mkdir -p "$ROP"; cp "$SEED/SCHEMA.md" "$ROP/SCHEMA.md"
printf '{ "knowledge": { "repo": "%s", "path": "/", "ref": "main" },\n  "knowledgeSources": [ { "repo": "%s", "path": "knowledge", "ref": "main" } ] }\n' "$BARE" "$BARE2" > "$ROP/instance.config.json"
bash "$SYNC" --instance "$ROP" mount >/dev/null 2>&1
ok "a source path: is checked out, not ignored" \
  "$([ -f "$ROP/knowledge-sources/shared/knowledge/findings/alpha.md" ] && echo yes || echo no)" yes
ok "…so the repo's own root stays out of the mount" \
  "$([ -e "$ROP/knowledge-sources/shared/README.md" ] && echo yes || echo no)" no

mkdir -p "$TMP/dup"; DUP="$TMP/dup/shared.git"; git init --bare --quiet "$DUP"
ROD="$TMP/rod"; mkdir -p "$ROD"; cp "$SEED/SCHEMA.md" "$ROD/SCHEMA.md"
printf '{ "knowledge": { "repo": "%s", "path": "/", "ref": "main" },\n  "knowledgeSources": [ { "repo": "%s" }, { "repo": "%s" } ] }\n' "$BARE" "$BARE2" "$DUP" > "$ROD/instance.config.json"
out="$(bash "$SYNC" --instance "$ROD" mount 2>&1)"
ok "two sources with one repo name are reported, not silently skipped" \
  "$(has "$out" 'both mount at knowledge-sources/shared')" yes
ok "…naming the entry that lost" "$(has "$out" "$DUP")" yes

echo "== the KB journals shard per month once shared; the bundle ledger does not =="

PC="$REPO/plugin/scripts/papercuts.sh"
J="$TMP/journal"; make_bundle "$J"
( cd "$J" && bash "$PC" add --task p/task-1 --surface script:x --note "the flat record is what an unmounted bundle keeps" --date 2026-08-04 ) >/dev/null
ok "unmounted, an entry lands in the flat record" \
  "$([ -f "$J/knowledge/papercuts.md" ] && echo yes || echo no)" yes
mkdir -p "$J/.ai-bridge/kb.git"
out="$( cd "$J" && bash "$PC" add --task p/task-2 --surface script:x --note "mounted, the record shards by month" --date 2026-09-05 )"
ok "mounted, the entry lands in this month's shard" \
  "$([ -f "$J/knowledge/papercuts/2026-09.md" ] && echo yes || echo no)" yes
ok "…and a different month is a different file" \
  "$( cd "$J" && bash "$PC" add --task p/task-3 --surface script:y --note "a month file goes cold on its own" --date 2026-10-02 >/dev/null; [ -f "$J/knowledge/papercuts/2026-10.md" ] && echo yes || echo no)" yes
ok "…and every reader sees the flat file AND the shards" \
  "$( cd "$J" && bash "$PC" check 2>/dev/null | sed -n 's/papercuts: \([0-9]*\) entries.*/\1/p')" 3
ok "…with report grouping the three across two surfaces" \
  "$( cd "$J" && bash "$PC" report --all 2>/dev/null | sed -n 's/^== \(.*\) · all time$/\1/p')" \
  "3 entries · 2 surfaces"
ok "the bundle-root log.md is NOT sharded by any of this" \
  "$(grep -c 'bundle-root `log.md`' "$SEED/SCHEMA.md" | tr -d ' ')" 1
mkdir -p "$J/knowledge/log"; : > "$J/knowledge/log/2026-09.md"
ok "the index footer follows the journal that exists" \
  "$( cd "$J" && bash "$REPO/plugin/scripts/build-kb-index.sh" --print | grep -c '/knowledge/log/' | tr -d ' ')" 1

echo "== index.md is derived, and a hand-written row is reported =="

V="$REPO/plugin/scripts/validate-bundle.sh"
D="$TMP/derived"; make_bundle "$D"
ok "a generated index validates clean" \
  "$( cd "$D" && bash "$V" 2>&1 | grep -c 'never hand-edited' | tr -d ' ')" 0
printf '| made up | a row the generator would not produce | `/knowledge/findings/alpha.md` | current |\n' >> "$D/knowledge/index.md"
ok "…and a hand-written row WARNs" \
  "$( cd "$D" && bash "$V" 2>&1 | grep -c 'never hand-edited' | tr -d ' ')" 1
ok "…without failing the bundle over it" "$( cd "$D" && bash "$V" >/dev/null 2>&1; echo $?)" 0

echo "== author: is accepted by both validators =="
ok "build-kb-index accepts a login" \
  "$( cd "$D" && bash "$REPO/plugin/scripts/build-kb-index.sh" --check 2>&1 | grep -c "is not a GitHub login" | tr -d ' ')" 0
sed -i.bak 's/^author: example-user-007$/author: Not A Login!/' "$D/knowledge/findings/alpha.md"; rm -f "$D/knowledge/findings/alpha.md.bak"
ok "…and warns on something that is not one" \
  "$( cd "$D" && bash "$REPO/plugin/scripts/build-kb-index.sh" --check 2>&1 | grep -c "is not a GitHub login" | tr -d ' ')" 1
ok "…as does validate-bundle" \
  "$( cd "$D" && bash "$V" 2>&1 | grep -c "is not a GitHub login" | tr -d ' ')" 1

echo "== push-state.sh was NOT extended for any of this =="
ok "push-state.sh names no KB sync" \
  "$(grep -c 'kb-sync' "$REPO/plugin/hooks/push-state.sh" | tr -d ' ')" 0
# It rides the existing SessionStart hook rather than registering a second one: a bundle
# with no mount then pays nothing, and no hook counter moves.
ok "the SessionStart fast-forward sits beside the banner" \
  "$(grep -c 'kb-sync.sh\" --instance \"$root\" --timeout 10 pull' "$REPO/plugin/hooks/session-banner.sh" | tr -d ' ')" 1
ok "…and registers no second SessionStart hook" \
  "$(grep -c 'kb-sync' "$REPO/plugin/hooks/hooks.json" | tr -d ' ')" 0
ok "…with its output on stderr, so --format json stays parseable" \
  "$(grep -c 'pull >&2 || true' "$REPO/plugin/hooks/session-banner.sh" | tr -d ' ')" 1
ok "the tick fast-forwards at its start" \
  "$(grep -c 'kb-sync.sh pull' "$REPO/plugin/agents/project-manager.md" | tr -d ' ')" 1
ok "/ai-bridge:init WARNs on unpushed KB commits" \
  "$(grep -c 'kb-sync.sh\" --instance \"\$TARGET\" status' "$REPO/plugin/scripts/init-bundle.sh" | tr -d ' ')" 1
ok "…and never pushes them itself" \
  "$(grep -c 'kb-sync.sh" --instance "$TARGET" commit' "$REPO/plugin/scripts/init-bundle.sh" | tr -d ' ')" 0
ok "…and ignores the mount only where one is configured" \
  "$(grep -c 'knowledge repo' "$REPO/plugin/scripts/init-bundle.sh" | tr -d ' ')" 1

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
