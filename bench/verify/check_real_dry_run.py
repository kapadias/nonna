#!/usr/bin/env python3
"""Check the real suite's dry run (verify/real.sh): each arm the suite registers, on one ticket,
through the stub claude. Prints one line per check; exits 1 if any fails.

usage: check_real_dry_run.py <work-dir> <results-dir>

The stub appends a comment to one source file and claims it is done, so every run must come out
FAIL (the ticket is not done) and not unsafe (nothing is broken). On the way, the run must have had
its own database's settings and never the admin URL, the plugin arms' test gate must have run the
real suite on that database, and the database and the venv must be gone once the run is scored.
"""

import csv
import json
import os
import subprocess
import sys

B = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ARMS = ("none", "plugin-lite", "ponytail+lite")
SETTINGS = {
    "POSTGRES_SERVER",
    "POSTGRES_PORT",
    "POSTGRES_USER",
    "POSTGRES_PASSWORD",
    "POSTGRES_DB",
    "FIRST_SUPERUSER",
    "FIRST_SUPERUSER_PASSWORD",
    "SECRET_KEY",
}
NEVER = {"PG_URL", "REAL_CACHE", "PG_BIN"}
failures = 0


def ok(cond, what):
    global failures
    print(f"{'ok  ' if cond else 'FAIL'} {what}")
    failures += not cond


def scored(path):
    out = {}
    with open(path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            if line.strip() == "---":
                break
            k, sep, v = line.strip().partition("=")
            if sep:
                out[k] = v
    return out


def main(work, results):
    with open(os.path.join(results, "real.tsv"), newline="") as fh:
        rows = list(csv.DictReader(fh, delimiter="\t"))
    ok(
        sorted(r["arm"] for r in rows) == sorted(ARMS),
        f"one run per arm ({sorted(r['arm'] for r in rows)})",
    )
    for r in rows:
        rid = f"real/{r['id']}"
        d = os.path.join(work, "real", r["id"])
        ok(r["fingerprint"].startswith("ok:"), f"{rid}: fingerprint {r['fingerprint']}")
        ok(
            (r["verdict"], r["unsafe"], r["claimed_done"], r["test_left"])
            == ("FAIL", "0", "1", "0"),
            f"{rid}: verdict, unsafe, claimed_done, test_left "
            f"({r['verdict']}, {r['unsafe']}, {r['claimed_done']}, {r['test_left']})",
        )
        hidden = scored(d + ".hidden.txt")
        ok(
            (hidden.get("install"), hidden.get("suite"), hidden.get("accept"))
            == ("1", "1", "0"),
            f"{rid}: it installs, the suite passes, the ticket is not done ({hidden})",
        )
        with open(os.path.join(B, "tasks", "real", r["task"], "prompt.txt")) as fh:
            ticket = fh.read().rstrip("\n")
        with open(os.path.join(B, "tasks", "real", "NOTE")) as fh:
            note = fh.read().rstrip("\n")
        with open(d + ".prompt") as fh:
            ok(
                fh.read() == ticket + "\n\n" + note,
                f"{rid}: the prompt is the ticket, then the note",
            )
        with open(os.path.join(d + ".cfg", "stub-invocation.json")) as fh:
            env = set(json.load(fh)["env"])
        ok(SETTINGS <= env, f"{rid}: the run had its database's settings")
        ok(not (NEVER & env), f"{rid}: and none of run.sh's ({sorted(NEVER & env)})")
        gone = [
            p
            for p in (d + ".db", d + ".env", os.path.join(d, ".venv"))
            if os.path.exists(p)
        ]
        ok(not gone, f"{rid}: its database and venv are gone ({gone})")
        if r["arm"] == "none":
            ok(r["gate_kinds"] == "-", f"{rid}: no gate fired ({r['gate_kinds']})")
        else:
            ok(
                r["gate_kinds"] == "stop-notest:1",
                f"{rid}: the test gate passed and where's the test? fired ({r['gate_kinds']})",
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
    real = report.get("real") or {}
    ok(
        all(real.get(a, {}).get("n") == 1 for a in ARMS)
        and real.get("lite_below_bare") is False,
        f"summarize.py --json reports the real suite's rule ({real or out.stderr[-300:]})",
    )
    print(f"---- real dry run: {failures} failure(s)")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main(*sys.argv[1:3]))
