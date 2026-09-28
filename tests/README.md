# Nonna self-tests — the harness held to its own bar

Nonna's thesis is _deterministic gates decide_. A harness that preaches gates must
**prove its own gates fire** — otherwise it is the very "green suite that asserts
nothing" it warns against ([ADR 0002](../docs/adr/0002-llm-proposes-gates-decide.md)).
These tests are [`boundaries.md`](../.claude/rules/boundaries.md) applied to Nonna
itself: if a gate is silently wrong, CI goes red.

## What runs

| File                                 | What it proves                                                         | How                                            |
| ------------------------------------ | ---------------------------------------------------------------------- | ---------------------------------------------- |
| [`run.sh`](run.sh)                   | **Every gate blocks vs. allows correctly** — gate golden tests.        | golden tests over real hook/script invocations |
| [`harness_lint.py`](harness_lint.py) | **The harness is internally consistent** — structural self-validation. | static checks over `.claude/` + docs           |

### `run.sh` — gate golden tests

Exercises each deterministic gate with fixed inputs and asserts the exit code:

- **secret detection** (`lib/secret-patterns.sh`): catches AWS/GitHub/Slack/Google/Stripe/OpenAI
  keys and hardcoded assignments; ignores placeholders and env-var refs.
- **secret-scan** (PreToolUse): blocks a write that introduces a secret and Bash
  reads/copies of secret files (segment-anchored, jq-independent); allows clean
  writes and sample secrets under `test/fixture/example` paths.
- **guard-branch** (PreToolUse): blocks `git commit`/`git push` on `main`/`master`/
  `develop` and `+refspec` force pushes (scoped to the push segment); allows work on
  a feature branch.
- **require-status-sync** (pre-push): blocks a code push without a `docs/STATUS.md`
  update or that introduces a secret (no fixture exemption at push time); allows a
  synced push.
- **session-start**: emits context, auto-installs the pre-push hook, and warns
  instead of overwriting a foreign one.
- **check-review** (review verdict gate): blocks on `request_changes`, any
  CRITICAL/HIGH, or an out-of-schema verdict/severity; extracts one fenced json
  block; fails closed on invalid JSON — same on the jq and no-jq paths.
- **check-review, optional findings** (ADR-0009): an approving verdict lists each MEDIUM/LOW
  finding whose fix adds code with no failing input as `optional:`; a named input or a
  non-code fix is not listed; the exit code never changes.
- **check-trivial** (fast-lane eligibility): qualifies a small reversible change;
  disqualifies over-budget, lockfile, critical-surface, and rename-into-critical
  changes; fails closed off a repo.
- **review-lanes** (review proportionality, ADR-0009): a fast-lane-sized, ordinary diff takes the
  light lane with no security review. Risky added **or removed** code (Python, Go, Node shell calls,
  a deleted auth check), a deleted risky file, a dependency manifest, harness markdown, a
  `NONNA_CRITICAL_PATHS` match, a non-ASCII file name, a subdirectory cwd and an untracked symlink
  all end in security review. No `develop`/`main` base, a bad base, no repo, a missing classifier
  or a legacy `KEEL_CRITICAL_PATHS` alone fail closed.
- **dep-audit** (supply-chain): exits non-zero when a required scanner is missing
  (a skipped scan is not a pass).
- **tests say no** (Stop and pre-push): when code changed, both run the project's own test
  command (detected, or `NONNA_TEST_CMD`) and refuse on red; the Stop hook blocks once, then lets
  an agent that cannot fix it stop and say so.
- **stop-dod** (Stop): blocks a turn ending with tracked code changed and
  `docs/STATUS.md` untouched; lets doc-only edits, untracked scratch, and a clean
  tree end freely; fails **open** outside a git repo, because a Stop hook that
  errors would wedge every turn.
- **subagent-verdict** (SubagentStop): runs `check-review.sh` against the
  reviewer's own last message, so ADR-0005 binds where the verdict is produced;
  blocks prose-instead-of-verdict and an `approve` carrying a CRITICAL finding;
  fails **open** when it cannot read the transcript, since `/review` still runs
  the real gate.
