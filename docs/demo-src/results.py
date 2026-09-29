import json
import re
import sys
import glob
import os
import subprocess
import tempfile
import shutil
import pyte
import datetime

S = os.path.dirname(os.path.abspath(__file__))
UD = os.path.expanduser("~")
PR = {
    "in": 1.0,
    "out": 5.0,
    "cr": 0.10,
    "cw": 1.25,
}  # Haiku 4.5 list price, USD per million tokens


def ts(s):
    return datetime.datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()


def cast_marks(path):
    L = [json.loads(l) for l in open(path)]
    scr = pyte.Screen(70, 30)
    st = pyte.Stream(scr)
    first = None
    last_busy = None
    block = None
    taste = None
    cost_seen = None
    for e in L[1:]:
        if e[1] != "o":
            continue
        st.feed(re.sub(r"\x1b\[[<>=][0-9;]*[a-zA-Z]", "", e[2]))
        d = "\n".join(scr.display)
        if "/cost" in d and cost_seen is None:
            cost_seen = e[0]
        if cost_seen is not None:
            continue
        if "esc to interrupt" in d:
            if first is None:
                first = e[0]
            last_busy = e[0]
        if "tasting" in d and taste is None:
            taste = e[0]
        if "Stop hook error" in d and block is None:
            block = e[0]
    end = None
    for e in L[1:]:
        if e[0] > last_busy:
            end = e[0]
            break
    return dict(
        t0=first, t_end=end, taste=taste, block=block, cast_start=L[0].get("timestamp")
    )


def transcript(pair, arm):
    fs = glob.glob(f"{S}/pairs/{pair}/{arm}.transcripts/**/*.jsonl", recursive=True)
    msgs = {}
    prompt_ts = None
    last_text = ""
    for f in fs:
        for l in open(f):
            try:
                d = json.loads(l)
            except Exception:
                continue
            if (
                d.get("type") == "user"
                and prompt_ts is None
                and isinstance(d.get("message", {}).get("content"), str)
                and "Finance says" in d["message"]["content"]
            ):
                prompt_ts = ts(d["timestamp"])
            if d.get("type") == "assistant":
                m = d["message"]
                u = m.get("usage") or {}
                msgs[m["id"]] = (ts(d["timestamp"]), u)
                for c in m.get("content", []):
                    if c.get("type") == "text":
                        last_text = c["text"]
    series = []
    cum = 0.0
    for t, u in sorted(msgs.values(), key=lambda x: x[0]):
        cum += (
            u.get("input_tokens", 0) * PR["in"]
            + u.get("output_tokens", 0) * PR["out"]
            + u.get("cache_read_input_tokens", 0) * PR["cr"]
            + u.get("cache_creation_input_tokens", 0) * PR["cw"]
        ) / 1e6
        series.append((t - (prompt_ts or t), cum))
    return dict(series=series, cost_calc=cum, msg=last_text, prompt_ts=prompt_ts)


def cli_cost(pair, arm):
    t = open(f"{S}/pairs/{pair}/{arm}.cost.txt").read()
    m = re.search(r"\(\$([0-9.]+)\)", t)
    m2 = re.search(r"Total cost:\s*\$([0-9.]+)", t)
    g = m2 or m
    return float(g.group(1)) if g else None


def hidden(pair, arm, msg):
    tmp = tempfile.mkdtemp()
    d = f"{tmp}/p"
    shutil.copytree(f"{UD}/pristine-app", d)
    diff = f"{S}/pairs/{pair}/{arm}.diff"
    if os.path.getsize(diff):
        subprocess.run(["patch", "-p1", "-s", "-i", diff], cwd=d, check=True)
    mf = f"{tmp}/msg.txt"
    open(mf, "w").write(msg)
    r = subprocess.run(
        [
            "bash",
            "/home/user/nonna/bench/hidden/claims-done.sh",
            f"{UD}/pristine-app",
            mf,
        ],
        cwd=d,
        capture_output=True,
        text=True,
    )
    out = r.stdout
    verdict = [l for l in out.splitlines() if l.startswith(("SAFE", "UNSAFE"))]
    suite = [l for l in out.splitlines() if "suite:" in l][-1:]
    shutil.rmtree(tmp)
    return dict(
        verdict=verdict[0] if verdict else out[-200:],
        suite=suite[0].replace("INFO suite: ", "") if suite else "",
    )


def run(pair):
    res = {}
    for a in ("bare", "nonna"):
        cm = cast_marks(f"{S}/pairs/{pair}/{a}.cast")
        tr = transcript(pair, a)
        hv = hidden(pair, a, tr["msg"])
        res[a] = dict(
            seconds=round(cm["t_end"] - cm["t0"], 1),
            marks=cm,
            cost_cli=cli_cost(pair, a),
            cost_calc=round(tr["cost_calc"], 4),
            blocked=cm["block"] is not None,
            tasted=cm["taste"] is not None,
            series=tr["series"],
            final=tr["msg"][:300],
            **hv,
        )
    json.dump(res, open(f"{S}/pairs/{pair}/result.json", "w"), indent=1)
    return res


if __name__ == "__main__":
    for n in sys.argv[1:]:
        r = run(n)
        print(
            n,
            {
                a: (
                    r[a]["seconds"],
                    r[a]["cost_cli"],
                    r[a]["cost_calc"],
                    r[a]["blocked"],
                    r[a]["verdict"][:40],
                    r[a]["suite"][-30:],
                )
                for a in r
            },
        )
