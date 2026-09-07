---
name: init
description: Create a new AI Bridge bundle, refresh an existing one, or convert a symlink-era bundle in place. Data only — a bundle it stamps carries no machinery and no link into any checkout.
argument-hint: "<dir>  [--refresh-seeds] [--with-objectives] [--normalise-config] [--owner L] [--email A] [--repos-root D]"
disable-model-invocation: true
allowed-tools: Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/init-bundle.sh:*), Bash(pwd), Bash(ls:*), Read, Glob
---

Run this, from anywhere, and **relay its output verbatim**:

```
bash ${CLAUDE_PLUGIN_ROOT}/scripts/init-bundle.sh $ARGUMENTS
```

`$ARGUMENTS` is the bundle directory, optionally followed by `--refresh-seeds`,
`--with-objectives`, `--normalise-config`, or one of `--owner <login>` / `--email
<address>` / `--repos-root <dir>` (see "When it says `needs`"). No directory means the
current one. That is the whole skill: every
decision, every guard and every line of output lives in the script, so a human running it
in a terminal and a session running it here get the same answer, and there is no second
copy here to drift.

**The plugin carries the installer.** No clone of this template is needed on the machine,
and a plugin update is what updates it.

## What it does, in one table

| | |
|---|---|
| **Creates** | a bundle at `<dir>`: seed docs, `instance.config.json` + `.local.json`, the derived-ignore lines, `AWAITING.md` and `SNAPSHOT.json`, and `repos/` linked from `reposRoot` |
| **Refreshes** | the same bundle again — idempotent, seeds only what is ABSENT, and never overwrites a value already there |
| **Converts** | a bundle stamped by the old `install.sh`: every machinery symlink into a template checkout is removed, the managed `.gitignore` machinery block is retired, and the data is untouched |
| **Creates on request** | `objectives/`, with `--with-objectives`. It is an optional layer (`SCHEMA.md` → type: Objective) — a project normally carries its own `success_criteria` — so a plain stamp makes no such directory, and an existing one is data and never touched |
| **Brings up to date** | an existing bundle, by running the welcome check-and-fix pass after the stamp — the idempotent tier only, and the same refusals: config files and tick locks are reported, never written. Seed drift is 3-way merged, decidable conflicts are resolved on the rule that decides them, and anything else is reported for you |
| **Reports** | config findings across `instance.config.json` and `instance.config.local.json` — a key in the wrong file, a seed key missing, keys out of order. Report-only unless you say yes at the prompt or pass `--normalise-config`, and then it moves, adds and reorders without ever changing a value, and leaves the tracked file **staged** |

**The only symlinks a stamped bundle holds are under `repos/`**, and those point at the
group's product repos, never at a checkout of this repo.

## The first stamp asks one question

At a terminal, on a **first** stamp only, it offers to collect the team's GitHub logins
and commit emails (`people`, `defaultOwner`, and this clone's `ownerGithubUser`). One
batched prompt, nothing written until it is confirmed. **Not at a terminal — a background
tick, a script — it skips and prints how to set the three values by hand.** Never on a
refresh, and never over a value already there.

## When it says `needs`, ask once and re-run

A clone with no `instance.config.local.json` gets one written: the script **derives**
`ownerGithubUser`, `authorEmail` and `reposRoot` and prints what it wrote. Anything it
could not derive it prints as a `needs` line naming the key and its flag.

- **Ask the human only for the keys on `needs` lines — one batched question, all of them
  at once.** Never ask for a value the script derived and printed; it already has it.
- Then re-run the same command with the flags for exactly those keys, e.g.
  `bash ${CLAUDE_PLUGIN_ROOT}/scripts/init-bundle.sh <dir> --owner <login> --email <address>`.
- **No `needs` line means nothing to ask.** A bundle whose local file already exists is
  left alone — the script says so — and the flags do not apply to it.

## What you must not do with the output

- **Do not act on a line it declined to act on.** A `stale` line names retired content
  that is the human's to keep or delete; the script prints the exact `rm` and does not
  run it. A `keep` line names a symlink of the human's own.
- **Do not act on a `CONFLICT` yourself.** A hand-diverged seed file is the only copy of
  a decision somebody made; the script reports it, names the diff, and stops. So do you.
- **`AUTONOMY.md` disappearing is a real change, not noise.** If the conversion removed
  it, delegated authority is off and the bundle is back to ask-first. Relay that line and
  the opt-back-in it prints (`/plugin install ai-bridge-yolo@ai-bridge` — the companion
  that ships the file); never re-create the file yourself.

## Afterwards

`instance.config.json` needs the group's `org` before anything else works;
`instance.config.local.json` is written for you, from what the machine already knows.
Then `/ai-bridge:welcome` for the banner, and `/ai-bridge:dispatch` for the loop.
**Run this command again after every plugin update** — it is the one that brings a
bundle up to the installed plugin.

If the directory is not a bundle and was not meant to be one, say which directory it is
and stop — never stamp somewhere on a guess.
