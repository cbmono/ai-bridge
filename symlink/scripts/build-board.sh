#!/usr/bin/env bash
#
# build-board.sh — render every instance's SNAPSHOT.json as ONE self-contained HTML
# page: projects collapsed to one summary line, each expandable to its task table,
# with a decision rail on top. A page a teammate opens on a phone.
#
# THE PAGE IS PER OWNER, AND HAS TWO HALVES. Your own projects come from this clone's
# SNAPSHOT.json, as they always did. Every OTHER owner's come from the tracked task
# documents at your current git HEAD, named and collapsed below them. Why it is shaped
# that way, and why it is not a shared board, is the "OTHER OWNERS" block further down.
#
#   Usage:
#     scripts/build-board.sh [--out FILE] [--standalone] [INSTANCE_DIR ...]
#     scripts/build-board.sh --list-instances [INSTANCE_DIR ...]
#
#     INSTANCE_DIR ...  the instances to render. With none given, the list comes
#                       from `boardInstances` in ./instance.config.local.json, else
#                       ./instance.config.json; if that key
#                       is absent or empty, just this instance.
#     --out FILE        where to write (default: ./board.html — it is the path an
#                       instance's .gitignore already covers)
#     --standalone      wrap the output in <!doctype html>/<head> for opening in a
#                       browser directly. OMIT for publishing (see OUTPUT SHAPE).
#                       Wrapping, not markup: the same page either way, which is why
#                       watch-board.sh can pass it and the publish step can not.
#     --list-instances  print the resolved instance directories, one per line, and
#                       exit without writing anything. This exists so watch-board.sh
#                       can learn WHICH directories to watch without carrying a third
#                       copy of the discovery rule below — one script owns it.
#
# WHY ONE SCRIPT WITH ONE LAYOUT — AND WHY THE OTHER ONE IS GONE RATHER THAN OFF.
# This file has been all three shapes, in this order:
#   1. two scripts — this one and a `build-artifact-board.sh`, 1,139 lines between them,
#      reading the same snapshot contract and differing only in markup. Two files meant
#      two copies of the parts a board must not get wrong, and the second copy was the
#      weaker one: it wrote a PR URL into an `href` without checking its scheme and read
#      every count with a bare `.get()`, so both hardening rules below lived in one file
#      and not the other.
#   2. one script, two layouts, `--layout` choosing the markup. That fixed the
#      duplication and left a new problem in its place: a DEFAULT. Every caller now had
#      to remember the flag, and the /pm-loop tick published with `--layout table` while
#      watch-board.sh forwarded no layout at all — so the local live page and the
#      published page were two different boards rendered by one script, and nothing in
#      the code said so.
#   3. one script, one layout. The owner saw both rendered from live data and rejected
#      the kanban `columns` page outright — "not necessary and it's not usable, it's just
#      not readable" — so it is DELETED: markup, CSS, its queue derivation and its tests.
#      Not defaulted away. A rejected path kept behind a flag is still maintained, still
#      tested, and still one forgotten argument away from being what a human sees; the
#      inconsistency in (2) is exactly that failure, and only deletion closes it by
#      construction. `--layout` is now refused BY NAME (see the arg loop), so a caller
#      written against (2) fails loudly instead of silently getting the other page.
# The rule this file keeps paying for: a second rendering path is a second place for a
# hardening rule to be missing. Do not add one back without deleting this paragraph.
#
# DISCOVERY IS EXPLICIT, NEVER A GLOB. This file is symlinked into every instance,
# so it may not know where anybody's workspace lives — no `~/workspace/*`, no
# guessing at sibling directories. Either you name the instances or the instance's
# own config does, and an unnamed instance is simply not on the board.
#
# ABSENCE IS THE OFF SWITCH, ON BOTH SIDES. An instance with no SNAPSHOT.json does
# not appear — no placeholder, no warning card, nothing (the run says so on stderr,
# where it costs a human nothing). See write-snapshot.sh for why that is permanent.
#
# EVERYTHING FROM A SNAPSHOT IS UNTRUSTED TEXT. Titles, descriptions and URLs come
# from task documents: human-written, quoting tool output and PR metadata, and none
# of it authored here. This is the same boundary show-awaiting.sh keeps when it
# fences items before they enter session context (see its closing comment) — the
# difference is only the sink. Here the sink is an HTML page that gets published, so:
#   · every string is HTML-escaped, attribute values included, at the single point
#     where it is written into the page;
#   · a URL is rendered as a link ONLY if its scheme is http/https — a `javascript:`
#     or `data:` PR URL renders as inert text. The writer already restricts what it
#     collects; the board does not trust it to have done so;
#   · nothing from a snapshot ever reaches a <script>, a style, or an event handler;
#   · no filesystem path reaches the page — an instance is identified by its directory
#     NAME, because a published board should not carry anybody's home directory.
# A malformed snapshot is a visible card, not a crash: a broken instance must not be
# able to blank the board for the others. That promise has TWO halves, because a
# snapshot can be broken in two different ways, and only one of them is a parse error:
#   · UNPARSEABLE (bad JSON, or a top level that is not an object) — the instance is
#     dropped and rendered as a named "Unreadable snapshot" note, so a human sees it.
#   · WRONG TYPES in valid JSON (`"tasks": "many"`, a non-string `group`) — the file
#     parses, so nothing above catches it; the wrong type surfaces later at an int()
#     or a sort comparison, and an uncaught ValueError/TypeError there means NO output
#     file is written at all. Every number therefore goes through toint() and `group`
#     is forced to str(), so the drifted field degrades to 0 while the instance and
#     every other instance still render. Coercion, not a note, is deliberate here: a
#     single junk count is not worth hiding a whole instance's real work behind a
#     warning card. Do not reintroduce a bare int() on snapshot data.
#
# WHY python3 AND NOT awk. Every other script here is bash + awk on purpose, so it
# ships into an instance unchanged. This one needs two things awk does badly and a
# board cannot be wrong about: parsing arbitrary JSON, and HTML-escaping. A
# hand-rolled JSON reader mis-handling a quote inside a title is exactly the bug that
# turns an untrusted title into markup on a published page. `json` and
# `html.escape(..., quote=True)` are the right primitives, they are in the standard
# library, and this is a human-run reporting step — not tick machinery a /pm-loop
# depends on. No npm, no pip, no new runtime.
#
# OUTPUT SHAPE. The default output is an **Artifact page body**: a <title>, an inline
# <style>, then content — no <!doctype>, <html>, <head> or <body> tags, because the
# publish step wraps the file in exactly those. Opening that file in a browser
# directly works but lands in quirks mode with no charset declared; use
# `--standalone` for a local look, and the plain file for publishing.
#
# WHAT THIS PAGE DOES AND DOES NOT CARRY. These were once "the table layout's"
# properties as opposed to the other one's; they are now simply the board's, and every
# test that reads them reads them off the only page there is.
#   · It uses <details>, never script, for collapsing. The first version rendered from
#     JavaScript and toggled with a click handler; two bugs came out of that and NEITHER
#     WAS DIAGNOSABLE IN PLACE, because the artifact host serves the page in an iframe
#     that exposes neither its console nor its accessibility tree, so a blank page had no
#     error to read. <details> needs no script, works with scripting off, is
#     keyboard-accessible for free, and its open/closed state is per-viewer.
#   · It DOES carry one <script> and one external <link>: a clipboard helper (a browser
#     cannot open a local file, so a task copies a SHORT REFERENCE — `<project>/tasks/<id>`
#     — instead of a link, and every button says what it copied so a failed copy is
#     visible rather than silent) and a webfont stylesheet. Nothing from a snapshot ever
#     reaches either of them; the escaping rules above are what hold, not "no script". A
#     retained project's deliverables panel copies with this SAME helper — every
#     `[data-copy]` button on the page shares it, and there is no second one.
#   · A retained project's deliverables panel is built from `deliverable_paths:` in the
#     project's own SNAPSHOT.json stanza — which write-snapshot.sh reads from
#     project.md's frontmatter, and ONLY from there. This renderer never opens `tasks/`
#     and never lists `deliverables/` from disk; that is what keeps it compatible with
#     the done-project skip (see write-snapshot.sh's header). Every entry is re-checked
#     against `/projects/<slug>/deliverables/<file>` (bundle_deliverable()) before it can
#     reach a button — so every DELIVERABLE path on this page resolves inside that
#     project's own `deliverables/`, a NESTED file below it included (an exported site's
#     `site/index.html`), which is inside the guarantee and rendered, not dropped. Scoped
#     to deliverables and no wider ON PURPOSE: this page renders a `/projects/<slug>/`
#     from an unvalidated slug elsewhere (the other-owners section), which this check
#     does not cover and does not claim to.
#   · Its decision rail surfaces one thing AWAITING.md does not: an open question on a
#     task that is no longer a draft. write-snapshot.sh only emits an `awaiting` verb for
#     a question while the task IS a draft, so such a question is invisible in the queue;
#     the rail adds it at the presentation layer, without touching the AWAITING.md
#     contract that awaiting-queue.test.sh pins.
#   · With no readable snapshot it writes NOTHING and exits 0. Publishing an empty board
#     is not useful, and an instance off the board is a choice, not an error.
#
# Deterministic. No network at build time — the only subprocess is a local `git` read for
# the other-owners section, described below. Verified by tests/snapshot.test.sh (the
# writer, plus this renderer's data-governance boundary), tests/artifact-board.test.sh
# (this renderer's markup and hardening), tests/per-owner-board.test.sh (the two-section
# split and its HEAD keying), tests/board-renderers.test.sh (print-board and watch-board)
# (this file's size).
set -euo pipefail

