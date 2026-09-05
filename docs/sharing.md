# Sharing one instance between two humans

An ai-bridge bundle can be shared by two humans, each with their own clone and their
own `/pm-loop`. Both see one set of projects and one knowledge base, and either can hand
a project or a single task across.

**The board is not shared either — each clone renders its own, and that costs nothing.**
There is no published page to share: every `/pm-loop` tick renders `.board-live/board.html`
on the machine it runs on. Each human's own projects come from their own snapshot, and
every *other* owner's is a named, collapsed section read from the tracked task documents at
their current git `HEAD`. **Git is what two clones genuinely share**, which is why this
half survived deleting the publish path intact: the cross-owner view never came from a
shared page. (It briefly came from one per human. Publishing was account-scoped — only the
owning account could ever update a page — so a shared URL gave a bundle one working board
and one publish step that failed silently forever; then the page vanished from under its
own owner at the next login, and the whole path was deleted.)

**All of it is a no-op on a single-human instance.** Absence means today's behaviour at
every step — never an error.

**The second human's own first hour — install, the skills, the two gates — is
[onboarding.md](onboarding.md).** This page is only the shared-instance half that goes on
top of it: steps 1, 2 and 5 of the table below are the same steps they read there.

---

## The short way

`scripts/add-second-human.sh <instance> [--apply]` does the shared, tracked half of this
— the `people` map and `defaultOwner` — and prints the commands the second human runs on
their own machine. Report-only by default. It validates the login and address before
writing, parses the config back before claiming success, and refuses if `python3` is
absent rather than editing JSON line-wise.

It cannot do their half: their `ownerGithubUser` and their absolute paths live in a
gitignored file on their machine.

## Do it in this order

| # | Step | Where | Command / value |
|---|---|---|---|
| 1 | Clone the bundle repo | second machine | `git clone <bundle-remote> _ai-bridge-<group>` |
| 2 | Link the machinery | second machine | `<this-repo>/install.sh ~/workspace/<group>/_ai-bridge-<group>` |
| 3 | Record who is who — **once**, tracked | either clone | `people` map in `instance.config.json` |
| 4 | Name who owns unowned work — **tracked** | either clone | `defaultOwner` in `instance.config.json` |
| 5 | Say which login this clone is | **each** clone | `{ "ownerGithubUser": "<login>" }` in `instance.config.local.json` |
| 6 | Put this machine's paths in the local file | **each** clone | `reposRoot`, `worktreeRoot`, `boardInstances` |
| 7 | Turn the nudges on (a clone is not a first stamp) | second clone | `touch AWAITING.md` — `SNAPSHOT.json` is seeded by the stamp itself |
| 8 | Untrack the derived indexes if already committed | either clone | run the `git rm --cached` that `install.sh` prints |
| 9 | Assign work | either clone | `owner: <github-login>` on a `project.md` or one `tasks/<id>.md` |

## The config split at a glance

| Key | File | Absent means | Overridable per machine? |
|---|---|---|---|
| `people` (login → commit email) | tracked `instance.config.json` | fall through to `authorEmail` | **No** — both clones must agree |
| `defaultOwner` | tracked `instance.config.json` | unowned work is **every** clone's ⇒ double dispatch | **No** — an override is the disagreement that breaks it |
| `ownerGithubUser` | `instance.config.local.json` | this clone has no configured human; unowned tasks clear, owned ones refuse | **Local only** |
| `authorEmail` | either | fall through to `git config user.email` | Yes |
| `reposRoot` | either | required for dispatch | Yes |
| `worktreeRoot` | either | `<reposRoot>/_wt` | Yes |
| `boardInstances` | either | the board is just this instance | Yes |
| `board` | tracked `instance.config.json` | on: the snapshot is seeded, each tick renders the local page, and a changing tick commits `/board.html` | **No** — one instance, one answer |

**The tracked `/board.html` is the one board artifact two clones DO contend for.** A tick
that changed something commits it, so on a shared bundle the file shows whichever clone
ticked last — that clone's own projects from its snapshot, plus everybody's from the
tracked documents at `HEAD`, which is the same second half both clones already render. The
contention is real and it is cheap: the page is derived, so a pull whose only conflicting
path is `board.html` is resolved by **re-rendering**, never by merging text (the tick's own
step 8 says so). **There is no per-clone opt-out, and do not go looking for one** — the
bundle's `.gitignore` is a tracked file both clones read, and neither it nor
`.git/info/exclude` has any effect on a path that is already tracked. The instance-wide
switches are the only ones: `board: false`, or a `board.html` line placed after the
`!/board.html` un-ignore in the bundle's own `.gitignore`.

