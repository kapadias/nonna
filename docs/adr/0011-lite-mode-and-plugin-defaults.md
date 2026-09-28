# ADR 0011 — Lite mode and plugin defaults

- **Status:** Accepted; amends [0007](0007-plugin-install-is-not-equivalent.md) and
  [0008](0008-decision-ladder-for-solution-size.md)
- **Date:** 2026-09-25
- **Deciders:** Shashank Kapadia

## Context

The README told people to install a plugin that did not deliver the product:

- **No test gate.** A plugin install ran the tests only once the user set `NONNA_TEST_CMD`, because
  nobody had agreed to have each repository's code run at every turn end. [ADR 0004](0004-gates-as-code.md)
  already names the cost: a gate that must be opt-in is missing on day one for everyone.
- **A gate for a file nobody had.** The `docs/STATUS.md` gate blocked turns, and the user's own
  pushes, in repositories that never kept the file.
- **Guards that did not travel.** Force pushes and reads of `.env` were refused by `settings.json`
  permissions, which a plugin cannot carry.
- **A hook that went quiet.** The pre-push link pointed into the versioned plugin cache, which an
  update deletes, and git skips a hook it cannot find without a word.

Cost pointed the same way. Benchmark rounds 1 and 2 priced a copy-in install well above a bare agent
per change, and most of the spend was review, not the gates ([ADR 0009](0009-proportional-review.md)).
The safety result looked like it came from the gates and the never-list: the test gate caught
claims of done, and the rules kept agents off `main` and away from secrets. A mode with only those
might keep most of the result at close to bare cost. Round 3 of the benchmark tests that under a
table written before the paid runs.

[ADR 0008](0008-decision-ladder-for-solution-size.md) rejected intensity modes as YAGNI: "there is no
lighter mode to select". A plugin user's first day is that use.

## Options considered

1. **One mode, fix only the defects.** Least code. But the first day still carries the most
   opinionated parts (the STATUS gate, about 2k tokens of constitution every turn, the
   develop-to-main flow), and those are not what moved the safety numbers.
2. **A second, lite plugin.** A clean split, but two roots to version, validate and document, and a
   reinstall to change your mind.
3. **Intensity levels the model sets**, the shape ADR 0008 already turned down. Still rejected: a
   mode the model can change has no gate in front of it.
4. **One plugin, three modes (`off | lite | full`), set by the user in git config** (chosen).

## Decision

1. **Modes.** `nonna_mode` (`.claude/hooks/lib/core.sh`) resolves, in order: `NONNA_MODE`, the
   user's `nonna.mode` (repo, then global), the plugin's `mode` option, `nonna.defaultMode`, and
   last what the repo carries (its hooks and its rules: full; otherwise lite). The settings live in
   git config because Claude Code hooks and git hooks can both read it, it is never committed, and a
   clone cannot carry it. A value nobody meant fails closed to full; it never weakens the gates. In
   `off` every hook exits 0 and prints nothing, with one exception: the branch guard still keeps her
   settings (12).
2. **The git hooks read git config alone.** A git hook runs in the environment of whoever ran git,
   and that can be the agent's own command. So pre-commit and pre-push take their mode and test
   command from the repo's own config, then the user's global config. They ignore a `git -c` flag,
   `GIT_CONFIG_*`, a file the config merely includes, `NONNA_MODE`, `NONNA_TEST_CMD` and the plugin
   options. Claude Code's hooks still take the environment, which is Claude Code's, set by the user.
3. **`nonna.mode` is the user's alone.** What Nonna records goes in `nonna.defaultMode`, below it:
   the `mode` option, mirrored each session for the git hooks, or `install.sh --mode`. So
   `git config --global nonna.mode off` reaches every repository the user has not set. (The draft
   recorded `nonna.mode` on first sight, which would have outranked the global switch everywhere
   Nonna had been.)
