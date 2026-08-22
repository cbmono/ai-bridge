# Autonomy and the merge gate

By default ai-bridge keeps two gates for the human: **promote** a `draft` to `ready`,
and **merge** the PR (build) or **approve** the deliverable (research). Delegating
either one is optional, and off unless you install it.

**Normative source:** [`symlink/AUTONOMY.md`](../symlink/AUTONOMY.md) defines the modes;
[`symlink/SCHEMA.md`](../symlink/SCHEMA.md) → "Independent verification gate" defines the
clearance predicate. This page is orientation — don't implement from it.

---

## The on/off switch is one file

| State | What every project does |
|---|---|
| `symlink/AUTONOMY.md` **present** | a project's `autonomy:` field is honoured |
| `symlink/AUTONOMY.md` **absent** | every project is `gated`, whatever its `autonomy:` says |

`rm symlink/AUTONOMY.md` disables delegated autonomy with **no other edits** — that is
the point of the design. `commit-as.sh` gates its promotion guard on the same presence
check, fail-closed. Full reasoning, including the one hazard the pattern does not cover:
[conventions.md invariant 4](conventions.md#4-a-capability-some-deployments-must-not-have-should-be-one-deletable-file).

> **The hazard, in one line.** `AUTONOMY.md` lives under `symlink/`, so it is machinery,
> and `install.sh` re-links machinery unconditionally — a per-instance `rm` comes back on
> the next `install.sh`/`upgrade.sh`. `upgrade.sh` samples the file's presence *before*
> calling the installer and reports the re-enable with the `rm` to undo it.

## Modes

| Mode | Promotion | Merge | Browser writes |
|---|---|---|---|
| `gated` (default, and the only mode when `AUTONOMY.md` is absent) | you | you | ask first |
| `yolo` | auto-promotes fully-refined build drafts with no open questions; research stays human-driven | merges on an independent clearance + fully green CI, at the exact verified commit | permitted |

There is **no partial variant, on purpose.** `yolo` is all-out. Don't reintroduce an
ask-first carve-out on top of it — carving out the browser while the loop self-merges is
inconsistent.

Pair it with `/audit`, the slow counter-metric that watches an autonomous loop for drift.

**Preflight.** With a single `gh` identity and no external reviewer, or with no required
status checks, the merge authority cannot be exercised at all. The loop says so once and
keeps surfacing PRs for you.

## Required checks — exit 0 is the only clearance

The merge gate's first precondition is `scripts/required-checks.sh <pr>`.

| Source, in order | When it answers |
|---|---|
| **Branch protection** (platform) | whenever the API returns JSON — an empty array legitimately falls through |
| **`.github/required-checks.txt`** on the PR's base branch | only when the platform says "no required checks" |
| *anything else* | **exit 2** — refuse |

| Outcome | Result |
|---|---|
| every declared check reports `pass` | exit 0 — the only clearance |
| a declared name no check reports | drift, not absence — refuse |
| missing, pending or **skipped** | refuse |
| the PR itself edits the list | a human decision — never auto-merged |

Declare only checks that **always run**. Configuring real branch protection later needs
no change: the script prefers it automatically, and the gate then binds human merges too.

Full reasoning — why the probe is classified on its payload and never its exit code, and
why stdout and stderr must be captured separately:
[conventions.md invariant 6](conventions.md#6-the-delegated-merge-gate-resolves-its-required-checks-in-required-checkssh-and-exit-0-is-the-only-clearance).

## The verification gate

Before any PR merges it is checked by an **independent** reviewer — fresh context, judged
on real signals (acceptance criteria met, CI actually green), never the implementing
agent's self-report. Role agents embed the task's `acceptance_criteria` in the PR body so
the reviewer evaluates against them. The reviewer is an external one (e.g. CodeRabbit)
when the repo configures it, otherwise the `qa-reviewer` agent is the fallback. Before
*that*, the implementing agent **self-reviews its own diff** and fixes findings
(`code-architect` / a careful pass) — a pre-filter that shifts cheap issues left, **not**
a replacement for the independent gate.

**A verdict is structured, and clearance is a nine-clause predicate.** The `qa-reviewer`
ends its review with a machine-readable `okf-verdict` trailer; the loop reads the verdict
**only** from that trailer and criteria coverage only from the checklist's checkbox state,
never from prose. **The full predicate — the normative list every consumer must check — is
in [`SCHEMA.md`](../symlink/SCHEMA.md) → "Independent verification gate".** Don't
implement from the summary below; it names three *failure classes* to convey the shape,
not the complete set of requirements.

| Failure class | What it looks like | Why it is a refusal |
|---|---|---|
| **An unfinished verdict** | trailer missing, partial, `inconclusive`, carrying `caveats`, or omitting a mandatory lens | an approval that admits its own analysis is unfinished is not an approval |
| **An unverified criterion** | any `acceptance_criteria` box left unchecked | green CI is not evidence for a criterion no check covers |
| **A refusal dressed as a pass** | the reviewer declaring it didn't review (rate-limited, quota exhausted, skipped) while a **green check** publishes alongside | the most convincing false pass in the system |

The predicate also requires a current `head_sha`, the right reviewer identity, no
unresolved reviewer thread, and — for an external reviewer — a reconciled comment count.
Each failure class above has cleared a real bug in a real run; this is contract, not
etiquette.

**Recommended:** set branch protection to require CI green + a review from that reviewer.
GitHub only enforces *that* CI passed and a review happened — whether the reviewer
actually checked the acceptance criteria is the reviewer's job, not something branch
protection can guarantee.

## One review per PR (cost control)

The gate needs *one* fresh-context review, not a review per push. Left at its defaults
CodeRabbit re-runs on **every push** and replies to **every comment**, so a PR whose
findings an agent then fixes burns several sessions to re-confirm a diff that's already
clean. Three rules keep it to one.

1. **Pin it in the target repo's `.coderabbit.yaml`** — `reviews.auto_review.auto_incremental_review: false`
   (stop re-reviewing each push) and `chat.auto_reply: false` (stop replying to every
   comment; it still answers an explicit `@coderabbitai`). Both default to `true`. This
   repo's own [`.coderabbit.yaml`](../.coderabbit.yaml) is a working, commented example.
2. **Don't pay for the same reviewer twice.** If CodeRabbit reviews the PR, the
   pre-filter self-review uses the *free local* reviewer (`code-architect`), not the
   `coderabbit` CLI. `qa-reviewer` likewise **reads** an existing CodeRabbit review off
   the PR (via the structured `--json reviews`, not `--comments`) rather than re-running
   the CLI over the same diff — and when the repo is configured but hasn't been reviewed
   *yet*, it reports the gate as pending instead of substituting a CLI run.
3. **Never re-review to confirm a fix.** Agents address findings, push, and reply once
   with what changed. A re-review is requested only after a rewrite substantial enough to
   invalidate the original review. **This is about the same diff.** A push moves the head,
   which makes any prior verdict stale (predicate clause 3), so the *new* commit still has
   to be verified before it can merge — that's re-verification of different code, not
   re-review of the same code, and the loop does it automatically.

## Browser writes

A project can let its role agents drive a real browser via Claude for Chrome
(`browser: claude-for-chrome`). Where a mode delegates them, browser **writes** are
permitted (forms included) — the loop already self-promotes and self-merges, so carving
out the browser would be inconsistent. Under `gated`, ask first. Read-only navigation and
screenshots need no permission either way.

Permissions are pre-wired so nothing stalls: Claude Code's tool permissions sit
*underneath* a project's `autonomy`, and left prompting a background agent would stall on
a prompt nobody is watching — the task would read as hung rather than blocked. So
`symlink/.claude/settings.json` allows `mcp__claude-in-chrome__*` and every instance picks
it up through the symlink. From there the extension's **per-site permissions** are the
boundary that actually holds, so restrict there. To restore prompts, shadow the rule with
`ask` in the instance's `.claude/settings.local.json`.

Agent-facing rules: [`SCHEMA.md` → "Browser access"](../symlink/SCHEMA.md).

### What browser access looks like in practice

There is **nothing to configure in the instance.** The Chrome extension *injects* the
`mcp__claude-in-chrome__*` tools into a live paired session — no `mcpServers` stanza, no
`.mcp.json`, and `claude mcp list` doesn't even show it. Machine-level setup is: install
the extension, then grant it **per-site** permissions there.

- **Background role agents can use it.** The connection is inherited by background subagents, so this is *not* foreground-only — `/pm-loop`-dispatched agents can drive Chrome. To make that reachable, `software-engineer`, `devops-engineer` and `qa-reviewer` carry `ToolSearch, mcp__claude-in-chrome__*` in their `tools:` allowlist (a closed allowlist otherwise excludes every MCP tool). The pattern resolves to nothing when the extension isn't paired, which is harmless — the rest of the allowlist still resolves.
- **Each agent gets its own tab group**, not the human's open tabs. Agents must navigate from an explicit URL; they can't "look at the tab you have open".
- **A headless/cron tick has no browser.** Agents degrade to a non-browser route and say so, rather than reporting the task blocked.

> **Upgrading an existing instance:** re-running `install.sh` picks up `SCHEMA.md` and the
> role agents (symlinked), but **not** `CLAUDE.md` — seed content is copied only when
> absent, never clobbered. Add the **Browser** bullet from `seed/CLAUDE.md`'s "Conventions
> for role agents working in target repos" to your instance's `CLAUDE.md` by hand.

---

## The audit counter-metric

`/pm-loop` optimizes throughput; **`/audit`** is the independent check that the throughput
is actually moving the real goals. Run it on a **slow cadence** — weekly, or after a batch
of projects close.

The read-only `auditor` grounds each objective's `success_criteria` against live `gh`/`git`
reality and flags the four ways a busy control panel drifts:

| Drift | What it looks like |
|---|---|
| **Goodhart** | lots closed, goal unmoved |
| **Measurement decay** | stale `Finding`s |
| **Green but not progressing** | projects passing every check without moving anything |
| **A weakened anchor** | a human gate or the verification gate slipping — or a merge-delegating project merging PRs an independent reviewer hasn't cleared |

It writes a dated audit to `log.md` and **never acts** — responding (adjust targets,
re-validate findings) is your governance call. It is the independent signal that catches
an autonomous loop gaming itself: a periodic, advisory guardrail, **not** a merge-blocking
guarantee.
