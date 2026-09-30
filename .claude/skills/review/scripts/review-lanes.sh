#!/usr/bin/env bash
# review-lanes.sh — how much review a diff buys, decided by script, not by the model.
#
# Prints two lines on stdout:
#   lane=light|full     light iff the fast-lane classifier (check-trivial.sh) qualifies the delta:
#                       one code reviewer on the cheaper tier. Anything else: the full review.
#   security=yes|no     no only when every changed path is ordinary AND no added or removed line
#                       matches a risky pattern. Risky paths: auth, secrets, money, migrations,
#                       deploy, CI, the harness itself, the Gemini CLI extension (its manifest) and a
#                       root hooks/hooks.json (the file Gemini CLI and a Claude plugin run hooks from),
#                       dependency manifests, lockfiles, submodules, NONNA_CRITICAL_PATHS. Risky
#                       lines: shell/exec, SQL, deserialization, network, env reads, crypto,
#                       authorization words. Lines in real test directories and ordinary markdown
#                       do not trigger it on their own.
#
# Fails closed: not a repo, no develop/main base, an unresolvable base, a missing classifier, an
# unreadable file, a non-regular untracked file, or a legacy KEEL_CRITICAL_PATHS with no
# NONNA_CRITICAL_PATHS all answer lane=full, security=yes. Always exits 0 so /review always has
# an answer to act on. A pattern list cannot see through deliberate obfuscation; the code reviewer
# still reads every diff (ADR-0009).
#
# Usage: review-lanes.sh [BASE_REF]   (default: develop, origin/develop, main, origin/main)
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
CT="$HERE/../../fast-lane/scripts/check-trivial.sh"

closed() {
  echo "review-lanes: $1 — full review with security (fail closed)." >&2
  printf 'lane=full\nsecurity=yes\n'
  exit 0
}

top="$(git rev-parse --show-toplevel 2>/dev/null)" || closed "not a git repository"
cd "$top" || closed "cannot enter the repository root"

if [ -n "${KEEL_CRITICAL_PATHS:-}" ] && [ -z "${NONNA_CRITICAL_PATHS:-}" ]; then
  closed "KEEL_CRITICAL_PATHS is set but the harness reads NONNA_CRITICAL_PATHS now (ADR-0010)"
fi

base="${1:-}"
if [ -z "$base" ]; then
  for c in develop origin/develop main origin/main; do
    if git rev-parse --verify -q "$c" >/dev/null 2>&1; then
      base="$c"
      break
    fi
  done
fi
[ -n "$base" ] || closed "no develop or main base to compare against"
git rev-parse --verify -q "$base" >/dev/null 2>&1 || closed "base '$base' is unresolvable"
mb="$(git merge-base "$base" HEAD 2>/dev/null)" || closed "no merge base with '$base'"

lane=full
if [ -f "$CT" ]; then
  bash "$CT" "$base" >/dev/null 2>&1 && lane=light
else
  echo "review-lanes: fast-lane classifier not found — full lane." >&2
fi

GITQ=(git -c core.quotePath=false)
DIFF=(diff --no-color --no-ext-diff --no-textconv --text --no-renames)

RISKY_PATH='(auth|login|logout|session|token|secret|credential|passw|crypt|payment|billing|invoice|checkout|wallet|ledger|webhook|admin|permission|policy|acl|oauth|sso|migration|deploy|dockerfile|/\.env|/\.github/|/\.claude/|/claude\.md$|/\.gitattributes$|/\.gitmodules$|/scripts/|gemini-extension\.json$|^/hooks/hooks\.json$)'
RISKY_LINE='(subprocess|os\.system|os\.popen|popen|shell *= *true|child_process|spawn|\beval *\(|\bexec *\(|exec\.command|os/exec|command::new|runtime\.getruntime|processbuilder|__import__|importlib|pickle|yaml\.load|marshal\.|unserialize|deserializ|innerhtml|dangerouslysetinnerhtml|\bsql|\.execute *\(|\.query *\(|\.raw *\(|cursor\.|\bselect\b.*\bfrom\b|\binsert +into\b|\bdelete +from\b|\bupdate +[a-z_."`]+ +set\b|passw|secret|token|api[_-]?key|credential|auth|jwt|oauth|csrf|cors|cookie|session|admin|permission|role|is_staff|is_superuser|login_required|owner|crypto|hashlib|hmac|verify *= *false|urllib|requests\.|httpx|aiohttp|net/http|http\.(get|post|newrequest)|reqwest|fetch *\(|axios|https?://|socket|os\.environ|getenv|process\.env|env::var|chmod|chown|sudo|rm -rf|rmtree|unlink)'

