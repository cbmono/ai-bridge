# Migrating from ai-bridge to loopd

**Nothing here applies yet.** The plugin, its marketplace and this repository are renamed
`loopd` by the rename PR (loopd/task-007, the flip) and released as 3.0.0 (task-008).
Until that release reaches your machine, keep running `/ai-bridge:*`.

Two parts, in order: the owner renames the repository once; then every machine and every
bundle moves over.

## 1. The owner's runbook — once, for the repository

| # | Step | Why here |
|---|---|---|
| 1 | Merge the prep PR (name derived, harnesses parametrised) | the plugin keeps working under `ai-bridge` |
| 2 | **Do not enable GitHub Pages under the old name.** Enable it at step 7 | GitHub redirects everything on a rename **except project-site URLs** — see below |
| 3 | Merge the flip PR | manifest, slugs and namespaces move together |
| 4 | `gh repo rename loopd --repo cbmono/ai-bridge`, right after the merge | the owner's step — no agent renames the repository; `cbmono/loopd` resolves from here |
| 5 | `plugin/scripts/release-bump.sh major` on `main`, push | 3.0.0 is what `claude plugin update` offers |
| 6 | `git remote set-url origin https://github.com/cbmono/loopd.git` in each clone | the old URL redirects, but only until a repo reuses the name |
| 7 | Settings → Pages → deploy from `main`, `/docs` | the site appears at `https://cbmono.github.io/loopd/` |

**Never create a new repository called `ai-bridge` afterwards.** GitHub drops every
redirect from the old name the moment one exists.

**The Pages URL is not redirected.** GitHub's
[renaming a repository](https://docs.github.com/en/repositories/creating-and-managing-repositories/renaming-a-repository)
page: *"all existing information, with the exception of project site URLs, is
automatically redirected to the new name"*. Checked 2026-09-30: Pages is **not enabled**
on `cbmono/ai-bridge` (`gh api repos/cbmono/ai-bridge/pages` → 404,
`https://cbmono.github.io/ai-bridge/` → 404), and no tracked file links that URL. So
nothing breaks, provided step 2 holds: a site first published at `/loopd/` never had an
old URL to lose.

## 2. Every machine, then every bundle on it

```text
/plugin marketplace add cbmono/loopd
/plugin install loopd@loopd
```

Restart Claude Code. Then, in **each** bundle:

```text
/loopd:init <bundle-path>
```

**`init` seeds only what is absent and never overwrites**, so three name-scoped copies a
bundle already holds are yours to edit. Each names the marketplace cache, whose path is
**name- and version-scoped**: `~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/`.

| File | Old | New |
|---|---|---|
| `CLAUDE.md` — the scripts-path line | `ls -d ~/.claude/plugins/cache/*/ai-bridge/*/scripts \| sort -V \| tail -1` | `ls -d ~/.claude/plugins/cache/*/loopd/*/scripts \| sort -V \| tail -1` |
| `CLAUDE.md` — every command and dispatch name | `/ai-bridge:<cmd>`, `ai-bridge:<role>` | `/loopd:<cmd>`, `loopd:<role>` — a bare role name does not resolve |
| `.claude/ai-bridge-statusline.sh` | `"$cache"/*/ai-bridge/*/scripts/status-line.sh` | `"$cache"/*/loopd/*/scripts/status-line.sh` |
| `.claude/settings.local.json` | `Bash(…/plugins/cache/ai-bridge/ai-bridge/*/scripts/*)` | `/loopd:init` adds the `loopd/loopd` rule; delete the old pair |

Find them with `grep -rn 'ai-bridge[:@]\|/ai-bridge/' CLAUDE.md .claude/`. Commit the edit.

**Only then uninstall the old plugin:**

```text
/plugin uninstall ai-bridge@ai-bridge
/plugin marketplace remove ai-bridge
```

Companions (`ai-bridge-yolo`, `ai-bridge-accounts`, `ai-bridge-llm`): uninstall each and
install it again from `@loopd` under the name the flip PR gives it — that PR fills the names
in here. Until you do, `yolo` projects read as `gated`, which is the safe direction.

Edit first, uninstall second. The cache keeps old versions on disk, so an unedited
scripts-path line may keep resolving to stale `ai-bridge` scripts instead of failing.

**Done when** the grep above prints nothing in every bundle and `/loopd:welcome` shows the
banner.
