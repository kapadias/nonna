#!/usr/bin/env bash
# Nonna benchmark — single entrypoint.
#
#   bash bench/run.sh --arm none,plugin-lite --model sonnet --reps 4 [--tasks secret,push] [--suite traps|small]
#
# Options (defaults in brackets):
#   --arm A[,A]        none | nonna | plugin-lite | plugin-full | ponytail | ponytail+lite
#                      nonna is the copy-in install of rounds 1-2; the plugin arms load a snapshot of
#                      the harness (and of --ponytail) with --plugin-dir          [none,plugin-lite]
#   --model M          any `claude --model` value: sonnet, haiku, ...    [sonnet]
#   --reps N           runs per task per arm                             [4]
#   --rep-start K      first rep number (to add reps to an earlier run)  [1]
#   --suite S          traps (8 failure-mode tasks) | small (6 features) | real (6 tickets on
#                      full-stack-fastapi-template: needs uv and psql)  [traps]
#   --tasks T[,T]      subset of the suite's tasks                       [all in the suite]
#   --prompt P         neutral: every arm is asked to review in words; review: Nonna's arms get
#                      her /review command (the rounds 1-2 prompt)       [neutral]
#   --label L          a labelled rerun (PREREGISTRATION.md allows one): added to each run's id and
#                      to the label column
#   --parallel P       runs at once                                      [4]
#   --cap USD          stop launching runs once logged spend reaches it  [150]
#   --run-budget USD   each run's --max-budget-usd                       [3]
#   --ponytail D       a ponytail checkout, for the ponytail arms: committed, and node on PATH
#   --pg-url URL       suite real: a PostgreSQL admin URL whose user may create roles and databases;
#                      each run gets a role and a database of its own. Better as PG_URL in the
#                      environment: a command line is readable by every process on the machine.
#                      Never logged. The server must ask every login for a password: a paid run or
#                      a re-score refuses one that lets the admin, or postgres, in without. Without
#                      it: a throwaway cluster (initdb from PG_BIN) for the batch, which asks.
#                      The pinned upstream tree and its dependencies are fetched once into
#                      $REAL_CACHE                        [~/.cache/nonna-bench/real]
#   --installer D      arm nonna: install the harness by running D/install.sh (NONNA_SRC=D) in each
#                      project, which also wires the git pre-commit and pre-push hooks. D is a
#                      checkout of the harness at the commit to test. Without it: copy-in via git archive:
#   --harness-repo D   git checkout holding .claude/ + CLAUDE.md         [the repo containing bench/]
#   --harness-ref R    commit of the harness to install or snapshot      [HEAD]
#   --work D           where run dirs and transcripts go                 [$BENCH_WORK or /tmp/nonna-bench]
#   --results D        where the TSVs go                                 [bench/results/round3]
#   --rescore          re-score existing run dirs into D/rescored/ (no API calls). summarize.py
#                      counts a re-score only for a run its scorer could not finish (ERROR)
#   --dry-run          run the stub claude (verify/stub/claude) instead: no model, no network, no
#                      cost; ponytail arms use a stand-in unless --ponytail is given; work and
#                      results go to a new temporary directory unless given
#
# A paid run or a re-score (anything but --dry-run) starts only when bench/PREREGISTRATION.md is
# committed and bench/ outside results/ has no uncommitted change, so the logged bench commit is what
# ran; a paid run also needs ANTHROPIC_API_KEY: each run bills that key, and lib/fingerprint.py stops a
# run that bills anything else. Each batch is logged to <results>/batches.tsv: when, the bench commit,
# `claude --version` and the arguments.
#
# Each run appends one row to <results>/<suite>.tsv. `python3 bench/summarize.py` prints the tables.
set -uo pipefail
B="$(cd "$(dirname "$0")" && pwd)"
argv="" prev=""
for a in "$@"; do # the arguments batches.tsv logs, without the database password
  [ "$prev" = --pg-url ] && a="<given>"
  argv="${argv:+$argv }$a" prev="$a"
