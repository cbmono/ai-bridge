# Step 3 — Dispatch `ready → in-progress`

**Loaded on demand.** The tick reads this file only when `tick-delta.sh digest` names
it on its `steps:` line (`project-manager.md` → "Step files"). Every rule in the core
prompt still binds here — both authority gates, the ownership gate, the UNKNOWN rule.

3. **Dispatch `ready → in-progress`.** **Build tasks only.** Skip any `kind: research`
   task entirely here — those are human-driven; never spawn an agent for them.

   **One agent per task, and a resume only for that task's next round.** The rule is
   stated once, in `CONVENTIONS.md` → "A subagent works ONE task":

   > same task and same PR ⇒ resume; anything else ⇒ dispatch fresh; a tick ⇒ never

   Nothing can check that from the outside — **you** hold it
   (`docs/pm-design.md#step-3` has the price of not holding it).

   **Gate 3 in the core is the ownership check this step depends on** — run
   `task-owner.sh` and take exit 0 as the only clearance before anything below.

   **A ROLE AGENT IS A DETACHED SESSION, NEVER YOUR CHILD.** Do not use the `Agent`
   tool here. Claude Code withholds a parent's completion notification until every
   background child has stopped, so an `Agent`-tool dispatch makes `tick duration =
   slowest role agent` and the launcher's lock is held for the whole wave — measured
   2026-09-13, ticks of 49, 75, 84 and 125 minutes that had each finished their own
   work inside ~5. `claude --bg` leaves your process tree, so the tick ends when its
   dispatches are recorded (`docs/pm-design.md#step-3-background`).

   For each **build** `ready` task whose `depends_on` are all `done`, that clears the
   ownership check, and that is not already in-progress: set `assignee` +
   `status: in-progress`, **and record `worktree:` (absolute) and `branch:` on the
   task — both, or neither** (`SCHEMA.md`: a recorded path with no recorded branch is a
   refusal, and the `WorktreeCreate` hook reads both).
   Write them BEFORE spawning, so a tick that dies mid-dispatch still leaves the
   record. Then spawn the role in its own worktree:

   ```bash
   cd <worktree> && claude --bg "<the whole brief>" \
     --agent ai-bridge:<assignee> --model <the alias you resolved> \
     --permission-mode bypassPermissions --add-dir <bundle root> < /dev/null
   ```

   It returns in about a second printing `backgrounded · <id>`. **Record that id as
   `session:` on the task as the very next thing you do** (`SCHEMA.md`), then move on.

   **This is the form for EVERY role agent this document tells you to dispatch** — the
   `qa-reviewer` at step 4, the `cataloguer` at step 7, a rebase round, a resume —
   because each of them would hold the tick open exactly as a first dispatch does. The
   two exceptions are the `advisor` and the `plan-architect` critique: they are short,
   they produce no artifact, and you read their answer inside the tick, so they stay
   `Agent`-tool dispatches.

   Six things about that command line, each of which costs a wave if you get it wrong:
   - **`--bg` and `-p` conflict** and the CLI refuses the pair at exit 1 — the prompt is
     positional, so drop `--print`.
   - **`--session-id` is ignored beside `--bg`**, which mints its own; that is why the
     id is recorded after the spawn and not before it.
   - **`--permission-mode bypassPermissions` with the plugin's `deny-destructive.sh`
     PreToolUse hook is the only posture measured to work.** Hooks fire in a `--bg`
     session. A mode that can prompt parks the agent in `state: blocked` with nobody to
     answer, and it holds its slot until `claude stop` — this machine still lists two
     such sessions from August.
   - **`--add-dir <bundle root>`**, or the agent cannot reach its own task document: its
     cwd is the worktree, and the bundle is outside it.
   - **The namespace is not optional** — the role agents ship in the `ai-bridge` plugin
     and a bare agent name does NOT resolve (measured 2026-09-02); it fails with "no
     such agent", never with "you forgot the namespace". **It applies to every one of
     the eight** — `ai-bridge:cataloguer`, `ai-bridge:advisor`, `ai-bridge:qa-reviewer`
     and the rest, wherever this document tells you to dispatch one. The three
     USER-level agents `init-bundle.sh --config` puts in `~/.claude/agents/` —
     `code-architect`, `deep-bug-scan`, `plan-architect` — are not plugin agents, stay
     BARE, and are still `Agent`-tool dispatches because they are advisory and short.
   - **`< /dev/null`**, so the spawn cannot inherit and hold your stdin.

   **The cap counts SESSIONS, and you read it rather than remember it.** The ceiling is
   **`maxAgentsInFlight`**, resolved with `${CLAUDE_PLUGIN_ROOT}/scripts/resolve-max-agents.sh` (local file
   first, tracked second — the cap is **this machine's** capacity, `SCHEMA.md` →
   "Per-machine config overrides"); it prints nothing and exits 1 when neither file
   sets the key — fall back to 4 then, the seeded, measured default (SCHEMA.md). What
   fills it is `${CLAUDE_PLUGIN_ROOT}/scripts/agent-sessions.sh in-flight <bundle root>`, which counts the
   `session:` ids recorded on `in-progress` tasks that are still `working` or
   `blocked`; **exit 2 is unknown, and unknown is not a free slot** — dispatch nothing
   this tick and say so. Leave the rest `ready` for the next tick.

   **A spawn that FAILS is a rollback, not a report — the other half of the window the
   pre-spawn write opens.** If the command exits non-zero or prints no id, put that
   task back to `status: ready`, clear `assignee`, and leave `worktree:`/`branch:`
   standing — a re-dispatch reuses that worktree, and a recorded path with no recorded
   branch is a refusal. Say so in the tick report. Left alone, the task claims a
   `maxAgentsInFlight` slot forever with nothing behind it, and step 4's sweep can only
   name it, never decide it.
   **Exit 0 is not proof the agent lives** — `--bg` returns before the session has done
   anything, so one that dies on plugin load looks identical here. That is step 4's
   question, asked from `agent-sessions.sh`, and not one to hold this tick open for.

   **A dispatch you send is finished when the ARTIFACT says so, and you will never be
   told.** A detached session sends you no notification at all, so every dispatch made
   here is checked by a LATER tick —
   `${CLAUDE_PLUGIN_ROOT}/scripts/check-dispatch.sh <task-path>`, per step 4. Note it now: waiting for
   a report is the coupling this whole step exists to remove, and the report was never
   trustworthy anyway (`docs/pm-design.md#step-3`).

   **Isolation (required for parallel safety).** If the product repos are a *single
   shared clone over one package store*, concurrent agents otherwise corrupt each
   other's worktrees. In every dispatch, instruct the agent to (a) work in its own
   worktree under the instance's `worktreeRoot` (from `instance.config.json` —
   **never** a path inside the synced `reposRoot`; absent, `<reposRoot>/_wt`),
   (b) run installs against a **private store** (e.g. `pnpm install --store-dir
   <worktree>/.pnpm-store`), and (c) **push early**. Two agents must never run a
   package install against the shared store at once — if two `ready` tasks touch the
   same repo's deps, stagger them across ticks.

   **Knowledge base (consult + capture).** Include both lines in every dispatch
   brief: *"Before you start, scan `knowledge/index.md` for prior `Finding`s /
   `Service` / `Runbook` docs on this area and reuse them — open only what matches,
   don't bulk-read `knowledge/`."* and *"If you discover something durable and
   reusable, write or update a `Finding` in `knowledge/findings/` per `SCHEMA.md` and
   link it from the task."*

   **Grounding, Effort, Commit attribution and Scratch (where to start reading, how big
   this is, how the commit is signed, and where the throwaway files go).** Before you
   spawn, run `${CLAUDE_PLUGIN_ROOT}/scripts/dispatch-brief.sh <task-path>` and paste its
   output into the brief **unchanged, all four headings and all** — the fixed headings are
   `## Grounding (<target_repo>)`, `## Effort`, `## Commit attribution` and `## Scratch`.
   Grounding is the
   target repo's
   `knowledge/services/<repo>.md` entry points, capped at 15 lines, or — when that Service
   doc does not exist — one line telling the agent to draft it alongside the task for the
   `cataloguer` to review. Effort is the files/LOC/turns budget derived from the task's
   criteria count and the instance's `maxPrLoc`/`maxPrFiles`. Commit attribution is the
   resolved `commitAttribution` (**absent ⇒ `claude`**), and it is in the brief precisely so
   the worker never reads that key itself. Scratch is one directory **this task alone
   owns** — keyed on the task's slug, and checked with `git check-ignore` against the target
   repo's own clone, because a per-session path is the SAME path for every agent one tick
   spawns and the second writer silently wins. **Never re-derive any of the four
   yourself**: an agent that has to find its own entry points spends its first turns
   searching, which is the whole cost this block exists to remove.

   **Do not repeat (what the previous round already tried).** Before you spawn, run
   `${CLAUDE_PLUGIN_ROOT}/scripts/do-not-repeat.sh brief <task-path>` and paste its output into the brief
   **unchanged, heading and all** — the fixed heading is
   `## Do not repeat (earlier rounds of this task)` and the lines under it are the previous
   agent's own words. **Never summarise or re-word them**: a paraphrase of a dead end is
   what a cold agent walks straight back into. It prints nothing when the task has no
   `do_not_repeat:` entries, which is every first dispatch. When a role agent's `append`
   refused at the cap (exit 1), move the oldest entries out of the field into `# Notes`
   yourself, so the next round has a slot to record one.

   **Model routing.** Read `models` (tier → alias) and `roleTiers` (role → default
   tier) from `instance.config.json`. For each dispatch: start from the assignee's
   default tier; **bump one tier up** (toward `deep`) for a genuinely complex build
   task (the same signal that makes the `plan-architect` approach critique mandatory); **drop toward `light`**
   for a trivial one. A task may set a `model:` field — honor it verbatim. Resolve
   the chosen tier with `${CLAUDE_PLUGIN_ROOT}/scripts/resolve-model.sh <agent>` and pass it as the model
   when you spawn — the same for **every** dispatch, including the `cataloguer` and
   the `plan-architect` critique. If `models`/`roleTiers` are absent the script prints
   why on stderr — **report that line to the human**, then inherit the session model;
   don't guess aliases.

   **Name the Explore model in every role-agent brief.** Broad reads go to an Explore
   subagent (`CONVENTIONS.md`), which is dispatched with a model override like any other,
   so the brief has to carry the alias: run
   `${CLAUDE_PLUGIN_ROOT}/scripts/resolve-model.sh explorer` and include *"Explore
   subagents: model `<alias>`"*. **No entry ⇒ write the seeded default `light` and say
   that is what it is** — *"Explore subagents: model `light` (this instance sets no
   `roleTiers.explorer`; seed default)"* — so the reader can tell a chosen tier from an
   unset one.

   **Record the dispatch the moment the id comes back — one line, written by the
   script, before you dispatch the next task:**

   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/agent-usage.sh dispatch <task-path> \
     --role <assignee> --model <the alias you dispatched on>
   ```

   It appends to the task's `# Notes`, so a **re-dispatch adds a second line** and the
   rounds stay countable; **you never compose the line yourself**.
   **The three usage numbers are gone with the notification, and the line says so.** A
   detached session reports nothing back and `claude agents` carries no cost, so drop
   `--tokens`/`--tools`/`--duration-ms` and let the line record `usage UNKNOWN` —
   the honest answer, and not a zero. That is the price of the decoupling, paid
   knowingly (`docs/pm-design.md#step-3-background`).


<!-- end of step 3 -->
