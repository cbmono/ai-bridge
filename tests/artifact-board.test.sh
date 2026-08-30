#!/usr/bin/env bash
#
# artifact-board.test.sh — `scripts/build-board.sh` renders an Artifact page BODY, from
# the snapshot only, and leaks nothing the snapshot does not carry.
#
# WHY THIS EXISTS SEPARATELY from board-renderers.test.sh: this renderer targets a
# different medium. The other renderers write a terminal table or a standalone HTML
# file; this one writes a fragment the artifact host wraps in
# <!doctype>/<html>/<head>/<body>. So the assertion that matters most here is the one no
# other harness makes — that the output carries NONE of those tags. A page that ships
# them gets double-nested.
#
# It was its own SCRIPT (`build-artifact-board.sh`) until the two HTML renderers were
# consolidated behind `--layout`, and became the only one when the kanban `columns`
# layout was deleted; every assertion below is the one it made as a separate script, run
# against the surviving entry point. Nothing was dropped in either move, which is the
# whole point of keeping this file rather than folding it into another one.
#
# THE FLAG IS GONE, AND ITS ABSENCE IS ASSERTED HERE. `--layout` chose between this page
# and a kanban `columns` one; the owner rejected `columns` as unreadable, so it was
# deleted rather than defaulted away. Two consequences are pinned below: the script
# refuses `--layout` BY NAME (a stale caller must fail loudly, never render silently),
# and NO tracked file in this repo invokes build-board.sh with it — checked over every
# tracked file rather than just symlink/, because README.md and docs/ were the half that
# rotted last time (see the retired-renderer block at the bottom of this file).
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
# No render below passes a layout flag: there is one page, and `--layout` now exits 2
# rather than selecting anything.
GEN="$REPO/symlink/scripts/build-board.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/artboard.XXXXXX")" || {
  echo "artifact-board.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp} — create that directory first." >&2; exit 2; }
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
rc=0; bash "$GEN" --out "$OUT" "$TMP/alpha" >/dev/null 2>&1 || rc=$?
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

# ---------------------------------------------------------------------------
# THE COLLAPSED VIEW HAS TO ANSWER "WHICH PROJECTS NEED ME?" ON ITS OWN.
#
# The pooled queue that used to sit above every project moved INSIDE each project on
# 2026-08-30. That move is only safe if the summary line carries the weight the pooled
# list used to carry, and this is the block that says so: sixteen closed rows with the
# queues hidden inside them and no marking is strictly worse than the clutter it
# replaced. Three channels are asserted separately, because each covers a reader the
# others do not — the COUNT (a number, for anyone), the MARKED CARD (a shape, for a
# reader skimming rather than reading) and the ORDER (colour-free, for a reader who
# cannot see the chip at all, or a phone showing four rows at a time). A test on only
# the chip would pass a page whose entire signal is one colour nobody can see.
#
# The fixture lists the quiet project FIRST in the snapshot, so the order assertion
# fails if the sort is dropped rather than passing on the input's own order.
#
# ONE BOUNDARY RULE for every "inside this project's card" assertion below, and it is
# not `t.index('</details>', i)`. A card can now contain NESTED <details> — every rail
# item is one — so that slice stops at the first ASK rather than at the end of the
# project, and an assertion cut that way reads a few hundred bytes and reports green on
# a page that is wrong immediately after them. A card ends where the NEXT card begins.
card() { # <file> <project title> -> just that project's card, on stdout
  python3 - "$1" "$2" <<'PYC'
import sys
t = open(sys.argv[1], encoding="utf-8").read()
i = t.index(sys.argv[2])
j = t.find('<details class="proj', i)
sys.stdout.write(t[i:] if j < 0 else t[i:j])
PYC
}
fhas_in()   { grep -qF -- "$1" && echo 0 || echo 1; }
fhasnt_in() { grep -qF -- "$1" && echo 1 || echo 0; }
before_in() { # <a> <b> — 0 when a appears before b on stdin
  python3 -c "
import sys
t = sys.stdin.read()
try:
    sys.exit(0 if t.index(sys.argv[1]) < t.index(sys.argv[2]) else 1)
except ValueError:
    sys.exit(1)" "$1" "$2" && echo 0 || echo 1
}
mkdir -p "$TMP/board15/projects/quiet" "$TMP/board15/projects/wants-me" \
         "$TMP/board15/projects/nostamp"
