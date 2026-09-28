# CLAUDE.md — Nonna

Nonna is a portable `.claude/` harness that keeps AI-assisted development disciplined, test-driven,
review-gated, and safe by construction. Language- and domain-agnostic: drop it into any repository
and the same loop applies.

**The operating rules are in [`.claude/rules/`](.claude/rules/), which loads on every turn.** Start
with [`00-core.md`](.claude/rules/00-core.md) — the three principles, the loop, the ladder, the never-list, and
routing. This file holds only what lives nowhere else.

## Caliber bar

Senior-staff engineering rigor. Every change is planned, tested first, reviewed, and verified before
it merges. We do not ship hope. "Works on my machine" is not done; **green tests + passing review +
synced docs** is done.

## Model-tier policy

Match model to task depth — never burn a deep-reasoning model on mechanical work.

- **Opus** — planning, architecture, code/security review, debugging hard failures, orchestration.
- **Sonnet** — the bulk of implementation and test-writing.
- **Haiku** — high-volume mechanical work: fan-out search, bulk edits, simple single-file changes.

## Rules precedence

Project rules in `.claude/rules/` override any global `~/.claude/rules/`. When in doubt, choose the
option that preserves correctness, safety, and reproducibility over cleverness or speed.

## Where things live

`.claude/README.md` maps the harness. Agent and skill descriptions are already in context —
do not re-read an index to find them. Nonna installs as a plugin
(`/plugin marketplace add kapadias/nonna`); a plugin install is **not** equivalent to a copy-in
install, and defaults to lite mode — see [`docs/INSTALL.md`](docs/INSTALL.md),
[ADR 0007](docs/adr/0007-plugin-install-is-not-equivalent.md) and [ADR 0011](docs/adr/0011-lite-mode-and-plugin-defaults.md).
