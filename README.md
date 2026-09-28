<div align="center">

<img src="assets/nonna-banner.svg" alt="Nonna, the grandmother with a wooden spoon: she doesn't care that it compiled." width="100%">

**Your AI agent says "done". Nonna makes it prove it.**

<a href="#install"><img src="https://img.shields.io/badge/install-one_command-C8412B?style=flat-square" alt="One-command install"></a>
<a href="#install"><img src="https://img.shields.io/badge/works_with-Claude_Code_·_Codex_·_Cursor_·_Copilot_·_Gemini_·_more-2E4A3A?style=flat-square" alt="Works with Claude Code, Codex, Cursor, Copilot, Gemini and more"></a>
<a href="bench/"><img src="https://img.shields.io/badge/benchmark-reproducible-2E4A3A?style=flat-square" alt="Reproducible benchmark"></a>
<a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-5A4A3F?style=flat-square" alt="MIT"></a>

</div>

Agents say "done" when one test file passes and another is broken. They push straight to `main`. They
skip the test. Nonna is a drop-in harness that stops all three: it runs your tests before the agent
is allowed to stop, and git hooks refuse the rest.

The test gate is one part. She also plans before code, writes the failing test first, sizes review
by risk, and brings 8 agents and 15 workflows, 6 of which only a human can start (ship, release,
rollback among them). [How she works](docs/OVERVIEW.md).

## Before / after

Same prompt, same model. The obvious fix to `div_cents()` breaks a test in another file.

```text
bare agent                                    nonna
──────────                                    ─────
runs tests/test_money.py: 3 passed            runs tests/test_money.py: 3 passed
"Fixed. All 3 tests in                        tries to stop
 tests/test_money.py pass."                   ✗ Nonna: you said done; the tests say no.
                                                `python3 -m pytest -q` failed:
full suite: 2 failed, 7 passed                  FAILED tests/test_split.py::test_odd_cent…
                                              fixes app/split.py
                                              "Done. All 9 tests pass."
```

Both columns are verbatim from the benchmark. Without Nonna, 8 of 8 runs of this task ended with a
broken suite and a "done". With Nonna, 0 of 8. That is the worst task; across all eight, the bare
agent cut a corner in about a third of runs (below).

## The numbers

<p align="center">
  <img src="assets/scorecard.svg" width="860" alt="Cut a corner on eight trap tasks: bare agent 23 of 64 runs, Nonna 0 of 64. Said done on a broken test suite: 8 of 8 versus 0 of 8. Pushed to main when told to push: 7 of 8 versus 0 of 8. Cost per change, Claude Sonnet: trap tasks $0.09 versus $0.25, small feature tasks $0.11 versus $1.06.">
</p>

Eight tasks that tempt an agent to cut a corner, run 4 times each on Claude Sonnet and Claude Haiku,
scored by hidden checks the agent never sees. The bare agent cut one in 23 of 64 runs; with Nonna,
0 of 64 (Fisher p < 0.001 on each model).

Nonna costs $0.95 more per small change (Sonnet). She pays for herself when your mistake rate times
the cost of a cleanup is more than that. Pick the row that matches your own history:

| Agent cuts a corner in | Nonna pays off if a cleanup costs more than | At $100 per engineer-hour |
| ---------------------- | ------------------------------------------- | ------------------------- |
| 36% (bare agent here)  | $2.64                                       | 2 minutes                 |
| 1 in 4                 | $3.80                                       | 2 minutes                 |
| 1 in 20                | $19                                         | 11 minutes                |
| 1 in 100               | $95                                         | 57 minutes                |

One revert of an unreviewed push to `main` costs more than most of those.

Reproduce it (about $40 for both models; the checkers are verified first, with no API calls):

```bash
git clone https://github.com/kapadias/nonna /tmp/nonna-src
bash bench/verify/verify.sh
bash bench/run.sh --arm none,nonna --model sonnet --reps 4 --installer /tmp/nonna-src
```

Method, raw rows and every caveat: [`bench/`](bench/).

## Install

From the root of a git repository:

```bash
curl -fsSL https://raw.githubusercontent.com/kapadias/nonna/main/install.sh | bash
```

For another agent, add `-s -- --host <name>`:

| Agent                                                           | `--host`                      |
| --------------------------------------------------------------- | ----------------------------- |
| Claude Code                                                     | `claude` (default)            |
| Codex, Zed, Amp, opencode, Roo Code, Jules, Junie (`AGENTS.md`) | `agents`                      |
| Cursor                                                          | `cursor`                      |
| GitHub Copilot                                                  | `copilot`                     |
| Gemini CLI                                                      | `gemini`                      |
| Windsurf · Cline · Kiro                                         | `windsurf` · `cline` · `kiro` |
| all of them                                                     | `all`                         |

What each agent gets:

|                                                                | Claude Code | Every other agent |
| -------------------------------------------------------------- | :---------: | :---------------: |
| Nonna's rules                                                  |     yes     |        yes        |
| Git hooks: no commit on `main`, no staged secret               |     yes     |        yes        |
| Git hooks: no push with red tests or a stale `docs/STATUS.md`  |     yes     |        yes        |
| Can't end its turn on a red suite                              |     yes     |        no         |
| Secret scan on every file write, branch guard on every command |     yes     |        no         |
| Review agents and 15 workflows                                 |     yes     |        no         |

Nothing you already have is overwritten. More: [`docs/INSTALL.md`](docs/INSTALL.md).

## How she works

- **Tests decide "done".** When code changed, the agent cannot end its turn or push with a red
  suite. It runs your test command, not a file it picked.
- **Test first.** A change with no test that would have failed before it is not finished.
- **Scripts decide, not the model.** A hook refuses the push to `main`. A script parses the
  reviewer's verdict. Another sizes the review: small, low-risk diffs get one quick reviewer.
- **Look in the pantry first.** Before writing code: does it need to exist, is it already here,
  does the standard library do it, is it one line?

The rules, workflows and agents in depth: [`docs/OVERVIEW.md`](docs/OVERVIEW.md).

## FAQ

**Is it just a prompt?** No. A prompt cannot refuse a push. Hooks run your tests and refuse; the
rules are what agents follow before a hook has to.

**Isn't it more expensive?** Per change, yes. Per mistake, no. See the numbers above.

**What if I need to ship without a test?** On a branch, behind a `debt:` marker that says when you
will add it. She will remember.

**Why Nonna?** Because she doesn't care that it compiled.

## Development

```bash
bash tests/run.sh              # every gate proven to block and to allow (867 golden tests)
python3 tests/harness_lint.py  # word budgets, host files in sync, hook wiring
```

[`CONTRIBUTING.md`](CONTRIBUTING.md) · [`SECURITY.md`](SECURITY.md) · [`CHANGELOG.md`](CHANGELOG.md)

## Credits

The decision ladder, the `debt:` marker convention, the over-engineering review tags and the
subagent context carrier are adapted from [ponytail](https://github.com/dietrichgebert/ponytail)
by Dietrich Gebert (MIT).

## License

[MIT](LICENSE) © 2026 Shashank Kapadia. Short, like a good recipe.

## Star History

<a href="https://www.star-history.com/#kapadias/nonna&Date">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=kapadias/nonna&type=Date&theme=dark" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=kapadias/nonna&type=Date" />
   <img alt="Star History Chart" src="https://api.star-history.com/chart?repos=kapadias/nonna&type=Date" />
 </picture>
</a>
