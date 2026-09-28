"""lib/fingerprint.py: a run is the arm it claims to be, or it is stopped before it costs more.

The fixtures in verify/fixtures/fp/ are the start of real Claude Code 2.1.283 stream-json runs, one
per arm, recorded offline (no request could leave the machine) and trimmed at the init event, with
their directories rewritten to /work/run. ponytail-nudge is the ponytail arm on a fresh config dir
whose statusline flag was never set.
"""

import copy
import json
import os
import re
import signal
import subprocess
import sys
import time

import pytest

V = os.path.dirname(os.path.abspath(__file__))
B = os.path.dirname(V)
FP = os.path.join(V, "fixtures", "fp")
sys.path.insert(0, os.path.join(B, "lib"))
import fingerprint  # noqa: E402

SNAP = {"nonna": "/work/run/snap/nonna/.claude", "ponytail": "/work/run/snap/ponytail"}
FIXTURE_ARM = {
    "none": "none",
    "nonna": "nonna",
    "plugin-lite": "plugin-lite",
    "plugin-full": "plugin-full",
    "ponytail": "ponytail",
    "ponytail-lite": "ponytail+lite",
}


def events(name):
    with open(os.path.join(FP, name + ".jsonl"), encoding="utf-8") as fh:
        return [json.loads(line) for line in fh if line.strip()]


def spec(arm, **kw):
    s = {
        "arm": arm,
        "model": "haiku",
        "cwd": "/work/run/proj",
        "test_cmd": "python3 -m pytest -q",
        "plugins": {n: SNAP[n] for n in sorted(fingerprint.ARMS[arm][0])},
    }
    s.update(kw)
    return s


def init_of(evs):
    return next(e for e in evs if e.get("subtype") == "init")


def with_init(name, **fields):
    evs = copy.deepcopy(events(name))
    init_of(evs).update(fields)
    return evs


def session_starts(evs):
    return [
        e
        for e in evs
        if e.get("subtype") == "hook_response" and e.get("hook_event") == "SessionStart"
    ]


def edit_session_start(name, marker, old, new):
    """The SessionStart response containing `marker`, with `old` replaced by `new`."""
    evs = copy.deepcopy(events(name))
    hit = [e for e in session_starts(evs) if marker in e["stdout"]]
    assert len(hit) == 1
    for k in ("stdout", "output"):
        assert old in hit[0][k]
        hit[0][k] = hit[0][k].replace(old, new)
    return evs


ASSISTANT = {
    "type": "assistant",
    "message": {"role": "assistant", "content": [{"type": "text", "text": "hi"}]},
}


@pytest.mark.parametrize("name,arm", FIXTURE_ARM.items())
def test_each_real_stream_is_its_own_arm(name, arm):
    verdict, detail = fingerprint.check(events(name), spec(arm), final=True)
    assert verdict == "ok", detail
    assert re.fullmatch(r"[0-9a-f]{8}", detail)


@pytest.mark.parametrize(
    "name,arm",
    [(n, a) for n in FIXTURE_ARM for a in fingerprint.ARMS if a != FIXTURE_ARM[n]],
)
def test_no_real_stream_passes_as_another_arm(name, arm):
    verdict, detail = fingerprint.check(events(name), spec(arm), final=True)
    assert verdict == "mismatch", f"{name} passed as {arm}"


