---
name: init
description: Create a new AI Bridge bundle, refresh an existing one, or convert a symlink-era bundle in place. Data only — a bundle it stamps carries no machinery and no link into any checkout.
argument-hint: "<dir>  [--refresh-seeds]"
allowed-tools: Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/init-bundle.sh:*), Bash(pwd), Bash(ls:*), Read, Glob
---

Run this, from anywhere, and **relay its output verbatim**:

```
bash ${CLAUDE_PLUGIN_ROOT}/scripts/init-bundle.sh $ARGUMENTS
```

`$ARGUMENTS` is the bundle directory, optionally followed by `--refresh-seeds`. No
directory means the current one. That is the whole skill: every decision, every guard and
every line of output lives in the script, so a human running it in a terminal and a
session running it here get the same answer, and there is no second copy here to drift.

**It replaces `install.sh`.** No clone of `cbmono/ai-bridge` is needed on the machine —
the plugin carries the installer, and `claude plugin update` is what updates it.

## What it does, in one table

| | |
|---|---|
| **Creates** | a bundle at `<dir>`: seed docs, `instance.config.json` + `.local.json`, the derived-ignore lines, `AWAITING.md` and `SNAPSHOT.json`, and `repos/` linked from `reposRoot` |
| **Refreshes** | the same bundle again — idempotent, seeds only what is ABSENT, and never overwrites a value already there |
| **Converts** | a bundle stamped by the old `install.sh`: every machinery symlink into a template checkout is removed, the managed `.gitignore` machinery block is retired, and the data is untouched |
| **Reports** | seed drift — a seed doc this repo changed since the bundle was stamped. Report-only unless you passed `--refresh-seeds` |

**The only symlinks a stamped bundle holds are under `repos/`**, and those point at the
group's product repos, never at a checkout of this repo.

## The first stamp asks one question

At a terminal, on a **first** stamp only, it offers to collect the team's GitHub logins
and commit emails (`people`, `defaultOwner`, and this clone's `ownerGithubUser`). One
batched prompt, nothing written until it is confirmed. **Not at a terminal — a background
tick, a script — it skips and prints how to set the three values by hand.** Never on a
refresh, and never over a value already there.

## What you must not do with the output

- **Do not act on a line it declined to act on.** A `stale` line names retired content
  that is the human's to keep or delete; the script prints the exact `rm` and does not
  run it. A `keep` line names a symlink of the human's own.
- **Do not re-run it with `--refresh-seeds` because it reported drift.** A 3-way merge
  writes into files the bundle owns. Report the drift, and let the human ask.
- **`AUTONOMY.md` disappearing is a real change, not noise.** If the conversion removed
  it, delegated authority is off and the bundle is back to ask-first. Relay that line and
  the restore command; never re-create the file yourself.

## Afterwards

`instance.config.json` needs the group's `org` and `reposRoot` before anything else works.
Then `/ai-bridge:welcome` for the banner, and `/ai-bridge:dispatch` for the loop.

If the directory is not a bundle and was not meant to be one, say which directory it is
and stop — never stamp somewhere on a guess.