OUT="board.html"
STANDALONE=0
LIST_ONLY=0
DIRS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --out) shift; [[ $# -gt 0 ]] || { echo "build-board: --out needs a path" >&2; exit 2; }; OUT="$1" ;;
    --out=*) OUT="${1#--out=}" ;;
    # The tombstone. --layout is gone (see the header), and a caller that still
    # passes it is refused BY NAME rather than by the generic unknown-flag line
    # below: every such caller was written when the flag chose between two pages, so
    # "unknown flag" would leave a human wondering which page they are now getting.
    --layout|--layout=*) echo "build-board: --layout was removed — there is only one board now. Drop the flag." >&2; exit 2 ;;
    --standalone) STANDALONE=1 ;;
    --list-instances) LIST_ONLY=1 ;;
    -h|--help) sed -n '2,/^set -euo/p' "$0" | sed 's/^# \{0,1\}//; $d'; exit 0 ;;
    -*) echo "build-board: unknown flag '$1'" >&2; exit 2 ;;
    *) DIRS+=("$1") ;;
  esac
  shift
done
command -v python3 >/dev/null 2>&1 || {
  echo "build-board: needs python3 (standard library only). See this script's header for why." >&2
  exit 2
}

BOARD_OUT="$OUT" BOARD_STANDALONE="$STANDALONE" BOARD_LIST_ONLY="$LIST_ONLY" \
  python3 - "${DIRS[@]+"${DIRS[@]}"}" <<'PY'
import html, json, os, re, subprocess, sys, time, unicodedata
from pathlib import Path

OUT = Path(os.environ["BOARD_OUT"])
STANDALONE = os.environ.get("BOARD_STANDALONE") == "1"


def e(v):
    """The single escape point. Everything from a snapshot goes through here."""
    return html.escape("" if v is None else str(v), quote=True)

def href(url):
    """A link only for http/https. Anything else is inert text (see header)."""
    u = "" if url is None else str(url)
    return u if u.lower().startswith(("http://", "https://")) else ""

def dirname(d):
    """The directory's own name — never a path.

    `.resolve()` first, because the default discovery target is Path("."), whose
    `.name` is EMPTY: a snapshot carrying no `group` (exactly what install.sh seeds
    on a first stamp) then fell through to str(d) and labelled the instance ".".
    Resolving yields the real basename, and taking only the basename keeps the
    published-page rule intact — a name leaves, a path never does.
    """
    try:
        return d.resolve().name
    except OSError:
        return d.name


def resolve_dirs(argv):
    if argv:
        return [Path(a).expanduser() for a in argv], None
    # `boardInstances` is an OVERRIDABLE key: the gitignored instance.config.local.json
    # wins over the tracked instance.config.json. It is a list of filesystem PATHS
    # (expanduser below), so it is machine-shaped by the same test as reposRoot and
    # worktreeRoot — the sibling instances a second clone can see are its own business.
    # Absent (or empty) local file ⇒ the tracked file answers, exactly as before.
    # Full overridable set: SCHEMA.md → "Per-machine config overrides".
    for name in ("instance.config.local.json", "instance.config.json"):
        cfg = Path(name)
        if not cfg.is_file():
            continue
        try:
            parsed = json.loads(cfg.read_text(encoding="utf-8"))
            # A config whose top level is a list/string/number parses fine but has no
            # .get — an AttributeError here would end the run in a traceback instead of
            # the documented fallback, so shape is checked, not assumed.
            listed = (parsed.get("boardInstances") or []) if isinstance(parsed, dict) else []
        except (ValueError, OSError, UnicodeDecodeError):
            listed = []
            # Say only what is true: an unreadable LOCAL file still lets the tracked
            # one answer on the next pass, so this must not claim the final fallback.
            print(f"build-board: {name} is unreadable; ignoring it.", file=sys.stderr)
        if isinstance(listed, list) and listed:
            return [Path(str(p)).expanduser() for p in listed], "boardInstances"
    return [Path(".")], "this instance"

dirs, source = resolve_dirs(sys.argv[1:])

# --list-instances: answer the discovery question and stop, writing nothing. It is
# deliberately the SAME resolve_dirs call the render path uses — a second
# implementation of the rule is a second thing to drift. Paths only, one per line, so
# a caller can read them into a shell array.
if os.environ.get("BOARD_LIST_ONLY") == "1":
    for d in dirs:
        # One path per LINE, so a path containing a newline would forge an entry in
        # the caller's array — the same class as push-state.sh encoding every
        # file-derived value to one line. `boardInstances` is human-written JSON, where
        # a "\n" is legal, so this is a refusal rather than an escape: an unusable name
        # is named on stderr and dropped, never silently split in two.
        if "\n" in str(d) or "\r" in str(d):
            print(f"build-board: skipping an instance path containing a newline: {d!r}",
                  file=sys.stderr)
            continue
        print(d)
    sys.exit(0)

# `inst_dirs` runs parallel to `instances`: the second section needs the DIRECTORY (to
# read its git HEAD and its config), while the snapshot itself must never carry a path.
# Kept as a separate list rather than a key on the parsed data, so there is no way for a
# filesystem path to be picked up by something that walks the snapshot's own fields.
instances, inst_dirs, broken = [], [], []
for d in dirs:
    snap = d / "SNAPSHOT.json"
    if not d.is_dir():
        print(f"build-board: skipped {d} — no such directory.", file=sys.stderr)
        continue
    if not snap.is_file():
        # The off switch. Absent from the board entirely, by design.
        print(f"build-board: skipped {d} — no SNAPSHOT.json (off the board).", file=sys.stderr)
        continue
    try:
        data = json.loads(snap.read_text(encoding="utf-8"))
        if not isinstance(data, dict):
            raise ValueError("top level is not an object")
    except (ValueError, OSError, UnicodeDecodeError) as exc:
        # The DIRECTORY NAME, never the path: this page can be published, and an
        # absolute path leaks the operator's home directory and username for no
        # reader benefit. The stderr line above still carries the full path, where
        # the person who can fix it is the only one reading.
        broken.append((dirname(d) or str(d), type(exc).__name__ + ": " + str(exc)))
        print(f"build-board: {d}/SNAPSHOT.json is malformed — rendering a note.", file=sys.stderr)
        continue
    data["_dir"] = dirname(d) or str(d)   # name, not path — see the note above
    # str(), not just truthiness: a non-string group (say 5) survives a `not` test and
    # then makes the awaiting sort compare int with str, which raises TypeError.
    data["group"] = str(data.get("group") or "") or dirname(d).removeprefix("_ai-bridge-") or str(d)
    instances.append(data)
    inst_dirs.append(d)

def tolist(v):
    return v if isinstance(v, list) else []

def todict(v):
    return v if isinstance(v, dict) else {}

def toint(v, default=0):
    """Every number in a snapshot is untrusted input. A syntactically valid file can
    still carry `"tasks": "many"`, and a bare int() there raises ValueError before a
    single byte is written — so ONE drifted instance would blank the board for every
    other instance, breaking the header's promise that a malformed snapshot is a
    visible card rather than a crash. Coerce, never trust."""
    try:
        return int(v)
    except (TypeError, ValueError):
        return default

# ---------------------------------------------------------------- the board
TONE = {"blocked": "stop", "review": "signal", "in-review": "signal",
        "done": "ok", "in-progress": "accent"}
PENDING = ("draft", "ready", "blocked")
RUNNING = ("in-progress", "in-review", "review")
TERMINAL = ("done", "cancelled")

