# ADR 0012 — A test command per directory

- **Status:** Accepted
- **Date:** 2026-09-30
- **Deciders:** Shashank Kapadia

## Context

A repository has one test command, `git config nonna.testCmd`, and the Stop hook runs it at the end
of every turn that changed code. In a monorepo that command is the whole suite, which often runs past
the Stop hook's 240-second budget. A suite that runs out of time there is not called red, so only the
pre-push hook gives a verdict, several turns after the agent said "done" (#29).

The test gate is Nonna's most critical surface. A selection that runs too little is a gate that is off
without saying so ([ADR 0004](0004-gates-as-code.md)), and so is a cache that remembers a green run it
should have forgotten.

## Options considered

1. **One command, as now.** Nothing to build; a monorepo gets no verdict at the end of a turn.
2. **A file in the repository** naming each package's command. Reviewable, but committed: a clone, or
   the agent editing the file, would choose what runs. Git config is never cloned, and the branch
   guard refuses the agent writing it.
3. **Detect the packages** (npm workspaces, `go.work`, Cargo workspaces). Many formats to read, and
   under the plugin, detection needs the user's consent (`run_tests`). It can come later, on top of
   the keys below.
4. **A git config key per directory, set by the user.** Chosen.

## Decision

1. **The key** is `git config nonna.<dir>.testCmd <command>`: a subsection per directory, named from
   the repository's top, with no leading `./` and no trailing `/`. `/nonna test --dir` writes it that
   way. The root `nonna.testCmd` is unchanged. A directory's key is read from the repository's own
   config only: a directory belongs to one repository, and a global key would reach every repository
   that has a directory of that name. An empty directory command is no command, so its files go to the
   next owner: a directory's key narrows what runs and can never turn the gate off.
2. **Ownership.** A changed file belongs to the longest configured directory that is its path or a
   directory above it, on a `/` boundary: `packages/api` owns `packages/api/x.py`, not
   `packages/apix/y.py`. A file in no directory belongs to the root's command, if there is one. The
   answer does not depend on the order the keys were set.
3. **Where a command runs.** A directory's command runs in that directory, so `pytest` there tests
   that package. The root's command runs where it runs today.
4. **At the end of a turn,** the Stop hook lists the files changed this session exactly (unquoted, a
   rename as both of its paths, `docs/` and `.claude/reviews/` left out as before) and runs each
   owning command once. The directories' commands run in the order git config lists them, which is the
   order `/nonna` shows, and the root's runs last. The commands share the 240 seconds. One that runs
   out of time stops the rest, and that is not red, as before. The first red blocks, named with its
   command and directory. A green run is remembered per directory, by the directory's own tree
   (tracked and untracked files) and its command, in `.git/nonna/green-<hash of the directory>`. So a
   package that no later change touched is not run again. The root's green run is remembered as
   before, by the whole tree and the command in `.git/nonna-green`, because the root's command may
   test everything.
5. **Before a push,** the pre-push hook makes the same selection over the code files of the pushed
   range. Each command gets the full 600 seconds, and the first red refuses the push, named. The hook
   already refuses a push whose files it cannot list. That is stricter than running every command, so
   this case needs no rule of its own.
6. **`NONNA_TEST_CMD`** still overrides everything at the end of a turn with one command, and the
   pre-push hook still ignores it. With no directory keys, both hooks behave exactly as before.
7. **`/nonna`.** `/nonna test --dir <dir> '<command>'` sets a directory's command, and
   `/nonna test --dir <dir> off` removes it. The directory is resolved (`./`, a trailing `/`, `..` and
   links) and must be a directory inside the repository, other than its top. `/nonna` lists each
   directory's command. `/nonna uninstall` removes every `nonna` section, subsections included, and
   names each setting it removes.
8. **The branch guard** already refuses the agent writing any `nonna.*` key, including a directory's.
   A golden test pins that.

### Choices inside the design

- **Run order: config order, not sorted.** Sorting needs `sort`, which the Stop hook avoids so that
  minimal machines keep working. Config order is stable, and `/nonna` shows it.
- **A directory's green run is keyed by its own tree, not the whole tree.** Keyed by the whole tree,
  a package would run again every time another package changed.
- **A directory's command runs in its directory, not at the top.** At the top, the issue's own example
  (`pytest`) would run the whole suite.
- **An empty directory command means no command, not "off".** If empty meant off, one empty value
  could switch testing off for a whole subtree without anyone noticing. A package that should test
  nothing says so with a command that passes, such as `true`.
- **`off` removes a directory's key; it does not set it empty.** With the key gone, the directory's
  files go back to the root's command. That is the safe direction, and it is what someone who set the
  wrong directory needs.

## Consequences

- A change in one package that breaks another is caught only by a command that runs the other
  package's tests. Per-directory commands trust the user's directory boundaries. A package that
  depends on code outside it can include that code's tests in its command, or leave that code to a
  root command that runs them.
- A package's green run is keyed by its own tree. Suppose its files changed earlier in the session and
  have not changed since, and a later change outside the package breaks its tests. The Stop hook's
  cache does not notice. The pre-push hook has no cache and runs the package's command.
- A repository with directory keys costs the Stop hook a few more git calls at each turn end: an exact
  list of the changed files, and a key for each owning directory. A repository without them costs
  nothing more.
- A hand-written key that is not a clean directory name (`./x`, `x/`) owns nothing. `/nonna test --dir`
  never writes one.
- Revisit if monorepo users ask for dependency-aware selection (run B when A changes, because B
  depends on A), or if detecting workspaces would save them the configuration.