The **one** place the overridable set is listed — with what each key means when absent —
is [`SCHEMA.md` → "Per-machine config overrides"](../symlink/SCHEMA.md). Every reader
must honour it.

---

## The reasoning

> Relocated verbatim. This is invariant 13 of
> [docs/conventions.md](conventions.md); it lives here because it is one topic and
> splitting it would leave half the argument on each side.

**A shared instance is three no-ops and one gate, and the gate is on the wrong verb if you get it backwards.**

### (a) `owner` gates DISPATCH, never promotion

`scripts/task-owner.sh` does **two things, and conflating them is the documentation bug review caught twice**: it *resolves* the task's owner — task `owner:` → project `owner:` → tracked **`defaultOwner`** → nobody (unowned) — and then *compares* that owner against `ownerGithubUser`. `ownerGithubUser` answers "who is this clone?" and is **never a source of ownership**; written into the chain as a third owner source it reads as though setting it assigns unowned work, which contradicts the next sentence in every doc that said it. Read from `instance.config.local.json`, else `instance.config.json`; **absent from both ⇒ this clone has no configured human**, so unowned tasks still clear and owned ones refuse), and **exit 0 is the only clearance** — the `required-checks.sh` discipline, for the same reason: exit 1 (someone else's) and exit 2 (unreadable frontmatter, a value that is not a GitHub username, not an instance root) are both refusals, because a clone that cannot prove a task is its own must not hand it to an agent. **No `owner:` anywhere means everything is this clone's**, which is exactly how the three existing single-human instances already behave — this must stay a no-op for them.

Promotion is deliberately *not* gated: `draft → ready` is the human's, and on a shared board it is *either* human's, so gating it would gate the wrong verb — the natural mistake here. Nor does it gate commits, the KB or `/close-project`. The loop must still **see and report** the other human's tasks (that is the entire point of sharing); only `AWAITING.md` narrows, and its layout is untouched because `session-banner.sh` greps for it literally. Say out loud that **it is not a lock** — it stops two loops dispatching the *same* task, not two loops acting in one tick window on tasks they each own; claiming more would claim a guarantee git cannot make.

The value is a **GitHub username, never an email**: public, stable, and it keeps addresses out of tracked documents, which is the no-PII rule applied to identity. `validate-bundle.sh` deliberately gains **no** `owner` check — it names a person outside the bundle, so nothing there can resolve it, and the shape is judged at dispatch where a refusal has somewhere to go.

**`owner` IS in the board snapshot, and that reverses an earlier rule** which excluded it because the allowlist excludes identity and the board's HTML can be published. It was reversed on 2026-08-26 for one reason: publishing is account-scoped, so each human publishes their own board, and a board that cannot say whose project is whose cannot separate your work from theirs. The concession stays narrow — a *username*, project-level, copied verbatim, with `authorEmail` still excluded — and it is stated in `write-snapshot.sh`'s own header rather than made quietly, so a reader who finds the old rule can tell which is current. `snapshot.test.sh` still fails on any *other* key added without reading why.

**`defaultOwner` is the piece that makes the chain sound, and it must stay tracked-only.** The final "unowned ⇒ every clone's" step is correct on one clone and a **double-dispatch bug** on two: the same task resolves to "mine" on both, so both loops dispatch it — the exact failure ownership exists to prevent. `defaultOwner` names, in the file **both** clones read, who unowned work belongs to, so exactly one matches. That holds only while both clones agree, which is why it is read from the tracked config **only**: a local override is precisely the disagreement that breaks it. It is the one key here deliberately excluded from the override set, and `task-owner.test.sh` pins both halves — one tracked config plus two local `ownerGithubUser` values clears on exactly one clone, and with `defaultOwner` absent it clears on **both** (the hazard, asserted rather than described).

### (b) Identity and machine paths belong in the per-machine file, and shared facts do not

`instance.config.json` is *tracked*, so a single `authorEmail` there authors both humans' commits as one person — destroying the per-agent provenance `commit-as.sh` exists to create. The fix that scales is a **tracked `people` map** (GitHub login → commit email) plus a local file carrying one key, `ownerGithubUser` — the same key the ownership gate already needs — so a second human's setup is one line and they never write their own address down.

