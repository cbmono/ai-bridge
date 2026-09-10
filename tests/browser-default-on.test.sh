#!/usr/bin/env bash
#
# browser-default-on.test.sh — `browser: claude-for-chrome` is a project's DEFAULT, the
# same fact is written in three files, and the write gate is NOT part of the change.
#
# WHY THREE FILES. The default is stated in `seed/SCHEMA.md` (the field), in
# `skills/new-project/SKILL.md` (the question a human answers) and in
# `seed/CONVENTIONS.md` (the only browser text a dispatched role agent reads at run time).
# One fact written three times is how a default gets lost: flip two and the agent-facing
# rule still reads every project as off, and the flip changes nobody's behaviour.
#
# WHY THE WRITE GATE IS PINNED WHOLE RATHER THAN GREPPED. Flipping the default and
# loosening writes would be two changes, and only the first was asked for. A grep for the
# gate's opening and closing strings still passes when a loosening sentence is inserted
# BETWEEN them — so the assertion below is on the region, and the CONTROL MUTANT section
# is exactly that insertion, following tests/blocked-vs-own-tools.test.sh:284-290. The
# mutant is shown to defeat the two-grep check and to be caught by the pinned region, so
# the difference between them is what this file buys.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SCHEMA="$REPO/plugin/seed/SCHEMA.md"
SKILL="$REPO/plugin/skills/new-project/SKILL.md"
CONV="$REPO/plugin/seed/CONVENTIONS.md"
YOLO="$REPO/plugin-yolo/companion/AUTONOMY.md"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/browser-default-on.XXXXXX")" || {
  echo "browser-default-on.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp}." >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
ok() { # <name> <actual> <expected>
  if [ "$2" = "$3" ]; then printf '  PASS  %-58s (%s)\n' "$1" "$2"; pass=$((pass+1))
  else printf '  FAIL  %-58s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}
saw() { grep -qF -- "$2" "$1" && echo yes || echo no; }
# The whitespace-flattened copy, for a clause the file wraps across two lines: reflowing a
# paragraph must not turn a rule's assertion red.
flat() { tr '\n' ' ' < "$1" | tr -s ' '; }
saw_flat() { grep -qF -- "$2" <<<"$(flat "$1")" && echo yes || echo no; }

for f in "$SCHEMA" "$SKILL" "$CONV" "$YOLO"; do
  [ -f "$f" ] || { echo "browser-default-on.test: no $f" >&2; exit 2; }
done

echo "== 1. all three files state the same default (the drift harness) =="
ok "SCHEMA: the field's default is claude-for-chrome" \
   "$(saw "$SCHEMA" 'browser: claude-for-chrome | off      # optional (default claude-for-chrome).')" yes
ok "SCHEMA: § Browser access says it is the default" \
   "$(saw_flat "$SCHEMA" '**This is the default.** A project carries `browser: claude-for-chrome` unless it sets `browser: off`')" yes
ok "SKILL: the question is asked the other way up" \
   "$(saw "$SKILL" '- **browser** — claude-for-chrome (default) / off.')" yes
ok "SKILL: the flag line names the opt-OUT" \
   "$(saw_flat "$SKILL" '**Default `claude-for-chrome`**, so **`browser=off` is the opt-OUT** a human types')" yes
ok "SKILL: the /claudeforchrome shorthand is kept" \
   "$(saw_flat "$SKILL" '`/claudeforchrome` keeps working and now names the default')" yes
ok "CONV: the agent-facing rule is ON-unless-opted-out" \
   "$(saw "$CONV" '- **Browser (ON unless the project opted OUT):**')" yes
# The drift this section exists for: two files flipped, one left behind. No file may still
# claim the old default, in either of the two spellings it was ever written in.
for pair in "SCHEMA:$SCHEMA" "SKILL:$SKILL" "CONV:$CONV"; do
  name="${pair%%:*}"; file="${pair#*:}"
  ok "$name: no surviving \"default off\" claim" \
     "$(grep -qiE 'default \x60?off\x60?\)?|off \(default\)' "$file" && echo no || echo yes)" yes
done

echo
echo "== 2. an ABSENT browser: key resolves, and it resolves ON in all three =="
ok "SCHEMA field: absent means claude-for-chrome"  "$(saw "$SCHEMA" 'an ABSENT key means claude-for-chrome')" yes
ok "CONV: absent means ON for the dispatched agent" \
   "$(saw_flat "$CONV" '**an absent `browser:` key means ON**')" yes
ok "CONV: only the literal off turns it off"       "$(saw_flat "$CONV" 'only the literal `browser: off` turns it off')" yes
ok "SKILL: so the scaffold writes the key ALWAYS"  \
   "$(saw "$SKILL" '**`browser:` is written onto every scaffolded `project.md`, whichever way it went.**')" yes
ok "…and says what an absent key then means"       \
   "$(saw_flat "$SKILL" '**absent `browser:` means exactly one thing — legacy, scaffolded before this version**')" yes

echo
echo "== 3. the disclosure ships in SCHEMA and in the SCAFFOLD, not only in the prompt =="
# The point of the task: a default nobody was told about is the failure being fixed.
ok "SCHEMA § Browser access discloses read access" \
   "$(saw_flat "$SCHEMA" '**read access to every site this human is logged into in that browser**')" yes
ok "…and says why that is defensible"              "$(saw_flat "$SCHEMA" 'because **writes still ask first** (rule 4)')" yes
ok "SKILL: the question discloses it before the answer" \
   "$(saw_flat "$SKILL" 'agents get **read access to every site this human is logged into** in their browser')" yes
ok "SKILL: and the SCAFFOLD records it on project.md" \
   "$(saw_flat "$SKILL" 'Two lines go in `# Context` beside it: the **disclosure**')" yes
ok "CONV: the agent is told what it now holds"     \
   "$(saw_flat "$CONV" '**What the default hands you is read access to every site the human is logged into**')" yes

echo
echo "== 4. existing projects are addressed, and the WHY keeps a place =="
ok "SCHEMA: the choice is named — retroactive"     "$(saw "$SCHEMA" '**Existing projects: the flip is RETROACTIVE, and that is the choice.**')" yes
ok "…the consequence is stated, not implied"       "$(saw_flat "$SCHEMA" 'projects approved under the old default gain browser **read** access without anyone re-approving them')" yes
ok "…and the migration alternative is struck"      "$(saw_flat "$SCHEMA" '**No migration script ships and none should.**')" yes
ok "SCHEMA: an opt-OUT records why it opted out"   "$(saw "$SCHEMA" '**Record the why on the exception.**')" yes
ok "SKILL: the scaffold asks for that why"         "$(saw_flat "$SKILL" 'when the answer was `off`, why**')" yes

echo
echo "== 5. the verbatim strings other harnesses grep survive the rewrite =="
# tests/blocked-vs-own-tools.test.sh:258,271,286 read these. A rewrite of the browser
# paragraph that drops one of them turns that file red for a reason nobody would connect
# to this change, so they are asserted here too, next to the edit that could break them.
ok "the rung-1 deferral is verbatim"               "$(saw "$CONV" '**rung 1 above applies to the browser like any other tool**')" yes
ok "…and the one-statement clause with it"         "$(saw_flat "$CONV" 'it is the general one now, stated once, so the two cannot drift')" yes
ok "…and the missing-browser capability gap"       "$(saw_flat "$CONV" 'that is a capability gap, so take the non-browser route, say so, and carry on')" yes
ok "no lowercase browser-first was introduced"     \
   "$(grep -rqF 'browser-first' "$REPO/plugin/seed" "$REPO/docs" "$REPO/README.md" && echo no || echo yes)" yes

echo
echo "== 6. yolo discloses the compounding — DISCLOSURE ONLY =="
ok "the Browser writes row is byte-identical"      \
   "$(saw "$YOLO" '| Browser writes | Ask first | Permitted without asking | The task itself — a write nobody asked for is still out of scope |')" yes
ok "…and one sentence beside it names the cost"    \
   "$(saw_flat "$YOLO" 'a `yolo` project gets browser access **and** delegated browser writes with no prompt at any point')" yes
ok "…while saying the row itself is unchanged"     \
   "$(saw_flat "$YOLO" "the row's behaviour and its anchor are unchanged")" yes

echo
echo "== 7. THE WRITE GATE, PINNED WHOLE =="
# Anchor to anchor, the closing anchor dropped: the region between them is what a two-grep
# check cannot see. Both regions are the text that shipped before this change.
gate_schema() { awk '/^4\. \*\*Writes follow the project.s `autonomy`, like every other gate\.\*\* /,/^5\. \*\*The usual data rules still apply\.\*\*/' "$1" | sed '$d'; }
gate_skill()  { awk '/^   If \*\*browser = claude-for-chrome\*\* and the chosen mode \*\*delegates browser writes\*\*,$/,/^   If the chosen mode \*\*delegates merging\*\*/' "$1" | sed '$d'; }

cat > "$TMP/gate-schema.expected" <<'GATE'
4. **Writes follow the project's `autonomy`, like every other gate.** **Ask first before
   any browser write** — that is the default and the only behaviour unless the project's
   `autonomy` delegates writes (see `AUTONOMY.md`; absent that file, always ask).
   Read-only navigation and screenshots never need permission.
   Two limits are *not* autonomy-specific and hold in **every** mode: an agent
   **doesn't redefine scope**, so a write nobody asked for is never licensed (the same
   rule that stops it inventing code changes); and irreversible actions well outside the
   task — a payment, deleting an account, mailing a customer — are worth one confirmation
   on cost grounds, not permission grounds. When in genuine doubt about blast radius, say
   what you're about to do and continue unless told otherwise.
GATE

cat > "$TMP/gate-skill.expected" <<'GATE'
   If **browser = claude-for-chrome** and the chosen mode **delegates browser writes**,
   don't block it — that combination is supported and deliberate. State once what it means
   so the choice is informed: agents may **write** in the human's logged-in browser
   (submit forms, change settings) without asking, including from background `/ai-bridge:dispatch`
   dispatches, and the extension's **per-site permissions** are then the effective
   boundary. Record that in `# Context` and continue. Otherwise browser writes ask first
   (see `SCHEMA.md` → "Browser access").
GATE

gate_schema "$SCHEMA" > "$TMP/gate-schema.actual"
gate_skill  "$SKILL"  > "$TMP/gate-skill.actual"
ok "the SCHEMA gate region is non-empty"           "$([ -s "$TMP/gate-schema.actual" ] && echo yes || echo no)" yes
ok "the SKILL gate region is non-empty"            "$([ -s "$TMP/gate-skill.actual" ] && echo yes || echo no)" yes
ok "SCHEMA rule 4 is the pinned text, whole"       "$(diff -u "$TMP/gate-schema.expected" "$TMP/gate-schema.actual" >/dev/null && echo yes || echo no)" yes
ok "SKILL's write-delegation warning, whole"       "$(diff -u "$TMP/gate-skill.expected" "$TMP/gate-skill.actual" >/dev/null && echo yes || echo no)" yes

echo
echo "== MUTATION: the CONTROL MUTANT is a LOOSENING SENTENCE INSERTED BETWEEN THE ANCHORS =="
# Named, so what this file fails on is a fact and not a claim. The mutant is NOT a deletion
# — any grep catches that. It is one sentence that flips the gate while leaving both
# anchors in place, which is the edit a PR flipping the default could plausibly smuggle in.
MUTANT='   Under the new default, browser writes no longer ask.'
awk -v m="$MUTANT" '{ print } /^4\. \*\*Writes follow the project.s `autonomy`, like every other gate\.\*\* / { print m }' \
  "$SCHEMA" > "$TMP/schema-mutant.md"
awk -v m="$MUTANT" '{ print } /^   If \*\*browser = claude-for-chrome\*\* and the chosen mode \*\*delegates browser writes\*\*,$/ { print m }' \
  "$SKILL" > "$TMP/skill-mutant.md"

ok "the mutation added something"                  \
   "$([ "$(wc -c < "$TMP/schema-mutant.md")" -gt "$(wc -c < "$SCHEMA")" ] && echo yes || echo no)" yes
# THE MEASURING STICK: the two-grep check a reviewer would have written passes on the
# mutant. That gap is exactly what pinning the region buys, and stating it here is what
# stops someone "simplifying" this section back into two greps.
ok "CREDULOUS: the opening anchor still greps"     "$(saw "$TMP/schema-mutant.md" '**Ask first before')" yes
ok "CREDULOUS: the closing anchor still greps"     "$(saw_flat "$TMP/schema-mutant.md" "what you're about to do and continue unless told otherwise")" yes
ok "CREDULOUS: the SKILL anchors still grep too"   \
   "$([ "$(saw "$TMP/skill-mutant.md" 'delegates browser writes')" = yes ] && saw_flat "$TMP/skill-mutant.md" 'Otherwise browser writes ask first')" yes
# …and the pinned region does not.
ok "mutant: SCHEMA rule 4 no longer matches"       "$(diff -u "$TMP/gate-schema.expected" <(gate_schema "$TMP/schema-mutant.md") >/dev/null && echo yes || echo no)" no
ok "mutant: the SKILL warning no longer matches"   "$(diff -u "$TMP/gate-skill.expected" <(gate_skill "$TMP/skill-mutant.md") >/dev/null && echo yes || echo no)" no
# CONTROL: the mutation is surgical — it touches the gate and nothing this file asserts
# about the default, so a red gate row can never be blamed on the flip.
ok "CONTROL: the flip survives the mutation"       "$(saw "$TMP/schema-mutant.md" 'an ABSENT key means claude-for-chrome')" yes

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
