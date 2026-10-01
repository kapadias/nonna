#!/usr/bin/env bash
# SubagentStart — the constitution reaches subagents under a plugin install.
# SessionStart additionalContext is parent-only: a Task-spawned subagent never sees
# it, so a plugin install ran every agent with no policy. A standalone checkout
# loads rules/ natively for subagents too ("project rules" are part of a subagent's
# initial context), so there this emits nothing. Scope by agent type with the
# settings-level matcher, not here. Fails OPEN; never reads stdin; never blocks a spawn.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$here/lib/core.sh"
cd "${CLAUDE_PROJECT_DIR:-$(pwd)}" 2>/dev/null || exit 0
[ "$(nonna_mode)" = off ] && exit 0 # off means off: nothing enforced, nothing said
core="$(nonna_core_carrier)"
[ -n "$core" ] || exit 0
nonna_emit_context SubagentStart "$core"
exit 0
