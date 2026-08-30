#!/usr/bin/env bash
#
# pr-body-clearance.sh — assert that a pull request's BODY carries the required SHAPE:
# a TL;DR line and a well-formed acceptance-criteria table. This is precondition 3 of the
# delegated merge gate (`AUTONOMY.md` → "Merge under `yolo`"). `required-checks.sh` is
# precondition 1 and calls in here for every PR it is about to clear, exactly as it calls
# `review-clearance.sh`.
#
#   Usage: scripts/pr-body-clearance.sh <pr> [--repo <owner>/<name>] [--head <sha>]
#          scripts/pr-body-clearance.sh --body-file <path>   (decide on a local draft)
#          scripts/pr-body-clearance.sh --self-test          (prove this script RUNS)
#
# WHY THIS EXISTS — `CONVENTIONS.md` has required a short, shaped PR body since the rule
# merged at 14:59 UTC on 2026-08-29. FIVE HOURS LATER an agent that had that rule — the
# document is symlinked into its instance and its own agent file references it — opened a
# 14,673-character description. The rule was present, reachable and referenced, and it was
# not followed, because the short form's only reader was `tests/pr-body-shape.test.sh`,
# which asserts THE RULE IS NAMED IN THE DOCUMENT. That is a reader for the documentation,
# not for the thing the rule governs. Nothing read a PR body. This file is that reader.
#
# IT REFUSES ON MISSING STRUCTURE AND NEVER ON LENGTH, AND THAT IS THE WHOLE DESIGN.
# A 1,137-line change may honestly need more than a tweet, and `CONVENTIONS.md` bounds
# the body's SHAPE and never its size — so a gate that punished size would be wrong on
# precisely the pull requests that most need explaining, and would be switched off within
# a week for refusing correct work. THE 14,673-CHARACTER BODY THAT MOTIVATED
# THIS FILE PASSES HERE if it carries a TL;DR and a criteria table. That is deliberate
# scope, not an oversight.
#
# SO LENGTH IS INFORMATION, NEVER A VERDICT. The character count is computed once, printed
# on stderr on every run that reads a body, and never read again: NO THRESHOLD, NO
# CONSTANT AND NO COMPARISON ON IT EXISTS ANYWHERE BELOW. The only numbers this file
# compares are an argument count, a table's cell count, a code fence's width and an exit
# status — none of which is a property of the prose, and none of which grows with it. `tests/pr-body-clearance.test.sh` asserts that statically (the
# count variable never appears on a line with a comparison operator) as well as
# behaviourally (a body far longer than the motivating one clears).
#
# THE TWO ELEMENTS, AND WHICH DIRECTION EACH MATCH FAILS IN. Text matching is unavoidable
# here — a PR body is prose — so it is arranged the way `review-clearance.sh` arranges its
# refusal detection: EVERY MATCH FAILS CLOSED. A false "structure missing" sends a human
# to look at a well-formed PR and costs a glance; a false "structure present" would clear
# a body nobody can read. Both tests below are therefore narrow, and both are computed on
# a rendering with FENCED CODE BLOCKS REMOVED — otherwise a body that merely QUOTES
# `CONVENTIONS.md`'s example (which is a fenced TL;DR line above a fenced table) would
# clear on the example rather than on its own content, which is the one false positive
# this file could plausibly have had.
#
#   1. A TL;DR MARKER LINE. Matched only where the marker LEADS THE LINE'S OWN CONTENT —
#      as the text of an ATX heading, as a CLOSED leading bold/italic run, or as a bare
#      token followed by a separator. Neither a sentence that mentions "the TL;DR rule"
#      mid-paragraph NOR a heading that merely contains the token (`## Is the TL;DR rule
#      required?`) matches: the first cut anchored the heading row at the `#` and then
#      allowed anything before the token, which cleared exactly that heading. The failure
#      is toward refusal. THE MARKER IS DELIBERATELY SPELLED THREE WAYS
#      BECAUSE THE RULE ITSELF IS MOVING: `CONVENTIONS.md` today specifies a bold
#      `**TL;DR** —` line, and `ai-bridge-v5/task-007` will require the named heading
#      `## Description (TL;DR)` opening every body. A gate that pinned either spelling
#      exclusively would refuse correct pull requests the day the other landed — and a
#      gate that refuses correct work is a gate somebody switches off. Both forms clear
#      here, today and after that change.
#
#   2. THE ACCEPTANCE-CRITERIA TABLE — THE SAME ARTIFACT THE MERGE GATE ALREADY READS.
#      `SCHEMA.md` clause 7 and `AUTONOMY.md` precondition 3 consume the `✓`/`✗` table in
#      the PR body; this file does not introduce a second format, it requires that one.
#      WELL-FORMED IS ASSERTED THE WAY THE HOST DEFINES IT: a header row, a delimiter row
#      with the SAME NUMBER OF CELLS (GitHub renders no table at all when those differ,
#      and a table that does not render is not a table a human can read), and at least one
#      data row. Plus one identifying property — at least one data row carries a `✓` or a
#      `✗` — so that a table of changed files is not mistaken for the criteria table. A
#      body whose marks are spelled some other way (`[x]`, "yes") is REFUSED, which is
#      again the safe direction: a glance, not a clearance.
#
# WHAT THIS DOES NOT DO, AND WHOSE JOB THAT IS. It answers "is the criteria table there
# and well-formed", never "is every row `✓`". WHETHER EVERY ROW IS `✓` STAYS
# `AUTONOMY.md` PRECONDITION 3 / `SCHEMA.md` CLAUSE 7 — an unverified criterion blocking
# clearance is an existing gate with an existing reader, and duplicating it here would
# give the repo two answers to one question. This file closes the gap that nothing read
# the body's SHAPE at all.
#
# GENERIC TEMPLATE FILE — symlinked from the `ai-bridge` template; do not edit per
# instance. It takes no org, repo or vendor identity: those come from the arguments.
#
# Exit codes — 0 is the ONLY clearance; every other code is a refusal:
#
#   0  the body carries a TL;DR marker AND a well-formed criteria table, at whatever
#      length
#   1  the body is readable and a required element is MISSING. stderr names which one —
#      the TL;DR line, the table, or both
#   2  usage error, or the environment cannot answer (no `gh`/`jq`, an unreadable PR, an
#      unreadable body file, a pattern table that will not compile, or a `--head` that no
#      longer matches the PR) — UNKNOWN, and unknown is never clearance
#
# FAILS CLOSED. A body this script cannot fetch is not an empty body: reading a transient
# 5xx as "no body" would be a refusal today and a clearance the moment anything downstream
# treated one of these codes as benign, so the fetch refuses at exit 2 rather than
# proceeding with an empty string.
#
# WHAT IT PRINTS IS UNTRUSTED TEXT. The body comes from a pull request, which anyone able
# to open one can write. Nothing from it is echoed back except the names of the elements
# that were missing, and no part of it is an input to anything but the two matches above.
#
# AND A TRUNCATED COPY OF THIS FILE IS UNKNOWN STATE TOO — the sibling's lesson, taken
# whole: `--self-test` proves this file RUNS, which is not proving it is COMPLETE. A copy
# cut off below the self-test block still runs and still prints the sentinel. The last
# line of this file is therefore a completeness sentinel, asserted by `--self-test`, which
# no cut short of the end can satisfy.
#
# No `set -e`: a `grep` that finds nothing is an ANSWER here, not a fault, and under `-e`
# the first such test would exit the script with a success-looking code. Every failure
# path below is explicit.
set -uo pipefail