mk "$TMP/board15" "board15" '[
 {"slug":"quiet","title":"Nothing waiting","kind":"build","status":"active","autonomy":"gated",
  "awaiting_close":false,"phase_progress":{"done":0,"total":0},
  "tasks":[{"id":"task-001","title":"Just working","status":"in-progress",
            "assignee":"software-engineer","awaiting":"","open_questions":0,
            "advisor_notes":3,"depends_on":[],"in_flight":true,"prs":[]}]},
 {"slug":"wants-me","title":"Two decisions","kind":"build","status":"active","autonomy":"gated",
  "awaiting_close":false,"phase_progress":{"done":0,"total":0},
  "tasks":[{"id":"task-001","title":"Promote me","status":"draft","assignee":"",
            "awaiting":"approve","open_questions":0,"advisor_notes":0,"depends_on":[],
            "in_flight":false,"prs":[]},
           {"id":"task-002","title":"Merge me","status":"in-review","assignee":"",
            "awaiting":"merge","open_questions":0,"advisor_notes":0,"depends_on":[],
            "in_flight":false,"prs":[]}]},
 {"slug":"nostamp","title":"No timestamp","kind":"build","status":"active","autonomy":"gated",
  "awaiting_close":false,"phase_progress":{"done":0,"total":0},"tasks":[]},
 {"slug":"nofile","title":"No project md","kind":"build","status":"active","autonomy":"gated",
  "awaiting_close":false,"phase_progress":{"done":0,"total":0},"tasks":[]},
 {"slug":"..","title":"Hostile slug here","kind":"build","status":"active","autonomy":"gated",
  "awaiting_close":false,"phase_progress":{"done":0,"total":0},"tasks":[]}]'
printf -- '---\ntype: Project\ntitle: Nothing waiting\nstatus: active\ntimestamp: 2026-03-04T10:11:12Z   # notes at %s\n---\n' \
  "/Users/attacker/board15-secret.md" > "$TMP/board15/projects/quiet/project.md"
printf -- '---\ntype: Project\ntitle: Two decisions\nstatus: active\ntimestamp: 2026-07-21T08:00:00Z\n---\n' \
  > "$TMP/board15/projects/wants-me/project.md"
printf -- '---\ntype: Project\ntitle: No timestamp\nstatus: active\n---\n' \
  > "$TMP/board15/projects/nostamp/project.md"
# The file a `..` slug reaches if the slug is joined to a path untested. It sits one
# level ABOVE projects/, which is the whole point: nothing here may read it.
printf -- '---\ntype: Project\ntitle: Outside projects\nstatus: active\ntimestamp: 1999-12-31T00:00:00Z\n---\n' \
  > "$TMP/board15/project.md"
BOUT="$TMP/board15.html"
brc=0; bash "$GEN" --out "$BOUT" "$TMP/board15" >/dev/null 2>&1 || brc=$?

echo "== the collapsed line answers 'which projects need me?' =="
assert "the fixture renders and exits 0"             "$(eq "$brc" 0)"
# (1) THE COUNT. Two awaiting items on that project, so the chip says two — the same
# number the pooled list used to contribute for it.
assert "a project with items carries a weighted count" \
  "$(fhas '<span class="c you"><b>2</b> awaiting you</span>' "$BOUT")"
assert "…and only the project that has items carries one" \
  "$(eq "$(grep -oF 'class="c you"' "$BOUT" | wc -l | tr -d ' ')" 1)"
# (2) THE MARKED CARD. Not the same fact as the chip: the chip is one pill among six in
# a row; this is the whole card, readable at a glance from any scroll position.
assert "…and the card itself is marked"              "$(fhas '<details class="proj wants">' "$BOUT")"
assert "a project with none is NOT marked"           "$(fhas '<details class="proj"><summary' "$BOUT")"
assert "…and carries no count chip inside it"        "$(card "$BOUT" 'Nothing waiting' | fhasnt_in 'class="c you"')"
# (3) THE ORDER — the colour-free channel. The snapshot lists `quiet` first; a project
# that wants you must still come out on top, or a reader who cannot see the chip has
# nothing left.
assert "…and it sorts ABOVE a project that wants nothing" "$(yes_if python3 -c "
import sys; t=open('$BOUT').read()
sys.exit(0 if t.index('Two decisions') < t.index('Nothing waiting') else 1)")"
# NON-VACUITY for that ordering: the snapshot really does list them the other way, so
# the assertion above measures the sort rather than the input's own order.
assert "…and the snapshot really lists them the other way round" "$(yes_if python3 -c "
import json, sys
s = json.load(open('$TMP/board15/SNAPSHOT.json'))
slugs = [p['slug'] for p in s['projects']]
sys.exit(0 if slugs.index('quiet') < slugs.index('wants-me') else 1)")"

