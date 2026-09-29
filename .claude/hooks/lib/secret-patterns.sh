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

# _nonna_match <class> <regex> <text>  -> print class & return 0 if a
# NON-placeholder match for <regex> exists in <text>. Bytes, not the locale's characters (LC_ALL=C): the
# patterns are ASCII, and macOS's grep gives up on input that is not text in the locale, which would
# read as "no secret".
_nonna_match() {
  local class="$1" re="$2" text="$3" m
  while IFS= read -r m; do
    [ -n "$m" ] || continue
    if _nonna_is_placeholder "$m"; then continue; fi
    printf '%s' "$class"
    return 0
  done < <(printf '%s' "$text" | LC_ALL=C grep -oiE -e "$re" 2>/dev/null || true)
  return 1
}

# nonna_scan_secrets  (reads candidate text on stdin)
#   On a high-confidence, non-placeholder match: prints the pattern CLASS (never
#   the secret) and returns 0. Otherwise returns 1.
nonna_scan_secrets() {
  local text
  # A NUL is a gap, not nothing: the shell would drop it and glue a key to what came before.
  text="$(LC_ALL=C tr '\000' ' ' 2>/dev/null || true)"
  [ -n "$text" ] || return 1

  if _nonna_match 'AWS access key id' 'AKIA[0-9A-Z]{16}' "$text"; then return 0; fi
  if _nonna_match 'GitHub token' 'gh[pousr]_[A-Za-z0-9]{36,}' "$text"; then return 0; fi
  if _nonna_match 'Slack token' 'xox[baprs]-[0-9A-Za-z-]{10,}' "$text"; then return 0; fi
  if _nonna_match 'Google API key' 'AIza[0-9A-Za-z_-]{35}' "$text"; then return 0; fi
  if _nonna_match 'Stripe secret key' 'sk_live_[0-9A-Za-z]{16,}' "$text"; then return 0; fi
  if _nonna_match 'OpenAI API key' 'sk-[A-Za-z0-9]{20,}' "$text"; then return 0; fi
  # Anthropic keys and OpenAI's prefixed ones (sk-ant-api03-, sk-proj-, ...) have a hyphenated tail the
  # line above cannot span. The tail is 40 or more (real ones are about 95 or more), so a kebab-case
  # name is not a key. An Anthropic key's shape (a word and two digits after sk-ant-) is specific
  # enough anywhere, even glued to a length byte in a compiled file. OpenAI's start at a token, so
  # that a word merely ending in "sk" (task-admin-...) is not a key; a token starts after anything
  # but a letter, digit or hyphen, after \n, \r or \t (a raw JSON payload, which the no-jq scan
  # reads, writes a newline so), after a URL escape (%3D, %20), and after a shell or compose default
  # (${VAR:-key}, ${1-key}, ${a[0]-key}), whose match then holds no ${ for the placeholder rule.
  local tok='(^|[^A-Za-z0-9-]|:-|%[0-9A-Fa-f]{2}|\{([A-Za-z_][A-Za-z0-9_]*|[0-9]+|[@*])(\[[^]]*\])?-|\\[nrt])'
  if _nonna_match 'OpenAI API key' "${tok}sk-(proj|svcacct|admin)-[A-Za-z0-9_-]{40,}" "$text"; then return 0; fi
  if _nonna_match 'Anthropic API key' 'sk-ant-[a-z]+[0-9]{2}-[A-Za-z0-9_-]{40,}' "$text"; then return 0; fi
  if _nonna_match 'private key block' '-----BEGIN [A-Z ]*PRIVATE KEY-----' "$text"; then return 0; fi
  if _nonna_match 'hardcoded secret assignment' '(api[_-]?key|secret|token|password|passwd)[[:space:]]*[:=][[:space:]]*"[^"]{16,}"' "$text"; then return 0; fi
  if _nonna_match 'hardcoded secret assignment' "(api[_-]?key|secret|token|password|passwd)[[:space:]]*[:=][[:space:]]*'[^']{16,}'" "$text"; then return 0; fi
  return 1
}
