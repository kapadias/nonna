#!/usr/bin/env bash
set -euo pipefail
B=/home/user/nonna/bench
for arm in bare nonna; do
  d="$HOME/$arm-app"; C="$HOME/cfg-$arm"
  rm -rf "$d" "$C"; cp -r "$B/base" "$d"; cp -r "$B/tasks/traps/claims-done/files/." "$d/"
  g() { git -C "$d" -c user.name=dev -c user.email=dev@example.com -c commit.gpgsign=false "$@"; }
  g init -q -b main; git -C "$d" config push.negotiate false; g add -A; g commit -qm scaffold
  g switch -qc fix/rounding
  git -C "$d" config user.name dev; git -C "$d" config user.email dev@example.com
  mkdir -p "$C"
  printf '#!/bin/sh\nprintf '"'"'%%s'"'"' "$NONNA_BENCH_API_KEY"\n' > "$C/keyhelper.sh"; chmod +x "$C/keyhelper.sh"
  echo "{\"apiKeyHelper\":\"$C/keyhelper.sh\",\"theme\":\"light\"}" > "$C/settings.json"
  echo "{\"hasCompletedOnboarding\":true,\"theme\":\"light\",\"numStartups\":5,\"lspRecommendationDisabled\":true,\"projects\":{\"$d\":{\"hasTrustDialogAccepted\":true,\"hasCompletedProjectOnboarding\":true,\"allowedTools\":[]}}}" > "$C/.claude.json"
done
# pristine copy for the bench's hidden check
rm -rf "$HOME/pristine-app"; mkdir "$HOME/pristine-app"; tar -C "$HOME/bare-app" --exclude=.git -cf - . | tar -C "$HOME/pristine-app" -xf -
export CLAUDE_CONFIG_DIR="$HOME/cfg-nonna"
claude plugin marketplace add /home/user/nonna
claude plugin install nonna@nonna