# ---------------------------------------------------------------- other owners
#
# WHY THERE IS A SECOND SECTION AT ALL, AND WHY IT IS NOT A SECOND SNAPSHOT.
#
# Artifact publishing is ACCOUNT-SCOPED: the update path needs an artifact the account
# owns, and no share level grants it, so exactly one account can ever publish to a given
# URL. Two humans sharing a bundle therefore cannot share one published board — each
# publishes their own, to their own URL — and a board that shows only its owner's work is
# half a board. The cross-owner half has to come from something both clones actually
# have.
#
# THAT IS GIT, AND ONLY GIT. `SNAPSHOT.json` is gitignored and untracked, so no clone
# ever holds another clone's; reaching for one would read a file that is never there.
# `projects/*/project.md` and `projects/*/tasks/*.md` ARE tracked. Reading those is also
# one derivation closer to the source of truth than a snapshot is, and reading them at
# HEAD rather than from the working tree means the section shows what you have PULLED —
# never your own uncommitted edits to a document you do not own.
#
# KEYED TO THE SHA, NOT TO A CLOCK. The instinct here was a 15- or 30-minute refresh, and
# it is the wrong primary trigger in both directions: this section can only change when
# HEAD moves, so a timer re-reads for nothing every minute you do not pull and shows a
# stale section the moment you do. The SHA is exact, free to read and cheap to compare.
# The wall clock survives as a FALLBACK for one case only, described at `others_for`.
#
# THE OWNERS ARE NAMED, ON A PAGE THAT GETS PUBLISHED. That is a decision, not an
# oversight — see write-snapshot.sh's header, which now carries `owner` for exactly this,
# and /knowledge/findings/board-owner-identity-named-not-redacted.md. The section is
# collapsed by default because it is CONTEXT rather than your queue; the names are in the
# HTML whether it is open or shut, so the collapse is ergonomics and never a privacy
# control. The footer says so in as many words, because a reader who sees a closed block
# should not conclude the names are hidden.
#
# EVERYTHING READ HERE IS UNTRUSTED TEXT, exactly as a snapshot is: same human-written
# documents, arriving through git instead of through the writer. It goes through the same
# e(), it renders only bundle-relative paths, and none of it reaches a <script>.
OTHERS_CACHE = ".board-others.json"
OTHERS_SCHEMA = "ai-bridge other-owners cache v1"
OTHERS_TTL = 900          # seconds — the FALLBACK only; see others_for()


def read_obj(path):
    """A JSON object from a file, or {} — never an exception and never a non-dict.

    Same shape as the config read in resolve_dirs, and for the same reason: a file whose
    top level is a list or a string parses fine and then has no .get, and an
    AttributeError here would end the run in a traceback instead of a documented
    fallback.
    """
    try:
        v = json.loads(path.read_text(encoding="utf-8"))
    except (ValueError, OSError, UnicodeDecodeError):
        return {}
    return v if isinstance(v, dict) else {}


def who_and_default(d):
    """(this clone's login, defaultOwner) for one instance directory.

    TWO DIFFERENT READS, on purpose, and SCHEMA.md → "Per-machine config overrides" is
    the one place that set is listed. `ownerGithubUser` answers "who is this clone?", so
    the gitignored local file wins over the tracked one — on a shared bundle a tracked
    value would make both clones claim the same identity. `defaultOwner` answers "who
    owns unowned work?", is only correct while BOTH clones agree, and is therefore read
    from the TRACKED file only: a local override there is precisely the disagreement it
    exists to prevent.
    """
    tracked = read_obj(d / "instance.config.json")
    local = read_obj(d / "instance.config.local.json")
    me = local.get("ownerGithubUser") or tracked.get("ownerGithubUser") or ""
    return str(me).strip(), str(tracked.get("defaultOwner") or "").strip()


def owner_of(p, default_owner):
    """SCHEMA.md's resolution, steps 2-4: the project's `owner:`, else `defaultOwner`,
    else nobody.

    Step 1 — a task's own `owner:` — is deliberately not applied. This board partitions
    by PROJECT, and a per-task override is a dispatch concern; honouring it here would
    split one project across two sections, which is less readable than the thing it fixes.
    """
    return str(p.get("owner") or "").strip() or default_owner


def is_mine(owner, me):
    """Unowned work is everybody's (SCHEMA.md step 4), and the comparison is
    case-insensitive, as SCHEMA.md requires.

    With no configured human (`me` empty) an OWNED project is NOT mine: this clone cannot
    prove the name is its own, which is the same refusal the dispatch gate makes. It
    still renders — under its owner, in the section below — so nothing disappears.
    """
    return not owner or owner.lower() == me.lower()


def git(d, *args):
    """One local git read, or None.

    Never raises and never blocks the render: a directory that is not a repository, a git
    that is not installed, a repository with no commits, and a call that times out are
    all "no second section", not a failed page.
    """
    try:
        r = subprocess.run(("git", "-C", str(d)) + args,
                           stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=30)
    except (OSError, subprocess.SubprocessError):
        return None
    return r.stdout.decode("utf-8", "replace") if r.returncode == 0 else None


FM_LINE = re.compile(r"^([A-Za-z_][A-Za-z0-9_-]*):[ \t]*(.*)$")


def frontmatter(text):
    """The scalar frontmatter keys of an OKF document.

    Same contract as write-snapshot.sh's awk, so the two halves of the board agree on
    what "unreadable" means: a document that does not OPEN with `---`, or opens and never
    closes, yields nothing rather than a guess. Scalars only — this reads four fields
    (title, status, kind, owner) and has no business parsing lists.
    """
    lines = text.split("\n")
    if not lines or lines[0].strip() != "---":
        return {}
    fm = {}
    for line in lines[1:]:
        if line.strip() == "---":
            return fm
        m = FM_LINE.match(line)
        if not m:
            continue
        v = m.group(2).strip()
        if len(v) > 1 and v[0] == v[-1] and v[0] in "\"'":
            v = v[1:-1]                      # one layer of quotes, as fmfield() strips
        if m.group(1) in ("status", "kind", "owner"):
            v = v.split("#")[0].strip()      # an enum's trailing comment is not the value
        fm[m.group(1)] = v
    return {}                                # opened and never closed: unreadable


def others_from_head(d, me, default_owner):
    """Every OTHER owner's projects, read from the tracked documents at this clone's HEAD.

    `-z` on the listing is load-bearing: without it git quotes any path with a non-ASCII
    or special character, and the quoted form is not a path you can hand back to
    `git show`. One `show` per document, and only for projects that turn out not to be
    this clone's — a project.md is read to learn the owner, its tasks only if the answer
    is somebody else.
    """
    listing = git(d, "ls-tree", "-r", "-z", "--name-only", "HEAD", "--", "projects")
    if listing is None:
        return None                          # no HEAD to read: no section at all
    projects, tasks = {}, {}
    for path in listing.split("\0"):
        parts = path.split("/")
        if len(parts) == 3 and parts[2] == "project.md":
            projects[parts[1]] = path
        elif (len(parts) == 4 and parts[2] == "tasks" and path.endswith(".md")
                and parts[3] not in ("index.md", "log.md")):
            tasks.setdefault(parts[1], []).append(path)
    out = []
    for slug in sorted(projects):
        blob = git(d, "show", "HEAD:" + projects[slug])
        if blob is None:
            continue
        fm = frontmatter(blob)
        owner = owner_of(fm, default_owner)
        if is_mine(owner, me):
            continue                         # rendered above, from the snapshot
        done = running = pending = 0
        for tpath in sorted(tasks.get(slug, [])):
            tblob = git(d, "show", "HEAD:" + tpath)
            if tblob is None:
                continue
            st = frontmatter(tblob).get("status", "")
            if st in TERMINAL:
                done += 1
            elif st in RUNNING:
                running += 1
            else:
                pending += 1
        out.append({"owner": owner, "slug": slug, "title": fm.get("title") or slug,
                    "status": fm.get("status", ""),
                    "done": done, "running": running, "pending": pending})
    return out


def others_for(d, me, default_owner):
    """The section's data, cached against the HEAD SHA.

    The cache is a gitignored file in the instance directory, and it carries the identity
    it was computed FOR: a clone that changes its `ownerGithubUser` partitions the board
    differently, so a cache keyed on the SHA alone would keep answering for the old human.

    THE WALL CLOCK IS HERE, AND ONLY HERE, and it is a fallback rather than a schedule.
    When the SHA cannot be read at all — no git on the machine, a directory that is not a
    repository, a repository with no commits yet, a `.git` momentarily unavailable under a
    sync or a worktree operation, or a call that times out under load — recomputing
    returns nothing, and writing that nothing to the cache would drop every other owner
    off the published page until the next pull. So a RECENT cached answer is served
    instead, and a cache entry without a SHA is never written: an unkeyed entry is worth
    nothing to the next run. Nothing here re-reads on a timer while a SHA is available.
    """
    head = (git(d, "rev-parse", "HEAD") or "").strip()
    cache = d / OTHERS_CACHE
    hit = read_obj(cache)
    usable = (hit.get("_schema") == OTHERS_SCHEMA and isinstance(hit.get("owners"), list)
              and hit.get("me") == me and hit.get("default") == default_owner)
    if usable and head and hit.get("head") == head:
        return hit["owners"]
    if usable and not head and time.time() - toint(hit.get("at")) < OTHERS_TTL:
        return hit["owners"]
    owners = others_from_head(d, me, default_owner)
    if owners is None:
        return []
    if head:
        try:
            cache.write_text(json.dumps({"_schema": OTHERS_SCHEMA, "head": head,
                                         "me": me, "default": default_owner,
                                         "at": int(time.time()), "owners": owners}),
                             encoding="utf-8")
        except (OSError, UnicodeEncodeError):
            pass          # a read-only instance still renders; it just re-reads next time
    return owners


