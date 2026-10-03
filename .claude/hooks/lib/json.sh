# shellcheck shell=bash
# Sourced helper — extract one field from the JSON a Claude Code hook receives on
# stdin. Why a shared helper: every hook parses the same envelope, and a sed
# fallback keeps the gates working on minimal machines where jq is absent.

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
# _nonna_cr: how this platform's bash reads a CR in a command (nonna_json_command), asked of it the first
# time a command holds one; never taken from the environment.
_nonna_cr=""

# nonna_json_command <jq_filter>
#   A field bash will run, read as this platform's bash reads a CR in it (_nonna_cr_mode):
#   keep     bash keeps a CR as part of a word (Linux, macOS), so every CR stays: a guard that dropped
#            one would read " <CR>#" as a comment and "\<CR><LF>" as a continued line, and miss what
#            bash runs.
#   drop     bash drops every CR from a command, whatever its options, as Git Bash's does (MSYS2
#            patches its input reader): there " <CR>#" starts a comment and gi<CR>t is git, so the
#            command is read without its CRs.
#   unknown  anything else, such as Cygwin's bash, whose igncr a command can switch partway through:
#            a command that holds a CR reads as nothing, which the guard refuses as one it cannot read.
#   A command without a CR reads alike everywhere, so bash is asked only about one that holds a CR.
nonna_json_command() {
  local v
  v="$(nonna_json_field "$@"; printf x)"
  v="${v%x}"
  case "$v" in *$'\r'*) ;; *) printf '%s' "$v"; return 0 ;; esac
  [ -n "$_nonna_cr" ] || _nonna_cr="$(_nonna_cr_mode)"
  case "$_nonna_cr" in
    keep) printf '%s' "$v" ;;
    drop) printf '%s' "$v" | LC_ALL=C tr -d '\r' ;; # bash's own ${v//} takes seconds on a large command
  esac
}

# _nonna_cr_mode: keep, drop or unknown, from how this bash reads a CR inside a word (a<CR>b) and one that
# ends a line (a<CR>): as it starts, then with igncr off, then on. Switched with shopt, which, unlike set,
# does not end a POSIX-mode shell over an option it lacks. Lengths come back, never a CR, so nothing that
# reads the answer can change it.
_nonna_cr_mode() {
  local r=$'\r' n=$'\n' part
  part="s=a${r}b t=a${r}${n}printf '%s%s ' \"\${#s}\" \"\${#t}\"${n}"
  case "$("${BASH:-bash}" -c "${part}shopt -uo igncr 2>/dev/null || :${n}${part}shopt -so igncr 2>/dev/null || :${n}${part}" 2>/dev/null </dev/null)" in
    '21 21 21 ') printf drop ;;
    '32 32 32 ') printf keep ;;
    *) printf unknown ;;
  esac
}

# nonna_json_field <jq_filter>
#   Reads JSON from stdin, prints the field exactly as the JSON holds it. With jq, any filter works.
#   Without jq, only simple string-field lookups (e.g. .tool_input.file_path) degrade
#   gracefully; complex filters return empty (callers must fail safe on empty).
nonna_json_field() {
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
