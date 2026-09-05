#!/usr/bin/env bash
#
# board-in-repo.test.sh — `/board.html` is TRACKED, and the two rules that make that
# safe are asserted behaviourally rather than by grepping for prose.
#
# WHY THE PAGE IS IN THE REPO AT ALL. The board had to become visible to a teammate on a
# phone, and the serving routes were measured and rejected: access-controlled GitHub
# Pages is an Enterprise Cloud feature, so a Pages site on a private bundle serves the
# page to the WORLD at an unlisted URL (measured 2026-09-02: `has_pages: false` and
# `GET /repos/<owner>/<repo>/pages` -> 404 on all three private bundles). Committing
# the file into the private bundle needs no second access-control system: who may read it
# IS the repo's permission list.
#
# AND THE ARTIFACT PATH IS BACK ALONGSIDE IT, per machine — `/ai-bridge:board`, sections 5
# and 6 below. It was deleted in 2026-08 because the URL was TRACKED and publishing is
# account-scoped; recorded per machine it is a second route to the same page rather than a
# replacement for this one, and `/board.html` stays what a reader without artifact access
# opens. The tracked page's rules are unchanged and every assertion about them below is the
# one it already made. A GitHub Actions workflow cannot render it either — a
# runner's checkout has neither the machinery (all of an instance's scripts/ are absolute
# symlinks into a machine-local template clone, and gitignored) nor the input
# (SNAPSHOT.json is gitignored) — so "each tick" means the LOCAL tick.
#
# THE ONE THAT MATTERS IS SECTION 3. Given no instance directory, build-board.sh
# discovers instances from `boardInstances`, which on a real machine names SIBLING
# BUNDLES. That was harmless while every render went to a gitignored path. It is not
# harmless now: a bare render writes another bundle's project titles into a repo with a
# different permission list, and the tick would commit it. So the trailing `.` in
# `--out board.html .` is a data-governance boundary, and nothing asserted it before this
# file. The section renders BOTH ways from one fixture, so it fails if the scoping breaks
# AND fails if the fixture stopped being able to leak (a one-sided assertion here would
# go green on a fixture whose second instance had quietly stopped rendering at all).
#
# WHY install.sh MIGRATES RATHER THAN REWRITES (section 2). Every instance in existence
# was seeded from a seed/.gitignore that IGNORED board.html. install.sh never removes a
# line from a live instance's .gitignore — that is what makes it safe to run blindly on a
# repo full of someone's work — so the migration APPENDS `!/board.html` and leans on
# git's own last-match-wins rule. Asserted with `git check-ignore`, not by grepping for
# the pattern text, because the ORDERING is the mechanism.
#
# ok() follows this directory's convention: it compares actual to expected.
set -uo pipefail

TPLSRC="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/board-in-repo.XXXXXX")" || {
  echo "board-in-repo.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp} — create that directory first." >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
