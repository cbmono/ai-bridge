# Who owns `~/.claude`

**`cbmono/ai-setup` owns `${CLAUDE_CONFIG_DIR:-~/.claude}`. This repo ships three files
into it and nothing else.**

If you are here because a command, hook, output style or skill you wanted is not under
`config/` any more: it is in [`cbmono/ai-setup`](https://github.com/cbmono/ai-setup), and
the fix is to run that repo's `install.sh`, not to add a copy back here. Adding one back
fails `tests/config-ownership.test.sh`, on purpose.

## What was wrong

`config/` was not a sibling of ai-setup's `.claude/` tree — it was a **fork** of it.
Measured 2026-08-23:

| | |
|---|---|
| ai-setup's installable entries | 26 |
| …also shipped by ai-bridge | **24** |
| …of those, diverged | **14**, in *both* directions |
| who decided which copy a machine got | **whichever installer ran last** |

Both installers linked into `${CLAUDE_CONFIG_DIR:-~/.claude}`. Neither knew about the
other. The machine that found this was on ai-bridge's side of the fork — the newer one — so
nothing looked broken; running ai-setup's installer would silently have flipped 24 entries
back to older copies.

**It was not found by review. It was found because two of the fixes that existed only in
this private fork closed secret-exposure paths that the public repo was still shipping:**

- `/acp` ran `git add -A` before scanning, so a tracked `.env` or private key reached the
  index and `git diff --cached` before any guardrail looked at it.
- `deepseek-session.sh` printed eight characters of a live third-party credential in an
  unsuppressible banner on every run.

Those fixes sat in a private fork for weeks. That is the cost being removed here, and it is
not a tidiness argument: a duplicate config layer converts every fix into a fix *one* of
the two copies has.

## The decision

**ai-setup owns the directory.** It is the public defaults repo, it is where consumers
already install from, and moving ownership there is what shrinks ai-bridge — which is what
this repo's current objective is for.

**ai-bridge keeps exactly the paths it PROBES for**, which today is three agents:
`code-architect`, `deep-bug-scan`, `plan-architect`. That is not a taste boundary, it is
the reason `config/` exists at all: this repo's role agents probe for those files with
`test -f`, and a fresh laptop must work after one clone and one install without cloning a
second repo. Everything beyond that set was a convenience that cost an entire second
config layer.

### Consequences, so the direction is not re-derived later

1. **Ownership is about who INSTALLS a path, not about which text survives.** Where the
   two copies had diverged, ai-bridge's was usually newer, so "ai-setup owns it" meant
   ai-setup **received** those fixes. It never meant ai-setup's older copy won.
2. **The divergence was resolved by porting, not by picking a winner.** In both
   directions: ai-setup's `commands/acp.md` was *ahead* of the fork's after its own
   hardening pass, and `hooks/statusline.sh` / `scripts/codegraph-sync.sh` differed only in
   which repo the header names — each copy right about its own repo. A file-wholesale sync
   in either direction would have deleted real work. **Port the fix, never the file.**
3. **The two installers now compose in either order.** ai-setup links top-level
   directories as units, so on any machine that ran it `~/.claude/agents` is a symlink.
   `--config` never writes *through* a symlinked directory (that would put a file inside
   someone else's checkout), but when the entry already resolves through it, the
   requirement — *the file exists on this machine* — is already met, so it reports
   `provided by …` and writes nothing. Before that, `--config` would have exited non-zero
   on the normal configuration.
4. **`CONFIG_MANAGED_TOPS` in `install.sh` is never pruned**, and it is what performed this
   handover: the roots this layer used to ship stay listed, so `--config` retires the
   now-dangling links from the old layer on the next run. Prune them and a retired command
   still registers, a retired hook still exits 127 on every launch.
5. **Neither repo's change is safe alone.** ai-bridge dropping the set before ai-setup
   ships the ported fixes leaves paths installed by nobody — silently, because an absent
   agent is a failed `test -f` and an absent command is a slash command that simply does
   not exist. The two PRs land together.
6. **A DANGLING-LINK AUDIT CANNOT SEE A PATH INSTALLED BY NOBODY.** This is the point in
   this document most likely to be re-derived the hard way, because the audit *looks* like
   the right check and it reports zero. A path that was never linked is **absent**, not
   dangling — so `find … -type l ! -exec test -e {} \;` returning 0 is not evidence that
   nothing was lost. It is not hypothetical, and the order that produces it is specific:

   > on a machine carrying the old layer's link, run **ai-setup's installer first** — it
   > saw a `settings.json`, said "already exists, left alone", and declined — then
   > `git pull` and `--config`, which retired its own now-dangling link. Result:
   > **`~/.claude/settings.json` absent, exit 0, 0 dangling.**

   Gone with it: the whole `permissions.deny` block (`.env*`, ssh keys,
   `.aws/credentials`, `sudo`, `rm -rf ~`), `statusLine`, `outputStyle` and the
   `PostToolUse` hook — recoverable only by re-running ai-setup's installer, which nothing
   prompts. The rule that fixed it lives in ai-setup — **a symlink is not your
   `settings.json`**: it holds a path, not content, so there is nothing of the user's to
   protect, and it is adopted rather than declined. That is
   [`ai-setup#71`](https://github.com/cbmono/ai-setup/pull/71), and it is why that PR lands
   **first**; at ai-setup `main` the installer still declines, so the sentence above is true
   of the pair and not of either half. Checked rather than asserted: the cross-repo group in
   `tests/config-ownership.test.sh` runs ai-setup's own installer from that starting state
   and goes red if the file does not end up pointing at ai-setup.

   The checks that *can* see this class are **presence over an enumerated owned set**, and
   there is now one on each side. **A set is still not enough on its own**, and that is the
   sharpest thing in this document: the loss was not a path leaving a list — the file was
   tracked, named by ai-setup's installer and in its manifest throughout — it was a
   **conditional decline**, a branch taken because our link happened to be sitting there. A
   membership check over derived paths is identical in the broken state and the fixed one,
   and no stricter grep of an installer repairs that: matching `ln -s … DEST/settings.json`
   matches the version that declines too. Only *running* the other installer, from the state
   an existing machine is in, can tell the two apart — which is what the cross-repo group in
   `tests/config-ownership.test.sh` now does. **Never measure order-independence from an
   empty config dir**, either: that is the one starting state in which this failure cannot
   appear.

## What holds the line

| Check | Where | What it fails on |
|---|---|---|
| `tests/config-ownership.test.sh` | here | a `~/.claude` path shipped from this repo that nothing probes for — `settings.json` included, which is the one the scan used to filter out before comparing; a path probed for that is not shipped; `config/opinionated/` coming back, or a tier under a new name; and — when an ai-setup checkout is reachable — an overlap wider than the three agents, a root in `CONFIG_MANAGED_TOPS` that neither layer installs, **and ai-setup's own installer, actually run from the state an existing machine is in, failing to end up providing every root handed to it** (the absent-path class of point 6: no dangling-link audit can see it, and no set can see the conditional decline that caused it) |
| `tests/claude-config-ownership.test.sh` | ai-setup | a path handed over that stops being *installable* from there (its `EXCLUDE`, its top-level linking), and a new entry the manifest has not been told about; and `settings.json` specifically, in all three states a config dir can be in — foreign link, dangling link, real file |
| `tests/config-hardening.test.sh` | ai-setup | any of the ten ported fixes regressing |
| `tests/config-layer.test.sh` | here | the arrow turning two-way, a whole-directory link for a drop-in dir, absence stopping being safe, a write that fails being counted as done — on **both** the link and the sweep halves, on install and on uninstall — and a **read** that fails being counted as an absence: a sweep that retires on a source list it could not fully discover, which is the destructive direction of the same defect and the only one that takes the layer with it |

One note on the first row, because it is a trap the derivation itself fell into:
ai-setup's `EXCLUDE` means *"the generic link loop skips this"*, **not** *"this is not
installed"*. `settings.json` is in that list and is installed by a dedicated branch, so a
set derived from `EXCLUDE` alone misses precisely the path that went missing. The harness
reads ai-setup's installer for excluded paths it names as a destination of its own, and
asserts both halves of that reasoning.

The expected set in the first of those is **derived from the probes**, not hardcoded: add
or delete a `test -f ~/.claude/agents/<x>.md` in `symlink/` and the expectation moves with
it. Both scans are exercised against a synthetic re-forked fixture, so "nothing found"
cannot mean "the scan never fires".

## If you need something that is not here

- **A command / hook / skill on a new machine** → run ai-setup's `install.sh`. That is the
  whole point: one repo installs it, so one repo fixes it.
- **A new agent this repo's own machinery probes for** → add the probe in `symlink/` and the
  file under `config/required/agents/`. `tests/config-ownership.test.sh` expects exactly
  that pairing and will tell you if you do only one half.
- **A fix to a shipped default** → make it in ai-setup. A fix made here would be invisible
  to every consumer, which is the failure this document exists to record.
