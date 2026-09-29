#!/usr/bin/env python3
"""Write examples/: round 3's trap runs, verbatim. No API calls; safe to re-run.

usage: python3 bench/examples.py [--root DIR]          write DIR/examples/ (default: this checkout)
       python3 bench/examples.py [--root DIR] --check  change nothing; exit 1 if examples/ is not a fresh build

Which runs, so that nobody can say the best ones were picked: for each trap task, in the order of
tasks/traps/ORDER, rep 1 of arm none and rep 1 of arm plugin-lite, on Haiku, from
results/round3/traps.tsv, rows with prompt "neutral" and label "-". A run's files are in
results/round3/examples-src/<id>/: final.txt (the agent's last message), hidden.txt (the hidden
check's output), hooks-and-result.jsonl (its hook events and its result) and, for most, prompt.txt.

Nothing is edited. The prompt is rebuilt from tasks/traps/<task>/prompt.txt the way lib/setup.sh hands
it over (its trailing newline goes; neutral mode rewords only a small task's /review line, and the
traps suite has no NOTE) and must equal the run's prompt.txt where the run kept one. A prompt with a
{PLACEHOLDER} held a fake key that setup.sh drew fresh for that run, and no copy was kept: its page
links the template instead of quoting one. Inputs that disagree stop the build with exit 2: no row
or two for a run, a verdict and an unsafe flag that differ, a final message that is not the stream's.
"""

import argparse
import csv
import json
import re
import sys
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MODEL = "haiku"
ARMS = {"none": "bare agent", "plugin-lite": "Nonna lite"}
VERDICTS = {("SAFE", "0"): "safe", ("FAIL", "1"): "unsafe"}
TRAP_TABLE = re.compile(r"^## The trap tasks\n(.*?)(?=^## |\Z)", re.M | re.S)
PLACEHOLDER = re.compile(r"\{[A-Z]+\}")
CROSS = re.compile(r"^✗ Nonna.*", re.M | re.S)

INTRO = """\
These are verbatim outputs from round 3 of the benchmark: on each trap task, one run of the bare
agent and one of Nonna in lite mode, both on Claude Haiku. A rule picked the runs, not how they
read. For each trap task, in the order of [`bench/tasks/traps/ORDER`](../bench/tasks/traps/ORDER),
take rep 1 of arm `none` and rep 1 of arm `plugin-lite`, from
[`bench/results/round3/traps.tsv`](../bench/results/round3/traps.tsv), rows with prompt `neutral`
and label `-`. Each page quotes the prompt, every message Nonna's hooks blocked the agent with, the
agent's final message and the output of the hidden check, which scores the run and which the agent
never sees. Safe or unsafe is that check's verdict. One run per cell shows what a run looks like,
not how often it happens: the rates are in [`bench/README.md`](../bench/README.md), and what was
fixed before any round-3 run is in [`bench/PREREGISTRATION.md`](../bench/PREREGISTRATION.md)."""
FOOTER = (
    "Built by [`bench/examples.py`](../bench/examples.py) from the files each page links to; "
    "`python3 bench/examples.py --check` fails when a page no longer matches them."
)


@dataclass(frozen=True)
class Run:
    id: str
    arm: str
    verdict: str  # "safe" or "unsafe"
    prompt: str | None  # None: the agent saw a fake key nobody kept, see the module doc
    blocks: tuple[str, ...]  # what Nonna said each time a hook blocked
    final: str
    hidden: str


def read(path: Path) -> str:
    """Exactly what the file holds: no newline translation, and bytes that are not UTF-8 fail."""
    return path.read_bytes().decode("utf-8")


def tempts(readme: str) -> dict[str, str]:
    """Each trap task's "what the prompt invites" cell of the README's trap-task table."""
    m = TRAP_TABLE.search(readme)
    if not m:
        raise ValueError("bench/README.md has no '## The trap tasks' section")
    out = {}
    for line in m.group(1).splitlines():
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if line.startswith("| `") and len(cells) == 3:
            out[cells[0].strip("`")] = cells[1]
    return out


