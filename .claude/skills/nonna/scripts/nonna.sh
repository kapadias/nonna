#!/usr/bin/env bash
# /nonna — see or change what Nonna enforces in this repository.
#
#   /nonna                  status
#   /nonna setup            record the test command detection finds, wire the git hooks, show what
#                           else would help
#   /nonna lite|full|off    this repository's mode (git config nonna.mode), then status
#   /nonna test <command>   this repository's test command (`/nonna test off` turns the gate off)
#   /nonna uninstall        take her git hooks, settings and state back out of this repository
#
# Only a person runs this: the skill's ! line runs it when the user types /nonna, and the skill sets
# disable-model-invocation, so the model cannot. The branch guard refuses the agent running these
# scripts itself, as it refuses git config nonna.*. Always exits 0: what it has to say is output,
# and the skill shows the output. Runs in the project directory, as her hooks do.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${CLAUDE_PROJECT_DIR:-$PWD}" 2>/dev/null || exit 0
if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "Nonna: this is not a git repository, so there is nothing of hers here to see or change."
  exit 0
fi

case "${1:-}" in
  "" | status) bash "$here/status.sh" ;;
  setup) bash "$here/setup.sh" ;;
  lite | full | off)
    git config nonna.mode "$1"
    echo "Nonna is $1 in this repository now (git config nonna.mode $1)."
    # Claude Code's environment outranks git config: say so rather than let the change look ignored.
    [ -z "${NONNA_MODE:-}" ] || [ "$NONNA_MODE" = "$1" ] \
      || echo "  But NONNA_MODE=$NONNA_MODE is set where Claude Code runs, and it decides until you unset it."
    echo
    bash "$here/status.sh"
    ;;
  test)
    shift
    # One argument is the command as the user quoted it; several are the words of one, each kept
    # whole (a quoted word with a space inside stays one word).
    if [ "$#" -le 1 ]; then cmd="${1:-}"; else cmd="$(printf '%q ' "$@")" && cmd="${cmd% }"; fi
    case "$cmd" in
      "") echo "Say which: /nonna test '<command>', or /nonna test off." ;;
      off | none | '""' | "''")
        git config nonna.testCmd ""
        echo "The test gate is off in this repository (git config nonna.testCmd is empty)."
        ;;
      *)
        git config nonna.testCmd "$cmd"
        echo "Before the agent can say done, and before a push, Nonna now runs: $cmd"
        ;;
    esac
    [ -z "$cmd" ] || [ "${NONNA_TEST_CMD+set}" != set ] \
      || echo "  But NONNA_TEST_CMD is set where Claude Code runs, and it decides at turn end until you unset it."
    ;;
  uninstall) bash "$here/uninstall.sh" ;;
  *) echo "Nonna does not know '$1'. Try /nonna, /nonna setup, /nonna lite|full|off, /nonna test '<command>' or /nonna uninstall." ;;
esac
exit 0
