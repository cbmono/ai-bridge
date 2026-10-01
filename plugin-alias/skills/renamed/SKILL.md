---
name: renamed
description: RENAMED — this plugin is now `loopd`. Prints the commands that move you to the new name.
allowed-tools: []
---

Print this, verbatim, and do nothing else. **Never** read the bundle, dispatch an agent,
or run a command.

```
ai-bridge is now loopd.

  /plugin marketplace add cbmono/loopd
  /plugin install loopd@loopd
  /exit, relaunch Claude Code, then in each bundle:  /loopd:init <bundle-path>

Then edit what init never overwrites and uninstall ai-bridge@ai-bridge —
MIGRATION.md in https://github.com/cbmono/loopd lists both.

Every command moves with it: /ai-bridge:<cmd> is now /loopd:<cmd>, and the
eight role agents dispatch as loopd:<role>.

This alias ships for ONE release and is then removed.
```
