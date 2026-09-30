# shellcheck shell=bash
# Sourced helper — GitHub Copilot CLI's hook payloads and replies, read and said as Claude Code's.
# Copilot runs her gates from hooks/copilot-hooks.json, which puts NONNA_HOST=copilot in their
# environment; a gate that needs this sources it inside its own `if [ "${NONNA_HOST:-}" = copilot ]`
# block (ADR-0015). The host is what that file says, never a guess from the payload.
#
# The hooks file names its events in PascalCase, so Copilot sends its VS Code compatible payload:
# snake_case, with session_id, cwd, stop_hook_active and Claude Code's tool name (Bash, Write, Edit,
# Read, Grep). Only its tools' arguments keep Copilot's own names, and only its replies take another
# form (docs.github.com/en/copilot/reference/hooks-reference). An apply_patch, which arrives as an
# Edit, is read as Codex's is: lib/patch.sh reads it by its grammar, and lib/host-codex.sh's
# _nonna_codex_files makes each file it touches Claude Code's Write or Edit.

# shellcheck source=/dev/null
. "$(dirname "${BASH_SOURCE[0]}")/host-codex.sh"

# nonna_copilot_payload
#   Reads a payload on stdin and prints it in Claude Code's shape, one payload per line. First the
#   shape Copilot sends is checked, and anything else is refused, never read untranslated: the payload
#   must be a JSON object; its tool_input an object, or, for an Edit (apply_patch's raw text) alone, a
#   string that does not hold JSON; path a string; paths one path or a flat, non-empty list of them;
#   file_text, content, old_str, new_str, input and patch strings; and a Write or an Edit names a path
#   or carries a patch.
#   Then Copilot's argument names, which its tools act on, win over any Claude-named key beside them
#   (a decoy): path is file_path, old_str old_string; a write's content keys (file_text, content,
#   input, patch) are joined into content, and new_str and new_string into new_string, so each is
#   scanned. An apply_patch (an Edit whose arguments are its raw text, or hold it as input or patch)
#   is one payload per file it touches, a Write or an Edit with the lines it adds, as Codex's is; a
#   patch the reader refuses (outside its grammar, over 256 KB, over 200 files) is refused, and an Edit
#   that also names a path is judged both ways. write_bash's input is a Bash command, and
#   str_replace_editor's view, which arrives as an Edit, a Read. A grep is one payload per path it
#   names, in paths or beside them; more than 32 paths, which could not all be judged before the hook
#   times out (and Copilot lets a timed-out call through), are refused up front. Several payloads are
#   for nonna_copilot_each. A payload with nothing to translate passes unchanged, on one line. Without
#   jq, "path" is renamed "file_path", and a "paths" that is one string "path", in the text, where the
#   gates' own reader finds them, and a patch is read by lib/json.sh's own decoder; what the text
#   cannot show with certainty is refused: a payload that does not close, arguments that are not an
#   object or that hold one, more than one path, a file_path beside path, a path or paths that are not
#   one string, a shell's input, a patch beside other arguments. A refusal is exit 2, her reason on
#   stderr.
nonna_copilot_payload() {
  local in out why="" patch="" ti='"tool_input"[[:space:]]*:[[:space:]]*'
  in="$(cat 2>/dev/null | tr '\n' ' ')" # a raw newline in JSON is whitespace: one line per payload
  case "$in" in *[![:space:]]*) ;; *) _nonna_copilot_refuse unread "its payload is empty"; return 2 ;; esac
  if ! command -v jq >/dev/null 2>&1; then
    local shape=0
    printf '%s' "$in" | _nonna_copilot_shape || shape=$?
    if [ "$shape" = 3 ]; then
      why="an object inside its arguments"
    elif [ "$shape" = 4 ]; then
      why="more than one path"
    elif [ "$shape" != 0 ]; then
      why="a payload that is not one JSON object that closes"
    elif printf '%s' "$in" | grep -qE "${ti}\""; then
      if ! printf '%s' "$in" | grep -qE '"tool_name"[[:space:]]*:[[:space:]]*"Edit"' \
        || printf '%s' "$in" | grep -qE "${ti}\"[[:space:]]*\\{"; then
        why="arguments given as a string"
      else
        patch=raw
      fi
    elif ! printf '%s' "$in" | grep -qE "${ti}\\{"; then
      why="arguments that are not an object"
    elif printf '%s' "$in" | grep -qE '"file_path"[[:space:]]*:'; then
      why="a file_path beside Copilot's own path"
    elif printf '%s' "$in" | grep -qE '"paths?"[[:space:]]*:[[:space:]]*[^"[:space:]]'; then
      why="a path or paths that are not one string"
    elif printf '%s' "$in" | grep -qE '"tool_name"[[:space:]]*:[[:space:]]*"write_(bash|powershell)"'; then
      why="input to a shell"
    elif printf '%s' "$in" | grep -qE '"tool_name"[[:space:]]*:[[:space:]]*"Edit"' \
      && printf '%s' "$in" | grep -qE '"(input|patch)"[[:space:]]*:'; then
      if printf '%s' "$in" | grep -qE '"(path|command)"[[:space:]]*:' \
        || { printf '%s' "$in" | grep -qE '"input"[[:space:]]*:' && printf '%s' "$in" | grep -qE '"patch"[[:space:]]*:'; }; then
        why="a patch beside other arguments"
      else
        patch=object
      fi
    fi
    if [ -n "$why" ]; then
      _nonna_copilot_refuse unread "without jq, ${why} cannot be read"
      return 2
    fi
    # A patch is read by its grammar, as Codex's is: its text goes under the key the reader takes.
    if [ "$patch" = raw ]; then
      printf '%s' "$in" | sed -e 's/"tool_input"\([[:space:]]*:[[:space:]]*\)"/"tool_input"\1{"command":"/' | _nonna_copilot_files
      return
    elif [ "$patch" = object ]; then
      printf '%s' "$in" | sed -e 's/"input"\([[:space:]]*:\)/"command"\1/' -e 's/"patch"\([[:space:]]*:\)/"command"\1/' | _nonna_copilot_files
      return
    fi
    printf '%s' "$in" | sed -e 's/"path"\([[:space:]]*:\)/"file_path"\1/g' -e 's/"paths"\([[:space:]]*:\)/"path"\1/g'
    return 0
  fi
  out="$(printf '%s' "$in" | jq -c --argjson most 32 '
    def joined($keys): [$keys[] as $k | .[$k] | strings] | if length > 0 then join("\n") else null end;
    def refuse($why): [{nonna_copilot_refuse: "unread", why: $why}];
    def paths_ok: type == "string" or (type == "array" and length > 0 and all(.[]; type == "string"));
    def texts_ok: . as $t | all(("file_text", "content", "old_str", "new_str", "input", "patch");
      . as $k | ($t | has($k) | not) or ($t[$k] | type) == "string");
    def holds_json: explode | map(select(. > 32)) | .[0] == 123;
    def patches: if (.tool_input | type) == "string" then [.tool_input] else [.tool_input.input, .tool_input.patch] | map(strings) end;
    def translate:
      (if .tool_name == "write_bash" or .tool_name == "write_powershell" then
          .tool_name = "Bash" | .tool_input.command = .tool_input.input
        else . end)
      | (if .tool_name == "Edit" then [patches[] | {nonna_copilot_patch: 1, tool_input: {command: .}}] else [] end) as $patch
      | if ($patch | length) > 0 and ((.tool_input | type) == "string" or (.tool_input | has("path") | not)) then $patch
        else
          (if .tool_name == "Edit" and .tool_input.command == "view" then .tool_name = "Read" else . end)
          | .tool_name as $tool
          | (if ($tool == "Write" or $tool == "Edit") and (.tool_input.path | type) != "string" then
              refuse("it is a file tool that names no path and carries no patch")
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
            else [.] end) + $patch
        end;
    . as $in
    | if type != "object" then refuse("its payload is not a JSON object")
      elif (.tool_input | type) == "string" then
        if .tool_name == "Edit" and (.tool_input | holds_json | not) then translate
        else refuse("its arguments are a string where Copilot sends an object") end
      elif (.tool_input | type) != "object" then refuse("its arguments are not an object")
      elif (.tool_input | has("path")) and (.tool_input.path | type) != "string" then refuse("its path is not a string")
      elif (.tool_input | has("paths")) and (.tool_input.paths | paths_ok | not) then
        refuse("its paths are neither one path nor a flat, non-empty list of them")
      elif (.tool_input | texts_ok | not) then
        refuse("its file_text, content, old_str, new_str, input or patch is not a string")
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
    *'{"nonna_copilot_patch":1,'*)
      out="$(_nonna_copilot_patches "$out")" || return 2
      ;;
  esac
  if [ -n "$out" ]; then printf '%s' "$out"; else printf '%s' "$in"; fi
}

