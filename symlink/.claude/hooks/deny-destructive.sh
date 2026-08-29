#!/usr/bin/env bash
#
# deny-destructive.sh — PreToolUse hook (ai-bridge machinery). The destructive-action
# deny baseline: the layer an agent cannot talk past.
#
# WHY THIS EXISTS. `permissions.deny` was empty in every live instance while agents ran
# unattended against real credentials. A prose rule ("don't touch the production
# database") is a request an agent may decline; this refuses the tool call before it
# runs, in the harness, the same category as branch protection.
#
# ------------------------------------------------- WHY A HOOK AND NOT `permissions.deny`
# `permissions.deny` matches a command PREFIX. Every shape actually worth denying is
# CONDITIONAL on something a prefix cannot see:
#
#   · `DROP TABLE` matters against a remote host and is routine against a test container;
#   · `kubectl delete pod` is routine, `kubectl delete namespace` is not;
#   · `rm -rf node_modules` is routine, `rm -rf <repo root>` is not — and which is which
#     depends on the session's cwd;
#   · `git push --force` to a feature branch is routine, to the default branch it is not.
#
# Written as prefixes, each of those is either too broad (and gets deleted, which is the
# failure mode of every over-strict lint — a baseline nobody keeps protects nothing) or
# too narrow (and is FALSE COMFORT, which is worse than nothing). A hook sees the whole
# command, the cwd and the repo, so each rule can be narrow enough to keep. It is also
# the only form that can be PROVEN: `tests/deny-baseline.test.sh` feeds this script real
# payloads and asserts both directions per rule.
#
# `settings.json` keeps a short `permissions.deny` block for the handful of shapes that
# ARE unconditional. Those are a redundant second layer, deliberately duplicated by rules
# here; nothing depends on them. See docs/conventions.md §19.
#
# ------------------------------------------------------------------- HOW TO ADD A RULE
# Three edits, no new mechanism:
#   1. write `rule_<name>()` below — print the reason to stdout and `return 0` to DENY,
#      `return 1` to allow. It is handed the full command string;
#   2. add `<name>` to `RULES`;
#   3. add BOTH directions to `tests/deny-baseline.test.sh` — the shape it denies AND a
#      neighbouring legitimate command it must still allow. A rule with only the refusal
#      half would pass while denying everything.
# Rules run in order and the first denial wins, so ordering only affects which reason the
# agent is shown.
#
# --------------------------------------------------------------- THE ESCAPE HATCH IS REAL
# Every rule here can be satisfied by a human running the command in their own terminal,
# outside the harness. That is deliberate: it means no rule has to be widened for a
# legitimate emergency, so no instance has a reason to switch the baseline off. The deny
# message says so, and tells the agent NOT to re-issue a variant that evades the pattern.
#
# --------------------------------------------------------------------- FAIL OPEN, LOUD
# This sits in front of every Bash call in every session, so an infrastructure failure —
# no `jq`, an unparseable payload — logs to stderr and lets the call through. A guard
# that blocks all work because its own plumbing broke is a guard that gets removed. A
# rule that MATCHES always denies; only the plumbing fails open. `set -e` is deliberately
# not used, for the same reason as agent-control.sh: an unexpected non-zero would surface
# as a "non-blocking error" on every tool call.
#
# A refusal is JSON on STDOUT. This script's only exit status is 0 — exit 2 would also
# block, but it routes the reason through stderr where it is mixed with noise.
#
# ------------------------------------------------------------------------ WHAT IT IS NOT
# Pattern matching over a command string. It stops the named shapes, not every route to
# the same outcome: a path built from a variable, SQL read from a file, a wrapper script,
# a language runtime. It raises the floor. THE REAL BOUNDARY IS CREDENTIALS — an agent
# that cannot reach production cannot harm it whatever it decides. This is not a
# substitute for that audit.
set -uo pipefail

# ------------------------------------------------------------------------------- payload
payload="$(cat 2>/dev/null || true)"
[ -n "$payload" ] || exit 0

# jq, hard, for the same reason agent-control.sh requires it: `tool_input` is arbitrary
# nested JSON and a grep/sed parser can be fooled by a command that CONTAINS the keys it
# looks for. Absent ⇒ log and fail open.
if ! command -v jq >/dev/null 2>&1; then
  echo "deny-destructive: jq not found — destructive-action baseline is NOT enforced in this session" >&2
  exit 0
