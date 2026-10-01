---
name: fix
description: The bounded fast lane for trivial, reversible fixes — check-trivial.sh decides eligibility (≤15 lines, ≤3 files, no new deps, off the critical surface); regression test, gate, and single machine-checked review are never skipped. Anything bigger routes to the full loop.
argument-hint: "[what to fix]"
model: sonnet
allowed-tools: Task, Read, Grep, Glob, Edit(.claude/reviews/**), Bash(git diff:*), Bash(git branch:*), Bash(git status:*), Bash(git rev-parse:*), Bash(git checkout:*), Bash(git add:*), Bash(git commit:*), Bash(git push -u origin:*), Bash(bash "${CLAUDE_SKILL_DIR}/../fast-lane/scripts/check-trivial.sh":*), Bash(bash "${CLAUDE_SKILL_DIR}/../code-review/scripts/check-review.sh":*)
---

!git branch --show-current
!git status --short

Fix: **$ARGUMENTS**

The autonomy dial, bounded (see the `fast-lane` skill): the leash length is set by a deterministic
script, not by self-assessment. If at any step this looks bigger than trivial, stop and take the
full loop.

## Steps

1. **Branch check.** Never on `main`/`master`/`develop` — branch as `fix/<id>-<slug>` first.
2. **Regression test first.** Pin the fixed behavior with a test that fails before the change
   (RED). Behavior changes are never exempt; only a docs/comment-only diff — nothing to pin —
   skips this.
3. **Implement the minimal fix** (GREEN). No drive-by improvements — surgical changes only.
4. **Eligibility — the script decides.** Run
   `bash "${CLAUDE_SKILL_DIR}/../fast-lane/scripts/check-trivial.sh"`. Non-zero means this is
   **not** a trivial change: stop and route through the full loop (`/plan` → `/tdd` → `/review` →
   `/ship`). Do not argue with the classifier.
5. **Full local gate** (`/test`): lint + type-check + tests + coverage. Never skipped, never
   reported green unless observed green.
6. **Single review — machine-checked.** Dispatch `code-reviewer` with `model: sonnet` (a fast-lane
   diff does not need the deep tier); write its fenced JSON verdict
   verbatim to `.claude/reviews/<sha>-code.json` (`git rev-parse --short HEAD`) and run
   `bash "${CLAUDE_SKILL_DIR}/../code-review/scripts/check-review.sh"` on it. Non-zero blocks the ship.
7. **Ship.** One-line `docs/STATUS.md` entry, conventional commit, `git push -u origin <branch>`,
   PR to `develop` linked to the tracked issue.

## Output

Report as **Assumptions / Changed / Verified / Remaining risk** — include the classifier's line
count, the observed gate result, and the review verdict.