_nonna_copilot_patches() { # <payloads>: each patch among them as its files' payloads, the rest as they are
  local one
  while IFS= read -r one; do
    case "$one" in
      '{"nonna_copilot_patch":1,'*) printf '%s' "$one" | _nonna_copilot_files || return 2 ;;
      *) printf '%s\n' "$one" ;;
    esac
  done <<<"$1"
}

_nonna_copilot_files() { # a payload whose tool_input.command is a patch, on stdin: one payload per file
  local files rc=0
  files="$(_nonna_codex_files)" || rc=$?
  if [ "$rc" = 0 ] && [ -n "$files" ]; then
    printf '%s\n' "$files"
    return 0
  fi
  if [ "$rc" = 3 ]; then # a hook that outruns its timeout lets the call through (lib/patch.sh)
    _nonna_copilot_refuse too_long "the patch is over 256 KB, too long to read before the hook times out"
  elif [ "$rc" = 4 ]; then
    _nonna_copilot_refuse too_long "the patch touches over 200 files, too many to judge before the hook times out"
  else
    _nonna_copilot_refuse unread "the patch could not be read by its grammar, a file at a time"
  fi
  return 2
}

_nonna_copilot_shape() { # the text on stdin, read without jq: 0 when it can be read with certainty
  # 1 when it is not one JSON object whose strings and brackets all close; 3 when its tool_input holds
  # an object (Copilot's own arguments hold only strings, numbers, booleans and lists of them); 4 when
  # it holds more than one "path". The gates' reader takes the first "path" in the text, so a decoy
  # before the real one would be judged in its place. Split into characters once, as json.sh does
  # (one-true-awk copies a string on every substr()), and a key name read from them only when it
  # could be tool_input.
  LC_ALL=C awk '
    BEGIN { RS = sprintf("%c", 1) }
    { s = s (NR > 1 ? RS : "") $0 }
    END {
      n = split(s, ch, ""); top = 0; str = 0; esc = 0; done = 0; from = 0; last = ""; want = 0; inside = 0
      nested = 0
      for (i = 1; i <= n; i++) {
        c = ch[i]
        if (str) {
          if (esc) esc = 0
          else if (c == "\\") esc = 1
          else if (c == "\"") {
            str = 0; last = ""
            if (top == 1 && i - from == 10) for (j = from; j < i; j++) last = last ch[j]
          }
          continue
        }
        if (c == " " || c == "\t" || c == "\r" || c == "\n") continue
        if (done || (top == 0 && c != "{")) exit 1
        if (c == "\"") { str = 1; from = i + 1; continue }
        if (c == ":") { want = (top == 1 && last == "tool_input"); last = ""; continue }
        last = ""
        if (c == "{" || c == "[") {
          if (c == "{" && inside) nested = 1
          stack[++top] = c
          if (want && c == "{") inside = top
        } else if (c == "}" || c == "]") {
          if (stack[top] != (c == "}" ? "{" : "[")) exit 1
          if (top == inside) inside = 0
          if (--top == 0) done = 1
        }
        want = 0
      }
      if (!done) exit 1
      if (nested) exit 3
      exit (gsub(/"path"[ \t\r\n]*:/, "", s) > 1 ? 4 : 0)
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
