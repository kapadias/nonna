# usage: ARM=bare|nonna source rc.sh
export CLAUDE_CONFIG_DIR="$HOME/cfg-$ARM"
export PS1='$ '
export TERM=xterm-256color
export DISABLE_AUTOUPDATER=1
claude() { command claude --model haiku --permission-mode acceptEdits --allowedTools "Bash,Edit,Write,MultiEdit,Read,Glob,Grep" "$@"; }
cd "$HOME/$ARM-app"