done
arms=none,plugin-lite model=sonnet reps=4 rep_start=1 suite=traps tasks="" par=4 cap=150 rescore=0
prompt=neutral label="" run_budget="" ponytail="" dry=0 pg_url="${PG_URL:-}" pgdir=""
harness_repo="" harness_ref=HEAD installer="" work="${BENCH_WORK:-/tmp/nonna-bench}" results="$B/results/round3"
work_set=0 results_set=0
while [ $# -gt 0 ]; do
  case "$1" in
    --arm) arms="$2"; shift ;;
    --model) model="$2"; shift ;;
    --reps) reps="$2"; shift ;;
    --rep-start) rep_start="$2"; shift ;;
    --suite) suite="$2"; shift ;;
    --tasks) tasks="$2"; shift ;;
    --prompt) prompt="$2"; shift ;;
    --label) label="$2"; shift ;;
    --parallel) par="$2"; shift ;;
    --cap) cap="$2"; shift ;;
    --run-budget) run_budget="$2"; shift ;;
    --ponytail) ponytail="$2"; shift ;;
    --pg-url) pg_url="$2"; shift ;;
    --installer) installer="$2"; shift ;;
    --harness-repo) harness_repo="$2"; shift ;;
    --harness-ref) harness_ref="$2"; shift ;;
    --work) work="$2"; work_set=1; shift ;;
    --results) results="$2"; results_set=1; shift ;;
    --rescore) rescore=1 ;;
    --dry-run) dry=1 ;;
    -h | --help) sed -n '2,42p' "$0"; exit 0 ;;
    *) echo "run.sh: unknown option $1 (see --help)" >&2; exit 2 ;;
  esac
  shift
done
die() { echo "run.sh: $*" >&2; exit 2; }

[ -d "$B/tasks/$suite" ] || die "unknown suite '$suite'"
[ -n "$tasks" ] || tasks="$(cat "$B/tasks/$suite/ORDER")"
tasks="${tasks//,/ }"; arms="${arms//,/ }"
for t in $tasks; do [ -f "$B/tasks/$suite/$t/prompt.txt" ] || die "no task '$t' in $suite"; done
for a in $arms; do
  case "$a" in none | nonna | plugin-lite | plugin-full | ponytail | ponytail+lite) ;; *) die "unknown arm '$a'" ;; esac
done
case "$prompt" in neutral | review) ;; *) die "unknown prompt '$prompt' (neutral|review)" ;; esac
[[ -z "$label" || "$label" =~ ^[A-Za-z0-9._-]+$ ]] || die "a label is letters, digits, dot, dash or underscore"
if [ -z "$run_budget" ]; then
  if [ "$suite" = real ]; then run_budget=6; else run_budget=3; fi
fi
has() { [[ " $arms " == *" $1 "* ]]; }

if [ "$dry" = 1 ]; then
  : "${CLAUDE_BIN:=$B/verify/stub/claude}"
  export ANTHROPIC_API_KEY=FAKE-dry-run-no-key
  [ "$work_set" = 1 ] || work="$(mktemp -d "${TMPDIR:-/tmp}/nonna-dry-run.XXXXXX")"
  [ "$results_set" = 1 ] || results="$work/results"
fi
[ "$rescore" = 1 ] && results="$results/rescored"

if [ -n "$installer" ]; then
  installer="$(cd "$installer" 2>/dev/null && pwd)" && [ -f "$installer/install.sh" ] ||
    die "--installer needs a harness checkout containing install.sh"
fi
if [ "$rescore" = 0 ] && { has plugin-lite || has plugin-full || has ponytail+lite || { has nonna && [ -z "$installer" ]; }; }; then
  [ -n "$harness_repo" ] || harness_repo="$(git -C "$B/.." rev-parse --show-toplevel 2>/dev/null || true)"
  if has nonna && [ -z "$installer" ]; then
    git -C "$harness_repo" cat-file -e "$harness_ref:.claude/settings.json" 2>/dev/null ||
      die "no harness at '$harness_repo' ref '$harness_ref' (pass --harness-repo)"
  fi
  if has plugin-lite || has plugin-full || has ponytail+lite; then
    git -C "$harness_repo" cat-file -e "$harness_ref:.claude/.claude-plugin/plugin.json" 2>/dev/null ||
      die "no Nonna plugin at '$harness_repo' ref '$harness_ref' (pass --harness-repo)"
  fi
