"""Assemble the Nonna launch film from the recorded pairs and the copy deck.

usage: build.py <copy.json> <out-prefix> [--gif] [--frames-only]
"""

import json
import os
import subprocess
import sys

import imageio_ffmpeg
from PIL import Image, ImageDraw

import film as F  # noqa: F401
from film import (
    BASIL,
    CREAM,
    H,
    INK,
    INK2,
    INK3,
    M,
    TOMATO,
    W,
    Arm,
    Painter,
    fmt_t,
    font,
    hairline,
    page,
    para,
    put_mascot,
    right,
    text,
    tracked,
    tracked_width,
    mix,
)

FPS = 24
SPEED = 3.0
IDLE_CAP = 2.0  # real seconds of silence kept at most (in both panes at once)
IDLE_TO = 2.0  # ... shown as this many real seconds (÷ SPEED on output)
XFADE = 12  # frames

HERE = os.path.dirname(os.path.abspath(__file__))
COPY = json.load(open(sys.argv[1]))
OUT = sys.argv[2]
FLAGS = set(sys.argv[3:])
KEY = {}  # named key frames for QA
# claims-done pairs 1-4 shared one config dir across concurrent tasks, so their captured final message can be
# another task's; claims-done.sh reads that message, so those four stay in the tables but out of every tally.
EXCLUDE = {"claims-done": {1, 2, 3, 4}}


def keyframe(name, im):
    if name not in KEY:
        KEY[name] = im.copy()


def progress(im, frac):
    d = ImageDraw.Draw(im)
    hairline(d, M, H - 40, W - M, mix(CREAM, INK3, 0.5))
    if frac > 0:
        d.rectangle([M, H - 41, M + int((W - 2 * M) * frac), H - 39], fill=BASIL)
    return im


def label(d, x, y, s, col=INK2, size=15):
    return tracked(d, (x, y), s, font("mono-m", size), col)


def label_right(d, xr, y, s, col=INK2, size=15):
    f = font("mono-m", size)
    tracked(d, (xr - tracked_width(d, s, f), y), s, f, col)


def tint(im, box, col, alpha=26):
    ov = Image.new("RGBA", im.size, (0, 0, 0, 0))
    ImageDraw.Draw(ov).rectangle(box, fill=col + (alpha,))
    return Image.alpha_composite(im.convert("RGBA"), ov).convert("RGB")


# ---------------------------------------------------------------- scenes
class Scene:
    n = 0

    def frame(self, k):
        raise NotImplementedError

    def key(self, k):
        return None


class Card(Scene):
    """A static card held for `seconds`, with an optional list of (frame, name) key frames."""

    def __init__(self, im, seconds, name=None):
        self.im, self.n, self.name = im, int(seconds * FPS), name

    def frame(self, k):
        if self.name and k == 0:
            keyframe(self.name, self.im)
        return self.im


class Reveal(Scene):
    """A card whose lines appear one after another (each held), then the whole is held."""

    def __init__(self, base, steps, hold, name=None):
        # steps: list of (image, seconds)
        self.steps, self.name = steps, name
        self.marks = []
        n = 0
        for im, s in steps:
            self.marks.append((n, im))
            n += int(s * FPS)
        self.n = n + int(hold * FPS)

    def frame(self, k):
        im = self.steps[0][0]
        for start, i in self.marks:
            if k >= start:
                im = i
        if self.name and k == self.n - 1:
            keyframe(self.name, im)
        return im


# ---------------------------------------------------------------- the split-screen chapter
PANE_SIZE, PANE_LH = 18, 23


