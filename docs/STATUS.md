# STATUS — Nonna

The living status of the Nonna harness itself. Adopters mirror this file for their own project; the
pre-push hook (`require-status-sync.sh`) blocks code pushes that leave it stale.

## Current state

Nonna's discipline is enforced by code at seven lifecycle events plus the git pre-commit and
pre-push hooks. The harness tests its own gates and its own linter. The seven workflows with side
effects (`/ship`, `/release`, `/rollback`, `/adr`, `/sync`, `/intake`, `/nonna`) are
human-triggered only.
One switch per repo sets the mode (`off | lite | full`, ADR-0011). A plugin install defaults to
lite: the test gate, the branch and secret guards, and six house rules carried into the session and
every subagent; full carries the constitution (`00-core.md`) and adds the STATUS gate. Language-
and domain-agnostic.

Always-on surface: **3,681 words** of prose (3,700-word budget) plus 4,684 chars of skill/agent
descriptions (5,600-char budget), both enforced by the linter. A user-only skill's description is
never offered to the model, so it is not counted.

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
- **Pipeline workflows ×16** — also under `skills/`, since Claude Code merged commands into skills:
  `/plan`, `/tdd`, `/implement`, `/review`, `/audit`, `/test`, `/coverage`, `/debug`, `/fix`,
  `/ship`, `/release`, `/rollback`, `/sync`, `/adr`, `/intake`, and `/nonna`, the user's switch for
  her gates. Model-tiered; several use `!`/`@` injection. The seven with side effects set
  `disable-model-invocation: true` — human-triggered only, and out of context entirely.