WORDING = {
    "approve": ("Approve", "go", "APPROVED — go ahead."),
    "discuss": ("Let’s discuss", "", "I want to discuss this before you proceed."),
    "reject": ("Reject", "no", "REJECTED — do not proceed."),
}

TABLE_HEAD = """<title>__TITLE__</title>
<meta name="viewport" content="width=device-width, initial-scale=1">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=IBM+Plex+Sans:wght@400;500;600&family=IBM+Plex+Mono:wght@400;500;600&display=swap">
<style>
/* Full light palette on BARE :root — no colour is ever defined only inside a media
   or [data-theme] block. Dark redefines the same tokens twice: once for the system
   preference (guarded so an explicit light choice wins), once for an explicit choice. */
:root{
  --ground:#f4f6f7; --surface:#fff; --sunk:#eceff1; --raise:#f8fafb;
  --ink:#15181d; --muted:#5c6470; --dim:#89919c; --line:#dde2e6;
  --accent:#0f6b66; --signal:#9c560d; --ok:#2c6647; --stop:#a03a32;
  --shadow:0 1px 2px rgba(20,26,34,.05),0 8px 24px -16px rgba(20,26,34,.22);
}
@media (prefers-color-scheme:dark){ :root:not([data-theme="light"]){
  --ground:#0e1013; --surface:#171a1e; --sunk:#1e2227; --raise:#1b1f24;
  --ink:#e5e8eb; --muted:#98a1ac; --dim:#6d7681; --line:#262b31;
  --accent:#44b0a7; --signal:#dda157; --ok:#5fac82; --stop:#dc7a70;
  --shadow:0 1px 2px rgba(0,0,0,.4),0 8px 24px -16px rgba(0,0,0,.7);
}}
:root[data-theme="dark"]{
  --ground:#0e1013; --surface:#171a1e; --sunk:#1e2227; --raise:#1b1f24;
  --ink:#e5e8eb; --muted:#98a1ac; --dim:#6d7681; --line:#262b31;
  --accent:#44b0a7; --signal:#dda157; --ok:#5fac82; --stop:#dc7a70;
  --shadow:0 1px 2px rgba(0,0,0,.4),0 8px 24px -16px rgba(0,0,0,.7);
}
*,*::before,*::after{box-sizing:border-box}
body{background:var(--ground);color:var(--ink);margin:0;
  font:400 15px/1.55 "IBM Plex Sans",ui-sans-serif,system-ui,sans-serif;
  -webkit-font-smoothing:antialiased;-webkit-text-size-adjust:100%}
.board{width:min(100% - 2rem, 104rem);margin:0 auto;display:flex;flex-direction:column;
  gap:1.1rem;padding:clamp(1.4rem,3vw,2.6rem) 0 4rem}
/* Prose keeps a readable measure even when the board is wide — only the data grows. */
.sub,.where,footer p{max-width:52rem}

.mast{display:flex;flex-wrap:wrap;gap:1.3rem;justify-content:space-between;
  align-items:flex-end;padding-bottom:1rem;border-bottom:2px solid var(--ink)}
h1{font-size:clamp(1.5rem,3.6vw,1.95rem);font-weight:600;letter-spacing:-.02em;
  margin:0;text-wrap:balance}
.sub{color:var(--muted);margin:.28rem 0 0;font-size:.82rem;
  font-family:"IBM Plex Mono",ui-monospace,monospace}
.tally{display:flex;gap:1.5rem;margin:0}
.tally div{display:flex;flex-direction:column-reverse;gap:.1rem}
.tally dt{font-size:.65rem;text-transform:uppercase;letter-spacing:.09em;
  color:var(--dim);margin:0}
.tally dd{margin:0;font:600 1.5rem/1 "IBM Plex Mono",ui-monospace,monospace;
  color:var(--muted);font-variant-numeric:tabular-nums}
.tally .live dd,.tally .live dt{color:var(--signal)}

.rail{border-left:.22rem solid var(--signal);border-radius:0 6px 6px 0;
  background:color-mix(in srgb,var(--signal) 8%,var(--surface));padding:.9rem 1rem}
.rail h2{margin:0 0 .7rem;font-size:.68rem;text-transform:uppercase;letter-spacing:.1em;
  color:var(--signal);font-weight:600}
.rail ul{list-style:none;margin:0;padding:0;display:flex;flex-direction:column;gap:.6rem}
.ask{display:flex;flex-direction:column;gap:.5rem;padding:.65rem .75rem;
  background:var(--surface);border:1px solid var(--line);border-radius:5px}
/* A snapshot that could not be parsed is a VISIBLE note here too, not just a line on
   stderr — one broken instance must not be able to disappear quietly. Named
   `.snapnote` rather than `.note`, because `.c.note` below is the advisor-concern
   pill and a bare `.note` rule would restyle it. */
.snapnote{border:1px solid var(--stop);border-left:.22rem solid var(--stop);
  border-radius:5px;padding:.7rem .85rem;font-size:.84rem;color:var(--muted);
  background:var(--surface)}
.line{display:flex;flex-wrap:wrap;gap:.3rem .55rem;align-items:baseline}
.what{font-weight:500}
.verb{font:600 .64rem/1.7 "IBM Plex Mono",ui-monospace,monospace;text-transform:uppercase;
  letter-spacing:.08em;color:var(--signal);white-space:nowrap}
.where{width:100%;font-size:.75rem;color:var(--dim)}
.acts{display:flex;flex-wrap:wrap;gap:.35rem}
/* The title line IS the toggle: click anywhere on it for the explanation. A caret
   marks it as expandable, since a heading that happens to be clickable is invisible. */
.why summary{cursor:pointer;list-style:none}
.why summary::-webkit-details-marker{display:none}
.why summary::after{content:"▸";color:var(--dim);font-size:.7rem;
  transition:transform .15s;display:inline-block;margin-left:.15rem}
.why[open] summary::after{transform:rotate(90deg)}
.why summary:hover .what{color:var(--accent)}
.why summary:hover::after{color:var(--accent)}
.why p{margin:.55rem 0 0;color:var(--muted);line-height:1.5;max-width:52rem;
  font-size:.83rem;border-left:2px solid var(--line);padding-left:.6rem}
button{font:500 .78rem/1 "IBM Plex Sans",sans-serif;cursor:pointer;border-radius:4px;
  padding:.38rem .62rem;border:1px solid var(--line);background:var(--raise);
  color:var(--ink)}
button:hover{border-color:var(--accent)}
button.go{border-color:var(--ok);color:var(--ok)}
button.no{border-color:var(--stop);color:var(--stop)}

/* Collapsed by default: no `open` attribute, and no script involved. */
.proj{background:var(--surface);border:1px solid var(--line);border-radius:6px;
  box-shadow:var(--shadow)}
.phead{display:flex;flex-wrap:wrap;gap:.5rem .9rem;align-items:center;cursor:pointer;
  padding:.8rem .95rem;list-style:none;border-radius:6px}
.phead::-webkit-details-marker{display:none}
.phead::before{content:"\\25B8";color:var(--dim);font-size:.8rem;flex-shrink:0;
  transition:transform .15s}
.proj[open] .phead::before{transform:rotate(90deg)}
.phead:hover{background:var(--raise)}
.phead:hover .ptitle{color:var(--accent)}
.ptitle{font-weight:600;letter-spacing:-.01em;flex:1 1 18rem;min-width:0;font-size:.97rem}
.counts{display:flex;gap:.35rem;flex-wrap:wrap}
.c{font-size:.72rem;color:var(--muted);border:1px solid var(--line);border-radius:3px;
  padding:.15rem .42rem;white-space:nowrap}
.c b{font-weight:600;color:var(--ink);font-variant-numeric:tabular-nums}
.c.ok b{color:var(--ok)} .c.run b{color:var(--accent)} .c.wait b{color:var(--signal)}
.tag{font-size:.65rem;text-transform:uppercase;letter-spacing:.07em;color:var(--muted);
  background:var(--sunk);border-radius:3px;padding:.14rem .38rem;white-space:nowrap}
.body{padding:0 .95rem .9rem;border-top:1px solid var(--line)}

/* Finished projects: sunk below a divider, desaturated, and labelled. Still fully
   readable when expanded — dimming the summary, not the contents. */
.sep{font-size:.66rem;text-transform:uppercase;letter-spacing:.11em;color:var(--dim);
  font-weight:600;margin:.9rem 0 -.35rem;display:flex;align-items:center;gap:.6rem}
.sep::after{content:"";flex:1;height:1px;background:var(--line)}
.proj.fin{background:transparent;box-shadow:none;border-style:dashed}
.proj.fin .ptitle{color:var(--muted);font-weight:500}
.proj.fin .phead{opacity:.8}
.proj.fin[open] .phead{opacity:1}
/* Another owner's work: the same card, set in mono and dimmed like a finished one,
   because it is context rather than your queue. It is NOT hidden — the name is in the
   markup whether this block is open or shut; the collapse is ergonomics. */
.proj.other{background:transparent;box-shadow:none;border-style:dashed}
.proj.other .ptitle{font-family:"IBM Plex Mono",ui-monospace,monospace;font-size:.9rem;
  color:var(--muted)}
.proj.other[open] .ptitle{color:var(--ink)}
.c.q{color:var(--signal);border-color:color-mix(in srgb,var(--signal) 40%,var(--line))}
.c.q b{color:var(--signal)}
.c.note{color:var(--dim);border-style:dashed}
.c.note b{color:var(--muted)}
.c.done-tag{color:var(--ok);border-color:color-mix(in srgb,var(--ok) 45%,var(--line));
  background:color-mix(in srgb,var(--ok) 9%,transparent);font-weight:600}

.scroll{overflow-x:auto}
table{border-collapse:collapse;width:100%;font-size:.86rem;min-width:min(100%,33rem)}
th{text-align:left;font-size:.64rem;text-transform:uppercase;letter-spacing:.09em;
  color:var(--dim);font-weight:500;padding:.7rem .45rem .35rem;
  border-bottom:1px solid var(--line);white-space:nowrap}
th.r,td.r{text-align:right}
th:not(:first-child),td:not(:first-child){width:1%;white-space:nowrap}
th:first-child,td:first-child{width:auto}
td{padding:.4rem .45rem;vertical-align:baseline;
  border-bottom:1px solid color-mix(in srgb,var(--line) 55%,transparent)}
tbody tr:last-child td{border-bottom:0}
tr.flight td:first-child{box-shadow:inset 2px 0 0 var(--accent)}
.tid{color:var(--dim);font-size:.74rem;margin-right:.4rem;
  font-family:"IBM Plex Mono",ui-monospace,monospace;font-variant-numeric:tabular-nums}
td:first-child{overflow-wrap:break-word}
.tbtn{background:none;border:0;padding:0;font:inherit;color:inherit;text-align:left;
  border-bottom:1px dotted var(--dim);border-radius:0}
.tbtn:hover{color:var(--accent);border-color:var(--accent)}
.promote{font-size:.68rem;padding:.14rem .4rem;margin-left:.4rem}
/* The Q count is a button only when there is something to ask about. Its TEXT is
   never on this page — the allowlist forbids question text, and AWAITING.md has it. */
.qbtn{font-family:"IBM Plex Mono",ui-monospace,monospace;font-size:.8rem;font-weight:600;
  color:var(--signal);border-color:color-mix(in srgb,var(--signal) 45%,var(--line));
  background:color-mix(in srgb,var(--signal) 10%,transparent);padding:.1rem .45rem;
  font-variant-numeric:tabular-nums}
.qs{display:inline-flex;gap:.2rem}
.qbtn:hover{border-color:var(--signal);background:color-mix(in srgb,var(--signal) 18%,transparent)}
button.ghost{font-size:.72rem;padding:.28rem .5rem;color:var(--muted)}
.deps{white-space:normal!important}
/* Two refs must not wrap: reserve button.dep's own box (3ch digits + .7rem pad +
   2px border, each) times two, a ", " separator in that same monospace context,
   and this td's own .9rem horizontal padding (box-sizing:border-box counts it) —
   sized from the pill's and td's own CSS, not eyeballed. 3+ refs may still wrap
   past that width, and a single ref never sees this min-width. */
.deps:has(button.dep:nth-of-type(2)){font-family:"IBM Plex Mono",ui-monospace,monospace;
  font-size:.74rem;min-width:calc(2*(3ch + .7rem + 2px) + 2ch + .9rem)}
button.dep{font-family:"IBM Plex Mono",ui-monospace,monospace;font-size:.74rem;
  padding:.08rem .35rem;color:var(--muted);background:var(--sunk);border-color:transparent;
  font-variant-numeric:tabular-nums}
button.dep:hover{color:var(--accent);border-color:var(--accent);background:transparent}
.delivs{padding:.85rem .95rem 0}
.delivs h3{margin:0 0 .5rem;font-size:.64rem;text-transform:uppercase;letter-spacing:.09em;
  color:var(--dim);font-weight:600}
.delivs ul{list-style:none;margin:0;padding:0;display:flex;flex-wrap:wrap;gap:.4rem}
button.dlv{font-family:"IBM Plex Mono",ui-monospace,monospace;font-size:.76rem;
  padding:.28rem .55rem;color:var(--muted);background:var(--sunk);border-color:transparent}
button.dlv:hover{color:var(--accent);border-color:var(--accent);background:transparent}
.state{font-size:.7rem;text-transform:uppercase;letter-spacing:.06em;color:var(--muted);
  white-space:nowrap}
.state.ok{color:var(--ok)} .state.signal{color:var(--signal)}
.state.stop{color:var(--stop)} .state.accent{color:var(--accent)}
.dim{color:var(--dim)} .sig{color:var(--signal);font-weight:500}
td.r,td.dim{font-family:"IBM Plex Mono",ui-monospace,monospace;font-size:.8rem}
td a{color:var(--accent);text-decoration:none;border-bottom:1px solid transparent;
  white-space:nowrap;font-family:"IBM Plex Mono",ui-monospace,monospace;font-size:.8rem}
td a:hover,td a:focus-visible{border-bottom-color:currentColor}
:focus-visible{outline:2px solid var(--accent);outline-offset:2px}

.toast{position:fixed;left:50%;bottom:1.3rem;transform:translateX(-50%);z-index:9;
  background:var(--ink);color:var(--ground);font-size:.83rem;padding:.55rem .9rem;
  border-radius:5px;box-shadow:var(--shadow);max-width:calc(100vw - 2rem);
  opacity:0;pointer-events:none;transition:opacity .18s}
.toast.on{opacity:1}
footer{border-top:1px solid var(--line);padding-top:.9rem}
footer p{margin:0 0 .5rem;font-size:.76rem;color:var(--dim);max-width:45rem}
footer p:last-child{margin:0}
code{font-family:"IBM Plex Mono",ui-monospace,monospace;font-size:.93em}
@media (prefers-reduced-motion:reduce){*{transition:none!important}}
</style>"""

