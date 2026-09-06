#!/usr/bin/env bash
#
# board-serve.test.sh — the local board server: port derivation, the one-per-bundle
# collision message, and the containment boundary.
#
# THE SECURITY HALF IS MEASURED, NEVER ASSERTED. `..` in a URL is normalised away by most
# clients before it reaches a socket, so a traversal "test" written with a plain `curl`
# proves the client behaves, not the server. Every request below is written onto a raw
# socket, byte for byte, and the control (`/board.html` -> 200) is what keeps the 404s
# from being the answer a dead server would also give.
#
# THE LOOPBACK BIND IS MEASURED THE ONLY WAY A HARNESS CAN: connect to this machine's own
# non-loopback address and require a refusal. No route, or no non-loopback address, is
# reported as SKIP rather than as a pass — a bind check that quietly certifies a machine
# it could not reach is worse than no check.
#
# EVERY SERVER THIS FILE STARTS CARRIES A DETACHED WATCHDOG, per CONVENTIONS.md: the
# subject is a resident process, so an interrupted run would otherwise leave one holding a
# port until the machine is rebooted (measured while writing this file — one did).
#
# ok() follows this directory's convention: it compares actual to expected.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SERVE="$REPO/plugin/scripts/board-serve.sh"
WRITER="$REPO/plugin/scripts/write-snapshot.sh"
for f in "$SERVE" "$WRITER"; do
  [ -f "$f" ] || { echo "board-serve.test: missing $f" >&2; exit 2; }
