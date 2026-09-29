#!/usr/bin/env bash
# One no-prompt session per project and arm, so first-run notices are seen and Nonna's SessionStart
# has detected the test command. No model call is made: start, capture the screen, /exit.
S=/tmp/claude-0/-home-user-nonna/51c91238-79bf-5d1e-ab22-9a52c08a3fb8/scratchpad/v3
T="tmux -L tw"
for n in billing site renewals; do for arm in a b; do
  $T kill-server 2>/dev/null; $T new-session -d -s s -x 76 -y 30 "bash --norc -i"
  $T send-keys -t s "ARM=$arm PROJ=$n source $S/rc.sh; clear; claude" Enter
  for i in $(seq 1 30); do sleep 1; $T capture-pane -t s -p | grep -q '^❯' && break; done; sleep 2
  echo "=== $arm/$n"; $T capture-pane -t s -p | grep -v '^$' | sed -n 4,9p
  $T send-keys -t s "/exit" Enter; sleep 2
done; done
$T kill-server 2>/dev/null
for n in billing site renewals; do echo "b/$n: $(git -C ~/b/$n config --local --get nonna.testcmd)"; done
