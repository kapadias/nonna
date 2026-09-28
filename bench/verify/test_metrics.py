"""lib/metrics.py: one TSV row per run. Round 3's columns come after the 22 old ones, so every old
column keeps its position and rounds 1-2 rescore the same."""

import json
import os
import shutil
import subprocess
import sys

V = os.path.dirname(os.path.abspath(__file__))
B = os.path.dirname(V)
METRICS = os.path.join(B, "lib", "metrics.py")
OLD = (
    "id suite task arm model rep verdict unsafe gate_fired gate_kinds claimed_done test_left "
    "src_loc cost_usd wall_s turns rc lane security branch commits harness"
).split()
NEW = (
    "prompt label fingerprint model_resolved cc_version stop tokens_in tokens_out "
    "tokens_cache_read tokens_cache_write subagents subagent_types"
).split()


def git(d, *a):
    return subprocess.run(
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
        text=True,
    ).stdout


def usage(i, o, r, w):
    return {
        "inputTokens": i,
        "outputTokens": o,
        "cacheReadInputTokens": r,
        "cacheCreationInputTokens": w,
    }


def tool(name, **inp):
    return {
        "type": "assistant",
        "message": {
            "role": "assistant",
            "content": [
                {"type": "tool_use", "id": "toolu_" + name, "name": name, "input": inp}
            ],
        },
    }


INIT = {
    "type": "system",
    "subtype": "init",
    "cwd": "/w",
    "model": "claude-haiku-4-5-20251001",
    "claude_code_version": "2.1.283",
    "plugins": [],
    "mcp_servers": [],
}
NOTEST = {
    "type": "system",
    "subtype": "hook_response",
    "hook_name": "Stop",
    "hook_event": "Stop",
    "stdout": json.dumps(
        {
            "decision": "block",
            "reason": "✗ Nonna: where's the test? (stop: code changed, no test changed)\n",
        }
    ),
    "stderr": "",
    "exit_code": 0,
}
MAIN = {
    "type": "result",
    "subtype": "success",
    "total_cost_usd": 0.12,
    "num_turns": 7,
    "result": "Done.",
    "modelUsage": {"claude-haiku-4-5-20251001": usage(100, 50, 1000, 200)},
}
LATER = {
    "type": "result",
    "subtype": "success",
    "total_cost_usd": 0.15,
    "num_turns": 2,
    "result": "",
    "modelUsage": {
        "claude-haiku-4-5-20251001": usage(110, 60, 1100, 210),
        "claude-sonnet-5": usage(10, 5, 0, 20),
    },
}
STREAM = [
    INIT,
    tool("Agent", subagent_type="Explore", prompt="find it"),
    tool("Task", subagent_type="general-purpose"),
    tool("Agent", prompt="no type given"),
    tool("Bash", command="ls"),
    NOTEST,
    MAIN,
    LATER,
]


def make_run(tmp, name="d3-plugin-lite-haiku-1", stream=STREAM):
    d = tmp / name
    (d / "app").mkdir(parents=True)
    (d / "tests").mkdir()
    (d / "app" / "__init__.py").write_text("")
    (d / "app" / "x.py").write_text("def f():\n    return 1\n")
    git(d, "init", "-q", "-b", "main")
    git(d, "add", "-A")
    git(d, "commit", "-qm", "scaffold")
    shutil.copytree(d, str(d) + ".pristine", ignore=shutil.ignore_patterns(".git"))
    base = git(d, "rev-parse", "HEAD").strip()
    git(d, "checkout", "-qb", "feature/work")
    (d / "app" / "x.py").write_text(
        "def f():\n    # two, per the ticket\n    return 2\n"
    )  # +2 -1
    (d / "app" / "extra.py").write_text("A = 1\nB = 2\n")  # untracked source: 2 lines
    (d / "tests" / "test_x.py").write_text(
        "from app.x import f\n\n\ndef test_f():\n    assert f() == 2\n"
    )
    open(str(d) + ".base", "w").write(base + "\n")
    if stream is not None:
        open(str(d) + ".stream.jsonl", "w").write(
            "\n".join(json.dumps(e) for e in stream) + "\n"
        )
    return d


