#!/usr/bin/env bash
#
# config-ownership.test.sh — the ONLY `~/.claude` paths this repo may ship are the ones it
# probes for. Everything else in that directory belongs to `cbmono/ai-setup`.
#
# WHY THIS FILE EXISTS. `config/` was a fork of ai-setup's `.claude/` tree. Both
# installers linked into `${CLAUDE_CONFIG_DIR:-~/.claude}`, 24 of ai-setup's 26 installable
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
# Read BEFORE anything here could set it, so the assertion at the bottom compares this
# harness's own effect against the environment it inherited. A contributor who exports
# CLAUDE_CONFIG_DIR must not turn that assertion red — the property is "nothing here
# exported one", not "nobody anywhere has one".
CCD_IN_ENV_AT_START="$(env | grep -c '^CLAUDE_CONFIG_DIR=' || true)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/cfgown.XXXXXX")" || {
  echo "config-ownership.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp} — create that directory first." >&2; exit 2; }
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
#
# settings.json IS NOT FILTERED HERE, and that is where this scan deliberately STOPS
# mirroring config_entries(). It used to be — the exclusion list was copied from the
# installer — and that made criterion 3's check blind to the single highest-value path in the
# directory: re-forking `config/required/commands/grill.md` produces 5 named failures, while
# re-forking `config/required/settings.json` left this file at 33 passed, 0 failed. The two
# lists answer different questions. config_entries() answers *what does `--config` LINK*,
# and it must skip settings.json because that file is ai-setup's and can already hold
# permissions a human tuned by hand. This answers *what `~/.claude` path does this repo
# SHIP*, and a copy of ai-setup's settings.json under `config/` is the fork growing back
# whether or not a link is ever made from it — worse unlinked, because then no config dir
# anywhere reveals it and the next "sync from the fork" picks it up. README.md,
# `*.example.json` and `.DS_Store` stay filtered: none of the three is a `~/.claude` path.
shipped() { # <template root>
  local root="$1"
  [ -d "$root/config" ] || return 0
  ( cd "$root/config" && find . -mindepth 2 -type f -print ) | sed 's#^\./[^/]*/##' \
  | while IFS= read -r rel; do
      [ -n "$rel" ] || continue
      case "${rel##*/}" in README.md|*.example.json|.DS_Store) continue ;; esac
      printf '%s\n' "$rel"
    done | sort -u
}

# The tier directories present on disk, and the ones install.sh is configured to link.
tier_dirs() { # <template root>
  [ -d "$1/config" ] || return 0
  ( cd "$1/config" && find . -mindepth 1 -maxdepth 1 -type d -print ) | sed 's#^\./##' | sort -u
}
config_tiers_of() { # <template root> → install.sh's CONFIG_TIERS, one per line
  sed -n 's/^CONFIG_TIERS="\(.*\)"$/\1/p' "$1/plugin/scripts/init-bundle.sh" | tr ' ' '\n' | grep . | sort -u
}

# The expected set, derived from what the machinery actually probes for.
# `project-manager.md` names plan-architect in prose, not in a `test -f`, so the regex
# cannot see it; it is added by name and that is the whole exception list.
# BOTH trees are scanned: the role agents that write these probes moved to
# `plugin/agents/` at the name swap, and a `symlink/`-only scan yields an empty expected
# set — which reads as "this repo ships two agents nothing probes for" rather than as a
# broken derivation.
probed_agents() {
  { grep -rhoE '~/\.claude/agents/[a-z0-9-]+\.md' "$REPO/symlink" "$REPO/plugin" 2>/dev/null | sed 's#.*/##'
    printf 'plan-architect.md\n'; } | sort -u | sed 's#^#agents/#'
}

shipped "$REPO" > "$TMP/shipped"
probed_agents        > "$TMP/expected"

# =========================================================================== #
echo "-- the expected set is derived from the probes, not hardcoded"
ok "the machinery probes for at least one agent" \
   "$([ "$(grep -c . "$TMP/expected")" -ge 2 ] && echo yes || echo no)" yes
