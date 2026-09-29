# Nonna Stack Pack — Python

Toolchain: **ruff** (lint + format) · **mypy** or **pyright** (types) · **pytest + pytest-cov** (tests + coverage) · **hypothesis** (property tests).

---

## Formatter — ruff format

```bash
ruff format "$FILE"
```

Install:

```bash
pip install ruff
# or: uv add --dev ruff
```

`ruff format` replaces black and is the canonical formatter for this stack. To also auto-fix lint violations on save, add `ruff check --fix "$FILE"` after the format line.

---

## Gate commands

### 1. Lint

```bash
ruff check .
```

Fails on any lint violation. Configure rules in `pyproject.toml` under `[tool.ruff.lint]`.

### 2. Type-check

```bash
mypy src/
# or, if using pyright:
pyright
```

Use the strictest settings your codebase can sustain. Recommended `pyproject.toml` snippet:

```toml
[tool.mypy]
strict = true
```

### 3. Tests + coverage

```bash
pytest --cov=src --cov-branch --cov-report=term-missing --cov-fail-under=80
```

- `--cov-branch` enables branch coverage (required by Nonna's testing rules).
- `--cov-fail-under=80` makes the test run exit non-zero when coverage falls below 80 %. Set this floor in `pyproject.toml` so it applies in CI automatically:

```toml
[tool.pytest.ini_options]
addopts = "--cov=src --cov-branch --cov-report=term-missing --cov-fail-under=80"
```

Adjust the floor upward on survival-critical modules (auth, money, persistence) — aim for 90–100 % on those paths.

**CI enforcement:** pytest exits with code 2 when the floor is not met; any CI runner that checks exit codes will fail the build automatically. No extra CI step is needed.

---

## Property tests — hypothesis

```bash
pip install hypothesis
# or: uv add --dev hypothesis
```

Hypothesis integrates with pytest natively. Use `@given` + `@settings` for deterministic replay (always set `deriving=True` or pin the database). On the survival-critical surface (money, auth, data integrity), pair every golden test with a property test.

**Template:** `.claude/skills/tdd-workflow/templates/python_pytest_hypothesis.py`

---

## Wire `/test`

Copy this block into your `/test` gate (commands run in order; first non-zero exit stops the gate):

```
ruff check .
mypy src/
pytest --cov=src --cov-branch --cov-report=term-missing --cov-fail-under=80
```

---

## Pre-approved commands

`settings.local.json` lets `pytest`, `python -m pytest`, `python3 -m pytest`, `ruff`, `mypy` and `pyright` run without a prompt. `python`, `pip` and `uv` are not on the list, because they run any code or install anything: `python -c`, `pip install` and `uv add` ask first.

---

## Install all dev dependencies

```bash
pip install ruff mypy pytest pytest-cov hypothesis
# or with uv:
uv add --dev ruff mypy pytest pytest-cov hypothesis
```
