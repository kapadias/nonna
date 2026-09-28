#!/usr/bin/env bash
# PreToolUse gate — protect main/master/develop, and the gates themselves. Dual-mode by tool:
#   • Edit|Write|MultiEdit on a protected branch  -> WARN once (exit 0).
#       Editing is fine; committing is what's forbidden. Editing .git/config or .git/hooks -> BLOCK.
#   • Bash `git commit`/`git merge` on a protected branch, or any `git push`
#     that is on/targets a protected branch (or pushes --all/--mirror) -> BLOCK. So is a force
#     push, skipping the git hooks, changing what Nonna's gates read, and running her /nonna
#     scripts. While she is off, only her settings (the last two, and her git hooks) are kept.
# The command is read the way the shell will run it: continued lines joined, a quoted commit message
# masked, quotes and backslashes removed, and ( ), $( ) and backticks opened into commands of their
# own. The git matcher tolerates a path prefix (/usr/bin/git) and global options (`-C <dir>`,
# `--git-dir`, `-c k=v`, …) between `git` and the subcommand, and git's abbreviated long options.
# A speed bump, not a sandbox: a script file, a shell variable or an alias the user already has
# still gets past it. Branch protection on the server is the wall (ADR-0011). Fails SAFE: if the
# branch can't be determined, it never blocks on it.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$here/lib/json.sh"

root="${CLAUDE_PROJECT_DIR:-$(pwd)}"
cd "$root" 2>/dev/null || exit 0
# shellcheck source=/dev/null
. "$here/lib/core.sh"
# Off means off, but for her settings: the user switched her off, so the agent may still not change
# what she reads, run her /nonna scripts or touch her git hooks. The user switches her on again, and
# decides what she runs then (ADR-0011). Nothing else is checked while she is off, and nothing said.
off=0
[ "$(nonna_mode)" = off ] && off=1
# The full ref, prefix stripped: --short gives heads/main once a tag named main exists, and the
# branch is named before its first commit too.
ref="$(git symbolic-ref --quiet HEAD 2>/dev/null || true)"
branch="${ref#refs/heads/}"

is_protected() { case "$1" in main | master | develop) return 0 ;; *) return 1 ;; esac; }

# `git` (optionally path-prefixed) + any run of global options, up to a subcommand, or git's own
# binary for one (git-push, in git --exec-path). A command starts a line, or follows a space, `{`,
# `!` or `=` (a command in a value: GIT_EDITOR=…, --exec=…). Matched without case, as macOS's disk
# finds /usr/bin/GIT, git-PUSH and RM.
GIT='(^|[[:space:]{!=])([^[:space:]]*/)?git(-|([[:space:]]+(-C[[:space:]]+[^[:space:]]+|-c[[:space:]]+[^[:space:]]+|--(git-dir|work-tree|namespace|exec-path|super-prefix|config-env|attr-source|shallow-file)(=[^[:space:]]*|[[:space:]]+[^[:space:]]+)|--[A-Za-z][A-Za-z-]*(=[^[:space:]]*)?|-[A-Za-z]))*[[:space:]]+)'
# Config keys that are Nonna's own switches, and keys that can route git around her hooks: an
# include, an alias, a hooks path, a mirror, a push refspec or push.default (either can make a plain
# git push push a protected branch, or every branch). Matched without case.
NKEY='nonna([.[:space:]=]|$)'
RKEY='(include(if)?\.|alias\.|core\.hookspath|remote\.[^[:space:]]*\.(mirror|push)|push\.default)'

recipe() { # <technical reason>: her settings are the user's
  echo "✗ Nonna: only the cook changes the recipe. (branch guard: $1)" >&2
  echo "  Her settings are the user's: they change them with /nonna." >&2
  exit 2
}
kitchen_door() { # <technical reason>: the git hooks are the gate
  echo "✗ Nonna: no sneaking past the kitchen door. (branch guard: $1)" >&2
  echo "  Fix what the hook refuses, or tell the user plainly why you cannot." >&2
  exit 2
}

