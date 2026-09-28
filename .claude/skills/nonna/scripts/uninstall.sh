#!/usr/bin/env bash
# /nonna uninstall: take Nonna's git hooks, settings and state back out of this repository, and
# name each thing taken, with its value. Only what is hers goes: a git hook that is not her link
# (nonna_hook_is_hers) is left alone and named, and so is the user's own hook that chains hers.
# Her hooks live in the repository's shared .git/hooks, wherever core.hooksPath now points; her
# state lives in each worktree's git dir. Runs in the project directory (nonna.sh sees to it).
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/../../.." && pwd)" # skills/nonna/scripts -> the harness (.claude/ or the plugin)
# shellcheck source=/dev/null
. "$root/hooks/lib/core.sh"
# shellcheck source=/dev/null
. "$root/hooks/lib/tests.sh"

removed=()
left=()
common="$(git rev-parse --git-common-dir)"
for pair in pre-push:require-status-sync.sh pre-commit:pre-commit.sh; do
  h="${pair%%:*}"
  s="${pair#*:}"
  d="$common/hooks/$h"
  if [ -L "$d" ] && nonna_hook_is_hers "$(readlink "$d")" "$s" "$root/hooks/$s"; then
    rm -f "$d" && removed+=("$d (her link to $s)")
  elif [ -e "$d" ] || [ -L "$d" ]; then
    if nonna_hook_chains_hers "$d" "$s" "$root/hooks/$s"; then
      left+=("$d is yours but still runs her $s: take that line out yourself")
    else
      left+=("$d is not hers: left alone")
    fi
  fi
done

# Her settings in this repository's config, each named with its value (a test command shown only
# when it carries no secret).
settings=()
while IFS= read -r line; do
  [ -n "$line" ] || continue
  k="${line%% *}"
  v=""
  [ "$k" = "$line" ] || v="${line#* }"
  case "$k" in
    nonna.testcmd) k=nonna.testCmd; v="$(nonna_shown_cmd "$v")" ;;
    nonna.defaultmode) k=nonna.defaultMode ;;
  esac
  settings+=("git config $k=$v")
done < <(git config --local --get-regexp '^nonna\.' 2>/dev/null)
if [ "${#settings[@]}" -gt 0 ]; then
  if git config --local --remove-section nonna 2>/dev/null; then
    removed+=("${settings[@]}")
  else
    left+=("could not remove the nonna section from this repository's git config")
  fi
fi

# Her state, in every worktree: where each session began, the last green tree, the branch warnings.
while IFS= read -r wt; do
  gd="$(git -C "$wt" rev-parse --absolute-git-dir 2>/dev/null)" || continue
  for f in "$gd/nonna" "$gd/nonna-green" "$gd"/.nonna-branch-warned-*; do
    if [ -e "$f" ]; then rm -rf "$f" && removed+=("$f"); fi
  done
done < <(git worktree list --porcelain 2>/dev/null | sed -n 's/^worktree //p')

echo "Nonna is out of this repository."
for r in ${removed[@]+"${removed[@]}"}; do echo "  - removed $r"; done
for l in ${left[@]+"${left[@]}"}; do echo "  ! $l"; done
[ "${#removed[@]}" -gt 0 ] || [ "${#left[@]}" -gt 0 ] || echo "  (there was nothing of hers here)"
if git config --global --get-regexp '^nonna\.' >/dev/null 2>&1; then
  echo "  Your global git config still has nonna.* settings: git config --global --get-regexp '^nonna\.'"
fi
if nonna_copy_in; then
  echo "Her files are part of this repository (.claude/): deleting them is a commit, and yours to make."
else
  echo "The plugin is still installed, and a new session here would set her up again. To keep her"
  echo "out: /plugin uninstall nonna@nonna. To keep the plugin but not here: /nonna off."
fi
