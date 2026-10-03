#!/usr/bin/env bash
# Scratch (#45, never merged): the Windows legs' last failures, and each fix for them, measured on Git Bash.
set -u
exec </dev/null
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; HOOKS="$ROOT/.claude/hooks"
say() { printf 'probe %s: %s\n' "$1" "$2"; }
ms() { date +%s%N | cut -c1-13; }
say env "$(uname -s) bash $BASH_VERSION MSYS=${MSYS:-} jq=$(command -v jq) $(jq --version 2>&1) python3=$(python3 --version 2>&1)"

# E1. A tailed hooks.json command: what python gets for it, and what the lint prints.
FX="$(mktemp -d)"
cp -R "$ROOT/.claude" "$ROOT/docs" "$ROOT/tests" "$ROOT/stacks" "$ROOT/.github" "$ROOT/.claude-plugin" "$ROOT/hosts" \
  "$ROOT/bench" "$ROOT/examples" "$ROOT/assets" "$ROOT/hooks" "$FX/" 2>/dev/null
cp "$ROOT"/*.md "$ROOT"/LICENSE "$ROOT/gemini-extension.json" "$FX/" 2>/dev/null
python3 - "$FX/.claude/hooks/hooks.json" PreToolUse '"${CLAUDE_PLUGIN_ROOT}"/hooks/guard-branch.sh || true' <<'PY'
import json, sys
path, event, cmd = sys.argv[1:4]
print("probe E1: python got", repr(cmd))
cfg = json.load(open(path, encoding="utf-8"))
cfg["hooks"][event][0]["hooks"][0]["command"] = cmd
json.dump(cfg, open(path, "w", encoding="utf-8"), indent=2)
PY
out="$(NONNA_LINT_ROOT="$FX" python3 "$ROOT/tests/harness_lint.py" 2>&1)"; say E1 "lint exit $?"
printf '%s\n' "$out" | head -12 | cut -c1-260 | sed 's/^/probe E1 | /'
python3 - "$FX/.claude/settings.json" PreToolUse '"$CLAUDE_PROJECT_DIR"/.claude/hooks/guard-branch.sh; exit 0' <<'PY'
import sys
print("probe E1: and the settings.json one, python got", repr(sys.argv[3]))
PY
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

# E4. The branch guard and multi-line commands, through this jq: before the fix (json.sh at 1b07932) and after.
TMP="$(mktemp -d)"; git -C "$TMP" init -q; git -C "$TMP" checkout -qb feature/x
OLD="$(mktemp -d)"; cp -R "$ROOT/.claude" "$OLD/"; git -C "$ROOT" show 1b07932:.claude/hooks/lib/json.sh > "$OLD/.claude/hooks/lib/json.sh"
BADAWK="$(mktemp -d)"; printf '#!/bin/sh\nexit 1\n' > "$BADAWK/awk"; chmod +x "$BADAWK/awk"
gbp() { printf '{"tool_name":"Bash","tool_input":{"command":%s}}' "$(printf '%s' "$3" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')" | PATH="$2" CLAUDE_PROJECT_DIR="$TMP" "$1/guard-branch.sh" 2>/dev/null; echo $?; }
printf 'probe E4: jq -r of "a\\nb" writes: '; printf '"a\\nb"' | jq -r . | od -c | head -n 1
for v in "before:$OLD/.claude/hooks" "after:$HOOKS"; do
  h="${v#*:}"
  say E4 "${v%%:*}: a force flag ending a line $(gbp "$h" "$PATH" "$(printf 'git push origin feature/x --force\necho done')"), a push continued $(gbp "$h" "$PATH" "$(printf 'git push \\\n  --force origin feature/x')"), git split with awk failing $(gbp "$h" "$BADAWK:$PATH" "$(printf 'g\\\nit push --force origin feature/x')"), an ordinary two lines $(gbp "$h" "$PATH" "$(printf 'git status\necho done')") (want 2 2 2 0)"
done
rm -rf "$TMP" "$OLD" "$BADAWK"

# E5. One lint run: the cross-check in turn (1b07932) and side by side (now).
git -C "$ROOT" show 1b07932:tests/harness_lint.py > "$ROOT/tests/lint-before.py"
t0=$(ms); NONNA_LINT_ROOT="$ROOT" python3 "$ROOT/tests/lint-before.py" >/dev/null 2>&1; t1=$(ms)
python3 "$ROOT/tests/harness_lint.py" >/dev/null 2>&1; t2=$(ms)
say E5 "lint in turn $(( t1 - t0 )) ms, side by side $(( t2 - t1 )) ms, $(nproc 2>/dev/null) processors"
rm -f "$ROOT/tests/lint-before.py"

# E6. --render through a .cmd that runs the Python stand-in for Chromium.
AX="$(mktemp -d)"; mkdir -p "$AX/bench/tasks" "$AX/bench/results" "$AX/.claude/.claude-plugin"
cp -R "$ROOT/assets" "$AX/"; cp -R "$ROOT/bench/tasks/traps" "$AX/bench/tasks/"; cp -R "$ROOT/bench/results/round3" "$AX/bench/results/"
cp "$ROOT/.claude/.claude-plugin/icon.png" "$AX/.claude/.claude-plugin/"; rm "$AX"/assets/*.png "$AX"/assets/cards/*.png "$AX/.claude/.claude-plugin/icon.png"
cat > "$AX/fake-chromium" <<'PY'
#!/usr/bin/env python3
import os, re, struct, sys, zlib
args = " ".join(sys.argv[1:])
if os.environ.get("FAKE_FAIL"):
    sys.exit("fake browser: no display")
w, h = map(int, re.search(r"--window-size=(\d+),(\d+)", args).groups())
k = int(re.search(r"--force-device-scale-factor=(\d+)", args).group(1))
out = re.search(r"--screenshot=(\S+)", args).group(1)
w, h = w * k, h * k + int(os.environ.get("FAKE_EXTRA_ROWS", "0"))
def chunk(kind, body): return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body))
raw = b"".join(b"\x00" + b"\xff\xff\xff" * w for _ in range(h))
png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
open(out, "wb").write(png + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))
PY
printf '@"%s" "%%~dp0fake-chromium" %%*\r\n' "$(python3 -c 'import sys; sys.stdout.write(sys.executable)')" > "$AX/fake-chromium.cmd"
say E6 "the .cmd: $(tr -d '\r' < "$AX/fake-chromium.cmd")"
FAKE_FAIL=1 CHROMIUM="$AX/fake-chromium.cmd" NONNA_ASSETS_ROOT="$AX" python3 -I -S "$ROOT/assets/build.py" --render >/dev/null 2>"$AX/err"
say E6 "a browser that fails: exit $? | $(tr '\n' ' ' < "$AX/err" | cut -c1-200)"
CHROMIUM="$AX/fake-chromium.cmd" NONNA_ASSETS_ROOT="$AX" python3 -I -S "$ROOT/assets/build.py" --render >/dev/null 2>"$AX/err"
say E6 "--render: exit $? | $(tr '\n' ' ' < "$AX/err" | cut -c1-200)"
NONNA_ASSETS_ROOT="$AX" python3 -I -S "$ROOT/assets/build.py" --check >/dev/null 2>"$AX/err"; say E6 "--check: exit $? | $(tr '\n' ' ' < "$AX/err" | cut -c1-200)"
say E6 "test_assets.py: $(python3 "$ROOT/tests/test_assets.py" 2>&1 | tail -n 3 | tr '\n' ' ')"
rm -rf "$AX"

# E7. A copy of her pre-push script, under a plugin, where the data dir holds what this ln makes.
TMP="$(mktemp -d)"; git -C "$TMP" init -q; PD="$(mktemp -d)"
cp "$HOOKS/require-status-sync.sh" "$TMP/.git/hooks/pre-push"
out="$(CLAUDE_PROJECT_DIR="$TMP" CLAUDE_PLUGIN_ROOT="$ROOT/.claude" "$HOOKS/session-start.sh" "$PD/data")"
say E7 "data dir current: $([ -L "$PD/data/current" ] && echo link || echo directory); says: $(printf '%s' "$out" | grep -o 'pre-push is[^;]*' | head -n 1 | cut -c1-120)"
rm -rf "$TMP" "$PD"

# E8. The root a copy-in session start announces, and pwd -P.
TMP="$(mktemp -d)"; git -C "$TMP" init -q; cp -R "$ROOT/.claude" "$TMP/"
out="$(CLAUDE_PROJECT_DIR="$TMP" "$TMP/.claude/hooks/session-start.sh")"
say E8 "pwd -P $(cd "$TMP" && pwd -P); announces $(printf '%s' "$out" | grep -o 'Harness root: [^ ]*' | head -n 1)"
rm -rf "$TMP"
