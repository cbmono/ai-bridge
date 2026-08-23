#!/usr/bin/env bash
#
# artifact-board.test.sh — `scripts/build-board.sh --layout table` renders an Artifact
# page BODY, from the snapshot only, and leaks nothing the snapshot does not carry.
#
# WHY THIS EXISTS SEPARATELY from board-renderers.test.sh: this LAYOUT targets a
# different medium. The other renderers write a terminal table or a standalone HTML
# file; this one writes a fragment the artifact host wraps in
# <!doctype>/<html>/<head>/<body>. So the assertion that matters most here is the one no
# other harness makes — that the output carries NONE of those tags. A page that ships
# them gets double-nested.
#
# It was its own SCRIPT (`build-artifact-board.sh`) until the two HTML renderers were
# consolidated behind `--layout`; every assertion below is the one it made then, run
# against the surviving entry point. Nothing was dropped in the move, which is the whole
# point of keeping this file rather than folding it into another one.
#
# The escaping assertions are not duplicated effort either. Escaping is per MEDIUM: the
# terminal renderer guards ESC and newline, this one guards `<`, `&` and `"` in an
# attribute, because every button carries untrusted title text in a data- attribute.
#
# Fixtures are hand-written SNAPSHOT.json files rather than write-snapshot.sh output:
# this harness is about the RENDERER, and building the input by hand is what lets it
# assert on forms the live instance does not currently contain.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
# Every render below passes `--layout table` explicitly: the DEFAULT is `columns`, so a
# missing flag would assert the table layout's properties against the kanban page.
GEN="$REPO/symlink/scripts/build-board.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/artboard.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
assert() { if [[ "$2" == 0 ]]; then printf '  PASS  %s\n' "$1"; pass=$((pass+1));
           else printf '  FAIL  %s\n' "$1"; fail=$((fail+1)); fi; }
yes_if() { if "$@" >/dev/null 2>&1; then echo 0; else echo 1; fi; }
fhas()   { grep -qF -- "$1" "$2" && echo 0 || echo 1; }
fhasnt() { grep -qF -- "$1" "$2" && echo 1 || echo 0; }
eq()     { [[ "$1" == "$2" ]] && echo 0 || echo 1; }

# Planted strings. Each must never appear in the page: the snapshot does not carry the
# fields they would come from, so their presence would mean the renderer invented a path
# back to the bundle.
HOSTILE='Rename <script>alert(1)</script> & "quote" it'

mk() { # <dir> <group> <json-projects>
  mkdir -p "$1"
  cat > "$1/SNAPSHOT.json" <<JSON
{"_schema":"ai-bridge board snapshot v1","group":"$2",
 "generated_at":"2026-08-23T12:00:00Z","counts":{"projects":1,"tasks":1,"awaiting":0},
 "projects":$3}
JSON
}

# ---- a live project, a finished one, and every affordance ------------------
mk "$TMP/alpha" "alpha" '[
 {"slug":"live-one","title":"Live work","kind":"build","status":"active","autonomy":"gated",
  "awaiting_close":false,"phase_progress":{"done":1,"total":3},
  "tasks":[
    {"id":"task-001","title":"First","status":"in-progress","assignee":"software-engineer",
     "awaiting":"","open_questions":0,"advisor_notes":0,"depends_on":[],"in_flight":true,
     "prs":[{"repo":"o/r","number":41,"url":"https://github.com/o/r/pull/41"}]},
    {"id":"task-002","title":"HOSTILE_TITLE","status":"draft","assignee":"",
     "awaiting":"approve","open_questions":0,"advisor_notes":2,
     "depends_on":["task-001"],"in_flight":false,"prs":[]},
    {"id":"task-003","title":"Third","status":"ready","assignee":"qa-reviewer",
     "awaiting":"","open_questions":2,"advisor_notes":0,
     "depends_on":["task-001","task-002"],"in_flight":false,"prs":[],
     "open_question_text":["Q1 body?","advisor: escalated one?"]}]},
 {"slug":"all-done","title":"Finished work","kind":"build","status":"active",
  "awaiting_close":true,"phase_progress":{"done":2,"total":2},
  "tasks":[{"id":"task-001","title":"Done","status":"done","assignee":"","awaiting":"",
            "open_questions":0,"advisor_notes":0,"depends_on":[],"in_flight":false,"prs":[]}]}]'
# substitute the hostile title without fighting JSON quoting in the heredoc
python3 - "$TMP/alpha/SNAPSHOT.json" "$HOSTILE" <<'PYS'
import json, sys
p, hostile = sys.argv[1], sys.argv[2]
d = json.load(open(p))
for pr in d["projects"]:
    for t in pr["tasks"]:
        if t["title"] == "HOSTILE_TITLE":
            t["title"] = hostile
json.dump(d, open(p, "w"))
PYS