class Chapter(Scene):
    def __init__(self, spec, pair_dir):
        self.spec = spec
        self.a = Arm(pair_dir, "a", spec["prompt_marker"])
        self.b = Arm(pair_dir, "b", spec["prompt_marker"])
        ca, cb = self.a.cast, self.b.cast
        self.P = Painter(ca.cols, ca.rows, PANE_SIZE, PANE_LH)
        self.pw, self.ph = self.P.w, self.P.h
        self.gap = W - 2 * M - 2 * self.pw
        self.xa, self.xb = M, M + self.pw + self.gap
        self.yp = 176
        # marks in shared time (seconds since the prompt)
        self.t_done_a = ca.rel(ca.t_end)
        self.t_done_b = cb.rel(cb.t_end)
        self.t_taste = cb.rel(cb.t_taste)
        blk = cb.first(lambda ls: any("✗" in l for l in ls))
        self.t_block = cb.rel(blk)
        self.t_cost = max(ca.rel(ca.t_cost) or 0, cb.rel(cb.t_cost) or 0)
        self.reveal = spec["reveal"]
        self.t_echo = {}
        self.t_settle = {}
        for arm, c in (("a", ca), ("b", cb)):
            echo = None
            for cmd in self.reveal:
                e = c.first(
                    lambda ls, cmd=cmd: any(l.rstrip() == "$ " + cmd for l in ls),
                    after=c.t_cost,
                )
                if e is not None:
                    echo = e
            self.t_echo[arm] = c.rel(echo) if echo is not None else None
            # settled: the prompt is back after the last command
            settle = None
            if echo is not None:
                for t, ls, _ in c.states:
                    if t < echo:
                        continue
                    nz = [l for l in ls if l.strip()]
                    if nz and nz[-1].strip() == "$":
                        settle = t
                        break
            self.t_settle[arm] = c.rel(settle) if settle is not None else None
        settles = [v for v in self.t_settle.values() if v is not None]
        self.has_reveal = bool(settles)
        self.t_start = (
            min(
                ca.rel(ca.first(lambda ls: any(spec["prompt_marker"] in l for l in ls)))
                or 0,
                0,
            )
            - 0.4
        )
        self.t_end = (max(settles) + 0.3) if settles else (self.t_cost + 1.0)
        # timeline
        times = sorted(
            {
                c.rel(t)
                for c in (ca, cb)
                for t, _, _ in c.states
                if self.t_start <= c.rel(t) <= self.t_end
            }
            | {self.t_start, self.t_end}
        )
        holds = spec.get("holds", {})
        hold_at = {}
        for name, sec in holds.items():
            t = {
                "done_a": self.t_done_a,
                "taste": self.t_taste,
                "block": self.t_block,
                "done_b": self.t_done_b,
                "cost": self.t_cost,
                "end": self.t_end,
            }.get(name)
            if t is not None:
                hold_at[t] = hold_at.get(t, 0) + sec
        self.tl = [(0.0, times[0])]
        out = 0.0
        applied = set()
        for i in range(1, len(times)):
            dt = times[i] - times[i - 1]
            out += (IDLE_TO if dt > IDLE_CAP else dt) / SPEED
            for ht, hs in hold_at.items():
                if ht not in applied and times[i] >= ht:
                    out += hs
                    applied.add(ht)
            self.tl.append((out, times[i]))
        self.total = out + hold_at.get(self.t_end, 0)
        self.n = int(self.total * FPS) + 1
        self.cap = spec["captions"]
        # tallies over every recorded pair of this task (pairs_table.py), for honest on-screen counts
        self.stats = dict(n_pairs=0, n_a_unsafe=0, n_b_unsafe=0, n_blocked=0, n_rules=0)
        tp = os.path.join(HERE, "pairs_table.json")
        if os.path.exists(tp):
            rows = [
                r
                for r in json.load(open(tp))
                if r["task"] == spec["task"]
                and r["n"] not in EXCLUDE.get(spec["task"], ())
            ]
            self.stats = dict(
                n_pairs=len(rows),
                n_a_unsafe=sum(r["a"]["verdict"] == "UNSAFE" for r in rows),
                n_b_unsafe=sum(r["b"]["verdict"] == "UNSAFE" for r in rows),
                n_blocked=sum(bool(r["b"]["blocked"]) for r in rows),
                n_rules=sum(
                    (not r["b"]["blocked"]) and r["b"]["verdict"] == "SAFE"
                    for r in rows
                ),
            )
        self.first_line_a = (
            self.a.final.strip().split("\n")[0] if self.a.final else ""
        )[:28]
        self.first_line_b = (
            self.b.final.strip().split("\n")[0] if self.b.final else ""
        )[:28]

    def tau_at(self, v):
        lo = 0
        for k, (ot, tt) in enumerate(self.tl):
            if ot <= v:
                lo = k
            else:
                break
        if lo + 1 < len(self.tl):
            (o0, t0), (o1, t1) = self.tl[lo], self.tl[lo + 1]
            if o1 > o0 and (o1 - o0) <= (t1 - t0) / SPEED + 1e-6:
                return min(t1, t0 + (v - o0) * SPEED)
        return self.tl[lo][1]

    def mark(self, name):
        base, _, off = name.partition("+")
        t = {
            "start": -1e9,
            "done_a": self.t_done_a,
            "taste": self.t_taste,
            "block": self.t_block,
            "done_b": self.t_done_b,
            "cost": self.t_cost,
            "reveal": min([v for v in self.t_echo.values() if v is not None] or [1e9]),
            "settle": max(
                [v for v in self.t_settle.values() if v is not None] or [1e9]
            ),
        }.get(base)
        if t is None:
            return None
        if base == "start" and off:
            t = 0.0
        return t + (float(off) if off else 0.0)

    def caption_at(self, tau):
        cur = self.cap[0]
        for c in self.cap:
            t = self.mark(c["at"])
            if t is not None and tau >= t - 0.01:
                cur = c
        return cur

    def highlight(self, im, arm, c, i, needle, col, rows_after=1, rows_before=0):
        rows = c.rows_with(i, needle)
        if not rows:
            return im
        y0 = rows[0] - rows_before
        y1 = rows[0] + rows_after
        x = self.xa if arm == "a" else self.xb
        im = tint(
            im,
            (
                x,
                self.yp + y0 * PANE_LH - 2,
                x + self.pw - 1,
                self.yp + (y1 + 1) * PANE_LH + 1,
            ),
            col,
            30,
        )
        ImageDraw.Draw(im).rectangle(
            [
                x - 4,
                self.yp + y0 * PANE_LH - 2,
                x - 1,
                self.yp + (y1 + 1) * PANE_LH + 1,
            ],
            fill=col,
        )
        return im

    def frame(self, k, final_tau=None):
        tau = self.tau_at(k / FPS) if final_tau is None else final_tau
        ca, cb = self.a.cast, self.b.cast
        ia, ib = ca.state_at(ca.t0 + tau), cb.state_at(cb.t0 + tau)
        im = page()
        d = ImageDraw.Draw(im)
        # header
        text(d, (M, 58), self.spec["number"], font("serif", 60), INK3)
        text(d, (M + 78, 58), self.spec["title"], font("serif", 60), INK)
        label_right(d, W - M, 74, COPY["badge"], INK2)
        # pane labels and readouts
        for arm, x, name, col, A in (
            ("a", self.xa, COPY["left_label"], TOMATO, self.a),
            ("b", self.xb, COPY["right_label"], BASIL, self.b),
        ):
            label(d, x, 146, name, col)
            done = tau >= A.seconds
            el = min(max(tau, 0), A.seconds)
            s = f"{int(el)} s   {A.cost_str if done else f'${A.cost_at(tau):.4f}'}"
            right(d, x + self.pw, 143, s, font("mono", 18), INK if done else INK2)
            if done:
                label_right(
                    d,
                    x + self.pw - d.textlength(s, font=font("mono", 18)) - 22,
                    147,
                    "STOPPED",
                    INK2,
                    13,
                )
        # panes
        im.paste(self.P.paint(ca, ia), (self.xa, self.yp))
        im.paste(self.P.paint(cb, ib), (self.xb, self.yp))
        d = ImageDraw.Draw(im)
        for x in (self.xa, self.xb):
            d.rectangle(
                [x - 1, self.yp - 1, x + self.pw, self.yp + self.ph],
                outline=mix(CREAM, INK3, 0.6),
            )
        # highlights on real lines
        if (
            self.t_done_a is not None
            and tau >= self.t_done_a - 0.01
            and self.first_line_a
            and tau < (self.t_cost or 1e9)
        ):
            im = self.highlight(
                im, "a", ca, ia, self.first_line_a, TOMATO, rows_after=2
            )
        if self.t_taste is not None and self.t_taste - 0.01 <= tau < (
            self.t_block or self.t_done_b or 1e9
        ):
            im = self.highlight(im, "b", cb, ib, "tasting", BASIL)
        if (
            self.t_block is not None
            and tau >= self.t_block - 0.01
            and tau < (self.t_cost or 1e9)
        ):
            im = self.highlight(
                im, "b", cb, ib, "✗", BASIL, rows_after=3, rows_before=1
            )
        if (
            self.t_cost
            and tau >= self.t_cost - 0.01
            and tau < min([v for v in self.t_echo.values() if v is not None] or [1e9])
        ):
            for arm, c, i in (("a", ca, ia), ("b", cb, ib)):
                im = self.highlight(im, arm, c, i, "Total cost:", INK3, rows_after=0)
        for arm, c, i in (("a", ca, ia), ("b", cb, ib)):
            te = self.t_echo.get(arm)
            if te is not None and tau >= te:
                for mark in self.spec.get("reveal_marks", []):
                    needle, kind = mark[0], mark[1]
                    side = mark[2] if len(mark) > 2 else None
                    if side and side != arm:
                        continue
                    im = self.highlight(
                        im,
                        arm,
                        c,
                        i,
                        needle,
                        TOMATO if kind == "bad" else BASIL,
                        rows_after=0,
                    )
        d = ImageDraw.Draw(im)
        # caption
        c = self.caption_at(tau)
        y = self.yp + self.ph + 34
        x = M
        if c.get("side"):
            col = TOMATO if c["side"] == "left" else BASIL
            x = label(d, M, y + 9, c["side"].upper(), col, 15) + 22
        f = font("sans", 27)
        line = c["text"].format(**self.stats)
        while d.textlength(line, font=f) > W - M - x:
            f = font("sans", f.size - 1)
        text(d, (x, y), line, f, INK)
        return im

    def key(self, k):
        pass


