#!/usr/bin/env bash
# release-bump.sh <minor|patch> — move the version ON THE DEFAULT BRANCH, after a merge.
# The ONLY writer of the five places that carry it: VERSION, plugin/VERSION, the two plugin
# manifests, and every tracked doc that DISPLAYS the number (its `─` rule is resized with
# the header). Refuses on a feature branch or a dirty tree, commits, prints the push.
# A pull request never carries the bump, so two of them can no longer collide on it.
# Exit: 0 bumped · 1 refused (branch, dirty tree, missing file, unverifiable result) · 2 usage.
# Reasoning: ai-bridge-next/task-026, docs/conventions.md §20. Verified by tests/release-bump.test.sh.
set -uo pipefail

usage() { sed -n '2,8p' "$0" >&2; exit 2; }
die() { printf 'release-bump: %s\n' "$1" >&2; exit 1; }

FIELD=""; ROOT=""; COMMIT=1; DRY=0
while [ $# -gt 0 ]; do
  case "$1" in
    minor|patch)  FIELD="$1"; shift ;;
    --repo)       shift; ROOT="${1:-}"; shift || true ;;
    --repo=*)     ROOT="${1#--repo=}"; shift ;;
    --no-commit)  COMMIT=0; shift ;;
    --dry-run)    DRY=1; COMMIT=0; shift ;;
    -h|--help)    usage ;;
    *) printf 'release-bump: unknown argument: %s\n' "$1" >&2; usage ;;
  esac
done
[ -n "$FIELD" ] || usage

[ -n "$ROOT" ] || ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
[ -f "$ROOT/VERSION" ] || die "no VERSION under $ROOT — pass --repo <checkout>"
command -v python3 >/dev/null 2>&1 || die "python3 is required: the manifests are JSON, and the banner rule is counted in CHARACTERS"
git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1 || die "$ROOT is not a git checkout"

# The bump belongs to the merge, so it belongs to the branch the merge landed on. An
# unresolvable default branch is a maintainer's own tree and is left alone.
BRANCH="$(git -C "$ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null)"
DEFAULT="$(git -C "$ROOT" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null)"; DEFAULT="${DEFAULT#origin/}"
[ -z "$DEFAULT" ] || [ "$BRANCH" = "$DEFAULT" ] \
  || die "on '$BRANCH', not the default branch '$DEFAULT' — the bump lands after the merge, never inside a PR"
[ -n "$(git -C "$ROOT" status --porcelain)" ] \
  && die "the working tree is dirty — the bump is its own commit and nothing else"

OLD="$(head -n 1 "$ROOT/VERSION" | tr -d '[:space:]')"
printf '%s' "$OLD" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$' || die "VERSION is not MAJOR.MINOR.PATCH: '$OLD'"
IFS=. read -r MA MI PA <<EOF
$OLD
EOF
case "$FIELD" in
  minor) NEW="$MA.$((MI + 1)).0" ;;
  patch) NEW="$MA.$MI.$((PA + 1))" ;;
esac

# One writer, one verifier: python3 rewrites each place in situ (no reformatting), then
# re-reads all five and refuses rather than leaving a half-moved number behind.
CHANGED="$(python3 - "$ROOT" "$NEW" "$DRY" <<'PY'
import io, json, os, re, subprocess, sys

root, new, dry = sys.argv[1], sys.argv[2], sys.argv[3] == "1"
HDR = re.compile(r'(AI-Bridge v?)(\d+\.\d+\.\d+)')
RULE = u"─"
changed = []

def read(path):
    return io.open(path, encoding="utf-8").read()

def write(path, text, rel):
    changed.append(rel)
    if dry:
        return
    tmp = path + ".release-bump.tmp"
    io.open(tmp, "w", encoding="utf-8").write(text)
    os.replace(tmp, path)

def refuse(msg):
    sys.stderr.write("release-bump: %s\n" % msg)
    sys.exit(1)

def set_version(text, where):
    out, n = re.subn(r'("version"\s*:\s*)"[^"]*"', lambda m: m.group(1) + '"%s"' % new, text, count=1)
    if n != 1:
        refuse("%s carries no \"version\" key" % where)
    return out

