# shellcheck shell=bash
# Single source of truth for high-confidence secret detection + the test-path
# policy, shared by secret-scan.sh (write-time) and require-status-sync.sh
# (push-time). Precision over recall — but NOT at the cost of trivial evasion:
#   • the placeholder/example exemption is applied to the MATCHED VALUE, never to
#     the whole line, so a trailing "# example" cannot smuggle a real key past;
#   • the test/fixture exemption is anchored to path SEGMENTS, so an ordinary
#     file like "latest_config.py" does not disarm the gate.

# nonna_is_test_path <path>  -> 0 if the path is a test/fixture/example location.
nonna_is_test_path() {
  case "$1" in
    */test/* | */tests/* | */fixture/* | */fixtures/* | */example/* | */examples/* | \
      */sample/* | */samples/* | */spec/* | */specs/* | */testdata/* | */__tests__/*) return 0 ;;
    test/* | tests/* | fixture/* | fixtures/* | example/* | examples/* | sample/* | \
      samples/* | spec/* | specs/* | testdata/*) return 0 ;;
    *_test.* | *.test.* | *_spec.* | *.spec.* | *.example | *.sample) return 0 ;;
    *) return 1 ;;
  esac
}

# nonna_a <class>  -> the class with its article, as a message says it: "an AWS access key id".
nonna_a() {
  case "$1" in [AEIOUaeiou]*) printf 'an %s' "$1" ;; *) printf 'a %s' "$1" ;; esac
}

# The words that make a value a sample, not a secret (the scan's text is in lower case).
_nonna_sample_words='xxxx|example|your[-_]|changeme|dummy|redacted|placeholder|fake|sample'

# _nonna_is_placeholder <matched-value>  -> 0 if the match is an obvious non-secret: a sample word, or
# a reference to a value kept elsewhere (${VAR}, env(...), os.environ, process.env, <name>). Read in
# the shell, with no process per match (the scan's text is in lower case): thousands of sample ids
# must not outlast the hook's timeout, since a hook that times out does not block. Bytes, as the
# patterns read them (LC_ALL=C): in a UTF-8 locale [^>] would not match a Latin-1 byte.
_nonna_is_placeholder() {
  local LC_ALL=C re="$_nonna_sample_words"'|\$\{|env\(|os\.environ|process\.env|<[^>]+>'
  # A regex retries <[^>]+> from every "<", so a long match (a quoted value) goes to grep, in one pass.
  if [ "${#1}" -gt 512 ]; then
    printf '%s' "$1" | LC_ALL=C grep -qiE -e "$re"
  else
    [[ $1 =~ $re ]]
  fi
}

# _nonna_real_key <match> <key-ERE>  -> 0 unless every key in the match is a placeholder. A key starts
# wherever its prefix (the key ERE up to its first bracket) does, overlapping starts too, and runs
# for the key ERE: a key's prefix and its shortest tail, in lower case, as the scan's text is. Only
# that is read, in the shell (no process per key): a sample word before a key, or glued after it,
# leaves a real key real, and a sample glued in front of one does not cover it. A match too long to
# walk, a key ERE with no literal prefix to walk from, or a match with no key in it to read, counts
# as a key: the scan fails closed.
_nonna_real_key() {
  local rest="$1" re="^($2)" lead="${2%%[[(]*}" at seen=""
  [ "${#1}" -le 512 ] && [ -n "$lead" ] || return 0
  while :; do
    case "$rest" in *"$lead"*) ;; *) break ;; esac
    at="$lead${rest#*"$lead"}"
    if [[ $at =~ $re ]]; then
      seen=1
      [[ ${BASH_REMATCH[0]} =~ $_nonna_sample_words ]] || return 0
    fi
    rest="${at:1}"
  done
  [ -z "$seen" ]
}

# _nonna_match <class> <regex> <text> [<key-ERE>]  -> print class & return 0 if a
# NON-placeholder match for <regex> exists in <text>. With <key-ERE>, the placeholder rule reads each
# key in a match and nothing else (_nonna_real_key); without it, the whole match. Bytes, not the
# locale's characters (LC_ALL=C): the patterns are ASCII, and macOS's grep gives up on input that is
# not text in the locale, which would read as "no secret".
_nonna_match() {
  local class="$1" re="$2" text="$3" key="${4:-}" m
  while IFS= read -r m; do
    [ -n "$m" ] || continue
    if [ -n "$key" ]; then
      _nonna_real_key "$m" "$key" || continue
    elif _nonna_is_placeholder "$m"; then
      continue
    fi
    printf '%s' "$class"
    return 0
  done < <(printf '%s' "$text" | LC_ALL=C grep -oiE -e "$re" 2>/dev/null || true)
  return 1
}

# nonna_scan_secrets  (reads candidate text on stdin)
#   On a high-confidence, non-placeholder match: prints the pattern CLASS (never
#   the secret) and returns 0. Otherwise returns 1.
#   A NUL is a gap to one reading and nothing to the other, and both are scanned: a key right after a
#   NUL is not glued to the text before it, and UTF-16 text (a NUL after every ASCII character) or a
#   key a NUL cuts in two is read whole. The shell cannot hold a NUL, so each becomes \001 first; a
#   caller that must keep text in a variable before the scan passes its NULs as \001 the same way.
#   The text is read in lower case, once: the patterns match any case (grep -i) all the same. The
#   reading with the NULs deleted holds only the lines that had one: the others read the same both
#   ways, and a rule that reads only it (a key glued to what came before) must not reach them.
nonna_scan_secrets() {
  local raw
  raw="$(LC_ALL=C tr '\000' '\001' 2>/dev/null | LC_ALL=C tr '[:upper:]' '[:lower:]' 2>/dev/null || true)"
  [ -n "$raw" ] || return 1
  case "$raw" in
    *$'\001'*)
      _nonna_scan_text "$(printf '%s' "$raw" | LC_ALL=C tr '\001' ' ')" \
        || _nonna_scan_text "$(_nonna_nul_lines "$raw" | LC_ALL=C tr -d '\001')" glued
      ;;
    *) _nonna_scan_text "$raw" ;;
  esac
}

# _nonna_nul_lines <text>  -> the lines that hold a \001 (a NUL, as the scan reads it); all of the
#   text should the selection fail, so that a tool gone missing reads more, never less.
_nonna_nul_lines() {
  local ctrl_a lines rc=0
  ctrl_a="$(printf '\001')"
  lines="$(printf '%s\n' "$1" | LC_ALL=C grep -a -e "$ctrl_a")" || rc=$?
  if [ "$rc" = 0 ]; then printf '%s' "$lines"; else printf '%s' "$1"; fi
}

# _nonna_scan_text <text> [glued]  -> the patterns, in order: the first class that matches, and 0.
#   "glued": the text is a reading with its NUL bytes deleted.
_nonna_scan_text() {
  local text="$1" glued="${2:-}" rc=0
  [ -n "$text" ] || return 1
  # One pass first for what some pattern below must contain: text with none of it (most binary files)
  # holds no key. Only grep's own "none" (1) skips the patterns; a failed grep reads them all.
  printf '%s' "$text" | LC_ALL=C grep -qiE -e 'akia|gh[pousr]_|xox[baprs]-|aiza|sk_live_|sk-|-----begin|api[_-]?key|secret|token|passw' || rc=$?
  [ "$rc" != 1 ] || return 1
  if _nonna_match 'AWS access key id' 'AKIA[0-9A-Z]{16}' "$text"; then return 0; fi
  if _nonna_match 'GitHub token' 'gh[pousr]_[A-Za-z0-9]{36,}' "$text" 'gh[pousr]_[a-z0-9]{36}'; then return 0; fi
  if _nonna_match 'Slack token' 'xox[baprs]-[0-9A-Za-z-]{10,}' "$text" 'xox[baprs]-[0-9a-z-]{10}'; then return 0; fi
  if _nonna_match 'Google API key' 'AIza[0-9A-Za-z_-]{35}' "$text"; then return 0; fi
  if _nonna_match 'Stripe secret key' 'sk_live_[0-9A-Za-z]{16,}' "$text" 'sk_live_[0-9a-z]{16}'; then return 0; fi
  if _nonna_match 'OpenAI API key' 'sk-[A-Za-z0-9]{20,}' "$text" 'sk-[a-z0-9]{20}'; then return 0; fi
  # Anthropic keys and OpenAI's prefixed ones (sk-ant-api03-, sk-proj-, ...) have a hyphenated tail the
  # line above cannot span. The tail is 40 or more (real ones are about 95 or more), so a kebab-case
  # name is not a key. An Anthropic key's shape (a word and two digits after sk-ant-) is specific
  # enough anywhere, even glued to a length byte in a compiled file. An OpenAI key shorter than a real
  # one starts at a token, so that a word merely ending in "sk" (task-admin-...) is not a key; a token
  # starts after anything but a letter, digit or hyphen, after a JSON or string escape (\n, \u0000,
  # \x01, \0, \e: the raw payload the no-jq scan reads writes a control character so, and so does a
  # byte literal), after a URL escape (%3D, %20), and after a shell or compose default (${VAR:-key},
  # ${1-key}, ${?-key}, ${!ref-key}, ${a[0]-key}). Any "]-" starts one, so no subscript is read: one
  # of any length or nesting (${a[${b[0]}]-key}) neither hides the key nor makes grep read past it.
  local tok='(^|[^A-Za-z0-9-]|:-|%[0-9A-Fa-f]{2}|\{!?([A-Za-z_][A-Za-z0-9_]*|[0-9]+|[@*#?$!-])-|\]-|\\[abefnrtv]|\\u[0-9A-Fa-f]{4}|\\x[0-9A-Fa-f]{1,2}|\\[0-7]{1,3})'
  if _nonna_match 'OpenAI API key' "${tok}sk-(proj|svcacct|admin)-[A-Za-z0-9_-]{40,}" "$text" 'sk-(proj|svcacct|admin)-[a-z0-9_-]{40}'; then return 0; fi
  # Where the NUL bytes are gone, one as long as a real key (a tail of 80 or more; real ones have
  # about 156) is a key wherever it starts: in UTF-16 text a kana's high byte ("0") is glued to the
  # key, and so is a string list's last name. Elsewhere a name can run that long (a URL slug after
  # "mask-admin-"), so only there.
  if [ -n "$glued" ] && _nonna_match 'OpenAI API key' 'sk-(proj|svcacct|admin)-[A-Za-z0-9_-]{80,}' "$text" 'sk-(proj|svcacct|admin)-[a-z0-9_-]{40}'; then return 0; fi
  if _nonna_match 'Anthropic API key' 'sk-ant-[a-z]+[0-9]{2}-[A-Za-z0-9_-]{40,}' "$text" 'sk-ant-[a-z]+[0-9]{2}-[a-z0-9_-]{40}'; then return 0; fi
  if _nonna_match 'private key block' '-----BEGIN [A-Z ]*PRIVATE KEY-----' "$text"; then return 0; fi
  if _nonna_match 'hardcoded secret assignment' '(api[_-]?key|secret|token|password|passwd)[[:space:]]*[:=][[:space:]]*"[^"]{16,}"' "$text"; then return 0; fi
  if _nonna_match 'hardcoded secret assignment' "(api[_-]?key|secret|token|password|passwd)[[:space:]]*[:=][[:space:]]*'[^']{16,}'" "$text"; then return 0; fi
  return 1
}