# Could what the guard cannot read touch her settings? Git or nonna in it however quoted, a $'…'
# escape, or a run inside her /nonna directory. While she is off, only such a command is refused
# for being unreadable; she keeps her settings then, and nothing else.
could_be_hers() { # <raw text>
  local bsnl=$'\\\n' # a continued line: the shell joins g\<newline>it into git
  [ "${in_hers:-0}" = 1 ] || printf '%s' "${1//"$bsnl"/}" | grep -qiE "g[\\'\"]*i[\\'\"]*t|n[\\'\"]*o[\\'\"]*n[\\'\"]*n[\\'\"]*a|\\$'"
}
unread() { # <what could not be read>: fail closed, never guess
  [ "$off" = 0 ] || could_be_hers "${cmd:-$payload}" || exit 0
  echo "✗ Nonna: I can't taste what I can't read. (branch guard: $1, so it is refused, not guessed at.)" >&2
  echo "  Run it again; if this repeats, check that awk and jq work in this shell." >&2
  exit 2
}
too_long() { # <reason>: a hook that outruns its timeout does not block, so what it cannot read in time is refused
  [ "$off" = 0 ] || could_be_hers "${cmd:-$payload}" || exit 0
  echo "✗ Nonna: that's too much to taste in one bite. (branch guard: $1)" >&2
  echo "  Write the content with the Write tool, or split the command." >&2
  exit 2
}
# Raw text the parsers could not read: a tool name, or a field that is there with a value.
raw_tool() { printf '%s' "$payload" | grep -oE '"tool_name"[[:space:]]*:[[:space:]]*"[A-Za-z]+"' | head -n 1 | sed -E 's/.*"([A-Za-z]+)"$/\1/'; }
has_field() { printf '%s' "$payload" | grep -qE "\"$1\"[[:space:]]*:[[:space:]]*\"[^\"]"; }

payload="$(cat 2>/dev/null || true)"
tool="$(printf '%s' "$payload" | nonna_json_field '.tool_name')"
[ -n "$tool" ] || tool="$(raw_tool)" # a parser that failed (jq, awk) leaves the name empty

