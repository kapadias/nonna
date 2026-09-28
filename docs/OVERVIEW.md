# How Nonna's kitchen works

The detail behind the [README](../README.md): the token economy, the layers, the crew, the gates,
and the repository layout. The harness itself is indexed in [`.claude/README.md`](../.claude/README.md).

## The token economy

Most "AI dev setups" fail the same way: they stuff every instruction into one always-on file. Every
token in that file is re-read on **every** turn, the window fills, and the agent gets duller as the
task gets longer. Nonna is built the other way — **progressive disclosure**:

|                 | Always-on (paid every turn)                                                                                                                             | On-demand (paid only when needed)                                         |
| --------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------- |
| **What**        | `CLAUDE.md` + 9 rules, plus the name+description of each skill, agent and workflow                                                                      | 12 skill playbooks + 15 pipeline workflows + 8 agents — bodies only       |
| **Footprint**   | **~7.1k tokens** — 3,681 words of prose (3,700-word budget) + 5,570 chars of descriptions (5,600-char budget), both enforced by `tests/harness_lint.py` | the bulk of Nonna — loaded only when relevant                             |
| **When loaded** | Every request                                                                                                                                           | Only when a trigger matches, a workflow runs, or a subagent is dispatched |

The six side-effecting workflows (`/ship`, `/release`, `/rollback`, `/adr`, `/sync`, `/intake`) carry
`disable-model-invocation: true`, so they cost **zero** always-on tokens — and Claude cannot invoke
them at all. Only you can.

## What's inside

| Layer                  | Loaded          | Purpose                                                                                       |
| ---------------------- | --------------- | --------------------------------------------------------------------------------------------- |
| `CLAUDE.md` + `rules/` | **Always**      | The dense, short policy the agent obeys every turn.                                           |
| `skills/`              | **On demand**   | Playbooks that cost nothing until triggered, plus the `/name` pipeline workflows.             |
| `agents/`              | **On delegate** | Specialists that spend _their own_ context and return conclusions.                            |
| `hooks/`               | **On event**    | Deterministic enforcement on edit, Bash, turn end, subagent start/stop, compaction, and push. |

## The crew

Eight specialist agents, each model-tiered so you never burn a frontier model on mechanical work.

| Agent               | Model  | Role                                                                                                                                           |
| ------------------- | ------ | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| `orchestrator`      | Opus   | Router. Decomposes a request and sequences the loop. Read-only; it plans and delegates.                                                        |
| `planner`           | Opus   | Read-only. Turns a request into a written plan — risks, decomposition, a gate per step.                                                        |
| `implementer`       | Sonnet | Builds features to make failing tests pass. The bulk of engineering.                                                                           |
| `test-engineer`     | Sonnet | Writes the failing tests that pin behavior, plus golden and property tests.                                                                    |
| `code-reviewer`     | Opus   | Independent, read-only correctness review; emits a machine-checkable JSON verdict. On a light-lane diff `/review` and `/fix` run it on Sonnet. |
| `security-reviewer` | Opus   | Read-only security review — injection, secrets, authz, supply chain.                                                                           |
| `explorer`          | Haiku  | Read-only fan-out search. Returns conclusions, not file dumps. The token-saver.                                                                |
| `debugger`          | Opus   | Reproduce, isolate, root-cause, and fix — the cause, not the symptom.                                                                          |

**On-demand skills** deepen the agents when triggered — most bundling runnable scripts/templates/
references: `tdd-workflow`, `code-review`, `debugging`, `refactoring`, `api-design`, `security-review`,
`migration-safety`, `observability`, `concurrency-performance`, `supply-chain`, `fast-lane`, `lean`
(the decision ladder in depth, with `check-debt.sh`).

## Workflows

Fifteen workflows, invoked as `/<name>`. The six marked **human-only** cannot be triggered by the
model at all. That is what makes "a human approves" a mechanism instead of a request.

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

Hooks turn the rules into deterministic guards — gates, not suggestions. Each reads the mode first
(`off`, `lite` or `full`, [ADR 0011](adr/0011-lite-mode-and-plugin-defaults.md)); `off` is silent,
and only the STATUS checks are full mode's:

