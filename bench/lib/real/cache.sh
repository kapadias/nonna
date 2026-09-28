#!/usr/bin/env bash
# usage: cache.sh <cache-dir>  -> prints the directory holding the pinned upstream tree
# The real suite's project is fastapi/full-stack-fastapi-template at the commit tasks/real/UPSTREAM
# pins. Once per cache dir, under a lock: fetch it, check its tree hash, unpack it, and warm a uv
# cache (<cache-dir>/uv-cache) with its locked dependencies, so that each run's
# `uv sync --offline` needs no network. A Python 3.11 that uv has to download goes to
# <cache-dir>/python, where every later uv call looks (UV_PYTHON_INSTALL_DIR), whatever its HOME.
# Later calls print the directory at once.
set -euo pipefail
B="$(cd "$(dirname "$0")/../.." && pwd)"
[ -n "${1:-}" ] || { echo "usage: cache.sh <cache-dir>" >&2; exit 2; }
mkdir -p "$1" && C="$(cd "$1" && pwd)"
pinned() { awk -v k="$1" '$1 == k { print $2 }' "$B/tasks/real/UPSTREAM"; }
url="$(pinned url)" commit="$(pinned commit)" tree="$(pinned tree)"
src="$C/src-$commit"
if [ ! -f "$src.ok" ]; then
  exec 9> "$C/.lock"
  flock 9
  if [ ! -f "$src.ok" ]; then
    [ -d "$C/upstream.git" ] || git clone -q --bare "$url" "$C/upstream.git"
    git -C "$C/upstream.git" cat-file -e "$commit^{commit}" 2>/dev/null ||
      git -C "$C/upstream.git" fetch -q "$url" "$commit"
    got="$(git -C "$C/upstream.git" rev-parse "$commit^{tree}")"
    [ "$got" = "$tree" ] || { echo "cache.sh: $commit has tree $got, not the pinned $tree" >&2; exit 1; }
    rm -rf "$src" && mkdir -p "$src"
    git -C "$C/upstream.git" archive "$commit" | tar -x -C "$src"
    # The locked dependencies, the dev group (pytest) included, into a venv of the cache's own.
    UV_CACHE_DIR="$C/uv-cache" UV_PYTHON_INSTALL_DIR="$C/python" UV_PROJECT_ENVIRONMENT="$C/warm-venv" \
      uv sync -q --frozen --package app --python 3.11 --project "$src"
    touch "$src.ok"
  fi
fi
printf '%s\n' "$src"
