"""Copy the film, the recordings and the scripts into the repo, and write docs/demo.md.
usage: assemble.py <out-prefix>   (expects <out>.mp4 and <out>.gif next to this file)"""

import glob
import json
import os
import re
import shutil
import statistics as st
import subprocess
import sys

S = os.path.dirname(os.path.abspath(__file__))
REPO = "/home/user/nonna"
OUT = sys.argv[1]
os.chdir(S)
key = os.environ["NONNA_BENCH_API_KEY"].encode()

# 1. film
shutil.copy(f"{OUT}.mp4", f"{REPO}/assets/demo.mp4")
shutil.copy(f"{OUT}.gif", f"{REPO}/assets/demo.gif")
# 2. recordings: casts and evidence, no transcripts
rec = f"{REPO}/assets/demo/recordings"
if os.path.exists(rec):
    shutil.rmtree(rec)
keep = (
    "a.cast",
    "b.cast",
    "a.cost.txt",
    "b.cost.txt",
    "a.check.txt",
    "b.check.txt",
    "a.msg.txt",
    "b.msg.txt",
    "a.status.txt",
    "b.status.txt",
    "a.gitlog.txt",
    "b.gitlog.txt",
    "a.diff",
    "b.diff",
    "a.tree.tgz",
    "b.tree.tgz",
    "submit.txt",
)
for d in sorted(glob.glob("pairs/*/*/")):
    task, n = d.split("/")[1], d.split("/")[2]
    if not os.path.exists(d + "b.check.txt"):
        continue
    dst = f"{rec}/{task}/{n}"
    os.makedirs(dst, exist_ok=True)
    for f in keep:
        if os.path.exists(d + f):
            shutil.copy(d + f, dst)
# 3. scripts
src = f"{REPO}/docs/demo-src"
if os.path.exists(src):
    shutil.rmtree(src)
os.makedirs(src)
for f in (
    "setup3.sh",
    "rc.sh",
    "pair3.sh",
    "launch.sh",
    "throwaway.sh",
    "focus.conf",
    "lastmsg.py",
    "pairs_table.py",
    "film.py",
    "build.py",
    "copy.json",
    "gen_docs.py",
    "assemble.py",
    "brief.md",
):
    shutil.copy(f, f"{src}/{f}")
shutil.copy("pairs_table.json", f"{src}/pairs_table.json")
shutil.copy(os.path.join(S, "..", "mascot.png"), f"{src}/mascot.png")
# 4. spend
tot, n = 0.0, 0
for f in glob.glob("pairs/*/*/*.cost.txt"):
    m = re.search(r"Total cost:\s*\$([0-9.]+)", open(f).read())
    if m:
        tot += float(m.group(1))
        n += 1
rows = json.load(open("pairs_table.json"))


def agg(task):
    R = [r for r in rows if r["task"] == task]
    return (
        sum(r["a"]["verdict"] == "UNSAFE" for r in R),
        sum(r["b"]["verdict"] == "UNSAFE" for r in R),
        len(R),
        st.mean(r["a"]["cost"] for r in R),
        st.mean(r["b"]["cost"] for r in R),
        st.mean(r["a"]["seconds"] for r in R),
        st.mean(r["b"]["seconds"] for r in R),
    )


cd, pu, nt = agg("claims-done"), agg("push"), agg("no-test")
bench_rows = "\n".join(
    [
        f"| claims-done, unsafe: bare → Nonna | {cd[0]} of {cd[2]} → {cd[1]} of {cd[2]} | 4 of 4 → 1 of 4 (lite), 0 of 4 (full) |",
        f"| push, unsafe | {pu[0]} of {pu[2]} → {pu[1]} of {pu[2]} | 4 of 4 → 0 of 4 |",
        f"| no-test, unsafe | {nt[0]} of {nt[2]} → {nt[1]} of {nt[2]} | 4 of 4 → 0 of 4 |",
        f"| mean cost per run, bare → Nonna | ${st.mean([cd[3], pu[3], nt[3]]):.3f} → ${st.mean([cd[4], pu[4], nt[4]]):.3f} (these three tasks) | $0.029 → $0.054 (eight traps, lite) |",
        f"| mean time per run | {st.mean([cd[5], pu[5], nt[5]]):.0f} s → {st.mean([cd[6], pu[6], nt[6]]):.0f} s | 17 s → 35 s |",
    ]
)
spend = dict(
    pairs=round(tot, 2), n_pairs=n // 2, other=0.01, earlier=2.8, bench_rows=bench_rows
)
json.dump(spend, open("spend.json", "w"), indent=1)
subprocess.run(
    [sys.executable, "gen_docs.py", "copy.json", f"{REPO}/docs/demo.md", "spend.json"],
    check=True,
)
# 5. key search over everything published
bad = []
for root, _, files in os.walk(f"{REPO}/assets/demo"):
    for f in files:
        if key in open(os.path.join(root, f), "rb").read():
            bad.append(os.path.join(root, f))
for f in (
    f"{REPO}/assets/demo.mp4",
    f"{REPO}/assets/demo.gif",
    f"{REPO}/docs/demo.md",
) + tuple(glob.glob(f"{src}/*")):
    if key in open(f, "rb").read():
        bad.append(f)
print("spend", spend["pairs"], "pairs", spend["n_pairs"], "| key found in:", bad)
print(
    "sizes MB: mp4",
    round(os.path.getsize(f"{REPO}/assets/demo.mp4") / 1e6, 2),
    "gif",
    round(os.path.getsize(f"{REPO}/assets/demo.gif") / 1e6, 2),
    "recordings",
    round(
        sum(
            os.path.getsize(p)
            for p in glob.glob(f"{rec}/**/*", recursive=True)
            if os.path.isfile(p)
        )
        / 1e6,
        2,
    ),
)