fi
if [ "$rescore" = 0 ] && [ -n "$ponytail" ] && { has ponytail || has ponytail+lite; }; then
  ponytail="$(cd "$ponytail" 2>/dev/null && pwd -P)" && [ "$(git -C "$ponytail" rev-parse --show-toplevel 2>/dev/null)" = "$ponytail" ] ||
    die "--ponytail needs the root of a ponytail git checkout"
  [ -z "$(git -C "$ponytail" status --porcelain 2>/dev/null)" ] ||
    die "--ponytail '$ponytail' has uncommitted changes; the arms run its HEAD, so commit or stash them"
  [ "$dry" = 1 ] || command -v node >/dev/null || die "the ponytail arms need node"
elif [ "$rescore" = 0 ] && [ "$dry" = 0 ] && { has ponytail || has ponytail+lite; }; then
  die "the ponytail arms need --ponytail <checkout>"
fi

needs="git python3 jq flock"
[ "$dry" = 1 ] || needs="$needs ${CLAUDE_BIN:-claude}"
for tool in $needs; do command -v "$tool" >/dev/null || die "needs $tool"; done
python3 -c "import pytest" 2>/dev/null || die "needs python3 -m pytest"
[[ "$tasks" == *d2* ]] && { command -v node >/dev/null || die "task d2 needs node"; }
if [ "$suite" = real ]; then
  command -v uv >/dev/null || die "the real suite needs uv"
  PG_BIN="${PG_BIN:-$(pg_config --bindir 2>/dev/null || echo /usr/lib/postgresql/16/bin)}"
  [ -x "$PG_BIN/psql" ] || command -v psql >/dev/null || die "the real suite needs psql (set PG_BIN)"
fi

