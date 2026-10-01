---
name: ship
disable-model-invocation: true
description: Run the full local gate, then commit on a feature branch, push, and open a PR to develop linked to its tracked issue — and update STATUS. The disciplined path to merge.
argument-hint: "[optional: PR title / summary]"
model: sonnet
allowed-tools: Bash(git diff:*), Bash(git branch:*), Bash(git status:*), Bash(git add:*), Bash(git checkout:*), Bash(git switch:*), Bash(git push -u origin:*), Bash(git commit:*), Bash(git log:*), Bash(git rev-parse:*), Bash(gh pr create:*), Bash(bash .claude/skills/code-review/scripts/check-review.sh:*), Bash(bash tests/run.sh:*), Bash(python3 tests/harness_lint.py:*), Read, Grep, Glob
---

!git branch --show-current
!git status --short
!git diff develop...HEAD --stat

Ship: **$ARGUMENTS**

## Steps

1. **Gate first — do not skip.** Run lint + type-check + tests + coverage (`/test`). If anything is
   red, stop and fix it. **Never ship with failing tests** (see
   [`.claude/rules/testing.md`](../../rules/testing.md)).
2. **Review gate — deterministic.** Verdict files for the **current** `git rev-parse --short HEAD`
   must exist under `.claude/reviews/` (missing or stale — the SHA in the filename differs — means
   `/review` has not run against this exact code: run it first). Then run
   `bash $NONNA/skills/code-review/scripts/check-review.sh` on each file — `$NONNA` is the harness root
   announced at SessionStart (`.claude` standalone, the plugin directory under a plugin install).
   **Any non-zero exit blocks the ship** (ADR-0005). Do not argue with the parser — fix and re-review.
3. **Branch check.** Ensure you are on a `feature|fix|chore|refactor/<id>-<slug>` branch, not
   `main`/`develop`. If not, create one and move your work (see
   [`.claude/rules/git-workflow.md`](../../rules/git-workflow.md)).
4. **Review the whole delta:** `git diff develop...HEAD`. Confirm there are no secrets, no debug spew,
   no unrelated changes.
5. **Commit** in logical units with conventional-commit messages (`feat:`, `fix:`, …), referencing the
   tracked issue.
6. **Sync the mirrors** (`/sync`): update `docs/STATUS.md`, add an ADR if a decision was made, and move
   the tracked issue. The pre-push hook will block a code push that skips `docs/STATUS.md`.
7. **Push & PR:** `git push -u origin <branch>`, open a PR **to `develop`** (never straight to `main`),
   summarize the delta and the test plan, and **link the PR to the issue**. Paste the PR link back onto
   the issue.

## Guardrails

- PR target is `develop`. Only `develop → main` goes to production.
- Do not open a PR if the gate is red or the diff contains secrets.

## Output

The branch, the commit(s), the PR link, and a checked-off Definition-of-Done list — reported as
**Assumptions / Changed / Verified / Remaining risk** (rules/dev-process.md §6), with the gate and
review results you _observed_, never inferred.