OUT="$TMP/page.html"
rc=0; bash "$GEN" --layout table --out "$OUT" "$TMP/alpha" >/dev/null 2>&1 || rc=$?
assert "it renders and exits 0"                      "$(eq "$rc" 0)"
assert "…and wrote the page"                         "$(yes_if test -s "$OUT")"

echo "== it is a page BODY, not a document =="
for tag in '<!doctype' '<!DOCTYPE' '<html' '<head>' '<body' '</body' '</html'; do
  assert "no $tag"                                   "$(fhasnt "$tag" "$OUT")"
done

echo "== the title names the workspace =="
assert "group becomes the title"                     "$(fhas '<title>Alpha Bridge Board</title>' "$OUT")"

echo "== projects are collapsed, and finished ones sink =="
assert "three <details>, none open"                  "$(fhasnt '<details class="proj" open' "$OUT")"
assert "a finished project is marked"                "$(fhas 'done-tag' "$OUT")"
assert "…under a Finished divider"                   "$(fhas 'class="sep"' "$OUT")"
assert "…and it sorts AFTER the live one"            "$(yes_if python3 -c "
import sys; h=open('$OUT').read()
sys.exit(0 if h.index('Live work') < h.index('Finished work') else 1)")"

echo "== untrusted title text is escaped for THIS medium =="
assert "no raw <script> survives"                    "$(fhasnt '<script>alert(1)</script>' "$OUT")"
assert "…the tag is entity-escaped"                  "$(fhas '&lt;script&gt;' "$OUT")"
assert "…and a quote inside an attribute is escaped" "$(fhasnt 'data-copy="Rename <' "$OUT")"

echo "== references are short, and never a real path =="
assert "a task ref drops projects/"                  "$(fhasnt 'data-copy="projects/' "$OUT")"
assert "…and drops .md"                              "$(fhasnt '.md"' "$OUT")"
assert "…and keeps <project>/tasks/<id>"             "$(fhas 'live-one/tasks/task-001' "$OUT")"

echo "== depends_on shows the NUMBER only =="
assert "a single dependency renders 001"             "$(fhas '>001</button>' "$OUT")"
assert "…two render as a pair"                       "$(fhas '>002</button>' "$OUT")"
assert "…never the full slug"                        "$(fhasnt '>task-001-<' "$OUT")"

echo "== questions =="
assert "a Qn handle exists per question"             "$(fhas 'Q2: ' "$OUT")"
assert "carried question text is shown"              "$(fhas 'Q1 body?' "$OUT")"
assert "an escalated concern says where it came from" "$(fhas 'could not settle it' "$OUT")"
assert "…and the advisor: marker is stripped"        "$(fhasnt 'Q2: advisor:' "$OUT")"
assert "a question on a READY task reaches the rail" "$(fhas 'class="verb">question' "$OUT")"

echo "== advisor_notes is information, not a demand =="
assert "an untriaged concern shows as a concern pill" "$(fhas 'concern' "$OUT")"
assert "…and never as an awaiting verb"              "$(fhasnt 'class="verb">advisor' "$OUT")"

echo "== a PR is a real link =="
assert "PR links to GitHub"                          "$(fhas 'href="https://github.com/o/r/pull/41"' "$OUT")"
assert "…and opens safely"                           "$(fhas 'rel="noopener noreferrer"' "$OUT")"

echo "== both themes are defined on bare :root =="
assert "no token defined only in a media/theme block" "$(yes_if python3 -c "
import re,sys
css=open('$OUT').read()
root=set(re.findall(r'--([a-z0-9-]+)\s*:', re.search(r':root\{(.*?)\}', css, re.S).group(1)))
allt=set(re.findall(r'--([a-z0-9-]+)\s*:', css))
sys.exit(0 if not (allt-root) else 1)")"
assert "body paints its own background"               "$(fhas 'background:var(--ground)' "$OUT")"

echo "== absence is safe =="
mkdir -p "$TMP/nosnap"
rc2=0; bash "$GEN" --layout table --out "$TMP/none.html" "$TMP/nosnap" >/dev/null 2>&1 || rc2=$?
assert "an instance with no snapshot exits 0"        "$(eq "$rc2" 0)"
assert "…and writes nothing"                         "$(fhasnt x "$TMP/none.html" 2>/dev/null || echo 0)"