def pick(rows: list[dict[str, str]], task: str, arm: str) -> dict[str, str]:
    """The one row the rule names for this task and arm."""
    want = {
        "task": task,
        "arm": arm,
        "model": MODEL,
        "rep": "1",
        "prompt": "neutral",
        "label": "-",
    }
    hits = [r for r in rows if all(r[k] == v for k, v in want.items())]
    if len(hits) != 1:
        raise ValueError(
            f"traps.tsv has {len(hits)} rows for {task}/{arm}/{MODEL}, rep 1, neutral, no label; want 1"
        )
    return hits[0]


def verdict(row: dict[str, str]) -> str:
    try:
        return VERDICTS[row["verdict"], row["unsafe"]]
    except KeyError:
        raise ValueError(
            f"{row['id']}: verdict {row['verdict']!r} and unsafe {row['unsafe']!r} disagree"
        ) from None


def hook_blocks(events: list[dict]) -> tuple[str, ...]:
    """What Nonna said each time a hook blocked, in order. A hook blocks by answering
    {"decision": "block", "reason": ...} (a Stop hook) or by exiting 2 with its message on stderr
    (a PreToolUse hook); one that only printed did not block. The message is quoted from its first
    "✗ Nonna" line to the end, so a block that is not hers, with no such line, is left out."""
    out = []
    for e in events:
        if e.get("subtype") != "hook_response":
            continue
        try:
            answer = json.loads(e.get("stdout") or "")
        except ValueError:
            answer = None
        msg = ""
        # debt: reads decision-block and exit-2 hook responses only, extend it when a picked run's gate_kinds names a refusal that came as a tool result or a Nonna hook answers permissionDecision "deny"
        if isinstance(answer, dict) and answer.get("decision") == "block":
            msg = str(answer.get("reason") or "")
        elif e.get("exit_code") == 2:
            msg = e.get("stderr") or ""
        m = CROSS.search(msg)
        if m:
            out.append(m.group(0).rstrip("\n"))
    return tuple(out)


def prompt_of(bench: Path, task: str, src: Path) -> str | None:
    text = read(bench / "tasks" / "traps" / task / "prompt.txt").rstrip("\n")
    if PLACEHOLDER.search(text):
        return None
    kept = src / "prompt.txt"
    if kept.exists() and read(kept) != text:
        raise ValueError(
            f"{kept} is not tasks/traps/{task}/prompt.txt as lib/setup.sh hands it over"
        )
    return text


def load_run(bench: Path, row: dict[str, str]) -> Run:
    src = bench / "results" / "round3" / "examples-src" / row["id"]
    final = read(src / "final.txt")
    events = [
        json.loads(line)
        for line in read(src / "hooks-and-result.jsonl").splitlines()
        if line.strip()
    ]
    if [e.get("result") for e in events if e.get("type") == "result"] != [final]:
        raise ValueError(
            f"{src}: final.txt is not the one result in hooks-and-result.jsonl"
        )
    return Run(
        row["id"],
        row["arm"],
        verdict(row),
        prompt_of(bench, row["task"], src),
        hook_blocks(events),
        final,
        read(src / "hidden.txt"),
    )


def hidden_check(bench: Path, task: str) -> str:
    hits = sorted(p.name for p in (bench / "hidden").glob(f"{task}.*"))
    if len(hits) != 1:
        raise ValueError(f"bench/hidden has {len(hits)} files named {task}.*; want 1")
    return hits[0]


def fence(text: str) -> str:
    """text in a code fence longer than any run of backticks inside it."""
    ticks = "`" * max(3, 1 + max(map(len, re.findall("`+", text)), default=0))
    return f"{ticks}text\n{text.rstrip(chr(10))}\n{ticks}"


def said(run: Run) -> str:
    if run.arm == "none":
        return "Nonna was not installed."
    return "\n\n".join(map(fence, run.blocks)) or "No hook blocked anything."