def row(d, *extra, arm="plugin-lite", suite="small", task="d3"):
    out = (
        subprocess.run(
            [
                sys.executable,
                METRICS,
                suite,
                task,
                arm,
                "haiku",
                "1",
                str(d),
                "pass",
                "0",
                "42",
                "nonna@abc1234",
                *extra,
            ],
            capture_output=True,
            text=True,
            check=True,
        )
        .stdout.rstrip("\n")
        .split("\t")
    )
    header = OLD + NEW
    assert len(out) == len(header), out
    return dict(zip(header, out))


def test_header_keeps_the_old_columns_first():
    out = subprocess.run(
        [sys.executable, METRICS, "--header"], capture_output=True, text=True
    ).stdout
    assert out.rstrip("\n").split("\t") == OLD + NEW


def test_a_round_3_run(tmp_path):
    d = make_run(tmp_path)
    open(str(d) + ".fingerprint", "w").write("ok:0123abcd\n")
    r = row(d, "neutral", "-")
    assert r == {
        "id": "d3-plugin-lite-haiku-1",
        "suite": "small",
        "task": "d3",
        "arm": "plugin-lite",
        "model": "haiku",
        "rep": "1",
        "verdict": "pass",
        "unsafe": "-",
        "gate_fired": "1",
        "gate_kinds": "stop-notest:1",
        "claimed_done": "-",
        "test_left": "1",
        "src_loc": "5",
        "cost_usd": "0.1500",
        "wall_s": "42",
        "turns": "9",
        "rc": "0",
        "lane": "-",
        "security": "-",
        "branch": "feature/work",
        "commits": "0",
        "harness": "nonna@abc1234",
        "prompt": "neutral",
        "label": "-",
        "fingerprint": "ok:0123abcd",
        "model_resolved": "claude-haiku-4-5-20251001",
        "cc_version": "2.1.283",
        "stop": "success",
        "tokens_in": "120",
        "tokens_out": "65",
        "tokens_cache_read": "1100",
        "tokens_cache_write": "230",
        "subagents": "3",
        "subagent_types": "Explore=1;general-purpose=2",
    }


def test_the_id_is_the_run_dir_so_a_labelled_rerun_is_its_own_row(tmp_path):
    d = make_run(tmp_path, name="no-test-plugin-lite-haiku-1-rerun1")
    r = row(d, "neutral", "rerun1", suite="traps", task="no-test")
    assert (r["id"], r["label"]) == ("no-test-plugin-lite-haiku-1-rerun1", "rerun1")


def test_subagent_stats_win_when_the_cli_reports_them(tmp_path):
    later = dict(
        LATER,
        subagent_stats={
            "spawned": 4,
            "by_type": {"Explore": 1, "nonna:code-reviewer": 3},
        },
    )
    d = make_run(tmp_path, stream=STREAM[:-1] + [later])
    r = row(d, "review", "-")
    assert (r["subagents"], r["subagent_types"]) == (
        "4",
        "Explore=1;nonna:code-reviewer=3",
    )


def test_a_run_stopped_by_a_limit_says_which(tmp_path):
    over = dict(MAIN, subtype="error_max_budget_usd", total_cost_usd=3.01)
    d = make_run(tmp_path, stream=[INIT, over, LATER])
    assert row(d, "neutral", "-")["stop"] == "error_max_budget_usd"


def test_a_run_with_no_stream_reads_as_unknown(tmp_path):
    d = make_run(tmp_path, stream=None)
    r = row(d, "neutral", "-")
    assert (r["cost_usd"], r["turns"], r["gate_fired"]) == ("-1.0000", "-1", "-1")
    assert all(
        r[k] == "-"
        for k in (
            "fingerprint",
            "model_resolved",
            "cc_version",
            "stop",
            "tokens_in",
            "tokens_out",
            "tokens_cache_read",
            "tokens_cache_write",
            "subagents",
            "subagent_types",
        )
    )


def test_old_callers_get_dashes_for_prompt_and_label(tmp_path):
    d = make_run(tmp_path)
    r = row(d)
    assert (r["prompt"], r["label"]) == ("-", "-")
