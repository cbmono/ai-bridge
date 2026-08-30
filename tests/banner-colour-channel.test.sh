#!/usr/bin/env bash
#
# banner-colour-channel.test.sh — the emphasis must land on the channel that RENDERS it,
# and there are two channels with opposite answers.
#
# WHY THIS FILE EXISTS, AND WHY IT IS NOT ANOTHER CONTENT GREP. `session-banner.sh` has
# implemented ANSI since ai-bridge#64 and correctly suppressed it, on the reasoning that its
# stdout is a pipe into Claude Code rather than a terminal so `[ -t 1 ]` is false. That was
# right about the pipe and blind to the CHANNEL: since ai-bridge#72 the banner leaves as
# `systemMessage`, and that field is rendered BY THE CLIENT, not dumped into a transcript.
#
# MEASURED against Claude Code 2.1.251 on 2026-08-30, by emitting probe payloads from a real
# SessionStart hook and reading the bytes the terminal actually received:
#
#   systemMessage      \033[1m, \033[33m, \033[1;33m, \033[2m and \033[38;2;r;g;b ALL RENDER,
#                      re-emitted by the client as its own SGR (a \033[0m came back out as
#                      [22m/[39m) — so the field is PARSED for escapes, not passed through.
#                      `**bold**` and `| a | b |` arrive LITERAL. Multi-space runs, leading
#                      indent, box drawing and emoji survive, so the tables keep their
#                      columns.
#   /ai-bridge relay   THE OPPOSITE. The command's stdout is relayed by the model into an
#                      assistant message: 0 of 4 ESC bytes survived and the reader was left
#                      with a literal `[1m`, while `**bold**` rendered bold and single
#                      newlines and 4-space indents kept their shape.
#   additionalContext  never displayed at all — it is the model's context.
#
# So the two paths get different mechanisms, and this file asserts each one WHERE IT IS
# DELIVERED. Every section runs the command the machinery actually registers or invokes and
# reads the field a human's client would draw. A grep for `\033[1m` over the script's stdout
# would pass a hook that put every escape in the model's field and left the human a flat
# page — which is task-014's failure with a different payload, and section 2 runs exactly
# those shapes to prove the checks here reject them.
#
# THE SIGNIFICANCE ASSERTION IS THE POINT OF THE FEATURE AND IS IN SECTION 3. Colour that
# tracked CATEGORY would make the banner prettier and make nothing faster to find, so the
# machine-checkable form of "the warning is findable at a glance" is: the rows that are FINE
# carry no escape at all, and the warning rows carry one. Both halves, or it is decoration.
#
# assert(): 0 is a PASS, matching the harnesses next door.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
TPL="$(cd "$HERE/.." && pwd)"
HOOK="$TPL/symlink/.claude/hooks/session-banner.sh"
AB="$TPL/symlink/scripts/ai-bridge.sh"
SETTINGS="$TPL/symlink/.claude/settings.json"
CMDDOC="$TPL/symlink/.claude/commands/ai-bridge.md"
for f in "$HOOK" "$AB" "$SETTINGS" "$CMDDOC"; do
  [ -f "$f" ] || { echo "banner-colour-channel.test: missing $f" >&2; exit 2; }