**The address is per-INSTANCE, not per-person, and that is the reason the map lives in each instance's own config rather than anywhere shared**: the same login maps to a different address in each group's bundle, because the address says which entity the work belongs to (one person working three clients commits as three addresses). Two consequences to preserve — never *derive* the address from the login (the mapping is a business fact, not a naming convention), and never move it into the local file, because that file says which login this clone *is* and reversing the split would let two clones of one instance disagree about which entity the work belongs to while git history recorded both.

`instance.config.local.json` (gitignored) also covers `authorEmail`, `reposRoot`, `worktreeRoot` and `boardInstances`, which are absolute paths on one machine and so cannot be right for two. **The overridable set is listed in exactly one place — `SCHEMA.md` → "Per-machine config overrides" — and every reader must honour it**: a half-honoured override (the loop dispatching against one `reposRoot` while `link-repos.sh` links from another) is worse than none, because nothing looks broken, so `config-override.test.sh` exercises all four readers *and* keeps a static check that a newly-added reader does the two-file lookup. The split has a rule behind it: **the tracked file holds facts both clones share, the local file holds facts about this machine and this human** — a key that must be *the same* on both clones to be correct (`defaultOwner`, `people`) is never overridable. Absence changes nothing at every step, which is the property every single-human instance depends on.

A derived `<login>@users.noreply.github.com` was **rejected, not skipped**: GitHub requires the ID-prefixed `<id>+<login>@…` form for accounts created after 2017-07-18, so a derived plain address silently fails to link — and the linking behaviour cannot be verified from here without pushing as that account. Real addresses in a private instance repo are fine; **this template is public, so `seed/instance.config.json` ships placeholder logins VERIFIED UNCLAIMED on github.com (`example-user-007`/`008`, both 404) and addresses at `example.com` (RFC 2606, cannot receive mail), and says so in a `$people` note** — the real map belongs in the instance. **Verify any new placeholder the same way**: `alice`, `bob` and `jane-doe` are all real accounts, so a plausible-looking example names a stranger, and an example is the thing people copy verbatim. Test fixtures follow the same rule, and `commit-as-identity.test.sh` asserts the seed carries no live-account name and no address outside `example.com`.

`install.sh` **does** ask for the map on a first stamp now — steps 3 to 5 of the table above, collected at install time instead of hand-edited afterwards. The three things that would have broken existing flows are the three guards it carries; they, and the failure the prompt's shape is designed around, are written up in ["The installer asks, once"](#the-installer-asks-once) at the end of this page.

### (c) The derived `index.md` files become gitignored

…and only *untracked* when a human runs the printed command — and the split was decided per file. Root `index.md` and `projects/*/index.md` are rewritten every tick from the documents they summarise, so two loops conflict on them on every push, and nothing is lost — `validate-bundle.sh` never validated them (an earlier version did, and buried 6 real errors under 77 warnings). `knowledge/index.md` stays **tracked**: it changes only when the KB changes rather than every tick, its rows are curated prose, and every agent is told to scan it, so a fresh clone needs it present — do not blanket-ignore `index.md`, which as a bare pattern would swallow it silently. Unlike `AWAITING.md`/`SNAPSHOT.json` these have **no off switch and need none** — they are navigation, re-seeded by `install.sh` and rewritten unconditionally.

Two properties worth keeping in mind when you touch it. **A `.gitignore` line is inert for a file git already tracks**, so `install.sh` appends the lines (outside the managed block, the `/repos/` pattern, because the seed is copied only when absent) and then *reports* the exact `git rm --cached` — it never untracks anything itself. And **the index lines must NOT go in `seed/.gitignore`**: that file is an active `.gitignore` inside the template's own `seed/` directory, so a `/index.md` line there matches `seed/index.md` and silently stops this repo from tracking its own seed file — measured, it broke the `upgrade.sh` fixture, which re-inits a repo over a copy of `seed/`. `instance.config.local.json` sits in both places because no seed file is named that. `derived-indexes.test.sh` asserts the trap stays closed, against `git check-ignore --no-index` rather than the pattern text.

Covered by `tests/task-owner.test.sh` (74 assertions, mostly refusals), `commit-as-identity.test.sh` (46), `derived-indexes.test.sh` (26) and `config-override.test.sh` (39).

---

