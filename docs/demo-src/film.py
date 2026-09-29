"""Nonna launch film, v3: design system, cast playback, terminal painting, compositing.

Everything inside a terminal pane is the recording. Overlays state only measured values.
"""

import copy
import glob
import json
import os
import re
from collections import OrderedDict
from datetime import datetime

import pyte
from fontTools.ttLib import TTFont
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
FONTS = os.path.join(HERE, "..", "fonts")
W, H = 1920, 1080
M = 96  # page margin

# ---------------------------------------------------------------- palette
CREAM = (0xFF, 0xF1, 0xDC)
PAPER = (0xFF, 0xF8, 0xEC)
INK = (0x2B, 0x2A, 0x26)
INK2 = (0x6B, 0x64, 0x59)  # secondary text
INK3 = (0xA8, 0x9F, 0x90)  # hairlines, tertiary
BASIL = (0x2E, 0x5A, 0x43)
TOMATO = (0xC8, 0x3C, 0x22)
AMBER = (0x9A, 0x6A, 0x10)


def mix(a, b, t):
    return tuple(int(round(a[i] * (1 - t) + b[i] * t)) for i in range(3))


# ---------------------------------------------------------------- fonts
_F = {}


def font(name, size):
    key = (name, size)
    if key not in _F:
        path = {
            "serif": "InstrumentSerif-Regular.ttf",
            "serif-i": "InstrumentSerif-Italic.ttf",
            "sans": "TrueType/IBM-Plex-Sans/IBMPlexSans-Regular.ttf",
            "sans-m": "TrueType/IBM-Plex-Sans/IBMPlexSans-Medium.ttf",
            "sans-sb": "TrueType/IBM-Plex-Sans/IBMPlexSans-SemiBold.ttf",
            "sans-i": "TrueType/IBM-Plex-Sans/IBMPlexSans-Italic.ttf",
            "mono": "TrueType/IBM-Plex-Mono/IBMPlexMono-Regular.ttf",
            "mono-m": "TrueType/IBM-Plex-Mono/IBMPlexMono-Medium.ttf",
            "mono-sb": "TrueType/IBM-Plex-Mono/IBMPlexMono-SemiBold.ttf",
            "mono-i": "TrueType/IBM-Plex-Mono/IBMPlexMono-Italic.ttf",
            "pserif": "TrueType/IBM-Plex-Serif/IBMPlexSerif-Regular.ttf",
            "pserif-i": "TrueType/IBM-Plex-Serif/IBMPlexSerif-Italic.ttf",
            "dvmono": "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf",
            "dvmono-b": "/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf",
            "dvsans": "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
            "freeserif": "/usr/share/fonts/truetype/freefont/FreeSerif.ttf",
        }[name]
        if not path.startswith("/"):
            path = os.path.join(FONTS, path)
        _F[key] = ImageFont.truetype(path, size)
    return _F[key]


_CMAP = {}


def has_glyph(f, ch):
    p = f.path
    if p not in _CMAP:
        _CMAP[p] = set(TTFont(p).getBestCmap().keys())
    return ord(ch) in _CMAP[p]


# ---------------------------------------------------------------- text helpers
def _fallback_for(f):
    p = os.path.basename(f.path)
    if p.startswith("InstrumentSerif"):
        return font("pserif", f.size)
    if "Mono" in p:
        return font("dvmono", f.size)
    return font("dvsans", f.size)


def text(d, xy, s, f, fill):
    """Draw text; glyphs the face lacks fall back to a companion face at the same size."""
    if all(has_glyph(f, ch) for ch in s):
        d.text(xy, s, font=f, fill=fill)
        return
    x, y = xy
    fb = _fallback_for(f)
    run, cur = "", None
    for ch in s + "\0":
        ff = None if ch == "\0" else (f if has_glyph(f, ch) else fb)
        if ff is cur and ch != "\0":
            run += ch
            continue
        if run:
            d.text((x, y), run, font=cur, fill=fill)
            x += d.textlength(run, font=cur)
        run, cur = ch, ff


