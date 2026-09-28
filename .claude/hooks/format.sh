#!/usr/bin/env bash
# PostToolUse — auto-format the file Claude just edited, with whatever formatter
# the project provides. Best-effort and language-agnostic: never blocks the edit
# (always exits 0) and silently no-ops when a formatter is absent.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$here/lib/json.sh"
# shellcheck source=/dev/null
. "$here/lib/core.sh"
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
    if have prettier; then
      prettier --write "$file" >/dev/null 2>&1 || true
    elif have npx; then
      npx --no-install prettier --write "$file" >/dev/null 2>&1 || true
    fi ;;
  *.go)
    have gofmt && { gofmt -w "$file" >/dev/null 2>&1 || true; } ;;
  *.rs)
    have rustfmt && { rustfmt "$file" >/dev/null 2>&1 || true; } ;;
  *.sh)
    have shfmt && { shfmt -w "$file" >/dev/null 2>&1 || true; } ;;
esac
exit 0
