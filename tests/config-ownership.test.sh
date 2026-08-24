#!/usr/bin/env bash
#
# config-ownership.test.sh — the ONLY `~/.claude` paths this repo may ship are the ones it
# probes for. Everything else in that directory belongs to `cbmono/ai-setup`.
#
# WHY THIS FILE EXISTS. `config/` was a fork of ai-setup's `.claude/` tree. Both
# installers linked into `${CLAUDE_CONFIG_DIR:-~/.claude}`, 23 of ai-setup's 25 installable
# entries were shipped by both, 14 had diverged in BOTH directions, and which copy a
# machine ended up with was decided by whichever installer ran last. It was not found by
# review — it was found because two of the fixes that existed only here closed
# secret-exposure paths that the PUBLIC repo was still shipping. A fork nobody notices is
# how that happens, and a fork is exactly what grows back one convenient file at a time:
# the next agent that needs `/grill` on a fresh laptop will reach for a copy.
#
# So the invariant is narrow and mechanical: **this repo ships exactly the files it probes
# for by absolute path, and nothing else.** Not "roughly the required tier" — an
# enumerated set, checked in both directions:
#
#   · nothing ships that is not probed for → a re-fork fails here, naming the file;
#   · nothing is probed for that does not ship → the silent-degradation failure this whole
#     layer exists to close (`config-layer.test.sh` covers this direction too, from the
#     probe side; here it keeps the manifest from being a hardcoded lie).
#
# THE MANIFEST IS DERIVED, NOT DECLARED. A hardcoded list of three filenames would pass
# forever while meaning nothing. The expected set is computed from the `test -f
# ~/.claude/agents/<x>.md` probes in `symlink/`, plus one explicitly-reasoned addition
# (`plan-architect`, which `project-manager.md` names in prose rather than in a probe). So
# deleting a probe or adding one MOVES the expected set, and the pin follows the code.
#
# NON-VACUITY IS MEASURED, NOT CLAIMED. The scan runs against a synthetic fixture that
# contains a re-forked file, and the test asserts it REPORTS that file. Without this,
# "no unowned path found" could mean "the scan never fires" — which is the state a
# refactor leaves it in, silently.
#
# THE CROSS-REPO HALF IS OPTIONAL AND SAYS SO. When an ai-setup checkout is reachable
# (`$AI_SETUP_DIR`, or a sibling clone) the intersection of the two installable sets is
# asserted to be exactly the manifest — the sanctioned overlap, no more, computed from
# ai-setup's own `EXCLUDE` list rather than a second copy of it. Absent a checkout the
# group prints a SKIP naming the variable that enables it. That is deliberately NOT a
# hidden pass: the assertions above hold this repo's side on their own, and the matching
# assertion for ai-setup's side lives in ai-setup
# (`tests/claude-config-ownership.test.sh`), where its own suite runs it every time.
# Nothing here reaches the network — an offline harness is the only kind that does not flake.
#
# ok() compares actual to expected, in that argument order — this directory's convention.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/cfgown.XXXXXX")"
if [ -z "$TMP" ] || [ ! -d "$TMP" ]; then
  echo "error: mktemp produced no directory (is TMPDIR set to a path that does not exist?)" >&2
  exit 1
