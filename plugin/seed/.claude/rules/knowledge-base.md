---
paths:
  - "/knowledge/**"
---

# Knowledge base

Loads when you read anything under `knowledge/`. The instance `CLAUDE.md` keeps
the index-first rule itself, because "scan the index before you research" has to
be in context *before* the first read — by the time this file loads you are
already reading a `knowledge/` doc.

- `knowledge/` is an OKF knowledge base in this bundle — a `Service` catalog,
  `Finding`s (decisions/learnings), `Runbook`s, `Team`s, and `Reference`s
  (durable specs/contracts) (see `SCHEMA.md`).
- The `cataloguer` agent builds/refreshes it (read-only on product repos); task
  agents **capture `Finding`s as a byproduct** of their work and link them from
  the task.
- **Use it index-first, to avoid re-deriving what's already known.** Before
  researching or implementing, scan `knowledge/index.md` (a compact one-line-per-
  entry catalog) for the service/area you're touching, then open **at most three**
  specific `Finding`s / `Service` / `Runbook` / `Team` docs that match — **never bulk-read
  `knowledge/`**. If a relevant `Finding` already answers a question, cite it and
  move on. The KB is **pull-based** (read on demand); it is deliberately *not*
  auto-loaded into context, so it never bloats a session.
- **A row under a `Superseded` heading is history, not guidance.** Open one to see why a
  decision was reversed; never cite it — `cite-check.sh` reports it as `SUPERSEDED` and
  drops it. Cite the replacement its `Superseded by` column names.
- **`index.md` is derived — fix the document, not the row.** `build-kb-index.sh` rebuilds
  every row from frontmatter (summary = the doc's `lesson:`), and `--check` fails when the
  file and the documents disagree. A hand-edited row is undone by the next rebuild.
- **Tags are a closed set: `knowledge/vocab.md`.** Ground a lookup by **longest match**
  over its **tag** and **alias** columns, use the canonical tag, and **never invent one** — if
  nothing fits, add the row in the same change. `--check` refuses anything else.
