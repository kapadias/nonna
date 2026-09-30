#!/usr/bin/env bash
# What native Windows does to Nonna's hooks, as facts: one "probe <name>: <result>" line each. Run it in
# Git Bash from a clone (bash tests/windows-probe.sh), or read the log of CI's Windows job, which runs it;
# docs/INSTALL.md's Windows section is written from that output.
#
# It reports and never fails, and changes nothing outside one temporary directory. "designed" is what a gate
# is meant to do with that input (on Linux and macOS, with the POSIX form of it); DIFFERS marks a gate that
# does something else. The inputs only Windows sends are the shapes Claude Code's hooks documentation gives:
# file paths with backslashes, and commands sent by the PowerShell tool.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)" || exit 0
trap 'rm -rf "$tmp"' EXIT

say() { printf 'probe %s: %s\n' "$1" "$2"; }
ver() { # <command...>: the first line of its version output, or the error it gave
  local out
  command -v "$1" >/dev/null 2>&1 || { printf '(not found)'; return; }
  out="$("$@" 2>&1 </dev/null | head -n 1 | cut -c1-110)"
  printf '%s' "${out:-(no output)}"
}

# 1. The machine, before any isolation: which tools the hooks will find, and in what order.
say os "$(uname -srm) | bash $BASH_VERSION | OSTYPE=$OSTYPE MSYSTEM=${MSYSTEM-unset} MSYS=${MSYS-unset}"
say git "$(git --version 2>&1) | system core.autocrlf=$(git config --system --get core.autocrlf 2>/dev/null || echo unset) core.symlinks=$(git config --system --get core.symlinks 2>/dev/null || echo unset) | effective core.autocrlf=$(git config --get core.autocrlf 2>/dev/null || echo unset)"
for t in awk sed grep find sort tr mktemp timeout perl jq python3 python; do
  say "tool $t" "$(type -ap "$t" 2>/dev/null | head -n 3 | tr '\n' ' ')"
done
say "version awk" "$(ver awk --version)"
say "version sed" "$(ver sed --version)"
say "version grep" "$(ver grep --version)"
say "version timeout" "$(ver timeout --version)"
say "version perl" "$(ver perl -e 'print "perl $^V\n"')"
say "version jq" "$(ver jq --version)"
# A native jq.exe under Git Bash writes CRLF (the jq manual, under --binary): every value it prints ends in CR.
if command -v jq >/dev/null 2>&1; then
  say "jq -r output, bytes" "$(jq -nr '"x"' 2>&1 | od -An -c | tr -s ' ') (LF: x \\n; CRLF: x \\r \\n)"
  say "jq -b -r output, bytes" "$(jq -b -nr '"x"' 2>&1 | od -An -c | tr -s ' ' | cut -c1-90)"
fi
say "version python3" "$(ver python3 --version)"
say "path (first 10)" "$(printf '%s' "$PATH" | tr ':' '\n' | head -n 10 | tr '\n' ' ')"
cygw="$(command -v cygpath 2>/dev/null || true)"
say paths "pwd=$PWD | git top=$(git -C "$ROOT" rev-parse --show-toplevel 2>/dev/null) | cygpath -w=$([ -n "$cygw" ] && cygpath -w "$ROOT") | cygpath -m=$([ -n "$cygw" ] && cygpath -m "$ROOT")"

# 2. Line endings. A plugin is installed by git clone, and Git for Windows clones with core.autocrlf=true.
if git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
  n=$(git -C "$ROOT" ls-files -z '*.sh' '*.awk' | xargs -0 grep -l "$(printf '\r')" 2>/dev/null | wc -l | tr -d ' ')
  say "eol of this checkout" "$n of $(git -C "$ROOT" ls-files '*.sh' '*.awk' | wc -l | tr -d ' ') tracked .sh and .awk files hold CRLF | $(git -C "$ROOT" ls-files --eol .claude/hooks/pre-commit.sh | tr -s ' \t' ' ')"
  if git clone -q --no-local -c core.autocrlf=true "$ROOT" "$tmp/crlf" 2>/dev/null; then
    say "eol of a clone with core.autocrlf=true" "$(git -C "$tmp/crlf" ls-files --eol .claude/hooks/guard-branch.sh | tr -s ' \t' ' ')"
    # A harmless command: the branch guard must let it through (0). Exit 127 is a hook that cannot start, which
    # Claude Code goes on from; exit 2 is a block, and on a PreToolUse hook it stops every tool call.
    benign='{"tool_name":"Bash","tool_input":{"command":"git status"}}'
    printf '%s' "$benign" | "$tmp/crlf/.claude/hooks/guard-branch.sh" >/dev/null 2>"$tmp/err"
    rc=$?
    say "CRLF hook started by its path" "exit $rc (designed 0) | $(head -n 1 "$tmp/err" | tr -d '\r' | cut -c1-110)"
    printf '%s' "$benign" | bash "$tmp/crlf/.claude/hooks/guard-branch.sh" >/dev/null 2>"$tmp/err"
    rc=$?
    say "CRLF hook started by bash" "exit $rc (designed 0) | $(head -n 1 "$tmp/err" | tr -d '\r' | cut -c1-110)"
  fi
