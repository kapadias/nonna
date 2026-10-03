#!/usr/bin/env bash
# Scratch (#45, never merged): what Git Bash does with a CR in a field the guard reads, and in a command
# as Claude Code hands it to bash (eval of it quoted, through Node's spawn). Facts only.
set -u
exec </dev/null
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; HOOKS="$ROOT/.claude/hooks"
say() { printf 'probe %s: %s\n' "$1" "$2"; }
show() { od -An -c | tr -s ' ' | tr '\n' ' '; }
CR="$(printf '\r')"
say E17 "\$(...) of a<CR><LF>b: $(v="$(printf 'a\r\nb')"; printf '%s' "$v" | show)"
say E17 "\$(...) of a<CR>b: $(v="$(printf 'a\rb')"; printf '%s' "$v" | show)"
say E17 "\$(...) of a<CR> at the end: $(v="$(printf 'a\r')"; printf '%s' "$v" | show)"
say E17 "\$(...) of a<CR><LF> at the end: $(v="$(printf 'a\r\n')"; printf '%s' "$v" | show)"
say E17 "\$(...; printf x) of a<CR><LF>: $(v="$(printf 'a\r\n'; printf x)"; printf '%s' "$v" | show)"
say E17 "read -d '' of a<CR><LF>b: $(IFS= read -r -d '' v < <(printf 'a\r\nb'); printf '%s' "$v" | show)"
say E17 "a variable through a pipe to od, set by printf -v: $(printf -v v 'a\r\nb'; printf '%s' "$v" | show)"
say E17 "a CR inside single quotes, bash -c: $(bash -c "printf '<%s>' 'a${CR}b'" | show)"
say E17 "a CR inside double quotes, bash -c: $(bash -c "printf '<%s>' \"a${CR}b\"" | show)"
say E17 "eval of a single-quoted string holding a CR, bash -c: $(bash -c "eval 'printf \"<%s>\" a${CR}b'" | show)"
say E17 "jq -b of x<CR>, then \$(...): $(v="$(printf '%s' '{"f":"x\r"}' | jq -b -r .f)"; printf '%s' "$v" | show)"
say E17 "jq -b of a<CR><LF>b, then \$(...): $(v="$(printf '%s' '{"f":"a\r\nb"}' | jq -b -r .f)"; printf '%s' "$v" | show)"
say E17 "nonna_json_field of a<CR><LF>b, then \$(...): $(printf '%s' '{"f":"a\r\nb"}' | bash -c '. "$1/lib/json.sh"; v="$(nonna_json_field .f)"; printf "%s" "$v"' _ "$HOOKS" | show)"
# secret-scan's view of a name that ends in a CR
LNK="$(mktemp -d)"; printf 'K=1\n' > "$LNK/.env"
(cd "$LNK" && MSYS=winsymlinks:nativestrict ln -s .env "x$CR")
say E17 "[ -L x<CR> ]: $([ -L "$LNK/x$CR" ] && echo yes || echo no); [ -e x ]: $([ -e "$LNK/x" ] && echo yes || echo no); readlink x<CR>: $(readlink "$LNK/x$CR" | show)"
say E17 "secret-scan's f for x<CR>: $(printf '%s' '{"tool_input":{"file_path":"x\r"}}' | bash -c '. "$1/lib/json.sh"; f="$(nonna_json_field .tool_input.file_path)"; printf "%s" "$f"' _ "$HOOKS" | show)"
rm -rf "$LNK"
say E17 "node: $(command -v node) $(node --version 2>&1)"
node "$ROOT/tests/win-cc.js" "$(cygpath -w /)bin\\bash.exe" "$(cygpath -w "$(command -v bash)")"