is_manifest() {
  case "$(basename "$1")" in
    package.json | package-lock.json | yarn.lock | pnpm-lock.yaml | bun.lockb | \
      pyproject.toml | poetry.lock | uv.lock | Pipfile | Pipfile.lock | requirements*.txt | setup.py | setup.cfg | \
      go.mod | go.sum | Cargo.toml | Cargo.lock | Gemfile | Gemfile.lock | \
      composer.json | composer.lock | .gitmodules) return 0 ;;
  esac
  return 1
}

is_quiet_path() { # lines here alone never trigger the security reviewer: real test dirs, plain docs
  case "/$1" in
    */tests/* | */test/* | */__tests__/* | */spec/* | */fixtures/*) return 0 ;;
  esac
  case "$(basename "$1")" in
    test_*.py | *_test.go | *.test.[jt]s | *.test.[jt]sx | *.spec.[jt]s | *.spec.[jt]sx | *.md) return 0 ;;
  esac
  return 1
}

path_is_risky() {
  local f="$1" g
  # The leading slash lets a pattern anchor at a directory name (/scripts/) or at the root (^/hooks/hooks.json).
  printf '/%s' "$f" | grep -qiE "$RISKY_PATH" && return 0
  is_manifest "$f" && return 0
  if [ -n "${NONNA_CRITICAL_PATHS:-}" ]; then
    local IFS=':'
    set -f
    for g in $NONNA_CRITICAL_PATHS; do
      # shellcheck disable=SC2254
      case "$f" in $g)
        set +f
        return 0
        ;;
      esac
    done
    set +f
  fi
  return 1
}

security=no
why=""
flag() {
  security=yes
  why="$1"
}

# A submodule pointer moving is new code nobody in this repo reviewed.
if "${GITQ[@]}" "${DIFF[@]}" --raw "$mb" 2>/dev/null | grep -qE '^:(160000|[0-7]{6} 160000) '; then
  flag "submodule pointer changed"
fi

check_file() { # <path> <tracked:1|0>
  local f="$1" tracked="$2" body
  if path_is_risky "$f"; then
    flag "path $f"
    return
  fi
  is_quiet_path "$f" && return
  if [ "$tracked" = 1 ]; then
    # Added AND removed lines: deleting a guard is as risky as adding a call.
    if ! body="$("${GITQ[@]}" "${DIFF[@]}" -U0 "$mb" --end-of-options -- "$f" 2>/dev/null)"; then
      flag "cannot read the diff of $f"
      return
    fi
    body="$(printf '%s\n' "$body" | grep -aE '^[+-]' | grep -avE '^(\+\+\+|---) ')"
  else
    if [ -L "$f" ] || [ ! -f "$f" ]; then
      flag "untracked non-regular file $f"
      return
    fi
    body="$(head -c 1048576 -- "$f" 2>/dev/null)" || {
      flag "cannot read $f"
      return
    }
  fi
  if printf '%s\n' "$body" | grep -aqiE "$RISKY_LINE"; then
    flag "risky code added or removed in $f"
  fi
}

while IFS= read -r -d '' f; do
  [ "$security" = yes ] && break
  check_file "$f" 1
done < <("${GITQ[@]}" diff --name-only --no-renames -z "$mb" 2>/dev/null)

while IFS= read -r -d '' f; do
  [ "$security" = yes ] && break
  check_file "$f" 0
done < <("${GITQ[@]}" ls-files --others --exclude-standard -z 2>/dev/null)

echo "review-lanes: lane=$lane vs $base; security=$security${why:+ ($why)}." >&2
printf 'lane=%s\nsecurity=%s\n' "$lane" "$security"
exit 0
