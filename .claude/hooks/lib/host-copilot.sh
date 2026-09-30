# shellcheck shell=bash
# Sourced helper — GitHub Copilot CLI's hook payloads and replies, read and said as Claude Code's.
# Copilot runs her gates from hooks/copilot-hooks.json, which puts NONNA_HOST=copilot in their
# environment; a gate that needs this sources it inside its own `if [ "${NONNA_HOST:-}" = copilot ]`
# block (ADR-0012). The host is what that file says, never a guess from the payload.
#
# The hooks file names its events in PascalCase, so Copilot sends its VS Code compatible payload:
# snake_case, with session_id, cwd, stop_hook_active and Claude Code's tool name (Bash, Write, Edit,
# Read, Grep). Only its tools' arguments keep Copilot's own names, and only its replies take another
# form (docs.github.com/en/copilot/reference/hooks-reference).

# nonna_copilot_payload
#   Reads a payload on stdin and prints it in Claude Code's shape. A file tool's path becomes
#   file_path, create's file_text content, edit's old_str and new_str old_string and new_string, and
#   grep's paths path (a list gives its first). apply_patch's raw patch text becomes content, all of
#   it scanned, so a patch that only removes a key is refused too. str_replace_editor's view, which
#   arrives as an Edit, becomes a Read. Copilot's own keys stay. A payload with nothing to translate,
#   or no JSON at all, passes byte for byte. Without jq, "path" keys are renamed "file_path" in the
#   text, where the gates' own reader finds them; the secret guard scans the raw payload then.
nonna_copilot_payload() {
  local in out
  in="$(cat 2>/dev/null || true)"
  if ! command -v jq >/dev/null 2>&1; then
    printf '%s' "$in" | sed 's/"path"\([[:space:]]*:\)/"file_path"\1/g'
    return 0
  fi
  out="$(printf '%s' "$in" | jq -c '
    . as $in
    | if type != "object" then .
      elif .tool_name == "Edit" and (.tool_input | type) == "string" then .tool_input = {content: .tool_input}
      elif (.tool_input | type) == "object" then
        (if .tool_name == "Edit" and .tool_input.command == "view" then .tool_name = "Read" else . end)
        | .tool_name as $tool
        | .tool_input |= (
            (if ($tool == "Read" or $tool == "Write" or $tool == "Edit") and has("path") and (has("file_path") | not)
              then .file_path = .path else . end)
          | (if has("file_text") and (has("content") | not) then .content = .file_text else . end)
          | (if has("old_str") and (has("old_string") | not) then .old_string = .old_str else . end)
          | (if has("new_str") and (has("new_string") | not) then .new_string = .new_str else . end)
          | (if has("paths") and (has("path") | not)
              then .path = (.paths | if type == "array" then .[0] else . end) else . end))
      else . end
    | if . == $in then empty else . end' 2>/dev/null)"
  if [ -n "$out" ]; then printf '%s' "$out"; else printf '%s' "$in"; fi
}

# nonna_copilot_reply
#   From here to the gate's exit, holds what it prints, and at exit says it in Copilot's form, with the
#   same exit status. A refusal (exit 2) also goes to stdout as permissionDecision "deny" with her
#   message as permissionDecisionReason: exit 2 alone denies, but the reason Copilot shows the agent
#   comes from there. Claude Code's hookSpecificOutput.additionalContext becomes a top-level
#   additionalContext, and its systemMessage, which Claude Code shows the user, a progress line, which
#   Copilot shows. Her messages still go to stderr. Without jq or a temporary directory nothing is
#   held: the reply stays Claude Code's, and exit 2 still denies.
nonna_copilot_reply() {
  command -v jq >/dev/null 2>&1 || return 0
  _nonna_copilot_held="$(mktemp -d 2>/dev/null)" && [ -d "$_nonna_copilot_held" ] || return 0
  exec 7>&1 8>&2 >"$_nonna_copilot_held/out" 2>"$_nonna_copilot_held/err"
  trap '_nonna_copilot_say "$?"' EXIT
}

_nonna_copilot_say() { # <exit status>: the held reply, in Copilot's form; then that exit
  local rc="$1" held="$_nonna_copilot_held"
  exec >&7 2>&8 7>&- 8>&-
  cat "$held/err" >&2
  if [ "$rc" = 2 ]; then
    jq -cn --arg r "$(cat "$held/err")" '{permissionDecision: "deny", permissionDecisionReason: $r}'
  else
    jq -c 'if type == "object" and (.hookSpecificOutput.additionalContext? | type) == "string" then
        (if (.systemMessage | type) == "string" and .systemMessage != "" then {type: "progress", message: .systemMessage} else empty end),
        {additionalContext: .hookSpecificOutput.additionalContext}
      else . end' "$held/out" 2>/dev/null || cat "$held/out"
  fi
  rm -rf "$held"
  exit "$rc"
}
