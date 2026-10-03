# shellcheck shell=bash
# Sourced helper — extract one field from the JSON a Claude Code hook receives on
# stdin. Why a shared helper: every hook parses the same envelope, and a sed
# fallback keeps the gates working on minimal machines where jq is absent.

# How a hook reads a field, decided once, when it sources this file (_nonna_cr):
#   keep     bash keeps a CR as part of a word (Linux, macOS), so every CR stays: a guard that dropped
#            one would read " <CR>#" as a comment and "\<CR><LF>" as a continued line, and miss what
#            bash runs. Only the CRLF a native jq.exe adds is undone (_nonna_jq_raw, below).
#   drop     bash drops every CR from a command it runs, as Git Bash's does (MSYS2 patches its input
#            reader): there " <CR>#" starts a comment and gi<CR>t is git, so every field is read without
#            its CRs. Asked of this bash itself.
#   unknown  an MSYS bash that does not answer as either, or Cygwin's, whose igncr a command can switch
#            on partway through: a field that holds a CR reads as nothing, so a guard refuses what it
#            cannot read as bash will.
# The platform comes from BASH_VERSINFO, which is read-only, never from OSTYPE, which the environment
# can set.
_nonna_cr=keep
case "${BASH_VERSINFO[5]:-}" in
  *-msys*)
    _nonna_cr=unknown
    if command -v tr >/dev/null 2>&1; then
      case "$("${BASH:-bash}" -c "printf '<%s>' a"$'\r'"b" 2>/dev/null)" in
        '<ab>') _nonna_cr=drop ;;
        "<a"$'\r'"b>") _nonna_cr=keep ;;
      esac
    fi
    ;;
  *-cygwin*) _nonna_cr=unknown ;;
esac
# _nonna_jq_raw: a native jq.exe writes each newline as CRLF, one inside a value too, unless -b: so -b
# where jq takes it (a no-op off Windows), else, where it writes CRLF, one CR off each line's end, which
# is all it added.
_nonna_jq_raw=""
if command -v jq >/dev/null 2>&1; then
  if jq -b -n 1 >/dev/null 2>&1; then
    _nonna_jq_raw="-b"
  elif [ "$(jq -rn '"a"' 2>/dev/null)" = "a"$'\r' ] && command -v sed >/dev/null 2>&1; then
    _nonna_jq_raw="crlf"
  fi
fi

# nonna_json_field <jq_filter>
#   Reads JSON from stdin, prints the field. With jq, any filter works. Without
#   jq, only simple string-field lookups (e.g. .tool_input.file_path) degrade
#   gracefully; complex filters return empty (callers must fail safe on empty).
#   A field is read as bash will run it (_nonna_cr): where bash drops every CR (Git Bash), so does the
#   field; where it cannot be told, a field that holds a CR reads as nothing. _nonna_json_value reads a
#   field exactly, for what bash does not run: an apply_patch, which Codex parses itself.
nonna_json_field() {
  case "$_nonna_cr" in
    drop) _nonna_json_value "$@" | LC_ALL=C tr -d '\r' ;;
    unknown)
      local v
      v="$(_nonna_json_value "$@"; printf x)"
      v="${v%x}"
      case "$v" in *$'\r'*) return 0 ;; esac
      printf '%s' "$v"
      ;;
    *) _nonna_json_value "$@" ;;
  esac
}

# _nonna_json_value <jq_filter>: the field exactly as the JSON holds it.
_nonna_json_value() {
  local filter="$1" payload
  payload="$(cat 2>/dev/null || true)"
  [ -n "$payload" ] || return 0

  if command -v jq >/dev/null 2>&1; then
    # // empty so a missing/null field prints nothing, not the literal "null". Streamed, never held in a
    # variable, which would drop a NUL its caller translates.
    case "$_nonna_jq_raw" in
      -b) printf '%s' "$payload" | jq -b -r "$filter // empty" 2>/dev/null || true ;;
      crlf) printf '%s' "$payload" | jq -r "$filter // empty" 2>/dev/null | sed $'s/\r$//' || true ;;
      *) printf '%s' "$payload" | jq -r "$filter // empty" 2>/dev/null || true ;;
    esac
    return 0
  fi

  # Fallback: reduce ".a.b.c" to its last key and decode the first string value
  # under it, escapes and all: an escaped quote does not end it (a command such as
  # git commit -m "x" && git push --force would otherwise be cut short). A string
  # that never ends prints nothing. Deliberately best-effort otherwise — booleans,
  # numbers, arrays, and nested objects are out of scope; a gate that needs more
  # must require jq or fail safe.
  local key="${filter##*.}"
  case "$key" in
    ''|*[!A-Za-z0-9_]*) return 0 ;;  # not a plain key — refuse to guess
  esac
  # In n log n time in any awk (one-true-awk measures and copies a string on every substr() and
  # append): one record, split once into characters, and the pieces joined pairwise.
  printf '%s' "$payload" | LC_ALL=C awk -v key="$key" '
    function join(   m, j) {
      while (np > 1) {
        m = 0
        for (j = 1; j <= np; j += 2) p[++m] = (j < np ? p[j] p[j + 1] : p[j])
        np = m
      }
      return (np ? p[1] : "")
    }
    BEGIN { RS = sprintf("%c", 1) }
    { s = s (NR > 1 ? RS : "") $0 }
    END {
      if (!match(s, "\"" key "\"[ \t\r\n]*:[ \t\r\n]*\"")) exit
      i = RSTART + RLENGTH; n = split(s, ch, ""); s = ""; np = 0
      while (i <= n) {
        c = ch[i]
        if (c == "\"") { printf "%s", join(); exit }
        if (c != "\\") { p[++np] = c; i++; continue }
        e = ch[i + 1]; i += 2
        if (e == "n") p[++np] = "\n"
        else if (e == "t") p[++np] = "\t"
        else if (e == "r") p[++np] = "\r"
        else if (e == "b") p[++np] = "\b"
        else if (e == "f") p[++np] = "\f"
        else if (e == "u") {
          v = 0
          for (j = 0; j < 4; j++) {
            h = (ch[i + j] == "" ? 0 : index("0123456789abcdef", tolower(ch[i + j])))
            if (!h) break
            v = v * 16 + h - 1
          }
          i += j
          p[++np] = ((j == 4 && v > 0 && v < 128) ? sprintf("%c", v) : "?") # beyond ASCII: a placeholder
        }
        else p[++np] = e # \" \\ \/
      }
    }' 2>/dev/null
}