echo "== each project's queue is INSIDE it, and the pooled one is gone =="
assert "the rail moved into the project"             "$(card "$BOUT" 'Two decisions' | fhas_in 'class="rail"')"
assert "…holding only THAT project's items"          \
  "$(eq "$(card "$BOUT" 'Two decisions' | grep -oF 'class="ask"' | grep -c . || true)" 2)"
assert "…above its task table, not below it"         "$(card "$BOUT" 'Two decisions' | before_in 'class="rail"' '<table>')"
# THE POOLED LIST IS GONE, and this is how that is stated without banning `.rail`
# outright: no rail may appear before the first project card. One that survived above
# them all would sit before that index.
assert "no pooled queue above the first project"     "$(yes_if python3 -c "
import sys
t = open('$BOUT').read()
sys.exit(0 if t.index('<details class=\"proj') < t.index('class=\"rail\"') else 1)")"
assert "…replaced by one line saying where to look" \
  "$(fhas '2 waiting on you, in 1 project — marked and sorted to the top below.' "$BOUT")"

echo "== the creation date comes from project.md, and ONLY a date does =="
assert "the date renders on the collapsed line" \
  "$(fhas '<span class="pdate" title="Project created 2026-07-21">2026-07-21</span>' "$BOUT")"
assert "…for the other project too"                  "$(fhas '>2026-03-04</span>' "$BOUT")"
# ONLY A DATE. frontmatter() does not strip a trailing YAML comment off `timestamp:`,
# so the raw value still carries whatever follows it — rendering the VALUE rather than
# the matched date would put an absolute path on a page that may be published.
assert "…never the time of day"                      "$(fhasnt '10:11:12' "$BOUT")"
assert "…and never a path hidden in that line's comment" "$(fhasnt 'attacker' "$BOUT")"
assert "a project.md with no timestamp renders no date" "$(card "$BOUT" 'No timestamp' | fhasnt_in 'class="pdate"')"
assert "…and so does a project with no project.md at all" "$(card "$BOUT" 'No project md' | fhasnt_in 'class="pdate"')"
# THE SLUG IS SHAPE-CHECKED BEFORE IT IS JOINED TO A PATH, exactly as it is for a
# deliverable path. `projects/../project.md` is a read OUTSIDE projects/, and the
# fixture plants a readable file there so this fails loudly rather than vacuously.
assert "a \`..\` slug reads nothing outside projects/" "$(fhasnt '1999-12-31' "$BOUT")"
assert "…and the file it would have read really is there" \
  "$(yes_if test -s "$TMP/board15/project.md")"

echo "== the ✕ copies a command and can never close anything =="
assert "it copies /close-project <slug>"             "$(fhas 'data-copy="/close-project wants-me"' "$BOUT")"
assert "…one per well-formed project"                "$(eq "$(grep -oF 'class="pclose"' "$BOUT" | wc -l | tr -d ' ')" 4)"
assert "…and none for a slug that is not one segment" "$(card "$BOUT" 'Hostile slug here' | fhasnt_in 'class="pclose"')"
# The tooltip is a promise to the reader, and the wrong wording IS the failure: a
# control labelled "close this project" that only copies is a lie, and one that really
# closed would be a rendered page performing /close-project's consolidation, log entry
# and folder removal. Both directions are asserted.
assert "the tooltip says it COPIES"                  "$(fhas 'title="Copy the command to close this project' "$BOUT")"
assert "…and no pclose tooltip starts any other way" "$(yes_if python3 -c "
import re, sys
t = open('$BOUT').read()
btns = re.findall(r'<button class=\"pclose\"[^>]*>', t)
bad = [b for b in btns if 'title=\"Copy the command to close this project' not in b]
sys.exit(0 if btns and not bad else 1)")"
# It is a BUTTON with no href, no form and no target: there is nothing for it to
# navigate to and nothing to submit, whatever any handler does or does not do.
assert "…and it is inert markup: no href, form or target" "$(yes_if python3 -c "
import re, sys
t = open('$BOUT').read()
btns = re.findall(r'<button class=\"pclose\"[^>]*>', t)
sys.exit(0 if btns and not any(a in b for b in btns
                               for a in ('href=', 'formaction=', 'target=')) else 1)")"