TABLE_SCRIPT = r"""<script>
// The ONLY scripted behaviour: put a button's text on the clipboard. Everything
// else — layout, collapse, links — is markup and CSS, so scripting off costs the
// page nothing but this.
(function(){
  var el;
  function toast(m){
    if(!el){ el=document.createElement('div'); el.className='toast'; document.body.appendChild(el); }
    el.textContent=m; el.classList.add('on');
    clearTimeout(toast.t); toast.t=setTimeout(function(){ el.classList.remove('on'); },3000);
  }
  document.addEventListener('click', function(e){
    var b = e.target.closest ? e.target.closest('[data-copy]') : null;
    if(!b) return;
    e.preventDefault();
    var text = b.getAttribute('data-copy'), what = b.getAttribute('data-what') || 'Text';
    var ok = function(){ toast(what + ' copied — paste it to Claude'); };
    var bad = function(){ toast('Copy failed. Select this instead: ' + text); };
    if(navigator.clipboard && navigator.clipboard.writeText){
      navigator.clipboard.writeText(text).then(ok, legacy);
    } else { legacy(); }
    function legacy(){
      try{
        var ta=document.createElement('textarea'); ta.value=text;
        ta.style.position='fixed'; ta.style.top='-1000px'; document.body.appendChild(ta);
        ta.select(); var done=document.execCommand('copy'); document.body.removeChild(ta);
        done ? ok() : bad();
      }catch(err){ bad(); }
    }
  });
})();
</script>"""


