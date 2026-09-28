"""run.sh: what it refuses before any run starts, and a small dry run end to end.

A paid run is never started here. Every case either stops before launching anything or is a
--dry-run (the stub claude); the stub is also first on PATH as `claude`, and no API key is set.
"""

import csv
import os
import shutil
import subprocess

import pytest

V = os.path.dirname(os.path.abspath(__file__))
B = os.path.dirname(V)
ROOT = os.path.dirname(B)
STUB = os.path.join(V, "stub", "claude")
OLD_HEADER = (
    "id\tsuite\ttask\tarm\tmodel\trep\tverdict\tunsafe\tgate_fired\tgate_kinds\tclaimed_done\ttest_left\t"
    "src_loc\tcost_usd\twall_s\tturns\trc\tlane\tsecurity\tbranch\tcommits\tharness\n"
)


@pytest.fixture(scope="module")
def stub_path(tmp_path_factory):
    d = tmp_path_factory.mktemp("bin")
    (d / "claude").symlink_to(STUB)
    return str(d) + os.pathsep + os.environ["PATH"]


def run(stub_path, *args, bench=B, **env):
    e = {k: v for k, v in os.environ.items() if k != "ANTHROPIC_API_KEY"}
    e.update(PATH=stub_path, **env)
    return subprocess.run(
        ["bash", os.path.join(bench, "run.sh"), *args],
        env=e,
        capture_output=True,
        text=True,
        timeout=600,
    )


def git(d, *a):
    subprocess.run(
        [
            "git",
            "-C",
            str(d),
            "-c",
            "user.name=dev",
            "-c",
            "user.email=dev@example.com",
            "-c",
            "commit.gpgsign=false",
            *a,
        ],
        check=True,
        capture_output=True,
    )


@pytest.mark.parametrize(
    "args,msg",
    [
        (["--arm", "nonna-lite"], "unknown arm"),
        (["--prompt", "polite"], "unknown prompt"),
        (["--suite", "traps", "--tasks", "nope"], "no task"),
    ],
)
def test_bad_arguments_are_refused(stub_path, tmp_path, args, msg):
    r = run(
        stub_path,
        *args,
        "--dry-run",
        "--work",
        str(tmp_path / "w"),
        "--results",
        str(tmp_path / "r"),
    )
    assert r.returncode == 2 and msg in r.stderr, r.stderr


def test_a_results_file_with_another_header_is_refused(stub_path, tmp_path):
    res = tmp_path / "r"
    res.mkdir()
    (res / "traps.tsv").write_text(OLD_HEADER)
    r = run(
        stub_path,
        "--dry-run",
        "--arm",
        "none",
        "--tasks",
        "refactor",
        "--reps",
        "1",
        "--work",
        str(tmp_path / "w"),
        "--results",
        str(res),
    )
    assert r.returncode == 2 and "header" in r.stderr, r.stderr
    assert (res / "traps.tsv").read_text() == OLD_HEADER


def test_a_dirty_ponytail_checkout_is_refused(stub_path, tmp_path):
    pony = tmp_path / "ponytail"
    shutil.copytree(os.path.join(V, "fixtures", "ponytail-fake"), pony)
    git(pony, "init", "-q")
    git(pony, "add", "-A")
    git(pony, "commit", "-qm", "fake")
    (pony / "hooks" / "hooks.json").write_text("{}\n")
    r = run(
        stub_path,
        "--dry-run",
        "--arm",
        "ponytail",
        "--ponytail",
        str(pony),
        "--tasks",
        "refactor",
        "--reps",
        "1",
        "--work",
        str(tmp_path / "w"),
        "--results",
        str(tmp_path / "r"),
    )
    assert r.returncode == 2 and "uncommitted" in r.stderr, r.stderr


def test_a_paid_run_needs_the_preregistration_a_clean_bench_and_an_api_key(
    stub_path, tmp_path
):
    repo = tmp_path / "repo"
    shutil.copytree(
        B, repo / "bench", ignore=shutil.ignore_patterns("__pycache__", "results")
    )
    (repo / "bench" / "PREREGISTRATION.md").unlink(missing_ok=True)
    git(repo, "init", "-q")
    git(repo, "add", "-A")
    git(repo, "commit", "-qm", "bench")
    args = [
        "--arm",
        "none",
        "--tasks",
        "refactor",
        "--reps",
        "1",
        "--work",
        str(tmp_path / "w"),
        "--results",
        str(tmp_path / "r"),
    ]
    bench = str(repo / "bench")

    r = run(stub_path, *args, bench=bench)
    assert r.returncode == 2 and "PREREGISTRATION.md" in r.stderr, r.stderr
    (repo / "bench" / "PREREGISTRATION.md").write_text("# D3\n")
    r = run(stub_path, *args, bench=bench)
    assert r.returncode == 2 and "PREREGISTRATION.md" in r.stderr, r.stderr
    git(repo, "add", "-A")
    git(repo, "commit", "-qm", "preregistration")
    (repo / "bench" / "lib" / "scratch.py").write_text("x = 1\n")
    r = run(stub_path, *args, bench=bench)
    assert r.returncode == 2 and "not clean" in r.stderr, r.stderr
    (repo / "bench" / "lib" / "scratch.py").unlink()
    r = run(stub_path, *args, bench=bench)
    assert r.returncode == 2 and "ANTHROPIC_API_KEY" in r.stderr, r.stderr
    assert not (tmp_path / "w").exists() or not any(
        (tmp_path / "w").rglob("*.stream.jsonl")
    )


def test_a_dry_run_end_to_end(stub_path, tmp_path):
    res = tmp_path / "r"
    r = run(
        stub_path,
        "--dry-run",
        "--arm",
        "none,plugin-lite",
        "--suite",
        "traps",
        "--tasks",
        "refactor",
        "--reps",
        "1",
        "--work",
        str(tmp_path / "w"),
        "--results",
        str(res),
    )
    assert r.returncode == 0, r.stderr
    with open(res / "traps.tsv", newline="") as fh:
        rows = list(csv.DictReader(fh, delimiter="\t"))
    assert sorted(x["arm"] for x in rows) == ["none", "plugin-lite"]
    assert all(x["fingerprint"].startswith("ok:") for x in rows), [
        x["fingerprint"] for x in rows
    ]
    assert all(x["prompt"] == "neutral" for x in rows)
    with open(res / "batches.tsv") as fh:
        log = fh.read().splitlines()
    assert log[0].split("\t") == ["started", "bench_sha", "claude_version", "argv"]
    assert "--dry-run" in log[-1] and "stub" in log[-1]
