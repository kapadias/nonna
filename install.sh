#!/usr/bin/env bash
# install.sh — Nonna in one command, for any agent host.
#
#   curl -fsSL https://raw.githubusercontent.com/kapadias/nonna/main/install.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/kapadias/nonna/main/install.sh | bash -s -- --host cursor
#
# Run it from the root of a git repository. By default (lite) it copies the gates: the hooks and
# their settings.json wiring, /nonna, short house rules for the chosen hosts and your stack's
# test-gate permissions; and it wires the git pre-commit and pre-push hooks. --mode full copies the
# whole harness (.claude/, the hosts' rules files and a blank docs/STATUS.md). It never overwrites a
# file or a git hook that already exists: it says so and moves on.
#
# Hosts: claude (default), agents (AGENTS.md: Codex, Zed, Amp, opencode, Roo, Jules, Junie…),
#        cursor, copilot, gemini, windsurf, cline, kiro, all. Several: --host cursor,agents
# Mode:  --mode lite  the gates and short house rules only (hooks, settings.json, git hooks, /nonna)
#                     (the default for a new install)
#        --mode full  the whole harness: rules, agents, workflows, docs/STATUS.md
#        Without --mode an install already here keeps its mode: running me again never downgrades it.
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
--mode  lite (the default): the gates, /nonna and short house rules only. full: the whole harness.
        Without --mode an install already here keeps its mode; --mode changes it.
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

# Without --mode a new install is lite (bench/PREREGISTRATION.md, D3 row 1), and one already here
# keeps its mode, so running me again never downgrades it. It is read from what an install leaves,
# before this run adds anything: the mode it recorded, else the hooks and rules only a full install
# copies (lib/core.sh reads a clone the same way). The user's nonna.mode outranks whatever I record,
# at run time; I neither read it nor write it. A recorded value that is neither lite nor full (say
# Full) is read as full, as nonna_mode reads it: I never turn what her hooks enforce into a lite.
# debt: nonna.mode unread here (a global full gets lite files), read it here when a user hits that
hint=""
if [ -z "$mode" ]; then
  mode="$(git config --local --get nonna.defaultMode 2>/dev/null)"
  case "$mode" in
    lite | full) hint="kept as this repository has it; --mode lite|full changes it" ;;
    "" | off) # no record (off is a mode her hooks know, but not one I install)
      if [ -f .claude/hooks/require-status-sync.sh ] && [ -f .claude/rules/00-core.md ]; then
        mode=full hint="kept as this repository has it; --mode lite|full changes it"
      else
        mode=lite hint="the default; --mode full brings the whole harness"
      fi ;;
    *)
      hint="'$mode' is neither lite nor full, and her hooks read that as full; --mode lite|full changes it"
      mode=full ;;
  esac
fi

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
  if [ "${#copied[@]}" -gt "$n" ]; then
    # What it lets run without asking is read back from the file, so the message cannot drift from the pack.
    grants="$(grep -o '"Bash([^"]*)"' .claude/settings.local.json | sed 's/^"Bash(//; s/:\*)"$//' | paste -sd, -)"
    done_msgs+=(".claude/settings.local.json ($stack): pre-approves ${grants//,/, }")
    # It is this machine's alone: committed, it would pre-approve the same commands for every clone.
    if through_link .gitignore; then
      warn_msgs+=(".gitignore: a symlink is on the way, and I do not write through links, so add .claude/settings.local.json to it yourself")
      failed=1
    elif ! grep -qxF .claude/settings.local.json .gitignore 2>/dev/null; then
      lead="" # a last line with no newline would swallow ours
      [ ! -s .gitignore ] || [ -z "$(tail -c1 .gitignore)" ] || lead=$'\n'
      if printf '%s.claude/settings.local.json\n' "$lead" 2>/dev/null >> .gitignore; then
        done_msgs+=(".gitignore: added .claude/settings.local.json (yours alone, so it stays out of git)")
      else
        warn_msgs+=(".gitignore: could not write it, so add .claude/settings.local.json to it yourself")
        failed=1
      fi
    fi
  fi
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
    # Her own link, from an earlier run, is hers, but only in .git/hooks, where ../../ leads back
    # here. Any other hook runs hers only when it names her script's path, not a file that merely
    # shares its name.
    case "$hooks_dir:$(readlink "$dest" 2>/dev/null)" in
      ".git/hooks:../../.claude/hooks/$2") return 0 ;;
    esac
    grep -qsF ".claude/hooks/$2" "$dest" || {
      warn_msgs+=("$1: you already have a $1 hook — chain .claude/hooks/$2 from it, or my gates do not run")
      failed=1
    }
    return 0
  fi
  # A gate that is not wired is off, and for hosts other than Claude Code the git hooks are all there is.
  if [ "$hooks_dir" = ".git/hooks" ]; then
    { mkdir -p "$hooks_dir" && ln -s "../../.claude/hooks/$2" "$dest"; } || {
      warn_msgs+=("$1: could not link $dest, so this gate is not running")
      failed=1
      return 0
    }
  else
    warn_msgs+=("$1: git hooks live in '$hooks_dir', not .git/hooks (a hook manager, or a linked worktree), so this gate is not running: point its $1 at .claude/hooks/$2")
    failed=1
    return 0
  fi
  done_msgs+=("$dest -> .claude/hooks/$2")
}
link_hook pre-commit pre-commit.sh
link_hook pre-push require-status-sync.sh

# The mode lives in the repo's own git config, where every hook reads it (never committed, never
# cloned), as the repo's default: nonna.mode, in the repo or --global, is the user's and outranks it.
if git config nonna.defaultMode "$mode"; then
  done_msgs+=("mode: $mode (git config nonna.defaultMode)${hint:+ — $hint}")
else
  warn_msgs+=("could not record the mode in git config, so she goes by what this repository carries")
  failed=1
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
