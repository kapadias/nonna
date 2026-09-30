# ADR 0012 — The Gemini CLI extension carries the rules only

- **Status:** Accepted
- **Date:** 2026-09-30
- **Deciders:** Shashank Kapadia

## Context

`install.sh --host gemini` writes `GEMINI.md` and links the git hooks. Gemini CLI can also install an
extension from a GitHub URL, `gemini extensions install https://github.com/kapadias/nonna`, which
needs a `gemini-extension.json` at the repository root. What an extension can carry decides what that
install is. The CLI's own code (0.62.0) and its offline commands (`extensions validate`, `link` and
`list`, on a fresh config, with no login and no model call) answer it; 0.8.2 gives the same for the
nested path.

- `contextFileName` is a path, a string or a list, relative to the extension directory. A nested
  `hosts/…/GEMINI.md` resolves: `extensions list` shows it under "Context files", and the CLI loads
  it into every session where the extension is enabled.
- The CLI skips, without a word, a path that is absolute, contains `..` or names no file. A
  directory is listed, then fails to load. Only `extensions validate` complains, and only about the
  first three.
- A GitHub URL installs the **latest release's source archive**, not `main`; it clones only when the
  repository has no release. Update checks compare release tags. The manifest's `version` is what
  `extensions list` shows.
- An extension can also carry hooks (`hooks/hooks.json`). Nonna's hook scripts read Claude Code's
  JSON and exit codes, so Gemini CLI's hooks need an adapter of their own (CONTRIBUTING, "Adding an
  agent host", step 3).

## Options considered

1. **Load `hosts/lite/GEMINI.md`.** No new file. But `install.sh` writes that file beside the git
   hooks it links, and its header says they refuse commits. An extension installs none, so the agent
   would be told about a gate that is not there.
2. **A `GEMINI.md` at the root**, which the CLI loads by default and the issue named as the fallback.
   Not needed, and it would load as project context for anyone who opens Gemini CLI in this
   repository.
3. **A generated `hosts/gemini-extension/GEMINI.md`**: lite's rules under a header that says the
   extension installs no hooks and `install.sh --host gemini` adds them (chosen).
4. **Ship hooks too** (`hooks/hooks.json`). A separate unit of work, taken up after this one.
5. **Full mode's rules.** The plugin starts in lite in 2.0 ([ADR 0011](0011-lite-mode-and-plugin-defaults.md)),
   and an extension's rules ride every session in every repository.

## Decision

Option 3. `gemini-extension.json` carries `name` (`nonna`), `version` (the plugin's),
`description` and `contextFileName`. `hosts/build.py` writes the context file from
`hooks/lib/lite.md` and `--check` covers it like the other hosts' files. The release workflow holds
the manifest's version to the tag with the other two manifests, since the archive Gemini CLI installs
is the tagged tree. The lint holds the manifest to the loader's own rules (a relative path to a real
file), to the sentence that says where the hooks come from, and to the plugin's version: each a way
the CLI stays silent.

## Consequences

- An extension-only install has no deterministic gate. The loaded text and the docs say so, and the
  rules stay the agent's to follow. On Gemini CLI the gates remain `install.sh`'s git hooks.
- A release now moves three version strings together: the plugin, the marketplace and the
  extension. The release workflow and the lint both refuse one that lags.
- The extension applies in every repository the user opens, where `install.sh` is per repository.
  Someone who runs both reads the rules twice.
- Checked against what the CLI reports loading, not in a live session. When hooks are added, the
  context file's header changes, and the lint's required sentence with it.
