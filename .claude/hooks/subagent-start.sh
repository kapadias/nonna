#!/usr/bin/env bash
# SubagentStart — the constitution reaches subagents under a plugin install.
# SessionStart additionalContext is parent-only: a Task-spawned subagent never sees
# it, so a plugin install ran every agent with no policy. A standalone checkout
# loads rules/ natively for subagents too ("project rules" are part of a subagent's
# initial context), so there this emits nothing. Scope by agent type with the
# settings-level matcher, not here. Fails OPEN; never reads stdin; never blocks a spawn.
set -uo pipefail
# ADR-0018: source libs by a literal ${CLAUDE_PLUGIN_ROOT} path. Claude Code sets it to this plugin's
# root; a copy-in leaves it unset, Codex points PLUGIN_ROOT here (so this is unset), and Copilot sets it
# to the repo with the harness under .claude/ — so when it does not point at the harness, resolve it
# from this script's own location (its hooks/ dir's parent).
if [ -z "${CLAUDE_PLUGIN_ROOT:-}" ] || [ ! -e "${CLAUDE_PLUGIN_ROOT}/hooks/lib/core.sh" ]; then
  CLAUDE_PLUGIN_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd)"
fi
# shellcheck source=/dev/null
. "${CLAUDE_PLUGIN_ROOT}/hooks/lib/core.sh"
cd "${CLAUDE_PROJECT_DIR:-$(pwd)}" 2>/dev/null || exit 0
[ "$(nonna_mode)" = off ] && exit 0 # off means off: nothing enforced, nothing said
core="$(nonna_core_carrier)"
[ -n "$core" ] || exit 0
nonna_emit_context SubagentStart "$core"
exit 0
