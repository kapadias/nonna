# Installing Nonna

Three ways in: the Claude Code plugin, the [GitHub Copilot CLI plugin](#github-copilot-cli-the-plugin),
or `install.sh`, which puts the gates in the repository itself, for Claude Code and for other agents.
All three start in lite mode. Codex can install the plugin too ([Codex: the plugin](#codex-the-plugin)).

## Claude Code: the plugin

```
/plugin marketplace add kapadias/nonna
/plugin install nonna@nonna
```

Or from a terminal: `claude plugin marketplace add kapadias/nonna && claude plugin install nonna@nonna`

The plugin starts in lite mode: the test gate, "where's the test?", the branch and secret guards, the
git hooks and six house rules. [Full mode](#full-mode) adds more, for teams. The plugin's two
options, `run_tests` and `mode`, are under [Configuration](#configuration).

The first session in each git repository tells you, once, what Nonna did there:

```text
Nonna is on here (lite). Before the agent can say done, Nonna runs: python3 -m pytest -q. Added .git/hooks/pre-push and pre-commit. See or change it with /nonna.
```

When she finds no test suite, it says so:

```text
Nonna is on here (lite). She found no test command here (or its runner is not installed), so the test gate is off; set one with: /nonna test '<command>'. Added .git/hooks/pre-push and pre-commit. See or change it with /nonna.
```

When a git hook could not be wired, a `Note:` says which gate is not enforced and why.

Using another agent, or want the gates committed for your whole team? See
[install.sh](#other-agents-installsh). Gemini CLI can also load the rules as
[an extension](#gemini-cli-the-extension), without the hooks.

### `/nonna`

```
/nonna                   what she enforces here, and where each setting comes from
/nonna setup             record the test command she finds, wire the git hooks, offer the rest
/nonna lite|full|off     this repository's mode
/nonna test 'make test'  this repository's test command (/nonna test off turns the gate off)
/nonna test --dir packages/api 'pytest -q'
                         that directory's own test command, for a monorepo (off takes it out)
/nonna uninstall         take her git hooks, settings and state back out of this repository
```

- `/nonna` shows her version, the mode and where it comes from, then one line each for the test
  gate (the command, where it comes from, and whether this tree already passed), each directory's
  own test command, the branch guard, the secret guard, the STATUS gate and the two git hooks. It
  changes nothing.
- `/nonna setup` records the test command detection finds, unless one is already recorded (an empty
  one included), and wires the git hooks. Then it offers what only you can decide: Claude Code's
  [deny-list](#optional-claude-codes-own-deny-list) in `.claude/settings.json`, and in full mode a
  `docs/STATUS.md`. Those files change only when you say yes. While she is off, it records and
  wires nothing.
- `/nonna lite|full|off` sets `git config nonna.mode` in this repository. If `NONNA_MODE` is set
  where Claude Code runs, it tells you that the variable still decides.
- `/nonna test '<command>'` sets `git config nonna.testCmd`; `/nonna test off` sets it empty, which
  turns the test gate off. If `NONNA_TEST_CMD` is set, it tells you that the variable still decides
  at the end of a turn.
- `/nonna test --dir <directory> '<command>'` gives a directory of the repository its own command,
  `git config nonna.<directory>.testCmd`, with the directory named from the repository's top; see
  [A test command per directory](#a-test-command-per-directory). `/nonna test --dir <directory> off`
  takes it out.
- `/nonna uninstall` takes out what is hers: see [Uninstall](#uninstall).

`/nonna` is yours. Claude Code runs it when you type it; the agent cannot invoke it, and the branch
guard refuses the agent running its scripts. If another command already has the name, type
`/nonna:nonna`, which always works. With Claude Code's `disableSkillShellExecution` setting on,
`/nonna` cannot run, and [git config](#configuration) still works.

## What Nonna changes on your machine

In each git repository where a session starts:

- **`.git/hooks/pre-push` and `.git/hooks/pre-commit`**: links to her scripts, added only where the
  hook does not exist yet. Under the plugin they lead through the plugin's data directory
  (`~/.claude/plugins/data/…/current`), which each session points at the running version, so the
  hooks survive plugin updates; a copy-in install links to the repository's own `.claude/hooks/`.
  They run her own scripts, never ones a repository ships: git refuses to let a clone install hooks,
  and so does she. An existing hook is never overwritten and a hook manager's directory
  (`core.hooksPath`) is never written: both are reported, and so is a hook of hers that points at
  nothing.
- **`.git/config`**: `nonna.testCmd` (the [test command](#the-test-command)), `nonna.defaultMode`
  (the plugin's `mode` option, mirrored for the git hooks, which cannot read it; or the mode
  `install.sh` installed) and `nonna.announced` (the first-session notice was shown). `nonna.mode`
  and a directory's `nonna.<directory>.testCmd` only when you set them.
- **`.git/nonna/`**: where each session began, so work committed during a session cannot dodge the
  test gate, and which changes were already asked for a test. Files older than a week are deleted.
  Also the last green run of each directory's own test command.
- **`.git/nonna-green`**: the last tree and test command the suite passed on.
- **`.git/.nonna-branch-warned-<branch>`**: an empty file, so the warning about editing on `main`,
  `master` or `develop` shows once.

Outside your repositories, the plugin keeps one link, `current`, in its data directory. Nothing is
committed, and her hooks make no network calls.

`/nonna uninstall` takes all of it back out of a repository. By hand:

```bash
ls -l .git/hooks/pre-push .git/hooks/pre-commit     # remove them only if they point at Nonna
rm .git/hooks/pre-push .git/hooks/pre-commit
git config --remove-section nonna
git config --remove-section nonna.packages/api      # and each other directory with its own command
rm -rf .git/nonna .git/nonna-green .git/.nonna-branch-warned-*
```

## Configuration

`/nonna` shows which setting decides, and where it comes from.

| Setting                | Where                                     | What it does                                                                                                                                              |
| ---------------------- | ----------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `nonna.mode`           | git config, the repository or `--global`  | `off`, `lite` or `full`. Yours alone: Nonna never writes it, and `/nonna lite\|full\|off` sets it for you.                                                |
| `nonna.testCmd`        | git config, the repository or `--global`  | The [test command](#the-test-command). Empty turns the test gate off.                                                                                     |
| `nonna.<dir>.testCmd`  | git config, the repository only           | A [directory's own test command](#a-test-command-per-directory), run when a change is in it. Empty is none.                                               |
| `NONNA_MODE`           | the environment Claude Code runs in       | Outranks `nonna.mode` in Claude Code's hooks. The git hooks ignore it.                                                                                    |
| `NONNA_TEST_CMD`       | the environment Claude Code runs in       | Outranks `nonna.testCmd` at the end of a turn; empty turns that gate off. The `pre-push` hook ignores it.                                                 |
| `NONNA_TEST_TIMEOUT`   | the environment of Claude Code, or of git | Seconds the suite may run. Unset: 240 at the end of a turn, 600 before a push.                                                                            |
| `NONNA_CRITICAL_PATHS` | the environment Claude Code runs in       | Colon-separated globs of paths to treat as critical: `/fix` sends a change there to the full loop, and `/review` gives it the full review with security.  |
| `NONNA_LADDER`         | the environment Claude Code runs in       | Full mode under the plugin: `off` leaves the constitution's decision ladder out, `on` keeps it even when another plugin states it.                        |
| `run_tests`            | plugin option                             | On (the default): while a repository has no `nonna.testCmd`, each session detects one and records it. Off: nothing is recorded.                           |
| `mode`                 | plugin option                             | `lite` (the default) or `full`: the mode wherever you set no `nonna.mode`. Each session mirrors it into `nonna.defaultMode`, where the git hooks read it. |

Change the plugin's options with `/plugin configure nonna@nonna`, or set them as you install from a
terminal: `claude plugin install nonna@nonna --config mode=full`.

Claude Code's hooks take the mode from, in order: `NONNA_MODE`, your `nonna.mode` (the repository's,
then the global one), the plugin's `mode` option, `nonna.defaultMode`, and last what the repository
carries (her hooks and her rules: full; otherwise lite). A value nobody meant, such as a typo, fails
closed to full. The git hooks take the same order without `NONNA_MODE` and the plugin option: they
read their mode and test command from git config alone, never from the environment, a `git -c` flag
or a file the config includes, so a command cannot switch them off for itself.

```bash
git config nonna.mode full            # this repository (lite, full or off)
git config --global nonna.mode off    # every repository without its own setting
NONNA_MODE=off claude                 # one session's Claude Code hooks
```

`off` enforces nothing and says nothing, git hooks included, with one exception: her settings
([below](#these-switches-are-yours)).

### The test command

The Stop hook runs it before a turn that changed code can end, and the git `pre-push` hook before a
push that changes code. It comes from, in order: `NONNA_TEST_CMD` (Claude Code's hooks only), then
`git config nonna.testCmd` (the repository's, then the global one). A copy-in install with neither
detects the command each time instead.

Under the plugin, while a repository has no `nonna.testCmd`, each session start detects one and
records it, if `run_tests` is on. Detection takes the first row of this table whose files are there
and whose runner is installed:

| Found in the repository                                                        | Recorded                | Needs                                     |
| ------------------------------------------------------------------------------ | ----------------------- | ----------------------------------------- |
| `pytest.ini`, `tox.ini`, `conftest.py` or test files such as `tests/test_*.py` | `python3 -m pytest -q`  | pytest installed                          |
| a `Gemfile`, and `.rspec` or `spec/spec_helper.rb`                             | `bundle exec rspec`     | `bundle` on the `PATH`                    |
| a `Gemfile` and a `Rakefile`, and `test/`                                      | `bundle exec rake test` | `bundle` on the `PATH`                    |
| `phpunit.xml`, `phpunit.xml.dist` or `phpunit.dist.xml`, and `vendor/bin/pest` | `vendor/bin/pest`       | `php` on the `PATH`; that file executable |
| the same, and `vendor/bin/phpunit`                                             | `vendor/bin/phpunit`    | `php` on the `PATH`; that file executable |
| `gradlew` (Java, Kotlin)                                                       | `./gradlew test`        | `gradlew` executable; a JVM               |
| `mvnw`                                                                         | `./mvnw test`           | `mvnw` executable; a JVM                  |
| a `pom.xml`                                                                    | `mvn test`              | `mvn` on the `PATH`                       |
| one `.sln`, `.slnx` or `.*proj` file (`.csproj`, `.fsproj`, ...)               | `dotnet test`           | `dotnet` on the `PATH`                    |
| a `mix.exs`                                                                    | `mix test`              | `mix` on the `PATH`                       |
| a `test` script in `package.json`                                              | `npm test --silent`     |                                           |
| a `go.mod`                                                                     | `go test ./...`         |                                           |
| a `Cargo.toml`                                                                 | `cargo test --quiet`    |                                           |

A missing runner would read as a red suite and block every push, so a row whose runner is missing is
skipped, and detection goes on to the rows below it: a repository that `package.json`, `go.mod` or
`Cargo.toml` gated before is gated still. (The pytest row is the one exception: its files claim the
repository, and without pytest nothing is recorded.) The back ends come before `package.json`
because in a Rails, Laravel or Phoenix app it usually serves the front end. The scripts a repository
ships bring no runtime, so `gradlew` and `mvnw` need a JVM (`JAVA_HOME/bin/java` when `JAVA_HOME` is
set, else `java` on the `PATH`, as they look for one) and the `vendor/bin` scripts need `php`. A
`Gemfile` alone is no Ruby suite, nor is a bare `spec/` or `test/` (Jasmine and mocha use them), and
`dotnet test` cannot choose among several solution or project files, so a folder with more than one
skips that row. Detection looks for a runner and never starts one, nor any code the repository ships.

Once one is recorded, Nonna never changes it, not even an empty one; turning `run_tests` off later
does not remove it. That is the consent: under the plugin, Nonna runs your tests only when
`run_tests` allowed it or you set the command yourself, and a repository cannot set it for you,
because `.git/config` is never cloned. Every recorded command runs code the repository ships;
`./gradlew`, `./mvnw` and `vendor/bin/*` are the repository's own files, run as they are. Turn
`run_tests` off before opening a repository you do not trust. No suite found means no gate, and the
first-session notice says so.

On red, the Stop hook sends the agent back once with the failing lines: it fixes them, or it tells
you plainly that it is not done. What the suite prints is shown to the agent quoted, as the
repository's words, never as Nonna's: a test cannot hand the agent instructions in her voice. A
green run is remembered by tree and command, so an unchanged tree is not tested twice at the end of
a turn. "Where's the test?" asks once for a set of changes; an answer that the change needs none
holds until more code changes.

At the end of a turn the suite has 240 seconds, and one that runs out of time is not called red
there; Claude Code stops the Stop hook at 300 seconds, whatever `NONNA_TEST_TIMEOUT` says. Before a
push it has 600 seconds, and a suite that runs out of time there is refused.

The `pre-push` test gate tastes what you push. It runs in the working tree, so it refuses a push
while the tree differs from `HEAD`, untracked files included, and a submodule checked out at another
commit, edited inside, or holding untracked files, whatever `.gitmodules` says to ignore
(`ignore = untracked` for build output included). A pushed branch that is not checked out gets a
warning that its tests did not run; tags and deletes run nothing. A pushed merge counts for what it
takes from each side, not only for what its resolution changed, so a clean merge runs the tests too.

### A test command per directory

In a monorepo the whole suite often takes longer than those 240 seconds. Give each package its own
command instead ([ADR 0014](adr/0014-a-test-command-per-directory.md)):

```
/nonna test --dir packages/api 'pytest -q'
/nonna test --dir packages/web 'npm test'
```

That sets `git config nonna.packages/api.testCmd`, the directory named from the repository's top. A
changed file belongs to the longest such directory it is in, and a file in none belongs to the
repository's own command, if there is one. At the end of a turn, the Stop hook runs the command of
each directory that owns a file changed this session (a new file git does not ignore counts), once
and in that directory, then the repository's command if a changed file is in no directory. If it
cannot list the changes, it runs every command. The commands run in the order `/nonna` lists them,
share the 240 seconds, and the first red one sends the agent back, named with its directory. A
directory's command is not run again while nothing but the directories beside it has changed since
it last passed; a shared file outside every package, such as a lockfile, or a package inside it,
runs it again. A directory that
leads out of the repository, through a link, is red. Before a push, the `pre-push` hook chooses the
same way from the pushed commits, and each command gets its 600 seconds.

`NONNA_TEST_CMD` still replaces them all at the end of a turn. A directory's command is read from the
repository's own config, never the global one. An empty one is no command, so the directory's files
go to the repository's command; to test nothing there, give it a command that passes, such as
`true`. With directory commands set, `/nonna test off` turns off only the repository's own command.
A change in one package that breaks another is caught only by a command that runs the other
package's tests.

### These switches are yours

The branch guard refuses an agent that tries to change Nonna's settings (her git config, config
that routes git around her hooks, the git hooks, the variables her gates read) or run `/nonna`'s
scripts, even while she is off, so she comes back on, with the test command you chose, only when you
say so. While she is on, it also refuses a force push and skipping the hooks. It reads each command
the way the shell will run it, quotes, brace lists and globs and all. It is still a speed bump, not
a sandbox: an agent that writes a script and runs it, runs git under another name, or computes a
flag when the command runs, is past it. The wall is on the server: protect `main` with a branch
protection rule.

## Full mode

|                                                                                               | lite (default)                                              | full                                                                                                                 |
| --------------------------------------------------------------------------------------------- | ----------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------- |
| Test gate: the whole suite before a turn that changed code can end, and before a push         | ✓                                                           | ✓                                                                                                                    |
| "Where's the test?": code changed and no test did, asked once per set of changes              | ✓                                                           | ✓                                                                                                                    |
| Branch guard: no commit or push on `main`/`master`/`develop`, no force push, no `--no-verify` | ✓                                                           | ✓                                                                                                                    |
| Secret guard: writes, reads and searches of secret files, commits, pushes                     | ✓                                                           | ✓                                                                                                                    |
| The rules the agent gets                                                                      | six house rules ([`lite.md`](../.claude/hooks/lib/lite.md)) | the constitution ([`00-core.md`](../.claude/rules/00-core.md)); in a copy-in install, all nine rules and `CLAUDE.md` |
| `docs/STATUS.md` must change with the code (and stay), at turn end and pre-push               |                                                             | ✓, where the file exists                                                                                             |
| Her agents and workflows (`/plan`, `/tdd`, `/review`, `/ship`…)                               | under the plugin                                            | ✓                                                                                                                    |

Full mode adds process, not safety. In round 3 of the benchmark it was no safer than lite: 0 of 64
trap runs cut a corner, against lite's 1 of 64, and a small change cost $0.096 on Claude Sonnet
against lite's $0.071 ([results](../bench/README.md)). Treat its extras as extras for teams.

Switch one repository with `/nonna full`, every repository without its own setting with
`git config --global nonna.mode full`, or set the plugin's `mode` option to full. A copy-in install
needs full's files: run `install.sh --mode full`, since `/nonna full` changes the mode and brings no
files.

Try `/plan`, `/tdd`, `/review` and `/ship`, or `/fix` for a trivial change (`check-trivial.sh`
decides what qualifies, not prose); under the plugin they are `/nonna:plan` and so on. Lite tells
the agent to run them only when you ask. `/test` runs your lint, type-check, test and coverage gate;
each pack under [`stacks/`](../stacks/README.md) lists its stack's commands.

### Under the plugin, only the constitution rides along

Claude Code's plugin schema has **no `rules` component**, and the root `CLAUDE.md` lives outside the
plugin root. So in full mode, `rules/00-core.md` (the three principles, the loop, the ladder, the
never-list) rides `SessionStart` into the session and `SubagentStart` into every subagent, with a
line that tells the agent where the other rules are. The other eight `.claude/rules/*.md` files and
`CLAUDE.md` do **not** load, even though they sit inside the published plugin directory. Lite is
not affected: its six house rules ride the same way, whole. If you want all of full mode's policy,
copy it in alongside the plugin:

```bash
git clone --depth 1 https://github.com/kapadias/nonna /tmp/nonna
mkdir -p .claude/rules && cp -r /tmp/nonna/.claude/rules/. .claude/rules/
[ -e CLAUDE.md ] || cp /tmp/nonna/CLAUDE.md CLAUDE.md
```

The last line keeps a `CLAUDE.md` you already have. Once the rules are in the repository, Claude
Code loads them in every session and Nonna stops carrying her own, in lite mode too.

If another plugin already gives the agent the same "reuse before you write" ladder, full mode leaves
its own copy out rather than say it twice. `NONNA_LADDER=on` or `off` decides it yourself.

## Codex: the plugin

Codex reads the same marketplace and installs the same plugin:

```
codex plugin marketplace add kapadias/nonna
```

Then install Nonna from `/plugins` in Codex, or with `codex plugin add nonna@nonna` from a terminal,
and trust her hooks in `/hooks`. Codex runs no plugin hook until you trust it, and asks again when
an update changes one.

Codex loads her hooks from `hooks/codex-hooks.json`, which the plugin's `.codex-plugin/plugin.json`
names, and runs the same scripts as Claude Code, with `NONNA_HOST=codex` so that each reads Codex's
payload:

| Codex event                   | What runs                                                                    |
| ----------------------------- | ---------------------------------------------------------------------------- |
| `SessionStart`                | wires the git hooks, records the test command, carries her rules             |
| `PreToolUse` on `Bash`        | the branch guard and the secret guard, as under Claude Code                  |
| `PreToolUse` on `apply_patch` | both guards, on each file the patch touches and the lines it adds            |
| `Stop`                        | the test gate and "where's the test?": a red suite sends the agent back once |
| `SubagentStart`               | carries her rules into each subagent                                         |

Codex edits with `apply_patch`, one call that can add, change, move and delete several files.
`lib/host-codex.sh` reads it as Claude Code's Write and Edit, one per file, so each guard judges a
file of the patch as it judges a Claude Code edit. It refuses a patch it cannot read with
certainty, and one over 256 KB or 200 files, too much to check before the hook times out.

Nothing else is wired: Codex's `PostCompact` takes no context (its `SessionStart` after a compaction
carries the rules again), the plugin never formats, and Codex runs none of her agents, so there is
no review verdict to check.

What differs from Claude Code:

- **Her settings are git config.** `/nonna` is Claude Code's command; where a notice names it, use
  `git config nonna.mode` and `git config nonna.testCmd` ([Configuration](#configuration)). The
  plugin's options are Claude Code's too: under Codex she runs with their defaults, lite and
  `run_tests` on.
- **The git hooks link through Codex's plugin data directory** (`~/.codex/plugins/data/…/current`).
  To take her out, run the [commands by hand](#what-nonna-changes-on-your-machine) in each
  repository, then `codex plugin remove nonna@nonna`.
- **Not yet proven in Codex.** The hooks are golden-tested against the payloads Codex documents,
  and Codex 0.159.2 installs the plugin and lists exactly these hooks. They have not yet run in a
  Codex session end to end, and the benchmark has no Codex arm, so no number in the README is
  Codex's.
- **What her Codex hooks do not see.** Codex runs no hook for input sent to a shell session that is
  already running, so a command typed into a shell that already passed the guards is not read by
  them, a later `git push --no-verify` there included. An `apply_patch` or a heredoc run through
  the shell reaches her as a shell command, and nothing it writes is scanned for secrets. Her git
  hooks are the backstop, except against `--no-verify`, which skips them; the wall is branch
  protection on the server.

Without the plugin, `install.sh --host agents` gives Codex the house rules in `AGENTS.md` and the git
hooks, as every other agent gets them.

## GitHub Copilot CLI: the plugin

```bash
copilot plugin marketplace add kapadias/nonna
copilot plugin install nonna@nonna
```

Copilot CLI reads this repository's `.github/plugin/marketplace.json`, which it checks before the
Claude Code one in `.claude-plugin/`. The plugin is the repository itself: `.github/plugin/plugin.json`
points at [`hooks/copilot-hooks.json`](../hooks/copilot-hooks.json), which runs her scripts from
`.claude/hooks/`. It needs Copilot CLI 1.0.72 or later on macOS or Linux (the hooks are bash; there
are no PowerShell entries), and it runs in the CLI only: Copilot cloud agent installs no plugins.

| Copilot event  | Her script                          | What it does                                                                                                                                                                                                                          |
| -------------- | ----------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `sessionStart` | `session-start.sh`                  | records the test command detection finds in `git config nonna.testCmd`, wires the git `pre-push` and `pre-commit` hooks through the plugin's data directory, carries the house rules into the session, and tells you once what it did |
| `preToolUse`   | `guard-branch.sh`, `secret-scan.sh` | the branch guard on every command and file edit; the secret guard on every command, file write and file read                                                                                                                          |
| `agentStop`    | `stop-dod.sh`                       | when code changed, runs the suite and sends the agent back on red, once, and asks "where's the test?"                                                                                                                                 |

The hooks file names the events in PascalCase (`SessionStart`, `PreToolUse`, `Stop`), and for those
Copilot sends its VS Code compatible payload: snake_case, with Claude Code's tool names, which her
scripts read as they read Claude Code's. Each hook runs with `NONNA_HOST=copilot` (the entry's `env`),
and [`host-copilot.sh`](../.claude/hooks/lib/host-copilot.sh) translates what still differs: the
tools' argument names (`path`, `file_text`, `old_str`, `new_str`, grep's `paths`, `write_bash`'s
`input`), which win over any Claude-named key beside them, and her replies. A grep over several paths
is judged path by path, and any refusal refuses; more than 32, too many to judge before the hook
times out, are refused up front. A call not in the shape Copilot sends (arguments that are not an
object, where only `apply_patch`'s raw text comes as a string; a path that is not a string; paths
that are not one path or a flat, non-empty list; a write's text, an edit's strings or a patch's
text that is not a string; a file tool that names no path and carries no patch) is refused, never
read untranslated. A refusal
also goes out as `permissionDecision: "deny"` with her message as the reason, the form Copilot
shows the agent, and session start's context as `additionalContext`
([ADR 0015](adr/0015-copilot-cli-plugin.md)).

What differs from Claude Code:

- **No `/nonna` and no plugin options.** The defaults hold (lite; record and run the test command).
  Change them in git config, as `/nonna` does: `git config nonna.mode full` (or `off`),
  `git config nonna.testCmd '<command>'`. Or run her script yourself from the repository:
  `bash ~/.copilot/installed-plugins/nonna/nonna/.claude/skills/nonna/scripts/nonna.sh test '<command>'`
  (under `$COPILOT_HOME` if you set it).
- **An `apply_patch` is read a file at a time.** `lib/patch.sh` reads it by its grammar, as it reads
  Codex's, and each file the patch adds, updates, moves or deletes reaches both guards as Claude
  Code's Write or Edit, with the lines the patch adds to it: a patch that touches `.git/config` or
  adds a key to any of its files is refused. So is a patch the reader cannot read with certainty,
  and one over 256 KB or 200 files, too much to judge before the hook times out. A guard that
  crashes denies the tool call, as Copilot rules, where Claude Code lets it through. Without jq,
  what the text alone cannot show safely (a payload that does not close, arguments that are not an
  object, a list of paths, a Claude-named key beside Copilot's, input to a shell, a patch beside
  other arguments) is refused.
- **Copilot's own switches are the user's.** Under either agent, the branch guard refuses the agent
  writing `.github/copilot/settings*.json`, where one `disableAllHooks` line turns every hook off, or
  anything under `.github/hooks/`, by file tool or by shell.
- **A copy-in install's hooks run too.** Copilot CLI also runs the hooks in a repository's
  `.claude/settings.json`, which `install.sh` writes: untranslated, so they read Copilot's commands
  but not its file tools, and beside the plugin each gate runs twice. Where Copilot leaves
  `CLAUDE_PROJECT_DIR` unset for them, they cannot start, and Copilot counts that as a denial. With
  Copilot, use the plugin.
- **Her git hooks point into Copilot's plugin data.** `/nonna` and its scripts do not take those
  links for hers: `uninstall` leaves them in place and says so. Remove `.git/hooks/pre-push` and
  `.git/hooks/pre-commit` yourself.
- **Not yet run in a live Copilot session.** The wiring is golden-tested against Copilot's
  documented hook payloads (`tests/run.sh`, "Copilot CLI plugin").

To remove her: `copilot plugin uninstall nonna@nonna`, then her two git hooks, and
`git config --remove-section nonna` if you want her settings gone too.

## Other agents: install.sh

One command, from the root of a git repository:

```bash
curl -fsSL https://raw.githubusercontent.com/kapadias/nonna/main/install.sh | bash
```

For another agent, add `-s -- --host <name>` (several at once: `--host cursor,agents`):

| Agent                                                                     | `--host`           | Rules file                                                                     |
| ------------------------------------------------------------------------- | ------------------ | ------------------------------------------------------------------------------ |
| Claude Code                                                               | `claude` (default) | lite: none, the `SessionStart` hook carries the house rules; full: `CLAUDE.md` |
| Codex, Zed, Amp, opencode, Roo Code, Jules, Junie, any `AGENTS.md` reader | `agents`           | `AGENTS.md`                                                                    |
| Cursor                                                                    | `cursor`           | `.cursor/rules/nonna.mdc`                                                      |
| GitHub Copilot                                                            | `copilot`          | `.github/copilot-instructions.md`                                              |
| Gemini CLI                                                                | `gemini`           | `GEMINI.md`                                                                    |
| Windsurf                                                                  | `windsurf`         | `.windsurf/rules/nonna.md`                                                     |
| Cline                                                                     | `cline`            | `.clinerules/nonna.md`                                                         |
| Kiro                                                                      | `kiro`             | `.kiro/steering/nonna.md`                                                      |
| All of them                                                               | `all`              | all of the above                                                               |

`install.sh` installs **lite** unless you say otherwise: her hooks and their `settings.json` wiring,
the git `pre-commit` and `pre-push` hooks, `/nonna`, and short house rules for each host that reads
a rules file. It writes no rules, agents or workflows, no `CLAUDE.md` and no `docs/STATUS.md`, and it
records `git config nonna.defaultMode lite`.

`--mode full` brings the whole harness: the nine rules, the eight agents, the fifteen workflows and
twelve playbooks, `CLAUDE.md` for Claude Code, the constitution in each other host's rules file, and
a blank `docs/STATUS.md`. It records `nonna.defaultMode full`.

In both modes, when it finds `pyproject.toml`, `setup.cfg` or `setup.py`, `package.json`, `go.mod`
or `Cargo.toml`, it also writes that stack's `.claude/settings.local.json` from
[`stacks/`](../stacks/README.md): Claude Code permissions that let the exact commands the stack's
gate runs (its test, lint, format and type-check commands) run without asking, for Python
`pytest`, `python3 -m pytest -q`, `ruff check .`, `mypy .` and a few more. Never a prefix, since a
runner's flags can run any program or write any file (`go test -exec`, `npm test --node-options`),
and never an interpreter, a package manager or `awk`. The output lists what the pack grants, and the file is
added to your `.gitignore` because it is yours alone. Where several stacks match, the last in that
list wins. A `settings.local.json` you already have is kept, and so is one an earlier `install.sh`
wrote, which pre-approved more: delete it and run again to get the narrow pack.

Every host gets the git hooks. `pre-commit` refuses a commit on `main`, `master` or `develop`, a
staged secret file and a staged credential; `pre-push` refuses a secret in any pushed commit, a red
test suite, and in full mode a code push that leaves `docs/STATUS.md` untouched. A repository born on
`main` makes its very first commit with `git commit --no-verify`, then branches. Claude Code also
gets the tool-level hooks: a write is scanned before it lands, a turn that ends on a red suite is
sent back, and the guards check every command, file write and file read. On other hosts the house
rules and the git hooks do the work. In round 3 of the benchmark, run in Claude Code, the house rules did most
of it: in lite, the test gate and the branch guard never had to fire.

Running it again without `--mode` never changes the mode: it keeps the mode recorded in
`nonna.defaultMode`. With no record, a repository that carries both
`.claude/hooks/require-status-sync.sh` and `.claude/rules/00-core.md`, as every install by the old
installer does, stays full, and the output says `kept as this repository has it`. A record that is
neither `lite` nor `full`, such as a typo like `Full`, counts as full, as her hooks read it, and the
output says so. `--mode lite` or `--mode full` changes it. No file is deleted or overwritten either
way, so an existing full install needs nothing done. Your own `nonna.mode`, in the repository or
`--global`, still outranks the recorded mode; the installer neither reads nor writes it.

It never overwrites a file or a git hook that already exists, and never writes through a symlink. It
merges into an existing `.claude/` file by file and lists what it left alone, so running it again
adds what is missing and leaves every file already there as it is. Where you already have a git
hook, it tells you to chain hers from it; where a hook manager owns the hooks (a custom
`core.hooksPath`) or a linked worktree shares the main checkout's, it tells you which scripts to
point them at. It exits non-zero when a gate is not in place, and the output says which: a symlink
in the way, a file it could not write, a `.claude/settings.json` of yours that does not run her
hooks, or a git hook it did not wire (yours does not run hers, a hook manager or a linked worktree
owns the directory, or the link failed). On hosts other than Claude Code the git hooks are the only
enforcement, so read that exit as a gate that is off. Once your hook or your hook manager runs hers,
running it again exits 0. Pin a release with `curl … | NONNA_REF=<tag> bash`. Prefer to read before
you pipe? `curl -fsSLO …/install.sh`, read it, then `bash install.sh`.

### Gemini CLI: the extension

Gemini CLI can also take the house rules as an extension, with nothing to pipe into a shell. This
works from v2.0.0: Gemini CLI installs the latest release, and v1.0.0, the one before, has no
extension manifest.

```bash
gemini extensions install https://github.com/kapadias/nonna
```

It carries lite's six house rules and nothing else. **An extension installs no git hooks**, so until
you add them, nothing but the agent's own care stops a commit on `main`, a secret or a push on a red
suite. Run `install.sh --host gemini` from the root of the repository for the hooks. That also
writes `GEMINI.md` with the same rules, so with both the agent reads them twice, which does no harm.

- **It applies everywhere.** Gemini CLI enables an extension in every repository you use it in;
  `gemini extensions disable nonna --scope workspace` turns it off in one. It changes nothing in
  your repositories: Gemini CLI keeps it in `~/.gemini/extensions/nonna`.
- **It installs a release.** Gemini CLI takes the latest GitHub release's source archive, not
  `main`. `--ref v2.0.0` pins one, and `gemini extensions update nonna` moves to a newer one. The
  release workflow refuses a tag that differs from the `version` in `gemini-extension.json`, the
  number `gemini extensions list` shows.
- **Check it.** Restart Gemini CLI. `gemini extensions list` shows `nonna` and, under
  `Context files:`, `hosts/gemini-extension/GEMINI.md`, the file the extension loads; ask the agent
  for the house rules. From a clone, `gemini extensions link .` tries your own changes.
- **Uninstall.** `gemini extensions uninstall nonna`.

## Copy-in install, for teams

`install.sh` puts the gates in the repository itself. Commit what it adds, and everyone who clones
the repository gets them, plugin or not.

- **What to commit**: `.claude/`, the host rules files, and in full mode `CLAUDE.md` and
  `docs/STATUS.md`. `.claude/settings.local.json` is yours alone: `install.sh` adds it to your
  `.gitignore`, so it stays out of the commit.
- **Each clone wires its own git hooks**, because git never copies hooks. Claude Code wires them
  when a session starts in the clone. With another agent, run `install.sh` once in the clone: it adds
  nothing that is already there, links the hooks and records the mode.
- **The mode travels with the files.** A clone has no `.git/config` record of its own, so it goes by
  what the repository carries: the hooks and the rules run full, the hooks alone run lite.
  `--mode lite` over a full install changes only the clone where you run it. A teammate who also has
  the plugin gets the plugin's mode in their clone, because its first session records it as the
  clone's default; `git config nonna.mode full` in their clone keeps full.
- **The test command is detected each time** instead of recorded, unless you set `nonna.testCmd`.
- **Only a copy-in formats on edit.** After each edit, it runs the formatter it finds (ruff,
  prettier, gofmt, rustfmt, shfmt) on that file. The plugin never formats your files: it would
  rewrite whole files your project never formatted, and a formatter's config can run the
  repository's own code.
- **`/nonna` comes with both modes**; the agents and the other workflows come with `--mode full`.

## Optional: Claude Code's own deny-list

A plugin cannot bring `settings.json` permissions into your project, and Nonna does not need it to:
the branch guard refuses force pushes, and the secret guard refuses reads and searches of secret
files, by any name that leads to one. The deny-list is belt and braces: Claude Code itself refuses
too. `/nonna setup` offers to add it to your `.claude/settings.json`, and a copy-in install brings it
in the `settings.json` it copies, unless you already had one. The block, kept in sync with
[`.claude/settings.json`](../.claude/settings.json):

```json
{
  "permissions": {
    "deny": [
      "Read(./**/.env)",
      "Read(./**/.env.*)",
      "Read(./**/secrets/**)",
      "Read(./**/*.pem)",
      "Read(./**/*.key)",
      "Read(./**/*.p12)",
      "Read(./**/id_rsa*)",
      "Read(./**/.ssh/**)",
      "Read(./**/.aws/**)",
      "Read(./**/.npmrc)",
      "Read(./**/*.p8)",
      "Read(./**/*.pfx)",
      "Read(./**/*.jks)",
      "Read(./**/kubeconfig)",
      "Read(./**/credentials)",
      "Bash(git push --force:*)",
      "Bash(git push --force-with-lease:*)",
      "Bash(git push -f:*)"
    ]
  }
}
```

## Uninstall

### The plugin

In each repository where it ran, then once for the plugin:

```
/nonna uninstall
/plugin uninstall nonna@nonna
```

`/nonna uninstall` removes only what is hers, in every worktree, and names each thing with its
value: her git hook links, the repository's `nonna.*` settings, `.git/nonna/`, `.git/nonna-green`
and the branch-warning files. A git hook of yours is left alone and named, and so is one of yours
that still runs hers. It tells you when your global git config still has `nonna.*` settings;
`git config --global --remove-section nonna` removes them. The
[commands by hand](#what-nonna-changes-on-your-machine) do the same for the main checkout.

Clean the repositories first: once the plugin is gone its git hooks point at nothing, and git skips
a hook it cannot find without a word. Until then, a new session in a repository sets her up again;
to keep the plugin but not in one repository, use `/nonna off`.

### The Gemini CLI extension

`gemini extensions uninstall nonna` removes it. It added nothing to your repositories; the git
hooks and `GEMINI.md` that `install.sh --host gemini` adds come out as in
[a copy-in install](#a-copy-in-install).

### A copy-in install

Her files are part of the repository, so taking them out is a commit, and yours to make:

1. Delete the files `install.sh` added, not ones you had before, and commit: in lite,
   `.claude/hooks/`, `.claude/settings.json`, `.claude/skills/nonna/` and `.claude/.claude-plugin/`;
   in full, her whole `.claude/`, `CLAUDE.md` and `docs/STATUS.md`; the host rules files; and
   `.claude/settings.local.json` with its line in `.gitignore`, if it wrote them.
2. In each clone, remove the git side with the
   [commands by hand](#what-nonna-changes-on-your-machine).

Why the plugin and a copy-in install differ: [ADR 0006](adr/0006-distribute-as-plugin.md),
[ADR 0007](adr/0007-plugin-install-is-not-equivalent.md) and
[ADR 0011](adr/0011-lite-mode-and-plugin-defaults.md).