ok "the derivation finds the probe in qa-reviewer" \
   "$(grep -q 'test -f ~/.claude/agents/code-architect.md' "$REPO/plugin/agents/qa-reviewer.md" && echo yes || echo no)" yes

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
mkdir -p "$NEWTIER/config/required/agents" "$NEWTIER/config/personal/commands" "$NEWTIER/plugin/scripts"
cp "$REPO/config/required/agents/"*.md "$NEWTIER/config/required/agents/"
printf 'a copy of ai-setup\n' > "$NEWTIER/config/personal/commands/grill.md"
shipped "$NEWTIER" > "$TMP/shipped-newtier"
ok "a tier under a NEW name is reported too" \
   "$(comm -23 "$TMP/shipped-newtier" "$TMP/expected" | tr '\n' ' ' | sed 's/ *$//')" "commands/grill.md"
# …and the tier-name pin sees it from the other side, whether or not install.sh links it.
# The fixture writes its OWN CONFIG_TIERS line rather than copying the repo's installer, so
# these two assertions stay meaningful no matter what the real one says — a non-vacuity
# check that moves with the thing it is checking is not one.
printf 'CONFIG_TIERS="required"\n' > "$NEWTIER/plugin/scripts/init-bundle.sh"
ok "…and the tier-dir pin reports the new dir" \
   "$(comm -3 <(tier_dirs "$NEWTIER") <(config_tiers_of "$NEWTIER") | tr -d '\t' | tr '\n' ' ' | sed 's/ *$//')" "personal"
# The one loophole worth closing explicitly: an author who adds the tier AND updates
# install.sh makes the dir/CONFIG_TIERS pin agree again. The "exactly one tier" assertion
# is what still fires — which is why it is a separate assertion and not folded into the
# comm above. Reproduced here as the reviewer's exact repro: CONFIG_TIERS="required
# personal" plus a re-forked commands/grill.md under it.
printf 'CONFIG_TIERS="required personal"\n' > "$NEWTIER/plugin/scripts/init-bundle.sh"
ok "…a matching install.sh silences only the dir pin" \
   "$(comm -3 <(tier_dirs "$NEWTIER") <(config_tiers_of "$NEWTIER") | tr -d '\t' | tr '\n' ' ' | sed 's/ *$//')" ""
ok "…and the one-tier pin still names it" \
   "$(config_tiers_of "$NEWTIER" | tr '\n' ' ' | sed 's/ *$//')" "personal required"
ok "…and the legitimate three still are not" \
   "$(comm -13 "$TMP/shipped-fix" "$TMP/expected" | tr '\n' ' ' | sed 's/ *$//')" ""
# The same for the "outside agents/" corollary, so it cannot pass by never matching.
ok "the outside-agents check fires on the fixture" \
   "$([ "$(grep -cv '^agents/' "$TMP/shipped-fix" || true)" -ge 1 ] && echo yes || echo no)" yes
# THE PATH THAT ACTUALLY GOT LOST, as a re-fork. It is the one file whose reappearance the
# installer would NOT reveal — config_entries() skips it, so `--config` links nothing and no
# config dir anywhere shows it — which is exactly why the scan must not skip it too. This
# assertion is the control for the filter above: with settings.json back in the filter, the
# fixture below reports an empty set and the group goes green having seen nothing.
SJFIX="$TMP/refork-sj"
mkdir -p "$SJFIX/config/required/agents"
cp "$REPO/config/required/agents/"*.md "$SJFIX/config/required/agents/"
printf '{"permissions":{"deny":["Read(**/.env)"]}}\n' > "$SJFIX/config/required/settings.json"
shipped "$SJFIX" > "$TMP/shipped-sj"
ok "a re-forked settings.json is reported" \
   "$(comm -23 "$TMP/shipped-sj" "$TMP/expected" | tr '\n' ' ' | sed 's/ *$//')" "settings.json"
