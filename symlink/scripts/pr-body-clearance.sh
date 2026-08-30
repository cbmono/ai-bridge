#!/usr/bin/env bash
#
# pr-body-clearance.sh — assert that a pull request's BODY carries the required SHAPE:
# a TL;DR line and a well-formed acceptance-criteria table whose rows stay inside the
# two-sided bound `CONVENTIONS.md` puts on their evidence. This is precondition 3 of the
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
# SO THE BODY'S LENGTH IS INFORMATION, NEVER A VERDICT. The character count is computed
# once, printed on stderr on every run that reads a body, and never read again: NO
# THRESHOLD, NO CONSTANT AND NO COMPARISON ON IT EXISTS ANYWHERE BELOW.
# `tests/pr-body-clearance.test.sh` asserts that statically (the count variable never
# appears on a line with a comparison operator) as well as behaviourally (a body far
# longer than the motivating one clears).
#
# EXACTLY ONE LENGTH IS COMPARED HERE, AND IT IS NOT THE BODY'S: the EVIDENCE CELL of a
# single acceptance-criteria row (element 3 below). The two are opposites, not a
# compromise. A body grows because the change is large, which is honest and is exactly
# when a reader needs the words; a ROW grows because its author put the reasoning in the
# table instead of the task doc, which is the defect `CONVENTIONS.md` already names and
# the one every measured regression has landed in. Bounding the body would refuse the
# first; bounding the cell catches the second. So the numbers this file compares are an
# argument count, a table's cell count, a code fence's width, an exit status, and ONE
# CELL of ONE ROW of ONE TABLE — never the prose around it, and never the sum.
#
# THE TWO TEXT-MATCHED ELEMENTS, AND WHICH DIRECTION EACH MATCH FAILS IN. Text matching
# is unavoidable
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
#   3. THE TWO-SIDED BOUND ON EACH CRITERIA ROW'S EVIDENCE CELL — MEASURED, NOT MATCHED.
#      `CONVENTIONS.md` has bounded that cell on both sides since 2026-08-29: a ceiling
#      ("a row carries what a reviewer needs to CHECK THE CLAIM, and stops — narration is
#      not wanted") and a floor ("short is the goal; cryptic is a failure"). NOTHING READ
#      IT, and a day later ai-bridge#71 shipped criteria rows of 500-600 characters whose
#      evidence column carried shell one-liners and their own reasoning — inside the very
#      machinery built to end unread rules. This element is that reader.
#
#      THE CELL, NOT THE ROW, AND THAT CHOICE IS FORCED BY THE DATA. A row also carries
#      the criterion text VERBATIM from the task document, which its author may not
#      shorten; charging that against a bound would punish an author for obeying a
#      different rule. Measured over the whole criteria table of three real pull requests
#      on 2026-08-30 (34 rows), whole-row length does not separate them at all — #70's
#      worst row is 577 bytes and #71's is 588 — while the evidence cell separates them
#      cleanly:
#
#          PR     rows   evidence cell, worst      verdict wanted
#          #67     11    377                       pass
#          #70     11    325                       pass
#          #71     12    422, 462, 487             fail (exactly these three)
#
#      CEILING 400 BYTES — the midpoint of the empty band 378-421, which is the widest
#      gap in the corpus. It leaves 23 bytes over the largest honest cell and stops 22
#      short of the smallest offending one, and it fails EXACTLY the three rows the
#      incident names and no other row of the 34. FLOOR 13 BYTES — the midpoint of 9 and
#      17, likewise measured: `see above` (9) is the longest thing `CONVENTIONS.md` names
#      as a floor FAILURE, and `CI run 1234 green` (17) is the shortest thing it offers as
#      real evidence, with #70's shortest genuine cell also 17. Both numbers therefore
#      have a margin on each side rather than sitting on an observation, and neither was
#      chosen for being round.
#
#      IT IS COUNTED IN BYTES, UNDER `LC_ALL=C`, ON PURPOSE. `length()` counts characters
#      in some awks and bytes in others, so an unpinned locale would put the threshold in
#      a different place on a developer's macOS than on CI — a gate whose verdict depends
#      on the machine is not a gate. Bytes are the reproducible unit; the numbers above
#      were measured the same way.
#
#      BOTH SIDES FAIL LOUDLY AND NAME THE ROW. A bare exit code sends the author back to
#      diff their own table against a threshold; the refusal below prints, per offending
#      row, its index, its measured length, the bound it broke and a bounded excerpt of
#      its criterion text.
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
#   0  the body carries a TL;DR marker AND a well-formed criteria table whose every row
#      is inside the evidence bound, at whatever total length
#   1  the body is readable and a required element is MISSING. stderr names which one —
#      the TL;DR line, the table, or both
#   2  usage error, or the environment cannot answer (no `gh`/`jq`, an unreadable PR, an
#      unreadable body file, a pattern table that will not compile, or a `--head` that no
#      longer matches the PR) — UNKNOWN, and unknown is never clearance
#   3  the shape is all there, but at least one criteria row's evidence cell is outside
#      the two-sided bound. stderr names every offending row. A SEPARATE CODE because the
#      fix is different — 1 says "add the missing thing", 3 says "move the reasoning to
#      the task doc" or "say what to run" — and callers that already treat any non-zero
#      as a refusal (`required-checks.sh`) need no change to honour it
#
# FAILS CLOSED. A body this script cannot fetch is not an empty body: reading a transient
# 5xx as "no body" would be a refusal today and a clearance the moment anything downstream
# treated one of these codes as benign, so the fetch refuses at exit 2 rather than
# proceeding with an empty string.
#
# WHAT IT PRINTS IS UNTRUSTED TEXT. The body comes from a pull request, which anyone able
# to open one can write. Nothing from it is echoed back except the names of the elements
# that were missing and, for a row outside the bound, an EXCERPT of that row's criterion
# text — reduced to printable ASCII (every other byte becomes `.`, which under `LC_ALL=C`
# also removes every control byte and so every terminal escape) and truncated to 60 bytes.
# No part of the body is an input to anything but the two matches and the one measurement
# above.
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