## One thing a second clone does not get automatically

The second clone is **not a first stamp** (`instance.config.json` arrives tracked), so
`install.sh` there will **not** create `AWAITING.md`. It says so, with the `touch` to turn
it on. See [conventions.md invariant 3](conventions.md#3-awaitingmd-is-ai-bridges-only-status-artifact-and-it-is-opt-in-by-presence)
for why that creation is gated on the first stamp.

`SNAPSHOT.json` is **not** gated that way and needs no `touch`: the installer seeds it on
any stamp where it is missing, unless `board` is `false`. The board's off switch is that
key, not the file's absence.

Two rules survive the per-machine override and are checked against the *effective*
values: `worktreeRoot` must never sit inside the synced `reposRoot`, and `reposRoot` must
not be the instance directory itself.

**The tick syncs for you; ownership does not.** Since
[#26](https://github.com/cbmono/ai-bridge/pull/26) and
[#27](https://github.com/cbmono/ai-bridge/pull/27), a `/pm-loop` tick pulls `--rebase`
before it re-derives anything and pushes after it commits, whenever the bundle has a
remote — so neither human runs git by hand for the loop's own work. A dirty tree
**defers** that pull to the end of the tick rather than blocking it, because concurrent
agents share one working tree here and a sibling mid-write is normal.

Two things it deliberately does not do. **A conflict stops the tick** rather than being
auto-resolved — conflicted task documents are contested state between two humans, and a
guessed resolution writes a `status:` nobody chose. And **nothing force-pushes**. Work
*you* commit by hand outside a tick is still yours to push. Ownership stops two loops
dispatching the same task; it was never a lock on pushing.

---

## The installer asks, once

Steps 3 to 5 of the table above used to be an eight-step checklist somebody performed
after the stamp. On a **first stamp**, at a terminal, `install.sh` now offers to collect
them instead: one line per person (`<github-login> <commit-email>`), yourself first, and
it writes the tracked `people` map, the tracked `defaultOwner`, and this clone's
gitignored `instance.config.local.json`. Nothing about the model above changed — this is
only the collection step it was missing.

**Three guards, each protecting a flow that already worked.**

| Guard | Why it exists |
|---|---|
| Only on the **first stamp** | `upgrade.sh` calls `install.sh` on *every* run, including its non-interactive report-only mode, so an unguarded prompt would block every upgrade. It reuses the same `FIRST_STAMP` that gates `AWAITING.md`, rather than inventing a second notion of "new" |
| Only when **stdin is a terminal** | otherwise it skips, leaves the placeholder, and prints the instruction. A prompt nobody can see is a hang, and a hang in a background agent is invisible |
| **Never overwrite** | only the seeded placeholder is ever rewritten, and the local file only when absent. Seeds-if-absent is what makes the installer safe to re-run on a repo full of somebody's work |

**One batched prompt, and the reason is the failure mode rather than the keystrokes.**
Asked person by person, a roster accumulates state across reads: enter one pair, hit
ctrl-C, and the instance is left with a map that resolves for one human and silently
falls through for the other. So the whole roster arrives as one block, and **nothing is
written until a separate confirmation** — an interrupt, EOF, an unreadable line and a
declined confirmation all take the same exit: write nothing, and say which happened. It
is also two reads regardless of team size, which is why `/new-project` batches its
capability questions the same way.

**Two more properties worth keeping if you touch it.** The write is *verified by parsing
it back* — before the temp file lands and again after — and if neither `jq` nor `python3`
is on the machine the prompt is **not offered at all**: a broken `instance.config.json`
breaks every later script in the instance, and this repo has a recorded incident of a
script printing success for a write that never landed
([conventions 9](conventions.md#9-migrate-bundlesh-fixes-only-what-has-one-right-answer-and-is-report-only-by-default)).
And **validation is the escaping**: a login must match the GitHub-username rule
`task-owner.sh` already applies and an address a conservative mail shape, so no accepted
value can carry a character that would need escaping into a JSON string. What counts as
"still the placeholder" is deliberately name-independent — an entry whose login equals
the local part of its address at `example.com` — so renaming the seed's example logins
cannot silently switch the prompt off.

Covered by `tests/team-setup.test.sh` (94 assertions, most of them refusals: a non-TTY
stamp, a refresh, an existing value, a real `SIGINT` delivered mid-answer, EOF, a
declined confirmation, unreadable input, and `--config`).
