# ai-bridge-v2 — deprecated

`ai-bridge-v2` was the **transition name** the plugin replatform shipped under. The
plugin is now `ai-bridge`, and this directory is a stub that ships for **one version**
so an already-installed machine finds out by name rather than by a command failing.

```
/plugin marketplace add cbmono/ai-bridge     # already added? skip
/plugin install ai-bridge@ai-bridge
/plugin  ->  Manage  ->  uninstall ai-bridge-v2
```

Then `/exit` and relaunch Claude Code.

Nothing else moves: the bundles (`projects/`, `knowledge/`, `instance.config.json`) and
every skill are unchanged — only the namespace. `/ai-bridge-v2:dispatch` becomes
`/ai-bridge:dispatch`, and the eight role agents dispatch as `ai-bridge:<role>`.

It carries exactly one skill, `/ai-bridge-v2:renamed`, which prints the block above. It
ships no agents and no hooks — the real plugin carries both, and two copies of an
enforcement hook firing in every session on the machine is not a transition aid.