case "$tool" in
  Edit | Write | MultiEdit)
    # Her settings and her git hooks are the user's: the file tools may not rewrite them either.
    file="$(printf '%s' "$payload" | nonna_json_field '.tool_input.file_path')"
    [ -n "$file" ] || ! has_field file_path || unread "the file path could not be read"
    case "/${file#./}" in
      */.git/config | */.git/hooks/* | */.git/nonna/* | */.git/nonna-green)
        recipe "refusing to edit ${file}: her settings and git hooks live there." ;;
    esac
    [ "$off" = 0 ] || exit 0
    if is_protected "$branch"; then
      marker="$root/.git/.nonna-branch-warned-$branch"
      if [ ! -f "$marker" ]; then
        touch "$marker" 2>/dev/null || true
        echo "⚠️  On protected branch '$branch'. Editing is fine, but do NOT commit here — branch first: git checkout -b feature/<id>-<slug>" >&2
      fi
    fi
    exit 0
    ;;
  Bash)
    cmd="$(printf '%s' "$payload" | nonna_json_field '.tool_input.command')"
    [ -n "$cmd" ] || ! has_field command || unread "the command could not be read"
    [ -n "$cmd" ] || exit 0
    cwd="$(printf '%s' "$payload" | nonna_json_field '.cwd')" # where the Bash tool will run it
    case "/$cwd/" in */skills/nonna/*) in_hers=1 ;; *) in_hers=0 ;; esac
    [ "${#cmd}" -le 262144 ] || too_long "the command is over 256 KB, too long to read before the hook times out."
    # How the shell will see it (lib/shell-words.awk). Readings, checked together: A keeps each word
    # whole, so a quoted value with a space cannot shift the words after it; B exposes what a quoted
    # string holds, so code in sh -c "…" or "$(…)" is seen; and B read again, masking nothing, while a
    # quote or an escape is left in it (up to six times), so a quote nested inside one (sh -c '…
    # "--force"') is removed as the inner shell removes it. Nesting deeper than that is refused. A
    # message is masked only where the reading is sure to be the shell's. A match in any refuses.
    # When the reader fails (awk missing or failing), a command that could touch git or her settings
    # (git or nonna in it, however quoted, or a $'…' escape) is refused; nothing else here reads one.
    words() { printf '%s\n' "$cmd" | LC_ALL=C awk -v out="$1" -f "$here/lib/shell-words.awk" 2>/dev/null; }
    quoted() { case "$1" in *[\'\"\\]*) return 0 ;; esac; return 1; }
    cant_read() {
      could_be_hers "$cmd" && unread "the command reader (awk) failed"
      exit 0
    }
    lvl="$(words B)" || cant_read
    segs="$(words A)" || cant_read
    segs="$segs"$'\n'"$lvl"
    code="$lvl" # every opened level, read as the code a nested shell would run
    n=0
    while [ "$n" -lt 6 ] && quoted "$lvl"; do
      next="$(printf '%s\n' "$lvl" | LC_ALL=C awk -v out=B -v nomask=1 -v relevel=1 -f "$here/lib/shell-words.awk" 2>/dev/null)" || cant_read
      [ "$next" = "$lvl" ] && break
      segs="$segs"$'\n'"$next"
      code="$code"$'\n'"$next"
      lvl="$next"
      n=$((n + 1))
    done
    if [ "$n" -ge 6 ] && quoted "$lvl"; then
      [ "$off" = 0 ] || could_be_hers "$cmd" || exit 0
      kitchen_door "refusing quotes nested deeper than the guard reads; run the inner command itself."
    fi

    # Brace lists and globs, as the shell expands them before it runs a word (lib/expand.awk): a line
    # it would expand is read again, expanded, with a glob read as the name of hers it could match
    # (git, git-push, a protected branch, .git/hooks). The command itself is read quote-exact (a
    # quoted brace is text); every opened level as code. A glob group (bash's @(…) under extglob,
    # zsh's (a|b)) is read in readings of its own, when a ( follows a word's character or $'…' could
    # hide one. An expansion too large to read in time is refused.
    top="$(printf '%s\n' "$cmd" | LC_ALL=C awk -v out=A -v qmark=1 -f "$here/lib/shell-words.awk" 2>/dev/null)" || cant_read
    if printf '%s' "$cmd" | grep -qE "[^[:space:]\$();&|<>\`]\(|\\$'"; then
      xw="$(printf '%s\n' "$cmd" | LC_ALL=C awk -v out=A -v qmark=1 -v xglob=1 -f "$here/lib/shell-words.awk" 2>/dev/null)" || cant_read
      top="$top"$'\n'"$xw"
      xl="$(printf '%s\n' "$cmd" | LC_ALL=C awk -v out=B -v xglob=1 -f "$here/lib/shell-words.awk" 2>/dev/null)" || cant_read
      code="$code"$'\n'"$xl"
      n=0
      while [ "$n" -lt 6 ] && quoted "$xl"; do
        xw="$(printf '%s\n' "$xl" | LC_ALL=C awk -v out=B -v nomask=1 -v relevel=1 -v xglob=1 -f "$here/lib/shell-words.awk" 2>/dev/null)" || cant_read
        [ "$xw" = "$xl" ] && break
        code="$code"$'\n'"$xw"
        xl="$xw"
        n=$((n + 1))
      done
    fi
    grown="$(printf '%s\n%s\n' "$top" "${code//$'\016'/?}" | LC_ALL=C awk -f "$here/lib/expand.awk" 2>/dev/null)"
    case $? in
      0) segs="$segs"$'\n'"$grown" ;;
      3) too_long "a brace list or a glob expands to more than it can read before the hook times out." ;;
      *) unread "the brace and glob reader (awk) failed" ;;
    esac
    runs_git() { printf '%s\n' "$segs" | grep -qiE "${GIT}[a-z]"; }
    RD=$'\002' # the mark shell-words.awk puts before a redirection the shell performs

    # What her gates read is the user's to set: an environment variable can switch a git hook off
    # or swap its test command, GIT_CONFIG_* and a borrowed HOME can hand git a config of their own.
    # Only a way of setting one counts. One that carries a value counts wherever it stands: a name=
    # given to export, declare and the like, or to env or sudo (behind builtin, command, nice,
    # timeout, a redirection or a trap string alike), and an assignment right before git. A bare
    # assignment, and a name given without a value (export NAME, read NAME, printf -v NAME), count at
    # the start of a command: after { ! if then do else elif while until time eval coproc, builtin,
    # command, other assignments, redirections, or sh -c and its kind (whose text B puts on the same
    # line). A grep for the name, or an echo of it, sets nothing.
    ASSIGN='[A-Za-z_][A-Za-z0-9_]*\+?=[^[:space:]]*'
    KW='(\{|!|if|then|do|else|elif|while|until|time([[:space:]]+-p)?|eval|coproc|builtin|command([[:space:]]+-[A-Za-z]+)*|[^[:space:]]*(sh|bash|zsh|dash|ksh)([[:space:]]+-[A-Za-z]+)*[[:space:]]+-[A-Za-z]*c)'
    # A redirection (marked by shell-words.awk, or bare without awk) may come first; taking more
    # for a command's start only ever refuses more.
    AT="^[[:space:]]*((${KW}|${ASSIGN}|${RD}?[0-9]*[<>]+([[:space:]]+${RD}?[<>]+)*[[:space:]]*[^[:space:]]+)[[:space:]]+)*"
    DECL='(export|declare|typeset|readonly|local)([[:space:]]+-[A-Za-z]+)*'
    assigns() { # <name regex>
      printf '%s\n' "$segs" | grep -qiE \
        -e "${AT}$1\+?=" \
        -e "(^|[[:space:]])${DECL}([[:space:]]+${ASSIGN})*[[:space:]]+$1\+?=" \
        -e "(^|[[:space:]])([^[:space:]]*/)?(env|sudo)[[:space:]](.*[[:space:]])?$1\+?=" \
        -e "${AT}${DECL}([[:space:]]+[A-Za-z_][A-Za-z0-9_]*(\+?=[^[:space:]]*)?)*[[:space:]]+$1([[:space:]]|$)" \
        -e "${AT}printf[[:space:]]+(-[^[:space:]]+[[:space:]]+)*-v[[:space:]]*$1([[:space:]]|$)" \
        -e "${AT}(read|readarray|mapfile)[[:space:]](.*[[:space:]])?$1([[:space:]]|$)" \
        -e "(^|[^A-Za-z0-9_])$1\+?=[^[:space:]]*[[:space:]]+(${ASSIGN}[[:space:]]+)*([^[:space:]]*/)?git([[:space:]]|$)"
    }
    if assigns '(NONNA_MODE|NONNA_TEST_CMD|CLAUDE_PLUGIN_OPTION_[A-Za-z0-9_]+|GIT_CONFIG[A-Za-z0-9_]*)' \
      || { assigns '(HOME|XDG_CONFIG_HOME)' && runs_git; }; then
      recipe "refusing to set what her gates read: NONNA_MODE, NONNA_TEST_CMD, CLAUDE_PLUGIN_OPTION_*, GIT_CONFIG_*, or HOME for git."
    fi

    # Config on the command line (-c, --config-env) that switches her off or routes git around her.
    if printf '%s\n' "$segs" | grep -qiE "(^|[[:space:]{!=])([^[:space:]]*/)?git[[:space:]](.*[[:space:]])?(-c[[:space:]]+|--config-env[=[:space:]]+)${NKEY}"; then
      recipe "refusing to change Nonna's own git config."
    fi
    if printf '%s\n' "$segs" | grep -qiE "(^|[[:space:]{!=])([^[:space:]]*/)?git[[:space:]](.*[[:space:]])?(-c[[:space:]]+|--config-env[=[:space:]]+)${RKEY}"; then
      kitchen_door "refusing an include, alias, hooks path, push refspec or push.default on the command line; the git hooks are the gate."
    fi

    # git config: a read is fine: --get*, --list, -l, the get/list subcommand, or one key (it has a
    # dot) with nothing after it, each after read-safe options only (git 2.45's --comment takes the
    # next word as its value, so a read flag after it is a comment). Every word after the key is a
    # value to git, an empty one ('') or one that looks like an option included, and git takes an
    # abbreviated action (--rem). A write to her keys, or to one that reroutes git, is refused.
    ROPT='[[:space:]]+(--(local|global|system|worktree|show-origin|show-scope|includes|no-includes|null|name-only|bool|int|bool-or-int|path|expiry-date)|-z|--type=[a-z-]+|--(file|blob)=[^[:space:]]+|(-f|--file|--blob|--type)[[:space:]]+[^-[:space:]][^[:space:]]*)'
    # Only the lines that run git config: one grep for the whole command, not processes per line (a
    # long heredoc must not outrun the hook's timeout, which would let the command run unguarded).
    cfg="$(printf '%s\n' "$segs" | grep -iE "${GIT}config([[:space:]]|$)")"
    [ "$?" -le 1 ] || unread "a check could not run"
    while IFS= read -r seg; do
      [ -n "$seg" ] || continue
      printf '%s' "$seg" | grep -qiE "${GIT}config(${ROPT})*[[:space:]]+(--get[a-z-]*|--list|-l)([[:space:]=]|$)" && continue
      printf '%s' "$seg" | grep -qiE "${GIT}config(${ROPT})*[[:space:]]+(get|list)([[:space:]]|$)" && continue
      printf '%s' "$seg" | sed -E "s/[[:space:]]+${RD}[0-9]*[<>]+([[:space:]]+${RD}[<>]+)*[[:space:]]+[^[:space:]]+//g" \
        | grep -qiE "${GIT}config(${ROPT})*[[:space:]]+[^-[:space:]'][^[:space:]]*\.[^[:space:]]*[[:space:]]*$" && continue
      printf '%s' "$seg" | grep -qiE "(^|[[:space:]])${NKEY}" && recipe "refusing to change Nonna's own git config."
      if printf '%s' "$seg" | grep -qiE "(^|[[:space:]])(${RKEY}|(-e|--edit|edit)([[:space:]]|$))"; then
        kitchen_door "refusing a config change that can route git around her hooks (include, alias, core.hooksPath, a push refspec or push.default, --edit)."
      fi
    done <<<"$cfg"

    # The same files by hand: .git/config and the git hooks, as the target of a write. Reading them
    # (cat, grep, sed -n, awk, cp from) is fine. A copy's target is its last word once redirections
    # are set aside, or the directory given to -t / --target-directory.
    GITF='(^|[^A-Za-z0-9_.-])\.git/(hooks([/[:space:]]|$)|config([[:space:]]|$))'
    if printf '%s\n' "$segs" | grep -qiE '>[[:space:]]*[^[:space:]]*\.git/(hooks|config)' \
      || printf '%s\n' "$segs" | grep -iE "$GITF" \
      | grep -qiE '(^|[[:space:]])(rm|unlink|chmod|chown|truncate|touch|shred|patch|ed|ex|vi|vim|nano|emacs|python3?|ruby|node|perl|tee|dd)([[:space:]]|$)|(^|[[:space:]])(sed|awk|gawk)[[:space:]](.*[[:space:]])?(-[A-Za-z]*i|--in-place)' \
      || printf '%s\n' "$segs" | grep -iE '(^|[[:space:]])(cp|mv|ln|install|rsync)[[:space:]]' \
      | sed -E "s/[[:space:]]+${RD}[0-9]*[<>]+([[:space:]]+${RD}[<>]+)*[[:space:]]+[^[:space:]]+//g" \
      | grep -qiE '(^|[^A-Za-z0-9_.-])\.git/(hooks(/[^[:space:]]*)?|config)[[:space:]]*$|(^|[[:space:]])(-[A-Za-z]*t[[:space:]]*|--ta[a-z-]*[=[:space:]]+)[^[:space:]]*\.git/(hooks|config)'; then
      recipe "refusing to change .git/config or .git/hooks by hand."
    fi

    # Her /nonna scripts are the user's switch, run by the skill when a person types /nonna: they
    # change her settings, as git config nonna.* does. A command that names them (her skill's
    # directory, nonna.sh, or any script when it runs inside her directory) and runs a shell is
    # refused, however the two are joined. A shell runs as a command (sh, bash, source, ., exec,
    # eval, a *.sh, or any program given by its path, as a copy would be) or through one that runs
    # another (env, sudo, xargs, find -exec, …); a shell's name as a word to grep for runs nothing.
    # A part of the command that only reads her files (cat, grep, shellcheck, git add or diff, …,
    # redirecting nothing) does not name them, unless a pipe or a command or process substitution
    # could carry what it read into a shell: so reading or linting her scripts, then running the
    # suite, passes.
    HERS='(^|[^A-Za-z0-9_.-])(skills/nonna|nonna/scripts|nonna\.sh)([^A-Za-z0-9_-]|$)'
    SH='([^[:space:]]*/)?(sh|bash|zsh|dash|ksh|mksh|yash|fish|busybox)'
    WRAP='([^[:space:]]*/)?(env|sudo|doas|xargs|nohup|exec|command|builtin|nice|timeout|time|stdbuf|setsid|ionice|chrt|taskset|flock|unbuffer|parallel|watch)|-(exec|execdir|ok|okdir)'
    SHELLS="${AT}(${SH}|source|\\.|exec|eval|[^[:space:]]*\\.sh|\\.{0,2}/[^[:space:]]*|~/[^[:space:]]*)([[:space:]]|$)|(^|[[:space:]])(${WRAP})[[:space:]](.*[[:space:]])?${SH}([[:space:]]|$)"
    # debt: the reader list trusts each reader's own options to run nothing, revisit if the script-file limit (ADR-0011 §4) is ever closed, since this is no stronger than it
    READS='(cat|less|more|head|tail|grep|egrep|fgrep|rg|ag|ack|wc|ls|stat|file|shellcheck|diff|cmp|nl|bat|git[[:space:]]+(add|diff|log|show|status|blame|ls-files|grep))'
    named="$segs"
    if ! printf '%s' "$cmd" | grep -qE '\||<\(|>\(|\$\(|`'; then
      named="$(printf '%s\n' "$segs" | grep -vE "^[[:space:]]*([^[:space:]]*/)?${READS}([[:space:]][^>${RD}]*)?$")"
    fi
    if { [ "$in_hers" = 1 ] || printf '%s\n' "$named" | grep -qiE "$HERS"; } \
      && printf '%s\n' "$segs" | grep -qiE "$SHELLS"; then
      recipe "refusing to run her /nonna scripts: they change her settings."
    fi
    [ "$off" = 0 ] || exit 0 # while she is off, her settings are all the guard keeps

    # The git hooks are the gate for a commit and a push, so skipping them is refused: --no-verify
    # (and its abbreviations), commit's -n, alone or in a cluster of flags that take no value, and
    # git's plumbing pushes, send-pack and http-push, which run no hook at all.
    if printf '%s\n' "$segs" | grep -qiE "${GIT}(commit|push|merge|am|rebase|cherry-pick|revert|pull)([[:space:]].*)?[[:space:]]--no-veri[a-z]*([=[:space:]]|$)" \
      || printf '%s\n' "$segs" | grep -qiE "${GIT}commit([[:space:]].*)?[[:space:]]-[aeiopqsvz]*n" \
      || printf '%s\n' "$segs" | grep -qiE "${GIT}(send-pack|http-push)([[:space:]]|$)"; then
      kitchen_door "refusing --no-verify and hook overrides; the git hooks are the gate."
    fi

    # Commit/merge while sitting on a protected branch.
    if is_protected "$branch" && printf '%s\n' "$segs" | grep -qiE "${GIT}(commit|merge)([[:space:]]|$)"; then
      echo "✗ Nonna: not in my kitchen, tesoro. Make a branch. (branch guard: refusing to commit on protected branch '$branch'.)" >&2
      echo "  Never commit to main/master/develop (rules/git-workflow.md). Branch first:" >&2
      echo "    git checkout -b feature/<id>-<slug>" >&2
      exit 2
    fi

    # Push handling, on the push commands alone: git push, and git subtree push.
    push="$(printf '%s\n' "$segs" | grep -iE "${GIT}(push|subtree([[:space:]].*)?[[:space:]]push)([[:space:]]|$)" || true)"
    if [ -n "$push" ]; then
      # --all / --mirror push (or delete) every local ref, incl. protected ones; so does a : refspec
      # (every branch the remote shares) and a wildcard (refs/heads/*).
      if printf '%s\n' "$push" | grep -qiE '[[:space:]]--(al|all|mi|mir|mirr|mirro|mirror)([=[:space:]]|$)|[[:space:]]\+?:([[:space:]]|$)|\*'; then
        echo "✗ Nonna: one pot at a time. (branch guard: refusing a push of every branch: --all, --mirror, a : refspec or a wildcard — it pushes (or deletes) protected refs.)" >&2
        echo "  Push one branch explicitly: git push origin <feature-branch> (rules/git-workflow.md)." >&2
        exit 2
      fi
      # Force pushes: --force and --force-with-lease (git takes any unique abbreviation, from --for),
      # and -f alone or in a cluster of flags that take no value (-uf). --follow-tags is not one.
      if printf '%s\n' "$push" | grep -qiE '(^|[[:space:]{,])(--for[a-z-]*(=[^[:space:]]*)?|-[unvqd46]*f)'; then
        echo "✗ Nonna: we don't force things in this house. (branch guard: refusing a force push.)" >&2
        echo "  Push a new commit instead (rules/git-workflow.md)." >&2
        exit 2
      fi
      # A refspec with a leading '+' is a force push in refspec syntax.
      if printf '%s\n' "$push" | grep -qE '(^|[[:space:]{,])\+[^[:space:]]'; then
        echo "✗ Nonna: we don't force things in this house. (branch guard: refusing 'git push' with a +refspec — that is a force push.)" >&2
        echo "  Force-pushing is denied (settings.json, rules/git-workflow.md); push a new commit instead." >&2
        exit 2
      fi
      # On a protected branch, or naming a protected ref as the target (main:feature only reads main).
      if is_protected "$branch" || printf '%s\n' "$push" | grep -qiE '(^|[[:space:]:/{,])(main|master|develop)([[:space:]},]|$)'; then
        echo "✗ Nonna: nobody pushes to main in my house. Open a PR. (branch guard: refusing to push to a protected branch.)" >&2
        echo "  Promote via PR (feature -> develop -> main), not a direct push (rules/git-workflow.md)." >&2
        exit 2
      fi
    fi
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