echo "== …reusing the ONE clipboard helper: no second script, no second link =="
assert "still exactly one <script>"                  "$(eq "$(grep -oF '<script' "$BOUT" | wc -l | tr -d ' ')" 1)"
assert "…and still exactly two <link> elements"      "$(eq "$(grep -cF '<link' "$BOUT")" 2)"
assert "…the ✕ using the same [data-copy] convention" "$(fhas 'data-what="Close command"' "$BOUT")"
# A FAILED COPY MUST DEGRADE VISIBLY. This page is opened over file://, where a
# clipboard write can be refused, and a control that appears to copy and does not is
# worse than no control. The live behaviour was measured in a browser on that origin
# (see the PR body); what is pinned HERE is that the shipped page still carries a
# failure state that is distinct, selectable and does not fade — a three-second
# unselectable notice is the regression this guards against.
# Asserted on the RULE, not on the page: `fhas 'pointer-events:auto'` is green on any
# page that happens to carry that declaration anywhere, including on a rule that has
# nothing to do with the toast. The property has to be in `.toast.fail`'s own block, or
# the failure notice is still the unclickable, unselectable one.
toast_fail_rule() { # <file> -> the body of the `.toast.fail{...}` rule
  python3 - "$1" <<'PYT'
import re, sys
m = re.search(r"\.toast\.fail\{([^}]*)\}", open(sys.argv[1], encoding="utf-8").read())
sys.stdout.write(m.group(1) if m else "")
PYT
}
assert "the failure state is its own toast rule"     "$(toast_fail_rule "$BOUT" | fhas_in 'background:var(--stop)')"
assert "…that accepts the pointer"                   "$(toast_fail_rule "$BOUT" | fhas_in 'pointer-events:auto')"
assert "…and whose text can be selected"             "$(toast_fail_rule "$BOUT" | fhas_in 'user-select:text')"
assert "…carrying the exact text in a selectable <code>" \
  "$(fhas '.toast.fail code{' "$BOUT")"
assert "…entering a state the success path never sets" "$(fhas "el.classList.add('on','fail');" "$BOUT")"
assert "…with a dismiss control, since it never fades" "$(fhas "dismiss.className='x'" "$BOUT")"

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

echo "== a retained project's deliverables panel =="
# A hand-written SNAPSHOT.json, exactly as write-snapshot.sh would emit it for a
# `status: done` project carrying `deliverable_paths:` — this harness is about the
# RENDERER's own shape check, so the hostile entries below are ones a human could
# still hand-edit into project.md even though closeout never writes them.
mk "$TMP/delivs" "delivs" '[
 {"slug":"with-delivs","title":"Shipped review","kind":"research","status":"done",
  "autonomy":"gated","awaiting_close":false,"phase_progress":{"done":0,"total":0},
  "tasks":[],
  "deliverable_paths":["/projects/with-delivs/deliverables/report.md",
                        "/projects/with-delivs/deliverables/summary.html",
                        "/projects/with-delivs/deliverables/site/index.html",
                        "/projects/other-project/deliverables/report.md",
                        "/Users/attacker/.ssh/id_rsa",
                        "/projects/with-delivs/deliverables/../../../etc/passwd",
                        "/projects/with-delivs/deliverables/site/../../../etc/shadow",
                        "/projects/with-delivs/deliverables/report.md ]   # from /Users/attacker/notes [old]",
                        "/projects/with-delivs/deliverables/report.md /Users/attacker/Desktop/report.md",
                        "/projects/with-delivs/deliverables/see#/Users/attacker/secret",
                        "/projects/with-delivs/deliverables/report.md\n/Users/attacker/Desktop/notes.md",
                        "/projects/with-delivs\u0308/deliverables/elsewhere.md"]},
 {"slug":"..","title":"Hostile slug","kind":"research","status":"done",
  "autonomy":"gated","awaiting_close":false,"phase_progress":{"done":0,"total":0},
  "tasks":[],
  "deliverable_paths":["/projects/../deliverables/id_rsa",
                        "/projects/../../Users/attacker/deliverables/id_rsa"]},
 {"slug":"no-delivs","title":"Closed with nothing stamped","kind":"build","status":"done",
  "autonomy":"gated","awaiting_close":false,"phase_progress":{"done":0,"total":0},
  "tasks":[],"deliverable_paths":[]}]'
DOUT="$TMP/delivs.html"
rc4=0; bash "$GEN" --out "$DOUT" "$TMP/delivs" >/dev/null 2>&1 || rc4=$?
assert "a bundle-relative deliverable renders as a copy button" \
  "$(fhas 'data-copy="/projects/with-delivs/deliverables/report.md"' "$DOUT")"
assert "…labelled by filename, not the full path"    "$(fhas '>report.md</button>' "$DOUT")"
assert "…and a second one too"                        "$(fhas 'data-copy="/projects/with-delivs/deliverables/summary.html"' "$DOUT")"
assert "…reusing the existing data-what convention"   "$(fhas 'data-what="Deliverable path"' "$DOUT")"
assert "a NESTED deliverable renders too, not dropped" \
  "$(fhas 'data-copy="/projects/with-delivs/deliverables/site/index.html"' "$DOUT")"
