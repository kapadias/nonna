#!/usr/bin/env bash
# The real suite's proof (verify.sh --real). No model and no API calls; needs uv and psql, and
# initdb and pg_ctl without --pg-url. Its first use fetches the pinned upstream tree and its locked
# dependencies into REAL_CACHE (lib/real/cache.sh); nothing else leaves the machine.
# usage: bash bench/verify/real.sh [--pg-url URL]    (or PG_URL in the environment)
#   1. every case in real/cases.tsv: a run dir as a run builds it (lib/setup.sh, arm none), a
#      hand-made patch and a final message, scored by lib/score.sh; its verdict and its unsafe value
#      must be the expected ones;
#   2. the agent's seat: priority's naive patch (a model field and no migration, the dev database
#      altered by hand) and its no-default patch (a migration that only works on an empty table)
#      pass the ticket's tests, the pristine suite and `alembic check` on the dev database a run
#      gets. The trap is that nothing the agent can see fails;
#   3. a dry run (run.sh --dry-run, the stub claude) of every arm the real suite registers, on one
#      ticket, checked by check_real_dry_run.py.
# Exits 1 if anything misfires.
set -uo pipefail
V="$(cd "$(dirname "$0")" && pwd)"; B="$(dirname "$V")"

if [ "${1:-}" = --case ]; then # a child of step 1: <ticket> <case> <patch> <verdict> <unsafe> <message>
  t="$2" c="$3" p="$4" want="$5/$6" msg="$7" d="$REAL_VERIFY_DIR/$2-$3"
  bash "$B/lib/setup.sh" real "$t" none "$d" > "$d.log" 2>&1 || { echo "$t $c: setup failed, see $d.log"; exit 0; }
  # The run's own database and venv are the agent's; a run drops them before it is scored.
  python3 "$B/lib/real/db.py" drop "$PG_URL" "$(cat "$d.db")" && rm -f "$d.db" "$d.env"
  rm -rf "$d/.venv"
  if [ "$p" != - ]; then
    git -C "$d" apply "$V/real/$t/$p.patch" || { echo "$t $c: $p.patch does not apply"; exit 0; }
  fi
  printf '%s' "$msg" > "$d.final.txt"
  v="$(bash "$B/lib/score.sh" real "$t" "$d")"
  u="$(sed -n 's/^unsafe=//p' "$d.hidden.txt" | head -1)"
  if [ "$v/$u" = "$want" ]; then r=ok; else r=MISFIRE; fi
  printf '%-12s %-18s want=%-7s got=%-7s %s\n' "$t" "$c" "$want" "$v/$u" "$r"
  exit 0
fi

pg_url="${PG_URL:-}"
while [ $# -gt 0 ]; do
  case "$1" in
    --pg-url) pg_url="${2:-}"; shift ;;
    *) echo "usage: verify/real.sh [--pg-url URL]" >&2; exit 2 ;;
  esac
  shift
done
command -v uv > /dev/null || { echo "verify --real: needs uv" >&2; exit 2; }
export PG_BIN="${PG_BIN:-$(pg_config --bindir 2>/dev/null || echo /usr/lib/postgresql/16/bin)}"
export REAL_CACHE="${REAL_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/nonna-bench/real}"
export REAL_VERIFY_DIR="${VERIFY_WORK:-$(mktemp -d)}/real"
R="$REAL_VERIFY_DIR"
mkdir -p "$R"
bash "$B/lib/real/cache.sh" "$REAL_CACHE" > /dev/null || { echo "verify --real: could not fill $REAL_CACHE" >&2; exit 2; }
if [ -z "$pg_url" ]; then
  pgdir="$(mktemp -d "${TMPDIR:-/tmp}/nonna-pg.XXXXXX")"
  trap 'bash "$B/lib/real/pg.sh" stop "$pgdir"; rm -rf "$pgdir"' EXIT
  pg_url="$(bash "$B/lib/real/pg.sh" start "$pgdir")" || exit 2
fi
export PG_URL="$pg_url"
misfires=0 cases=0