fi

tool="$(printf '%s' "$payload" | jq -r '.tool_name // ""' 2>/dev/null || true)"
[ "$tool" = "Bash" ] || exit 0

CMD="$(printf '%s' "$payload" | jq -r '.tool_input.command // ""' 2>/dev/null || true)"
[ -n "$CMD" ] || exit 0

CWD="$(printf '%s' "$payload" | jq -r '.cwd // ""' 2>/dev/null || true)"
[ -n "$CWD" ] && [ -d "$CWD" ] || CWD="$PWD"
# PHYSICAL, IMMEDIATELY. `git rev-parse --show-toplevel` always answers with symlinks
# resolved, so a session whose cwd is reported through a symlink (on macOS every path under
# `mktemp -d` is: `/var/...` vs `/private/var/...`) would compare a lexical path against a
# resolved one and MISS. This trap has bitten this codebase repeatedly — see
# .claude/rules/tests.md, "Compare resolved paths".
CWD="$(cd "$CWD" 2>/dev/null && pwd -P || printf '%s' "$CWD")"

# ------------------------------------------------------------------------------ plumbing
# bash 3.2 is the floor (macOS ships it, and CI runs macOS): no associative arrays, no
# `${v,,}`, no `mapfile`.
SEP="$(printf '\001')"

lower() { printf '%s' "$1" | tr 'ABCDEFGHIJKLMNOPQRSTUVWXYZ' 'abcdefghijklmnopqrstuvwxyz'; }

# One command per line. `&&`, `||`, `;` and newline end a command; `|` does NOT, so a
# pipeline stays one line here — the exfiltration rule needs `cat .env | curl …` intact.
segments() {
  local s="$1"
  s="${s//&&/$SEP}"
  s="${s//||/$SEP}"
  s="${s//;/$SEP}"
  s="${s//$'\n'/$SEP}"
  printf '%s' "$s" | tr "$SEP" '\n'
}

# One pipeline STAGE per line — segments split further on `|`. Command-oriented rules use
# this so `terraform destroy | tee log` is still seen as a `terraform` invocation.
stages() {
  local s="$1"
  s="${s//&&/$SEP}"
  s="${s//||/$SEP}"
  s="${s//;/$SEP}"
  s="${s//$'\n'/$SEP}"
  printf '%s' "$s" | tr "$SEP|" '\n\n'
}

# One token per line, surrounding quotes stripped. Redirections, subshell parens and
# backticks become separators so `$(cat .env)` yields `.env` as its own token.
tokens_of() {
  printf '%s' "$1" \
    | tr '<>()`' '     ' \
    | tr ' \t' '\n\n' \
    | sed -e 's/^["'"'"']*//' -e 's/["'"'"']*$//' \
    | grep -v '^[[:space:]]*$'
}

# The command word of a stage: the first token that is not an environment assignment, a
# flag, or a wrapper that takes another command as its argument.
first_word() {
  local w
  while IFS= read -r w; do
    case "$w" in
      [A-Za-z_]*=*) continue ;;
      env|sudo|nohup|time|command|exec|nice|ionice|stdbuf|xargs) continue ;;
      -*) continue ;;
      *) printf '%s' "${w##*/}"; return 0 ;;
    esac
  done <<EOF
$(tokens_of "$1")
EOF
  return 1
}

# The first non-flag token after <word>. `kubectl delete` ⇒ the resource kind.
word_after() { # <stage> <word>
  local w seen=0
  while IFS= read -r w; do
    if [ "$seen" = 0 ]; then
      [ "$w" = "$2" ] && seen=1
      continue
    fi
    case "$w" in
      -*) continue ;;
      [A-Za-z_]*=*) continue ;;
      *) printf '%s' "$w"; return 0 ;;
    esac
  done <<EOF
$(tokens_of "$1")
EOF
  return 1
}

has_token() { # <stage> <token>
  local w
  while IFS= read -r w; do
    [ "$w" = "$2" ] && return 0
  done <<EOF
$(tokens_of "$1")
EOF
  return 1
}

# The value of `-x val` / `--flag val` / `--flag=val`.
flag_value() { # <stage> <flag> [flag...]
  local stage="$1"; shift
  local w f want=0
  while IFS= read -r w; do
    if [ "$want" = 1 ]; then printf '%s' "$w"; return 0; fi
    for f in "$@"; do
      case "$w" in
        "$f") want=1; break ;;
        "$f"=*) printf '%s' "${w#*=}"; return 0 ;;
      esac
    done
  done <<EOF
