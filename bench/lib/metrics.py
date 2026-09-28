#!/usr/bin/env python3
"""One TSV row for one finished run. No API calls; safe to re-run.

usage: metrics.py <suite> <task> <arm> <model> <rep> <run-dir> <verdict> <rc> <wall_s> <harness>
                  [<prompt> <label>]
       metrics.py --header

The id is the run dir's name, so a labelled rerun is its own row. Round 3's columns come after the
22 old ones: every old column keeps its position, and a run with no stream reads "-" in them. The
real suite's unsafe, claimed_done and test_left are its scorer's (hidden/real/score.py); a run it
could not score (verdict ERROR) reads "-" in unsafe.
"""

import json
import os
import re
import subprocess
import sys
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gates  # noqa: E402

COLS = (
    "id suite task arm model rep verdict unsafe gate_fired gate_kinds claimed_done test_left "
    "src_loc cost_usd wall_s turns rc lane security branch commits harness "
    "prompt label fingerprint model_resolved cc_version stop tokens_in tokens_out "
    "tokens_cache_read tokens_cache_write subagents subagent_types"
).split()
DETAIL = COLS[COLS.index("model_resolved"):]
TOKENS = (
    ("tokens_in", "inputTokens", "input_tokens"),
    ("tokens_out", "outputTokens", "output_tokens"),
    ("tokens_cache_read", "cacheReadInputTokens", "cache_read_input_tokens"),
    ("tokens_cache_write", "cacheCreationInputTokens", "cache_creation_input_tokens"),
)

# Paths that are not "source" for the LOC count: tests wherever they live, docs, the harness, env
# files, lockfiles, and the real suite's generated frontend client.
EXC = re.compile(
    r"(^|/)(tests?/|docs/|\.claude/|CLAUDE\.md$|README\.md$|__pycache__|\.pytest_cache|"
    r"[^/]*_test\.py$|test_[^/]*\.py$|[^/]*\.test\.[a-z]+$|[^/]*\.spec\.[a-z]+$|\.env[^/]*$|"
    r"(uv|poetry|Cargo|yarn)\.lock$|package-lock\.json$|pnpm-lock\.yaml$|bun\.lockb?$)"
    r"|^frontend/src/client/"
)
LANE = re.compile(r"review-lanes: lane=([a-z]+) vs [^;\s]+; security=([a-z]+)")


def git(d, *a):
    r = subprocess.run(["git", "-C", d, *a], capture_output=True, text=True)
    return r.stdout if r.returncode == 0 else ""


def stream_stats(path):
    cost, turns = -1.0, -1
    try:
        for line in open(path, encoding="utf-8", errors="replace"):
            try:
                j = json.loads(line)
            except ValueError:
                continue
            if j.get("type") == "result":
                # A background subagent can emit a second result: cost is cumulative, turns add up.
                cost = max(cost, float(j.get("total_cost_usd") or -1))
                turns = max(turns, 0) + int(j.get("num_turns") or 0)
    except FileNotFoundError:
        pass
    return cost, turns


def stream_detail(path):
    """The resolved model and CLI version (init), how the run stopped (the first error result, else
    the first result), its tokens over every model and the subagents it started (the last result:
    both are running totals). Subagents are the CLI's own count when it reports one, else the Agent
    and Task tool calls in the stream."""
    init, results, spawned = {}, [], Counter()
    try:
        for line in open(path, encoding="utf-8", errors="replace"):
            try:
                j = json.loads(line)
            except ValueError:
                continue
            if j.get("type") == "system" and j.get("subtype") == "init" and not init:
                init = j
            elif j.get("type") == "result":
                results.append(j)
            elif j.get("type") == "assistant":
                for c in (j.get("message") or {}).get("content") or []:
                    if isinstance(c, dict) and c.get("type") == "tool_use" and c.get("name") in ("Agent", "Task"):
                        spawned[(c.get("input") or {}).get("subagent_type") or "general-purpose"] += 1
    except FileNotFoundError:
        pass
    out = dict.fromkeys(DETAIL, "-")
    if init:
        out["model_resolved"] = init.get("model") or "-"
        out["cc_version"] = init.get("claude_code_version") or "-"
    if results:
        errors = [r["subtype"] for r in results if str(r.get("subtype", "")).startswith("error")]
        out["stop"] = errors[0] if errors else results[0].get("subtype") or "-"
        top = max(results, key=lambda r: float(r.get("total_cost_usd") or -1))
        per_model = [m for m in (top.get("modelUsage") or {}).values() if isinstance(m, dict)]
        for col, key, legacy in TOKENS:
            if per_model:
                out[col] = str(sum(int(m.get(key) or 0) for m in per_model))
            elif isinstance(top.get("usage"), dict):
                out[col] = str(int(top["usage"].get(legacy) or 0))
        stats = top.get("subagent_stats")
        if isinstance(stats, dict) and isinstance(stats.get("spawned"), int):
            spawned = Counter(stats.get("by_type") or {})
            out["subagents"] = str(stats["spawned"])
    if init or results:
        if out["subagents"] == "-":
            out["subagents"] = str(sum(spawned.values()))
        out["subagent_types"] = ";".join(f"{k}={v}" for k, v in sorted(spawned.items())) or "-"
    return out


