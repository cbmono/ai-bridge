#!/usr/bin/env bash
#
# retire-machinery.test.sh — install.sh removes a machinery symlink whose target the
# template no longer ships, and nothing else.
#
# WHY. Removing a capability from symlink/ (the /todo feature was the first) leaves every
# already-stamped instance with a symlink into a path that no longer exists. That is worse
# than an absent file: a dangling command still registers, and a SessionStart hook whose
# script has vanished exits 127 on every launch. Nothing else in the template noticed —
# the link loop only iterates files that DO exist.
#
# The negative properties are the point, and they are what this file mostly asserts:
#   · a real file is never removed, however dead it looks;
#   · a symlink pointing somewhere OTHER than this template is never removed, even when
#     it dangles — it is not ours to judge;
#   · a link that still resolves is left alone;
#   · seed content is never removed. A `todos.md` surviving a retired feature is the
#     human's own writing.
#
# assert(): 0 is a PASS, matching the other harnesses here.
set -uo pipefail

TPLSRC="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/retire-fixture.XXXXXX")" || {
  echo "retire-machinery.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp} — create that directory first." >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
assert() { if [[ "$2" == 0 ]]; then printf '  PASS  %s\n' "$1"; pass=$((pass+1));
           else printf '  FAIL  %s\n' "$1"; fail=$((fail+1)); fi; }
yes_if() { if "$@" >/dev/null 2>&1; then echo 0; else echo 1; fi; }
no_if()  { if "$@" >/dev/null 2>&1; then echo 1; else echo 0; fi; }
has()    { printf '%s\n' "$2" | grep -q -- "$1" && echo 0 || echo 1; }
hasnt()  { printf '%s\n' "$2" | grep -q -- "$1" && echo 1 || echo 0; }

# A copy of the template, so removing a machinery file here cannot touch the real one.
TPL="$TMP/tpl"; mkdir -p "$TPL"
( cd "$TPLSRC" && git ls-files . ) | while IFS= read -r f; do
  [ -n "$f" ] || continue
  mkdir -p "$TPL/$(dirname "$f")"; cp "$TPLSRC/$f" "$TPL/$f" 2>/dev/null || true
