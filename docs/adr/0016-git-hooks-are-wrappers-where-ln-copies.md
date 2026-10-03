# ADR 0016 — Where `ln -s` copies, her git hooks are wrappers

- **Status:** Accepted
- **Date:** 2026-10-02
- **Deciders:** Shashank Kapadia

## Context

Her git hooks (`pre-commit`, `pre-push`) are links into her scripts, which find their `lib/` beside
themselves. A copy-in install links `.git/hooks/<name>` to `../../.claude/hooks/<script>`, relative so it
survives a repository move; a plugin install links it to `${CLAUDE_PLUGIN_DATA}/current/hooks/<script>`,
and `current` to the running plugin version, refreshed every session, so a hook follows her across an
update ([ADR-0011](0011-lite-mode-and-plugin-defaults.md)).

Git Bash's `ln -s` makes a copy, not a link, unless native symlinks are on (Developer Mode and
`MSYS=winsymlinks:nativestrict`), and that is not the default. A copy of her script in `.git/hooks` finds
no `lib/` beside it: git runs it and it lets everything through. Session start refused to leave one and
said so, so where Git for Windows has its defaults no git hook was installed at all, and a staged key
committed (CI's Windows probe, run 36771120623). `ln -sfn` copied too: a plugin's `current` became a
copy of the whole plugin, stale after the first update. And a plugin root that arrives as a drive's path
(`D:/…`) read as relative, so a plugin install wired nothing even with native symlinks.

## Options considered

1. **Require native symlinks.** What the docs said. Most Git for Windows installs have no gate, and a
   gate that is off without anyone choosing it is what [ADR-0004](0004-gates-as-code.md) exists to prevent.
2. **Copy her `lib/` beside each hook.** It works until the first update, then runs the old rules, and
   it leaves her files in `.git/hooks`.
3. **`core.hooksPath` at her hooks.** It takes every hook from the user, not two, and her scripts are not
   named as git's hooks are.
4. **A wrapper: a short script in place of the link, which runs her script** (chosen).

## Decision

1. **A link where `ln -s` makes one; her wrapper where it copies.** Nothing changes on Linux, macOS, or
   Windows with native symlinks. `nonna_hook_link` (`lib/core.sh`) tries the link, made from the hook's
   own directory, and writes the wrapper when the result is not a link. Never in place of a hook that is
   there, nor one written while she wires (a hook manager, a second session): the wrapper is written to a
   temp file `mktemp` makes and goes in by a hard link, which fails where a file is (`mv -n` where a file
   system has none). Session start, `install.sh` and `/nonna setup` wire through it.
2. **The wrapper's text follows from its target alone** (`nonna_hook_wrapper`): `#!/bin/sh`, a line
   `# Nonna: <target>`, the target (absolute, or from the hook's own directory, as a link's), and
   `exec bash "$t" "$@"`. Her script, run by its own path, finds its `lib/`.
3. **A hook is her wrapper only byte for byte.** `nonna_hook_target` reads the target from the second
   line and writes the wrapper again; anything that differs, even by a byte, is the user's, never
   rewired, repaired or removed. Her wrapper is then judged as her link is (`nonna_hook_is_hers`).
4. **A wrapper whose script is gone runs nothing and says so** on stderr, and exits 0: git skips a link
   that points at nothing, and a removed install must not block every commit. Session start repairs a
   wrapper of hers whose script is gone, as it repairs a dangling link of hers, and `/nonna status` shows
   it as pointing at nothing. Both follow a chain of links and wrappers to its end (a plugin's is two
   deep), with the wrapper's own test, `[ -f ]`.
5. **A plugin's `current` is a directory of wrappers where `ln -s` copies**, one per script a git hook
   runs, each to the running version's script, written again every session (`nonna_hook_wrappers`). A git
   hook leads to `current/hooks/<script>` in either form. Where links work, `current` stays a link; a
   directory left from a session where they did not is kept and rewritten, never deleted. A link at
   `current` or `current/hooks` is removed, never written through: through it she would overwrite her own
   scripts with wrappers of themselves.
6. **A drive's path is absolute** (`nonna_abs`): `C:/…` and `C:\…` as well as `/…`.

## Consequences

- Under Git Bash's defaults her git hooks are installed and enforce: a staged key is refused through a
  wrapper, in a copy-in and in a plugin install (the Windows legs of CI, which now block).
- A wrapper whose script is gone prints one line on every commit or push until a session rewires it or
  the user deletes it, where a dangling link was silent.
- The suite makes real symlinks where its tests are about links: on Windows that needs native symlinks
  (Developer Mode, or the right to make them, as GitHub's runners have).
- Still open, in [#45](https://github.com/kapadias/nonna/issues/45): the PowerShell tool, `git.exe`, and
  file paths with backslashes in the guards.
