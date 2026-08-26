#!/usr/bin/env bash
#
# write-snapshot.sh — write this instance's board snapshot (SNAPSHOT.json).
#
#   Usage: scripts/write-snapshot.sh [--quiet]
#
# WHAT IT IS. One flat JSON file at the bundle root, derived from the bundle's own
# frontmatter (`projects/*/project.md`, `projects/*/phases/*.md`,
# `projects/*/tasks/*.md` — the schema-defined locations, per SCHEMA.md). It is the
# OBSERVATION CONTRACT for the cross-instance board: `scripts/build-board.sh` reads
# these files, from several instances, and renders one HTML page. Nothing else reads
# it, and nothing reads the bundle to build the board.
#
# ABSENCE IS THE OFF SWITCH — the same contract as AWAITING.md, and the reason this
# script exists rather than the PM hand-assembling JSON:
#
#   · No SNAPSHOT.json  ⇒  exit 0, write nothing, say nothing. That instance simply
#     does not appear on the board.
#   · `rm SNAPSHOT.json` is therefore permanent: this script NEVER creates the file,
#     and `install.sh` creates it on the FIRST STAMP ONLY (FIRST_STAMP), so
#     no later refresh resurrects it.
#   · `touch SNAPSHOT.json` turns it back on. Presence is the switch; content is
#     derived, so an empty or truncated file is fine — the next run overwrites it.
#
# It must NOT be a file under `symlink/`. AUTONOMY.md is a deletable capability that
# does live there, and install.sh re-links it unconditionally, so a per-instance `rm`
# is silently undone (upgrade.sh now has to warn about exactly that). A generated,
# gitignored root file has no such hole.
#
# DATA GOVERNANCE — READ BEFORE ADDING A FIELD.
# The board is rendered to an HTML page that a human may PUBLISH to a URL. AWAITING.md
# never leaves the instance; this file is one step from leaving it. So the snapshot
# deliberately carries STRICTLY LESS than AWAITING.md does:
#
#   CARRIED (the whole allowlist):
#     project: slug, title, description, kind, status, autonomy
#     phase:   file, order, title, status
#     task:    id, title, kind, status, assignee (a ROLE slug, never a person),
#              in_flight, awaiting (a verb, not a reason), open_questions (a COUNT),
#              prs (repo, number, url)
#   NEVER CARRIED:
#     · task `description:` and every document BODY (`# Context`, `# Notes`,
#       `# Result`) — free prose, the likeliest place a logged-in page or a customer
#       record gets quoted;
#     · the TEXT of `open_questions` or of a blocker reason — the board shows the
#       verb (❓ answer, ⛔ unblock) and the task it belongs to, and the human opens
#       the task doc for the question itself. AWAITING.md carries that text; the
#       board does not;
#     · any author identity (`authorEmail`), any filesystem path outside this bundle
#       (`reposRoot`, `worktreeRoot`), any URL other than a PR URL;
#     · `owner:` — on a bundle shared by two humans this names a PERSON, and the
#       board's HTML can be published. It is identity, so it belongs with
#       `authorEmail` on this list, not with `assignee` (which is a role slug and
#       names nobody). A shared board is read by people who already know whose
#       project is whose; a published page is not.
#
# Titles ARE carried: a board without them is unreadable. They are written by humans
# and could say anything, so **this file is exactly as sensitive as the task documents
# it derives from** — that sentence is repeated in the file's own `_sensitivity` key,
# because whoever finds the JSON will not have read this header. No customer PII
# belongs in a task title in the first place (instance `CLAUDE.md`, "Data handling").
#
# Deterministic, no network, no `jq`, no `python3` — bash + awk, like every other
# script under `scripts/`, so it ships into every instance unchanged. `generated_at`
# is the only non-deterministic field; set `SNAPSHOT_NOW` to pin it.
#
# A `status: done` PROJECT IS READ NO FURTHER THAN ITS FRONTMATTER. Its stanza is
# emitted from fields already parsed; `phases/` and `tasks/` are never opened. See the
# `continue` in the assembly loop for why that one line is what makes `retain: true`
# affordable.
#
# Verified by tests/snapshot.test.sh.
set -euo pipefail

