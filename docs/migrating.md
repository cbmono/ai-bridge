# Migrating an existing install

For anyone running AI Bridge from **before the plugin** — an instance whose
`.claude/commands/` still holds symlinks, and whose commands are the bare `/pm-loop`,
`/new-project`, `/answer`, … Nothing errors. Those files simply stopped being shipped,
and a dangling command still registers, so the instance offers `/pm-loop` and fails when
you run it.

**There are two ways forward and they are not equally safe.** Pick with the table, then
read only that section.

---

## The decision rule

**Upgrade in place. That is the default, and it is the right answer for almost everyone.**

| | **A — upgrade in place** | **B — fresh re-home** |
|---|---|---|
| The folder | you keep it | you stamp a **new** one, then delete the old |
| git history | **kept in full** — every task, review and decision the loop has recorded | left behind in the backup; the new folder starts at commit 1 |
| `projects/` and `knowledge/` | **never touched.** They are bundle *content*, not machinery, and no step of the upgrade reads or writes them | copied by hand, and every copy is a chance to miss one |
| What it costs | one report-first script | six steps, the last of which deletes something |
| Pick it when | you want the plugin era, and that is all | you **deliberately** want a clean folder — a new group, a rename, a bundle you are re-homing |

**B is not a better A.** It buys exactly one thing — a folder with no history — and pays
for it with the history. If you cannot name why you want that, you want A.

