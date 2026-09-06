#!/usr/bin/env bash
# do-not-repeat.sh — what an earlier round of THIS task already tried, so the next agent
# does not retry it. `append <task> --line <text>` adds one entry to the task's
# `do_not_repeat:` (whitespace folded, 200 chars, deduped, capped at 10); `brief <task>`
# prints the block the PM pastes into the next dispatch verbatim, under a fixed heading,
# and prints nothing when there is nothing. Exit: 0 done, 1 at the cap (fold the oldest
# into `# Notes`, then retry), 2 cannot answer, 3 write failed (temp-file writes, nothing
# partial). Reasoning: ai-bridge-next/task-012, the qualitative half of stall-counter.sh —
# that counts rounds, this says what not to try again.
set -uo pipefail

FIELD=do_not_repeat
MAX_ENTRIES=10
MAX_CHARS=200
# THE ONE COPY OF THE HEADING. project-manager.md quotes it and tests/do-not-repeat.test.sh
# pins both against this line, so a rename cannot land in one place only.
HEADING='## Do not repeat (earlier rounds of this task)'
TRAILER='Each line is an approach an earlier round already tried and the evidence it failed on. Do not retry one; if you must, say why in your report.'

usage() { sed -n '2,8p' "$0" >&2; exit 2; }

# The frontmatter block. Exit 3 when the file does not open with `---`, exit 4 when it
# opens but never closes — the same reader stall-counter.sh and check-dispatch.sh use.
fm_block() {
  awk '
    NR==1 && $0!="---" { bad=3; exit }
    /^---$/ { n++; if (n==2) { closed=1; exit } ; next }
    n==1 { print }
    END { if (bad) exit bad; if (!closed) exit 4 }
  ' "$1"
}

field() { # <key> — only the FIRST occurrence counts
  printf '%s\n' "$FM" | awk -v key="$1" '
    !got && index($0, key ":") == 1 {
      v = $0
      sub(/^[^:]*:[[:space:]]*/, "", v)
      sub(/[[:space:]]+$/, "", v)
      print v; got = 1
    }'
}

# `[ "a", "b" ]` back to one unescaped entry per line. A value carrying no quote at all is
# split on commas instead: the field is script-owned, but a hand-typed bare entry must read
# as itself rather than silently vanish from the brief.
split_entries() { # <raw value>
  printf '%s' "$1" | awk '
    {
      body = $0; sub(/^[[:space:]]*\[/, "", body); sub(/\][[:space:]]*$/, "", body)
      if (index(body, "\"") == 0) {
        n = split(body, a, ",")
        for (i = 1; i <= n; i++) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", a[i]); if (a[i] != "") print a[i] }
        next
      }
      n = length(body); inq = 0; buf = ""
      for (i = 1; i <= n; i++) {
        c = substr(body, i, 1)
        if (!inq) { if (c == "\"") inq = 1; continue }
        if (c == "\\") { i++; buf = buf substr(body, i, 1); continue }
        if (c == "\"") { print buf; buf = ""; inq = 0; continue }
        buf = buf c
      }
    }'
}

# Text to a double-quoted scalar: whitespace folded to one line and truncated, because an
# entry is read by a human in the task document and pasted into a brief — a line, never a
# pasted log. Folding also makes the dedupe comparison stable across rounds.
yaml_quote() { # <text>
  printf '"%s"' "$(printf '%s' "$1" \
    | tr '\n\t\r' '   ' \
    | sed 's/  */ /g; s/^ //; s/ $//' \
    | cut -c "1-$MAX_CHARS" \
    | sed 's/\\/\\\\/g; s/"/\\"/g')"
}
normalise() { # <text> — exactly what an appended entry becomes
  printf '%s' "$1" | tr '\n\t\r' '   ' | sed 's/  */ /g; s/^ //; s/ $//' | cut -c "1-$MAX_CHARS"
}