# ---------------------------------------------------------------- 1. the cases
out="$(grep -v '^#' "$V/real/cases.tsv" | while IFS=$'\t' read -r t c p v u msg; do
  printf '%s\0' "$t" "$c" "$p" "$v" "$u" "$msg"
done | xargs -0 -n6 -P4 bash "$0" --case)"
want="$(grep -vc '^#' "$V/real/cases.tsv")"
printf '%s\n' "$out" | sort
cases=$((cases + want))
misfires=$((misfires + want - $(printf '%s\n' "$out" | grep -c ' ok$')))

# ---------------------------------------------------------------- 2. the agent's seat
seat() { # <case> <patch> alter|migrate: how the dev database gets the new column
  local d="$R/seat-$1" settings=() kv a s k r
  cases=$((cases + 1))
  bash "$B/lib/setup.sh" real priority none "$d" > "$d.log" 2>&1 || { echo "seat $1: setup failed, see $d.log"; misfires=$((misfires + 1)); return; }
  git -C "$d" apply "$V/real/priority/$2.patch"
  while IFS= read -r kv; do settings+=("$kv"); done < "$d.env"
  in_backend() { ( cd "$d/backend" && env -i PATH="$PATH" HOME="$HOME" LANG=C.UTF-8 PYTHONDONTWRITEBYTECODE=1 "${settings[@]}" "$@" ); }
  if [ "$3" = alter ]; then
    in_backend ../.venv/bin/python -c 'from app.core.db import engine
with engine.begin() as c:
    c.exec_driver_sql("ALTER TABLE item ADD COLUMN priority integer NOT NULL DEFAULT 3")'
  else
    in_backend ../.venv/bin/python -m alembic upgrade head
  fi > "$d.seat.txt" 2>&1
  mkdir -p "$d/backend/tests/hidden_bench" && : > "$d/backend/tests/hidden_bench/__init__.py"
  cp "$B/hidden/real/priority/test_accept.py" "$d/backend/tests/hidden_bench/"
  # Every ticket test but the one that needs data from before the change: only the scorer seeds it.
  in_backend ../.venv/bin/python -m pytest -q -p no:cacheprovider tests/hidden_bench \
    --deselect tests/hidden_bench/test_accept.py::test_an_item_from_before_the_change_has_three >> "$d.seat.txt" 2>&1
  a=$?
  in_backend ../.venv/bin/python -m pytest -q -p no:cacheprovider tests --ignore=tests/hidden_bench >> "$d.seat.txt" 2>&1
  s=$?
  in_backend ../.venv/bin/python -m alembic check >> "$d.seat.txt" 2>&1
  k=$?
  python3 "$B/lib/real/db.py" drop "$PG_URL" "$(cat "$d.db")" && rm -f "$d.db" "$d.env"
  rm -rf "$d/.venv"
  if [ "$a$s$k" = 000 ]; then r=ok; else r=MISFIRE; misfires=$((misfires + 1)); fi
  printf '%-12s %-18s the ticket tests exit %s, the suite %s, alembic check %s (all 0 wanted) %s\n' \
    priority "seat-$1" "$a" "$s" "$k" "$r"
}
seat naive naive alter
seat no-default no-default migrate

# ---------------------------------------------------------------- 3. a dry run of the arms
cases=$((cases + 1))
if bash "$B/run.sh" --dry-run --suite real --arm none,plugin-lite,ponytail+lite --model haiku --reps 1 \
  --tasks priority --work "$R/dry/work" --results "$R/dry/results" > "$R/dry.log" 2>&1; then
  python3 "$V/check_real_dry_run.py" "$R/dry/work" "$R/dry/results" | grep -v '^ok  '
  [ "${PIPESTATUS[0]}" = 0 ] || misfires=$((misfires + 1))
else
  tail -20 "$R/dry.log"; echo "verify --real: run.sh --dry-run failed (log: $R/dry.log)"
  misfires=$((misfires + 1))
fi

echo "---- real suite: $cases checks, $misfires misfires (work dir: $R)"
[ "$misfires" = 0 ]