ok "…and the legitimate three still are not" \
   "$(comm -13 "$TMP/shipped-sj" "$TMP/expected" | tr '\n' ' ' | sed 's/ *$//')" ""
# It is not filtered for being at the top level either: one under a subdirectory too.
SJFIX2="$TMP/refork-sj2"
mkdir -p "$SJFIX2/config/required/agents"
cp "$REPO/config/required/agents/"*.md "$SJFIX2/config/required/agents/"
printf '{}\n' > "$SJFIX2/config/required/agents/settings.json"
ok "…at any depth"  \
   "$(shipped "$SJFIX2" | grep -cx 'agents/settings.json' || true)" 1

# =========================================================================== #
echo "-- the decision is written down where the next reader looks"
# Criterion: not only in a commit message. A reader who wonders why `/grill` is not here
# must be able to find the answer from the files they are already in.
DOC="$REPO/docs/claude-config-ownership.md"
ok "the ownership doc exists"            "$(yn test -f "$DOC")" yes
ok "…it names the repo that owns ~/.claude" "$(grep -qF 'cbmono/ai-setup' "$DOC" && echo yes || echo no)" yes
ok "…and install.sh points at it"        "$(grep -qF 'docs/claude-config-ownership.md' "$REPO/plugin/scripts/init-bundle.sh" && echo yes || echo no)" yes
ok "…and so does the README"             "$(grep -qF 'claude-config-ownership' "$REPO/README.md" && echo yes || echo no)" yes

# =========================================================================== #
echo "-- cross-repo: the two installable sets overlap only where sanctioned"
# Reachable ai-setup checkout, in order of explicitness. Never cloned, never fetched —
# this harness is offline, and a network call in a test suite is a flake waiting to happen.
AS=""
for cand in "${AI_SETUP_DIR:-}" "$REPO/../ai-setup" "$HOME/workspace/ai-setup"; do
  [ -n "$cand" ] || continue
  if [ -d "$cand/.claude" ] && [ -f "$cand/plugin/scripts/init-bundle.sh" ]; then AS="$(cd "$cand" && pwd)"; break; fi
done
if [ -z "$AS" ]; then
  echo "  SKIP: no ai-setup checkout found (set AI_SETUP_DIR to enable this group)"
  echo "        The assertions above hold this repo's side without it."