# ---------------------------------------------------------------- cards
def disclosure():
    """The honesty line, generated from the renderer's own constants so it cannot drift."""
    return (
        f"Plays at {SPEED:g}×; a silence longer than {IDLE_CAP:g} s of real time is cut to {IDLE_TO:g} s "
        f"({IDLE_TO / SPEED:.1f} s on screen). No frame is edited and no step is cut; the clocks show real time. "
        f"The running cost is Claude Code’s own usage log at list prices; the final figure is its /cost."
    )


def card_cold_open(ch):
    """Real frames from the bare arm, large: its last message; then the full suite in the same shell."""
    ca = ch.a.cast
    P = Painter(ca.cols, ca.rows, 22, 28)
    frames = []
    # 1. the statement
    im = page()
    d = ImageDraw.Draw(im)
    f = font("serif", 132)
    lines = COPY["cold"]["statement"]
    y = H // 2 - len(lines) * 75
    for i, l in enumerate(lines):
        text(d, (M, y + i * 150), l, f, BASIL if i == len(lines) - 1 else INK)
    frames.append((im, 2.6))
    # 2. the bare terminal at its final message
    i_done = ca.state_at(ca.t_end + 0.5) if ca.t_end else len(ca.states) - 1
    x0 = (W - P.w) // 2
    y0 = 92
    im2 = page()
    im2.paste(P.paint(ca, i_done), (x0, y0))
    d = ImageDraw.Draw(im2)
    d.rectangle([x0 - 1, y0 - 1, x0 + P.w, y0 + P.h], outline=mix(CREAM, INK3, 0.6))
    label(d, x0, 56, COPY["cold"]["label_done"], INK2)
    rows = ca.rows_with(i_done, ch.first_line_a)
    if rows:
        im2 = tint(
            im2,
            (x0, y0 + rows[0] * 28 - 3, x0 + P.w - 1, y0 + (rows[0] + 3) * 28 + 2),
            TOMATO,
            30,
        )
        ImageDraw.Draw(im2).rectangle(
            [x0 - 4, y0 + rows[0] * 28 - 3, x0 - 1, y0 + (rows[0] + 3) * 28 + 2],
            fill=TOMATO,
        )
    d = ImageDraw.Draw(im2)
    text(d, (x0, y0 + P.h + 18), COPY["cold"]["under_done"], font("sans", 24), INK2)
    frames.append((im2, 3.2))
    # 3. the same shell, the full suite
    if ch.has_reveal and ch.t_settle.get("a") is not None:
        i_rev = ca.state_at(ca.t0 + ch.t_settle["a"] + 0.2)
        im3 = page()
        im3.paste(P.paint(ca, i_rev), (x0, y0))
        d = ImageDraw.Draw(im3)
        d.rectangle([x0 - 1, y0 - 1, x0 + P.w, y0 + P.h], outline=mix(CREAM, INK3, 0.6))
        label(d, x0, 56, COPY["cold"]["label_suite"], INK2)
        for mark in ch.spec.get("reveal_marks", []):
            needle, col = mark[0], mark[1]
            if len(mark) > 2 and mark[2] != "a":
                continue
            rows = ca.rows_with(i_rev, needle)
            if rows:
                im3 = tint(
                    im3,
                    (
                        x0,
                        y0 + rows[-1] * 28 - 3,
                        x0 + P.w - 1,
                        y0 + (rows[-1] + 1) * 28 + 2,
                    ),
                    TOMATO if col == "bad" else BASIL,
                    34,
                )
                ImageDraw.Draw(im3).rectangle(
                    [
                        x0 - 4,
                        y0 + rows[-1] * 28 - 3,
                        x0 - 1,
                        y0 + (rows[-1] + 1) * 28 + 2,
                    ],
                    fill=TOMATO if col == "bad" else BASIL,
                )
        d = ImageDraw.Draw(im3)
        text(
            d, (x0, y0 + P.h + 18), COPY["cold"]["under_suite"], font("sans", 24), INK2
        )
        xe = label(d, x0, y0 + P.h + 58, COPY["cold"]["verdict_label"], TOMATO, 14)
        text(
            d,
            (xe + 18, y0 + P.h + 55),
            COPY["cold"]["verdict_text"],
            font("mono", 16),
            INK2,
        )
        frames.append((im3, 3.6))
    return frames


