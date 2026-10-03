---
name: rollback
disable-model-invocation: true
description: Revert a bad change or roll back a deployment — the risk-reducing counterpart to /ship. Fast-path but still gated by tests.
argument-hint: "<commit-hash or PR number or description of what to revert>"
model: sonnet
allowed-tools: Bash(git log:*), Bash(git diff:*), Bash(git branch:*), Bash(git status:*), Bash(git checkout:*), Bash(git switch:*), Bash(git revert:*), Bash(git push -u origin:*), Bash(gh pr create:*), Bash(gh pr list:*), Read, Grep, Glob
---

!git log --oneline -20
!git status --short

Rollback: **$ARGUMENTS**

## Safety posture

Rollback is **risk-reducing** — it narrows blast radius, so it may be expedited. But "expedited" does not mean "untested": the revert still passes the gate before it ships. The external system is the source of truth — reconcile actual state before declaring success (see [`.claude/rules/safety.md`](../../rules/safety.md)).

## Steps

1. **Identify the target.** From the `git log` above, pinpoint the offending commit(s) or the PR range to revert. State in one sentence: _reverting X because Y_.
2. **Check current state.** Confirm what is live (branch, last deploy, any in-flight PRs touching the same surface). Do not revert a commit that has already been superseded.
3. **Create the revert.** Use `git revert <hash> --no-edit` (one commit) or `git revert <oldest>..<newest> --no-edit` (a range). Do not `reset --hard` or force-push unless the change has not yet reached `develop`/`main` and you have explicit authorization.
4. **Run the gate.** `/test` — the suite must be green on the revert branch. A revert that breaks tests is not safe to ship.
5. **Fast-path PR.** Open a PR to `develop` (or `main` if the bad commit is already there and a hotfix path is approved). Label it `rollback`. Link the original PR/issue.
6. **Reconcile the external system.** If the bad change reached production (a deploy, a migration, a published package), confirm the live system reflects the intended state — don't assume the revert is sufficient without checking. Halt on unexplained divergence.
7. **Sync.** Update `docs/STATUS.md`, move the tracker issue, run `/sync`.

## Output

The revert commit(s), the PR link, gate result, and a one-line confirmation that the external system state is reconciled.