done
chmod +x "$TPL/install.sh" "$TPL"/symlink/scripts/*.sh 2>/dev/null || true

INST="$TMP/group/_ai-bridge-group"; mkdir -p "$INST"
bash "$TPL/install.sh" "$INST" >"$TMP/out1" 2>&1
assert "a fresh instance stamps"            "$(yes_if test -f "$INST/instance.config.json")"

# Add a machinery file, stamp it in, then retire it from the template.
printf '#!/usr/bin/env bash\nexit 0\n' > "$TPL/symlink/scripts/doomed.sh"
bash "$TPL/install.sh" "$INST" >"$TMP/out2" 2>&1
assert "the new machinery file is linked"   "$(yes_if test -L "$INST/scripts/doomed.sh")"
assert "…and it resolves"                   "$(yes_if test -e "$INST/scripts/doomed.sh")"

# Decoys that must survive the sweep.
printf 'my own notes\n' > "$INST/scripts/mine.sh"                    # a real file
ln -s "$TMP/nowhere-at-all"  "$INST/scripts/foreign-dangling"        # dangles, NOT ours
ln -s "$TPL/symlink/scripts/commit-as.sh" "$INST/scripts/still-good" # ours, resolves

rm "$TPL/symlink/scripts/doomed.sh"
bash "$TPL/install.sh" "$INST" >"$TMP/out3" 2>&1
RC=$?

assert "install.sh still exits 0"           "$([[ $RC -eq 0 ]] && echo 0 || echo 1)"
assert "the dangling link is removed"       "$(no_if test -L "$INST/scripts/doomed.sh")"
assert "…and it is reported"                "$(yes_if grep -q 'retire scripts/doomed.sh' "$TMP/out3")"
assert "a real file is NOT removed"         "$(yes_if grep -q 'my own notes' "$INST/scripts/mine.sh")"
assert "a foreign dangling link survives"   "$(yes_if test -L "$INST/scripts/foreign-dangling")"
assert "a resolving link of ours survives"  "$(yes_if test -e "$INST/scripts/still-good")"
# Seed content outlives a retired feature: it is the human's writing, not machinery.
printf 'a note I wrote\n' > "$INST/leftover-seed.md"
bash "$TPL/install.sh" "$INST" >"$TMP/out4" 2>&1
assert "seed-shaped content is untouched"   "$(yes_if grep -q 'a note I wrote' "$INST/leftover-seed.md")"
# Idempotent: a second sweep with nothing to do says nothing and still exits 0.
assert "a repeat run retires nothing"       "$(no_if grep -q 'retire ' "$TMP/out4")"

# --- a ROOT-level machinery file, which the first version of the sweep could not see.
# machinery_paths() places SCHEMA.md, AUTONOMY.md and CONVENTIONS.md directly at the
# instance root and more under agents/. The sweep originally scanned only .claude/ and
# scripts/, so it missed exactly the most load-bearing files — and this harness mirrored
# that scope, which is why it passed. Raised in review on PR #62.
printf 'root machinery\n' > "$TPL/symlink/DOOMED-ROOT.md"
mkdir -p "$TPL/symlink/agents"
printf 'nested machinery\n' > "$TPL/symlink/agents/doomed-nested.md"
bash "$TPL/install.sh" "$INST" >"$TMP/out5" 2>&1
assert "a root machinery file links"        "$(yes_if test -L "$INST/DOOMED-ROOT.md")"
assert "a nested one links too"             "$(yes_if test -L "$INST/agents/doomed-nested.md")"
rm "$TPL/symlink/DOOMED-ROOT.md" "$TPL/symlink/agents/doomed-nested.md"
bash "$TPL/install.sh" "$INST" >"$TMP/out6" 2>&1
assert "a dangling ROOT link is swept"      "$(no_if test -L "$INST/DOOMED-ROOT.md")"
assert "…and reported"                      "$(yes_if grep -q 'retire DOOMED-ROOT.md' "$TMP/out6")"
assert "a dangling nested link is swept"    "$(no_if test -L "$INST/agents/doomed-nested.md")"
# A repos/ link points at reposRoot, not into symlink/, so a whole-instance scan must
# still leave it alone — this is what makes widening the scan safe.
mkdir -p "$TMP/elsewhere" && ln -sfn "$TMP/elsewhere" "$INST/repos-decoy"
bash "$TPL/install.sh" "$INST" >"$TMP/out7" 2>&1
assert "a link outside symlink/ survives"   "$(yes_if test -L "$INST/repos-decoy")"

# --- an instance path containing glob metacharacters (SC2295).
# `${dst#$TARGET/}` expands TARGET as a PATTERN, so a `[` in the path strips nothing,
# `rel` stays absolute, `ours` tests a doubled path and returns false — the dead link is
# silently kept. Quoting it fixes that, and only this fixture can tell the difference.
ODD="$TMP/od[d]group/_ai-bridge-odd"; mkdir -p "$ODD"
bash "$TPL/install.sh" "$ODD" >"$TMP/out8" 2>&1
printf 'doomed again\n' > "$TPL/symlink/DOOMED-TWICE.md"
bash "$TPL/install.sh" "$ODD" >"$TMP/out9" 2>&1
assert "glob-y path: the link is created"   "$(yes_if test -L "$ODD/DOOMED-TWICE.md")"
rm "$TPL/symlink/DOOMED-TWICE.md"
bash "$TPL/install.sh" "$ODD" >"$TMP/out10" 2>&1
assert "glob-y path: the link is swept"     "$(no_if test -L "$ODD/DOOMED-TWICE.md")"

# --- the one script this sweep has actually had to retire: build-artifact-board.sh.
# The two HTML renderers were consolidated into `build-board.sh`, which
# deleted the second one from the template — so every instance stamped before that carries
# a link to a path that no longer exists. The generic case above already covers it, and
# that is the claim worth pinning: NO installer edit was needed, so nothing in install.sh
# names this script and nothing there would notice if the sweep regressed. The criterion
# asked for the links to be swept; this asserts that outcome against the real name.
#
# The link is made by INSTALL.SH from a template that still ships the script, not by hand:
# `ln -s "$TPL/..."` writes an unresolved path, and on macOS install.sh resolves its own
# location through /var -> /private/var, so `ours` would not recognise the hand-made link
# and this would pass for the wrong reason. Stamping it the way an instance really got it
# is also the only faithful fixture — that instance was stamped before the deletion.
printf '#!/usr/bin/env bash\nexit 0\n' > "$TPL/symlink/scripts/build-artifact-board.sh"
bash "$TPL/install.sh" "$INST" >/dev/null 2>&1
assert "an instance stamped before the merge has it" "$(yes_if test -e "$INST/scripts/build-artifact-board.sh")"
rm "$TPL/symlink/scripts/build-artifact-board.sh"
bash "$TPL/install.sh" "$INST" >"$TMP/out-board" 2>&1
assert "the retired renderer's link is swept"        "$(no_if test -L "$INST/scripts/build-artifact-board.sh")"
assert "…and reported by name"                       "$(yes_if grep -q 'retire scripts/build-artifact-board.sh' "$TMP/out-board")"
assert "…while the surviving renderer stays linked"  "$(yes_if test -e "$INST/scripts/build-board.sh")"
# Generic on purpose: install.sh must not carry a list of retired machinery to sweep.
assert "install.sh names no retired script"          "$(no_if grep -q 'build-artifact-board' "$TPL/install.sh")"

# --- the two enforcement hooks the plugin absorbed (AI Bridge 2.0, task-003).
# `deny-destructive.sh` and `agent-control.sh` left `symlink/.claude/hooks/` in one change,
# and this is the retirement an instance FEELS most: `settings.json` is itself a link into
# the template, so its `PreToolUse` block goes live the moment the template is pulled,
# while the hook FILES stay linked-and-dangling until a stamp. Between those two clocks the
# instance has no enforcement from either side, which is exactly the ⚠️ the PR carries.
#
# Asserted as a PAIR, not two singles: the failure that matters is partial. One swept and
# one left is indistinguishable from a clean run in any assertion that looks at a single
# name, and the surviving link is a `PreToolUse` command that exits 127 on every tool call.
# Stamped through install.sh, for the reason given above the build-artifact-board block.
V2_HOOKS="deny-destructive agent-control"
mkdir -p "$TPL/symlink/.claude/hooks"
for h in $V2_HOOKS; do printf '#!/usr/bin/env bash\nexit 0\n' \
  > "$TPL/symlink/.claude/hooks/$h.sh"; done
bash "$TPL/install.sh" "$INST" >/dev/null 2>&1
hooked=0; for h in $V2_HOOKS; do [ -e "$INST/.claude/hooks/$h.sh" ] && hooked=$((hooked+1)); done
assert "an instance stamped before the plugin move has both hooks" \
  "$([ "$hooked" -eq 2 ] && echo 0 || echo 1)"
rm -f "$TPL"/symlink/.claude/hooks/deny-destructive.sh "$TPL"/symlink/.claude/hooks/agent-control.sh
bash "$TPL/install.sh" "$INST" >"$TMP/out-hooks" 2>&1
hleft=0; hunreported=0
for h in $V2_HOOKS; do
  [ -L "$INST/.claude/hooks/$h.sh" ] && hleft=$((hleft+1))
  grep -qF "retire .claude/hooks/$h.sh" "$TMP/out-hooks" || hunreported=$((hunreported+1))
done
assert "…and one re-stamp leaves neither"          "$([ "$hleft" -eq 0 ] && echo 0 || echo 1)"
assert "…each reported by name, both of them"      "$([ "$hunreported" -eq 0 ] && echo 0 || echo 1)"
# The hooks that did NOT move must still be linked — a sweep that took the whole directory
# would satisfy both assertions above and break every session's banner.
assert "…while session-banner.sh and push-state.sh stay linked" \
  "$([ -e "$INST/.claude/hooks/session-banner.sh" ] && [ -e "$INST/.claude/hooks/push-state.sh" ] && echo 0 || echo 1)"
# Generic, exactly as with build-artifact-board.sh and the eight commands: the sweep must
# not carry a list of what it retired, or the next retirement needs an installer edit
# nobody will make. THIS IS CRITERION 3's "no install.sh edit" stated as a test.
assert "install.sh names neither hook" \
  "$(no_if grep -qE 'deny-destructive|agent-control' "$TPL/install.sh")"

# --- the agent rename: `oncall-guide` -> `failure-analyst`.
# An agent lives at `.claude/agents/<name>.md`, so renaming one is a machinery DELETE plus
# a machinery ADD, and only the delete half has an owner here. The generic cases above
# cover `scripts/`, the instance root and `agents/` — but NOT `.claude/agents/`, which is
# where every agent actually lives, and a dangling agent file is the same class of failure
# as a dangling command: it stays registered and resolves to nothing. Stamped the way a
# real instance got it (install.sh writes the link, never `ln -s`) for the reason given
# above the build-artifact-board block.
printf -- '---\nname: oncall-guide\ntools: Read\n---\nfixture\n' \
  > "$TPL/symlink/.claude/agents/oncall-guide.md"
bash "$TPL/install.sh" "$INST" >/dev/null 2>&1
assert "an instance stamped before the rename has the old agent" \
  "$(yes_if test -e "$INST/.claude/agents/oncall-guide.md")"
rm "$TPL/symlink/.claude/agents/oncall-guide.md"
bash "$TPL/install.sh" "$INST" >"$TMP/out-agent" 2>&1
assert "the renamed agent's stale link is swept" \
  "$(no_if test -L "$INST/.claude/agents/oncall-guide.md")"
assert "…and reported by name" \
  "$(yes_if grep -qF 'retire .claude/agents/oncall-guide.md' "$TMP/out-agent")"
assert "…while the new name is linked and resolves" \
  "$(yes_if test -e "$INST/.claude/agents/failure-analyst.md")"

# --- the eight commands the plugin absorbed (AI Bridge 2.0).
# The whole command layer left `symlink/` between #107 and #112, one command per slice, as
# each became an `ai-bridge-v2` plugin skill. That is the largest retirement this sweep has
# ever had to make, and it is the one an instance FEELS: a dangling command still registers,
# so until the re-stamp the instance offers `/pm-loop` and fails when you run it.
#
# Asserted as a SET rather than one more single-file case, because the failure that matters
# is partial — seven swept and one left is indistinguishable from a clean run in any
# assertion that looks at a single name, and `docs/operations.md` promises a human that one
# `upgrade.sh` clears all of them. Stamped through install.sh, for the reason given above
# the build-artifact-board block.
V2_COMMANDS="ai-bridge answer audit fanout pr-review-request new-project close-project pm-loop"
mkdir -p "$TPL/symlink/.claude/commands"
for c in $V2_COMMANDS; do printf -- '---\ndescription: fixture\n---\n%s\n' "$c" \
  > "$TPL/symlink/.claude/commands/$c.md"; done
bash "$TPL/install.sh" "$INST" >/dev/null 2>&1
linked=0; for c in $V2_COMMANDS; do [ -e "$INST/.claude/commands/$c.md" ] && linked=$((linked+1)); done
assert "an instance stamped before the migration has all 8" "$([ "$linked" -eq 8 ] && echo 0 || echo 1)"
rm -f "$TPL"/symlink/.claude/commands/*.md
bash "$TPL/install.sh" "$INST" >"$TMP/out-v2" 2>&1
left=0; unreported=0
for c in $V2_COMMANDS; do
  [ -L "$INST/.claude/commands/$c.md" ] && left=$((left+1))
  grep -qF "retire .claude/commands/$c.md" "$TMP/out-v2" || unreported=$((unreported+1))
done
assert "…and one re-stamp leaves none of them"    "$([ "$left" -eq 0 ] && echo 0 || echo 1)"
assert "…each reported by name, all 8"            "$([ "$unreported" -eq 0 ] && echo 0 || echo 1)"
assert "…with the line docs/operations.md quotes" \
  "$(yes_if grep -qF 'retire .claude/commands/pm-loop.md (no longer shipped by the template)' "$TMP/out-v2")"
# Generic, exactly as with build-artifact-board.sh: the sweep must not carry a list of the
# commands it retired, or the next retirement needs an installer edit nobody will make.
assert "install.sh names none of the 8 commands" \
  "$(no_if grep -qE 'pm-loop|pr-review-request|close-project' "$TPL/install.sh")"

# --- retired SEED content: reported with an rm, never removed.
# The asymmetry with the machinery sweep above is the whole point. A symlink into this
# template whose target is gone has one possible meaning; a seed file the human has owned
# since it was copied does not — `todos.md` is literally their notes. install.sh's safety
# property is that it only links and seeds-if-absent, so it may report and must not delete.
SEEDY="$TMP/group/_ai-bridge-seedy"; mkdir -p "$SEEDY"
bash "$TPL/install.sh" "$SEEDY" >/dev/null 2>&1
printf 'my private notes\n' > "$SEEDY/retired-thing.md"
printf 'retired-thing.md\tthe X feature was removed\n' > "$TPL/RETIRED"
OUT="$(bash "$TPL/install.sh" "$SEEDY" 2>&1)"
assert "retired seed content is reported"    "$(has 'stale retired-thing.md' "$OUT")"
assert "…with its reason"                    "$(has 'the X feature was removed' "$OUT")"
assert "…and the exact rm command"           "$(has 'rm .*_ai-bridge-seedy/retired-thing.md' "$OUT")"
assert "…and is NOT deleted"                 "$(yes_if grep -q 'my private notes' "$SEEDY/retired-thing.md")"
# A manifest entry for a file the instance does not have must stay quiet — most entries
# will be irrelevant to most instances, forever.
assert "an absent entry says nothing" \
  "$(hasnt 'stale ' "$(bash "$TPL/install.sh" "$INST" 2>&1)")"
# Comments, blanks and a reason-less line must all parse without noise.
printf '# a comment\n\nretired-thing.md\n' > "$TPL/RETIRED"
OUT2="$(bash "$TPL/install.sh" "$SEEDY" 2>&1)"
assert "a reason-less entry still reports"   "$(has 'stale retired-thing.md' "$OUT2")"
assert "…with a default reason"              "$(has 'no longer shipped by the template' "$OUT2")"
assert "…and comments are not reported"      "$(hasnt 'stale # a comment' "$OUT2")"
# Absence of the manifest is silence, not an error — the AUTONOMY.md convention.
rm -f "$TPL/RETIRED"
RC=0; OUT3="$(bash "$TPL/install.sh" "$SEEDY" 2>&1)" || RC=$?
assert "no manifest: exits 0"                "$([[ $RC -eq 0 ]] && echo 0 || echo 1)"
assert "no manifest: reports nothing"        "$(hasnt 'stale ' "$OUT3")"
assert "no manifest: file still there"       "$(yes_if grep -q 'my private notes' "$SEEDY/retired-thing.md")"
# A dangling SYMLINK at a manifested path belongs to the sweep, not to this list.
: > "$TPL/RETIRED"; printf 'linky.md\tretired\n' >> "$TPL/RETIRED"
ln -sfn "$TMP/gone-forever" "$SEEDY/linky.md"
OUT4="$(bash "$TPL/install.sh" "$SEEDY" 2>&1)"
assert "a symlink is not reported as stale"  "$(hasnt 'stale linky.md' "$OUT4")"

# --- a manifest entry that escapes the instance root is refused, not reported.
# `../victim.md` would make the printed `rm` operate OUTSIDE the instance, and a human
# pasting a command this script handed them has every reason to trust it.
printf 'escapee\n' > "$TMP/group/victim.md"
printf '../victim.md\tretired\n' > "$TPL/RETIRED"
OUT5="$(bash "$TPL/install.sh" "$SEEDY" 2>&1)"
assert "an escaping entry is not reported"   "$(hasnt 'stale \.\./victim.md' "$OUT5")"
assert "…no rm command is printed for it"    "$(hasnt 'rm .*victim.md' "$OUT5")"
assert "…it is warned about instead"         "$(has 'escapes the instance root' "$OUT5")"
assert "…and the outside file is untouched"  "$(yes_if grep -q 'escapee' "$TMP/group/victim.md")"
printf '/etc/passwd\tretired\n' > "$TPL/RETIRED"
OUT6="$(bash "$TPL/install.sh" "$SEEDY" 2>&1)"
assert "an absolute entry is refused"        "$(has 'not instance-relative' "$OUT6")"
assert "…and prints no rm"                   "$(hasnt 'rm /etc/passwd' "$OUT6")"
# A path merely CONTAINING dots is fine — only a `..` component escapes.
printf 'my..notes.md\tretired\n' > "$TPL/RETIRED"
printf 'dotty\n' > "$SEEDY/my..notes.md"
OUT7="$(bash "$TPL/install.sh" "$SEEDY" 2>&1)"
assert "a dotted filename is NOT refused"    "$(has 'stale my\.\.notes.md' "$OUT7")"

echo
printf 'pass=%d fail=%d\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
