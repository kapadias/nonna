#!/usr/bin/env bash
# PostToolUse — auto-format the file Claude just edited, with whatever formatter
# the project provides. Best-effort and language-agnostic: never blocks the edit
# (always exits 0) and silently no-ops when a formatter is absent.
# Copy-in installs only: the project installed this. Under the plugin it would rewrite whole files
# a project never formatted, and a formatter's config can run the repository's own code.
set -uo pipefail
# ADR-0018: source libs by a literal ${CLAUDE_PLUGIN_ROOT} path. Claude Code sets it to this plugin's
# root; a copy-in leaves it unset, Codex points PLUGIN_ROOT here (so this is unset), and Copilot sets it
# to the repo with the harness under .claude/ — so when it does not point at the harness, resolve it
# from this script's own location (its hooks/ dir's parent).
if [ -z "${CLAUDE_PLUGIN_ROOT:-}" ] || [ ! -e "${CLAUDE_PLUGIN_ROOT}/hooks/lib/core.sh" ]; then
  CLAUDE_PLUGIN_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd)"
fi
# shellcheck source=/dev/null
. "${CLAUDE_PLUGIN_ROOT}/hooks/lib/json.sh"
# shellcheck source=/dev/null
. "${CLAUDE_PLUGIN_ROOT}/hooks/lib/core.sh"
( cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null && nonna_copy_in ) || exit 0
[ "$(cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null && nonna_mode)" = off ] && exit 0 # off means off

# The edited file path comes from the hook JSON on stdin (.tool_input.file_path),
# with an optional env override.
file="${CLAUDE_FILE_PATH:-}"
[ -n "$file" ] || file="$(nonna_json_field '.tool_input.file_path')"
[ -n "$file" ] && [ -f "$file" ] || exit 0

have() { command -v "$1" >/dev/null 2>&1; }

case "$file" in
  *.py)
    if have ruff; then
      ruff format "$file" >/dev/null 2>&1 || true
      ruff check --fix "$file" >/dev/null 2>&1 || true
    fi ;;
  *.ts|*.tsx|*.js|*.jsx|*.json|*.css|*.md|*.yaml|*.yml)
    # A prettier on PATH, else the project's own: the hook never fetches one the project lacks.
    project_prettier="${CLAUDE_PROJECT_DIR:-.}/node_modules/.bin/prettier"
    if have prettier; then
      prettier --write "$file" >/dev/null 2>&1 || true
    elif [ -x "$project_prettier" ]; then
      "$project_prettier" --write "$file" >/dev/null 2>&1 || true
    fi ;;
  *.go)
    have gofmt && { gofmt -w "$file" >/dev/null 2>&1 || true; } ;;
  *.rs)
    have rustfmt && { rustfmt "$file" >/dev/null 2>&1 || true; } ;;
  *.sh)
    have shfmt && { shfmt -w "$file" >/dev/null 2>&1 || true; } ;;
esac
exit 0
