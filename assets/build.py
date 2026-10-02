#!/usr/bin/env python3
"""Build Nonna's launch images from the benchmark data.

    python3 assets/build.py             write the SVGs
    python3 assets/build.py --render    write the SVGs, then render every PNG with headless Chromium
    python3 assets/build.py --check     verify what is committed; writes nothing

The scorecard, the social preview and one card per trap task are functions of
bench/results/round3 (summary.json, traps.tsv, the example streams), bench/tasks/traps, the banner's
portrait and the glyph outlines in assets/font/. No number in an image is typed in here: change the
data and every image that quotes it goes stale until it is rebuilt, and --check says so.

The logo, assets/nonna.svg, is the one image drawn by hand: build.py reads it, never writes it, and
--render draws it into the plugin's icon, .claude/.claude-plugin/icon.png.

Text is outlined as SVG paths, laid out from assets/font/space-grotesk.json, so viewing or building
needs no font. Only --render needs a browser: $CHROMIUM, or a chromium on PATH. --check rebuilds the
SVGs and compares them with the committed ones, then reads each PNG's header, size and stamp, on the
standard library alone (CI's lint job installs nothing).

NONNA_ASSETS_ROOT points the build at a different tree, so tests/run.sh can copy the repository,
break exactly one thing, and assert --check catches it. CI never sets it.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import os
import re
import shutil
import struct
import subprocess
import sys
import xml.etree.ElementTree as ET
import zlib
from collections import defaultdict
from collections.abc import Iterable, Iterator, Sequence
from dataclasses import dataclass
from pathlib import Path
from typing import Any
from xml.sax.saxutils import escape

Box = tuple[float, float, float, float]

# --- where things live, relative to the repository root ---------------------------------------
FONT = "assets/font/space-grotesk.json"
BANNER = "assets/nonna-banner.svg"
LOGO = "assets/nonna.svg"
ICON = ".claude/.claude-plugin/icon.png"  # the logo, rendered, for the plugin directory's listing
RESULTS = "bench/results/round3"
TRAPS = "bench/tasks/traps"
EXAMPLES = f"{RESULTS}/examples-src"

# --- what the images are about ---------------------------------------------------------------
BARE, LITE = "none", "plugin-lite"
MODELS = ("sonnet", "haiku")
COST_MODEL = "sonnet"
SCOPE = "Claude Sonnet + Haiku"
EXAMPLE_MODEL = "haiku"
EXAMPLE = f"{LITE}-{EXAMPLE_MODEL}-1"  # the run a card takes its Nonna line from
NONNA_MARK = "✗ Nonna"
# bytes: the tightest limit any place we post to sets (GitHub's social preview, 1 MB)
PNG_BUDGET = 1_000_000

# --- palette: the banner's and the scorecard's -----------------------------------------------
CREAM, PANEL, INK, MUTED = "#FFF1DC", "#FFFBF3", "#2A1E17", "#7A6658"
RULE, TERRA = "#EADFCB", "#E14B2D"


class DataError(ValueError):
    """The benchmark data, or a file built from it, is not what the images need."""


# ==============================================================================================
# data -> numbers
# ==============================================================================================


@dataclass(frozen=True)
class Tally:
    unsafe: int
    n: int

    def __str__(self) -> str:
        return f"{self.unsafe} of {self.n}"


@dataclass(frozen=True)
class Numbers:
    tasks: tuple[str, ...]
    runs_each: int  # per task, arm and model
    bare: Tally  # all trap tasks, both models
    lite: Tally
    per_task: dict[str, tuple[Tally, Tally]]  # task -> (bare, lite), both models
    traps_cost: tuple[float, float]  # mean per run on COST_MODEL: (bare, lite)
    small_cost: tuple[float, float]


def _round3(groups: list[Any]) -> list[dict[str, Any]]:
    """The groups the launch quotes: round 3, the neutral prompt, no label."""
    return [
        g
        for g in groups
        if isinstance(g, dict)
        and g.get("round") == "3"
        and g.get("prompt") == "neutral"
        and g.get("label") == "-"
    ]


def _group(groups: list[Any], suite: str, model: str, arm: str) -> dict[str, Any]:
    found = [
        g
        for g in _round3(groups)
        if (g.get("suite"), g.get("model"), g.get("arm")) == (suite, model, arm)
    ]
    where = f"{suite}/{model}/{arm}"
    if not found:
        raise DataError(f"summary.json: no round 3 neutral group for {where}")
    if len(found) > 1:
        raise DataError(
            f"summary.json: more than one round 3 neutral group for {where}"
        )
    return found[0]


def pooled(groups: list[Any], arm: str) -> Tally:
    """An arm's unsafe runs over every trap task, on every model."""
    unsafe = n = 0
    for model in MODELS:
        g = _group(groups, "traps", model, arm)
        u, k = g.get("unsafe"), g.get("n")
        if not (isinstance(u, int) and isinstance(k, int) and 0 <= u <= k):
            raise DataError(
                f"summary.json: traps/{model}/{arm} has unsafe={u!r} of n={k!r}"
            )
        unsafe, n = unsafe + u, n + k
    return Tally(unsafe, n)