fi
trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
ok() { if [ "$2" = "$3" ]; then printf '  PASS  %-58s (%s)\n' "$1" "$2"; pass=$((pass+1))
       else printf '  FAIL  %-58s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi; }
yn() { if "$@" >/dev/null 2>&1; then echo yes; else echo no; fi; }

# ------------------------------------------------------------------ the primitives
# Every path a `--config` run would link, as it would appear under the config dir. This
# mirrors install.sh's config_entries(): both tiers if present, minus the three kinds of
# file that are never linked. Parameterised by root so the same scan runs over the real
# checkout and over a synthetic fixture.
# EVERY tier directory, whatever it happens to be CALLED. This used to read
# `for tier in required opinionated`, and that hardcoding is what made the whole check
# weaker than the two-tier duplicate-path guard install.sh dropped when the second tier
# went: with `CONFIG_TIERS="required personal"` in install.sh and a re-forked
# `config/personal/commands/grill.md` on disk, `--config` linked the fork and this harness
# reported 18 passed, 0 failed. The invariant is "this repo ships exactly what it probes
# for" — a tier under a new name is precisely how the fork grows back, so the scan must not
# be able to name the tiers it looks in. The tier NAMES are pinned separately below,
# against install.sh's own CONFIG_TIERS, which closes the other direction: a tier directory
# install.sh does not link, and a tier install.sh links that has no directory.
#
# -mindepth 2 mirrors config_entries(): it scans `config/<tier>/...`, so a loose file at
# `config/x.md` is shipped by nobody and belongs to neither set.
shipped() { # <template root>
  local root="$1"
  [ -d "$root/config" ] || return 0
  ( cd "$root/config" && find . -mindepth 2 -type f -print ) | sed 's#^\./[^/]*/##' \
  | while IFS= read -r rel; do
      [ -n "$rel" ] || continue
      case "${rel##*/}" in README.md|settings.json|*.example.json|.DS_Store) continue ;; esac
      printf '%s\n' "$rel"
    done | sort -u
}

# The tier directories present on disk, and the ones install.sh is configured to link.
tier_dirs() { # <template root>
  [ -d "$1/config" ] || return 0
  ( cd "$1/config" && find . -mindepth 1 -maxdepth 1 -type d -print ) | sed 's#^\./##' | sort -u
}
config_tiers_of() { # <template root> → install.sh's CONFIG_TIERS, one per line
  sed -n 's/^CONFIG_TIERS="\(.*\)"$/\1/p' "$1/install.sh" | tr ' ' '\n' | grep . | sort -u
}

# The expected set, derived from what the machinery actually probes for.
# `project-manager.md` names plan-architect in prose, not in a `test -f`, so the regex
# cannot see it; it is added by name and that is the whole exception list.
probed_agents() {
  { grep -rhoE '~/\.claude/agents/[a-z0-9-]+\.md' "$REPO/symlink" 2>/dev/null | sed 's#.*/##'
    printf 'plan-architect.md\n'; } | sort -u | sed 's#^#agents/#'
}

shipped "$REPO" > "$TMP/shipped"
probed_agents        > "$TMP/expected"

# =========================================================================== #
echo "-- the expected set is derived from the probes, not hardcoded"
ok "the machinery probes for at least one agent" \
   "$([ "$(grep -c . "$TMP/expected")" -ge 2 ] && echo yes || echo no)" yes
ok "the derivation finds the probe in qa-reviewer" \
   "$(grep -q 'test -f ~/.claude/agents/code-architect.md' "$REPO/symlink/.claude/agents/qa-reviewer.md" && echo yes || echo no)" yes

# =========================================================================== #
echo "-- this repo ships exactly what it probes for"
# The direction that stops the fork growing back. When this fails it names the file, and
# the answer is almost always "that belongs in cbmono/ai-setup" — see
# docs/claude-config-ownership.md before adding anything here.
ok "no ~/.claude path is shipped that nothing probes for" \
   "$(comm -23 "$TMP/shipped" "$TMP/expected" | tr '\n' ' ' | sed 's/ *$//')" ""
ok "…and nothing probed for is missing"  \
   "$(comm -13 "$TMP/shipped" "$TMP/expected" | tr '\n' ' ' | sed 's/ *$//')" ""
