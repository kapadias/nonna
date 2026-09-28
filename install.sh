#!/usr/bin/env bash
# install.sh — Nonna in one command, for any agent host.
#
#   curl -fsSL https://raw.githubusercontent.com/kapadias/nonna/main/install.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/kapadias/nonna/main/install.sh | bash -s -- --host cursor
#
# Run it from the root of a git repository. It copies the harness (.claude/), the chosen hosts'
# rules files, a blank docs/STATUS.md and your stack's test-gate permissions, and wires the git
# pre-commit and pre-push hooks. It never overwrites a file or a git hook that already exists: it
# says so and moves on.
#
# Hosts: claude (default), agents (AGENTS.md: Codex, Zed, Amp, opencode, Roo, Jules, Junie…),
#        cursor, copilot, gemini, windsurf, cline, kiro, all. Several: --host cursor,agents
# Mode:  --mode lite  the gates and short house rules only (hooks, settings.json, git hooks, /nonna)
#        --mode full  the whole harness: rules, agents, workflows, docs/STATUS.md (the default)
# Env:   NONNA_REF  branch or tag to install (default: main)
#        NONNA_SRC  install from a local checkout instead of cloning (used by the tests)
set -uo pipefail

REPO="https://github.com/kapadias/nonna"

host_file() { # <host> -> the path its rules file lives at
  case "$1" in
    claude) echo "CLAUDE.md" ;;
    agents) echo "AGENTS.md" ;;
    cursor) echo ".cursor/rules/nonna.mdc" ;;
    copilot) echo ".github/copilot-instructions.md" ;;
    gemini) echo "GEMINI.md" ;;
    windsurf) echo ".windsurf/rules/nonna.md" ;;
    cline) echo ".clinerules/nonna.md" ;;
    kiro) echo ".kiro/steering/nonna.md" ;;
    *) return 1 ;;
  esac
}

usage() {
  cat <<'USAGE'
install.sh — Nonna in one command, for any agent host. Run it from the root of a git repository.

  curl -fsSL https://raw.githubusercontent.com/kapadias/nonna/main/install.sh | bash
  curl -fsSL https://raw.githubusercontent.com/kapadias/nonna/main/install.sh | bash -s -- --host cursor

--host  claude (default), agents (AGENTS.md: Codex, Zed, Amp, opencode, Roo, Jules, Junie…),
        cursor, copilot, gemini, windsurf, cline, kiro, all. Several: --host cursor,agents
--mode  lite: the gates, /nonna and short house rules only. full: the whole harness (the default).
Env:    NONNA_REF  branch or tag to install (default: main)
        NONNA_SRC  install from a local checkout instead of cloning
USAGE
}

# Arrays expand as ${a[@]+"${a[@]}"}: macOS bash 3.2 calls an empty one unbound under set -u.
# Everything runs inside main, called on the last line: a download cut short runs nothing.
main() {
hosts="claude"
mode=""
while [ $# -gt 0 ]; do
  case "$1" in
    --host)
      [ $# -ge 2 ] || { echo "install.sh: --host needs a value" >&2; exit 2; }
      hosts="$2"; shift 2 ;;
    --host=*) hosts="${1#--host=}"; shift ;;
    --mode)
      [ $# -ge 2 ] || { echo "install.sh: --mode needs a value" >&2; exit 2; }
      mode="$2"; shift 2 ;;
    --mode=*) mode="${1#--mode=}"; shift ;;
    -h | --help) usage; exit 0 ;;
    *) echo "install.sh: unknown argument '$1' (try --host <name> or --mode lite|full)" >&2; exit 2 ;;
  esac
done
case "$mode" in
  "" | lite | full) ;;
  *) echo "install.sh: unknown mode '$mode' (lite or full)" >&2; exit 2 ;;
esac
[ "$hosts" = all ] && hosts="claude,agents,cursor,copilot,gemini,windsurf,cline,kiro"

IFS=',' read -r -a HOSTS <<<"$hosts"
[ "${#HOSTS[@]}" -gt 0 ] || { echo "install.sh: --host needs a value" >&2; exit 2; }
for h in "${HOSTS[@]}"; do
  host_file "$h" >/dev/null || { echo "install.sh: unknown host '$h' (claude, agents, cursor, copilot, gemini, windsurf, cline, kiro, all)" >&2; exit 2; }
