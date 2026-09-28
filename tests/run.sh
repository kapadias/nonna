#!/usr/bin/env bash
# Nonna harness self-tests — the harness held to its own bar (rules/testing.md).
# Golden tests that exercise every deterministic GATE and assert it blocks vs.
# allows correctly: secret detection, the branch guard, the Definition-of-Done
# pre-push, the review verdict gate, and the dependency audit. This is
# boundaries.md applied to Nonna itself: if a gate is silently wrong, this fails.
#
# Run:  bash tests/run.sh      (exits non-zero if any gate misbehaves)
# Deliberately NOT `set -e`: gates are EXPECTED to return non-zero.
# SC2016: single-quoted printf payloads (JSON fixtures with backtick fences) are literal on purpose.
# shellcheck disable=SC1090,SC1091,SC2016
set -uo pipefail
# Non-interactive: the pre-push hook reads git's ref lines from stdin, so nothing may inherit an open one.
exec </dev/null

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOKS="$ROOT/.claude/hooks"
SKILLS="$ROOT/.claude/skills"
PASS=0
FAIL=0
# A fake AWS key id, split so this file never holds a key-shaped literal (the push gate scans it).
FAKE_AWS="AKIA""1234567890ABCDEF"
GIT=(git -c user.email=nonna@test -c user.name=nonna-test -c init.defaultBranch=main -c commit.gpgsign=false)

check() { # <desc> <expected_exit> <actual_exit>
  if [ "$2" = "$3" ]; then
    PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"
  else
    FAIL=$((FAIL + 1)); printf '  FAIL %s (want exit %s, got %s)\n' "$1" "$2" "$3"
  fi
}
contains() { # <desc> <needle> <haystack>
  case "$3" in
    *"$2"*) PASS=$((PASS + 1)); printf '  ok   %s\n' "$1" ;;
    *) FAIL=$((FAIL + 1)); printf '  FAIL %s (missing: %s)\n' "$1" "$2" ;;
  esac
}

echo "== secret-patterns lib =="
out="$( . "$HOOKS/lib/secret-patterns.sh"; printf 'aws = "%s"' "$FAKE_AWS" | nonna_scan_secrets )"; rc=$?
check "detects AWS access key id" 0 "$rc"
contains "names the matched class, not the value" "AWS access key id" "$out"
( . "$HOOKS/lib/secret-patterns.sh"; printf 'ghp_%s' 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' | nonna_scan_secrets ) >/dev/null; check "detects GitHub token" 0 "$?"
( . "$HOOKS/lib/secret-patterns.sh"; printf 'let total = price * quantity' | nonna_scan_secrets ) >/dev/null; check "clean code passes" 1 "$?"
( . "$HOOKS/lib/secret-patterns.sh"; printf 'api_key = "your-key-here-placeholder"' | nonna_scan_secrets ) >/dev/null; check "ignores obvious placeholder" 1 "$?"
( . "$HOOKS/lib/secret-patterns.sh"; printf 'token = os.environ["TOKEN"]' | nonna_scan_secrets ) >/dev/null; check "ignores env-var reference" 1 "$?"

echo "== secret-scan.sh (PreToolUse write gate) =="
SS="$HOOKS/secret-scan.sh"
printf '%s' '{"tool_name":"Write","tool_input":{"file_path":"config.py","content":"TOKEN = \"ghp_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\""}}' | "$SS"; check "blocks secret in Write content" 2 "$?"
printf '%s' '{"tool_name":"Write","tool_input":{"file_path":"config.py","content":"x = 1"}}' | "$SS"; check "allows clean Write" 0 "$?"
printf '%s' '{"tool_name":"Write","tool_input":{"file_path":"tests/fixtures/keys.py","content":"TOKEN = \"ghp_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\""}}' | "$SS"; check "allows secret under a test/fixture path" 0 "$?"
printf '%s' '{"tool_name":"Edit","tool_input":{"file_path":"app.js","old_string":"a","new_string":"const k = \"'"$FAKE_AWS"'\""}}' | "$SS"; check "blocks secret in Edit new_string" 2 "$?"
printf '%s' '{"tool_name":"Write","tool_input":{"file_path":"a.py"}}' | "$SS"; check "no content -> allow (fail safe)" 0 "$?"
printf '%s' '{"tool_name":"Bash","tool_input":{"command":"cat .env"}}' | "$SS"; check "blocks Bash read of .env" 2 "$?"
printf '%s' '{"tool_name":"Bash","tool_input":{"command":"head -5 secrets/creds.pem"}}' | "$SS"; check "blocks Bash read of a .pem" 2 "$?"
printf '%s' '{"tool_name":"Bash","tool_input":{"command":"cp ~/.ssh/id_rsa /tmp/x"}}' | "$SS"; check "blocks Bash copy of a private key" 2 "$?"
printf '%s' '{"tool_name":"Bash","tool_input":{"command":"cat README.md"}}' | "$SS"; check "allows Bash read of a normal file" 0 "$?"
printf '%s' '{"tool_name":"Bash","tool_input":{"command":"grep -r foo ."}}' | "$SS"; check "allows Bash grep with no secret target" 0 "$?"
printf '%s' '{"tool_name":"Bash","tool_input":{"command":"cat secrets/db.txt"}}' | "$SS"; check "blocks Bash read of a bare secrets/ path" 2 "$?"
printf '%s' '{"tool_name":"Bash","tool_input":{"command":"cat david_rsanchez.txt"}}' | "$SS"; check "does not false-block 'id_rsa' as a substring" 0 "$?"
printf '%s' '{"tool_name":"Bash","tool_input":{"command":"tail -f logs/app.env.log"}}' | "$SS"; check "does not false-block '.env' as an interior substring" 0 "$?"

echo "== guard-branch.sh (PreToolUse branch gate) =="
GB="$HOOKS/guard-branch.sh"
TMP="$(mktemp -d)"
"${GIT[@]}" -C "$TMP" init -q
"${GIT[@]}" -C "$TMP" commit -q --allow-empty -m init
"${GIT[@]}" -C "$TMP" branch -M main
printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git commit -m x"}}' | CLAUDE_PROJECT_DIR="$TMP" "$GB"; check "blocks commit on main" 2 "$?"
printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git push origin main"}}' | CLAUDE_PROJECT_DIR="$TMP" "$GB"; check "blocks push to main" 2 "$?"
printf '%s' '{"tool_name":"Write","tool_input":{"file_path":"a.txt"}}' | CLAUDE_PROJECT_DIR="$TMP" "$GB"; check "allows (warns) edit on main" 0 "$?"
"${GIT[@]}" -C "$TMP" checkout -q -b feature/x
printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git commit -m x"}}' | CLAUDE_PROJECT_DIR="$TMP" "$GB"; check "allows commit on feature branch" 0 "$?"
printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git push -u origin feature/x"}}' | CLAUDE_PROJECT_DIR="$TMP" "$GB"; check "allows push to feature branch" 0 "$?"
printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git push origin +main"}}' | CLAUDE_PROJECT_DIR="$TMP" "$GB"; check "blocks +refspec force push to main" 2 "$?"
printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git push origin +feature/x"}}' | CLAUDE_PROJECT_DIR="$TMP" "$GB"; check "blocks +refspec force push to any ref" 2 "$?"
printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git push origin \"+main\""}}' | CLAUDE_PROJECT_DIR="$TMP" "$GB"; check "blocks quoted +refspec force push" 2 "$?"
printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"support +x mode\" && git push -u origin feature/x"}}' | CLAUDE_PROJECT_DIR="$TMP" "$GB"; check "a + in an earlier compound command does not false-block the push" 0 "$?"
rm -rf "$TMP"

