#!/usr/bin/env python3
"""Check a dry run (verify.sh --dry-run): every arm on every task through the stub claude, and one
run per fault. Prints one line per check; exits 1 if any fails.

usage: check_dry_run.py <work-dir> <results-dir>
"""

import csv
import json
import os
import re
import subprocess
import sys

B = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ARMS = ["none", "nonna", "plugin-lite", "plugin-full", "ponytail", "ponytail+lite"]
NONNA_ARMS = {"nonna", "plugin-lite", "plugin-full", "ponytail+lite"}
PLUGIN_DIRS = {
    "none": [],
    "nonna": [],
    "plugin-lite": ["nonna"],
    "plugin-full": ["nonna"],
    "ponytail": ["ponytail"],
    "ponytail+lite": ["ponytail", "nonna"],
}
BAD_START = ("extra-plugin", "mcp", "model", "no-sessionstart")
failures = 0


def ok(cond, what):
    global failures
    print(f"{'ok  ' if cond else 'FAIL'} {what}")
    failures += not cond


def rows(results, suite):
    with open(os.path.join(results, f"{suite}.tsv"), newline="") as fh:
        return list(csv.DictReader(fh, delimiter="\t"))


def plugin_kinds(argv):
    """ponytail / nonna for each --plugin-dir, in order."""
    dirs = [argv[i + 1] for i, a in enumerate(argv) if a == "--plugin-dir"]
    return [
        "ponytail"
        if "ponytail" in d
        else "nonna"
        if re.search(r"/nonna-[0-9a-f]+/\.claude$", d)
        else d
        for d in dirs
    ]


def main(work, results):
    everything = rows(results, "traps") + rows(results, "small")
    runs = [r for r in everything if not r["label"].startswith("fault-")]
    for suite in ("traps", "small"):
        with open(os.path.join(B, "tasks", suite, "ORDER")) as fh:
            tasks = fh.read().split()
        for arm in ARMS:
            got = sorted(
                r["task"] for r in runs if r["suite"] == suite and r["arm"] == arm
            )
            ok(
                got == sorted(tasks),
                f"{suite}/{arm}: one run per task ({len(got)}/{len(tasks)})",
            )

    for r in runs:
        rid = f"{r['suite']}/{r['id']}"
        ok(r["fingerprint"].startswith("ok:"), f"{rid}: fingerprint {r['fingerprint']}")
        ok(
            (r["stop"], r["rc"], r["cost_usd"]) == ("success", "0", "0.0123"),
            f"{rid}: stop, rc and cost",
        )
        ok(
            (r["model_resolved"], r["cc_version"]) == ("claude-haiku-stub", "stub"),
            f"{rid}: model and CLI version",
        )
        ok(
            (
                r["tokens_in"],
                r["tokens_out"],
                r["tokens_cache_read"],
                r["tokens_cache_write"],
            )
            == ("1000", "200", "5000", "800"),
            f"{rid}: tokens",
        )
        ok(
            (r["subagents"], r["subagent_types"]) == ("1", "Explore=1"),
            f"{rid}: subagents",
        )
        ok(r["prompt"] == "neutral", f"{rid}: prompt")
        with open(
            os.path.join(work, r["suite"], r["id"] + ".cfg", "stub-invocation.json")
        ) as fh:
            inv = json.load(fh)
        ok(
            plugin_kinds(inv["argv"]) == PLUGIN_DIRS[r["arm"]],
            f"{rid}: --plugin-dir {plugin_kinds(inv['argv'])}",
        )
        kinds = r["gate_kinds"]
        if r["arm"] in NONNA_ARMS:
            ok(kinds.startswith("stop-"), f"{rid}: a Stop block ({kinds})")
        else:
            ok(kinds == "-", f"{rid}: no gate fired ({kinds})")
    for arm in NONNA_ARMS:
        ok(
            any("stop-notest" in r["gate_kinds"] for r in runs if r["arm"] == arm),
            f"{arm}: where's the test? fired",
        )

    faults = {
        r["label"][len("fault-") :]: r
        for r in everything
        if r["label"].startswith("fault-")
    }
    ok(
        sorted(faults) == sorted(BAD_START + ("budget",)),
        f"one run per fault ({sorted(faults)})",
    )
    for kind in BAD_START:
        r = faults.get(kind, {})
        survived = os.path.exists(
            os.path.join(work, "traps", r.get("id", "?") + ".cfg", "stub-survived")
        )
        ok(
            r.get("fingerprint", "").startswith("mismatch:")
            and r.get("rc") == "86"
            and not survived,
            f"fault {kind}: stopped at once ({r.get('fingerprint')}, rc {r.get('rc')}, survived {survived})",
        )
    b = faults.get("budget", {})
    ok(
        b.get("fingerprint", "").startswith("ok:")
        and b.get("stop") == "error_max_budget_usd",
        f"fault budget: the run says it stopped at its budget ({b.get('stop')})",
    )

    out = subprocess.run(
        [sys.executable, os.path.join(B, "summarize.py"), "--json", results],
        capture_output=True,
        text=True,
    )
    try:
        report = json.loads(out.stdout)
    except ValueError:
        report = {}
    ok(
        bool(report),
        "summarize.py --json parses" + ("" if report else ": " + out.stderr[-300:]),
    )
    dropped = sorted(x["id"] for x in report.get("dropped", []))
    want = sorted(faults[k]["id"] for k in BAD_START if k in faults)
    ok(
        dropped == want,
        f"summarize drops exactly the runs that were not their arm ({len(dropped)})",
    )
    ok(report.get("d3") is not None, "summarize computes D3")
    print(f"---- dry run: {failures} failure(s)")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main(*sys.argv[1:3]))