done

top="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "✗ Nonna: I cook in a kitchen, not a car park. Run this from inside a git repository." >&2
  exit 1
}
cd "$top" || exit 1

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
if [ -n "${NONNA_SRC:-}" ]; then
  src="$NONNA_SRC"
else
  git clone -q --depth 1 --branch "${NONNA_REF:-main}" "$REPO" "$work/src" 2>/dev/null || {
    echo "✗ Nonna: could not fetch $REPO@${NONNA_REF:-main}." >&2
    exit 1
  }
  src="$work/src"
fi
# Tracked files only: never a review verdict, a local setting or a stray file from the source.
mkdir -p "$work/pkg"
git -C "$src" ls-files -z -- .claude hosts stacks CLAUDE.md \
  | (cd "$src" && tar --null -T - -cf -) | tar -xf - -C "$work/pkg" || {
  echo "✗ Nonna: could not read the harness from $src." >&2
  exit 1
}
P="$work/pkg"

done_msgs=()
kept_msgs=()
warn_msgs=()
copied=()
failed=0
through_link() { # <relative path>: true when it, or a directory on the way to it, is a symlink
  local p="$1"
  while [ -n "$p" ] && [ "$p" != . ]; do
    [ -L "$p" ] && return 0
    p="$(dirname "$p")"
  done
  return 1
}
put() { # <source file> <dest>: copy unless dest exists; never through a symlink
  if through_link "$2"; then
    warn_msgs+=("$2: a symlink is on the way — I do not write through links, so I left it alone")
    failed=1
    return 0
  fi
  if [ -e "$2" ]; then
    kept_msgs+=("$2")
    return 0
  fi
  if mkdir -p "$(dirname "$2")" && cp -P "$1" "$2"; then
    copied+=("$2")
  else
    warn_msgs+=("$2: could not write it")
    failed=1
  fi
}

