#!/usr/bin/env bash
# SessionStart — make the harness self-installing and situational.
#   1. Idempotently install the Definition-of-Done pre-push hook, so the gate
#      runs on a fresh clone without a manual symlink (closes the "never wired"
#      gap that made the DoD gate inert in v0.1).
#   2. Detect the project's toolchain.
#   3. Inject a short additionalContext note: the gates are live, and the likely
#      test command.
# Best-effort: always exits 0; a SessionStart failure must never wedge a session.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$here/lib/core.sh"
root="${CLAUDE_PROJECT_DIR:-$(pwd)}"
cd "$root" 2>/dev/null || exit 0
[ "$(nonna_mode)" = off ] && exit 0 # off means off: nothing enforced, nothing said

# 0. Resolve the harness root. A standalone checkout has .claude/ in the repo; a
#    plugin install has the harness at ${CLAUDE_PLUGIN_ROOT} and NOTHING in the
#    repo. Guarding only on the project-local path made a plugin install skip the
#    DoD gate in silence — a gate that is off without saying so is precisely the
#    unwired-gate defect ADR-0004 exists to prevent.
#    Resolution lives in lib/core.sh, shared with subagent-start.sh.
nonna_root="$(nonna_harness_root)"
# 0. Where this session began. Stop tests everything changed since, committed or not, so work
#    committed during a session cannot dodge the gate. One file per session, kept a week.
# shellcheck source=/dev/null
. "$here/lib/json.sh"
sid="$(nonna_json_field '.session_id' <<<"$(cat 2>/dev/null || true)" | tr -cd 'A-Za-z0-9._-')"
if [ -n "$sid" ] && base_dir="$(git rev-parse --git-path nonna 2>/dev/null)" && mkdir -p "$base_dir" 2>/dev/null; then
  find "$base_dir" \( -name 'base-*' -o -name 'notest-*' \) -mtime +7 -delete 2>/dev/null || true
  if [ ! -e "$base_dir/base-$sid" ] && head_sha="$(git rev-parse --verify --quiet HEAD)"; then
    printf '%s\n' "$head_sha" > "$base_dir/base-$sid" 2>/dev/null || true
  fi
fi

# 1. Wire the git hooks (pre-push, pre-commit). A copy-in install links relative to the repo's own
#    .claude/hooks, which survives a repo move. A plugin install links through
#    ${CLAUDE_PLUGIN_DATA}/current, a link to the running plugin version refreshed every session: the
#    versioned cache directory is removed after an update, and git silently skips a dangling hook.
#    A foreign hook is never overwritten, a hook manager's directory never written: both are
#    reported, because a gate that is off without saying so is what ADR-0004 exists to prevent.
data="${1:-${CLAUDE_PLUGIN_DATA:-}}"
hooks_dir="$(git rev-parse --git-path hooks 2>/dev/null || true)"
hooks_src=""
if nonna_copy_in; then
  hooks_src="../../.claude/hooks" # the repo's own harness: its own scripts, relative
elif [ -n "$nonna_root" ]; then # a plugin: its own scripts, never ones the repo ships
  hooks_src="$nonna_root/hooks"
  if [ -n "$data" ] && mkdir -p "$data" 2>/dev/null && ln -sfn "$nonna_root" "$data/current" 2>/dev/null; then
    hooks_src="$data/current/hooks"
  fi
