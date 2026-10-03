# ADR 0017 — A command is read as the bash that runs it reads a CR

- **Status:** Accepted
- **Date:** 2026-10-03
- **Deciders:** Shashank Kapadia

## Context

The branch guard reads a command the way the shell will run it ([ADR-0004](0004-gates-as-code.md)), and
shells do not agree on a CR. Bash on Linux and macOS keeps a CR as part of a word: `: <CR>#; git push
--force` runs the push, since `<CR>#` starts no comment. Git Bash's bash drops every CR from a command
before reading it (MSYS2 patches its input reader): there `gi<CR>t push --force` is a force push,
`\<CR><LF>` continues a line, and `echo A <CR>#; echo RAN` prints only `A`.

Claude Code hands its Bash tool's command to bash as `… && eval <the command, quoted> && pwd -P >| …`,
with `-c -l`, and its quoting keeps each CR, inside quotes. Through exactly that, from Node, Git Bash
dropped every CR, quoted or not, in a heredoc body too, and bash on Linux kept every one (CI's Windows
probe, run 37090986099). Git Bash's dropping cannot be switched: it has an `igncr` option, off as it
starts, and `set`, `shopt`, `SHELLOPTS`, a script file and `source` change nothing (run 37090477431).
Cygwin's bash, by contrast, drops CRs only while `igncr` is on, which a command can switch partway
through.

The guard read every CR as Linux's bash does, so under Git Bash those three commands got through. The
first fix dropped every CR everywhere, which let `: <CR>#; git push --force` through on Linux; the
reviews caught it before it shipped.

## Options considered

1. **Drop every CR everywhere.** Lets through on Linux what it stops under Git Bash.
2. **Decide from `OSTYPE`.** The environment can set it, and bash keeps an inherited one.
3. **Decide from `BASH_VERSINFO`.** Read-only, but Git Bash's says `x86_64-pc-cygwin`, as Cygwin's
   does, though the two differ on exactly this.
4. **Read every command each way, and refuse if either reading is refused.** No platform to know, but
   it refuses on Linux what only Git Bash would run (`gi<CR>t`), and on Git Bash the reverse.
5. **Ask the bash that runs the hooks how it reads a CR, when a command holds one** (chosen).

## Decision

1. **A command is read by `nonna_json_command`** (`lib/json.sh`), as this platform's bash reads a CR in
   it; every other field (a path, a tool's name, a Codex patch) by `nonna_json_field`, exactly as the
   JSON holds it, since a path is opened and a patch parsed, never run by bash.
2. **The answer comes from bash itself** (`_nonna_cr_mode`), the bash that runs the hooks (`$BASH`): the
   lengths of `a<CR>b` and of an `a<CR>` that ends a line, as it starts, then with `igncr` off, then
   on (`shopt -o`, which never ends a POSIX-mode shell over an option it lacks). Lengths come back,
   never a CR, so nothing that reads the answer can change it.
   - **keep**: 3 and 2 each time. Every CR stays.
   - **drop**: 2 and 1 each time. The command is read without its CRs.
   - **unknown**: anything else: an `igncr` a command can switch, a bash that drops only a CR before a
     newline, no answer. A command that holds a CR reads as nothing, and the guard refuses a command
     it could not read.
3. **Bash is asked only about a command that holds a CR**, since one without reads alike everywhere: a
   fork on the rare command, never on every call. Nothing the environment sets decides it: not
   `OSTYPE`, and not an exported `_nonna_cr`, which `json.sh` clears when it loads.
4. **Only the CRLF a native `jq.exe` adds is undone** in any field: `-b` where jq takes it, else one CR
   off each line's end, which is all it added.

## Consequences

- Under Git Bash the guard refuses `gi<CR>t push --force`, `git pu<CR>sh --force` and a push to
  `ma<CR>in`; on Linux and macOS it refuses `: <CR>#; git push --force` and a command after
  `\<CR><LF>`. CI checks each where it runs, drop on its Windows legs and keep on Linux and macOS, as
  each platform's bash measures itself (`CR_MODE` in `tests/run.sh`, asked with `set` where `json.sh`
  asks with `shopt`).
- Where a command can switch how its bash reads a CR (Cygwin), any command that holds a CR is refused.
- The hooks' bash stands for the bash that runs the command: on Windows Claude Code requires Git Bash
  for both. A hook run by one bash for commands another runs could misread a CR.
- Not decided here: Claude Code rewrites a command that holds a `|`, splitting its words on whitespace
  bash keeps in a word, a no-break space among them, on every platform. That is a gap of its own,
  [#54](https://github.com/kapadias/nonna/issues/54).