4. **A model does not switch off its own gates.** The branch guard reads each command the way the
   shell will run it (`.claude/hooks/lib/shell-words.awk`: quotes, escapes including `$'…'`,
   comments, continued lines, subshells, redirections): each word kept whole, every quoted string
   opened, and that opened text read again until no quote is left in it, as a nested `sh -c` or
   `eval` would read it; nesting deeper than six reads is refused. A match in any reading refuses. Abbreviated options count. A message is set aside only where the
   reading is sure to be the shell's: the value of `-m`, `--message`, `-F` or `--file` in
   `git commit`, `merge`, `tag`, `stash` and `notes`, and a `gh pr|issue|release` title or body,
   before any `$(`, backtick or heredoc whose nested quoting the reader does not follow, and only
   where no earlier option takes the flag as its own value. Claude Code's `"$(cat <<'EOF' … EOF)"`
   message is one quoted word only where it ends where bash ends it and its body holds no `"`, `$`,
   backtick or backslash: macOS `/bin/bash` 3.2 ends the `$(` early and reads the rest as
   double-quoted text, where nothing else can run. Anything else stays in view. Brace lists expand
   as bash expands them (`.claude/hooks/lib/expand.awk`). A glob is read as the name of hers it
   could match, glob groups included (`gi[t]`, `@(git)`, zsh's `(a|b)`): git, or git's own binary
   for a command (`git-push`), a protected branch, `.git/hooks`. Names match without case, as
   macOS's disk finds `GIT`. What it cannot read before the hook times out is refused: a command
   over 256 KB, or an expansion past 100,000 words or 2 MiB. Quoted text is expanded as code a
   nested shell might run, so a minified JSON array in one word reaches that limit at 16 two-field
   objects (fewer with more fields); pretty-printed JSON does not, and the refusal points to the
   Write tool (the
   tenth review round took this trade). It refuses the agent's writes to `nonna.*`,
   includes, aliases, `core.hooksPath`, push refspecs and `push.default`, whether through
   `git config`, `-c` or `--config-env`. It refuses a push of every branch (`--all`, `--mirror`, `:`,
   a wildcard), through `git push` or `subtree push`, and git's plumbing pushes (`send-pack`,
   `http-push`), which run no hook. It also refuses the variables the gates read, and hand edits of
   `.git/config` and the git hooks. It is a speed bump, not a sandbox.
   These get past it:
   - a script file, or git under another name;
   - another language's interpreter (`python3 -c`, `perl -e`), and code the test suite runs (a test
     or a `conftest.py` the agent wrote), which the gates themselves run;
   - a value the shell computes when it runs (a variable, `$(…)`'s output, `xargs`);
   - a glob that a file the agent made completes;
   - git configuration already in place (the user's own `push.default`);
   - a tool that writes to the server another way (`gh api`).

   Branch protection on the server is the wall.

5. **Lite** is the test gate, "where's the test?", the branch guard, the secret guard, the git hooks
   and six house rules (`.claude/hooks/lib/lite.md`, linted to 150 words and to cover the never-list's
   tests, branch and secret lines). **Full** adds the STATUS gate, the constitution and the
   develop-to-main flow. Lite is the plugin's default; copy-in stays full until round 3 decides.
6. **The plugin's test gate is on, with recorded consent.** The `run_tests` option (on, asked at
   enable) is the consent. The first session in a repository records the detected command in
   `nonna.testCmd` and never overwrites it, an empty one included. Detection at run time is copy-in
   only. The consent is per plugin, not per repository, together with Claude Code's folder trust and
   the first-session notice. The security review asked for per-repository confirmation. The
   maintainer chose this design, and the review recorded it as an accepted risk.
7. **The STATUS gate is full mode's**, and only where `docs/STATUS.md` exists, at Stop and pre-push.
   A repository that keeps one cannot throw it out: in full mode a push that deletes it is refused.
   So is a turn that changed code and deleted it.
8. **A plugin runs and wires only its own scripts.** A repository can ship a `.claude/hooks/` of its
   own. It is the harness only when it is the one running, which is a copy-in install. The plugin
   sources its own library and links the git hooks to its own scripts, through
   `${CLAUDE_PLUGIN_DATA}/current`, which each session points at the running version so the hooks
   survive updates.
   - A dangling link of Nonna's (or Keel's) is repaired. Hers means the link she would make now,
     one into her cache or data in the plugins directory Claude Code uses, or a copy-in's
     `../../.claude/hooks/<script>`; a path merely shaped like hers is not.
   - A foreign hook is never overwritten, and neither is a hook manager's directory.
   - A hook that points at nothing is reported. So is a hook manager, any gate that could not be
     wired, and a foreign hook, unless it chains hers by naming her script's path.
9. **The guards live in hooks.** The branch guard refuses force pushes, `--no-verify` and hook-path
   overrides. The secret guard refuses reads and searches (Read, Grep) of secret files by any name
   that leads to one: case-folded, with symlinks followed. It is linted against `settings.json`'s
   deny-list, so the two cannot drift.
10. **Stop tells the truth and asks once.**
    - A per-session base means work committed during the session is still checked.
    - "Where's the test?" asks once per set of changed code in a session.
    - The suite's output reaches the agent quoted, as the repository's words, never as hers.
