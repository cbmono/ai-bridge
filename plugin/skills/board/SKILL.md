---
name: board
disable-model-invocation: true
description: Publish this instance's board as a PRIVATE artifact at a stable URL — rendered from SNAPSHOT.json only, updating the same page in place on every run. Interactive only; a session with no artifact capability says so and stops.
argument-hint: "(no arguments)"
---

Publish this instance's board as a **private artifact**, at **one URL that never
changes**. Run it from the instance root.

The page is the same page the tick already renders — `${CLAUDE_PLUGIN_ROOT}/scripts/build-board.sh`, from
`SNAPSHOT.json` and nothing else. This skill adds no markup, no heading and no note of
its own; what it publishes is the bytes the renderer wrote.

## The seven steps

1. **Confirm you are at an instance root** — `instance.config.json` is present. If it is
   not, say which directory this is and stop. Never improvise a board.
2. **Refresh the data**: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/write-snapshot.sh --quiet`. No `SNAPSHOT.json` ⇒ the
   writer writes nothing and exits 0 — that is how a human takes this instance off the
   board, so say so in one line and stop. Never create the file.
3. **Read `board` from the tracked `instance.config.json`** — the same key `install.sh`
   reads at stamp time, and deliberately *not* per-machine overridable. `false` ⇒ say the
   board is switched off and stop. Absent or `true` ⇒ carry on.
4. **Render, scoped to this instance**, from the instance root:

   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/build-board.sh --out .board-live/artifact-body.html .
   ```

   **No `--standalone`**: the artifact host supplies `<!doctype>`, `<html>`, `<head>` and
   `<body>`, and a page that ships its own gets double-nested. The default output is
   exactly that body.

   **The trailing `.` is load-bearing — never drop it.** Given no instance directory the
   renderer discovers instances from `boardInstances`, which on a real machine names
   **other bundles**. This output is published, so a bare render would put another
   bundle's project titles on a page with a different audience. `.` renders this
   instance's snapshot and nothing else. No readable snapshot ⇒ nothing written, exit 0 ⇒
   stop here.

   `.board-live/` is gitignored, so the rendered body is never committed.
5. **Publish it, updating the same artifact.** Read the rendered file and publish its
   contents with this session's artifact capability:

   - a URL already recorded (step 6)? **update that artifact in place**, so the URL a
     human bookmarked, or shared, keeps working. Never create a second one;
   - no URL recorded? create one, **private** — the default, and the only setting this
     skill ever asks for. It shares the page with nobody.

   **Title it with the page's own `<h1>`** — the masthead the renderer already wrote from
   the snapshot's `group`. Do not compose a title, a description or a summary: an org, a
   person, a repo or a path you type in is a literal the field allowlist never cleared,
   and it would sit on the page next to data that did.
6. **Record the URL in `instance.config.local.json`**, under `boardArtifactUrl`, creating
   the file if it is absent and preserving every key already in it.

   **That file and no other.** It is per-machine and gitignored;
   `instance.config.json` is tracked, and a tracked URL is the failure this design exists
   to avoid — publishing is **account-scoped**, so exactly one account can ever update a
   given artifact, and a shared value produces one working board and one silently dead
   publish step on the other clone (`SCHEMA.md` → "Per-machine config overrides").
7. **Report one line** — `BOARD: published <url>` — and nothing else. The next session's
   banner prints the same URL.

## When this session cannot publish

**A headless tick cannot, and that is measured, not assumed.** On Claude Code 2.1.261 a
`claude -p` session's tool inventory carries no artifact tool and a tool search for one
returns nothing, so the dispatch tick never publishes — it renders the local page, and
says `run /ai-bridge:board to refresh` instead.

So if this session has no artifact capability either: **say that in one line, name the
rendered file, and stop.** It is not an error and not a failure of the instance —
`.board-live/artifact-body.html` is on disk, `/board.html` is the tracked fallback, and
nothing is half-published.

## Sharing it with a second human

Share the artifact from its own share control, read-only. The URL does not change, so
every later run of this skill updates the page they already have.

**Sharing does not grant publishing.** No share level makes a second account able to
update your artifact; each human publishes their own board from their own clone, and the
cross-owner half of the page comes from the tracked task documents at your git `HEAD` —
never from anybody's published page.

## What must not happen here

- **Never write `/board.html`.** That file is the tick's, rendered `--standalone` and
  committed; this skill only ever writes under `.board-live/`.
- **Never put the URL in `instance.config.json`**, and never remove or rewrite a key
  already in the local file.
- **Never widen what the page carries.** The renderer's input is the snapshot, whose
  field allowlist is a data-governance boundary (`docs/operations.md` → "Before it leaves
  the machine, know what it carries"). Publishing does not license adding to it.
- **Never share the artifact as part of this command.** Sharing is a human decision made
  once, in the step above.