assert "…labelled by its filename only, not its nested path" "$(fhas '>index.html</button>' "$DOUT")"
assert "the panel is titled with a count that matches what renders" \
  "$(fhas 'Deliverables · 3' "$DOUT")"
echo "== every rendered path is bundle-relative to THIS project — nothing else survives =="
assert "another project's deliverable is dropped"     "$(fhasnt 'other-project/deliverables' "$DOUT")"
assert "an absolute filesystem path is dropped"       "$(fhasnt 'attacker' "$DOUT")"
# LOOK INSIDE THE VALUE. `fhasnt 'data-copy="/Users'` only says no value BEGINS with
# /Users — and the leak this exists to catch puts the absolute path in the MIDDLE of a
# value whose first characters are a perfectly good bundle-relative prefix (a swallowed
# YAML comment, see the last fixture entry). Spelled the first way, this assertion read
# green on a page that was leaking, which is worse than not having it at all.
no_copy_value_with() { # <needle> <file>
  ! grep -o 'data-copy="[^"]*"' "$2" | grep -qF -- "$1"
}
assert "…and no /Users ANYWHERE inside a data-copy value" \
  "$(yes_if no_copy_value_with '/Users' "$DOUT")"
assert "a traversal attempt is dropped"               "$(fhasnt 'etc/passwd' "$DOUT")"
assert "a traversal attempt through a nested segment is dropped too" "$(fhasnt 'etc/shadow' "$DOUT")"
# A REAL path with a YAML trailing comment folded into it. The writer strips that comment
# before it can ever get this far (write-snapshot.sh's deliverable_path_entries), so what
# this fixture stands for is the input that never met the writer at all: SNAPSHOT.json is
# a file on disk, and this renderer reads it back without knowing who wrote it. Its prefix
# is this project's and it has no `..`, so a guard that only anchors the prefix passes it
# — and it carries an absolute path.
assert "a swallowed YAML comment is dropped, not rendered as a path" \
  "$(fhasnt 'report.md ]' "$DOUT")"
# THE VECTOR THAT NEEDS NO COMMENT AT ALL, and the reason this guard stopped listing bad
# characters and started requiring a whole shape. Two paths in one value: correct prefix,
# no `..`, no `#`, nothing on any denylist — and rendered whole it puts the publisher's
# home directory in a copy button labelled `report.md`, so the page looks right. What
# rejects it is that a deliverable path may not contain WHITESPACE, and this value does.
assert "two paths sharing one value are dropped, not rendered as one" \
  "$(fhasnt 'Desktop/report.md' "$DOUT")"
# …and the same shape with no whitespace either, which is why `#` is excluded on its own
# account and not merely as the character a comment starts with.
assert "an absolute path glued on after a # is dropped too" \
  "$(fhasnt 'deliverables/see#' "$DOUT")"
# A NEWLINE and a second path after an otherwise perfect value. This is what fullmatch()
# buys over a prefix test plus an end anchor: Python's `$` also matches just before a
# trailing newline, so "the whole value, with no remainder" has to be the match itself.
assert "a trailing remainder after a newline is dropped" \
  "$(fhasnt 'Desktop/notes.md' "$DOUT")"
# THE SLUG IS CHECKED BY THE SAME RULE AS EVERY OTHER SEGMENT. It used to be interpolated
# into the prefix and trusted, so a hand-written snapshot claiming its slug was `..` got
# `/projects/../deliverables/<file>` rendered as this project's own deliverable — the
# guard compared the value against a prefix the value itself had chosen.
assert "a hostile slug cannot render a path out of the bundle" \
  "$(fhasnt 'data-copy="/projects/../' "$DOUT")"
# THE SLUG AGAIN, THROUGH A COMBINING MARK. bundle_deliverable() strips category-M
# characters before it tests the SHAPE, so that a macOS-decomposed filename is not
# dropped. Strip them from the whole value and they come off the SLUG too: `with-delivs`
# + U+0308 reduces to `with-delivs`, the shape matches, and a button would point at a
# NEIGHBOURING project's directory while claiming to be this project's deliverable.
# What rejects it is that the slug is pinned on the ORIGINAL value, not on the stripped
# one — the mark-tolerance is bought for the filename segments only.
# Asserted with no_copy_value_with and not a whole-file `fhasnt`, for the reason this
# file already learned once: a page-wide grep is only an assertion while no OTHER
# fixture can satisfy it, and the thing being denied here is specifically a data-copy
# VALUE.
assert "a combining mark in the slug does not smuggle in another project's path" \
  "$(yes_if no_copy_value_with 'elsewhere.md' "$DOUT")"