echo "== one drifted instance must not blank the board =="
mkdir -p "$TMP/bad"; printf 'not json at all\n' > "$TMP/bad/SNAPSHOT.json"
rc3=0; bash "$GEN" --layout table --out "$TMP/mixed.html" "$TMP/bad" "$TMP/alpha" >/dev/null 2>&1 || rc3=$?
assert "a broken snapshot is skipped, not fatal"     "$(eq "$rc3" 0)"
assert "…and the good instance still renders"        "$(fhas 'Alpha Bridge Board' "$TMP/mixed.html")"
assert "…and it is a VISIBLE note, not a silent absence" "$(fhas 'Unreadable snapshot' "$TMP/mixed.html")"
assert "…naming the instance by directory NAME"      "$(fhas 'bad/SNAPSHOT.json' "$TMP/mixed.html")"
assert "…and never by its path"                      "$(fhasnt "$TMP/bad" "$TMP/mixed.html")"
# THE OTHER HALF, and the one this layout did not have before the consolidation: valid
# JSON carrying wrong TYPES. `"tasks":"three"` parses, so nothing above catches it — the
# string was then iterated as a list of task dicts and `.get` raised AttributeError,
# which meant NO FILE WAS WRITTEN AT ALL. One drifted instance blanked the published
# board for every healthy one. Measured against the pre-consolidation script; it is why
# both layouts now share one toint()/tolist()/todict() path.
mkdir -p "$TMP/drift"
drift_case() { # <label> <snapshot json>
  printf '%s\n' "$2" > "$TMP/drift/SNAPSHOT.json"
  # Removed first: a page left behind by the previous case would satisfy the
  # "still renders" half even if this case wrote nothing at all.
  rm -f "$TMP/drift.html"
  local rc=0 out
  out="$(bash "$GEN" --layout table --out "$TMP/drift.html" "$TMP/alpha" "$TMP/drift" 2>&1)" || rc=$?
  assert "$1: exits 0"                           "$(eq "$rc" 0)"
  assert "$1: no traceback"                      "$(printf '%s\n' "$out" | grep -qF Traceback && echo 1 || echo 0)"
  # alpha's own project, not the page title: with two instances on the board the title
  # is the generic "Bridge Board", so asserting on it would prove nothing about alpha.
  assert "$1: the healthy instance still renders" "$(fhas 'Live work' "$TMP/drift.html")"
}
drift_case "tasks is not a list" \
  '{"group":"drift","counts":{"tasks":1},"projects":[{"slug":"p","title":"Drifted","status":"active","tasks":"three"}]}'
drift_case "projects is not a list" \
  '{"group":"drift","counts":{"tasks":"many"},"projects":"lots"}'
drift_case "a non-numeric phase total" \
  '{"group":"drift","counts":{"tasks":1},"projects":[{"slug":"p","title":"Drifted","status":"active","phase_progress":{"total":"two","done":"one"},"tasks":[]}]}'
drift_case "a task is a string, not an object" \
  '{"group":"drift","counts":{"tasks":1},"projects":[{"slug":"p","title":"Drifted","status":"active","tasks":["oops"]}]}'
# A NUMERIC task id, on a task the decision rail renders. Found by reading this diff, not
# by any of the cases above: the rail concatenated the id with a string, so `"id": 5`
# raised TypeError and wrote no file at all — the same one-instance-blanks-the-board
# failure, reached through the one field that was still handled raw.
drift_case "a task id is a number" \
  '{"group":"drift","counts":{"tasks":1},"projects":[{"slug":"p","title":"Drifted","status":"active","tasks":[{"id":5,"title":"numeric id","status":"draft","awaiting":"approve","open_questions":0}]}]}'
rm -rf "$TMP/drift"

echo "== an absurd question count cannot render forever =="
# toint() cannot catch this one: the type is right and the value is absurd. A button per
# question means a nine-digit count renders for hours and produces a page nobody can
# open, so the count is capped. Runs with a timeout because the failure mode IS the hang.
mk "$TMP/manyq" "manyq" '[
 {"slug":"p","title":"Question flood","kind":"build","status":"active","awaiting_close":false,
  "phase_progress":{"done":0,"total":0},
  "tasks":[{"id":"task-001","title":"Absurd count","status":"draft","assignee":"",
            "awaiting":"answer","open_questions":900000000,"advisor_notes":0,
            "depends_on":[],"in_flight":false,"prs":[]}]}]'
QOUT="$TMP/manyq.html"
qrc=0
( bash "$GEN" --layout table --out "$QOUT" "$TMP/manyq" >/dev/null 2>&1 ) &
qpid=$!
for _ in $(seq 1 30); do kill -0 "$qpid" 2>/dev/null || break; sleep 1; done
if kill -0 "$qpid" 2>/dev/null; then kill -9 "$qpid" 2>/dev/null; qrc=1; fi
wait "$qpid" 2>/dev/null || true
assert "the page renders instead of hanging"         "$(eq "$qrc" 0)"
assert "…and it was written"                         "$(yes_if test -s "$QOUT")"
assert "…with the first question handle"             "$(fhas 'Q1</button>' "$QOUT")"
assert "…and the count capped, not unbounded"        "$(fhasnt 'Q25</button>' "$QOUT")"

