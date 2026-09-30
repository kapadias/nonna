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
# nonna_detect_test_cmd  prints the command detection finds here: the first row of this list that
#                  matches, and only when its runner is there. A missing runner would read as a red suite
#                  and block every push, so a row whose runner is missing is skipped and the search goes
#                  on below it: a repository that package.json, go.mod or Cargo.toml gates is gated still.
#                  pytest's row is the old exception: its files claim the repository, and without pytest
#                  nothing is named. Detection looks for a runner and never starts one.
#                    pytest config or tests; pytest                   python3 -m pytest -q
#                    Gemfile, .rspec or spec/spec_helper.rb; bundle   bundle exec rspec
#                    Gemfile, Rakefile and test/; bundle              bundle exec rake test
#                    phpunit.xml, .xml.dist or phpunit.dist.xml; php
#                      vendor/bin/pest (executable)                   vendor/bin/pest
#                      vendor/bin/phpunit (executable)                vendor/bin/phpunit
#                    gradlew (executable); a JVM                      ./gradlew test
#                    mvnw (executable); a JVM                         ./mvnw test
#                    pom.xml; mvn                                     mvn test
#                    one .sln, .slnx or .*proj file; dotnet           dotnet test
#                    mix.exs; mix                                     mix test
#                    a "test" script in package.json                  npm test --silent
#                    go.mod                                           go test ./...
#                    Cargo.toml                                       cargo test --quiet
#                  The back ends come before package.json, which in a Rails, Laravel or Phoenix app
#                  usually serves the front end. A Gemfile alone is no Ruby suite, nor is a bare spec/
#                  (Jasmine has one). The scripts a repository ships bring no runtime, so gradlew and mvnw
#                  need a JVM, looked for as they look (JAVA_HOME/bin/java when JAVA_HOME is set, else
#                  java on PATH), and vendor/bin/pest and phpunit need php. dotnet test cannot choose
#                  among several solution or project files.
# nonna_run_tests  runs it with a timeout (NONNA_TEST_TIMEOUT seconds, default 600), in the directory
#                  given (a directory's own command, below), else here; exit status is
#                  the suite's, 124 when it timed out, 1 when the directory does not lead to one inside
#                  the repository. $NONNA_TEST_TAIL gets what a person needs to
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

nonna_have() { command -v "$1" >/dev/null 2>&1; } # <command>: found on PATH; looking runs nothing
nonna_have_java() { # a JVM as gradlew and mvnw find one: $JAVA_HOME/bin/java if JAVA_HOME is set, else java on PATH
  # debt: macOS's /usr/bin/java stub counts as a JVM with no JDK installed, ask java_home when a Mac reports a red ./gradlew test
  if [ -n "${JAVA_HOME:-}" ]; then [ -x "$JAVA_HOME/bin/java" ]; else nonna_have java; fi
}