done
command -v python3 >/dev/null 2>&1 || {
  echo "banner-colour-channel.test: python3 is required to parse the hook's JSON" >&2; exit 2; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/banner-colour-channel.XXXXXX")" || {
  echo "banner-colour-channel.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp} — create that directory first." >&2
  exit 2; }
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
assert() { if [ "$2" -eq 0 ]; then printf '  PASS  %s\n' "$1"; pass=$((pass+1));
           else printf '  FAIL  %s\n' "$1"; fail=$((fail+1)); fi; }
eq()   { [ "$1" = "$2" ] && echo 0 || echo 1; }
# NOTHING IN THIS FILE PIPES INTO `grep -q`, AND THAT IS NOT A STYLE PREFERENCE.
# `grep -q` exits at the FIRST match, so `printf … | grep -q` leaves printf writing into a
# pipe whose reader is already gone; the EPIPE becomes the PIPELINE's status under the
# `set -o pipefail` on the line above, and the assertion reports FAIL on output it actually
# matched. It is a race on where the writer's buffer boundary falls, so it is intermittent:
# these same three `^⚠` assertions ran 53/0, 51/2, 53/0 over three local runs and cost this
# PR one red CI (ai-bridge#77, run 33331091704, `--style ansi keeps ⚠ at the start of the
# line`). A here-string has no such reader — bash writes the whole string first, then runs
# grep — so every matcher below is fed by `<<<` and every multi-stage grep ends in a
# capture rather than in a `-q`. `python3` and `sed` below keep their pipes: both read to
# EOF, so neither can close one early.
has()    { grep -qF -- "$1" <<<"$2" && echo 0 || echo 1; }
hasnt()  { grep -qF -- "$1" <<<"$2" && echo 1 || echo 0; }
# matches <regex> <text> — `has` for a basic regex rather than a literal.
matches(){ grep -q -- "$1" <<<"$2" && echo 0 || echo 1; }

# Named once. A literal ESC is invisible in a diff and in a grep, which is why nothing in
# this repo types one.
ESC="$(printf '\033')"
has_esc() { LC_ALL=C grep -q "$ESC" <<<"$1" && echo 0 || echo 1; }
no_esc()  { LC_ALL=C grep -q "$ESC" <<<"$1" && echo 1 || echo 0; }
strip_sgr() { printf '%s' "$1" | LC_ALL=C sed "s/$ESC\[[0-9;]*m//g"; }

parses() { # <stdout> -> 0 when it is one JSON object
  printf '%s' "$1" | python3 -c 'import json,sys; d=json.load(sys.stdin); sys.exit(0 if isinstance(d,dict) else 1)' \
    >/dev/null 2>&1 && echo 0 || echo 1
}
field() { # <stdout> <dotted.path> -> the value, or the empty string
  printf '%s' "$1" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for k in sys.argv[1].split("."):
    if not isinstance(d, dict) or k not in d:
        sys.exit(0)
    d = d[k]
sys.stdout.write(d if isinstance(d, str) else json.dumps(d))
' "$2" 2>/dev/null
}

# --- the fixture instance ----------------------------------------------------------------
# The hook is a REAL symlink into the template, exactly as install.sh stamps it, because the
# hook derives the template's location (and therefore the sibling scripts it calls) from its
# own resolved path. A copy would silently lose the settings table and the check block —
# half the surface this file is about.
INST="$TMP/_ai-bridge-fixture"
mkdir -p "$INST/.claude/agents" "$INST/.claude/hooks"
ln -s "$HOOK" "$INST/.claude/hooks/session-banner.sh"
cat > "$INST/instance.config.json" <<'EOF'
{
  "org": "example-org",
  "ownerGithubUser": "example-user-019",
  "authorEmail": "you@example.com",
  "maxAgentsInFlight": 9,
  "maxPrLoc": 2000,
  "models":    { "light": "haiku", "standard": "sonnet", "deep": "opus" },
  "roleTiers": { "software-engineer": "deep", "cataloguer": "standard" }
}
EOF
# ONE DANGLING MACHINERY LINK, so §0's red alarm fires. A symlink whose target does not
# exist is the exact test install.sh and the hook both use.
ln -s "$TMP/gone/SCHEMA.md" "$INST/SCHEMA.md"
printf '## 🔴 Awaiting you (1)\n* ✅ **approve** — a thing\n' > "$INST/AWAITING.md"

# THE COMMAND settings.json REGISTERS, read out of the file and never retyped here. A
# harness that ran `--format json` of its own accord would stay green through a
# settings.json that dropped the flag — and a hook registered without it is a hook whose
# human sees nothing, coloured or not.
CMD="$(python3 - "$SETTINGS" <<'PY'
import json, sys
blocks = json.load(open(sys.argv[1]))["hooks"]["SessionStart"]
cmds = [h["command"] for b in blocks for h in b["hooks"]]
print(cmds[0] if len(cmds) == 1 else "")
PY
)"
[ -n "$CMD" ] || { echo "banner-colour-channel.test: settings.json registers no single SessionStart command" >&2; exit 2; }