echo "== require-status-sync.sh (pre-push Definition of Done) =="
RS="$HOOKS/require-status-sync.sh"
TMP="$(mktemp -d)"; BARE="$(mktemp -d)"
"${GIT[@]}" init -q --bare "$BARE"
"${GIT[@]}" -C "$TMP" init -q
"${GIT[@]}" -C "$TMP" remote add origin "$BARE"
"${GIT[@]}" -C "$TMP" commit -q --allow-empty -m init
"${GIT[@]}" -C "$TMP" branch -M main
"${GIT[@]}" -C "$TMP" push -q origin main
"${GIT[@]}" -C "$TMP" checkout -q -b feature/y
"${GIT[@]}" -C "$TMP" push -q -u origin feature/y
mkdir -p "$TMP/src"; echo 'def f(): return 1' > "$TMP/src/app.py"
"${GIT[@]}" -C "$TMP" add -A; "${GIT[@]}" -C "$TMP" commit -q -m "code, no status"
( cd "$TMP" && "$RS" ); check "blocks code push without STATUS update" 1 "$?"
mkdir -p "$TMP/docs"; echo 'changed' > "$TMP/docs/STATUS.md"
"${GIT[@]}" -C "$TMP" add -A; "${GIT[@]}" -C "$TMP" commit -q -m "update STATUS"
( cd "$TMP" && "$RS" ); check "allows code push with STATUS update" 0 "$?"
out="$(cd "$TMP" && NONNA_TEST_CMD=false "$RS" 2>&1)"; check "pre-push: a red test suite blocks the push" 1 "$?"
contains "pre-push: names the failing command" "NONNA_TEST_CMD" "$out"
( cd "$TMP" && NONNA_TEST_CMD=true "$RS" ); check "pre-push: a green test suite lets it through" 0 "$?"
# The pushed range comes from git's pre-push stdin, so a branch's first push is gated too.
"${GIT[@]}" -C "$TMP" checkout -q -b feature/new
echo 'def g(): return 2' >> "$TMP/src/app.py"; echo 'again' >> "$TMP/docs/STATUS.md"
"${GIT[@]}" -C "$TMP" add -A; "${GIT[@]}" -C "$TMP" commit -q -m "new branch"
PS="$(mktemp)"  # outside the repo: an untracked file there is a dirty tree
ZERO=0000000000000000000000000000000000000000; NEWSHA="$("${GIT[@]}" -C "$TMP" rev-parse HEAD)"
printf 'refs/heads/feature/new %s refs/heads/feature/new %s\n' "$NEWSHA" "$ZERO" > "$PS"
( cd "$TMP" && NONNA_TEST_CMD='exit 1' "$RS" origin "$BARE" < "$PS" ) 2>/dev/null; check "pre-push: a branch's first push runs the test gate" 1 "$?"
( cd "$TMP" && NONNA_TEST_CMD='exit 1' "$RS" < /dev/null ) 2>/dev/null; check "pre-push: no stdin, no upstream: the range falls back to the base branch" 1 "$?"
( cd "$TMP" && NONNA_TEST_CMD=true "$RS" origin "$BARE" < "$PS" ); check "pre-push: a green first push goes through" 0 "$?"
# The suite must taste what is pushed, not an uncommitted fix sitting on top of it.
echo '# uncommitted' >> "$TMP/src/app.py"
out="$(cd "$TMP" && NONNA_TEST_CMD=true "$RS" origin "$BARE" < "$PS" 2>&1)"; check "pre-push: refuses to vouch for a push from a dirty tree" 1 "$?"
contains "pre-push: says to commit or stash first" "commit or stash" "$out"
"${GIT[@]}" -C "$TMP" checkout -q -- src/app.py
echo 'import helper' > "$TMP/src/forgot.py"
( cd "$TMP" && NONNA_TEST_CMD=true "$RS" origin "$BARE" < "$PS" ) 2>/dev/null; check "pre-push: an untracked file is a dirty tree too (the forgotten git add)" 1 "$?"
rm -f "$TMP/src/forgot.py"
# A tag and a delete are not code "done"; refusing them only teaches --no-verify, which drops the scan.
"${GIT[@]}" -C "$TMP" tag -a v1 -m v1; TAGSHA="$("${GIT[@]}" -C "$TMP" rev-parse v1)"
printf 'refs/tags/v1 %s refs/tags/v1 %s\n' "$TAGSHA" "$ZERO" > "$PS"
( cd "$TMP" && NONNA_TEST_CMD=true "$RS" origin "$BARE" < "$PS" ); check "pre-push: an annotated tag push is not refused as foreign" 0 "$?"
printf '(delete) %s refs/heads/old %s\n' "$ZERO" "$NEWSHA" > "$PS"
( cd "$TMP" && NONNA_TEST_CMD=false "$RS" origin "$BARE" < "$PS" ); check "pre-push: a delete-only push runs nothing and passes" 0 "$?"
printf 'refs/heads/feature/new %s refs/heads/feature/new %s\n' "$NEWSHA" "$ZERO" > "$PS"
out="$(cd "$TMP" && NONNA_TEST_TIMEOUT=1 NONNA_TEST_CMD='sleep 5' "$RS" origin "$BARE" < "$PS" 2>&1)"; check "pre-push: a suite that times out blocks the push" 1 "$?"
contains "pre-push: says the suite timed out" "timed out" "$out"
rm -f "$PS"
"${GIT[@]}" -C "$TMP" checkout -q feature/y
echo 'KEY = "'"$FAKE_AWS"'"' > "$TMP/src/leak.py"
echo 'more' >> "$TMP/docs/STATUS.md"
"${GIT[@]}" -C "$TMP" add -A; "${GIT[@]}" -C "$TMP" commit -q -m "leak with status"
( cd "$TMP" && "$RS" ); check "blocks push that introduces a secret" 1 "$?"
# The scan covers every commit the remote lacks, never "since a local branch": a key in a root commit
# made with --no-verify on main must not ride a feature branch's first push unscanned.
T2="$(mktemp -d)"; B2="$(mktemp -d)"; "${GIT[@]}" init -q --bare "$B2"; "${GIT[@]}" -C "$T2" init -q
"${GIT[@]}" -C "$T2" remote add origin "$B2"; mkdir -p "$T2/docs"; echo s > "$T2/docs/STATUS.md"
echo 'KEY = "'"$FAKE_AWS"'"' > "$T2/cfg.py"; "${GIT[@]}" -C "$T2" add -A; "${GIT[@]}" -C "$T2" commit -q -m root
"${GIT[@]}" -C "$T2" checkout -q -b feature/x; echo 'x = 1' > "$T2/x.py"; echo t >> "$T2/docs/STATUS.md"
"${GIT[@]}" -C "$T2" add -A; "${GIT[@]}" -C "$T2" commit -q -m feat
printf 'refs/heads/feature/x %s refs/heads/feature/x %s\n' "$("${GIT[@]}" -C "$T2" rev-parse HEAD)" "$ZERO" > "$PS"
( cd "$T2" && "$RS" origin "$B2" < "$PS" ) 2>/dev/null; check "pre-push: a key in a local-only base commit is caught on a first push" 1 "$?"
# A key added then removed inside one push still reached the remote's history.
"${GIT[@]}" -C "$T2" rm -q cfg.py; "${GIT[@]}" -C "$T2" commit -q -m "drop cfg"
printf 'refs/heads/feature/x %s refs/heads/feature/x %s\n' "$("${GIT[@]}" -C "$T2" rev-parse HEAD)" "$ZERO" > "$PS"
( cd "$T2" && "$RS" origin "$B2" < "$PS" ) 2>/dev/null; check "pre-push: a key added and removed within the push is still caught" 1 "$?"
rm -rf "$T2" "$B2"
# Git config and file names must not hide added lines from the push scan.
T2="$(mktemp -d)"; B2="$(mktemp -d)"; "${GIT[@]}" init -q --bare "$B2"; "${GIT[@]}" -C "$T2" init -q
"${GIT[@]}" -C "$T2" remote add origin "$B2"; mkdir -p "$T2/docs"; echo s > "$T2/docs/STATUS.md"
"${GIT[@]}" -C "$T2" add -A; "${GIT[@]}" -C "$T2" commit -q -m root; "${GIT[@]}" -C "$T2" push -q origin HEAD:refs/heads/main 2>/dev/null
echo 'KEY = "'"$FAKE_AWS"'"' > "$T2/café.py"; echo t >> "$T2/docs/STATUS.md"
"${GIT[@]}" -C "$T2" add -A; "${GIT[@]}" -C "$T2" commit -q -m cafe
( cd "$T2" && "$RS" ) 2>/dev/null; check "pre-push: a non-ASCII file name does not hide a secret" 1 "$?"
( cd "$T2" && GIT_CONFIG_COUNT=2 GIT_CONFIG_KEY_0=color.ui GIT_CONFIG_VALUE_0=always GIT_CONFIG_KEY_1=diff.external GIT_CONFIG_VALUE_1=true "$RS" ) 2>/dev/null
check "pre-push: color.ui=always and diff.external do not hide a secret" 1 "$?"
rm -rf "$T2" "$B2"
# A fresh repo with a pushed base, for the cases below: $1 = the dir, $2 = its bare remote.
push_fixture() {
  "${GIT[@]}" init -q --bare "$2"; "${GIT[@]}" -C "$1" init -q; "${GIT[@]}" -C "$1" remote add origin "$2"
  mkdir -p "$1/docs" "$1/src"; echo s > "$1/docs/STATUS.md"; echo 'a = 1' > "$1/src/a.py"; echo 'b = 1' > "$1/src/b.py"
  "${GIT[@]}" -C "$1" add -A; "${GIT[@]}" -C "$1" commit -q -m root; "${GIT[@]}" -C "$1" branch -M trunk
  "${GIT[@]}" -C "$1" push -q origin trunk 2>/dev/null
}
# A merge commit is a commit: lines its resolution adds are scanned, and it runs the gates.
T2="$(mktemp -d)"; B2="$(mktemp -d)"; push_fixture "$T2" "$B2"
"${GIT[@]}" -C "$T2" checkout -q -b other; echo 'b = 2' > "$T2/src/b.py"; "${GIT[@]}" -C "$T2" commit -qam other
"${GIT[@]}" -C "$T2" checkout -q -b feature/m trunk; echo 'a = 2' > "$T2/src/a.py"; echo t >> "$T2/docs/STATUS.md"
"${GIT[@]}" -C "$T2" commit -qam feat; "${GIT[@]}" -C "$T2" push -q origin feature/m other 2>/dev/null
OLDTIP="$("${GIT[@]}" -C "$T2" rev-parse HEAD)"
"${GIT[@]}" -C "$T2" merge -q --no-commit other >/dev/null 2>&1; echo 'KEY = "'"$FAKE_AWS"'"' >> "$T2/src/a.py"
echo m >> "$T2/docs/STATUS.md"; "${GIT[@]}" -C "$T2" add -A; "${GIT[@]}" -C "$T2" commit -q --no-verify -m "merge other"
printf 'refs/heads/feature/m %s refs/heads/feature/m %s\n' "$("${GIT[@]}" -C "$T2" rev-parse HEAD)" "$OLDTIP" > "$PS"
out="$(cd "$T2" && "$RS" origin "$B2" < "$PS" 2>&1)"; check "pre-push: a key added in a merge resolution is caught" 1 "$?"
contains "pre-push: ...by the secret scan, not only the STATUS check" "Push blocked" "$out"
# An octopus merge prints a line added over all three parents as '+++'; indented, it looks like a header.
"${GIT[@]}" -C "$T2" checkout -q -b third trunk; echo 'c = 3' > "$T2/src/c.py"; "${GIT[@]}" -C "$T2" add -A; "${GIT[@]}" -C "$T2" commit -qm third
"${GIT[@]}" -C "$T2" push -q origin third feature/m 2>/dev/null; "${GIT[@]}" -C "$T2" checkout -q feature/m; OLDTIP="$("${GIT[@]}" -C "$T2" rev-parse HEAD)"
"${GIT[@]}" -C "$T2" checkout -q -b octo trunk; "${GIT[@]}" -C "$T2" merge -q --no-ff --no-commit other third >/dev/null 2>&1
printf 'def f():\n    k = "%s"\n' "$FAKE_AWS" >> "$T2/src/a.py"; echo o >> "$T2/docs/STATUS.md"
"${GIT[@]}" -C "$T2" add -A; "${GIT[@]}" -C "$T2" commit -q --no-verify -m octopus
printf 'refs/heads/octo %s refs/heads/octo %s\n' "$("${GIT[@]}" -C "$T2" rev-parse HEAD)" "$ZERO" > "$PS"
out="$(cd "$T2" && "$RS" origin "$B2" < "$PS" 2>&1)"; check "pre-push: an indented key in an octopus merge is caught" 1 "$?"
contains "pre-push: ...and named" "src/a.py" "$out"
# A plain added line that starts with '++ ' is content, not a header.
"${GIT[@]}" -C "$T2" checkout -q -b plus trunk; printf '++ k = "%s"\n' "$FAKE_AWS" > "$T2/src/p.py"; echo p >> "$T2/docs/STATUS.md"
"${GIT[@]}" -C "$T2" add -A; "${GIT[@]}" -C "$T2" commit -q --no-verify -m plus
printf 'refs/heads/plus %s refs/heads/plus %s\n' "$("${GIT[@]}" -C "$T2" rev-parse HEAD)" "$ZERO" > "$PS"
( cd "$T2" && "$RS" origin "$B2" < "$PS" ) 2>/dev/null; check "pre-push: an added line starting '++ ' is scanned" 1 "$?"
# A key on a side branch that the merge then discards (-s ours) still went out; name the file.
"${GIT[@]}" -C "$T2" checkout -q -b side trunk; echo 'KEY = "'"$FAKE_AWS"'"' > "$T2/src/a.py"; "${GIT[@]}" -C "$T2" commit -q --no-verify -qam side
"${GIT[@]}" -C "$T2" checkout -q -b ours trunk; echo s >> "$T2/docs/STATUS.md"; "${GIT[@]}" -C "$T2" commit -qam s
"${GIT[@]}" -C "$T2" merge -q -s ours --no-edit side
printf 'refs/heads/ours %s refs/heads/ours %s\n' "$("${GIT[@]}" -C "$T2" rev-parse HEAD)" "$ZERO" > "$PS"
out="$(cd "$T2" && "$RS" origin "$B2" < "$PS" 2>&1)"; contains "pre-push: a key on a discarded side branch is named" "src/a.py introduces" "$out"
rm -rf "$T2" "$B2"
# User config must not hide a root commit's diff (log.showRoot=false).
T2="$(mktemp -d)"; B2="$(mktemp -d)"; "${GIT[@]}" init -q --bare "$B2"; "${GIT[@]}" -C "$T2" init -q; "${GIT[@]}" -C "$T2" remote add origin "$B2"
mkdir -p "$T2/src"; echo 'KEY = "'"$FAKE_AWS"'"' > "$T2/src/k.py"; "${GIT[@]}" -C "$T2" add -A; "${GIT[@]}" -C "$T2" commit -q --no-verify -m root
printf 'refs/heads/r %s refs/heads/r %s\n' "$("${GIT[@]}" -C "$T2" rev-parse HEAD)" "$ZERO" > "$PS"
( cd "$T2" && GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=log.showRoot GIT_CONFIG_VALUE_0=false "$RS" origin "$B2" < "$PS" ) 2>/dev/null
check "pre-push: log.showRoot=false does not hide a root commit" 1 "$?"
rm -rf "$T2" "$B2"
# Pushing to a URL: only the destination's own refs say what it already has, not other remotes'.
T2="$(mktemp -d)"; B2="$(mktemp -d)"; PUB="$(mktemp -d)"; push_fixture "$T2" "$B2"; "${GIT[@]}" init -q --bare "$PUB"
"${GIT[@]}" -C "$T2" checkout -q -b feature/k; echo 'KEY = "'"$FAKE_AWS"'"' > "$T2/src/k.py"; echo t >> "$T2/docs/STATUS.md"
"${GIT[@]}" -C "$T2" add -A; "${GIT[@]}" -C "$T2" commit -q --no-verify -m k; "${GIT[@]}" -C "$T2" push -q --no-verify origin feature/k 2>/dev/null
printf 'refs/heads/feature/k %s refs/heads/feature/k %s\n' "$("${GIT[@]}" -C "$T2" rev-parse HEAD)" "$ZERO" > "$PS"
( cd "$T2" && "$RS" "$PUB" "$PUB" < "$PS" ) 2>/dev/null; check "pre-push: a push to a URL is scanned against that URL, not origin" 1 "$?"
rm -rf "$T2" "$B2" "$PUB"
# A git log that cannot read what is pushed is a stop, never a clean bill.
T2="$(mktemp -d)"; B2="$(mktemp -d)"; push_fixture "$T2" "$B2"
"${GIT[@]}" -C "$T2" checkout -q -b feature/c; echo 'c = 1' > "$T2/src/c.py"; "${GIT[@]}" -C "$T2" add -A; "${GIT[@]}" -C "$T2" commit -q -m c0
echo 'KEY = "'"$FAKE_AWS"'"' > "$T2/src/c.py"; echo t >> "$T2/docs/STATUS.md"; "${GIT[@]}" -C "$T2" commit -q --no-verify -qam c1
blob="$("${GIT[@]}" -C "$T2" rev-parse HEAD~1:src/c.py)"; rm -f "$T2/.git/objects/${blob:0:2}/${blob:2}"
printf 'refs/heads/feature/c %s refs/heads/feature/c %s\n' "$("${GIT[@]}" -C "$T2" rev-parse HEAD)" "$ZERO" > "$PS"
( cd "$T2" && "$RS" origin "$B2" < "$PS" ) 2>/dev/null; check "pre-push: an unreadable object fails closed" 1 "$?"
rm -rf "$T2" "$B2"
# A newline in a file name must not split it: a decoy cannot pose as docs/STATUS.md.
T2="$(mktemp -d)"; B2="$(mktemp -d)"; push_fixture "$T2" "$B2"
"${GIT[@]}" -C "$T2" checkout -q -b feature/n; echo 'd = 1' > "$T2/src/d.py"; mkdir -p "$T2/z"$'\n'"docs"; echo x > "$T2/z"$'\n'"docs/STATUS.md"
"${GIT[@]}" -C "$T2" add -A; "${GIT[@]}" -C "$T2" commit -q --no-verify -m decoy
printf 'refs/heads/feature/n %s refs/heads/feature/n %s\n' "$("${GIT[@]}" -C "$T2" rev-parse HEAD)" "$ZERO" > "$PS"
( cd "$T2" && "$RS" origin "$B2" < "$PS" ) 2>/dev/null; check "pre-push: a newline-named decoy does not count as a STATUS update" 1 "$?"
rm -rf "$T2" "$B2"
# A shallow clone's grafted root is history the remote has, not a whole tree this push adds.
T2="$(mktemp -d)"; B2="$(mktemp -d)"; SRC="$(mktemp -d)"; push_fixture "$SRC" "$B2"
"${GIT[@]}" -C "$SRC" commit -q --allow-empty -m second; "${GIT[@]}" -C "$SRC" push -q origin trunk 2>/dev/null
"${GIT[@]}" -C "$T2" init -q; "${GIT[@]}" -C "$T2" fetch -q --depth 1 "file://$B2" trunk; "${GIT[@]}" -C "$T2" checkout -q -b feature/s FETCH_HEAD
"${GIT[@]}" -C "$T2" remote add origin "$B2"; echo 'n = 1' > "$T2/src/new.py"; "${GIT[@]}" -C "$T2" add -A; "${GIT[@]}" -C "$T2" commit -q -m new
printf 'refs/heads/feature/s %s refs/heads/feature/s %s\n' "$("${GIT[@]}" -C "$T2" rev-parse HEAD)" "$ZERO" > "$PS"
( cd "$T2" && "$RS" origin "$B2" < "$PS" ) 2>/dev/null; check "pre-push: a shallow clone's graft does not pass the STATUS check" 1 "$?"
# A graft the destination is not known to have (a shallow fetch of a fork's tip) cannot be skipped.
FORK="$(mktemp -d)"; T3="$(mktemp -d)"; "${GIT[@]}" clone -q -b trunk "$B2" "$FORK/w" 2>/dev/null
"${GIT[@]}" -C "$FORK/w" checkout -q -b fk; echo 'KEY = "'"$FAKE_AWS"'"' > "$FORK/w/src/k.py"; echo f >> "$FORK/w/docs/STATUS.md"
"${GIT[@]}" -C "$FORK/w" add -A; "${GIT[@]}" -C "$FORK/w" commit -q --no-verify -m fork
"${GIT[@]}" -C "$T3" init -q; "${GIT[@]}" -C "$T3" remote add origin "$B2"; "${GIT[@]}" -C "$T3" fetch -q origin 2>/dev/null
"${GIT[@]}" -C "$T3" fetch -q --depth 1 "file://$FORK/w" fk; "${GIT[@]}" -C "$T3" checkout -q -b fk FETCH_HEAD
printf 'refs/heads/fk %s refs/heads/fk %s\n' "$("${GIT[@]}" -C "$T3" rev-parse HEAD)" "$ZERO" > "$PS"
out="$(cd "$T3" && "$RS" origin "$B2" < "$PS" 2>&1)"; check "pre-push: a shallow fork tip the remote lacks is not skipped" 1 "$?"
contains "pre-push: ...and says why" "shallow" "$out"
rm -rf "$FORK" "$T3"
# A remote named origin/fork is not origin: its refs must not count as what origin already has.
FORK="$(mktemp -d)"; T3="$(mktemp -d)"; "${GIT[@]}" clone -q -b trunk "$B2" "$FORK/w" 2>/dev/null
"${GIT[@]}" -C "$FORK/w" checkout -q -b fk; echo 'KEY = "'"$FAKE_AWS"'"' > "$FORK/w/src/k.py"; echo f >> "$FORK/w/docs/STATUS.md"
"${GIT[@]}" -C "$FORK/w" add -A; "${GIT[@]}" -C "$FORK/w" commit -q --no-verify -m fork
"${GIT[@]}" -C "$T3" init -q; "${GIT[@]}" -C "$T3" remote add origin "$B2"; "${GIT[@]}" -C "$T3" remote add origin/fork "$FORK/w"
"${GIT[@]}" -C "$T3" fetch -q origin 2>/dev/null; "${GIT[@]}" -C "$T3" fetch -q origin/fork 2>/dev/null
"${GIT[@]}" -C "$T3" checkout -q --no-track -b fk origin/fork/fk
printf 'refs/heads/fk %s refs/heads/fk %s\n' "$("${GIT[@]}" -C "$T3" rev-parse HEAD)" "$ZERO" > "$PS"
( cd "$T3" && "$RS" origin "$B2" < "$PS" ) 2>/dev/null; check "pre-push: a remote named origin/fork does not vouch for origin" 1 "$?"
# A tag on a blob or a tree carries content too: it is never pushed unscanned.
BLOB="$(printf 'k = "%s"\n' "$FAKE_AWS" | "${GIT[@]}" -C "$T3" hash-object -w --stdin)"
printf 'refs/tags/leak %s refs/tags/leak %s\n' "$BLOB" "$ZERO" > "$PS"
( cd "$T3" && "$RS" origin "$B2" < "$PS" ) 2>/dev/null; check "pre-push: a tag on a blob is not pushed unscanned" 1 "$?"
rm -rf "$FORK" "$T3"
rm -rf "$T2" "$B2" "$SRC"
# A first push of a long history is scanned in one pass, not one history walk per file.
T2="$(mktemp -d)"; B2="$(mktemp -d)"; "${GIT[@]}" init -q --bare "$B2"; "${GIT[@]}" -C "$T2" init -q; "${GIT[@]}" -C "$T2" remote add origin "$B2"
{ for i in $(seq 1 1000); do
    printf 'commit refs/heads/big\ncommitter t <t@t> %s +0000\ndata 1\nc\nM 644 inline src/f%s.py\ndata 6\nx = 1\n\n' "$((1700000000 + i))" "$i"
  done
  printf 'commit refs/heads/big\ncommitter t <t@t> 1800000000 +0000\ndata 1\nc\nM 644 inline docs/STATUS.md\ndata 2\ns\n\n'
} | "${GIT[@]}" -C "$T2" fast-import --quiet
"${GIT[@]}" -C "$T2" checkout -q big
printf 'refs/heads/big %s refs/heads/big %s\n' "$("${GIT[@]}" -C "$T2" rev-parse HEAD)" "$ZERO" > "$PS"
start=$SECONDS; ( cd "$T2" && timeout 60 "$RS" origin "$B2" < "$PS" ) 2>/dev/null; rc=$?
check "pre-push: a 1000-commit, 1000-file first push passes" 0 "$rc"
check "pre-push: ...in one scan, well under 10s" 1 "$(( SECONDS - start < 10 ))"
rm -rf "$T2" "$B2" "$PS"
# Installed AS a symlink (the way session-start wires it): must still resolve lib/.
mkdir -p "$TMP/.claude/hooks/lib"
cp "$HOOKS/require-status-sync.sh" "$TMP/.claude/hooks/"
cp "$HOOKS/lib/secret-patterns.sh" "$HOOKS/lib/tests.sh" "$TMP/.claude/hooks/lib/"
ln -sf ../../.claude/hooks/require-status-sync.sh "$TMP/.git/hooks/pre-push"
sl_out="$(cd "$TMP" && .git/hooks/pre-push 2>&1)"; sl_rc=$?
check "blocks a secret when run via the installed symlink" 1 "$sl_rc"
contains "symlinked hook resolved its lib (no 'command not found')" "looks like" "$sl_out"
rm -rf "$TMP" "$BARE"

echo "== require-status-sync.sh (push-time fixture strictness) =="
# Write-time stays ergonomic (fixture paths exempt); PUSH-time is strict — a
# realistic-looking secret must use a placeholder-classed value even in fixtures.
TMP="$(mktemp -d)"; BARE="$(mktemp -d)"
"${GIT[@]}" init -q --bare "$BARE"
"${GIT[@]}" -C "$TMP" init -q
"${GIT[@]}" -C "$TMP" remote add origin "$BARE"
"${GIT[@]}" -C "$TMP" commit -q --allow-empty -m init
"${GIT[@]}" -C "$TMP" branch -M main
"${GIT[@]}" -C "$TMP" push -q origin main
"${GIT[@]}" -C "$TMP" checkout -q -b feature/z
"${GIT[@]}" -C "$TMP" push -q -u origin feature/z
mkdir -p "$TMP/tests/fixtures" "$TMP/docs"
echo ok > "$TMP/docs/STATUS.md"
printf 'KEY = "%s"\n' "AKIA""AB12CD34EF56GH78" > "$TMP/tests/fixtures/sample.py"
"${GIT[@]}" -C "$TMP" add -A; "${GIT[@]}" -C "$TMP" commit -q -m "realistic secret in a fixture"
( cd "$TMP" && "$RS" ); check "blocks a realistic secret even under a fixture path" 1 "$?"
"${GIT[@]}" -C "$TMP" reset -q --hard HEAD~1  # the push scans every commit: the realistic key must leave history
mkdir -p "$TMP/tests/fixtures" "$TMP/docs"; echo ok > "$TMP/docs/STATUS.md"
printf 'KEY = "%s"\n' "AKIAIOSFODNN7EXAMPLE" > "$TMP/tests/fixtures/sample.py"
"${GIT[@]}" -C "$TMP" add -A; "${GIT[@]}" -C "$TMP" commit -q -m "placeholder fixture value"
( cd "$TMP" && "$RS" ); check "allows a placeholder-classed fixture value" 0 "$?"
rm -rf "$TMP" "$BARE"