fi

# From here on, git judges a scratch repository on defaults, never on this machine's configuration.
export GIT_CONFIG_GLOBAL="$tmp/gitconfig" GIT_CONFIG_NOSYSTEM=1
: >"$GIT_CONFIG_GLOBAL"
G=(git -c user.email=probe@example.invalid -c user.name=probe -c init.defaultBranch=main)

# 3. Symbolic links: Git Bash's ln -s makes a copy unless MSYS=winsymlinks:nativestrict is set.
(
  cd "$tmp" && mkdir lnt && cd lnt && printf 'x\n' >target && mkdir dir
  ln -s target link 2>"$tmp/err"
  if [ -L link ]; then r="a symlink -> $(readlink link)"; elif [ -e link ]; then r="a COPY, not a link"; else r="no file: $(head -n 1 "$tmp/err")"; fi
  say "ln -s file" "$r"
  ln -sfn dir cur 2>"$tmp/err"
  if [ -L cur ]; then r="a symlink"; elif [ -e cur ]; then r="a COPY, not a link"; else r="nothing: $(head -n 1 "$tmp/err")"; fi
  say "ln -sfn directory" "$r"
)

# 4. timeout(1) and the perl fallback behind it (lib/tests.sh).
out="$(timeout 5 bash -c 'exit 7' 2>&1)"
rc=$?
say "timeout runs a command" "exit $rc (GNU: 7) ${out:+| $(printf '%s' "$out" | head -n 1 | cut -c1-90)}"
out="$(perl -e 'setpgrp(0, 0); print "setpgrp ok"' 2>&1)"
rc=$?
say "perl setpgrp" "exit $rc | $(printf '%s' "$out" | head -n 1 | cut -c1-90)"

# 5. The gates, started the way Claude Code starts a plugin hook (the plugin root as C:/... on Windows), fed
#    what the tools deliver there. A scratch repository on main stands in for the project.
repo="$tmp/project"
mkdir -p "$repo" && "${G[@]}" -C "$repo" init -q && "${G[@]}" -C "$repo" commit -q --allow-empty -m init
form() { # <w|m|p> <posix path>: a path as Windows writes it (w backslashes, m forward slashes) or as given (p)
  local p="C:$2"
  case "$1$cygw" in
    w?*) cygpath -w "$2" ;;
    m?*) cygpath -m "$2" ;;
    w) printf '%s' "${p//\//\\}" ;;
    m) printf '%s' "$p" ;;
    *) printf '%s' "$2" ;;
  esac
}
json() { printf '%s' "${1//\\/\\\\}"; } # a path as the inside of a JSON string
hook() { # <script> <payload> [plugin root]: the exit code of the hook, started as hooks.json starts it
  printf '%s' "$2" | CLAUDE_PROJECT_DIR="$repo" CLAUDE_PLUGIN_ROOT="${3:-$ROOT/.claude}" \
    bash -c '"${CLAUDE_PLUGIN_ROOT}"/hooks/'"$1" >/dev/null 2>"$tmp/err"
  echo $?
}
want() { # <name> <designed exit> <script> <payload> [plugin root]
  local got
  got="$(hook "$3" "$4" "${5:-}")"
  if [ "$got" = "$2" ]; then r=ok; else r="DIFFERS"; fi
  say "$1" "exit $got (designed $2) $r"
}
bash_cmd() { printf '{"tool_name":"%s","tool_input":{"command":"%s"}}' "$1" "$2"; }
file_tool() { printf '{"tool_name":"%s","tool_input":{"file_path":"%s"%s}}' "$1" "$(json "$2")" "${3:-}"; }
WB="$(form w "$repo")"
for f in p m w; do
  if [ "$f" = p ] || [ -n "$cygw" ]; then
    want "guard: force push, CLAUDE_PLUGIN_ROOT as $f" 2 guard-branch.sh "$(bash_cmd Bash 'git push --force origin feature/x')" "$(form $f "$ROOT/.claude")"
  fi
done
want "guard: commit on main (Bash tool)" 2 guard-branch.sh "$(bash_cmd Bash 'git commit -m x')"
want "guard: force push (PowerShell tool)" 2 guard-branch.sh "$(bash_cmd PowerShell 'git push --force origin feature/x')"
want "guard: force push by git.exe" 2 guard-branch.sh "$(bash_cmd Bash 'git.exe push --force origin feature/x')"
want "guard: Edit of .git/config (path as given)" 2 guard-branch.sh "$(file_tool Edit "$repo/.git/config")"
want "guard: Edit of .git\\config (backslashes)" 2 guard-branch.sh "$(file_tool Edit "$WB\\.git\\config")"
want "guard: Write of .git\\hooks\\pre-commit (backslashes)" 2 guard-branch.sh "$(file_tool Write "$WB\\.git\\hooks\\pre-commit")"
want "guard: a script run in her skill directory (cwd with backslashes)" 2 guard-branch.sh \
  "$(printf '{"tool_name":"Bash","cwd":"%s","tool_input":{"command":"bash setup.sh"}}' "$(json 'C:\x\.claude\skills\nonna\scripts')")"
