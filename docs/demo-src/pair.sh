#!/usr/bin/env bash
set -u
S=/tmp/claude-0/-home-user-nonna/51c91238-79bf-5d1e-ab22-9a52c08a3fb8/scratchpad/v2
N=$1; P=$S/pairs/$N; rm -rf $P; mkdir -p $P
for a in bare nonna; do
  d=$HOME/$a-app; git -C $d reset -q --hard; git -C $d clean -fdxq; git -C $d switch -q fix/rounding
  rm -rf $HOME/cfg-$a/projects $HOME/cfg-$a/sessions 2>/dev/null
done
tmux kill-server 2>/dev/null; tmux start-server; tmux set -g focus-events on
for a in bare nonna; do
  tmux new-session -d -s $a -x 70 -y 30 "bash --norc -i"; tmux set -t $a status off
  tmux send-keys -t $a "ARM=$a source $S/rc.sh; clear; asciinema rec -q --cols 70 --rows 30 -c 'bash --norc -i' $P/$a.cast" Enter
done
sleep 2
for a in bare nonna; do tmux send-keys -t $a "ARM=$a source $S/rc.sh; clear" Enter; done; sleep 1.5
for a in bare nonna; do tmux send-keys -t $a "claude" Enter; done; sleep 8
tmux load-buffer -b p ~/demo-prompt.txt
for a in bare nonna; do tmux paste-buffer -b p -t $a; done; sleep 4
date +%s.%N > $P/submit.txt
for a in bare nonna; do tmux send-keys -t $a Enter; done; sleep 3
for a in bare nonna; do tmux send-keys -t $a Enter; done
declare -A c=([bare]=0 [nonna]=0)
for i in $(seq 1 180); do sleep 3
  for a in bare nonna; do t=$(tmux capture-pane -t $a -p)
    if echo "$t" | grep -qE "for .* · done [0-9]+:[0-9]{2} [AP]M" && ! echo "$t" | grep -qE "esc to interrupt|tasting"; then c[$a]=$((c[$a]+1)); else c[$a]=0; fi
  done
  [ ${c[bare]} -ge 5 ] && [ ${c[nonna]} -ge 5 ] && break
done
for a in bare nonna; do tmux send-keys -t $a "/cost" Enter; done; sleep 5
for a in bare nonna; do tmux capture-pane -t $a -p > $P/$a.cost.txt; done
sleep 2
for a in bare nonna; do tmux send-keys -t $a "/exit" Enter; done; sleep 3
for a in bare nonna; do tmux send-keys -t $a "exit" Enter; done; sleep 2
tmux kill-server 2>/dev/null
for a in bare nonna; do cp -r $HOME/cfg-$a/projects $P/$a.transcripts 2>/dev/null; git -C $HOME/$a-app diff > $P/$a.diff; done
echo finished $N
