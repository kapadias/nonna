#!/usr/bin/env bash
# Scratch (#45, never merged): the security re-review's fixes on Git Bash: the mode, OSTYPE, unknown, Codex.
set -u
exec </dev/null
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; HOOKS="$ROOT/.claude/hooks"; GB="$HOOKS/guard-branch.sh"; SS="$HOOKS/secret-scan.sh"
say() { printf 'probe %s: %s\n' "$1" "$2"; }
pass=0; fail=0
check() { if [ "$2" = "$3" ]; then pass=$((pass + 1)); say ok "$1"; else fail=$((fail + 1)); say FAIL "$1 (want $2, got $3)"; fi; }
contains() { case "$3" in *"$2"*) pass=$((pass + 1)); say ok "$1" ;; *) fail=$((fail + 1)); say FAIL "$1 (missing: $2)" ;; esac; }
mode() { bash -c '. "$1/lib/json.sh"; printf %s "$_nonna_cr"' _ "$HOOKS"; }
say E15 "BASH_VERSINFO[5]=${BASH_VERSINFO[5]} mode=$(mode) with OSTYPE=linux-gnu: $(OSTYPE=linux-gnu mode) with OSTYPE=cygwin: $(OSTYPE=cygwin mode)"
eval "$(sed -n '/^DROPS_CR=no/p' "$ROOT/tests/run.sh")"
eval "$(sed -n '/^check "json: where bash drops every CR, so does a field"/,/^check "json: ...nor one of linux-gnu"/p' "$ROOT/tests/run.sh")"
# Codex: an apply_patch whose line holds a CR before a key, read as Codex reads it.
KEY="sk-proj-$(printf 'A%.0s' $(seq 1 120))"
PAY="$(python3 -c 'import json,sys; print(json.dumps({"tool_name":"apply_patch","tool_input":{"command":"*** Begin Patch\n*** Add File: k.py\n+a\r"+sys.argv[1]+"\n*** End Patch"}}))' "$KEY")"
out="$(printf '%s' "$PAY" | bash -c '. "$1/lib/core.sh"; . "$1/lib/host-codex.sh"; _nonna_codex_files' _ "$HOOKS")"
contains "codex: the patch keeps its CR, as this platform reads it" 'a\u000dsk-proj-' "$out"
R="$(mktemp -d)"; git -C "$R" init -q
rc=0; printf '%s' "$PAY" | (cd "$R" && NONNA_HOST=codex "$SS" >/dev/null 2>&1) || rc=$?
check "codex: secret-scan refuses a key behind a CR in a patch line" 2 "$rc"
# The guard still refuses what Git Bash runs, with the mode as it is.
TMP="$(mktemp -d)"; git -C "$TMP" init -q; git -C "$TMP" checkout -qb feature/x
eval "$(sed -n '/^gbp() {/p' "$ROOT/tests/run.sh")"
check "guard: gi<CR>t push, as bash reads it here" "$([ "$DROPS_CR" = yes ] && echo 2 || echo 0)" "$(gbp "$PATH" "$(printf 'gi\rt push --for''ce origin feature/x')")"
check "guard: ...and with OSTYPE=linux-gnu in the environment" "$([ "$DROPS_CR" = yes ] && echo 2 || echo 0)" "$(OSTYPE=linux-gnu gbp "$PATH" "$(printf 'gi\rt push --for''ce origin feature/x')")"
say E15 "$pass passed, $fail failed"