BUILTIN = {"name": "agents-md", "path": "builtin", "source": "agents-md@builtin"}
NONNA_INLINE = {
    "name": "nonna",
    "path": SNAP["nonna"],
    "source": "nonna@inline",
    "version": "2.0.0",
}
MUTATIONS = {
    # an init field that makes the run something other than its arm -> the reason names it
    "extra plugin": (
        with_init("none", plugins=[NONNA_INLINE, BUILTIN]),
        "none",
        "plugins",
    ),
    "missing plugin": (
        with_init(
            "ponytail-lite",
            plugins=[init_of(events("ponytail-lite"))["plugins"][0], BUILTIN],
        ),
        "ponytail+lite",
        "plugins",
    ),
    "plugin from elsewhere": (
        with_init(
            "plugin-lite",
            plugins=[dict(NONNA_INLINE, path="/home/u/nonna/.claude"), BUILTIN],
        ),
        "plugin-lite",
        "not the snapshot",
    ),
    "plugin from a marketplace": (
        with_init(
            "plugin-lite", plugins=[dict(NONNA_INLINE, source="nonna@nonna"), BUILTIN]
        ),
        "plugin-lite",
        "nonna@nonna",
    ),
    "plugin error": (
        with_init(
            "plugin-lite",
            plugin_errors=[
                {"plugin": "nonna", "type": "hooks", "message": "bad hooks.json"}
            ],
        ),
        "plugin-lite",
        "bad hooks.json",
    ),
    "MCP server": (
        with_init("none", mcp_servers=[{"name": "github", "status": "connected"}]),
        "none",
        "MCP",
    ),
    "subscription login": (
        with_init("none", apiKeySource="none"),
        "none",
        "apiKeySource",
    ),
    "permission mode": (
        with_init("none", permissionMode="default"),
        "none",
        "permissionMode",
    ),
    "model family": (with_init("none", model="claude-sonnet-5"), "none", "model"),
    "cwd": (with_init("none", cwd="/work/run/other"), "none", "cwd"),
    # SessionStart
    "Nonna in the wrong mode": (
        events("plugin-full"),
        "plugin-lite",
        "Nonna is on (full)",
    ),
    "test gate off": (
        edit_session_start(
            "plugin-lite",
            "Nonna is on",
            "Test gate: python3 -m pytest -q runs",
            "Test gate: off, no test command found here. Runs",
        ),
        "plugin-lite",
        "test gate",
    ),
    "test gate on another command": (events("plugin-lite"), "plugin-lite", "test gate"),
    "Nonna warns": (
        edit_session_start(
            "plugin-lite",
            "Nonna is on",
            "Detected stack: python.",
            "Detected stack: python. WARNING: .git/hooks/pre-push is not Nonna's;",
        ),
        "plugin-lite",
        "WARNING",
    ),
    "statusline nudge": (events("ponytail-nudge"), "ponytail", "statusline"),
    "ponytail in a Nonna arm": (events("ponytail-lite"), "plugin-lite", "plugins"),
    "a failed SessionStart hook": (
        [
            dict(e, exit_code=1)
            if e.get("hook_event") == "SessionStart"
            and e.get("subtype") == "hook_response"
            else e
            for e in events("plugin-lite")
        ],
        "plugin-lite",
        "exit 1",
    ),
    "a foreign SessionStart hook": (
        events("plugin-lite")[:1]
        + [
            dict(
                session_starts(events("plugin-lite"))[0],
                stdout="team bootstrap ok",
                output="team bootstrap ok",
            )
        ]
        + events("plugin-lite")[1:],
        "plugin-lite",
        "unexpected SessionStart",
    ),
    "any SessionStart in the bare arm": (
        [dict(session_starts(events("plugin-lite"))[0], stdout="hello", output="hello")]
        + events("none"),
        "none",
        "unexpected SessionStart",
    ),
}


@pytest.mark.parametrize("case", MUTATIONS)
def test_each_rule_stops_a_run(case):
    evs, arm, why = MUTATIONS[case]
    s = (
        spec(arm, test_cmd="pytest -x")
        if case == "test gate on another command"
        else spec(arm)
    )
    verdict, detail = fingerprint.check(evs, s, final=True)
    assert verdict == "mismatch"
    assert why.lower() in detail.lower(), detail


def test_the_model_alias_may_be_a_full_id():
    assert (
        fingerprint.check(
            events("none"), spec("none", model="claude-haiku-4-5"), final=True
        )[0]
        == "ok"
    )
    assert (
        fingerprint.check(
            events("none"), spec("none", model="claude-haiku-4-5-20251001"), final=True
        )[0]
        == "ok"
    )
    assert (
        fingerprint.check(events("none"), spec("none", model="sonnet"), final=True)[0]
        == "mismatch"
    )


def test_a_mismatch_at_init_needs_no_model_call():
    """The init event alone decides a wrong plugin set: no assistant event is waited for."""
    evs = with_init("none", plugins=[NONNA_INLINE, BUILTIN])
    assert fingerprint.check(evs, spec("none"))[0] == "mismatch"


def test_a_missing_marker_waits_for_the_first_call_then_stops():
    init = init_of(events("plugin-lite"))
    late = [init] + session_starts(events("plugin-lite"))
    assert fingerprint.check([init], spec("plugin-lite")) == ("pending", "")
    assert fingerprint.check(late, spec("plugin-lite"))[0] == "ok"
    verdict, detail = fingerprint.check([init, ASSISTANT], spec("plugin-lite"))
    assert verdict == "mismatch" and "no SessionStart from Nonna" in detail