def _mean_cost(groups: list[Any], suite: str, arm: str) -> float:
    cost = _group(groups, suite, COST_MODEL, arm).get("mean_cost")
    if isinstance(cost, bool) or not isinstance(cost, (int, float)) or cost < 0:
        raise DataError(
            f"summary.json: {suite}/{COST_MODEL}/{arm} has mean_cost={cost!r}"
        )
    return float(cost)


def compute_numbers(
    summary: dict[str, Any], rows: Iterable[dict[str, str]], order: Sequence[str]
) -> Numbers:
    groups = summary.get("groups")
    if not isinstance(groups, list):
        raise DataError("summary.json: no groups")
    flags: dict[tuple[str, str, str], list[int]] = defaultdict(list)
    for r in rows:
        if r.get("prompt") != "neutral" or r.get("label") != "-":
            continue
        if r.get("arm") not in (BARE, LITE) or r.get("model") not in MODELS:
            continue
        if r.get("unsafe") not in ("0", "1"):
            raise DataError(
                f"traps.tsv: unsafe is {r.get('unsafe')!r} for "
                f"{r.get('task')}/{r.get('arm')}/{r.get('model')}, want 0 or 1"
            )
        flags[(r.get("task", ""), r["arm"], r["model"])].append(int(r["unsafe"]))
    for task in order:
        for arm in (BARE, LITE):
            for model in MODELS:
                if (task, arm, model) not in flags:
                    raise DataError(f"traps.tsv: no {arm} runs of {task} on {model}")
    runs = {len(v) for k, v in flags.items() if k[0] in order}
    if len(runs) != 1:
        raise DataError(
            f"traps.tsv: uneven runs per task, arm and model: {sorted(runs)}"
        )

    def tally(task: str, arm: str) -> Tally:
        cells = [flags[(task, arm, m)] for m in MODELS]
        return Tally(sum(map(sum, cells)), sum(map(len, cells)))

    per_task = {t: (tally(t, BARE), tally(t, LITE)) for t in order}
    total = [
        Tally(
            sum(p[i].unsafe for p in per_task.values()),
            sum(p[i].n for p in per_task.values()),
        )
        for i in (0, 1)
    ]
    bare, lite = pooled(groups, BARE), pooled(groups, LITE)
    if (bare, lite) != tuple(total):
        raise DataError(
            "summary.json and traps.tsv disagree: "
            f"bare {bare} vs {total[0]}, lite {lite} vs {total[1]}"
        )
    return Numbers(
        tasks=tuple(order),
        runs_each=runs.pop(),
        bare=bare,
        lite=lite,
        per_task=per_task,
        traps_cost=(
            _mean_cost(groups, "traps", BARE),
            _mean_cost(groups, "traps", LITE),
        ),
        small_cost=(
            _mean_cost(groups, "small", BARE),
            _mean_cost(groups, "small", LITE),
        ),
    )


def load_numbers(root: Path) -> Numbers:
    results = root / RESULTS
    summary = json.loads((results / "summary.json").read_text(encoding="utf-8"))
    with open(results / "traps.tsv", newline="", encoding="utf-8") as fh:
        rows = list(csv.DictReader(fh, delimiter="\t"))
    order = (root / TRAPS / "ORDER").read_text(encoding="utf-8").split()
    return compute_numbers(summary, rows, order)


# What comes off the end of a line before its ellipsis: an ellipsis after a colon reads as a typo.
TRAILING = " ,;:.-\u2013\u2014("


# bench/lib/setup.sh fills these with fresh fakes on every run; a card shows the shape of what was
# pasted, since the values themselves were never kept.
PLACEHOLDERS = {
    "{KEY}": "sk_live_\u2026",
    "{AKID}": "AKIA\u2026",
    "{SAK}": "\u2026",
    "{PW}": "\u2026",
}


def pair_quotes(text: str) -> str:
    """Straight double quotes as typographic pairs: the font draws a straight one as a closing quote."""
    out, opening = [], True
    for ch in text:
        if ch == '"':
            out.append("\u201c" if opening else "\u201d")
            opening = not opening
        else:
            out.append(ch)
    return "".join(out)


def prompt_line(text: str) -> str:
    """A prompt's first line, ending in an ellipsis when the prompt goes on past it."""
    first, *rest = text.splitlines() or [""]
    if not first.strip():
        raise DataError("prompt.txt: the first line is empty")
    first = first.strip()
    for placeholder, shown in PLACEHOLDERS.items():
        first = first.replace(placeholder, shown)
    first = pair_quotes(first)
    return first.rstrip(TRAILING) + "\u2026" if any(r.strip() for r in rest) else first


# ==============================================================================================
# the line Nonna said
# ==============================================================================================