def scored(d):
    """The real suite's key=value lines from its scorer, up to the detail."""
    out = {}
    try:
        for line in open(d + ".hidden.txt", encoding="utf-8", errors="replace"):
            if line.strip() == "---":
                break
            k, sep, v = line.strip().partition("=")
            if sep:
                out[k] = v
    except FileNotFoundError:
        pass
    return out


def src_loc(d, base):
    n = 0
    for line in git(d, "diff", "--numstat", base).splitlines():
        parts = line.split("\t")
        if len(parts) == 3 and not EXC.search(parts[2]) and parts[0] != "-":
            n += int(parts[0]) + int(parts[1])
    for f in git(d, "ls-files", "--others", "--exclude-standard").splitlines():
        if f and not EXC.search(f):
            try:
                with open(os.path.join(d, f), "rb") as fh:
                    n += fh.read().count(b"\n")
            except OSError:
                pass
    return n


def lanes(d):
    """Sequence of review-lanes verdicts, main stream first, then saved subagent transcripts."""
    texts = []
    for p in [d + ".stream.jsonl"]:
        if os.path.exists(p):
            texts.append(open(p, encoding="utf-8", errors="replace").read())
    tdir = d + ".transcripts"
    if os.path.isdir(tdir):
        for root, _, fs in sorted(os.walk(tdir)):
            for f in sorted(fs):
                if f.endswith(".jsonl"):
                    texts.append(
                        open(
                            os.path.join(root, f), encoding="utf-8", errors="replace"
                        ).read()
                    )
    seen = []
    for t in texts:
        for m in LANE.finditer(t):
            if m.groups() not in seen:
                seen.append(m.groups())
    if not seen:
        return "-", "-"
    return ">".join(dict.fromkeys(l for l, _ in seen)), ">".join(
        dict.fromkeys(s for _, s in seen)
    )


def main(argv):
    if argv[:1] == ["--header"]:
        print("\t".join(COLS))
        return
    suite, task, arm, model, rep, d, verdict, rc, wall, harness = argv[:10]
    prompt, label = (argv[10:12] + ["-", "-"])[:2]
    base = open(d + ".base").read().strip()
    cost, turns = stream_stats(d + ".stream.jsonl")
    gn, gk = gates.count(d + ".stream.jsonl")
    claimed = "-"
    if task == "claims-done":
        try:
            m = re.search(r"claimed_done=(\d)", open(d + ".hidden.txt").read())
            claimed = m.group(1) if m else "-"
        except FileNotFoundError:
            pass
    if suite == "real":
        hidden = scored(d)
        claimed = hidden.get("claimed_done", "-")
        tl = hidden.get("test_left", "-")
        unsafe = hidden.get("unsafe", "-") if verdict in ("pass", "FAIL") else "-"
    else:
        tl = (
            subprocess.run(
                [sys.executable, os.path.join(HERE, "testleft.py"), d, d + ".pristine"],
                capture_output=True,
                text=True,
            ).stdout[:1]
            or "-"
        )
        unsafe = {"SAFE": "0", "FAIL": "1"}.get(verdict, "-") if suite == "traps" else "-"
    lane, sec = lanes(d) if arm != "none" else ("-", "-")
    try:
        fp = open(d + ".fingerprint").readline().strip() or "-"
    except FileNotFoundError:
        fp = "-"
    detail = stream_detail(d + ".stream.jsonl")
    row = [
        os.path.basename(os.path.normpath(d)),
        suite,
        task,
        arm,
        model,
        rep,
        verdict,
        unsafe,
        gn,
        gk,
        claimed,
        tl,
        src_loc(d, base),
        f"{cost:.4f}",
        wall,
        turns,
        rc,
        lane,
        sec,
        git(d, "branch", "--show-current").strip() or "-",
        git(d, "rev-list", "--count", f"{base}..HEAD").strip() or "0",
        harness,
        prompt or "-",
        label or "-",
        fp,
        *(detail[c] for c in DETAIL),
    ]
    print("\t".join(map(str, row)))


if __name__ == "__main__":
    main(sys.argv[1:])
