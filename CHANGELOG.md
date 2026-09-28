# Changelog

All notable changes to Nonna. Format follows [Keep a Changelog](https://keepachangelog.com/1.1.0/);
versioning is [SemVer](https://semver.org/spec/v2.0.0.html).

## [2.0.0] — 2026-10-08 — "Tests Decide Done"

### Upgrading from 1.x (Keel)

- Reinstall: `/plugin uninstall keel@keel`, then `/plugin marketplace add kapadias/nonna` and
  `/plugin install nonna@nonna`.
- Environment variables are now `NONNA_*` (for example `NONNA_CRITICAL_PATHS`).
- The plugin now starts in **lite** mode: the test gate, the branch and secret guards and six house
  rules. For 1.x's behaviour (the constitution and the STATUS gate), run `git config nonna.mode full`
  in a repository, add `--global` for all of them, or set the plugin's `mode` option to full.
- The STATUS gate runs only in full mode, and only where `docs/STATUS.md` exists.
- The plugin runs your tests before the agent can say done and before a push. The first session in a
  repository records the command it detects in `git config nonna.testCmd`; set it to `""` there to
  turn the gate off, or turn the `run_tests` option off before Nonna meets your repositories.
- The git hooks now read git config alone. `NONNA_TEST_CMD` and `NONNA_MODE` still steer Claude
  Code's hooks, but no longer the git hooks: for your own pushes, set `git config nonna.testCmd`.

### Added

- **Modes: `off`, `lite` and `full`, one switch per repository** (ADR-0011). Every hook reads, in
  order: `NONNA_MODE` (Claude Code's hooks only), your `nonna.mode` (repository, then global), the
  plugin's `mode` option, `nonna.defaultMode`, and last what the repository carries (the hooks and
  the rules: full; otherwise lite). A value nobody meant fails closed to full; `off` enforces
  nothing and says nothing. Nonna never writes `nonna.mode` herself: what she records goes in
  `nonna.defaultMode`, below it, so `git config --global nonna.mode off` reaches every repository
  you have not set. The git hooks take nothing from the environment, a `git -c` flag or a file the
  config includes, so a command cannot switch them off for itself.
- **Lite**, the plugin's default: the test gate, "where's the test?", the branch and secret guards,
  the git hooks, and six house rules (`hooks/lib/lite.md`, linted to 150 words and to cover the
  never-list) in place of the constitution. `install.sh --mode lite|full` (copy-in stays full by
  default), with lite rules for the other hosts in `hosts/lite/`.
- **The plugin's test gate works out of the box, with consent.** The `run_tests` option (on) is the
  consent: the first session in a repository records the detected command in `nonna.testCmd`, where
  the Stop and pre-push hooks read it, and never overwrites one, an empty one included. The first
  session also tells you, once, what Nonna did there: the mode, the test command and the git hooks
  she added.
- **"Where's the test?"** When source changed and no test file did, Stop sends the agent back for a
  test that fails without the change, or a plain reason why none is needed. It asks once for a set of
  changes in a session.
- **Committed work cannot dodge the Stop gate.** SessionStart records where the session began, and
  Stop checks everything changed since, committed or not.
- **The Stop block shows what failed**: the failing lines from pytest, jest, go, cargo or TAP output,
  quoted as the repository's words (a test cannot speak in her voice), with any line that looks like
  a secret hidden, then what to do.
- **Guards that travel with the plugin.** The branch guard refuses force pushes (`--force`, `-f`,
  `--force-with-lease`, abbreviated or in a cluster), a push of every branch (`:`, a wildcard),
  `--no-verify`, hook-path overrides, push config, and an agent's changes to Nonna's own settings or
  git hooks, through `git push`, `subtree push` or git's own `git-push`, and git's plumbing pushes,
  which run no hook (`send-pack`). It reads each
  command the way the shell will run it, so quotes, escapes, brace lists, globs, capitals and a
  nested `sh -c` do not hide a flag; a value computed when the command runs can. It is a speed bump:
  branch protection on the server is the wall. The secret
  guard refuses reads and searches (Read, Grep) of secret files, by any name that leads to one,
  linted against the `settings.json` deny-list.
- **Plugin git hooks survive updates**, and plugin installs get `pre-commit` too. The links go
  through the plugin's data directory, re-pointed at the running version each session. They lead to
  Nonna's own scripts, never scripts a repository ships. A dangling link of Nonna's is repaired; a
  foreign hook, a hook manager and a hook that points at nothing are reported, never overwritten.
- In full mode, when another enabled plugin already states the "reuse before you write" ladder, the
  constitution's copy is left out (`NONNA_LADDER=on|off` decides it yourself).
- **"Done" means the suite passes.** In the benchmark, agents said "done" on a broken suite in 16 of
  16 bare runs and most harnessed ones: nothing deterministic ran the tests. Now the Stop hook and
  the pre-push hook run the project's own test command (pytest, npm, go or cargo, detected; or
  `NONNA_TEST_CMD`) whenever code changed, and refuse on red. `hooks/lib/tests.sh` holds it.
  Detection runs at every turn end only in a copy-in install; the plugin records what it detects
  once per repository, with consent (above). A green tree is not re-tested at every turn end, a Stop-time timeout does not
  block, and the pre-push gate reads the pushed range from git, so a branch's first push is gated.
  The push scan covers every commit the remote lacks, one diff per commit, so a key in a local-only
  base commit, or one added and removed inside the push, is caught; colour, external-diff config and
  non-ASCII names no longer hide a line. Merge resolutions are scanned too, a URL push is judged
  against that URL, a failed `git log` blocks, a shallow clone's graft is excluded, and the scan is
  one pass over the push rather than one history walk per file. Added lines are found by position,
  not text (octopus merges, content starting `++ `), `log.showRoot=false` cannot hide a root commit,
  and a shallow boundary the destination may lack blocks the push. A remote named `origin/fork` no
  longer counts as `origin`, and a tag on a blob or tree is refused rather than pushed unscanned.
- **One-command install** (`install.sh`, `--host` for eight agent hosts), host rules generated from
  `00-core.md` (`hosts/build.py`, drift-linted), and a git `pre-commit` hook every host gets.

### Changed

- **The STATUS gate is full mode's**, and only where `docs/STATUS.md` exists, at Stop and at
  pre-push. A repository that never kept the file is no longer blocked for not updating it; one that
  keeps it cannot throw it out.
- **The host rules say exactly what the git hooks refuse**: a commit on a protected branch. They
  had claimed the git hooks refused the push itself, which only Claude Code's branch guard does.
- **`docs/INSTALL.md` leads with the plugin**, and says what Nonna changes on your machine and how
  to take it back out.
- **2.0 packaging.** Both manifests say 2.0.0. The plugin shows as "Nonna" in `/plugin` and asks
  two things at install: whether to run the project's tests (`run_tests`, default on) and the
  default mode (`mode`, default lite), and the hooks read both (above). The marketplace and plugin carry descriptions, a category and
  keywords, and `claude plugin validate --strict` passes on both, now in CI. Every hook command
  quotes its root (`"${CLAUDE_PLUGIN_ROOT}"/...`, `"$CLAUDE_PROJECT_DIR"/...`), so a path with a
  space no longer splits and silently skips the gate; the linter holds both files to it. While the
  Stop hook runs your tests the spinner says so. Issue templates (false block, missed, bug, new
  agent) and a code of conduct.
- **Security review of the installer and the new hooks.** `install.sh` merges into an existing
  `.claude/`, never writes through a symlink, chmods only what it copied, and exits non-zero rather
  than linking a git hook to a missing script. `pre-commit` reads staged file names literally and
  binary-safe (type changes included), and fails closed when git cannot diff. The Stop hook's no-jq
  output is valid JSON. The macOS timeout fallback kills the suite's whole process group. The
  installer says so when your kept `.claude/settings.json` leaves Nonna's hooks unwired.
- **Keel is now Nonna** (ADR-0010). The plugin id is `nonna@nonna`, environment variables are
  `NONNA_*` (for example `NONNA_CRITICAL_PATHS`), and gate messages open with a line in her voice
  before the technical reason. Reinstall the plugin under the new id.

### Added

- **Proportional review** (ADR-0009). `skills/review/scripts/review-lanes.sh` decides how much
  review a diff buys: a diff the fast-lane classifier accepts gets one `code-reviewer` on the
  cheaper tier, and the security reviewer runs only when a changed path or added line touches a
  risky surface, on added or removed lines, in any file name, from any directory. It fails closed
  to full review with security. `/review` itself and `/fix`'s single
  reviewer move to the cheaper tier. Small changes start in `/fix`; off the critical surface, one
  test that would have failed before is enough.
- **Optional findings are named by the gate.** A verdict finding may carry `adds_code` and
  `failing_input`. On approve, `check-review.sh` lists each adds-code finding with no failing input
  as `optional:`, and the implementer leaves it. Exit codes unchanged.

- **The decision ladder** (ADR-0008). `rules/00-core.md` now says, in seven rungs, how much code
  to write: YAGNI, already in this codebase, stdlib, native platform, installed dependency, one
  line, only then the minimum that works. It lives in the constitution because that is the one rule
  a plugin install receives. Always-on prose 3,599 → 3,690 words (with the review-inflation rule
  below), budget unchanged.
- **`debt:` markers and `check-debt.sh`.** A `debt: <ceiling>, <upgrade trigger>` comment marks a
  deliberate corner; the new gate under `skills/lean/scripts/` fails closed on a marker with no
  trigger, `--range` gates only the lines a PR adds, `--ledger` prints the ledger. `/review` runs
  it on the diff, `/sync` prints the ledger.
- **`lean` skill** (preloaded into `implementer`) and **`/audit`** (repo-wide over-engineering
  sweep, read-only).
- **`category: simplicity`** in the review verdict, capped at MEDIUM — over-engineering never blocks
  a merge alone (ADR-0005 amended; `check-review.sh` unchanged).
- **`SubagentStart` → `subagent-start.sh`.** Under a plugin install, subagents now receive
  `00-core.md`; `SessionStart` context was parent-only, so they had been running with no policy.
  Standalone checkouts emit nothing (subagents load `rules/` natively). `hooks/lib/core.sh` holds
  the shared harness-root resolution, carrier and emitter.
- **Three lint checks** with failing-case tests: the seven rung keywords in both ladder copies;
  `/review` and `/sync` wire `check-debt.sh`; an adapted project's name appears only in `README.md`.
- **Automated releases.** Pushing a `v*` tag publishes the GitHub Release with notes read from this
  file (`.github/workflows/release.yml`). It refuses to publish when the version's section is
  missing or empty, or when the tag disagrees with the plugin manifests.
- `.github/scripts/release-notes.sh` — the notes extractor, golden-tested like every other gate;
  a version matches literally, so `1.0.0` cannot select a `1x0x0` section.

### Changed

- **README says what Nonna is and why**, with Nonna measured against a bare agent, not against its
  own previous version; the architecture detail (token economy, layers, crew, gates,
  repository tree) lives verbatim in the new `docs/OVERVIEW.md`, and the bare-agent-vs-Nonna
  benchmark is a chart.
- **A review ask that adds code must name a failing input** (ADR-0008, amended). The severity
  rubric, `code-review`, `code-reviewer`, `implementer` and `dev-process.md` §4 ("fix MEDIUM when it
  names a failing case; one that only adds code without one gets a `debt:` marker instead")
  all carry it, pinned by two lint checks. Found by the first ladder eval, where the review loop turned
  a six-line check into 25 lines.
- `engineering.md` Simplicity now names what is never simplified away and the `debt:` marker;
  "Reuse over rewrite" folded into `dev-process.md` §0; **Remaining risk** now includes what was
  deliberately skipped and the trigger to add it. `code-review` gains a Complexity checklist;
  `debugging` and `debugger` gain the grep-every-caller root-cause rule; `planner`/`/plan` ask rung
  one first; `test-engineer` applies the ladder to test code without cutting the test.
- The no-jq fallback of the SessionStart emitter now escapes its payload — a multi-line carrier
  was not valid JSON without jq.
- **The banner carries no version and no licence.** `assets/nonna-banner.svg` hardcoded `v0.1.0` and
  `MIT` — the version was two releases stale and nobody noticed, which is the argument against
  putting expiring facts in a hand-edited image. The `License` and `release` badges are gone from the
  README header for the same reason. The live version lives in `CHANGELOG.md` and the manifests; the
  licence lives in `LICENSE`.

### Fixed

- **`subagent-verdict.sh` graded the wrong transcript and blocked the wrong verdicts** (#7). The
  SubagentStop gate read `transcript_path`, which for that event is the _parent_ session's
  transcript — so `check-review.sh` ran against the orchestrator's prose and rejected every
  reviewer verdict as "not valid JSON". It now reads `last_assistant_message` (the subagent's final
  text; the hooks reference names it as the source because the transcript file may lag), falls
  back to the last assistant text in `agent_transcript_path`, and never touches the parent
  transcript — if neither field is present it fails open with a stderr note, since grading the
  parent can only produce a false verdict. It also blocked on _any_ non-zero checker exit; only
  exit 2 (no verdict, unparseable, ambiguous) is a breach of the contract, while exit 1 is a
  well-formed `request_changes` or a blocking finding — the reviewer doing its job, which `/review`
  and `/ship` turn into a red gate. **Behaviour change:** an approve carrying a CRITICAL finding no
  longer bounces the reviewer; it stops, and the downstream checker on the same text still exits 1.
  And it honours `stop_hook_active`, so a reviewer that cannot produce the contract is sent back
  once, not forever. The `tests/run.sh` section is rewritten (24 checks, 8 red against the old
  hook); the old section had pinned the bug by feeding `transcript_path`.

## [1.0.0] — 2026-08-01 — "The Model Cannot Ship Itself"

The first GitHub release. `v0.1.0` was tagged but never released; `v0.2.0` was neither tagged nor
released, and the manifests claimed it against no artifact. This is the first real one.

### ⚠️ Breaking

- **`.claude/commands/` no longer exists.** All 14 pipeline workflows moved to
  `.claude/skills/<name>/SKILL.md`. Claude Code merged custom commands into skills, and only skills
  support invocation control, bundled supporting files, and `context: fork`. Every `/name` still
  works exactly as before — but anyone who copy-installed a v0.2-era `.claude/` and pulls these files
  in piecemeal must delete their `commands/` directory, or the same `/name` will resolve twice.
- **The always-on rule set changed shape.** A new `.claude/rules/00-core.md` is now the constitution
  the other eight rules elaborate; `CLAUDE.md` dropped from 836 to 234 words. If you have local edits
  to `CLAUDE.md` or the rules, re-apply them against the new structure rather than merging blindly.

### Added

- **`Stop` gate** (`stop-dod.sh`) — a turn cannot end with tracked code changed and `docs/STATUS.md`
  untouched. The pre-push Definition-of-Done gate fired too late; by push time the agent had usually
  declared "done" several turns earlier. Deliberately narrow: reading, planning, doc-only edits and
  untracked scratch all end freely, and it fails **open** outside a git repo.
- **`SubagentStop` gate** (`subagent-verdict.sh`) — runs the existing `check-review.sh` against the
  reviewer's own output, so ADR-0005's machine-checkable verdict binds where the verdict is
  _produced_, not several steps later. A reviewer returning prose is now caught immediately.
- **`PostCompact` hook** (`post-compact.sh`) — restates branch, HEAD, uncommitted count, STATUS state
  and whether review verdicts exist for the current SHA. Compaction keeps the narrative and drops the
  bookkeeping, which is exactly the state the gates key on.
- **`rules/00-core.md`** — the constitution, and the only thing a plugin install receives. Budgeted
  under 9,000 characters so it fits the 10,000-character `SessionStart` channel.
- **`CHANGELOG.md`** (this file) and **ADR 0007**.
- Agents gained `skills:` preloading (`code-reviewer` ← `code-review`, `security-reviewer` ←
  `security-review` + `code-review`, `debugger` ← `debugging`, `test-engineer` ← `tdd-workflow`),
  plus `effort:` and `maxTurns:`.
- `fable` accepted as a model tier.

### Changed

- **Six workflows are human-only.** `/ship`, `/release`, `/rollback`, `/adr`, `/sync` and `/intake`
  set `disable-model-invocation: true`. Claude cannot trigger them, and their descriptions leave the
  context window entirely. `rules/safety.md` always said a human approves promotion to production;
  this makes it a mechanism instead of a request, and the linter asserts it.
- **Always-on context down ~24%**, ~9.1k → ~6.9k tokens per turn: prose 4,252 → 3,599 words,
  description metadata 6,952 → 4,389 characters. Every cut removed content that was stated two or
  three times _within the always-on surface itself_.
- Budgets tightened and newly enforced: `CLAUDE.md` 900 → 300 words, per-rule 700 → 520, total
  always-on 4,500 → 3,700, plus new caps on `00-core.md` size and total description metadata.
- Golden tests 78 → 136. `harness_lint.py` grew roughly 13 → 22 distinct checks.
- `docs/INSTALL.md` no longer claims the two install paths "end with the same harness". They do not.

### Fixed

- **The Definition-of-Done gate was silently absent under a plugin install.** `session-start.sh`
  guarded the pre-push install on a project-relative path that does not exist there, so it no-opped
  without a word. It now resolves from `${CLAUDE_PLUGIN_ROOT}` and **warns** when it can locate
  neither source. This was the one true fail-open in the harness.
- **Gate scripts were unreachable under a plugin install.** `/review`, `/ship` and `/fix` invoked
  `check-review.sh` and `check-trivial.sh` through hardcoded `.claude/skills/…` literals.
  `SessionStart` now announces the resolved harness root. (These failed _closed_ — exit 127 blocks
  the ship — so the commands were unusable rather than unsafe.)
- **Four workflows could not run their own instructions.** `allowed-tools` is a pre-approval grant,
  so a missing entry halts for approval interactively and is denied outright in non-interactive runs.
  `/ship` lacked `git add` and any branch verb; `/release` lacked `git push` while its step 4 says
  "Push the tag"; `/adr` lacked `Edit` while its step 3 says "Link it from the ADR index";
  `/rollback` lacked a branch verb.
- **ADR-0006 asserted that `rules/` is a plugin component.** It is not — Claude Code's plugin schema
  has no `rules` component — so a plugin install loaded none of the operating discipline. Superseded
  by ADR-0007; `session-start.sh` now carries `00-core.md` through `additionalContext`.
- `harness_lint.py` rejected `fable`, blocking adopters from using a current model tier, and its
  calibration comment was stale.

### Known limitations

- A plugin install still receives only `00-core.md`, not the full rule set, and cannot inherit
  `settings.json` permissions. Both are documented in `docs/INSTALL.md` with a copy-in remedy.
- The plugin-path fixes are proven by golden tests that simulate `CLAUDE_PLUGIN_ROOT`, **not** by an
  observed `/plugin install`.
- Still open: a statusline, orphan detection in the linter, a markdownlint CI job, and a
  behavioural eval on the failures the gates exist for.
- Persistent agent `memory:` was evaluated and **deliberately rejected** — it is LLM-authored state
  that steers future sessions with no gate in front of it, which `boundaries.md` forbids. Adopting it
  requires an ADR and a validation gate first.

## [0.2.0] — 2026-06-23 — "Gates as Code" (never tagged)

Turned prose discipline into blocking scripts: `guard-branch.sh`, `secret-scan.sh`, the pre-push
Definition-of-Done hook, the machine-checkable review verdict (ADR-0005), the `/fix` bounded fast
lane, stack packs for python/typescript/go/rust, and plugin distribution (ADR-0006).

## [0.1.0] — 2026-06-22

Initial harness: rules, agents, skills, commands, and the development loop — described, not yet
enforced.

[1.0.0]: https://github.com/kapadias/nonna/releases/tag/v1.0.0
[0.1.0]: https://github.com/kapadias/nonna/releases/tag/v0.1.0