def read_events(path: Path) -> list[Any]:
    events = []
    for n, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if line.strip():
            try:
                events.append(json.loads(line))
            except json.JSONDecodeError as e:
                raise DataError(
                    f"{path.parent.name}/{path.name}:{n}: not JSON ({e.msg})"
                ) from e
    return events


def _texts(value: Any) -> Iterator[str]:
    """Every string in a decoded JSON value, and inside the strings that are themselves JSON."""
    if isinstance(value, str):
        yield value
        if value.lstrip()[:1] in ("{", "["):
            try:
                inner = json.loads(value)
            except json.JSONDecodeError:
                return
            yield from _texts(inner)
    elif isinstance(value, dict):
        for v in value.values():
            yield from _texts(v)
    elif isinstance(value, list):
        for v in value:
            yield from _texts(v)


def _hook_and_tool_texts(event: Any) -> Iterator[str]:
    if not isinstance(event, dict):
        return
    if event.get("type") == "system" and event.get("subtype") == "hook_response":
        for key in ("output", "stdout", "stderr"):
            yield from _texts(event.get(key))
    elif event.get("type") == "user":
        message = event.get("message")
        content = message.get("content") if isinstance(message, dict) else None
        for block in content if isinstance(content, list) else []:
            if isinstance(block, dict) and block.get("type") == "tool_result":
                yield from _texts(block.get("content"))


def nonna_line(events: Iterable[Any]) -> str | None:
    """The first line, in hook-response or tool-result text, that starts with Nonna's cross."""
    for event in events:
        for text in _hook_and_tool_texts(event):
            for line in text.splitlines():
                if line.startswith(NONNA_MARK):
                    return line.rstrip()
    return None


# ==============================================================================================
# text -> outlines
# ==============================================================================================

# One command letter and the numbers after it. fontTools writes a lineto that follows a moveto as
# more numbers after the M, so the letter alone does not say how many numbers a command has.
_COMMAND = re.compile(r"([MLHVQZ])([^MLHVQZ]*)")


class Font:
    """Advance widths and outlines per weight, in font units (y up), from the committed JSON."""

    def __init__(self, data: dict[str, Any]) -> None:
        self.upm: float = data["upm"]
        self._glyphs: dict[str, dict[str, list[Any]]] = data["glyphs"]

    def glyph(self, ch: str, weight: int) -> tuple[int, str]:
        table = self._glyphs.get(str(weight))
        if table is None:
            raise ValueError(f"the font has no weight {weight}")
        if ch not in table:
            raise ValueError(
                f"no glyph for {ch!r} (U+{ord(ch):04X}) at weight {weight}"
            )
        advance, outline = table[ch]
        return advance, outline

    def advance(
        self, text: str, weight: int, size: float, tracking: float = 0.0
    ) -> float:
        """Width of a run: tracking sits between glyphs, never after the last."""
        k, width = size / self.upm, 0.0
        for ch in text:
            width += self.glyph(ch, weight)[0] * k + tracking * size
        return width - tracking * size if text else 0.0


def load_font(path: Path) -> Font:
    return Font(json.loads(path.read_text(encoding="utf-8")))


@dataclass(frozen=True)
class Run:
    d: str  # SVG path data
    width: float  # advance width
    box: Box  # ink extent (control points included)


def _num(v: float) -> str:
    s = f"{v:.1f}".rstrip("0").rstrip(".")
    return "0" if s == "-0" else s


def _place(
    outline: str, x: float, y: float, k: float
) -> tuple[str, list[float], list[float]]:
    """Scale an outline by k, flip it about the baseline y, and move it to x."""
    out, xs, ys = [], [], []
    for cmd, numbers in _COMMAND.findall(outline):
        vals = []
        for i, tok in enumerate(numbers.split()):
            if cmd == "H" or (cmd != "V" and i % 2 == 0):  # an x; the rest are y
                xs.append(x + float(tok) * k)
                vals.append(_num(xs[-1]))
            else:
                ys.append(y - float(tok) * k)
                vals.append(_num(ys[-1]))
        out.append(cmd + " ".join(vals))
    return "".join(out), xs, ys


def text_run(
    font: Font,
    text: str,
    x: float,
    y: float,
    weight: int,
    size: float,
    tracking: float = 0.0,
    anchor: str = "start",
) -> Run:
    """Outline `text` with its baseline at y. anchor="start" starts the pen at x, "end" ends the
    advance there, and "ink" starts the first glyph's ink there, so lines that open on letters with
    different side bearings share a left edge.
    """
    # debt: no pair kerning, like the banner's lettering, add the GPOS pairs to the JSON if a headline shows a gap
    k = size / font.upm
    width = font.advance(text, weight, size, tracking)
    pen = x - width if anchor == "end" else x
    if anchor == "ink":
        pen = x - (text_run(font, text, 0, y, weight, size, tracking).box[0])
    parts: list[str] = []
    xs: list[float] = []
    ys: list[float] = []
    for ch in text:
        advance, outline = font.glyph(ch, weight)
        if outline:
            d, gx, gy = _place(outline, pen, y, k)
            parts.append(d)
            xs += gx
            ys += gy
        pen += advance * k + tracking * size
    box = (min(xs), min(ys), max(xs), max(ys)) if xs else (x, y, x, y)
    return Run("".join(parts), width, box)


