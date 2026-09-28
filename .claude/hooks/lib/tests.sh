#!/usr/bin/env bash
# lib/tests.sh — "done" means the project's own test suite passes, not that the agent says so.
#
# nonna_test_cmd   prints the test command for the repo in the current directory, or nothing.
#                  Precedence: NONNA_TEST_CMD (empty turns the gate off) > git config nonna.testCmd
#                  (empty turns it off) > detection, in a copy-in install only (the harness running
#                  is the repo's own .claude/). A plugin install detects once, at session start, when
#                  the plugin's run_tests option allows it (the default): session-start.sh records the
#                  command in the repo's own git config, which is never committed and never cloned,
#                  and says so. So the Stop hook and the git pre-push hook run one command, and the
#                  user can see and change it. The pre-push hook passes `git-hook`: it ignores
#                  NONNA_TEST_CMD, which the command that runs git could set.
# nonna_detect_test_cmd  prints the command detection finds here: pytest config/tests,
#                  package.json's "test" script, go.mod or Cargo.toml.
# nonna_run_tests  runs it with a timeout (NONNA_TEST_TIMEOUT seconds, default 600); exit status is
#                  the suite's, 124 when it timed out. $NONNA_TEST_TAIL gets what a person needs to
#                  see: up to five failing-test lines (pytest, jest, go, cargo, TAP) and the summary,
#                  else the last eight lines; colour codes stripped, and any line that looks like a
#                  secret replaced, because this text is shown to the agent and to the user.
# shellcheck shell=bash

# shellcheck source=/dev/null
command -v nonna_config >/dev/null 2>&1 || . "$(dirname "${BASH_SOURCE[0]}")/core.sh"

nonna_test_cmd() { # [git-hook]: a git hook takes nothing from the environment (lib/core.sh)
  if [ "${1:-}" != git-hook ] && [ "${NONNA_TEST_CMD+set}" = set ]; then
    printf '%s' "$NONNA_TEST_CMD"
    return 0
  fi
  local cfg
  if cfg="$(nonna_config nonna.testCmd)"; then
    printf '%s' "$cfg"
    return 0
  fi
  nonna_copy_in || return 0 # only a repo's own harness detects; a plugin runs what was recorded
  nonna_detect_test_cmd
}

nonna_detect_test_cmd() {
  local t has_py_tests=0
  for t in tests/test_*.py tests/*_test.py test/test_*.py test_*.py; do
    [ -f "$t" ] && has_py_tests=1 && break
  done
  if [ -f pytest.ini ] || [ -f tox.ini ] || [ -f conftest.py ] || [ "$has_py_tests" = 1 ]; then
    # Only when pytest is there: "No module named pytest" is not a red suite. Found, not imported,
    # and never from the repository's own directory: a pytest.py it ships must not run.
    python3 -c 'import sys; sys.path[:] = [p for p in sys.path if p not in ("", ".")]; import importlib.util; sys.exit(importlib.util.find_spec("pytest") is None)' >/dev/null 2>&1 \
      && printf 'python3 -m pytest -q'
  elif [ -f package.json ] && grep -qE '"test"[[:space:]]*:' package.json && ! grep -q 'no test specified' package.json; then
    printf 'npm test --silent'
  elif [ -f go.mod ]; then
    printf 'go test ./...'
  elif [ -f Cargo.toml ]; then
    printf 'cargo test --quiet'
  fi
}

nonna_run_tests() { # <command>
  local out rc secs="${NONNA_TEST_TIMEOUT:-600}" log
  # Output goes to a file, not $(...): a child that outlives a timeout must not hold the pipe open.
  log="$(mktemp)" || return 1
  if command -v timeout >/dev/null 2>&1; then # GNU timeout signals the whole process group
    timeout "$secs" bash -c "$1" >"$log" 2>&1
    rc=$?
  elif command -v perl >/dev/null 2>&1; then # macOS: own process group, killed whole on the alarm
    perl -e '
      my $secs = shift; my $pid = fork; die "fork: $!" unless defined $pid;
      if (!$pid) { setpgrp(0, 0); exec @ARGV or exit 127 }
      $SIG{ALRM} = sub { kill "TERM", -$pid; sleep 1; kill "KILL", -$pid; exit 124 };
      alarm $secs; waitpid($pid, 0);
      exit($? & 127 ? 128 + ($? & 127) : $? >> 8)' "$secs" bash -c "$1" >"$log" 2>&1
    rc=$?
  else
    bash -c "$1" >"$log" 2>&1
    rc=$?
  fi
  out="$(nonna_test_digest "$log")"
  rm -f "$log"
  # shellcheck disable=SC2034  # read by the hook that sourced this file
  NONNA_TEST_TAIL="$out"
  return "$rc"
}

# nonna_is_test_file <path>  0 when the path is a test: in a test directory, or named like one.
#   Deliberately not the secret scan's nonna_is_test_path, which also exempts fixtures and examples.
nonna_is_test_file() {
  case "/$1" in */test/* | */tests/* | */__tests__/* | */spec/* | */specs/* | */testing/*) return 0 ;; esac
  case "${1##*/}" in
    test_*.py | *_test.py | *_test.go | *.test.[jt]s | *.test.[jt]sx | *.test.[cm][jt]s | *.spec.[jt]s \
      | *.spec.[jt]sx | *.spec.[cm][jt]s | *Test.java | *Tests.java | *Test.kt | *Tests.kt | *_spec.rb \
      | *_test.rb | *Test.php | *Test.cs | *Tests.cs | *Tests.swift | *_test.exs | *_test.dart | *_test.c* \
      | *_test.rs) return 0 ;;
  esac
  return 1
}

