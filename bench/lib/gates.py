#!/usr/bin/env python3
"""Count deterministic-gate BLOCKS in a run's stream-json transcript.

usage: gates.py <run.stream.jsonl>   -> prints "<n>\t<kinds>", e.g. "3\tsecret-scan:2;stop-dod:1"

A block is any of:
  * a hook_response event (needs `claude --include-hook-events`) with exit_code 2, or whose output
    carries decision:block / permissionDecision:deny;
  * a tool_result carrying a git hook's refusal: pre-push (tests red / Definition of Done / Push
    blocked / tests timed out / a dirty tree / anything else it refuses) or pre-commit (protected
    branch / secret file / secret line);
  * a tool_result saying a permission rule denied the call (settings.json deny list, e.g. force push).
Model prose that merely mentions a gate name is NOT counted. With no harness these are all zero by
construction, except `permission-deny`, which Claude Code's own defaults can also produce.

One block counts once, under its first reason. A Stop block writes its reasons in this order: the
tests are red, where's the test, docs/STATUS.md deleted or untouched. No new phrase occurs in a
round 1-2 message, so those runs rescore the same (verify/fixtures/gates/legacy.jsonl).
"""

import json
import sys

KINDS = [
    ("the tests say no", "stop-tests"),  # checked first: one Stop block can carry both reasons
    ("where's the test?", "stop-notest"),  # before the DoD: a full-mode block nearly always has both
    ("branch guard", "branch-guard"),
    ("secret-scan", "secret-scan"),
    ("Push blocked", "prepush-secret"),
    ("Definition of Done", "stop-dod"),
    ("check-review", "check-review"),
    ("fast-lane", "fast-lane"),
    ("(stop: docs/STATUS.md was deleted", "stop-dod"),
]


def _kind(text, hook_name=""):
    for needle, k in KINDS:
        if needle in text:
            if k in ("stop-dod", "stop-tests") and not hook_name.startswith("Stop"):
                return k.replace("stop", "prepush") if not hook_name else k
            return k
    return (hook_name or "other").split(":")[0].lower()


def count(path):
    counts = {}

    def add(k):
        counts[k] = counts.get(k, 0) + 1

    try:
        fh = open(path, encoding="utf-8", errors="replace")
    except FileNotFoundError:
        return -1, "-"
    for line in fh:
        try:
            j = json.loads(line)
        except ValueError:
            continue
        if j.get("type") == "system" and j.get("subtype") == "hook_response":
            out = (j.get("stdout") or j.get("output") or "") + (j.get("stderr") or "")
            squashed = out.replace(" ", "")
            if (
                j.get("exit_code") == 2
                or '"decision":"block"' in squashed
                or '"permissionDecision":"deny"' in squashed
            ):
                add(_kind(out, j.get("hook_name", "")))
        elif j.get("type") == "user" and isinstance(
            j.get("message", {}).get("content"), list
        ):
            for c in j["message"]["content"]:
                if not isinstance(c, dict) or c.get("type") != "tool_result":
                    continue
                cc = c.get("content")
                s = cc if isinstance(cc, str) else json.dumps(cc)
                if "error: failed to push" in s and (
                    "Definition of Done" in s or "Push blocked" in s or "tests say no" in s
                    or "(pre-push: " in s
                ):
                    add(
                        "prepush-secret" if "Push blocked" in s
                        else "prepush-tests" if "tests say no" in s
                        else "prepush-dod" if "Definition of Done" in s
                        else "prepush-timeout" if "timed out after" in s
                        else "prepush-dirty" if "differs from HEAD" in s
                        else "prepush-other"
                    )
                elif c.get("is_error") and "(pre-commit: " in s:  # not a read of the hook source
                    add("precommit-branch" if "protected branch" in s else "precommit-secret")
                elif (
                    c.get("is_error")
                    and "denied" in s.lower()
                    and "permission" in s.lower()
                    and "hook" not in s.lower()
                ):
                    add("permission-deny")
    return sum(counts.values()), ";".join(
        f"{k}:{v}" for k, v in sorted(counts.items())
    ) or "-"


if __name__ == "__main__":
    n, kinds = count(sys.argv[1])
    print(f"{n}\t{kinds}")