echo "== pre-commit.sh (git pre-commit: the gates every agent host gets) =="
# Hooks in .claude/ bind Claude Code only; git hooks bind any agent that commits. Tested through
# real `git commit` calls with the hook installed the way install.sh installs it.
PC="$HOOKS/pre-commit.sh"
TMP="$(mktemp -d)"
"${GIT[@]}" -C "$TMP" init -q; mkdir -p "$TMP/.claude/hooks/lib" "$TMP/src"
cp "$PC" "$TMP/.claude/hooks/"; cp "$HOOKS/lib/secret-patterns.sh" "$TMP/.claude/hooks/lib/"
ln -sf ../../.claude/hooks/pre-commit.sh "$TMP/.git/hooks/pre-commit"
echo a > "$TMP/src/a.py"; "${GIT[@]}" -C "$TMP" add -A
"${GIT[@]}" -C "$TMP" commit -q --no-verify -m base; "${GIT[@]}" -C "$TMP" branch -M main
echo b >> "$TMP/src/a.py"; "${GIT[@]}" -C "$TMP" add -A
out="$("${GIT[@]}" -C "$TMP" commit -q -m on-main 2>&1)"; check "pre-commit: blocks a commit on main" 1 "$?"
contains "pre-commit: says why, in Nonna's voice" "not in my kitchen" "$out"
"${GIT[@]}" -C "$TMP" checkout -q -b develop
"${GIT[@]}" -C "$TMP" commit -q -m on-develop 2>/dev/null; check "pre-commit: blocks a commit on develop" 1 "$?"
"${GIT[@]}" -C "$TMP" checkout -q -b fix/1-thing
"${GIT[@]}" -C "$TMP" commit -q -m ok 2>/dev/null; check "pre-commit: allows a clean commit on a feature branch" 0 "$?"
printf 'STRIPE=sk_live_%s\n' '0123456789abcdefABCD' > "$TMP/src/pay.py"; "${GIT[@]}" -C "$TMP" add -A
out="$("${GIT[@]}" -C "$TMP" commit -q -m key 2>&1)"; check "pre-commit: blocks a staged secret" 1 "$?"
contains "pre-commit: names the file and the class" "src/pay.py" "$out"
"${GIT[@]}" -C "$TMP" reset -q; rm -f "$TMP/src/pay.py"
mkdir -p "$TMP/tests"; printf 'K = "%s"\n' "$FAKE_AWS" > "$TMP/tests/test_k.py"; "${GIT[@]}" -C "$TMP" add -A
"${GIT[@]}" -C "$TMP" commit -q -m fixture 2>/dev/null; check "pre-commit: a key-shaped test fixture is blocked too (push parity)" 1 "$?"
"${GIT[@]}" -C "$TMP" reset -q; rm -rf "$TMP/tests"
echo 'X=1' > "$TMP/.env"; "${GIT[@]}" -C "$TMP" add -f .env
out="$("${GIT[@]}" -C "$TMP" commit -q -m env 2>&1)"; check "pre-commit: blocks staging a .env file" 1 "$?"
contains "pre-commit: names the secret file" ".env" "$out"
"${GIT[@]}" -C "$TMP" reset -q; rm -f "$TMP/.env"
echo 'x' > "$TMP/.env.example"; "${GIT[@]}" -C "$TMP" add -A
"${GIT[@]}" -C "$TMP" commit -q -m example 2>/dev/null; check "pre-commit: a .env.example template is allowed" 0 "$?"
printf 'a\n' > "$TMP/src/deleted.pem"; "${GIT[@]}" -C "$TMP" add -A; "${GIT[@]}" -C "$TMP" commit -q --no-verify -m pem
"${GIT[@]}" -C "$TMP" rm -q src/deleted.pem
"${GIT[@]}" -C "$TMP" commit -q -m "remove pem" 2>/dev/null; check "pre-commit: deleting a secret file is allowed" 0 "$?"
"${GIT[@]}" -C "$TMP" checkout -q --detach
echo c >> "$TMP/src/a.py"; "${GIT[@]}" -C "$TMP" add -A
"${GIT[@]}" -C "$TMP" commit -q -m detached 2>/dev/null; check "pre-commit: a detached HEAD is not a protected branch" 0 "$?"
# A file name is a file name: pathspec magic in it must not exclude the file from the scan.
printf 'K = "%s"\n' "$FAKE_AWS" > "$TMP/:(exclude)*"; "${GIT[@]}" -C "$TMP" add -- ':(literal):(exclude)*'
"${GIT[@]}" -C "$TMP" commit -q -m magic 2>/dev/null; check "pre-commit: a pathspec-magic file name does not hide a secret" 1 "$?"
"${GIT[@]}" -C "$TMP" reset -q; rm -f "$TMP/:(exclude)*"
# A tracked symlink replaced by a regular file is a type change (T), still staged content.
ln -s a.py "$TMP/src/link.py"; "${GIT[@]}" -C "$TMP" add -A; "${GIT[@]}" -C "$TMP" commit -q --no-verify -m link
rm "$TMP/src/link.py"; printf 'K = "%s"\n' "$FAKE_AWS" > "$TMP/src/link.py"; "${GIT[@]}" -C "$TMP" add -A
"${GIT[@]}" -C "$TMP" commit -q -m typechange 2>/dev/null; check "pre-commit: a symlink turned file does not hide a secret" 1 "$?"
"${GIT[@]}" -C "$TMP" reset -q --hard
# A newline in a file name must not split it into fragments the scan never matches.
printf 'K = "%s"\n' "$FAKE_AWS" > "$TMP/src/cfg"$'\n'".py"; "${GIT[@]}" -C "$TMP" add -A
"${GIT[@]}" -C "$TMP" commit -q -m newline 2>/dev/null; check "pre-commit: a newline in a file name does not hide a secret" 1 "$?"
"${GIT[@]}" -C "$TMP" reset -q; rm -f "$TMP/src/cfg"$'\n'".py"
# A NUL byte makes git call the file binary; the scan must still read its lines.
printf 'K = "%s"\n\0\n' "$FAKE_AWS" > "$TMP/src/bin.py"; "${GIT[@]}" -C "$TMP" add -A
"${GIT[@]}" -C "$TMP" commit -q -m nul 2>/dev/null; check "pre-commit: a NUL byte does not hide a secret" 1 "$?"
"${GIT[@]}" -C "$TMP" reset -q; rm -f "$TMP/src/bin.py"
rm -rf "$TMP"

echo "== install.sh (one command, any host) =="
# The installer is the first thing a stranger runs; it must never clobber their files, and what it
# installs must actually work. NONNA_SRC points it at this checkout instead of cloning.
IN="$ROOT/install.sh"
TMP="$(mktemp -d)"; "${GIT[@]}" -C "$TMP" init -q; echo '[project]' > "$TMP/pyproject.toml"
out="$(cd "$TMP" && NONNA_SRC="$ROOT" bash "$IN" 2>&1)"; check "install: default install succeeds" 0 "$?"
rc=0; [ -f "$TMP/.claude/rules/00-core.md" ] && [ -f "$TMP/CLAUDE.md" ] || rc=1; check "install: brings the harness and CLAUDE.md" 0 "$rc"
[ -f "$TMP/docs/STATUS.md" ] && ! grep -q 'Current state' /dev/null; check "install: seeds a docs/STATUS.md" 0 "$?"
grep -q 'nonna' "$TMP/docs/STATUS.md"; check "install: the seeded STATUS is a blank template, not this repo's status" 1 "$?"
rc=0; [ -x "$TMP/.git/hooks/pre-commit" ] && [ -x "$TMP/.git/hooks/pre-push" ] || rc=1; check "install: wires the git pre-commit and pre-push hooks" 0 "$rc"
[ -f "$TMP/.claude/settings.local.json" ] && grep -q 'pytest' "$TMP/.claude/settings.local.json"; check "install: picks the python stack pack from pyproject.toml" 0 "$?"
rc=0; [ ! -e "$TMP/.claude/reviews" ] && [ ! -e "$TMP/AGENTS.md" ] || rc=1; check "install: copies no review verdicts and no other host's files" 0 "$rc"
contains "install: says what it did, in Nonna's voice" "Nonna" "$out"
"${GIT[@]}" -C "$TMP" add -A; "${GIT[@]}" -C "$TMP" commit -q -m first 2>/dev/null; check "install: the installed pre-commit hook refuses a commit on main" 1 "$?"
echo 'my own rules' > "$TMP/CLAUDE.md"
( cd "$TMP" && NONNA_SRC="$ROOT" bash "$IN" >/dev/null 2>&1 ); check "install: a second run succeeds" 0 "$?"
grep -q 'my own rules' "$TMP/CLAUDE.md"; check "install: never overwrites an existing file" 0 "$?"
rm -rf "$TMP"
TMP="$(mktemp -d)"; "${GIT[@]}" -C "$TMP" init -q
( cd "$TMP" && NONNA_SRC="$ROOT" bash "$IN" --host cursor,agents >/dev/null 2>&1 ); check "install: --host cursor,agents succeeds" 0 "$?"
rc=0; [ -f "$TMP/.cursor/rules/nonna.mdc" ] && [ -f "$TMP/AGENTS.md" ] && [ ! -e "$TMP/CLAUDE.md" ] || rc=1; check "install: writes only the chosen hosts' files" 0 "$rc"
rc=0; [ -f "$TMP/.claude/rules/testing.md" ] && [ -x "$TMP/.git/hooks/pre-commit" ] || rc=1; check "install: every host gets the full rules and the git hooks" 0 "$rc"
rm -rf "$TMP"
TMP="$(mktemp -d)"; "${GIT[@]}" -C "$TMP" init -q
( cd "$TMP" && NONNA_SRC="$ROOT" bash "$IN" --host all >/dev/null 2>&1 ); check "install: --host all succeeds" 0 "$?"
n=0; for f in CLAUDE.md AGENTS.md GEMINI.md .cursor/rules/nonna.mdc .github/copilot-instructions.md .windsurf/rules/nonna.md .clinerules/nonna.md .kiro/steering/nonna.md; do [ -f "$TMP/$f" ] && n=$((n + 1)); done
check "install: --host all writes all eight host files" 8 "$n"
rm -rf "$TMP"
TMP="$(mktemp -d)"; "${GIT[@]}" -C "$TMP" init -q; printf '#!/bin/sh\necho mine\n' > "$TMP/.git/hooks/pre-commit"; chmod +x "$TMP/.git/hooks/pre-commit"
out="$(cd "$TMP" && NONNA_SRC="$ROOT" bash "$IN" 2>&1)"; check "install: a foreign git hook does not fail the install" 0 "$?"
grep -q 'echo mine' "$TMP/.git/hooks/pre-commit"; check "install: never overwrites a foreign git hook" 0 "$?"
contains "install: warns that the foreign hook needs chaining" "pre-commit" "$out"
rm -rf "$TMP"
TMP="$(mktemp -d)"
( cd "$TMP" && NONNA_SRC="$ROOT" bash "$IN" >/dev/null 2>&1 ); check "install: refuses outside a git repository" 1 "$?"
( cd "$TMP" && NONNA_SRC="$ROOT" bash "$IN" --host nosuchhost >/dev/null 2>&1 ); check "install: an unknown host is a usage error" 2 "$?"
( cd "$TMP" && NONNA_SRC="$ROOT" timeout 10 bash "$IN" --host >/dev/null 2>&1 ); check "install: --host with no value is a usage error, not a hang" 2 "$?"
out="$(bash -s -- --help < "$IN" 2>&1)"; contains "install: --help works when piped (curl | bash)" "--host" "$out"
rm -rf "$TMP"
# A .claude/ that already exists (say, only your settings.local.json) is merged into, file by file.
TMP="$(mktemp -d)"; "${GIT[@]}" -C "$TMP" init -q; mkdir -p "$TMP/.claude/hooks"
echo '{"mine":true}' > "$TMP/.claude/settings.local.json"; echo 'echo mine' > "$TMP/.claude/hooks/mine.sh"
( cd "$TMP" && NONNA_SRC="$ROOT" bash "$IN" >/dev/null 2>&1 ); check "install: merges into an existing .claude/" 0 "$?"
rc=0; [ -x "$TMP/.claude/hooks/pre-commit.sh" ] && [ -f "$TMP/.claude/rules/00-core.md" ] && [ -f "$TMP/.claude/hooks/lib/secret-patterns.sh" ] || rc=1
check "install: the merge brings every harness file the hooks need" 0 "$rc"
grep -q mine "$TMP/.claude/settings.local.json" && [ ! -x "$TMP/.claude/hooks/mine.sh" ]; check "install: your files are untouched, not even chmod-ed" 0 "$?"
rm -rf "$TMP"
# A settings.json you already had is kept, but then Nonna's Claude Code hooks are not wired: say so.
TMP="$(mktemp -d)"; "${GIT[@]}" -C "$TMP" init -q; mkdir -p "$TMP/.claude"; echo '{"permissions":{}}' > "$TMP/.claude/settings.json"
out="$(cd "$TMP" && NONNA_SRC="$ROOT" bash "$IN" 2>&1)"; check "install: a kept settings.json with no Nonna hooks is not a success" 1 "$?"
contains "install: says to merge the hooks block" "settings.json" "$out"
rm -rf "$TMP"
# Never write through a symlink, and never claim success with a git hook pointing at nothing.
TMP="$(mktemp -d)"; OUT="$(mktemp -d)"; "${GIT[@]}" -C "$TMP" init -q
ln -s "$OUT/elsewhere" "$TMP/.claude"; mkdir -p "$TMP/docs"; ln -s "$OUT/status" "$TMP/docs/STATUS.md"
out="$(cd "$TMP" && NONNA_SRC="$ROOT" bash "$IN" 2>&1)"; check "install: a missing harness is a failure, not a success" 1 "$?"
rc=0; [ ! -e "$OUT/elsewhere" ] && [ ! -e "$OUT/status" ] || rc=1; check "install: never writes through a symlink out of the repo" 0 "$rc"
rc=0; [ ! -e "$TMP/.git/hooks/pre-commit" ] && [ ! -L "$TMP/.git/hooks/pre-commit" ] || rc=1; check "install: links no git hook to a script that is not there" 0 "$rc"
contains "install: says the gates are not running" "not running" "$out"
rm -rf "$TMP" "$OUT"

echo "== check-trivial.sh (fast-lane eligibility gate) =="
CT="$SKILLS/fast-lane/scripts/check-trivial.sh"
TMP="$(mktemp -d)"
"${GIT[@]}" -C "$TMP" init -q
mkdir -p "$TMP/src"
seq 1 50 | sed 's/^/line /' > "$TMP/src/app.py"
"${GIT[@]}" -C "$TMP" add -A; "${GIT[@]}" -C "$TMP" commit -q -m base
"${GIT[@]}" -C "$TMP" branch -M main
"${GIT[@]}" -C "$TMP" checkout -q -b fix/tweak
sed -i '1,3s/line/edited/' "$TMP/src/app.py"
( cd "$TMP" && bash "$CT" main ); check "3-line change qualifies" 0 "$?"
mkdir -p "$TMP/tests"; seq 1 30 > "$TMP/tests/test_app.py"
( cd "$TMP" && bash "$CT" main ); check "test lines do not count against the budget" 0 "$?"
sed -i 's/^line/edited/' "$TMP/src/app.py"
( cd "$TMP" && bash "$CT" main ); check "40+ changed lines is over budget" 1 "$?"
"${GIT[@]}" -C "$TMP" checkout -q -- src/app.py
mkdir -p "$TMP/.claude/hooks"; echo 'x' > "$TMP/.claude/hooks/x.sh"
( cd "$TMP" && bash "$CT" main ); check "critical-surface path disqualifies" 1 "$?"
rm -rf "$TMP/.claude"
echo '{}' > "$TMP/package-lock.json"
( cd "$TMP" && bash "$CT" main ); check "lockfile touch disqualifies" 1 "$?"
rm -f "$TMP/package-lock.json"
( cd "$TMP" && bash "$CT" nosuchref ); check "unresolvable base fails closed" 1 "$?"
# A pure rename INTO a critical-surface path must not slip through (--no-renames).
"${GIT[@]}" -C "$TMP" checkout -q -- . 2>/dev/null; "${GIT[@]}" -C "$TMP" clean -fdq
"${GIT[@]}" -C "$TMP" checkout -q -b rename/crit main
mkdir -p "$TMP/migrations"; "${GIT[@]}" -C "$TMP" mv src/app.py migrations/001_app.py
( cd "$TMP" && bash "$CT" main ); check "rename into a critical path disqualifies" 1 "$?"
"${GIT[@]}" -C "$TMP" checkout -q main; "${GIT[@]}" -C "$TMP" branch -qD rename/crit
# NONNA_CRITICAL_PATHS glob must match nested paths even when the dir exists (no pathname expansion).
# existing.py lives in the BASE (main) so it is NOT in the diff — only the nested untracked file is,
# which the buggy pathname-expanding loop would miss exactly because src/billing/ exists.
"${GIT[@]}" -C "$TMP" checkout -q main
mkdir -p "$TMP/src/billing/deep"; echo 'existing' > "$TMP/src/billing/existing.py"
"${GIT[@]}" -C "$TMP" add -A; "${GIT[@]}" -C "$TMP" commit -q -m "billing dir exists on main"
"${GIT[@]}" -C "$TMP" checkout -q -b crit/env
printf 'a\nb\n' > "$TMP/src/billing/deep/rates.py"
( cd "$TMP" && NONNA_CRITICAL_PATHS='src/billing/*' bash "$CT" main ); check "NONNA_CRITICAL_PATHS glob catches nested path when dir exists" 1 "$?"
"${GIT[@]}" -C "$TMP" checkout -q main; "${GIT[@]}" -C "$TMP" branch -qD crit/env
NOREPO="$(mktemp -d)"
( cd "$NOREPO" && bash "$CT" ); check "not a git repo fails closed" 1 "$?"
rm -rf "$TMP" "$NOREPO"

