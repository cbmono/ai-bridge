#!/usr/bin/env bash
#
# native-worktrees-probe-2.sh — re-measures the "Re-test" section of
# docs/spikes/native-worktrees.md. Fixture bundle + fixture product repo (default branch
# `trunk`) under a temp root; no production bundle is touched and nothing is deployed.
# Probes 1-6 need no auth (the worktree is created before the auth check) and use a
# throwaway CLAUDE_CONFIG_DIR; probes 7-9 spend one haiku turn each against your REAL
# config and are skipped without --live.
# Exit 0 always: this reports, it never gates.
set -uo pipefail

LIVE="${1:-}"
LAB="$(mktemp -d "${TMPDIR:-/tmp}/native-worktrees-probe.XXXXXX")" || {
  echo "native-worktrees-probe-2: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp}." >&2; exit 2; }
[ -d "$LAB" ] || { echo "native-worktrees-probe-2: mktemp -d returned no usable directory." >&2; exit 2; }
# Only ever the fixture's own trees, by path, under a mktemp root: never a scan of a
# real worktreeRoot — that is the 2026-08-04 incident, and this file must not model it.
cleanup() {
  local w
  git -C "$LAB/product" worktree list --porcelain 2>/dev/null |
    awk '/^worktree /{print $2}' | tail -n +2 |
    while read -r w; do git -C "$LAB/product" worktree remove -f -f "$w" 2>/dev/null; done
  rm -rf "$LAB"
}
trap cleanup EXIT
say() { printf '%-46s %s\n' "$1" "$2"; }

P="$LAB/product"; mkdir -p "$P"
git -C "$P" init -q -b trunk .
git -C "$P" -c user.email=f@f -c user.name=f commit -q --allow-empty -m init
B="$LAB/bundle"; mkdir -p "$B/repos" "$LAB/wtroot" "$LAB/log"
git -C "$B" init -q -b main .
git -C "$B" -c user.email=f@f -c user.name=f commit -q --allow-empty -m init
ln -s "$P" "$B/repos/product"