def tracked(d, xy, s, f, fill, spacing=0.12):
    """Uppercase label with letter-spacing (Pillow has no tracking)."""
    x, y = xy
    sp = f.size * spacing
    for ch in s:
        d.text((x, y), ch, font=f, fill=fill)
        x += d.textlength(ch, font=f) + sp
    return x


def tracked_width(d, s, f, spacing=0.12):
    return (
        sum(d.textlength(ch, font=f) + f.size * spacing for ch in s) - f.size * spacing
    )


def right(d, xr, y, s, f, fill):
    d.text((xr - d.textlength(s, font=f), y), s, font=f, fill=fill)


def wrap(d, s, f, maxw):
    out, cur = [], ""
    for w in s.split():
        t = (cur + " " + w).strip()
        if d.textlength(t, font=f) <= maxw:
            cur = t
        else:
            out.append(cur)
            cur = w
    if cur:
        out.append(cur)
    return out


def para(d, x, y, s, f, fill, maxw, lh=None):
    lh = lh or int(f.size * 1.35)
    for i, line in enumerate(wrap(d, s, f, maxw)):
        d.text((x, y + i * lh), line, font=f, fill=fill)
    return y + len(wrap(d, s, f, maxw)) * lh


def hairline(d, x0, y, x1, col=INK3, w=1):
    d.rectangle([x0, y, x1, y + w - 1], fill=col)


def page():
    return Image.new("RGB", (W, H), CREAM)


_MASC = None


def mascot(size):
    global _MASC
    if _MASC is None:
        _MASC = Image.open(os.path.join(HERE, "..", "mascot.png")).convert("RGBA")
    return _MASC.resize((size, size), Image.LANCZOS)


def put_mascot(im, size, xy):
    m = mascot(size)
    im.paste(m, xy, m)


# ---------------------------------------------------------------- casts
ANSI = {
    "black": INK,
    "red": (0xB0, 0x30, 0x28),
    "green": BASIL,
    "brown": (0x8A, 0x5E, 0x0C),
    "blue": (0x2A, 0x55, 0xA0),
    "magenta": (0x8A, 0x3A, 0x8A),
    "cyan": (0x1F, 0x6E, 0x74),
    "white": (0x5A, 0x55, 0x4C),
    "brightblack": (0x7A, 0x74, 0x68),
    "brightred": (0xC8, 0x40, 0x38),
    "brightgreen": (0x2E, 0x7A, 0x50),
    "brightbrown": (0x9A, 0x70, 0x18),
    "brightblue": (0x3A, 0x6A, 0xC0),
    "brightmagenta": (0xA0, 0x50, 0xA0),
    "brightcyan": (0x30, 0x88, 0x90),
    "brightwhite": INK,
}


def lum(c):
    return 0.299 * c[0] + 0.587 * c[1] + 0.114 * c[2]


def color(c, bg):
    if c == "default":
        return PAPER if bg else INK
    if c in ANSI:
        return ANSI[c]
    try:
        return tuple(int(c[i : i + 2], 16) for i in (0, 2, 4))
    except Exception:
        return PAPER if bg else INK