def card_title():
    im = page()
    d = ImageDraw.Draw(im)
    put_mascot(im, 460, (M, 300))
    x = M + 560
    text(d, (x, 300), "Nonna", font("serif", 180), BASIL)
    text(d, (x + 6, 500), COPY["title"]["tag"], font("serif", 74), INK)
    y = 620
    for l in COPY["title"]["sub"]:
        y = para(d, x + 8, y, l, font("sans", 29), INK2, W - M - (x + 8), lh=42)
    return im


def card_method():
    im = page()
    d = ImageDraw.Draw(im)
    c = COPY["method"]
    label(d, M, 100, c["kicker"], INK2)
    y = 150
    for l in c["head"]:
        text(d, (M - 4, y), l, font("serif", 96), INK)
        y += 108
    if c.get("sub"):
        text(d, (M, y + 10), c["sub"], font("sans", 27), INK2)
        y += 52
    y += 24
    hairline(d, M, y, W - M)
    y += 34
    colw = (W - 2 * M - 2 * 60) // 3
    for i, (k, v) in enumerate(c["facts"]):
        x = M + i * (colw + 60)
        label(d, x, y, k, BASIL)
        para(d, x, y + 34, v, font("sans", 24), INK, colw, lh=32)
    if c.get("prompts"):
        y2 = y + 176
        hairline(d, M, y2, W - M)
        label(d, M, y2 + 22, c["prompts_label"], INK2)
        for i, (k, v) in enumerate(c["prompts"]):
            x = M + i * (colw + 60)
            label(d, x, y2 + 60, k, BASIL, 13)
            para(d, x, y2 + 84, v, font("mono", 16), INK, colw, lh=22)
    para(d, M, H - 132, disclosure(), font("sans-i", 20), INK2, W - 2 * M, lh=27)
    return im