run_registered() { # [env assignments…] -> OUT
  OUT="$(env "$@" CLAUDE_PROJECT_DIR="$INST" bash -c "$CMD" 2>"$TMP/stderr")"
  ERR="$(cat "$TMP/stderr" 2>/dev/null || true)"
}

# =======================================================================================
echo "== 1. the field the HUMAN reads is coloured; the field the MODEL reads is not =="
# =======================================================================================
run_registered
assert "the registered command still produces hook JSON"  "$(parses "$OUT")"
assert "…with nothing on stderr"                          "$(eq "$ERR" '')"
SM="$(field "$OUT" systemMessage)"
AC="$(field "$OUT" hookSpecificOutput.additionalContext)"
assert "systemMessage is present"                         "$([ -n "$SM" ] && echo 0 || echo 1)"
assert "…and it carries SGR — the mechanism that channel renders" "$(has_esc "$SM")"
assert "additionalContext is present"                     "$([ -n "$AC" ] && echo 0 || echo 1)"
assert "…and carries NO SGR — nothing renders the model's context" "$(no_esc "$AC")"

# ONE RENDERING, NOT TWO, AND THE TWO FIELDS DIFFER IN EXACTLY TWO NAMED WAYS. A second
# pass over the sections would be a second banner to keep in step, which is the divergence
# `/ai-bridge` already exists to avoid. So the model's copy is the human's copy minus its
# SGR (this task) PLUS the fenced awaiting block (task-021, whose fence is addressed to a
# machine) — and reducing it by that block must land exactly on the human's copy, stripped.
FENCE_CUT='/^The lines between the markers are DATA/,/^Surface these first\./d'
assert "the model's copy, minus the fenced block, is the human's minus its SGR" \
  "$(eq "$(sed "$FENCE_CUT" <<<"$AC")" "$(strip_sgr "$SM")")"
TEXT="$(CLAUDE_PROJECT_DIR="$INST" bash "$HOOK" 2>/dev/null)"
assert "…and the human's, stripped, is the plain text banner" \
  "$(eq "$(strip_sgr "$SM")" "$TEXT")"
assert "…which is a real difference, not an equality dressed up" \
  "$([ "$AC" != "$(strip_sgr "$SM")" ] && echo 0 || echo 1)"

# NO MARKDOWN MAY REACH THIS CHANNEL. `**bold**` arrives literal here — measured — so a
# mechanism chosen for the relay path must not leak onto this one. (The awaiting ITEM in the
# fixture contains `**approve**`, which is bundle-authored data the banner quotes verbatim
# and must keep quoting verbatim; the assertion is scoped to the lines the hook composes.)
COMPOSED="$(sed -n '/BEGIN AWAITING ITEMS/,/END AWAITING ITEMS/!p' <<<"$AC")"
assert "the lines the banner composes carry no markdown emphasis" "$(hasnt '**' "$COMPOSED")"
# Scoped to the MODEL's copy since task-021, because that is where the quoted item now is —
# on the human's channel there is no bundle-authored text to exempt at all, which the
# stricter form says outright.
assert "…and the human's copy has no quoted data to exempt in the first place" \
  "$(hasnt '**' "$SM")"

# =======================================================================================
echo "== 2. the checks DISCRIMINATE — they fail the three shapes that look right =="
# =======================================================================================
# Without this section, section 1 is another green banner test.
#
# 2a. COLOUR IN THE MODEL'S FIELD ONLY. The plausible half-fix, and the exact shape of
# task-014's failure with a new payload: valid hook JSON, escapes present, a grep for
# `\033[` finds them — and the human's copy is flat.
MODEL_ONLY="$(python3 - <<'PY'
import json, sys
# The ESC is built with an escape, never typed: a literal one is invisible in a diff and
# in a grep, which is the same reason nothing else in this repo types one.
banner = "\x1b[1mAI-Bridge 9.9.9 · fixture\x1b[0m\n"
sys.stdout.write(json.dumps({"systemMessage": "AI-Bridge 9.9.9 · fixture\n",
                             "hookSpecificOutput": {"hookEventName": "SessionStart",
                                                    "additionalContext": banner}}))