class Cast:
    """An asciinema v2 cast replayed through pyte into a list of screen states."""

    def __init__(self, path):
        L = [json.loads(line) for line in open(path)]
        self.cols, self.rows = L[0]["width"], L[0]["height"]
        scr = pyte.Screen(self.cols, self.rows)
        st = pyte.Stream(scr)
        self.states = []  # (t, lines, buffer)
        for e in L[1:]:
            if e[1] != "o":
                continue
            st.feed(re.sub(r"\x1b\[[<>=][0-9;]*[a-zA-Z]", "", e[2]))
            self.states.append(
                (e[0], list(scr.display), copy.deepcopy(dict(scr.buffer)))
            )
        self.duration = self.states[-1][0]
        # marks, in cast time
        self.busy_first = self.first(
            lambda ls: any("esc to interrupt" in l for l in ls)
        )
        cost_i = self.index(
            lambda ls: any(l.startswith("❯ /cost") or "Total cost:" in l for l in ls)
        )
        busy = [
            t
            for i, (t, ls, _) in enumerate(self.states)
            if (cost_i is None or i < cost_i)
            and any("esc to interrupt" in l for l in ls)
        ]
        self.busy_last = busy[-1] if busy else None
        self.t_end = next(
            (
                t
                for t, _, _ in self.states
                if self.busy_last is not None and t > self.busy_last
            ),
            self.busy_last,
        )
        self.t_cost = self.first(lambda ls: any("Total cost:" in l for l in ls))
        self.t_exit = self.first(lambda ls: any(l.startswith("❯ /exit") for l in ls))
        self.t_taste = self.first(lambda ls: any("tasting" in l for l in ls))
        self.t_block = self.first(lambda ls: any("Stop hook error" in l for l in ls))
        self.t0 = self.busy_first if self.busy_first is not None else 0.0

    def index(self, pred, start=0):
        for i in range(start, len(self.states)):
            if pred(self.states[i][1]):
                return i
        return None

    def first(self, pred, after=None):
        for t, ls, _ in self.states:
            if after is not None and t < after:
                continue
            if pred(ls):
                return t
        return None

    def first_shell(self, cmd):
        """Time the reveal command's echo appears after /exit, and time its output settles."""
        t_echo = self.first(
            lambda ls: any(l.rstrip() == "$ " + cmd for l in ls), after=self.t_exit
        )
        return t_echo

    def state_at(self, t):
        lo = 0
        for i, (tt, _, _) in enumerate(self.states):
            if tt <= t:
                lo = i
            else:
                break
        return lo

    def rows_with(self, i, needle):
        return [y for y, l in enumerate(self.states[i][1]) if needle in l]

    def rel(self, t):
        return None if t is None else t - self.t0


class Painter:
    """Paints a pyte buffer at a given mono size; LRU-cached per (cast id, state index)."""

    def __init__(self, cols, rows, size=18, lh=23):
        self.cols, self.rows, self.size, self.lh = cols, rows, size, lh
        self.f = font("mono", size)
        self.fb = font("mono-sb", size)
        self.fi = font("mono-i", size)
        self.cw = self.f.getlength("M")
        self.w = int(round(cols * self.cw))
        self.h = rows * lh
        self.fallbacks = [
            font("dvmono", size),
            font("dvmono-b", size),
            font("dvsans", size - 1),
            font("freeserif", size),
        ]
        self.cache = OrderedDict()

    def glyph_font(self, f, ch):
        if has_glyph(f, ch):
            return f
        for ff in self.fallbacks:
            if has_glyph(ff, ch):
                return ff
        return f

    def paint(self, cast, i):
        key = (id(cast), i)
        if key in self.cache:
            self.cache.move_to_end(key)
            return self.cache[key]
        buf = cast.states[i][2]
        im = Image.new("RGB", (self.w, self.h), PAPER)
        d = ImageDraw.Draw(im)
        cw, lh = self.cw, self.lh
        for y in range(self.rows):
            row = buf.get(y, {})
            for x in range(self.cols):
                c = row.get(x)
                if c is None:
                    continue
                fg, bg = color(c.fg, False), color(c.bg, True)
                if c.reverse:
                    fg, bg = bg, fg
                if bg == PAPER and lum(fg) > 120:
                    fg = mix(fg, INK, 0.45)
                if bg != PAPER:
                    d.rectangle(
                        [round(x * cw), y * lh, round((x + 1) * cw), (y + 1) * lh],
                        fill=bg,
                    )
                ch = c.data
                if not ch or ch == " ":
                    continue
                if ch == "─":
                    yy = y * lh + lh // 2
                    d.rectangle([round(x * cw), yy, round((x + 1) * cw), yy], fill=INK3)
                    continue
                f = self.fb if c.bold else (self.fi if c.italics else self.f)
                f = self.glyph_font(f, ch)
                d.text((x * cw, y * lh + 2), ch, font=f, fill=fg)
        self.cache[key] = im
        if len(self.cache) > 160:
            self.cache.popitem(last=False)
        return im


