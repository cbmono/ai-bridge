---
runs: 2
max_turns: 8
timeout_seconds: 240
allowed_tools: [Read, Glob, Grep]
---

Our knowledge base is `knowledge/` in this bundle: about 140 `Finding` documents under `knowledge/findings/`, a handful of `Service` docs, and a generated `knowledge/index.md` carrying one row per document with its title and its one-line lesson.

I'm about to write a harness that builds a throwaway git repo as a fixture. What do we already know about test fixtures that I should read first? Answer from the knowledge base.