def wrap(
    font: Font,
    text: str,
    weight: int,
    size: float,
    width: float,
    max_lines: int,
    balance: bool = False,
) -> list[str]:
    """Greedy word wrap; text past max_lines ends the last line in an ellipsis that fits.

    balance narrows the lines as far as it can without adding one, so the last is not an orphan.
    """

    def fits(s: str, at: float = width) -> bool:
        return font.advance(s, weight, size) <= at

    def greedy(at: float) -> list[str]:
        lines: list[str] = []
        cur = ""
        for word in text.split():
            trial = f"{cur} {word}" if cur else word
            if cur and not fits(trial, at):
                lines.append(cur)
                cur = word
            else:
                cur = trial
        return lines + [cur] if cur else lines

    lines = greedy(width)
    if len(lines) <= max_lines:
        if balance and len(lines) > 1:
            lo, hi = 0, int(width)  # the line count never falls as the width shrinks
            while lo < hi:
                mid = (lo + hi) // 2
                lo, hi = (lo, mid) if len(greedy(mid)) <= len(lines) else (mid + 1, hi)
            return greedy(hi)
        return lines
    words = lines[max_lines - 1].split()
    while words and not fits(" ".join(words) + "\u2026"):
        words.pop()
    return lines[: max_lines - 1] + [" ".join(words).rstrip(TRAILING) + "\u2026"]


@dataclass(frozen=True)
class Style:
    weight: int
    size: float
    fill: str
    tracking: float = 0.0


def _g(v: float) -> str:
    return f"{v:g}"


class Scene:
    """The elements of one SVG. Lettering is checked against the safe area as it is added, so a
    line that would run off the image fails the build instead of shipping cropped."""

    def __init__(
        self, font: Font, width: int, height: int, safe: Box | None = None
    ) -> None:
        self.font, self.width, self.height, self.safe = font, width, height, safe
        self.parts: list[str] = []

    def raw(self, markup: str) -> None:
        self.parts.append(markup)

    def rect(
        self,
        x: float,
        y: float,
        w: float,
        h: float,
        fill: str,
        rx: float = 0,
        opacity: float = 1,
    ) -> None:
        rounded = f' rx="{_g(rx)}"' if rx else ""
        faint = f' fill-opacity="{_g(opacity)}"' if opacity != 1 else ""
        self.raw(
            f'<rect x="{_g(x)}" y="{_g(y)}" width="{_g(w)}" height="{_g(h)}"{rounded} fill="{fill}"{faint}/>'
        )

    def text(
        self, s: str, x: float, y: float, style: Style, anchor: str = "start"
    ) -> None:
        run = text_run(
            self.font, s, x, y, style.weight, style.size, style.tracking, anchor=anchor
        )
        if self.safe:
            x0, y0, x1, y1 = self.safe
            bx0, by0, bx1, by1 = run.box
            if bx0 < x0 or by0 < y0 or bx1 > x1 or by1 > y1:
                shown = tuple(round(v, 1) for v in run.box)
                raise ValueError(
                    f"{s!r} lies outside the safe area {self.safe}: {shown}"
                )
        self.raw(f'<path d="{run.d}" fill="{style.fill}"/>')

    def cross(self, x: float, cy: float, size: float, width: float, color: str) -> None:
        """A cross in a size-by-size box whose left edge is x and whose middle is cy."""
        top, bottom = _num(cy - size / 2), _num(cy + size / 2)
        left, right = _num(x), _num(x + size)
        self.raw(
            f'<path d="M{left} {top}L{right} {bottom}M{right} {top}L{left} {bottom}" fill="none"'
            f' stroke="{color}" stroke-width="{_g(width)}" stroke-linecap="round"/>'
        )

    def svg(self, prefix: str, title: str, desc: str) -> str:
        w, h = self.width, self.height
        ids = f"{prefix}t {prefix}d"
        return (
            f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {h}" width="{w}" height="{h}"'
            f' role="img" aria-labelledby="{ids}">\n'
            f'  <title id="{prefix}t">{escape(title)}</title>\n'
            f'  <desc id="{prefix}d">{escape(desc)}</desc>\n'
            + "".join(f"  {p}\n" for p in self.parts)
            + "</svg>\n"
        )


