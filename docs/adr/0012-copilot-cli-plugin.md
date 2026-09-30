# ADR 0012 — A Copilot CLI plugin runs her gates in Copilot's hooks

- **Status:** Accepted
- **Date:** 2026-09-30
- **Deciders:** Shashank Kapadia

## Context

Copilot CLI users got the house rules (`.github/copilot-instructions.md`) and the git hooks from
`install.sh`, so nothing stopped a turn ending on a red suite, and no guard saw a command or a file
write before it ran. Copilot CLI has plugins, and hooks for the events her gates need:
`sessionStart`, `preToolUse` (exit 2 denies) and `agentStop` (`decision: "block"` sends the agent
back, `stop_hook_active` marks the forced turn, and eight blocks in a row end it)
([hooks reference](https://docs.github.com/en/copilot/reference/hooks-reference),
[plugin reference](https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-plugin-reference)).

The hooks file decides the payload's form, event by event. camelCase names (`preToolUse`) send
`toolName`, `toolArgs` as a JSON string, and `sessionId`, which her scripts cannot read: `git commit`
on `main` passed. PascalCase names (`PreToolUse`) send a VS Code compatible payload: `session_id`,
`cwd`, `stop_hook_active`, and `tool_input` under Claude Code's tool name (`Bash`, `Write`, `Edit`,
`Read`, `Grep`), matched by Claude Code's rules. What still differs: the tools' argument names
(`path`, `file_text`, `old_str`, `new_str`, grep's `paths`; `apply_patch` sends raw patch text), and
the replies. Copilot shows the agent a refusal's reason from stdout's `permissionDecisionReason`, and
reads session context as a top-level `additionalContext`.

Plugin hooks get `CLAUDE_PLUGIN_ROOT`, `CLAUDE_PLUGIN_DATA` and `CLAUDE_PROJECT_DIR` (as well as
Copilot's own names), and an `env` of their own. Copilot looks for `.github/plugin/marketplace.json`
before `.claude-plugin/marketplace.json`; without the first it installs the Claude Code plugin
(`.claude/`), whose hooks cannot tell they run under Copilot, and its 28 skills, written for Claude
Code (`/nonna` needs Claude Code's `!` lines, so it cannot run there).

## Options considered

1. **Do nothing: Copilot installs the Claude Code plugin.** It already does. But file writes pass
   unread, a refusal reaches the agent without its reason, and skills written for Claude Code load.
2. **camelCase events, translated in full.** Copilot's native form, but every field differs, and
   `toolArgs` is JSON inside a string: the most translation, in every script.
3. **One dispatcher for every host, which tells them apart by the payload's shape.** A guess is not
   a gate: a payload shaped like another host's would be read as that host's, and one file would
   change for every host.
4. **PascalCase events, and a Copilot adapter the hooks file switches on** (chosen).

## Decision

1. **The plugin is this repository.** `.github/plugin/marketplace.json` lists it (`source: "."`);
   `.github/plugin/plugin.json` points at `hooks/copilot-hooks.json`, whose commands run
   `"${CLAUDE_PLUGIN_ROOT}"/.claude/hooks/<script>.sh`. It carries no skills or agents. The hooks file
   is not `hooks/hooks.json`, the path Gemini CLI reads at a repository's root.
2. **PascalCase events.** `SessionStart` runs `session-start.sh`; `PreToolUse` runs `guard-branch.sh`
   and `secret-scan.sh` on `Bash` and on `Edit|Write`, and `secret-scan.sh` on `Read|Grep`; `Stop` runs
   `stop-dod.sh`. Timeouts are no shorter than Claude Code's (60 seconds, 300 for the stop gate):
   Copilot lets a tool call through when its hook times out.
3. **The hooks file names the host.** Each entry's `env` sets `NONNA_HOST=copilot`, and a script that
   needs it sources `.claude/hooks/lib/host-copilot.sh` in one block,
   `if [ "${NONNA_HOST:-}" = copilot ]; then …; fi`. `nonna_copilot_payload` renames the arguments; a
   payload with nothing to rename passes byte for byte. `nonna_copilot_reply` holds the script's
   output and says it at exit in Copilot's form, with the same exit status. `guard-branch.sh` and
   `secret-scan.sh` use both, `session-start.sh` the reply. `stop-dod.sh` needs neither: `Stop` sends
   `session_id` and `stop_hook_active`, and takes `{decision, reason}` as it is. Without jq, the
   adapter renames `"path"` keys in the text and the reply stays Claude Code's: exit 2 still denies.
4. **Where a payload cannot be read as finely, read it wider.** An `apply_patch` is scanned whole, as
   the no-jq path scans a raw payload, so a patch that only removes a key is refused too. A grep over
   several paths is judged by its first.

## Consequences

- Copilot CLI gets the stop gate and both guards where they fire, not only at the next push. Claude
  Code's path is unchanged: without `NONNA_HOST`, none of it runs.
- One more host to follow, and no live Copilot session in any test. Golden tests (`tests/run.sh`,
  "Copilot CLI plugin") pin the payloads from Copilot's documentation and the tool definitions in
  Copilot CLI 1.0.89. Revisit when a Copilot release changes the hooks reference, or when a live
  session joins the release checks.
- Under Copilot a guard that crashes denies the tool call, Copilot's rule, where Claude Code lets it
  through.
- `nonna_hook_is_hers` knows Claude Code's plugin directories, not Copilot's: `/nonna`'s scripts
  leave the git hooks the Copilot plugin wired, and a later Claude Code session in the same
  repository warns about them. Revisit when both plugins share repositories in practice.
- Copilot has no `/nonna`: its settings are git config (`docs/INSTALL.md`).