set_field() { # <task-doc> <yaml-value>
  local tmp rc=0
  tmp="$(mktemp "${TMPDIR:-/tmp}/do-not-repeat.XXXXXX")" || return 3
  # The value travels in the ENVIRONMENT, never through `awk -v`: -v applies escape
  # processing, so a stored `\"` would arrive as a bare quote and corrupt the scalar.
  DNR_KEY="$FIELD" DNR_VAL="$2" awk '
    BEGIN { k = ENVIRON["DNR_KEY"]; v = ENVIRON["DNR_VAL"] }
    NR == 1 && $0 == "---" { n = 1; print; next }
    n == 1 && $0 == "---" { if (!done) { print k ": " v; done = 1 } n = 2; print; next }
    n == 1 && !done && index($0, k ":") == 1 { print k ": " v; done = 1; next }
    { print }
  ' "$1" > "$tmp" || rc=3
  [ "$rc" -eq 0 ] || { rm -f "$tmp"; return 3; }
  cat "$tmp" > "$1" || rc=3            # rewrite in place: keeps the inode and the mode
  rm -f "$tmp"
  return "$rc"
}

CMD="${1:-}"; shift 2>/dev/null || true
case "$CMD" in append|brief) ;; -h|--help|'') usage ;; *) echo "do-not-repeat: unknown command '$CMD'" >&2; usage ;; esac

TASK="${1:-}"; [ -n "$TASK" ] || usage; shift
[ -f "$TASK" ] || { echo "do-not-repeat: no such task document: $TASK" >&2; exit 2; }

LINE=""; HAVE_LINE=no
while [ $# -gt 0 ]; do
  case "$1" in
    --line) [ $# -ge 2 ] || { echo "do-not-repeat: --line needs a value" >&2; exit 2; }
            LINE="$2"; HAVE_LINE=yes; shift 2 ;;
    *) echo "do-not-repeat: unexpected argument '$1'" >&2; usage ;;
  esac
done

FM=""; fm_rc=0
FM="$(fm_block "$TASK")" || fm_rc=$?
[ "$fm_rc" -eq 0 ] || {
  echo "do-not-repeat: $TASK has no readable YAML frontmatter — refusing rather than" >&2
  echo "               writing into a document whose shape is unknown." >&2
  exit 2
}

ENTRIES="$(split_entries "$(field "$FIELD")")"
COUNT=0
[ -n "$ENTRIES" ] && COUNT="$(printf '%s\n' "$ENTRIES" | grep -c '')"

case "$CMD" in
  brief)
    [ "$COUNT" -gt 0 ] || exit 0
    printf '%s\n\n' "$HEADING"
    printf '%s\n' "$ENTRIES" | sed 's/^/- /'
    printf '\n%s\n' "$TRAILER"
    exit 0
    ;;

  append)
    [ "$HAVE_LINE" = yes ] || { echo "do-not-repeat: append needs --line <text>" >&2; exit 2; }
    NEW="$(normalise "$LINE")"
    [ -n "$NEW" ] || { echo "do-not-repeat: --line is empty after folding — nothing to record" >&2; exit 2; }
    # An identical entry is a no-op rather than a second copy: a re-run of the same round
    # must not spend one of the ten slots on a line already there.
    if [ -n "$ENTRIES" ] && printf '%s\n' "$ENTRIES" | grep -qxF -- "$NEW"; then
      printf 'KEPT      %s/%s — already recorded\n' "$COUNT" "$MAX_ENTRIES"
      exit 0
    fi
    if [ "$COUNT" -ge "$MAX_ENTRIES" ]; then
      echo "do-not-repeat: $TASK is at the cap of $MAX_ENTRIES $FIELD entries. Fold the" >&2
      echo "               oldest into '# Notes' and re-run; nothing was written." >&2
      exit 1
    fi
    QUOTED=""
    while IFS= read -r e; do
      [ -n "$e" ] || continue
      QUOTED="${QUOTED}$(yaml_quote "$e"), "
    done <<EOF
$ENTRIES
EOF
    QUOTED="${QUOTED}$(yaml_quote "$NEW")"
    set_field "$TASK" "[ $QUOTED ]" || { echo "do-not-repeat: could not write $FIELD" >&2; exit 3; }
    printf 'RECORDED  %s/%s — %s\n' "$((COUNT + 1))" "$MAX_ENTRIES" "$NEW"
    exit 0
    ;;
esac