assert "…and that project gets no deliverables panel at all" "$(yes_if python3 -c "
import sys
t = open('$DOUT').read()
i = t.index('Hostile slug')
j = t.index('</details>', i)
sys.exit(0 if 'class=\"delivs\"' not in t[i:j] else 1)")"
# Not a second `Deliverables · 3` grep — that was byte-identical to the assertion above
# and could not fail independently of it. Counting the BUTTONS is the half the heading
# cannot certify: heading and list are built from the same filtered sequence, so a
# desync between them is exactly what a count of one and not the other would miss.
DELIV_BTNS="$(grep -oF 'data-what="Deliverable path"' "$DOUT" | grep -c . || true)"
assert "…and the buttons themselves number 3, matching that heading (saw $DELIV_BTNS)" \
  "$(eq "$DELIV_BTNS" 3)"
echo "== absent/empty deliverable_paths renders no panel, and no error =="
# The exit code itself, not file non-emptiness — a renderer that wrote partial output
# and then failed would still pass a `test -s` check.
assert "it still exits 0"                             "$(eq "$rc4" 0)"
assert "…and produces non-empty output"               "$(yes_if test -s "$DOUT")"
assert "no deliverables panel for a project with none" "$(yes_if python3 -c "
import sys
t = open('$DOUT').read()
i = t.index('Closed with nothing stamped')
j = t.index('</details>', i)
sys.exit(0 if 'class=\"delivs\"' not in t[i:j] else 1)")"
echo "== it reuses the ONE existing clipboard helper — no second <script> =="
# -c counts LINES, not occurrences — a second <script> on the SAME line as the first
# would still read 1 and pass. -o prints one match per line, so piping to `wc -l` counts
# occurrences regardless of how many share a line.
assert "exactly one <script> element on this page too" \
  "$(eq "$(grep -oF '<script' "$DOUT" | wc -l | tr -d ' ')" 1)"

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
rc2=0; bash "$GEN" --out "$TMP/none.html" "$TMP/nosnap" >/dev/null 2>&1 || rc2=$?
assert "an instance with no snapshot exits 0"        "$(eq "$rc2" 0)"
assert "…and writes nothing"                         "$(fhasnt x "$TMP/none.html" 2>/dev/null || echo 0)"

echo "== --out creates its directory, but only when there is something to write =="
# THE TICK RENDERS TO `.board-live/board.html`, a directory that exists on a machine
# which has run watch-board.sh and on no other. A renderer that raised FileNotFoundError
# the first time each tick called it would be a board nobody ever sees — so the parent is
# created here rather than in every caller.
rcd=0; bash "$GEN" --standalone --out "$TMP/fresh/deeper/board.html" "$TMP/alpha" >/dev/null 2>&1 || rcd=$?
assert "a missing --out directory is created"        "$(eq "$rcd" 0)"
assert "…and the page is written into it"            "$(yes_if test -s "$TMP/fresh/deeper/board.html")"
# The other half, and the one that keeps "absence is safe" above true: an instance that
# is off the board must leave no trace at all, so the mkdir sits AFTER the nothing-to-write
# exit rather than beside the argument parsing.
rcd2=0; bash "$GEN" --out "$TMP/untouched/board.html" "$TMP/nosnap" >/dev/null 2>&1 || rcd2=$?
assert "…while a board with no snapshot exits 0"     "$(eq "$rcd2" 0)"
assert "…and creates no directory at all"            "$(yes_if test ! -e "$TMP/untouched")"

