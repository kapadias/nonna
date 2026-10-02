---
name: audit
description: Repo-wide over-engineering sweep: ranked delete/stdlib/native/yagni/shrink findings + the debt ledger. Read-only, one-shot.
argument-hint: "[optional: a directory to scope; defaults to the whole repo]"
model: opus
allowed-tools: Task, Read, Grep, Glob, Bash(bash "${CLAUDE_SKILL_DIR}/../lean/scripts/check-debt.sh":*)
---

Audit for over-engineering: **$ARGUMENTS** (if empty, the whole repository).

Applies the `lean` ladder to a tree instead of a diff — a full sweep for accumulated complexity
rather than a check on one change. This produces findings only; nothing is applied. Correctness
and security are `/review`'s job, not this skill's.

## Steps

1. **Fan out.** Dispatch `explorer` per top-level source directory, concurrently, each carrying the
   same hunt list: dependencies the stdlib or platform already ships, single-implementation
   interfaces, factories with one product, wrappers that only delegate, files exporting one thing,
   dead flags and config, hand-rolled stdlib. Each subagent returns `path:line` plus a tag and a
   replacement — never file contents.
2. **Rank.** Merge the returned findings, deduplicate, and order biggest cut first. One line per
   finding, tagged `delete:` / `stdlib:` / `native:` / `yagni:` / `shrink:` (the tag format is
   defined in the `lean` skill).
3. **Ledger.** Run `bash "${CLAUDE_SKILL_DIR}/../lean/scripts/check-debt.sh" --ledger` and append
   its output to the report. A `no-trigger` marker from the script is itself a finding —
   report it, do not discard it.

## Output

Ranked lines in the form `<tag> <what to cut>. <replacement>. [path:line]`, followed by the debt
ledger, then a closing `net: -N lines, -M deps possible.` — or, if the sweep turns up nothing,
`Lean already. Ship.` Apply nothing here: route any accepted cut through `/plan` then `/tdd`, since
a deletion still needs the suite green before it merges.