$(tokens_of "$stage")
EOF
  return 1
}

# A generic naming convention, not an org literal: `prod` / `production` / `prd` / `live`
# as a whole dash/underscore/dot-delimited token. Substring matching would fire on
# `reproduce` and on `alive`.
looks_production() { # <string>
  local s; s="$(lower "$1")"
  case "$s" in
    prod|production|prd|live) return 0 ;;
    *[-_.]prod|*[-_.]production|*[-_.]prd|*[-_.]live) return 0 ;;
    prod[-_.]*|production[-_.]*|prd[-_.]*|live[-_.]*) return 0 ;;
    *[-_.]prod[-_.]*|*[-_.]production[-_.]*|*[-_.]prd[-_.]*|*[-_.]live[-_.]*) return 0 ;;
  esac
  return 1
}

# `git` is consulted at most once per rule that needs it, and only when that rule has
# already matched a command shape — a hook in front of every Bash call must not pay for
# two subprocesses it will not use.
_repo_root=""; _repo_root_done=0
repo_root() {
  if [ "$_repo_root_done" = 0 ]; then
    _repo_root_done=1
    _repo_root="$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null || true)"
  fi
  printf '%s' "$_repo_root"
}

_default_branch=""; _default_branch_done=0
default_branch() {
  if [ "$_default_branch_done" = 0 ]; then
    _default_branch_done=1
    _default_branch="$(git -C "$CWD" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null || true)"
    _default_branch="${_default_branch#*/}"
  fi
  printf '%s' "$_default_branch"
}

