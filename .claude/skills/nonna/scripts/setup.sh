#!/usr/bin/env bash
# /nonna setup: the test command, the git hooks, then what else would help. The user asked for the
# first two by running it; a change to their own files is offered (OFFER: lines, which the skill
# asks about), never made here. Runs in the project directory (nonna.sh sees to it).
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/../../.." && pwd)" # skills/nonna/scripts -> the harness (.claude/ or the plugin)
# shellcheck source=/dev/null
. "$root/hooks/lib/core.sh"
# shellcheck source=/dev/null
. "$root/hooks/lib/tests.sh"

if [ "$(nonna_mode)" = off ]; then
  echo "Nonna is off in this repository ($(nonna_mode_source)), so setup records and wires nothing."
  echo "Turn her on first: /nonna lite or /nonna full."
  echo
  bash "$here/status.sh"
  exit 0
fi

echo "Nonna is setting the table."
# 1. The test command. One already set, an empty one (the gate turned off) included, is the
#    user's: shown, never replaced.
if cur="$(nonna_config nonna.testCmd)"; then
  if [ -n "$cur" ]; then
    echo "  test gate: $(nonna_shown_cmd "$cur"), already recorded. Change it: /nonna test '<command>'"
  else
    echo "  test gate: off, as you set it. Turn it on: /nonna test '<command>'"
  fi
elif found="$(nonna_detect_test_cmd)" && [ -n "$found" ]; then
  git config nonna.testCmd "$found"
  echo "  test gate: $found, detected and recorded (git config nonna.testCmd). Change it: /nonna test '<command>'"
else
  echo "  test gate: no pytest, npm, go or cargo suite found. Set one: /nonna test '<command>'"
fi

# 2. The git hooks: what every session start does, done now, through the plugin's data directory
#    when Claude Code gave one. It never overwrites a hook, and the status below says which gates
#    are not wired.
CLAUDE_PROJECT_DIR="$PWD" bash "$root/hooks/session-start.sh" "${CLAUDE_PLUGIN_DATA:-}" </dev/null >/dev/null 2>&1 || true

# 3. What only the user can decide: offered, with what would change.
if ! grep -qs '"Read(./\*\*/.env)"' .claude/settings.json; then
  echo "OFFER: add Nonna's permissions.deny list to .claude/settings.json, so Claude Code itself also"
  echo "  refuses reading secret files and force pushes (her hooks already do). The entries to add:"
  sed -n '/"deny"/,/\]/p' "$root/settings.json" | sed '1d;$d' | sed 's/^[[:space:]]*/    /'
fi
if [ "$(nonna_mode)" = full ] && [ ! -e docs/STATUS.md ]; then
  echo "OFFER: create docs/STATUS.md, full mode's Definition-of-Done record, with three sections:"
  echo "  Current state, Recently changed, Next / open."
fi
echo
bash "$here/status.sh"