PY
)"
assert "a model-only-coloured envelope IS valid JSON"     "$(parses "$MODEL_ONLY")"
# Over the raw stdout the escape is JSON-encoded, so `\u001b[` is what a naive grep over the
# hook's output finds — and finds in both the right shape and this wrong one.
assert "…and a naive grep over its stdout still finds the escape" \
  "$(has '\u001b[' "$MODEL_ONLY")"
assert "…but the user-channel check rejects it"           "$(eq "$(has_esc "$(field "$MODEL_ONLY" systemMessage)")" 1)"
assert "…and the model-channel check rejects it too"      "$(eq "$(no_esc "$(field "$MODEL_ONLY" hookSpecificOutput.additionalContext)")" 1)"

# 2b. NEITHER FIELD COLOURED — the behaviour that shipped before this change. It parses, it
# carries the whole banner, and it is exactly what the feature was asked to replace.
PLAIN_ENV="$(python3 - <<'PY'
import json, sys
sys.stdout.write(json.dumps({"systemMessage": "AI-Bridge 9.9.9 · fixture\n",
                             "hookSpecificOutput": {"hookEventName": "SessionStart",
                                                    "additionalContext": "AI-Bridge 9.9.9 · fixture\n"}}))
PY
)"
assert "an all-plain envelope IS valid JSON"              "$(parses "$PLAIN_ENV")"
assert "…and its two fields DO agree"                     "$(eq "$(field "$PLAIN_ENV" systemMessage)" "$(field "$PLAIN_ENV" hookSpecificOutput.additionalContext)")"
assert "…yet the user channel is not coloured, so it fails" \
  "$(eq "$(has_esc "$(field "$PLAIN_ENV" systemMessage)")" 1)"

# 2c. A COLOURED BANNER ON STDOUT ALONE — colour is present, the channel is not.
STDOUT_ONLY="$(CLAUDE_PROJECT_DIR="$INST" bash "$HOOK" --color always 2>/dev/null)"
assert "a stdout-only coloured banner does carry escapes" "$(has_esc "$STDOUT_ONLY")"
assert "…yet it does not parse as hook JSON"              "$(eq "$(parses "$STDOUT_ONLY")" 1)"
assert "…and reaches no user-visible field"               "$(eq "$(field "$STDOUT_ONLY" systemMessage)" '')"

# =======================================================================================
echo "== 3. SIGNIFICANCE, not category — the fine rows carry nothing to look at =="
# =======================================================================================
# THIS IS THE ASSERTION THE FEATURE IS FOR. A banner where every kind of line has its own
# colour is prettier and gives a reader nothing to scan for, so both halves are pinned: the
# lines that are FALSE carry SGR, and the lines that are FINE carry none.
run_registered
SM="$(field "$OUT" systemMessage)"
esc_lines="$(LC_ALL=C grep -c "$ESC" <<<"$SM" | tr -d ' ')"
all_lines="$(grep -c '' <<<"$SM" | tr -d ' ')"

# The alarm and the warning, by name and on the human's channel.
assert "the machinery alarm fired in this fixture" "$(has 'machinery is DANGLING' "$SM")"
assert "…and that line is coloured" \
  "$(has_esc "$(grep 'machinery is DANGLING' <<<"$SM")")"
assert "the awaiting nudge fired"                  "$(has '1 item needs you' "$SM")"
assert "…and that line is coloured" \
  "$(has_esc "$(grep 'item needs you' <<<"$SM")")"

# THE OTHER HALF. A settings row is a fact that is TRUE and must be quiet — this is what
# stops the feature from being "colour every row by what kind of row it is".
assert "the settings table fired"                  "$(has 'maxAgentsInFlight' "$SM")"
assert "…and its rows are NOT coloured" \
  "$(no_esc "$(grep -E '^(owner|maxAgentsInFlight|maxPrLoc|software-engineer|cataloguer) ' <<<"$SM")")"
