# ADR 0007 — A plugin install is not equivalent to a copy-in install

- **Status:** Accepted
- **Date:** 2026-08-01
- **Supersedes:** the component-coverage claim in
  [ADR 0006](0006-distribute-as-plugin.md) (its distribution decision stands)

## Context

ADR 0006 chose zero-duplication plugin distribution: `.claude/` _is_ the plugin root, published via a
root `marketplace.json` with `"source": "./.claude"`. That decision was right and is unchanged.

One factual claim inside it was wrong. ADR 0006 states:

> All component directories (`agents/`, `skills/`, `hooks/`, `commands/`, `rules/`) are already at
> the correct relative paths within the plugin root.

**Claude Code's plugin schema has no `rules` component.** The manifest recognises `skills`,
`commands`, `agents`, `workflows`, `hooks`, `mcpServers`, `outputStyles`, `lspServers`,
`experimental.themes`, `experimental.monitors`, `userConfig`, `channels` and `dependencies` — and
nothing else. `.claude/rules/` sits inside the published plugin directory and is never scanned. The
root `CLAUDE.md` is outside the plugin root entirely.

The consequence was measured, not theorised: a `/plugin install nonna@nonna` loaded **zero** of the
4,252 words of always-on operating discipline, while `docs/INSTALL.md` claimed both install paths
"end with the same harness." Three further defects followed from the same project-relative
assumption:

1. `session-start.sh` guarded the Definition-of-Done hook install on `[ -f .claude/hooks/… ]`, a
   path that does not exist under a plugin install. It **silently no-opped** — the pre-push DoD gate
   was simply absent and nothing reported it. This is the failure mode ADR 0004 exists to prevent.
2. `/review`, `/ship` and `/fix` invoked `check-review.sh` and `check-trivial.sh` through hardcoded
   `.claude/skills/…` literals. Under a plugin install those resolve to nothing. They fail _closed_
   (exit 127 blocks the ship), so this was a usability break rather than a safety hole — but the
   commands were unusable.
3. `settings.json` permissions do not propagate either. ADR 0006 already recorded this one.

## Decision

**State the inequivalence and enforce what can be enforced; do not pretend the paths are the same.**

1. `docs/INSTALL.md` documents both gaps explicitly — the rules gap and the permission gap — with a
   copy-in remedy for each. The false equivalence claim is removed.
2. `session-start.sh` resolves the harness root from the project first, then `${CLAUDE_PLUGIN_ROOT}`
   (a real environment variable in hook processes). It installs the DoD hook from whichever it
   finds, and when it finds neither it **warns that the Definition of Done is NOT enforced**. A gate
   that is off must say so.
3. `session-start.sh` announces the resolved harness root in `additionalContext`, so gate scripts
   under `skills/*/scripts/` are locatable in either install mode. The model never guesses the path;
   the one process holding `${CLAUDE_PLUGIN_ROOT}` computes it.
4. Golden tests pin all three modes: plugin install, standalone checkout, and neither-locatable.

## Options considered

- **Do nothing.** Rejected: the harness advertised discipline that a documented install path did not
  deliver, and a gate was silently absent. That is the defect this project is built to prevent.
- **Duplicate `rules/` into a `skills/` shim so the plugin carries it.** Rejected: it creates the
  second source of truth ADR 0006 explicitly refused, and a skill loads on trigger, not always —
  turning an unconditional rule into a probabilistic one is a silent fail-open.
- **Drop plugin distribution.** Rejected: versioned, shareable installation is worth having; the
  honest fix is to scope the claim, not withdraw the channel.
- **Carry a compressed core through `SessionStart` `additionalContext`** (10,000-char cap).
  Accepted in principle, deferred to the always-on compression work — the current core is ~29,000
  characters and does not fit. This ADR records the intent; the mechanism lands when the core does.

## Consequences

- Adopters get the truth about what each install path delivers, and a two-command remedy.
- The one silent fail-open in the harness is closed and regression-tested.
- Gate scripts are reachable under a plugin install. Their first invocation may prompt for approval,
  because an absolute plugin path cannot be pre-declared in `allowed-tools`. A prompt is an
  acceptable cost; an unrunnable gate is not.
- Compressing the always-on surface is now load-bearing for distribution, not only for tokens: below
  ~9,000 characters the core can ride the `SessionStart` channel and the rules gap closes for real.
- ADR 0006's distribution decision stands. Only its component-coverage claim is superseded.

## Amendment (2026-09-23)

The `SessionStart` carrier deferred above shipped. `rules/00-core.md` is ~3,420 characters, well
under the 10,000-character `additionalContext` cap, so it rides the channel intact — the rules gap
this ADR describes is closed for the top-level conversation. ADR 0008's `SubagentStart` hook
extends the same carrier to spawned subagents in plugin mode. The "deferred … the current core is
~29,000 characters" text in Options considered is historical: it describes the pre-compaction core,
not the shipped one.

## Amendment (2026-10-01)

The approval prompt in Consequences is gone for the workflows that run a gate script. Claude Code
substitutes `${CLAUDE_SKILL_DIR}`, the skill's own directory, in a skill's `allowed-tools` and in its
body, under a plugin install and a copy-in alike. So `/fix`, `/review`, `/ship` and `/audit` grant
`Bash(bash "${CLAUDE_SKILL_DIR}/../<skill>/scripts/<script>":*)` and run that same text: the
plugin's own script, pre-approved in both installs. The grants they had named the script by its
path in the project (`.claude/skills/...`), which matched only a copy-in, and under a plugin install
would have pre-approved whatever script the project ships at that path. `/sync`, which grants
nothing, still runs its script from the harness root and may prompt.