QUIET=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --quiet|-q) QUIET=1 ;;
    -h|--help) sed -n '2,/^set -euo/p' "$0" | sed 's/^# \{0,1\}//; $d'; exit 0 ;;
    *) echo "usage: $0 [--quiet]" >&2; exit 2 ;;
  esac
  shift
done

[[ -f SCHEMA.md && -f instance.config.json ]] || {
  echo "write-snapshot: run from a control-panel instance root (SCHEMA.md + instance.config.json)." >&2
  exit 2
}

OUT="SNAPSHOT.json"

# The off switch, checked before any work. Absent = this instance opted out of the
# board; that is silence and success, never an error and never a create.
if [[ ! -e "$OUT" ]]; then
  [[ $QUIET -eq 1 ]] || echo "write-snapshot: no $OUT — this instance is off the board (touch $OUT to enable)."
  exit 0
fi
# A directory (or anything not a regular file) at that path is a human's doing, and
# overwriting it would destroy content. Refuse loudly instead.
[[ -f "$OUT" ]] || { echo "write-snapshot: $OUT exists but is not a regular file — refusing to overwrite." >&2; exit 2; }

NOW="${SNAPSHOT_NOW:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"
GROUP="$(basename "$PWD")"; GROUP="${GROUP#_ai-bridge-}"

# ---------------------------------------------------------------- JSON primitives
# Single-line YAML values only, so parameter expansion is enough and correct: strip
# C0 controls and DEL (they cannot appear in a legal JSON string unescaped), then
# escape the four things that can occur in a title. Order matters — backslash first.
jstr() {
  local s
  s="$(printf '%s' "${1-}" | tr -d '\000-\010\013\014\016-\037\177')"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\t'/\\t}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\n'/\\n}"
  printf '"%s"' "$s"
}

# ---------------------------------------------------------------- frontmatter
# Same contract as validate-bundle.sh: exit 3 when the file does not open with
# `---`, exit 4 when it opens and never closes. Either way we treat the document as
# unreadable and skip it — a malformed doc is validate-bundle's finding to report,
# not something to guess at here.
frontmatter() {
  awk '
    NR==1 && $0!="---" { bad=3; exit }
    /^---$/ { n++; if (n==2) { closed=1; exit } ; next }
    n==1 { print }
    END { if (bad) exit bad; if (!closed) exit 4 }
  ' "$1"
}

