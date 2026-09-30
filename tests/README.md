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
| [`test_assets.py`](test_assets.py)   | **The launch images match the data** — numbers, lettering, SVGs.       | unit tests, standard library only              |

### `run.sh` — gate golden tests

Exercises each deterministic gate with fixed inputs and asserts the exit code:

- **secret detection** (`lib/secret-patterns.sh`): catches AWS/GitHub/Slack/Google/Stripe/OpenAI/
  Anthropic keys and hardcoded assignments; ignores placeholders, env-var refs, key prefixes in
  prose and short samples. A property test holds the tail bound for every prefixed key.
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
- **Copilot CLI plugin** (`hooks/copilot-hooks.json`, `lib/host-copilot.sh`, ADR-0012): each gate
  runs as Copilot's hooks file wires it, on Copilot's documented payloads. `git commit` on `main`, a
  new file holding a key, an edit of `.git/config`, a view or grep of `.env`, an `apply_patch` that
  adds a key, and a command sent to a running shell are refused, the reason in Copilot's
  `permissionDecisionReason`; a clean edit and a clean patch pass; `agentStop` on a red suite blocks,
  once; session start records the test command and the session's start, wires the git hooks, and
  answers in `additionalContext`. A Claude-named decoy beside Copilot's own key never stands in for
  it, and a grep over several paths is judged path by path. An equivalence test runs Claude Code's
  own Write, Edit, Read and Grep goldens rewritten in Copilot's names, and every order of a
  several-path grep, and wants the same exit codes. Writes to Copilot's repository settings and hooks
  are refused under either agent. A Claude Code payload passes the adapter byte for byte, nothing is
  translated without `NONNA_HOST=copilot`; without jq, what the text cannot show safely is refused,
  and so is JSON jq cannot translate. A copy-in install's hooks under Copilot are pinned as they are
  (untranslated). The hooks file, the manifests, and every command run from a path with a space are
  checked too.
- **assets/build.py** (the launch images): `run.sh` runs `test_assets.py`, then drives `--check` on
  the standard library alone (`python3 -I -S`, as CI's lint job would). It passes on the real
  tree, and on a copy that has had exactly one thing broken it fails, naming the file: an SVG
  edited by hand, data that moved without a rebuild, a `traps.tsv` that disagrees with
  `summary.json`, and a PNG that is missing, not a PNG, the wrong size, over the 1 MB budget or
  rendered from a different SVG. A plain run rewrites the SVGs byte for byte; `--render` fails
  without a browser, on a browser that fails or draws the wrong size, and with a stand-in browser
  it renders and then passes `--check`.
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

### `test_assets.py` — the launch images

`assets/build.py` builds the scorecard, the social preview and one card per trap task from
`bench/results/round3`. Its tests hold the numbers to the verified round-3 values (bare agent 24 of
64, Nonna lite 1 of 64; per task; Sonnet's mean cost) and to a tiny fixture, refuse data that
disagrees with itself, find the `✗ Nonna` line in a hook response or a tool result, and lay text
out from the committed glyph outlines. The banner's own lettering is the oracle: "nonna", the
tagline, a pill and the footer come out of the same JSON **to the digit**, so the font and its
weights are pinned rather than eyeballed.

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
python3 tests/test_assets.py    # the launch images (run.sh runs it too)
```

Both run in CI on every push and pull request (`.github/workflows/ci.yml`),
alongside `shellcheck` over every script and `claude plugin validate --strict` on both
manifests. `run.sh` also runs on a macOS runner under `/bin/bash` 3.2 with only Apple's tools on
the PATH (no Homebrew), because the guards parse shell in bash and awk and those differ from
Linux's. Adopters wire their own
lint/type/test/coverage gate as additional jobs — see [`stacks/`](../stacks/).