# Lexical, not `realpath`: the target of an `rm -rf` may not exist, and resolving symlinks
# is not wanted here — `rm -rf <symlink-to-repo>` is a different command.
norm_path() { # <path>
  local p="$1" out="" part oldopts
  case "$p" in
    "~") p="$HOME" ;;
    "~/"*) p="$HOME/${p#\~/}" ;;
  esac
  p="${p//\$\{HOME\}/$HOME}"
  p="${p//\$HOME/$HOME}"
  case "$p" in /*) ;; *) p="$CWD/$p" ;; esac
  oldopts="$(set +o | grep noglob)"
  set -f
  local IFS=/
  for part in $p; do
    case "$part" in
      ""|.) ;;
      ..) out="${out%/*}" ;;
      *) out="$out/$part" ;;
    esac
  done
  eval "$oldopts"
  printf '%s' "${out:-/}"
}

# The physical form of a path — symlinks resolved — for the comparison above. Falls back to
# the input when nothing on the path exists, which is the right answer for a target that is
# already gone.
phys() { # <path>
  local d b r
  if [ -d "$1" ]; then
    r="$(cd "$1" 2>/dev/null && pwd -P)" && { printf '%s' "$r"; return 0; }
  fi
  b="${1##*/}"; d="${1%/*}"; [ -n "$d" ] || d="/"
  if [ "$d" != "$1" ] && [ -d "$d" ]; then
    r="$(cd "$d" 2>/dev/null && pwd -P)" && { printf '%s/%s' "${r%/}" "$b"; return 0; }
  fi
  printf '%s' "$1"
}

# 0 when <p> IS <x> or is an ancestor directory of <x>.
covers() { # <p> <x>
  [ -n "$1" ] && [ -n "$2" ] || return 1
  [ "$1" = "$2" ] && return 0
  [ "$1" = "/" ] && return 0
  case "$2" in "$1"/*) return 0 ;; esac
  return 1
}

# =============================================================================== RULES ==
# Print the reason, `return 0` to DENY. See "HOW TO ADD A RULE" at the top.
RULES="terraform_destroy k8s_irreversible_delete k8s_production_target sql_destructive_remote rm_rf_repo_root force_push_protected secret_exfiltration"

# --- terraform_destroy --------------------------------------------------------------- #
# JUSTIFIED BY: `destroy` deletes real infrastructure and there is no legitimate agent
# task that needs it unattended. NARROW ENOUGH TO KEEP: `terraform plan -destroy` — the
# read-only "what would this remove?" query, which is the thing an agent actually needs —
# is explicitly allowed, as is every other terraform subcommand including `apply`.
rule_terraform_destroy() {
  local stage c sub
  while IFS= read -r stage; do
    [ -n "$stage" ] || continue
    c="$(first_word "$stage")" || continue
    case "$c" in terraform|tofu|terragrunt) ;; *) continue ;; esac
    sub="$(word_after "$stage" "$c" || true)"
    [ "$sub" = "plan" ] && continue
    if has_token "$stage" destroy || has_token "$stage" -destroy || has_token "$stage" --destroy; then
      printf '`%s destroy` (or `apply -destroy`) tears down real infrastructure, and a plan file is not consulted here. `%s plan -destroy` answers the same question without acting and is allowed.' "$c" "$c"
      return 0
    fi
  done <<EOF
$(stages "$1")
EOF
  return 1
}

# --- k8s_irreversible_delete --------------------------------------------------------- #
# JUSTIFIED BY: these kinds cannot be recreated from the cluster. A namespace delete
# cascades to everything in it; a PV/PVC delete destroys data; a CRD delete destroys every
# custom resource of that type; a node delete evicts a machine. `--all` turns any of them
# into a sweep. NARROW ENOUGH TO KEEP: the routine deletes — pod, job, deployment,
# configmap, secret, ingress, `-f manifest.yaml` — are all still allowed, in any namespace.
rule_k8s_irreversible_delete() {
  local stage c sub kind k
  local irreversible="namespace namespaces ns persistentvolume persistentvolumes pv persistentvolumeclaim persistentvolumeclaims pvc customresourcedefinition customresourcedefinitions crd crds node nodes"
  while IFS= read -r stage; do
    [ -n "$stage" ] || continue
    c="$(first_word "$stage")" || continue
    case "$c" in kubectl|oc) ;; *) continue ;; esac
    sub="$(word_after "$stage" "$c" || true)"
    [ "$sub" = "delete" ] || continue
    if has_token "$stage" --all || has_token "$stage" --all-namespaces || has_token "$stage" -A; then
      printf '`%s delete --all` deletes every matching object in scope at once. Name the objects you mean, or hand this to the human.' "$c"
      return 0
    fi
    kind="$(word_after "$stage" delete || true)"
    kind="$(lower "${kind%%/*}")"
    for k in $irreversible; do
      if [ "$kind" = "$k" ]; then
        printf 'Deleting a `%s` is not recoverable from the cluster — it cascades to the objects (or the data) it owns. Routine deletes (pod, job, deployment, configmap, `-f manifest.yaml`) are still allowed.' "$kind"
        return 0
      fi
    done
  done <<EOF
$(stages "$1")
EOF
  return 1
}

# --- k8s_production_target ----------------------------------------------------------- #
# JUSTIFIED BY: the namespace or context is the only production signal available in the
# command itself. NARROW ENOUGH TO KEEP: only DESTRUCTIVE verbs are covered (`delete`,
# `drain`, `helm uninstall`) — `get`, `logs`, `describe`, `apply`, `helm upgrade` against
# production are untouched, so reading and deploying still work. The `dev` half of the
# task's "outside a dev namespace" wording is deliberately NOT implemented as
# "deny unless namespace == dev": namespace naming is per-org, and a deny-unless list
# would refuse every routine delete in a namespace whose name this file cannot know.
rule_k8s_production_target() {
  local stage c sub ns ctx target
  while IFS= read -r stage; do
    [ -n "$stage" ] || continue
    c="$(first_word "$stage")" || continue
    case "$c" in kubectl|oc|helm) ;; *) continue ;; esac
    sub="$(word_after "$stage" "$c" || true)"
    case "$c:$sub" in
      kubectl:delete|kubectl:drain|oc:delete|oc:drain|helm:uninstall|helm:delete) ;;
      *) continue ;;
    esac
    ns="$(flag_value "$stage" -n --namespace || true)"
    ctx="$(flag_value "$stage" --context --kube-context || true)"
    target=""
    looks_production "$ns" && target="namespace \`$ns\`"
    [ -z "$target" ] && looks_production "$ctx" && target="context \`$ctx\`"
    if [ -n "$target" ]; then
      printf '`%s %s` against %s. Read-only verbs and `apply`/`upgrade` against the same target are still allowed; a destructive one belongs to a human at a terminal.' "$c" "$sub" "$target"
      return 0
    fi
  done <<EOF
$(stages "$1")
EOF
  return 1
}

# --- sql_destructive_remote ---------------------------------------------------------- #
# JUSTIFIED BY: this is the shape the owner named. NARROW ENOUGH TO KEEP: a LOCAL client
# call is untouched, which is where an agent's legitimate database work happens — a test
# container reached over the default unix socket, or explicitly on `localhost`. Only a
# non-local target is refused.
#
# AN UNRESOLVABLE TARGET COUNTS AS NON-LOCAL. `psql "$DATABASE_URL" -c 'DROP TABLE …'` is
# exactly the command that reaches production from a session holding live credentials, and
# reading the variable to find out is not available here. The reason names the fix
# (`-h localhost`) for the case where it really was local.
rule_sql_destructive_remote() {
  local stage c verb host w unresolved seen
  while IFS= read -r stage; do
    [ -n "$stage" ] || continue
    c="$(first_word "$stage")" || continue
    case "$c" in psql|mysql|mariadb|mongosh|mongo|clickhouse-client|cockroach|sqlcmd) ;; *) continue ;; esac

    verb=""
    case "$(printf '%s' "$stage" | tr '\n\t' '  ' | tr -s ' ' | tr 'ABCDEFGHIJKLMNOPQRSTUVWXYZ' 'abcdefghijklmnopqrstuvwxyz')" in
      *"drop database"*) verb="DROP DATABASE" ;;
      *"drop table"*)    verb="DROP TABLE" ;;
      *"drop schema"*)   verb="DROP SCHEMA" ;;
      *truncate*)        verb="TRUNCATE" ;;
    esac
    [ -n "$verb" ] || continue

    # A connection target that is a shell variable cannot be judged.
    unresolved=0; seen=0
    while IFS= read -r w; do
      if [ "$seen" = 0 ]; then [ "$w" = "$c" ] && seen=1; continue; fi
      case "$w" in *'$'*|*'`'*) unresolved=1; break ;; esac
    done <<EOT
$(tokens_of "$stage")
EOT

    host=""
    while IFS= read -r w; do
      case "$w" in
        postgres://*|postgresql://*|mysql://*|mongodb://*|mongodb+srv://*|clickhouse://*)
          host="${w#*://}"; host="${host##*@}"; host="${host%%/*}"; host="${host%%\?*}"; host="${host%%:*}"
          break ;;
      esac
    done <<EOT
$(tokens_of "$stage")
EOT
    [ -n "$host" ] || host="$(flag_value "$stage" -h --host --hostname || true)"
    [ -n "$host" ] || host="$(flag_value "$stage" PGHOST MYSQL_HOST MYSQL_TCP_ADDR || true)"

    if [ -z "$host" ] && [ "$unresolved" = 0 ]; then
      continue   # no host named and nothing hidden ⇒ local socket ⇒ allowed
    fi
    case "$(lower "$host")" in
      localhost|127.0.0.1|0.0.0.0|::1|host.docker.internal|*.localhost|/*) continue ;;
      127.*) continue ;;
    esac

    if [ "$unresolved" = 1 ] && [ -z "$host" ]; then
      printf '`%s` with `%s` and a connection target this guard cannot read (it comes from a variable). A session holding live credentials reaches production exactly this way. If the target really is local, say so — `-h localhost` — and this is allowed.' "$c" "$verb"
    else
      printf '`%s` against the non-local host `%s`. Destructive DDL on a remote database is not something an agent should issue; run it yourself, at a terminal, if it is right. Local targets (`-h localhost`, or the default socket) are allowed.' "$verb" "$host"
    fi
    return 0
  done <<EOF
$(stages "$1")
EOF
  return 1
}

# --- rm_rf_repo_root ----------------------------------------------------------------- #
# JUSTIFIED BY: a recursive delete at or above the working tree destroys uncommitted and
# unpushed work, and above the repo it takes sibling clones and worktrees with it.
# NARROW ENOUGH TO KEEP: everything BELOW the repo root is allowed — `rm -rf node_modules`,
# `rm -rf dist`, `rm -rf .pnpm-store` — and so is any path outside the repo that is not at
# or above `$HOME`, which keeps every `rm -rf "$TMP"` fixture cleanup working.
#
# A PATH BUILT FROM A VARIABLE IS ALLOWED, not denied: `rm -rf "$TMP"` is the single most
# common legitimate recursive delete in this codebase, and denying what it cannot resolve
# would make this the rule an instance switches the baseline off to escape. `$HOME` and
# `~` are the two it does resolve.
rule_rm_rf_repo_root() {
  local stage c w recursive seen op p root
  while IFS= read -r stage; do
    [ -n "$stage" ] || continue
    c="$(first_word "$stage")" || continue
    [ "$c" = "rm" ] || continue

    recursive=0
    while IFS= read -r w; do
      case "$w" in
        --recursive) recursive=1 ;;
        --*) ;;
        -*[rR]*) recursive=1 ;;
      esac
    done <<EOT
$(tokens_of "$stage")
EOT
    [ "$recursive" = 1 ] || continue

    root="$(repo_root)"
    seen=0
    while IFS= read -r w; do
      if [ "$seen" = 0 ]; then [ "$w" = "rm" ] && seen=1; continue; fi
      case "$w" in -*) continue ;; esac
      op="$w"
      case "$op" in *'$'*|*'`'*) continue ;; esac
      # A trailing glob means "everything in the parent", so judge the parent.
      case "$op" in
        */\*) op="${op%/\*}" ;;
        \*) op="." ;;
        *\*) continue ;;
      esac
      p="$(phys "$(norm_path "$op")")"
      if [ "$p" = "/" ]; then
        printf '`rm -r /` — refused.'
        return 0
      fi
      if covers "$p" "$(phys "$HOME")"; then
        printf '`rm -r %s` is at or above your home directory.' "$p"
        return 0
      fi
      if [ -n "$root" ] && covers "$p" "$root"; then
        printf '`rm -r %s` is at or above the root of the working tree (`%s`) — it would take uncommitted and unpushed work, and anything alongside it. Deleting a path INSIDE the tree (build output, node_modules, a scratch dir) is allowed.' "$p" "$root"
        return 0
      fi
    done <<EOT