**Either way, the plugin is `ai-bridge`.** `ai-bridge-v2` was the transition name and
ships for one more version as a stub that says so. Every command is namespaced —
`/ai-bridge:dispatch`, `/ai-bridge:welcome`, `/ai-bridge:new-project`, and the
[rest](../README.md#commands) — and so is every role agent
(`ai-bridge:software-engineer`), because a bare name does not resolve.

---

## Path A — upgrade in place (the default)

**Written once, in one place, and not repeated here:**
[operations.md § Moving a stamped instance into the plugin era](operations.md#moving-a-stamped-instance-into-the-plugin-era--run-this-once).

Four steps — plugin install (per machine), `./upgrade.sh <instance>` to report,
`--apply`, restart. It re-stamps, so the sweep below removes the dangling symlink-era
command links for you, and `install.sh` never removes instance content.

**Nothing on the [checklist](#what-you-must-not-lose-and-what-must-not-travel) below
applies to you**, because on path A nothing moves. It is there for path B.

---

## Path B — fresh re-home, in six steps

Placeholders throughout: `<group>` is the group folder, `<new-folder>` the instance
directory you are stamping, `<user>` your GitHub login.

### 1. Back up the whole bundle — as a git repo, because it is one

There is no bespoke backup tool and there should not be: your instance is a git repo, so
git's own two answers are the backup.

```bash
cd ~/workspace/<group>/_ai-bridge-<group>
git status --short                                  # nothing outstanding before you start
git add -A && git commit -m "chore: pre-migration checkpoint" || echo "nothing to commit"
git push                                            # a remote is already a backup

# a second copy that survives the original being deleted — either form is complete
mkdir -p ~/backups                                  # git bundle will not create it
git clone --no-hardlinks . ~/backups/_ai-bridge-<group>-backup
git bundle create ~/backups/_ai-bridge-<group>.bundle --all
```

`--no-hardlinks` is not optional: a plain local clone shares object files with the
original, and you are about to delete the original.

**Then check the backup, before anything is deleted:**

```bash
git -C ~/backups/_ai-bridge-<group>-backup log --oneline -1
git bundle verify ~/backups/_ai-bridge-<group>.bundle
```

> "Bundle" is overloaded here. `git bundle` is git's single-file archive; an *OKF
> Knowledge Bundle* is what your instance **is**. This step makes the first out of the
> second.

### 2. Install the plugin — once per MACHINE

The two lines are in [README § Install step
1](../README.md#1-install-the-plugin--once-per-machine). Per machine, not per instance:
if this machine already has `ai-bridge`, skip the step. If it has `ai-bridge-v2`, install
`ai-bridge`, uninstall the old one from `/plugin` → Manage, and relaunch Claude Code.

### 3. Stamp the new folder

```bash
mkdir -p ~/workspace/<group>/<new-folder>
~/workspace/ai-bridge/install.sh ~/workspace/<group>/<new-folder>
```

Name it `_ai-bridge-<group>` unless you are deliberately renaming
([README § 3](../README.md#3-make-the-instance-directory)).

**Answer the roster prompt.** A first stamp at a terminal offers to collect
`<github-login> <commit-email>` pairs, and the same prompt writes this clone's
`instance.config.local.json` — the one file that must **not** come from the old folder.
Step 4 overwrites `instance.config.json` on top of what the prompt puts there, and that
is fine; the local file is what you are here for.

### 4. Copy the content over

**Copy from git, not from disk.** `git archive` emits exactly the tracked files, so every
derived and per-machine file on the do-not-copy list is excluded by construction rather
than by you remembering.

```bash
old=~/workspace/<group>/_ai-bridge-<group>
new=~/workspace/<group>/<new-folder>

git -C "$old" archive HEAD projects knowledge objectives log.md instance.config.json \
  | tar -x -C "$new"

# everything tracked, so you can see what you are choosing to leave behind
git -C "$old" ls-files | cut -d/ -f1 | sort -u
```

Drop any path that does not exist in `HEAD` — `git archive` fails on an unknown one. A
`cp -R` works too, but it copies the derived files as well, and then the
[checklist](#what-you-must-not-lose-and-what-must-not-travel) is yours to run by hand.

**Not on that list: `CLAUDE.md` and `README.md`.** They are seed content and yours to
edit, but the old copies still say `/pm-loop`. Port *your* edits onto the freshly stamped
ones — don't copy the files whole and re-import the dead command names you are migrating
away from.

### 5. Re-stamp, then re-home the git repo

Same shell as step 4 — `$old` and `$new` are still set.

```bash
# a) the SECOND stamp: reposRoot is real now, so repos/ is linked, and the managed
#    .gitignore block is refreshed against the content you just copied
~/workspace/ai-bridge/install.sh "$new"

# b) a fresh repo — the old history stayed in the backup, deliberately
cd "$new"
git init && git add -A && git commit -m "chore: bootstrap control panel"
gh repo create <user>/<new-folder> --private --source=. --push

# c) the documents, against the schema the machinery now ships
scripts/validate-bundle.sh
```

Two things this step is for:

- **The second stamp is not redundant.** Repo linking is skipped while `reposRoot` is the
  seeded placeholder, so it could not have run in step 3 — the real `reposRoot` only
  arrived with step 4.
- **The derived indexes come back on the first LIVE tick**, not now. Root `index.md` and
  `projects/*/index.md` are rewritten by the PM's curate step; a DRY RUN stops before it.
  If `install.sh` reports either as *tracked*, run the `git rm --cached` line it prints —
  they are views, and a committed view is a merge conflict every tick.

### 6. Verify

```bash
cd "$new" && claude
```

Then, in the session:

| Run | What proves it worked |
|---|---|
| `/ai-bridge:welcome` | the banner renders and names **this** instance. *Unknown command* accuses the **plugin**, never the stamp |
| `/ai-bridge:welcome check` | each line a fact with its evidence — read the `⚠` lines |
| `/ai-bridge:dispatch`, then say **DRY RUN** | it reports what it *would* dispatch and spawns nothing. Your projects and tasks appearing **by name** is the proof `projects/` arrived intact |

Only once this passes do you delete anything — see
[below](#uninstalling-the-old-symlink-era-install).

---

## What you must not lose, and what must not travel

### Keep — this is the work

| Path | Why |
|---|---|
| `projects/` | every project, task, deliverable and per-project `log.md` |
| `knowledge/` | `Finding`s, `Service`s, `Runbook`s, `Team`s, `Reference`s — **including `knowledge/index.md`**, which is tracked and curated, not derived |
| `objectives/` | the `Objective` documents projects hang off |
| `log.md` | the instance ledger |
| `instance.config.json` | `org`, `reposRoot`, `worktreeRoot`, `people`, `defaultOwner`, `maxPrLoc` — tracked, and therefore shared, and therefore it travels |
| `CLAUDE.md`, `README.md` | seed content, **yours since the day it was copied** — but port your edits onto the fresh copies rather than copying the old files, which still name `/pm-loop` |
| `AUTONOMY.md` | the **decision** it encodes, never the file itself — it is a symlink, see below |

### Do not copy — every one of these regenerates

| Path | What it is |
|---|---|
| `instance.config.local.json` | **per machine**: `ownerGithubUser`, `authorEmail`, `models`/`roleTiers`. Copying it to another machine is how a bundle ends up authoring as somebody else. `install.sh` writes a fresh one |
| `.tick-lock`, `.tick-lock.claim` | the dispatch lock, **per clone**. A copied lock is one nobody holds and nothing releases |
| `.tick-state` | the tick delta cache, per clone |
| `.board-live/`, `.board-others.json`, `board.html`, `SNAPSHOT.json` | the board's derived output and its caches |
| `AWAITING.md` | the derived awaiting-you queue, rewritten every tick |
| root `index.md`, `projects/*/index.md` | derived navigation, rewritten every tick. **One exception:** a *retained* project's `index.md` is written once at closeout and is committed |
| `repos/` | a derived symlink view of the group's repos; `scripts/link-repos.sh` rebuilds it |
| `scripts/`, `.claude/`, `SCHEMA.md`, `CONVENTIONS.md`, `AUTONOMY.md`, `agents/` | **absolute symlinks into the template.** Copying one gets you a link into the old folder's template, or a dangling one. The stamp re-links all of them |
| `tmp/`, `*.bak.*` | scratch, and the files `install.sh` moved aside |

**`AUTONOMY.md` is a symlink, so its per-instance state is a deletion, not an edit.**
Delegated autonomy is honoured when the file is present and every project is `gated` when
it is absent, so an instance that had `rm`'d it was making a decision. Make it again:
`rm <new-folder>/AUTONOMY.md` after the stamp — machinery is re-linked unconditionally,
so it comes back on **every** stamp. On path A `upgrade.sh` samples the file first and
reports the re-enable with the `rm` to undo it; on path B nothing will.
([autonomy.md](autonomy.md#the-onoff-switch-is-one-file))

---

## Uninstalling the old symlink-era install

| Path | What removes the old command links |
|---|---|
| **A** | `install.sh`'s **step 2b sweep**, which `upgrade.sh` runs for you. It deletes a link only when it points into this template's `plugin/` **and** its target is gone — so exactly the retired commands, and nothing of yours. One `retire <path> (no longer shipped by the template)` line each ([operations.md § 2](operations.md#2-retiring-content-swept-vs-reported)) |
| **B** | you delete the whole old folder, so there is nothing to sweep |

**Step 2b is not cosmetic and it is not optional.** Without the re-stamp, the dangling
files still register and the instance keeps offering commands that fail.

Deleting the old folder — last, and only once step 6 passed:

```bash
# optional: detach the machinery first, so what is left is only your content
~/workspace/ai-bridge/install.sh --uninstall ~/workspace/<group>/_ai-bridge-<group>
rm -rf ~/workspace/<group>/_ai-bridge-<group>
```

`--uninstall` removes only the symlinks it created; real files, `*.bak.*` backups and
your content are left alone. It is not required before the delete — it is there so you
can look at what remains and confirm every last file of it is yours.

**The plugin is not part of any of this.** It is per machine and every instance on that
machine uses it, so do not uninstall `ai-bridge`. Uninstall `ai-bridge-v2` if it is still
listed. The optional `~/.claude` config layer is its own separate thing:
`install.sh --config --uninstall` ([README § Uninstall](../README.md#uninstall)).