echo "== a PR URL is a link only on http/https, here too =="
mk "$TMP/hostile" "hostile" '[
 {"slug":"p","title":"Scheme check","kind":"build","status":"active","awaiting_close":false,
  "phase_progress":{"done":0,"total":0},
  "tasks":[{"id":"task-001","title":"Two PRs, one hostile","status":"in-review","assignee":"",
            "awaiting":"","open_questions":0,"advisor_notes":0,"depends_on":[],"in_flight":false,
            "prs":[{"repo":"o/r","number":41,"url":"https://github.com/o/r/pull/41"},
                   {"repo":"o/r","number":9,"url":"javascript:alert(1)"}]}]}]'
OUT2="$TMP/scheme.html"
bash "$GEN" --layout table --out "$OUT2" "$TMP/hostile" >/dev/null 2>&1
# The other rule this layout did not carry: it wrote the snapshot's URL straight into
# the href, so a `javascript:` PR URL became a live link on a page meant for publishing.
assert "a javascript: URL is never an href"          "$(fhasnt 'href="javascript:' "$OUT2")"
assert "…and is inert text instead"                  "$(fhas 'link withheld: not http/https' "$OUT2")"
assert "…while the http PR link beside it still works" "$(fhas 'href="https://github.com/o/r/pull/41"' "$OUT2")"

echo "== flags =="
assert "an unknown flag is refused"                  "$(yes_if bash -c "bash '$GEN' --nope 2>/dev/null; [ \$? -eq 2 ]")"
assert "--help prints the header"                    "$(yes_if bash -c "bash '$GEN' --help 2>&1 | grep -q 'Artifact page body'")"

echo "== --layout picks the markup, and refuses to guess =="
# The consolidation's contract. `columns` is the DEFAULT so that no existing caller
# changed when the second script was deleted; an unknown value must refuse rather than
# fall back, because falling back would publish the wrong page silently.
assert "an unknown layout exits 2"                   "$(yes_if bash -c "bash '$GEN' --layout kanban --out '$TMP/x.html' '$TMP/alpha' 2>/dev/null; [ \$? -eq 2 ]")"
assert "…naming both layouts on stderr"              "$(yes_if bash -c "bash '$GEN' --layout kanban --out '$TMP/x.html' '$TMP/alpha' 2>&1 >/dev/null | grep -q 'columns|table'")"
assert "…and writes no page"                         "$(fhasnt x "$TMP/x.html" 2>/dev/null || echo 0)"
assert "--layout with no value exits 2"              "$(yes_if bash -c "bash '$GEN' --layout 2>/dev/null; [ \$? -eq 2 ]")"
bash "$GEN" --layout=table --out "$TMP/eq.html" "$TMP/alpha" >/dev/null 2>&1
assert "--layout=table is the same page as --layout table" "$(yes_if cmp -s "$TMP/eq.html" "$OUT")"
DEF="$TMP/default.html"
bash "$GEN" --out "$DEF" "$TMP/alpha" >/dev/null 2>&1
assert "the default layout is columns — the kanban strip"  "$(fhas 'class="cols"' "$DEF")"
assert "…not the table's decision rail"                    "$(fhasnt 'class="rail"' "$DEF")"
assert "…and it is what --layout columns emits"            "$(yes_if bash -c "bash '$GEN' --layout columns --out '$TMP/cols.html' '$TMP/alpha' >/dev/null 2>&1; cmp -s '$TMP/cols.html' '$DEF'")"

echo "== --standalone is orthogonal to --layout: wrapping, not markup =="
SA="$TMP/sa.html"
bash "$GEN" --layout table --standalone --out "$SA" "$TMP/alpha" >/dev/null 2>&1
assert "the table layout can be standalone too"      "$(yes_if sh -c 'head -1 "$1" | grep -qF "<!doctype html>"' _ "$SA")"
assert "…with exactly one <body>"                    "$(eq "$(grep -cF '<body>' "$SA")" 1)"
assert "…the <style> in <head> and the board in <body>" "$(yes_if python3 -c "
import sys
t=open('$SA').read()
head=t[t.index('<head>'):t.index('</head>')]
body=t[t.index('<body>'):t.index('</body>')]
sys.exit(0 if '<style>' in head and 'class=\"board\"' in body and '<h1>' not in head else 1)")"
assert "…and the same markup as the page body"       "$(fhas 'class="rail"' "$SA")"

echo "== there is only ONE HTML renderer now =="
assert "build-artifact-board.sh is gone"             "$(yes_if test ! -e "$REPO/symlink/scripts/build-artifact-board.sh")"
# The runnable form, not the name: build-board.sh's own header still explains what was
# merged into it, and a comment recording that is not a caller.
assert "…and no machinery still tells anyone to run it" "$(yes_if bash -c "! grep -rlF scripts/build-artifact-board '$REPO/symlink' >/dev/null 2>&1")"

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
