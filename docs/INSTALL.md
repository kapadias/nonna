# Installing Nonna

Two ways in: the Claude Code plugin, or `install.sh`, which puts the gates in the repository itself,
for Claude Code and for other agents. Both start in lite mode. On native Windows, read
[Windows](#windows) first: some gates do not run there.

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
Nonna is on here (lite). She found no test command here, so the test gate is off; set one with: /nonna test '<command>'. Added .git/hooks/pre-push and pre-commit. See or change it with /nonna.
```

When a git hook could not be wired, a `Note:` says which gate is not enforced and why.

Using another agent, or want the gates committed for your whole team? See
[install.sh](#other-agents-installsh).

### `/nonna`

```
/nonna                   what she enforces here, and where each setting comes from
/nonna setup             record the test command she finds, wire the git hooks, offer the rest
/nonna lite|full|off     this repository's mode
/nonna test 'make test'  this repository's test command (/nonna test off turns the gate off)
/nonna uninstall         take her git hooks, settings and state back out of this repository
```

- `/nonna` shows her version, the mode and where it comes from, then one line each for the test
  gate (the command, where it comes from, and whether this tree already passed), the branch guard,
  the secret guard, the STATUS gate and the two git hooks. It changes nothing.
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
  only when you set it.
- **`.git/nonna/`**: where each session began, so work committed during a session cannot dodge the
  test gate, and which changes were already asked for a test. Files older than a week are deleted.
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
rm -rf .git/nonna .git/nonna-green .git/.nonna-branch-warned-*
```

## Configuration

`/nonna` shows which setting decides, and where it comes from.

| Setting                | Where                                     | What it does                                                                                                                                              |
| ---------------------- | ----------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `nonna.mode`           | git config, the repository or `--global`  | `off`, `lite` or `full`. Yours alone: Nonna never writes it, and `/nonna lite\|full\|off` sets it for you.                                                |
| `nonna.testCmd`        | git config, the repository or `--global`  | The [test command](#the-test-command). Empty turns the test gate off.                                                                                     |
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
records it, if `run_tests` is on: `python3 -m pytest -q` (pytest installed, and a `pytest.ini`,
`tox.ini` or `conftest.py`, or test files such as `tests/test_*.py`), `npm test --silent` (a `test`
script in `package.json`), `go test ./...` or `cargo test --quiet`. Once one is recorded, Nonna never
changes it, not even an empty one; turning `run_tests` off later does not remove it. That is the
consent: under the plugin, Nonna runs your tests only when `run_tests` allowed it or you set the
command yourself, and a repository cannot set it for you, because `.git/config` is never cloned. No
suite found means no gate, and the first-session notice says so.

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
while the tree differs from `HEAD`, untracked files included. A pushed branch that is not checked
out gets a warning that its tests did not run; tags and deletes run nothing.

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

## Windows

**Native Windows is not safe today. Use WSL 2.** Where Git for Windows is installed, Claude Code runs her
hooks in Git Bash. Most of her gates run there, but several do not stop what they guard, and a git hook
cannot be installed without native symlinks, which Git Bash does not use by default. Where Git for Windows
is not installed, none of her Claude Code hooks runs at all. Claude Code goes on after a hook that cannot
run: it reports a non-blocking error and does not stop.

This was measured on GitHub's `windows-latest` (Windows Server 2025, image `windows-2025-vs2026` 20260925.250.1)
by [the Windows job in CI](../.github/workflows/ci.yml) and [`tests/windows-probe.sh`](../tests/windows-probe.sh),
which prints the same facts on your machine: run `bash tests/windows-probe.sh` in Git Bash. WSL 2 was not
measured, because no CI job runs it. The gaps are tracked from #30 and listed in [`docs/STATUS.md`](STATUS.md).

**In WSL 2**, Claude Code runs on Linux and her hooks run as they do there, which is where her tests run.
That is expected, not measured. Install Claude Code and `git` inside the distribution, and keep the
repository on its own file system (`~/project`, not `/mnt/c`, which is slow and can hold a Windows
checkout's CRLF).

### Which shell runs her hooks

Claude Code chooses by whether Git for Windows is there
([setup](https://code.claude.com/docs/en/setup#set-up-on-windows),
[hooks](https://code.claude.com/docs/en/hooks)).

- **With Git for Windows**, a hook command runs in Git Bash. Two things arrive in Windows form: the
  plugin's paths (`${CLAUDE_PLUGIN_ROOT}` is `C:/Users/you/…`) and the paths of file tools, with
  backslashes (`C:\project\src\app.py`). Claude Code also turns on its **PowerShell tool**, by default
  for claude.ai and Console accounts, and then treats PowerShell as its primary shell. Her command
  guards match the `Bash` tool only, so they never see what it runs. Turn the tool off in
  `~/.claude/settings.json`:

  ```json
  { "env": { "CLAUDE_CODE_USE_POWERSHELL_TOOL": "0" } }
  ```

- **Without Git for Windows**, or where Claude Code cannot find it (set `CLAUDE_CODE_GIT_BASH_PATH` to
  `bash.exe`), hooks run in PowerShell and there is no Bash tool. Her hooks are bash, and PowerShell
  cannot parse their command. None of her Claude Code hooks runs, and `install.sh` needs bash too, so
  nothing is enforced.

### What runs where

Measured with Git for Windows 2.55.0.windows.5 (bash 5.3.15). `fails open` is a hook that runs and lets
through what it should stop; `never runs` is a hook that cannot start; `untested` is WSL 2.

| Hook                                   | Git for Windows, Git Bash                                                                                                                                                                                                                                                                  | PowerShell, no Git for Windows | WSL 2    |
| -------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------ | -------- |
| `session-start.sh`                     | runs. A plugin install wires no git hook: `D:/…` reads as a relative path, and the note calls her scripts "missing from the harness". A copy-in install got copies, not links, and said it had added them (it now removes a copy and says the gate is not enforced)                        | never runs                     | untested |
| `guard-branch.sh`, commands            | Bash tool: refuses a force push and a commit on `main`, whether `CLAUDE_PLUGIN_ROOT` is `/d/…`, `D:/…` or `D:\…`. Passes: the PowerShell tool, `git.exe push --force`, and a script run from her skill directory (the `cwd` has backslashes)                                               | never runs                     | untested |
| `guard-branch.sh`, Edit and Write      | fails open: `.git/config` is refused, but `D:\…\.git\config` and `D:\…\.git\hooks\pre-commit` pass                                                                                                                                                                                         | never runs                     | untested |
| `secret-scan.sh`, Read and Grep        | refuses `.env` by a backslash path. Passes `.ssh\id_rsa` and `secrets\db.yml` when their directory does not exist, which was the probe's case; it resolves a path through its directory first, which is why `.env` (its directory exists) was refused. The probe now makes the directories | never runs                     | untested |
| `secret-scan.sh`, Write and Edit       | refuses a key by a backslash path; refuses one under `tests\` too, where the exemption should let it through                                                                                                                                                                               | never runs                     | untested |
| `secret-scan.sh`, commands             | Bash tool: runs. PowerShell tool: `Get-Content .env` passes                                                                                                                                                                                                                                | never runs                     | untested |
| `format.sh` (copy-in only)             | runs                                                                                                                                                                                                                                                                                       | never runs                     | untested |
| `stop-dod.sh`                          | runs: GNU `timeout` comes first on the PATH. Its fallback for a machine without `timeout` failed the suite's check                                                                                                                                                                         | never runs                     | untested |
| `subagent-verdict.sh`                  | runs with jq; without jq it exits 0 and checks nothing, as designed                                                                                                                                                                                                                        | never runs                     | untested |
| `subagent-start.sh`, `post-compact.sh` | run                                                                                                                                                                                                                                                                                        | never run                      | untested |
| git `pre-commit` and `pre-push`        | a link runs and refuses a staged key (exit 1). A copy, which is what `ln -s` makes, cannot find its `lib/` and lets the commit through (exit 0)                                                                                                                                            | not installed                  | untested |

`tests/run.sh` passed 1164 of its 1264 checks on an LF checkout, and 1193 with native symlinks and no jq. What
fails is mostly the suite's own assumptions (real symlinks, jq, POSIX paths in Python) and the two gaps above;
the follow-up issues say which.

### What stops a hook, in the words you will see

- **PowerShell**, for the command every hook in `hooks.json` has the shape of: exit 1,
  `You must provide a value expression following the '/' operator.` (PowerShell 7.6.6, and Windows
  PowerShell 5.1.26100.33438). Claude Code reports `Failed with non-blocking status code` and goes on.
  With Git for Windows off the PATH, `bash` is `C:\Windows\system32\bash.exe`, the WSL launcher, and there
  is no `git`.
- **A copied git hook**: bash stops at line 22 of the copy, where it sources `lib/secret-patterns.sh` from the
  directory beside it (`.git/hooks/pre-commit: line 22: …/.git/hooks/lib/secret-patterns.sh: No such file or
directory`; the probe's row was cut off after `…/.git/ho`, and now keeps the whole line), and a staged
  AWS-style key commits (exit 0). Git Bash's `ln -s` makes a copy unless Developer Mode is on and
  `MSYS=winsymlinks:nativestrict` is set ([MSYS2](https://www.msys2.org/docs/symlinks/)); with both, the
  hooks were links and the same commit was refused (exit 1).
- **`D:/…` paths**: a plugin's root and data directory arrive with a drive letter, which session start reads
  as a relative path: `Note: require-status-sync.sh is missing from the harness, so the pre-push gate is NOT enforced`.
- **CRLF**: Git Bash runs a CRLF script without a word (exit 0). `core.autocrlf=true` is Git for Windows'
  default, and the runner's system config has it. A CRLF checkout failed two checks more than an LF one,
  which compare bytes or anchor a regex at a line end. The repository's `.gitattributes` now makes every
  checkout LF. WSL's bash does not tolerate CRLF (reproduced on Linux: `/usr/bin/env: 'bash\r': No such file or directory`).
- **jq.exe**: the runner's jq 1.8.1 is a native Windows build and writes CRLF (`x \r \n`, and `x \n` with
  `--binary`). It made no difference to a gate: the probe's rows are the same with and without it. Git for
  Windows brings no jq.

### Versions and cost

Windows Server 2025 (10.0.26100); Git for Windows 2.55.0.windows.5 with `core.autocrlf=true` and
`core.symlinks=true` in its system config; bash 5.3.15(2) on MSYS 3.6.10, GNU Awk 5.4.1, sed 4.9, grep 3.0,
`timeout` from GNU coreutils 8.32, Perl 5.42.3; jq 1.8.1; Python 3.12.10; PowerShell 7.6.6 and Windows
PowerShell 5.1.26100.33438. Claude Code's documentation is as of 2.1.285. One `guard-branch.sh` run took 1.3
to 1.7 seconds here and 0.1 on Linux, and a Bash tool call runs two hooks.

### If you use it anyway

Check each gate on your machine before you trust it: `bash tests/windows-probe.sh` marks `DIFFERS` where a gate
does something else than it does on Linux, and then the three checks that matter are to commit on `main`,
write a fake key into a file, and end a turn on a failing test. Each must be refused. What helps:

- Turn the PowerShell tool off, as above.
- Use native symlinks: Developer Mode, and `MSYS=winsymlinks:nativestrict` in your user environment, so that
  `ls -l .git/hooks/pre-push` shows `->`. A plugin install still wires no git hook, because of the `D:/…`
  paths; use a copy-in install ([`install.sh`](#other-agents-installsh)) in Git Bash instead.
- In a copy-in install, add `*.sh text eol=lf` and `*.awk text eol=lf` to your own `.gitattributes`: the
  repository's covers its own checkout, not the files it copies into yours.
- Add Claude Code's own [deny-list](#optional-claude-codes-own-deny-list), which it matches after turning
  `C:\Users\alice` into `/c/Users/alice` ([permissions](https://code.claude.com/docs/en/permissions)): it
  covers the secret files her Read guard can miss.

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
