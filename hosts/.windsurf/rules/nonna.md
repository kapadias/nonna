---
trigger: always_on
---

# Nonna — house rules for this repository

This repository runs Nonna. These are the non-negotiables. Each section links to the full rule in
`.claude/rules/`; read it before you act in that area. Git hooks refuse a commit on main, master or
develop, a secret in a commit or a push, and a push with a red test suite or a stale
docs/STATUS.md; `--no-verify` is not yours to use.

## The three principles

1. **The LLM proposes; deterministic gates decide.** An LLM may read, hypothesize, draft, and
   explain. Tests, types, linters, schema checks, and human review decide what merges or acts. Never
   act on free-text model output that touches production, money, user data, or an irreversible
   action without a gate between it and the consequence. → [boundaries.md](.claude/rules/boundaries.md)
2. **Safety is lexicographically prior to speed.** Risk-_reducing_ actions (revert, halt, roll back,
   narrow scope) may be automatic. Every risk-_increasing_ action passes a gate or a human. When the
   safety layer and the fast layer disagree, safety wins. → [safety.md](.claude/rules/safety.md)
3. **Context is a budget.** Keep the always-on surface tiny; load depth on demand; delegate fan-out
   reading to subagents and keep the conclusion, not the dump. Thrift never buys out a test, a
   review, a validation, or a gate. → [token-economy.md](.claude/rules/token-economy.md)

## The loop

```
Research & Reuse → Plan → TDD (RED → GREEN → REFACTOR) → Implement → Review → Verify → Commit & PR → Sync
```

Do not skip stages. One exception: a trivial, reversible fix may take the fast lane (`.claude/skills/fix/SKILL.md`) —
`check-trivial.sh` decides eligibility, never prose. → [dev-process.md](.claude/rules/dev-process.md)

## Before writing code

Understand the problem first — trace the real flow — then stop at the first rung that holds:

1. **YAGNI** — does it need to exist at all?
2. Already in this **codebase**? Reuse it.
3. The **stdlib** does it? Use it.
4. A **native** platform feature covers it? Use it.
5. An already-**installed** dependency solves it? Use it.
6. Can it be **one line**? One line.
7. Only then: the **minimum code** that works.

The ladder sizes the solution, never the loop. → [engineering.md](.claude/rules/engineering.md)

## Never

- Commit or push to `main`/`develop`, or force-push. (the git pre-commit hook refuses a commit on them.)
- Put a secret in code, logs, traces, or prompts. (the git pre-commit and pre-push hooks block it.)
- Mark work done — in a tracker, in `STATUS.md`, or in a PR — with failing tests.
- Ship production logic with no test that would have failed before it.
- Override a gate's verdict with your own judgment.

## A human approves

First promotion to production · anything that widens blast radius (raising a limit, broadening a
permission, deleting at scale) · overriding a safety gate · onboarding an external dependency with
access to data or money.

## Done means the mirrors agree

Tracker · `docs/STATUS.md` · docs/ADR · branch + PR · the `.claude/` index · memory. Merged code with
a drifted mirror is a silent lie about the state of the system. → [sync.md](.claude/rules/sync.md)

Branch `feature|fix|chore|refactor/<id>-<slug>` → PR to `develop` → PR to `main`. Conventional
commits, one logical change each. → [git-workflow.md](.claude/rules/git-workflow.md)
