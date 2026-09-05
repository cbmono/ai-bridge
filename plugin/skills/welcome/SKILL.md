---
name: welcome
description: The AI Bridge welcome screen — banner, `check` (state that could be wrong), or `fix` (repairs the idempotent tier only). Reports facts, never rules; `fix` never writes config files and never clears a tick lock.
argument-hint: "[check|fix]  omit for the banner"
allowed-tools: Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/ai-bridge.sh:*), Bash(pwd), Bash(ls:*), Read, Glob
---

Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/ai-bridge.sh $ARGUMENTS` from the bundle root and **relay
its output verbatim**. `$ARGUMENTS` is empty, `check` or `fix` — nothing else; anything else is a
typo and the script will say so rather than guess.

That is the whole skill. Every fact, every warning and every repair lives in the
script, so the answer is the same whether a human runs it in a terminal or a session runs
it here — and there is no second copy of any of it in this file to drift from the first.

**Relay it as markdown — never inside a code fence, and never re-wrapped.** The script
already emitted the emphasis this channel renders: piped output is styled with `**bold**`
on the `⚠` lines of `check`, and on the banner's identity line and its two table headers,
because a relayed answer is rendered as markdown and ANSI does not survive the relay at all
(measured — 0 of 4 escape bytes reached the reader). A fence turns that emphasis back into
literal asterisks and hands the human the flat page the styling exists to replace.

**And relay every other byte unaltered, the spaces included.** The banner's two tables are
fixed-width: their `FROM` column is a column only as long as nothing re-flows the lines and
nothing adds or removes a character. The script's side of that bargain is that no cell
contains a character markdown treats as active — an `<address>` in the owner row was eaten
as an autolink once, and that row's `FROM` sat two columns left of every other's.

## The three forms

| You ran | It does |
|---|---|
| `/welcome` | `exec`s the SessionStart hook, so you get **that** banner, not a copy of it |
| `/welcome check` | reports state that could be wrong, each line a fact with its evidence |
| `/welcome fix` | repairs the **idempotent** tier only, and prints every other tier without acting |

## What you must not do with the output

- **Do not summarise the `⚠` lines away.** They are facts about this instance, and the
  human is the one who acts on most of them.
- **Do not act on a tier the script declined to act on.** If `fix` printed a line and did
  not repair it, that is the design, not an omission for you to finish. In particular:
  never revert, stage or rewrite `instance.config.json` / `instance.config.local.json`
  (an uncommitted value there is routinely a decision somebody made minutes ago), and
  never remove or rewrite `.tick-lock` / `.tick-lock.claim` (`${CLAUDE_PLUGIN_ROOT}/scripts/tick-lock.sh
  release` is the human's override — a long tick is not a dead one).
- **Do not turn it into a rules recital.** This skill reports facts that can be false.
  It does not remind anyone of a convention, and adding a line that reads the same on a
  healthy instance and a broken one is what it exists not to do.

## Outside an instance, or the script is missing

- Not an instance root at all (no `instance.config.json`)? Say which directory this is,
  name any instance directories you can see nearby, and stop — never improvise a banner.
- A bundle, but `${CLAUDE_PLUGIN_ROOT}/scripts/ai-bridge.sh` is missing? That is a broken
  plugin install, not a bundle problem — say so, and give the repair (`/plugin install
  ai-bridge@ai-bridge`, then restart Claude Code) rather than improvising the checks by
  hand.
