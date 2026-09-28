# Contributing to Nonna

Nonna is a portable `.claude/` operating system for disciplined, test-driven, review-gated, safe
AI-assisted development — the backbone that keeps you upright. Contributions are welcome and held to
the same bar the harness enforces on everyone else.

## Philosophy

Three principles govern everything here:

1. **The LLM proposes; deterministic gates decide.** Agent output is a proposal; tests, types, linters,
   and human review are the deciders.
2. **Safety is lexicographically prior to speed.** A risk-reducing check is never traded for throughput.
3. **Context is a budget — spend it deliberately.** A tiny always-on core; depth on demand.

## Project layout

- **`.claude/`** — the harness: `rules/` (always-on policy), `agents/`, `skills/` (playbooks + workflows),
  `hooks/`, and `settings.json`. This is the product.
- **`docs/`** — `STATUS.md` (the living state), `INSTALL.md`, `OVERVIEW.md`, `benchmarks/`, and
  `adr/` (numbered decisions). `CHANGELOG.md` lives at the repo root.
- **`.github/`** — CI (`workflows/ci.yml`), `workflows/release.yml`, `scripts/` (release tooling),
  the PR template, and the issue templates (`ISSUE_TEMPLATE/`).

## How to add to the harness

Pick the smallest surface that fits. The default bias is **on-demand, not always-on**.

- **A rule** (`.claude/rules/*.md`) — only for guidance that is load-bearing on nearly every turn.
  Rules are always loaded, so they are paid for every turn: keep them **dense and short**, and resist
  growth. If it isn't needed almost always, it is not a rule.
- **A skill** (`.claude/skills/*`) — a procedure or body of knowledge loaded **only when invoked**. This
  is the default home for depth: workflows, checklists, domain method. Prefer a skill over enlarging a
  rule.
- **A workflow skill** (`.claude/skills/<name>/SKILL.md`) — an explicit action invoked by name
  (`/plan`, `/review`, `/ship`, …). Claude Code merged commands into skills, so these live under
  `skills/` too. If it has side effects, set `disable-model-invocation: true` so only a human can
  trigger it; the linter enforces that for the six that do.
- **An agent** (`.claude/agents/*.md`) — a delegated role with its own context window
  (`orchestrator`, `implementer`, `explorer`, …). Add one when work should fan out and return
  _conclusions, not raw context_ to the main session.

When in doubt, ship it as a skill. Growing the always-on rules is the expensive choice and
must be justified (see [ADR 0003](docs/adr/0003-progressive-disclosure-token-economy.md)).

## Style guide

Write like a senior staff engineer: terse, declarative, high signal. No marketing fluff, no emoji.
Markdown with an H1 title and a short intro line, `##` sections, **bold** key terms, tables and code
blocks where they earn their space. Wrap prose at ~100 columns.

Frontmatter shapes (validated in CI by `harness-lint`):

```yaml
# agent — .claude/agents/<name>.md
---
name: explorer
description: Read-only fan-out search; returns conclusions, not file dumps.
model: <model id>
---
```

```yaml
# workflow skill — .claude/skills/<name>/SKILL.md
---
name: <name>
description: One line on what it does and when to invoke it.
model: sonnet
disable-model-invocation: true # if it has side effects: human-triggered only
---
```

```yaml
# skill — .claude/skills/<name>/SKILL.md
---
name: tdd-workflow
description: When to use this skill and what it does.
---
```

## The dev loop & Definition of Done

Every change moves through the loop:

```
Research & Reuse → Plan → TDD (RED → GREEN → REFACTOR) → Implement → Review → Verify → Commit & PR → Sync
```

A unit of work is **done** only when the **five mirrors** agree:

1. **Issue tracker** — the issue is updated and linked.
2. **`docs/STATUS.md`** — reflects what changed and the current state.
3. **Git / PR** — branch and PR open, linked to the issue, targeting `develop`.
4. **The `.claude/` harness** — index/README updated if any agent, skill, or rule changed.
5. **Memory** — durable decisions captured (an ADR via `/adr` when a real decision was made).

`/sync` reconciles drift across the five mirrors. The pre-push hook `require-status-sync.sh` blocks code
pushes that leave `docs/STATUS.md` stale — keep it current.

## How to propose a change

- Branch from `develop`: `<type>/<id>-<slug>` where `<type>` is `feature | fix | chore | refactor`
  (e.g. `feature/42-explorer-budget`).
- **Conventional commits** (`feat:`, `fix:`, `docs:`, `refactor:`, `test:`, `chore:`).
- Open a PR **to `develop`** (never `main`), linked to its tracker issue. Fill in the PR template
  including the Definition-of-Done checklist.
- Address every review finding; CI (`shellcheck` + `harness-lint` + `tests/run.sh`) must be green.

Welcome aboard — bring rigor, keep it dense, and let the gates decide.