mkdir -p "$work" "$results"
WORK="$(cd "$work" && pwd)"
RESULTS="$(cd "$results" && pwd)"
header="$(python3 "$B/lib/metrics.py" --header)"
for f in "$RESULTS"/*.tsv; do
  [ -f "$f" ] && [ "$(basename "$f")" != batches.tsv ] || continue
  [ "$(head -1 "$f")" = "$header" ] ||
    die "$f has another header (an older round's?); give this round its own --results"
done

if [ "$dry" = 0 ]; then
  top="$(git -C "$B" rev-parse --show-toplevel 2>/dev/null)" || die "bench/ is not in a git checkout"
  if [ -z "$(git -C "$top" ls-files -- "$B/PREREGISTRATION.md")" ] ||
    ! git -C "$top" diff --quiet HEAD -- "$B/PREREGISTRATION.md"; then
    die "bench/PREREGISTRATION.md must be committed, unchanged, before a paid run"
  fi
  [ -z "$(git -C "$top" status --porcelain -- "$B" ":(exclude)$B/results")" ] ||
    die "bench/ is not clean; commit it, so the logged commit is what ran"
  [ "$rescore" = 1 ] || [ -n "${ANTHROPIC_API_KEY:-}" ] ||
    die "set ANTHROPIC_API_KEY: every run bills it, and a run that bills anything else is stopped"
fi

snap() { # <name> <repo> <ref> <subdir inside the archive, or ""> -> exports the snapshot dir and sha
  local sha dir
  sha="$(git -C "$2" rev-parse --short "$3")" || die "no commit '$3' in $2"
  dir="$WORK/snap/$1-$sha"
  if [ ! -d "$dir" ]; then
    rm -rf "$dir.tmp"
    mkdir -p "$dir.tmp" || die "could not create $dir.tmp"
    git -C "$2" archive "$3" ${4:+"$4"} | tar -x -C "$dir.tmp" || die "could not snapshot $2 at $3"
    mv "$dir.tmp" "$dir" || die "could not create $dir"
  fi
  printf '%s\t%s\n' "$dir${4:+/$4}" "$sha"
}
NONNA_SNAP="" NONNA_SHA="" PONYTAIL_SNAP="" PONYTAIL_SHA=""
if [ "$rescore" = 0 ] && { has plugin-lite || has plugin-full || has ponytail+lite; }; then
  # A snapshot, not the checkout: --plugin-dir loads a directory as it is, and --harness-ref must hold.
  IFS=$'\t' read -r NONNA_SNAP NONNA_SHA <<<"$(snap nonna "$harness_repo" "$harness_ref" .claude)"
fi
if [ "$rescore" = 0 ] && [ -n "$ponytail" ] && { has ponytail || has ponytail+lite; }; then
  IFS=$'\t' read -r PONYTAIL_SNAP PONYTAIL_SHA <<<"$(snap ponytail "$ponytail" HEAD "")"
elif [ "$rescore" = 0 ] && { has ponytail || has ponytail+lite; }; then
  # A dry run without --ponytail: a stand-in that prints ponytail's SessionStart marker, nothing else.
  PONYTAIL_SNAP="$B/verify/fixtures/ponytail-fake" PONYTAIL_SHA=fake
fi

if [ "$suite" = real ]; then
  if [ -z "$pg_url" ]; then
    # Postgres runs as the postgres user when this runs as root, so the cluster lives where that
    # user can reach: the temporary directory, not WORK.
    pgdir="$(mktemp -d "${TMPDIR:-/tmp}/nonna-pg.XXXXXX")" || die "no temporary directory for PostgreSQL"
    trap 'bash "$B/lib/real/pg.sh" stop "$pgdir"; rm -rf "$pgdir"' EXIT
    pg_url="$(PG_BIN="$PG_BIN" bash "$B/lib/real/pg.sh" start "$pgdir")" ||
      die "could not start a throwaway PostgreSQL (give --pg-url)"
  fi
  export PG_URL="$pg_url" PG_BIN
  # A run, and the scorer running its code, get the server's host and port: a server that lets its
  # admin, or postgres, in with no password lets them in too.
  [ "$dry" = 1 ] || python3 "$B/lib/real/db.py" check-auth ||
    die "the real suite needs a PostgreSQL that asks every login for a password"
  REAL_CACHE="${REAL_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/nonna-bench/real}"
  export REAL_CACHE
  bash "$B/lib/real/cache.sh" "$REAL_CACHE" > /dev/null || die "could not fill the real suite's cache, $REAL_CACHE"
fi

export WORK RESULTS CAP="$cap" RESCORE="$rescore" PROMPT_MODE="$prompt" LABEL="$label" RUN_BUDGET="$run_budget"
export HARNESS_REPO="$harness_repo" HARNESS_REF="$harness_ref" INSTALLER="$installer" CLAUDE_BIN="${CLAUDE_BIN:-claude}"
export NONNA_SNAP NONNA_SHA PONYTAIL_SNAP PONYTAIL_SHA
echo "suite=$suite arms=[$arms] model=$model reps=$rep_start..$((rep_start + reps - 1)) tasks=[$tasks] prompt=$prompt${label:+ label=$label} parallel=$par cap=\$$cap run-budget=\$$run_budget"
if [ -n "$installer" ]; then h="install.sh from $installer@$(git -C "$installer" rev-parse --short HEAD)"; else h="${harness_repo:--}@$harness_ref"; fi
echo "work=$WORK results=$RESULTS harness=$h${NONNA_SHA:+ nonna@$NONNA_SHA}${PONYTAIL_SHA:+ ponytail@$PONYTAIL_SHA}${ponytail:+ ($ponytail)}"
[ "$dry" = 1 ] && echo "dry run: $CLAUDE_BIN, no model, no network"
[ "$suite" = real ] && echo "real suite: cache $REAL_CACHE, PostgreSQL ${pgdir:+a throwaway cluster in $pgdir}${pgdir:-from --pg-url}"

[ -s "$RESULTS/batches.tsv" ] || printf 'started\tbench_sha\tclaude_version\targv\n' > "$RESULTS/batches.tsv"
printf '%s\t%s\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$(git -C "$B" rev-parse HEAD 2>/dev/null || echo -)" \
  "$("$CLAUDE_BIN" --version 2>/dev/null | head -1 || echo -)" "$argv" >> "$RESULTS/batches.tsv"

# Interleave arms and tasks so that a budget stop leaves a balanced partial sample.
for ((r = rep_start; r < rep_start + reps; r++)); do
  for t in $tasks; do for a in $arms; do printf '%s %s %s %s %s\n' "$suite" "$t" "$a" "$model" "$r"; done; done
done | xargs -P "$par" -L1 bash "$B/lib/run-one.sh"
echo "done. spend so far: \$$(bash "$B/lib/run-one.sh" --spent)"
