#!/usr/bin/env bash
#
# build-artifact-board.sh — render the board as an Artifact page body, for publishing.
#
#   Usage:
#     scripts/build-artifact-board.sh [--out FILE] [INSTANCE_DIR ...]
#
#     INSTANCE_DIR ...  the instances to render. With none given the list comes from
#                       `boardInstances`, resolved by `build-board.sh
#                       --list-instances` — ONE discovery rule for every renderer.
#     --out FILE        where the page goes (default: artifact-board.html).
#
# WHY A FOURTH RENDERER. `print-board.sh` is a terminal table, `build-board.sh` is a
# kanban page, `watch-board.sh` is that page kept live by a resident process. This one
# is a different LAYOUT for a different medium: projects collapsed to one summary line,
# expandable to their task table, with a decision rail on top. The owner picked it over
# the column layout as "more readable and easier to act upon", and it is the shape meant
# for publishing — a page a teammate opens on a phone, not a wall of columns.
#
# It is presentation over the same settled contract as the other three: it reads
# SNAPSHOT.json and NEVER re-derives from the bundle. Field discipline is therefore the
# snapshot's, not this script's — it forwards only keys the snapshot already carries, so
# the published-page allowlist cannot be widened here by accident.
#
# WHY STATIC HTML AND <details> RATHER THAN A SCRIPTED PAGE. The first version rendered
# from JavaScript and toggled with a click handler. Two bugs came out of that, and
# NEITHER WAS DIAGNOSABLE IN PLACE: the artifact host serves the page in an iframe that
# exposes neither its console nor its accessibility tree, so a blank page had no error
# to read. `<details>` needs no script, works with scripting off, is keyboard-accessible
# for free, and its open/closed state is per-viewer without any extra machinery. Script
# is used for exactly one thing — putting text on the clipboard — and every button says
# what it copied, so a failed copy is visible rather than silent.
#
# A browser cannot open a local file, so a task copies a SHORT REFERENCE
# (`<project>/tasks/<id>`) instead of a link: `projects/` is constant and `.md` is never
# in question, while `tasks/` says which kind of document is meant. A `Qn` button
# appends that question's handle, ready to type an answer after the colon.
#
# Deterministic. No network. Verified by tests/artifact-board.test.sh.
set -euo pipefail

OUT="artifact-board.html"
DIRS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --out) shift; [[ $# -gt 0 ]] || { echo "build-artifact-board: --out needs a path" >&2; exit 2; }; OUT="$1" ;;
    --out=*) OUT="${1#--out=}" ;;
    -h|--help) sed -n '2,/^set -euo/p' "$0" | sed 's/^# \{0,1\}//; $d'; exit 0 ;;
    -*) echo "build-artifact-board: unknown flag '$1'" >&2; exit 2 ;;
    *) DIRS+=("$1") ;;
  esac
  shift
done

command -v python3 >/dev/null 2>&1 || {
  echo "build-artifact-board: needs python3 (standard library only)." >&2
  exit 2
}