- **post-compact** (PostCompact): restates branch, STATUS state, and whether
  review verdicts exist for the current SHA after a summary.
- **subagent-start** (SubagentStart): carries `00-core.md` into a subagent under
  a plugin install (valid JSON with and without jq, never waits on stdin); emits
  nothing in a standalone checkout; fails **open** when the harness cannot be
  located.
- **check-debt** (debt-marker gate + ledger): a `debt:` marker with no upgrade
  trigger after the comma fails closed; `--range` gates only lines a PR adds;
  `--ledger` groups by file and tags `no-trigger`; skips dependency dirs and
  markdown; fails closed on an unknown flag, outside a repo, or on a bad range.
- **format.sh** (PostToolUse, best-effort): exits 0 even when no formatter for
  the file's language is present on `PATH` — formatting never blocks the edit.
- **bypass-resistance** (review-finding regressions): a trailing placeholder
  word cannot smuggle a real key past value-level matching; AWS's own
  `…EXAMPLE` key stays exempt; the secret gate fails **closed** when `jq` is
  absent; the path allowlist is segment-anchored, so a `latest_config.py` is
  not exempted by a `test` substring; `guard-branch` tolerates `git -C`,
  absolute-path `git`, and blocks `push --all` and a qualified
  `refs/heads/main` push; `subagent-verdict` fails **open** on an unreadable
  or missing transcript, since `/review` still runs the real gate.
- **release-notes.sh** (the release gate, nine golden tests): extracts an
  existing version's section, keeps the markdown headings `git tag -F` would
  strip, leads with a breaking change, and stops at the next version with no
  bleed; fails closed on an absent version, an empty version, a missing
  changelog, a whitespace-only section, and a version matched literally
  rather than as a regex.
- **harness_lint itself** — see below.

### `harness_lint.py` — structural self-validation

Fails the build on: read-only agents granting mutating tools, invalid model tiers
or effort levels, an agent preloading a `skills:` entry that does not exist,
skills missing a trigger, a side-effecting workflow that does not set
`disable-model-invocation`, a skill body running a `git` verb its
`allowed-tools` does not grant, a `/name` that resolves to no skill,
wired hooks absent on disk, `settings.json` and `hooks.json` disagreeing about
which gates are wired, dead intra-repo markdown links, backticked `docs/`
references that do not exist, domain-specific vocabulary in a domain-agnostic
harness, malformed plugin manifests, five token budgets (CLAUDE.md, per-rule,
total always-on, `00-core.md`'s SessionStart-channel size, and the combined
skill/agent description metadata), a ladder rung missing from either of its two
copies, `/review` or `/sync` no longer wiring `check-debt.sh`, the review-inflation
rule dropping out of `dev-process.md` or the severity rubric, and an adapted
project's name anywhere but `README.md`.

### The linter is itself a gate

A linter with no failing-case test is an unverified gate: it would still print
`OK` if a check silently stopped firing — the same unwired-gate defect ADR-0005
exists to prevent, one level up. `NONNA_LINT_ROOT` retargets the linter at a
different tree so `run.sh` can copy the repo, break exactly one thing, and assert
it is caught. CI never sets the variable.

Each case proves a specific check bites: an unknown model tier is rejected and
named, an unresolved `/name` is caught, a skill name **is** accepted as a slash
reference, the word and description budgets block bloat, `00-core.md` outgrowing
the 10,000-char `SessionStart` channel is blocked (it truncates silently rather
than erroring), unwiring `check-review.sh` from `/ship` is blocked citing
ADR-0005, a desynced `hooks.json` is blocked, and stripping
`disable-model-invocation` from `/release` is blocked with a message pointing at
`rules/safety.md`.

## Run it

```bash
bash tests/run.sh        # gate golden tests  (exit non-zero on any failure)
python3 tests/harness_lint.py   # structural self-validation
```

Both run in CI on every push and pull request (`.github/workflows/ci.yml`),
alongside `shellcheck` over every script and `claude plugin validate --strict` on both
manifests. Adopters wire their own
lint/type/test/coverage gate as additional jobs — see [`stacks/`](../stacks/).
