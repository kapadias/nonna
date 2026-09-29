# How Nonna's kitchen works

The detail behind the [README](../README.md): the modes, the token economy, the layers, the crew,
the gates, and the repository layout. The harness itself is indexed in
[`.claude/README.md`](../.claude/README.md).

## Modes

One switch per repository: `/nonna off`, `/nonna lite` or `/nonna full`, or `git config nonna.mode`
([configuration](INSTALL.md#configuration)).

| Mode             | What it carries                                                                                                                                                                                                                          |
| ---------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `off`            | Nothing. No gate runs and nothing is said, git hooks included. The branch guard still refuses an agent that changes her settings.                                                                                                        |
| `lite` (default) | The test gate and "where's the test?" before a turn can end, the branch and secret guards, the git `pre-commit` and `pre-push` hooks, and six house rules ([`lite.md`](../.claude/hooks/lib/lite.md)) in the session and every subagent. |
| `full`           | Lite's gates, plus the `docs/STATUS.md` gate where the file exists, and the constitution in place of the house rules: [`00-core.md`](../.claude/rules/00-core.md) under the plugin, all nine rules and `CLAUDE.md` in a copy-in install. |

Under the plugin, her agents and workflows are there in both modes, and lite tells the agent to run
them only when you ask; a copy-in install brings them with full mode only. In round 3 of the
benchmark, full mode was no safer than lite (0 of 64 trap runs cut a corner, against lite's 1 of 64),
so its extras are for teams, not for safety ([results](../bench/README.md)).

## The token economy

Most "AI dev setups" fail the same way: they stuff every instruction into one always-on file. Every
token in that file is re-read on **every** turn, the window fills, and the agent gets duller as the
task gets longer. Nonna is built the other way, with **progressive disclosure**: a small always-on
surface, and everything else loaded on demand.

| Always-on (paid every turn)                                                                                                                       | Size                         | Budget, enforced by `tests/harness_lint.py` |
| ------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------- | ------------------------------------------- |
| **Lite**: the six house rules ([`lite.md`](../.claude/hooks/lib/lite.md)), carried in by `SessionStart` and into each subagent by `SubagentStart` | 139 words                    | 150 words                                   |
| **Full, copy-in**: `CLAUDE.md` + the 9 rules, which Claude Code loads itself                                                                      | 3,681 words                  | 3,700 words                                 |
| **Full, plugin**: the constitution ([`00-core.md`](../.claude/rules/00-core.md)) alone, carried in the same way as lite's rules                   | 520 words (3,440 characters) | 520 words; 9,000 characters                 |
| **Descriptions**: the name and description of each skill and agent the model can call; under the plugin in both modes, and in a full copy-in      | 4,684 characters             | 5,600 characters                            |

Each session also starts with a short note on which gates are live and what the test gate runs. So
lite's always-on surface is the house rules and that note, plus the descriptions under the plugin; a
lite copy-in has no agents and no workflow the model can call. Words are counted as the lint counts
them, split on whitespace. `claude plugin details nonna@nonna` (Claude Code 2.1.284, a fresh config
and this repository as a local marketplace) puts the plugin's descriptions at about 2,300 tokens; it
also counts the seven user-only workflows, and it counts hooks as free, so the rules `SessionStart`
carries come on top.

On demand, paid only when needed: the bodies of 12 skill playbooks, 16 workflows and 8 agents, loaded
when a trigger matches, a workflow runs, or a subagent is dispatched.

The seven side-effecting workflows (`/ship`, `/release`, `/rollback`, `/adr`, `/sync`, `/intake`,
`/nonna`) carry `disable-model-invocation: true`: Claude cannot invoke them at all, and the lint does
not count their descriptions, since the model is never offered them. Only you can run them.

## What's inside

| Layer                  | Loaded                        | Purpose                                                                                                                       |
| ---------------------- | ----------------------------- | ----------------------------------------------------------------------------------------------------------------------------- |
| `CLAUDE.md` + `rules/` | **Always**, in a full copy-in | The dense, short policy the agent obeys every turn. Under the plugin, full mode carries `00-core.md` alone.                   |
| `hooks/lib/lite.md`    | **Always**, in lite           | Six house rules, carried in by the hooks.                                                                                     |
| `skills/`              | **On demand**                 | Playbooks that cost nothing until triggered, plus the `/name` pipeline workflows.                                             |
| `agents/`              | **On delegate**               | Specialists that spend _their own_ context and return conclusions.                                                            |
| `hooks/`               | **On event**                  | Deterministic enforcement on session start, edit, read, Bash, turn end, subagent start and stop, compaction, commit and push. |

## The crew

Eight specialist agents, each model-tiered so you never burn a frontier model on mechanical work.

| Agent               | Model  | Role                                                                                                                                           |
| ------------------- | ------ | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| `orchestrator`      | Opus   | Router. Decomposes a request and sequences the loop. Read-only; it plans and delegates.                                                        |
| `planner`           | Opus   | Read-only. Turns a request into a written plan: risks, decomposition, a gate per step.                                                         |
| `implementer`       | Sonnet | Builds features to make failing tests pass. The bulk of engineering.                                                                           |
| `test-engineer`     | Sonnet | Writes the failing tests that pin behavior, plus golden and property tests.                                                                    |
| `code-reviewer`     | Opus   | Independent, read-only correctness review; emits a machine-checkable JSON verdict. On a light-lane diff `/review` and `/fix` run it on Sonnet. |
| `security-reviewer` | Opus   | Read-only security review: injection, secrets, authz, supply chain.                                                                            |
| `explorer`          | Haiku  | Read-only fan-out search. Returns conclusions, not file dumps. The token-saver.                                                                |
| `debugger`          | Opus   | Reproduce, isolate, root-cause, and fix the cause, not the symptom.                                                                            |

**On-demand skills** deepen the agents when triggered, most bundling runnable scripts, templates or
references: `tdd-workflow`, `code-review`, `debugging`, `refactoring`, `api-design`,
`security-review`, `migration-safety`, `observability`, `concurrency-performance`, `supply-chain`,
`fast-lane`, `lean` (the decision ladder in depth, with `check-debt.sh`).

## Workflows

Fifteen workflows, invoked as `/<name>` (`/nonna:<name>` under the plugin), plus `/nonna`, the
switch for her gates ([INSTALL.md](INSTALL.md)). The six marked **human-only** cannot be triggered by
the model at all, and neither can `/nonna`. That is what makes "a human approves" a mechanism instead
of a request.

| Workflow                     | Does                                                                                  |
| ---------------------------- | ------------------------------------------------------------------------------------- |
| `/plan`                      | Restate the requirement, look for reuse, name the risks, split into reviewable steps. |
| `/tdd`                       | RED → GREEN → REFACTOR for one unit of behavior. The default way to build.            |
| `/implement`                 | Minimal, typed code against a failing test that already exists.                       |
| `/fix`                       | The quick lane for a small, reversible fix. `check-trivial.sh` decides who qualifies. |
| `/review`                    | Review sized by `review-lanes.sh`: one quick taste, the full review, plus security.   |
| `/audit`                     | Whole-repo sweep for over-building, ranked, plus the `debt:` ledger. Read-only.       |
| `/test`                      | Run your lint, type-check, test and coverage gate and summarize.                      |
| `/coverage`                  | Line and branch coverage, with the critical surface and its gaps up front.            |
| `/debug`                     | Reproduce, isolate, fix the cause, leave a regression test.                           |
| `/ship` **(human-only)**     | Full gate, conventional commit, push, PR to `develop` linked to the issue.            |
| `/release` **(human-only)**  | Promote `develop` to `main`: a human-gated release with tag and notes.                |
| `/rollback` **(human-only)** | Revert a bad change or roll back a deploy.                                            |
| `/sync` **(human-only)**     | Make every record of the system agree: tracker, docs, PR, harness index, memory.      |
| `/adr` **(human-only)**      | Write a numbered Architecture Decision Record with real alternatives.                 |
| `/intake` **(human-only)**   | Turn a raw idea or bug into a tidy, de-duplicated issue.                              |

Eight agents work in her kitchen: a planner, an implementer, a test engineer, two reviewers, an
explorer, a debugger and a router. Who runs on which model: see the crew above.

## Safety & enforcement

Hooks turn the rules into deterministic guards: gates, not suggestions. Each reads the mode first
(`off`, `lite` or `full`, [ADR 0011](adr/0011-lite-mode-and-plugin-defaults.md)). `off` enforces
nothing and says nothing, except that the branch guard still keeps her settings; only the STATUS
checks are full mode's.

- **`guard-branch.sh`** **blocks** `git commit` and `git push` on or to `main`, `master` or
  `develop` (and warns once on edits there), a push of every branch (`--all`, `--mirror`, `:`, a
  wildcard), force pushes, `--no-verify` and hook-path overrides, and the agent's changes to her own
  settings. It reads each command the way the shell will run it, brace lists and globs included. A
  speed bump for the agent; server-side branch protection is the wall.
- **`secret-scan.sh`** **blocks** an edit or write that introduces a high-confidence secret (AWS,
  GitHub, Slack, Google, Stripe, OpenAI and Anthropic keys, private-key blocks, hardcoded
  credentials; sample values under test, fixture and example paths pass), and reads and searches of
  secret files (Read, Grep, or `cat .env` in Bash). For Read and Grep it refuses every path the Read
  deny list refuses, by any name that leads to one.
- **`format.sh`** formats the file the agent just edited with the formatter it finds (ruff,
  prettier, gofmt, rustfmt, shfmt). Best effort, never blocking, and in a copy-in install only:
  the plugin never formats your files.
- **`session-start.sh`** (**SessionStart**) wires the git hooks, records the plugin's test command
  and mode, carries the mode's rules into the session, and tells you once what it did.
- **`require-status-sync.sh`**, the git `pre-push` hook (wired at `SessionStart` and by
  `install.sh`; a hook of yours is reported, never overwritten), blocks a push with a red suite or a
  new secret (no fixture exemption at push time), and in full mode a code push that skips
  `docs/STATUS.md`. **`pre-commit.sh`** refuses a commit on a protected branch or a staged secret.
- **`stop-dod.sh`** (**Stop**): when code changed since the session began, it runs the suite and
  sends the agent back once on red, asks once for a test when no test changed, and in full mode
  blocks on a stale `docs/STATUS.md`.
- **`subagent-verdict.sh`** (**SubagentStop**) runs `check-review.sh` on the reviewer's own output,
  so ADR-0005 binds where the verdict is produced.
- **`subagent-start.sh`** (**SubagentStart**) carries the mode's rules (`00-core.md`, or lite's house
  rules) into every subagent, where `SessionStart` context never reaches. It is silent when the
  repository has its own `.claude/rules/`, which load natively.
- **`post-compact.sh`** (**PostCompact**) restates the branch, `HEAD`, the STATUS state and the
  review verdicts after a summary.

Review is sized by script, not by the model (ADR-0009). `review-lanes.sh` answers two questions for
`/review`: is the diff small enough for one reviewer on the cheaper tier (the same classifier as the
fast lane), and does any changed path, or any added or removed line, touch a risky surface (auth,
secrets, money, migrations, deploy, CI, dependencies, shell, SQL, deserialization, network, env,
crypto, or `NONNA_CRITICAL_PATHS`)? The second answer adds the security reviewer. Any doubt answers
"full review, with security".

A copy-in install's `settings.json` denies reading project paths (`./**/.env`, `./**/secrets/**`,
`./**/*.pem`, `./**/*.key`, `./**/.ssh/**`, `./**/.aws/**`, and more) and denies `git push --force`;
a plugin cannot carry it, and the hooks refuse the same things. The Bash branch of `secret-scan.sh`
also catches Bash reads of `~/.ssh`-style paths outside the project root. The harness **tests its
own gates**: `bash tests/run.sh` runs golden tests proving each one blocks and allows as it should,
and CI fails if any gate regresses.

See [`SECURITY.md`](../SECURITY.md) for how to report a vulnerability privately.

## Repository structure

```
nonna/
├── CLAUDE.md                  # always-on root guidance
├── README.md
├── LICENSE                    # MIT
├── CONTRIBUTING.md            # how to extend the harness, or add an agent host
├── CODE_OF_CONDUCT.md
├── SECURITY.md                # how to report a vulnerability
├── CHANGELOG.md               # release history
├── install.sh                 # the copy-in install, for any agent host
├── .claude/
│   ├── README.md              # harness index
│   ├── settings.json          # secret-deny + hook wiring
│   ├── .claude-plugin/        # plugin manifest (plugin.json)
│   ├── rules/                 # 9 always-on rules (00-core is the constitution)
│   ├── agents/                # 8 specialists
│   ├── skills/                # 12 playbooks + 16 workflows (7 human-only, /nonna among them)
│   └── hooks/                 # 10 hooks: 8 on 7 Claude Code events + the git pre-commit and pre-push
├── hosts/                     # other agents' rules files, generated by hosts/build.py (lite ones in lite/)
├── tests/                     # gate golden tests + harness self-validation
├── stacks/                    # python · typescript · go · rust gate packs
├── bench/                     # the benchmark: tasks, hidden checks, runner, results
├── examples/                  # one run of each trap task, word for word
├── docs/
│   ├── STATUS.md              # the living state mirror
│   ├── INSTALL.md             # the plugin, install.sh, configuration, uninstall
│   ├── OVERVIEW.md            # this file
│   ├── benchmarks/            # earlier dated benchmark runs and writeups
│   └── adr/                   # Architecture Decision Records
├── .claude-plugin/            # marketplace.json (plugin distribution)
├── assets/                    # the banner, the scorecard, the launch images (build.py), the demo
└── .github/                   # CI, release workflow, release scripts, PR and issue templates
```
