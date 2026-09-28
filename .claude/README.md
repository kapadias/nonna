# Nonna's kitchen: the `.claude/` harness

The agentic developer harness for any repository. It encodes _how the work gets done_ so that
AI-assisted development stays disciplined, test-driven, review-gated, and safe — and the
discipline is **enforced by code, not prose**. Start with [`../CLAUDE.md`](../CLAUDE.md).

## Layout

- **`rules/`** — always-on operating discipline (dense and short; you pay for them every turn), and
  budgeted by `harness_lint.py`. Start at [`00-core.md`](rules/00-core.md) — the constitution: three
  principles, the loop, the decision ladder, the never-list, who must approve, and routing. It is also the **only** rule
  a full-mode plugin install receives (ADR-0007), so it is budgeted under 9,000 chars to ride `SessionStart`;
  lite carries [`hooks/lib/lite.md`](hooks/lib/lite.md) instead (ADR-0011).
  The rest elaborate it: [`boundaries.md`](rules/boundaries.md) (LLM proposes / gates decide),
  [`safety.md`](rules/safety.md) (blast radius & irreversible actions),
  [`token-economy.md`](rules/token-economy.md), [`dev-process.md`](rules/dev-process.md),
  [`testing.md`](rules/testing.md), [`engineering.md`](rules/engineering.md),
  [`git-workflow.md`](rules/git-workflow.md), [`sync.md`](rules/sync.md). Project rules override
  global `~/.claude/rules/`.
- **`agents/`** — 8 specialists. `orchestrator` (router), `planner` (read-only plan author),
  `implementer`, `test-engineer`, `code-reviewer` (read-only; emits a machine-checkable JSON verdict),
  `security-reviewer` (read-only; same verdict contract), `explorer` (read-only fan-out, token-saver),
  `debugger`. Each pins a model tier; the five that own a playbook **preload it** via `skills:`
  (`implementer` ← `lean`), so the depth arrives deterministically instead of by description-trigger.
- **`skills/`** — 28 entries, since Claude Code merged commands into skills. Two kinds:
  - **12 playbooks** — knowledge Claude loads when the trigger matches, most bundling runnable
    scripts/templates/references that load only when opened: `tdd-workflow`, `code-review`,
    `debugging`, `refactoring`, `api-design`, `security-review`, `migration-safety`, `observability`,
    `concurrency-performance`, `supply-chain`, `fast-lane` (bundles `check-trivial.sh`), `lean`
    (the decision ladder in depth; bundles `check-debt.sh`, the debt-marker gate and ledger).
  - **16 pipeline workflows** — `/plan`, `/tdd`, `/implement`, `/review`, `/audit`, `/test`,
    `/coverage`, `/debug`, `/fix`, `/ship`, `/release`, `/rollback`, `/sync`, `/adr`, `/intake`, and
    `/nonna`, the user's switch for her gates (status, setup, lite/full/off, test, uninstall; its
    scripts in `skills/nonna/scripts/`, ADR-0011 §12). `/review` bundles
    `review-lanes.sh`, which sizes the review (ADR-0009). Each declares its
    model tier; several use `!` bash injection / `@` refs to act on real repo state. The seven with
    side effects — `/ship`, `/release`, `/rollback`, `/adr`, `/sync`, `/intake`, `/nonna` — set
    **`disable-model-invocation: true`**: only a human can trigger them, and their descriptions stay
    out of context entirely. That is what makes "a human approves promotion to production"
    ([`rules/safety.md`](rules/safety.md)) a mechanism rather than a request; the linter asserts it.
- **`hooks/`** — the gates, now **blocking**. Each reads the mode first (`nonna_mode`: `off`, `lite`
  or `full`, ADR-0011) and `off` is silent, but for the branch guard, which still keeps her
  settings. `guard-branch.sh` (blocks commits/pushes to
  `main`/`master`/`develop`, `--all`/`--mirror`, force pushes in `+refspec` and flag form,
  `--no-verify` and hook-path overrides, and the agent's own changes to her settings or git hooks
  or runs of her `/nonna` scripts;
  it reads a command the way the shell will run it), `secret-scan.sh` (blocks writes that introduce
  a secret, and reads of secret files by Read, Grep or Bash, by any name that leads to one — parity
  with the Read deny list, linted), `format.sh` (post-edit auto-format),
  `require-status-sync.sh` (pre-push: the test suite, a strict secret scan — no fixture exemption at
  push time; use placeholder-classed values — and in full mode the Definition-of-Done),
  `pre-commit.sh` (git pre-commit: no commit on a protected branch, no staged secret),
  `session-start.sh` (installs both git hooks — through the plugin's data directory under a plugin
  install, so they survive updates; warns instead of overwriting a foreign one — records the plugin's
  test command and mode in git config, carries the mode's rules into plugin installs, and tells the
  user once what it did), `stop-dod.sh` (**Stop** — code changed since the session began: runs the
  suite, asks "where's the test?", and in full mode blocks on a stale `docs/STATUS.md`),
  `subagent-verdict.sh` (**SubagentStop** — runs `check-review.sh` on the reviewer's own
  output, so ADR-0005 binds where the verdict is produced), `post-compact.sh` (**PostCompact** —
  restates branch, STATUS state, and review verdicts after a summary), `subagent-start.sh`
  (**SubagentStart** — carries the mode's rules into every subagent under a plugin install, where
  `SessionStart` context never reaches them; silent in a standalone checkout). Shared logic in
  `lib/` (`json.sh`, `secret-patterns.sh`, `core.sh` — harness root, the mode, the carrier, the
  context emitter; `shell-words.awk` — how the shell will read a command, for the branch guard;
  `expand.awk` — its brace lists and globs, as the shell expands them;
  `tests.sh` — the test command, runner and failure digest; `lite.md` — lite's house
  rules; `ladder.sh` — whether another plugin already states the ladder); plugin wiring in
  `hooks.json`, asserted equivalent to `settings.json` by the linter.