fi
wired=()
hook_warns=()
wire_hook() { # <git hook name> <script name>
  local dest="$hooks_dir/$1" target="$hooks_src/$2"
  if [ -L "$dest" ] && [ ! -e "$dest" ] && nonna_hook_is_hers "$(readlink "$dest")" "$2" "$target"; then
    rm -f "$dest" # dangling and hers: repaired below
  fi
  if [ ! -e "$dest" ] && [ ! -L "$dest" ]; then
    # Never create a dangling link: git would skip it without a word.
    case "$target" in /*) ;; *) [ -e "$hooks_dir/$target" ] || { hook_warns+=("$2 is missing from the harness, so the $1 gate is NOT enforced"); return 0; } ;; esac
    [ -e "$target" ] || [ "${target#/}" = "$target" ] || { hook_warns+=("$2 is missing from the harness, so the $1 gate is NOT enforced"); return 0; }
    mkdir -p "$hooks_dir" 2>/dev/null && ln -s "$target" "$dest" 2>/dev/null && wired+=("$1")
    [ -e "$dest" ] || hook_warns+=("could not install $dest, so that gate is NOT enforced")
  else
    if nonna_hook_is_hers "$(readlink "$dest" 2>/dev/null)" "$2" "$target"; then
      # Hers, but git skips a link that points at nothing without a word.
      [ -e "$dest" ] || hook_warns+=("$dest points at nothing, so her $1 gate is NOT enforced")
    else # the user's own, even when it shares her script's name, unless it chains hers
      nonna_hook_chains_hers "$dest" "$2" "$target" \
        || hook_warns+=("$dest is not Nonna's, so her $1 gate is NOT enforced; chain $target from it")
    fi
  fi
}
if ! git rev-parse --git-dir >/dev/null 2>&1; then
  : # not a git checkout: nothing to wire, nothing to warn about
elif [ -z "$hooks_src" ]; then
  hook_warns+=("Nonna's git hooks could not be located (no .claude/hooks/ here and CLAUDE_PLUGIN_ROOT unset), so they are NOT enforced")
else
  case "$hooks_dir" in
    .git/hooks | */.git/hooks | */.git/worktrees/*/hooks)
      wire_hook pre-push require-status-sync.sh
      wire_hook pre-commit pre-commit.sh
      ;;
    *) hook_warns+=("git hooks live in $hooks_dir (a hook manager?): point its pre-push at $hooks_src/require-status-sync.sh and its pre-commit at $hooks_src/pre-commit.sh, or they are NOT enforced") ;;
  esac
fi
hook_warn=""
[ "${#hook_warns[@]}" -eq 0 ] || hook_warn=" WARNING: $(printf '%s; ' "${hook_warns[@]}")"

# 2. Plugin install: record what the git hooks cannot read from the plugin's options, in the repo's
#    own git config, which is never committed and never cloned, so a hostile repo cannot plant it.
#    The mode option is mirrored every session into nonna.defaultMode, which ranks below the user's
#    nonna.mode (repo or global): Nonna never writes nonna.mode. The first time Nonna meets the
#    repo, and only when the run_tests option allows it (the default), the test command detection
#    finds is recorded; a command already set is never overwritten, nor an empty one (gate off).
if ! nonna_copy_in && [ -n "$nonna_root" ] && git rev-parse --git-dir >/dev/null 2>&1; then
  case "${CLAUDE_PLUGIN_OPTION_MODE:-}" in
    lite | full)
      [ "$(git config --local --get nonna.defaultMode 2>/dev/null)" = "$CLAUDE_PLUGIN_OPTION_MODE" ] \
        || git config nonna.defaultMode "$CLAUDE_PLUGIN_OPTION_MODE" 2>/dev/null || true
      ;;
  esac
  case "${CLAUDE_PLUGIN_OPTION_RUN_TESTS:-true}" in
    false | False | FALSE | 0 | no | off) : ;;
    *)
      if ! nonna_config nonna.testCmd >/dev/null && [ -f "$here/lib/tests.sh" ]; then
        # shellcheck source=/dev/null
        . "$here/lib/tests.sh"
        detected="$(nonna_detect_test_cmd)"
        [ -z "$detected" ] || git config nonna.testCmd "$detected" 2>/dev/null || true
      fi
      ;;
  esac
fi
gate=""
if [ -f "$here/lib/tests.sh" ]; then # this hook's own library, never one the repo ships
  # shellcheck source=/dev/null
  . "$here/lib/tests.sh"
  gate="$(nonna_test_cmd)"
fi

# 3. Detect toolchain.
stack=""
[ -f package.json ] && stack="$stack node"
{ [ -f pyproject.toml ] || [ -f setup.cfg ]; } && stack="$stack python"
[ -f go.mod ] && stack="$stack go"
[ -f Cargo.toml ] && stack="$stack rust"
stack="$(printf '%s' "$stack" | sed 's/^ //')"
[ -n "$stack" ] || stack="undetected"

# 4. Emit additionalContext (JSON on stdout; exit 0).
mode="$(nonna_mode)"
status_gate=""
[ "$mode" = full ] && [ -f docs/STATUS.md ] && status_gate=", the Definition-of-Done record (docs/STATUS.md, at turn end and pre-push)"
msg="Nonna is on (${mode}). Gates live: branch guard (no commits or pushes to main/master/develop, no force push, no skipping the git hooks), secret guard (writes, reads of secret files, commits, pushes)${status_gate}. Detected stack: ${stack}.${hook_warn}"
# Announce where the harness actually lives. Commands invoke gate scripts under
# skills/*/scripts/; that path differs between a standalone checkout and a plugin
# install, and the model cannot infer it. Resolving it here — in the one process
# that has CLAUDE_PLUGIN_ROOT exported — keeps the model out of the guess.
[ -n "$nonna_root" ] && msg="${msg} Harness root: ${nonna_root} — gate scripts live at \${NONNA}/skills/<skill>/scripts/, e.g. ${nonna_root}/skills/code-review/scripts/check-review.sh."
if [ -n "$gate" ]; then
  msg="${msg} Test gate: ${gate} runs before a turn that changed code can end, and before a push; a red suite blocks."
else
  msg="${msg} Test gate: off, no test command found here. The user can set one: /nonna test '<command>'."
fi

# 5. Plugin install: carry the constitution in (nonna_core_carrier, lib/core.sh —
#    the same carrier subagent-start.sh uses, so parent and subagents agree).
core="$(nonna_core_carrier)"
[ -n "$core" ] && msg="${msg}

${core}"

# 6. The first session in a repo (per major version) tells the user, not only the agent, what Nonna
#    did here: a plugin that edits .git/hooks and .git/config without saying so would be right to be
#    distrusted. Claude Code shows a systemMessage to the user.
user_msg=""
if [ "$(nonna_config nonna.announced)" != 2 ] && git rev-parse --git-dir >/dev/null 2>&1; then
  user_msg="Nonna is on here (${mode})."
  if [ -n "$gate" ]; then
    user_msg="$user_msg Before the agent can say done, Nonna runs: ${gate}."
  else
    user_msg="$user_msg She found no test command here, so the test gate is off; set one with: /nonna test '<command>'."
  fi
  if [ "${#wired[@]}" -gt 0 ]; then
    added="${wired[0]}"
    [ "${#wired[@]}" -lt 2 ] || added="${wired[0]} and ${wired[1]}"
    user_msg="$user_msg Added .git/hooks/${added}."
  fi
  [ "${#hook_warns[@]}" -eq 0 ] || user_msg="$user_msg Note: $(printf '%s; ' "${hook_warns[@]}")"
  user_msg="$user_msg See or change it with /nonna."
  git config nonna.announced 2 2>/dev/null || true
fi

nonna_emit_context SessionStart "$msg" "$user_msg"
exit 0