done
command -v python3 >/dev/null 2>&1 || { echo "board-serve.test: needs python3" >&2; exit 2; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/board-serve.XXXXXX")" \
  || { echo "board-serve.test: mktemp -d failed under TMPDIR=${TMPDIR:-/tmp}" >&2; exit 2; }
PIDS=""
cleanup() {
  for p in $PIDS; do kill -TERM "$p" 2>/dev/null; done
  rm -rf "$TMP"
}
trap cleanup EXIT

pass=0; fail=0; skip=0
ok() { # <name> <actual> <expected>
  if [ "$2" = "$3" ]; then printf '  PASS  %-62s (%s)\n' "$1" "$2"; pass=$((pass+1))
  else printf '  FAIL  %-62s got %s, want %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}
skipped() { printf '  SKIP  %s\n' "$1"; skip=$((skip+1)); }
yes_if() { if "$@" >/dev/null 2>&1; then echo yes; else echo no; fi; }

new_instance() { # <dir>
  mkdir -p "$1/projects/p/tasks"
  : > "$1/SCHEMA.md"
  cat > "$1/instance.config.json" <<CFG
{ "org": "fixture-org", "reposRoot": "$TMP/repos" }
CFG
  cat > "$1/projects/p/project.md" <<'PRJ'
---
type: Project
title: Demo
kind: build
status: active
---
PRJ
  cat > "$1/projects/p/tasks/task-001.md" <<'TSK'
---
type: Task
title: Do a thing
kind: build
status: ready
assignee: software-engineer
---
TSK
  touch "$1/SNAPSHOT.json"
  ( cd "$1" && SNAPSHOT_NOW=2026-09-06T00:00:00Z bash "$WRITER" --quiet )
}

# A raw HTTP GET: the request line is written verbatim, so `..` and `%2e%2e` reach the
# server exactly as typed. Prints the status code, or `000`.
raw_get() { # <port> <request-target>
  python3 - "$1" "$2" <<'PY'
import socket, sys
port, target = int(sys.argv[1]), sys.argv[2]
try:
    s = socket.create_connection(("127.0.0.1", port), timeout=5)
    s.sendall(("GET %s HTTP/1.0\r\nHost: localhost\r\n\r\n" % target).encode())
    data = b""
    while len(data) < 4096:
        chunk = s.recv(4096)
        if not chunk:
            break
        data += chunk
    s.close()
    print(data.split(b"\r\n", 1)[0].split(b" ")[1].decode())
except Exception:
    print("000")
PY
}

body_of() { # <port> <request-target>
  python3 - "$1" "$2" <<'PY'
import socket, sys
port, target = int(sys.argv[1]), sys.argv[2]
try:
    s = socket.create_connection(("127.0.0.1", port), timeout=5)
    s.sendall(("GET %s HTTP/1.0\r\nHost: localhost\r\n\r\n" % target).encode())
    data = b""
    while True:
        chunk = s.recv(65536)
        if not chunk:
            break
        data += chunk
    s.close()
    sys.stdout.write(data.split(b"\r\n\r\n", 1)[-1].decode("utf-8", "replace"))
except Exception:
    pass
PY
}

# `exec` so the subshell BECOMES the server: $! is then the pid a TERM has to reach, and
# the pid the state file must name. Without it the subshell dies and python does not.
start_server() { # <instance dir> <logfile> — starts, watchdogs, waits for the port
  ( cd "$1" && exec bash "$SERVE" ) > "$2" 2>&1 &
  local p=$!
  PIDS="$PIDS $p"
  ( sleep 120; kill -TERM "$p" 2>/dev/null ) >/dev/null 2>&1 &
  local port deadline
  port="$(cd "$1" && bash "$SERVE" --print-port)"
  deadline=$(( $(date +%s) + 20 ))
  while [ "$(date +%s)" -lt "$deadline" ]; do
    [ "$(raw_get "$port" /__bundle)" = "200" ] && break
    sleep 1
  done
  printf '%s' "$p"
}

echo "== 1. the port derives from the bundle path, stably, in the 4xxxx band =="
A="$TMP/group/_ai-bridge-alpha"
B="$TMP/group/_ai-bridge-beta"
new_instance "$A"; new_instance "$B"

PA="$(cd "$A" && bash "$SERVE" --print-port)"
PA2="$(cd "$A" && bash "$SERVE" --print-port)"
PB="$(cd "$B" && bash "$SERVE" --print-port)"
ok "the same bundle answers on the same port twice"   "$PA" "$PA2"
ok "two bundles get two ports"                        "$([ "$PA" != "$PB" ] && echo yes || echo no)" yes
ok "alpha's port is in the 4xxxx band"                "$([ "$PA" -ge 40000 ] && [ "$PA" -le 49999 ] && echo yes || echo no)" yes
ok "beta's port is in the 4xxxx band"                 "$([ "$PB" -ge 40000 ] && [ "$PB" -le 49999 ] && echo yes || echo no)" yes

# THE FORMULA, PINNED TWICE. Restating it here catches a change to the script; the
# `cksum` literal catches the platform disagreeing, which is the failure a restatement
# alone would carry straight through (`cksum` is POSIX and must answer the same on macOS
# and on Linux — if it ever does not, two machines derive two ports for one bundle).
ok "cksum is the POSIX CRC on this platform"          "$(printf 'ai-bridge' | cksum | awk '{print $1}')" 638729929
ok "…and the port is 40000 + cksum(path) % 10000"     "$PA" \
  "$(( 40000 + $(printf '%s' "$(cd "$A" && pwd -P)" | cksum | awk '{print $1}') % 10000 ))"

printf '{ "boardPort": 41234 }\n' > "$A/instance.config.local.json"
ok "boardPort in the LOCAL config wins over the derivation" "$(cd "$A" && bash "$SERVE" --print-port)" 41234
printf '{ "boardPort": 41234 }\n' > "$B/instance.config.json"
ok "…and the TRACKED config is not read for it (per-machine key)" "$(cd "$B" && bash "$SERVE" --print-port)" "$PB"
rm -f "$A/instance.config.local.json" "$B/instance.config.json"
new_instance "$B" >/dev/null

ok "outside an instance root it says nothing and exits 0" \
  "$(cd "$TMP" && bash "$SERVE" --print-port 2>&1; echo "rc=$?")" "rc=0"

echo
echo "== 2. one process per bundle: a second start says so and exits 0 =="
SRV_A="$(start_server "$A" "$TMP/a.log")"
ok "the server came up"                               "$(raw_get "$PA" /__bundle)" 200
ok "…and the state file names its live pid"          "$(sed -n 2p "$A/.board-live/.serve")" "$SRV_A"
SECOND="$(cd "$A" && bash "$SERVE" 2>&1; echo "rc=$?")"
ok "a second start exits 0"                           "$(printf '%s' "$SECOND" | tail -1)" "rc=0"
ok "…and names the port as already served"            \
  "$(yes_if grep -qF "already served — http://localhost:$PA" <<<"$SECOND")" yes

# A FOREIGN holder of the port is a different answer, and it has to be: telling a human
# "already served" about somebody else's process sends them to a page that is not theirs.
# The holder goes to a FILE first: a heredoc spawn puts its own body between the `&` and
# the watchdog, and background-teardown.test.sh's scanner reads it as an unbounded spawn.
cat > "$TMP/hold.py" <<'PY'
import socket, sys, time
s = socket.socket(); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(("127.0.0.1", int(sys.argv[1]))); s.listen(1)
time.sleep(60)
PY
python3 "$TMP/hold.py" "$PB" > "$TMP/foreign.log" 2>&1 &
FPID=$!
( sleep 90; kill -TERM "$FPID" 2>/dev/null ) >/dev/null 2>&1 &
PIDS="$PIDS $FPID"
sleep 2
FOUT="$(cd "$B" && bash "$SERVE" 2>&1; echo "rc=$?")"
ok "a port held by something else exits 3"            "$(printf '%s' "$FOUT" | tail -1)" "rc=3"
ok "…and says to set boardPort instead"               \
  "$(yes_if grep -qF 'set "boardPort" in instance.config.local.json' <<<"$FOUT")" yes
kill -TERM "$FPID" 2>/dev/null; wait "$FPID" 2>/dev/null

echo
echo "== 3. it serves .board-live/ and nothing else =="
ln -sf "$A/instance.config.json" "$A/.board-live/leak.json"
ok "CONTROL: the board page itself is served"         "$(raw_get "$PA" /board.html)" 200
ok "…and / is the board page"                         "$(raw_get "$PA" /)" 200
ok "a raw ../instance.config.json is 404"             "$(raw_get "$PA" /../instance.config.json)" 404
ok "…percent-encoded too"                             "$(raw_get "$PA" /%2e%2e%2finstance.config.json)" 404
ok "…and doubled up"                                  "$(raw_get "$PA" /../../../etc/passwd)" 404
ok "an absolute path is 404"                          "$(raw_get "$PA" //etc/passwd)" 404
ok "a symlink OUT of .board-live/ is 404"             "$(raw_get "$PA" /leak.json)" 404
ok "…so no config byte reached the wire"              \
  "$(yes_if sh -c '! grep -q fixture-org "$1"' _ <(body_of "$PA" /leak.json))" yes

# THE BIND. Connect to this machine's own non-loopback address; a server bound to
# 127.0.0.1 refuses it. Unreachable address => SKIP, never a pass.
LANIP="$(python3 - <<'PY'
import socket
try:
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.connect(("192.0.2.1", 9))
    ip = s.getsockname()[0]
    s.close()
    print("" if ip.startswith("127.") else ip)
except Exception:
    print("")
PY
)"
if [ -z "$LANIP" ]; then
  skipped "no non-loopback address on this machine — the bind is not measured here"
else
  REACH="$(python3 - "$LANIP" "$PA" <<'PY'
import socket, sys
try:
    socket.create_connection((sys.argv[1], int(sys.argv[2])), timeout=3).close()
    print("reachable")
except Exception:
    print("refused")
PY
)"
  ok "the port is NOT reachable on $LANIP (127.0.0.1 only)" "$REACH" refused
