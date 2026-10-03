#!/usr/bin/env bash
# Scratch (#45, never merged): can a command switch how Git Bash reads a CR partway through? And the CR
# checks of tests/run.sh (asking bash, a command only), on Git Bash.
set -u
exec </dev/null
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; HOOKS="$ROOT/.claude/hooks"; SS="$HOOKS/secret-scan.sh"; GB="$HOOKS/guard-branch.sh"
say() { printf 'probe %s: %s\n' "$1" "$2"; }
show() { od -An -c | tr -s ' ' | tr '\n' ' '; }
CR="$(printf '\r')"; LF='
'
say E16 "BASH_VERSINFO[5]=${BASH_VERSINFO[5]} OSTYPE=$OSTYPE MSYSTEM=${MSYSTEM:-} uname=$(uname -s) BASH=$BASH"
say E16 "igncr as bash starts: $(bash -c 'shopt -o igncr' 2>&1)"
say E16 "default, set +o igncr, set -o igncr (a line each): $(bash -c "printf '<%s>' a${CR}b${LF}set +o igncr 2>/dev/null${LF}printf '<%s>' a${CR}b${LF}set -o igncr 2>/dev/null${LF}printf '<%s>' a${CR}b" 2>&1 | show)"
say E16 "default, shopt -uo igncr, shopt -so igncr (a line each): $(bash -c "printf '<%s>' a${CR}b${LF}shopt -uo igncr 2>/dev/null${LF}printf '<%s>' a${CR}b${LF}shopt -so igncr 2>/dev/null${LF}printf '<%s>' a${CR}b" 2>&1 | show)"
say E16 "set +o igncr, then on the same line: $(bash -c "set +o igncr; printf '<%s>' a${CR}b" 2>&1 | show)"
say E16 "a CR that ends a line: $(bash -c "printf '<%s>' a${CR}${LF}" 2>&1 | show)"
say E16 "SHELLOPTS=igncr from the environment: $(env SHELLOPTS=igncr bash -c "printf '<%s>' a${CR}b" 2>&1 | show)"
say E16 "a script file, set +o igncr then a CR: $(d="$(mktemp -d)"; printf 'set +o igncr\nprintf "<%%s>" a\rb\n' > "$d/s.sh"; bash "$d/s.sh" 2>&1 | show; rm -rf "$d")"
say E16 "eval of a string with a CR: $(bash -c "eval \"printf '<%s>' a\$(printf '\\\\r')b\"" 2>&1 | show)"
say E16 "source of a file with a CR: $(d="$(mktemp -d)"; printf 'printf "<%%s>" a\rb\n' > "$d/s.sh"; bash -c ". '$d/s.sh'" 2>&1 | show; rm -rf "$d")"
say E16 "json.sh asks: $(bash -c '. "$1/lib/json.sh"; _nonna_cr_mode' _ "$HOOKS")"

# The checks, as tests/run.sh has them.
pass=0; fail=0
check() { if [ "$2" = "$3" ]; then pass=$((pass + 1)); say ok "$1"; else fail=$((fail + 1)); say FAIL "$1 (want $(printf %q "$2"), got $(printf %q "$3"))"; fi; }
contains() { case "$3" in *"$2"*) pass=$((pass + 1)); say ok "$1" ;; *) fail=$((fail + 1)); say FAIL "$1 (missing: $2)" ;; esac; }
eval "$(sed -n '/^link() {/,/^}/p' "$ROOT/tests/run.sh")"
eval "$(sed -n '/^cr_bytes() {/,/^esac/p' "$ROOT/tests/run.sh")"
say E16 "the suite measures CR_MODE=$CR_MODE"
eval "$(sed -n "/^# A command is read as this platform.s bash will run it/,/^done. _ \"\$HOOKS\" . python3 -c \"\$CR_PROP\" check)\"/p" "$ROOT/tests/run.sh")"
LNK="$(mktemp -d)"; printf 'K=1\n' > "$LNK/.env"
eval "$(sed -n '/^link .env "\$LNK\/\$(printf/,/^printf .*name ending in a CR/p' "$ROOT/tests/run.sh")"
say E16 "the name with a CR, as ls shows it: $(ls -la "$LNK" | tail -n +2 | tr '\n' '|')"
rm -rf "$LNK"
TMP="$(mktemp -d)"; git -C "$TMP" init -q; git -C "$TMP" checkout -qb feature/x
eval "$(sed -n '/^gbp() {/p' "$ROOT/tests/run.sh")"
eval "$(sed -n '/^crv() {/,/^}/p' "$ROOT/tests/run.sh")"
eval "$(sed -n '/^crv "a CR before #, as bash reads it/,/^crv "...and ma<CR>in is main"/p' "$ROOT/tests/run.sh")"
CXS=s; CXR="$TMP"; FAKE_OAI="sk-proj-$(printf 'A%.0s' $(seq 1 120))"
eval "$(sed -n "/^cx_event() {/,/^}/p" "$ROOT/tests/run.sh")"; eval "$(sed -n "/^cx_tool() {/,/^}/p" "$ROOT/tests/run.sh")"
eval "$(sed -n '/^cx_patch() {/,/^}/p' "$ROOT/tests/run.sh")"
eval "$(sed -n '/^out="\$(cx_patch .\*\*\* Add File: k.py. "+a/,/the patch keeps its CR/p' "$ROOT/tests/run.sh")"
rc=0; cx_patch '*** Add File: k.py' "+a$(printf '\r')$FAKE_OAI" | (cd "$TMP" && NONNA_HOST=codex "$SS" >/dev/null 2>&1) || rc=$?
check "codex: secret-scan refuses a key behind a CR in a patch line" 2 "$rc"
rm -rf "$TMP"
say E16 "$pass passed, $fail failed"