def card_result(ch, spec):
    """End of a chapter: the two outcomes, in words and measured numbers."""
    im = page()
    d = ImageDraw.Draw(im)
    text(d, (M, 58), spec["number"], font("serif", 60), INK3)
    text(d, (M + 78, 58), spec["title"], font("serif", 60), INK)
    r = spec["result"]
    xa, xb, cw = ch.xa, ch.xb, ch.pw
    y = 196
    hairline(d, xa, y, xa + cw)
    hairline(d, xb, y, xb + cw)
    label(d, xa, y + 22, COPY["left_label"], TOMATO)
    label(d, xb, y + 22, COPY["right_label"], BASIL)
    for x, A, big, col, line in (
        (xa, ch.a, r["left_big"], TOMATO, r["left_line"]),
        (xb, ch.b, r["right_big"], BASIL, r["right_line"]),
    ):
        big = big.format(suite=A.suite or "", verdict=A.verdict)
        f = font("serif", 84)
        while d.textlength(big, font=f) > cw:
            f = font("serif", f.size - 4)
        text(d, (x - 3, y + 62), big, f, col)
        yy = y + 190
        text(
            d,
            (x, yy),
            f"{int(A.seconds)} s  ·  {A.cost_str}",
            font("mono", 26),
            INK,
        )
        label(
            d,
            x,
            yy + 44,
            r["verdict_label"].format(verdict=A.verdict),
            col if A.verdict == "UNSAFE" else BASIL,
        )
        yy = para(d, x, yy + 90, line.format(**ch.stats), font("sans", 27), INK, cw)
    ybot = y + 470
    hairline(d, M, ybot, W - M)
    vals = dict(
        dt=fmt_t(ch.b.seconds - ch.a.seconds),
        dsec=int(round(ch.b.seconds - ch.a.seconds)),
        dcost=int(round((ch.b.cost - ch.a.cost) * 100)),
        a_sec=int(round(ch.a.seconds)),
        b_sec=int(round(ch.b.seconds)),
        **ch.stats,
    )
    take = r["takeaway"].format(**vals)
    para(d, M - 2, ybot + 36, take, font("serif", 54), INK, W - 2 * M, lh=64)
    if r.get("foot"):
        para(
            d,
            M,
            H - 150,
            r["foot"].format(**vals),
            font("sans-i", 22),
            INK2,
            W - 2 * M,
            lh=30,
        )
    return im