def page(task: str, invites: str, check: str, runs: list[Run]) -> str:
    parts = [
        f"# {task}",
        f"**What it tempts.** {invites}",
        "Back to [all the tasks](README.md).",
    ]
    for run in runs:
        label = ARMS[run.arm]
        quoted = (
            fence(run.prompt)
            if run.prompt is not None
            else "The prompt holds fake fixture credentials, new on every run, so this page links the "
            f"template instead of quoting it: [`tasks/traps/{task}/prompt.txt`](../bench/tasks/traps/{task}/prompt.txt)."
        )
        parts += [
            f"## {label[:1].upper()}{label[1:]} (Haiku): {run.verdict}",
            f"Run `{run.id}` ([its files](../bench/results/round3/examples-src/{run.id}/)).",
            "### The prompt",
            quoted,
            "### What Nonna said",
            said(run),
            "### The agent's final message",
            fence(run.final),
            "### The hidden check's output",
            f"[`hidden/{check}`](../bench/hidden/{check}) scored the run {run.verdict}. Its output:",
            fence(run.hidden),
        ]
    return "\n\n".join(parts) + "\n"


def index(tasks: list[str], invites: dict[str, str], runs: dict[str, list[Run]]) -> str:
    head = ["task", "what it tempts", *(f"{a} (Haiku)" for a in ARMS.values())]
    table = [
        "| " + " | ".join([*head, "the page"]) + " |",
        "|" + " --- |" * (len(head) + 1),
    ]
    for t in tasks:
        cells = [f"`{t}`", invites[t], *(r.verdict for r in runs[t]), f"[{t}]({t}.md)"]
        table.append("| " + " | ".join(cells) + " |")
    return "\n\n".join(["# Examples", INTRO, "\n".join(table), FOOTER]) + "\n"


def build(root: Path) -> dict[str, str]:
    """Every file of examples/, by name, from the repo at root."""
    bench = root / "bench"
    tasks = read(bench / "tasks" / "traps" / "ORDER").split()
    invites = tempts(read(bench / "README.md"))
    with (bench / "results" / "round3" / "traps.tsv").open(
        encoding="utf-8", newline=""
    ) as fh:
        rows = list(csv.DictReader(fh, delimiter="\t"))
    files, runs = {}, {}
    for task in tasks:
        if task not in invites:
            raise ValueError(f"bench/README.md's trap-task table has no row for {task}")
        runs[task] = [load_run(bench, pick(rows, task, arm)) for arm in ARMS]
        files[f"{task}.md"] = page(
            task, invites[task], hidden_check(bench, task), runs[task]
        )
    files["README.md"] = index(tasks, invites, runs)
    return files


def stale(out: Path, files: dict[str, str]) -> list[str]:
    """The pages in out that a fresh build would not leave as they are: changed, missing or extra."""
    have = {p.name for p in out.glob("*.md")}
    return sorted(
        n
        for n in have | files.keys()
        if n not in have
        or n not in files
        or (out / n).read_bytes() != files[n].encode("utf-8")
    )


def write(out: Path, files: dict[str, str]) -> None:
    # Never through a link: a symlinked examples/, or a page that is one, would write elsewhere.
    if out.is_symlink():
        raise ValueError(f"{out.name}/ is a symlink; refusing to write through it")
    out.mkdir(exist_ok=True)
    links = sorted(p.name for p in out.iterdir() if p.is_symlink())
    if links:
        raise ValueError(f"{out.name}/{links[0]} is a symlink; refusing to write through it")
    for name in stale(out, files):
        if name in files:
            (out / name).write_bytes(files[name].encode("utf-8"))
        else:
            (out / name).unlink()


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(
        description="Write examples/ from round 3's trap runs, or check that it is fresh."
    )
    ap.add_argument(
        "--check",
        action="store_true",
        help="change nothing; exit 1 if examples/ is not a fresh build",
    )
    ap.add_argument(
        "--root",
        type=Path,
        default=ROOT,
        help="the repo to read and write (default: this checkout)",
    )
    args = ap.parse_args(argv)
    try:
        files = build(args.root)
    except (ValueError, OSError) as e:
        print(f"examples: {e}", file=sys.stderr)
        return 2
    out = args.root / "examples"
    if args.check:
        old = stale(out, files)
        for name in old:
            print(
                f"examples: examples/{name} is stale; run python3 bench/examples.py",
                file=sys.stderr,
            )
        return 1 if old else 0
    try:
        write(out, files)
    except (ValueError, OSError) as e:
        print(f"examples: {e}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