# The create hook under test: log the whole payload, then place a worktree of the
# PRODUCT repo at <worktreeRoot>/<name> and print it. `emit` swaps its last line.
emit() { cat > "$LAB/create.sh" <<HOOK
#!/usr/bin/env bash
payload="\$(cat)"
printf 'create\n' >> "$LAB/log/events"
printf '%s %s\n' "\$(date -u +%FT%T.%N)" "\$payload" >> "$LAB/log/create.jsonl"
name="\$(printf '%s' "\$payload" | sed -n 's/.*"name":"\([^"]*\)".*/\1/p')"
git -C "$P" worktree add -q "$LAB/wtroot/\$name" -b "\$name" trunk 2>/dev/null || true
$1
HOOK
chmod +x "$LAB/create.sh"; }
emit 'printf "%s\n" "'"$LAB"'/wtroot/$name"'
cat > "$LAB/remove.sh" <<HOOK
#!/usr/bin/env bash
{ printf '%s ' "\$(date -u +%FT%T.%N)"; cat; printf '\n'; } >> "$LAB/log/remove.jsonl"
exit 1
HOOK
cat > "$LAB/pretool.sh" <<HOOK
#!/usr/bin/env bash
printf 'pretool\n' >> "$LAB/log/events"
{ printf '%s ' "\$(date -u +%FT%T.%N)"; cat; printf '\n'; } >> "$LAB/log/pretool.jsonl"
HOOK
chmod +x "$LAB/remove.sh" "$LAB/pretool.sh"
settings() { cat > "$LAB/settings.json" <<JSON
{${1:-}"hooks":{
 "WorktreeCreate":[{"hooks":[{"type":"command","command":"$LAB/create.sh"}]}],
 "WorktreeRemove":[{"hooks":[{"type":"command","command":"$LAB/remove.sh"}]}],
 "PreToolUse":[{"matcher":"Agent","hooks":[{"type":"command","command":"$LAB/pretool.sh"}]}]}}
JSON
}
settings

# run <seconds> <cwd> <args…> — bounded by a SIBLING watchdog, so the bound holds even
# if this shell is killed (CONVENTIONS.md, background teardown).
run() {
  local secs="$1" dir="$2"; shift 2
  ( cd "$dir" && claude -p --model haiku --dangerously-skip-permissions "$@" ) \
    </dev/null >"$LAB/out" 2>&1 &
  local child=$!
  ( sleep "$secs"; kill "$child" 2>/dev/null ) >/dev/null 2>&1 &
  wait "$child" 2>/dev/null
}
offline() { CLAUDE_CONFIG_DIR="$LAB/home" run 120 "$@" --settings "$LAB/settings.json"; }
last_payload() { sed -e 's/"transcript_path":"[^"]*",//' "$LAB/log/create.jsonl" | tail -1; }

# --- 1-2. the payload, and whether it names the task or the base ref -------------
offline "$B" --worktree task-029 'x'
say "1: create payload" "$(last_payload | cut -d' ' -f2-)"
say "2: base_ref present" "$(last_payload | grep -qc base_ref && echo yes || echo no)"
settings '"worktree":{"baseRef":"fresh"},'
offline "$B" --worktree task-030 'x'
say "2b: …with worktree.baseRef set" "$(last_payload | grep -qc base_ref && echo yes || echo no)"
settings

# --- 3. the path the hook prints must EXIST --------------------------------------
# Existence only — probe 6 accepts a pre-existing tree the hook did not create, so nothing
# here establishes that Claude checks OWNERSHIP of the directory.
emit 'printf "%s\n" "'"$LAB"'/wtroot/never-created"'
offline "$B" --worktree nc 'x'
say "3: prints a path that does not exist" "$(sed -n 's/.*\(does not exist or is not a directory\).*/\1/p' "$LAB/out" | head -1)"

# --- 4. a non-zero create hook aborts creation -----------------------------------
emit 'printf "%s\n" "'"$LAB"'/wtroot/$name"; exit 1'
offline "$B" --worktree nz 'x'
say "4: non-zero create hook" "$(sed -n 's/.*\(WorktreeCreate hook failed\).*/\1/p' "$LAB/out" | head -1)"
emit 'printf "%s\n" "'"$LAB"'/wtroot/$name"'

# --- 5. naming: a relative path, and a path with a space -------------------------
mkdir -p "$B/wtroot/rel"
emit 'printf "%s\n" "wtroot/rel"'
offline "$B" --worktree rel 'x'
say "5: relative path" "$(sed -n 's/.*\(Refusing to use\).*/\1/p' "$LAB/out" | head -1)"
emit 'git -C "'"$P"'" worktree add -q "'"$LAB"'/wtroot/task 031 sp" -b sp-space trunk 2>/dev/null; printf "%s\n" "'"$LAB"'/wtroot/task 031 sp"'
offline "$B" --worktree sp 'x'
say "5b: path containing a space" "$(grep -qc 'Not logged in' "$LAB/out" && echo accepted || echo refused)"

# --- 6. a DIRTY existing worktree ------------------------------------------------
git -C "$P" worktree add -q "$LAB/wtroot/task-032" -b task-032 trunk
echo uncommitted > "$LAB/wtroot/task-032/scratch.txt"
emit 'printf "%s\n" "'"$LAB"'/wtroot/task-032"'
offline "$B" --worktree dirty 'x'
say "6: dirty tree reused" "$(grep -qc 'Not logged in' "$LAB/out" && echo accepted || echo refused)"
say "6b: uncommitted file survived" "$(cat "$LAB/wtroot/task-032/scratch.txt" 2>/dev/null)"
emit 'printf "%s\n" "'"$LAB"'/wtroot/$name"'

# --- 6c. the hookless route locks, and locks inside the product clone ------------
CLAUDE_CONFIG_DIR="$LAB/home" run 120 "$P" --worktree probe-lock 'x'
say "6c: hookless --worktree" "$(git -C "$P" worktree list | sed -n 's|.*/\(\.claude/worktrees/probe-lock\) *[0-9a-f]* \(.*\)|\1 \2|p')"

[ "$LIVE" = "--live" ] || { say "live probes" "skipped (pass --live)"; exit 0; }

# --- 7. a SESSION named by the task lands in <worktreeRoot>/<task-id> ------------
run 300 "$B" --settings "$LAB/settings.json" --worktree task-033 \
  'Run these as separate commands, report raw output only: pwd ; git rev-parse --abbrev-ref HEAD ; git worktree list --porcelain'
say "7: session cwd" "$(grep -o "$LAB/wtroot/task-033\$" "$LAB/out" | head -1)"
say "7b: branch" "$(grep -ox 'task-033' "$LAB/out" | head -1)"
# Its OWN stanza only: probe 6c left a genuinely locked hookless tree in the same repo,
# and a bare `grep locked` over the listing counts that one instead.
say "7c: its own tree locked while it ran" \
  "$(awk '/^worktree .*wtroot\/task-033$/{f=1;next} /^worktree /{f=0} f&&/^locked/{print "yes"}' \
     "$LAB/out" | head -1 | grep -q yes && echo yes || echo no)"

# --- 8. a SUBAGENT lands there too, but the payload cannot name the task ---------
rm -f "$LAB/log/pretool.jsonl" "$LAB/log/events"
run 420 "$B" --settings "$LAB/settings.json" \
  --agents '{"probe":{"description":"probe","tools":["Bash"],"isolation":"worktree","prompt":"Run `pwd` and report its raw output only."}}' \
  'In ONE message, use the Agent tool TWICE in parallel to dispatch two subagents of type `probe`: prompts "TASK-101 pwd" and "TASK-202 pwd". Report both outputs verbatim.'
say "8: subagent worktree names" "$(sed -n 's/.*"name":"\(agent-[^"]*\)".*/\1/p' "$LAB/log/create.jsonl" | tail -2 | tr '\n' ' ')"
say "8b: distinct prompt_ids over both" \
  "$(sed -n 's/.*"prompt_id":"\([^"]*\)".*/\1/p' "$LAB/log/create.jsonl" | tail -2 | sort -u | wc -l | tr -d ' ')"
# Arrival order, not timestamp order: one appended line per event to ONE file, so the file
# IS the total order. Two clocks can tie, and a tie broken by the label would report an
# ordering nothing measured.
say "8c: hook order over one turn (unstable — seen both ways)" \
  "$(tr '\n' ' ' < "$LAB/log/events" 2>/dev/null)"

# --- 9. WorktreeRemove ----------------------------------------------------------
say "9: WorktreeRemove fired" "$([ -s "$LAB/log/remove.jsonl" ] && echo yes || echo no)"
say "9b: the session's own tree survived" \
  "$(git -C "$P" worktree list | grep -c 'wtroot/task-033' | tr -d ' ')"