def card_ledger(c):
    im = page()
    d = ImageDraw.Draw(im)
    label(d, M, 100, c["kicker"], INK2)
    y = 150
    if c.get("head"):
        text(d, (M - 4, y), c["head"], font("serif", 96), INK)
        y += 130
    hairline(d, M, y, W - M)
    y += 26
    for k, v in c["rows"]:
        label(d, M, y + 8, k, BASIL, 16)
        yy = para(d, M + 430, y, v, font("sans", 27), INK, W - M - (M + 430), lh=36)
        y = yy + 22
        hairline(d, M, y, W - M, mix(CREAM, INK3, 0.55))
        y += 26
    para(d, M, H - 150, c["foot"], font("sans-i", 22), INK2, W - 2 * M, lh=30)
    return im


def card_cost(ch):
    im = page()
    d = ImageDraw.Draw(im)
    c = COPY["cost"]
    label(d, M, 100, c["kicker"], INK2)
    y = 150
    for l in c["head"]:
        text(d, (M - 4, y), l, font("serif", 96), INK)
        y += 108
    y += 24
    hairline(d, M, y, W - M)
    y += 26
    vals = dict(a_cost=ch.a.cost_str, b_cost=ch.b.cost_str)
    for k, v in c["rows"]:
        label(d, M, y + 8, k, BASIL, 16)
        yy = para(
            d,
            M + 430,
            y,
            v.format(**vals),
            font("sans", 27),
            INK,
            W - M - (M + 430),
            lh=36,
        )
        y = yy + 22
        hairline(d, M, y, W - M, mix(CREAM, INK3, 0.55))
        y += 26
    para(d, M, H - 150, c["foot"], font("sans-i", 22), INK2, W - 2 * M, lh=30)
    return im


def card_numbers():
    im = page()
    d = ImageDraw.Draw(im)
    c = COPY["numbers"]
    label(d, M, 100, c["kicker"], INK2)
    text(d, (M - 4, 150), c["head"], font("serif", 96), INK)
    y = 300
    hairline(d, M, y, W - M)
    y += 40
    # the two figures
    for i, (lab, big, col) in enumerate(c["figures"]):
        x = M + i * 440
        label(d, x, y + 4, lab, INK2)
        text(
            d,
            (x - 6, y + 22),
            big,
            font("serif", 190),
            {"#tomato": TOMATO, "#basil": BASIL, "#ink": INK}.get(col, INK),
        )
    para(d, M, y + 262, c["big_sub"], font("sans", 27), INK, 860, lh=36)
    xr = M + 1008
    yy = y + 4
    for k, v in c["rows"]:
        label(d, xr, yy, k, INK2)
        yy = para(d, xr, yy + 30, v, font("sans", 25), INK, W - M - xr, lh=34) + 34
    text(d, (M, H - 130), c["foot"], font("sans-i", 21), INK2)
    return im