# What an image may carry: markup that draws, and nothing that runs or reaches outside the file.
# So a short allow-list, not a list of what to keep out (a prefixed <s:script>, SMIL, image-set()
# and a CSS escape all got past that): the SVG elements the eleven images and the banner's portrait
# use today, which tests/test_assets.py holds equal to the list, and attributes that stay in the
# file. Anything else is refused however it is spelled.
SVG_NS = "http://www.w3.org/2000/svg"
ALLOWED_ELEMENTS = frozenset(
    f"{{{SVG_NS}}}{name}"
    for name in (
        "circle",
        "clipPath",
        "desc",
        "ellipse",
        "g",
        "path",
        "rect",
        "svg",
        "title",
    )
)
# The one attribute with a namespace that may appear: xlink:href, held to the rule for href.
_XLINK_HREF = "{http://www.w3.org/1999/xlink}href"
# Read before parsing, since a parser never shows either as an element: a DOCTYPE (an ENTITY only
# exists inside one) and a processing instruction such as <?xml-stylesheet?>. The XML declaration
# is not one.
_DECLARATION = re.compile(r"<!(?:DOCTYPE|ENTITY)|<\?(?!xml\s)[^\s?>]*", re.I)
# The only url() a value may hold: a reference to an id in the file, quoted or not.
_LOCAL_URL = re.compile(r"""url\(\s*(["']?)#[^\s"'()]+\1\s*\)""", re.I)
# Never in a value, whatever else it says: a CSS escape (it can spell url( another way), and the
# two things that fetch without saying url(.
# debt: values are checked for the CSS fetchers known today, add each new one a browser ships (src() is a candidate)
_NEVER_IN_A_VALUE = re.compile(r"\\|image-set|@import", re.I)


def unsafe_markup(svg: str) -> str | None:
    """The first thing in this SVG that is more than drawing, or None when it is all drawing."""
    found = _DECLARATION.search(svg)
    if found:
        return found.group(0)
    try:
        root = ET.fromstring(svg)
    except ET.ParseError as e:
        return f"markup that does not parse ({e})"
    for el in root.iter():
        if el.tag not in ALLOWED_ELEMENTS:
            return f"<{el.tag}>"
        for name, value in el.attrib.items():
            local = name.rpartition("}")[2].lower()
            if (
                (name.startswith("{") and name != _XLINK_HREF)
                or local.startswith("on")
                or (local == "href" and not value.startswith("#"))
                or _NEVER_IN_A_VALUE.search(value)
                or "url(" in _LOCAL_URL.sub("", value).lower()
            ):
                return f'{name}="{value[:60]}"'
    return None


def portrait(banner: str) -> str:
    """The banner's portrait: the markup inside its placement group, untouched, ids and all."""
    open_tag = '<g transform="translate(34 34) scale(0.88)">'
    start = banner.find(open_tag)
    if start < 0:
        raise DataError(
            f"{BANNER}: the portrait group is not where build.py looks for it"
        )
    depth = 0
    for m in re.finditer(r"<g[\s>]|</g>", banner[start:]):
        depth += -1 if m.group(0) == "</g>" else 1
        if depth == 0:
            inner = banner[start + len(open_tag) : start + m.start()]
            unsafe = unsafe_markup(f'<svg xmlns="{SVG_NS}">{inner}</svg>')
            if unsafe:
                raise DataError(
                    f"{BANNER}: the portrait carries {unsafe}: "
                    "the images take markup that draws, nothing that runs or reaches out"
                )
            return inner
    raise DataError(f"{BANNER}: the portrait group is never closed")


# ==============================================================================================
# the images
# ==============================================================================================


@dataclass(frozen=True)
class Image:
    name: str  # under assets/, without extension
    svg: str
    width: int  # the SVG's; the PNG is width*scale wide
    height: int
    scale: int
    png: str | None = None  # path from the root; None puts the PNG beside the SVG
    source: bool = False  # the SVG is made by hand: read, never written


def _dollars(c: float) -> str:
    return f"${c:.2f}"


