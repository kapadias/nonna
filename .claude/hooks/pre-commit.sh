#!/usr/bin/env bash
# Pre-commit git hook — the gates every agent host gets, not just Claude Code.
#
# .claude/ hooks bind Claude Code alone; a git hook binds any agent (or person) that commits:
#   • no commit on main, master or develop — branch first (rules/git-workflow.md)
#   • no staged secret file (.env, *.pem, *.key, id_rsa, …) — templates like .env.example pass
#   • no staged line that looks like a live credential — no fixture exemption, same as pre-push
#
# Installed by install.sh as .git/hooks/pre-commit. Bypass, knowingly: git commit --no-verify
# That includes the very first commit of a repo born on main: make it with --no-verify, then branch.
set -uo pipefail
self="${BASH_SOURCE[0]}"
while [ -L "$self" ]; do
  link="$(readlink "$self")"
  case "$link" in
    /*) self="$link" ;;
    *) self="$(dirname "$self")/$link" ;;
  esac
done
here="$(cd "$(dirname "$self")" && pwd)"
# shellcheck source=/dev/null
. "$here/lib/secret-patterns.sh"
# shellcheck source=/dev/null
. "$here/lib/core.sh"
[ "$(nonna_mode git-hook)" = off ] && exit 0 # off means off: nothing enforced, nothing said

fail=0

# The full ref, prefix stripped: --short gives heads/main once a tag named main exists, and the
# branch is named before its first commit too.
ref="$(git symbolic-ref --quiet HEAD 2>/dev/null || true)"
branch="${ref#refs/heads/}"
case "$branch" in
  main | master | develop)
    {
      echo "✗ Nonna: not in my kitchen, tesoro. Make a branch. (pre-commit: refusing to commit on protected branch '$branch'.)"
      echo "  git switch -c fix/<id>-<slug>, then commit there (rules/git-workflow.md)."
    } >&2
    fail=1
    ;;
esac

# Added, modified or type-changed paths: deleting a secret file is the fix, not the leak.
staged="$(mktemp)" || exit 1
trap 'rm -f "$staged"' EXIT
if ! git -c core.quotePath=false diff --cached --name-only --diff-filter=ACMRT -z > "$staged"; then
  echo "✗ Nonna: I could not see what you staged, so I cannot vouch for it. (pre-commit: git diff failed.)" >&2
  exit 1
fi
# NUL-separated all the way: a newline in a name must not split it into fragments nobody scans.
while IFS= read -r -d '' f; do
  case "$(basename "$f")" in
    *.example | *.sample | *.template | *.dist) continue ;;
    .env | .env.* | *.pem | *.key | *.p12 | *.pfx | *.jks | *.p8 | id_rsa* | id_ed25519* | credentials | kubeconfig | .npmrc)
      echo "✗ Nonna: that drawer is private. (pre-commit: '$f' is a secret file — unstage it and add it to .gitignore.)" >&2
      fail=1
      continue
      ;;
  esac
  # A file name is never pathspec magic, a NUL byte never makes a file "binary", and a diff that
  # cannot be read is a stop, not a clean bill.
  if ! diff="$(git --literal-pathspecs -c core.quotePath=false diff --cached --text --no-color --no-ext-diff --no-textconv -U0 -- "$f")"; then
    echo "✗ Nonna: I could not read what you staged in '$f', so I cannot vouch for it. (pre-commit: git diff failed.)" >&2
    fail=1
    continue
  fi
  added="$(printf '%s\n' "$diff" | grep -aE '^\+' | grep -avE '^\+\+\+ ' || true)"
  [ -n "$added" ] || continue
  if class="$(printf '%s' "$added" | nonna_scan_secrets)"; then
    echo "✗ Nonna: you don't leave the house key under the mat. (pre-commit: '$f' stages what looks like a ${class} — remove it and rotate it.)" >&2
    fail=1
  fi
done < "$staged"

exit "$fail"
