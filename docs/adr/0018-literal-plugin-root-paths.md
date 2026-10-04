# ADR 0018 — Every path the plugin loader runs is a literal `${CLAUDE_PLUGIN_ROOT}` path

- **Status:** Accepted
- **Date:** 2026-10-03
- **Deciders:** Shashank Kapadia

## Context

The claude.ai plugin **directory** validator — the review a public submission passes, stricter than the
`claude plugin validate` CLI — refuses a plugin (`COMMAND_PATH_COMPUTED`) when the plugin folder is a
subfolder of its repository (ours is `./.claude`, per `.claude-plugin/marketplace.json`) and a command
the loader runs has a path the shell computes: a variable other than `${CLAUDE_PLUGIN_ROOT}`, a command
substitution, a glob or brace, or an inline program it cannot read (`python3 -c`, `perl -e`, `awk '…'`,
`node -e`). The validator follows plain shell scripts from the hook entry points, so the rule reaches a
computed path inside a sourced library too; a non-shell file run by a literal path (an `.awk`, `.py` or
`.pl`) it holds for a human reviewer rather than refusing.

Nonna's hooks each located their own tree with `here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"`
and then sourced libs, ran `awk -f` programs, and re-ran a sibling hook through `$here/…`; the `lib/`
helpers self-sourced through `$(dirname "${BASH_SOURCE[0]}")/…`. This is portable across the install
modes, but every one of those paths is "computed" to the validator.

The variable is not one value. Under the Claude plugin, Claude Code sets `${CLAUDE_PLUGIN_ROOT}` to the
harness (`.claude`). Codex runs the same scripts through `${PLUGIN_ROOT}` and leaves `CLAUDE_PLUGIN_ROOT`
unset (ADR-0013). Copilot sets it to the **repository**, with the harness under `.claude/` (ADR-0015). A
copy-in and a git hook leave it unset (ADR-0016). So a shipped script cannot assume the set value is its
harness — yet the validator still wants every sourced path spelled from `${CLAUDE_PLUGIN_ROOT}`.

## Options considered

1. **Require `${CLAUDE_PLUGIN_ROOT}` and have the copy-in installer and git-hook wrappers export it.**
   No computation in the scripts, but the burden moves into the install wiring, where a wrong value
   fails silently and off the validated path.
2. **Keep self-location under a different variable.** Still a computed path; still refused.
3. **Resolve `${CLAUDE_PLUGIN_ROOT}` once per file, with a fallback when it is unset, and spell every
   executed or sourced path literally from it** (chosen).

## Decision

1. **Each hook entry script resolves `${CLAUDE_PLUGIN_ROOT}` to its own harness before it sources
   anything**, because the set value cannot be trusted to be the harness (see Context):

   ```sh
   if [ -z "${CLAUDE_PLUGIN_ROOT:-}" ] || [ ! -e "${CLAUDE_PLUGIN_ROOT}/hooks/lib/core.sh" ]; then
     CLAUDE_PLUGIN_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd -P)"
   fi
   ```

   It recomputes from `${BASH_SOURCE[0]}` whenever the value does not point at this harness (its own
   `hooks/lib/core.sh` missing under it) — so it self-locates under Codex, Copilot, a copy-in and a git
   hook alike, while keeping the set value under the Claude plugin, where it is already right. An entry
   script at `hooks/<name>.sh` resolves `…/..`; a self-sourcing library at `hooks/lib/<name>.sh` resolves
   `…/../..` and keeps the simpler unset-only `:=`, since it is reached only after an entry script has
   corrected the variable, or stand-alone with it unset. Either is a variable assignment, not the path of
   a command that runs a file, so the rule does not reach it. The recompute resolves with `pwd -P`, not
   plain `pwd`: `core.sh`'s own `_nonna_self` resolves symlinks, so a recomputed root must too, or the two
   disagree on a platform where the temp dir is a symlink (macOS `/var` → `/private/var`) and
   `nonna_harness_root` reports the wrong path.

2. **Every `.`/`source`, every `awk -f`, and every re-run of a hook names a literal
   `${CLAUDE_PLUGIN_ROOT}/hooks/…` path.** The two helpers that re-ran a hook generically
   (`nonna_copilot_each`, `nonna_codex_payload`) now take the hook's **name** and `case`-dispatch to a
   literal path, so no `bash "$var"` remains for the validator to flag.
3. **The two inline interpreter programs move to files run by a literal path:** the `python3 -c` pytest
   probe becomes `lib/has-pytest.py`, and the `perl -e` process-group timeout fallback becomes
   `lib/timeout.pl`. Both are held for a reviewer, not refused, and the timeout keeps the behaviour
   pinned by `tests.sh: no timeout(1)`.
4. **Inline `awk` and `sed` that only filter stdin stay.** They open no file and cannot reach outside
   the plugin; moving dozens of them into files would bloat the tree and risk behaviour for no gain.
5. **A harness-lint check mirrors the rule** (`tests/harness_lint.py`): a computed exec/source path, an
   interpreter run on a computed file path, or an inline `-c`/`-e` program in a followed hook script
   fails the build, so this cannot regress — the deterministic gate the directory validator is not,
   locally.

## Consequences

- The three install modes resolve the same directory they did before, so the suite stays green;
  `${CLAUDE_PLUGIN_ROOT}` is now the single name for a hook's own tree.
- The directory validator is not runnable locally (`claude plugin validate --strict` does not enforce
  this rule), so resubmission is the real oracle. The harness-lint mirror is the local stand-in.
- The `.awk`, `.py` and `.pl` files run by literal path, and the remaining inline `awk`/`sed` filters,
  may draw a reviewer's eye on submission but are not blockers.
- The recompute keeps a `${CLAUDE_PLUGIN_ROOT}` that already points at a harness (its `hooks/lib/core.sh`
  is present) and self-locates only otherwise, so lib sourcing now trusts a host-set value where it once
  always self-located from `${BASH_SOURCE[0]}`. Within the threat model this is unreachable — a hook runs
  with the trusted host's environment, prompt injection cannot persist a variable into a later hook, and
  an attacker who can both set the variable and plant a `core.sh` already has code execution in the
  hook's context — so the security review recorded it as a hardening follow-up, not a blocker.
- Not decided here: moving the inline `awk`/`sed` filters into files, should a later validator pass
  flag them; and hardening the recompute (re-assert the full lib set under the resolved root, or keep
  `${BASH_SOURCE[0]}` authoritative and spell paths from `${CLAUDE_PLUGIN_ROOT}` only for the validator).
