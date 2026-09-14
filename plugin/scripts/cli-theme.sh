#!/usr/bin/env bash
#
# cli-theme.sh — THE one place a plugin surface's SGR escapes are spelled. Sourced, never
# run: `ab_theme <0|1> [auto|truecolor|ansi256|basic]` sets T_OFF T_BOLD T_BLUE T_PINK
# T_INK T_MUTED T_DIM T_DIM_I and the mark's T_SHIP_*, every one empty when colour is off.
# The CALLER decides colour at all (`--color`/`--format`/`NO_COLOR`); this decides the tier.
# `auto` degrades truecolor -> ansi256 -> basic; `basic` never probes the terminal.
# Values are COPIED from the loopd tokens (cli-theme.json). `basic` has no tokens to copy,
# so it keeps this repo's own 3/4-bit codes. A caller pairs `. cli-theme.sh 2>/dev/null` with
# `command -v ab_theme >/dev/null || ab_theme() { :; }` and reads `${T_…:-}`, so a missing
# theme degrades to no colour and never blanks a banner. Reasoning: loopd/task-004.

# shellcheck disable=SC2034  # every T_* below is set FOR the caller, by design
ab_theme() {
  local on="${1:-0}" tier="${2:-auto}" esc tc
  T_OFF=""; T_BOLD=""; T_BLUE=""; T_PINK=""; T_INK=""; T_MUTED=""; T_DIM=""; T_DIM_I=""
  T_SHIP_WATER=""; T_SHIP_HULL=""; T_SHIP_BRIDGE=""
  [ "$on" = 1 ] || return 0
  # `$(printf '\033')`, and `${esc}[` braced: an ESC typed into a literal is invisible in a
  # diff, and `"$esc[1m"` is bash's array-subscript spelling (shellcheck SC1087).
  esc="$(printf '\033')"
  if [ "$tier" = auto ]; then
    tc=0
    if command -v tput >/dev/null 2>&1; then tc="$(tput colors 2>/dev/null || echo 0)"; fi
    case "$tc" in ''|*[!0-9]*) tc=0 ;; esac
    case "${COLORTERM:-}" in
      truecolor|24bit) tier=truecolor ;;
      *) if [ "$tc" -ge 256 ]; then tier=ansi256; else tier=basic; fi ;;
    esac
  fi
  T_OFF="${esc}[0m"; T_BOLD="${esc}[1m"
  case "$tier" in
    truecolor)
      T_BLUE="${esc}[38;2;94;162;255m";   T_PINK="${esc}[38;2;255;122;194m"
      T_INK="${esc}[1;38;2;233;237;244m"; T_MUTED="${esc}[38;2;154;164;181m"
      T_DIM="${esc}[2;38;2;108;116;136m"; T_DIM_I="${esc}[2;3;38;2;108;116;136m"
      T_SHIP_WATER="${esc}[38;2;95;168;211m";  T_SHIP_HULL="${esc}[38;2;239;163;165m"
      T_SHIP_BRIDGE="${esc}[38;2;245;215;110m" ;;
    ansi256)
      T_BLUE="${esc}[38;5;75m";    T_PINK="${esc}[38;5;212m"
      T_INK="${esc}[1;38;5;255m";  T_MUTED="${esc}[38;5;248m"
      T_DIM="${esc}[2;38;5;243m";  T_DIM_I="${esc}[2;3;38;5;243m"
      T_SHIP_WATER="${esc}[38;5;74m";   T_SHIP_HULL="${esc}[38;5;217m"
      T_SHIP_BRIDGE="${esc}[38;5;222m" ;;
    *)
      T_BLUE="${esc}[94m"; T_PINK="${esc}[95m"
      T_INK="${esc}[1m";   T_MUTED=""
      T_DIM="${esc}[2m";   T_DIM_I="${esc}[2;3m"
      T_SHIP_WATER="${esc}[94m";  T_SHIP_HULL="${esc}[95m"
      T_SHIP_BRIDGE="${esc}[93m" ;;
  esac
}
