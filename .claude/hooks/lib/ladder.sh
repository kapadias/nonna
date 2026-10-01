# shellcheck shell=bash
# Sourced helper — the decision ladder, when another plugin already states it.
#
# ponytail ships the same ladder Nonna adapted from it (credited in README.md). With both installed,
# full mode's constitution would state it twice, so the carrier drops Nonna's copy. Lite mode has no
# ladder, so the two never overlap there. This is the one harness file that names ponytail: the
# plugin id is the only way to tell it is on.

# nonna_ladder_elsewhere
#   0 when the ladder is stated elsewhere: NONNA_LADDER=off, or (unless NONNA_LADDER=on) ponytail
#   enabled in Claude Code's settings, local then project then user, the first file that names it
#   deciding. Runs from the project directory.
nonna_ladder_elsewhere() {
  case "${NONNA_LADDER:-}" in off) return 0 ;; on) return 1 ;; esac
  local f v
  for f in .claude/settings.local.json .claude/settings.json "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"; do
    [ -f "$f" ] || continue
    if command -v jq >/dev/null 2>&1; then
      # Not `// empty`: jq's alternative operator treats false as missing, and an explicit false
      # in a project must win over a true in the user's settings.
      v="$(jq -r '.enabledPlugins["ponytail@ponytail"] | if . == null then empty else tostring end' "$f" 2>/dev/null)"
    else
      v="$(grep -oE '"ponytail@ponytail"[[:space:]]*:[[:space:]]*(true|false)' "$f" 2>/dev/null | head -n 1 | grep -oE '(true|false)$')"
    fi
    case "$v" in
      true) return 0 ;;
      false) return 1 ;;
    esac
  done
  return 1
}

# nonna_drop_ladder
#   stdin -> stdout without the constitution's "## Before writing code" section.
nonna_drop_ladder() {
  awk '/^## Before writing code/ { skip = 1; next } /^## / { skip = 0 } !skip'
}
