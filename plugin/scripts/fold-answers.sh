#!/usr/bin/env bash
#
# fold-answers.sh — move every ` --- `-answered `open_questions` entry into
# `answered_questions`, stamped `<ISO 8601> by <login> · <entry verbatim>`.
#
#   Usage: fold-answers.sh [--instance DIR] <task-doc>
#          fold-answers.sh --list <task-doc> <frontmatter-key>   # read-only
#
# Exit: 0 done (nothing to move is also 0) · 2 usage · 3 a list it could not round-trip,
# nothing written · 4 the move would leave one entry in BOTH lists, nothing written.
#
# THE MECHANICAL MOVE ONLY. Baking the answer into `# Context` or a criterion is the
# model's, before this runs; this script neither writes nor checks it.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
usage() { sed -n '4,6p' "$0" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "fold-answers: python3 is required" >&2; exit 2; }

inst="."; doc=""; list_key=""
while [ $# -gt 0 ]; do
  case "$1" in
    --instance) [ $# -ge 2 ] || usage; inst="$2"; shift 2 ;;
    --list)     [ $# -ge 3 ] || usage; doc="$2"; list_key="$3"; shift 3 ;;
    -h|--help)  usage ;;
    -*)         usage ;;
    *)          [ -z "$doc" ] || usage; doc="$1"; shift ;;
  esac
done
[ -n "$doc" ] && [ -r "$doc" ] || { echo "fold-answers: no readable task document given" >&2; exit 2; }

# THE LOGIN IS NEVER THE MODEL'S. `--author` attributes a reply that arrived as a commit to
# whoever pushed it; `--self` is this session's. Unattributable prints `<unknown>`, which is
# written as-is: an omitted stamp is indistinguishable from a decision nobody made.
login="<unknown>"
if [ -z "$list_key" ] && [ -x "$HERE/decision-stamp.sh" ]; then
  login="$(bash "$HERE/decision-stamp.sh" --instance "$inst" --author "$doc" 2>/dev/null || true)"
  case "$login" in ""|"<unknown>")
    login="$(bash "$HERE/decision-stamp.sh" --instance "$inst" --self 2>/dev/null || true)" ;;
  esac
  [ -n "$login" ] || login="<unknown>"
fi

python3 - "$doc" "$list_key" "$login" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" <<'PY'
import re, sys

path, list_key, login, stamp = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
src = open(path, encoding="utf-8").read()


def die(code, msg):
    sys.stderr.write("fold-answers: %s\n" % msg)
    sys.exit(code)


def frontmatter(text):
    if not text.startswith("---\n"):
        die(3, "no frontmatter")
    end = text.find("\n---", 3)
    if end < 0:
        die(3, "unterminated frontmatter")
    return 4, end + 1


FM_START, FM_END = frontmatter(src)


def scan_flow(text, i):
    """A real scanner for a YAML flow sequence of scalars: returns (entries, end_index).

    Quoted scalars are consumed by their own grammar, which is the whole point — a
    bracket, a comma or a ` --- ` inside an entry is data, and every hand-rolled
    split on this shape has cut an entry in half on exactly one of the three."""
    n = len(text)
    while i < n and text[i] in " \t\n":
        i += 1
    if i >= n or text[i] != "[":
        die(3, "%s is not a flow list" % list_key)
    i += 1
    out = []
    while True:
        while i < n and text[i] in " \t\n,":
            i += 1
        if i >= n:
            die(3, "unterminated flow list")
        if text[i] == "]":
            return out, i + 1
        if text[i] == '"':
            i += 1
            buf = []
            while True:
                if i >= n:
                    die(3, "unterminated double-quoted entry")
                c = text[i]
                if c == "\\":
                    if i + 1 >= n:
                        die(3, "trailing escape")
                    nxt = text[i + 1]
                    buf.append({"n": "\n", "t": "\t"}.get(nxt, nxt))
                    i += 2
                    continue
                if c == '"':
                    i += 1
                    break
                buf.append(c)
                i += 1
            out.append("".join(buf))
        elif text[i] == "'":
            i += 1
            buf = []
            while True:
                if i >= n:
                    die(3, "unterminated single-quoted entry")
                if text[i] == "'":
                    if i + 1 < n and text[i + 1] == "'":
                        buf.append("'")
                        i += 2
                        continue
                    i += 1
                    break
                buf.append(text[i])
                i += 1
            out.append("".join(buf))
        else:
            j = i
            while j < n and text[j] not in ",]\n":
                j += 1
            v = text[i:j].strip()
            if v:
                out.append(v)
            i = j


def find_key(key):
    m = re.search(r"(?m)^%s:[ \t]*" % re.escape(key), src[FM_START:FM_END])
    if not m:
        return None
    return FM_START + m.end()


def read(key):
    at = find_key(key)
    if at is None:
        return None, None, None
    entries, end = scan_flow(src, at)
    return entries, at, end


def emit(entries):
    if not entries:
        return "[ ]"
    parts = []
    for e in entries:
        if "\n" in e:
            die(3, "an entry contains a newline; refusing to write a damaged list")
        parts.append('"%s"' % e.replace("\\", "\\\\").replace('"', '\\"'))
    return "[ " + ", ".join(parts) + " ]"


if list_key:
    entries, _, _ = read(list_key)
    for e in entries or []:
        print(e)
    sys.exit(0)

open_q, o_at, o_end = read("open_questions")
ans_q, a_at, a_end = read("answered_questions")
if open_q is None:
    sys.exit(0)
if ans_q is None:
    ans_q, a_at, a_end = [], None, None

answered = [e for e in open_q if " --- " in e]
if not answered:
    sys.exit(0)
keep = [e for e in open_q if " --- " not in e]
moved = ["%s by %s · %s" % (stamp, login, e) for e in answered]
new_ans = ans_q + moved

# THE FAILURE THIS SCRIPT EXISTS FOR. An entry left in both lists blocks the draft forever
# and nothing downstream can see it — so refuse rather than write it.
for e in keep:
    if any(e in a for a in new_ans):
        die(4, "entry would remain in BOTH lists: %s" % e[:80])
if len(keep) + len(answered) != len(open_q):
    die(4, "entry count does not balance; nothing written")

new = emit(keep)
new_a = emit(new_ans)

if a_at is None:
    die(3, "no answered_questions: key to fold into")

# Highest offset first, so the earlier span's indices stay valid.
edits = sorted([(o_at, o_end, new), (a_at, a_end, new_a)], reverse=True)
out = src
for at, end, text in edits:
    out = out[:at] + text + out[end:]

# THE ROUND TRIP IS THE GUARD: re-read what we are about to write and refuse unless both
# lists parse back to exactly what we meant.
src = out
FM_START, FM_END = frontmatter(out)
back_o, _, _ = read("open_questions")
back_a, _, _ = read("answered_questions")
if back_o != keep or back_a != new_ans:
    die(3, "the re-parse does not match; nothing written")

open(path, "w", encoding="utf-8").write(out)
print("folded: %d entr%s -> answered_questions" % (len(moved), "y" if len(moved) == 1 else "ies"))
PY