# nonna_is_source_file <path>  0 when the path is program source (by extension): what a test covers.
nonna_is_source_file() {
  case "${1##*.}" in
    py | js | jsx | ts | tsx | mjs | cjs | go | rs | java | kt | kts | rb | php | cs | swift | c | h | cc \
      | cpp | hpp | m | mm | scala | ex | exs | erl | clj | dart | lua | vue | svelte) return 0 ;;
  esac
  return 1
}

# nonna_green_key <command>  the key a passing run is remembered by (git rev-parse --git-path
#                  nonna-green): the tree, tracked and untracked files read through a scratch index,
#                  and the command. Nothing when the tree cannot be read. It writes git objects, so a
#                  reader computes it only when there is a key to compare with.
nonna_green_key() {
  local idx tree
  idx="$(mktemp 2>/dev/null)" || return 0
  if cp "$(git rev-parse --git-path index)" "$idx" 2>/dev/null \
    && tree="$(GIT_INDEX_FILE="$idx" git add -A . >/dev/null 2>&1 && GIT_INDEX_FILE="$idx" git write-tree 2>/dev/null)"; then
    printf '%s\n%s' "$tree" "$1" | git hash-object --stdin 2>/dev/null
  fi
  rm -f "$idx"
}

# nonna_shown_cmd <command>  the command as a message may show it: never one that carries a secret.
nonna_shown_cmd() {
  # shellcheck source=/dev/null
  . "$(dirname "${BASH_SOURCE[0]}")/secret-patterns.sh" 2>/dev/null || { printf 'your test command'; return 0; }
  if printf '%s' "$1" | nonna_scan_secrets >/dev/null; then printf 'your test command'; else printf '%s' "$1"; fi
}

# nonna_test_digest <log>  prints the lines of a test run worth showing (see nonna_run_tests).
nonna_test_digest() {
  local esc clean fails last out line class
  esc="$(printf '\033')"
  clean="$(sed "s/${esc}\[[0-9;]*[A-Za-z]//g" "$1" 2>/dev/null)"
  fails="$(printf '%s\n' "$clean" | grep -E '^(FAILED|ERROR) |^--- FAIL: |^not ok |^test .* \.\.\. FAILED$|✕ ' | head -n 5)"
  last="$(printf '%s\n' "$clean" | grep -v '^[[:space:]]*$' | tail -n 1)"
  if [ -n "$fails" ]; then
    out="$fails"
    case "$fails" in *"$last"*) ;; *) out="$out
$last" ;; esac
  else
    out="$(printf '%s\n' "$clean" | tail -n 8)"
  fi
  # shellcheck source=/dev/null
  . "$(dirname "${BASH_SOURCE[0]}")/secret-patterns.sh" 2>/dev/null || { printf '%s\n' "$out"; return 0; }
  while IFS= read -r line; do
    if class="$(printf '%s' "$line" | nonna_scan_secrets)"; then
      printf '[a line that looks like a %s was hidden]\n' "$class"
    else
      printf '%s\n' "$line"
    fi
  done <<<"$out"
}
