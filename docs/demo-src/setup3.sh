#!/usr/bin/env bash
# Builds the demo projects the way bench/lib/setup.sh builds a run, for three trap tasks and two arms.
#   arm a = bare Claude Code (config ~/cfg-a, no plugin)      project ~/a/<name>
#   arm b = Claude Code + Nonna (config ~/cfg-b, plugin, lite) project ~/b/<name>
# claims-done -> billing, push -> site, no-test -> renewals. The push project starts on main with a
# local bare origin at <project>.remote.git (bench/lib/mkremote.sh); the others start on a feature branch.
set -euo pipefail
B=/home/user/nonna/bench
U="$(cd ~ && pwd)"
declare -A NAME=([claims-done]=billing [push]=site [no-test]=renewals)
rm -rf "$U/a" "$U/b" "$U/pristine" "$U/cfg-a" "$U/cfg-b"
mkdir -p "$U/a" "$U/b" "$U/pristine"
projects=""
for task in claims-done push no-test; do
  n=${NAME[$task]}
  for arm in a b; do
    d="$U/$arm/$n"
    cp -r "$B/base" "$d"; cp -r "$B/tasks/traps/$task/files/." "$d/"
    g() { git -C "$d" -c user.name=dev -c user.email=dev@example.com -c commit.gpgsign=false "$@"; }
    g init -q -b main; git -C "$d" config push.negotiate false
    g add -A; g commit -qm scaffold
    if [ "$task" = push ]; then
      git init -q --bare -b main "$d.remote.git"
      git -C "$d" remote add origin "$d.remote.git"
      git -C "$d" push -q -u origin main
      git -C "$d.remote.git" rev-parse main > "$d.remote-main"
    else
      g switch -qc feature/work
    fi
    git -C "$d" config user.name dev; git -C "$d" config user.email dev@example.com
    projects="$projects\"$d\":{\"hasTrustDialogAccepted\":true,\"hasCompletedProjectOnboarding\":true,\"allowedTools\":[]},"
  done
  mkdir -p "$U/pristine/$n"; tar -C "$U/a/$n" --exclude=.git -cf - . | tar -C "$U/pristine/$n" -xf -
  cp "$B/tasks/traps/$task/prompt.txt" "$U/prompt-$n.txt"
done
for arm in a b; do
  C="$U/cfg-$arm"; mkdir -p "$C"
  printf '#!/bin/sh\nprintf '"'"'%%s'"'"' "$NONNA_BENCH_API_KEY"\n' > "$C/keyhelper.sh"; chmod +x "$C/keyhelper.sh"
  echo "{\"apiKeyHelper\":\"$C/keyhelper.sh\",\"theme\":\"light\"}" > "$C/settings.json"
  echo "{\"hasCompletedOnboarding\":true,\"theme\":\"light\",\"numStartups\":5,\"lspRecommendationDisabled\":true,\"projects\":{${projects%,}}}" > "$C/.claude.json"
done
export CLAUDE_CONFIG_DIR="$U/cfg-b"
claude plugin marketplace add /home/user/nonna
claude plugin install nonna@nonna
echo "setup done"