ok() { # <name> <actual> <expected>
  if [ "$2" = "$3" ]; then printf '  PASS  %-66s (%s)\n' "$1" "$2"; pass=$((pass+1))
  else printf '  FAIL  %-66s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}
yes_if() { if "$@" >/dev/null 2>&1; then echo yes; else echo no; fi; }

# A copy of the template, so install.sh's own worktree-refusal guard never fires (it
# inspects its own dirname's .git, and this copy has none). Same shape as
# index-ignore-restamp.test.sh.
TPL="$TMP/tpl"; mkdir -p "$TPL"
( cd "$TPLSRC" && git ls-files . ) | while IFS= read -r f; do
  [ -n "$f" ] || continue
  mkdir -p "$TPL/$(dirname "$f")"; cp "$TPLSRC/$f" "$TPL/$f" 2>/dev/null || true
done
chmod +x "$TPL/plugin/scripts/init-bundle.sh" "$TPL"/plugin/scripts/*.sh 2>/dev/null || true

ignored() { # <dir> <path> -> yes if git says the path is ignored there
  ( cd "$1" && git init -q . >/dev/null 2>&1 || true; git check-ignore -q "$2" ) \
    && echo yes || echo no
}

# =======================================================================================
echo "== 1. seed/.gitignore does not ignore board.html =="
# =======================================================================================
# The seed file is the contract for every instance stamped from now on. Checked through
# git rather than by grepping the file: a `board.html` line could return in a form the
# grep missed, and only git decides what git tracks.
SEEDED="$TMP/seeded"; mkdir -p "$SEEDED"
cp "$TPL/plugin/seed/.gitignore" "$SEEDED/.gitignore"
: > "$SEEDED/board.html"
ok "a repo seeded from seed/ does NOT ignore board.html" "$(ignored "$SEEDED" board.html)" no
# The neighbours must keep their ignores — dropping one line must not have dropped three.
: > "$SEEDED/SNAPSHOT.json"; mkdir -p "$SEEDED/.board-live"; : > "$SEEDED/.board-live/board.html"
ok "…SNAPSHOT.json is still ignored"                     "$(ignored "$SEEDED" SNAPSHOT.json)" yes
ok "…and .board-live/board.html still is too"            "$(ignored "$SEEDED" .board-live/board.html)" yes

# =======================================================================================
echo "== 2. install.sh migrates an instance stamped while board.html was ignored =="
# =======================================================================================
# A stamp, then the OLD ignore line put back by hand — this is the shape every existing
# instance is in right now, and it must not be simulated away.
LEGACY="$TMP/legacy"; mkdir -p "$LEGACY"
bash "$TPL/plugin/scripts/init-bundle.sh" "$LEGACY" >"$TMP/outL1" 2>&1
printf '\n# derived board snapshot (legacy comment)\nSNAPSHOT.json\nboard.html\n' >> "$LEGACY/.gitignore"
: > "$LEGACY/board.html"
ok "the legacy shape really does ignore board.html first" "$(ignored "$LEGACY" board.html)" yes

bash "$TPL/plugin/scripts/init-bundle.sh" "$LEGACY" >"$TMP/outL2" 2>&1
ok "a re-stamp appends the un-ignore"        "$(yes_if grep -qxF '!/board.html' "$LEGACY/.gitignore")" yes
ok "…and git now reports board.html as NOT ignored"      "$(ignored "$LEGACY" board.html)" no
# The migration must never remove a line from a live instance's .gitignore.
ok "…the human's old line is left in place"  "$(yes_if grep -qxF 'board.html' "$LEGACY/.gitignore")" yes

bash "$TPL/plugin/scripts/init-bundle.sh" "$LEGACY" >"$TMP/outL3" 2>&1
ok "a THIRD stamp appends nothing (idempotent)" \
  "$(grep -cxF '!/board.html' "$LEGACY/.gitignore")" 1
ok "…and board.html is still not ignored"                "$(ignored "$LEGACY" board.html)" no

# A freshly seeded instance has no `board.html` line, so there is nothing to un-ignore
# and the migration must stay quiet — an unconditional append would put a negation into
# every new instance for no reason.
FRESH="$TMP/fresh"; mkdir -p "$FRESH"
bash "$TPL/plugin/scripts/init-bundle.sh" "$FRESH" >"$TMP/outF1" 2>&1
ok "a fresh stamp appends NO un-ignore"      "$(grep -cxF '!/board.html' "$FRESH/.gitignore")" 0
ok "…and board.html is not ignored there either"         "$(ignored "$FRESH" board.html)" no

# =======================================================================================
echo "== 3. THE CROSS-BUNDLE LEAK: --out board.html . renders THIS instance only =="
# =======================================================================================
BB="$TPL/plugin/scripts/build-board.sh"
snap() { # <dir> <slug> <unique title>
  cat > "$1/SNAPSHOT.json" <<JSON
{
  "_schema": "ai-bridge board snapshot v1",
  "group": "$2-group",
  "generated_at": "2026-09-02T00:00:00Z",
  "counts": {"projects": 1, "tasks": 1, "awaiting": 0},
  "projects": [
    {
      "slug": "$2", "title": "$3", "description": "fixture", "kind": "build",
      "status": "active", "autonomy": "gated", "owner": "",
      "awaiting_close": false,
      "phase_progress": {"done": 0, "total": 1},
      "phases": [{"title": "phase one", "order": 1, "status": "active"}],
      "tasks": [{"id": "task-001", "title": "$3 task", "kind": "build",
                 "status": "ready", "assignee": "software-engineer", "in_flight": false,
                 "awaiting": "", "open_questions": 0, "open_question_ids": [],
                 "advisor_notes": 0, "depends_on": [], "pr": ""}],
      "deliverable_paths": []
    }
  ]
}
JSON
}
MINE="$TMP/mine"; OTHER="$TMP/other"; mkdir -p "$MINE" "$OTHER"
snap "$MINE"  mine-slug  ZZMINEPROJECTZZ
snap "$OTHER" other-slug ZZOTHERPROJECTZZ
# The hazard's own precondition: boardInstances naming a SIBLING bundle. This is the
# ordinary configuration on a machine with more than one bundle, not a contrived one.
cat > "$MINE/instance.config.json" <<JSON
{ "group": "mine-group", "board": true, "boardInstances": ["$MINE", "$OTHER"] }
JSON

( cd "$MINE" && bash "$BB" --standalone --out board.html . ) >"$TMP/out-scoped" 2>&1
ok "scoped render writes the file"          "$(yes_if test -s "$MINE/board.html")" yes
ok "…and it carries THIS instance's project" "$(yes_if grep -q ZZMINEPROJECTZZ "$MINE/board.html")" yes
ok "…and NOT the sibling bundle's project"   "$(yes_if grep -q ZZOTHERPROJECTZZ "$MINE/board.html")" no

# The other half, and it is not decoration: without it this section passes on a fixture
# whose sibling stopped rendering for an unrelated reason, which would make the assertion
# above vacuous. A bare render MUST still pull the sibling in.
( cd "$MINE" && bash "$BB" --standalone --out bare.html ) >"$TMP/out-bare" 2>&1
ok "a BARE render still reaches boardInstances (fixture is live)" \
  "$(yes_if grep -q ZZOTHERPROJECTZZ "$MINE/bare.html")" yes

# =======================================================================================
echo "== 4. the tick's own instructions carry both rules =="
# =======================================================================================
# Text checks, because the tick is a document an agent reads and there is nothing else to
# execute. Kept to the two strings that are load-bearing: the scoped render (a missing `.`
# is the leak above) and the commit (without it nothing is ever published).
PM="$TPL/plugin/agents/project-manager.md"
ok "project-manager.md exists"                          "$(yes_if test -f "$PM")" yes
ok "…names the SCOPED render"    "$(yes_if grep -qF -- '--standalone --out board.html .' "$PM")" yes
ok "…names the commit step"      "$(yes_if grep -qF -- 'commit-as.sh project-manager "chore: refresh board.html" -- board.html' "$PM")" yes
ok "…and still names the live render it does NOT commit" \
  "$(yes_if grep -qF -- '--out .board-live/board.html' "$PM")" yes
# The launcher's standing facts are what a human reads to know what the loop does.
SK="$TPL/plugin/skills/dispatch/SKILL.md"
ok "the dispatch skill names the tracked board" \
  "$(yes_if grep -qF -- '--standalone --out board.html .' "$SK")" yes

# =======================================================================================
echo "== 5. THE SAME BOUNDARY ON THE ARTIFACT PATH: /ai-bridge:board publishes =="
# =======================================================================================
# WHY THIS SECTION EXISTS ALONGSIDE SECTION 3 RATHER THAN INSTEAD OF IT. Section 3 renders
# `--standalone --out board.html .` — the tick's tracked page, whose audience is the repo's
# permission list. `/ai-bridge:board` renders the SAME script with the SAME trailing `.`
# but WITHOUT `--standalone`, because the artifact host supplies the wrapper — a different
# invocation, and an invocation is what the scoping lives in. A guard asserted only against
# the flag combination the tick happens to use would go green on a publish path that
# dropped the `.`, and that page's audience is whoever holds the URL rather than whoever
# holds a clone. So the boundary is asserted against the bytes the publish step reads.
ABASE="$TMP/artifact"; AMINE="$ABASE/mine"; AOTHER="$ABASE/other"
mkdir -p "$AMINE" "$AOTHER"
snap "$AMINE"  mine-slug  ZZMINEPROJECTZZ
snap "$AOTHER" other-slug ZZOTHERPROJECTZZ
# A config carrying one planted literal of each kind the publish criterion names. Every one
# is a real key of a real instance config, and NONE is in the snapshot's field allowlist —
# so any of them reaching the page means the renderer found a route back to the bundle that
# the allowlist never cleared.
#
# `ownerGithubUser` MATCHES `defaultOwner` ON PURPOSE, and it is not decoration: the page is
# per owner, so a project with an empty `owner` resolves to `defaultOwner`, and if that is
# not this clone's login the project sinks into the collapsed other-owners section — which
# reads TRACKED task documents at HEAD, of which this fixture has none. The project would
# then be absent for a reason that has nothing to do with scoping, and the leak assertion
# below would pass vacuously on an empty page.
cat > "$AMINE/instance.config.json" <<JSON
{ "group": "mine-group", "board": true,
  "boardInstances": ["$AMINE", "$AOTHER"],
  "org": "ZZORGLITERALZZ",
  "defaultRepo": "ZZREPOLITERALZZ",
  "defaultOwner": "ZZPERSONLITERALZZ",
  "ownerGithubUser": "ZZPERSONLITERALZZ",
  "authorEmail": "ZZEMAILLITERALZZ@example.com",
  "reposRoot": "/tmp/ZZPATHLITERALZZ",
  "people": { "ZZPERSONLITERALZZ": "ZZEMAILLITERALZZ@example.com" } }
JSON

( cd "$AMINE" && bash "$BB" --out artifact-body.html . ) >"$TMP/out-art" 2>&1
ok "the artifact render writes a body"       "$(yes_if test -s "$AMINE/artifact-body.html")" yes
ok "…and it carries THIS instance's project" "$(yes_if grep -q ZZMINEPROJECTZZ "$AMINE/artifact-body.html")" yes
ok "…and NOT the sibling bundle's project"   "$(yes_if grep -q ZZOTHERPROJECTZZ "$AMINE/artifact-body.html")" no
# The same two-sided shape section 3 uses, and for the same reason: without it the
# assertion above passes on a fixture whose sibling had quietly stopped rendering.
( cd "$AMINE" && bash "$BB" --out bare-artifact.html ) >"$TMP/out-art-bare" 2>&1
ok "a BARE artifact render still reaches boardInstances (fixture is live)" \
  "$(yes_if grep -q ZZOTHERPROJECTZZ "$AMINE/bare-artifact.html")" yes

# ONE LITERAL AT A TIME, NAMED IN THE FAILURE. Checked over the SCOPED page, which is the
# one that gets published.
for lit in ZZORGLITERALZZ ZZREPOLITERALZZ ZZPERSONLITERALZZ ZZEMAILLITERALZZ ZZPATHLITERALZZ; do
  ok "no $lit in the published page" \
    "$(yes_if grep -q "$lit" "$AMINE/artifact-body.html")" no
done
# The bundle's own absolute path is a path literal too, and the one a renderer is most
# likely to embed by accident — it is an argument to the command that produced the page.
ok "…nor the instance's own absolute path" "$(yes_if grep -qF "$AMINE" "$AMINE/artifact-body.html")" no

# NON-VACUITY, and it is the assertion that makes the six above mean something. "No literal
# appears" is satisfied by a renderer that emits nothing at all, so a REPO NAME the snapshot
# DOES allow — inside a PR link, which is on the documented carried list — must still reach
# the page. It is the same kind of literal as `defaultRepo` above and the opposite verdict,
# which is exactly the distinction the criterion draws: what the allowlist cleared travels,
# what it never cleared does not.
python3 - "$AMINE/SNAPSHOT.json" <<'PYALLOW' 2>/dev/null || true
import json, sys
d = json.load(open(sys.argv[1]))
d["projects"][0]["tasks"][0]["prs"] = [
    {"repo": "o/ZZALLOWEDREPOZZ", "number": 7,
     "url": "https://example.com/o/ZZALLOWEDREPOZZ/pull/7"}]
json.dump(d, open(sys.argv[1], "w"))
PYALLOW
( cd "$AMINE" && bash "$BB" --out allowed.html . ) >"$TMP/out-art-allowed" 2>&1
ok "an ALLOWED repo name inside a PR link does render (the scan is not vacuous)" \
  "$(yes_if grep -q ZZALLOWEDREPOZZ "$AMINE/allowed.html")" yes
ok "…while the config's defaultRepo still does not" \
  "$(yes_if grep -q ZZREPOLITERALZZ "$AMINE/allowed.html")" no

# =======================================================================================
echo "== 6. the skill and the tick each carry their half of the publish contract =="
# =======================================================================================
# Text checks, because both are documents an agent reads. Kept to the strings that are
# load-bearing: the scoped render on the skill's side (a missing `.` is the leak above),
# and on the tick's side the fact that it does NOT publish — measured, not assumed.
SK_BOARD="$TPL/plugin/skills/board/SKILL.md"
ok "the board skill ships"                              "$(yes_if test -f "$SK_BOARD")" yes
ok "…and names the SCOPED artifact render" \
  "$(yes_if grep -qF -- 'scripts/build-board.sh --out .board-live/artifact-body.html .' "$SK_BOARD")" yes
ok "…and never writes the tracked board.html" \
  "$(yes_if grep -qF -- '--out board.html' "$SK_BOARD")" no
ok "the tick tells the human what refreshes the published page" \
  "$(yes_if grep -qF -- 'run /ai-bridge:board to refresh' "$PM")" yes

printf '\nboard-in-repo.test: pass=%d fail=%d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
