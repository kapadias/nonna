#!/usr/bin/env bash
# usage: cache.sh <cache-dir> [<new-dir>]
# The real suite's project is fastapi/full-stack-fastapi-template at the commit tasks/real/UPSTREAM
# pins. Once per cache dir, under a lock: fetch it into a bare repository, and warm a uv cache
# (<cache-dir>/uv-cache) with its locked dependencies, so that each run's `uv sync --offline` needs
# no network. A Python 3.11 that uv has to download goes to <cache-dir>/python, where every later uv
# call looks (UV_PYTHON_INSTALL_DIR), whatever its HOME.
# Every call checks the pinned commit's tree hash. With <new-dir>, it then writes that tree there
# from git's object store, so no run starts from, and no scorer compares against, a copy that an
# earlier run could have changed. Without it, it prints the repository's path.
set -euo pipefail
B="$(cd "$(dirname "$0")/../.." && pwd)"
[ -n "${1:-}" ] || { echo "usage: cache.sh <cache-dir> [<new-dir>]" >&2; exit 2; }
mkdir -p "$1" && C="$(cd "$1" && pwd)"
pinned() { awk -v k="$1" '$1 == k { print $2 }' "$B/tasks/real/UPSTREAM"; }
url="$(pinned url)" commit="$(pinned commit)" tree="$(pinned tree)"
repo="$C/upstream.git"
if [ ! -f "$C/ok-$commit" ]; then
  exec 9> "$C/.lock"
  flock 9
  if [ ! -f "$C/ok-$commit" ]; then
    [ -d "$repo" ] || git clone -q --bare "$url" "$repo"
    git -C "$repo" cat-file -e "$commit^{commit}" 2>/dev/null || git -C "$repo" fetch -q "$url" "$commit"
    warm="$(mktemp -d "$C/warm.XXXXXX")"
    git -C "$repo" archive "$commit" | tar -x -C "$warm"
    # The locked dependencies, the dev group (pytest) included, into a venv that goes again: what
    # stays is the uv cache.
    UV_CACHE_DIR="$C/uv-cache" UV_PYTHON_INSTALL_DIR="$C/python" UV_PROJECT_ENVIRONMENT="$warm/.venv" \
      uv sync -q --frozen --package app --python 3.11 --project "$warm"
    rm -rf "$warm"
    touch "$C/ok-$commit"
  fi
  exec 9>&-
fi
got="$(git -C "$repo" rev-parse "$commit^{tree}")"
[ "$got" = "$tree" ] || { echo "cache.sh: $commit has tree $got, not the pinned $tree" >&2; exit 1; }
if [ -n "${2:-}" ]; then
  mkdir "$2"
  git -C "$repo" archive "$commit" | tar -x -C "$2"
else
  printf '%s\n' "$repo"
fi