$(tokens_of "$stage")
EOT
  done <<EOF
$(stages "$1")
EOF
  return 1
}

# --- force_push_protected ------------------------------------------------------------ #
# JUSTIFIED BY: a force-push or a delete of the default branch discards commits on the one
# ref nothing else can reconstruct, and every role agent in this bundle pushes for a
# living. NARROW ENOUGH TO KEEP: force-pushing a FEATURE branch is normal work after a
# rebase and stays allowed, as does every non-force push, including to the default branch
# (this control panel commits straight to it by design).
rule_force_push_protected() {
  local stage c w seen sub skipnext force del args remote r d dst p protected oldopts
  while IFS= read -r stage; do
    [ -n "$stage" ] || continue
    c="$(first_word "$stage")" || continue
    [ "$c" = "git" ] || continue

    seen=0; sub=""; skipnext=0; force=0; del=0; args=""
    while IFS= read -r w; do
      if [ "$skipnext" = 1 ]; then skipnext=0; continue; fi
      if [ "$seen" = 0 ]; then [ "$w" = "git" ] && seen=1; continue; fi
      if [ -z "$sub" ]; then
        case "$w" in
          -C|-c|--git-dir|--work-tree|--namespace|--exec-path) skipnext=1; continue ;;
          -*) continue ;;
          *) sub="$w"; continue ;;
        esac
      fi
      case "$w" in
        --force|--force-with-lease|--force-with-lease=*|--force-if-includes) force=1 ;;
        --delete) del=1 ;;
        --*) ;;
        -*) case "$w" in *f*) force=1 ;; esac
            case "$w" in *d*) del=1 ;; esac ;;
        *) args="$args $w" ;;
      esac
    done <<EOT
