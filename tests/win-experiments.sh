#!/usr/bin/env bash
# Scratch (#45, never merged): the third review's checks, run as tests/run.sh writes them, on Git Bash.
set -u
exec </dev/null
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; HOOKS="$ROOT/.claude/hooks"; GB="$HOOKS/guard-branch.sh"; SS="$HOOKS/secret-scan.sh"
say() { printf 'probe %s: %s\n' "$1" "$2"; }
say env "$(uname -s) bash $BASH_VERSION MSYS=${MSYS:-} jq=$(command -v jq) $(jq --version 2>&1)"
say E9 "this jq takes -b: $(jq -b -n 1 >/dev/null 2>&1 && echo yes || echo no); json.sh picks: $(bash -c '. "$1/lib/json.sh"; printf %s "${_nonna_jq_raw:-plain}"' _ "$HOOKS")"
pass=0; fail=0
check() { if [ "$2" = "$3" ]; then pass=$((pass + 1)); say ok "$1"; else fail=$((fail + 1)); say FAIL "$1 (want $2, got $3)"; fi; }
eval "$(sed -n '/^link() {/,/^}/p' "$ROOT/tests/run.sh")"
TMP="$(mktemp -d)"; git -C "$TMP" init -q; git -C "$TMP" checkout -qb feature/x
BADAWK="$(mktemp -d)"; printf '#!/bin/sh\nexit 1\n' > "$BADAWK/awk"; chmod +x "$BADAWK/awk"
eval "$(sed -n '/^gbp() {/p' "$ROOT/tests/run.sh")"
eval "$(sed -n '/Two jqs stand/,/her \/nonna scripts too/p' "$ROOT/tests/run.sh")"
LNK="$(mktemp -d)"; printf 'K=1\n' > "$LNK/.env"
eval "$(sed -n '/^link .env "\$LNK\/\$(printf/,/name ending in a CR, which is the name Read opens/p' "$ROOT/tests/run.sh")"
say E9 "the CR-named link: $(ls -la "$LNK" | sed -n '4,5p' | tr '\n' ' ' | cut -c1-200)"
W="$(mktemp -d)"
eval "$(sed -n '/^DIRLN="\$(mktemp -d)"/,/^rm -rf "\$R"$/p' "$ROOT/tests/run.sh")"
say E9 "$pass passed, $fail failed"
rm -rf "$TMP" "$BADAWK" "$LNK" "$W"
