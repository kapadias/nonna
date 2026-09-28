"""The benchmark harness's own golden tests. No API calls, no network.

usage: python3 -m pytest -q bench/verify/test_harness.py    (verify.sh runs it first)

Fixtures live in verify/fixtures/. Each gate fixture line is one stream-json event plus "_expect",
what lib/gates.py must print for a transcript holding only that event.
"""

import json
import os
import sys

import pytest

V = os.path.dirname(os.path.abspath(__file__))
B = os.path.dirname(V)
FIX = os.path.join(V, "fixtures")
sys.path.insert(0, os.path.join(B, "lib"))
import gates  # noqa: E402


def events(path):
    with open(path, encoding="utf-8") as fh:
        return [json.loads(line) for line in fh if line.strip()]


GATE_CASES = [
    pytest.param(name, i, ev, id=f"{name}-{i}-{ev['_expect'].split(chr(9))[1]}")
    for name in ("legacy", "new")
    for i, ev in enumerate(events(os.path.join(FIX, "gates", name + ".jsonl")))
]


@pytest.mark.parametrize("name,i,ev", GATE_CASES)
def test_gate_kind(name, i, ev, tmp_path):
    """legacy: the round 1-2 hooks' messages score as they always did, so old runs rescore the same.
    new: the round-3 hooks' messages get their own kinds."""
    p = tmp_path / "run.stream.jsonl"
    p.write_text(json.dumps(ev) + "\n", encoding="utf-8")
    n, kinds = gates.count(str(p))
    assert f"{n}\t{kinds}" == ev["_expect"]


@pytest.mark.parametrize("name", ["legacy", "new"])
def test_gate_counts_add_up(name):
    """A whole transcript counts every block once and sums the kinds."""
    evs = events(os.path.join(FIX, "gates", name + ".jsonl"))
    want = {}
    for ev in evs:
        n, kinds = ev["_expect"].split("\t")
        if kinds != "-":
            k, v = kinds.split(":")
            want[k] = want.get(k, 0) + int(v)
    n, kinds = gates.count(os.path.join(FIX, "gates", name + ".jsonl"))
    assert n == sum(want.values())
    assert kinds == ";".join(f"{k}:{v}" for k, v in sorted(want.items()))


def test_gate_missing_transcript(tmp_path):
    assert gates.count(str(tmp_path / "absent.jsonl")) == (-1, "-")