- **`settings.json`** — denies reading secrets (`.env`/`*.pem`/`*.key`/`.ssh`/`.aws`/…) and
  `git push --force`, which the hooks also refuse, because a plugin cannot carry this file; wires the
  hooks (PreToolUse, PostToolUse, SessionStart, SubagentStart, Stop, SubagentStop, PostCompact).
- **`.claude-plugin/`** — `plugin.json`, so Nonna installs as a Claude Code plugin.

Companion top-level surfaces: [`../docs/OVERVIEW.md`](../docs/OVERVIEW.md) (how the pieces
fit — token economy, crew, gates, layout), [`../tests/`](../tests/) (the harness's own gate golden tests +
self-validation — `bash tests/run.sh`), [`../stacks/`](../stacks/) (python/typescript/go/rust gate
packs), and [`../.claude-plugin/marketplace.json`](../.claude-plugin/marketplace.json) (plugin
distribution).

## How the pieces fit

```
rules/00-core.md     →  constitution (also the plugin carrier — ADR-0007)
CLAUDE.md + rules/   →  always-on    (tiny, dense, paid every turn; lint-budgeted)
skills/              →  on-demand    (playbooks load on trigger; workflows on /name)
agents/              →  delegation   (spend a subagent's context, keep the conclusion)
hooks/               →  enforcement  (deterministic gates that BLOCK around edits, turns, and pushes)
```

This is the token economy in one picture: keep the always-on surface small, push depth into surfaces
that load only when needed, and delegate fan-out so the main thread keeps conclusions, not file dumps.

## Enforcement (gates, not suggestions)

- **Branch safety:** `guard-branch.sh` **blocks** `git commit`/`git push` to `main`/`master`/`develop`
  (warns on edits there). It tolerates `git -C`/`--git-dir`/path-prefixed git and blocks
  `push --all/--mirror`, force pushes and `--no-verify`.
- **Secrets:** `secret-scan.sh` **blocks** any edit/write introducing a high-confidence secret, and
  reads/copies of secret files (Read, Grep, or `cat .env`); it fails closed when `jq` is absent. The
  pre-push hook re-scans the pushed range with no fixture exemption.
- **Tests:** `stop-dod.sh` runs the suite when a turn changed code and sends the agent back once on
  red; the git `pre-push` hook runs it again.
- **Definition of Done (full mode):** `require-status-sync.sh` blocks a code push that skips
  `docs/STATUS.md`, in a repo that keeps one. It is **auto-installed** as the git `pre-push` hook at
  `SessionStart` — no manual symlink. Run `/sync` to reconcile drift across the five mirrors.
- **Formatting** is automatic on edit (`format.sh`).
- **The harness tests its own gates:** `bash tests/run.sh` (golden tests proving each gate blocks vs.
  allows) and `python3 tests/harness_lint.py` (structural self-validation) run in CI.

## Local overrides

Create `.claude/settings.local.json` (git-ignored) to pre-approve routine commands (your test runner,
linter, `git`) and reduce permission prompts. The [`../stacks/`](../stacks/) packs ship ready-made
`settings.local.json` allow-lists per language.

## Adapting Nonna to your project

Nonna is language-agnostic. To make it yours: copy a [`../stacks/`](../stacks/) pack (or set your
test/lint commands in [`skills/test/SKILL.md`](skills/test/SKILL.md) and [`skills/ship/SKILL.md`](skills/ship/SKILL.md)),
set your tracker's issue prefix in [`rules/git-workflow.md`](rules/git-workflow.md), and point your
formatter in [`hooks/format.sh`](hooks/format.sh). Everything else is principle, not tooling.