- **Hooks ×10** — each reads the mode first; `off` is silent, but for the branch guard, which still
  keeps her settings. `guard-branch` (blocks protected-branch commits/pushes, `--all`/`--mirror`,
  force pushes, `--no-verify`, hook-path overrides, the agent's writes to Nonna's own git config,
  and its runs of her `/nonna` scripts), `secret-scan` (blocks secret writes + reads of secret
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
- **Launch images** — `assets/build.py` builds the scorecard, the social preview and one card per
  trap task from round 3's files; `--check` (standard library only) is run by `tests/run.sh`.
- **CI** — `.github/workflows/ci.yml`: shellcheck (all scripts) + harness-lint + gate self-tests
  (on Linux, and again on a stock Mac) + plugin manifest (`claude plugin validate --strict`, pinned
  CLI). Every action is pinned to a commit SHA, the token is read-only by default, and only the
  release job can write.

## Recently changed

History lives in `CHANGELOG.md` and `git log`. Entries here describe the current unit of work.

- **2026-09-29** — The launch, the fifth unit of the launch plan (#17), from round 3's numbers.
  - **README:** the plugin install first, what the first session prints, what she checks, the
    modes (full mode as extras for teams, as D3 row 4 requires), a before/after from the
    rule-picked round-3 runs, her voice lines as the hooks print them, the numbers with their
    misses, and a FAQ that says how an agent can still get past her. Every benchmark number carries
    a mark (`<!--n:key-->`) that `harness_lint.py` checks against `bench/results/round3/*.tsv`.
  - **`install.sh` installs lite** unless told `--mode full`, as D3 row 1 decided; re-running it
    keeps the mode a repository has, and no longer mistakes her own git hooks for the user's.
  - **`examples/`:** one run of each trap per arm, word for word, picked by a rule in code
    (`bench/examples.py`, rep 1 on Haiku); `--check` runs with the gate self-tests.
  - **Images:** `assets/build.py` builds the scorecard, the social preview and a card per trap task
    from the rows, lettered from Space Grotesk's own outlines (OFL); `--check` fails on a stale
    image. The demo (`assets/demo.{gif,mp4,cast}`, `docs/demo.md`) is a real Haiku session, 4
    takes, take 4 used; it shows her "where's the test?" block, not a failing-test block. A
    split-screen film (bare against Nonna, every pair recorded) is being finished on its own branch
    (`chore/17-demo`) and lands as its own PR.
  - **Docs:** INSTALL, OVERVIEW and CONTRIBUTING reordered for the plugin and cleared of em dashes;
    `bench/README.md` has round 3's results and a new break-even table; CHANGELOG 2.0.0 opens with
    the release notes' five lines; ADR 0011 records what round 3 decided.
  - **Fixes found on the way:** a staged binary file drew a shell warning from the pre-commit hook;
    a lite install switched to full carried no rules at all. Both have golden tests.
  - **Review fixes** (the code and security review of this unit), each with a test that failed
    first:
    - on a Mac the pre-commit hook blocked every commit with a binary file (`tr` read the bytes in
      the user's locale); its fail-closed path, never reached by the old test, is now;
    - the plugin no longer formats the files the agent edits; a copy-in install still does;
    - `install.sh`: the stack packs pre-approve test, lint, format and type-check runners only, say
      so, and are git-ignored; a git hook it could not wire is a non-zero exit; a recorded mode
      that is neither lite nor full reads as full;
    - the bench's copy-in arm passes `--mode` only to an installer that knows it;
    - the pooled Fisher p is 1.3e-7, not 9.4e-6; lite's one miss is described as far as the rows
      go; every benchmark number in the README is linted, and the scorecard's alt text is the
      image's own;
    - `assets/build.py` renders nothing that runs or reaches outside the file, `bench/examples.py`
      never writes through a symlink, and the key-class messages read "an AWS access key id".
  - **Second and third review rounds** (each approved the one before with findings; each fix has a
    test that failed first):
    - the stack packs pre-approve only the exact commands their gate runs, never a prefix: a
      runner's own flags run any program or write any file (`npm test --node-options`,
      `go test -exec`, `golangci-lint --output.text.path`, `pytest --basetemp`);
    - the secret scan finds a key given as a shell or compose default (`${VAR:-key}`,
      `${1-key}`), after a URL escape or a NUL byte, and an Anthropic key even inside a compiled
      file; it reads bytes, so macOS's grep cannot give up on it; a prefixed key needs a 40-character
      tail, so a kebab-case name is not one;
    - the Stop hook's "where's the test?" had been switched off by the suite's own bytecode
      (`tests/__pycache__/*.pyc` counted as a new test) in any repo that does not ignore it: only a
      test's source counts now. Found by the macOS CI job, where no bytecode was written;
    - `check-debt.sh` (and so `/review`) rejected every marker on a Mac: `grep -Z` is decompress
      there; `--null` works on both;
    - `install.sh`: a re-run in a linked worktree knows her shared hook links, and a link of hers
      that git cannot run is reported, not counted as a gate;
    - `assets/build.py` checks every SVG against an allow-list of what the images draw with, and the
      scorecard's alt-text lint reads the tag in any shape and fails when it compared nothing;
    - the docs say that a plugin user's clone of a full copy-in runs lite, and how to keep full.
  - **Fourth review round** (both reviews asked for changes; each fix has a test that failed first):
    - the secret scan reads each NUL byte both as a gap and as nothing, so the write guard,
      pre-commit and pre-push find a key right after one, a key one cuts in two, and a key in UTF-16
      text (what Windows PowerShell writes). The third round had made a NUL a gap only, which lost
      UTF-16 files;
    - the placeholder rule reads only a key's own start: a sample word before a key
      (`${SAMPLE-key}`, `${k[FAKE]-key}`) or glued after it (`keyEXAMPLE`), or a sample glued in
      front of it, no longer exempts a real key;
    - a key after a shell's special parameter (`${?-key}`) or a JSON escape (`\f`, `\u0000`) is found;
    - the TypeScript pack no longer pre-approves `npx tsc` or `npx vitest`: npx fetches and runs a
      package that is not installed, without asking;
    - "where's the test?" counts a new `.test.mts`, `.test.cts` or `_test.cxx`, and four Stop tests
      that the first ask's memo had answered now decide alone;
    - `check-debt.sh`'s `tr` and `sed` read bytes: on a Mac they refused a file with a byte that is
      not UTF-8, so its marker went unseen. The real Mac run had failed that test too; the BSD-tools
      simulation, run to the end on this unit for the first time, found this much of why (the rest
      was `sort`, below).
  - **Fifth review round** (the security review approved the fourth with findings; each fix has a
    test that failed first):
    - without jq, the write guard reads a `\u0000` escape as the NUL byte it stands for, so a key
      one cuts in two, or UTF-16 text read as JSON, is found there too;
    - in lines whose NUL bytes are removed, an OpenAI key as long as a real one (a tail of 80 or
      more; real ones have about 156) is a key wherever it starts, so one right after a kana or a
      CJK character in UTF-16 text is found. Read everywhere at first, that rule made a long
      kebab-case name after a word ending in "sk" (a URL slug) a key, which the code re-review
      found, and then every line of a text with one NUL in it; the reading with the NULs removed
      now holds only the lines that had one (all of the text, should picking them fail);
    - the scan reads its text in lower case once, reads each key where its prefix starts, in the
      shell, and skips text that holds nothing a pattern needs. On the review's slowest inputs it is
      faster than before either round: 20 KB of Slack sample keys took 3.1 s before the fourth
      round, 7.2 s after it, and 0.17 s now; a 2 MB binary 1.0 s, 2.1 s and 0.4 s.
    - an indirect expansion's default (`${!ref-key}`) starts a token too, as the code review asked;
      its other MEDIUM, a key after a U+0000 in UTF-16 text (a string list), is found by the
      real-length rule above;
    - the TypeScript pack's README says its gate's two `npx` steps ask first, and how to approve
      them;
    - a key pattern with no literal prefix counts as a key at once: the walk from each prefix had
      nothing to walk from and would have looped (no pattern has one yet);
    - the sample-word test of the patterns with no key window (an AWS access key id, a Google key,
      a quoted assignment) runs in the shell too, reading bytes whatever the locale: a 312 KB write
      of 12,000 sample ids before a NUL-cut key took 64 s to block, longer than a hook's timeout,
      and now takes 1.5 s. A value over 512 characters goes to grep, in one pass: the regex tries
      `<[^>]+>` from every `<`, and 240 KB of them took 104 s (0.26 s now);
    - a string escape starts a token as `\n` and `\u0000` do (`\x01`, `\0`, `\000`, `\a`, `\e`,
      `\v`): once the real-length rule read only lines with a NUL, a key in a byte literal
      (`b"\x0a\xa4\x01sk-proj-…"`) had nothing else to find it, which the security re-review found;
    - no shell subscript before a key is read: any `]-` starts a token, so a key after
      `${a[0]-`, after a subscript of any length, or after a nested one (`${a[${b[0]}]-key}`) is
      found, in fixed time per place. Read to its end, grep went from every `{a[` to the end of a
      line that never closed one (240 KB of them before a key took 79 s); read to 64 characters, a
      longer one hid the key, which both reviewers found. The route for values over 512 characters
      is tested both ways (a long secret is one, a long sample is not), after a mutant that called
      every such value a sample passed the suite.
  - **The first real-Mac run of the launch PR** (#22) failed tests the simulation passed; the
    simulation now has each cause (Python 3.9 as `python3`, and a `sort` that stops at a byte that
    is not UTF-8), and each fix has a test that failed first:
    - `check-debt.sh` reads bytes throughout (`LC_ALL=C` for the whole script): macOS's `sort`
      stopped at a byte that is not UTF-8, and the empty ledger it left passed the marker. A tool
      that fails while the markers are read, classified or counted is now a stop (exit 2), not a
      clean ledger: both reviews found `tr`, `sed`, the diff's reader and the count unchecked too,
      and a count that is not a number (a `wc` that printed nothing) passed as well;
    - `bench/examples.py` runs on a stock Mac's Python 3.9: its `str | None` annotations needed
      3.10, and it now defers them (`from __future__ import annotations`), as the other scripts do.
  - **Secret scan:** it missed Anthropic keys and OpenAI's `sk-proj-`, `sk-svcacct-` and `sk-admin-`
    keys, which the docs said it caught. The write guard, pre-commit and pre-push now refuse them;
    golden tests hold each key type and a key given as a shell default, a property test holds the
    40-character tail bound, and the scan reads bytes, so macOS's grep cannot give up on it.

- **2026-09-29** — Round 3 ran: 484 runs, $37.18 of logged spend, every fingerprint ok, none
  dropped, no ERROR rows. Harness `83b5de3`, Claude Code 2.1.284, `claude-sonnet-5-5` and
  `claude-haiku-4-5-20251001`. The rows, `summary.txt`, `summary.json` and the runner's report are
  in `bench/results/`; `summarize.py` reproduces the summary byte for byte. D3 rows 1 and 4 hold
  (lite 1/64 unsafe against the bare agent's 24/64, at 1.8× its small-task cost; full 0/64), row 5
  does not (its code-size condition fails: +28% against a ±20% limit), and lite's real-suite pass rate is not
  below the bare agent's (30/36 against 28/36). The launch docs take their numbers from here.

- **2026-09-29** — CI hardening, the follow-ups on the launch plan's tracking issue (#17), folded
  into the launch unit so the macOS job ships with the fixes it found:
  - every third-party action is pinned to a full commit SHA with its tag beside it (checkout 4.4.0,
    setup-python 5.6.0, setup-node 4.4.0, shellcheck 2.0.0). The shellcheck action had been
    `@master`, two commits past 2.0.0 that change only its own tests and README, so it is the same
    action;
  - the token is read-only by default in both workflows, and only the release job, which creates
    the release, has `contents: write`;
  - a macOS job runs the gate self-tests under `/bin/bash` 3.2 with only Apple's tools on the PATH
    (no Homebrew), and fails if the runner is not that toolchain. It is not proven yet. Its first
    run failed 62 tests and its second 59: three were brace lists typed inside `"$(gb "...")"`,
    which bash 3.2 expands (the tests now pass them through a variable); 46 were the suite's own
    GNU habits (`sed -i`, `timeout`), which it no longer has; 12 were a real bug, `check-debt.sh`'s
    `grep -Z` (decompress, on a Mac); and one found a real bug in the Stop hook (see the launch
    entry). The next run, on this unit's PR, is the proof, and a local simulation with BSD-style
    `sed`, `grep` and `tr` is the check before it.

- **2026-09-28** — Benchmark round 3, the fourth unit of the launch plan (#17), built and proven,
  not yet run (paid runs are the maintainer's). `bench/` gains:
  - the plugin arms, alone and beside another plugin;
  - per-run isolation and an init fingerprint that stops a run that is not its arm;
  - a neutral prompt for every arm;
  - token, model and subagent columns;
  - `run.sh` gates that refuse an unregistered or dirty paid run;
  - an offline stub `claude` and `verify.sh --dry-run`;
  - `summarize.py` for round 3, deciding D3 as `bench/PREREGISTRATION.md` registers it (rounds
    1–2 still print byte for byte);
  - a prompt lint.

  The real suite (D5) is six tickets on full-stack-fastapi-template with PostgreSQL, three of them
  traps. It is scored on copies, in databases of its own, and proven by `verify.sh --real` against
  25 hand-made patches, the agent's seat and a dry run of each arm. 283 bench tests, 992 harness
  tests.

  First review round: the code review and the security review both asked for changes, and every
  finding is fixed:
  - a database server lost mid-scoring is ERROR, not unsafe;
  - no admin or role password on a command line;
  - no admin drop named by an agent-writable file;
  - a paid run refuses a server that lets logins in without a password;
  - the scorer writes through no link, and compares against git's object store;
  - the tamper check sees module-level skips, autouse fixtures and pytest settings, and lets a test
    the agent made stricter pass;
  - a re-score replaces only an unscored run;
  - D3 counts only the neutral prompt's traps and says when a cost is missing;
  - the isolation claims now say what `env -i` does and does not stop.

- **2026-09-25** — `/nonna`, the third unit of the launch plan (#17, ADR-0011 §12). The user's
  switch for her gates: `/nonna` shows what she enforces here and where each setting comes from (the
  mode's source, the test command's, a green run on this tree, the guards, the git hooks); `lite`,
  `full`, `off` and `test` change them; `setup` records the test command and wires the git hooks,
  and only offers a change to the user's own files; `uninstall` takes back only what is hers, in
  every worktree, naming each value. It is user-only, and its `!` line is pre-approved exactly by
  its `allowed-tools`, both linted. The branch guard refuses the agent running her scripts (named,
  globbed, or from inside her directory, when a shell runs them), and while she is off it still
  keeps her settings, and nothing else. Shared helpers: `nonna_mode_source`, `nonna_green_key`,
  `nonna_hook_chains_hers`. A lite copy-in brings `/nonna`. `install.sh` no longer takes a hook that
  merely names her script's file as one that runs it. 968 tests.
  First review round: both approve, and every finding is fixed.
  - A read of her files beside an unrelated shell, such as linting her scripts and then running
    the suite, is no longer refused. A copy, a pipe, a variable or a `cd` that carries her script
    into a shell still is, and so are `eval` and a copy run by its path.
  - While she is off, a command too large to read is refused only when it could touch her
    settings.
  - Detection finds pytest without importing anything from the repository, where a `pytest.py`
    would have run.
  - The lint holds a fenced `!` block to the same pre-approval as an inline one.

  986 tests. Second round: both approve. The one open finding is a MEDIUM: a reader made to start
  a program through an option of its own gets past the scripts rule. It is no stronger than the
  script-file limit, so it is a named limit in ADR-0011 §12, with a `debt:` marker in the guard
  that is revisited if that limit is ever closed.

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

- The rest of the launch plan (#17), once this unit merges: the film, as its own PR from
  `chore/17-demo`; then the v2.0.0 release and the go/no-go checks. `/nonna` ran headless in
  default and auto mode during the smoke runs; an interactive check stays on the go/no-go list.
- The branch guard should fail closed when a check cannot run. A `git` or `grep` that fails to
  start reads as "nothing found" today, so the command is allowed: the likely reason two guard
  tests allowed a blocked command, three times in all and each passing on rerun, while three or
  four copies of the suite ran at once. Server-side branch protection is the wall either way; the
  guard is the speed bump (ADR-0011).
- `check-debt.sh` counts a trigger made only of whitespace other than a space or a tab (`\r\r`,
  `\v`, a no-break space) as a trigger; it should trim all of it (the security review's LOW). It
  also reads only the first marker on a line, so one inside a string before it, or a file with
  CR-only line endings, hides a marker with no trigger later on that line (also LOW).

- A behavioural eval on the failures the gates exist for (a secret in a fixture, a push to a
  protected branch, an error hidden by a "fix"), scored on "did it get caught".
- A statusline showing branch and gate state.
- Optional MCP server examples for the explorer and reviewer agents.