def scorecard_svg(font: Font, n: Numbers) -> str:
    """Four panels, chosen before round 3 ran; the numbers are whatever the data says."""
    s = Scene(font, 1200, 560)
    s.rect(0, 0, 1200, 560, CREAM, rx=28)
    claims, push = n.per_task["claims-done"], n.per_task["push"]
    panels = [
        (
            "Cut a corner on a trap task",
            f"{len(n.tasks)} tasks, {SCOPE}, {n.runs_each} runs each",
            str(n.bare),
            str(n.lite),
        ),
        (
            "Said “done” on a broken test suite",
            "the obvious fix breaks a test elsewhere",
            str(claims[0]),
            str(claims[1]),
        ),
        (
            "Pushed to main when told to push",
            "“fix it, then commit and push it”",
            str(push[0]),
            str(push[1]),
        ),
    ]
    for (title, sub, bare, lite), (cx, cy) in zip(
        panels, [(20, 20), (610, 20), (20, 280)]
    ):
        s.rect(cx, cy, 570, 240, PANEL, rx=20)
        s.text(title, cx + 32, cy + 50, Style(600, 26, INK))
        s.text(sub, cx + 32, cy + 78, Style(400, 17, MUTED))
        s.rect(cx + 32, cy + 100, 506, 2, RULE)
        s.text("bare agent", cx + 32, cy + 148, Style(500, 20, MUTED))
        s.text(bare, cx + 538, cy + 152, Style(600, 40, MUTED), anchor="end")
        s.text("nonna lite", cx + 32, cy + 206, Style(600, 20, TERRA))
        s.text(lite, cx + 538, cy + 210, Style(700, 40, TERRA), anchor="end")
    cx, cy = 610, 280
    s.rect(cx, cy, 570, 240, TERRA, rx=20)
    s.text("What it costs per change", cx + 32, cy + 50, Style(600, 26, PANEL))
    s.text(
        f"bare agent vs nonna lite, mean, Claude {COST_MODEL.title()}",
        cx + 32,
        cy + 78,
        Style(400, 17, CREAM),
    )
    s.rect(cx + 32, cy + 100, 506, 2, CREAM, opacity=0.4)
    costs = [("trap tasks", n.traps_cost), ("small feature tasks", n.small_cost)]
    for (label, (without, with_lite)), dy in zip(costs, (148, 206)):
        s.text(label, cx + 32, cy + dy, Style(500, 20, CREAM))
        s.text(
            f"{_dollars(without)} vs {_dollars(with_lite)}",
            cx + 538,
            cy + dy + 4,
            Style(700, 36, PANEL),
            anchor="end",
        )
    desc = (
        f"Cut a corner on {len(n.tasks)} trap tasks, {SCOPE}, {n.runs_each} runs each: "
        f"bare agent {n.bare} runs, nonna lite {n.lite}. "
        f"Said done on a broken test suite: {claims[0]} versus {claims[1]}. "
        f"Pushed to main when told to push: {push[0]} versus {push[1]}. "
        f"Cost per change, Claude {COST_MODEL.title()}: "
        f"trap tasks {_dollars(n.traps_cost[0])} versus {_dollars(n.traps_cost[1])}, "
        f"small feature tasks {_dollars(n.small_cost[0])} versus {_dollars(n.small_cost[1])}."
    )
    return s.svg("s", "Nonna lite versus a bare agent", desc)


def social_svg(font: Font, n: Numbers, mark: str) -> str:
    """1280x640, keeping 40 px clear on every edge: X crops."""
    s = Scene(font, 1280, 640, safe=(40, 40, 1240, 600))
    s.rect(0, 0, 1280, 640, CREAM)
    s.rect(0, 0, 480, 640, TERRA)
    s.raw(f'<g transform="translate(40 120) scale(1)">{mark}</g>')
    x = 536
    s.text("nonna", x, 218, Style(600, 112, INK, -0.03), anchor="ink")
    s.text("Your AI agent says done.", x, 314, Style(600, 56, INK), anchor="ink")
    s.text("Nonna makes it prove it.", x, 384, Style(600, 56, TERRA), anchor="ink")
    proof = f"{n.lite.unsafe}/{n.lite.n} corner cuts \u00b7 bare agent {n.bare.unsafe}/{n.bare.n}"
    s.text(proof, x, 484, Style(500, 26, MUTED), anchor="ink")
    desc = (
        "Nonna, an unimpressed grandmother with a wooden spoon, beside the words: nonna. "
        f"Your AI agent says done. Nonna makes it prove it. {proof}."
    )
    return s.svg("p", "Nonna: your AI agent says done, Nonna makes it prove it", desc)


CARD, MARGIN, BAND = 1080, 72, 200  # a card, its margin, its header band


def _pill(s: Scene, text: str, right: float, cy: float, fill: str, ink: str) -> None:
    size = 24
    w = s.font.advance(text, 500, size) + 56
    s.rect(right - w, cy - 26, w, 52, fill, rx=26)
    s.text(text, right - w + 28, cy + size * 0.34, Style(500, size, ink))


def _chip(s: Scene, bottom: float, caption: str, line: str) -> None:
    """Nonna's line on a dark chip, its cross drawn: the font has none."""
    pad, size, pitch = 28, 32, 44
    cross = line.startswith("\u2717 ")
    text = line[2:] if cross else line
    width = CARD - 2 * MARGIN
    indent = 46 if cross else 0
    lines = wrap(s.font, text, 500, size, width - 2 * pad - indent, 3, balance=True)
    first = 16 + 47  # caption cap height, then the gap to the first line's baseline
    top = bottom - (pad + first + pitch * (len(lines) - 1) + pad)
    s.rect(MARGIN, top, width, bottom - top, INK, rx=28)
    s.text(caption, MARGIN + pad, top + pad + 16, Style(400, 22, RULE))
    base = top + pad + first
    if cross:
        s.cross(MARGIN + pad, base - size * 0.35, 19, 4.5, TERRA)
    for i, ln in enumerate(lines):
        s.text(ln, MARGIN + pad + indent, base + pitch * i, Style(500, size, CREAM))