want "secret: Read of .env (path as given)" 2 secret-scan.sh "$(file_tool Read "$repo/.env")"
want "secret: Read of .env (backslashes)" 2 secret-scan.sh "$(file_tool Read "$WB\\.env")"
want "secret: Read of .ssh\\id_rsa (backslashes)" 2 secret-scan.sh "$(file_tool Read "$WB\\.ssh\\id_rsa")"
want "secret: Read of secrets\\db.yml (backslashes)" 2 secret-scan.sh "$(file_tool Read "$WB\\secrets\\db.yml")"
want "secret: Get-Content .env (PowerShell tool)" 2 secret-scan.sh "$(bash_cmd PowerShell 'Get-Content .env')"
key="AKIA""1234567890ABCDEF" # split, so this file holds no key-shaped literal
want "secret: Write of a key (backslashes)" 2 secret-scan.sh "$(file_tool Write "$WB\\src\\app.py" ",\"content\":\"k = '$key'\"")"
want "secret: Write of a key under tests\\ (the fixture exemption)" 0 secret-scan.sh "$(file_tool Write "$WB\\tests\\app.py" ",\"content\":\"k = '$key'\"")"

# 6. The git hooks, wired the way session-start.sh wires a copy-in install: with this shell's ln -s. A staged
#    key must stop the commit whether the hook is a link or not; a hook that is a copy cannot find its lib/.
wired="$tmp/wired"
mkdir -p "$wired/.claude" && cp -R "$ROOT/.claude/hooks" "$wired/.claude/hooks"
"${G[@]}" -C "$wired" init -q && "${G[@]}" -C "$wired" commit -q --allow-empty -m init
out="$(printf '{"session_id":"probe"}' | CLAUDE_PROJECT_DIR="$wired" bash "$wired/.claude/hooks/session-start.sh" 2>&1 | tr -d '\n')"
for h in pre-commit pre-push; do
  if [ -L "$wired/.git/hooks/$h" ]; then r="a symlink"; elif [ -e "$wired/.git/hooks/$h" ]; then r="a COPY (no lib/ beside it)"; else r="not installed"; fi
  say "git hook $h after session-start" "$r"
done
say "session-start says" "$(printf '%s' "$out" | grep -o '"systemMessage":"[^"]*"' | cut -c1-200)"
"${G[@]}" -C "$wired" switch -q -c feature/x
printf 'k = "%s"\n' "$key" >"$wired/leak.txt" && "${G[@]}" -C "$wired" add leak.txt
"${G[@]}" -C "$wired" commit -q -m leak >"$tmp/out" 2>&1
rc=$?
if [ "$rc" = 1 ]; then r=ok; else r=DIFFERS; fi
say "commit of a staged key" "exit $rc (designed 1) $r | $(head -n 1 "$tmp/out" | cut -c1-100)"

# 7. A plugin install: CLAUDE_PLUGIN_ROOT and the data directory arrive as C:/Users/... (forward slashes).
plug="$tmp/plugin"
mkdir -p "$plug/data" "$tmp/plugin-project" && "${G[@]}" -C "$tmp/plugin-project" init -q && "${G[@]}" -C "$tmp/plugin-project" commit -q --allow-empty -m init
proot="$ROOT/.claude" pdata="$plug/data"
[ -z "$cygw" ] || { proot="$(cygpath -m "$proot")"; pdata="$(cygpath -m "$pdata")"; }
out="$(printf '{"session_id":"probe"}' | CLAUDE_PROJECT_DIR="$tmp/plugin-project" CLAUDE_PLUGIN_ROOT="$proot" \
  bash "$ROOT/.claude/hooks/session-start.sh" "$pdata" 2>&1 | tr -d '\n')"
say "plugin session-start (root $proot)" "$(printf '%s' "$out" | grep -o '"systemMessage":"[^"]*"' | cut -c1-260)"
say "plugin git hooks" "$(for h in pre-push pre-commit; do [ -e "$tmp/plugin-project/.git/hooks/$h" ] && printf '%s ' "$h"; done)"

# 8. What one gate costs here: a hook started by Bash on every tool call.
t="$( { TIMEFORMAT=%R; time hook guard-branch.sh "$(bash_cmd Bash 'git status')" >/dev/null; } 2>&1 )"
say "time of one guard-branch run" "${t}s"
exit 0
