# shellcheck shell=bash
# Sourced helper — extract one field from the JSON a Claude Code hook receives on
# stdin. Why a shared helper: every hook parses the same envelope, and a sed
# fallback keeps the gates working on minimal machines where jq is absent.

# nonna_json_field <jq_filter>
#   Reads JSON from stdin, prints the field. With jq, any filter works. Without
#   jq, only simple string-field lookups (e.g. .tool_input.file_path) degrade
#   gracefully; complex filters return empty (callers must fail safe on empty).
nonna_json_field() {
  local filter="$1" payload
  payload="$(cat 2>/dev/null || true)"
  [ -n "$payload" ] || return 0

  if command -v jq >/dev/null 2>&1; then
    # // empty so a missing/null field prints nothing, not the literal "null".
    printf '%s' "$payload" | jq -r "$filter // empty" 2>/dev/null || true
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
