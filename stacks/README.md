# Nonna Stack Packs

Nonna's `/test` skill and `format.sh` hook are deliberately language-agnostic. Stack packs wire them to a concrete toolchain in three steps.

## What is a stack pack?

A stack pack is a per-language directory containing:

- **`README.md`** — exact commands for lint, type-check, test, and coverage; how to invoke the formatter from `format.sh`; a property-testing library recommendation; and a copy-pasteable gate command block.
- **`settings.local.json`** — a Claude Code local-settings file that pre-approves the exact commands the stack's gate runs (its test, lint, format and type-check commands), and only those, so they run without permission prompts. Never a prefix: a runner's flags can run any program or write any file (`go test -exec`, `npm test --node-options`, cargo's `--config`), so any other form of the command asks. It never lists an interpreter, a package manager or `awk`.

## The 3-step wire-up

### Step 1 — Pick your stack

Choose the sub-directory matching your language:

```
stacks/python/
stacks/typescript/
stacks/go/
stacks/rust/
```

### Step 2 — Copy the allow-list into your project

Copy `stacks/<lang>/settings.local.json` to the root of your project as `.claude/settings.local.json` (create the `.claude/` directory if it does not exist). This pre-approves the gate commands so Nonna can run them non-interactively.

```bash
mkdir -p .claude
cp /path/to/nonna/stacks/<lang>/settings.local.json .claude/settings.local.json
```

If you already have a `.claude/settings.local.json`, merge the `permissions.allow` array entries into it.

The file is yours alone: committed, its pre-approvals reach everyone who clones the repository.
`install.sh` writes it, lists what it pre-approves and adds `.claude/settings.local.json` to your
`.gitignore`; by hand, add that line yourself.

A runner still runs your project's own code (tests, `conftest.py`, build scripts), so the pack narrows
what runs without asking; it is not a sandbox. Each stack's README lists what it pre-approves and what
still asks.

### Step 3 — Set your `/test` gate commands

Open `.claude/skills/test/SKILL.md` (or the equivalent in your project's harness copy) and set the gate commands to the ones listed in the stack's `README.md` under **Wire `/test`**. The commands run in order; the gate fails on the first non-zero exit.

### Formatter (optional but recommended)

`format.sh` already handles Python, JS/TS, Go and Rust out of the box. The PostToolUse hook
(`format.sh`) invokes it automatically after edits; if the file's formatter is absent on `PATH` the
hook is a no-op.

---

See `.claude/skills/tdd-workflow/templates/` for matching test-file templates (pytest+hypothesis, vitest+fast-check, go testing/quick).
