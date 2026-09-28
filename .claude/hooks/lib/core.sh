# shellcheck shell=bash
# Sourced helper — where the harness lives, and how the constitution travels.
# Shared by session-start.sh (parent session) and subagent-start.sh (every
# subagent), so the two carriers cannot drift apart (ADR-0007, ADR-0008).

# The harness this file belongs to (hooks/lib/../..), wherever it was loaded from: a copy-in repo's
# .claude/, the plugin's directory, or a git hook's link target. Symlinks resolved.
_nonna_self="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." 2>/dev/null && pwd -P)"

# nonna_harness_root
#   Prints the harness the running hook belongs to: ${CLAUDE_PLUGIN_ROOT} under a plugin install
#   (Claude Code sets it), else the directory this library was loaded from; nothing when neither
#   is a harness. Never a project's .claude/ unless that is the harness running: a repository can
#   ship a .claude/hooks/ of its own, and a plugin must not source, run or wire what it ships.
nonna_harness_root() {
  if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/hooks/require-status-sync.sh" ]; then
    printf '%s' "${CLAUDE_PLUGIN_ROOT}"
  elif [ -n "$_nonna_self" ] && [ -f "$_nonna_self/hooks/require-status-sync.sh" ]; then
    printf '%s' "$_nonna_self"
  fi
}

# nonna_copy_in
#   True when the running harness is this repository's own .claude/ (a copy-in install): only then
#   may Nonna detect and run the repo's test command unasked, and link its git hooks to repo scripts.
#   Runs from the project directory.
nonna_copy_in() {
  local repo
  repo="$(cd .claude 2>/dev/null && pwd -P)" || return 1
  [ -n "$_nonna_self" ] && [ "$_nonna_self" = "$repo" ]
}

# nonna_config <key>
#   The key from the repo's own git config, else from the user's global one: never from a file
#   those merely include, a `git -c` flag or GIT_CONFIG_* variables, which whoever runs git can
#   set for one command. Set to "" prints "" and succeeds, because empty means off.
nonna_config() {
  git config --local --no-includes --get "$1" 2>/dev/null \
    || git config --global --no-includes --get "$1" 2>/dev/null
}

# nonna_hook_is_hers <link target> <script> [<her link now>]
#   True when a git hook's link leads to her own <script>: the link she would make now, one into her
#   plugin's cache or data under the plugins directory Claude Code uses (a version since removed;
#   Keel was her name), or a copy-in's ../../.claude/hooks/<script>. A user's own script that
#   shares the name, a path merely shaped like hers, or one that climbs back out of hers with ..,
#   is not hers. The plugins directory is read as written (a doubled slash squeezed, as a HOME
#   ending in / gives) and as resolved.
nonna_hook_is_hers() {
  local p plugins real
  [ -n "${3:-}" ] && [ "$1" = "$3" ] && return 0
  [ "$1" = "../../.claude/hooks/$2" ] && return 0
  case "$1" in */../* | */..) return 1 ;; esac
  plugins="$(printf '%s' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins" | tr -s /)"
  real="$(cd "$plugins" 2>/dev/null && pwd -P)"
  for p in "$plugins" ${real:+"$real"}; do
    case "$1" in
      "$p"/cache/nonna/*/"$2" | "$p"/cache/keel/*/"$2" | "$p"/data/nonna*/"$2" | "$p"/data/keel*/"$2") return 0 ;;
    esac
  done
  return 1
}

# nonna_hook_chains_hers <hook file> <script> [<her link now>]
#   True when a hook that is not hers runs hers: its text names her script's path (the link she
#   would make, .claude/hooks/<script> or current/hooks/<script>), not merely a file that shares
#   the script's name.
nonna_hook_chains_hers() {
  grep -qsF -e ".claude/hooks/$2" -e "current/hooks/$2" -e "${3:-.claude/hooks/$2}" "$1"
}

# nonna_mode [git-hook]
#   Prints off, lite or full: what Nonna enforces in the repo in the current directory.
#   Precedence: NONNA_MODE > git config nonna.mode (repo, then global) > the plugin's `mode`
#   option > nonna.defaultMode > what the repo carries (the hooks and the rules: full; else lite).
#   git config is the per-repo switch because git hooks read it too, it is never committed, and a
#   clone cannot carry it. nonna.mode is the user's alone; what Nonna records (the plugin option,
#   for git hooks that cannot see it, or install.sh --mode) goes in nonna.defaultMode, below it, so
#   a global off still reaches every repo. A value nobody meant (a typo) fails closed to full.
#   A git hook passes `git-hook`: it runs in the environment of whoever ran git, which may be the
#   agent's own command, so it takes nothing from the environment. Claude Code's hooks run in
#   Claude Code's environment, which the user set.
nonna_mode() {
  _nonna_mode_read "${1:-}"
  case "$_nonna_mode" in off | lite | full) printf '%s' "$_nonna_mode" ;; *) printf 'full' ;; esac
}

# nonna_mode_source [git-hook]
#   Prints where nonna_mode's answer comes from, as /nonna shows it: NONNA_MODE, git config
#   nonna.mode, the plugin's mode option, git config nonna.defaultMode, the harness the repository
#   carries, or the default.
nonna_mode_source() {
  _nonna_mode_read "${1:-}"
  printf '%s' "$_nonna_from"
}