def card_svg(
    font: Font,
    task: str,
    prompt: str,
    tallies: tuple[Tally, Tally],
    line: str | None,
    runs_each: int,
    mark: str,
) -> str:
    """One trap task, 1080x1080: what was asked, what the bare agent did, what Nonna lite did."""
    bare, lite = tallies
    width = CARD - 2 * MARGIN
    s = Scene(font, CARD, CARD, safe=(40, 40, CARD - 40, CARD - 40))
    s.rect(0, 0, CARD, CARD, CREAM)
    s.rect(0, 0, CARD, BAND, TERRA)
    s.raw(f'<g transform="translate({MARGIN} 34) scale(0.33)">{mark}</g>')
    s.text("nonna", 236, 121, Style(600, 80, CREAM, -0.03))
    _pill(s, "trap task", CARD - MARGIN, 100, CREAM, TERRA)
    dy = 0 if line else 100  # no chip: centre the body, or the bottom third stays blank
    s.text(task, MARGIN, 344 + dy, Style(600, 124, INK, -0.03), anchor="ink")
    lines = wrap(font, prompt, 400, 32, width - 28, 3)
    s.rect(MARGIN, 404 + dy, 5, 46 * len(lines) - 6, TERRA, rx=2.5)
    for i, ln in enumerate(lines):
        s.text(ln, MARGIN + 28, 428 + dy + 46 * i, Style(400, 32, MUTED))
    s.rect(MARGIN, 572 + dy, width, 2, INK, opacity=0.15)
    rows = [("Bare:", f"{bare} unsafe", MUTED), ("Nonna lite:", str(lite), TERRA)]
    label_w = max(font.advance(label, 500, 40) for label, _, _ in rows)
    for (label, value, fill), y in zip(rows, (664 + dy, 752 + dy)):
        s.text(label, MARGIN, y, Style(500, 40, fill))
        s.text(value, MARGIN + label_w + 32, y, Style(700, 72, fill))
    scope = f"{SCOPE}, {runs_each} runs each"
    s.text(scope, MARGIN, 810 + dy, Style(400, 24, MUTED))
    said = f"What Nonna said in one Claude {EXAMPLE_MODEL.title()} run"
    if line:
        _chip(s, CARD - MARGIN, said, line)
    desc = (
        f"Trap task {task}. Prompt: {' '.join(lines)} Bare: {bare} unsafe. Nonna lite: {lite}. "
        f"{scope}." + (f" {said}: {line}" if line else "")
    )
    return s.svg("c", f"{task}: bare agent {bare} unsafe, nonna lite {lite}", desc)


def build_all(root: Path) -> list[Image]:
    font = load_font(root / FONT)
    n = load_numbers(root)
    mark = portrait((root / BANNER).read_text(encoding="utf-8"))
    logo = (root / LOGO).read_text(encoding="utf-8")
    images = [
        Image("scorecard", scorecard_svg(font, n), 1200, 560, 2),
        Image("social-preview", social_svg(font, n, mark), 1280, 640, 1),
        Image("nonna", logo, 400, 400, 2, png=ICON, source=True),
    ]
    for task in n.tasks:
        prompt = prompt_line(
            (root / TRAPS / task / "prompt.txt").read_text(encoding="utf-8")
        )
        stream = root / EXAMPLES / f"{task}-{EXAMPLE}" / "hooks-and-result.jsonl"
        line = nonna_line(read_events(stream))
        svg = card_svg(font, task, prompt, n.per_task[task], line, n.runs_each, mark)
        images.append(Image(f"cards/{task}", svg, 1080, 1080, 1))
    return images


# ==============================================================================================
# PNGs: stamped with the SVG they were rendered from, so --check can tell a stale one
# ==============================================================================================

_MAGIC = b"\x89PNG\r\n\x1a\n"
_STAMP = b"nonna-svg-sha256\0"


def png_size(data: bytes) -> tuple[int, int]:
    if len(data) < 24 or data[:8] != _MAGIC or data[12:16] != b"IHDR":
        raise ValueError("not a PNG")
    width, height = struct.unpack(">II", data[16:24])
    return width, height


def _chunks(data: bytes) -> Iterator[tuple[bytes, bytes]]:
    pos = 8
    while pos + 12 <= len(data):
        (n,) = struct.unpack(">I", data[pos : pos + 4])
        yield data[pos + 4 : pos + 8], data[pos + 8 : pos + 8 + n]
        if data[pos + 4 : pos + 8] == b"IEND":
            return
        pos += 12 + n


def png_stamp(data: bytes) -> str | None:
    for kind, body in _chunks(data):
        if kind == b"tEXt" and body.startswith(_STAMP):
            return body[len(_STAMP) :].decode("latin-1")
    return None


def stamp_png(data: bytes, digest: str) -> bytes:
    """The PNG with a tEXt chunk after IHDR naming the SVG it came from; an old stamp goes."""
    png_size(data)
    body = _STAMP + digest.encode("ascii")
    stamp = struct.pack(">I", len(body)) + b"tEXt" + body
    stamp += struct.pack(">I", zlib.crc32(b"tEXt" + body))
    out, pos = [data[:8]], 8
    for kind, chunk in _chunks(data):
        end = pos + 12 + len(chunk)
        if not (kind == b"tEXt" and chunk.startswith(_STAMP)):
            out.append(data[pos:end])
            if kind == b"IHDR":
                out.append(stamp)
        pos = end
    return b"".join(out)


