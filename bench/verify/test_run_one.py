"""lib/run-one.sh: one run, cut off from the machine it runs on and watched from its first event.

Every run here is the stub claude (verify/stub/claude), which is also first on PATH as `claude`, so
nothing here can reach the real CLI: no model, no network. The environment carries what a developer's
shell may export, and none of it may reach the run.
"""

import csv
import json
import os
import subprocess
import time

import pytest

V = os.path.dirname(os.path.abspath(__file__))
B = os.path.dirname(V)
ROOT = os.path.dirname(B)
STUB = os.path.join(V, "stub", "claude")
PONY = os.path.join(V, "fixtures", "ponytail-fake")
LEAKS = {
    "NONNA_MODE": "off",
    "NONNA_TEST_CMD": "",
    "CLAUDECODE": "1",
    "CLAUDE_CODE_ENTRYPOINT": "cli",
    "CLAUDE_PLUGIN_OPTION_MODE": "full",
    "ANTHROPIC_BASE_URL": "http://127.0.0.1:9",
}


@pytest.fixture(scope="module")
def snaps(tmp_path_factory):
    t = tmp_path_factory.mktemp("snap")
    sha = subprocess.run(
        ["git", "-C", ROOT, "rev-parse", "--short", "HEAD"],
        capture_output=True,
        text=True,
        check=True,
    ).stdout.strip()
    nonna = t / f"nonna-{sha}"
    nonna.mkdir()
    archive = subprocess.run(
        ["git", "-C", ROOT, "archive", "HEAD", ".claude"],
        capture_output=True,
        check=True,
    )
    subprocess.run(["tar", "-x", "-C", str(nonna)], input=archive.stdout, check=True)
    bindir = t / "bin"
    bindir.mkdir()
    (bindir / "claude").symlink_to(STUB)
    return {
        "NONNA_SNAP": str(nonna / ".claude"),
        "NONNA_SHA": sha,
        "PONYTAIL_SNAP": PONY,
        "PONYTAIL_SHA": "fake",
        "bin": str(bindir),
    }


def run_one(tmp_path, snaps, suite, task, arm, claude=STUB, **env):
    work, results = tmp_path / "work", tmp_path / "results"
    e = dict(os.environ)
    e.update(LEAKS)
    e.update(
        PATH=snaps["bin"] + os.pathsep + e["PATH"],
        WORK=str(work),
        RESULTS=str(results),
        CAP="150",
        TIMEOUT="60",
        MAX_TURNS="5",
        RUN_BUDGET="3",
        PROMPT_MODE="neutral",
        LABEL="",
        CLAUDE_BIN=claude,
        ANTHROPIC_API_KEY="FAKE-stub-not-a-key",
        HARNESS_REPO=ROOT,
        HARNESS_REF="HEAD",
        INSTALLER="",
        **{k: v for k, v in snaps.items() if k != "bin"},
    )
    e.update(env)
    t0 = time.monotonic()
    r = subprocess.run(
        ["bash", os.path.join(B, "lib", "run-one.sh"), suite, task, arm, "haiku", "1"],
        env=e,
        capture_output=True,
        text=True,
        timeout=300,
    )
    took = time.monotonic() - t0
    assert r.returncode == 0, r.stderr
    with open(results / f"{suite}.tsv", newline="") as fh:
        rows = list(csv.DictReader(fh, delimiter="\t"))
    d = work / suite / rows[-1]["id"]
    inv = {}
    if os.path.exists(f"{d}.cfg/stub-invocation.json"):
        with open(f"{d}.cfg/stub-invocation.json") as fh:
            inv = json.load(fh)
    return rows[-1], d, inv, took


def flag(inv, name):
    a = inv["argv"]
    return [a[i + 1] for i, x in enumerate(a) if x == name]


def test_a_plugin_run_is_cut_off_and_watched(tmp_path, snaps):
    row, d, inv, _ = run_one(tmp_path, snaps, "traps", "no-test", "plugin-lite")
    assert row.get("fingerprint", "").startswith("ok:"), (
        row.get("fingerprint"),
        open(f"{d}.err.txt").read(),
    )
    assert (row["stop"], row["model_resolved"], row["cc_version"]) == (
        "success",
        "claude-haiku-stub",
        "stub",
    )
    assert row["harness"] == "nonna@" + snaps["NONNA_SHA"]
    assert row["gate_kinds"].startswith("stop-"), row["gate_kinds"]
    assert flag(inv, "--plugin-dir") == [snaps["NONNA_SNAP"]]
    assert flag(inv, "--setting-sources") == ["project,local"]
    assert flag(inv, "--max-budget-usd") == ["3"]
    assert flag(inv, "--model") == ["haiku"]
    assert "--strict-mcp-config" in inv["argv"]
    (sid,) = flag(inv, "--session-id")
    assert set(LEAKS).isdisjoint(inv["env"])
    assert "ANTHROPIC_API_KEY" in inv["env"]
    assert os.path.exists(f"{d}.transcripts/{sid}.jsonl")


def test_ponytail_lite_loads_both_as_a_returning_user(tmp_path, snaps):
    row, d, inv, _ = run_one(tmp_path, snaps, "small", "d3", "ponytail+lite")
    assert row.get("fingerprint", "").startswith("ok:"), row.get("fingerprint")
    assert flag(inv, "--plugin-dir") == [PONY, snaps["NONNA_SNAP"]]
    assert os.path.exists(f"{d}.cfg/.ponytail-statusline-nudged")
    assert row["harness"] == f"nonna@{snaps['NONNA_SHA']}+ponytail@fake"
    assert row["prompt"] == "neutral"


def test_a_bare_run_loads_nothing(tmp_path, snaps):
    row, d, inv, _ = run_one(tmp_path, snaps, "traps", "refactor", "none")
    assert row.get("fingerprint", "").startswith("ok:"), row.get("fingerprint")
    assert flag(inv, "--plugin-dir") == []
    assert (row["gate_fired"], row["gate_kinds"]) == ("0", "-")


def test_the_copy_in_arm_runs_the_project_hooks(tmp_path, snaps):
    row, d, inv, _ = run_one(tmp_path, snaps, "traps", "refactor", "nonna")
    assert row.get("fingerprint", "").startswith("ok:"), row.get("fingerprint")
    assert flag(inv, "--plugin-dir") == []


def test_a_mismatched_run_is_stopped_before_it_costs_more(tmp_path, snaps):
    fault = os.path.join(V, "stub", "fault", "extra-plugin", "claude")
    row, d, inv, took = run_one(
        tmp_path, snaps, "traps", "refactor", "plugin-lite", claude=fault
    )
    assert row.get("fingerprint", "").startswith("mismatch:plugins"), row.get(
        "fingerprint"
    )
    assert row["rc"] == "86"
    assert not os.path.exists(f"{d}.cfg/stub-survived")
    assert took < 60


def test_a_labelled_rerun_gets_its_own_run_dir(tmp_path, snaps):
    row, d, inv, _ = run_one(
        tmp_path, snaps, "traps", "refactor", "none", LABEL="rerun1"
    )
    assert row["id"] == "refactor-none-haiku-1-rerun1"
    assert row["label"] == "rerun1"
