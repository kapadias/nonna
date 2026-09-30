# ADR 0014 — A Copilot CLI plugin runs her gates in Copilot's hooks

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

Copilot also runs the hooks in a repository's `.claude/settings.json`, and a copy-in install
(`install.sh`) writes Nonna's there. Those run untranslated, with no `NONNA_HOST`: they read Copilot's
commands but not its file tools, beside a plugin every gate runs twice, and their commands start
from `$CLAUDE_PROJECT_DIR`, which Copilot documents setting for plugin hooks only. That predates this
decision, and the plugin does not make it worse. And one line in Copilot's repository settings
(`.github/copilot/settings*.json`, `disableAllHooks`) turns off every hook, a plugin's included,
while a file in `.github/hooks/` adds hooks of its own.

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
   and `secret-scan.sh` on `Bash`, on `write_bash|write_powershell` (input sent to a running shell)
   and on `Edit|Write`, and `secret-scan.sh` on `Read|Grep`; `Stop` runs `stop-dod.sh`. Timeouts are
   no shorter than Claude Code's (60 seconds, 300 for the stop gate): Copilot lets a tool call through
   when its hook times out.
3. **The hooks file names the host.** Each entry's `env` sets `NONNA_HOST=copilot`, and a script that
   needs it sources `.claude/hooks/lib/host-copilot.sh` in one block,
   `if [ "${NONNA_HOST:-}" = copilot ]; then …; fi`. `nonna_copilot_payload` renames the arguments;
   a payload with nothing to rename passes unchanged. `nonna_copilot_reply` holds the script's output
   and says it at exit in Copilot's form, with the same exit status. `guard-branch.sh` and
   `secret-scan.sh` use both, `session-start.sh` the reply. `stop-dod.sh` needs neither: `Stop` sends
   `session_id` and `stop_hook_active`, and takes `{decision, reason}` as it is.
4. **Copilot's names win, and every target is judged.** Copilot's tools act on their own argument
   names, so those are what the gates read, whatever Claude-named key sits beside them (a decoy): a
   write's content keys are joined and all scanned. A grep over several paths becomes one payload
   per path, and `nonna_copilot_each` runs the gate on each, refusing on the first refusal; past 32
   paths, which could not all be judged before the hook's timeout (which lets a call through), it is
   refused up front. An `apply_patch` is read as Codex's is (ADR-0013): `lib/patch.sh` reads it by
   its grammar, and `lib/host-codex.sh`'s `_nonna_codex_files` makes each file it touches Claude
   Code's Write or Edit, with the lines the patch adds, so no second parser and no second shape;
   `nonna_copilot_each` runs the gate on each, and a patch the reader refuses (outside its grammar,
   over 256 KB or 200 files) is refused. An Edit that names a path and carries a patch is judged
   both ways. A call not in the shape Copilot sends is refused, never read untranslated: a payload
   that is not a JSON object, arguments that are not an object (only `apply_patch`'s raw text comes
   as a string, and never as JSON in one), a path that is not a string, paths that are not one path
   or a flat, non-empty list. Where the payload cannot be read safely it is refused too: without jq,
   a payload that does not close, a list of paths, a Claude-named key beside Copilot's, or input to
   a shell; with jq, JSON it cannot translate.
5. **Copilot's switches are the user's.** Under either agent, the branch guard refuses a write to
   `.github/copilot/settings*.json` or under `.github/hooks/`, by file tool or by shell, as it does
   `.git/config` and the git hooks.

## Consequences

- Copilot CLI gets the stop gate and both guards where they fire, not only at the next push. Claude
  Code's path is unchanged but for decision 5: without `NONNA_HOST`, none of the adapter runs.
- One more host to follow, and no live Copilot session in any test. Golden tests (`tests/run.sh`,
  "Copilot CLI plugin") pin the payloads from Copilot's documentation and the tool definitions in
  Copilot CLI 1.0.89, and an equivalence test holds the adapter to Claude Code's own goldens,
  rewritten in Copilot's names. Revisit when a Copilot release changes the hooks reference, or when a
  live session joins the release checks.
- A copy-in install under Copilot still runs untranslated beside the plugin (Context). Copilot users
  are pointed to the plugin; a copy-in that reads Copilot's payloads is a separate change.
- Under Copilot a guard that crashes denies the tool call, Copilot's rule, where Claude Code lets it
  through.
- Copilot's and Codex's patches share one reader and one shape: a change to `lib/patch.sh` or to
  `_nonna_codex_files` changes what both hosts' gates judge, and the Copilot adapter sources
  Codex's to reach it. Only the lines a patch adds are scanned, as only an Edit's new text is.
- `review-lanes.sh` counts `hooks/copilot-hooks.json` a risky path, as it does a root
  `hooks/hooks.json`: a change to which gates Copilot runs always reaches the security reviewer.
  The manifests, under `.github/`, already did.
- `nonna_hook_is_hers` knows Claude Code's plugin directories, not Copilot's: `/nonna`'s scripts
  leave the git hooks the Copilot plugin wired, and a later Claude Code session in the same
  repository warns about them. Revisit when both plugins share repositories in practice.
- Copilot has no `/nonna`: its settings are git config (`docs/INSTALL.md`).