def core_entry_span(text):
    """The offsets of the marketplace object whose source is ./plugin — found by balancing
    braces outwards, so the edit can never land on a companion sharing the number."""
    m = re.search(r'"source"\s*:\s*"\./plugin"', text)
    if not m:
        refuse("marketplace.json has no entry with source ./plugin")
    i, depth = m.start() - 1, 0
    while i >= 0:
        if text[i] == "}":
            depth += 1
        elif text[i] == "{":
            if depth == 0:
                break
            depth -= 1
        i -= 1
    j, depth = i, 0
    while j < len(text):
        if text[j] == "{":
            depth += 1
        elif text[j] == "}":
            depth -= 1
            if depth == 0:
                break
        j += 1
    if i < 0 or j >= len(text):
        refuse("marketplace.json: the ./plugin entry's braces do not balance")
    return i, j + 1

for rel in ("VERSION", "plugin/VERSION"):
    write(os.path.join(root, rel), new + "\n", rel)

rel = "plugin/.claude-plugin/plugin.json"
write(os.path.join(root, rel), set_version(read(os.path.join(root, rel)), rel), rel)

rel = ".claude-plugin/marketplace.json"
text = read(os.path.join(root, rel))
i, j = core_entry_span(text)
write(os.path.join(root, rel), text[:i] + set_version(text[i:j], "the ./plugin entry") + text[j:], rel)

docs = [d for d in subprocess.check_output(
    ["git", "-C", root, "ls-files", "*.md"]).decode("utf-8").split() if not d.startswith("tests/")]
for rel in docs:
    lines, hit = read(os.path.join(root, rel)).splitlines(True), False
    for k, line in enumerate(lines):
        body = line.rstrip("\n")
        if not HDR.search(body):
            continue
        hit = True
        header = HDR.sub(lambda m: m.group(1) + new, body)
        lines[k] = header + ("\n" if line.endswith("\n") else "")
        nxt = lines[k + 1].rstrip("\n") if k + 1 < len(lines) else ""
        if header.startswith("AI-Bridge") and nxt and set(nxt) == set(RULE):
            lines[k + 1] = RULE * len(header) + "\n"
    if hit:
        write(os.path.join(root, rel), "".join(lines), rel)

if not dry:
    if read(os.path.join(root, "VERSION")).strip() != new or read(os.path.join(root, "plugin/VERSION")).strip() != new:
        refuse("a VERSION file did not take the new number")
    own = json.load(io.open(os.path.join(root, "plugin/.claude-plugin/plugin.json"), encoding="utf-8"))
    mkt = json.load(io.open(os.path.join(root, ".claude-plugin/marketplace.json"), encoding="utf-8"))
    core = [p for p in mkt.get("plugins", []) if p.get("source") == "./plugin"]
    if own.get("version") != new or len(core) != 1 or core[0].get("version") != new:
        refuse("a manifest did not take the new number — `git checkout -- .` to undo")
    for rel in docs:
        lines = read(os.path.join(root, rel)).splitlines()
        for k, line in enumerate(lines):
            m = HDR.search(line)
            if not m:
                continue
            nxt = lines[k + 1] if k + 1 < len(lines) else ""
            if m.group(2) != new:
                refuse("%s still displays %s" % (rel, m.group(2)))
            if line.startswith("AI-Bridge") and nxt and set(nxt) == set(RULE) and len(nxt) != len(line):
                refuse("%s: the rule under the banner is %d wide, the header is %d" % (rel, len(nxt), len(line)))

print("\n".join(changed))
PY
)" || die "the bump did not complete — check 'git -C $ROOT status', then 'git -C $ROOT checkout -- .'"

if [ "$DRY" = 1 ]; then
  printf 'release-bump: %s -> %s (dry run) would write:\n%s\n' "$OLD" "$NEW" "$CHANGED"
  exit 0
fi
if [ "$COMMIT" = 0 ]; then
  printf 'release-bump: %s -> %s written, not committed:\n%s\n' "$OLD" "$NEW" "$CHANGED"
  exit 0
fi

git -C "$ROOT" add -A || die "git add failed"
git -C "$ROOT" commit -q -m "chore: VERSION $OLD -> $NEW (bumped on $BRANCH after the merge)" \
  || die "git commit failed"
printf 'release-bump: %s -> %s committed on %s. Now push it:\n  git -C %s push origin %s\n' \
  "$OLD" "$NEW" "$BRANCH" "$ROOT" "$BRANCH"
