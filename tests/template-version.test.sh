#!/usr/bin/env bash
#
# template-version.test.sh — the version is ONE string, the docs that show it agree with
# it, and the drift check speaks only when it is actually behind.
#
# WHY THE FAILURE PATHS ARE THE POINT OF THIS FILE. "Prints a warning when a newer version
# exists" is the easy half and the half that cannot go quietly wrong: if it stops firing,
# someone eventually notices they are stale. The half that CAN go quietly wrong is the
# other one — a check that says "you are behind" when the laptop is on a train, when the
# token expired, when the remote-tracking ref was never fetched, or when it simply cannot
# parse what it read. One false alarm of that kind and the human starts ignoring the line,
# at which point the true one costs a week (which is what this whole mechanism exists to
# prevent: two hooks merged and sat inert in all three instances for exactly that long).
# So every silence below is asserted on BYTE-EMPTY stdout, not on "no warning word".
#
# AND WHY THE COMPARISON IS DRIVEN AGAINST REAL GIT REPOSITORIES rather than stubbed. The
# one arithmetic mistake available here — comparing `0.10.0` to `0.9.1` as strings — is
# invisible in every assertion that does not use two-digit fields, and a fixture that fakes
# `git show` would pass with the real remote lookup broken. Each case below builds a bare
# repo, clones it, and asks the shipped script the same question the session banner asks.
#
# THE FOUR PROPERTIES A REVIEWER SHOULD BE ABLE TO REFUSE THE CHANGE ON:
#   1. Exactly ONE VERSION file exists, and every doc that displays the number agrees with
#      it. Two copies is how a version starts lying, and a lying version is worse than none.
#   2. BEHIND speaks; equal and ahead are silent. Not "quieter" — byte-empty.
#   3. A failure is never "behind". Offline, unauthenticated, no checkout, no ref, no file,
#      unparseable: byte-empty, exit 0.
#   4. `core` is a closed list of paths, and it is the same list the two path-scoped rule
#      files govern — so the rule loads exactly when an agent opens a file it covers.
#
# ok() follows this directory's convention: it compares actual to expected.
set -uo pipefail