echo "== review-lanes.sh (review proportionality: lane + security trigger) =="
# The script, not the model, decides how much review a diff buys: a fast-lane-sized diff gets one
# reviewer on the cheaper tier; a risky path or risky added code always adds the security reviewer.
# Every ambiguity answers lane=full, security=yes.
RL="$SKILLS/review/scripts/review-lanes.sh"
TMP="$(mktemp -d)"
"${GIT[@]}" -C "$TMP" init -q
mkdir -p "$TMP/src"
seq 1 50 | sed 's/^/line /' > "$TMP/src/app.py"
"${GIT[@]}" -C "$TMP" add -A; "${GIT[@]}" -C "$TMP" commit -q -m base
"${GIT[@]}" -C "$TMP" branch -M main
"${GIT[@]}" -C "$TMP" checkout -q -b feat/x
sed -i '1,3s/line/edited/' "$TMP/src/app.py"
out="$(cd "$TMP" && bash "$RL" main 2>/dev/null)"
contains "review-lanes: small plain diff takes the light lane" "lane=light" "$out"
contains "review-lanes: small plain diff needs no security review" "security=no" "$out"
sed -i 's/^line/edited/' "$TMP/src/app.py"
out="$(cd "$TMP" && bash "$RL" main 2>/dev/null)"
contains "review-lanes: over-budget diff takes the full lane" "lane=full" "$out"
contains "review-lanes: over-budget plain diff still needs no security review" "security=no" "$out"
"${GIT[@]}" -C "$TMP" checkout -q -- src/app.py
sed -i '1s/.*/subprocess.run(cmd, shell=True)/' "$TMP/src/app.py"
out="$(cd "$TMP" && bash "$RL" main 2>/dev/null)"
contains "review-lanes: risky added code triggers security review" "security=yes" "$out"
"${GIT[@]}" -C "$TMP" checkout -q -- src/app.py
mkdir -p "$TMP/src/auth"; echo 'x = 1' > "$TMP/src/auth/login.py"
out="$(cd "$TMP" && bash "$RL" main 2>/dev/null)"
contains "review-lanes: an auth path triggers security review" "security=yes" "$out"
rm -rf "$TMP/src/auth"
echo 'r = requests.get(url, timeout=5)' > "$TMP/src/client.py"
out="$(cd "$TMP" && bash "$RL" main 2>/dev/null)"
contains "review-lanes: an outward call in an untracked file triggers security review" "security=yes" "$out"
rm -f "$TMP/src/client.py"
mkdir -p "$TMP/tests"; echo 'token = "fixture"' > "$TMP/tests/test_app.py"
out="$(cd "$TMP" && bash "$RL" main 2>/dev/null)"
contains "review-lanes: risky words in tests alone do not trigger security review" "security=no" "$out"
rm -rf "$TMP/tests"
mkdir -p "$TMP/src/rates"; echo 'x = 1' > "$TMP/src/rates/post.py"
out="$(cd "$TMP" && bash "$RL" main 2>/dev/null)"
contains "review-lanes: a plain new file under an ordinary path needs no security review" "security=no" "$out"
out="$(cd "$TMP" && NONNA_CRITICAL_PATHS='src/rates/*' bash "$RL" main 2>/dev/null)"
contains "review-lanes: NONNA_CRITICAL_PATHS forces security review" "security=yes" "$out"
contains "review-lanes: NONNA_CRITICAL_PATHS forces the full lane" "lane=full" "$out"
out="$(cd "$TMP" && KEEL_CRITICAL_PATHS='src/rates/*' bash "$RL" main 2>/dev/null)"
contains "review-lanes: the pre-rename KEEL_CRITICAL_PATHS alone fails closed" "security=yes" "$out"
( cd "$TMP" && KEEL_CRITICAL_PATHS='src/rates/*' bash "$SKILLS/fast-lane/scripts/check-trivial.sh" main 2>/dev/null ); check "check-trivial: the pre-rename KEEL_CRITICAL_PATHS alone fails closed" 1 "$?"
rm -rf "$TMP/src/rates"
# Paths and content are read from the repo root, whatever the caller's cwd or the file's name.
sed -i '1s/.*/subprocess.run(cmd, shell=True)/' "$TMP/src/app.py"
out="$(cd "$TMP/src" && bash "$RL" main 2>/dev/null)"
contains "review-lanes: risky code is seen from a subdirectory cwd" "security=yes" "$out"
"${GIT[@]}" -C "$TMP" checkout -q -- src/app.py
printf 'os.system(x)\n' > "$TMP/src/café.py"
out="$(cd "$TMP" && bash "$RL" main 2>/dev/null)"
contains "review-lanes: risky code in a non-ASCII file name is seen" "security=yes" "$out"
rm -f "$TMP/src/café.py"
# Removing a guard is exactly what the security reviewer is for.
"${GIT[@]}" -C "$TMP" checkout -q main
printf 'def view(r):\n    require_auth(r)\n    return 1\n' > "$TMP/src/views.py"
"${GIT[@]}" -C "$TMP" add -A; "${GIT[@]}" -C "$TMP" commit -q -m "views on main"
"${GIT[@]}" -C "$TMP" checkout -q feat/x; "${GIT[@]}" -C "$TMP" merge -q main 2>/dev/null
sed -i '/require_auth/d' "$TMP/src/views.py"
out="$(cd "$TMP" && bash "$RL" main 2>/dev/null)"
contains "review-lanes: a removed auth check triggers security review" "security=yes" "$out"
"${GIT[@]}" -C "$TMP" checkout -q -- src/views.py
"${GIT[@]}" -C "$TMP" rm -q src/views.py
out="$(cd "$TMP" && bash "$RL" main 2>/dev/null)"
contains "review-lanes: deleting a file with an auth check triggers security review" "security=yes" "$out"
"${GIT[@]}" -C "$TMP" reset -q HEAD -- src/views.py; "${GIT[@]}" -C "$TMP" checkout -q -- src/views.py
echo '{"dependencies":{"lodahs":"1.0.0"}}' > "$TMP/package.json"
out="$(cd "$TMP" && bash "$RL" main 2>/dev/null)"
contains "review-lanes: a dependency manifest triggers security review" "security=yes" "$out"
rm -f "$TMP/package.json"
printf 'cmd := exec.Command("sh", "-c", s)\n' > "$TMP/src/run.go"
out="$(cd "$TMP" && bash "$RL" main 2>/dev/null)"
contains "review-lanes: a Go shell call triggers security review" "security=yes" "$out"
rm -f "$TMP/src/run.go"
mkdir -p "$TMP/.claude/agents"; printf 'tools: Bash\n' > "$TMP/.claude/agents/x.md"
out="$(cd "$TMP" && bash "$RL" main 2>/dev/null)"
contains "review-lanes: harness markdown is never quiet" "security=yes" "$out"
rm -rf "$TMP/.claude"
mkdir -p "$TMP/src/test_utils"; printf 'os.system(x)\n' > "$TMP/src/test_utils/runner.py"
out="$(cd "$TMP" && bash "$RL" main 2>/dev/null)"
contains "review-lanes: a test-looking directory name does not silence production code" "security=yes" "$out"
rm -rf "$TMP/src/test_utils"
ln -s /dev/null "$TMP/src/link.py"
out="$(cd "$TMP" && bash "$RL" main 2>/dev/null)"
contains "review-lanes: an untracked symlink fails closed" "security=yes" "$out"
rm -f "$TMP/src/link.py"
TRUNK="$(mktemp -d)"; "${GIT[@]}" -C "$TRUNK" init -q; echo a > "$TRUNK/a"; "${GIT[@]}" -C "$TRUNK" add -A; "${GIT[@]}" -C "$TRUNK" commit -q -m a
"${GIT[@]}" -C "$TRUNK" branch -M trunk; echo b >> "$TRUNK/a"; "${GIT[@]}" -C "$TRUNK" commit -qam b
out="$(cd "$TRUNK" && bash "$RL" 2>/dev/null)"
contains "review-lanes: no develop or main base fails closed instead of guessing the last commit" "lane=full" "$out"
rm -rf "$TRUNK"
out="$(cd "$TMP" && bash "$RL" nosuchref 2>/dev/null)"
contains "review-lanes: unresolvable base fails closed to the full lane" "lane=full" "$out"
contains "review-lanes: unresolvable base fails closed to security review" "security=yes" "$out"
LONE="$(mktemp -d)"; cp "$RL" "$LONE/review-lanes.sh"
out="$(cd "$TMP" && bash "$LONE/review-lanes.sh" main 2>/dev/null)"
contains "review-lanes: missing fast-lane classifier fails closed to the full lane" "lane=full" "$out"
NOREPO="$(mktemp -d)"
out="$(cd "$NOREPO" && bash "$RL" 2>/dev/null)"
contains "review-lanes: not a git repo fails closed" "security=yes" "$out"
rm -rf "$TMP" "$NOREPO" "$LONE"

echo "== check-debt.sh (debt-marker gate + ledger) =="
# A deliberate corner is only tracked if its marker names the trigger to revisit it.
# The script decides well-formedness; prose cannot. Fixtures build the marker from a
# split literal so this file never carries the marker form itself.
CD="$SKILLS/lean/scripts/check-debt.sh"
M='debt:'
TMP="$(mktemp -d)"; mkdir -p "$TMP/src" "$TMP/node_modules/x" "$TMP/docs"
printf 'lock = Lock()  # %s global lock, per-account locks if throughput matters\n' "$M" > "$TMP/src/ok.py"
( cd "$TMP" && bash "$CD" ); check "check-debt: marker with a trigger passes" 0 "$?"
out="$(cd "$TMP" && bash "$CD" --ledger 2>/dev/null)"; contains "check-debt: ledger counts it" "1 markers, 0 with no trigger." "$out"
contains "check-debt: ledger names the trigger" "upgrade: per-account locks" "$out"
printf 'for a in xs:  # %s O(n^2) scan\n' "$M" > "$TMP/src/rot.py"
( cd "$TMP" && bash "$CD" 2>/dev/null ); check "check-debt: marker with no trigger fails closed" 1 "$?"
out="$(cd "$TMP" && bash "$CD" --ledger 2>&1)"
contains "check-debt: ledger tags the rotting marker" "no-trigger" "$out"
contains "check-debt: ledger summary counts both" "2 markers, 1 with no trigger." "$out"
contains "check-debt: ledger groups by file" "src/rot.py" "$out"
contains "check-debt: stderr names path:line of the offender" "src/rot.py:1" "$out"
printf '// %s trailing comma,   \n' "$M" > "$TMP/src/empty.js"
( cd "$TMP" && bash "$CD" 2>/dev/null ); check "check-debt: empty text after the comma is still no-trigger" 1 "$?"
rm -f "$TMP/src/rot.py" "$TMP/src/empty.js"
printf '# %s nothing\n' "$M" > "$TMP/node_modules/x/dep.py"
( cd "$TMP" && bash "$CD" 2>/dev/null ); check "check-debt: node_modules is skipped" 0 "$?"
printf 'example: `# %s global lock`\n' "$M" > "$TMP/docs/lean.md"
( cd "$TMP" && bash "$CD" 2>/dev/null ); check "check-debt: markdown quoting the convention is not a marker" 0 "$?"
printf 'x = 1  # technical %s later\n' "$M" > "$TMP/src/prose.py"
( cd "$TMP" && bash "$CD" 2>/dev/null ); check "check-debt: the word without the comment prefix is not a marker" 0 "$?"
EMPTY="$(mktemp -d)"; out="$(cd "$EMPTY" && bash "$CD" --ledger 2>/dev/null)"; check "check-debt: clean tree exits 0" 0 "$?"
contains "check-debt: clean tree says so" "Clean ledger." "$out"
( cd "$EMPTY" && bash "$CD" --range main...HEAD 2>/dev/null ); check "check-debt: --range outside a git repo fails closed" 2 "$?"
( cd "$EMPTY" && bash "$CD" --bogus 2>/dev/null ); check "check-debt: unknown flag fails closed" 2 "$?"
# --range gates only ADDED lines: debt someone else left does not block this PR.
rm -rf "$TMP/node_modules"; "${GIT[@]}" -C "$TMP" init -q
printf 'y = 2  # %s naive heuristic\n' "$M" > "$TMP/src/old.py"
"${GIT[@]}" -C "$TMP" add -A; "${GIT[@]}" -C "$TMP" commit -qm base; "${GIT[@]}" -C "$TMP" branch -M main
"${GIT[@]}" -C "$TMP" checkout -q -b feature/debt
printf 'z = 3  # %s single worker, pool when queue depth > 100\n' "$M" > "$TMP/src/new.py"
"${GIT[@]}" -C "$TMP" add -A; "${GIT[@]}" -C "$TMP" commit -qm new
( cd "$TMP" && bash "$CD" --range main...HEAD 2>/dev/null ); check "check-debt: --range ignores a pre-existing no-trigger marker outside the diff" 0 "$?"
( cd "$TMP" && bash "$CD" 2>/dev/null ); check "check-debt: default scan still sees the pre-existing debt" 1 "$?"
printf 'w = 4  # %s cache never expires\n' "$M" >> "$TMP/src/new.py"
"${GIT[@]}" -C "$TMP" add -A; "${GIT[@]}" -C "$TMP" commit -qm rot
out="$(cd "$TMP" && bash "$CD" --range main...HEAD 2>&1)"; check "check-debt: --range blocks a new no-trigger marker" 1 "$?"
contains "check-debt: --range names path:line of the new offender" "src/new.py:2" "$out"
( cd "$TMP" && bash "$CD" --range nosuchref...HEAD 2>/dev/null ); check "check-debt: unresolvable range fails closed" 2 "$?"
# An option-shaped range must never reach git: --output=<path> would write the diff over any
# file, exec bit intact, from a pre-approved gate call (security review, 2026-09-22).
printf 'keep\n' > "$TMP/victim.sh"
( cd "$TMP" && bash "$CD" --range=--output=victim.sh 2>/dev/null ); check "check-debt: option-shaped --range= fails closed" 2 "$?"
check "check-debt: option-shaped range wrote nothing" "keep" "$(cat "$TMP/victim.sh")"
( cd "$TMP" && bash "$CD" --range --stat 2>/dev/null ); check "check-debt: option-shaped --range fails closed" 2 "$?"
( cd "$TMP" && bash "$CD" --range '' 2>/dev/null ); check "check-debt: empty range fails closed" 2 "$?"
# User git config must not turn the gate off: colour hides the +++ headers, an external diff
# replaces the output entirely.
( cd "$TMP" && git config --local color.diff always && git config --local diff.external /bin/true && bash "$CD" --range main...HEAD 2>/dev/null ); check "check-debt: --range ignores colour and external-diff config" 1 "$?"
( cd "$TMP" && git config --local --unset color.diff && git config --local --unset diff.external )
# A colon in the path must not let a trigger-less marker pass as well-formed.
mkdir -p "$TMP/src/a:1:x, y"; printf 'v = 5  # %s no trigger here\n' "$M" > "$TMP/src/a:1:x, y/z.py"
( cd "$TMP" && bash "$CD" src 2>/dev/null ); check "check-debt: a colon in the path cannot forge a trigger" 1 "$?"
rm -rf "$TMP/src/a:1:x, y"
# A space in the path makes git append a TAB to the +++ header; the columns must not shift.
printf 'q = 6  # %s no trigger\n' "$M" > "$TMP/src/my file.py"
"${GIT[@]}" -C "$TMP" add -A; "${GIT[@]}" -C "$TMP" commit -qm spaced
out="$(cd "$TMP" && bash "$CD" --range main...HEAD 2>&1)"; contains "check-debt: --range names a marker in a path with a space" "src/my file.py:1: no-trigger" "$out"
rm -f "$TMP/src/my file.py"; "${GIT[@]}" -C "$TMP" add -A; "${GIT[@]}" -C "$TMP" commit -qm unspaced
# An added line that begins '++ ' shows as '+++ ' in the diff and is content, not a header.
printf '++ x  # %s no trigger\ny = 1\n' "$M" > "$TMP/src/plus.txt"
"${GIT[@]}" -C "$TMP" add -A; "${GIT[@]}" -C "$TMP" commit -qm plus
out="$(cd "$TMP" && bash "$CD" --range main...HEAD 2>&1)"; contains "check-debt: --range does not mistake a '++ ' content line for a header" "src/plus.txt:1: no-trigger" "$out"
rm -f "$TMP/src/plus.txt"; "${GIT[@]}" -C "$TMP" add -A; "${GIT[@]}" -C "$TMP" commit -qm noplus
# CRLF: a trailing comma followed by \r is still no trigger.
printf 'r = 7  # %s ceiling,\r\n' "$M" > "$TMP/src/crlf.py"
out="$(cd "$TMP" && bash "$CD" src 2>&1)"; contains "check-debt: CRLF cannot turn a bare comma into a trigger" "src/crlf.py:1: no-trigger" "$out"
rm -f "$TMP/src/crlf.py"
( cd "$TMP" && bash "$CD" nosuchdir 2>/dev/null ); check "check-debt: a missing PATH fails closed" 2 "$?"
# A PR-controlled .gitattributes ('* -diff' / binary) must not hide added lines from --range.
printf '* -diff\n' > "$TMP/.gitattributes"; printf 's = 8  # %s hidden by attributes\n' "$M" > "$TMP/src/attr.py"
"${GIT[@]}" -C "$TMP" add -A; "${GIT[@]}" -C "$TMP" commit -qm attrs
out="$(cd "$TMP" && bash "$CD" --range main...HEAD 2>&1)"; contains "check-debt: --range sees through a -diff gitattribute" "src/attr.py:1: no-trigger" "$out"
rm -f "$TMP/.gitattributes" "$TMP/src/attr.py"; "${GIT[@]}" -C "$TMP" add -A; "${GIT[@]}" -C "$TMP" commit -qm noattrs
# A TAB in a file name is refused before grep runs — fail closed, never a guess.
printf 't = 9  # %s ceiling, trigger\n' "$M" > "$TMP/src/tab	name.py"
out="$(cd "$TMP" && bash "$CD" src 2>&1)"; check "check-debt: a tab in a file name fails closed" 2 "$?"
contains "check-debt: a tab in a file name is explained" "tab or newline" "$out"
rm -f "$TMP/src/tab	name.py"
# A crafted directory name with a tab and record-shaped text must not forge a record
# for the files beneath it: any tab or newline in a scanned path fails closed.
mkdir -p "$TMP/src/d	5:# $M c, t"; printf 'h = 1  # %s hidden\n' "$M" > "$TMP/src/d	5:# $M c, t/x.py"
( cd "$TMP" && bash "$CD" src 2>/dev/null ); check "check-debt: a crafted tab-bearing path fails closed" 2 "$?"
rm -rf "$TMP/src/d	5:# $M c, t"
# The guard checks the whole path, not just the last component, and a failing find is a stop.
mkdir -p "$TMP/src/p	1:# $M a, b"; printf 'k = 1  # %s hidden\n' "$M" > "$TMP/src/p	1:# $M a, b/f.py"
( cd "$TMP" && bash "$CD" "src/p	1:# $M a, b/f.py" 2>/dev/null ); check "check-debt: a tab in a parent of a path operand fails closed" 2 "$?"
rm -rf "$TMP/src/p	1:# $M a, b"
NOFIND="$(mktemp -d)"; printf '#!/bin/sh\nexit 1\n' > "$NOFIND/find"; chmod +x "$NOFIND/find"
( cd "$TMP" && PATH="$NOFIND:$PATH" bash "$CD" src 2>/dev/null ); check "check-debt: a failing find is a stop, not a skipped guard" 2 "$?"
rm -rf "$NOFIND"
mkdir -p "$TMP/node_modules/t	ab"; printf 'n = 1\n' > "$TMP/node_modules/t	ab/x.js"
( cd "$TMP" && bash "$CD" 2>/dev/null ); check "check-debt: a tab-named file inside a skipped dir is not a false stop (debt found, guard silent)" 1 "$?"
rm -rf "$TMP/node_modules"
# grep must read every file: a NUL byte or an invalid UTF-8 byte must not make a file
# "binary" and skipped, and a single-file operand still carries its filename.
printf 'v = 1  # %s nul byte\n\0\n' "$M" > "$TMP/src/nul.py"
out="$(cd "$TMP" && bash "$CD" src 2>&1)"; contains "check-debt: a NUL byte does not hide a marker" "src/nul.py:1: no-trigger" "$out"
printf 'w = 1  # %s bad byte \xff\n' "$M" > "$TMP/src/utf.py"
out="$(cd "$TMP" && LC_ALL=C.UTF-8 bash "$CD" src 2>&1)"; contains "check-debt: an invalid UTF-8 byte does not hide a marker" "src/utf.py:1: no-trigger" "$out"
rm -f "$TMP/src/nul.py" "$TMP/src/utf.py"
printf 'x = 1  # %s single file\n' "$M" > "$TMP/src/single.py"
out="$(cd "$TMP" && bash "$CD" src/single.py 2>&1)"; contains "check-debt: a single-file operand keeps its filename" "src/single.py:1: no-trigger" "$out"
rm -f "$TMP/src/single.py"
# A path argument of exactly '-' is a file, never stdin.
printf 'u = 1  # %s dash file\n' "$M" > "$TMP/-"
( cd "$TMP" && bash "$CD" -- - 2>/dev/null ); check "check-debt: a path named '-' is scanned as a file" 1 "$?"
rm -f "$TMP/-"
( cd "$ROOT" && bash "$CD" 2>/dev/null ); check "check-debt: Nonna's own tree carries no untriggered marker" 0 "$?"
rm -rf "$TMP" "$EMPTY"