def digest(svg: str) -> str:
    return hashlib.sha256(svg.encode("utf-8")).hexdigest()


def _png_problems(png: Path, rel: str, img: Image) -> list[str]:
    try:
        data = png.read_bytes()
    except FileNotFoundError:
        return [f"{rel}: missing"]
    try:
        got = png_size(data)
    except ValueError:
        return [f"{rel}: not a PNG"]
    problems = []
    want = (img.width * img.scale, img.height * img.scale)
    if got != want:
        problems.append(f"{rel}: {got[0]}x{got[1]}, want {want[0]}x{want[1]}")
    if len(data) > PNG_BUDGET:
        problems.append(f"{rel}: over the {PNG_BUDGET}-byte budget ({len(data)} bytes)")
    # debt: a PNG passes if it carries its SVG's hash, compare pixels if a bad render ever ships
    if png_stamp(data) != digest(img.svg):
        problems.append(f"{rel}: rendered from a different SVG")
    return problems


def check(root: Path, images: list[Image]) -> list[str]:
    """What is wrong with the committed images; nothing means they match a fresh build."""
    problems: list[str] = []
    for img in images:
        rel = f"assets/{img.name}"
        try:
            committed = (root / f"{rel}.svg").read_text(encoding="utf-8")
        except FileNotFoundError:
            problems.append(f"{rel}.svg: missing")
        else:
            if committed != img.svg:
                problems.append(f"{rel}.svg: differs from a fresh build")
        png = img.png or f"{rel}.png"
        problems += _png_problems(root / png, png, img)
    return problems


# ==============================================================================================
# writing and rendering
# ==============================================================================================


def render_command(
    chromium: str, svg: Path, png: Path, width: int, height: int, scale: int
) -> list[str]:
    return [
        chromium,
        "--no-sandbox",
        "--headless",
        "--disable-gpu",
        "--hide-scrollbars",
        "--default-background-color=00000000",
        f"--force-device-scale-factor={scale}",
        f"--screenshot={png}",
        f"--window-size={width},{height}",
        svg.as_uri(),
    ]


def find_chromium() -> str:
    names = (
        "chromium",
        "chromium-browser",
        "google-chrome",
        "chrome",
        "headless_shell",
    )
    exe = os.environ.get("CHROMIUM") or next((n for n in names if shutil.which(n)), "")
    found = shutil.which(exe) if exe else None
    if not found:
        raise DataError("no headless Chromium found: set CHROMIUM to the path of one")
    return found


def render(root: Path, images: list[Image]) -> None:
    # The browser gets nothing that runs or reaches outside the file, whatever put it in the SVG.
    for img in images:
        unsafe = unsafe_markup(img.svg)
        if unsafe:
            raise DataError(
                f"{img.name}.svg carries {unsafe}: "
                "the images take markup that draws, nothing that runs or reaches out"
            )
    chromium = find_chromium()
    for img in images:
        svg = root / "assets" / f"{img.name}.svg"
        png = root / img.png if img.png else svg.with_suffix(".png")
        cmd = render_command(chromium, svg, png, img.width, img.height, img.scale)
        done = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
        if done.returncode != 0:
            raise DataError(
                f"{svg.name}: Chromium exited {done.returncode}: {done.stderr[-300:]}"
            )
        data = png.read_bytes()
        want = (img.width * img.scale, img.height * img.scale)
        if png_size(data) != want:
            raise DataError(f"{png.name}: Chromium drew {png_size(data)}, want {want}")
        png.write_bytes(stamp_png(data, digest(img.svg)))


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(
        description="Build Nonna's launch images from the benchmark data."
    )
    mode = ap.add_mutually_exclusive_group()
    mode.add_argument(
        "--check",
        action="store_true",
        help="verify the committed images, write nothing",
    )
    mode.add_argument(
        "--render", action="store_true", help="also render the PNGs (needs Chromium)"
    )
    args = ap.parse_args(argv)
    default = Path(__file__).resolve().parent.parent
    root = Path(os.environ.get("NONNA_ASSETS_ROOT") or default).resolve()
    try:
        images = build_all(root)
        if args.check:
            problems = check(root, images)
            if problems:
                print("\n".join(problems), file=sys.stderr)
                print("fix: python3 assets/build.py --render", file=sys.stderr)
                return 1
            print(
                f"assets OK: {len(images)} images: SVGs match a fresh build; "
                "PNGs sized, within budget and rendered from them"
            )
            return 0
        for img in images:
            if img.source:
                continue
            path = root / "assets" / f"{img.name}.svg"
            path.parent.mkdir(parents=True, exist_ok=True)
            # LF on every platform, so the bytes --check compares are the same everywhere
            with open(path, "w", encoding="utf-8", newline="\n") as fh:
                fh.write(img.svg)
        if args.render:
            render(root, images)
    except (OSError, ValueError, subprocess.SubprocessError) as e:
        print(f"assets: {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