$(tokens_of "$stage")
EOT
    [ "$sub" = "push" ] || continue

    # First positional is the remote; the rest are refspecs.
    oldopts="$(set +o | grep noglob)"; set -f
    # shellcheck disable=SC2086  # deliberate split; globbing is off for the duration
    set -- $args
    eval "$oldopts"
    remote="${1:-}"; [ "$#" -gt 0 ] && shift

    dst=""
    if [ "$#" -eq 0 ]; then
      d="$(git -C "$CWD" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
      [ "$d" = "HEAD" ] && d=""
      dst="$d"
    else
      for r in "$@"; do
        case "$r" in +*) force=1; r="${r#+}" ;; esac
        case "$r" in :*) del=1 ;; esac
        case "$r" in *:*) r="${r##*:}" ;; esac
        r="${r#refs/heads/}"
        dst="$dst $r"
      done
    fi
    [ -n "${dst// /}" ] || continue
    { [ "$force" = 1 ] || [ "$del" = 1 ]; } || continue

    protected="main master develop trunk production"
    d="$(default_branch)"
    [ -n "$d" ] && protected="$protected $d"
    for r in $dst; do
      for p in $protected; do
        if [ "$r" = "$p" ]; then
          if [ "$del" = 1 ]; then
            printf 'Deleting the protected branch `%s` on `%s`.' "$p" "${remote:-origin}"
          else
            printf 'Force-pushing to the protected branch `%s` on `%s` discards commits nothing else can reconstruct. Force-pushing a FEATURE branch is allowed, and so is a normal (non-force) push to `%s`.' "$p" "${remote:-origin}" "$p"
          fi
          return 0
        fi
      done
    done
  done <<EOF
