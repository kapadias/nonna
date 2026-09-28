#!/usr/bin/env bash
# PostCompact — re-state where the loop is after the conversation is summarized.
#
# Compaction preserves the narrative and drops the bookkeeping. What reliably
# survives is "we were working on X"; what reliably dies is the loop state — the
# branch, whether a review verdict exists for THIS commit, whether STATUS has
# moved. That is exactly the state Nonna's gates key on, so after a compaction the
# agent tends to re-review code it already reviewed, or believe it already
# shipped something it did not.
#
# Costs nothing until a compaction actually happens, and reads only git facts —
# no model output, nothing to trust. Always exits 0; a broken PostCompact must
# never wedge a session.
set -uo pipefail
root="${CLAUDE_PROJECT_DIR:-$(pwd)}"
cd "$root" 2>/dev/null || exit 0
command -v git >/dev/null 2>&1 || exit 0
git rev-parse --git-dir >/dev/null 2>&1 || exit 0
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$here/lib/core.sh"
[ "$(nonna_mode)" = off ] && exit 0 # off means off: nothing enforced, nothing said

branch="$(git branch --show-current 2>/dev/null || echo '(detached)')"
sha="$(git rev-parse --short HEAD 2>/dev/null || echo none)"
changed="$(git status --porcelain 2>/dev/null | grep -c . || true)"

status_state="STALE (not touched)"
git status --porcelain -- docs/STATUS.md 2>/dev/null | grep -q . && status_state="updated in the working tree"

verdicts="none for ${sha} — /review has not run against this exact code"
found=""
for f in ".claude/reviews/${sha}-"*.json; do
  [ -f "$f" ] && found="${found}${f##*/} "
done
[ -n "$found" ] && verdicts="$found"

msg="Nonna loop state after compaction — branch: ${branch} · HEAD: ${sha} · uncommitted files: ${changed} · docs/STATUS.md: ${status_state} · review verdicts: ${verdicts}. Gates are unchanged and still blocking; re-derive anything else from the repo rather than from memory of the summarized conversation."

if command -v jq >/dev/null 2>&1; then
  jq -cn --arg c "$msg" '{hookSpecificOutput: {hookEventName: "PostCompact", additionalContext: $c}}'
else
  printf '{"hookSpecificOutput":{"hookEventName":"PostCompact","additionalContext":"%s"}}\n' "$msg"
fi
exit 0
