#!/usr/bin/env bash
# Scratch probes for #45 (never merged): facts about Git Bash, printed, never asserted.
set -u
say() { printf 'X %s\n' "$*"; }
flat() { tr '\r\n' '~|' | cut -c1-"${1:-400}"; }
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOKS="$ROOT/.claude/hooks"

say "0 uname=$(uname -sr) MSYS=[${MSYS:-}] bash=$BASH_VERSION"
say "0 /tmp: pwd=[$(cd /tmp && pwd)] pwd-P=[$(cd /tmp && pwd -P)] TMPDIR=[${TMPDIR:-}] TMP=[${TMP:-}]"
say "0 mktemp -d: [$(mktemp -d)] | cygpath: [$(command -v cygpath)]"
say "0 ldd bash: $(ldd /usr/bin/bash 2>&1 | flat 500)"
say "0 bash files: $(ls -l /usr/bin/bash* /usr/bin/msys-2.0.dll 2>&1 | flat 500)"

# --- A. the suite's private tool directory: links (or copies) vs shim scripts -------------------------
D="$(mktemp -d)"; ln -s "$(command -v bash)" "$D/bash" 2>/dev/null; ln -s "$(command -v grep)" "$D/grep" 2>/dev/null
say "A0 ln -s into a dir: bash is-link=$([ -L "$D/bash" ] && echo y || echo n) size=$(wc -c < "$D/bash" 2>/dev/null)"
o="$(PATH="$D" bash -c 'echo ok' 2>&1)"; say "A1 PATH=links bash -c: rc=$? [$(printf '%s' "$o" | flat)]"
o="$(PATH="$D" /usr/bin/bash -c 'echo ok; grep -c x <<< x' 2>&1)"; say "A2 real bash, PATH=links, grep via PATH: rc=$? [$(printf '%s' "$o" | flat)]"
o="$(PATH="$D:/usr/bin" bash -c 'echo ok' 2>&1)"; say "A3 PATH=links:/usr/bin: rc=$? [$(printf '%s' "$o" | flat)]"
N="$(mktemp -d)"; MSYS=winsymlinks:nativestrict ln -s "$(command -v bash)" "$N/bash" 2>&1 | flat
say "A4 native link: is-link=$([ -L "$N/bash" ] && echo y || echo n) -> [$(readlink "$N/bash")]"
o="$(PATH="$N" bash -c 'echo ok' 2>&1)"; say "A5 PATH=native links: rc=$? [$(printf '%s' "$o" | flat)]"
S="$(mktemp -d)"
for b in bash sh env cat grep sed awk tr dirname git; do
  p="$(command -v "$b")" || continue
  printf '#!/bin/sh\nexec "%s" "$@"\n' "$p" > "$S/$b"; chmod +x "$S/$b"
done
o="$(PATH="$S" bash -c 'echo ok; grep -c x <<< x; echo y | sed s/y/z/; echo 1 | awk "{print \$1+1}"; command -v jq || echo no-jq' 2>&1)"
say "A6 PATH=shims: rc=$? [$(printf '%s' "$o" | flat)]"
printf '#!/usr/bin/env bash\necho "envbash ${BASH_VERSION} src=${BASH_SOURCE[0]}"\n' > "$S/t.sh"; chmod +x "$S/t.sh"
o="$(PATH="$S" "$S/t.sh" 2>&1)"; say "A7 #!/usr/bin/env bash script, PATH=shims: rc=$? [$(printf '%s' "$o" | flat)]"
o="$(printf '{}' | PATH="$S" bash "$HOOKS/check-review.sh" 2>&1)"; say "A8 check-review.sh with PATH=shims (no jq): rc=$? [$(printf '%s' "$o" | flat 200)]"
t0=$(date +%s%N); for _ in 1 2 3 4 5 6 7 8 9 10; do PATH="$S" bash -c 'grep -c x <<< x' >/dev/null; done; t1=$(date +%s%N)
for _ in 1 2 3 4 5 6 7 8 9 10; do bash -c 'grep -c x <<< x' >/dev/null; done; t2=$(date +%s%N)
say "A9 10 runs: shims $(( (t1 - t0) / 1000000 ))ms, plain $(( (t2 - t1) / 1000000 ))ms"