- **`guard-branch.sh`** — **blocks** `git commit` / `git push` to `main` / `master` / `develop` (warns
  on edits there), plus a push of every branch (`--all`, `--mirror`, `:`, a wildcard), force pushes,
  `--no-verify` and hook-path overrides, reading each command the way the shell will run it, brace
  lists and globs included. A speed bump for the agent; server-side branch protection is the wall.
  The "never commit to a protected branch" rule, actually enforced.
- **`secret-scan.sh`** — **blocks** any edit/write that introduces a high-confidence secret (AWS /
  GitHub / Slack / Google keys, private-key blocks, hardcoded credentials), and reads/copies of
  secret files (Read, Grep, or `cat .env`), by any name that leads to one — parity with the Read
  deny list.
- **`format.sh`** — auto-formats the file you just touched (ruff / prettier / gofmt / rustfmt —
  best-effort, never blocking).
- **`require-status-sync.sh`** (pre-push, **auto-installed at `SessionStart`** — warns instead of
  overwriting a foreign pre-push hook) — blocks a push with a red suite or a new secret (no fixture
  exemption at push time), and in full mode a code push that skips `docs/STATUS.md`. The Definition
  of Done, enforced. **`pre-commit.sh`** refuses a commit on a protected branch or a staged secret.
- **`stop-dod.sh`** (**Stop**) — when code changed since the session began: runs the suite and sends
  the agent back once on red, asks once for a test when no test changed, and in full mode blocks on a
  stale `docs/STATUS.md`.
- **`subagent-verdict.sh`** (**SubagentStop**) — runs `check-review.sh` on the reviewer's own output,
  so ADR-0005 binds where the verdict is produced.
- **`subagent-start.sh`** (**SubagentStart**) — carries the mode's rules (`00-core.md`, or lite's
  house rules) into every subagent under a plugin install, where `SessionStart` context never
  reaches them; silent in a standalone checkout.
- **`post-compact.sh`** (**PostCompact**) — restates branch, STATUS state, and review verdicts after
  a summary.

Review is sized by script, not by the model (ADR-0009). `review-lanes.sh` answers two questions for
`/review`: is the diff small enough for one reviewer on the cheaper tier (the same classifier as the
fast lane), and does any changed path or added line touch a risky surface (auth, secrets, money,
migrations, deploy, shell, SQL, deserialization, network, env, or `NONNA_CRITICAL_PATHS`)? The
second answer adds the security reviewer. Any doubt answers "full review, with security".

`settings.json` denies reading project paths — `./**/.env`, `./**/secrets/**`, `./**/*.pem`,
`./**/*.key`, `./**/.ssh/**`, `./**/.aws/**`, and more — and denies `git push --force`; the Bash
branch of `secret-scan.sh` catches Bash reads of `~/.ssh`-style paths outside the project root. The
harness even **tests its own gates**: `bash tests/run.sh` runs golden tests proving each one blocks
vs. allows, and CI fails if any gate regresses.

See [`SECURITY.md`](../SECURITY.md) for how to report a vulnerability privately.

## Repository structure

```
nonna/
├── CLAUDE.md                  # always-on root guidance (read first)
├── README.md
├── LICENSE                    # MIT
├── CONTRIBUTING.md            # how to extend the harness
├── SECURITY.md                # how to report a vulnerability
├── CHANGELOG.md               # release history
├── .claude/
│   ├── README.md              # harness index
│   ├── settings.json          # secret-deny + hook wiring
│   ├── .claude-plugin/        # plugin manifest (plugin.json)
│   ├── rules/                 # 9 always-on rules (00-core is the constitution)
│   ├── agents/                # 8 specialists
│   ├── skills/                # 12 playbooks + 16 pipeline workflows (7 human-only)
│   └── hooks/                 # 9 hooks: 8 on 7 Claude Code events + the git pre-push hook
├── tests/                     # gate golden tests + harness self-validation
├── stacks/                    # python · typescript · go · rust gate packs
├── docs/
│   ├── STATUS.md              # the living state mirror
│   ├── INSTALL.md             # copy-in vs. plugin, and their gaps
│   ├── OVERVIEW.md            # this file
│   ├── benchmarks/            # dated benchmark runs and writeups
│   └── adr/                   # Architecture Decision Records
├── .claude-plugin/            # marketplace.json (plugin distribution)
├── assets/                    # the banner and the benchmark chart
└── .github/                   # CI, release workflow, release scripts, PR template
```