# .claude/ is merged file by file: yours stay, what is missing arrives. Lite brings the gates and
# their wiring, and /nonna, the user's switch for them (with the manifest it reads her version
# from): never the rules, agents or other workflows.
n_before=${#kept_msgs[@]}
while IFS= read -r -d '' rel; do
  rel="${rel#./}"
  if [ "$mode" = lite ]; then
    case "$rel" in hooks/* | settings.json | skills/nonna/* | .claude-plugin/plugin.json) ;; *) continue ;; esac
  fi
  put "$P/.claude/$rel" ".claude/$rel"
done < <(cd "$P/.claude" && find . \( -type f -o -type l \) -print0)
[ "${#copied[@]}" -gt 0 ] && done_msgs+=(".claude/ (${#copied[@]} files)")
n_kept=$((${#kept_msgs[@]} - n_before))
if [ "$n_kept" -gt 0 ]; then
  kept_msgs=(${kept_msgs[@]+"${kept_msgs[@]:0:n_before}"} ".claude/ ($n_kept of your files)")
fi
for f in ${copied[@]+"${copied[@]}"}; do
  case "$f" in *.sh) chmod +x "$f" ;; esac
done

for h in "${HOSTS[@]}"; do
  f="$(host_file "$h")"
  n=${#copied[@]}
  if [ "$mode" = lite ]; then
    # Claude Code gets lite's house rules from the SessionStart hook; other hosts read a file.
    [ "$h" = claude ] || put "$P/hosts/lite/$f" "$f"
  elif [ "$h" = claude ]; then put "$P/CLAUDE.md" "$f"; else put "$P/hosts/$f" "$f"; fi
  [ "${#copied[@]}" -gt "$n" ] && done_msgs+=("$f")
done

if [ "$mode" = lite ]; then
  : # the Definition-of-Done record (docs/STATUS.md) is full mode's
elif through_link docs/STATUS.md; then
  warn_msgs+=("docs/STATUS.md: a symlink is on the way — I do not write through links, so I left it alone")
  failed=1
elif [ ! -e docs/STATUS.md ]; then
  mkdir -p docs
  printf '# STATUS\n\nWhat is true right now. The pre-push hook blocks a code push that leaves this file stale.\n\n## Current state\n\n## Recently changed\n\n## Next / open\n' > docs/STATUS.md
  done_msgs+=("docs/STATUS.md")
else
  kept_msgs+=("docs/STATUS.md")
fi

stack=""
[ -f pyproject.toml ] || [ -f setup.cfg ] || [ -f setup.py ] && stack=python
[ -f package.json ] && stack=typescript
[ -f go.mod ] && stack=go
[ -f Cargo.toml ] && stack=rust
if [ -n "$stack" ] && [ -f "$P/stacks/$stack/settings.local.json" ]; then
  n=${#copied[@]}
  put "$P/stacks/$stack/settings.local.json" ".claude/settings.local.json"
  [ "${#copied[@]}" -gt "$n" ] && done_msgs+=(".claude/settings.local.json ($stack)")
fi

# A settings.json you already had was kept; without Nonna's hooks in it, her Claude Code gates are off.
if [ -f .claude/settings.json ] && ! grep -q '\.claude/hooks/' .claude/settings.json; then
  warn_msgs+=(".claude/settings.json: yours was kept, so my Claude Code hooks are not running — merge the \"hooks\" block from $REPO/blob/main/.claude/settings.json")
  failed=1
fi

hooks_dir="$(git rev-parse --git-path hooks)"
link_hook() { # <git hook name> <script under .claude/hooks>
  local dest="$hooks_dir/$1"
  if [ -L .claude ] || [ -L .claude/hooks ] || [ ! -x ".claude/hooks/$2" ] || [ ! -f .claude/hooks/lib/secret-patterns.sh ]; then
    warn_msgs+=("$1: .claude/hooks/$2 is not here, so this gate is not running")
    failed=1
    return 0
  fi
  if [ -e "$dest" ] || [ -L "$dest" ]; then
    # It runs hers only when it names her script's path, not a file that merely shares its name.
    grep -qsF ".claude/hooks/$2" "$dest" || warn_msgs+=("$1: you already have a $1 hook — chain .claude/hooks/$2 from it, or my gates do not run")
    return 0
  fi
  if [ "$hooks_dir" = ".git/hooks" ]; then
    mkdir -p "$hooks_dir" && ln -s "../../.claude/hooks/$2" "$dest"
  else
    warn_msgs+=("$1: git hooks live in '$hooks_dir' (a hook manager?) — point its $1 at .claude/hooks/$2")
    return 0
  fi
  done_msgs+=("$dest -> .claude/hooks/$2")
}
link_hook pre-commit pre-commit.sh
link_hook pre-push require-status-sync.sh

# The mode lives in the repo's own git config, where every hook reads it (never committed, never
# cloned), as the repo's default: nonna.mode, in the repo or --global, is the user's and outranks
# it. Without --mode a copy-in install is full, and nothing is written.
if [ -n "$mode" ]; then
  if git config nonna.defaultMode "$mode"; then
    done_msgs+=("mode: $mode (git config nonna.defaultMode)")
  else
    warn_msgs+=("could not record the mode in git config, so she runs as full")
    failed=1
  fi
fi

if [ "$failed" = 1 ]; then
  echo "Nonna could not set the whole table."
else
  echo "Nonna is in the kitchen."
fi
for m in ${done_msgs[@]+"${done_msgs[@]}"}; do echo "  + $m"; done
for m in ${kept_msgs[@]+"${kept_msgs[@]}"}; do echo "  = $m (already here, left alone)"; done
for m in ${warn_msgs[@]+"${warn_msgs[@]}"}; do echo "  ! $m"; done
if [ "$failed" = 1 ]; then
  echo "Some gates are not running. Fix what is marked '!' and run me again: I never overwrite, so it is safe."
  exit 1
fi
if [ "$mode" = lite ]; then
  echo "No commits on main, no keys in files, and the whole suite before done. Now go make a branch."
else
  echo "No commits on main, no keys in files, and write it in docs/STATUS.md. Now go make a branch."
fi
exit 0
}

main "$@"