# --- B. readlink of native links, and what ln -s does with a missing target ----------------------------
B="$(mktemp -d)"; mkdir -p "$B/.git/hooks" "$B/.claude/hooks"; : > "$B/.claude/hooks/x.sh"
( cd "$B/.git/hooks" && MSYS=winsymlinks:nativestrict ln -s ../../.claude/hooks/x.sh rel 2>&1 | flat;
  MSYS=winsymlinks:nativestrict ln -s "$B/.claude/hooks/x.sh" abs 2>&1 | flat;
  MSYS=winsymlinks:nativestrict ln -s /gone/x.sh dangling 2>&1 | flat )
say "B1 native readlink: rel=[$(readlink "$B/.git/hooks/rel")] abs=[$(readlink "$B/.git/hooks/abs")] dangling=[$(readlink "$B/.git/hooks/dangling")] B=[$B]"
( cd "$B/.git/hooks" && ln -s ../../.claude/hooks/x.sh crel 2>&1 | flat; ln -s /gone/x.sh cgone 2>&1 | flat )
say "B2 default ln -s: crel is-link=$([ -L "$B/.git/hooks/crel" ] && echo y || echo n) exists=$([ -e "$B/.git/hooks/crel" ] && echo y || echo n); to a missing target: exists=$([ -e "$B/.git/hooks/cgone" ] || [ -L "$B/.git/hooks/cgone" ] && echo y || echo n)"
L="$(mktemp -d)"; ln -s x "$L/l" 2>/dev/null; say "B3 ln -s to a missing name: rc-made=$([ -L "$L/l" ] && echo link || { [ -e "$L/l" ] && echo file || echo nothing; })"

# --- C. how paths are spelled --------------------------------------------------------------------------
R="$(mktemp -d)"; git init -q "$R"; mkdir -p "$R/sub/deep"
( cd "$R/sub/deep" && say "C1 R=[$R] pwd=[$(pwd)] pwd-P=[$(pwd -P)] top=[$(git rev-parse --show-toplevel)] prefix=[$(git rev-parse --show-prefix)] cdup=[$(git rev-parse --show-cdup)] hooks=[$(git rev-parse --git-path hooks)] gitdir=[$(git rev-parse --git-dir)] cygpath-u-top=[$(cygpath -u "$(git rev-parse --show-toplevel)" 2>&1)]" )
( cd "$R" && say "C2 at top: hooks=[$(git rev-parse --git-path hooks)] nonna-path=[$(git rev-parse --git-path nonna)]" )

# --- D. a git hook that is a wrapper script ------------------------------------------------------------
W="$(mktemp -d)/with space"; mkdir -p "$W"; git -C "$W" init -q; mkdir -p "$W/.claude/hooks/lib"
printf '#!/usr/bin/env bash\necho "real hook ran: src=${BASH_SOURCE[0]} lib=$(ls "$(dirname "${BASH_SOURCE[0]}")/lib" | tr -d "\\n") args=$# pwd=$(pwd)" >&2\nexit 1\n' > "$W/.claude/hooks/pre-commit.sh"
: > "$W/.claude/hooks/lib/core.sh"
printf '#!/bin/sh\n# nonna: ../../.claude/hooks/pre-commit.sh\nexec bash "$(dirname "$0")"/'"'"'../../.claude/hooks/pre-commit.sh'"'"' "$@"\n' > "$W/.git/hooks/pre-commit"; chmod +x "$W/.git/hooks/pre-commit"
printf '#!/bin/sh\necho "dollar0=[$0]" >&2\n' > "$W/.git/hooks/probe0"
( cd "$W" && echo a > a && git add a && o="$(git -c user.email=a@b -c user.name=n commit -qm x 2>&1)"; say "D1 commit through a relative wrapper: rc=$? [$(printf '%s' "$o" | flat)]" )
printf '#!/bin/sh\n# nonna: %s\nexec bash '"'"'%s'"'"' "$@"\n' "$W/.claude/hooks/pre-commit.sh" "$W/.claude/hooks/pre-commit.sh" > "$W/.git/hooks/pre-commit"
( cd "$W" && o="$(git -c user.email=a@b -c user.name=n commit -qm x 2>&1)"; say "D2 commit through an absolute wrapper (a space in the path): rc=$? [$(printf '%s' "$o" | flat)]" )
( cd "$W/.claude" && o="$(git -c user.email=a@b -c user.name=n commit -qm x 2>&1)"; say "D3 commit from a subdirectory, absolute wrapper: rc=$? [$(printf '%s' "$o" | flat)]" )
printf '#!/bin/sh\necho "dollar0=[$0] pwd=[$(pwd)]" >&2\nexit 1\n' > "$W/.git/hooks/pre-commit"
( cd "$W/.claude" && o="$(git -c user.email=a@b -c user.name=n commit -qm x 2>&1)"; say "D4 what git passes as \$0, from a subdirectory: [$(printf '%s' "$o" | flat)]" )

