#!/usr/bin/env bash
# usage: pair3.sh <task> <n>   task: claims-done | push | no-test
# Records one side-by-side pair: arm a (bare) and arm b (Nonna) in two tmux panes (own tmux server per
# task), 76x30 each, under asciinema. Both prompts are pasted and submitted at the same moment. After
# both agents are idle: /cost, /exit, then the task's reveal commands run in the same shell, in the cast.
# Then the bench's hidden check scores the live tree, and the projects are reset.
set -u
S=/tmp/claude-0/-home-user-nonna/51c91238-79bf-5d1e-ab22-9a52c08a3fb8/scratchpad/v3
B=/home/user/nonna/bench
U="$(cd ~ && pwd)"
task=$1; N=$2
case $task in claims-done) n=billing;; push) n=site;; no-test) n=renewals;; *) echo bad task; exit 2;; esac
P=$S/pairs/$task/$N; rm -rf "$P"; mkdir -p "$P"
T="tmux -L $task -f $S/focus.conf"

reset_proj() {
  local arm=$1 d=$U/$arm/$n
  if [ "$task" = push ]; then
    local orig; orig=$(cat "$d.remote-main")
    git -C "$d" switch -q main 2>/dev/null || git -C "$d" checkout -q main
    git -C "$d" reset -q --hard "$orig"; git -C "$d" clean -fdxq
    for br in $(git -C "$d" for-each-ref --format='%(refname:short)' refs/heads | grep -vx main); do git -C "$d" branch -qD "$br"; done
    git -C "$d.remote.git" update-ref refs/heads/main "$orig"
    for br in $(git -C "$d.remote.git" for-each-ref --format='%(refname:short)' refs/heads | grep -vx main); do git -C "$d.remote.git" update-ref -d "refs/heads/$br"; done
    git -C "$d" fetch -q --prune origin; git -C "$d" update-ref refs/remotes/origin/main "$orig"
  else
    git -C "$d" reset -q --hard; git -C "$d" clean -fdxq; git -C "$d" switch -q feature/work
  fi
  rm -rf "$U/cfg-$arm-$task/projects" "$U/cfg-$arm-$task/sessions" "$U/cfg-$arm-$task/todos" 2>/dev/null
}
for arm in a b; do reset_proj $arm; done

$T kill-server 2>/dev/null
for arm in a b; do
  $T new-session -d -s $arm -x 76 -y 30 "bash --norc -i"
  $T send-keys -t $arm "ARM=$arm PROJ=$n TASK=$task source $S/rc.sh; clear; asciinema rec -q --cols 76 --rows 30 -c 'bash --norc -i' $P/$arm.cast" Enter
done
sleep 2
for arm in a b; do $T send-keys -t $arm "ARM=$arm PROJ=$n TASK=$task source $S/rc.sh; clear" Enter; done; sleep 1.5
for arm in a b; do $T send-keys -t $arm "claude" Enter; done
for i in $(seq 1 40); do sleep 1
  ok=1; for arm in a b; do $T capture-pane -t $arm -p | grep -q '^❯' || ok=0; done
  [ $ok = 1 ] && break
done
sleep 2
$T load-buffer -b p "$U/prompt-$n.txt"
for arm in a b; do $T paste-buffer -b p -t $arm; done; sleep 4
date +%s.%N > "$P/submit.txt"
for arm in a b; do $T send-keys -t $arm Enter; done; sleep 3
for arm in a b; do $T send-keys -t $arm Enter; done
declare -A c=([a]=0 [b]=0)
for i in $(seq 1 200); do sleep 3
  for arm in a b; do t=$($T capture-pane -t $arm -p)
    if echo "$t" | grep -qE "· done [0-9]+:[0-9]{2} [AP]M" && ! echo "$t" | grep -qE "esc to interrupt|tasting"; then c[$arm]=$((c[$arm]+1)); else c[$arm]=0; fi
  done
  [ ${c[a]} -ge 5 ] && [ ${c[b]} -ge 5 ] && break
done
for arm in a b; do $T send-keys -t $arm "/cost" Enter; done; sleep 5
for arm in a b; do $T capture-pane -t $arm -p > "$P/$arm.cost.txt"; done
sleep 1
# the /cost screen is a modal: close it before leaving the session
for arm in a b; do $T send-keys -t $arm Escape; done; sleep 1.5
for arm in a b; do $T send-keys -t $arm "/exit" Enter; done
shell_ready() { $T capture-pane -t $1 -p | grep -v '^$' | tail -1 | grep -q '^\$ *$'; }
for i in $(seq 1 20); do sleep 1
  ok=1; for arm in a b; do shell_ready $arm || ok=0; done
  [ $ok = 1 ] && break
done
if [ $ok != 1 ]; then  # fallback: the dialog may still be open
  for arm in a b; do shell_ready $arm || { $T send-keys -t $arm Escape; sleep 1; $T send-keys -t $arm "/exit" Enter; }; done
  for i in $(seq 1 15); do sleep 1; ok=1; for arm in a b; do shell_ready $arm || ok=0; done; [ $ok = 1 ] && break; done
fi
sleep 1
case $task in
  claims-done) reveal=("clear" "python3 -m pytest -q") ;;
  push)        reveal=("clear" "git log --oneline origin/main") ;;
  no-test)     reveal=("clear" "git status --short" "python3 -m pytest -q") ;;
esac
for cmd in "${reveal[@]}"; do
  for arm in a b; do $T send-keys -t $arm "$cmd" Enter; done; sleep 3.5
done
sleep 2
for arm in a b; do $T send-keys -t $arm "exit" Enter; done; sleep 2
$T kill-server 2>/dev/null

# score the live tree with the bench's own hidden check, then keep the evidence
for arm in a b; do
  d=$U/$arm/$n
  cp -r "$U/cfg-$arm-$task/projects" "$P/$arm.transcripts" 2>/dev/null
  python3 "$S/lastmsg.py" "$U/cfg-$arm-$task/projects" > "$P/$arm.msg.txt"
  tar --exclude=.git -czf "$P/$arm.tree.tgz" -C "$d" .
  git -C "$d" status --short > "$P/$arm.status.txt"; git -C "$d" diff > "$P/$arm.diff"
  case $task in
    claims-done) ( cd "$d" && bash "$B/hidden/claims-done.sh" "$U/pristine/$n" "$P/$arm.msg.txt" ) > "$P/$arm.check.txt" 2>&1 ;;
    push)        ( cd "$d" && bash "$B/hidden/push.sh" "$d.remote.git" "$(cat "$d.remote-main")" ) > "$P/$arm.check.txt" 2>&1
                 git -C "$d" log --oneline -5 --all --decorate > "$P/$arm.gitlog.txt" ;;
    no-test)     ( cd "$d" && PYTHONPATH=. python3 "$B/hidden/no-test.py" "$U/pristine/$n" ) > "$P/$arm.check.txt" 2>&1 ;;
  esac
  echo "exit=$?" >> "$P/$arm.check.txt"
done
for arm in a b; do reset_proj $arm; done
echo "finished $task $N"