nonna_detect_test_cmd() {
  local t f dotnet_files=0 has_phpunit_xml=0 has_py_tests=0
  for t in tests/test_*.py tests/*_test.py test/test_*.py test_*.py; do
    [ -f "$t" ] && has_py_tests=1 && break
  done
  for f in *.sln *.slnx *.*proj; do [ -f "$f" ] && dotnet_files=$((dotnet_files + 1)); done # MSBuild's own glob
  for f in phpunit.xml phpunit.xml.dist phpunit.dist.xml; do [ -f "$f" ] && has_phpunit_xml=1; done
  if [ -f pytest.ini ] || [ -f tox.ini ] || [ -f conftest.py ] || [ "$has_py_tests" = 1 ]; then
    # Only when pytest is there: "No module named pytest" is not a red suite. Found, not imported,
    # and never from the repository's own directory: a pytest.py it ships must not run.
    python3 -c 'import sys; sys.path[:] = [p for p in sys.path if p not in ("", ".")]; import importlib.util; sys.exit(importlib.util.find_spec("pytest") is None)' >/dev/null 2>&1 \
      && printf 'python3 -m pytest -q'
  # The back ends come before package.json, which in a Rails, Laravel or Phoenix app serves the front
  # end. A row whose runner is missing is skipped, not claimed: the search goes on below it, so a
  # repository that package.json, go.mod or Cargo.toml gates stays gated. A runner is looked for
  # (nonna_have, -x), never started. The wrappers a repository ships bring no runtime: a JVM or php too.
  elif [ -f Gemfile ] && { [ -f .rspec ] || [ -f spec/spec_helper.rb ]; } && nonna_have bundle; then # a bare spec/ is also Jasmine's
    printf 'bundle exec rspec'
  elif [ -f Gemfile ] && [ -f Rakefile ] && [ -d test ] && nonna_have bundle; then
    printf 'bundle exec rake test'
  elif [ "$has_phpunit_xml" = 1 ] && nonna_have php && [ -x vendor/bin/pest ]; then
    printf 'vendor/bin/pest' # a Pest project: phpunit runs none of its tests
  elif [ "$has_phpunit_xml" = 1 ] && nonna_have php && [ -x vendor/bin/phpunit ]; then
    printf 'vendor/bin/phpunit'
  elif [ -x gradlew ] && nonna_have_java; then
    printf './gradlew test'
  elif [ -x mvnw ] && nonna_have_java; then
    printf './mvnw test'
  elif [ -f pom.xml ] && nonna_have mvn; then
    printf 'mvn test'
  elif [ "$dotnet_files" = 1 ] && nonna_have dotnet; then
    # dotnet test exits with MSB1011, which reads as a red suite, where several solution or project files sit.
    # debt: a .sln and a .csproj of one name count as two and are skipped, name the solution when a repository reports it
    printf 'dotnet test'
  elif [ -f mix.exs ] && nonna_have mix; then
    printf 'mix test'
  elif [ -f package.json ] && grep -qE '"test"[[:space:]]*:' package.json && ! grep -q 'no test specified' package.json; then
    printf 'npm test --silent'
  elif [ -f go.mod ]; then
    printf 'go test ./...'
  elif [ -f Cargo.toml ]; then
    printf 'cargo test --quiet'
  fi
}

# A directory can have a test command of its own (ADR-0014), so a monorepo runs only the suites that
# changed. The hooks read the keys, give each changed file its owner, and run what the owners name.

# nonna_read_pkgs [git-hook]  sets NONNA_PKG_DIRS and NONNA_PKG_CMDS side by side: each directory's own
#                  command, git config nonna.<dir>.testCmd with <dir> named from the repository's top, in
#                  the order git config lists them. The repository's own config alone: a directory is one
#                  repository's. An empty command is none. While NONNA_TEST_CMD is set it is one command
#                  for everything, so there are none; a git hook ignores it (nonna_test_cmd).
nonna_read_pkgs() {
  local kv k
  NONNA_PKG_DIRS=() NONNA_PKG_CMDS=()
  if [ "${1:-}" != git-hook ] && [ "${NONNA_TEST_CMD+set}" = set ]; then return 0; fi
  while IFS= read -r -d '' kv; do # "<key>\n<value>": a name holds no newline, a value may
    case "$kv" in *$'\n'?*) ;; *) continue ;; esac
    k="${kv%%$'\n'*}"
    k="${k#nonna.}"
    NONNA_PKG_DIRS+=("${k%.testcmd}")
    NONNA_PKG_CMDS+=("${kv#*$'\n'}")
  done < <(git config --local --no-includes -z --get-regexp '^nonna\..+\.testcmd$' 2>/dev/null)
}

# nonna_test_owner <path>  sets NONNA_OWNER to the index in NONNA_PKG_DIRS of the directory that owns the
#                  path (named from the top): the longest that is the path or a directory above it, on a
#                  / boundary. Empty when none does: the path is the repository's. The order the keys were
#                  set in does not change the answer; of a key set twice, the later counts, as in git.
nonna_test_owner() {
  local i=0 len=-1
  NONNA_OWNER=""
  while [ "$i" -lt "${#NONNA_PKG_DIRS[@]}" ]; do
    case "$1/" in
      "${NONNA_PKG_DIRS[i]}"/*)
        if [ "${#NONNA_PKG_DIRS[i]}" -ge "$len" ]; then NONNA_OWNER="$i" len="${#NONNA_PKG_DIRS[i]}"; fi
        ;;
    esac
    i=$((i + 1))
  done
}

# nonna_test_runs <command> [<path>...]  after nonna_read_pkgs, sets NONNA_RUN_DIRS and NONNA_RUN_CMDS
#                  side by side: what the test gate runs for these changed paths. With no directory of its
#                  own, the command, for the whole tree. Otherwise each directory's command that owns a
#                  path, once, in the order git config lists them; then the command, when a path is in no
#                  directory. "" is the repository; an empty command runs nothing.
nonna_test_runs() {
  local cmd="$1" f i=0 root="" sel=()
  shift
  # shellcheck disable=SC2034  # read by the hook that sourced this file
  NONNA_RUN_DIRS=() NONNA_RUN_CMDS=()
  if [ "${#NONNA_PKG_DIRS[@]}" -eq 0 ]; then
    root=1
  else
    # debt: every path against every directory, stop once all are chosen if a push of thousands of files is slow
    for f in "$@"; do
      nonna_test_owner "$f"
      if [ -n "$NONNA_OWNER" ]; then sel[NONNA_OWNER]=1; else root=1; fi
    done
  fi
  while [ "$i" -lt "${#NONNA_PKG_DIRS[@]}" ]; do
    if [ -n "${sel[i]:-}" ]; then NONNA_RUN_DIRS+=("${NONNA_PKG_DIRS[i]}"); NONNA_RUN_CMDS+=("${NONNA_PKG_CMDS[i]}"); fi
    i=$((i + 1))
  done
  if [ -n "$root" ] && [ -n "$cmd" ]; then NONNA_RUN_DIRS+=(""); NONNA_RUN_CMDS+=("$cmd"); fi
}

nonna_run_tests() { # <command> [<directory, from the repository's top>]
  local out rc secs="${NONNA_TEST_TIMEOUT:-600}" log
  # Output goes to a file, not $(...): a child that outlives a timeout must not hold the pipe open.
  log="$(mktemp)" || return 1
  (
    # A directory that is gone, or leads out of the repository (a link), fails; it never passes.
    if [ -n "${2:-}" ] && ! { top="$(git rev-parse --show-toplevel 2>/dev/null)" && top="$(cd -P "$top" 2>/dev/null && pwd -P)" \
      && cd -P "$top/$2" 2>/dev/null && case "$(pwd -P)/" in "$top"/?*) ;; *) false ;; esac; }; then
      echo "$2 is not a directory inside this repository, so its command did not run."
      exit 1
    fi
    if command -v timeout >/dev/null 2>&1; then # GNU timeout signals the whole process group
      timeout "$secs" bash -c "$1"
    elif command -v perl >/dev/null 2>&1; then # macOS: own process group, killed whole on the alarm
      perl -e '
        my $secs = shift; my $pid = fork; die "fork: $!" unless defined $pid;
        if (!$pid) { setpgrp(0, 0); exec @ARGV or exit 127 }
        $SIG{ALRM} = sub { kill "TERM", -$pid; sleep 1; kill "KILL", -$pid; exit 124 };
        alarm $secs; waitpid($pid, 0);
        exit($? & 127 ? 128 + ($? & 127) : $? >> 8)' "$secs" bash -c "$1"
    else
      bash -c "$1"
    fi
  ) >"$log" 2>&1
  rc=$?
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
    py | js | jsx | ts | tsx | mjs | cjs | mts | cts | go | rs | java | kt | kts | rb | php | cs | swift | c \
      | h | cc | cpp | cxx | hpp | m | mm | scala | ex | exs | erl | clj | dart | lua | vue | svelte) return 0 ;;
  esac
  return 1
}

# nonna_green_key <command> [<directory>]  the key a passing run is remembered by (git rev-parse
#                  --git-path nonna-green): the tree, tracked and untracked files read through a scratch
#                  index, and the command. With a directory's own command (after nonna_read_pkgs), the
#                  whole tree but the directories beside it that have their own, read from wherever
#                  this runs: another package's change leaves its key as it was, a shared file does not,
#                  nor one in a package inside it, which its command runs over too.
#                  Nothing when the tree cannot be read. It writes git objects, so a
#                  reader computes it only when there is a key to compare with.
nonna_green_key() {
  local idx tree d spec=. others=()
  if [ -n "${2:-}" ]; then
    spec=":/"
    for d in ${NONNA_PKG_DIRS[@]+"${NONNA_PKG_DIRS[@]}"}; do
      case "$2/" in "$d"/*) continue ;; esac # itself, or one around it
      case "$d/" in "$2"/*) continue ;; esac # one inside it
      others+=(":(top,literal)$d")
    done
  fi
  idx="$(mktemp 2>/dev/null)" || return 0
  if cp "$(git rev-parse --git-path index)" "$idx" 2>/dev/null \
    && tree="$(GIT_INDEX_FILE="$idx" git add -A "$spec" >/dev/null 2>&1 \
      && { [ "${#others[@]}" -eq 0 ] || GIT_INDEX_FILE="$idx" git rm -r -q --cached --ignore-unmatch -- "${others[@]}" >/dev/null 2>&1; } \
      && GIT_INDEX_FILE="$idx" git write-tree 2>/dev/null)"; then
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
