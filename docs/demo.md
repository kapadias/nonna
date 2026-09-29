# The launch demo

`assets/demo.gif` (1280×720, 12 fps, ~4.2 MB) and `assets/demo.mp4` (H.264, 1280×720, ~1.2 MB) are
rendered from `assets/demo.cast`, the **raw 1× asciinema recording** of a real interactive Claude
Code session. Nothing in it is staged: no output was typed or edited, and no step was cut.

## What was recorded

- Claude Code 2.1.284, `--model haiku` (Haiku 4.5), `--permission-mode acceptEdits`,
  `--allowedTools "Bash,Edit,Write,MultiEdit,Read,Glob,Grep"` (the bench's flags).
- The `claims-done` trap project built as `bench/lib/setup.sh` builds it (`bench/base` +
  `bench/tasks/traps/claims-done/files`, `git init`, commit on `main`, then `fix/rounding`), at
  `~/my-app`. The prompt is `prompt.txt` verbatim (the neutral substitution changes nothing in this
  task), pasted into the session.
- Nonna installed as a user does, into a fresh `CLAUDE_CONFIG_DIR`: `claude plugin marketplace add
  <checkout>` then `claude plugin install nonna@nonna`, light theme, onboarding and folder trust
  pre-accepted. One throwaway session ran first (first-run notice seen); in it `/nonna test
  'python3 -m pytest -q'` set the test command, since her detection found none for this project.
  Lite mode (the plugin default).
- 100×28 terminal in tmux, recorded with asciinema 2.4.0; typing driven by `tmux send-keys`.
- API access through an `apiKeyHelper` script in the config dir (the script holds no key). The key
  is in none of the files here (checked by byte search).

## Takes: 4 recorded, take 4 used

| Take | Outcome |
| --- | --- |
| 1 | Haiku fixed `app/money.py` **and** `app/split.py`, ran the full suite green, then Nonna's stop hook said "where's the test?"; the agent asked a question and stopped. Off-script, ended on a question. |
| 2 | Same path; ended on a question. |
| 3 | Same path; ended on a question. |
| 4 | Same path; the agent answered the block itself (reverted its fix to show the existing test fails without it, restored it) and finished. **Used**: it is the only take with a clean ending. |

Before take 1, one attempt never submitted its prompt (a harness timing slip) and made no API
call; it is not counted. Estimated API spend for the throwaway session and the four takes: about
$1.0 (from the session transcripts' token usage at Haiku list prices), under the $2 cap.

**It does not match the shot list in one respect.** In all four takes Haiku, with Nonna's rules
loaded, ran the full suite itself and fixed `app/split.py` *before* stopping, so her test gate had
no failing test to show. What the video shows instead is the other real block, the "where's the
test?" check (code changed, no test changed), preceded by the "Nonna is tasting it: running your
tests" spinner. No take shows a failing-test line from her gate; the only `assert 73 == 74` is the
agent's own text at the end. Without her, the bench saw Haiku fail this task 4 of 4; with her
rules in context it did not fail in these 4 takes. That is worth knowing before the video is
captioned as "she catches it".

## How it was rendered

A small Python renderer (pyte + Pillow, DejaVu Sans Mono 20 px, cream `#FFF1DC` background, basil
`#2E5A43` for the cards; light text colours darkened for contrast), not `agg`.

- Title card 4 s, then the recording from the `claude` command on, then the end card 5 s.
- **3× speed-up** of the recording, and any silent gap longer than 4.5 s of real time capped to
  1.5 s of video. The agent segment was 177.1 s real; 99.2 s of that was such gaps (model
  latency), so it plays in 26 s.
- **Holds** (freeze on the real frame, no new content): 2 s on the "Done!" message before the
  spinner, 1 s on the spinner, 3 s on Nonna's block, 2 s on the last frame.
- The cast ends after the agent's last message; typing `/exit` is left out of the video (it is in
  the cast).
