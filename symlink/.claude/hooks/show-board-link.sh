#!/usr/bin/env bash
#
# show-board-link.sh — SessionStart hook (ai-bridge machinery).
#
# Prints the path to THIS machine's rendered board when a session starts, so the human
# can open it immediately instead of hunting for it. The board is `.board-live/board.html`
# — the same default path `scripts/watch-board.sh` writes and `install.sh` gitignores, and
# the path a `/pm-loop` tick re-renders as its last act (see project-manager.md step 8).
# One board, one path, one place it lives. This hook never renders it and never writes it.
#
# A LOCAL FILE, NOT A PUBLISHED URL — AND THAT IS A REVERSAL. This hook used to print a
# recorded artifact URL, the page a tick republished every gap. That whole path is
# deleted: artifact publishing is ACCOUNT-SCOPED, so the board vanished from under its own
# owner the moment they switched Claude accounts, and no share level ever made it writable
# by a second human. A rendered file on disk has neither problem — it belongs to the
# machine, not to an account — and the other owners' projects still appear on it, because
# `build-board.sh` reads those from the tracked task documents at this clone's git `HEAD`
# rather than from anything published.
#
# IT IS NOT LIVE, AND IT MUST NOT READ AS LIVE. Nothing refreshes a rendered file; the
# tick re-renders it once per gap and it is stale in between. The page's own masthead
# timestamp says how old it is, so the third line points at that and at
# `scripts/watch-board.sh` for a view that re-renders on every change. Claiming a
# freshness this surface cannot deliver is worse than saying nothing.
#
# TWO SURFACES FOR ONE PATH, DELIBERATELY. `file://` is a hyperlink in some terminals and
# inert text in others, so the bare path is printed on its own line, unprefixed and
# unindented, where a triple-click copies exactly the path and nothing else.
#
# Absence is the off switch, same shape as show-awaiting.sh. No `instance.config.json`
# (a non-bridge project that inherits this hook), no `.claude/agents` (same "is this
# actually an instance" signature check-machinery.sh and push-state.sh use), `board:
# false`, or no rendered page yet — every one of those means exit 0 in silence, never an
# error. Deliberately narrow: the ONLY thing this hook ever prints is that path. It reads
# no task document, so nothing task-derived can reach stdout — that's `show-awaiting.sh`'s
# job, already covered, and a second copy of its field discipline is exactly what this
# hook must not become.
set -uo pipefail

root="${CLAUDE_PROJECT_DIR:-$PWD}"
cfg="$root/instance.config.json"
[ -f "$cfg" ] && [ -d "$root/.claude/agents" ] || exit 0

# THE `board` GATE — THE SAME KEY `install.sh` ALREADY READS, NOT A SECOND SWITCH.
# `install.sh` reads it at STAMP time (`cfg_bool board true`) to decide whether
# SNAPSHOT.json is seeded; this is a second reader of the same key at the other end of the
# lifecycle. Same file — the TRACKED `instance.config.json`, because `board` is not in the
# per-machine override set (SCHEMA.md → "Per-machine config overrides") and reading it
# from somewhere the stamp-time reader does not look is how one key becomes two switches.
# Same default, too: absent means on.
#
# A FIXED GREP FOR `false`, NEVER A `\(true\|false\)` ALTERNATION. That alternation is a
# GNU sed extension; BSD sed matches nothing with it and the reader then returns its
# default forever — which is exactly how `install.sh`'s own `cfg_bool()` came to ignore
# `board: false` once already (its header records the fix, and this is the same fix). A
# switch whose reader silently always answers "default" is indistinguishable from the
# inert key this gate exists to close, so it is worth the repetition.
#
# Only `false` is tested, because the default is on: `true` and absent do the same thing.
# Testing the opt-OUT rather than the opt-in is also the safer direction — a value this
# grep cannot make sense of leaves the board switched on, never silently switched off.
#
# Not line-anchored, which is what makes a hand-written one-liner (`{ "board": false }` —
# the shape SCHEMA.md tells a second human to write) read the same as the pretty-printed
# tracked file. The leading quote in `"board"` is what keeps the seeded `"$board"` doc
# string, whose prose mentions both `true` and `false`, from ever being read AS the
# setting, and what keeps `"boardInstances"` out of it.
#
# grep rather than a jq dependency, matching show-awaiting.sh and push-state.sh (bash +
# sed/awk only) rather than agent-control.sh's jq-hard-requirement, which pays for a real
# parser because it is a security control.
#
# NEWLINES ARE FLATTENED FIRST, because `grep` reads one line at a time and JSON does not
# have to put a key and its value on one. `{"board":\n  false}` is valid, and a line-wise
# reader answers "on" for it — failing OPEN again, by a second route. Flattening cannot
# widen the match across members: the pattern requires `false` immediately after the
# colon, so `"board": true, "x": false` still reads as true.
#
# THIS IS ONE STEP AHEAD OF `install.sh`'s `cfg_bool()`, WHICH IS DELIBERATE. That reader
# is line-wise and stays that way — it is pinned by tests/snapshot.test.sh and is not this
# change's to move. On the split-line config the two disagree in the SAFE direction: the
# installer seeds a snapshot, and this hook still honours the `false` and stays quiet.
if tr '\n' ' ' < "$cfg" 2>/dev/null | grep -q '"board"[[:space:]]*:[[:space:]]*false'; then
  exit 0
fi

page="$root/.board-live/board.html"
[ -f "$page" ] || exit 0

echo "🔗 Board: file://$page"
echo "$page"
echo "   rendered at the last tick — the masthead says when; scripts/watch-board.sh keeps a live one"
