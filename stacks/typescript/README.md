# Nonna Stack Pack — TypeScript

Toolchain: **eslint + prettier** (lint + format) · **tsc** (types) · **vitest + @vitest/coverage-v8** (tests + coverage) · **fast-check** (property tests).

---

## Formatter — prettier

```bash
prettier --write "$FILE"
```

Install:

```bash
npm install --save-dev prettier eslint
# or: pnpm add -D prettier eslint
```

Add a `.prettierrc` (or `prettier` key in `package.json`) for project-wide format settings.

---

## Gate commands

### 1. Lint

```bash
eslint .
```

Fails on any ESLint error (`--max-warnings 0` is recommended to treat warnings as errors too):

```bash
eslint . --max-warnings 0
```

Configure rules in `eslint.config.js` (flat config, ESLint v9+) or `.eslintrc.json`.

### 2. Type-check

```bash
npx tsc --noEmit
```

`--noEmit` runs the full type-checker without emitting output files. Use `"strict": true` in `tsconfig.json`. Fix all type errors before merge; never suppress with `@ts-ignore` without a documented reason.

### 3. Tests + coverage

```bash
npx vitest run --coverage
```

Configure coverage thresholds in `vitest.config.ts` so the run exits non-zero when coverage falls below the floor:

```ts
// vitest.config.ts
import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    coverage: {
      provider: "v8",
      reporter: ["text", "lcov"],
      thresholds: {
        lines: 80,
        branches: 80,
        functions: 80,
        statements: 80,
      },
    },
  },
});
```

Raise thresholds to 90–100 % for survival-critical modules (auth, money, persistence). Vitest exits with a non-zero code when any threshold is not met — CI fails automatically.

Install the coverage provider:

```bash
npm install --save-dev @vitest/coverage-v8
```

---

## Property tests — fast-check

```bash
npm install --save-dev fast-check
```

Use `fc.property` + `fc.assert` inside any Vitest `test()` block. fast-check integrates without any additional setup. Always set `numRuns` explicitly in CI-sensitive suites; use `fc.seed()` for deterministic replay.

**Template:** `.claude/skills/tdd-workflow/templates/typescript_vitest_fastcheck.test.ts`

---

## Wire `/test`

Copy this block into your `/test` gate (commands run in order; first non-zero exit stops the gate):

```
eslint . --max-warnings 0
npx tsc --noEmit
npx vitest run --coverage
```

The two `npx` steps ask before they run: the pack does not pre-approve npx, which fetches and runs a package that is not installed (see below). Once TypeScript and Vitest are in your `devDependencies`, approve those two commands yourself when Claude Code asks, or put them in `package.json`'s `test` script and run `npm test`, which is pre-approved.

---

## Pre-approved commands

`settings.local.json` lets exactly these run without a prompt: `npm test` (also with `--silent`, the command Nonna's test gate runs), `npm run test`, `pnpm test`, `vitest run`, `tsc --noEmit`, `eslint .` (also with `--max-warnings 0`), `prettier --check .` and `prettier --write .`. Only those exact commands: a runner's flags can run any program or write any file, so any other form of them asks first. (`npm test --node-options` runs any JavaScript.) `node`, `npx` and the other `npm` and `pnpm` commands are not on the list, because they run any code or install anything: `node -e` and `npm install` ask first, and so does `npx tsc --noEmit`, because npx fetches and runs a package that is not installed without asking when its input is not a terminal.

---

## Install all dev dependencies

```bash
npm install --save-dev eslint prettier typescript vitest @vitest/coverage-v8 fast-check
```