# A scalar field. Strips one layer of matching surrounding quotes (a YAML title may
# legitimately be quoted because it contains a colon).
fmfield() { # <frontmatter> <key>
  local v
  v="$(printf '%s\n' "$1" | sed -n "s/^$2:[[:space:]]*//p" | head -1)"
  v="${v%"${v##*[![:space:]]}"}"          # rtrim
  case "$v" in
    \"*\") v="${v#\"}"; v="${v%\"}" ;;
    \'*\') v="${v#\'}"; v="${v%\'}" ;;
  esac
  printf '%s' "$v"
}

# An enum-ish field: same, but a trailing `# comment` is not part of the value.
fmenum() { # <frontmatter> <key>
  local v; v="$(fmfield "$1" "$2")"
  v="${v%%#*}"
  v="${v%"${v##*[![:space:]]}"}"
  printf '%s' "$v"
}

# The raw text of a list field, in BOTH YAML forms (inline `k: [ a, b ]` and a block
# sequence of `- ` lines). Copied in shape from validate-bundle.sh's refs_for, for
# the same reason: no instance uses block style today, and nothing forbids it.
list_region() { # <frontmatter> <key>
  printf '%s\n' "$1" | awk -v k="$2" '
    $0 ~ "^" k ":" { rest=$0; sub(/^[^:]*:/, "", rest); print rest; inblk=1; next }
    inblk && /^[[:space:]]+-[[:space:]]*/ { print; next }
    inblk && /^[[:space:]]*$/ { next }
    /^[^[:space:]]/ { inblk=0 }
  '
}

# Is a list field non-empty? `[]`, `[ ]`, and a bare key all count as empty.
list_filled() { # <frontmatter> <key>
  local r; r="$(list_region "$1" "$2")"
  r="$(printf '%s' "$r" | tr -d '[:space:]' | tr -d '[]')"
  [[ -n "$r" ]]
}

# How many open questions. SCHEMA.md requires every entry to be numbered (Q1, Q2, …),
# so counting the numbered entries is exact for a conforming document and needs no
# comma-inside-quotes parsing. An unnumbered but non-empty list counts as 1 — the
# board only ever renders "this task needs an answer", so the fallback is honest
# rather than a guess at a number.
count_questions() { # <frontmatter>
  local r n
  r="$(list_region "$1" open_questions)"
  # `\b` is a GNU extension, NOT in POSIX ERE. It happens to work on this machine's
  # BSD grep 2.6.0-FreeBSD, which advertises GNU compatibility — but this script ships
  # into instances on machines we never see, and a grep without it silently degrades
  # the count to the 1 fallback rather than erroring. The bracket form is POSIX and
  # counts identically: the leading character it also consumes is irrelevant, because
  # the result is piped to `grep -c .`, which counts LINES, not captures.
  n="$(printf '%s\n' "$r" | grep -oE '(^|[^A-Za-z0-9_])Q[0-9]+[.:]' | grep -c . || true)"
  if [[ "${n:-0}" -gt 0 ]]; then printf '%s' "$n"
  elif list_filled "$1" open_questions; then printf '1'
  else printf '0'; fi
}

# ONE normaliser for every list field, because three ad-hoc pipelines drifted into
# three different bugs (CodeRabbit, PR #8): a quoted `depends_on` entry kept its
# closing quote so the `.md` strip missed and the ID came out `task-001.md"`; a
# flow-form `advisor_notes` with two entries counted 1; and a flow-form
# `open_questions` stranded a quote on the first and last entry.
#
# The single cause in all three was ORDER: split before trimming, or strip quotes
# before removing the flow brackets, and the outer entries keep a stray character.
# So: trim, unwrap the brackets, trim again, THEN split, THEN unquote, THEN trim.
#
# Splitting is quote-aware. A quoted list is split on the quote-comma-quote seam,
# never a bare comma — question text routinely contains commas and splitting on those
# shreds one question into several. An unquoted list (the form `depends_on` uses) has
# no such hazard, so a bare comma is the right separator there.
yaml_list_entries() { # <frontmatter> <key>
  local r inner
  r="$(list_region "$1" "$2")"
  inner="$(printf '%s\n' "$r" \
    | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' \
    | sed -e 's/^-[[:space:]]*//' \
    | sed -e 's/^\[//' -e 's/\]$//' \
    | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  case "$inner" in
    *'"'*) inner="$(printf '%s\n' "$inner" | sed -e 's/"[[:space:]]*,[[:space:]]*"/\
/g')" ;;
    *)     inner="$(printf '%s\n' "$inner" | sed -e 's/[[:space:]]*,[[:space:]]*/\
/g')" ;;
  esac
  printf '%s\n' "$inner" \
    | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' \
    | sed -e 's/^"//' -e 's/"$//' \
    | sed -e "s/^'//" -e "s/'\$//" \
    | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' \
    | grep -v '^$' \
    | grep -vE '^(\[|\]|\[\])$' || true
}

# The task IDs a task depends on. Emitted as IDs, not paths: an ID is what a human
# reads on the board and the full path is derivable from the project slug, so
# carrying the path would be redundant AND longer. Bundle-relative either way, so
# this adds no out-of-bundle path to the published page.
#
# WHY THIS IS INSIDE THE ALLOWLIST rather than an exception to it: `depends_on` is a
# structural reference between two documents in this bundle, exactly like `phase:`
# which the snapshot already carries. It is not free prose, not identity, and not a
# path outside the bundle — the four things the allowlist actually names. A reader
# adding a field here should be able to say which of those four it is; this is none.
depends_ids() { # <frontmatter>
  # Entries arrive already trimmed and unquoted, so basename-then-suffix is safe.
  yaml_list_entries "$1" depends_on | sed -e 's#^.*/##' -e 's#\.md$##' | grep -v '^$' || true
}

# The TEXT of each open question — OPT-IN, and off unless SNAPSHOT_QUESTION_TEXT=1.
#
# THIS CROSSES THE ALLOWLIST ON PURPOSE, at the bundle owner's explicit instruction
# (2026-08-23): a board that says "1 open question" and will not say which one is not
# actionable. Everything about the shape is chosen so the DEFAULT stays exactly as it
# was — absence of the variable means absence of the key, so an instance that never
# sets it publishes precisely what it published before, and the two assertions that
# forbid question text (snapshot.test.sh: "open-question TEXT never reaches the
# snapshot", and the secrets sweep over the rendered page) still hold unchanged.
#
# Set it only for an instance whose task titles AND question text are safe to publish.
# The Alteos instance states no-PII rules four times in its CLAUDE.md; it is exactly
# the case this stays off for.
# How many advisor concerns are still untriaged. A COUNT, never the text: unlike
# `open_questions` this is not a human gate at all — it is the loop's own inbox — so
# the board shows it as information, not as something demanding attention. It gets no
# awaiting verb for exactly that reason.
advisor_note_count() { # <frontmatter>
  local n
  n="$(yaml_list_entries "$1" advisor_notes | grep -c . || true)"
  if [[ "${n:-0}" -gt 0 ]]; then printf '%s' "$n"
  # Non-empty but nothing parsed: report 1 rather than 0. The board only ever says
  # "there is something here", so an honest floor beats a silent zero.
  elif list_filled "$1" advisor_notes; then printf '1'
  else printf '0'; fi
}

question_texts() { # <frontmatter>
  [[ "${SNAPSHOT_QUESTION_TEXT:-}" == 1 ]] || return 0
  yaml_list_entries "$1" open_questions
}

# ---------------------------------------------------------------- assembly
tasks_total=0
awaiting_total=0
projects_json=""
projects_n=0

# `find | sort` rather than a glob, so an instance with no projects/ dir is a clean
# empty snapshot instead of a literal `projects/*/project.md` path.
PROJECT_FILES="$(find ./projects -mindepth 2 -maxdepth 2 -name 'project.md' 2>/dev/null | sort || true)"

while IFS= read -r pfile; do
  [[ -n "$pfile" ]] || continue
  pdir="$(dirname "$pfile")"
  slug="$(basename "$pdir")"
  pfm=""; if ! pfm="$(frontmatter "$pfile" 2>/dev/null)"; then pfm=""; fi
  [[ -n "$pfm" ]] || continue          # unreadable frontmatter: skip, don't guess

  p_title="$(fmfield "$pfm" title)"; [[ -n "$p_title" ]] || p_title="$slug"
  p_desc="$(fmfield "$pfm" description)"
  p_kind="$(fmenum "$pfm" kind)";      [[ -n "$p_kind" ]] || p_kind="build"
  p_status="$(fmenum "$pfm" status)"
  p_autonomy="$(fmenum "$pfm" autonomy)"; [[ -n "$p_autonomy" ]] || p_autonomy="gated"

  # ---- a DONE project is read no further than this line.
  #
  # A finished project used to be deleted at closeout, and the stated reason was never
  # disk — it was that "a done folder left live would only cost context on every PM
  # tick" (SCHEMA.md). `retain: true` keeps the folder, so that cost has to go
  # somewhere, and here is where it goes: the project frontmatter is ALREADY parsed
  # above, before anything walks `phases/` or `tasks/`, so skipping here costs exactly
  # one frontmatter parse per retained project and opens `tasks/` zero times. That is
  # the trade that makes retention affordable; if this `continue` ever moves below the
  # task loop it silently gives the cost back.
  #
  # The project STANZA is still emitted, from the frontmatter in hand — the skip is of
  # the phase and task WALKS, not of the project. A retained project is a reference card
  # on the board (its deliverables are listed from `deliverable_paths:` in project.md),
  # and a project omitted from the snapshot entirely could not be rendered at all.
  # `awaiting_close` is false by definition here: a done project is already closed.
  if [[ "$p_status" == "done" ]]; then
    projects_n=$((projects_n+1))
    projects_json="$projects_json${projects_json:+,}
    {
      \"slug\": $(jstr "$slug"),
      \"title\": $(jstr "$p_title"),
      \"description\": $(jstr "$p_desc"),
      \"kind\": $(jstr "$p_kind"),
      \"status\": $(jstr "$p_status"),
      \"autonomy\": $(jstr "$p_autonomy"),
      \"awaiting_close\": false,
      \"phase_progress\": {\"done\": 0, \"total\": 0},
      \"phases\": [],
      \"tasks\": []
    }"
    continue
  fi

  # ---- phases
  phases_json=""; ph_total=0; ph_done=0
  while IFS= read -r phfile; do
    [[ -n "$phfile" ]] || continue
    phfm=""; if ! phfm="$(frontmatter "$phfile" 2>/dev/null)"; then phfm=""; fi
    [[ -n "$phfm" ]] || continue
    ph_title="$(fmfield "$phfm" title)"; [[ -n "$ph_title" ]] || ph_title="$(basename "$phfile" .md)"
    ph_status="$(fmenum "$phfm" status)"
    ph_order="$(fmenum "$phfm" order)"
    case "$ph_order" in ''|*[!0-9]*) ph_order=0 ;; esac
    ph_total=$((ph_total+1))
    [[ "$ph_status" == "done" ]] && ph_done=$((ph_done+1))
    phases_json="$phases_json${phases_json:+,}
      {\"file\": $(jstr "$(basename "$phfile")"), \"order\": $ph_order, \"title\": $(jstr "$ph_title"), \"status\": $(jstr "$ph_status")}"
  done <<EOF
$(find "$pdir/phases" -maxdepth 1 -name '*.md' 2>/dev/null | grep -vE '/(index|log)\.md$' | sort || true)
EOF

  # ---- tasks
  tasks_json=""; t_count=0; t_terminal=0
  while IFS= read -r tfile; do
    [[ -n "$tfile" ]] || continue
    tfm=""; if ! tfm="$(frontmatter "$tfile" 2>/dev/null)"; then tfm=""; fi
    [[ -n "$tfm" ]] || continue
    t_id="$(basename "$tfile" .md)"
    t_title="$(fmfield "$tfm" title)"; [[ -n "$t_title" ]] || t_title="$t_id"
    t_status="$(fmenum "$tfm" status)"
    t_kind="$(fmenum "$tfm" kind)"; [[ -n "$t_kind" ]] || t_kind="$p_kind"
    t_assignee="$(fmenum "$tfm" assignee)"
    t_phase="$(fmfield "$tfm" phase)"; t_phase="$(basename "$t_phase" 2>/dev/null || true)"
    [[ "$t_phase" == "." ]] && t_phase=""
    oq="$(count_questions "$tfm")"

    # PR URLs only — never the surrounding `pr:` text, whatever else it holds.
    prs_json=""
    while IFS= read -r url; do
      [[ -n "$url" ]] || continue
      num="${url##*/}"
      case "$num" in ''|*[!0-9]*) continue ;; esac
      repo="${url%/pull/*}"; repo="${repo#*://}"; repo="${repo#*/}"
      prs_json="$prs_json${prs_json:+, }{\"repo\": $(jstr "$repo"), \"number\": $num, \"url\": $(jstr "$url")}"
    done <<EOF
