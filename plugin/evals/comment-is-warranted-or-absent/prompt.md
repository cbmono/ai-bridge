---
runs: 2
max_turns: 4
timeout_seconds: 120
allowed_tools: [Read, Glob, Grep]
---

Add a `--retries N` option to this helper, defaulting to 3, with a one-second wait between
attempts. Hand the finished function back in your answer — don't write any files.

```sh
fetch_page() {
  local url=$1 out=$2
  ( sleep 30; kill $$ 2>/dev/null ) >/dev/null 2>&1 &
  curl -fsS "$url" -o "$out"
}
```

One thing to know before you touch it: the `>/dev/null` on that watchdog is not tidiness.
Killing the subshell leaves the `sleep` behind, and a `sleep` holding our stdout blocks any
caller reading us with `$( … )` for the full 30 seconds after we have finished.
