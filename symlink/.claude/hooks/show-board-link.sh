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
# A single top-level scalar — grep/sed rather than a jq dependency, matching
# show-awaiting.sh and push-state.sh (bash + sed/awk only) rather than agent-control.sh's
# jq-hard-requirement, which pays for a real parser because it is a security control.
#
# `tr` FIRST, and it is load-bearing rather than tidying: a config written as a one-liner
# (`{ "board": false }`) puts no member at the start of a line, so a line-anchored pattern
# would match nothing there and read the switch as absent — failing OPEN, which is
# precisely the defect this gate exists to close. Breaking every `{` and `,` onto its own
# line puts each JSON member at a line start whichever way the file is formatted.
#
# The value must be a BARE `true`/`false`. That is what keeps the seeded `"$board"` doc
# string — a quoted prose value that describes the setting — from ever being read AS the
# setting, and what keeps `"boardInstances"`, a different key that merely starts the same
# way, out of it.
board="$(tr '{,' '\n\n' < "$cfg" \
  | sed -n 's/^[[:space:]]*"board"[[:space:]]*:[[:space:]]*\(true\|false\).*$/\1/p' \
  | head -n1)"
if [ "$board" = false ]; then exit 0; fi

page="$root/.board-live/board.html"
[ -f "$page" ] || exit 0

echo "🔗 Board: file://$page"
echo "$page"
echo "   rendered at the last tick — the masthead says when; scripts/watch-board.sh keeps a live one"
