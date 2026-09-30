# Nonna Stack Pack — Rust

Toolchain: **rustfmt** (format) · **clippy** (lint) · **cargo test** (tests) · **cargo-llvm-cov** or **cargo-tarpaulin** (coverage) · **proptest** (property tests).

---

## Formatter — rustfmt

```bash
rustfmt "$FILE"
```

`rustfmt` ships with the Rust toolchain via `rustup`. Ensure the `rustfmt` component is installed:

```bash
rustup component add rustfmt
```

Configure style in `rustfmt.toml` at the project root.

---

## Gate commands

### 1. Lint — clippy

```bash
cargo clippy --all-targets --all-features -- -D warnings
```

- `--all-targets` includes tests, examples, and benchmarks.
- `--all-features` catches issues gated behind feature flags.
- `-D warnings` promotes all clippy warnings to errors — the gate fails on any warning.

Install clippy (ships with rustup):

```bash
rustup component add clippy
```

Configure allowed/denied lints in `[lints.clippy]` in `Cargo.toml`.

### 2. Type-check (fast, no link)

```bash
cargo check --all-targets --all-features
```

`cargo check` is faster than a full build and catches all type errors. Run it before the full test suite to fail fast.

### 3. Tests + coverage

**Option A — cargo-llvm-cov (recommended, LLVM-based, accurate branch coverage):**

```bash
cargo llvm-cov --all-features --branch --fail-under-lines 80
```

Install:

```bash
cargo install cargo-llvm-cov
rustup component add llvm-tools-preview
```

- `--branch` enables branch coverage.
- `--fail-under-lines 80` exits non-zero when line coverage falls below 80 %. Adjust per module — raise to 90–100 % for auth, money, persistence, and any `unsafe` block.

**Option B — cargo-tarpaulin (alternative, simpler setup):**

```bash
cargo tarpaulin --all-features --fail-under 80
```

Install:

```bash
cargo install cargo-tarpaulin
```

**CI enforcement:** both tools exit non-zero when the floor is not met; the build fails automatically.

---

## Property tests — proptest

```toml
# Cargo.toml
[dev-dependencies]
proptest = "1"
```

Use `proptest!` macros or the `Strategy` API. proptest shrinks counterexamples automatically; always add a `#[test]` attribute so `cargo test` picks it up. For deterministic replay, set `PROPTEST_SEED` in the environment.

On the survival-critical surface (money, auth, data integrity, `unsafe` code), pair every golden test with a property test.

---

## Wire `/test`

Copy this block into your `/test` gate (commands run in order; first non-zero exit stops the gate):

```
cargo check --all-targets --all-features
cargo clippy --all-targets --all-features -- -D warnings
cargo llvm-cov --all-features --branch --fail-under-lines 80
```

If using tarpaulin instead of llvm-cov, replace the last line with:

```
cargo tarpaulin --all-features --fail-under 80
```

---

## Pre-approved commands

`settings.local.json` lets exactly these run without a prompt: `cargo test` (also with `--quiet`, the command Nonna's test gate runs), `cargo check` and `cargo clippy`, bare or as the gate above runs them, and `cargo fmt` (also with `--check`). Only those exact commands: a runner's flags can run any program or write any file, so any other form of them asks first. (Cargo's `--config` can set a test runner or a compiler wrapper.) The other `cargo` commands (`cargo run`, `cargo install`, `cargo llvm-cov`), `rustfmt` on a path and `rustup` are not on the list, so the coverage line of the gate above asks first, and so do the install commands below.

---

## Install all dev dependencies

```bash
rustup component add rustfmt clippy llvm-tools-preview
cargo install cargo-llvm-cov
# proptest goes in Cargo.toml [dev-dependencies], not installed separately
```
