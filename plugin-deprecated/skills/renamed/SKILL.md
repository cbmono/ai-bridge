---
name: renamed
description: DEPRECATED — this plugin is now `ai-bridge`. Prints the two commands that move you to the new name.
allowed-tools: []
---

Print this, verbatim, and do nothing else. **Never** read the bundle, dispatch an agent,
or run a command: this skill exists only to answer a `/ai-bridge-v2:` tab-completion with
the new name.

```
ai-bridge-v2 was the transition name. The plugin is now `ai-bridge`.

  /plugin marketplace add cbmono/ai-bridge     (already added? skip)
  /plugin install ai-bridge@ai-bridge
  /plugin  ->  Manage  ->  uninstall ai-bridge-v2

Then /exit and relaunch Claude Code.

Every command moves with it: /ai-bridge-v2:dispatch is now /ai-bridge:dispatch, and
so on for :new-project, :close-project, :answer, :audit, :fanout,
:pr-review-request, :welcome, :brief-me, :capture, :work and :handoff.
The eight role agents dispatch as `ai-bridge:<role>`.

This stub ships for ONE version and is then removed.
```
