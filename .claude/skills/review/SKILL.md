---
name: review
description: Proportional review before merge — review-lanes.sh sizes it: one cheap reviewer for a fast-lane diff, full review otherwise, plus a security review when a risky path or line is touched.
argument-hint: "[scope — paths/files; defaults to the current branch diff vs develop]"
model: sonnet
allowed-tools: Task, Read, Grep, Glob, Edit(.claude/reviews/**), Bash(git diff:*), Bash(git branch:*), Bash(git status:*), Bash(git rev-parse:*), Bash(bash .claude/skills/review/scripts/review-lanes.sh:*), Bash(bash .claude/skills/code-review/scripts/check-review.sh:*), Bash(bash .claude/skills/lean/scripts/check-debt.sh:*)
---

!git branch --show-current
!git status --short
!git diff develop...HEAD --stat

Review: **$ARGUMENTS** (if empty, review the current branch's diff vs `develop`).

## Steps

1. **Size it — the script decides.** Run `bash $NONNA/skills/review/scripts/review-lanes.sh`
   (`$NONNA` as in step 4). It prints `lane=light|full` and `security=yes|no`, and fails closed to
   `full` / `yes`. Anything but exactly `lane=light` means full; anything but exactly
   `security=no` means yes — including a run that fails or prints nothing. Never re-classify by
   judgement, up or down (ADR-0009).
2. **Launch reviewers in PARALLEL** (independent — do not serialize):
   - **Always:** `code-reviewer` — correctness, broken contracts, missing/weak tests, silent failures,
     reproducibility, style fit. On `lane=light`, launch it with `model: sonnet`: a diff the
     fast-lane classifier accepts does not need the deep tier.
   - **If `security=yes`:** also `security-reviewer`, at its own tier — injection, secret leakage,
     broken authz, unsafe deserialization, supply chain.
3. **Persist each verdict — verbatim.** Every reviewer ends with exactly one fenced json verdict
   block. Write each block **byte-for-byte** — no merging, no rewriting, no "cleanup" — to
   `.claude/reviews/<sha>-code.json` and (when the security reviewer ran)
   `.claude/reviews/<sha>-security.json`, where `<sha>` is `git rev-parse --short HEAD`. These are
   transient gate inputs, git-ignored; a new commit invalidates them by construction.
4. **Run the gate — the script decides.** Run
   `bash $NONNA/skills/code-review/scripts/check-review.sh` on **each** verdict file, where `$NONNA`
   is the harness root announced at SessionStart (`.claude` in a standalone checkout; the plugin
   directory in a plugin install — never guess it). A non-zero exit means the review gate is red.
   Report the script's output as the verdict and **never override it** — the parser, not the model,
   decides merge-readiness (ADR-0005).
5. **Debt gate.** Run `bash $NONNA/skills/lean/scripts/check-debt.sh --range develop...HEAD` (the
   same range as the diff). A new `debt:` marker with no upgrade trigger is a gate failure (exit 1)
   — report it alongside the verdict gates; it is fixed by naming the trigger, never by deleting the
   comment while keeping the corner.
6. **Synthesize for the human.** Merge findings into one report, deduplicated, grouped by severity —
   **CRITICAL / HIGH / MEDIUM / LOW** — each with `path:line`, the issue, and a concrete fix. Any breach
   of a trust boundary, a safety gate, or "fail-closed" is automatically CRITICAL. The prose explains;
   the gate's exit code decides. If any finding carries `category: simplicity`, end with the line
   `net: -N lines possible.`

## Output

The gate result (per verdict file), then the consolidated, severity-grouped findings. If any issues
were fixed inline, note them and **re-run `/review`** — verdicts are per-commit, and the lanes are
re-computed on the new diff. Update the tracked
issue with the outcome.
