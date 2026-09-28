# STATUS — Nonna

The living status of the Nonna harness itself. Adopters mirror this file for their own project; the
pre-push hook (`require-status-sync.sh`) blocks code pushes that leave it stale.

## Current state

Nonna's discipline is enforced by code at seven lifecycle events plus the git pre-commit and
pre-push hooks. The harness tests its own gates and its own linter. The six workflows with side
effects (`/ship`, `/release`, `/rollback`, `/adr`, `/sync`, `/intake`) are human-triggered only.
One switch per repo sets the mode (`off | lite | full`, ADR-0011). A plugin install defaults to
lite: the test gate, the branch and secret guards, and six house rules carried into the session and
every subagent; full carries the constitution (`00-core.md`) and adds the STATUS gate. Language-
and domain-agnostic.

Always-on surface: **3,681 words** of prose (3,700-word budget) plus 5,570 chars of skill/agent
descriptions (5,600-char budget), both enforced by the linter.

## What exists

- **Rules ×9** — `00-core` (the constitution, the decision ladder; also the plugin carrier),
  `dev-process`, `testing`, `engineering`, `git-workflow`, `sync`, `boundaries`, `safety`,
  `token-economy`. The dense, always-on policy surface — **3,681 words with `CLAUDE.md`, budgeted at 3,700 by
  `harness_lint.py`**.
- **Agents ×8** — `orchestrator`, `planner`, `implementer`, `test-engineer`, `code-reviewer`,
  `security-reviewer`, `explorer`, `debugger`. Reviewers emit a structured JSON verdict.
- **Skills ×12** — `tdd-workflow`, `code-review`, `debugging`, `refactoring`, `api-design`,
  `security-review`, `migration-safety`, `observability`, `concurrency-performance`, `supply-chain`,
  `fast-lane`, `lean` (bundles `check-debt.sh`) — most bundling runnable scripts/templates/references.
- **Pipeline workflows ×15** — also under `skills/`, since Claude Code merged commands into skills:
  `/plan`, `/tdd`, `/implement`, `/review`, `/audit`, `/test`, `/coverage`, `/debug`, `/fix`,
  `/ship`, `/release`, `/rollback`, `/sync`, `/adr`, `/intake`. Model-tiered; several use `!`/`@` injection.
  The six with side effects set `disable-model-invocation: true` — human-triggered only, and out of
  context entirely.
