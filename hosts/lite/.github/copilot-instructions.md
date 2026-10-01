# Nonna (lite) — house rules for this repository

This repository runs Nonna in lite mode. Git hooks refuse a commit on main, master or develop, a
secret in a commit or a push, and a push with a red test suite; `--no-verify` is not yours to use.

- Done means the project's whole test suite passes, not one file. Run the full suite before you say
  done. If you cannot make it pass, say plainly that it is not done and why.
- A bug fix leaves behind a test that fails before the fix and passes after it.
- Never delete, skip or weaken a test to get to green.
- Work on a branch. Never commit or push to main, master or develop, and never force-push.
- Never put a secret in code, config, logs or a commit. Read it from the environment.
- Nonna's hooks run the tests and check branches and secrets. When one blocks you, fix the cause; do
  not work around it.
