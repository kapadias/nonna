#!/usr/bin/env bash
# Scratch (#45, never merged): the Windows legs' last failures, and each fix for them, measured on Git Bash.
set -u
exec </dev/null
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; HOOKS="$ROOT/.claude/hooks"
say() { printf 'probe %s: %s\n' "$1" "$2"; }
ms() { date +%s%N | cut -c1-13; }
say env "$(uname -s) bash $BASH_VERSION MSYS=${MSYS:-} jq=$(command -v jq) $(jq --version 2>&1) python3=$(python3 --version 2>&1)"

# E3. The detection property, with Git Bash's bash and a grep script on the private PATH.
L="$(mktemp)"; t0=$(ms)
say E3 "$(python3 "$ROOT/tests/detect_property.py" "$HOOKS" "$L" 2>&1 | tr '\n' ' ' | cut -c1-400) ($(( $(ms) - t0 )) ms)"
B="$(mktemp -d)"; mkdir "$B/lib"; printf 'echo boom >&2\nreturn 7\n' > "$B/lib/tests.sh"
say E3 "a broken source: $(python3 "$ROOT/tests/detect_property.py" "$B" "$L" 2>&1 | head -n 1)"
rm -rf "$B" "$L"