ok "the shipped set is three files"      "$(grep -c . "$TMP/shipped")" 3
# Two structural corollaries, asserted directly because each has its own way of coming
# back: a whole second tier, and a non-agents subtree inside the one that stays.
ok "config/opinionated/ is gone"         "$(yn test -d "$REPO/config/opinionated")" no
# THE TIER NAMES ARE PINNED, in both directions, because the scan above deliberately cannot
# see them. One tier is the decision (docs/claude-config-ownership.md); a second one under
# ANY name is the fork coming back, and a mismatch between the directories on disk and the
# list install.sh reads is a path shipped by nobody or a path shipped invisibly.
tier_dirs "$REPO"        > "$TMP/tier-dirs"
config_tiers_of "$REPO"  > "$TMP/tier-cfg"
ok "install.sh's CONFIG_TIERS was found" "$([ -s "$TMP/tier-cfg" ] && echo yes || echo no)" yes
ok "…and it names exactly one tier"     "$(tr '\n' ' ' < "$TMP/tier-cfg" | sed 's/ *$//')" "required"
ok "the tier dirs on disk match it"     "$(comm -3 "$TMP/tier-dirs" "$TMP/tier-cfg" | tr -d '\t' | tr '\n' ' ' | sed 's/ *$//')" ""
ok "config/ ships nothing outside agents/" \
   "$(grep -cv '^agents/' "$TMP/shipped" || true)" 0

# =========================================================================== #
echo "-- the scan reports a re-fork (non-vacuity)"
# A synthetic template with one file put back where it used to live. If the scan cannot
# see this, every PASS above is meaningless.
FIX="$TMP/refork"
mkdir -p "$FIX/config/required/agents" "$FIX/config/opinionated/commands"
cp "$REPO/config/required/agents/"*.md "$FIX/config/required/agents/"
printf 'a copy of ai-setup\n' > "$FIX/config/opinionated/commands/grill.md"
shipped "$FIX" > "$TMP/shipped-fix"
ok "the fixture's extra file is reported" \
   "$(comm -23 "$TMP/shipped-fix" "$TMP/expected" | tr '\n' ' ' | sed 's/ *$//')" "commands/grill.md"
# THE TIER UNDER A NEW NAME — the case the old hardcoded `required opinionated` loop could
# not see at all, and the reason this group is not decorative. `personal` is not a name
# either repo has ever used, which is the point: the scan must be blind to tier names.
NEWTIER="$TMP/newtier"
mkdir -p "$NEWTIER/config/required/agents" "$NEWTIER/config/personal/commands"
cp "$REPO/config/required/agents/"*.md "$NEWTIER/config/required/agents/"
printf 'a copy of ai-setup\n' > "$NEWTIER/config/personal/commands/grill.md"
shipped "$NEWTIER" > "$TMP/shipped-newtier"
ok "a tier under a NEW name is reported too" \
   "$(comm -23 "$TMP/shipped-newtier" "$TMP/expected" | tr '\n' ' ' | sed 's/ *$//')" "commands/grill.md"
# …and the tier-name pin sees it from the other side, whether or not install.sh links it.
# The fixture writes its OWN CONFIG_TIERS line rather than copying the repo's installer, so
# these two assertions stay meaningful no matter what the real one says — a non-vacuity
# check that moves with the thing it is checking is not one.
printf 'CONFIG_TIERS="required"\n' > "$NEWTIER/install.sh"
ok "…and the tier-dir pin reports the new dir" \
   "$(comm -3 <(tier_dirs "$NEWTIER") <(config_tiers_of "$NEWTIER") | tr -d '\t' | tr '\n' ' ' | sed 's/ *$//')" "personal"
# The one loophole worth closing explicitly: an author who adds the tier AND updates
# install.sh makes the dir/CONFIG_TIERS pin agree again. The "exactly one tier" assertion
# is what still fires — which is why it is a separate assertion and not folded into the
# comm above. Reproduced here as the reviewer's exact repro: CONFIG_TIERS="required
# personal" plus a re-forked commands/grill.md under it.
printf 'CONFIG_TIERS="required personal"\n' > "$NEWTIER/install.sh"
ok "…a matching install.sh silences only the dir pin" \
   "$(comm -3 <(tier_dirs "$NEWTIER") <(config_tiers_of "$NEWTIER") | tr -d '\t' | tr '\n' ' ' | sed 's/ *$//')" ""
ok "…and the one-tier pin still names it" \
   "$(config_tiers_of "$NEWTIER" | tr '\n' ' ' | sed 's/ *$//')" "personal required"
