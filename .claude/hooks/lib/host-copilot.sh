# shellcheck shell=bash
# Sourced helper — GitHub Copilot CLI's hook payloads and replies, read and said as Claude Code's.
# Copilot runs her gates from hooks/copilot-hooks.json, which puts NONNA_HOST=copilot in their
# environment; a gate that needs this sources it inside its own `if [ "${NONNA_HOST:-}" = copilot ]`
# block (ADR-0014). The host is what that file says, never a guess from the payload.
#
# The hooks file names its events in PascalCase, so Copilot sends its VS Code compatible payload:
# snake_case, with session_id, cwd, stop_hook_active and Claude Code's tool name (Bash, Write, Edit,
# Read, Grep). Only its tools' arguments keep Copilot's own names, and only its replies take another
# form (docs.github.com/en/copilot/reference/hooks-reference).

# nonna_copilot_payload
#   Reads a payload on stdin and prints it in Claude Code's shape, one payload per line. First the
#   shape Copilot sends is checked, and anything else is refused, never read untranslated: the payload
#   must be a JSON object; its tool_input an object, or, for an Edit (apply_patch's raw text) alone, a
#   string that does not hold JSON; path a string; paths one path or a flat, non-empty list of them.
#   Then Copilot's argument names, which its tools act on, win over any Claude-named key beside them
#   (a decoy): path is file_path, old_str old_string; a write's content keys (file_text, content, and
#   apply_patch's text, raw or as input or patch) are joined into content, and new_str and new_string
#   into new_string, so each is scanned; a patch is scanned whole. write_bash's input is a Bash
#   command, and str_replace_editor's view, which arrives as an Edit, a Read. A grep is one payload per
#   path it names, in paths or beside them, for nonna_copilot_each; more than 32 paths, which could not
#   all be judged before the hook times out (and Copilot lets a timed-out call through), are refused
#   up front. A payload with nothing to translate passes unchanged, on one line. Without jq, "path" is
#   renamed "file_path", and a "paths" that is one string "path", in the text, where the gates' own
#   reader finds them, and what the text cannot show with certainty is refused: a payload that does not
#   close, arguments that are not an object, a file_path beside path, a path or paths that are not one
#   string, a shell's input. A refusal is exit 2, her reason on stderr.
nonna_copilot_payload() {
  local in out why="" ti='"tool_input"[[:space:]]*:[[:space:]]*'
  in="$(cat 2>/dev/null | tr '\n' ' ')" # a raw newline in JSON is whitespace: one line per payload
  case "$in" in *[![:space:]]*) ;; *) _nonna_copilot_refuse unread "its payload is empty"; return 2 ;; esac
  if ! command -v jq >/dev/null 2>&1; then
    if ! printf '%s' "$in" | _nonna_copilot_closes; then
      why="a payload that is not one JSON object that closes"
    elif printf '%s' "$in" | grep -qE "${ti}\""; then
      if ! printf '%s' "$in" | grep -qE '"tool_name"[[:space:]]*:[[:space:]]*"Edit"' \
        || printf '%s' "$in" | grep -qE "${ti}\"[[:space:]]*\\{"; then
        why="arguments given as a string"
      fi
    elif ! printf '%s' "$in" | grep -qE "${ti}\\{"; then
      why="arguments that are not an object"
    elif printf '%s' "$in" | grep -qE '"file_path"[[:space:]]*:'; then
      why="a file_path beside Copilot's own path"
    elif printf '%s' "$in" | grep -qE '"paths?"[[:space:]]*:[[:space:]]*[^"[:space:]]'; then
      why="a path or paths that are not one string"
    elif printf '%s' "$in" | grep -qE '"tool_name"[[:space:]]*:[[:space:]]*"write_(bash|powershell)"'; then
      why="input to a shell"
    fi
    if [ -n "$why" ]; then
      _nonna_copilot_refuse unread "without jq, ${why} cannot be read"
      return 2
    fi
    printf '%s' "$in" | sed -e 's/"path"\([[:space:]]*:\)/"file_path"\1/g' -e 's/"paths"\([[:space:]]*:\)/"path"\1/g'
    return 0
  fi
  out="$(printf '%s' "$in" | jq -c --argjson most 32 '
    def joined($keys): [$keys[] as $k | .[$k] | strings] | if length > 0 then join("\n") else null end;
    def refuse($why): [{nonna_copilot_refuse: "unread", why: $why}];
    def paths_ok: type == "string" or (type == "array" and length > 0 and all(.[]; type == "string"));
    def holds_json: explode | map(select(. > 32)) | .[0] == 123;
    def translate:
      (if .tool_name == "write_bash" or .tool_name == "write_powershell" then
          .tool_name = "Bash" | .tool_input.command = .tool_input.input
        else . end)
      | (if .tool_name == "Edit" and (.tool_input | type) == "string" then .tool_input = {content: .tool_input} else . end)
      | (if .tool_name == "Edit" and .tool_input.command == "view" then .tool_name = "Read" else . end)
      | .tool_name as $tool
      | if $tool == "Write" or $tool == "Edit" then
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
        else [.] end;
    . as $in
    | if type != "object" then refuse("its payload is not a JSON object")
      elif (.tool_input | type) == "string" then
        if .tool_name == "Edit" and (.tool_input | holds_json | not) then translate
        else refuse("its arguments are a string where Copilot sends an object") end
      elif (.tool_input | type) != "object" then refuse("its arguments are not an object")
      elif (.tool_input | has("path")) and (.tool_input.path | type) != "string" then refuse("its path is not a string")
      elif (.tool_input | has("paths")) and (.tool_input.paths | paths_ok | not) then
        refuse("its paths are neither one path nor a flat, non-empty list of them")
      else translate end
    | if . == [$in] then empty else .[] end' 2>/dev/null)" || {
    # Not JSON that jq reads, or a jq that cannot run this: refused, never read with Copilot's names unread.
    _nonna_copilot_refuse unread "its payload is not JSON that jq can translate"
    return 2
  }
  case "$out" in
    '{"nonna_copilot_refuse":'*)
      _nonna_copilot_refuse "$(printf '%s' "$out" | jq -r .nonna_copilot_refuse)" "$(printf '%s' "$out" | jq -r .why)"
      return 2
      ;;
  esac
  if [ -n "$out" ]; then printf '%s' "$out"; else printf '%s' "$in"; fi
}

_nonna_copilot_closes() { # the text on stdin is one JSON object whose strings and brackets all close
  # Split into characters once, as json.sh does (one-true-awk copies a string on every substr()).
  LC_ALL=C awk '
    BEGIN { RS = sprintf("%c", 1) }
    { s = s (NR > 1 ? RS : "") $0 }
    END {
      n = split(s, ch, ""); top = 0; str = 0; esc = 0; done = 0
      for (i = 1; i <= n; i++) {
        c = ch[i]
        if (str) { if (esc) esc = 0; else if (c == "\\") esc = 1; else if (c == "\"") str = 0; continue }
        if (c == " " || c == "\t" || c == "\r" || c == "\n") continue
        if (done || (top == 0 && c != "{")) exit 1
        if (c == "\"") str = 1
        else if (c == "{" || c == "[") stack[++top] = c
        else if (c == "}" || c == "]") {
          if (stack[top] != (c == "}" ? "{" : "[")) exit 1
          if (--top == 0) done = 1
        }
      }
      exit (done ? 0 : 1)
    }' 2>/dev/null
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
