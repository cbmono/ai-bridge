---
description: Reprint the SessionStart banner, or report the state of this instance that could be wrong (`check`), or repair only the class that is safe to repair (`fix`). Reports facts, never rules. `fix` never writes config files and never clears a tick lock.
allowed-tools: Bash(scripts/ai-bridge.sh:*), Bash(bash scripts/ai-bridge.sh:*), Bash(pwd)
---

Run `scripts/ai-bridge.sh $ARGUMENTS` from the instance root and **relay its output
verbatim**. `$ARGUMENTS` is empty, `check` or `fix` — nothing else; anything else is a
typo and the script will say so rather than guess.

That is the whole command. Every fact, every warning and every repair lives in the
script, so the answer is the same whether a human runs it in a terminal or a session runs
it here — and there is no second copy of any of it in this file to drift from the first.

**Relay it as markdown — never inside a code fence, and never re-wrapped.** The script
already emitted the emphasis this channel renders: piped output is styled with `**bold**`
on the `⚠` lines, because a relayed answer is rendered as markdown and ANSI does not
survive the relay at all (measured — 0 of 4 escape bytes reached the reader). A fence turns
that emphasis back into literal asterisks and hands the human the flat page the styling
exists to replace.

## The three forms

| You ran | It does |
|---|---|
| `/ai-bridge` | `exec`s the SessionStart hook, so you get **that** banner, not a copy of it |
| `/ai-bridge check` | reports state that could be wrong, each line a fact with its evidence |
| `/ai-bridge fix` | repairs the **idempotent** tier only, and prints every other tier without acting |

## What you must not do with the output

- **Do not summarise the `⚠` lines away.** They are facts about this instance, and the
  human is the one who acts on most of them.
- **Do not act on a tier the script declined to act on.** If `fix` printed a line and did
  not repair it, that is the design, not an omission for you to finish. In particular:
  never revert, stage or rewrite `instance.config.json` / `instance.config.local.json`
  (an uncommitted value there is routinely a decision somebody made minutes ago), and
  never remove or rewrite `.tick-lock` / `.tick-lock.claim` (`scripts/tick-lock.sh
  release` is the human's override — a long tick is not a dead one).
- **Do not turn it into a rules recital.** This command reports facts that can be false.
  It does not remind anyone of a convention, and adding a line that reads the same on a
  healthy instance and a broken one is what it exists not to do.

## If the script is missing

`scripts/ai-bridge.sh` is machinery, so an instance stamped before it shipped has no link
to it. That is itself the fact `check` reports about other files: say so, and give the
repair — `bash <template>/install.sh <instance-root>` — rather than improvising the checks
by hand.
