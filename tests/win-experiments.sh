#!/usr/bin/env bash
# Scratch (#45, never merged): the Windows legs' last failures, and each fix for them, measured on Git Bash.
set -u
exec </dev/null
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; HOOKS="$ROOT/.claude/hooks"
say() { printf 'probe %s: %s\n' "$1" "$2"; }
ms() { date +%s%N | cut -c1-13; }
say env "$(uname -s) bash $BASH_VERSION MSYS=${MSYS:-} jq=$(command -v jq) $(jq --version 2>&1) python3=$(python3 --version 2>&1)"

# E1. A tailed hooks.json command, written as set_hook_cmd now writes it (the command on stdin), and the lint.
FX="$(mktemp -d)"
cp -R "$ROOT/.claude" "$ROOT/docs" "$ROOT/tests" "$ROOT/stacks" "$ROOT/.github" "$ROOT/.claude-plugin" "$ROOT/hosts" \
  "$ROOT/bench" "$ROOT/examples" "$ROOT/assets" "$ROOT/hooks" "$FX/" 2>/dev/null
cp "$ROOT"/*.md "$ROOT"/LICENSE "$ROOT/gemini-extension.json" "$FX/" 2>/dev/null
eval "$(sed -n '/^set_hook_cmd()/,/^}/p' "$ROOT/tests/run.sh")"
set_hook_cmd "$FX/.claude/hooks/hooks.json" PreToolUse '"${CLAUDE_PLUGIN_ROOT}"/hooks/guard-branch.sh || true'
say E1 "hooks.json holds: $(grep -o '"command": "[^,]*|| true"' "$FX/.claude/hooks/hooks.json")"
out="$(NONNA_LINT_ROOT="$FX" python3 "$ROOT/tests/harness_lint.py" 2>&1)"; say E1 "lint exit $?"
printf '%s\n' "$out" | grep -F "PreToolUse hook '" | cut -c1-200 | sed 's/^/probe E1 | /'
rm -rf "$FX"

# E2. What makes a file one that cannot run: chmod -x, and a file without its #!.
d="$(mktemp -d)"; printf '#!/bin/sh\nexit 0\n' > "$d/f"; chmod +x "$d/f"
a=no; [ -x "$d/f" ] && a=yes; chmod -x "$d/f"; b=no; [ -x "$d/f" ] && b=yes
sed -i '1{/^#!/d;}' "$d/f"; c=no; [ -x "$d/f" ] && c=yes
say E2 "with #! and +x, -x says $a; after chmod -x, $b; without its #! too, $c"
rm -rf "$d"

# E3. The detection property, with Git Bash's bash and a grep script on the private PATH.
L="$(mktemp)"; t0=$(ms)
say E3 "$(python3 "$ROOT/tests/detect_property.py" "$HOOKS" "$L" 2>&1 | tr '\n' ' ' | cut -c1-400) ($(( $(ms) - t0 )) ms)"
B="$(mktemp -d)"; mkdir "$B/lib"; printf 'echo boom >&2\nreturn 7\n' > "$B/lib/tests.sh"
say E3 "a broken source: $(python3 "$ROOT/tests/detect_property.py" "$B" "$L" 2>&1 | head -n 1)"
rm -rf "$B" "$L"

