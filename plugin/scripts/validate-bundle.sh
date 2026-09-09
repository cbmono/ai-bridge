#!/usr/bin/env bash
#
# validate-bundle.sh — check that this bundle is machine-readable from frontmatter
# alone: every concept document has a known `type`, a `status` in that type's enum,
# a `timestamp`, and every structural cross-reference resolves.
#
#   Usage: validate-bundle.sh [--strict]
#          --strict   treat warnings as failures too
#
# WHY THIS EXISTS, AND WHAT IT DELIBERATELY DOES NOT CHECK.
# Measured across three live instances (2026-08-21, ~570 documents) BEFORE it was
# written, because a validator that reports problems nobody has is one people learn
# to ignore:
#   · status enums:      23 violations, all in `knowledge/`. The first measurement
#                        reported ZERO and was wrong: it sampled only Objective,
#                        Project, Phase and Task and never looked at Finding or
#                        Service. Findings carry `open` and `active` where the enum
#                        is `current|superseded`, and six Services carry `current`
#                        where theirs is `active|deprecated` — someone applied the
#                        Finding enum to a Service. Enum checking is NOT a
#                        future-typo guard; it is catching live drift, and the drift
#                        is concentrated exactly where nobody was looking.
#   · missing timestamp: 16 documents across two instances.
#   · frontmatter refs:  15 of 115 dangling (13%). This was the motivating rot. `/close-project` removes a project
#                        folder by design, so a surviving `depends_on:` or
#                        `objective:` pointing into it breaks silently.
#   · `Reference`:       the fifth knowledge kind, `knowledge/references/*.md`. It was
#                        ALREADY collected (the location filter is `knowledge/<kind>/`,
#                        not a list of four names) and already checked for type,
#                        timestamp and dangling refs — measured on the one live
#                        instance that has the directory: 7 documents, 0 findings. The
#                        single gap was its `status`, unchecked because `Reference` had
#                        no enum, so the exact drift class this script was built for —
#                        one type's enum applied to another — was invisible there.
#                        `current|superseded` is what all 7 already carry, so adding it
#                        is a no-op on live data and a real check on the next edit.
#                        Root documents typed `Reference` (SCHEMA.md, AUTONOMY.md) are
#                        NOT in a schema-defined location, so no enum reaches them.
#   · `owner`:           deliberately NOT checked. It is neither an enum nor a
#                        structural reference — it names a person outside the bundle,
#                        so nothing here can resolve it, and a warning about a name
#                        this script cannot verify is exactly the noise that buries
#                        real errors. `task-owner.sh` validates the shape at
#                        the one moment it matters: when the loop decides to dispatch.
#   · `id` / `updated`:  NOT required, and not added. No document in any instance
#                        carried either. The file path is already the identifier —
#                        a duplicate `id` can only drift from it — and OKF names the
#                        time field `timestamp`, so renaming it would diverge from
#                        the spec this bundle claims to follow. The v2 plan asked
#                        for both; the data said no.
#
# WHAT COUNTS AS A CONCEPT DOCUMENT. Only the schema-defined locations:
# `objectives/*.md` (OPTIONAL — a bundle with none is valid), `projects/*/project.md`,
# `projects/*/phases/*.md`, `projects/*/tasks/*.md`, `knowledge/<kind>/*.md`. Everything
# else — `index.md`, `log.md`, `sources/`, `deliverables/`, a doc a human dropped into a
# project — is content or navigation. The first version of this script validated those
# too and buried 6 real errors under 77 warnings, which is exactly how a validator
# teaches people to ignore it.
#
# BODY PROSE IS NOT CHECKED. A body may cite a closed project's task as history —
# that is the record working as intended. Only FRONTMATTER references, which
# machinery actually follows, must resolve. A `Finding`'s `source:` is provenance no
# machinery follows, so it is NOT checked here: `build-kb-index.sh --check` owns it,
# at WARN (SCHEMA.md, "A `source:` is a durable URL").
#
# `artifacts:` WARNS rather than fails: a research task legitimately declares a
# deliverable before it is written.
#
# A `Finding` over 40 lines, or without a one-line `lesson:`, WARNS for the same reason —
# `CONVENTIONS.md` -> "Write less" sets both, and the 133 findings that predate the rule
# average 110 lines. A warning puts them on the cataloguer's list; an error would fail
# every bundle that has one, which is every bundle.
#
# Run from a control-panel instance root. Generic: no org/repo/path literals.
# Bash + awk only — no jq, no python — so it ships into every instance unchanged.
#
# Verified by tests/validate-bundle.test.sh.
set -euo pipefail