- **Hooks ×10** — each reads the mode first; `off` is silent. `guard-branch` (blocks protected-branch
  commits/pushes, `--all`/`--mirror`, force pushes, `--no-verify`, hook-path overrides, and the
  agent's writes to Nonna's own git config), `secret-scan` (blocks secret writes + reads of secret
  files, Read, Grep or Bash), `format`, `require-status-sync` (pre-push: the test suite, a strict secret
  scan, and in full mode the DoD), `pre-commit` (no commit on a protected branch, no staged secret),
  `session-start` (wires both git hooks, through the plugin's data directory under a plugin install;
  records the plugin's test command and mode; carries the mode's rules; tells the user once),
  `stop-dod` (Stop — since the session began: the suite, "where's the test?", and in full mode a
  stale STATUS), `subagent-verdict` (SubagentStop — ADR-0005 enforced where the verdict is
  produced), `post-compact` (PostCompact — restates loop state), `subagent-start` (SubagentStart —
  carries the mode's rules into every subagent under a plugin install). Seven events wired; shared
  `lib/` (including `lite.md`, the lite house rules) + plugin `hooks.json`, asserted equivalent to
  `settings.json` by the linter.
- **Settings** — denies reading secrets and force-push (the hooks refuse both too, since a plugin
  cannot carry this file); wires all hooks.
- **Tests** — `tests/run.sh` (gate golden tests; the count is derived and drift-linted, never
  hardcoded) + `tests/harness_lint.py` (self-validation).
- **Stacks** — `stacks/{python,typescript,go,rust}` wiring the test gate.
- **Plugin** — `.claude/.claude-plugin/plugin.json` (2.0.0, `displayName`, `userConfig`:
  `run_tests`, `mode`) + `.claude-plugin/marketplace.json`. Both validate with `--strict`.
- **Docs** — this `STATUS.md`, `INSTALL.md`, `OVERVIEW.md`, `docs/benchmarks/`, `CHANGELOG.md`, the
  `docs/adr/` index, and ADRs 0001–0011.
- **CI** — `.github/workflows/ci.yml`: shellcheck (all scripts) + harness-lint + gate self-tests +
  plugin manifest (`claude plugin validate --strict`, pinned CLI).

## Recently changed

History lives in `CHANGELOG.md` and `git log`. Entries here describe the current unit of work.

- **2026-09-25** — Plugin defaults, the second unit of the launch plan (#17, ADR-0011). One switch
  per repo, git config `nonna.mode` (`off | lite | full`), read by every Claude Code hook and git
  hook. The plugin defaults to lite: the test gate, "where's the test?", the branch and secret guards
  and six house rules (`hooks/lib/lite.md`). Full adds the STATUS gate, now only where
  `docs/STATUS.md` exists. The plugin's test gate is on out of the box: the `run_tests` option is the
  consent, and the first session records the detected command in `nonna.testCmd`. What Nonna records
  about the mode goes in `nonna.defaultMode`, below the user's `nonna.mode`, so a global off reaches
  every repo. Git hooks link through the plugin's data directory, so an update no longer leaves them
  dangling, and `pre-commit` is wired too. Force pushes, `--no-verify`, hook-path overrides and reads
  of secret files are refused by hooks, which a plugin carries. Stop checks everything since the
  session began, shows the failing lines with secrets hidden, and asks for a test once when code
  changed and none did. The first session tells the user what Nonna did in their repo. Full mode
  drops the ladder when another plugin already states it. `install.sh --mode lite|full`.
  `INSTALL.md` leads with the plugin.
  Review round (code and security, both request changes, all addressed but one). The git hooks read
  git config alone, never the environment, `git -c` or an included file, so a command cannot switch
  them off for itself. The branch guard reads a command the way the shell will run it (quotes,
  continued lines, subshells, abbreviated flags) and refuses changes to her settings, includes,
  aliases, hooks path and git hooks. A plugin never sources or wires scripts a repository ships.
  A hook that points at nothing is reported (Keel-era links are repaired). An untracked STATUS counts
  as written, and full mode refuses a turn or push that deletes it. "Where's the test?" asks once per
  set of changes. The suite's output is quoted as the repository's words. The secret guard covers
  Grep, symlinks and case. The suite runs on its own git config. Per-repository test consent stays
  plugin-wide by the maintainer's decision (ADR-0011).
  Second review round (code approved; security found the message masking could hide a command): the
  guard now tokenizes a command the way the shell does (lib/shell-words.awk) and checks two readings,
  words whole and quoted strings opened. Grep globs are matched as patterns, and "where's the test?"
  remembers the code, not the file names. A macOS CI job is a follow-up (#17). 675 tests.
  Third review round (both request changes; security approved the heredoc fix): Claude Code's
  heredoc message is read as one word only where it opens outside any quote and ends where bash
  ends it, and it is set aside only as a git message, so a body that `sh -c` or `eval` runs stays in
  view. A message is masked only in `git commit`, `merge`, `tag`, `stash` and `notes` (and `gh`
  titles and bodies), before any expansion the reader does not follow, and never where an earlier
  option takes the flag as its value (`-Fm`, `-t -m`). Quotes nested in `sh -c`, `$'…'` escapes and
  `>|` no longer hide anything. A config read flag counts only before the key, and one key alone is
  a read. Assignments count after `{`, `then`, `eval` and `time`, and through `export NAME`,
  `printf -v`, `read` and `sudo`. A copy's target is found past a redirection or `-t`. A Grep glob is
  judged by the secret files it would read. 745 tests.
  Fourth review round (security approved; code found four holes): a heredoc message is set aside
  only when its body holds no `"`, `$`, backtick or backslash, because macOS `/bin/bash` 3.2 ends the
  `$(` inside the body. `&>` is one redirection. An empty quoted word stays a word, a config read is
  one dotted key with only read-safe options before it, and an abbreviated `--rem` is an action.
  `--attr-source` and `--shallow-file` take a value, a git command inside a value (`GIT_EDITOR=…`,
  `--exec=…`) is read, and nesting deeper than six reads is refused. Assignment rules hold only at
  the start of a command (or after `sh -c`), so a search for `export NONNA_MODE` passes. In the
  project a Grep glob is judged by the secret files there, a sample name no longer decides. A fuzz
  of 700 heredoc messages under bash 3.2 and 5.2 finds no command the guard lets through. 776 tests.
  Fifth review round (both request changes): git 2.45's `--comment` takes the next word as its
  value, so a read flag counts only after read-safe options, and a digit with a space before `>` is
  an argument, not a file descriptor (`git config core.hooksPath 2 >/dev/null` writes). An assignment
  that carries a value counts wherever it stands again (after `builtin`, `command`, a redirection,
  `nice env`, or in a `trap` string); anchoring had let those through. 792 tests.
  Sixth review round (security approved; code found one hole): a quoted value that looked like a
  redirection (`git config core.hooksPath '>/dev/null'`) was set aside as one. The reader now marks
  each redirection the shell performs, and only marked ones are set aside. 799 tests.
  Seventh review round (code found the mark had broken the start-of-command anchor): a command that
  begins with a redirection is a command's start again, so `>/dev/null GIT_CONFIG_GLOBAL=…` is
  refused. 803 tests.
  Eighth review round (both approved; security's MEDIUM): the guard refuses what it cannot read.
  Without jq, a JSON string is decoded in full; an escaped quote had cut
  `git commit -m "x" && git push --force` short. A failing jq or awk no longer waves a git command
  through, even one whose name is split across a continued line. 812 tests.
  Ninth review round (code: a long heredoc outran the hook's timeout, and a glob named git): the
  reader runs in linear time in every awk (macOS's one-true-awk had taken over a minute on 100 KB),
  and a command over 256 KB is refused, since a hook that times out does not block. Brace lists
  expand as bash expands them, and a glob is read as what it could match (`gi[t]`, `@(git)`,
  `mai[n]`, `.g?t/hooks`); an expansion too large to read is refused. Probing found more spellings,
  now refused too: git's own binaries (`/usr/lib/git-core/git-push`), capitals (macOS finds
  `GIT`), a path to `env`, `send-pack` (which runs no hook), `subtree push`, the `:` and wildcard refspecs, and push
  refspecs or `push.default` in the config. 856 tests.
  Tenth review round: both approve. The one LOW is the declared trade: quoted text is expanded as
  code, so a minified JSON array in one word is refused as too large to read from 16 two-field
  objects (fewer with more fields; ADR-0011 §4).
  Two follow-ups, found while planning `/nonna`. The guard now knows a branch before its first
  commit; it had let the first commit onto a new, empty `main` through. And a git hook link is hers
  only when it leads to her own script. A user's own `scripts/pre-commit.sh` link had been taken
  for hers, which left her gate off without a word. 859 tests.
  Eleventh review round, three findings, all fixed. A tag named `main` made the branch read as
  `heads/main`, so the guard and the pre-commit hook let a commit onto `main` through; both now
  read the full ref. Her plugin paths are anchored to the plugins directory Claude Code uses, so a
  link merely shaped like hers is not hers. And a user's hook chains hers only when it names her
  script's path, not a file that merely shares its name. 864 tests.
  Twelfth review round: both approve, and their two LOWs are fixed. A path that climbs back out of
  her cache with `..` is not hers, and her plugins directory is read as written and as resolved, so
  a `HOME` ending in `/` or a symlinked config directory still gets her dangling link repaired.
  867 tests.

- **2026-09-25** — 2.0 packaging, the first unit of the launch plan (#17). Both manifests say 2.0.0;
  the plugin shows as "Nonna" and declares two install options, `run_tests` and `mode`. The hooks
  begin reading these options in the plugin-defaults unit (#17), so for now declaring them changes
  nothing. `claude plugin validate --strict` passes on both manifests and runs in CI at a pinned
  CLI version. Every hook command quotes its root, so a path with a space no longer skips the
  gate. The linter enforces the quoting in both files, and a golden test runs every wired command
  from such a path. SessionStart receives the plugin data dir, and the Stop and SessionStart
  spinners name Nonna. The CHANGELOG's `[Unreleased]` section is now `[2.0.0]`, with an upgrade
  block. Issue templates and a code of conduct are added.
  Review round: the linter now holds every hook command to one exact form (quoted root, script,
  nothing after it), because a `|| true` tail in one install mode would turn a gate's block into a
  pass and still lint clean. The only argument allowed is SessionStart's plugin data dir. The
  other keys are pinned the same way: a gate is type "command", never async, with no timeout under
  10 s, and timed the same in both install modes. `disableAllHooks` in settings.json is refused.
  399 tests.

- **2026-09-24** — README answers an outside review. A bridge sentence says the 8 of 8 task is
  the worst case (a third of runs on average); the break-even is a four-row table so readers can pick
  their own mistake rate (derivation now in `bench/README.md`); one line up top names the rest of the
  harness (8 agents, 15 workflows, 6 human-only); and a table says what Claude Code gets versus
  every other agent.
- **2026-09-24** — Fourth security review (of the third round's fixes, after `main` was promoted)
  addressed, 8 more tests (370): added lines are found by position, not text, so an octopus merge's
  `+++` lines and content starting `++ ` are scanned; `--root` overrides `log.showRoot=false`; a
  shallow boundary the destination is not known to have is a stop; the per-file pass names a key on
  a side branch a merge discarded. The merge-scan test now proves the scan, not the STATUS check.
  Fifth review (approve) MEDIUMs, 2 more tests (372): a remote named `origin/fork` no longer vouches
  for `origin`; a tag on a blob or tree is a stop; the shallow check is one `grep` over the range
  (60 s to milliseconds on a 2,000-boundary clone).
  The repo is now `kapadias/nonna`: install, clone, plugin, security-advisory and star-history
  links point there (ADR-0006 keeps its historical wording).
- **2026-09-24** — Third security review addressed before promotion to `main` (8 more tests, 362).
  The push scan now sees merge resolutions (`--cc`), scans a URL push against that URL rather than
  other remotes, treats a failed `git log` as a stop, reads file names NUL-safe in pre-commit and
  pre-push, excludes a shallow clone's graft, and scans the whole push in one pass (a 1,000-commit
  first push: 99 s before, 0.2 s after).
- **2026-09-24** — Second security review addressed (12 more tests, 354): the push scan covers
  every commit the remote lacks, per commit, whatever the git config; tags and deletes are not
  refused; untracked files make the tree dirty for the test gate; the macOS timeout kills the
  process group; a kept `settings.json` without Nonna's hooks is reported.
  The pytest-detection tests carry a stand-in pytest, so they pass whether or not the machine has it.
- **2026-09-24** — Security review of `install.sh` and the new hooks addressed, with 26 new golden
  tests (342): installer merge, symlink and failure handling; the test gate is opt-in under a plugin
  install; a cached green tree and a timeout budget for the Stop hook; the pre-push range comes from
  git's stdin; `pre-commit` is pathspec- and binary-safe.
- **2026-09-24** — The harness is Nonna (ADR-0010): renamed across code, docs and plugin
  manifests; gate messages carry her voice ahead of the technical reason. New mascot (`assets/nonna.svg`),
  banner and README in her voice; the failure-mode and re-run benchmarks are in progress.
- **2026-09-24** — Reproducible benchmark in `bench/` (8 trap tasks, n=4, Claude Sonnet and Haiku): bare
  agent cut a corner in 23 of 64 runs, Nonna in 0 of 64. README rewritten around that number, one
  before/after and one-command install; workflows table moved to `docs/OVERVIEW.md`; banner says "for AI coding agents".
- **2026-09-24** — "Done" means the suite passes: the Stop and pre-push hooks run the project's
  test command when code changed and refuse on red (`hooks/lib/tests.sh`). The benchmark showed
  agents claiming done on a broken suite; nothing had checked.
- **2026-09-24** — One-command install (`install.sh`, `--host` for eight hosts): harness, host rules,
  blank STATUS, stack pack, git hooks; never overwrites. 18 golden tests.
- **2026-09-24** — Beyond Claude Code: `hosts/build.py` generates each agent host's rules file
  (AGENTS.md, Cursor, Copilot, Gemini, Windsurf, Cline, Kiro) from `00-core.md`, drift-linted; a git
  `pre-commit` hook (branch guard, secret files, staged secrets) binds any agent that commits.
- **2026-09-24** — README numbers tell the total cost: the bill you see ($0.13 vs $1.96 per change),
  the bill you don't (5 mistakes in 20 bare runs vs 0 in 22), and the break-even ($7 per cleanup at 1
  in 4). Derivation in the failure-mode benchmark; line counts exclude tests.
- **2026-09-24** — README numbers now come from the failure-mode and proportional-review evals
  (flat scorecard, `assets/scorecard.svg`): cost per change about a third lower; light lane still
  unmeasured.
- **2026-09-24** — Failure-mode benchmark (`docs/benchmarks/2026-09-24-failure-modes.md`): bare agent
  5 mistakes in 20 runs, Nonna 0 in 22, prevented by the rules; no hook had to block.
- **2026-09-24** — Review found `review-lanes.sh` under-reviewing risky diffs (removed checks,
  manifests, other languages, odd paths); fixed with 13 new golden tests. Flat mascot and banner, lettering in Space Grotesk.
- **2026-09-24** — Proportional review (ADR-0009): `review-lanes.sh` sizes `/review` by script, so a
  small diff pays for one cheaper reviewer and the security reviewer runs on evidence in the diff.
  `/review` and `/fix`'s reviewer move to the cheaper tier; small changes start in `/fix`; off the
  critical surface one test is enough. `check-review.sh` lists adds-code findings with no
  failing input as `optional:`. The verdict-gate fix from `develop` is merged in.

## Next / open

- The rest of the launch plan (#17): `/nonna` (status, setup, `lite|full|off`, uninstall), then
  benchmark round 3 with lite, full and the real FastAPI suite, then the launch README and assets.

- A behavioural eval on the failures the gates exist for (a secret in a fixture, a push to a
  protected branch, an error hidden by a "fix"), scored on "did it get caught".
- A statusline showing branch and gate state.
- Optional MCP server examples for the explorer and reviewer agents.
