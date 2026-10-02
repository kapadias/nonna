---
name: test
description: Run the project's test gate — lint, type-check, tests, and coverage — then summarize failures and coverage gaps. Adapt the commands to your stack.
argument-hint: "[optional: a subset/path to test; defaults to the whole suite]"
model: sonnet
---

!ls package.json pyproject.toml go.mod Cargo.toml Makefile 2>/dev/null

Run the gate for: **$ARGUMENTS** (if empty, the whole suite).

## Steps

1. **Detect the toolchain** from the repo (e.g. `package.json`, `pyproject.toml`, `Cargo.toml`,
   `go.mod`, `Makefile`) and run the project's gate. Typical shapes — use the one that fits:
   - JS/TS: `npm run lint && npm run typecheck && npm test -- --coverage`
   - Python: `ruff check && mypy . && pytest --cov`
   - Go: `golangci-lint run && go test ./... -cover`
   - Rust: `cargo clippy && cargo test`
   - Or `make test` / the repo's documented command.
2. **Run it** and capture real output. Do not infer pass/fail — observe it.
3. **Summarize failures** precisely: the failing test, the assertion, and the likely cause. Hand hard
   failures to `/debug`.
4. **Report coverage** against the project's floor. Hold the **highest bar on the survival-critical
   surface** (money, auth, data, persistence, irreversible actions) — flag any such code lacking golden
   or property tests (see [`.claude/rules/testing.md`](../../rules/testing.md)).

## Guardrails

- **Never report green you did not observe.** If tests failed, say so with the output. If a step was
  skipped, say that.
- Do not mark any task done with failing tests (see [`.claude/rules/sync.md`](../../rules/sync.md)).

## Output

Pass/fail per stage, the failing-test summary, the coverage number vs. floor, and the next action.