# --- table 3: the two-sided bound on one criteria row's EVIDENCE cell ----------
# Bytes, under `LC_ALL=C`. Both numbers are midpoints of a measured empty band, not round
# numbers — element 3 of the header carries the corpus and the arithmetic. Moving either
# one means re-measuring: `tests/pr-body-clearance.test.sh` pins all four boundary values
# (377 and 325 clear, 422 and 487 refuse; 17 clears, 9 refuses), so a change made without
# the measurement goes red rather than through.
#
# THIS IS NOT A BODY LENGTH AND MUST NEVER BECOME ONE. Nothing below sums these, and
# nothing below compares them to `body_chars`; see the header.
CRITERIA_EVIDENCE_CEILING=400
CRITERIA_EVIDENCE_FLOOR=13

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

# --- elements 2 and 3: the table's shape, and each of its rows' evidence ------
# ONE PASS, ONE PARSER, ON PURPOSE. Elements 2 and 3 ask two questions of the same
# artifact ("is the criteria table well-formed" and "is each of its rows inside the
# bound"), and a second parser for the second question would give this repo two answers
# to "which table is the criteria table" — the exact defect this file's header warns
# about one level up. So the table is located once and both answers come out of that.
#
# Output is TAB-separated, state first:
#   state<TAB>ok        a header + a cell-count-matching delimiter + >=1 data row, and a
#                       data row carries one of the marks the merge gate reads
#   state<TAB>unmarked  a well-formed table exists, but no data row carries `✓`/`✗` — so
#                       it is some other table, and the criteria table is absent
#   state<TAB>none      no well-formed table at all
#   row<TAB>over|under<TAB><n><TAB><bytes><TAB><criterion excerpt>
#                       one line per criteria row outside the bound. Emitted only for
#                       rows that CARRY A MARK, so a continuation or spacer row inside
#                       the table is never measured as if it were a criterion.
#
# GREP'S STATUS IS NOT CONSULTED HERE BECAUSE NOTHING IS GREPPED: the shape is decided
# structurally, in one awk pass, which is the same move the sibling made when it took
# evidence and pinning off prose and onto the structured API.
#
# `LC_ALL=C` PINS THE UNIT. See element 3 in the header: `length()` is characters in some
# awks and bytes in others, and a threshold that moves with the machine is not a
# threshold. It changes nothing else here — every pattern in this program is ASCII, and
# the marks are compared with `index()`, which is a byte search either way.
table_scan() { # <rendered-body>
  # awk's `-v` cannot carry a literal newline, so the table travels as one RS-separated
  # (0x1e) field and is split back below. A record separator cannot occur in a PR body
  # the host serves as JSON text, so nothing an author writes can add a row here.
  LC_ALL=C awk -v marks="$(rows "$CRITERIA_MARKS" | tr '\n' '\036')" \
       -v ceiling="$CRITERIA_EVIDENCE_CEILING" -v floor="$CRITERIA_EVIDENCE_FLOOR" '
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
    # A cell that is NOTHING BUT a mark — `✓`, `**✗**`, `` `✓` `` — is the merge-gate
    # column, not evidence and not criterion text. A cell that merely CONTAINS a mark is
    # content. An EMPTY cell is neither: it answers 0, so that a row whose evidence cell
    # was left blank is measured (at length 0) rather than skipped over.
    function mark_only(c,   t) {
      t = c
      gsub(/[*_` ~]/, "", t)
      if (t == "") return 0
      # One glyph and nothing else: 3 bytes under LC_ALL=C, 1 character if some future
      # caller loses that pinning. `<= 3` covers both rather than depending on it.
      return has_mark(t) && length(t) <= 3
    }
    # Splits one row into R_EVI (the evidence cell), R_LABEL (a bounded, sanitised excerpt
    # of the cells before it) and R_MARKLAST (the row has no evidence column at all).
    #
    # EVIDENCE IS THE LAST CELL. Not "the last cell that is not a mark", which sounds more
    # forgiving and is worse: it silently skips a BLANK evidence cell and reports the
    # criterion text in its place, so the one row with no evidence at all is the one row
    # that clears. Last-cell is also the shape the CONVENTIONS.md example prescribes and
    # the shape all three measured pull requests use, and reading from the right means an
    # extra leading column (an index, as in #71) costs nothing. A row whose last cell is
    # the bare mark has put the evidence somewhere this reader will not look, and says so
    # in those words rather than measuring the mark.
    # (No apostrophes below this line until the closing quote — the whole awk program is
    # one single-quoted shell word, so one would end it.)
    function split_row(s,   arr, n, i, c, out) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
      gsub(/\\\|/, "\002", s)      # an escaped pipe is CONTENT, exactly as in cellcount
      sub(/^\|/, "", s); sub(/\|$/, "", s)
      n = split(s, arr, "|")
      R_EVI = ""; R_LABEL = ""; R_MARKLAST = 0
      if (n < 1) return 0
      R_EVI = arr[n]
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", R_EVI)
      R_MARKLAST = mark_only(R_EVI)
      gsub(/\002/, "|", R_EVI)
      out = ""
      for (i = 1; i < n; i++) {
        c = arr[i]
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", c)
        if (c == "" || mark_only(c)) continue
        out = (out == "" ? c : out " " c)
      }
      # UNTRUSTED TEXT LEAVES HERE. Under LC_ALL=C `[:print:]` is ASCII 0x20-0x7e, so this
      # one substitution strips control bytes (and so every terminal escape) and the
      # trailing half of a multi-byte character the truncation below could otherwise cut
      # in two. Then a fixed 60 bytes, because an excerpt that identifies the row is the
      # whole job and a body must not be able to print itself through this gate.
      gsub(/\002/, "|", out)       # restore first: a `|` is content and must survive
      gsub(/[^[:print:]]/, ".", out)
      if (length(out) > 60) out = substr(out, 1, 57) "..."
      R_LABEL = (out == "" ? "(row " nth ")" : out)
      return 1
    }
    { lines[NR] = $0 }
    END {
      found = 0; marked = 0; nth = 0; offenders = ""
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
          if (!has_mark(lines[j])) continue
          rowmarked = 1
          # ELEMENT 3, measured on this row and nothing else. A row with no evidence cell
          # at all reports length 0, which is a floor failure — the honest answer, since
          # a criterion whose evidence column is empty is exactly the assertion-without-
          # evidence the floor exists to refuse.
          nth++
          if (!split_row(lines[j])) continue
          len = length(R_EVI)
          if (R_MARKLAST)
            offenders = offenders sprintf("row\tmark\t%d\t%d\t%s\n", nth, len, R_LABEL)
          else if (len > ceiling)
            offenders = offenders sprintf("row\tover\t%d\t%d\t%s\n", nth, len, R_LABEL)
          else if (len < floor)
            offenders = offenders sprintf("row\tunder\t%d\t%d\t%s\n", nth, len, R_LABEL)
        }
        if (rowcount < 1) continue
        found = 1
        if (rowmarked) marked = 1
      }
      # The state line comes FIRST and always, so a reader can take the verdict without
      # having to know how many row lines follow it.
      if (found && marked)  printf "state\tok\n"
      else if (found)       printf "state\tunmarked\n"
      else                  printf "state\tnone\n"
      # Rows are only ever reported for the state the caller acts on. Under `unmarked` or
      # `none` there is no criteria table, so a length measured inside some other table
      # would be a refusal about a row nobody wrote as a criterion.
      if (found && marked) printf "%s", offenders
    }
  ' "$1"
}

# --- element 3's verdict: the shape is here, are the rows inside the bound? ---
# Reached ONLY when both structural elements are present, so every message below is about
# a body that is otherwise correct.
#
# IT FAILS LOUDLY AND IT NAMES THE ROW, on BOTH sides. A gate that answered `3` and
# stopped would leave the author diffing a twelve-row table against a number they have to
# go and read, and the natural response to that is to stop running the gate. Each
# offending row therefore gets its index, its measured length, which bound it broke, and
# what to do — and the two sides get DIFFERENT advice, because they are different
# mistakes: over the ceiling means the reasoning belongs in the task doc, under the floor
# means the row does not say what to run.
report_rows() { # <scan> <label> -> 0 clear, 3 at least one row outside the bound
  local scan="$1" label="$2" offenders n kind idx len text tab
  tab="$(printf '\t')"
  offenders="$(printf '%s\n' "$scan" | awk -F'\t' '$1 == "row" { print }')"
  [ -n "$offenders" ] || {
    echo "ok: $label carries a TL;DR line and a well-formed acceptance-criteria table." >&2
    return 0
  }
  n="$(printf '%s\n' "$offenders" | grep -c '^')"
  echo "refuse: $label carries both structural elements, but $n acceptance-criteria" >&2
  echo "        row(s) fall outside the two-sided bound CONVENTIONS.md puts on the" >&2
  echo "        EVIDENCE column — floor $CRITERIA_EVIDENCE_FLOOR bytes, ceiling $CRITERIA_EVIDENCE_CEILING bytes:" >&2
  while IFS="$tab" read -r _ kind idx len text; do
    [ -n "${kind:-}" ] || continue
    if [ "$kind" = mark ]; then
      echo "        row $idx has NO evidence column: \"$text\"" >&2
      echo "          Its last cell is the ✓/✗ mark. Evidence goes in the LAST column —" >&2
      echo "          '| Criterion | ✓ | Verified by |' — which is where a reader looks" >&2
      echo "          for it and the only cell this bound reads." >&2
    elif [ "$kind" = over ]; then
      echo "        row $idx over the CEILING at $len bytes: \"$text\"" >&2
      echo "          Cut it to the command and its result. Why you chose the approach," >&2
      echo "          what you tried first and the incident behind it belong in the" >&2
      echo "          commit message and the task doc, which travel with the change." >&2
    else
      echo "        row $idx under the FLOOR at $len bytes: \"$text\"" >&2
      echo "          Name the artifact a reader can re-run — the test file and its" >&2
      echo "          tally, the command, the CI run, the URL. 'ok', 'see above' and a" >&2
      echo "          bare commit SHA tell a reader nothing to do next." >&2
    fi
  done <<EOF
$offenders
EOF
  echo "        This bounds ONE CELL of ONE ROW, never the body: a long body whose rows" >&2
  echo "        are inside the bound clears here, and its character count is reported as" >&2
  echo "        information only. See CONVENTIONS.md, 'The criteria table is the merge" >&2
  echo "        gate'." >&2
  return 3
}

# --- the verdict, over a body already on disk ---------------------------------
# The ONE place a body becomes an exit code, so both call sites (a fetched PR and a local
# draft) answer identically. <label> only names the subject in the messages.
decide() { # <rendered-body> <label> -> 0 clear, 1 refuse, 2 unknown, 3 a row is unbounded
  local rendered="$1" label="$2" tldr scan tstate rc
  has_tldr "$rendered"; tldr=$?
  [ "$tldr" -eq 2 ] && return 2
  scan="$(table_scan "$rendered")"
  tstate="$(printf '%s\n' "$scan" | awk -F'\t' '$1 == "state" { print $2; exit }')"
  case "$tstate" in ok|unmarked|none) : ;; *) return 2 ;; esac

  # STRUCTURE IS DECIDED BEFORE THE ROW BOUND, AND THAT ORDER IS THE POINT. Exit 1 says a
  # required element is missing; exit 3 says every element is there and one row is out of
  # bounds. Reporting the second while the first is unresolved would tell an author to
  # trim rows of a table the gate has not agreed exists.
  [ "$tldr" -eq 0 ] && [ "$tstate" = ok ] && { report_rows "$scan" "$label"; return $?; }

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
# drives the real decision function in EVERY direction it can answer in — clear, missing
# element, over the ceiling, under the floor — so a copy whose tables no longer fire, or
# whose row bound has been quietly widened to infinity, cannot answer 0 here. The two row
# probes are built at the MEASURED boundary values (element 3), not at a comfortable
# distance from them, so a copy that moved the constant by a little fails as surely as one
# that deleted it.
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

  # An evidence cell of exactly <n> bytes, so the two row probes sit ON the measured
  # boundary rather than near it.
  st_cell() { printf '%*s' "$1" '' | tr ' ' 'x'; }

  st_probe 0 "a conforming body (heading form)" \
    '## Description (TL;DR)' 'It does the thing.' '' \
    '| Criterion | ✓ | Verified by |' '|---|---|---|' '| it works | ✓ | `a.test.sh` 40/0 |'
  st_probe 0 "a conforming body (bold form)" \
    '**TL;DR** — it does the thing.' '' \
    '| Criterion | ✓ | Verified by |' '|---|---|---|' '| it works | ✗ | needs a human |'
  st_probe 1 "a body with no TL;DR marker" \
    'It does the thing.' '' \
    '| Criterion | ✓ | Verified by |' '|---|---|---|' '| it works | ✓ | `a.test.sh` 40/0 |'
  st_probe 1 "a body with no criteria table" \
    '## Description (TL;DR)' 'It does the thing.' '' 'Some prose and nothing else.'
  st_probe 1 "a body whose only table is inside a code fence" \
    '## Description (TL;DR)' 'It does the thing.' '' '```md' \
    '| Criterion | ✓ | Verified by |' '|---|---|---|' '| it works | ✓ | `a.test.sh` 40/0 |' '```'
  st_probe 0 "a row at the largest honest evidence cell measured (#67, 377)" \
    '## Description (TL;DR)' 'It does the thing.' '' \
    '| Criterion | ✓ | Verified by |' '|---|---|---|' \
    "| it works | ✓ | $(st_cell 377) |"
  st_probe 3 "a row at ai-bridge#71's worst evidence cell (487)" \
    '## Description (TL;DR)' 'It does the thing.' '' \
    '| Criterion | ✓ | Verified by |' '|---|---|---|' \
    "| it works | ✓ | $(st_cell 487) |"
  st_probe 3 "a row whose evidence is 'see above'" \
    '## Description (TL;DR)' 'It does the thing.' '' \
    '| Criterion | ✓ | Verified by |' '|---|---|---|' '| it works | ✓ | see above |'

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