# ---------------------------------------------------------------- transcripts, cost
PRICE = {
    "in": 1.0,
    "out": 5.0,
    "cr": 0.10,
    "cw": 1.25,
}  # Haiku 4.5, USD per million tokens


def ts(s):
    return datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()


def cost_series(transcripts_dir, prompt_marker):
    """(seconds since the prompt, cumulative list-price cost) per assistant message."""
    msgs, prompt_ts, last = {}, None, ""
    for f in glob.glob(os.path.join(transcripts_dir, "**", "*.jsonl"), recursive=True):
        for line in open(f):
            try:
                d = json.loads(line)
            except Exception:
                continue
            if d.get("type") == "user" and prompt_ts is None:
                c = d.get("message", {}).get("content")
                if isinstance(c, str) and prompt_marker in c:
                    prompt_ts = ts(d["timestamp"])
            if d.get("type") == "assistant":
                m = d["message"]
                u = m.get("usage") or {}
                msgs[m["id"]] = (ts(d["timestamp"]), u)
                for c in m.get("content", []):
                    if c.get("type") == "text" and c["text"].strip():
                        last = c["text"]
    out, cum = [], 0.0
    for t, u in sorted(msgs.values()):
        cum += (
            u.get("input_tokens", 0) * PRICE["in"]
            + u.get("output_tokens", 0) * PRICE["out"]
            + u.get("cache_read_input_tokens", 0) * PRICE["cr"]
            + u.get("cache_creation_input_tokens", 0) * PRICE["cw"]
        ) / 1e6
        out.append((t - (prompt_ts or t), cum))
    return out, last


def cli_cost(path):
    m = re.search(r"Total cost:\s*\$([0-9.]+)", open(path).read())
    return float(m.group(1)) if m else None


def fmt_t(sec):
    sec = max(0, sec)
    return f"{int(sec // 60)}:{int(sec % 60):02d}"


def fmt_c(c):
    return f"${c:.2f}"


# ---------------------------------------------------------------- a recorded pair
class Arm:
    def __init__(self, pair_dir, arm, prompt_marker):
        self.cast = Cast(os.path.join(pair_dir, f"{arm}.cast"))
        self.cost = cli_cost(os.path.join(pair_dir, f"{arm}.cost.txt"))
        m = re.search(r"Total cost:\s*(\$[0-9.]+)", open(os.path.join(pair_dir, f"{arm}.cost.txt")).read())
        self.cost_str = m.group(1) if m else f"${self.cost:.4f}"
        series, self.final = cost_series(
            os.path.join(pair_dir, f"{arm}.transcripts"), prompt_marker
        )
        k = (
            (self.cost / series[-1][1])
            if series and series[-1][1] and self.cost
            else 1.0
        )
        self.series = [(t, c * k) for t, c in series]
        self.seconds = (self.cast.t_end - self.cast.t0) if self.cast.t_end else 0.0
        chk = open(os.path.join(pair_dir, f"{arm}.check.txt")).read()
        self.verdict = (
            "UNSAFE"
            if re.search(r"^(UNSAFE|LEAK)", chk, re.M)
            else (
                "SAFE"
                if re.search(r"^SAFE", chk, re.M)
                else ("UNSAFE" if "exit=1" in chk else "SAFE")
            )
        )
        self.check = chk
        m = re.search(r"suite: (.*passed.*|.*failed.*)", chk)
        self.suite = m.group(1).split(" in ")[0].strip() if m else ""

    def cost_at(self, tau):
        if tau >= self.seconds:
            return self.cost or 0.0
        c = 0.0
        for t, v in self.series:
            if t <= tau:
                c = v
        return c