else
  echo "        using $AS"
  # ai-setup's installable set, computed from ITS installer's own EXCLUDE list rather than
  # a copy of it here, so the two cannot drift apart.
  #
  # BOTH DERIVATIONS ARE FUNCTIONS OF THEIR INPUTS, which is what lets the non-vacuity checks
  # below re-run them against a MUTATED installer instead of editing a derived file by hand.
  # That distinction is not cosmetic: the previous version proved its membership check could
  # report a missing root by deleting a line from the derived list, which exercises the
  # comparison and never the derivation — and the derivation was the half that was blind.
  EXCL="$(sed -n 's/^EXCLUDE="\(.*\)"$/\1/p' "$AS/install.sh")"
  ok "ai-setup's EXCLUDE list was found"  "$([ -n "$EXCL" ] && echo yes || echo no)" yes
  ( cd "$AS" && git ls-files .claude 2>/dev/null ) | sed 's#^\.claude/##' | sort -u > "$TMP/as-tracked"
  as_generic() { # <tracked list> <EXCLUDE> → what the generic link loop links
    local rel top
    while IFS= read -r rel; do
      [ -n "$rel" ] || continue
      top="${rel%%/*}"
      case " $2 " in *" $top "*) continue ;; esac
      case " $2 " in *" $rel "*) continue ;; esac
      printf '%s\n' "$rel"
    done < "$1" | sort -u
  }
  as_generic "$TMP/as-tracked" "$EXCL" > "$TMP/as-shipped"
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

  # ======================================================================= #
  echo "-- cross-repo: and no root this layer hands over is installed by NOBODY"
  #
  # A DANGLING-LINK AUDIT CANNOT SEE THIS CLASS, WHICH IS WHY IT NEEDS ITS OWN ASSERTION.
  # `~/.claude/settings.json` really was lost, order-dependently: on a machine carrying the
  # old layer's link, running ai-setup's installer (which declined — "already exists") and
  # then this layer's `--config` (which retired its own now-dangling link) left the file
  # ABSENT, exit 0, and **0 dangling**. Every audit used as evidence for criterion 1 counted
  # dangling links, and a path that was never linked is absent, not dangling — so the number
  # that was supposed to prove nothing was lost is structurally incapable of seeing the loss.
  # Twice now the recorded rationale has been wrong about this in opposite directions ("23
  # paths installed by nobody", then "the only risk is content regression"). Prose cannot be
  # relied on to stay right about it; set membership can.
  #
  # THE INVARIANT: every root in `CONFIG_MANAGED_TOPS` — the roots this layer's sweep
  # retires links under — is either still shipped HERE, or installed by ai-setup.
  MTOPS="$(sed -n 's/^CONFIG_MANAGED_TOPS="\(.*\)"$/\1/p' "$REPO/plugin/scripts/init-bundle.sh")"
  ok "this layer's managed-root list was found" "$([ -n "$MTOPS" ] && echo yes || echo no)" yes

  # ai-setup's EXCLUDE means "the generic link loop skips this". It does NOT mean "this is
  # not installed": ai-setup installs `settings.json` from a dedicated branch at the end of
  # its installer, precisely because it is the one file that may already hold permissions a
  # human tuned by hand. So a set derived from EXCLUDE alone MISSES it — and settings.json is
  # exactly the path that got lost. The add-back is detected from that installer (an excluded
  # path it names as a destination of its own), never hardcoded here, so it follows the code.
  as_special() { # <tracked list> <installer> <EXCLUDE> → excluded paths it installs anyway
    local rel
    while IFS= read -r rel; do
      [ -n "$rel" ] || continue
      case " $3 " in *" $rel "*) ;; *) continue ;; esac
      grep -q "DEST/$rel" "$2" && printf '%s\n' "$rel"
    done < "$1" | sort -u
  }
  as_special "$TMP/as-tracked" "$AS/install.sh" "$EXCL" > "$TMP/as-special"
  # Both halves of the reasoning error, pinned: the EXCLUDE-only set does not have it, and
  # the corrected set does. Delete the add-back and the second goes red; delete the special
  # branch from ai-setup's installer and the first stops being a near miss.
  ok "settings.json is absent from the EXCLUDE-only set" \
     "$(grep -cx 'settings.json' "$TMP/as-shipped" || true)" 0
  ok "…and present once the installer's own branch is read" \
     "$(grep -cx 'settings.json' "$TMP/as-special" || true)" 1
  cat "$TMP/as-shipped" "$TMP/as-special" | cut -d/ -f1 | sort -u > "$TMP/as-tops"
  cut -d/ -f1 "$TMP/shipped" | sort -u > "$TMP/ab-tops"

  # A root neither layer installs is a loss ONLY if this layer ever shipped anything under
  # it. `rules` is in CONFIG_MANAGED_TOPS and in neither installed set, and it is not a
  # loss: git says nothing was ever shipped under `config/*/rules/`, so the sweep looks
  # there and finds nothing of ours. Asking git rather than listing an exception here is
  # what keeps this from going stale — add a root that WAS shipped and it is not exempt.
  # `grep -c .`, NOT `grep -q .`: this file runs under `set -o pipefail`, and `grep -q`
  # exits the moment it matches, closing the pipe and killing `git log` with SIGPIPE — so
  # the pipeline's status is non-zero on SUCCESS and the predicate answered "no" for every
  # root, including the ones that were shipped. It made the two non-vacuity assertions below
  # go green by never firing, which is the same vacuity this whole file exists to prevent.
  # `grep -c` drains its input, so there is no SIGPIPE to invert the answer.
  ever_shipped() { # <top> → yes if config/<tier>/<top>/ ever existed on any ref
    local n
    n="$( ( cd "$REPO" && git log --all --pretty=format: --name-only \
              -- "config/*/$1" "config/*/$1/*" 2>/dev/null ) | grep -c . || true )"
    [ "$n" -gt 0 ] && echo yes || echo no
  }
  orphan_roots() { # <as-tops file> → the roots installed by nobody, one per line
    local top
    for top in $MTOPS; do
      grep -qx "$top" "$TMP/ab-tops" && continue
      grep -qx "$top" "$1" && continue
      [ "$(ever_shipped "$top")" = yes ] && printf '%s\n' "$top"
    done
  }
  ok "no root this layer hands over is installed by nobody" \
     "$(orphan_roots "$TMP/as-tops" | tr '\n' ' ' | sed 's/ *$//')" ""
  # …and `rules` is the reason that is a real 0 and not an empty loop.
  ok "…and rules/ was skipped because it was never shipped here" "$(ever_shipped rules)" no
  ok "…while commands/ WAS shipped here"  "$(ever_shipped commands)" yes
  # NON-VACUITY, AND IT MUST EXERCISE THE DERIVATION, NOT A HAND-BUILT SET. This used to
  # delete a line from the derived file and check that the comparison noticed — which proves
  # `orphan_roots` can subtract, and nothing about whether the set feeding it can ever lose a
  # path. It cannot, for the case that mattered: `settings.json` is tracked, excluded, and
  # named as a `DEST/` destination at ai-setup `main` too, so the derived set was
  # BYTE-IDENTICAL before and after the fix that made the file survive. So the mutation goes
  # into the INPUT — a copy of ai-setup's installer with its settings.json destinations
  # removed — and the derivation is re-run over it.
  sed '/DEST\/settings\.json/d' "$AS/install.sh" > "$TMP/as-installer-nosj"
  ok "the installer mutation applied" \
     "$([ "$(grep -c 'DEST/settings.json' "$AS/install.sh" || true)" -gt 0 ] \
        && [ "$(grep -c 'DEST/settings.json' "$TMP/as-installer-nosj" || true)" -eq 0 ] \
        && echo yes || echo no)" yes
  as_special "$TMP/as-tracked" "$TMP/as-installer-nosj" "$EXCL" > "$TMP/as-special-nosj"
  ok "…the derivation then drops settings.json" \
     "$(grep -cx 'settings.json' "$TMP/as-special-nosj" || true)" 0
  cat "$TMP/as-shipped" "$TMP/as-special-nosj" | cut -d/ -f1 | sort -u > "$TMP/as-tops-nosj"
  ok "…and the membership check names it" \
     "$(orphan_roots "$TMP/as-tops-nosj" | tr '\n' ' ' | sed 's/ *$//')" "settings.json"
  # The same for a whole directory, so none of this is settings.json-specific. `commands` is
  # not excluded, so the mutation belongs in the OTHER derivation's input: EXCLUDE it and the
  # generic link loop stops linking all eleven paths under it.
  as_generic "$TMP/as-tracked" "$EXCL commands" > "$TMP/as-shipped-nocmd"
  ok "excluding commands drops it from the generic set" \
     "$(cut -d/ -f1 "$TMP/as-shipped-nocmd" | grep -cx commands || true)" 0
  cat "$TMP/as-shipped-nocmd" "$TMP/as-special" | cut -d/ -f1 | sort -u > "$TMP/as-tops-nocmd"
  ok "…and names a whole directory the same way" \
     "$(orphan_roots "$TMP/as-tops-nocmd" | tr '\n' ' ' | sed 's/ *$//')" "commands"

  # ======================================================================= #
  echo "-- cross-repo: and ai-setup really does install them, from the state a machine is in"
  #
  # SET MEMBERSHIP CANNOT SEE A CONDITIONAL DECLINE, and that is what the defect was. Every
  # assertion above compares derived lists of paths, and the loss of `~/.claude/settings.json`
  # was not a path leaving a list: the file was tracked, named by the installer, and in the
  # manifest throughout. What went wrong was a BRANCH — "a settings.json already exists, left
  # alone" — taken because this layer's own link was sitting there. So the set was identical
  # in the broken state and the fixed one, and no stricter grep repairs that: `ln -s.*
  # DEST/settings.json` matches ai-setup `main` on two lines. Grepping an installer for a
  # destination proves it mentions the path, never that it installs it in every starting
  # state. Only running it does.
  #
  # THE STATE IS THE POINT. From an empty config dir every order works — that is the one
  # starting state in which "installed by nobody" cannot appear, and it is the state the
  # original order-independence measurement used. This starts from the state every existing
  # machine is in: this layer's link already there, resolving into a checkout of ours.
  ASFIX="$TMP/as-fixture"; mkdir -p "$ASFIX"
  ( cd "$AS" && git ls-files .claude install.sh 2>/dev/null ) | while IFS= read -r f; do
      [ -n "$f" ] || continue
      mkdir -p "$ASFIX/$(dirname "$f")"
      cp "$AS/$f" "$ASFIX/$f"
    done
  # A git copy, never the checkout: ai-setup's installer refuses to run from a worktree, and
  # nothing here may write into a tree another agent or harness is reading.
  ( cd "$ASFIX" && git init -q . && git add -A && git -c user.name=t -c user.email=t@t commit -qm fixture ) >/dev/null 2>&1
  ASFIXR="$(cd "$ASFIX" && pwd)"
  ok "the ai-setup fixture is a git checkout" "$(yn test -d "$ASFIX/.git")" yes
  ASD="$TMP/as-dest"; mkdir -p "$ASD" "$TMP/old-bridge/config/opinionated"
  printf '{"permissions":{"deny":["Read(**/.env)"]}}\n' > "$TMP/old-bridge/config/opinionated/settings.json"
  ln -s "$TMP/old-bridge/config/opinionated/settings.json" "$ASD/settings.json"
  CLAUDE_CONFIG_DIR="$ASD" bash "$ASFIX/install.sh" >"$TMP/as-out" 2>&1
  ok "ai-setup's installer exits 0 from that state" "$?" 0
  ok "…and did not fall back to its hardcoded list" \
     "$(grep -cF 'FALLBACK_DEFAULTS' "$TMP/as-out" || true)" 0
  # PROVIDED BY ai-setup means the entry resolves INTO the ai-setup tree. Not merely
  # "resolves": at `main` the settings.json link still resolves — into the old ai-bridge
  # checkout it was already pointing at — which is precisely the state that becomes an absent
  # file the moment `--config` retires that link.
  provided_by_as() { # <top>
    case "$(readlink "$ASD/$1" 2>/dev/null)" in "$ASFIXR/.claude"/*) echo yes ;; *) echo no ;; esac
  }
  notprov=""
  for top in $MTOPS; do
    grep -qx "$top" "$TMP/ab-tops" && continue          # still shipped here
    [ "$(ever_shipped "$top")" = yes ] || continue       # never ours, so never a loss
    [ "$(provided_by_as "$top")" = yes ] || notprov="$notprov $top"
  done
  ok "every root handed over is installed by ai-setup" "${notprov# }" ""
  ok "…settings.json among them, pointing at ai-setup" \
     "$(readlink "$ASD/settings.json")" "$ASFIXR/.claude/settings.json"
  ok "…and the old link's path is recoverable"  \
     "$(find "$ASD" -maxdepth 1 -name 'settings.json.bak.*' | wc -l | tr -d ' ')" 1
  ok "…without writing into the other checkout" \
     "$(cat "$TMP/old-bridge/config/opinionated/settings.json")" \
     '{"permissions":{"deny":["Read(**/.env)"]}}'
  # NON-VACUITY, on the installer that is actually run: narrow its adopt branch back to
  # dangling links only — the pre-fix condition — and the probe must go red naming the file.
  ASFIX2="$TMP/as-fixture-nofix"; cp -R "$ASFIX" "$ASFIX2"
  sed -e 's#^elif \[ -L "\$DEST/settings\.json" \]; then$#elif [ -L "$DEST/settings.json" ] \&\& [ ! -e "$DEST/settings.json" ]; then#' \
      "$ASFIX/install.sh" > "$ASFIX2/install.sh"
  ok "the adopt-branch mutation applied" \
     "$(grep -c '! -e "\$DEST/settings.json" \]; then' "$ASFIX2/install.sh" | tr -d ' ')" 1
  ASD2="$TMP/as-dest-nofix"; mkdir -p "$ASD2"
  ln -s "$TMP/old-bridge/config/opinionated/settings.json" "$ASD2/settings.json"
  CLAUDE_CONFIG_DIR="$ASD2" bash "$ASFIX2/install.sh" >"$TMP/as-out2" 2>&1
  ok "without the adopt branch it declines"    \
     "$(readlink "$ASD2/settings.json")" "$TMP/old-bridge/config/opinionated/settings.json"
  ok "…which is a path THIS layer is retiring" \
     "$(printf '%s' "$(readlink "$ASD2/settings.json")" | grep -c '/config/opinionated/' || true)" 1

  # ======================================================================= #
  echo "-- cross-repo: the number the ownership doc quotes is the number derived here"
  # B4: the doc's headline figure was 25/23, derived from EXCLUDE alone and therefore off by
  # exactly `settings.json` — inside the document whose own point 6 warns against that
  # derivation, and repeated in four other files. A number in prose that nothing recomputes
  # drifts from the code the moment the code moves. When this fails because ai-setup
  # legitimately gained or lost an installable entry, update the doc's table (and its date):
  # that is the assertion doing its job, not noise.
  DERIVED="$(cat "$TMP/as-shipped" "$TMP/as-special" | sort -u | grep -c . || true)"
  DOCN="$(sed -n 's/^| ai-setup.s installable entries | \([0-9]*\) |$/\1/p' "$DOC")"
  ok "the doc quotes an installable-entry count" "$([ -n "$DOCN" ] && echo yes || echo no)" yes
  ok "…and it is the count derived from the installer" "$DOCN" "$DERIVED"
