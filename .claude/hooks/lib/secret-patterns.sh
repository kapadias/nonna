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

# _nonna_is_placeholder <matched-value>  -> 0 if the match is an obvious non-secret.
_nonna_is_placeholder() {
  printf '%s' "$1" | LC_ALL=C grep -qiE 'XXXX|EXAMPLE|YOUR[-_]|CHANGEME|DUMMY|REDACTED|PLACEHOLDER|FAKE|SAMPLE|\$\{|ENV\(|OS\.ENVIRON|PROCESS\.ENV|<[^>]+>'
}

# _nonna_real_key <match> <key-ERE>  -> 0 unless every key in the match is a placeholder. A key is
# wherever <key-ERE> (a key's prefix and its shortest tail, in lower case) starts in the match, and
# only that is read: a sample word in the text before a key, or glued after it, leaves a real key
# real, and a sample glued in front of one does not cover it. A match too long to walk, or with no
# key in it to read, counts as a key: the scan fails closed.
_nonna_real_key() {
  local m re="^($2)" i=0 seen=""
  [ "${#1}" -le 512 ] || return 0
  m="$(printf '%s' "$1" | LC_ALL=C tr '[:upper:]' '[:lower:]')"  # grep -i found it, so any case is read the same
  while [ "$i" -lt "${#m}" ]; do
    if [[ ${m:$i} =~ $re ]]; then
      seen=1
      _nonna_is_placeholder "${BASH_REMATCH[0]}" || return 0
    fi
    i=$((i + 1))
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
nonna_scan_secrets() {
  local raw
  raw="$(LC_ALL=C tr '\000' '\001' 2>/dev/null || true)"
  [ -n "$raw" ] || return 1
  case "$raw" in
    *$'\001'*)
      _nonna_scan_text "$(printf '%s' "$raw" | LC_ALL=C tr '\001' ' ')" \
        || _nonna_scan_text "$(printf '%s' "$raw" | LC_ALL=C tr -d '\001')"
      ;;
    *) _nonna_scan_text "$raw" ;;
  esac
}

# _nonna_scan_text <text>  -> the patterns, in order: the first class that matches, and 0.
_nonna_scan_text() {
  local text="$1"
  [ -n "$text" ] || return 1
  if _nonna_match 'AWS access key id' 'AKIA[0-9A-Z]{16}' "$text"; then return 0; fi
  if _nonna_match 'GitHub token' 'gh[pousr]_[A-Za-z0-9]{36,}' "$text" 'gh[pousr]_[a-z0-9]{36}'; then return 0; fi
  if _nonna_match 'Slack token' 'xox[baprs]-[0-9A-Za-z-]{10,}' "$text" 'xox[baprs]-[0-9a-z-]{10}'; then return 0; fi
  if _nonna_match 'Google API key' 'AIza[0-9A-Za-z_-]{35}' "$text"; then return 0; fi
  if _nonna_match 'Stripe secret key' 'sk_live_[0-9A-Za-z]{16,}' "$text" 'sk_live_[0-9a-z]{16}'; then return 0; fi
  if _nonna_match 'OpenAI API key' 'sk-[A-Za-z0-9]{20,}' "$text" 'sk-[a-z0-9]{20}'; then return 0; fi
  # Anthropic keys and OpenAI's prefixed ones (sk-ant-api03-, sk-proj-, ...) have a hyphenated tail the
  # line above cannot span. The tail is 40 or more (real ones are about 95 or more), so a kebab-case
  # name is not a key. An Anthropic key's shape (a word and two digits after sk-ant-) is specific
  # enough anywhere, even glued to a length byte in a compiled file. OpenAI's start at a token, so
  # that a word merely ending in "sk" (task-admin-...) is not a key; a token starts after anything
  # but a letter, digit or hyphen, after a JSON escape (\n, \f, \u0000: the raw payload the no-jq
  # scan reads writes a control character so), after a URL escape (%3D, %20), and after a shell or
  # compose default (${VAR:-key}, ${1-key}, ${a[0]-key}, ${?-key}).
  local tok='(^|[^A-Za-z0-9-]|:-|%[0-9A-Fa-f]{2}|\{([A-Za-z_][A-Za-z0-9_]*|[0-9]+|[@*#?$!-])(\[[^]]*\])?-|\\[bfnrt]|\\u[0-9A-Fa-f]{4})'
  if _nonna_match 'OpenAI API key' "${tok}sk-(proj|svcacct|admin)-[A-Za-z0-9_-]{40,}" "$text" 'sk-(proj|svcacct|admin)-[a-z0-9_-]{40}'; then return 0; fi
  if _nonna_match 'Anthropic API key' 'sk-ant-[a-z]+[0-9]{2}-[A-Za-z0-9_-]{40,}' "$text" 'sk-ant-[a-z]+[0-9]{2}-[a-z0-9_-]{40}'; then return 0; fi
  if _nonna_match 'private key block' '-----BEGIN [A-Z ]*PRIVATE KEY-----' "$text"; then return 0; fi
  if _nonna_match 'hardcoded secret assignment' '(api[_-]?key|secret|token|password|passwd)[[:space:]]*[:=][[:space:]]*"[^"]{16,}"' "$text"; then return 0; fi
  if _nonna_match 'hardcoded secret assignment' "(api[_-]?key|secret|token|password|passwd)[[:space:]]*[:=][[:space:]]*'[^']{16,}'" "$text"; then return 0; fi
  return 1
}
