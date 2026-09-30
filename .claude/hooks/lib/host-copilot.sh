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
#   Reads a payload on stdin and prints it in Claude Code's shape, one payload per line. Copilot's
#   argument names are what its tools act on, so they win over any Claude-named key beside them (a
#   decoy): path is file_path, old_str old_string; a write's content keys (file_text, content, and
#   apply_patch's text, raw or as input or patch) are joined into content, and new_str and new_string
#   into new_string, so each is scanned; a patch is scanned whole. write_bash's input is a Bash
#   command, and str_replace_editor's view, which arrives as an Edit, a Read. A grep is one payload per
#   path it names, in paths or beside them, for nonna_copilot_each; more than 32 paths, which could not
#   all be judged before the hook times out (and Copilot lets a timed-out call through), are refused
#   up front. A payload with nothing to translate, or no JSON at all, passes unchanged, on one line.
#   Without jq, "path" is renamed
#   "file_path", and a "paths" that is one string "path", in the text, where the gates' own reader
#   finds them; what the text cannot be trusted to show (a file_path beside path, a list of paths, a
#   shell's input) is refused: exit 2, her reason on stderr.
nonna_copilot_payload() {
  local in out why=""
  in="$(cat 2>/dev/null | tr '\n' ' ')" # a raw newline in JSON is whitespace: one line per payload
  if ! command -v jq >/dev/null 2>&1; then
    if printf '%s' "$in" | grep -qE '"file_path"[[:space:]]*:'; then
      why="a file_path beside Copilot's own path"
    elif printf '%s' "$in" | grep -qE '"paths"[[:space:]]*:[[:space:]]*\['; then
      why="a list of paths"
    elif printf '%s' "$in" | grep -qE '"tool_name"[[:space:]]*:[[:space:]]*"write_(bash|powershell)"'; then
      why="input to a shell"
    fi
    if [ -n "$why" ]; then
      echo "✗ Nonna: I can't taste what I can't read. (Copilot CLI: without jq, ${why} cannot be read, so it is refused.)" >&2
      echo "  Run it again once jq is installed, or tell the user plainly why you cannot." >&2
      return 2
    fi
    printf '%s' "$in" | sed -e 's/"path"\([[:space:]]*:\)/"file_path"\1/g' -e 's/"paths"\([[:space:]]*:\)/"path"\1/g'
    return 0
  fi
  out="$(printf '%s' "$in" | jq -c --argjson most 32 '
    def joined($keys): [$keys[] as $k | .[$k] | strings] | if length > 0 then join("\n") else null end;
    . as $in
    | if type != "object" then [.]
      else
        (if .tool_name == "write_bash" or .tool_name == "write_powershell" then
            .tool_name = "Bash" | if (.tool_input | type) == "object" then .tool_input.command = .tool_input.input else . end
          else . end)
        | (if .tool_name == "Edit" and (.tool_input | type) == "string" then .tool_input = {content: .tool_input} else . end)
        | (if .tool_name == "Edit" and (.tool_input | type) == "object" and .tool_input.command == "view" then .tool_name = "Read" else . end)
        | .tool_name as $tool
        | if (.tool_input | type) != "object" then [.]
          elif $tool == "Write" or $tool == "Edit" then
            [.tool_input |= (
                (if (.path | type) == "string" then .file_path = .path else . end)
              | (joined(["file_text", "content", "input", "patch"]) as $c | if $c == null then . else .content = $c end)
              | (joined(["new_str", "new_string"]) as $n | if $n == null then . else .new_string = $n end)
              | (if (.old_str | type) == "string" then .old_string = .old_str else . end))]
          elif $tool == "Read" then
            [.tool_input |= (if (.path | type) == "string" then .file_path = .path else . end)]
          elif $tool == "Grep" then
            ([.tool_input.path, (.tool_input.paths | if type == "array" then .[] else . end)] | map(strings) | unique) as $each
            | if ($each | length) > $most then
                [{nonna_copilot_refuse: "too_long", why: "a grep over more than \($most) paths is refused: each path is judged on its own, and so many would outrun the timeout of the hook"}]
              elif ($each | length) == 0 then [.]
              else [. as $call | $each[] | . as $one | $call | .tool_input.path = $one] end
          else [.] end
      end
    | if . == [$in] then empty else .[] end' 2>/dev/null)" || {
    # No JSON at all goes on, for the gate's own reader to judge. JSON that jq could not translate would
    # reach the gate with Copilot's names unread: refused.
    if printf '%s' "$in" | jq empty >/dev/null 2>&1; then
      echo "✗ Nonna: I can't taste what I can't read. (Copilot CLI: jq could not translate this call, so it is refused.)" >&2
      return 2
    fi
    out=""
  }
  case "$out" in
    '{"nonna_copilot_refuse":'*)
      _nonna_copilot_refuse "$(printf '%s' "$out" | jq -r .nonna_copilot_refuse)" "$(printf '%s' "$out" | jq -r .why)"
      return 2
      ;;
  esac
  if [ -n "$out" ]; then printf '%s' "$out"; else printf '%s' "$in"; fi
}

_nonna_copilot_refuse() { # <too_long|unread> <why>: her refusal, on stderr, as the branch guard says one
  if [ "$1" = too_long ]; then
    echo "✗ Nonna: that's too much to taste in one bite. (Copilot CLI: $2.)" >&2
    echo "  Split it into smaller calls." >&2
  else
    echo "✗ Nonna: I can't taste what I can't read. (Copilot CLI: $2, so it is refused, not guessed at.)" >&2
    echo "  Call the tool with its own arguments, or tell the user plainly why you cannot." >&2
  fi
}

# nonna_copilot_each <script> <payloads>
#   A call that names several targets comes out of nonna_copilot_payload as one payload per line. Then
#   <script> judges each on its own, with NONNA_HOST cleared, and the gate exits with the first answer
#   that is not 0, or with 0. With one payload it returns, and the gate reads that one.
nonna_copilot_each() {
  local one rc
  case "$2" in *$'\n'*) ;; *) return 0 ;; esac
  while IFS= read -r one; do
    [ -n "$one" ] || continue
    printf '%s' "$one" | NONNA_HOST='' bash "$1"
    rc=$?
    [ "$rc" = 0 ] || exit "$rc"
  done <<<"$2"
  exit 0
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