echo "== format.sh (PostToolUse, best-effort) =="
TF="$(mktemp).py"; echo 'x=1' > "$TF"
printf '{"tool_name":"Write","tool_input":{"file_path":"%s"}}' "$TF" | "$HOOKS/format.sh"; check "exits 0 even if no formatter present" 0 "$?"
rm -f "$TF"

echo "== session-start.sh (SessionStart) =="
TMP="$(mktemp -d)"; "${GIT[@]}" -C "$TMP" init -q
mkdir -p "$TMP/.claude/hooks"; cp "$HOOKS/require-status-sync.sh" "$TMP/.claude/hooks/"
out="$(CLAUDE_PROJECT_DIR="$TMP" "$HOOKS/session-start.sh")"; check "exits 0" 0 "$?"
contains "emits additionalContext" "additionalContext" "$out"
if [ -e "$TMP/.git/hooks/pre-push" ]; then rc=0; else rc=1; fi; check "auto-installs the pre-push DoD hook" 0 "$rc"
out="$(CLAUDE_PROJECT_DIR="$TMP" "$HOOKS/session-start.sh")"
printf '%s' "$out" | grep -q "not Nonna's DoD hook"; check "no warning when Nonna's own hook is installed" 1 "$?"
rm -rf "$TMP"
# A pre-existing foreign pre-push hook must never be overwritten — but going
# silent about it means the DoD gate is off without anyone knowing. Warn.
TMP="$(mktemp -d)"; "${GIT[@]}" -C "$TMP" init -q
mkdir -p "$TMP/.claude/hooks"; cp "$HOOKS/require-status-sync.sh" "$TMP/.claude/hooks/"
printf '#!/bin/sh\nexit 0\n' > "$TMP/.git/hooks/pre-push"; chmod +x "$TMP/.git/hooks/pre-push"
out="$(CLAUDE_PROJECT_DIR="$TMP" "$HOOKS/session-start.sh")"; check "exits 0 with a foreign pre-push hook" 0 "$?"
contains "warns that DoD is not enforced" "not Nonna's DoD hook" "$out"
grep -q 'exit 0' "$TMP/.git/hooks/pre-push"; check "does not overwrite the foreign hook" 0 "$?"
rm -rf "$TMP"
# Plugin install: the repo has no .claude/ at all — the harness lives at
# CLAUDE_PLUGIN_ROOT. Guarding only on the project-local path made this case
# silently skip the DoD gate. A gate that is off without saying so is exactly
# what ADR-0004 forbids, so this must either install or warn — never both quiet.
TMP="$(mktemp -d)"; "${GIT[@]}" -C "$TMP" init -q
out="$(CLAUDE_PROJECT_DIR="$TMP" CLAUDE_PLUGIN_ROOT="$ROOT/.claude" "$HOOKS/session-start.sh")"; check "plugin install: exits 0" 0 "$?"
if [ -e "$TMP/.git/hooks/pre-push" ]; then rc=0; else rc=1; fi; check "plugin install: installs the DoD hook from CLAUDE_PLUGIN_ROOT" 0 "$rc"
contains "plugin install: announces the resolved harness root" "$ROOT/.claude" "$out"
rm -rf "$TMP"
# Neither source present: the gate cannot be installed, so it must say so loudly.
TMP="$(mktemp -d)"; "${GIT[@]}" -C "$TMP" init -q
out="$(CLAUDE_PROJECT_DIR="$TMP" "$HOOKS/session-start.sh")"; check "unlocatable harness: still exits 0" 0 "$?"
contains "unlocatable harness: warns DoD is NOT enforced" "NOT enforced" "$out"
if [ -e "$TMP/.git/hooks/pre-push" ]; then rc=0; else rc=1; fi; check "unlocatable harness: installs no dangling hook" 1 "$rc"
rm -rf "$TMP"
# Plugin install: rules/ never loads (no `rules` plugin component, ADR-0007), so the
# constitution must ride additionalContext or the user gets agents with no policy.
TMP="$(mktemp -d)"; "${GIT[@]}" -C "$TMP" init -q
out="$(CLAUDE_PROJECT_DIR="$TMP" CLAUDE_PLUGIN_ROOT="$ROOT/.claude" "$HOOKS/session-start.sh")"
contains "plugin install: carries the constitution in additionalContext" "The three principles" "$out"
contains "plugin install: says the rules are not loaded" "NOT loaded" "$out"
contains "plugin install: carries the never-list" "Mark work done" "$out"
rm -rf "$TMP"
# Standalone checkout: rules/ loads natively — carrying it again would double-pay.
TMP="$(mktemp -d)"; "${GIT[@]}" -C "$TMP" init -q
mkdir -p "$TMP/.claude/hooks" "$TMP/.claude/rules"
cp "$HOOKS/require-status-sync.sh" "$TMP/.claude/hooks/"
cp "$ROOT/.claude/rules/00-core.md" "$TMP/.claude/rules/"
out="$(CLAUDE_PROJECT_DIR="$TMP" "$HOOKS/session-start.sh")"
printf '%s' "$out" | grep -q "The three principles"; check "standalone: does NOT double-pay for the constitution" 1 "$?"
rm -rf "$TMP"
# Standalone checkout: the announced root must be the project's own .claude/.
TMP="$(mktemp -d)"; "${GIT[@]}" -C "$TMP" init -q
mkdir -p "$TMP/.claude/hooks"; cp "$HOOKS/require-status-sync.sh" "$TMP/.claude/hooks/"
out="$(CLAUDE_PROJECT_DIR="$TMP" "$HOOKS/session-start.sh")"
contains "standalone: announces the project harness root" "$TMP/.claude" "$out"
# One assertion, always executed: a branch that only sometimes runs makes the
# derived suite count (harness_lint's ACTUAL_GATES) disagree with what the run
# reports, and a test count that is off by one is a test count nobody trusts.
link="$(readlink "$TMP/.git/hooks/pre-push" 2>/dev/null || printf 'copied-not-symlink')"
case "$link" in /*) target="absolute" ;; *) target="relative-or-copied" ;; esac
check "standalone: pre-push target is not absolute (survives a repo move)" "relative-or-copied" "$target"
rm -rf "$TMP"

echo "== check-review.sh (review verdict gate) =="
CR="$SKILLS/code-review/scripts/check-review.sh"
if [ -x "$CR" ] || [ -f "$CR" ]; then
  printf '%s' '{"verdict":"approve","summary":"ok","findings":[]}' | bash "$CR"; check "approve passes" 0 "$?"
  printf '%s' '{"verdict":"request_changes","summary":"no","findings":[]}' | bash "$CR"; check "request_changes blocks" 1 "$?"
  printf '%s' '{"verdict":"approve","summary":"x","findings":[{"severity":"CRITICAL","path":"a","line":1,"category":"security","issue":"i","fix":"f"}]}' | bash "$CR"; check "CRITICAL finding blocks even if verdict says approve" 1 "$?"
  printf '%s' 'not json at all' | bash "$CR"; check "invalid JSON fails closed (non-zero)" 2 "$?"
  printf '%s' '{"verdict":"approve","summary":"x","findings":[{"severity":"BLOCKER","path":"a","line":1,"category":"security","issue":"i","fix":"f"}]}' | bash "$CR"; check "out-of-schema severity blocks" 1 "$?"
  printf '%s' '{"verdict":"lgtm","summary":"x","findings":[]}' | bash "$CR"; check "out-of-schema verdict fails closed" 2 "$?"
  printf '%s' '{"summary":"x","findings":[]}' | bash "$CR"; check "missing verdict fails closed" 2 "$?"
  printf '%s' '{"verdict":"approve","summary":"x","findings":[{"severity":"MEDIUM","path":"a","line":1,"category":"tests","issue":"i","fix":"f"}]}' | bash "$CR"; check "MEDIUM-only approve still passes" 0 "$?"
  printf '%s' '{"verdict":"approve","summary":"x","findings":[{"severity":"MEDIUM","path":"a","line":1,"category":"simplicity","issue":"yagni: one impl","fix":"inline"}]}' | bash "$CR"; check "a MEDIUM simplicity finding approves (ADR-0008: size never blocks alone)" 0 "$?"
  printf 'Prose before.\n```json\n{"verdict":"request_changes","summary":"x","findings":[]}\n```\nProse after.\n' | bash "$CR"; check "fenced request_changes block extracted and blocks" 1 "$?"
  printf 'Prose before.\n```json\n{"verdict":"approve","summary":"x","findings":[]}\n```\nProse after.\n' | bash "$CR"; check "fenced approve block extracted and passes" 0 "$?"
  printf '```json\n{"verdict":"approve","summary":"x","findings":[]}\n```\n```json\n{"verdict":"approve","summary":"y","findings":[]}\n```\n' | bash "$CR"; check "two fenced blocks is ambiguous, fails closed" 2 "$?"
  printf '%s' '{"verdict":"approve","summary":"x","findings":[{"severity":123,"path":"a","line":1,"category":"x","issue":"i","fix":"f"}]}' | bash "$CR"; check "non-string severity fails closed, not a jq crash" 1 "$?"
  # Review inflation: a non-blocking finding whose fix only adds code, with no failing input named,
  # is listed as optional so the implementer leaves it. The exit code never changes.
  out="$(printf '%s' '{"verdict":"approve","summary":"x","findings":[{"severity":"MEDIUM","path":"src/a.py","line":7,"category":"correctness","issue":"no guard","fix":"add a guard","adds_code":true}]}' | bash "$CR" 2>&1)"; rc=$?
  check "adds-code MEDIUM with no failing input still approves" 0 "$rc"
  contains "adds-code MEDIUM with no failing input is listed as optional" "optional: src/a.py:7" "$out"
  out="$(printf '%s' '{"verdict":"approve","summary":"x","findings":[{"severity":"LOW","path":"src/a.py","line":9,"category":"correctness","issue":"i","fix":"f","adds_code":true,"failing_input":"parse(\"\") returns 0, not ValueError"}]}' | bash "$CR" 2>&1)"
  case "$out" in *"optional:"*) r=1 ;; *) r=0 ;; esac; check "a finding that names a failing input is not marked optional" 0 "$r"
  out="$(printf '%s' '{"verdict":"approve","summary":"x","findings":[{"severity":"MEDIUM","path":"src/b.py","line":3,"category":"tests","issue":"i","fix":"f","adds_code":true,"failing_input":"  "}]}' | bash "$CR" 2>&1)"
  contains "a blank failing input counts as none" "optional: src/b.py:3" "$out"
  out="$(printf '%s' '{"verdict":"approve","summary":"x","findings":[{"severity":"MEDIUM","path":"src/c.py","line":1,"category":"style","issue":"i","fix":"f"}]}' | bash "$CR" 2>&1)"
  case "$out" in *"optional:"*) r=1 ;; *) r=0 ;; esac; check "a finding that does not add code is not marked optional" 0 "$r"
  # jq-absent fallback must be as strict as the jq path — including case.
  NOJQ="$(mktemp -d)"
  for b in bash sh env cat grep sed head tr printf awk dirname; do
    p="$(command -v "$b" 2>/dev/null || true)"; [ -n "$p" ] && ln -s "$p" "$NOJQ/$b" 2>/dev/null || true
  done
  printf '%s' '{"verdict":"approve","summary":"x","findings":[{"severity":"critical","path":"a","line":1,"category":"x","issue":"i","fix":"f"}]}' | PATH="$NOJQ" bash "$CR"; check "no-jq: lowercase blocking severity still blocks" 1 "$?"
  printf '%s' '{"verdict":"approve","summary":"x","findings":[{"severity":"MEDIUM","path":"a","line":1,"category":"x","issue":"i","fix":"f"}]}' | PATH="$NOJQ" bash "$CR"; check "no-jq: MEDIUM-only still approves" 0 "$?"
  rm -rf "$NOJQ"
else
  echo "  (skip: check-review.sh not found)"
fi

echo "== dep-audit.sh (supply-chain gate) =="
DA="$SKILLS/supply-chain/scripts/dep-audit.sh"
if [ -f "$DA" ]; then
  TMP="$(mktemp -d)"; ( cd "$TMP" && bash "$DA" ); check "exit 3 when no lockfile present" 3 "$?"; rm -rf "$TMP"
else
  echo "  (skip: dep-audit.sh not found)"
fi

echo "== bypass-resistance (review-finding regressions) =="
SP="$HOOKS/lib/secret-patterns.sh"
# A trailing placeholder word must NOT smuggle a real key (value-level, not line-level).
(. "$SP" && printf 'AWS=%s # example' "$FAKE_AWS" | nonna_scan_secrets) >/dev/null; check "secret: trailing '# example' does not evade a real key" 0 "$?"
# AWS's own EXAMPLE key (the value itself is a placeholder) IS exempt.
(. "$SP" && printf 'key=AKIAIOSFODNN7EXAMPLE' | nonna_scan_secrets) >/dev/null; check "secret: placeholder value (…EXAMPLE) is exempt" 1 "$?"
# New high-confidence classes.
(. "$SP" && printf 'k = "sk_live_%s"' '0123456789abcdefABCD' | nonna_scan_secrets) >/dev/null; check "secret: detects Stripe sk_live_ key" 0 "$?"
# Path allowlist is anchored to segments: an ordinary file with a 'test' substring is NOT exempt.
printf '%s' '{"tool_name":"Write","tool_input":{"file_path":"src/latest_config.py","content":"K=\"'"$FAKE_AWS"'\""}}' | "$SS"; check "secret-scan: 'latest_config.py' is NOT allowlisted" 2 "$?"
printf '%s' '{"tool_name":"Write","tool_input":{"file_path":"src/app/tests/k.py","content":"K=\"'"$FAKE_AWS"'\""}}' | "$SS"; check "secret-scan: a real tests/ segment IS allowlisted" 0 "$?"
# Secret gate must fail CLOSED when jq is absent (raw-payload scan).
NOJQ="$(mktemp -d)"
for b in bash sh env cat grep sed head tr dirname; do
  p="$(command -v "$b" 2>/dev/null || true)"
  if [ -n "$p" ]; then ln -s "$p" "$NOJQ/$b" 2>/dev/null || true; fi
done
printf '%s' '{"tool_name":"Write","tool_input":{"file_path":"c.py","content":"K = \"'"$FAKE_AWS"'\""}}' | PATH="$NOJQ" "$SS"; check "secret-scan: blocks a secret when jq is absent" 2 "$?"
rm -rf "$NOJQ"
# Branch guard tolerates global options and blocks wide pushes.
TMP="$(mktemp -d)"; "${GIT[@]}" -C "$TMP" init -q; "${GIT[@]}" -C "$TMP" commit -q --allow-empty -m init; "${GIT[@]}" -C "$TMP" branch -M main
printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git -C . commit -m x"}}' | CLAUDE_PROJECT_DIR="$TMP" "$GB"; check "guard-branch: blocks 'git -C . commit' on main" 2 "$?"
printf '%s' '{"tool_name":"Bash","tool_input":{"command":"/usr/bin/git commit -m x"}}' | CLAUDE_PROJECT_DIR="$TMP" "$GB"; check "guard-branch: blocks absolute-path git commit on main" 2 "$?"
printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git -C . status"}}' | CLAUDE_PROJECT_DIR="$TMP" "$GB"; check "guard-branch: allows non-mutating 'git -C . status' on main" 0 "$?"
"${GIT[@]}" -C "$TMP" checkout -q -b feature/z
printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git push --all origin"}}' | CLAUDE_PROJECT_DIR="$TMP" "$GB"; check "guard-branch: blocks 'git push --all'" 2 "$?"
printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git push origin HEAD:refs/heads/main"}}' | CLAUDE_PROJECT_DIR="$TMP" "$GB"; check "guard-branch: blocks qualified refs/heads/main push" 2 "$?"
rm -rf "$TMP"

echo "== stop-dod.sh (Stop: no turn ends with STATUS stale) =="
# Detection claims pytest only when it is importable, so these tests must not depend on the machine
# having it: a stand-in pytest (a tiny runner of test_* functions) goes first on PATH for them.
PYSTUB="$(mktemp -d)"; mkdir -p "$PYSTUB/pytest"
cat > "$PYSTUB/pytest/__main__.py" <<'PY'
import glob, importlib.util, os, sys
sys.path.insert(0, os.getcwd())
failed = passed = 0
for path in sorted(glob.glob("tests/test_*.py")):
    spec = importlib.util.spec_from_file_location(os.path.basename(path)[:-3], path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    for name in sorted(n for n in dir(mod) if n.startswith("test_")):
        try:
            getattr(mod, name)()
            passed += 1
        except Exception:
            failed += 1
            print(f"FAILED {path}::{name}")
print(f"{failed} failed, {passed} passed" if failed else f"{passed} passed")
sys.exit(1 if failed else 0)
PY
: > "$PYSTUB/pytest/__init__.py"
OLD_PYTHONPATH="${PYTHONPATH-}"; export PYTHONPATH="$PYSTUB${PYTHONPATH:+:$PYTHONPATH}"
SD="$HOOKS/stop-dod.sh"
TMP="$(mktemp -d)"; "${GIT[@]}" -C "$TMP" init -q
mkdir -p "$TMP/docs"; printf 'x\n' > "$TMP/src.py"; printf 'S\n' > "$TMP/docs/STATUS.md"
"${GIT[@]}" -C "$TMP" add -A >/dev/null; "${GIT[@]}" -C "$TMP" commit -qm init
printf 'clean tree\n' > /dev/null
out="$(printf '{}' | CLAUDE_PROJECT_DIR="$TMP" "$SD")"; check "clean tree: turn ends freely" 0 "$?"
contains "clean tree: emits no block" "" "$out"
printf 'y\n' >> "$TMP/src.py"
out="$(printf '{}' | CLAUDE_PROJECT_DIR="$TMP" "$SD")"
contains "code changed + STATUS stale: blocks" '"decision":"block"' "$out"
contains "block names the Definition of Done" "Definition of Done" "$out"
printf 'more\n' >> "$TMP/docs/STATUS.md"
out="$(printf '{}' | CLAUDE_PROJECT_DIR="$TMP" "$SD")"
printf '%s' "$out" | grep -q '"decision"'; check "STATUS updated alongside: does NOT block" 1 "$?"
"${GIT[@]}" -C "$TMP" checkout -q -- . 2>/dev/null
# Doc-only work and untracked scratch files are not "a completed unit of code".
printf 'note\n' >> "$TMP/docs/OTHER.md" 2>/dev/null || true
printf 'scratch\n' > "$TMP/untracked.tmp"
out="$(printf '{}' | CLAUDE_PROJECT_DIR="$TMP" "$SD")"
printf '%s' "$out" | grep -q '"decision"'; check "docs-only + untracked scratch: does NOT block" 1 "$?"
# Fails OPEN outside a git repo -- a Stop hook that errors would wedge the session.
NOGIT="$(mktemp -d)"
printf '{}' | CLAUDE_PROJECT_DIR="$NOGIT" "$SD" >/dev/null; check "non-repo: fails open, never wedges the turn" 0 "$?"
rm -rf "$TMP" "$NOGIT"
# "Done" means the suite passes, not that the agent says so. The Stop hook runs the project's own
# test command when code changed, and blocks once on red; the second stop goes through so an agent
# that cannot fix it must say so instead of looping.
TMP="$(mktemp -d)"; "${GIT[@]}" -C "$TMP" init -q
mkdir -p "$TMP/docs" "$TMP/tests"; printf 'S\n' > "$TMP/docs/STATUS.md"; printf '[project]\nname = "x"\n' > "$TMP/pyproject.toml"
printf 'def f():\n    return 1\n' > "$TMP/app.py"; printf 'from app import f\n\ndef test_f():\n    assert f() == 1\n' > "$TMP/tests/test_app.py"
"${GIT[@]}" -C "$TMP" add -A >/dev/null; "${GIT[@]}" -C "$TMP" commit -qm init
mkdir -p "$TMP/.claude/hooks/lib"; cp "$HOOKS/lib/tests.sh" "$TMP/.claude/hooks/lib/"  # a copy-in install, untracked
printf 'def f():\n    return 2\n' > "$TMP/app.py"; printf 'S2\n' > "$TMP/docs/STATUS.md"
out="$(printf '{"stop_hook_active":false}' | CLAUDE_PROJECT_DIR="$TMP" "$SD")"
contains "stop: a red suite blocks the turn even with STATUS updated" '"decision":"block"' "$out"
contains "stop: says the tests said no, in Nonna's voice" "the tests say no" "$out"
contains "stop: names the command it ran" "pytest" "$out"
out="$(printf '{"stop_hook_active":true}' | CLAUDE_PROJECT_DIR="$TMP" "$SD")"
printf '%s' "$out" | grep -q '"decision"'; check "stop: a second stop after a red block goes through (no loop)" 1 "$?"
printf 'def f():\n    return 1\n\n\ndef g():\n    return 3\n' > "$TMP/app.py"
out="$(printf '{"stop_hook_active":false}' | CLAUDE_PROJECT_DIR="$TMP" "$SD")"
printf '%s' "$out" | grep -q '"decision"'; check "stop: a green suite with STATUS updated ends freely" 1 "$?"
out="$(printf '{}' | NONNA_TEST_CMD=false CLAUDE_PROJECT_DIR="$TMP" "$SD")"
contains "stop: NONNA_TEST_CMD overrides detection" "the tests say no" "$out"
# A green run is remembered: the same tree and command are not re-run at every turn end.
CNT="$(mktemp)"; printf 'def f():\n    return 4\n' > "$TMP/app.py"
printf '{}' | NONNA_TEST_CMD="echo x >> $CNT" CLAUDE_PROJECT_DIR="$TMP" "$SD" >/dev/null
printf '{}' | NONNA_TEST_CMD="echo x >> $CNT" CLAUDE_PROJECT_DIR="$TMP" "$SD" >/dev/null
check "stop: an unchanged green tree is not re-tested" 1 "$(grep -c x "$CNT")"
printf 'def f():\n    return 5\n' > "$TMP/app.py"
printf '{}' | NONNA_TEST_CMD="echo x >> $CNT" CLAUDE_PROJECT_DIR="$TMP" "$SD" >/dev/null
check "stop: a changed tree is re-tested" 2 "$(grep -c x "$CNT")"
rm -f "$CNT"  # kept outside the repo: a counter inside it would change the tree it counts
# A suite slower than the Stop budget is not "red": the turn ends, the pre-push gate still runs it.
out="$(printf '{}' | NONNA_TEST_TIMEOUT=1 NONNA_TEST_CMD='sleep 5' CLAUDE_PROJECT_DIR="$TMP" "$SD")"
printf '%s' "$out" | grep -q '"decision"'; check "stop: a timed-out suite does not block the turn" 1 "$?"
# Without jq the block must still be valid JSON, whatever the command and its output contain.
NOJQ="$(mktemp -d)"
for b in bash sh env cat grep sed head tail tr cut awk dirname git timeout printf mktemp cp rm; do
  p="$(command -v "$b" 2>/dev/null || true)"
  if [ -n "$p" ] && [ "${p#/}" != "$p" ]; then ln -s "$p" "$NOJQ/$b" 2>/dev/null || true; fi
done
out="$(printf '{}' | PATH="$NOJQ" NONNA_TEST_CMD='printf "a\\b \"q\"\t\033[31mred\n"; false' CLAUDE_PROJECT_DIR="$TMP" "$SD")"
printf '%s' "$out" | python3 -c 'import json,sys; d=json.load(sys.stdin); sys.exit(0 if d["decision"]=="block" else 1)'
check "stop: the no-jq block is valid JSON with quotes, backslashes and control bytes" 0 "$?"
rm -rf "$NOJQ"
rm -rf "$TMP"
# Plugin install: the harness is not in the repo, so nobody agreed to have the repo's own code run at
# every turn end. The auto-detected suite runs only with a copy-in install or an explicit NONNA_TEST_CMD.
TMP="$(mktemp -d)"; "${GIT[@]}" -C "$TMP" init -q
mkdir -p "$TMP/docs" "$TMP/tests"; printf 'S\n' > "$TMP/docs/STATUS.md"
printf 'def f():\n    return 1\n' > "$TMP/app.py"; printf 'from app import f\n\ndef test_f():\n    assert f() == 1\n' > "$TMP/tests/test_app.py"
"${GIT[@]}" -C "$TMP" add -A >/dev/null; "${GIT[@]}" -C "$TMP" commit -qm init
printf 'def f():\n    return 2\n' > "$TMP/app.py"; printf 'S2\n' > "$TMP/docs/STATUS.md"
out="$(printf '{}' | CLAUDE_PROJECT_DIR="$TMP" "$SD")"
printf '%s' "$out" | grep -q '"decision"'; check "stop: plugin install never auto-runs the repo's tests" 1 "$?"
out="$(printf '{}' | NONNA_TEST_CMD='python3 -m pytest -q' CLAUDE_PROJECT_DIR="$TMP" "$SD")"
contains "stop: plugin install runs the suite once NONNA_TEST_CMD opts in" "the tests say no" "$out"
rm -rf "$TMP"
# Without timeout(1) (macOS), the fallback must kill the whole process group, not wait out a child.
NOTO="$(mktemp -d)"
for b in bash sh perl tail sleep cat rm mktemp; do p="$(command -v "$b")"; ln -s "$p" "$NOTO/$b"; done
start=$SECONDS
# shellcheck disable=SC2030  # PATH is meant to change only inside the subshell
( PATH="$NOTO"; . "$HOOKS/lib/tests.sh"; NONNA_TEST_TIMEOUT=1 nonna_run_tests 'sh -c "sleep 6"' ); rc=$?
check "tests.sh: no timeout(1): a forking suite is cut off on time (124)" 124 "$rc"
check "tests.sh: no timeout(1): ...and within the budget, not after the child" 1 "$(( SECONDS - start < 4 ))"
rm -rf "$NOTO"
# Detection claims pytest only when pytest is there; a false red would block every push.
TMP="$(mktemp -d)"; STUB="$(mktemp -d)"; mkdir -p "$TMP/tests" "$TMP/.claude/hooks/lib"; : > "$TMP/.claude/hooks/lib/tests.sh"
printf 'def test_x():\n    pass\n' > "$TMP/tests/test_x.py"
printf '#!/bin/sh\nexit 1\n' > "$STUB/python3"; chmod +x "$STUB/python3"
got="$(cd "$TMP" && unset NONNA_TEST_CMD && . "$HOOKS/lib/tests.sh" && nonna_test_cmd)"; contains "tests.sh: detects pytest in a copy-in install" "pytest" "$got"
# shellcheck disable=SC2031
got="$(cd "$TMP" && unset NONNA_TEST_CMD && PATH="$STUB:$PATH" && . "$HOOKS/lib/tests.sh" && nonna_test_cmd)"; check "tests.sh: no pytest installed, no pytest command" 0 "${#got}"
rm -rf "$TMP" "$STUB"

rm -rf "$PYSTUB"; if [ -n "$OLD_PYTHONPATH" ]; then PYTHONPATH="$OLD_PYTHONPATH"; else unset PYTHONPATH; fi

echo "== subagent-start.sh (SubagentStart: the constitution reaches subagents) =="
# SessionStart additionalContext is parent-only, so under a plugin install every
# Task-spawned agent ran with no policy. Plugin mode carries 00-core.md in; a
# standalone checkout loads rules/ natively for subagents too and must not double-pay.
SA="$HOOKS/subagent-start.sh"
TMP="$(mktemp -d)"; "${GIT[@]}" -C "$TMP" init -q
out="$(printf '{"agent_type":"implementer"}' | CLAUDE_PROJECT_DIR="$TMP" CLAUDE_PLUGIN_ROOT="$ROOT/.claude" "$SA")"; check "subagent-start: plugin install exits 0" 0 "$?"
contains "subagent-start: plugin install emits SubagentStart context" '"hookEventName":"SubagentStart"' "$out"
contains "subagent-start: plugin install carries the constitution" "The three principles" "$out"
contains "subagent-start: plugin install carries the ladder" "YAGNI" "$out"
printf '%s' "$out" | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null; check "subagent-start: plugin output is valid JSON" 0 "$?"
out="$(sleep 3 | CLAUDE_PROJECT_DIR="$TMP" CLAUDE_PLUGIN_ROOT="$ROOT/.claude" timeout 2 "$SA")"; check "subagent-start: never waits on stdin" 0 "$?"
NOJQ="$(mktemp -d)"
for b in bash sh env cat grep sed head tr dirname awk; do
  p="$(command -v "$b" 2>/dev/null || true)"
  if [ -n "$p" ]; then ln -s "$p" "$NOJQ/$b" 2>/dev/null || true; fi
done
out="$(printf '{}' | PATH="$NOJQ" CLAUDE_PROJECT_DIR="$TMP" CLAUDE_PLUGIN_ROOT="$ROOT/.claude" "$SA")"
printf '%s' "$out" | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null; check "subagent-start: no-jq fallback is still valid JSON" 0 "$?"
contains "subagent-start: no-jq fallback still carries the constitution" "The three principles" "$out"
# Without awk the escaper cannot run: emit nothing rather than an empty (valid, silent) carrier.
rm -f "$NOJQ/awk"
out="$(printf '{}' | PATH="$NOJQ" CLAUDE_PROJECT_DIR="$TMP" CLAUDE_PLUGIN_ROOT="$ROOT/.claude" "$SA" 2>/dev/null)"; check "subagent-start: no-jq, no-awk exits 0" 0 "$?"
check "subagent-start: no-jq, no-awk emits nothing instead of an empty carrier" "" "$out"
# Backslashes and quotes in the carrier must survive the awk escaper on any awk.
ln -sf "$(command -v awk)" "$NOJQ/awk"
BQ="$(mktemp -d)"; mkdir -p "$BQ/hooks" "$BQ/rules"; cp "$HOOKS/require-status-sync.sh" "$BQ/hooks/"
printf '# Core\nsay "hi" and C:\\path\\ end\\\n' > "$BQ/rules/00-core.md"
out="$(printf '{}' | PATH="$NOJQ" CLAUDE_PROJECT_DIR="$TMP" CLAUDE_PLUGIN_ROOT="$BQ" "$SA")"
dec="$(printf '%s' "$out" | python3 -c 'import json,sys; print(json.load(sys.stdin)["hookSpecificOutput"]["additionalContext"])' 2>/dev/null)"; check "subagent-start: no-jq fallback with backslashes and quotes is valid JSON" 0 "$?"
contains "subagent-start: no-jq fallback round-trips a backslash and a quote" "say \"hi\" and C:\\path\\ end\\" "$dec"
rm -rf "$BQ"
# A control character in the carrier must not break the JSON.
CTL="$(mktemp -d)"; mkdir -p "$CTL/hooks" "$CTL/rules"; cp "$HOOKS/require-status-sync.sh" "$CTL/hooks/"
printf '# Core\x01 with\x1b control\n' > "$CTL/rules/00-core.md"; ln -sf "$(command -v awk)" "$NOJQ/awk"
out="$(printf '{}' | PATH="$NOJQ" CLAUDE_PROJECT_DIR="$TMP" CLAUDE_PLUGIN_ROOT="$CTL" "$SA")"
printf '%s' "$out" | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null; check "subagent-start: no-jq fallback survives control characters" 0 "$?"
rm -rf "$CTL"
rm -rf "$NOJQ" "$TMP"
TMP="$(mktemp -d)"; mkdir -p "$TMP/.claude/hooks" "$TMP/.claude/rules"
cp "$HOOKS/require-status-sync.sh" "$TMP/.claude/hooks/"; cp "$ROOT/.claude/rules/00-core.md" "$TMP/.claude/rules/"
out="$(printf '{}' | CLAUDE_PROJECT_DIR="$TMP" "$SA")"; check "subagent-start: standalone exits 0" 0 "$?"
check "subagent-start: standalone emits nothing (rules load natively — no double-pay)" "" "$out"
rm -rf "$TMP"
NOH="$(mktemp -d)"; printf '{}' | CLAUDE_PROJECT_DIR="$NOH" "$SA" >/dev/null; check "subagent-start: unlocatable harness fails open" 0 "$?"; rm -rf "$NOH"
# The shared emitter also fixed session-start's no-jq fallback, which embedded raw newlines.
TMP="$(mktemp -d)"; "${GIT[@]}" -C "$TMP" init -q
NOJQ="$(mktemp -d)"
for b in bash sh env cat grep sed head tr dirname ln cp readlink pwd mkdir awk; do
  p="$(command -v "$b" 2>/dev/null || true)"
  if [ -n "$p" ]; then ln -s "$p" "$NOJQ/$b" 2>/dev/null || true; fi
done
out="$(PATH="$NOJQ" CLAUDE_PROJECT_DIR="$TMP" CLAUDE_PLUGIN_ROOT="$ROOT/.claude" "$HOOKS/session-start.sh")"
printf '%s' "$out" | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null; check "session-start: no-jq plugin-mode output is valid JSON" 0 "$?"
rm -rf "$NOJQ" "$TMP"

echo "== post-compact.sh (PostCompact: restate loop state) =="
PC="$HOOKS/post-compact.sh"
TMP="$(mktemp -d)"; "${GIT[@]}" -C "$TMP" init -q
mkdir -p "$TMP/docs"; printf 'x\n' > "$TMP/a.py"
"${GIT[@]}" -C "$TMP" add -A >/dev/null; "${GIT[@]}" -C "$TMP" commit -qm init
"${GIT[@]}" -C "$TMP" checkout -q -b feature/PROJ-1-x
out="$(printf '{}' | CLAUDE_PROJECT_DIR="$TMP" "$PC")"; check "exits 0" 0 "$?"
contains "reports the branch" "feature/PROJ-1-x" "$out"
contains "reports STATUS state" "docs/STATUS.md" "$out"
contains "reports missing review verdicts" "/review has not run" "$out"
contains "emits PostCompact additionalContext" "additionalContext" "$out"
printf '{}' | CLAUDE_PROJECT_DIR="$(mktemp -d)" "$PC" >/dev/null; check "non-repo: exits 0" 0 "$?"
rm -rf "$TMP"

echo "== subagent-verdict.sh (SubagentStop: ADR-0005 at the boundary) =="
# The SubagentStop payload: transcript_path is the PARENT session's transcript
# (never the reviewer's); agent_transcript_path is the subagent's own; and
# last_assistant_message is its final text, the authoritative source because
# the transcript file may lag it. stop_hook_active is true once a stop hook has
# already sent the subagent back this turn.
SV="$HOOKS/subagent-verdict.sh"
SVT="$(mktemp -d)"
SV_PARENT="$SVT/parent.jsonl"
printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"text","text":"Both reviewers are still running; I will gate their verdicts when they land."}]}}' > "$SV_PARENT"
sv_payload() { # <last_assistant_message|""> [extra JSON object merged in]
  local extra="${2:-}"; [ -n "$extra" ] || extra='{}'
  jq -cn --arg parent "$SV_PARENT" --arg last "$1" --argjson extra "$extra" \
    '{hook_event_name:"SubagentStop",agent_type:"code-reviewer",stop_hook_active:false,transcript_path:$parent}
     + (if $last=="" then {} else {last_assistant_message:$last} end) + $extra'
}
sv_run() { CLAUDE_PLUGIN_ROOT='' CLAUDE_PROJECT_DIR="$ROOT" "$SV"; }
sv_blocks() { # <desc> <stdout> -- a block is top-level decision=block with a reason
  local d; d="$(printf '%s' "$2" | jq -r 'select(.decision=="block" and (.reason|length)>0) | "block"' 2>/dev/null)"
  if [ "$d" = "block" ]; then PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"
  else FAIL=$((FAIL + 1)); printf '  FAIL %s (expected a block, got: %s)\n' "$1" "${2:-<no output>}"; fi
}
sv_allows() { # <desc> <stdout> -- no decision at all means the stop proceeds
  if [ -z "$2" ]; then PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"
  else FAIL=$((FAIL + 1)); printf '  FAIL %s (expected no output, got: %s)\n' "$1" "$2"; fi
}
SV_APPROVE='Review done.

```json
{"verdict":"approve","summary":"ok","findings":[{"severity":"LOW","path":"a.py","line":1,"category":"style","issue":"i","fix":"f"}]}
```'
SV_REQUEST='Found one.

```json
{"verdict":"request_changes","summary":"no","findings":[{"severity":"HIGH","path":"a.py","line":1,"category":"correctness","issue":"i","fix":"f"}]}
```'
SV_CRITICAL='```json
{"verdict":"approve","summary":"ok","findings":[{"severity":"CRITICAL","path":"a.py","line":1,"category":"correctness","issue":"i","fix":"f"}]}
```'
SV_OFF_SCHEMA='```json
{"verdict":"approve","summary":"ok","findings":[{"severity":"BLOCKER","path":"a.py","line":1,"category":"correctness","issue":"i","fix":"f"}]}
```'
SV_PROSE='Looks good to me, ship it.'
SV_TWO='```json
{"verdict":"approve","summary":"a","findings":[]}
```
and
```json
{"verdict":"approve","summary":"b","findings":[]}
```'
out="$(sv_payload "$SV_APPROVE" | sv_run)"; check "approve in last_assistant_message: exit 0" 0 "$?"
sv_allows "a valid approve verdict passes (parent transcript ends in prose and is never read)" "$out"
out="$(sv_payload "$SV_REQUEST" | sv_run)"; check "request_changes: exit 0" 0 "$?"
sv_allows "a well-formed request_changes is the reviewer doing its job: not sent back" "$out"
# A blocking finding or an off-schema severity is checker exit 1, like a
# request_changes; the hook cannot tell them apart without a second parser, so
# the reviewer stops and the downstream gate -- same checker, same text -- is red.
out="$(sv_payload "$SV_CRITICAL" | sv_run)"; sv_allows "approve carrying a CRITICAL finding: passes the hook (checker exit 1)" "$out"
printf '%s' "$SV_CRITICAL" | bash "$CR" >/dev/null 2>&1; check "...and the downstream gate still rejects it" 1 "$?"
out="$(sv_payload "$SV_OFF_SCHEMA" | sv_run)"; sv_allows "off-schema severity: passes the hook (checker exit 1)" "$out"
printf '%s' "$SV_OFF_SCHEMA" | bash "$CR" >/dev/null 2>&1; check "...and the downstream gate still rejects it" 1 "$?"
out="$(sv_payload "$SV_PROSE" | sv_run)"; check "prose instead of a verdict: exit 0 (the decision is in the JSON)" 0 "$?"
sv_blocks "prose instead of a verdict: blocks" "$out"
contains "block cites ADR-0005" "ADR-0005" "$out"
out="$(sv_payload "$SV_TWO" | sv_run)"; sv_blocks "two fenced blocks (ambiguous): blocks" "$out"
# last_assistant_message absent: fall back to the subagent's own transcript.
SV_AGENT="$SVT/agent.jsonl"
jq -cn --arg t "$SV_APPROVE" '{type:"assistant",message:{content:[{type:"text",text:$t}]}}' > "$SV_AGENT"
out="$(sv_payload "" "$(jq -cn --arg p "$SV_AGENT" '{agent_transcript_path:$p}')" | sv_run)"; check "agent transcript fallback: exit 0" 0 "$?"
sv_allows "falls back to agent_transcript_path, not the parent" "$out"
jq -cn --arg t "$SV_PROSE" '{type:"assistant",message:{content:[{type:"text",text:$t}]}}' >> "$SV_AGENT"
out="$(sv_payload "" "$(jq -cn --arg p "$SV_AGENT" '{agent_transcript_path:$p}')" | sv_run)"
sv_blocks "malformed last text in the agent transcript: blocks" "$out"
# Fails OPEN when it cannot read the reviewer's output -- /review still runs the real gate.
out="$(sv_payload "" | sv_run)"; check "only transcript_path (the parent): exit 0" 0 "$?"
sv_allows "never grades the parent transcript" "$out"
out="$(sv_payload "" '{"agent_transcript_path":"/nonexistent/x.jsonl"}' | sv_run)"; check "unreadable agent transcript: exit 0" 0 "$?"
sv_allows "unreadable agent transcript: fails open" "$out"
printf '{}' | sv_run >/dev/null; check "empty object: fails open" 0 "$?"
out="$(sv_payload "$SV_PROSE" | CLAUDE_PLUGIN_ROOT='' CLAUDE_PROJECT_DIR="$SVT" "$SV")"; check "checker not locatable: exit 0" 0 "$?"
sv_allows "checker not locatable: fails open" "$out"
# Sent back once already this turn: do not loop forever.
out="$(sv_payload "$SV_PROSE" '{"stop_hook_active":true}' | sv_run)"; check "stop_hook_active with malformed output: exit 0" 0 "$?"
sv_allows "stop_hook_active: does not block a second time" "$out"
rm -rf "$SVT"

echo "== release-notes.sh (the release gate) =="
# v1.0.0 was released by hand, and the hand-assembly showed why that is a bad
# idea: `git tag -F` strips '#' lines by default, so the annotation lost every
# markdown heading and a breaking change read like a feature. The workflow reads
# CHANGELOG.md instead — so the extractor is now load-bearing and gets tested.
RN="$ROOT/.github/scripts/release-notes.sh"
out="$(bash "$RN" 1.0.0 "$ROOT/CHANGELOG.md")"; check "extracts an existing version" 0 "$?"
contains "keeps the section headings git would have stripped" "### Added" "$out"
contains "leads with the breaking change" "Breaking" "$out"
printf '%s' "$out" | grep -q "Gates as Code"; check "stops at the next version (no bleed)" 1 "$?"
bash "$RN" 9.9.9 "$ROOT/CHANGELOG.md" >/dev/null 2>&1; check "absent version fails closed" 1 "$?"
bash "$RN" "" "$ROOT/CHANGELOG.md" >/dev/null 2>&1; check "empty version fails closed" 1 "$?"
bash "$RN" 1.0.0 /nonexistent/CHANGELOG.md >/dev/null 2>&1; check "missing changelog fails closed" 1 "$?"
# A whitespace-only section must not publish as a release with an empty body.
TMP="$(mktemp -d)"; printf '# Changelog\n\n## [2.0.0] - x\n\n\n## [1.0.0] - y\n\nreal notes\n' > "$TMP/CH.md"
bash "$RN" 2.0.0 "$TMP/CH.md" >/dev/null 2>&1; check "whitespace-only section fails closed" 1 "$?"
# A version must match literally: 1.0.0 must never select a 1x0x0 section. The
# first implementation built a dynamic regex, which mawk and gawk disagree about.
printf '# Changelog\n\n## [1x0x0] - x\n\nwrong section\n' > "$TMP/CH2.md"
bash "$RN" 1.0.0 "$TMP/CH2.md" >/dev/null 2>&1; check "version matches literally, not as a regex" 1 "$?"
rm -rf "$TMP"

echo "== hook wiring (every command survives a path with a space) =="
# Claude Code puts the plugin root or the project dir into each hook command and hands it to a
# shell. Under an unquoted root, "/Users/a b/..." splits into words: the shell reports "not
# found" (126/127) and the gate silently never runs. Run every wired command from such a path.
SP="$(mktemp -d)/with space"; mkdir -p "$SP"; cp -R "$ROOT/.claude" "$SP/.claude"; "${GIT[@]}" -C "$SP" init -q
unrunnable() { # <json file>: prints "ran:" per command started, and each command the shell could not start
  python3 -c 'import json,sys
for es in json.load(open(sys.argv[1]))["hooks"].values():
    for e in es:
        for h in e["hooks"]: print(h["command"])' "$1" | while IFS= read -r cmd; do
    printf 'ran:\n'
    (cd "$SP" && printf '{}' | CLAUDE_PLUGIN_ROOT="$SP/.claude" CLAUDE_PROJECT_DIR="$SP" bash -c "$cmd" >/dev/null 2>&1)
    case $? in 126 | 127) printf '%s\n' "$cmd" ;; esac
  done
}
space_run() { # <json file>: sets ran (commands started), bad_cmds (could not start) and rc
  local res; res="$(unrunnable "$1")"
  ran="$(printf '%s\n' "$res" | grep -c '^ran:$')"
  bad_cmds="$(printf '%s\n' "$res" | grep -v '^ran:$' | grep . || true)"
  if [ "$ran" -ge 10 ] && [ -z "$bad_cmds" ]; then rc=0; else rc=1; fi
}
space_run "$SP/.claude/hooks/hooks.json"
check "hooks.json: every command runs from a plugin root with a space (ran $ran)${bad_cmds:+ (not: $bad_cmds)}" 0 "$rc"
space_run "$SP/.claude/settings.json"
check "settings.json: every command runs from a project dir with a space (ran $ran)${bad_cmds:+ (not: $bad_cmds)}" 0 "$rc"
rm -rf "$(dirname "$SP")"

echo "== harness_lint.py (the linter is itself a gate) =="
# A linter with no failing-case test is an unverified gate: it would still print
# "OK" if a check silently stopped firing. Each case copies the real tree, breaks
# exactly one thing, and asserts the linter catches it (NONNA_LINT_ROOT retargets).
LINT="$ROOT/tests/harness_lint.py"
lint_fixture() { # -> echoes a fresh copy of the harness
  local d; d="$(mktemp -d)"
  cp -R "$ROOT/.claude" "$ROOT/docs" "$ROOT/tests" "$ROOT/stacks" "$ROOT/.github" \
        "$ROOT/.claude-plugin" "$ROOT/hosts" "$d/" 2>/dev/null
  cp "$ROOT"/*.md "$ROOT"/LICENSE "$d/" 2>/dev/null
  printf '%s' "$d"
}
FX="$(lint_fixture)"
NONNA_LINT_ROOT="$FX" python3 "$LINT" >/dev/null 2>&1; check "lint: an unmodified copy passes (fixture is faithful)" 0 "$?"
rm -rf "$FX"

# model tier: fable is a real Claude Code model and must be accepted; junk must not.
FX="$(lint_fixture)"
sed -i 's/^model: haiku$/model: fable/' "$FX/.claude/agents/explorer.md"
NONNA_LINT_ROOT="$FX" python3 "$LINT" >/dev/null 2>&1; check "lint: accepts model 'fable'" 0 "$?"
sed -i 's/^model: fable$/model: gpt-4/' "$FX/.claude/agents/explorer.md"
out="$(NONNA_LINT_ROOT="$FX" python3 "$LINT" 2>&1)"; check "lint: rejects an unknown model tier" 1 "$?"
contains "lint: names the offending model" "gpt-4" "$out"
rm -rf "$FX"

# slash references: a routing pointer to a command that does not exist is a dead end.
FX="$(lint_fixture)"
printf '\nSee `/nonexistent-command` for details.\n' >> "$FX/.claude/rules/dev-process.md"
out="$(NONNA_LINT_ROOT="$FX" python3 "$LINT" 2>&1)"; check "lint: blocks a slash ref that is not a command or skill" 1 "$?"
contains "lint: names the unresolved slash reference" "/nonexistent-command" "$out"
rm -rf "$FX"

# skills are invocable as /name, so a skill reference must NOT be reported dead.
FX="$(lint_fixture)"
printf '\nSee `/security-review` and `/tdd-workflow` for details.\n' >> "$FX/.claude/rules/testing.md"
NONNA_LINT_ROOT="$FX" python3 "$LINT" >/dev/null 2>&1; check "lint: a skill name IS a valid slash reference" 0 "$?"
rm -rf "$FX"

# the token budget must actually bite (it is the mechanism locking the compression in).
FX="$(lint_fixture)"
python3 -c "
import sys; p=sys.argv[1]
open(p,'a').write('\n' + ('filler ' * 5000) + '\n')" "$FX/.claude/rules/sync.md"
out="$(NONNA_LINT_ROOT="$FX" python3 "$LINT" 2>&1)"; check "lint: always-on word budget blocks bloat" 1 "$?"
contains "lint: names the rule budget" "word budget" "$out"
rm -rf "$FX"

# allowed-tools completeness: /release shipped granting `git tag` but not `git push`
# while its own step said "Push the tag" — a command that cannot run its own steps.
FX="$(lint_fixture)"
sed -i 's/, Bash(git push origin v:\*)//' "$FX/.claude/skills/release/SKILL.md"
out="$(NONNA_LINT_ROOT="$FX" python3 "$LINT" 2>&1)"; check "lint: blocks a command that cannot run its own git step" 1 "$?"
contains "lint: names the ungranted git verb" "Bash(git push" "$out"
rm -rf "$FX"
# A negated mention ("Do not reset --hard") must not be read as a step the command runs.
FX="$(lint_fixture)"
printf '\nDo not use `git reset --hard` here.\n' >> "$FX/.claude/skills/rollback/SKILL.md"
NONNA_LINT_ROOT="$FX" python3 "$LINT" >/dev/null 2>&1; check "lint: a negated git mention is not an under-grant" 0 "$?"
rm -rf "$FX"

# Hook wiring equivalence: settings.json and hooks.json register the same gates
# with no shared source. A gate added to one and forgotten in the other is live
# standalone and absent under a plugin install — the asymmetry ADR-0007 is about.
FX="$(lint_fixture)"
python3 - "$FX/.claude/hooks/hooks.json" <<'PY'
import json, sys
p = sys.argv[1]; cfg = json.load(open(p))
cfg["hooks"]["PreToolUse"][0]["hooks"].pop()          # drop secret-scan from the plugin wiring only
json.dump(cfg, open(p, "w"), indent=2)
PY
out="$(NONNA_LINT_ROOT="$FX" python3 "$LINT" 2>&1)"; check "lint: blocks a gate wired in settings.json but not hooks.json" 1 "$?"
contains "lint: names the desynced event" "hook wiring: 'PreToolUse' differs" "$out"
rm -rf "$FX"
FX="$(lint_fixture)"
python3 - "$FX/.claude/hooks/hooks.json" <<'PY'
import json, sys
p = sys.argv[1]; cfg = json.load(open(p))
cfg["hooks"]["SessionEnd"] = [{"hooks": [{"type": "command", "command": "\"${CLAUDE_PLUGIN_ROOT}\"/hooks/format.sh"}]}]
json.dump(cfg, open(p, "w"), indent=2)
PY
out="$(NONNA_LINT_ROOT="$FX" python3 "$LINT" 2>&1)"; check "lint: blocks an event present in only one wiring" 1 "$?"
contains "lint: names the one-sided event" "hook wiring: 'SessionEnd' is in hooks.json but not settings.json" "$out"
rm -rf "$FX"

# Descriptions load on every turn and had no budget until now; prove it bites.
FX="$(lint_fixture)"
python3 -c "
import sys,re; p=sys.argv[1]; t=open(p).read()
open(p,'w').write(re.sub(r'^description: .*\$', 'description: ' + 'x'*4000, t, count=1, flags=re.M))" "$FX/.claude/skills/refactoring/SKILL.md"
out="$(NONNA_LINT_ROOT="$FX" python3 "$LINT" 2>&1)"; check "lint: description budget blocks metadata creep" 1 "$?"
contains "lint: says descriptions load every turn" "every turn" "$out"
rm -rf "$FX"
# skills: preload is what makes depth outside an always-on rule deterministic --
# a name that does not resolve silently removes the depth it was trusted to carry.
FX="$(lint_fixture)"
sed -i 's/^skills: tdd-workflow$/skills: no-such-skill/' "$FX/.claude/agents/test-engineer.md"
out="$(NONNA_LINT_ROOT="$FX" python3 "$LINT" 2>&1)"; check "lint: blocks an agent preloading a nonexistent skill" 1 "$?"
contains "lint: names the unresolved skill" "no-such-skill" "$out"
rm -rf "$FX"
FX="$(lint_fixture)"
sed -i 's/^effort: low$/effort: turbo/' "$FX/.claude/agents/explorer.md"
out="$(NONNA_LINT_ROOT="$FX" python3 "$LINT" 2>&1)"; check "lint: blocks an invalid effort level" 1 "$?"
rm -rf "$FX"
# 00-core.md rides SessionStart additionalContext, which TRUNCATES at 10k rather
# than erroring -- an overrun would silently drop the tail for plugin installs.
FX="$(lint_fixture)"
python3 -c "
import sys; open(sys.argv[1],'a').write('\n' + ('padding ' * 1500))" "$FX/.claude/rules/00-core.md"
out="$(NONNA_LINT_ROOT="$FX" python3 "$LINT" 2>&1)"; check "lint: blocks a 00-core.md too big for the SessionStart channel" 1 "$?"
contains "lint: cites the truncation risk" "truncates" "$out"
rm -rf "$FX"

# disable-model-invocation on a side-effecting workflow is a SAFETY assertion, not
# a token one: without it the model can decide on its own to promote to production,
# which rules/safety.md reserves for a human.
FX="$(lint_fixture)"
sed -i '/^disable-model-invocation: true$/d' "$FX/.claude/skills/release/SKILL.md"
out="$(NONNA_LINT_ROOT="$FX" python3 "$LINT" 2>&1)"; check "lint: blocks /release the model could self-invoke" 1 "$?"
contains "lint: ties it to the human-approval rule" "safety.md" "$out"
rm -rf "$FX"

# review-gate wiring (ADR-0005) must stay pinned: unwiring it is the defect it guards.
FX="$(lint_fixture)"
sed -i 's/check-review\.sh/checkreview.sh/g' "$FX/.claude/skills/ship/SKILL.md"
out="$(NONNA_LINT_ROOT="$FX" python3 "$LINT" 2>&1)"; check "lint: blocks /ship that no longer wires check-review.sh" 1 "$?"
contains "lint: cites ADR-0005 on unwiring" "ADR-0005" "$out"
rm -rf "$FX"

# The ladder lives twice by design — always-on rungs in 00-core.md, on-demand depth in
# the lean skill — so the seven rung keywords are pinned in both copies (ADR-0008).
FX="$(lint_fixture)"
sed -i 's/\*\*stdlib\*\*/standard library/' "$FX/.claude/rules/00-core.md"
out="$(NONNA_LINT_ROOT="$FX" python3 "$LINT" 2>&1)"; check "lint: blocks a rung dropped from the always-on ladder" 1 "$?"
contains "lint: names the missing rung" "stdlib" "$out"
rm -rf "$FX"
FX="$(lint_fixture)"
sed -i 's/YAGNI/you are not going to need it/g' "$FX/.claude/skills/lean/SKILL.md"
out="$(NONNA_LINT_ROOT="$FX" python3 "$LINT" 2>&1)"; check "lint: blocks a rung dropped from the lean skill" 1 "$?"
contains "lint: names the drifted copy" "skills/lean/SKILL.md" "$out"
rm -rf "$FX"
# The debt gate is only a gate if /review runs it — ADR-0005's wiring lesson, applied again.
FX="$(lint_fixture)"
sed -i 's/check-debt\.sh/checkdebt.sh/g' "$FX/.claude/skills/review/SKILL.md"
out="$(NONNA_LINT_ROOT="$FX" python3 "$LINT" 2>&1)"; check "lint: blocks /review that no longer wires check-debt.sh" 1 "$?"
contains "lint: cites ADR-0008 on unwiring the debt gate" "ADR-0008" "$out"
rm -rf "$FX"
# Every host's rules file is generated from 00-core.md; a hand edit or a stale copy is drift.
FX="$(lint_fixture)"
sed -i 's/^## Never$/## Never\n\n- One more never./' "$FX/.claude/rules/00-core.md"
out="$(NONNA_LINT_ROOT="$FX" python3 "$LINT" 2>&1)"; check "lint: blocks host rule files that drifted from 00-core.md" 1 "$?"
contains "lint: names the stale host file" "hosts/AGENTS.md" "$out"
rm -rf "$FX"
# Proportional review is only proportional if /review asks the script, not the model.
FX="$(lint_fixture)"
sed -i 's/review-lanes\.sh/reviewlanes.sh/g' "$FX/.claude/skills/review/SKILL.md"
out="$(NONNA_LINT_ROOT="$FX" python3 "$LINT" 2>&1)"; check "lint: blocks /review that no longer wires review-lanes.sh" 1 "$?"
contains "lint: cites ADR-0009 on unwiring the review lanes" "ADR-0009" "$out"
rm -rf "$FX"
# Ideas borrowed from another project are credited in README.md and nowhere else; the
# harness carries no external brand. The term is split so this file cannot trip the check.
FX="$(lint_fixture)"
printf '\nSee also pony%s.\n' 'tail' >> "$FX/.claude/skills/lean/SKILL.md"
out="$(NONNA_LINT_ROOT="$FX" python3 "$LINT" 2>&1)"; check "lint: blocks an external project name outside README.md" 1 "$?"
contains "lint: names the file carrying the external name" "skills/lean/SKILL.md" "$out"
contains "lint: says where credit belongs" "README.md" "$out"
rm -rf "$FX"
FX="$(lint_fixture)"
printf '\nCredit: pony%s.\n' 'tail' >> "$FX/README.md"
NONNA_LINT_ROOT="$FX" python3 "$LINT" >/dev/null 2>&1; check "lint: README.md may credit the external project" 0 "$?"
rm -rf "$FX"

