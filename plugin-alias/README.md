# ai-bridge — renamed loopd

This directory is the `ai-bridge` **alias** the marketplace keeps for **one release**, so a
machine that installed `ai-bridge@ai-bridge` finds out by name rather than by a command
that stopped resolving. The plugin is now `loopd`; [`MIGRATION.md`](../MIGRATION.md) is
the whole move.

It ships one skill, `renamed`, and **no hooks and no agents**: two copies of an
enforcement hook firing in every session on the machine is not a transition aid.
