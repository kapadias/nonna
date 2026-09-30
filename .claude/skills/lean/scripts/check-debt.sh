#!/usr/bin/env bash
# check-debt.sh — the debt-marker gate and ledger.
#
# A deliberate simplification with a known ceiling is marked in code with a comment of
# the form  <comment-prefix> debt: <ceiling>, <upgrade trigger>  — the text after the
# first comma is the trigger to revisit it. A marker with no trigger is "later means
# never" waiting to happen, so this script fails on it. The model proposes the corner;
# the script decides the marker is well-formed.
#
# Usage: check-debt.sh [--ledger] [--range <git-range>] [PATH...]
#   default   scan PATH... (or .) for markers; skips VCS/dependency/build dirs and *.md
#             (prose that quotes the convention is not debt)
#   --range   scan only lines ADDED by `git diff <git-range>` — a PR is gated on the debt
#             it introduces, not on debt someone else left
#   --ledger  print the grouped ledger to stdout (exit code unchanged)
# Exit: 0 every marker names a trigger · 1 at least one does not · 2 usage error,
#       --range outside a git repo, an unresolvable range, or a tool that fails (fail closed).
# The comma is the only separator; a ceiling that needs a comma gets reworded. If real
# markers ever need a second separator, add it here and in the lean skill together.
set -uo pipefail
# Bytes, not the locale's characters: a file may hold a byte that is not text in the user's
# locale, and macOS's grep, tr, sed and sort stop at one, which would drop its marker.
export LC_ALL=C

PATTERN='(#|//) ?debt:'
SKIP_DIRS=(.git node_modules dist build target vendor .venv venv __pycache__ coverage htmlcov)

usage() { sed -n '10,17p' "$0" >&2; exit 2; }

ledger=0; range=""; range_given=0; paths=()
while [ $# -gt 0 ]; do
  case "$1" in
    --ledger) ledger=1 ;;
    --range) [ $# -ge 2 ] || usage; range="$2"; range_given=1; shift ;;
    --range=*) range="${1#--range=}"; range_given=1 ;;
    -h|--help) usage ;;
    --) shift; paths+=("$@"); break ;;
    -*) printf 'check-debt: unknown option %s\n' "$1" >&2; usage ;;
    *) paths+=("$1") ;;
  esac
  shift
done
[ ${#paths[@]} -gt 0 ] || paths=(.)
# A range is data: empty or option-shaped (leading '-') is a usage error, never git's problem.
if [ "$range_given" -eq 1 ]; then
  case "$range" in ''|-*) printf 'check-debt: --range needs a git range, got %s\n' "'$range'" >&2; exit 2 ;; esac
fi

# Collect candidate lines as  path<TAB>line:text  — one source per mode. A tab, not a
# colon, separates the path: a path may contain colons, and a crafted one could otherwise
# smuggle a fake ", trigger" into the classifier.
collect() {
  if [ -n "$range" ]; then
    git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
      printf 'check-debt: --range needs a git repository\n' >&2; return 2; }
    local diff
    # --end-of-options: the range is data, never a git option (--output=<path> would write
    # the diff over any file from a pre-approved gate call). --no-color/--no-ext-diff: user
    # config must not hide the +++ headers or replace the diff we parse. --text/--no-textconv:
    # a PR-controlled .gitattributes (-diff, binary) must not turn added lines into
    # "Binary files differ".
    # core.quotePath=false: a non-ASCII path arrives as bytes, not as a quoted C string.
    diff="$(git -c core.quotePath=false diff --no-color --no-ext-diff --text --no-textconv -U0 --inter-hunk-context=0 --no-prefix --no-renames --end-of-options "$range" -- . ':(exclude)*.md' 2>/dev/null)" || {
      printf 'check-debt: cannot resolve range %s\n' "$range" >&2; return 2; }
    # rem = added lines still owed by the current hunk (from the @@ header), so an added
    # line that itself begins "++ " is content, never mistaken for the next +++ header.
    # git appends a TAB to a +++ header whose path contains a space; strip it.
    printf '%s\n' "$diff" | awk -v pat="$PATTERN" '
      /^@@/ {
        ln = 0; rem = 1
        if (match($0, /\+[0-9]+(,[0-9]+)?/)) {
          r = substr($0, RSTART + 1, RLENGTH - 1); c = index(r, ",")
          ln = (c ? substr(r, 1, c - 1) : r) + 0; rem = (c ? substr(r, c + 1) : 1) + 0
        }
        next
      }
      rem > 0 && /^\+/ { if (file != "/dev/null" && substr($0, 2) ~ pat) printf "%s\t%d:%s\n", file, ln, substr($0, 2); ln++; rem--; next }
      /^\+\+\+ / { file = substr($0, 5); sub(/\t$/, "", file); rem = 0; next }'
  else
    local args=() d p rc
    local i
    for i in "${!paths[@]}"; do
      p="${paths[$i]}"
      [ -e "$p" ] || { printf 'check-debt: no such path %s\n' "$p" >&2; return 2; }
      case "$p" in -*) paths[i]="./$p" ;; esac   # grep reads "-" as stdin even after --
    done
    # A tab or newline in a path would let the path forge a record (the classifier splits
    # on the tab grep's NUL becomes). Refuse such trees outright: exit 2, never a guess.
    local prune=() hit
    for d in "${SKIP_DIRS[@]}"; do prune+=(-name "$d" -prune -o); done
    hit="$(find "${paths[@]}" "${prune[@]}" \( -path "*"$'\t'"*" -o -path "*"$'\n'"*" \) -print -quit)" \
      || { printf 'check-debt: find failed — refusing to scan\n' >&2; return 2; }
    if [ -n "$hit" ]; then
      printf 'check-debt: a path contains a tab or newline — rename it before scanning\n' >&2; return 2
    fi
    for d in "${SKIP_DIRS[@]}"; do args+=("--exclude-dir=$d"); done
    # -a: a NUL byte must not make a file "binary" and skipped; -H: a single-file operand
    # still carries its name; LC_ALL=C: an invalid UTF-8 byte must not skip the file either,
    # nor stop tr or sed, which on macOS refuse a byte that is not text in the user's locale;
    # --null, not -Z, which macOS's grep reads as --decompress and so writes no NUL at all.
    LC_ALL=C grep -rnHaE --null "${args[@]}" --exclude='*.md' -- "$PATTERN" "${paths[@]}" \
      | LC_ALL=C tr '\0' '\t' | LC_ALL=C sed 's#^\./##'
    rc=${PIPESTATUS[0]}
    [ "$rc" -le 1 ] || { printf 'check-debt: grep failed (%s)\n' "$rc" >&2; return 2; }
  fi
  return 0
}