# The shape a deliverable path may have, spelled ONCE and in the positive. Read this
# before adding another `if <something bad> in p: return None` below.
#
# FOUR ROUNDS OF REVIEW DEFEATED THE OTHER DESIGN, which anchored the PREFIX and then
# listed the characters it knew were bad. That asks "does this START right, and does it
# lack the one byte I thought of?" — so every round closed the reported vector and left
# the next one, and the simplest of them needed no exotic input at all:
#
#     /projects/p/deliverables/report.md /Users/somebody/Desktop/report.md
#
# Correct prefix, no `..`, no `#`, TWO paths in one value — rendered whole into a
# `data-copy` and labelled `report.md`, so nothing looked wrong. The value was never
# required to be a single, whole, well-formed path. Now it is:
#
#   segment  what a FILENAME may be made of, stated as a set rather than as the set's
#            complement: a word character (`\w` — Unicode-aware on a `str`, so a letter
#            in any script, a digit, `_`), then any run of word characters, `.`, `-`
#            and `+`.
#   marks    `\w` does NOT include a COMBINING MARK (Unicode category M), and a comment
#            here once claimed it did. macOS hands back decomposed filenames, so a
#            stamped `Übersicht.md` can arrive as `U` + U+0308 + `bersicht.md` and was
#            silently dropped — the "loses a real entry" class three rounds went to
#            eliminate. Marks are therefore removed from the string the shape is TESTED
#            on and kept in the string that is RETURNED. Stripping is safe because a
#            mark is decoration on the preceding base character: category M contains no
#            separator, no whitespace, no `#`, `:` or `/`, so removing them can only
#            turn a value the shape would have rejected into one it accepts, never
#            change what the accepted value points AT. It is also complete where
#            NFC-normalising is not — Devanagari matras, Thai vowel signs and Hebrew
#            points have no precomposed form and would still have been dropped.
#   whole    `/projects/<slug>/deliverables/` then one or more segments — and
#            fullmatch(), which is what makes "no trailing remainder" part of the shape
#            instead of one more separate check.
#
# WHY POSITIVE AND NOT ONE MORE EXCLUSION. The class here used to be `[^/\s#]+`, which is
# a denylist wearing a whitelist's clothes: it still had to have thought of every
# dangerous byte, and it had not thought of `:` —
#
#     /projects/p/deliverables/deck.md:/Users/victim/.ssh/id_rsa
#
# renders whole into a `data-copy`, labelled `id_rsa`. Appending `:` to the exclusions
# would be one more round of the same move. Stated positively there is nothing to
# enumerate: `/`, every kind of whitespace, `#`, `:`, `@`, `\`, ZWSP, BOM, U+2028 and the
# bidi overrides are all simply not in the set, and the next separator nobody has thought
# of is not in it either.
#
# TWO PERMISSIONS THAT CARRY RISK, NAMED RATHER THAN LEFT IMPLICIT:
#   · `.` — required (every extension has one). `.` and `..` as WHOLE segments are
#     impossible by construction, because a segment must begin with a word character,
#     so traversal needs no rule of its own.
#   · a word character in any script, plus any combining mark — so two filenames can be
#     homoglyphs (Cyrillic `а` vs Latin `a`), or differ only by an invisible mark, and
#     look alike on the page. Containment is unaffected: the value still resolves inside
#     this project's own `deliverables/`, which is the guarantee this guard makes.
#     Excluding non-ASCII instead would silently drop a legitimately stamped
#     `Übersicht.md`, which is the more likely event by far.
#
# WHAT IT COSTS, said plainly: a deliverable whose filename contains a space, `&`, `'`,
# `(`, `%` or `,` is dropped from the panel — visibly, because the count is computed from
# the same filtered list. Closeout resolves these names from `artifacts:` and a file can
# be renamed; an absolute path rendered onto a published page cannot be recalled.
#
# THE SLUG IS A SEGMENT LIKE ANY OTHER, which is the point: it is checked by the same
# rule rather than interpolated into a prefix and trusted, so `/projects/../deliverables/x`
# no longer walks out of the bundle when a hand-written SNAPSHOT.json says its slug is `..`.
DELIV_SEG = r"\w[\w.+-]*"
DELIV_PATH = re.compile(
    r"/projects/(%s)/deliverables/%s(?:/%s)*" % (DELIV_SEG, DELIV_SEG, DELIV_SEG))


def bundle_deliverable(path, slug):
    """The path itself when it is a whole, well-formed deliverable path belonging to
    THIS project — otherwise None, and the entry is dropped from the panel AND from the
    count with it, never dropped from one while the other still reports it.

    NESTED paths (a research project shipping an exported site, e.g.
    `deliverables/site/index.html`) are deliberately allowed: they are still inside this
    project's own deliverables directory, which is the guarantee this guard keeps.

    Why the renderer re-checks at all, when closeout verified each path on disk before
    stamping it (close-project-folder.sh): the same rule href() applies to a PR URL's
    scheme. A writer having restricted what it collects is never a reason for the reader
    to trust it — a human can hand-edit project.md, and SNAPSHOT.json is a file on disk
    this renderer reads back without knowing who wrote it.
    """
    value = str(path or "")
    probe = "".join(c for c in value if unicodedata.category(c)[0] != "M")
    # THE SHAPE IS TESTED ON `probe`, SO THE SLUG IS PINNED ON `value`. Stripping marks
    # from the whole string also strips them from the slug, and `m.group(1) == slug`
    # would then read `/projects/p̈/deliverables/x.md` as project `p`'s own deliverable —
    # a button pointing at a NEIGHBOURING project's directory. Comparing the original
    # prefix closes that, and the slug is still checked as one well-formed segment by
    # the fullmatch above (which is what rejects a `..` or a `a/b` slug), so this is an
    # identity check on top of the shape check, not a return to trusting a prefix.
    if not DELIV_PATH.fullmatch(probe):
        return None
    return value if value.startswith("/projects/%s/deliverables/" % slug) else None


def short_ref(slug, tid):
    """`ai-bridge-v3/tasks/task-005` — what a human pastes back.

    Drops `projects/` (constant, so it carries no information) and `.md` (the
    document type is never in question). KEEPS `tasks/`: a project also holds
    `phases/`, `sources/` and `deliverables/`, so this segment is the one that says
    which kind of document is meant, and it costs six characters. The `task-` prefix
    makes it technically redundant today — but only while tasks are the only thing
    with a copy button.
    """
    return "%s/tasks/%s" % (slug, tid)


def task_number(tid):
    """Just the number — `task-003-some-slug` -> `003`.

    Falls back to the id with `task-` stripped when there is no number to find, so an
    id that does not follow the convention still renders something identifiable rather
    than an empty cell.
    """
    m = re.match(r"^task-0*(\d+)", tid or "")
    if m:
        return m.group(1).zfill(3)
    return (tid or "")[5:] if (tid or "").startswith("task-") else (tid or "")


Q_BUTTON_CAP = 24


def q_range(t):
    """1..N for a task's open questions, N capped.

    `open_questions` is a COUNT the writer derives from the task document, and a button
    is emitted per question — so a drifted `"open_questions": 900000000` is a valid int
    that renders for hours and produces a page nobody can open. toint() cannot catch
    that: the type is right and the value is absurd. The cap is deliberately far above
    any real task (a document with two dozen open questions has a different problem) and
    is not a silent truncation of anything that occurs in practice.
    """
    return range(1, min(toint(t.get("open_questions")), Q_BUTTON_CAP) + 1)


def explain(verb, p, t, hint):
    """One short paragraph saying what this verb means and why THIS item is here.

    Composed from the verb plus counts the snapshot already carries — never from a
    task description, a document body, or the text of a question or blocker, none
    of which the snapshot forwards. So this adds no field to the published-page
    allowlist. Kept under ~280 characters on purpose: enough to act on, short
    enough to read without deciding to read it.
    """
    ts = [todict(x) for x in tolist(p.get("tasks"))]
    ph = todict(p.get("phase_progress"))
    nd = sum(1 for x in ts if x.get("status") == "done")
    nc = sum(1 for x in ts if x.get("status") == "cancelled")
    if verb == "close":
        bits = "%d done" % nd + (", %d cancelled" % nc if nc else "")
        phase = (", %d/%d phases complete" % (toint(ph.get("done")), toint(ph.get("total")))
                 if toint(ph.get("total")) else "")
        return ("Every task here has finished (%s%s), so there is nothing left to build. "
                "Closing rolls the project up, drops it off the active list and proposes "
                "marking its objective achieved. Nothing is deleted — run %s."
                % (bits, phase, hint or "/close-project"))
    if verb == "approve":
        return ("A draft is never dispatched. This one has been refined and its acceptance "
                "criteria are written, so it is waiting on you to promote it to ready — "
                "after which an agent can pick it up. Approving does not start work "
                "immediately; the next loop tick does.")
    if verb in ("answer", "question"):
        qs = [str(q) for q in tolist(t.get("open_question_text"))]
        if qs:
            # An escalated concern is prefixed `advisor:` by the project-manager. Say
            # once, in prose, where it came from — then strip the marker, so the
            # question does not read "Q1: advisor: …".
            def strip(q):
                return q[len("advisor:"):].lstrip() if q.lower().startswith("advisor:") else q
            escalated = any(q.lower().startswith("advisor:") for q in qs)
            lead = ("The advisor raised this and the project-manager could not settle it from "
                    "the documents, so it came to you. ") if escalated else ""
            body = "  ".join("Q%d: %s" % (i, strip(q)) for i, q in enumerate(qs, 1))
            return lead + body + ("  — an unanswered question blocks promotion, so the "
                                  "loop will not dispatch this task.")
        # No text carried (the default) — fall through to the count wording.
        n = toint(t.get("open_questions"))
        one = n == 1
        return ("There %s %d open question%s on this task, and an unanswered question blocks "
                "promotion — the loop will not dispatch it. The board never carries question "
                "text; use the Q button in the task table to copy a prompt that opens "
                "%s, or read AWAITING.md, which does carry %s."
                % ("is" if one else "are", n, "" if one else "s",
                   "it" if one else "them", "it" if one else "them"))
    if verb == "merge":
        prs = [todict(x) for x in tolist(t.get("prs"))]
        nums = ", ".join("#%s" % x.get("number") for x in prs)
        one = len(prs) == 1
        return ("The work is built and its pull request%s open and reviewed. It needs your "
                "merge — agents deliberately do not merge their own work."
                % (" (%s) is" % nums if one else
                   ("s (%s) are" % nums if nums else "s are")))
    if verb == "unblock":
        return ("An agent stopped because something outside its control is in the way — a "
                "missing credential, a failing dependency, a decision it cannot make. The "
                "task document records what. It will not retry until you clear it.")
    return ("This item is waiting on a human decision. The task document has the detail; "
            "the board deliberately does not carry it.")