def test_no_init_is_pending_until_the_stream_ends():
    ss = session_starts(events("plugin-lite"))
    assert fingerprint.check(ss, spec("plugin-lite")) == ("pending", "")
    verdict, detail = fingerprint.check(ss, spec("plugin-lite"), final=True)
    assert verdict == "mismatch" and "init" in detail


def test_the_hash_names_the_configuration_not_the_run():
    base = fingerprint.check(events("plugin-lite"), spec("plugin-lite"))[1]
    other_run = with_init(
        "plugin-lite",
        session_id="99999999-2222-4333-8444-555555555555",
        uuid="x",
        cwd="/work/run2/proj",
    )
    assert (
        fingerprint.check(other_run, spec("plugin-lite", cwd="/work/run2/proj"))[1]
        == base
    )
    bumped = with_init(
        "plugin-lite", plugins=[dict(NONNA_INLINE, version="2.0.1"), BUILTIN]
    )
    assert fingerprint.check(bumped, spec("plugin-lite"))[1] != base
    newer = with_init("plugin-lite", model="claude-haiku-5")
    assert fingerprint.check(newer, spec("plugin-lite"))[1] != base


def test_spec_names_a_known_arm():
    with pytest.raises(ValueError):
        fingerprint.check(events("none"), dict(spec("none"), arm="nonna-lite"))


# ---------------------------------------------------------------- the launcher
FAKE = r"""
import os, sys, time
sys.stdout.write(open(sys.argv[1]).read()); sys.stdout.flush()
open(sys.argv[2], "w").write(str(os.getpid()))
time.sleep(float(sys.argv[3]))
open(sys.argv[2] + ".survived", "w").write("1")
"""


def launch(tmp_path, fixture, arm, hang, timeout=30):
    """Run a fake claude that prints a fixture stream, then hangs, under `fingerprint.py run`."""
    st, pidf = tmp_path / "run.stream.jsonl", tmp_path / "pid"
    specf = tmp_path / "spec.json"
    specf.write_text(json.dumps(spec(arm)))
    src = os.path.join(FP, fixture + ".jsonl") if fixture else os.devnull
    cmd = [
        sys.executable,
        os.path.join(B, "lib", "fingerprint.py"),
        "run",
        str(specf),
        str(st),
        str(tmp_path / "err.txt"),
        str(tmp_path / "verdict"),
        str(timeout),
        "--",
        sys.executable,
        "-c",
        FAKE,
        src,
        str(pidf),
        str(hang),
    ]
    return subprocess.Popen(cmd), pidf, tmp_path / "verdict"


def alive(pid):
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    return True


def test_launcher_passes_a_good_run_through(tmp_path):
    p, pidf, verdict = launch(tmp_path, "plugin-lite", "plugin-lite", 0)
    assert p.wait(30) == 0
    assert verdict.read_text().startswith("ok:")
    assert (tmp_path / "pid.survived").exists()


def test_launcher_kills_a_mismatched_run_at_once(tmp_path):
    t0 = time.monotonic()
    p, pidf, verdict = launch(tmp_path, "none", "plugin-lite", 20)
    assert p.wait(30) == fingerprint.ABORTED
    assert time.monotonic() - t0 < 10
    assert verdict.read_text().startswith("mismatch:")
    assert not alive(int(pidf.read_text()))
    assert not (tmp_path / "pid.survived").exists()


def test_launcher_enforces_the_timeout(tmp_path):
    p, pidf, verdict = launch(tmp_path, "plugin-lite", "plugin-lite", 30, timeout=2)
    assert p.wait(30) == 124
    assert verdict.read_text().startswith("ok:")
    assert not alive(int(pidf.read_text()))


def test_launcher_rejects_a_run_that_ends_before_init(tmp_path):
    p, pidf, verdict = launch(tmp_path, None, "plugin-lite", 0)
    assert p.wait(30) == 0
    assert verdict.read_text().startswith("mismatch:")


def test_launcher_takes_its_run_down_when_it_is_stopped(tmp_path):
    p, pidf, verdict = launch(tmp_path, "plugin-lite", "plugin-lite", 30)
    for _ in range(200):
        if pidf.exists() and pidf.read_text():
            break
        time.sleep(0.05)
    child = int(pidf.read_text())
    p.send_signal(signal.SIGTERM)
    assert p.wait(30) == 128 + signal.SIGTERM
    for _ in range(100):
        if not alive(child):
            break
        time.sleep(0.05)
    assert not alive(child)
