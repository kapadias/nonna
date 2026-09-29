#!/usr/bin/env bash
# usage: launch.sh <first-n> <last-n>  — records pairs first..last for all three tasks, concurrently.
S=/tmp/claude-0/-home-user-nonna/51c91238-79bf-5d1e-ab22-9a52c08a3fb8/scratchpad/v3
for t in claims-done push no-test; do
  nohup bash -c "for n in \$(seq $1 $2); do $S/pair3.sh $t \$n; done" > "$S/loop-$t-$1-$2.log" 2>&1 &
done
echo launched