# --- table 1: what a TL;DR marker line looks like -----------------------------
# One POSIX ERE per line, matched case-insensitively against the fence-stripped body.
# Blank lines and whole-line `#` comments are ignored; a pattern may not carry a trailing
# comment, because the whole line is the pattern. Same reading rules as the sibling's
# tables, and — like them — every row is compiled up front by `validate_tables`, because
# a table that will not compile is not a table that matches less, it is a table that
# matches NOTHING, and here that turns every PR into a refusal nobody can explain.
#
# EVERY ROW IS ANCHORED AT THE START OF A LINE. That anchor is the fail-closed property:
# without it, a body that discusses the TL;DR rule in a sentence would clear on the
# discussion. Row 1 is the heading form `## Description (TL;DR)` that `task-007`
# introduces; row 2 is the leading-emphasis form `**TL;DR** — …` that `CONVENTIONS.md`
# specifies today; row 3 is the bare token followed by a separator, which is what an
# author writes when they are not looking at either document.
TLDR_MARKERS='
^[[:space:]]{0,3}#{1,6}[[:space:]]+(description[[:space:]]*)?\(?tl[;:/ ]?dr
^[[:space:]]{0,3}(\*\*|__|\*|_)[[:space:]]*(description[[:space:]]*)?\(?tl[;:/ ]?dr\)?[[:space:]]*(\*\*|__|\*|_)
^[[:space:]]{0,3}\(?tl[;:/ ]?dr\)?[[:space:]]*[]):：.,;—–-]
'

