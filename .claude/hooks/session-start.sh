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
if [ "${NONNA_HOST:-}" = copilot ]; then # Copilot CLI: its reply (ADR-0015)
  # shellcheck source=/dev/null
  . "$here/lib/host-copilot.sh"
  nonna_copilot_reply
fi

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
#    .claude/hooks (in the subdirectory the session runs in), which survives a repo move. A plugin
#    install links through ${CLAUDE_PLUGIN_DATA}/current, a link to the running plugin version
#    refreshed every session: the versioned cache directory is removed after an update, and git
#    silently skips a dangling hook. Where ln -s makes a copy (Git Bash without native symlinks), each
#    link is her wrapper instead, a script that runs her script (nonna_hook_wrapper, lib/core.sh), and
#    current is a directory of wrappers. A foreign hook is never overwritten, a hook manager's directory
#    never written: both are reported, because a gate that is off without saying so is what ADR-0004
#    exists to prevent.
data="${1:-${CLAUDE_PLUGIN_DATA:-}}"
hooks_dir="$(git rev-parse --git-path hooks 2>/dev/null || true)"
hooks_src=""
if nonna_copy_in; then # the repo's own harness: its own scripts, relative to the hooks dir
  # Outside .git/ (a hook manager's dir) or a submodule's, nothing is linked: the warning below names
  # the resolved path of the .claude/ nonna_copy_in just found here.
  hooks_src="$(nonna_copy_in_hooks "$hooks_dir" "$(git rev-parse --show-prefix 2>/dev/null)")" \
    || hooks_src="$(cd .claude && pwd -P)/hooks"
elif [ -n "$nonna_root" ]; then # a plugin: its own scripts, never ones the repo ships
  hooks_src="$nonna_root/hooks"
  if [ -n "$data" ] && mkdir -p "$data" 2>/dev/null; then
    if { [ -L "$data/current" ] || [ ! -e "$data/current" ]; } && nonna_links "$data"; then
      ln -sfn "$nonna_root" "$data/current" 2>/dev/null && hooks_src="$data/current/hooks"
    # Where ln -s copies (Git Bash), current is a directory of her wrappers, written again every session. A
    # link left from when links worked goes first: written through, it would write into her.
    elif { [ ! -L "$data/current" ] || rm -f "$data/current"; } && nonna_hook_wrappers "$data/current/hooks" "$nonna_root/hooks"; then
      hooks_src="$data/current/hooks"
    fi
  fi
fi
wired=()
hook_warns=()
wire_hook() { # <git hook name> <script name>
  local dest="$hooks_dir/$1" target="$hooks_src/$2" real
  real="$target"
  nonna_abs "$target" || real="$hooks_dir/$target" # where her script is, from here
  if nonna_hook_is_hers "$(nonna_hook_target "$dest" 2>/dev/null)" "$2" "$target" && nonna_hook_dangles "$dest"; then
    rm -f "$dest" # hers, and leading to nothing: repaired below
  fi
  if [ ! -e "$dest" ] && [ ! -L "$dest" ]; then
    # Never wire a hook to nothing: git would skip a link to it without a word.
    [ -e "$real" ] || { hook_warns+=("$2 is missing from the harness, so the $1 gate is NOT enforced"); return 0; }
    # A link, or where ln -s copies (Git Bash) her wrapper: a copy of her script would find no lib/ beside
    # it, and git would run it and it would wave everything through.
    if nonna_hook_link "$target" "$dest"; then
      wired+=("$1")
    else
      hook_warns+=("could not install $dest, so that gate is NOT enforced")
    fi
  else
    if nonna_hook_is_hers "$(nonna_hook_target "$dest" 2>/dev/null)" "$2" "$target"; then
      # Hers, but git skips a link that points at nothing without a word, and her wrapper runs nothing.
      ! nonna_hook_dangles "$dest" || hook_warns+=("$dest points at nothing, so her $1 gate is NOT enforced")
    elif nonna_hook_is_copy "$dest" "$real" || { [ -n "$nonna_root" ] && nonna_hook_is_copy "$dest" "$nonna_root/hooks/$2"; }; then
      # What an older session start left where ln -s copies (Git Bash): it runs, finds no lib/ beside itself
      # and enforces nothing. Named and never deleted: it was there before me. Compared with her script itself,
      # since where ln -s copies a plugin's data dir holds her wrapper of it.
      hook_warns+=("$dest is a copy of her $2, not a link, and a copy cannot find its lib/ (unless you copied its lib/ beside it), so her $1 gate is NOT enforced; delete it")
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
#    The mode option is mirrored every session into nonna.defaultMode, as the hooks read it (lite,
#    else full: nonna_option_mode), which ranks below the user's nonna.mode (repo or global): Nonna
#    never writes nonna.mode. The first time Nonna meets the repo, and only when the run_tests
#    option allows it (the default), the test command detection finds is recorded; a command
#    already set is never overwritten, nor an empty one (gate off).
if ! nonna_copy_in && [ -n "$nonna_root" ] && git rev-parse --git-dir >/dev/null 2>&1; then
  option_mode="$(nonna_option_mode)"
  if [ -n "$option_mode" ] && [ "$(git config --local --get nonna.defaultMode 2>/dev/null)" != "$option_mode" ]; then
    git config nonna.defaultMode "$option_mode" 2>/dev/null || true
  fi
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
  msg="${msg} Test gate: off, no test command found here (or its runner is not installed). The user can set one: /nonna test '<command>'."
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
    user_msg="$user_msg She found no test command here (or its runner is not installed), so the test gate is off; set one with: /nonna test '<command>'."
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