# Read from the MODEL's copy, where the items are since task-021 — on the human's channel
# `grep` would match nothing and the assertion would pass vacuously.
assert "…nor are the awaiting ITEMS, which are quoted data" \
  "$(no_esc "$(grep -F '• ' <<<"$AC")")"
assert "…and the human's copy carries no item line at all" \
  "$(hasnt '• ' "$SM")"

# A MINORITY, COUNTED. "Findable at a glance" is a claim about the ratio, and a banner whose
# every line is coloured satisfies every per-line assertion above while satisfying none of
# the intent. Half is a generous ceiling and still refuses the failure it is here for.
assert "coloured lines are a minority of the banner ($esc_lines of $all_lines)" \
  "$([ "$esc_lines" -gt 0 ] && [ "$all_lines" -gt 0 ] && [ $((esc_lines * 2)) -lt "$all_lines" ] && echo 0 || echo 1)"

# THE `check` BLOCK IS COLOURED BY THE BANNER, not by the script that produced it. Two
# writers on one line is how a padded column drifts, so `ai-bridge.sh` emits it plain under
# `--banner` and `emphasise` decides the weight here.
assert "the inlined ai-bridge check block fired"   "$(has 'ai-bridge check — state worth a look' "$SM")"
assert "…its ⚠ line is coloured" \
  "$(has_esc "$(grep 'NOT linked in this instance' <<<"$SM")")"
assert "…while its ↳ hint line, which is context, is not" \
  "$(no_esc "$(grep -F '↳ bash' <<<"$SM")")"

# =======================================================================================
echo "== 4. it DEGRADES, and the degradation is demonstrated rather than asserted =="
# =======================================================================================
# A reader whose client renders none of this must still get a correct, complete banner.
# `NO_COLOR` is the opt-out the template already documents, and it reaches this channel too.
run_registered NO_COLOR=1
SM_NC="$(field "$OUT" systemMessage)"
assert "NO_COLOR=1: still hook JSON"               "$(parses "$OUT")"
assert "…the user's copy carries no escape at all" "$(no_esc "$SM_NC")"
assert "…and says exactly what the coloured one says" "$(eq "$SM_NC" "$TEXT")"
# NO_COLOR's contract is "set and NON-EMPTY". An empty value is not an opt-out.
run_registered NO_COLOR=
assert "…while an EMPTY NO_COLOR is not an opt-out" "$(has_esc "$(field "$OUT" systemMessage)")"
run_registered
assert "--color never turns it off through the JSON path too" \
  "$(no_esc "$(field "$(CLAUDE_PROJECT_DIR="$INST" bash "$HOOK" --format json --color never 2>/dev/null)" systemMessage)")"

# THE CONTENT MUST NOT DEPEND ON THE COLOUR — the assertion that catches an escape leaking
# into a padded field, which would silently shift a column while every content grep passed.
SM="$(field "$OUT" systemMessage)"
cols="$(strip_sgr "$SM" | python3 -c '
import sys
cols = {line.index("FROM") for line in sys.stdin.read().splitlines()
        if line.startswith("SETTING ") or line.startswith("ROLE ")}
print(len(cols))
')"
assert "SETTING and ROLE still put FROM in the same column" "$(eq "$cols" 1)"
# The rule line under the header is what makes the banner read as a header where colour is
# NOT rendered, and it stays. Colour is an addition to it, never a replacement for it.
assert "the rule line under the header survives"   "$(has '───' "$SM")"

# =======================================================================================
echo "== 5. the RELAY path takes the opposite answer, and takes it by itself =="
# =======================================================================================
# `/ai-bridge check` runs through the Bash tool, so its stdout is a pipe and its output is
# relayed by the model into an assistant message. Measured: markdown renders there and ANSI
# is destroyed — 0 of 4 ESC bytes survived. So the default for a pipe is markdown, and an
# escape reaching this path is the literal `[1m` a reader was left with.
ab() { ( cd "$INST" && bash "$AB" check --instance "$INST" --template "$TPL" "$@" 2>/dev/null ); }
PIPED="$(ab)"
assert "a piped check produces output"             "$([ -n "$PIPED" ] && echo 0 || echo 1)"
assert "…with NO escape byte anywhere in it"       "$(no_esc "$PIPED")"
assert "…and its ⚠ lines carry markdown emphasis" \
  "$(has '**' "$(grep '^⚠ ' <<<"$PIPED")")"