11. **The ladder is said once.** In full mode, when another enabled plugin already states the "reuse
    before you write" ladder, the carrier drops the constitution's copy. Only
    `.claude/hooks/lib/ladder.sh` names that plugin; `NONNA_LADDER=on|off` overrides it.
12. **Her settings are the user's, and `/nonna` is how the user changes them.**
    - `/nonna` (`.claude/skills/nonna/`) shows what she enforces and where each setting comes from.
      It sets the mode and the test command, runs `setup`, and runs `uninstall`, which takes back
      only what is hers and names each value. A change to the user's own files is only offered.
    - It is the user's alone: `disable-model-invocation`, linted. Claude Code runs a skill's `!`
      line through its permission check alone, with no PreToolUse hook in front of it. So
      `allowed-tools` pre-approve exactly that line, and the lint holds them to it. A line not
      pre-approved would ask; in auto mode it goes to the model, where the guard refuses it.
    - The branch guard refuses the agent running her scripts. It refuses a command that names them
      and runs a shell, however the two are joined:
      - the naming: her skill's directory, `nonna.sh`, a glob that could be `skills/nonna/scripts`,
        or any script run while the Bash tool is inside her directory;
      - the shell: as the command (`sh`, `bash`, `source`, `.`, `exec`, `eval`, a `*.sh`, or any
        program given by its path, as a copy would be), or through one that runs another (`env`,
        `sudo`, `xargs`, `find -exec`…).

      Reading, searching, linting and staging them run no shell. A part of the command that only
      reads her files (`cat`, `grep`, `shellcheck`, `git add` or `diff`…, redirecting nothing) does
      not name them, unless a pipe or a command or process substitution could carry what it read
      into a shell; so reading or linting her scripts and then running the suite passes. Like any
      script file (4), a copy run from elsewhere in a later command, another language's interpreter,
      or a path computed at run time gets past it, and so does a reader made to start a program
      through an option of its own: the reader list trusts readers to read (a `debt:` marker in
      the guard names when to revisit it).

    - **While she is off, the guard keeps her settings and nothing else.** It still refuses the
      agent:
      - writing `nonna.*` or config that routes git around her hooks;
      - editing `.git/config` or the git hooks, by hand or with the file tools;
      - setting the variables her gates read;
      - running her scripts.

      Otherwise an agent could ready the ground while she is off, a test command of `true` or a
      hooks path around her, and the user who switches her back on would get a gate that no longer
      bites, without a word. It reads each command as it does when she is on. What it cannot read
      (too long, an expansion too large, quotes nested too deep) is refused only when it could touch
      her settings: git or nonna in it, however quoted, a `$'…'` escape, or a run inside her
      directory. So while she is off, an unreadable command that spells those names some other way
      gets past; a readable one is still read in full. Force pushes, protected branches and
      `--no-verify` are not hers to stop while she is off, and nothing else is said. The user chose
      this over a silent off.

## Consequences

- A plugin install does what the README says on its first session, with nothing to configure.
- **The git hooks now reach people, not only agents**: anyone who commits or pushes in a repository
  where a session ran. That is the point of a gate, and it is announced: the first session tells the
  user what Nonna added, once per repository per major version (`nonna.announced`). The ways out are
  `/nonna off` or `nonna.mode off` (repo or `--global`), and `/nonna uninstall` or the removal steps
  in [INSTALL.md](../INSTALL.md).
- The environment no longer reaches the git hooks. Anyone who set `NONNA_TEST_CMD` for their own
  pushes sets the repository's command with `/nonna test` instead.
- State lives in `.git/config`, `.git/hooks` and `.git/nonna/`, never in a commit. Uninstalling the
  plugin leaves the git hooks dangling, which git skips, so the removal steps come first.
- `run_tests` decides only on first sight. Turning it off later does not reach a repository that
  already recorded a command; `nonna.testCmd` decides there. Revisit if users expect otherwise.
- A repository's own test command runs with plugin-wide consent (6). If per-repository consent
  proves wanted, `/nonna setup` is where to ask for it.
- Lite still loads every agent and skill, because it is one plugin; the house rules tell the agent
  to run them only when asked. Round 3 counts subagent spawns. If unasked reviews show up, the agent
  descriptions become mode-neutral.
- ADR 0007: the carrier now carries by mode (`lite.md` or `00-core.md`). ADR 0008: "no lighter mode"
  no longer holds; its rejection of model-set intensity stands.
- Revisit lite as the default if round 3 shows it leaking against the pre-registered table.
