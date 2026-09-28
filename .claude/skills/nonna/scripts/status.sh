#!/usr/bin/env bash
# /nonna status: what Nonna enforces in this repository, and where each setting comes from. Reads
# only. Plain text but for the check marks, and no colour: the output reaches the user through the
# model. Runs in the project directory (nonna.sh sees to it).
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/../../.." && pwd)" # skills/nonna/scripts -> the harness (.claude/ or the plugin)
# shellcheck source=/dev/null
. "$root/hooks/lib/core.sh"
# shellcheck source=/dev/null
. "$root/hooks/lib/tests.sh"

row() { printf '  %-13s %-4s %s\n' "$1" "$2" "$3"; }
ago() { # <file>: how long ago it last changed
  local m s
  m="$(stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null)" || return 0
  [ -n "$m" ] || return 0
  s=$(($(date +%s) - m))
  if [ "$s" -lt 60 ]; then printf 'just now'
  elif [ "$s" -lt 3600 ]; then printf '%d min ago' $((s / 60))
  elif [ "$s" -lt 172800 ]; then printf '%d h ago' $((s / 3600))
  else printf '%d days ago' $((s / 86400)); fi
}
hook_state() { # <git hook> <her script>: a check mark, or what is wrong
  local dir d
  dir="$(git rev-parse --git-path hooks 2>/dev/null)"
  case "$dir" in
    .git/hooks | */.git/hooks | */.git/worktrees/*/hooks) ;;
    *) printf 'not wired (git hooks live in %s)' "$dir"; return 0 ;;
  esac
  d="$dir/$1"
  if [ -L "$d" ] && [ ! -e "$d" ]; then printf 'points at nothing'
  elif [ ! -e "$d" ]; then printf 'missing'
  elif nonna_hook_is_hers "$(readlink "$d" 2>/dev/null)" "$2" "$root/hooks/$2" \
    || nonna_hook_chains_hers "$d" "$2" "$root/hooks/$2"; then printf '✓'
  else printf 'not hers'; fi
}
unhooked() { # why Claude Code runs none of her hooks here, or nothing when it runs them
  local f
  for f in .claude/settings.local.json .claude/settings.json "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"; do
    grep -qsE '"disableAllHooks"[[:space:]]*:[[:space:]]*true' "$f" && { printf 'disableAllHooks is set in %s' "$f"; return 0; }
  done
  if nonna_copy_in; then f=.claude/settings.json; else f="$root/hooks/hooks.json"; fi
  if ! grep -qs guard-branch.sh "$f" || ! grep -qs secret-scan.sh "$f"; then printf 'her hooks are not in %s' "$f"; fi
}

version="$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$root/.claude-plugin/plugin.json" 2>/dev/null | head -n 1)"
mode="$(nonna_mode)"
# The branch by its full ref (named before its first commit too), else the commit it sits on.
ref="$(git symbolic-ref --quiet HEAD 2>/dev/null || true)"
on="${ref#refs/heads/}"
[ -n "$on" ] || on="a detached HEAD at $(git rev-parse --short HEAD 2>/dev/null)"
printf 'Nonna %s · %s (%s) · %s on %s\n' "${version:-(version unknown)}" "$mode" "$(nonna_mode_source)" \
  "$(basename "$PWD")" "$on"

if [ "$mode" = off ]; then
  for g in "test gate" "branch guard" "secret guard" "status doc"; do row "$g" off "(Nonna is off here)"; done
else
  why="$(unhooked)"
  cmd="$(nonna_test_cmd)"
  if [ -n "$cmd" ]; then
    if [ "${NONNA_TEST_CMD+set}" = set ]; then src="NONNA_TEST_CMD"
    elif nonna_config nonna.testCmd >/dev/null; then src="git config nonna.testCmd"
    else src="detected"; fi
    green=""
    gf="$(git rev-parse --git-path nonna-green 2>/dev/null)"
    # The key writes git objects: compute it only when there is a green run to compare it with.
    if [ -s "$gf" ] && [ "$(cat "$gf" 2>/dev/null)" = "$(nonna_green_key "$cmd")" ]; then
      green="; green on this tree $(ago "$gf")"
    fi
    [ -z "$why" ] || green="$green; at push only"
    row "test gate" on "$(nonna_shown_cmd "$cmd") ($src)$green"
  elif [ "${NONNA_TEST_CMD+set}" = set ]; then
    row "test gate" off "NONNA_TEST_CMD is set empty where Claude Code runs"
  elif nonna_config nonna.testCmd >/dev/null; then
    row "test gate" off "as you set it: /nonna test '<command>' turns it on"
  else
    row "test gate" off "no test command here: /nonna test '<command>'"
  fi
  if [ -n "$why" ]; then
    row "branch guard" off "($why)"
    row "secret guard" off "($why)"
  else
    row "branch guard" on "no commit or push on main, master or develop; no force push; no --no-verify"
    row "secret guard" on "file writes, reads and searches of secret files, commits, pushes"
  fi
  if [ "$mode" != full ]; then row "status doc" off "(full mode only)"
  elif [ -f docs/STATUS.md ]; then row "status doc" on "docs/STATUS.md changes with the code"
  else row "status doc" off "(no docs/STATUS.md here)"; fi
fi
printf '  %-13s pre-push %s  pre-commit %s\n' "git hooks" \
  "$(hook_state pre-push require-status-sync.sh)" "$(hook_state pre-commit pre-commit.sh)"
echo "Change: /nonna setup · /nonna lite | full | off · /nonna test '<command>' · /nonna uninstall"