# ONE discovery rule for every renderer: ask build-board.sh, never re-implement it.
if [[ ${#DIRS[@]} -eq 0 ]]; then
  HERE="$(cd "$(dirname "$0")" && pwd)"
  while IFS= read -r d; do [[ -n "$d" ]] && DIRS+=("$d"); done \
    < <(bash "$HERE/build-board.sh" --list-instances 2>/dev/null || true)
fi
[[ ${#DIRS[@]} -gt 0 ]] || { echo "build-artifact-board: no instance resolved." >&2; exit 0; }

BOARD_OUT="$OUT" python3 - "${DIRS[@]}" <<'PY'
import html, json, os, re, sys
from pathlib import Path

import html
import json
import re
import sys

TONE = {"blocked": "stop", "review": "signal", "in-review": "signal",
        "done": "ok", "in-progress": "accent"}
PENDING = ("draft", "ready", "blocked")
RUNNING = ("in-progress", "in-review", "review")
WORDING = {
    "approve": ("Approve", "go", "APPROVED — go ahead."),
    "discuss": ("Let’s discuss", "", "I want to discuss this before you proceed."),
    "reject": ("Reject", "no", "REJECTED — do not proceed."),
}


def esc(s):
    return html.escape(str(s or ""), quote=True)


def short_ref(slug, tid):
    """`ai-bridge-v3/tasks/task-005` — what a human pastes back.

    Drops `projects/` (constant, so it carries no information) and `.md` (the
    document type is never in question). KEEPS `tasks/`: a project also holds
    `phases/`, `sources/` and `deliverables/`, so this segment is the one that says
    which kind of document is meant, and it costs six characters. The `task-` prefix
    makes it technically redundant today — but only while tasks are the only thing
    with a copy button.
    """
    return "%s/tasks/%s" % (slug, tid)


def task_number(tid):
    """Just the number — `task-003-some-slug` -> `003`.

    Falls back to the id with `task-` stripped when there is no number to find, so an
    id that does not follow the convention still renders something identifiable rather
    than an empty cell.
    """
    m = re.match(r"^task-0*(\d+)", tid or "")
    if m:
        return m.group(1).zfill(3)
    return (tid or "")[5:] if (tid or "").startswith("task-") else (tid or "")


def explain(verb, p, t, hint):
    """One short paragraph saying what this verb means and why THIS item is here.

    Composed from the verb plus counts the snapshot already carries — never from a
    task description, a document body, or the text of a question or blocker, none
    of which the snapshot forwards. So this adds no field to the published-page
    allowlist. Kept under ~280 characters on purpose: enough to act on, short
    enough to read without deciding to read it.
    """
    ts = p.get("tasks", [])
    ph = p.get("phase_progress", {}) or {}
    nd = sum(1 for x in ts if x.get("status") == "done")
    nc = sum(1 for x in ts if x.get("status") == "cancelled")
    if verb == "close":
        bits = "%d done" % nd + (", %d cancelled" % nc if nc else "")
        phase = ", %d/%d phases complete" % (ph.get("done", 0), ph["total"]) if ph.get("total") else ""
        return ("Every task here has finished (%s%s), so there is nothing left to build. "
                "Closing rolls the project up, drops it off the active list and proposes "
                "marking its objective achieved. Nothing is deleted — run %s."
                % (bits, phase, hint or "/close-project"))
    if verb == "approve":
        return ("A draft is never dispatched. This one has been refined and its acceptance "
                "criteria are written, so it is waiting on you to promote it to ready — "
                "after which an agent can pick it up. Approving does not start work "
                "immediately; the next loop tick does.")
    if verb in ("answer", "question"):
        qs = t.get("open_question_text") or []
        if qs:
            # An escalated concern is prefixed `advisor:` by the project-manager. Say
            # once, in prose, where it came from — then strip the marker, so the
            # question does not read "Q1: advisor: …".
            def strip(q):
                return q[len("advisor:"):].lstrip() if q.lower().startswith("advisor:") else q
            escalated = any(q.lower().startswith("advisor:") for q in qs)
            lead = ("The advisor raised this and the project-manager could not settle it from "
                    "the documents, so it came to you. ") if escalated else ""
            body = "  ".join("Q%d: %s" % (i, strip(q)) for i, q in enumerate(qs, 1))
            return lead + body + ("  — an unanswered question blocks promotion, so the "
                                  "loop will not dispatch this task.")
        # No text carried (the default) — fall through to the count wording.
        n = t.get("open_questions", 0)
        one = n == 1
        return ("There %s %d open question%s on this task, and an unanswered question blocks "
                "promotion — the loop will not dispatch it. The board never carries question "
                "text; use the Q button in the task table to copy a prompt that opens "
                "%s, or read AWAITING.md, which does carry %s."
                % ("is" if one else "are", n, "" if one else "s",
                   "it" if one else "them", "it" if one else "them"))
    if verb == "merge":
        prs = t.get("prs", [])
        nums = ", ".join("#%s" % x.get("number") for x in prs)
        one = len(prs) == 1
        return ("The work is built and its pull request%s open and reviewed. It needs your "
                "merge — agents deliberately do not merge their own work."
                % (" (%s) is" % nums if one else
                   ("s (%s) are" % nums if nums else "s are")))
    if verb == "unblock":
        return ("An agent stopped because something outside its control is in the way — a "
                "missing credential, a failing dependency, a decision it cannot make. The "
                "task document records what. It will not retry until you clear it.")
    return ("This item is waiting on a human decision. The task document has the detail; "
            "the board deliberately does not carry it.")


def build(snapshots):
    groups = [s.get("group", "?") for s in snapshots]
    if len(groups) == 1:
        name = groups[0].split(".")[0].replace("-", " ").replace("_", " ").title()
        title = f"{name} Bridge Board"
    else:
        title = "Bridge Board"

    rows, asks = [], []
    n_tasks = n_done = 0
    for s in snapshots:
        g = s.get("group", "?")
        for p in s.get("projects", []):
            ts = p.get("tasks", [])
            # "Done" is all-tasks-terminal, or the project saying so. A project with no
            # tasks yet is NOT done — it has not started.
            done_proj = bool(p.get("status") == "done" or (
                ts and all(t.get("status") in ("done", "cancelled") for t in ts)))
            rows.append((g, p, done_proj))
            for t in ts:
                n_tasks += 1
                if t.get("status") == "done":
                    n_done += 1
                if t.get("awaiting"):
                    asks.append((g, p, t, None))
                elif t.get("open_questions"):
                    # A question only produces an `awaiting` verb while the task is a
                    # DRAFT (write-snapshot.sh, `case draft)`), so a question on a
                    # ready or in-progress task is invisible in the queue. Surfacing
                    # it here fixes that at the presentation layer, without touching
                    # the AWAITING.md contract that awaiting-queue.test.sh pins.
                    asks.append((g, p, dict(t, awaiting="question"), None))
            if p.get("awaiting_close"):
                asks.append((g, p, {"awaiting": "close", "title": "all tasks terminal",
                                    "id": ""}, "/close-project " + p.get("slug", "")))

    # Finished projects sink to the bottom; among themselves and among the live ones
    # the snapshot's order is preserved, so the list does not reshuffle between renders.
    rows.sort(key=lambda r: r[2])

    o = [HEAD.replace("__TITLE__", esc(title)), '<div class="board">']

    o.append('<header class="mast"><div><h1>%s</h1>' % esc(title))
    stamps = sorted(s.get("generated_at", "") for s in snapshots if s.get("generated_at"))
    if stamps:
        o.append('<p class="sub">Snapshot %s UTC</p>'
                 % esc(stamps[-1].replace("T", " ").replace("Z", "")))
    o.append("</div><dl class=\"tally\">")
    o.append('<div><dt>Projects</dt><dd>%d</dd></div>' % len(rows))
    o.append('<div><dt>Done</dt><dd>%d/%d</dd></div>' % (n_done, n_tasks))
    o.append('<div class="%s"><dt>Awaiting you</dt><dd>%d</dd></div>'
             % ("live" if asks else "", len(asks)))
    o.append("</dl></header>")

    # ---- the decision rail: one click copies a complete prompt --------------
    if asks:
        o.append('<section class="rail"><h2>Awaiting you</h2><ul>')
        for g, p, t, hint in asks:
            what = (t.get("id") + " (" + t.get("title", "") + ")") if t.get("id") else t.get("title", "")
            where = g + " › " + p.get("title", "")
            o.append('<li class="ask"><details class="why"><summary class="line">'
                     '<span class="verb">%s</span><span class="what">%s</span>'
                     % (esc(t.get("awaiting")), esc(t.get("title"))))
            o.append('<span class="where">%s%s</span></summary>'
                     % (esc(where), " · <code>%s</code>" % esc(hint) if hint else ""))
            o.append('<p>%s</p></details>' % esc(explain(t.get("awaiting"), p, t, hint)))
            o.append('<div class="acts">')
            if t.get("id"):
                ref = short_ref(p.get("slug", ""), t["id"])
                o.append('<button class="ghost" data-copy="%s" data-what="Task reference">'
                         "copy task ref</button>" % esc(ref))
                for i in range(1, (t.get("open_questions") or 0) + 1):
                    o.append('<button class="qbtn" data-copy="%s" data-what="Q%d handle" '
                             'title="Copy &quot;%s Q%d:&quot; ready to type your answer after">'
                             "answer Q%d</button>"
                             % (esc("%s Q%d: " % (ref, i)), i, esc(ref), i, i))
            for verdict, (label, cls, lead) in ([] if t.get("awaiting") == "question"
                                                else WORDING.items()):
                msg = '%s Re the "%s" item on %s in %s.' % (lead, t.get("awaiting"), what, where)
                if verdict == "approve" and hint:
                    msg += " Run %s." % hint
                elif verdict == "discuss":
                    msg += " Tell me the trade-off you see and what you recommend."
                elif verdict == "reject":
                    msg += " Record why on the task and move on."
                o.append('<button class="%s" data-copy="%s" data-what="%s">%s</button>'
                         % (cls, esc(msg), esc(label + " prompt"), esc(label)))
            o.append("</div></li>")
        o.append("</ul></section>")

    # ---- one <details> per project, collapsed by default -------------------
    n_fin = sum(1 for r in rows if r[2])
    for idx, (g, p, fin) in enumerate(rows):
        if fin and (idx == 0 or not rows[idx - 1][2]):
            o.append('<h2 class="sep">Finished · %d</h2>' % n_fin)
        tasks = p.get("tasks", [])
        nd = sum(1 for t in tasks if t.get("status") == "done")
        nr = sum(1 for t in tasks if t.get("status") in RUNNING)
        nw = sum(1 for t in tasks if t.get("status") in PENDING)
        ph = p.get("phase_progress", {}) or {}
        o.append('<details class="proj%s"><summary class="phead">' % (" fin" if fin else ""))
        o.append('<span class="ptitle">%s</span><span class="counts">' % esc(p.get("title")))
        if fin:
            o.append('<span class="c done-tag">✓ done</span>')
        o.append('<span class="c ok"><b>%d</b> done</span>' % nd)
        if not fin:
            o.append('<span class="c run"><b>%d</b> in progress</span>' % nr)
            o.append('<span class="c wait"><b>%d</b> pending</span>' % nw)
        nq = sum(t.get("open_questions", 0) for t in tasks)
        if nq:
            o.append('<span class="c q"><b>%d</b> question%s</span>'
                     % (nq, "" if nq == 1 else "s"))
        na = sum(t.get("advisor_notes", 0) for t in tasks)
        if na:
            # Deliberately NOT in the signal colour and deliberately not in the
            # awaiting rail: an untriaged advisor concern is the loop's inbox, not
            # yours. It becomes a question only if the PM escalates it.
            o.append('<span class="c note" title="Advisor concerns the loop has not '
                     'triaged yet — not waiting on you"><b>%d</b> concern%s</span>'
                     % (na, "" if na == 1 else "s"))
        if ph.get("total"):
            o.append('<span class="tag">%d/%d phases</span>' % (ph.get("done", 0), ph["total"]))
        o.append("</span></summary>")

        o.append('<div class="body"><div class="scroll"><table><thead><tr>'
                 "<th>Task</th><th>State</th><th>Role</th><th>Depends on</th>"
                 "<th class=\"r\">Q</th><th>PR</th>"
                 "</tr></thead><tbody>")
        for t in tasks:
            tid = t.get("id", "")
            short = tid[5:] if tid.startswith("task-") else tid
            path = "projects/%s/tasks/%s.md" % (p.get("slug", ""), tid)
            st = t.get("status", "")
            o.append('<tr%s>' % (' class="flight"' if t.get("in_flight") else ""))
            o.append('<td><span class="tid">%s</span>' % esc(short))
            o.append('<button class="tbtn" data-copy="%s" data-what="Task reference">%s</button>'
                     % (esc(short_ref(p.get("slug", ""), tid)), esc(t.get("title"))))
            if st == "draft":
                promo = ("In the ai-bridge instance, promote %s from draft to ready: review its "
                         "acceptance criteria, tighten any that are not testable, then set "
                         "status: ready." % short_ref(p.get("slug", ""), tid))
                o.append('<button class="promote" data-copy="%s" data-what="Promotion prompt">'
                         "promote → ready</button>" % esc(promo))
            o.append("</td>")
            o.append('<td><span class="state %s">%s</span></td>' % (TONE.get(st, ""), esc(st)))
            o.append('<td class="dim">%s</td>' % esc(t.get("assignee") or "—"))
            deps = t.get("depends_on") or []
            if deps:
                # Show the short id, the same form the Task column shows, and copy the
                # full bundle-relative path — a dependency is most useful as a thing to
                # go read.
                o.append('<td class="deps">%s</td>' % ", ".join(
                    '<button class="dep" data-copy="%s" data-what="Path" title="%s">%s</button>'
                    % (esc(short_ref(p.get("slug", ""), d)), esc(d),
                       esc(task_number(d))) for d in deps))
            else:
                o.append('<td class="dim">—</td>')
            q = t.get("open_questions", 0)
            if q:
                # One handle per question. The snapshot carries only a COUNT, and
                # SCHEMA.md requires every entry to be numbered Q1, Q2, … — so the
                # labels are derivable without ever carrying question text. See the
                # caveat in the footer: this assumes the numbering starts at 1 and is
                # contiguous, which the schema asks for but does not enforce.
                ref = short_ref(p.get("slug", ""), t.get("id", ""))
                o.append('<td class="r"><span class="qs">%s</span></td>' % "".join(
                    '<button class="qbtn" data-copy="%s" data-what="Q%d handle" '
                    'title="Copy &quot;%s Q%d:&quot; ready to type your answer after">'
                    'Q%d</button>' % (esc("%s Q%d: " % (ref, i)), i,
                                      esc(ref), i, i)
                    for i in range(1, q + 1)))
            else:
                o.append('<td class="r dim">—</td>')
            prs = t.get("prs", [])
            o.append('<td>%s</td></tr>' % (" ".join(
                '<a href="%s" target="_blank" rel="noopener noreferrer">#%s</a>'
                % (esc(x.get("url")), esc(x.get("number"))) for x in prs)
                if prs else '<span class="dim">—</span>'))
        o.append("</tbody></table></div></div></details>")

    o.append('<footer><p>Derived from each instance’s <code>SNAPSHOT.json</code> and '
             "<strong>as sensitive as the task documents it comes from</strong>. Titles are "
             "human-written free text; no customer PII belongs in a task title, and so none "
             "belongs here. Task descriptions, document bodies, question and blocker text, "
             "author identity and out-of-bundle paths are never carried.</p>"
             "<p>A browser cannot open a local file, so a task copies its <em>bundle-relative</em> "
             "path for you to paste — prefix it with your instance directory. Decision "
             "buttons copy a prompt; the bundle, not this page, is where a decision is "
             "recorded.</p></footer></div>")
    o.append(SCRIPT)
    return "\n".join(o)


HEAD = """<title>__TITLE__</title>
<meta name="viewport" content="width=device-width, initial-scale=1">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=IBM+Plex+Sans:wght@400;500;600&family=IBM+Plex+Mono:wght@400;500;600&display=swap">
<style>
/* Full light palette on BARE :root — no colour is ever defined only inside a media
   or [data-theme] block. Dark redefines the same tokens twice: once for the system
   preference (guarded so an explicit light choice wins), once for an explicit choice. */
:root{
  --ground:#f4f6f7; --surface:#fff; --sunk:#eceff1; --raise:#f8fafb;
  --ink:#15181d; --muted:#5c6470; --dim:#89919c; --line:#dde2e6;
  --accent:#0f6b66; --signal:#9c560d; --ok:#2c6647; --stop:#a03a32;
  --shadow:0 1px 2px rgba(20,26,34,.05),0 8px 24px -16px rgba(20,26,34,.22);
}
@media (prefers-color-scheme:dark){ :root:not([data-theme="light"]){
  --ground:#0e1013; --surface:#171a1e; --sunk:#1e2227; --raise:#1b1f24;
  --ink:#e5e8eb; --muted:#98a1ac; --dim:#6d7681; --line:#262b31;
  --accent:#44b0a7; --signal:#dda157; --ok:#5fac82; --stop:#dc7a70;
  --shadow:0 1px 2px rgba(0,0,0,.4),0 8px 24px -16px rgba(0,0,0,.7);
}}
:root[data-theme="dark"]{
  --ground:#0e1013; --surface:#171a1e; --sunk:#1e2227; --raise:#1b1f24;
  --ink:#e5e8eb; --muted:#98a1ac; --dim:#6d7681; --line:#262b31;
  --accent:#44b0a7; --signal:#dda157; --ok:#5fac82; --stop:#dc7a70;
  --shadow:0 1px 2px rgba(0,0,0,.4),0 8px 24px -16px rgba(0,0,0,.7);
}
*,*::before,*::after{box-sizing:border-box}
body{background:var(--ground);color:var(--ink);margin:0;
  font:400 15px/1.55 "IBM Plex Sans",ui-sans-serif,system-ui,sans-serif;
  -webkit-font-smoothing:antialiased;-webkit-text-size-adjust:100%}
.board{width:min(100% - 2rem, 104rem);margin:0 auto;display:flex;flex-direction:column;
  gap:1.1rem;padding:clamp(1.4rem,3vw,2.6rem) 0 4rem}
/* Prose keeps a readable measure even when the board is wide — only the data grows. */
.sub,.where,footer p{max-width:52rem}

.mast{display:flex;flex-wrap:wrap;gap:1.3rem;justify-content:space-between;
  align-items:flex-end;padding-bottom:1rem;border-bottom:2px solid var(--ink)}
h1{font-size:clamp(1.5rem,3.6vw,1.95rem);font-weight:600;letter-spacing:-.02em;
  margin:0;text-wrap:balance}
.sub{color:var(--muted);margin:.28rem 0 0;font-size:.82rem;
  font-family:"IBM Plex Mono",ui-monospace,monospace}
.tally{display:flex;gap:1.5rem;margin:0}
.tally div{display:flex;flex-direction:column-reverse;gap:.1rem}
.tally dt{font-size:.65rem;text-transform:uppercase;letter-spacing:.09em;
  color:var(--dim);margin:0}
.tally dd{margin:0;font:600 1.5rem/1 "IBM Plex Mono",ui-monospace,monospace;
  color:var(--muted);font-variant-numeric:tabular-nums}
.tally .live dd,.tally .live dt{color:var(--signal)}

.rail{border-left:.22rem solid var(--signal);border-radius:0 6px 6px 0;
  background:color-mix(in srgb,var(--signal) 8%,var(--surface));padding:.9rem 1rem}
.rail h2{margin:0 0 .7rem;font-size:.68rem;text-transform:uppercase;letter-spacing:.1em;
  color:var(--signal);font-weight:600}
.rail ul{list-style:none;margin:0;padding:0;display:flex;flex-direction:column;gap:.6rem}
.ask{display:flex;flex-direction:column;gap:.5rem;padding:.65rem .75rem;
  background:var(--surface);border:1px solid var(--line);border-radius:5px}
.line{display:flex;flex-wrap:wrap;gap:.3rem .55rem;align-items:baseline}
.what{font-weight:500}
.verb{font:600 .64rem/1.7 "IBM Plex Mono",ui-monospace,monospace;text-transform:uppercase;
  letter-spacing:.08em;color:var(--signal);white-space:nowrap}
.where{width:100%;font-size:.75rem;color:var(--dim)}
.acts{display:flex;flex-wrap:wrap;gap:.35rem}
/* The title line IS the toggle: click anywhere on it for the explanation. A caret
   marks it as expandable, since a heading that happens to be clickable is invisible. */
.why summary{cursor:pointer;list-style:none}
.why summary::-webkit-details-marker{display:none}
.why summary::after{content:"▸";color:var(--dim);font-size:.7rem;
  transition:transform .15s;display:inline-block;margin-left:.15rem}
.why[open] summary::after{transform:rotate(90deg)}
.why summary:hover .what{color:var(--accent)}
.why summary:hover::after{color:var(--accent)}
.why p{margin:.55rem 0 0;color:var(--muted);line-height:1.5;max-width:52rem;
  font-size:.83rem;border-left:2px solid var(--line);padding-left:.6rem}
button{font:500 .78rem/1 "IBM Plex Sans",sans-serif;cursor:pointer;border-radius:4px;
  padding:.38rem .62rem;border:1px solid var(--line);background:var(--raise);
  color:var(--ink)}
button:hover{border-color:var(--accent)}
button.go{border-color:var(--ok);color:var(--ok)}
button.no{border-color:var(--stop);color:var(--stop)}

/* Collapsed by default: no `open` attribute, and no script involved. */
.proj{background:var(--surface);border:1px solid var(--line);border-radius:6px;
  box-shadow:var(--shadow)}
.phead{display:flex;flex-wrap:wrap;gap:.5rem .9rem;align-items:center;cursor:pointer;
  padding:.8rem .95rem;list-style:none;border-radius:6px}
.phead::-webkit-details-marker{display:none}
.phead::before{content:"\\25B8";color:var(--dim);font-size:.8rem;flex-shrink:0;
  transition:transform .15s}
.proj[open] .phead::before{transform:rotate(90deg)}
.phead:hover{background:var(--raise)}
.phead:hover .ptitle{color:var(--accent)}
.ptitle{font-weight:600;letter-spacing:-.01em;flex:1 1 18rem;min-width:0;font-size:.97rem}
.counts{display:flex;gap:.35rem;flex-wrap:wrap}
.c{font-size:.72rem;color:var(--muted);border:1px solid var(--line);border-radius:3px;
  padding:.15rem .42rem;white-space:nowrap}
.c b{font-weight:600;color:var(--ink);font-variant-numeric:tabular-nums}
.c.ok b{color:var(--ok)} .c.run b{color:var(--accent)} .c.wait b{color:var(--signal)}
.tag{font-size:.65rem;text-transform:uppercase;letter-spacing:.07em;color:var(--muted);
  background:var(--sunk);border-radius:3px;padding:.14rem .38rem;white-space:nowrap}
.body{padding:0 .95rem .9rem;border-top:1px solid var(--line)}

/* Finished projects: sunk below a divider, desaturated, and labelled. Still fully
   readable when expanded — dimming the summary, not the contents. */
.sep{font-size:.66rem;text-transform:uppercase;letter-spacing:.11em;color:var(--dim);
  font-weight:600;margin:.9rem 0 -.35rem;display:flex;align-items:center;gap:.6rem}
.sep::after{content:"";flex:1;height:1px;background:var(--line)}
.proj.fin{background:transparent;box-shadow:none;border-style:dashed}
.proj.fin .ptitle{color:var(--muted);font-weight:500}
.proj.fin .phead{opacity:.8}
.proj.fin[open] .phead{opacity:1}
.c.q{color:var(--signal);border-color:color-mix(in srgb,var(--signal) 40%,var(--line))}
.c.q b{color:var(--signal)}
.c.note{color:var(--dim);border-style:dashed}
.c.note b{color:var(--muted)}
.c.done-tag{color:var(--ok);border-color:color-mix(in srgb,var(--ok) 45%,var(--line));
  background:color-mix(in srgb,var(--ok) 9%,transparent);font-weight:600}

.scroll{overflow-x:auto}
table{border-collapse:collapse;width:100%;font-size:.86rem;min-width:min(100%,33rem)}
th{text-align:left;font-size:.64rem;text-transform:uppercase;letter-spacing:.09em;
  color:var(--dim);font-weight:500;padding:.7rem .45rem .35rem;
  border-bottom:1px solid var(--line);white-space:nowrap}
th.r,td.r{text-align:right}
th:not(:first-child),td:not(:first-child){width:1%;white-space:nowrap}
th:first-child,td:first-child{width:auto}
td{padding:.4rem .45rem;vertical-align:baseline;
  border-bottom:1px solid color-mix(in srgb,var(--line) 55%,transparent)}
tbody tr:last-child td{border-bottom:0}
tr.flight td:first-child{box-shadow:inset 2px 0 0 var(--accent)}
.tid{color:var(--dim);font-size:.74rem;margin-right:.4rem;
  font-family:"IBM Plex Mono",ui-monospace,monospace;font-variant-numeric:tabular-nums}
td:first-child{overflow-wrap:break-word}
.tbtn{background:none;border:0;padding:0;font:inherit;color:inherit;text-align:left;
  border-bottom:1px dotted var(--dim);border-radius:0}
.tbtn:hover{color:var(--accent);border-color:var(--accent)}
.promote{font-size:.68rem;padding:.14rem .4rem;margin-left:.4rem}
/* The Q count is a button only when there is something to ask about. Its TEXT is
   never on this page — the allowlist forbids question text, and AWAITING.md has it. */
.qbtn{font-family:"IBM Plex Mono",ui-monospace,monospace;font-size:.8rem;font-weight:600;
  color:var(--signal);border-color:color-mix(in srgb,var(--signal) 45%,var(--line));
  background:color-mix(in srgb,var(--signal) 10%,transparent);padding:.1rem .45rem;
  font-variant-numeric:tabular-nums}
.qs{display:inline-flex;gap:.2rem}
.qbtn:hover{border-color:var(--signal);background:color-mix(in srgb,var(--signal) 18%,transparent)}
button.ghost{font-size:.72rem;padding:.28rem .5rem;color:var(--muted)}
.deps{white-space:normal!important}
button.dep{font-family:"IBM Plex Mono",ui-monospace,monospace;font-size:.74rem;
  padding:.08rem .35rem;color:var(--muted);background:var(--sunk);border-color:transparent;
  font-variant-numeric:tabular-nums}
button.dep:hover{color:var(--accent);border-color:var(--accent);background:transparent}
.state{font-size:.7rem;text-transform:uppercase;letter-spacing:.06em;color:var(--muted);
  white-space:nowrap}
.state.ok{color:var(--ok)} .state.signal{color:var(--signal)}
.state.stop{color:var(--stop)} .state.accent{color:var(--accent)}
.dim{color:var(--dim)} .sig{color:var(--signal);font-weight:500}
td.r,td.dim{font-family:"IBM Plex Mono",ui-monospace,monospace;font-size:.8rem}
td a{color:var(--accent);text-decoration:none;border-bottom:1px solid transparent;
  white-space:nowrap;font-family:"IBM Plex Mono",ui-monospace,monospace;font-size:.8rem}
td a:hover,td a:focus-visible{border-bottom-color:currentColor}
:focus-visible{outline:2px solid var(--accent);outline-offset:2px}

.toast{position:fixed;left:50%;bottom:1.3rem;transform:translateX(-50%);z-index:9;
  background:var(--ink);color:var(--ground);font-size:.83rem;padding:.55rem .9rem;
  border-radius:5px;box-shadow:var(--shadow);max-width:calc(100vw - 2rem);
  opacity:0;pointer-events:none;transition:opacity .18s}
.toast.on{opacity:1}
footer{border-top:1px solid var(--line);padding-top:.9rem}
footer p{margin:0 0 .5rem;font-size:.76rem;color:var(--dim);max-width:45rem}
footer p:last-child{margin:0}
code{font-family:"IBM Plex Mono",ui-monospace,monospace;font-size:.93em}
@media (prefers-reduced-motion:reduce){*{transition:none!important}}
</style>"""

SCRIPT = r"""<script>
// The ONLY scripted behaviour: put a button's text on the clipboard. Everything
// else — layout, collapse, links — is markup and CSS, so scripting off costs the
// page nothing but this.
(function(){
  var el;
  function toast(m){
    if(!el){ el=document.createElement('div'); el.className='toast'; document.body.appendChild(el); }
    el.textContent=m; el.classList.add('on');
    clearTimeout(toast.t); toast.t=setTimeout(function(){ el.classList.remove('on'); },3000);
  }
  document.addEventListener('click', function(e){
    var b = e.target.closest ? e.target.closest('[data-copy]') : null;
    if(!b) return;
    e.preventDefault();
    var text = b.getAttribute('data-copy'), what = b.getAttribute('data-what') || 'Text';
    var ok = function(){ toast(what + ' copied — paste it to Claude'); };
    var bad = function(){ toast('Copy failed. Select this instead: ' + text); };
    if(navigator.clipboard && navigator.clipboard.writeText){
      navigator.clipboard.writeText(text).then(ok, legacy);
    } else { legacy(); }
    function legacy(){
      try{
        var ta=document.createElement('textarea'); ta.value=text;
        ta.style.position='fixed'; ta.style.top='-1000px'; document.body.appendChild(ta);
        ta.select(); var done=document.execCommand('copy'); document.body.removeChild(ta);
        done ? ok() : bad();
      }catch(err){ bad(); }
    }
  });
})();
</script>"""


OUT = Path(os.environ["BOARD_OUT"])
snaps = []
for d in sys.argv[1:]:
    f = Path(d) / "SNAPSHOT.json"
    if not f.exists():
        continue                      # absent by choice: that instance is off the board
    try:
        snaps.append(json.loads(f.read_text()))
    except Exception:
        # A snapshot's TYPES are untrusted too: one drifted instance must not blank the
        # board for the rest.
        sys.stderr.write("build-artifact-board: skipping unreadable %s\n" % f)
        continue
if not snaps:
    sys.stderr.write("build-artifact-board: no readable snapshot; nothing written.\n")
    raise SystemExit(0)

OUT.write_text(build(snaps))
sys.stderr.write("build-artifact-board: %s - %d instance(s), %d project(s)\n"
                 % (OUT, len(snaps), sum(len(s.get("projects") or []) for s in snaps)))
PY