def render_table():
    groups = [s.get("group", "?") for s in instances]
    if len(groups) == 1:
        name = groups[0].split(".")[0].replace("-", " ").replace("_", " ").title()
        title = "%s Bridge Board" % name
    else:
        title = "Bridge Board"

    rows, asks, others = [], [], []
    n_tasks = n_done = 0
    for s, d in zip(instances, inst_dirs):
        g = s.get("group", "?")
        me, default_owner = who_and_default(d)
        others += others_for(d, me, default_owner)
        for p in tolist(s.get("projects")):
            p = todict(p)
            # Somebody else's project renders ONCE, below, from HEAD. Skipping it here is
            # what stops the two sections from showing the same work twice — the failure
            # a naive "append a second section" produces, and one that looks fine.
            #
            # The one thing this drops: a project owned by somebody else that exists in
            # YOUR working tree and is not committed yet. It is skipped here and HEAD has
            # never heard of it, so it appears nowhere. That is the honest answer rather
            # than a gap — an uncommitted document is not something the other clone can
            # see either, and committing it is what publishes it to both boards.
            if not is_mine(owner_of(p, default_owner), me):
                continue
            ts = [todict(t) for t in tolist(p.get("tasks"))]
            # "Done" is all-tasks-terminal, or the project saying so. A project with no
            # tasks yet is NOT done — it has not started.
            done_proj = bool(p.get("status") == "done" or (
                ts and all(t.get("status") in TERMINAL for t in ts)))
            rows.append((g, p, done_proj))
            for t in ts:
                n_tasks += 1
                if t.get("status") == "done":
                    n_done += 1
                if t.get("awaiting"):
                    asks.append((g, p, t, None))
                elif t.get("open_questions"):
                    # A question only produces an `awaiting` verb while the task is a
                    # DRAFT (write-snapshot.sh, `case draft)`), so a question on a
                    # ready or in-progress task is invisible in the queue. Surfacing
                    # it here fixes that at the presentation layer, without touching
                    # the AWAITING.md contract that awaiting-queue.test.sh pins.
                    asks.append((g, p, dict(t, awaiting="question"), None))
            if p.get("awaiting_close"):
                asks.append((g, p, {"awaiting": "close", "title": "all tasks terminal",
                                    "id": ""}, "/close-project " + str(p.get("slug") or "")))

    # Finished projects sink to the bottom; among themselves and among the live ones
    # the snapshot's order is preserved, so the list does not reshuffle between renders.
    rows.sort(key=lambda r: r[2])

    head = [TABLE_HEAD.replace("__TITLE__", e(title))]
    o = ['<div class="board">']

    o.append('<header class="mast"><div><h1>%s</h1>' % e(title))
    stamps = sorted(str(s.get("generated_at") or "") for s in instances if s.get("generated_at"))
    if stamps:
        o.append('<p class="sub">Snapshot %s UTC</p>'
                 % e(stamps[-1].replace("T", " ").replace("Z", "")))
    o.append("</div><dl class=\"tally\">")
    o.append('<div><dt>Projects</dt><dd>%d</dd></div>' % len(rows))
    o.append('<div><dt>Done</dt><dd>%d/%d</dd></div>' % (n_done, n_tasks))
    o.append('<div class="%s"><dt>Awaiting you</dt><dd>%d</dd></div>'
             % ("live" if asks else "", len(asks)))
    o.append("</dl></header>")

    for d, msg in broken:
        o.append('<div class="snapnote"><strong>Unreadable snapshot.</strong> '
                 '<code>%s/SNAPSHOT.json</code> could not be parsed, so that instance is '
                 'not on the board. Re-run <code>scripts/write-snapshot.sh</code> there. '
                 '<br>%s</div>' % (e(d), e(msg)))

    # ---- the decision rail: one click copies a complete prompt --------------
    if asks:
        o.append('<section class="rail"><h2>Awaiting you</h2><ul>')
        for g, p, t, hint in asks:
            # str() on the id, not just on the title: a snapshot carrying `"id": 5`
            # parses, so the malformed-snapshot path never sees it, and `5 + " ("` then
            # raised TypeError — which meant NO FILE WAS WRITTEN AT ALL, one drifted
            # instance blanking the published board for every healthy one. Same class as
            # toint() above, and the reason nothing here concatenates snapshot data raw.
            tid_txt = str(t.get("id") or "")
            what = (tid_txt + " (" + str(t.get("title") or "") + ")") if tid_txt else str(t.get("title") or "")
            where = g + " › " + str(p.get("title") or "")
            o.append('<li class="ask"><details class="why"><summary class="line">'
                     '<span class="verb">%s</span><span class="what">%s</span>'
                     % (e(t.get("awaiting")), e(t.get("title"))))
            o.append('<span class="where">%s%s</span></summary>'
                     % (e(where), " · <code>%s</code>" % e(hint) if hint else ""))
            o.append('<p>%s</p></details>' % e(explain(t.get("awaiting"), p, t, hint)))
            o.append('<div class="acts">')
            if tid_txt:
                ref = short_ref(str(p.get("slug") or ""), tid_txt)
                o.append('<button class="ghost" data-copy="%s" data-what="Task reference">'
                         "copy task ref</button>" % e(ref))
                for i in q_range(t):
                    o.append('<button class="qbtn" data-copy="%s" data-what="Q%d handle" '
                             'title="Copy &quot;%s Q%d:&quot; ready to type your answer after">'
                             "answer Q%d</button>"
                             % (e("%s Q%d: " % (ref, i)), i, e(ref), i, i))
            for verdict, (label, cls, lead) in ([] if t.get("awaiting") == "question"
                                                else WORDING.items()):
                msg = '%s Re the "%s" item on %s in %s.' % (lead, t.get("awaiting"), what, where)
                if verdict == "approve" and hint:
                    msg += " Run %s." % hint
                elif verdict == "discuss":
                    msg += " Tell me the trade-off you see and what you recommend."
                elif verdict == "reject":
                    msg += " Record why on the task and move on."
                o.append('<button class="%s" data-copy="%s" data-what="%s">%s</button>'
                         % (cls, e(msg), e(label + " prompt"), e(label)))
            o.append("</div></li>")
        o.append("</ul></section>")

    # ---- one <details> per project, collapsed by default -------------------
    n_fin = sum(1 for r in rows if r[2])
    for idx, (g, p, fin) in enumerate(rows):
        if fin and (idx == 0 or not rows[idx - 1][2]):
            o.append('<h2 class="sep">Finished · %d</h2>' % n_fin)
        tasks = [todict(t) for t in tolist(p.get("tasks"))]
        nd = sum(1 for t in tasks if t.get("status") == "done")
        nr = sum(1 for t in tasks if t.get("status") in RUNNING)
        nw = sum(1 for t in tasks if t.get("status") in PENDING)
        ph = todict(p.get("phase_progress"))
        # From project.md's `deliverable_paths:` ONLY — never `tasks/`, never a
        # filesystem listing of `deliverables/`. That is what keeps this panel
        # compatible with the done-project skip (write-snapshot.sh): a retained
        # project's `tasks` list above is already empty, and this does not change
        # that. Reject anything that is not this project's own bundle-relative
        # shape before it ever reaches a button.
        dps = [d for d in (bundle_deliverable(x, str(p.get("slug") or ""))
                           for x in tolist(p.get("deliverable_paths"))) if d]
        o.append('<details class="proj%s"><summary class="phead">' % (" fin" if fin else ""))
        o.append('<span class="ptitle">%s</span><span class="counts">' % e(p.get("title")))
        if fin:
            o.append('<span class="c done-tag">✓ done</span>')
        o.append('<span class="c ok"><b>%d</b> done</span>' % nd)
        if not fin:
            o.append('<span class="c run"><b>%d</b> in progress</span>' % nr)
            o.append('<span class="c wait"><b>%d</b> pending</span>' % nw)
        nq = sum(toint(t.get("open_questions")) for t in tasks)
        if nq:
            o.append('<span class="c q"><b>%d</b> question%s</span>'
                     % (nq, "" if nq == 1 else "s"))
        na = sum(toint(t.get("advisor_notes")) for t in tasks)
        if na:
            # Deliberately NOT in the signal colour and deliberately not in the
            # awaiting rail: an untriaged advisor concern is the loop's inbox, not
            # yours. It becomes a question only if the PM escalates it.
            o.append('<span class="c note" title="Advisor concerns the loop has not '
                     'triaged yet — not waiting on you"><b>%d</b> concern%s</span>'
                     % (na, "" if na == 1 else "s"))
        if toint(ph.get("total")):
            o.append('<span class="tag">%d/%d phases</span>'
                     % (toint(ph.get("done")), toint(ph.get("total"))))
        if dps:
            o.append('<span class="tag">%d deliverable%s</span>'
                     % (len(dps), "" if len(dps) == 1 else "s"))
        o.append("</span></summary>")

        o.append('<div class="body"><div class="scroll"><table><thead><tr>'
                 "<th>Task</th><th>State</th><th>Role</th><th>Depends on</th>"
                 "<th class=\"r\">Q</th><th>PR</th>"
                 "</tr></thead><tbody>")
        for t in tasks:
            tid = str(t.get("id") or "")
            short = tid[5:] if tid.startswith("task-") else tid
            st = str(t.get("status") or "")
            o.append('<tr%s>' % (' class="flight"' if t.get("in_flight") else ""))
            o.append('<td><span class="tid">%s</span>' % e(short))
            o.append('<button class="tbtn" data-copy="%s" data-what="Task reference">%s</button>'
                     % (e(short_ref(str(p.get("slug") or ""), tid)), e(t.get("title"))))
            if st == "draft":
                promo = ("In the ai-bridge instance, promote %s from draft to ready: review its "
                         "acceptance criteria, tighten any that are not testable, then set "
                         "status: ready." % short_ref(str(p.get("slug") or ""), tid))
                o.append('<button class="promote" data-copy="%s" data-what="Promotion prompt">'
                         "promote → ready</button>" % e(promo))
            o.append("</td>")
            o.append('<td><span class="state %s">%s</span></td>' % (TONE.get(st, ""), e(st)))
            o.append('<td class="dim">%s</td>' % e(t.get("assignee") or "—"))
            deps = [str(d) for d in tolist(t.get("depends_on"))]
            if deps:
                # Show the short id, the same form the Task column shows, and copy the
                # full bundle-relative path — a dependency is most useful as a thing to
                # go read.
                o.append('<td class="deps">%s</td>' % ", ".join(
                    '<button class="dep" data-copy="%s" data-what="Path" title="%s">%s</button>'
                    % (e(short_ref(str(p.get("slug") or ""), d)), e(d),
                       e(task_number(d))) for d in deps))
            else:
                o.append('<td class="dim">—</td>')
            q = toint(t.get("open_questions"))
            if q:
                # One handle per question. The snapshot carries only a COUNT, and
                # SCHEMA.md requires every entry to be numbered Q1, Q2, … — so the
                # labels are derivable without ever carrying question text. See the
                # caveat in the footer: this assumes the numbering starts at 1 and is
                # contiguous, which the schema asks for but does not enforce.
                ref = short_ref(str(p.get("slug") or ""), tid)
                o.append('<td class="r"><span class="qs">%s</span></td>' % "".join(
                    '<button class="qbtn" data-copy="%s" data-what="Q%d handle" '
                    'title="Copy &quot;%s Q%d:&quot; ready to type your answer after">'
                    'Q%d</button>' % (e("%s Q%d: " % (ref, i)), i,
                                      e(ref), i, i)
                    for i in q_range(t)))
            else:
                o.append('<td class="r dim">—</td>')
            # The http/https rule applies here too: a PR URL is a link only on that
            # scheme, and anything else is inert text. This layout used to write the
            # URL straight into the href — one of the two hardening rules the second
            # script did not carry (see the header).
            cells = []
            for x in (todict(x) for x in tolist(t.get("prs"))):
                u = href(x.get("url"))
                if u:
                    cells.append('<a href="%s" target="_blank" rel="noopener noreferrer">#%s</a>'
                                 % (e(u), e(x.get("number"))))
                else:
                    cells.append('<span class="dim">#%s (link withheld: not http/https)</span>'
                                 % e(x.get("number")))
            o.append('<td>%s</td></tr>' % (" ".join(cells) if cells
                                           else '<span class="dim">—</span>'))
        o.append("</tbody></table></div>")
        if dps:
            # Reuses the ONE clipboard helper the page already ships (TABLE_SCRIPT,
            # `[data-copy]`/`data-what`) — no second script, no new event handler.
            # The label shown is just the filename; the full bundle-relative path is
            # both the copied text and the hover title, so a reader can see what a
            # click will paste before clicking it.
            o.append('<div class="delivs"><h3>Deliverables · %d</h3><ul>' % len(dps))
            for dp in dps:
                fname = dp.rsplit("/", 1)[-1]
                o.append('<li><button class="dlv" data-copy="%s" data-what="Deliverable path" '
                         'title="%s">%s</button></li>' % (e(dp), e(dp), e(fname)))
            o.append("</ul></div>")
        o.append("</div></details>")

    # ---- the other owners, one collapsed block each, from git HEAD ----------
    # NAMED and COLLAPSED. No `open` attribute, and no script — the same <details> the
    # projects above use, for the same reasons. The collapse is ergonomics: this is
    # context, not your queue. It hides nothing, and the footer says so.
    by_owner = {}
    for x in others:
        x = todict(x)
        by_owner.setdefault(str(x.get("owner") or "?"), []).append(x)
    if by_owner:
        o.append('<h2 class="sep">Other owners · %d</h2>' % len(by_owner))
        for who in sorted(by_owner, key=lambda s: s.lower()):
            entries = by_owner[who]
            nd = sum(toint(x.get("done")) for x in entries)
            nr = sum(toint(x.get("running")) for x in entries)
            nw = sum(toint(x.get("pending")) for x in entries)
            o.append('<details class="proj other"><summary class="phead">')
            o.append('<span class="ptitle">%s</span><span class="counts">' % e(who))
            o.append('<span class="c"><b>%d</b> project%s</span>'
                     % (len(entries), "" if len(entries) == 1 else "s"))
            o.append('<span class="c ok"><b>%d</b> done</span>' % nd)
            o.append('<span class="c run"><b>%d</b> in progress</span>' % nr)
            o.append('<span class="c wait"><b>%d</b> pending</span>' % nw)
            o.append("</span></summary>")
            o.append('<div class="body"><div class="scroll"><table><thead><tr>'
                     "<th>Project</th><th>Where</th><th>State</th>"
                     "<th class=\"r\">Done</th><th class=\"r\">Running</th>"
                     "<th class=\"r\">Pending</th></tr></thead><tbody>")
            for x in entries:
                st = str(x.get("status") or "")
                # BUNDLE-RELATIVE, always. `/projects/<slug>/` is the same form the copy
                # buttons above use and the only kind of path allowed to reach this page:
                # a published board must not carry anybody's home directory.
                o.append('<tr><td>%s</td><td class="dim"><code>/projects/%s/</code></td>'
                         '<td><span class="state %s">%s</span></td>'
                         '<td class="r">%d</td><td class="r">%d</td><td class="r">%d</td></tr>'
                         % (e(x.get("title")), e(x.get("slug")), TONE.get(st, ""), e(st),
                            toint(x.get("done")), toint(x.get("running")),
                            toint(x.get("pending"))))
            o.append("</tbody></table></div>"
                     "<p class=\"where\">Read from the tracked documents at this clone’s "
                     "current <code>HEAD</code> — never from another clone’s snapshot, "
                     "which is gitignored and never present here. It moves when you pull, "
                     "and it never shows uncommitted work.</p></div></details>")

    o.append('<footer><p>Derived from each instance’s <code>SNAPSHOT.json</code> and '
             "<strong>as sensitive as the task documents it comes from</strong>. Titles are "
             "human-written free text; no customer PII belongs in a task title, and so none "
             "belongs here. Task descriptions, document bodies, question and blocker text, "
             "author email addresses and out-of-bundle paths are never carried.</p>"
             "<p>Project owners are carried, on purpose, so this board can tell your work "
             "from theirs — so the <strong>names of other owners are on this page whether "
             "their section is open or shut</strong>. Collapsing it is for reading comfort, "
             "not privacy.</p>"
             "<p>A browser cannot open a local file, so a task copies its <em>bundle-relative</em> "
             "path for you to paste — prefix it with your instance directory. Decision "
             "buttons copy a prompt; the bundle, not this page, is where a decision is "
             "recorded.</p></footer></div>")
    o.append(TABLE_SCRIPT)
    return head, o, len(asks)


# ---------------------------------------------------------------- write it out
if not instances:
    # Publishing an empty page is not useful, so nothing is written at all. Exit 0
    # anyway: an instance off the board is a choice, not an error.
    print("build-board: no readable snapshot; nothing written.", file=sys.stderr)
    sys.exit(0)

head, parts, n_awaiting = render_table()

head_html = "\n".join(head)
body_html = "\n".join(parts)
if STANDALONE:
    doc = ('<!doctype html>\n<html lang="en">\n<head>\n<meta charset="utf-8">\n'
           + head_html + "\n</head>\n<body>\n" + body_html + "\n</body>\n</html>\n")
else:
    doc = head_html + "\n" + body_html + "\n"
OUT.write_text(doc, encoding="utf-8")
print(f"build-board: wrote {OUT} — {len(instances)} instance(s), "
      f"{n_awaiting} awaiting, {len(broken)} unreadable snapshot(s).")
PY