# --- table 2: the marks that identify the ACCEPTANCE-CRITERIA table ------------
# Fixed strings, not EREs — these are the two glyphs `SCHEMA.md` clause 7 and
# `AUTONOMY.md` precondition 3 already read, and this file requires that same artifact
# rather than inventing a second one. A data row carrying one of them is what tells the
# criteria table apart from any other table in a body.
CRITERIA_MARKS='✓
✗'

usage() {
  echo "Usage: $(basename "$0") <pr> [--repo <owner>/<name>] [--head <sha>]" >&2
  echo "       $(basename "$0") --body-file <path>   (decide on a local draft)" >&2
  echo "       $(basename "$0") --self-test          (prove this script RUNS)" >&2
  exit 2
}

# `rows <table>` strips comments and blank lines; every table is read through it, so a
# malformed row is inert rather than silently matching everything.
rows() { printf '%s\n' "$1" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' \
                                  | grep -v '^#' | grep -v '^$'; }

# Compile every ERE row before anything is classified with it. Checked here (up front),
# and again in --self-test so the caller refuses a sibling carrying a broken table.
validate_tables() {
  local bad="" r
  while IFS= read -r r; do
    [ -n "$r" ] || continue
    printf '' | grep -Eq "$r" 2>/dev/null || [ $? -eq 1 ] || bad="$bad          $r
"
  done <<EOF
$(rows "$TLDR_MARKERS")
EOF
  [ -z "$bad" ] || {
    echo "error: these rows in this script's TL;DR table are not valid POSIX EREs, so" >&2
    echo "       the table matches nothing and every PR would be refused for a reason" >&2
    echo "       that is not about its body. Refusing (fail closed):" >&2
    printf '%s' "$bad" >&2
    return 2
  }
  return 0
}

# --- the rendering both tests read -------------------------------------------
# ONE question: which lines of this body would a reader actually see as content? Fenced
# blocks (``` and ~~~, at up to three spaces of indent, closed or left open to EOF) are
# removed, because a body that QUOTES the convention's example would otherwise clear on
# the example. Carriage returns go too — the host stores CRLF for a body typed in the web
# editor, and a stray \r at end of line defeats an anchored match for no reason a human
# could see.
#
# THE STRIPPER IS A TOGGLE, AND AN UNBALANCED FENCE THEREFORE BLANKS THE REST OF THE BODY.
# That is the fail-closed direction HERE and it is worth stating, because in
# `review-clearance.sh` the same property was a defect: there, a blanked body stopped a
# REFUSAL being seen, which cleared a PR. Here everything downstream needs to FIND
# something, so a blanked body finds neither element and refuses. An author who opens a
# fence and never closes it gets a refusal and a glance, which is the correct answer to a
# body the host will render as one long code block anyway.
render_body() { # <src> <dst>
  tr -d '\r' < "$1" | awk '
    {
      line = $0
      if (fence == 0) {
        if (match(line, /^[[:space:]]{0,3}(`{3,}|~{3,})/)) {
          opener = substr(line, RSTART, RLENGTH)
          sub(/^[[:space:]]+/, "", opener)
          fchar = substr(opener, 1, 1)
          fwidth = length(opener)
          fence = 1
          next
        }
        print line
        next
      }
      # Inside a fence, and CommonMark closes one ONLY on a run of the SAME character
      # that is at least as long, with nothing but whitespace after it. A toggle that
      # closed on any fence line read a ``` nested inside a ````md block as the closer,
      # exposing the QUOTED content below it as body content — which is the one direction
      # that matters, because quoted content is exactly what must not clear this gate.
      if (match(line, /^[[:space:]]{0,3}(`{3,}|~{3,})[[:space:]]*$/)) {
        closer = substr(line, RSTART, RLENGTH)
        gsub(/[[:space:]]/, "", closer)
        if (substr(closer, 1, 1) == fchar && length(closer) >= fwidth) fence = 0
      }
      next
    }
  ' > "$2"
}

# --- element 1: is there a TL;DR marker line? --------------------------------
#   0 yes   1 no   2 the table will not compile (unknown; the caller refuses)
has_tldr() { # <rendered-body>
  local pat rc
  while IFS= read -r pat; do
    [ -n "$pat" ] || continue
    grep -Eiq "$pat" "$1" 2>/dev/null; rc=$?
    [ "$rc" -eq 0 ] && return 0
    [ "$rc" -eq 1 ] || return 2
  done <<EOF
$(rows "$TLDR_MARKERS")
EOF
  return 1
}

# --- element 2: is the acceptance-criteria table present and well-formed? -----
# Prints one word:
#   ok        a header + a cell-count-matching delimiter + >=1 data row, and a data row
#             carries one of the marks the merge gate reads
#   unmarked  a well-formed table exists, but no data row carries `✓`/`✗` — so it is some
#             other table, and the criteria table is absent
#   none      no well-formed table at all
#
# GREP'S STATUS IS NOT CONSULTED HERE BECAUSE NOTHING IS GREPPED: the shape is decided
# structurally, in one awk pass, which is the same move the sibling made when it took
# evidence and pinning off prose and onto the structured API.
table_state() { # <rendered-body>
  # awk's `-v` cannot carry a literal newline, so the table travels as one RS-separated
  # (0x1e) field and is split back below. A record separator cannot occur in a PR body
  # the host serves as JSON text, so nothing an author writes can add a row here.
  awk -v marks="$(rows "$CRITERIA_MARKS" | tr '\n' '\036')" '
    function cellcount(s,   arr, n) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
      # An ESCAPED pipe is content, not a cell boundary — that is how GFM says to put a
      # `|` inside a cell, and counting it as a boundary would inflate the header past
      # the delimiter row and refuse a table the host renders perfectly.
      gsub(/\\\|/, "", s)
      sub(/^\|/, "", s); sub(/\|$/, "", s)
      n = split(s, arr, "|")
      return n
    }
    # A delimiter row is one whose EVERY cell is a GFM delimiter cell — a run of dashes
    # with an optional leading and/or trailing colon. Asking only whether the LINE is made
    # of pipes, dashes, colons and spaces is not the same question and is weaker in the
    # dangerous direction: `|---|:|` passes that test while GitHub renders no table at
    # all, so a marked row underneath it would have cleared a non-table. GitHub also
    # renders nothing when the cell count differs from the header row above, and that
    # equality is checked at the call site.
    function is_delim(s,   arr, n, i, c) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
      if (index(s, "|") == 0) return 0
      sub(/^\|/, "", s); sub(/\|$/, "", s)
      n = split(s, arr, "|")
      if (n < 1) return 0
      for (i = 1; i <= n; i++) {
        c = arr[i]
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", c)
        if (c !~ /^:?-+:?$/) return 0
      }
      return 1
    }
    function has_mark(s,   i, n, m) {
      n = split(marks, m, "\036")
      for (i = 1; i <= n; i++) if (m[i] != "" && index(s, m[i]) > 0) return 1
      return 0
    }
    { lines[NR] = $0 }
    END {
      found = 0; marked = 0
      for (i = 2; i <= NR; i++) {
        if (!is_delim(lines[i])) continue
        head = lines[i-1]
        if (index(head, "|") == 0) continue
        if (cellcount(head) < 2) continue
        if (cellcount(head) != cellcount(lines[i])) continue
        rowcount = 0; rowmarked = 0
        for (j = i + 1; j <= NR; j++) {
          if (index(lines[j], "|") == 0) break
          if (lines[j] ~ /^[[:space:]]*$/) break
          rowcount++
          if (has_mark(lines[j])) rowmarked = 1
        }
        if (rowcount < 1) continue
        found = 1
        if (rowmarked) marked = 1
      }
      if (found && marked) { print "ok"; exit }
      if (found)           { print "unmarked"; exit }
      print "none"
    }
  ' "$1"
}

# --- the verdict, over a body already on disk ---------------------------------
# The ONE place a body becomes an exit code, so both call sites (a fetched PR and a local
# draft) answer identically. <label> only names the subject in the messages.
decide() { # <rendered-body> <label> -> 0 clear, 1 refuse, 2 unknown
  local rendered="$1" label="$2" tldr tstate rc
  has_tldr "$rendered"; tldr=$?
  [ "$tldr" -eq 2 ] && return 2
  tstate="$(table_state "$rendered")"
  case "$tstate" in ok|unmarked|none) : ;; *) return 2 ;; esac

  [ "$tldr" -eq 0 ] && [ "$tstate" = ok ] && {
    echo "ok: $label carries a TL;DR line and a well-formed acceptance-criteria table." >&2
    return 0
  }

  echo "refuse: $label does not carry the shape CONVENTIONS.md requires of a PR body." >&2
  rc=1
  [ "$tldr" -eq 0 ] || {
    echo "        MISSING: the TL;DR line. One sentence — what changes, and why it is" >&2
    echo "        safe to merge — as '## Description (TL;DR)' or a leading '**TL;DR**'." >&2
  }
  case "$tstate" in
    none)
      echo "        MISSING: the acceptance-criteria table. One row per criterion, a" >&2
      echo "        '✓'/'✗', and the evidence. No well-formed markdown table was found" >&2
      echo "        (a header row, a delimiter row with the same number of cells, and at" >&2
      echo "        least one data row)." >&2 ;;
    unmarked)
      echo "        MISSING: the acceptance-criteria table. A well-formed table is here," >&2
      echo "        but no row of it carries a '✓' or a '✗' — that column IS the checkbox" >&2
      echo "        state SCHEMA.md clause 7 and AUTONOMY.md read, so as written there is" >&2
      echo "        nothing for the merge gate to consult." >&2 ;;
  esac
  echo "        This refuses on missing STRUCTURE, never on length: a long body carrying" >&2
  echo "        both elements clears. See CONVENTIONS.md, 'The PR body has a required" >&2
  echo "        shape'." >&2
  return "$rc"
}

# --- --self-test: no network, no PR -------------------------------------------
#
# It PROVES THIS SCRIPT RUNS, which `[ -x ]` does not. A dead shebang, a syntax error, a
# zero-byte file and a copy truncated half-way through an install all carry the executable
# bit and then fail every invocation — which in a caller that treats a non-zero code as
# "refuse" would look like a gate working perfectly while it read nothing at all. So
# `required-checks.sh` runs this first and refuses unless it exits 0 AND prints
# SELFTEST_OK verbatim. That string is the contract between the two files, duplicated
# there on purpose: a shared constant would have to be sourced, and sourcing a broken file
# is the failure being tested for.
#
# THE CONTROLS ARE THE POINT — a banner would pass for any stub that prints a banner. This
# drives the real decision function in BOTH directions over four literal bodies, so a copy
# whose tables no longer fire cannot answer 0 here.
#
# AND "IT RUNS" IS NOT "IT IS COMPLETE": this block sits near the TOP, so a copy truncated
# below it would still reach this exit. The last line of the file is asserted here.
SELFTEST_OK="pr-body-clearance: self-test ok"
EOF_SENTINEL="#EOF: pr-body-clearance.sh is complete to here"
if [ "${1:-}" = "--self-test" ]; then
  [ "$#" -eq 1 ] || usage
  [ -r "$0" ] || {
    echo "self-test: cannot read '$0' to prove it is complete — refusing" >&2; exit 2; }
  [ "$(tail -n 1 "$0")" = "$EOF_SENTINEL" ] || {
    echo "self-test: this file does not end with its completeness sentinel, so it is" >&2
    echo "           truncated or was cut short — the tables and the classifier below" >&2
    echo "           this line cannot be assumed to be here. Refusing." >&2; exit 2; }
  TMPD="$(mktemp -d)" || {
    echo "self-test: could not create a temp dir — refusing" >&2; exit 2; }
  trap 'rm -rf "$TMPD"' EXIT
  validate_tables || exit 2

  st_probe() { # <expected-rc> <name> <body lines...>
    local want="$1" name="$2"; shift 2
    printf '%s\n' "$@" > "$TMPD/raw"
    render_body "$TMPD/raw" "$TMPD/rendered"
    decide "$TMPD/rendered" "self-test body" >/dev/null 2>&1
    [ "$?" -eq "$want" ] || {
      echo "self-test: $name did not answer $want — refusing" >&2; exit 2; }
  }

  st_probe 0 "a conforming body (heading form)" \
    '## Description (TL;DR)' 'It does the thing.' '' \
    '| Criterion | ✓ | Verified by |' '|---|---|---|' '| it works | ✓ | a.test.sh |'
  st_probe 0 "a conforming body (bold form)" \
    '**TL;DR** — it does the thing.' '' \
    '| Criterion | ✓ | Verified by |' '|---|---|---|' '| it works | ✗ | needs a human |'
  st_probe 1 "a body with no TL;DR marker" \
    'It does the thing.' '' \
    '| Criterion | ✓ | Verified by |' '|---|---|---|' '| it works | ✓ | a.test.sh |'
  st_probe 1 "a body with no criteria table" \
    '## Description (TL;DR)' 'It does the thing.' '' 'Some prose and nothing else.'
  st_probe 1 "a body whose only table is inside a code fence" \
    '## Description (TL;DR)' 'It does the thing.' '' '```md' \
    '| Criterion | ✓ | Verified by |' '|---|---|---|' '| it works | ✓ | a.test.sh |' '```'

  printf '%s\n' "$SELFTEST_OK"
  exit 0
fi

# --- argument parsing ---------------------------------------------------------
pr=""; repo=""; want_head=""; body_file=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo)      repo="${2:-}";      [ -n "$repo" ] || usage; shift 2 ;;
    --head)      want_head="${2:-}"; [ -n "$want_head" ] || usage; shift 2 ;;
    --body-file) body_file="${2:-}"; [ -n "$body_file" ] || usage; shift 2 ;;
    -h|--help)   usage ;;
    -*) echo "error: unknown option '$1'" >&2; usage ;;
    *) [ -z "$pr" ] || { echo "error: unexpected argument '$1'" >&2; usage; }
       pr="$1"; shift ;;
  esac
done

validate_tables || exit 2

command -v jq >/dev/null 2>&1 || {
  echo "error: jq not found — the body cannot be read, so this refuses (fail closed)" >&2
  exit 2
}

TMPD="$(mktemp -d)" || {
  echo "error: could not create a temp dir — refusing (fail closed)" >&2
  exit 2
}
trap 'rm -rf "$TMPD"' EXIT

# --- route 1: a local draft, so an author can check before opening the PR ------
# It exists because the cheapest moment to catch a malformed body is before it is
# published, and an author who has to open the PR to learn the shape was wrong will fix
# it in a force-push nobody reads. It is not the gate: `required-checks.sh` always takes
# route 2, against what the host actually serves.
if [ -n "$body_file" ]; then
  [ -z "$pr" ] && [ -z "$repo" ] && [ -z "$want_head" ] || {
    echo "error: --body-file decides on a local file; it takes no PR, repo or head." >&2
    usage
  }
  [ -r "$body_file" ] || {
    echo "error: cannot read '$body_file' — a body this script cannot read is unknown" >&2
    echo "       state, and unknown is never clearance. Refusing." >&2
    exit 2
  }
  # `jq -Rs length` counts CODE POINTS, which is what the host reports as a body's
  # length; `wc -c` would count UTF-8 bytes and disagree with the number in the incident
  # this file exists for. INFORMATION ONLY — see the header; nothing below reads it.
  body_chars="$(jq -Rs 'length' < "$body_file" 2>/dev/null)" || body_chars="unknown"
  echo "pr-body-clearance: $body_file is $body_chars characters (information only —" >&2
  echo "                   no exit code in this script is derived from that number)" >&2
  render_body "$body_file" "$TMPD/rendered"
  decide "$TMPD/rendered" "'$body_file'"
  exit $?
fi

# --- route 2: the actual PR body, from the host -------------------------------
[ -n "$pr" ] || usage

command -v gh >/dev/null 2>&1 || {
  echo "error: gh not found — the PR body cannot be read, so this refuses" >&2
  exit 2
}

# bash 3.2 (the macOS default) errors on "${arr[@]}" when arr is empty under `set -u`.
R=()
[ -n "$repo" ] && R=(--repo "$repo")

# A FETCH THAT ERRORS IS NOT AN EMPTY BODY. Reading a transient 5xx as "no body" is a
# refusal today and would be a clearance the moment anything downstream treated one of
# these codes as benign, so this refuses at exit 2 instead of classifying an empty string.
raw="$(gh pr view "$pr" ${R[@]+"${R[@]}"} \
       --json url,number,body,headRefOid 2>/dev/null)" || {
  echo "error: could not read PR $pr${repo:+ in $repo} — its body is unknown, and" >&2
  echo "       unknown is never clearance. Refusing (fail closed)." >&2
  exit 2
}

head_sha="$(printf '%s' "$raw" | jq -r '.headRefOid // ""' 2>/dev/null)" || head_sha=""
url="$(printf '%s' "$raw" | jq -r '.url // ""' 2>/dev/null)" || url=""
[ -n "$head_sha" ] && [ -n "$url" ] || {
  echo "error: could not resolve the head SHA / URL of PR $pr — the answer would be" >&2
  echo "       about a PR this script cannot identify. Refusing (fail closed)." >&2
  exit 2
}

# The verified head the caller pinned must still be the PR's head. Same guard as the two
# siblings: if it moved, every answer here is about a different state of the pull request,
# which is unknown rather than refused.
if [ -n "$want_head" ] && [ "$want_head" != "$head_sha" ]; then
  echo "error: head moved — verified $want_head, PR $pr is now at $head_sha. The body" >&2
  echo "       read here is not the one that was verified. Refusing (fail closed)." >&2
  exit 2
fi

# An ABSENT body field is a read that did not answer; an EMPTY one is a body somebody
# left blank. Both refuse, but not with the same code — a blank body is a real, readable
# PR missing both elements, and telling its author that is more useful than "unknown".
printf '%s' "$raw" | jq -e 'has("body")' >/dev/null 2>&1 || {
  echo "error: PR $pr reports no body field at all, so its body is unknown rather than" >&2
  echo "       empty. Unknown is never clearance. Refusing (fail closed)." >&2
  exit 2
}
printf '%s' "$raw" | jq -r '.body // ""' > "$TMPD/body" 2>/dev/null || {
  echo "error: the body of PR $pr could not be extracted — refusing (fail closed)" >&2
  exit 2
}

# INFORMATION ONLY. Taken from the JSON string's own length, so it is the host's count of
# characters rather than a byte count of a file. Nothing below reads it; see the header.
body_chars="$(printf '%s' "$raw" | jq -r '(.body // "") | length' 2>/dev/null)" \
  || body_chars="unknown"
echo "pr-body-clearance: PR $pr body is $body_chars characters (information only — no" >&2
echo "                   exit code in this script is derived from that number)" >&2

render_body "$TMPD/body" "$TMPD/rendered"
decide "$TMPD/rendered" "the body of PR $pr ($url)"
exit $?

# --- completeness sentinel — THIS MUST REMAIN THE LAST LINE OF THIS FILE -------
# `--self-test` asserts that the last line of this file is exactly the line below, which
# is how a truncated copy is told from a complete one. See the header.
#EOF: pr-body-clearance.sh is complete to here