fi

# The harness runs another repo's installer, so the rule that keeps that safe is asserted
# rather than trusted: every invocation is prefixed with a throwaway CLAUDE_CONFIG_DIR, and
# nothing here exports one. Both are falsifiable — drop a prefix, or add an `export`, and
# this goes red — which the previous form of the same idea in ai-setup's harness was not.
# The `[$]` in both patterns is what stops each grep from matching its own line — a
# self-matching pattern would make this pair unequal for a reason that has nothing to do
# with the property.
# …and this one keeps the pair above from passing vacuously: if `$0` were unreadable both
# greps would print nothing, two empty strings would compare equal, and the check would be a
# hidden pass — the shape this file exists to prevent.
ok "…and there were invocations to check" \
   "$([ "$(grep -c 'bash "[$]ASFIX' "$0" | tr -d ' ')" -ge 2 ] && echo yes || echo no)" yes
ok "every installer invocation is prefixed with a throwaway config dir" \
   "$(grep -c 'bash "[$]ASFIX' "$0" | tr -d ' ')" \
   "$(grep -c 'CLAUDE_CONFIG_DIR="[$]ASD[0-9]*" bash "[$]ASFIX' "$0" | tr -d ' ')"
ok "…and this harness exported no CLAUDE_CONFIG_DIR" \
   "$(env | grep -c '^CLAUDE_CONFIG_DIR=' || true)" "$CCD_IN_ENV_AT_START"

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
