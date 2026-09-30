# ADR 0012 — Codex runs Nonna's hooks through a payload adapter

- **Status:** Accepted
- **Date:** 2026-09-30
- **Deciders:** Shashank Kapadia

## Context

Codex users got `AGENTS.md` and the git hooks, so Codex could still end a turn on a red suite. Codex
has hooks with Nonna's contracts: exit code 2 blocks a `PreToolUse` call, a `Stop` hook that prints
`{"decision":"block","reason":…}` sends the agent back, and a plugin's hooks get `PLUGIN_ROOT` and
`CLAUDE_PLUGIN_ROOT`. What Codex 0.159.2 does was checked against the binary itself, offline:
`codex plugin marketplace add`, `codex plugin add`, and its app server's `plugin/read` and
`hooks/list` on a scratch home, with the hook schemas bundled in `@openai/codex`.

- **The plugin root is `.claude/`.** Codex reads the legacy `.claude-plugin/marketplace.json`, whose
  `source` is `./.claude`, and installs that directory into its plugin cache.
- **Without a manifest of its own, Codex would load Claude Code's `hooks/hooks.json`**, by default
  discovery, with `${CLAUDE_PLUGIN_ROOT}` filled in. Those hooks run, but they guard nothing Codex
  edits: Codex edits with `apply_patch`, which neither guard reads. A patch that adds a key, or
  edits `.git/config`, exited 0.
- **Most of Codex's payload already has Claude Code's shape.** A shell call is `tool_name: "Bash"`
  with `tool_input.command`; `session_id`, `cwd` and `stop_hook_active` keep their names; the
  `Stop` and `SessionStart` answers Nonna prints are ones Codex reads. An edit is the exception: one
  `apply_patch` call, the patch in `tool_input.command`, can add, update, move and delete several
  files. Nonna's gates read one file a call, as Claude Code's Write and Edit send it.
- **Codex's hook handlers take no environment.** A handler has `command`, `timeout`,
  `statusMessage` and a few Codex-only keys; the command runs in a shell, from the session's
  directory, with the plugin root written into it.

## Options considered

1. **Sniff the payload** (`turn_id`, `model`, `tool_name: apply_patch`) to tell Codex from Claude
   Code. No manifest to keep, but the host becomes a guess made from input the agent's own tools
   shape, and each new host adds a guess.
2. **A shared dispatcher** that every script calls, choosing an adapter per host. One place, but
   every gate then depends on code that changes with each host, and two hosts built at once
   collide in it.
3. **Translate the patch into one Claude Code payload.** One file path cannot carry several files:
   a patch whose second file is `.git/config` would pass.
4. **The host names itself in its own hooks file, and one adapter per host** (chosen).

## Decision

1. **A Codex manifest, `.claude/.codex-plugin/plugin.json`**, on the plugin's version, whose `hooks`
   names `hooks/codex-hooks.json`. Codex prefers it to `.claude-plugin/plugin.json`, and a `hooks`
   entry replaces the default `hooks/hooks.json`.
2. **`hooks/codex-hooks.json` runs the same scripts**, each command
   `NONNA_HOST=codex "${PLUGIN_ROOT}"/hooks/<script>.sh`, on `SessionStart` (with `${PLUGIN_DATA}`),
   `PreToolUse` on `^Bash$` and on `^apply_patch$` (both guards), `Stop` (300 seconds, as for Claude
   Code) and `SubagentStart`. Not wired: `PostCompact`, whose answer Codex reads without context
   (its `SessionStart` after a compaction carries the rules again); the formatter, which the plugin
   never runs; and the review verdict gate, since Codex runs none of her agents.
3. **The host comes from the hooks file, never from the payload.** A script that needs it has one
   small block: under `NONNA_HOST=codex` it sources `lib/host-codex.sh` and reads the payload
   through `nonna_codex_payload`. Anything but an `apply_patch` passes through unchanged, so Claude
   Code's input is read exactly as before. Another host gets its own `lib/host-<host>.sh` and its own
   block.
4. **An `apply_patch` is checked a file at a time, by the gate itself.** The adapter turns the patch
   into Claude Code's payloads: a Write of each file it adds, its lines as the content; an Edit of
   each file it updates or moves a file to, with the lines it adds; an Edit with nothing added of
   each file it deletes or moves away. The gate runs once on each, and the first refusal stands. File
   headers are read as Codex's parser reads them, blanks trimmed. Only the lines a patch adds are
   scanned, as the pre-commit hook scans a diff, so a patch that takes a key out passes. A patch that
   cannot be read (jq or awk failing) is refused, and so is one in which no file is read: Codex's
   grammar puts a file in every patch.
5. **The lint holds the Codex file to its own form and core gates**: the command form above, the
   gates on `Bash`, `apply_patch`, `Stop` and `SessionStart`, and a manifest that names the file on
   the plugin's version. The release checks the Codex manifest's version with the others.

## Consequences

- Codex gets the test gate, "where's the test?" and both guards on its edits and commands, from the
  same scripts. Golden tests run each hook as Codex starts it, from the file, on Codex's documented
  payloads. None of it has run in a Codex session end to end, and the benchmark has no Codex arm,
  so the README claims no parity. Revisit when either exists.
- Codex runs a plugin's hooks only once the user trusts them in `/hooks`, and asks again when a
  hook changes, so an update that edits `codex-hooks.json` asks each user again.
- Codex hands a `Stop` hook's reason to the agent as a new prompt. The failing lines stay quoted as
  the repository's words, as under Claude Code; a suite's output can still address the agent there.
- A patch over many files starts the gate once per file: about 45 ms a file for each guard when
  measured, so 100 files took 4.5 seconds. A hook that outruns its timeout does not block, and Codex
  allows 600 seconds by default, which a patch would need some 13,000 files to use up. Revisit if
  long patches come near it; refusing a patch over a file count would close it.
- `/nonna` and the plugin's options are Claude Code's. Under Codex, her settings are git config, and
  the first-session notice, which names `/nonna`, says so less well than it could.
- Only a payload whose `tool_name` is `apply_patch` is read as a patch: that is the shape Codex
  documents, and the one tested. Codex's shell tool can also run `apply_patch` as a program. If a
  hook ever sees such a call as `Bash`, the guards give it their shell reading, which does not read
  the patch inside it, and the git hooks are the backstop. Confirm it in a Codex session.