def card_close():
    im = page()
    d = ImageDraw.Draw(im)
    c = COPY["close"]
    put_mascot(im, 520, (M, 280))
    x = M + 620
    label(d, x, 250, c["kicker"], INK2)
    for i, l in enumerate(F.wrap(d, c["head"], font("serif", 96), W - M - x)):
        text(d, (x - 3, 290 + i * 104), l, font("serif", 96), BASIL)
    y = 520
    for cmd in c["commands"]:
        hairline(d, x, y, W - M)
        text(d, (x, y + 22), cmd, font("mono-m", 38), INK)
        y += 104
    hairline(d, x, y, W - M)
    text(d, (x, y + 30), c["url"], font("serif", 72), BASIL)
    para(d, x + 2, y + 130, c["line"], font("sans", 22), INK2, W - M - x, lh=30)
    return im


# ---------------------------------------------------------------- assemble
def build_scenes():
    scenes = []
    chapters = []
    for spec in COPY["chapters"]:
        chapters.append(
            Chapter(spec, os.path.join(HERE, "pairs", spec["task"], str(spec["pair"])))
        )
    ch1 = chapters[0]
    cold = card_cold_open(ch1)
    scenes.append(("cold", Reveal(None, cold, 0.4, name="cold_last")))
    scenes.append(("title", Card(card_title(), COPY["title"]["seconds"], "title")))
    scenes.append(("method", Card(card_method(), COPY["method"]["seconds"], "method")))
    for spec, ch in zip(COPY["chapters"], chapters):
        scenes.append((f"ch{spec['number']}", ch))
        scenes.append(
            (
                f"res{spec['number']}",
                Card(
                    card_result(ch, spec),
                    spec["result"]["seconds"],
                    f"result{spec['number']}",
                ),
            )
        )
    for i, hc in enumerate(COPY["harness"]):
        scenes.append(
            (f"harness{i}", Card(card_ledger(hc), hc["seconds"], f"harness{i}"))
        )
    scenes.append(
        ("numbers", Card(card_numbers(), COPY["numbers"]["seconds"], "numbers"))
    )
    scenes.append(("cost", Card(card_cost(ch1), COPY["cost"]["seconds"], "cost")))
    scenes.append(("close", Card(card_close(), COPY["close"]["seconds"], "close")))
    return scenes, chapters


def frames(scenes):
    total = sum(s.n for _, s in scenes) + XFADE * (len(scenes) - 1)
    k = 0
    prev_last = None
    for si, (name, s) in enumerate(scenes):
        first = None
        for j in range(s.n):
            im = s.frame(j)
            if j == 0:
                first = im
                if prev_last is not None:
                    for f in range(XFADE):
                        t = (f + 1) / (XFADE + 1)
                        yield (
                            name,
                            progress(Image.blend(prev_last, first, t), k / total),
                        )
                        k += 1
            yield name, progress(im.copy(), k / total)
            k += 1
            prev_last = im
        # chapter key frames for QA
        if isinstance(s, Chapter):
            for nm, t in (
                ("start", 4.0),
                ("done_a", (s.t_done_a or 0) + 0.3),
                ("taste", s.t_taste),
                ("block", (s.t_block + 0.4) if s.t_block is not None else None),
                ("done_b", (s.t_done_b or 0) + 0.3),
                ("cost", (s.t_cost or 0) + 0.5),
                ("reveal", s.t_end - 0.2),
            ):
                if t is not None:
                    keyframe(f"{name}_{nm}", progress(s.frame(0, final_tau=t), 0.5))