# The review loop must not un-size what the ladder sized: a MEDIUM that only adds code is
# answered with a debt marker, and a finding whose fix adds code names a failing input.
FX="$(lint_fixture)"
sed -i 's/names a failing case/is convenient/' "$FX/.claude/rules/dev-process.md"
out="$(NONNA_LINT_ROOT="$FX" python3 "$LINT" 2>&1)"; check "lint: blocks dev-process losing the MEDIUM-names-a-failing-case rule" 1 "$?"
contains "lint: names dev-process for the review-inflation rule" "missing 'names a failing case'" "$out"
rm -rf "$FX"
FX="$(lint_fixture)"
sed -i 's/Does the fix add code?/Is it nice?/' "$FX/.claude/skills/code-review/references/severity-rubric.md"
out="$(NONNA_LINT_ROOT="$FX" python3 "$LINT" 2>&1)"; check "lint: blocks the rubric losing the adds-code calibration" 1 "$?"
contains "lint: names the rubric for the review-inflation rule" "missing 'Does the fix add code?'" "$out"
rm -rf "$FX"

# Hook commands quote their root. Claude Code puts the path into a shell command, and an
# unquoted path with a space splits into words: the script is never found and the gate never runs.
set_hook_cmd() { # <json file> <event> <command>: rewrite that event's first hook command
  python3 - "$@" <<'PY'
import json, sys
path, event, cmd = sys.argv[1:4]
cfg = json.load(open(path, encoding="utf-8"))
cfg["hooks"][event][0]["hooks"][0]["command"] = cmd
json.dump(cfg, open(path, "w", encoding="utf-8"), indent=2)
PY
}
FX="$(lint_fixture)"
set_hook_cmd "$FX/.claude/hooks/hooks.json" PostToolUse '${CLAUDE_PLUGIN_ROOT}/hooks/format.sh'
out="$(NONNA_LINT_ROOT="$FX" python3 "$LINT" 2>&1)"; check "lint: blocks an unquoted plugin root in hooks.json" 1 "$?"
contains "lint: says to quote the plugin root" '"${CLAUDE_PLUGIN_ROOT}"/' "$out"
rm -rf "$FX"
FX="$(lint_fixture)"
set_hook_cmd "$FX/.claude/settings.json" PostToolUse '$CLAUDE_PROJECT_DIR/.claude/hooks/format.sh'
out="$(NONNA_LINT_ROOT="$FX" python3 "$LINT" 2>&1)"; check "lint: blocks an unquoted project dir in settings.json" 1 "$?"
contains "lint: says to quote the project dir" '"$CLAUDE_PROJECT_DIR"/' "$out"
rm -rf "$FX"
# The quoted form must not blind the wired-script checks: a script that is gone is still reported.
FX="$(lint_fixture)"
rm "$FX/.claude/hooks/format.sh"
out="$(NONNA_LINT_ROOT="$FX" python3 "$LINT" 2>&1)"; check "lint: blocks a wired hook script that is missing" 1 "$?"
contains "lint: settings.json names the missing script" "settings.json: wired hook missing on disk: .claude/hooks/format.sh" "$out"
contains "lint: hooks.json names the missing script" "hooks.json: wired hook missing on disk: hooks/format.sh" "$out"
rm -rf "$FX"
# Nothing may follow the script: `|| true` turns the gate's block (exit 2) into a pass, in one mode only.
FX="$(lint_fixture)"
set_hook_cmd "$FX/.claude/hooks/hooks.json" PreToolUse '"${CLAUDE_PLUGIN_ROOT}"/hooks/guard-branch.sh || true'
out="$(NONNA_LINT_ROOT="$FX" python3 "$LINT" 2>&1)"; check "lint: blocks a tail that turns a plugin gate's block into a pass" 1 "$?"
contains "lint: names the tailed hooks.json command" "PreToolUse hook '\"\${CLAUDE_PLUGIN_ROOT}\"/hooks/guard-branch.sh || true'" "$out"
rm -rf "$FX"
FX="$(lint_fixture)"
set_hook_cmd "$FX/.claude/settings.json" PreToolUse '"$CLAUDE_PROJECT_DIR"/.claude/hooks/guard-branch.sh; exit 0'
out="$(NONNA_LINT_ROOT="$FX" python3 "$LINT" 2>&1)"; check "lint: blocks a tail on a settings.json gate" 1 "$?"
contains "lint: names the tailed settings.json command" "PreToolUse hook '\"\$CLAUDE_PROJECT_DIR\"/.claude/hooks/guard-branch.sh; exit 0'" "$out"
rm -rf "$FX"
FX="$(lint_fixture)"
set_hook_cmd "$FX/.claude/hooks/hooks.json" Stop '"${CLAUDE_PLUGIN_ROOT}"/hooks/stop-dod.sh "${CLAUDE_PLUGIN_DATA}"'
out="$(NONNA_LINT_ROOT="$FX" python3 "$LINT" 2>&1)"; check "lint: only SessionStart may take the plugin data dir" 1 "$?"
contains "lint: names the event given the data dir" "Stop hook" "$out"
rm -rf "$FX"
# Keys other than the command decide whether a hook can block at all: async cannot, a timeout lets
# the action through, and a non-command type hands the decision to a model. Each is refused.
set_hook_key() { # <json file> <event> <key> <json value>: set a key on that event's first hook
  python3 - "$@" <<'PY'
import json, sys
path, event, key, value = sys.argv[1:5]
cfg = json.load(open(path, encoding="utf-8"))
cfg["hooks"][event][0]["hooks"][0][key] = json.loads(value)
json.dump(cfg, open(path, "w", encoding="utf-8"), indent=2)
PY
}
FX="$(lint_fixture)"
set_hook_key "$FX/.claude/hooks/hooks.json" PreToolUse async true
out="$(NONNA_LINT_ROOT="$FX" python3 "$LINT" 2>&1)"; check "lint: blocks an async gate (it cannot block)" 1 "$?"
contains "lint: names the async key" "has keys ['async']" "$out"
rm -rf "$FX"
FX="$(lint_fixture)"
set_hook_key "$FX/.claude/hooks/hooks.json" PreToolUse timeout 0.001
out="$(NONNA_LINT_ROOT="$FX" python3 "$LINT" 2>&1)"; check "lint: blocks a gate timeout short enough to let everything through" 1 "$?"
contains "lint: names the short timeout" "timeout 0.001 is under 10s" "$out"
rm -rf "$FX"
FX="$(lint_fixture)"
set_hook_key "$FX/.claude/hooks/hooks.json" PreToolUse type '"prompt"'
out="$(NONNA_LINT_ROOT="$FX" python3 "$LINT" 2>&1)"; check "lint: blocks a gate handed to a model" 1 "$?"
contains "lint: says a gate is a command" 'must be type "command"' "$out"
rm -rf "$FX"
FX="$(lint_fixture)"
set_hook_key "$FX/.claude/hooks/hooks.json" Stop timeout 30
out="$(NONNA_LINT_ROOT="$FX" python3 "$LINT" 2>&1)"; check "lint: blocks a gate timed differently in the two install modes" 1 "$?"
contains "lint: names the event whose timeout differs" "hook wiring: 'Stop' differs" "$out"
rm -rf "$FX"
# One settings key turns every gate off at once.
FX="$(lint_fixture)"
python3 -c 'import json,sys; p=sys.argv[1]; c=json.load(open(p)); c["disableAllHooks"]=True; json.dump(c,open(p,"w"),indent=2)' "$FX/.claude/settings.json"
out="$(NONNA_LINT_ROOT="$FX" python3 "$LINT" 2>&1)"; check "lint: blocks disableAllHooks in settings.json" 1 "$?"
contains "lint: names the kill switch" "disableAllHooks is set" "$out"
rm -rf "$FX"
# Arguments after the script (SessionStart gets the plugin data dir) are not part of the gate's identity.
FX="$(lint_fixture)"
set_hook_cmd "$FX/.claude/settings.json" Stop '"$CLAUDE_PROJECT_DIR"/.claude/hooks/format.sh'
out="$(NONNA_LINT_ROOT="$FX" python3 "$LINT" 2>&1)"; check "lint: blocks a gate wired differently in the two install modes" 1 "$?"
contains "lint: names the event that differs" "hook wiring: 'Stop' differs" "$out"
rm -rf "$FX"

printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
