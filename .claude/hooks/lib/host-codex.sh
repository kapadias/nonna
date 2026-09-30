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
#   Reads a Codex apply_patch payload on stdin and prints one Claude Code payload a line, one for each
#   file the patch touches, in its order. Fails when the patch is there and cannot be read, or names
#   no file: Codex's grammar puts one in every patch, so a patch in which none is read was not
#   understood.
#   A file header is read the way Codex's parser reads one, blanks around it trimmed; a line that
#   starts with + under a file is a line the patch adds. jq writes a \u0000 in the patch as a NUL byte,
#   which the shell would drop: it reaches the scan as \001 (lib/secret-patterns.sh reads it both ways),
#   written back as \u0001. Characters are escaped one at a time and joined pairwise, in n log n time in
#   any awk (as lib/json.sh decodes).
_nonna_codex_files() {
  local payload patch files
  payload="$(cat)"
  patch="$(printf '%s' "$payload" | nonna_json_field '.tool_input.command' \
    | LC_ALL=C tr '\000' '\001')" || return 1
  if [ -z "$patch" ]; then # nothing to write, unless the reader failed on a patch that is there
    printf '%s' "$payload" | grep -qE '"command"[[:space:]]*:[[:space:]]*"[^"]' && return 1
    return 0
  fi
  files="$(printf '%s\n' "$patch" | LC_ALL=C awk '
    function joined(   m, j) {
      while (np > 1) {
        m = 0
        for (j = 1; j <= np; j += 2) p[++m] = (j < np ? p[j] p[j + 1] : p[j])
        np = m
      }
      return (np ? p[1] : "")
    }
    function esc(s,   n, i, c) {
      n = split(s, ch, ""); np = 0
      for (i = 1; i <= n; i++) { c = ch[i]; p[++np] = (c in E) ? E[c] : c }
      return joined()
    }
    function file(kind, path) {
      nf++; kd[nf] = kind; pa[nf] = esc(path); mv[nf] = ""; lo[nf] = nl + 1; hi[nf] = nl
      return nf
    }
    function emit(tool, path, field, text) {
      printf "{\"tool_name\":\"%s\",\"tool_input\":{\"file_path\":\"%s\",\"%s\":\"%s\"}}\n", tool, path, field, text
    }
    BEGIN {
      for (i = 1; i < 32; i++) E[sprintf("%c", i)] = sprintf("\\u%04x", i)
      E["\\"] = "\\\\"; E["\""] = "\\\""
    }
    {
      t = $0; sub(/^[ \t\r]+/, "", t); sub(/[ \t\r]+$/, "", t)
      if (index(t, "*** Add File: ") == 1) { cur = file("Write", substr(t, 15)); next }
      if (index(t, "*** Update File: ") == 1) { cur = file("Edit", substr(t, 18)); next }
      if (index(t, "*** Delete File: ") == 1) { file("Edit", substr(t, 18)); cur = 0; next }
      if (index(t, "*** Move to: ") == 1) { if (cur) mv[cur] = esc(substr(t, 14)); next }
      if (cur && substr($0, 1, 1) == "+") { ln[++nl] = esc(substr($0, 2)); hi[cur] = nl }
    }
    END {
      for (i = 1; i <= nf; i++) {
        np = 0
        for (k = lo[i]; k <= hi[i]; k++) { if (np) p[++np] = "\\n"; p[++np] = ln[k] }
        text = joined()
        if (mv[i] != "") { emit("Edit", pa[i], "new_string", ""); emit("Edit", mv[i], "new_string", text) }
        else if (kd[i] == "Write") emit("Write", pa[i], "content", text)
        else emit("Edit", pa[i], "new_string", text)
      }
    }')" || return 1
  [ -n "$files" ] || return 1
  printf '%s\n' "$files"
}