fi

echo
echo "== 4. it re-renders on a snapshot change, and the page reloads itself =="
ok "the served page carries the auto-reload poller"    \
  "$(yes_if grep -qF "fetch('/__rev')" <(body_of "$PA" /board.html))" yes
REV0="$(body_of "$PA" /__rev)"
sed -i.bak 's/Do a thing/Do another thing/' "$A/projects/p/tasks/task-001.md"
( cd "$A" && SNAPSHOT_NOW=2026-09-06T00:05:00Z bash "$WRITER" --quiet )
DEADLINE=$(( $(date +%s) + 5 ))
while [ "$(date +%s)" -lt "$DEADLINE" ]; do
  REV1="$(body_of "$PA" /__rev)"
  [ "$REV1" != "$REV0" ] && break
  sleep 1
done
ok "the revision moved within 5s of the snapshot changing" \
  "$([ "${REV1:-}" != "$REV0" ] && echo yes || echo no)" yes
ok "…and the new title is on the page"                 \
  "$(yes_if grep -qF 'Do another thing' <(body_of "$PA" /board.html))" yes

kill -TERM "$SRV_A" 2>/dev/null
sleep 1
ok "stopping it removes the state file the banner reads" \
  "$(yes_if sh -c '! test -e "$1"' _ "$A/.board-live/.serve")" yes

echo
echo "== 5. no LLM anywhere in the path =="
ok "board-serve.sh invokes no model"                   \
  "$(grep -cE '(^|[^a-z-])claude( |$)|anthropic|--model' "$SERVE")" 0
ok "…and reads SNAPSHOT.json through build-board.sh only" \
  "$(yes_if grep -qF 'build-board.sh' "$SERVE")" yes
# THE ALLOWLIST IS THE SPEC. The server may not reach past the snapshot to a task document,
# a project document or the config — the renderer's input is one file and that is what the
# field allowlist is scoped for.
ok "…and opens no task or project document"           \
  "$(grep -cE 'projects/|/tasks/' "$SERVE")" 0
ok "…and only TESTS for the tracked config, never reads it" \
  "$(grep -n 'instance\.config\.json' "$SERVE" | grep -cv -- '-f instance\.config\.json')" 0

echo
echo "pass=$pass fail=$fail skip=$skip"
[ "$fail" -eq 0 ]