ok "…and the legitimate three still are not" \
   "$(comm -13 "$TMP/shipped-fix" "$TMP/expected" | tr '\n' ' ' | sed 's/ *$//')" ""
# The same for the "outside agents/" corollary, so it cannot pass by never matching.
ok "the outside-agents check fires on the fixture" \
   "$([ "$(grep -cv '^agents/' "$TMP/shipped-fix" || true)" -ge 1 ] && echo yes || echo no)" yes

# =========================================================================== #
echo "-- the decision is written down where the next reader looks"
# Criterion: not only in a commit message. A reader who wonders why `/grill` is not here
# must be able to find the answer from the files they are already in.
DOC="$REPO/docs/claude-config-ownership.md"
ok "the ownership doc exists"            "$(yn test -f "$DOC")" yes
ok "…it names the repo that owns ~/.claude" "$(grep -qF 'cbmono/ai-setup' "$DOC" && echo yes || echo no)" yes
ok "…and install.sh points at it"        "$(grep -qF 'docs/claude-config-ownership.md' "$REPO/install.sh" && echo yes || echo no)" yes
ok "…and so does the README"             "$(grep -qF 'claude-config-ownership' "$REPO/README.md" && echo yes || echo no)" yes

# =========================================================================== #
echo "-- cross-repo: the two installable sets overlap only where sanctioned"
# Reachable ai-setup checkout, in order of explicitness. Never cloned, never fetched —
# this harness is offline, and a network call in a test suite is a flake waiting to happen.
AS=""
for cand in "${AI_SETUP_DIR:-}" "$REPO/../ai-setup" "$HOME/workspace/ai-setup"; do
  [ -n "$cand" ] || continue
  if [ -d "$cand/.claude" ] && [ -f "$cand/install.sh" ]; then AS="$(cd "$cand" && pwd)"; break; fi
done
if [ -z "$AS" ]; then
  echo "  SKIP: no ai-setup checkout found (set AI_SETUP_DIR to enable this group)"
  echo "        The assertions above hold this repo's side without it."
else
  echo "        using $AS"
  # ai-setup's installable set, computed from ITS installer's own EXCLUDE list rather than
  # a copy of it here, so the two cannot drift apart.
  EXCL="$(sed -n 's/^EXCLUDE="\(.*\)"$/\1/p' "$AS/install.sh")"
  ok "ai-setup's EXCLUDE list was found"  "$([ -n "$EXCL" ] && echo yes || echo no)" yes
  ( cd "$AS" && git ls-files .claude 2>/dev/null ) | sed 's#^\.claude/##' | while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    top="${rel%%/*}"
    case " $EXCL " in *" $top "*) continue ;; esac
    case " $EXCL " in *" $rel "*) continue ;; esac
    printf '%s\n' "$rel"
  done | sort -u > "$TMP/as-shipped"
  ok "…and it has an installable set to compare" \
     "$([ "$(grep -c . "$TMP/as-shipped")" -ge 20 ] && echo yes || echo no)" yes
  # THE criterion-3 assertion: the intersection is exactly the three probed agents. One
  # more shared path and this fails, in either repo's direction.
  comm -12 "$TMP/shipped" "$TMP/as-shipped" > "$TMP/overlap"
  ok "the overlap is exactly the probed agents" \
     "$(comm -3 "$TMP/overlap" "$TMP/expected" | tr -d '\t' | tr '\n' ' ' | sed 's/ *$//')" ""
  # Non-vacuity for this half too: `comm -12` must be capable of reporting a difference,
  # so an extra path in one set is checked to change the answer.
  printf 'commands/grill.md\n' >> "$TMP/shipped-fix"
  sort -u -o "$TMP/shipped-fix" "$TMP/shipped-fix"
  ok "…and a re-forked path would widen it" \
     "$(comm -12 "$TMP/shipped-fix" "$TMP/as-shipped" | grep -c 'commands/grill.md' || true)" 1
fi

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