STRICT=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --strict) STRICT=1 ;;
    -h|--help) sed -n '2,/^set -euo/p' "$0" | sed 's/^# \{0,1\}//; $d'; exit 0 ;;
    *) echo "usage: $0 [--strict]" >&2; exit 2 ;;
  esac
  shift
done

[[ -f SCHEMA.md && -f instance.config.json ]] || {
  echo "validate-bundle: run from a control-panel instance root (SCHEMA.md + instance.config.json)." >&2
  exit 2
}

# Closed enums, per type. SCHEMA.md is the contract; this is its enforcement, so
# keep the two in step.
enum_for() {
  case "$1" in
    Objective) echo "active paused achieved dropped" ;;
    Project)   echo "active paused done" ;;
    Phase)     echo "not-started active done" ;;
    Task)      echo "draft ready in-progress in-review blocked cancelled done" ;;
    Finding)   echo "current superseded corrected" ;;
    Service)   echo "active deprecated" ;;
    Reference) echo "current superseded" ;;
    *)         echo "" ;;
  esac
}

KNOWN_TYPES="Objective Project Phase Task Agent Service Finding Team Runbook Reference"

# CONVENTIONS.md -> "Write less". Lowering it is free; raising it is a rule change.
FINDING_MAX_LINES=40
# CONVENTIONS.md -> the `do_not_repeat` cap. `do-not-repeat.sh append` refuses past it;
# this reports a list already over it, which is the PM's cue to fold the oldest into `# Notes`.
DO_NOT_REPEAT_MAX=10

errors=0; warns=0; checked=0

# Print the frontmatter block. Exit 3 when the file does not open with `---`, and
# exit 4 when it opens but never closes — an unterminated block used to return the
# whole file, so a malformed document with valid-looking fields passed validation.
frontmatter() {
  awk '
    NR==1 && $0!="---" { bad=3; exit }
    /^---$/ { n++; if (n==2) { closed=1; exit } ; next }
    n==1 { print }
    END { if (bad) exit bad; if (!closed) exit 4 }
  ' "$1"
}

# Collect path references from the given frontmatter keys, in BOTH YAML forms:
#   depends_on: [ /a.md, /b.md ]     (inline)
#   depends_on:                       (block)
#     - /a.md
# The line-based first version saw only the inline form, so a valid block sequence
# was silently skipped and the validator could report success while a structural
# reference dangled. No instance uses block style today; nothing forbids it.
refs_for() { # <frontmatter> <key-alternation> <path-regex>
  printf '%s\n' "$1" | awk -v keys="$2" '
    $0 ~ "^(" keys "):" { inblock=1; rest=$0; sub(/^[^:]*:/, "", rest); print rest; next }
    inblock && /^[[:space:]]+-[[:space:]]*/ { print; next }
    inblock && /^[[:space:]]*$/ { next }
    /^[^[:space:]]/ { inblock=0 }
  ' | grep -oE "$3" | sort -u || true
}
# Quoted entries in an inline flow list, counted the way do-not-repeat.sh splits them:
# a `\"` inside an entry is not a delimiter.
flow_entries() { # <raw value>
  printf '%s' "$1" | awk '{
    n = length($0); inq = 0; c = 0
    for (i = 1; i <= n; i++) {
      ch = substr($0, i, 1)
      if (!inq) { if (ch == "\"") inq = 1; continue }
      if (ch == "\\") { i++; continue }
      if (ch == "\"") { inq = 0; c++ }
    }
    print c
  }'
}

