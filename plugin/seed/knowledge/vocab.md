# Knowledge base — controlled vocabulary

The **only** tags a `Finding` may carry. `build-kb-index.sh --check` refuses a `tags:`
entry that is not a `Tag` or an `Alias` below, so the KB stays searchable by a fixed set
instead of by 133 one-off words.

**How to ground a lookup:** take the phrase you were going to invent, and match it against
the `Tag` and `Alias` columns by **longest match** — `github-actions-cache` matches
`github-actions` before it matches `ci`. Use the canonical `Tag` in frontmatter; aliases
exist so a lookup finds it, not so a document spells it differently. **Never invent a
tag.** If nothing fits, add a row here in the same change — extending the vocabulary is a
deliberate edit, and `--check` is what makes it one.

Rows are per-instance: keep the three kinds, replace the examples with your own systems.

## Services

One row per system in `knowledge/services/`. Empty until this instance has some.

| Tag | Kind | Aliases |
|---|---|---|

## Components

| Tag | Kind | Aliases |
|---|---|---|
| `plugin` | component | commands, skills, agents, marketplace |
| `harness` | component | tests, suite, fixtures |
| `bundle` | component | instance, stamp, seed, control-panel |
| `config` | component | instance-config, settings, roleTiers |
| `ci` | component | github-actions, workflow, required-checks |
| `docs` | component | readme, conventions, schema |
| `review` | component | coderabbit, pr-review, clearance |
| `dispatch` | component | pm-loop, tick, project-manager |
| `worktree` | component | isolation, git-worktree |
| `knowledge-base` | component | kb, index, findings, cataloguer |

## Failure classes

| Tag | Kind | Aliases |
|---|---|---|
| `false-green` | failure | vacuous-pass, false-zero, silent-success |
| `silent-failure` | failure | swallowed-error, exit-code-lost |
| `drift` | failure | staleness, out-of-sync, hand-edited |
| `race` | failure | concurrency, collision, parallel-write |
| `quota` | failure | rate-limit, budget, spend |
| `regression` | failure | reverted, reintroduced |
| `data-loss` | failure | destructive, irreversible |
| `misread-contract` | failure | wrong-assumption, undocumented-behaviour |