echo "== one drifted instance must not blank the board =="
mkdir -p "$TMP/bad"; printf 'not json at all\n' > "$TMP/bad/SNAPSHOT.json"
rc3=0; bash "$GEN" --out "$TMP/mixed.html" "$TMP/bad" "$TMP/alpha" >/dev/null 2>&1 || rc3=$?
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
# every count and every container here goes through toint()/tolist()/todict().
mkdir -p "$TMP/drift"
drift_case() { # <label> <snapshot json>
  printf '%s\n' "$2" > "$TMP/drift/SNAPSHOT.json"
  # Removed first: a page left behind by the previous case would satisfy the
  # "still renders" half even if this case wrote nothing at all.
  rm -f "$TMP/drift.html"
  local rc=0 out
  out="$(bash "$GEN" --out "$TMP/drift.html" "$TMP/alpha" "$TMP/drift" 2>&1)" || rc=$?
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
( bash "$GEN" --out "$QOUT" "$TMP/manyq" >/dev/null 2>&1 ) &
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
bash "$GEN" --out "$OUT2" "$TMP/hostile" >/dev/null 2>&1
# The other rule this layout did not carry: it wrote the snapshot's URL straight into
# the href, so a `javascript:` PR URL became a live link on a page meant for publishing.
assert "a javascript: URL is never an href"          "$(fhasnt 'href="javascript:' "$OUT2")"
assert "…and is inert text instead"                  "$(fhas 'link withheld: not http/https' "$OUT2")"
assert "…while the http PR link beside it still works" "$(fhas 'href="https://github.com/o/r/pull/41"' "$OUT2")"

echo "== flags =="
assert "an unknown flag is refused"                  "$(yes_if bash -c "bash '$GEN' --nope 2>/dev/null; [ \$? -eq 2 ]")"
assert "--help prints the header"                    "$(yes_if bash -c "bash '$GEN' --help 2>&1 | grep -q 'Artifact page body'")"

echo "== --layout is REMOVED, and is refused by name =="
# WHY A REFUSAL AND NOT AN IGNORED FLAG. Every caller that passed `--layout` was written
# when the flag chose between two DIFFERENT pages, so accepting-and-ignoring it would
# hand that caller a page it did not ask for, silently — which is the exact failure the
# deletion exists to close (the tick published `table` while watch-board.sh rendered
# `columns`). Exit 2, and say the flag was REMOVED rather than "unknown", so the stderr
# line tells a human what happened instead of looking like a typo.
for form in "--layout table" "--layout columns" "--layout=table" "--layout"; do
  assert "\`$form\` exits 2"                          "$(yes_if bash -c "bash '$GEN' $form --out '$TMP/x.html' '$TMP/alpha' 2>/dev/null; [ \$? -eq 2 ]")"
  assert "…saying the flag was REMOVED"                "$(yes_if bash -c "bash '$GEN' $form --out '$TMP/x.html' '$TMP/alpha' 2>&1 >/dev/null | grep -q 'was removed'")"
done
assert "…and writes no page"                         "$(fhasnt x "$TMP/x.html" 2>/dev/null || echo 0)"
# The rejected page is DELETED, not merely unreachable: nothing selects it and nothing
# renders it, so the markup and its selector are both gone from the script.
assert "the kanban strip is not in the page"         "$(fhasnt 'class="cols"' "$OUT")"
assert "…and the decision rail IS"                   "$(fhas 'class="rail"' "$OUT")"
assert "…no columns renderer in the script"          "$(fhasnt 'render_columns' "$REPO/symlink/scripts/build-board.sh")"
assert "…and no layout variable to select one"       "$(fhasnt 'BOARD_LAYOUT' "$REPO/symlink/scripts/build-board.sh")"

echo "== --standalone is wrapping, not markup =="
SA="$TMP/sa.html"
bash "$GEN" --standalone --out "$SA" "$TMP/alpha" >/dev/null 2>&1
assert "--standalone opens with a doctype"           "$(yes_if sh -c 'head -1 "$1" | grep -qF "<!doctype html>"' _ "$SA")"
assert "…with exactly one <body>"                    "$(eq "$(grep -cF '<body>' "$SA")" 1)"
assert "…the <style> in <head> and the board in <body>" "$(yes_if python3 -c "
import sys
t=open('$SA').read()
head=t[t.index('<head>'):t.index('</head>')]
body=t[t.index('<body>'):t.index('</body>')]
sys.exit(0 if '<style>' in head and 'class=\"board\"' in body and '<h1>' not in head else 1)")"
assert "…and the same markup as the page body"       "$(fhas 'class="rail"' "$SA")"

echo "== no caller anywhere in the repo passes the removed flag =="
# THE INVARIANT IS "NO CALLER", NOT "NO CALLER UNDER symlink/". The obvious check here is
# `grep -rn -- --layout symlink/`, and it would have passed on a tree carrying three live
# instructions to run the flag — README.md's command block, docs/operations.md's two
# tables, and seed/instance.config.json's own `$board` note. That is the same shape as
# the retired-renderer rot pinned at the bottom of this file: the check's SCOPE was
# narrower than the promise it stood for.
#
# It is also not a line-scoped grep. `.claude/commands/pm-loop.md` wrapped one invocation
# across a newline (`build-board.sh --layout` / `table`), so a scanner that reads a file
# line by line can miss the half of an invocation that sits on the next line. Whitespace
# is flattened first, and fixture (c) below is that exact shape.
#
# ONE scanner serves the real check and every fixture: a fixture that re-implements the
# rule proves the copy, not the shipped check.
layout_callers() { # <root> -> one path per line that INVOKES build-board.sh with --layout
  python3 - "$1" <<'PYL'
import re, sys
from pathlib import Path

root = Path(sys.argv[1])
# The only two files where the flag's NAME may still appear: the script that refuses it
# (its header records why it went, and its arg loop names it to refuse it) and this
# harness, which asserts that refusal. Neither is a caller. Nothing else is exempt.
SKIP = {"symlink/scripts/build-board.sh", "tests/artifact-board.test.sh"}
# An INVOCATION, not a mention: `build-board.sh` followed by whitespace and then only
# argument-shaped tokens up to `--layout`. Prose about the removal ("`build-board.sh`
# refuses `--layout` by name") cannot match, because a backtick is not an argument
# character and the run of tokens has to be unbroken.
INVOKE = re.compile(r"""build-board\.sh(?:\s+(?!--layout)[-\w=./$"'{}\[\]:]+){0,6}\s+--layout""")

for f in sorted(root.rglob("*")):
    if not f.is_file() or f.is_symlink():
        continue
    rel = f.relative_to(root).as_posix()
    if rel.split("/")[0].startswith(".") and rel.split("/")[0] != ".claude":
        continue
    if rel in SKIP:
        continue
    try:
        text = f.read_text(encoding="utf-8")
    except (UnicodeDecodeError, OSError):
        continue
    if INVOKE.search(re.sub(r"\s+", " ", text)):
        print(rel)
PYL
}
CALLERS="$(layout_callers "$REPO")"
assert "no tracked file invokes build-board.sh --layout${CALLERS:+ (saw: $(printf '%s' "$CALLERS" | tr '\n' ' '))}" \
  "$(eq "$CALLERS" "")"

# NON-VACUITY, and specifically for what a narrower check would have missed. Each fixture
# is fed to the SAME function above.
FIX="$TMP/callers"; mkdir -p "$FIX/docs"
printf 'run `scripts/build-board.sh --layout table` each tick\n'          > "$FIX/docs/a.md"
printf 'scripts/build-board.sh --out "$out" --layout table\n'             > "$FIX/b.sh"
printf 'the tick runs `scripts/build-board.sh --layout\ntable` and publishes\n' > "$FIX/docs/c.md"
FOUND="$(layout_callers "$FIX")"
for f in docs/a.md b.sh docs/c.md; do
  assert "…flags a planted caller in $f" "$(printf '%s\n' "$FOUND" | grep -qx -- "$f" && echo 0 || echo 1)"
done
# …and does NOT flag the two shapes that are not callers, or the guard is just a ban on
# the string and the header explaining the removal could never be written.
rm -f "$FIX/docs/a.md" "$FIX/b.sh" "$FIX/docs/c.md"
printf '`build-board.sh` refuses `--layout` by name, so a stale caller fails loudly\n' > "$FIX/docs/d.md"
printf 'scripts/build-board.sh --out "$out" --standalone\n'               > "$FIX/e.sh"
assert "…and flags neither prose about the removal nor a clean call" "$(eq "$(layout_callers "$FIX")" "")"
rm -rf "$FIX"

echo "== there is only ONE HTML renderer now =="
assert "build-artifact-board.sh is gone"             "$(yes_if test ! -e "$REPO/symlink/scripts/build-artifact-board.sh")"
# The runnable form, not the name: build-board.sh's own header still explains what was
# merged into it, and a comment recording that is not a caller.
assert "…and no machinery still tells anyone to run it" "$(yes_if bash -c "! grep -rlF scripts/build-artifact-board '$REPO/symlink' >/dev/null 2>&1")"

# THE DOCS WERE THE HALF THAT ROTTED, so they are asserted too. Deleting the script and
# sweeping symlink/ left FIVE live instructions to run it: four in docs/operations.md (a
# copy-pasteable command block, the renderer comparison table, the "which renderer"
# decision table, and the paragraph under it) and one inside seed/instance.config.json's
# own `$board` explanation. Each was a reader's entry point, no test looked outside
# symlink/, and the assertion above passed the entire time.
#
# THE BARE NAME here, not the runnable form as above: prose names a script without a
# `scripts/` prefix as often as with one, and a doc has no reason to carry retired
# machinery at all — that history belongs in build-board.sh's header and in git. So the
# rule for these three trees is the simple one: don't name it.
# install.sh is deliberately NOT in this list — tests/retire-machinery.test.sh owns that
# file, beside the sweep behaviour it is about.
for tree in docs README.md seed; do
  assert "no retired renderer named in $tree" \
    "$(yes_if bash -c "! grep -rlF build-artifact-board '$REPO/$tree' >/dev/null 2>&1")"
done
# NON-VACUITY: the same expression must FIND a planted mention, or it checks nothing.
mkdir -p "$TMP/tree"; printf 'run scripts/build-artifact-board.sh\n' > "$TMP/tree/doc.md"
assert "…and the same check finds a planted one" \
  "$(yes_if bash -c "grep -rlF build-artifact-board '$TMP/tree' >/dev/null 2>&1")"
rm -rf "$TMP/tree"

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
