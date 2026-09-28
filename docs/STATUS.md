# STATUS — Nonna

The living status of the Nonna harness itself. Adopters mirror this file for their own project; the
pre-push hook (`require-status-sync.sh`) blocks code pushes that leave it stale.

## Current state

Nonna's discipline is enforced by code at seven lifecycle events plus the git pre-push hook. The
harness tests its own gates and its own linter. The six workflows with side effects (`/ship`,
`/release`, `/rollback`, `/adr`, `/sync`, `/intake`) are human-triggered only. A plugin install
carries the constitution (`00-core.md`) into the session and into every subagent. Language- and
domain-agnostic.

Always-on surface: **3,690 words** of prose (3,700-word budget) plus 5,570 chars of skill/agent
descriptions (5,600-char budget), both enforced by the linter.

## What exists

- **Rules ×9** — `00-core` (the constitution, the decision ladder; also the plugin carrier),
  `dev-process`, `testing`, `engineering`, `git-workflow`, `sync`, `boundaries`, `safety`,
  `token-economy`. The dense, always-on policy surface — **3,690 words, budgeted at 3,700 by
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
- **Hooks ×9** — `guard-branch` (blocks protected-branch commits/pushes + `--all`/`--mirror`/`+refspec`
  force pushes), `secret-scan` (blocks secret writes + Bash reads of secret files), `format`,
  `require-status-sync` (pre-push DoD + strict secret scan, auto-installed at SessionStart — warns on
  a foreign hook), `session-start` (also carries `00-core.md` into plugin installs), `stop-dod`
  (Stop — no turn ends with STATUS stale), `subagent-verdict` (SubagentStop — ADR-0005 enforced where
  the verdict is produced), `post-compact` (PostCompact — restates loop state), `subagent-start`
  (SubagentStart — carries `00-core.md` into every subagent under a plugin install). Seven events
  wired; shared `lib/` + plugin `hooks.json`, asserted equivalent to `settings.json` by the linter.
- **Settings** — denies reading secrets and force-push; wires all hooks.
- **Tests** — `tests/run.sh` (gate golden tests; the count is derived and drift-linted, never
  hardcoded) + `tests/harness_lint.py` (self-validation).
- **Stacks** — `stacks/{python,typescript,go,rust}` wiring the test gate.
- **Plugin** — `.claude/.claude-plugin/plugin.json` (2.0.0, `displayName`, `userConfig`:
  `run_tests`, `mode`) + `.claude-plugin/marketplace.json`. Both validate with `--strict`.
- **Docs** — this `STATUS.md`, `INSTALL.md`, `OVERVIEW.md`, `docs/benchmarks/`, `CHANGELOG.md`, the
  `docs/adr/` index, and ADRs 0001–0008.
- **CI** — `.github/workflows/ci.yml`: shellcheck (all scripts) + harness-lint + gate self-tests +
  plugin manifest (`claude plugin validate --strict`, pinned CLI).

## Recently changed

History lives in `CHANGELOG.md` and `git log`. Entries here describe the current unit of work.

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

- A behavioural eval on the failures the gates exist for (a secret in a fixture, a push to a
  protected branch, an error hidden by a "fix"), scored on "did it get caught".
- A statusline showing branch and gate state.
- Optional MCP server examples for the explorer and reviewer agents.