hits="$(collect)"; rc=$?
[ "$rc" -eq 0 ] || exit "$rc"

# Classify: split the marker text at the first comma; both halves must be non-empty.
rows="$(printf '%s\n' "$hits" | awk -v pat="$PATTERN" '
  /^$/ { next }
  {
    # A record that does not parse (a tab in the file name) is a failure, never a skip:
    # a gate that drops what it cannot read fails open.
    t = index($0, "\t"); file = (t ? substr($0, 1, t - 1) : $0); rest = (t ? substr($0, t + 1) : "")
    c = index(rest, ":"); ln = (c ? substr(rest, 1, c - 1) : ""); rest = (c ? substr(rest, c + 1) : "")
    if (t == 0 || c == 0 || ln !~ /^[0-9]+$/) { printf "%s\t0\t0\tunparsable record\t\n", file; next }
    if (!match(rest, pat)) next
    text = substr(rest, RSTART + RLENGTH); sub(/\r$/, "", text)
    i = index(text, ",")
    ceiling = (i > 0) ? substr(text, 1, i - 1) : text
    trigger = (i > 0) ? substr(text, i + 1) : ""
    gsub(/^[ \t]+|[ \t]+$/, "", ceiling); gsub(/^[ \t]+|[ \t]+$/, "", trigger)
    ok = (ceiling != "" && trigger != "") ? 1 : 0
    printf "%s\t%s\t%d\t%s\t%s\n", file, ln, ok, ceiling, trigger
  }' | sort -t "$(printf '\t')" -k1,1 -k2,2n)" \
  || { printf 'check-debt: cannot classify the markers — refusing to pass them\n' >&2; exit 2; }

total=0; bad=0
if [ -n "$rows" ]; then
  total="$(printf '%s\n' "$rows" | wc -l | tr -d ' ')"
  bad="$(printf '%s\n' "$rows" | awk -F'\t' '$3 == 0' | wc -l | tr -d ' ')"
fi

if [ "$ledger" -eq 1 ]; then
  if [ "$total" -eq 0 ]; then
    echo "No debt markers. Clean ledger."
  else
    printf '%s\n' "$rows" | awk -F'\t' '
      $1 != last { print $1; last = $1 }
      { if ($3 == 1) printf "  L%s: %s — upgrade: %s\n", $2, $4, $5
        else          printf "  L%s: %s — no-trigger\n", $2, $4 }'
    printf '%s markers, %s with no trigger.\n' "$total" "$bad"
  fi
fi

if [ "$bad" -gt 0 ]; then
  printf '%s\n' "$rows" | awk -F'\t' '$3 == 0 { printf "✗ check-debt: %s:%s: no-trigger — %s\n", $1, $2, $4 }' >&2
  printf '✗ check-debt: %s marker(s), %s with no trigger — name the trigger after the comma.\n' "$total" "$bad" >&2
  exit 1
fi
printf '✓ check-debt: %s marker(s), 0 with no trigger.\n' "$total" >&2
exit 0