# _nonna_mode_read [git-hook]: the precedence itself, once. Sets _nonna_mode (as found) and _nonna_from.
_nonna_mode_read() {
  _nonna_mode="" _nonna_from=""
  if [ "${1:-}" != git-hook ] && [ -n "${NONNA_MODE:-}" ]; then
    _nonna_mode="$NONNA_MODE" _nonna_from=NONNA_MODE
  elif _nonna_mode="$(nonna_config nonna.mode)" && [ -n "$_nonna_mode" ]; then
    _nonna_from="git config nonna.mode"
  elif [ "${1:-}" != git-hook ] && [ -n "${CLAUDE_PLUGIN_OPTION_MODE:-}" ]; then
    _nonna_mode="$CLAUDE_PLUGIN_OPTION_MODE" _nonna_from="the plugin's mode option"
  elif _nonna_mode="$(nonna_config nonna.defaultMode)" && [ -n "$_nonna_mode" ]; then
    _nonna_from="git config nonna.defaultMode"
  # A repo that carries the whole harness (its hooks and its rules) is a full copy-in; a lite
  # copy-in carries no rules, and its clones have no nonna.defaultMode, since .git/config is not
  # cloned. What a repo carries can only raise the mode to full, never lower it.
  elif [ -f .claude/hooks/require-status-sync.sh ] && [ -f .claude/rules/00-core.md ]; then
    _nonna_mode=full _nonna_from="the harness this repository carries"
  else
    _nonna_mode=lite _nonna_from="the default"
  fi
}

# nonna_core_carrier
#   Plugin install: Claude Code's plugin schema has no `rules` component, so
#   .claude/rules/ never loads for a plugin user — they would get every agent,
#   skill and command but none of the policy that governs them. additionalContext
#   is the only channel that reaches them, and only 00-core.md rides it: budgeted
#   under 9,000 chars against the 10,000 cap, because an overrun truncates silently.
#   A standalone checkout already loads rules/ natively — print nothing, never
#   double-pay. Runs from the project directory.
#   What rides depends on the mode: lite carries the short house rules (hooks/lib/lite.md), full
#   carries the constitution, off carries nothing. In full mode, when another plugin already states
#   the decision ladder (lib/ladder.sh), the constitution's copy is dropped rather than said twice.
nonna_core_carrier() {
  local root mode file core
  [ -f ".claude/rules/00-core.md" ] && return 0
  root="$(nonna_harness_root)"
  [ -n "$root" ] || return 0
  mode="$(nonna_mode)"
  case "$mode" in
    lite) file="$root/hooks/lib/lite.md" ;;
    full) file="$root/rules/00-core.md" ;;
    *) return 0 ;;
  esac
  [ -f "$file" ] || return 0
  core="$(cat "$file" 2>/dev/null)"
  [ -n "$core" ] || return 0
  if [ "$mode" = lite ]; then
    printf '%s\n' "$core"
    return 0
  fi
  # shellcheck source=/dev/null
  if . "$root/hooks/lib/ladder.sh" 2>/dev/null && nonna_ladder_elsewhere; then
    core="$(printf '%s\n' "$core" | nonna_drop_ladder)"
  fi
  printf '%s\n\n%s\n' \
    "Nonna's operating rules are NOT loaded in this install (plugin installs cannot carry .claude/rules/ — see ADR-0007). The constitution follows; the full rules are readable at ${root}/rules/." \
    "$core"
}

# nonna_emit_context <event> <text> [user message]
#   Prints the hookSpecificOutput envelope Claude Code reads for context injection, plus a
#   systemMessage, which Claude Code shows to the user, when a user message is given. jq does the
#   escaping when present; the fallback escapes the JSON strings by hand so a multi-line carrier
#   is still valid JSON without it.
nonna_emit_context() {
  local event="$1" text="$2" user="${3:-}" esc uesc
  if command -v jq >/dev/null 2>&1; then
    jq -cn --arg e "$event" --arg c "$text" --arg u "$user" \
      '{hookSpecificOutput: {hookEventName: $e, additionalContext: $c}} + (if $u == "" then {} else {systemMessage: $u} end)'
    return 0
  fi
  esc="$(_nonna_json_escape "$text")"
  # No awk: the escaper yields nothing from non-empty input. Emit nothing and say so, never an
  # empty, silent carrier.
  if [ -n "$text" ] && [ -z "$esc" ]; then
    printf 'nonna: cannot emit %s context without jq or awk\n' "$event" >&2
    return 0
  fi
  uesc=""
  [ -z "$user" ] || uesc="$(_nonna_json_escape "$user")"
  if [ -n "$uesc" ]; then
    printf '{"systemMessage":"%s","hookSpecificOutput":{"hookEventName":"%s","additionalContext":"%s"}}\n' "$uesc" "$event" "$esc"
  else
    printf '{"hookSpecificOutput":{"hookEventName":"%s","additionalContext":"%s"}}\n' "$event" "$esc"
  fi
}

# _nonna_json_escape <text>
#   The text as the inside of a JSON string, without jq. Character by character with plain string
#   literals: gsub replacement strings treat backslashes differently in mawk and gawk, and a JSON
#   escaper cannot afford that. Tab/CR become escapes; every other C0 control byte is dropped (JSON
#   forbids them raw, and none carries meaning here); newlines are joined last. Without awk it
#   prints nothing, and the caller says so.
_nonna_json_escape() {
  printf '%s' "$1" \
    | tr -d '\000-\010\013\014\016-\037' \
    | awk '{ out = ""
             for (i = 1; i <= length($0); i++) { c = substr($0, i, 1)
               if (c == "\\") c = "\\\\"; else if (c == "\"") c = "\\\""
               else if (c == "\t") c = "\\t"; else if (c == "\r") c = "\\r"
               out = out c }
             if (NR > 1) printf "\\n"; printf "%s", out }' 2>/dev/null
}