$(stages "$1")
EOF
  return 1
}

# --- secret_exfiltration ------------------------------------------------------------- #
# JUSTIFIED BY: this is the one shape where a single command turns a credential the agent
# can legitimately read into a credential someone else holds, and it is irreversible the
# moment it succeeds. NARROW ENOUGH TO KEEP: BOTH halves must be present IN THE SAME
# PIPELINE — reading a `.env` is allowed, and so is any network call. A `&&` chain is two
# commands, not one, so `grep KEY .env && curl …/health` is untouched.
#
# Three carve-outs kill the realistic false positives: `.env.example`/`.sample`/`.template`
# are not secrets; a path that is the operand of `-o`/`--output` is a DOWNLOAD, not an
# upload; and a local target (localhost/127.0.0.1) is not exfiltration.
rule_secret_exfiltration() {
  local seg w prev sender secret
  while IFS= read -r seg; do
    [ -n "$seg" ] || continue

    case "$seg" in
      *localhost*|*127.0.0.1*|*0.0.0.0*|*'::1'*|*host.docker.internal*) continue ;;
    esac

    sender=""
    while IFS= read -r w; do
      case "${w##*/}" in
        curl|wget|nc|ncat|netcat|socat|telnet|ssh|scp|sftp|rsync|http|httpie) sender="${w##*/}"; break ;;
      esac
    done <<EOT
$(tokens_of "$seg")
EOT
    [ -n "$sender" ] || continue

    secret=""; prev=""
    while IFS= read -r w; do
      case "$prev" in -o|--output|-O|--output-dir|--remote-name) prev="$w"; continue ;; esac
      prev="$w"
      w="${w#@}"
      case "$w" in
        *.env.example|*.env.sample|*.env.template|*.env.dist|*.env.example*) continue ;;
      esac
      case "$w" in
        .env|*/.env|*.env|.env.*|*/.env.*) secret="$w"; break ;;
        *id_rsa*|*id_ed25519*|*id_ecdsa*|*id_dsa*) secret="$w"; break ;;
        *.pem|*.p12|*.pfx) secret="$w"; break ;;
        .npmrc|*/.npmrc|.netrc|*/.netrc|.pgpass|*/.pgpass) secret="$w"; break ;;
        */.aws/credentials|*/.ssh/*|*kubeconfig*|*service-account*.json|*credentials.json) secret="$w"; break ;;
      esac
    done <<EOT
$(tokens_of "$seg")
EOT
    [ -n "$secret" ] || continue

    printf 'This pipeline reads `%s` and hands it to `%s` in the same command — that is credential exfiltration, and it cannot be undone once it lands. Reading the file is allowed, and so is the network call; only the two joined together are refused.' "$secret" "$sender"
    return 0
  done <<EOF
$(segments "$1")
EOF
  return 1
}

# =============================================================================== decide ==
matched=""; reason=""
for _rule in $RULES; do
  if reason="$("rule_$_rule" "$CMD" 2>/dev/null)"; then
    matched="$_rule"
    break
  fi
done
[ -n "$matched" ] || exit 0

# The fence marks the reason as data. It is assembled from literals in this file plus
# fragments of the agent's own command, and lands in the agent's context.
body="ai-bridge destructive-action baseline — rule \`$matched\` refused this command.

$reason

This is enforced by the harness before the tool runs, not by a convention, so it is not
something to argue past. Do NOT re-issue a variant that evades the pattern: if the command
is genuinely right, say so to the human and let them run it in their own terminal, outside
this session. That escape hatch is why this baseline can stay narrow enough to keep."

jq -n --arg r "$body" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: $r
  }
}'
exit 0