def main():
    scenes, chapters = build_scenes()
    total = sum(s.n for _, s in scenes) + XFADE * (len(scenes) - 1)
    print(
        "scenes:",
        [(n, round(s.n / FPS, 1)) for n, s in scenes],
        "total",
        round(total / FPS, 1),
        "s",
    )
    for ch in chapters:
        print(
            ch.spec["task"],
            "marks",
            {
                k: (round(v, 1) if v is not None else None)
                for k, v in dict(
                    done_a=ch.t_done_a,
                    taste=ch.t_taste,
                    block=ch.t_block,
                    done_b=ch.t_done_b,
                    cost=ch.t_cost,
                    echo=ch.t_echo,
                    settle=ch.t_settle,
                    end=ch.t_end,
                ).items()
                if not isinstance(v, dict)
            },
            ch.t_echo,
            ch.t_settle,
            "reveal" if ch.has_reveal else "NO REVEAL",
        )
    if "--frames-only" in FLAGS:
        for name, s in scenes:
            if isinstance(s, Chapter):
                for nm, t in (
                    ("start", 4.0),
                    ("done_a", (s.t_done_a or 0) + 0.3),
                    ("taste", s.t_taste),
                    ("block", (s.t_block + 0.4) if s.t_block is not None else None),
                    ("done_b", (s.t_done_b or 0) + 0.3),
                    ("cost", (s.t_cost or 0) + 0.5),
                    ("reveal", s.t_end - 0.2),
                ):
                    if t is not None:
                        keyframe(f"{name}_{nm}", progress(s.frame(0, final_tau=t), 0.5))
            else:
                s.frame(0)
                s.frame(s.n - 1)
        os.makedirs(OUT + "_frames", exist_ok=True)
        for k, v in KEY.items():
            v.save(f"{OUT}_frames/{k}.png")
        print("frames:", sorted(KEY))
        return
    ff = imageio_ffmpeg.get_ffmpeg_exe()
    p = subprocess.Popen(
        [
            ff,
            "-y",
            "-loglevel",
            "error",
            "-f",
            "rawvideo",
            "-pix_fmt",
            "rgb24",
            "-s",
            f"{W}x{H}",
            "-r",
            str(FPS),
            "-i",
            "-",
            "-c:v",
            "libx264",
            "-preset",
            "medium",
            "-crf",
            "19",
            "-pix_fmt",
            "yuv420p",
            "-movflags",
            "+faststart",
            OUT + ".mp4",
        ],
        stdin=subprocess.PIPE,
    )
    n = 0
    gif = []
    GF = 6
    gif_scenes = None
    gw = 1280
    for fl in FLAGS:
        if fl.startswith("--gif-scenes="):
            gif_scenes = set(fl.split("=", 1)[1].split(","))
        if fl.startswith("--gif-width="):
            gw = int(fl.split("=", 1)[1])
    for name, im in frames(scenes):
        p.stdin.write(im.tobytes())
        if (
            "--gif" in FLAGS
            and n % (FPS // GF) == 0
            and (gif_scenes is None or name in gif_scenes)
        ):
            gif.append(im.resize((gw, gw * 9 // 16), Image.LANCZOS))
        n += 1
    p.stdin.close()
    p.wait()
    os.makedirs(OUT + "_frames", exist_ok=True)
    for k, v in KEY.items():
        v.save(f"{OUT}_frames/{k}.png")
    print(
        "mp4",
        round(os.path.getsize(OUT + ".mp4") / 1e6, 2),
        "MB;",
        n,
        "frames;",
        round(n / FPS, 1),
        "s; key frames:",
        len(KEY),
    )
    if gif:
        # one palette for the whole GIF (per-frame palettes flicker), built from a sample of frames
        step = max(1, len(gif) // 12)
        strip = Image.new("RGB", (gif[0].width, gif[0].height * len(gif[::step])))
        for i, im in enumerate(gif[::step]):
            strip.paste(im, (0, i * gif[0].height))
        pal = strip.quantize(
            colors=96, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE
        )
        ims, durs, prev = [], [], None
        for im in gif:
            b = im.tobytes()
            if b == prev:
                durs[-1] += 1000 // GF
            else:
                ims.append(im.quantize(palette=pal, dither=Image.Dither.NONE))
                durs.append(1000 // GF)
                prev = b
        ims[0].save(
            OUT + ".gif",
            save_all=True,
            append_images=ims[1:],
            duration=durs,
            loop=0,
            optimize=True,
            disposal=1,
        )
        print(
            "gif",
            round(os.path.getsize(OUT + ".gif") / 1e6, 2),
            "MB",
            len(ims),
            "frames",
        )


if __name__ == "__main__":
    main()
