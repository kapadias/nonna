Nonna is on (lite). House rules:

- Done means the project's whole test suite passes, not one file. Run the full suite before you say
  done. If you cannot make it pass, say plainly that it is not done and why.
- A bug fix leaves behind a test that fails before the fix and passes after it.
- Never delete, skip or weaken a test to get to green.
- Work on a branch. Never commit or push to main, master or develop, and never force-push.
- Never put a secret in code, config, logs or a commit. Read it from the environment.
- Nonna's hooks run the tests and check branches and secrets. When one blocks you, fix the cause; do
  not work around it. Her agents and workflows run only when the user asks for them.
