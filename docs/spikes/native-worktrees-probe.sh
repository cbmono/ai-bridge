#!/usr/bin/env bash
#
# native-worktrees-probe.sh — re-measures docs/spikes/native-worktrees.md.
# Builds a fixture bundle + fixture product repo under a temp root and prints
# one line per probe. Probes 1-3 need no auth (the worktree is created before
# the auth check); probes 4-5 spend one haiku turn each, use your REAL
# CLAUDE_CONFIG_DIR because they need auth, and are skipped without --live.
# Exit 0 always: this reports, it never gates.
set -uo pipefail

LAB="$(mktemp -d)"; LIVE="${1:-}"
trap 'rm -rf "$LAB"' EXIT
say() { printf '%-42s %s\n' "$1" "$2"; }

P="$LAB/product"; mkdir -p "$P"
git -C "$P" init -q -b trunk .
git -C "$P" -c user.email=f@f -c user.name=f commit -q --allow-empty -m init

B="$LAB/bundle"; mkdir -p "$B/repos"
git -C "$B" init -q -b main .
git -C "$B" -c user.email=f@f -c user.name=f commit -q --allow-empty -m init
ln -s "$P" "$B/repos/product"

mkdir -p "$LAB/wtroot"
cat > "$LAB/create.sh" <<HOOK
#!/usr/bin/env bash
payload="\$(cat)"; printf '%s\n' "\$payload" > "$LAB/create-payload.json"
name="\$(printf '%s' "\$payload" | sed -n 's/.*"name":"\([^"]*\)".*/\1/p')"
git -C "$P" worktree add -q "$LAB/wtroot/\$name" -b "hooked-\$name" trunk 2>/dev/null || true
printf '%s\n' "$LAB/wtroot/\$name"
HOOK
cat > "$LAB/remove.sh" <<HOOK
#!/usr/bin/env bash
cat > "$LAB/remove-payload.json"
HOOK
chmod +x "$LAB/create.sh" "$LAB/remove.sh"
cat > "$LAB/settings.json" <<JSON
{"hooks":{
 "WorktreeCreate":[{"hooks":[{"type":"command","command":"$LAB/create.sh"}]}],
 "WorktreeRemove":[{"hooks":[{"type":"command","command":"$LAB/remove.sh"}]}]}}
JSON

# run <seconds> <cwd> <extra-args...> — bounded by a SIBLING watchdog, so the
# bound holds even if this shell is killed (CONVENTIONS.md, background teardown).
run() {
  local secs="$1" dir="$2"; shift 2
  ( cd "$dir" && claude -p --model haiku --dangerously-skip-permissions "$@" ) \
    </dev/null >"$LAB/out" 2>&1 &
  local child=$!
  ( sleep "$secs"; kill "$child" 2>/dev/null ) >/dev/null 2>&1 &
  wait "$child" 2>/dev/null
}

# --- 1. no hook: --worktree worktrees the CWD's repo, inside it, and locks it ---
CLAUDE_CONFIG_DIR="$LAB/home" run 120 "$P" --worktree probe-a 'x'
say "a: worktree path" \
  "$(git -C "$P" worktree list | sed -n 's|.*/\(\.claude/worktrees/probe-a\).*|\1|p' | head -1)"
say "a: branch"  "$(git -C "$P" worktree list | sed -n 's/.*\[\(worktree-probe-a\)\].*/\1/p')"
say "a: locked"  "$(git -C "$P" worktree list | grep -c 'probe-a.*locked')"
say "a: product repo dirty" "$(git -C "$P" status --porcelain | tr -d '\n')"

# --- 2. hook precedence when the cwd IS a git repo -------------------------------
CLAUDE_CONFIG_DIR="$LAB/home" run 120 "$P" --settings "$LAB/settings.json" --worktree probe-b 'x'
say "b: hook won over .claude/worktrees" \
  "$([ -d "$LAB/wtroot/probe-b" ] && [ ! -d "$P/.claude/worktrees/probe-b" ] && echo yes || echo no)"

# --- 3. cross-repo: cwd = bundle, hook emits a worktree of the PRODUCT repo ------
CLAUDE_CONFIG_DIR="$LAB/home" run 120 "$B" --settings "$LAB/settings.json" --worktree probe-c 'x'
say "c: worktree is of the product repo" \
  "$(git -C "$P" worktree list | grep -c 'probe-c')"
say "c: bundle worktrees (1 = main only)" "$(git -C "$B" worktree list | wc -l | tr -d ' ')"
say "c: payload" "$(cat "$LAB/create-payload.json" 2>/dev/null)"

[ "$LIVE" = "--live" ] || { say "live probes" "skipped (pass --live)"; exit 0; }

# --- 4. a live session really lands in the hook's cross-repo worktree ------------
run 240 "$B" --settings "$LAB/settings.json" --worktree probe-d \
  'Run exactly: pwd; git rev-parse --abbrev-ref HEAD. Print the raw output only.'
say "d: session cwd" "$(grep -o "$LAB/wtroot/probe-d" "$LAB/out" | head -1)"

# --- 5. a subagent with isolation:"worktree" lands there too, and is not reaped --
run 300 "$B" --settings "$LAB/settings.json" \
  --agents '{"probe":{"description":"probe","tools":["Bash"],"isolation":"worktree","prompt":"Run: pwd; git rev-parse --abbrev-ref HEAD. Report raw output only."}}' \
  'Dispatch the `probe` agent once with the Task tool. Report its output verbatim.'
say "e: agent worktree name" "$(sed -n 's/.*"name":"\(agent-[^"]*\)".*/\1/p' "$LAB/create-payload.json")"
say "e: WorktreeRemove fired" "$([ -f "$LAB/remove-payload.json" ] && echo yes || echo no)"

git -C "$P" worktree list --porcelain | awk '/^worktree /{print $2}' | tail -n +2 |
  while read -r w; do git -C "$P" worktree remove -f -f "$w" 2>/dev/null || rm -rf "$w"; done
