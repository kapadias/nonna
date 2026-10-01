---
name: coverage
description: Report line and branch coverage; spotlight survival-critical surface gaps; fail if below the project floor. Extracted from /test for focused coverage work.
argument-hint: "[optional: path or module to focus on; defaults to whole project]"
model: sonnet
---

!ls package.json pyproject.toml go.mod Cargo.toml Makefile 2>/dev/null

Coverage report for: **$ARGUMENTS** (if empty, the whole project).

## Steps

1. **Detect the toolchain** from the manifest files listed above and run coverage with the appropriate command:
   - JS/TS: `npm test -- --coverage` or `vitest run --coverage`
   - Python: `pytest --cov --cov-branch --cov-report=term-missing $ARGUMENTS`
   - Go: `go test ./... -coverprofile=coverage.out && go tool cover -func=coverage.out`
   - Rust: `cargo tarpaulin --out Stdout` (or `cargo llvm-cov`)
   - Or `make coverage` / the repo's documented command.
2. **Report the numbers.** Line coverage % and branch coverage % for the scope requested. Compare against the project's declared floor (check `pyproject.toml`, `jest.config.*`, `.nycrc`, `Makefile`, or CI config). **Fail loudly if below the floor** — do not soften the number.
3. **Spotlight the survival-critical surface.** Scan for any code touching **money, auth, data integrity, persistence, or irreversible/outward-facing actions** (see [`.claude/rules/testing.md`](../../rules/testing.md)). For each such file or module, report:
   - Current line % and branch %
   - Whether a **golden test** (exact oracle) exists
   - Whether a **property test** (invariant over generated inputs) exists
   - Gap: what behavior is uncovered
4. **List the top gaps.** Rank uncovered lines/branches by blast radius — survival-critical surface first, then the rest. Give file paths and line ranges, not just percentages.

## Guardrails

- Do not mutate any files. This command observes and reports; it does not fix. To add tests, run `/tdd`.
- Never report a number you did not observe from actual tool output.

## Output

Overall line % and branch % vs. floor (pass/fail). Survival-critical surface table (file, line %, branch %, golden?, property?). Top-N uncovered spans by blast radius. Next action: either green (no gaps on critical surface, above floor) or a prioritized list for `/tdd`.
