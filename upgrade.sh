#!/usr/bin/env bash
#
# upgrade.sh — RETIRED. `/ai-bridge:welcome fix` replaces it.
#
# It shipped for one version as this stub so a bookmarked command or a stale doc says
# what to run instead of failing with "no such file". Delete it at the next version.
#
# Exits 2 on every path: this is a refusal, not a no-op.
set -eu

cat >&2 <<'EOF'
upgrade.sh is retired. Its four stages are reachable from the ai-bridge PLUGIN.

  · machinery symlinks (stage 1)   gone — a bundle carries no machinery. `/ai-bridge:init`
                                   converts a bundle stamped by the old install.sh.
  · validate + migrate (2 and 3)   /ai-bridge:welcome check
  · seed drift, 3-way merged (4)   /ai-bridge:welcome fix
                                   (or: /ai-bridge:init <dir> --refresh-seeds)

Install the plugin once per machine:
  /plugin marketplace add cbmono/ai-bridge
  /plugin install ai-bridge@ai-bridge

docs/migrating.md walks the conversion of an existing bundle.
EOF
exit 2
