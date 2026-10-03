#!/usr/bin/env bash
# Scratch (#45, never merged): what Git Bash's bash, awk and the guards make of a CR, as facts.
set -u
exec </dev/null
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; HOOKS="$ROOT/.claude/hooks"; GB="$HOOKS/guard-branch.sh"; SS="$HOOKS/secret-scan.sh"
say() { printf 'probe %s: %s\n' "$1" "$2"; }
show() { od -An -c | tr -s ' ' | tr '\n' ' '; }
say env "$(uname -s) bash $BASH_VERSION MSYS=${MSYS:-} shellopts=$SHELLOPTS"
# E10. bash: a backslash before a CR and a newline; a CR before #; a CR at a word's end.
say E10 "bash -c 'echo A \\<CR><LF>echo RAN' prints: $(bash -c "$(printf 'echo A \\\r\necho RAN')" 2>&1 | show)"
say E10 "bash -c 'echo A <CR>#; echo RAN' prints: $(bash -c "$(printf 'echo A \r#; echo RAN')" 2>&1 | show)"
say E10 "bash -c 'printf [%%s] --force<CR>' prints: $(bash -c "$(printf 'printf "[%%s]" --force\r')" 2>&1 | show)"
say E10 "a script file with \\<CR><LF>: $(d="$(mktemp -d)"; printf 'echo A \\\r\necho RAN\n' > "$d/s.sh"; bash "$d/s.sh" 2>&1 | show; rm -rf "$d")"
say E10 "bash -o igncr known: $(bash -o igncr -c 'echo yes' 2>&1 | head -n 1)"
# E11. awk: does it keep a CR before a newline?
say E11 "awk lengths of x<CR><LF>y<LF>: $(printf 'x\r\ny\n' | awk '{ printf "%d ", length($0) }')"
say E11 "awk as the guard runs it (LC_ALL=C): $(printf 'x\r\ny\n' | LC_ALL=C awk '{ printf "%d ", length($0) }')"
say E11 "sed keeps the CR: $(printf 'x\r\n' | sed 's/x/y/' | show)"
say E11 "grep sees a CR: $(printf 'x\r\n' | grep -c "$(printf '\r')")"
# E12. The guard on exact input (gbp as tests/run.sh writes it), with a working awk.
TMP="$(mktemp -d)"; git -C "$TMP" init -q; git -C "$TMP" checkout -qb feature/x
eval "$(sed -n '/^gbp() {/p' "$ROOT/tests/run.sh")"
say E12 "git commit -m \\<CR><LF>'git' push --force: $(gbp "$PATH" "$(printf "git commit -m \\\\\r\n'git' push --force origin feature/x")")"
say E12 ": \\<CR><LF>bash .claude/skills/nonna/scripts/x.sh off: $(gbp "$PATH" "$(printf ': \\\r\nbash .claude/skills/nonna/scripts/x.sh off')")"
say E12 "git commit -m \\<LF>'git' push --force (a real continuation): $(gbp "$PATH" "$(printf "git commit -m \\\\\n'git' push --force origin feature/x")")"
say E12 "the same, two commands (LF only): $(gbp "$PATH" "$(printf "git commit -m x\n'git' push --force origin feature/x")")"
# E13. A file whose name ends in a CR, a link to .env: what MSYS and Python see.
LNK="$(mktemp -d)"; printf 'K=1\n' > "$LNK/.env"; (cd "$LNK" && ln -s .env "$(printf 'x\r')")
say E13 "[ -L x<CR> ]: $( (cd "$LNK" && [ -L "$(printf 'x\r')" ]) && echo yes || echo no); cat: $( (cd "$LNK" && cat "$(printf 'x\r')") 2>&1 | head -c 40)"
say E13 "python open('x\\r'): $(cd "$LNK" && python3 -c 'import sys
try: print(repr(open("x\r").read()))
except Exception as e: print(type(e).__name__, e)' 2>&1 | head -c 120)"
say E13 "python listdir: $(cd "$LNK" && python3 -c 'import os; print([n.encode("unicode_escape").decode() for n in os.listdir(".")])')"
say E13 "secret-scan Read x<CR>: exit $(printf '%s' '{"tool_name":"Read","tool_input":{"file_path":"x\r"}}' | CLAUDE_PROJECT_DIR="$LNK" "$SS" >/dev/null 2>&1; echo $?)"
rm -rf "$TMP" "$LNK"