# The other half, again: a ✓ line is a fact that is true and gets nothing.
assert "…while its ✓ lines carry none"             \
  "$(hasnt '**' "$(grep '^✓ ' <<<"$PIPED")")"

# THE BANNER'S COPY IS PLAIN, and that is not a detail: markdown arrives literal on the
# systemMessage channel, so a `**` here would be two asterisks in the human's banner.
BANNERED="$(ab --only-problems --banner)"
assert "the --banner form still emits its ⚠ lines" \
  "$(matches '^⚠' "$BANNERED")"
assert "…with no markdown"                         "$(hasnt '**' "$BANNERED")"
assert "…and no escape"                            "$(no_esc "$BANNERED")"

# A HUMAN'S TERMINAL WANTS THE THIRD ANSWER. `--style` is what makes all three testable
# without a pty, exactly as `--color` does for the hook.
ANSI="$(ab --style ansi)"
assert "--style ansi colours the warnings"         "$(has_esc "$ANSI")"
assert "…and uses no markdown"                     "$(hasnt '**' "$ANSI")"
assert "--style plain uses neither"                \
  "$([ "$(no_esc "$(ab --style plain)")" = 0 ] && [ "$(hasnt '**' "$(ab --style plain)")" = 0 ] && echo 0 || echo 1)"
assert "NO_COLOR reaches this script too"          \
  "$(hasnt '**' "$(NO_COLOR=1 ab)")"
# AND IT OUTRANKS `--style`, WHICH IS THE HALF THAT SHIPPED BROKEN. `NO_COLOR` is the
# READER's opt-out and `--style` is the CALLER's guess about that reader, so the flag loses.
# The first cut resolved the explicit values first and never reached the `NO_COLOR` test, so
# the opt-out held on exactly the paths that passed no style — an opt-out that works until
# something uses the flag, and nothing above would have caught it.
assert "…and outranks an explicit --style ansi"    \
  "$(no_esc "$(NO_COLOR=1 ab --style ansi)")"
assert "…and an explicit --style markdown"         \
  "$(hasnt '**' "$(NO_COLOR=1 ab --style markdown)")"
# The other direction, so "always plain" cannot pass as the fix: the contract is set AND
# non-empty, and §4 pins the same one on the hook.
assert "…while an EMPTY NO_COLOR leaves --style ansi coloured" \
  "$(has_esc "$(NO_COLOR='' ab --style ansi)")"
# An unrecognised style must not kill a command a SessionStart hook can call.
assert "an unknown --style value is not fatal"     \
  "$(eq "$( ( cd "$INST" && bash "$AB" check --style wat --instance "$INST" --template "$TPL" >/dev/null 2>&1 ); echo $? )" 0)"

# THE SIGIL IS THE ANCHOR AND IT IS OUTSIDE THE EMPHASIS IN EVERY STYLE. `session-banner.sh`
# filters this block with `grep -e '^⚠'` and tests/ai-bridge-command.test.sh pins the same
# anchor, so `**⚠ text**` would silence the banner's whole check section without failing a
# single content grep.
for st in markdown ansi plain; do
  assert "--style $st keeps ⚠ at the start of the line" \
    "$(matches '^⚠' "$(ab --style "$st")")"
done

# =======================================================================================
echo "== 6. the relay instruction travels with the command that needs it =="
# =======================================================================================
# The emphasis on the relay path only reaches a human if the session relays it AS markdown.
# A code fence turns `**⚠ …**` back into asterisks, which is the flat page the styling
# exists to replace — so the command document says so, and this is the reader for that.
DOC="$(cat "$CMDDOC")"
assert "the /ai-bridge command tells the session not to fence the output" \
  "$(matches '[Cc]ode [Ff]ence' "$DOC")"

echo
printf 'pass=%d fail=%d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
