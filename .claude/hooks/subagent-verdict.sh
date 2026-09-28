#!/usr/bin/env bash
# SubagentStop (code-reviewer | security-reviewer) — validate the verdict where
# it is produced, not several steps later.
#
# ADR-0005 makes a machine-checkable JSON verdict the thing that decides merges,
# and check-review.sh the decider. But that contract only binds if /review
# remembers to write the verdict file and run the checker. A reviewer that
# returns prose, an unparseable block, or two blocks currently sails past this
# boundary and is only caught downstream — if at all.
#
# This runs the SAME check-review.sh against the reviewer's own output, at the
# moment it finishes. No new parser, no second source of truth for the schema.
#
# Fails OPEN when it cannot read the reviewer's output or locate the checker:
# this is a defence-in-depth layer, and /review + /ship still run the real gate.
# It fails CLOSED on what it can actually judge — output that is present but
# malformed — by sending the reviewer back once with the contract as its next
# instruction. Once, not forever: see stop_hook_active below.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$here/lib/core.sh"
[ "$(cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null && nonna_mode)" = off ] && exit 0 # off means off
payload="$(cat 2>/dev/null || true)"
[ -n "$payload" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0   # structured read required; backstopped by /review

# Already sent back once this turn. Blocking again would loop for as long as
# the reviewer cannot produce the contract; let it stop and let /review decide.
active="$(printf '%s' "$payload" | jq -r '.stop_hook_active // false' 2>/dev/null)"
[ "$active" = "true" ] && exit 0

# What the reviewer returned. `last_assistant_message` is the subagent's final
# text and the authoritative source. `agent_transcript_path` is the subagent's
# own transcript, the fallback for a Claude Code that does not send the message:
# the file is written asynchronously and may lag the final text, so this path
# can grade a stale interim message and send the reviewer back once for nothing
# — once, because stop_hook_active stops the second round. `transcript_path` is
# the PARENT session's transcript and is never read: grading it means grading
# the orchestrator's prose, which rejects every verdict as "not valid JSON".
last="$(printf '%s' "$payload" | jq -r '.last_assistant_message // empty' 2>/dev/null)"
if [ -z "$last" ]; then
  transcript="$(printf '%s' "$payload" | jq -r '.agent_transcript_path // empty' 2>/dev/null)"
  transcript="${transcript/#\~/$HOME}"
  if [ -z "$transcript" ] || [ ! -f "$transcript" ]; then
    # Visible in --debug, so an inert gate is not mistaken for a passing one.
    echo "subagent-verdict: no reviewer output in the payload; not judging" >&2
    exit 0
  fi
  last="$(jq -rs '[.[] | select(.type=="assistant") | .message.content[]?
                   | select(.type=="text") | .text] | last // empty' \
          "$transcript" 2>/dev/null)"
fi
[ -n "$last" ] || exit 0

# Locate the decider in either install mode (ADR-0007).
root="${CLAUDE_PROJECT_DIR:-$(pwd)}"
checker=""
for cand in \
  "${CLAUDE_PLUGIN_ROOT:-}/skills/code-review/scripts/check-review.sh" \
  "$root/.claude/skills/code-review/scripts/check-review.sh"; do
  [ -n "$cand" ] && [ -f "$cand" ] && { checker="$cand"; break; }
done
[ -n "$checker" ] || exit 0

# check-review.sh: 0 = approve; 1 = a well-formed request_changes (or a
# blocking finding) — the reviewer doing its job, and /review turns that into a
# red gate; 2 = no verdict, or one that is unparseable or ambiguous. Only 2 is a
# breach of the contract, and only that is worth sending the reviewer back for.
out="$(printf '%s' "$last" | bash "$checker" 2>&1)"; rc=$?
[ "$rc" -eq 2 ] || exit 0

reason="Reviewer verdict rejected by check-review.sh (exit ${rc}): ${out}. ADR-0005: the reviewer must emit exactly one fenced json block with a verdict and findings[]. Re-run the reviewer and have it emit the contract — do not hand-write or paraphrase the verdict."
jq -cn --arg r "$reason" '{decision: "block", reason: $r}'
exit 0