TPL="$(cd "$(dirname "$0")/.." && pwd)"
CHECK="$TPL/plugin/scripts/check-template-version.sh"
BANNER="$TPL/plugin/hooks/session-banner.sh"
VERFILE="$TPL/VERSION"
[ -f "$CHECK" ] || { echo "template-version.test: missing $CHECK" >&2; exit 2; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/template-version.XXXXXX")" || {
  echo "template-version.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp} — create that directory first." >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
ok() { # <name> <actual> <expected>
  if [ "$2" = "$3" ]; then printf '  PASS  %-62s (%s)\n' "$1" "$2"; pass=$((pass+1))
  else printf '  FAIL  %-62s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}
yn() { if "$@" >/dev/null 2>&1; then echo yes; else echo no; fi; }

# Identity is forced rather than inherited: a machine with no `user.email` configured would
# otherwise fail every fixture commit for a reason that has nothing to do with this change.
GIT() { git -c user.email=test@example.com -c user.name=Test -c commit.gpgsign=false "$@"; }

# =======================================================================================
echo "== 1. ONE version, one line, and nothing else claims to hold it =="
# =======================================================================================
# The count is over TRACKED files, and by basename anywhere in the tree: the failure this
# guards is a second `VERSION` arriving beside the first (a banner's copy, a sub-package's
# copy) and quietly disagreeing with it.
n_version="$(cd "$TPL" && git ls-files | grep -cE '(^|/)VERSION$' || true)"
ok "exactly one tracked VERSION file in the tree" "$n_version" 1
ok "…and it is at the template root"              "$(yn test -f "$VERFILE")" yes

ver="$(head -n 1 "$VERFILE" 2>/dev/null)"
ok "it is version-shaped (MAJOR.MINOR.PATCH)" \
  "$(printf '%s' "$ver" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$' && echo yes || echo no)" yes
ok "…and it is exactly one line"      "$(wc -l < "$VERFILE" | tr -d ' ')" 1
# A file with no trailing newline reads as one line to `head` and as zero to `wc -l`; both
# spellings are pinned so the value stays trivially `cat`-able and `read`-able.
ok "…terminated by a newline"         "$(tail -c 1 "$VERFILE" | od -An -c | tr -d ' \n')" '\n'

# NO RELEASE PROCESS CAME WITH IT — asserted, because this is the direction the change is
# most likely to grow in later, and the scope decision was explicit: one consumer group and
# a symlinked template do not need a pipeline.
ok "no package.json at the root"  "$(yn test -e "$TPL/package.json")" no
ok "no CHANGELOG"                 "$(yn test -e "$TPL/CHANGELOG.md")" no
ok "no publish/release step in CI" \
  "$(grep -rlEi 'npm publish|gh release|actions/create-release' "$TPL/.github" >/dev/null 2>&1 && echo yes || echo no)" no

# =======================================================================================
echo "== 2. one source, MIRRORED not duplicated: a doc that shows the number agrees =="
# =======================================================================================
# THE SCANNED FORM IS NAMED, NOT INFERRED. A blanket hunt for `\d+\.\d+\.\d+` in the docs
# would also catch the HISTORY — `docs/conventions.md` records that there was no version
# before 0.9.1, and that sentence must NOT move when the number does. So the scan is over
# the one shape that is a DISPLAY of the current version: the banner header, `AI-Bridge
# X.Y.Z`. A new display form means adding its shape here, and the non-vacuity assertion
# below is what makes forgetting that visible rather than silent.
# `/dev/null` as a fixed argument to grep, not decoration: BSD xargs runs the utility even
# on empty input, and a `grep` with no file operands reads STDIN — so an empty file list
# would hang this harness rather than fail it.
displays="$(cd "$TPL" && git ls-files '*.md' | grep -v '^tests/' \
            | xargs grep -hoE 'AI-Bridge v?[0-9]+\.[0-9]+\.[0-9]+' /dev/null 2>/dev/null \
            | sed 's/^AI-Bridge v\{0,1\}//' | sort -u)"
n_displays="$(printf '%s' "$displays" | grep -c . || true)"
ok "at least one doc displays the version (the scan is not vacuous)" \
  "$([ "$n_displays" -ge 1 ] && echo yes || echo no)" yes
mismatched="$(printf '%s\n' "$displays" | grep -v "^${ver}$" | grep -c . || true)"
[ "$mismatched" -eq 0 ] || printf '        DISPLAYED BUT NOT IN VERSION: %s\n' "$(printf '%s' "$displays" | tr '\n' ' ')" >&2
ok "every displayed version equals VERSION" "$mismatched" 0
# The extractor must be able to fail: a planted disagreement has to come out non-zero, or
# the assertion above would pass on a scan that matches nothing.
planted="$(printf 'AI-Bridge 0.0.1 · x\n' | grep -oE 'AI-Bridge v?[0-9]+\.[0-9]+\.[0-9]+' | sed 's/^AI-Bridge v\{0,1\}//' | grep -vc "^${ver}$")"
ok "…and that comparison catches a planted mismatch" "$planted" 1

# A DISPLAY IS A SAMPLE OF REAL OUTPUT, so it has to stay one. The banner underlines its
# header with a rule exactly as wide as the header, and the first bump caught the sample
# drifting out of that shape by one character — the `0.9.1` -> `0.10.0` edit lengthened the
# line and left the rule where it was. Checked here rather than left to the eye, since the
# whole point of the sample is that it looks like what the hook prints.
#
# IN PYTHON BECAUSE THE COMPARISON IS IN CHARACTERS, NOT BYTES. `·` is two bytes and `─` is
# three, so an `awk length()` reads a correctly underlined header as 53 against 153 and
# fails it — the same multibyte trap the banner's own `pad()` exists for. (The sibling
# session-banner harness already depends on python3 for its scan.)
# One scanner, run twice: over the real docs, and over a planted sample whose rule is one
# character short. A check that can only pass is not a check.
rule_drift() { # reads file names on stdin, prints how many headers are mis-underlined
  python3 -c '
import io, re, sys
hdr = re.compile(r"^AI-Bridge v?[0-9]+\.[0-9]+\.[0-9]+ ")
drifted = 0
for name in sys.stdin.read().split():
    lines = io.open(name, encoding="utf-8").read().splitlines()
    for prev, cur in zip(lines, lines[1:]):
        if hdr.match(prev) and cur and set(cur) == {u"\u2500"} and len(cur) != len(prev):
            sys.stderr.write("        RULE %d vs HEADER %d in %s\n" % (len(cur), len(prev), name))
            drifted += 1
print(drifted)
'
}
widths="$(cd "$TPL" && git ls-files '*.md' | grep -v '^tests/' | rule_drift)"
ok "every sampled banner header is underlined to its own width" "$widths" 0
mkdir -p "$TMP/planted"
{ printf 'AI-Bridge %s \xc2\xb7 x\n' "$ver"; printf '\xe2\x94\x80\xe2\x94\x80\n'; } > "$TMP/planted/sample.md"
ok "…and that scan flags a rule that is too short" \
  "$(printf '%s\n' "$TMP/planted/sample.md" | rule_drift 2>/dev/null)" 1

# =======================================================================================
echo "== 3. \`core\` is a closed list, and it is the list the rule files govern =="
# =======================================================================================
# The convention is only actionable if "is this a core change?" has one answer, and it is
# only MET if the answer loads when an agent opens the file. Both rule files' `paths:`
# globs are the delivery mechanism, so the documented list is derived from them here rather
# than restated: if someone widens a glob without widening the rule, this fails.
# `LC_ALL=C` on the sort: the set is compared as a string, and a locale that orders
# `RETIRED` after `config` would fail this for a reason that has nothing to do with the
# rule files.
# A PER-FILE GLOB INSIDE A DIRECTORY GLOB IS NOT A NEW CORE PATH, and collapsing it here
# is what keeps this list about the CONVENTION rather than about rule-file plumbing:
# `installer.md` names `/plugin/scripts/init-bundle.sh` so its own rules load when you open
# the installer, but `/plugin/**` already made that path core. Only the outermost entries
# are compared.
raw_globs="$(sed -n '/^---$/,/^---$/p' "$TPL/.claude/rules/machinery.md" "$TPL/.claude/rules/installer.md" \
         | grep -oE '"/[^"]+"' | tr -d '"' | sed -e 's#^/##' -e 's#/\*\*$##' \
         | LC_ALL=C sort -u)"
globs="$(printf '%s\n' "$raw_globs" | awk '
  NF { g[++n] = $0 }
  END {
    for (i = 1; i <= n; i++) {
      keep = 1
      for (j = 1; j <= n; j++) if (i != j && index(g[i], g[j] "/") == 1) keep = 0
      if (keep) print g[i]
    }
  }' | LC_ALL=C sort -u | tr '\n' ' ')"
ok "the two rule files cover exactly the core paths" \
  "$globs" "RETIRED config install.sh plugin plugin-yolo seed upgrade.sh "

# Each of those names must appear in the core sentence the agent reads. Anchored on the
# CLAUDE.md bullet rather than the whole file, so an unrelated mention elsewhere cannot
# answer for it.
core_bullet="$(grep -F 'A change to `core` PROPOSES a version bump' "$TPL/CLAUDE.md" || true)"
missing=0
for p in plugin plugin-yolo seed config install.sh upgrade.sh RETIRED; do
  printf '%s' "$core_bullet" | grep -qF "\`$p" || { missing=$((missing+1)); printf '        NOT NAMED IN CLAUDE.md: %s\n' "$p" >&2; }
done
ok "…and CLAUDE.md's core bullet names every one of them" "$missing" 0

# WHERE THE RULE LIVES. A convention nobody meets is not a convention: the role agents read
# CONVENTIONS.md (symlinked into every instance) before their first write in a target repo,
# and the two rule files load on a read of the paths they govern.
ok "CONVENTIONS.md carries the propose-don't-bump-silently rule" \
  "$(grep -qF 'PROPOSE the bump, never make it silently' "$TPL/seed/CONVENTIONS.md" && echo yes || echo no)" yes
ok "…and says the human approves by merging" \
  "$(grep -qF 'approves it by merging' "$TPL/seed/CONVENTIONS.md" && echo yes || echo no)" yes
ok "…and forbids inventing a release process" \
  "$(grep -qiE 'no changelog, no tag' "$TPL/seed/CONVENTIONS.md" && echo yes || echo no)" yes
ok "machinery.md carries it (loads on a /symlink/** read)" \
  "$(grep -qF 'PROPOSES a version bump' "$TPL/.claude/rules/machinery.md" && echo yes || echo no)" yes
ok "installer.md carries it (loads on install.sh, seed/, config/)" \
  "$(grep -qF 'PROPOSES a version bump' "$TPL/.claude/rules/installer.md" && echo yes || echo no)" yes
ok "the reasoning is in docs/conventions.md, once" \
  "$(grep -c '^## 20\. The version is a number' "$TPL/docs/conventions.md")" 1

# =======================================================================================
echo "== 4. the drift check: BEHIND speaks, equal and ahead are byte-empty =="
# =======================================================================================
# Every case builds a real bare repo and a real clone of it. `remote_ver` is what the
# default branch carries; `local_ver` is what the checkout's working tree carries, because
# the working tree is what an instance's symlinks actually resolve into.
mkfixture() { # <name> <remote-version> <local-version> [branch]
  local name="$1" rver="$2" lver="$3" branch="${4:-main}"
  local bare="$TMP/$name.git" work="$TMP/$name.seed" tpl="$TMP/$name"
  GIT init -q --bare "$bare"
  # The BARE repo's HEAD is what a clone reads as the remote's default branch, and `git
  # init` sets it from the local `init.defaultBranch` — so a fixture that only pushes a
  # branch leaves the remote pointing at a ref that does not exist, and the clone comes
  # back with no `origin/HEAD` at all. Setting it here is what makes the "the default
  # branch is not assumed to be main" case a real test of the lookup.
  GIT -C "$bare" symbolic-ref HEAD "refs/heads/$branch"
  GIT init -q "$work"
  GIT -C "$work" symbolic-ref HEAD "refs/heads/$branch"
  printf '%s\n' "$rver" > "$work/VERSION"
  GIT -C "$work" add VERSION
  GIT -C "$work" commit -qm "remote $rver"
  GIT -C "$work" push -q "$bare" "$branch"
  # Cloning a POPULATED bare repo is what gives the clone an `origin/HEAD`, which is how
  # the script learns the default branch without assuming one.
  GIT clone -q "$bare" "$tpl" 2>/dev/null
  rm -rf "$work"
  mkdir -p "$tpl/plugin/scripts"
  cp "$CHECK" "$tpl/plugin/scripts/"
  printf '%s\n' "$lver" > "$tpl/VERSION"
  GIT -C "$tpl" add -A >/dev/null 2>&1
  GIT -C "$tpl" commit -qm "local $lver" >/dev/null 2>&1
  printf '%s' "$tpl"
}
# Invoked exactly as the instance invokes it: through the file inside the template, with no
# --template, so the self-location path is exercised too.
run_check() { # <template-dir> [extra args…]
  local tpl="$1"; shift
  OUT="$(bash "$tpl/plugin/scripts/check-template-version.sh" --instance "$TMP/inst" "$@" 2>/dev/null)"
  RC=$?
}
len() { printf '%s' "${#OUT}"; }

behind="$(mkfixture behind 0.10.0 0.9.1)"
run_check "$behind"
ok "behind: exit 0"                       "$RC" 0
ok "…says so once"                        "$(printf '%s\n' "$OUT" | grep -c 'UPDATE')" 1
ok "…naming the version this machine runs" \
  "$(printf '%s\n' "$OUT" | grep -qF 'runs 0.9.1' && echo yes || echo no)" yes
ok "…and the version on the default branch" \
  "$(printf '%s\n' "$OUT" | grep -qF 'has 0.10.0' && echo yes || echo no)" yes
# 0.10.0 > 0.9.1 is FALSE as a string compare, and that is the whole reason this fixture
# uses those two numbers rather than 1.0.0 and 2.0.0.
ok "…so the compare is numeric per field, not lexicographic" \
  "$(printf '%s\n' "$OUT" | grep -qF 'UPDATE' && echo yes || echo no)" yes
# THE REPAIR IS TWO COMMANDS AND THE SECOND ONE IS STILL THE POINT: updating the plugin
# refreshes the machinery, but a SEED change reaches a bundle only through a stamp. It was
# `install.sh`; it is `/ai-bridge:init` since the bundle stopped carrying machinery.
ok "…and it names the RE-STAMP, not just the update" \
  "$(printf '%s\n' "$OUT" | grep -qF '/ai-bridge:init' && echo yes || echo no)" yes

equal="$(mkfixture equal 1.2.3 1.2.3)"
run_check "$equal"
ok "equal: byte-empty"                    "$(len)" 0
ok "…exit 0"                              "$RC" 0

ahead="$(mkfixture ahead 0.9.1 0.10.0)"
run_check "$ahead"
ok "ahead: byte-empty"                    "$(len)" 0

# `1.0` and `1.0.0` are the same version: a missing field is 0, never "older".
short="$(mkfixture short 1.0 1.0.0)"
run_check "$short"
ok "1.0 vs 1.0.0: same version, byte-empty" "$(len)" 0

# The default branch is NOT assumed to be `main` — this remote's is `next`, and origin/HEAD
# is what says so.
nextbr="$(mkfixture nextbr 2.0.0 1.9.9 next)"
run_check "$nextbr"
ok "default branch 'next': still detected as behind" \
  "$(printf '%s\n' "$OUT" | grep -qF 'UPDATE' && echo yes || echo no)" yes

# =======================================================================================
echo "== 5. a FAILURE is never 'behind' =="
# =======================================================================================
# THE LOAD-BEARING GROUP. Each case is a way the answer can be unavailable, and every one
# of them must be indistinguishable from "you are up to date": byte-empty, exit 0.

# 5a. UNREACHABLE REMOTE, with the fetch explicitly asked for. The remote path does not
# exist, so `git fetch` fails the way an offline laptop or an expired token fails.
offline="$(mkfixture offline 3.0.0 1.0.0)"
GIT -C "$offline" remote set-url origin "$TMP/does-not-exist.git"
run_check "$offline" --fetch
ok "unreachable remote + --fetch: byte-empty" "$(len)" 0
ok "…and exit 0, not a failed hook"           "$RC" 0

# 5b. …and the same repo WITHOUT --fetch still answers from the ref already on disk. This
# is the pair that proves the session path makes no network call at all: the remote is
# unreachable in both runs, and only the one that asked to talk to it went quiet.
run_check "$offline"
ok "no --fetch: answered offline from the on-disk ref" \
  "$(printf '%s\n' "$OUT" | grep -qF 'UPDATE' && echo yes || echo no)" yes

# 5c. No remote-tracking ref at all — a checkout that has never fetched.
noref="$(mkfixture noref 4.0.0 1.0.0)"
GIT -C "$noref" update-ref -d refs/remotes/origin/next >/dev/null 2>&1
GIT -C "$noref" update-ref -d refs/remotes/origin/main >/dev/null 2>&1
GIT -C "$noref" symbolic-ref -d refs/remotes/origin/HEAD >/dev/null 2>&1
run_check "$noref"
ok "no origin/<default> ref: byte-empty"      "$(len)" 0

# 5c-bis. THE FALLBACK THAT WAS REMOVED, pinned so it cannot come back. This remote's
# default branch is `master`, and it ALSO carries a `main` — the ordinary shape of a repo
# that renamed its default branch and kept the old ref. With `origin/HEAD` gone there is no
# way to know which one is authoritative, and the earlier code assumed `origin/main`: it
# resolved, it was newer, and the check would have announced an update against a branch
# nobody asked about. "A wrong name resolves to nothing and is therefore silent" is only
# true when the wrong name does not exist, which is exactly the case this fixture is not.
assumed="$(mkfixture assumed 6.0.0 1.0.0 master)"
GIT -C "$assumed" update-ref refs/remotes/origin/main refs/remotes/origin/master
GIT -C "$assumed" symbolic-ref -d refs/remotes/origin/HEAD >/dev/null 2>&1
run_check "$assumed"
ok "no origin/HEAD but a stale origin/main: byte-empty" "$(len)" 0
ok "…and exit 0"                                        "$RC" 0
# THE POSITIVE CONTROL, without which the assertion above passes on a broken fixture: put
# `origin/HEAD` back and the very same repo speaks. So the silence is the missing symbolic
# ref, not a fixture that could never have answered.
GIT -C "$assumed" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/master
run_check "$assumed"
ok "…and with origin/HEAD restored it DOES speak" \
  "$(printf '%s\n' "$OUT" | grep -qF 'UPDATE' && echo yes || echo no)" yes
# …against `master`, the branch origin/HEAD names — never the `main` that is still sitting
# there. Both branches carry 6.0.0 here, so the ref NAMED in the line is what separates them.
ok "…naming the default branch it actually resolved" \
  "$(printf '%s\n' "$OUT" | grep -qF 'origin/master' && echo yes || echo no)" yes

# Same fixture, one more property: THE LABEL IS DERIVED FROM THE CHECKOUT, not hardcoded — `symlink/**` carries no repo
# literals, and a renamed clone must name itself. The fixture directory is `assumed`, so
# that is what the line says.
ok "…and the line names the template checkout, not a hardcoded project" \
  "$(printf '%s\n' "$OUT" | grep -qF 'TEMPLATE UPDATE (assumed)' && echo yes || echo no)" yes

# 5d. Not a git checkout at all (a template copied, not cloned).
plain="$TMP/plain"
mkdir -p "$plain/plugin/scripts"
cp "$CHECK" "$plain/plugin/scripts/"
printf '1.0.0\n' > "$plain/VERSION"
run_check "$plain"
ok "not a git checkout: byte-empty"           "$(len)" 0
ok "…exit 0"                                  "$RC" 0

# 5e. No VERSION here.
noversion="$(mkfixture noversion 5.0.0 1.0.0)"
rm -f "$noversion/VERSION"
run_check "$noversion"
ok "no local VERSION: byte-empty"             "$(len)" 0

# 5f. No VERSION on the remote's branch — the state of every commit before this one.
novremote="$TMP/novremote"
GIT init -q --bare "$novremote.git"
GIT -C "$novremote.git" symbolic-ref HEAD refs/heads/main
GIT init -q "$novremote.seed"
GIT -C "$novremote.seed" symbolic-ref HEAD refs/heads/main
printf 'x\n' > "$novremote.seed/README.md"
GIT -C "$novremote.seed" add README.md
GIT -C "$novremote.seed" commit -qm "no VERSION here"
GIT -C "$novremote.seed" push -q "$novremote.git" main
GIT clone -q "$novremote.git" "$novremote" 2>/dev/null
rm -rf "$novremote.seed"
mkdir -p "$novremote/plugin/scripts"
cp "$CHECK" "$novremote/plugin/scripts/"
printf '1.0.0\n' > "$novremote/VERSION"
run_check "$novremote"
ok "remote branch has no VERSION: byte-empty"  "$(len)" 0

# 5g. UNPARSEABLE, either side. A pre-release has no defensible ordering against a release,
# and prose is not a version — both are unknown, and unknown is silence, never "behind".
# The ESC case matters twice over: this content would otherwise reach session context.
junk="$(mkfixture junk 9.9.9 1.0.0)"
printf 'not a version\n' > "$junk/VERSION"
run_check "$junk"
ok "prose in the local VERSION: byte-empty"    "$(len)" 0
printf '1.0.0-rc1\n' > "$junk/VERSION"
run_check "$junk"
ok "a pre-release is unordered, so: byte-empty" "$(len)" 0
printf '\033[31m1.0.0\n' > "$junk/VERSION"
run_check "$junk"
ok "an ESC sequence in VERSION: byte-empty"    "$(len)" 0
ok "…and nothing from that file reached stdout" \
  "$(printf '%s' "$OUT" | grep -c '31m' || true)" 0

# 5h. IT NEVER WRITES. Not the checkout, not the refs, not the working tree — the human
# pulls and re-stamps, and a checker that touched the repo it was reporting on would be a
# far worse trade than a stale answer.
before="$(GIT -C "$behind" status --porcelain; GIT -C "$behind" rev-parse HEAD)"
run_check "$behind"
after="$(GIT -C "$behind" status --porcelain; GIT -C "$behind" rev-parse HEAD)"
ok "the checkout is untouched by a run"         "$([ "$before" = "$after" ] && echo yes || echo no)" yes

# =======================================================================================
echo "== 6. the banner prints it, under the header, and only when it is true =="
# =======================================================================================
# The line has to reach a human, and the banner is the surface: end to end here, through
# the real hook, in a fake instance whose template is a real behind-the-remote clone.
INST="$TMP/inst"
mkdir -p "$INST/.claude/agents"
printf 'stub\n' > "$INST/SCHEMA.md"
printf '{ "org": "example-org" }\n' > "$INST/instance.config.json"

wire() { # <template-dir> — give a fixture template the hook the banner is
  mkdir -p "$1/plugin/hooks"
  cp "$BANNER" "$1/plugin/hooks/session-banner.sh"
  cp "$TPL/plugin/scripts/resolve-config.sh" "$1/plugin/scripts/" 2>/dev/null || true
}
banner() { # <template-dir>
  OUT="$(CLAUDE_PROJECT_DIR="$INST" bash "$1/plugin/hooks/session-banner.sh" 2>&1)"
  RC=$?
}

wire "$behind"
banner "$behind"
ok "banner: exit 0"                            "$RC" 0
ok "…prints the drift line"                    "$(printf '%s\n' "$OUT" | grep -c 'UPDATE')" 1
# Under the header and its rule, attached to the number it contradicts — not filed among
# the settings rows further down.
# COUNTED FROM THE IDENTITY LINE, NOT FROM LINE 1. The banner opens with one blank line
# (task-027) so the harness's `SessionStart:<source> says: ` label ends the line it owns —
# so "directly under the header rule" is the identity line, its rule, §2b's own blank
# separator and then the line — index plus three, and it stays that whatever precedes the
# header. The claim is unchanged; only the anchor is.
HEAD_NO="$(printf '%s\n' "$OUT" | awk '$0 != "" { print NR; f = 1; exit } END { if (!f) print 0 }')"
ok "…the banner opens with exactly ONE blank line"  "$HEAD_NO" 2
ok "…and the drift line is directly under the header rule (line $((HEAD_NO + 3)))" \
  "$(printf '%s\n' "$OUT" | sed -n "$((HEAD_NO + 3))p" | grep -qF 'UPDATE' && echo yes || echo no)" yes
ok "…and the header still carries this template's own version" \
  "$(printf '%s\n' "$OUT" | grep -qF 'AI-Bridge v0.9.1' && echo yes || echo no)" yes

wire "$equal"
banner "$equal"
ok "up to date: the banner says nothing about versions" \
  "$(printf '%s\n' "$OUT" | grep -c 'UPDATE' || true)" 0
ok "…and the rest of the banner is intact"     "$(printf '%s\n' "$OUT" | grep -c 'AI-Bridge' )" 1

# An instance stamped before this script shipped has no file to run. Absence is silence —
# the same contract every other optional section of the banner keeps.
rm -f "$equal/plugin/scripts/check-template-version.sh"
banner "$equal"
ok "checker absent: still exit 0"              "$RC" 0
ok "…and still no line about it"               "$(printf '%s\n' "$OUT" | grep -c 'UPDATE' || true)" 0

# =======================================================================================
echo "== 7. the shipped file is executable in the INDEX, like every other script =="
# =======================================================================================
# `install.sh` chmods what it stamps, which launders a committed-644 file on every machine
# that has ever run it — so the index is the only place the real mode lives. Asserted here
# too, and not left to scripts-executable.test.sh alone, because this is the file the
# change adds and a 644 here means the banner's `bash <path>` still works while a direct
# invocation does not.
mode="$(cd "$TPL" && git ls-files -s plugin/scripts/check-template-version.sh | awk '{print $1}')"
ok "check-template-version.sh is 100755 in the index" "$mode" 100755

echo
printf 'pass=%d fail=%d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