# Entries of a list-valued key, one per line, in BOTH YAML forms — flow
# (`k: [ a, "b, c" ]`) and block (`k:` then `  - a`), quoted or bare. `flow_entries`
# above counts only QUOTED flow entries, which is enough for a warning and not for a
# gate: a form that reads as empty would let the write it holds through in silence.
list_entries() { # <frontmatter> <key>
  printf '%s\n' "$1" | awk -v key="$2" '
    function trim(s) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", s); return s }
    function emit(s,   q) {
      s = trim(s); q = substr(s, 1, 1)
      if (length(s) > 1 && (q == "\"" || q == SQ) && substr(s, length(s)) == q)
        s = substr(s, 2, length(s) - 2)
      if (s != "") print s
    }
    function flow(t,   i, n, ch, inq, q, cur) {
      n = length(t); cur = ""; inq = 0
      for (i = 1; i <= n; i++) {
        ch = substr(t, i, 1)
        if (inq) {
          if (ch == "\\") { cur = cur ch substr(t, i + 1, 1); i++; continue }
          if (ch == q) inq = 0
          cur = cur ch; continue
        }
        if (ch == "\"" || ch == SQ) { inq = 1; q = ch; cur = cur ch; continue }
        if (ch == ",") { emit(cur); cur = ""; continue }
        cur = cur ch
      }
      emit(cur)
    }
    BEGIN { SQ = sprintf("%c", 39) }
    $0 ~ "^" key ":" {
      rest = trim(substr($0, length(key) + 2))
      # From the LAST `]`, so a trailing `# comment` is not read as an entry.
      if (rest ~ /^\[/) { sub(/^\[/, "", rest); sub(/\][^]]*$/, "", rest); flow(rest); inblock = 0 }
      else if (rest == "" || rest ~ /^#/) inblock = 1
      else { emit(rest); inblock = 0 }
      next
    }
    inblock && /^[[:space:]]+-[[:space:]]*/ { line = $0; sub(/^[[:space:]]+-[[:space:]]*/, "", line); emit(line); next }
    inblock && /^[[:space:]]*$/ { next }
    /^[^[:space:]]/ { inblock = 0 }
  '
}

fail() { printf '  ERROR  %s\n         %s\n' "$1" "$2"; errors=$((errors+1)); }
warn() { printf '  WARN   %s\n         %s\n' "$1" "$2"; warns=$((warns+1)); }

collect_files() {
  find ./objectives -maxdepth 1 -name '*.md' 2>/dev/null || true
  find ./projects -maxdepth 2 -name 'project.md' 2>/dev/null || true
  find ./projects -path '*/phases/*.md' 2>/dev/null || true
  find ./projects -path '*/tasks/*.md' 2>/dev/null || true
  find ./knowledge -mindepth 2 -maxdepth 2 -type f -name '*.md' 2>/dev/null || true
}

FILE_LIST="$(collect_files | grep -vE '/(index|log)\.md$' | sort -u || true)"

while IFS= read -r file; do
  [[ -n "$file" ]] || continue
  rel="${file#./}"
  fm_rc=0
  fm="$(frontmatter "$file")" || fm_rc=$?
  if [[ $fm_rc -eq 3 ]] || { [[ $fm_rc -eq 0 ]] && [[ -z "$fm" ]]; }; then
    fail "$rel" "no YAML frontmatter, but it sits in a schema-defined location"
    continue
  fi
  if [[ $fm_rc -eq 4 ]]; then
    fail "$rel" "frontmatter opens with --- but is never closed by a second ---"
    continue
  fi
  checked=$((checked+1))

  type="$(printf '%s\n' "$fm" | sed -n 's/^type:[[:space:]]*//p' | head -1)"
  if [[ -z "$type" ]]; then
    fail "$rel" "missing required field: type"
    continue
  fi
  case " $KNOWN_TYPES " in
    *" $type "*) : ;;
    *) fail "$rel" "unknown type '$type' (known: $KNOWN_TYPES)" ;;
  esac

  allowed="$(enum_for "$type")"
  if [[ -n "$allowed" ]]; then
    status="$(printf '%s\n' "$fm" | sed -n 's/^status:[[:space:]]*//p' | head -1 | sed 's/[[:space:]]*#.*//;s/[[:space:]]*$//')"
    if [[ -z "$status" ]]; then
      fail "$rel" "type $type requires a status (one of: $allowed)"
    else
      case " $allowed " in
        *" $status "*) : ;;
        *) fail "$rel" "status '$status' is not valid for type $type (one of: $allowed)" ;;
      esac
    fi
  fi

  if ! printf '%s\n' "$fm" | grep -q '^timestamp:[[:space:]]*[^[:space:]]'; then
    fail "$rel" "missing required field: timestamp"
  fi

  if [[ "$type" == Finding ]]; then
    lines="$(grep -c '' "$file" || true)"
    if [[ -n "$lines" && "$lines" -gt $FINDING_MAX_LINES ]]; then
      warn "$rel" "Finding is $lines lines; CONVENTIONS.md 'Write less' caps it at $FINDING_MAX_LINES — the history behind it belongs in the task doc"
    fi
    if ! printf '%s\n' "$fm" | grep -q '^lesson:[[:space:]]*[^[:space:]]'; then
      warn "$rel" "Finding has no one-line 'lesson:' — the takeaway the next agent needs, required by CONVENTIONS.md 'Write less'"
    fi
    # The index row, the tags and the supersession edges are build-kb-index.sh's half of
    # the contract; it reads knowledge/index.md, which is not a concept document.
    if printf '%s\n' "$fm" | grep -q '^superseded_by:[[:space:]]*[^[:space:]]' \
       && [[ "$(printf '%s\n' "$fm" | sed -n 's/^status:[[:space:]]*//p' | head -1)" != superseded ]]; then
      fail "$rel" "carries superseded_by: but status is not 'superseded' — SCHEMA.md 'Superseding a Finding' sets both"
    fi
  fi

  if [[ "$type" == Task ]]; then
    dnr="$(printf '%s\n' "$fm" | sed -n 's/^do_not_repeat:[[:space:]]*//p' | head -1)"
    if [[ -n "$dnr" ]]; then
      n="$(flow_entries "$dnr")"
      if [[ -n "$n" && "$n" -gt $DO_NOT_REPEAT_MAX ]]; then
        warn "$rel" "do_not_repeat carries $n entries; CONVENTIONS.md caps it at $DO_NOT_REPEAT_MAX — the project-manager folds the oldest into '# Notes'"
      fi
    fi

    # `open_caveats` holds a TERMINAL write only — `done`/`cancelled`. Any other status
    # with a caveat outstanding is the normal working state and stays silent.
    if [[ "$status" == done || "$status" == cancelled ]]; then
      while IFS= read -r caveat; do
        [[ -n "$caveat" ]] || continue
        fail "$rel" "status '$status' is held by an open caveat (SCHEMA.md 'open_caveats' — clear it with evidence, in its own edit): $caveat"
      done <<< "$(list_entries "$fm" open_caveats)"
    fi
  fi

  structural="$(refs_for "$fm" 'objective|project|phase|depends_on' '/(objectives|projects|knowledge|agents)/[A-Za-z0-9._/-]+[.]md')"
  while IFS= read -r ref; do
    [[ -n "$ref" ]] || continue
    [[ -e ".$ref" ]] || fail "$rel" "dangling reference: $ref"
  done <<< "$structural"

  declared="$(refs_for "$fm" 'artifacts' '/projects/[A-Za-z0-9._/-]+[.]md')"
  while IFS= read -r ref; do
    [[ -n "$ref" ]] || continue
    [[ -e ".$ref" ]] || warn "$rel" "declared artifact does not exist yet: $ref"
  done <<< "$declared"
done <<< "$FILE_LIST"

echo "---"
printf 'validate-bundle: %d documents checked, %d errors, %d warnings.\n' "$checked" "$errors" "$warns"
[[ $errors -eq 0 ]] || exit 1
if [[ $STRICT -eq 1 && $warns -gt 0 ]]; then
  echo "(--strict: warnings are failures)"
  exit 1
fi
exit 0
