# shellcheck shell=bash
# Sourced helper — Codex's hook payloads, read as Claude Code's (ADR-0012). Codex runs the plugin's
# hooks from hooks/codex-hooks.json with NONNA_HOST=codex, and a gate that reads a tool call passes
# Codex's payload through nonna_codex_payload before it reads it. Most of it already has Claude
# Code's shape: a shell command is tool_name Bash with tool_input.command, and session_id,
# stop_hook_active and cwd keep their names. An edit does not. Codex edits with apply_patch, one call
# whose patch (in tool_input.command) can add, update, move and delete several files, where the
# gates read one file a call, as Claude Code's Write and Edit send it.

# shellcheck source=/dev/null
. "$(dirname "${BASH_SOURCE[0]}")/json.sh"
# shellcheck source=/dev/null
. "$(dirname "${BASH_SOURCE[0]}")/patch.sh"

# nonna_codex_payload <gate>
#   Reads a hook payload on stdin. A Codex apply_patch is checked a file at a time: <gate>, the
#   script that called this, runs once for each file the patch touches, on that file as Claude Code's
#   file tools would send it: a Write of a file the patch adds, the lines it adds as the content; an
#   Edit of a file it updates or moves a file to, the lines it adds as the new text; an Edit with no
#   new text of a file it deletes or moves away. The first refusal stands: it returns non-zero, the
#   gate's reason already on stderr. A patch it cannot read is refused the same way, never guessed
#   at. A patch that passes returns 0. Either way it prints nothing. Any other payload is printed
#   unchanged.
nonna_codex_payload() {
  local gate="${1:-}" payload files f
  payload="$(cat 2>/dev/null || true)"
  # The name, read raw: a JSON string escapes its quotes, so no value inside one reads as this.
  if ! printf '%s' "$payload" | grep -qE '"tool_name"[[:space:]]*:[[:space:]]*"apply_patch"'; then
    printf '%s' "$payload"
    return 0
  fi
  if ! files="$(printf '%s' "$payload" | _nonna_codex_files)"; then
    echo "✗ Nonna: I can't taste what I can't read. (codex: the patch could not be read, so it is refused, not guessed at.)" >&2
    echo "  Check that it names each file it changes; if it does, check that awk and jq work in this shell." >&2
    return 2
  fi
  # Each file's check is the gate's own, NONNA_HOST cleared so it reads the payload as it is; what the
  # gate prints goes to stderr, never into the payload its caller goes on to read.
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    printf '%s' "$f" | NONNA_HOST='' "$BASH" "$gate" >&2 || return 2
  done <<<"$files"
  return 0
}

# _nonna_codex_files
#   Reads a Codex apply_patch payload on stdin and prints one Claude Code payload a line for each file
#   the patch touches, in its order: a Write of a file the patch adds, an Edit of one it updates, and
#   an Edit with nothing added of one it deletes or moves away (the file a move makes gets the lines).
#   lib/patch.sh reads the patch by its grammar; its status stands when it refuses one, and so does a
#   patch that is there and could not be decoded. jq writes a \u0000 in the patch as a NUL byte, which
#   the shell would drop: it reaches lib/patch.sh as \001, as the secret scan reads a NUL.
_nonna_codex_files() {
  local payload patch records
  payload="$(cat)"
  patch="$(printf '%s' "$payload" | nonna_json_field '.tool_input.command' \
    | LC_ALL=C tr '\000' '\001')" || return 1
  if [ -z "$patch" ]; then # nothing to write, unless the reader failed on a patch that is there
    printf '%s' "$payload" | grep -qE '"command"[[:space:]]*:[[:space:]]*"[^"]' && return 1
    return 0
  fi
  records="$(printf '%s\n' "$patch" | nonna_patch_files)" || return "$?"
  # A record's fields are already the inside of JSON strings, so they go into the payload as they are.
  printf '%s\n' "$records" | LC_ALL=C awk '
    function emit(tool, path, field, text) {
      printf "{\"tool_name\":\"%s\",\"tool_input\":{\"file_path\":\"%s\",\"%s\":\"%s\"}}\n", tool, path, field, text
    }
    BEGIN { FS = "\t" }
    $1 == "Add" { emit("Write", $2, "content", $4) }
    $1 == "Update" && $3 == "" { emit("Edit", $2, "new_string", $4) }
    $1 == "Update" && $3 != "" { emit("Edit", $2, "new_string", ""); emit("Edit", $3, "new_string", $4) }
    $1 == "Delete" { emit("Edit", $2, "new_string", "") }'
}
