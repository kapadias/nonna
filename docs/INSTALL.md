# Installing Nonna

## Claude Code: install the plugin

```
/plugin marketplace add kapadias/nonna
/plugin install nonna@nonna
```

Claude Code asks two things when you enable it: whether Nonna may run your tests (`run_tests`, on)
and which mode to start in (`mode`, lite). Change either later with `/plugin configure nonna@nonna`.

The first session in each repository tells you, once, what Nonna did there:

> Nonna is on here (lite). Before the agent can say done, Nonna runs: python3 -m pytest -q. Added
> .git/hooks/pre-push and pre-commit.

Using another agent, or want the gates to travel with the repo for your whole team? Use
[install.sh](#other-agents-or-a-whole-team-installsh).

## `/nonna`: see or change what she enforces

```
/nonna                   what she enforces here, and where each setting comes from
/nonna setup             record the test command she finds, wire the git hooks, offer the rest
/nonna lite|full|off     this repository's mode
/nonna test 'make test'  this repository's test command (/nonna test off turns the gate off)
/nonna uninstall         take her git hooks, settings and state back out of this repository
```

`/nonna` is yours. Claude Code runs it when you type it; the agent cannot invoke it, and the branch
guard refuses the agent running its scripts. If another command already has the name, type
`/nonna:nonna`, which always works. `setup` changes your own files only when you say yes: it offers
Claude Code's deny-list for secret files, and in full mode a `docs/STATUS.md`. With Claude Code's
`disableSkillShellExecution` setting on, `/nonna` cannot run, and the git config below still works.

## Modes

|                                                                                               | lite (default)                                              | full                                                           |
| --------------------------------------------------------------------------------------------- | ----------------------------------------------------------- | -------------------------------------------------------------- |
| Test gate: the whole suite before a turn that changed code can end, and before a push         | ✓                                                           | ✓                                                              |
| "Where's the test?": code changed and no test did, asked once per set of changes              | ✓                                                           | ✓                                                              |
| Branch guard: no commit or push on `main`/`master`/`develop`, no force push, no `--no-verify` | ✓                                                           | ✓                                                              |
| Secret guard: writes, reads and searches of secret files, commits, pushes                     | ✓                                                           | ✓                                                              |
| What rides into the session                                                                   | six house rules ([`lite.md`](../.claude/hooks/lib/lite.md)) | the constitution ([`00-core.md`](../.claude/rules/00-core.md)) |
| `docs/STATUS.md` must change with the code (and stay), at turn end and pre-push               |                                                             | ✓, if the file exists                                          |

`off` enforces nothing and says nothing, git hooks included, with one exception: her settings.
While she is off, the agent still may not change them (her git config, config that routes git
around her hooks, the git hooks, the variables her gates read) or run `/nonna`'s scripts, so she
comes back on, and with the test command you chose, only when you say so. Nonna's agents and
workflows (`/plan`, `/tdd`, `/review`, `/ship`…) are there in both modes; lite tells the agent to
run them only when you ask.

Switch with `/nonna lite|full|off`, or with git config, which your repository never commits and a
clone never carries:

```bash
git config nonna.mode full            # this repository (lite, full or off)
git config --global nonna.mode off    # every repository without its own setting
NONNA_MODE=off claude                 # one session's Claude Code hooks
```

The `mode` option is the default for repositories where you have set nothing. The git hooks read
git config alone, never the environment, a `git -c` flag or a file the config includes: a command
cannot switch them off for itself.

These switches are yours. The branch guard refuses an agent that tries to change Nonna's settings,
run `/nonna`'s scripts, edit `.git/config` or the git hooks, force a push, or skip the hooks, and it reads each command the
way the shell will run it, quotes, brace lists and globs and all. It is still a speed bump, not a
sandbox: an agent that writes a script and runs it, runs git under another name, or computes a flag
when the command runs, is past it. The wall is on the server: protect `main` with a branch
protection rule.

## The test gate

When a turn changed code, the Stop hook runs the whole suite. On red it sends the agent back with the
failing lines, once: it fixes them, or it tells you plainly that it is not done. The git `pre-push`
hook runs the suite again, for the agent and for you.
A green tree is remembered, so an idle turn end costs nothing. A suite slower than the Stop budget
(240 s, `NONNA_TEST_TIMEOUT`) is not called red there; pre-push still runs it in full.

The command comes from, in order: `NONNA_TEST_CMD` (empty turns the gate off; Claude Code's hooks
only), then `git config nonna.testCmd` (empty turns it off). A plugin install fills in the second one for you:
the first session in a repository, when `run_tests` is on, detects `pytest`, `npm test`, `go test`
or `cargo test` and records it. That is the consent: nothing runs your repository's code unless
`run_tests` allowed it or you set the command yourself, and a repository cannot choose the command,
because `.git/config` is never cloned.

Change it with `/nonna test 'make test'` (`/nonna test off` turns the gate off), or with git config:

```bash
git config nonna.testCmd 'make test'   # your own command
git config nonna.testCmd ""            # the test gate off, in this repository
```

`run_tests` only decides what happens the first time Nonna meets a repository. After that, the
repository's `nonna.testCmd` decides; Nonna never overwrites it, not even an empty one. No suite
found means no gate, and the first-session notice says so.

The pre-push test gate tastes what you push. It runs in the working tree, so it refuses a push while
the tree differs from `HEAD`, untracked files included. A pushed branch that is not checked out gets
a warning that its tests did not run; tags and deletes run nothing.

What the suite prints is shown to the agent quoted, as the repository's words, never as Nonna's:
a test cannot hand the agent instructions in her voice. "Where's the test?" asks once for a set of
changes; an answer that the change needs none holds until more code changes.

## What Nonna changes on your machine

In each repository where a session runs, and nowhere else:

- **`.git/hooks/pre-push` and `.git/hooks/pre-commit`**, links to Nonna's scripts through the
  plugin's data directory (`~/.claude/plugins/data/…/current`), which each session points at the
  running version, so the hooks survive plugin updates. They are Nonna's own scripts, never scripts
  a repository ships: git refuses to let a clone install hooks, and so does she. An existing hook is
  never overwritten and a hook manager's directory (`core.hooksPath`) is never written: both are
  reported, and so is a hook that points at nothing.
- **`.git/config`**: `nonna.testCmd` (above), `nonna.defaultMode` (the `mode` option, which git
  hooks cannot read, mirrored for them; your own `nonna.mode` always outranks it) and
  `nonna.announced` (the notice was shown).
- **`.git/nonna/`**: where each session began, so work committed during a session cannot dodge the
  test gate, and which changes were already asked for a test. Pruned after a week.
  **`.git/nonna-green`**: the last tree the suite passed on.

Nothing is committed, nothing is written outside `.git/`, and Nonna's hooks make no network calls.

To take it all back out of a repository, then remove the plugin: `/nonna uninstall` removes only
what is hers, in every worktree, and names each thing with its value. By hand:

```bash
ls -l .git/hooks/pre-push .git/hooks/pre-commit     # remove them only if they point at Nonna
rm .git/hooks/pre-push .git/hooks/pre-commit
git config --remove-section nonna
rm -rf .git/nonna .git/nonna-green
```

```
/plugin uninstall nonna@nonna
```

Clean the repositories first: once the plugin is gone its git hooks point at nothing, and git skips a
hook it cannot find without a word.

## Full mode on a plugin: only the constitution rides along

Claude Code's plugin schema has **no `rules` component**, and the root `CLAUDE.md` lives outside the
plugin root. In full mode `rules/00-core.md` (the three principles, the loop, the ladder, the
never-list) rides `SessionStart` into the session and `SubagentStart` into every subagent; in lite,
the house rules ride the same way. The other eight `.claude/rules/*.md` files and `CLAUDE.md` do
**not** load, even though they sit inside the published plugin directory. If you want all of full
mode's policy, copy it in alongside the plugin:

```bash
git clone --depth 1 https://github.com/kapadias/nonna /tmp/nonna
mkdir -p .claude/rules && cp -r /tmp/nonna/.claude/rules/. .claude/rules/
cp /tmp/nonna/CLAUDE.md CLAUDE.md
```

If another plugin already gives the agent a "reuse before you write" ladder, full mode leaves its
own copy out rather than say it twice. `NONNA_LADDER=on` or `off` decides it yourself.

## Optional: Claude Code's own deny-list

A plugin cannot bring `settings.json` permissions into your project. Nonna's hooks cover what they
were for (the branch guard refuses force pushes; the secret guard refuses reads and searches of
secret files, by any name that leads to one),
so this is belt and braces: Claude Code itself refuses too. Copy the block, kept in sync with
[`.claude/settings.json`](../.claude/settings.json), into your project's `.claude/settings.json`:

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

## Other agents, or a whole team: install.sh

One command, from the root of a git repository. It copies the gates into the repository itself, so
everyone who clones it gets them, plugin or not:

```bash
curl -fsSL https://raw.githubusercontent.com/kapadias/nonna/main/install.sh | bash
```

`--mode lite` brings the gates and nothing else: the hooks, their `settings.json` wiring and the git
hooks, with the house rules for hosts that read a rules file. `--mode full`, today's default, brings
the whole harness: the rules, agents, workflows and a blank `docs/STATUS.md`. The mode is recorded
as the repository's `nonna.defaultMode`; a copy-in install detects the test command each time
instead of recording it. A clone has no `.git/config` of its own to carry that record, so it goes
by what the repository carries: the hooks and the rules run full, the hooks alone run lite.

For another agent, name it (several at once: `--host cursor,agents`):

| Host                                                                      | Command                           | Rules file written                |
| ------------------------------------------------------------------------- | --------------------------------- | --------------------------------- |
| Claude Code                                                               | `… \| bash`                       | `CLAUDE.md` + `.claude/`          |
| Codex, Zed, Amp, opencode, Roo Code, Jules, Junie, any `AGENTS.md` reader | `… \| bash -s -- --host agents`   | `AGENTS.md`                       |
| Cursor                                                                    | `… \| bash -s -- --host cursor`   | `.cursor/rules/nonna.mdc`         |
| GitHub Copilot                                                            | `… \| bash -s -- --host copilot`  | `.github/copilot-instructions.md` |
| Gemini CLI                                                                | `… \| bash -s -- --host gemini`   | `GEMINI.md`                       |
| Windsurf                                                                  | `… \| bash -s -- --host windsurf` | `.windsurf/rules/nonna.md`        |
| Cline                                                                     | `… \| bash -s -- --host cline`    | `.clinerules/nonna.md`            |
| Kiro                                                                      | `… \| bash -s -- --host kiro`     | `.kiro/steering/nonna.md`         |
| All of them                                                               | `… \| bash -s -- --host all`      | all of the above                  |

Every host gets the same thing:

- **The house rules**, generated by `hosts/build.py` from `.claude/rules/00-core.md` (full) or
  `.claude/hooks/lib/lite.md` (lite). Full also brings the whole `.claude/rules/` for depth.
- **Git hooks that enforce them for any agent**: `pre-commit` refuses a commit on `main`, `master` or
  `develop`, a staged secret file, and a staged credential; `pre-push` refuses any secret and a red
  test suite, and in full mode a code push that leaves `docs/STATUS.md` stale. A repo born on `main`
  makes its very first commit with `git commit --no-verify`, then branches.
- In full mode, **a blank `docs/STATUS.md`** and, if it finds `pyproject.toml`, `package.json`,
  `go.mod` or `Cargo.toml`, that stack's test-gate permissions.

It never overwrites a file or a git hook that already exists, and never writes through a symlink; it
merges into an existing `.claude/` file by file and lists what it left alone. If a gate could not be
installed it says so and exits non-zero. If you use a hook manager (a custom `core.hooksPath`), it
tells you which scripts to point it at. Pin a release with `curl … | NONNA_REF=<tag> bash`. Prefer to
read before you pipe? `curl -fsSLO …/install.sh`, read it, then `bash install.sh`.

Claude Code gets more than the other hosts: the tool-level hooks (a write is scanned before it
lands, a turn cannot end on a red suite, a reviewer's verdict is machine-checked), the agents, and
the fifteen workflows. On other hosts the rules and the git hooks do the work; the benchmark showed
the rules are what kept agents off `main` and away from secrets.

## After installing

1. Full mode: pick your language pack under [`stacks/`](../stacks/README.md), copy its
   `settings.local.json` and adapt `/test`'s commands to your stack.
2. Try `/plan`, `/tdd`, `/review`, `/ship`, or `/fix` for a trivial change (the fast lane's
   eligibility is decided by `check-trivial.sh`, not by prose).

Why the plugin and a copy-in install differ: [ADR 0006](adr/0006-distribute-as-plugin.md),
[ADR 0007](adr/0007-plugin-install-is-not-equivalent.md) and
[ADR 0011](adr/0011-lite-mode-and-plugin-defaults.md).