# --- E. the lint's secret-scan cross-check, from native Python ------------------------------------------
python3 - "$ROOT" <<'PY'
import json, os, shutil, subprocess, sys
root = sys.argv[1]
win_root = os.path.dirname(os.path.dirname(os.path.abspath(os.path.join(root, "tests", "x"))))
print("X E0 python sees root as", repr(os.path.abspath(".")), "| which bash:", shutil.which("bash"))
r = subprocess.run(["bash", "-c", "echo $BASH_VERSION; uname -s"], capture_output=True, text=True)
print("X E1 bash -c from python:", r.returncode, repr(r.stdout), repr(r.stderr[:200]))
here = os.path.abspath(".")
for label, envroot in (("python root", here), ("posix root", root)):
    payload = json.dumps({"tool_name": "Read", "tool_input": {"file_path": "./x/.env"}})
    r = subprocess.run(["bash", os.path.join(here, ".claude/hooks/secret-scan.sh")], input=payload,
                       capture_output=True, text=True, env={**os.environ, "NONNA_MODE": "full", "CLAUDE_PROJECT_DIR": envroot})
    print("X E2", label, repr(envroot), "rc=", r.returncode, "err=", repr(r.stderr[:300]))
PY
o="$(printf '%s' '{"tool_name":"Read","tool_input":{"file_path":"./x/.env"}}' | NONNA_MODE=full CLAUDE_PROJECT_DIR="$ROOT" bash "$HOOKS/secret-scan.sh" 2>&1)"; say "E3 the same from Git Bash: rc=$? [$(printf '%s' "$o" | flat 200)]"
o="$(printf '%s' '{"tool_name":"Read","tool_input":{"file_path":"./x/.env"}}' | NONNA_MODE=full CLAUDE_PROJECT_DIR="$(cygpath -w "$ROOT")" bash "$HOOKS/secret-scan.sh" 2>&1)"; say "E4 ...with a Windows-style project dir: rc=$? [$(printf '%s' "$o" | flat 200)]"
o="$(cd "$ROOT" && python3 tests/harness_lint.py 2>&1 | head -3)"; say "E5 lint head: [$(printf '%s' "$o" | flat 300)]"

# --- F. the assets tests ---------------------------------------------------------------------------------
o="$(cd "$ROOT" && python3 -m unittest tests/test_assets.py 2>&1 | tail -40)"; say "F1 test_assets: [$(printf '%s' "$o" | flat 3000)]"

# --- G. session start in a copy-in, and the root it announces ---------------------------------------------
T="$(mktemp -d)"; git init -q "$T"; mkdir -p "$T/.claude/hooks" && cp -R "$HOOKS/." "$T/.claude/hooks/"
o="$(printf '{}' | CLAUDE_PROJECT_DIR="$T" "$T/.claude/hooks/session-start.sh" 2>&1)"
say "G1 T=[$T] announced: [$(printf '%s' "$o" | grep -o 'Harness root: [^ ]*' | head -1)]"
say "G2 git hooks after it: $(ls -la "$T/.git/hooks" 2>&1 | grep -E 'pre-(push|commit)$' | flat 300)"
say "done"
