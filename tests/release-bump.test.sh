#!/usr/bin/env bash
#
# release-bump.test.sh — the version moves at MERGE time, on the default branch, and a pull
# request that touches `plugin/` carries no bump at all.
#
# WHY THIS FILE EXISTS. Every core PR used to edit the same five places — `VERSION`,
# `plugin/VERSION`, both manifests and the banner sample in `docs/operations.md` — so any
# two open core PRs conflicted on those five and had to land one at a time, each after a
# fresh merge-main and a full suite run. Measured 2026-09-06 with seven open PRs: the
# version files were the only conflict in five of six merges
# (knowledge/findings/parallel-core-prs-collide-on-one-version-number-…). A user-owned repo
# cannot have a merge queue, so the fix is to take the number out of the PR entirely.
#
# THE INVERSION IS THE PROPERTY, and it is pinned END TO END rather than by grepping prose:
# a fixture checkout takes a real `plugin/` edit with NO version change and
# `tests/template-version.test.sh` must PASS on it, and the same fixture after
# `release-bump.sh` must pass it again. Nothing weaker would notice a harness quietly
# reinstating "a plugin change bumps the version".
#
# THE LOCKSTEP GUARANTEE IS NOT WEAKENED — the five still have to agree with each other,
# which is exactly what running the real harness in both fixtures asserts.
#
# THE FIXTURE IS `git archive HEAD`, not a clone: a CI checkout of a pull request is a
# DETACHED head, and cloning one produces an empty working tree. It also means this reads
# your last commit, not your unstaged edits.
#
# ok() follows this directory's convention: it compares actual to expected.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
BUMP="$REPO/plugin/scripts/release-bump.sh"
[ -f "$BUMP" ] || { echo "release-bump.test: missing $BUMP" >&2; exit 2; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/release-bump.XXXXXX")" \
  || { echo "release-bump.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp}" >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
ok() { # <name> <actual> <expected>
  if [ "$2" = "$3" ]; then printf '  PASS  %-62s (%s)\n' "$1" "$2"; pass=$((pass+1))
  else printf '  FAIL  %-62s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}
# Identity is forced rather than inherited: a machine with no `user.email` would otherwise
# fail every fixture commit for a reason that has nothing to do with this change.
GIT() { git -c user.email=test@example.com -c user.name=Test -c commit.gpgsign=false "$@"; }
run() { "$BUMP" "$@" >/dev/null 2>&1; echo $?; }

fixture() { # <dir> — this repo at HEAD, committed, on `main`, with an origin/HEAD to match
  mkdir -p "$1"
  GIT -C "$REPO" archive HEAD | tar -x -C "$1"
  GIT -C "$1" init -q -b main >/dev/null 2>&1 || { GIT -C "$1" init -q; GIT -C "$1" checkout -q -b main; }
  GIT -C "$1" add -A >/dev/null
  GIT -C "$1" commit -q -m "fixture: the repo at HEAD"
  GIT -C "$1" update-ref refs/remotes/origin/main "$(GIT -C "$1" rev-parse HEAD)"
  GIT -C "$1" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
}
plant() { # <dir> <version> — set VERSION alone, so the bump has to move the other four
  printf '%s\n' "$2" > "$1/VERSION"
  GIT -C "$1" commit -q -am "plant $2"
}
mkt_core() { # <dir> — the marketplace version of the entry the host resolves
  python3 -c '
import json, sys
mkt = json.load(open(sys.argv[1] + "/.claude-plugin/marketplace.json", encoding="utf-8"))
print([p["version"] for p in mkt["plugins"] if p.get("source") == "./plugin"][0])' "$1"
}
five() { # <dir> — the five places, space-separated, so one assertion reads them all
  printf '%s %s %s %s %s' \
    "$(head -n 1 "$1/VERSION")" "$(head -n 1 "$1/plugin/VERSION")" \
    "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]+"/plugin/.claude-plugin/plugin.json",encoding="utf-8"))["version"])' "$1")" \
    "$(mkt_core "$1")" \
    "$(grep -hoE 'AI-Bridge v?[0-9]+\.[0-9]+\.[0-9]+' "$1/docs/operations.md" | sed 's/^AI-Bridge v\{0,1\}//' | sort -u)"
}
harness() { # <dir> <harness> — run a real harness IN the fixture; its tally and its exit
  local out rc
  out="$(cd "$1" && bash "tests/$2" 2>&1)"; rc=$?
  printf '%s rc=%d' "$(printf '%s' "$out" | grep -oE 'fail=[0-9]+' | tail -n 1)" "$rc"
}

echo
echo "== 1. the guards: the bump lands on the default branch, on a clean tree =="
ok "no field is a usage error"            "$(run)" 2
ok "an unknown argument is too"           "$(run major)" 2
ok "a directory with no VERSION is refused" "$(run patch --repo "$TMP")" 1

fixture "$TMP/guards"
ok "…a clean fixture on its default branch is accepted" "$(run patch --repo "$TMP/guards")" 0
GIT -C "$TMP/guards" checkout -q -b feat/something
ok "…and a FEATURE branch is refused (the PR never carries it)" \
  "$(run patch --repo "$TMP/guards")" 1
ok "…naming the branch it wanted" \
  "$("$BUMP" patch --repo "$TMP/guards" 2>&1 >/dev/null | grep -c "not the default branch 'main'")" 1
GIT -C "$TMP/guards" checkout -q main
printf 'dirty\n' >> "$TMP/guards/README.md"
ok "…and a dirty tree is refused (the bump is its own commit)" \
  "$(run patch --repo "$TMP/guards")" 1

echo
echo "== 2. one script writes all five places, and the banner rule follows =="
fixture "$TMP/five"
plant "$TMP/five" 2.4.7
ok "patch is accepted"                     "$(run patch --repo "$TMP/five")" 0
ok "…and moves the last field in all five" "$(five "$TMP/five")" "2.4.8 2.4.8 2.4.8 2.4.8 2.4.8"
ok "…while minor moves the middle one and zeroes the last" \
  "$(run minor --repo "$TMP/five" >/dev/null; five "$TMP/five")" "2.5.0 2.5.0 2.5.0 2.5.0 2.5.0"
# The `─` rule under the sampled banner header is as wide as the header, in CHARACTERS —
# `·` is two bytes and `─` is three, so this is the one place a byte count reads as correct
# and is not. 2.9.0 -> 2.10.0 is the shortest bump that lengthens the header.
plant "$TMP/five" 2.9.0
run minor --repo "$TMP/five" >/dev/null
ok "…and the banner rule is re-cut to the new header's WIDTH" \
  "$(python3 -c '
import io, re, sys
lines = io.open(sys.argv[1] + "/docs/operations.md", encoding="utf-8").read().splitlines()
bad = [i for i, l in enumerate(lines[:-1])
       if l.startswith("AI-Bridge ") and set(lines[i+1]) == {u"─"} and len(lines[i+1]) != len(l)]
print(len(bad))' "$TMP/five")" 0
ok "…on a header that really did get longer"  "$(five "$TMP/five" | cut -d' ' -f1)" 2.10.0

fixture "$TMP/dry"
before="$(five "$TMP/dry")"
ok "--dry-run is accepted"                 "$(run minor --dry-run --repo "$TMP/dry")" 0
ok "…and writes nothing"                   "$(five "$TMP/dry")" "$before"
ok "…and leaves the tree clean"             "$(GIT -C "$TMP/dry" status --porcelain | wc -l | tr -d ' ')" 0
ok "…while naming the five places it would write" \
  "$("$BUMP" minor --dry-run --repo "$TMP/dry" | grep -cE '^(VERSION|plugin/VERSION|plugin/\.claude-plugin/plugin\.json|\.claude-plugin/marketplace\.json|docs/operations\.md)$')" 5

echo
echo "== 3. a PR touching plugin/ WITHOUT a bump passes — the whole point of the change =="
fixture "$TMP/pr"
base="$(head -n 1 "$TMP/pr/VERSION")"
GIT -C "$TMP/pr" checkout -q -b feat/a-plugin-change
printf '\n# a change under plugin/, carrying no version bump\n' >> "$TMP/pr/plugin/scripts/task-owner.sh"
GIT -C "$TMP/pr" commit -q -am "feat: a plugin change with no bump"
ok "the branch really did change plugin/ and NOT the version" \
  "$(GIT -C "$TMP/pr" diff --name-only origin/main...HEAD | grep -cE '^plugin/|^VERSION$' )" 1
ok "…VERSION is untouched"                 "$(head -n 1 "$TMP/pr/VERSION")" "$base"
ok "…and template-version.test.sh PASSES on it" "$(harness "$TMP/pr" template-version.test.sh)" "fail=0 rc=0"

echo
echo "== 4. …and main after release-bump.sh passes the same harness =="
GIT -C "$TMP/pr" checkout -q main
GIT -C "$TMP/pr" merge -q --no-ff -m "merge: the plugin change" feat/a-plugin-change
ok "release-bump.sh runs on the merged main" "$(run minor --repo "$TMP/pr")" 0
ok "…template-version.test.sh passes there too" "$(harness "$TMP/pr" template-version.test.sh)" "fail=0 rc=0"
ok "…in ONE commit carrying exactly the five places" \
  "$(GIT -C "$TMP/pr" show --name-only --format= HEAD | grep . | LC_ALL=C sort | tr '\n' ' ')" \
  ".claude-plugin/marketplace.json VERSION docs/operations.md plugin/.claude-plugin/plugin.json plugin/VERSION "
# `claude plugin update` compares the installed version against plugin.json and does
# nothing when they match, so a bump that misses that file is a release nobody is offered.
ok "…including plugin.json, so a plugin update sees the bump" \
  "$(GIT -C "$TMP/pr" show --name-only --format= HEAD | grep -c '^plugin/\.claude-plugin/plugin\.json$')" 1
ok "…and the commit names the move"        \
  "$(GIT -C "$TMP/pr" log -1 --format=%s | grep -cE '^chore: VERSION [0-9.]+ -> [0-9.]+ \(bumped on main')" 1

echo
echo "== 5. it is the ONLY writer — nothing else moves a version place =="
# A WRITE is a redirection, a `sed -i` or a `tee` whose TARGET is one of the five — not a
# line that merely names one, which is why the place has to follow the operator with no
# space between. Comment lines are dropped first: `<root>/…` in prose carries a `>`.
WRITE='(>[[:space:]]*"?[^[:space:]|&]*(VERSION|plugin\.json|marketplace\.json)'
WRITE="$WRITE"'|sed -i[^|]*(VERSION|plugin\.json|marketplace\.json)'
WRITE="$WRITE"'|tee[[:space:]][^|]*(VERSION|plugin\.json|marketplace\.json))'
writers() { # <file…> -> the basenames that write a version place
  local f
  for f in "$@"; do
    [ -f "$f" ] || continue
    [ "$(basename "$f")" = release-bump.sh ] && continue
    grep -vE '^[[:space:]]*#' "$f" | grep -qE "$WRITE" && printf '%s\n' "${f##*/}"
  done
  return 0
}
ok "no other shipped script or workflow writes one" \
  "$(writers "$REPO"/plugin/scripts/*.sh "$REPO"/plugin/hooks/*.sh "$REPO"/.github/workflows/* | tr '\n' ' ')" ""
# The detector has to be able to fire, or the line above passes on a scan that matches
# nothing — the planted script is the shape a second bump path would actually take.
mkdir -p "$TMP/planted"
printf '#!/usr/bin/env bash\nprintf "9.9.9\\n" > "$root/VERSION"\n' > "$TMP/planted/second-bumper.sh"
ok "…and that scan catches a planted second writer" \
  "$(writers "$TMP/planted/second-bumper.sh")" second-bumper.sh
ok "…nothing bumps automatically on merge either" \
  "$(grep -rlE '(VERSION|marketplace\.json)' "$REPO"/.github/workflows/ | wc -l | tr -d ' ')" 0

echo
echo "== 6. the docs carry the new order: merge, bump, push =="
saw() { grep -Fq -- "$2" "$1" && echo yes || echo no; }
OPS="$REPO/docs/operations.md"
ok "operations.md names the order"          "$(saw "$OPS" 'merge, bump, push')" yes
ok "…and the script that does it"           "$(saw "$OPS" 'release-bump.sh')" yes
ok "…and that the bump commit goes straight to main" "$(saw "$OPS" 'straight to main')" yes
ok "…and that main's own suite on push is the check" \
  "$(saw "$OPS" "main's suite on the push is the check")" yes
ok "CLAUDE.md's core bullet says the PR does not carry it" \
  "$(saw "$REPO/CLAUDE.md" 'A change to `core` carries NO version bump')" yes
ok "machinery.md carries it"                "$(saw "$REPO/.claude/rules/machinery.md" 'carries NO version bump')" yes
ok "installer.md carries it"                "$(saw "$REPO/.claude/rules/installer.md" 'carries NO version bump')" yes
ok "the seed CONVENTIONS.md carves the repo out" \
  "$(saw "$REPO/plugin/seed/CONVENTIONS.md" 'THE BUMP HAPPENS ON THE DEFAULT BRANCH AT MERGE TIME')" yes

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
