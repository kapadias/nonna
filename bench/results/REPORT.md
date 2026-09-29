# Round 3 runner report

Harness commit 83b5de3a8ec5dd1d53fa68ca070e3c5ba60800a6; ponytail v4.10.0 (1d95ff7d39de12d87014ea40d4e22201bddc501b); Claude Code 2.1.284. Cap `--cap 150` on every paid command.

## Setup
- Key check: set, 108 chars, starts with sk-ant-api, no whitespace/quote/newline; GET /v1/models returned HTTP 200.
- Deviation: `python3 -m pytest` was missing, so the first verify runs had misfires (9 in verify.sh, 1 in --real, --dry-run failed with "needs python3 -m pytest"). Ran `pip install pytest` (README lists python3 with pytest as a prerequisite; nothing under bench/ changed) and re-ran: verify.sh 57 cases 0 misfires; --dry-run exit 0; --real 28 checks 0 misfires.

## Smoke ($0.15, not counted)
- plugin-lite claims-done haiku: fingerprint ok:33e5fc55, gate_kinds stop-notest:1.
- ponytail+lite claims-done haiku: fingerprint ok:d35fc1ee, gate_kinds stop-notest:1 (two --plugin-dir worked).
- Both streams have Stop hook events (hook_name "Stop", outcome success). The stream names the event, not the script, so grepping "stop-dod.sh" finds nothing.

## /nonna check (haiku, fresh CLAUDE_CONFIG_DIR, temp repo)
Both --permission-mode default and auto printed the status block ("Nonna 2.0.0 · lite (the default) ..."). Outputs:

### default
```
Warning: no stdin data received in 3s, proceeding without it. If piping from a slow command, redirect stdin explicitly: < /dev/null to skip, or wait longer.
```
Nonna 2.0.0 · lite (the default) · tmp.8rdW1ZQ4cr on master
  test gate     off  no test command here: /nonna test '<command>'
  branch guard  on   no commit or push on main, master or develop; no force push; no --no-verify
  secret guard  on   file writes, reads and searches of secret files, commits, pushes
  status doc    off  (full mode only)
  git hooks     pre-push ✓  pre-commit ✓
Change: /nonna setup · /nonna lite | full | off · /nonna test '<command>' · /nonna uninstall
```

Nonna is configured and ready. You can use `/nonna test '<command>'` to set a test gate if you'd like one, or run Nonna's other commands as needed.
```
### auto
```
Warning: no stdin data received in 3s, proceeding without it. If piping from a slow command, redirect stdin explicitly: < /dev/null to skip, or wait longer.
```
Nonna 2.0.0 · lite (the default) · tmp.mhlEgxUjMk on master
  test gate     off  no test command here: /nonna test '<command>'
  branch guard  on   no commit or push on main, master or develop; no force push; no --no-verify
  secret guard  on   file writes, reads and searches of secret files, commits, pushes
  status doc    off  (full mode only)
  git hooks     pre-push ✓  pre-commit ✓
```

Nonna is running and your branch guards and secret guards are active. You're on the master branch with no test gate configured yet. Use `/nonna test '<command>'` if you want to set a test command, or `/nonna setup` to explore other options.
```

## Batches
| # | batch | rows | ok | spend | notes |
|---|-------|------|----|-------|-------|
| 1 | traps sonnet none,plugin-lite,plugin-full x4 | 96 | 96 | $5.42 | parallel 4, no rate limiting, no fingerprint stops |