$(list_region "$tfm" pr | grep -oE 'https?://[A-Za-z0-9._~:/?#@!$&*+=%-]+/pull/[0-9]+' | sort -u || true)
EOF

    # in_flight = a role agent is working it. `in-review` is NOT in flight: the agent
    # has handed over and the PR is waiting on a reviewer or a merge.
    in_flight=false; [[ "$t_status" == "in-progress" ]] && in_flight=true

    # depends_on -> a JSON array of IDs. jstr() does the escaping, as everywhere else.
    an="$(advisor_note_count "$tfm")"
    qt_json=""
    while IFS= read -r qt; do
      [[ -n "$qt" ]] || continue
      [[ -n "$qt_json" ]] && qt_json="$qt_json, "
      qt_json="$qt_json$(jstr "$qt")"
    done <<< "$(question_texts "$tfm")"

    dep_json=""
    while IFS= read -r dep; do
      [[ -n "$dep" ]] || continue
      [[ -n "$dep_json" ]] && dep_json="$dep_json, "
      dep_json="$dep_json$(jstr "$dep")"
    done <<< "$(depends_ids "$tfm")"

    # The awaiting verb, and ONLY the verb — mirrors show-awaiting.sh's glyph set
    # (✅ approve · ❓ answer · 🔀 merge · ⛔ unblock · 🏁 close) minus the reason text.
    # A `draft` with no acceptance_criteria is still being refined, so it awaits
    # nothing yet; with questions open it awaits an answer, not an approval.
    awaiting=""
    case "$t_status" in
      draft)
        if [[ "$oq" != 0 ]]; then awaiting="answer"
        elif list_filled "$tfm" acceptance_criteria; then awaiting="approve"; fi ;;
      in-review) [[ -n "$prs_json" ]] && awaiting="merge" ;;
      blocked)   awaiting="unblock" ;;
    esac
    [[ -n "$awaiting" ]] && awaiting_total=$((awaiting_total+1))

    case "$t_status" in done|cancelled) t_terminal=$((t_terminal+1)) ;; esac
    t_count=$((t_count+1)); tasks_total=$((tasks_total+1))

    tasks_json="$tasks_json${tasks_json:+,}
      {\"id\": $(jstr "$t_id"), \"title\": $(jstr "$t_title"), \"kind\": $(jstr "$t_kind"), \"status\": $(jstr "$t_status"), \"assignee\": $(jstr "$t_assignee"), \"phase\": $(jstr "$t_phase"), \"in_flight\": $in_flight, \"awaiting\": $(jstr "$awaiting"), \"open_questions\": $oq, \"advisor_notes\": $an${qt_json:+, \"open_question_text\": [$qt_json]}, \"depends_on\": [$dep_json], \"prs\": [$prs_json]}"
  done <<EOF
$(find "$pdir/tasks" -maxdepth 1 -name '*.md' 2>/dev/null | grep -vE '/(index|log)\.md$' | sort || true)
EOF

  # A close proposal, same rule as the PM's step 6: every task terminal, at least
  # one task, project not already done. Never an action — the board only shows it.
  awaiting_close=false
  if [[ $t_count -gt 0 && $t_terminal -eq $t_count && "$p_status" != "done" ]]; then
    awaiting_close=true; awaiting_total=$((awaiting_total+1))
  fi

  projects_n=$((projects_n+1))
  projects_json="$projects_json${projects_json:+,}
    {
      \"slug\": $(jstr "$slug"),
      \"title\": $(jstr "$p_title"),
      \"description\": $(jstr "$p_desc"),
      \"kind\": $(jstr "$p_kind"),
      \"status\": $(jstr "$p_status"),
      \"autonomy\": $(jstr "$p_autonomy"),
      \"awaiting_close\": $awaiting_close,
      \"phase_progress\": {\"done\": $ph_done, \"total\": $ph_total},
      \"phases\": [$phases_json],
      \"tasks\": [$tasks_json]
    }"
done <<EOF
$PROJECT_FILES
EOF

# ---------------------------------------------------------------- write
# Temp file BESIDE the target, never $TMPDIR: a cross-filesystem `mv` degrades to
# copy-and-remove, where an interruption leaves a half-written snapshot that the
# board would then report as malformed. Same reasoning as migrate-bundle.sh.
tmp="$OUT.tmp.$$"
trap 'rm -f "$tmp"' EXIT
cat > "$tmp" <<JSON
{
  "_schema": "ai-bridge board snapshot v1",
  "_sensitivity": "Derived and gitignored. AS SENSITIVE AS THE TASK DOCUMENTS IT COMES FROM: titles are human-written free text. No customer PII belongs in a task title, and none belongs here. Delete this file to take this instance off the board for good.",
  "_carries": "project title/description/kind/status/autonomy; phase title/order/status; task id/title/kind/status/assignee-ROLE/in_flight/awaiting-VERB/open-question COUNT/advisor_notes COUNT/depends_on IDs/PR links; open_question_text ONLY when SNAPSHOT_QUESTION_TEXT=1 (opt-in, off by default). Never: task descriptions, document bodies, question or blocker TEXT, author identity, or any path outside this bundle.",
  "group": $(jstr "$GROUP"),
  "generated_at": $(jstr "$NOW"),
  "counts": {"projects": $projects_n, "tasks": $tasks_total, "awaiting": $awaiting_total},
  "projects": [$projects_json]
}
JSON

mv "$tmp" "$OUT"
trap - EXIT

# Verify the write landed rather than claiming it did — migrate-bundle.sh once
# printed FIXED for a write it never made, on a real bundle.
[[ -s "$OUT" ]] || { echo "write-snapshot: FAILED — $OUT is empty after the write." >&2; exit 1; }
[[ $QUIET -eq 1 ]] || printf 'write-snapshot: %s — %d project(s), %d task(s), %d awaiting.\n' \
  "$OUT" "$projects_n" "$tasks_total" "$awaiting_total"
exit 0
