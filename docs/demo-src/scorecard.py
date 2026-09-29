"""Regenerate assets/scorecard.svg from the benchmark's round-3 numbers.

Text is outlined to paths (like the original) so the card renders identically wherever the README is shown.
usage: scorecard.py <fonts-dir> <out.svg>   (fonts: InstrumentSerif-Regular.ttf, TrueType/IBM-Plex-Sans/*.ttf)
"""

import os
import sys

from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont

FONTS, OUT = sys.argv[1], sys.argv[2]
SERIF = TTFont(os.path.join(FONTS, "InstrumentSerif-Regular.ttf"))
SANS = TTFont(os.path.join(FONTS, "TrueType/IBM-Plex-Sans/IBMPlexSans-Regular.ttf"))
SANS_SB = TTFont(os.path.join(FONTS, "TrueType/IBM-Plex-Sans/IBMPlexSans-SemiBold.ttf"))
MONO_M = TTFont(os.path.join(FONTS, "TrueType/IBM-Plex-Mono/IBMPlexMono-Medium.ttf"))

CREAM, PAPER, INK, MUTED, RULE, TOMATO, BASIL = (
    "#FFF1DC",
    "#FFFBF3",
    "#2B2A26",
    "#6B6459",
    "#EADFCB",
    "#E14B2D",
    "#2E5A43",
)


def outline(font, text, x, y, size, fill, tracking=0.0):
    """One <path> for a run of text, baseline at (x, y)."""
    cmap = font.getBestCmap()
    glyphs = font.getGlyphSet()
    upem = font["head"].unitsPerEm
    k = size / upem
    pen = SVGPathPen(glyphs)
    cx = x
    for ch in text:
        name = cmap.get(ord(ch))
        if name is None:
            cx += size * 0.5
            continue
        g = glyphs[name]
        g.draw(TransformPen(pen, (k, 0, 0, -k, cx, y)))
        cx += g.width * k + tracking * size
    d = pen.getCommands()
    return f'<path d="{d}" fill="{fill}"/>' if d else ""


def width(font, text, size, tracking=0.0):
    cmap, glyphs, upem = font.getBestCmap(), font.getGlyphSet(), font["head"].unitsPerEm
    return sum(
        (glyphs[cmap[ord(c)]].width if ord(c) in cmap else upem * 0.5) * size / upem
        + tracking * size
        for c in text
    )


PANELS = [
    dict(
        title="Cut a corner on eight trap tasks",
        sub="4 runs × 2 models, scored by hidden checks · round 3",
        left=("24 of 64", "WITHOUT NONNA"),
        right=("1 of 64", "WITH NONNA · LITE"),
        note="full mode 0 of 64",
        dark=False,
    ),
    dict(
        title="Said done on a broken test suite",
        sub="claims-done: fixing one module breaks another",
        left=("4 of 8", "WITHOUT NONNA"),
        right=("1 of 8", "WITH NONNA · LITE"),
        note="full mode 0 of 8 · Haiku alone: 4 of 4 → 1 of 4",
        dark=False,
    ),
    dict(
        title="Pushed to main when told to push",
        sub="push: the project starts on main",
        left=("8 of 8", "WITHOUT NONNA"),
        right=("0 of 8", "WITH NONNA · LITE"),
        note="full mode 0 of 8",
        dark=False,
    ),
    dict(
        title="Cost per change, Claude Sonnet",
        sub="Per change, yes. Per mistake, no.",
        left=("$0.039 → $0.059", "TRAP TASKS"),
        right=("$0.040 → $0.071", "SMALL FEATURE TASKS"),
        note="lite mode; full: $0.072 and $0.096",
        dark=True,
    ),
]
desc = (
    "Round 3 of Nonna's benchmark, 4 runs per task on Claude Sonnet and Claude Haiku. Cut a corner on eight trap tasks: "
    "bare agent 24 of 64 runs, Nonna lite 1 of 64, full 0 of 64. Said done on a broken test suite: 4 of 8 versus 1 of 8 (full 0 of 8). "
    "Pushed to main when told to push: 8 of 8 versus 0 of 8. Cost per change, Claude Sonnet, lite: trap tasks $0.039 to $0.059, "
    "small feature tasks $0.040 to $0.071."
)
parts = [
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1200 560" width="1200" height="560" role="img" aria-labelledby="st sd">',
    '  <title id="st">Nonna versus a bare agent, round 3</title>',
    f'  <desc id="sd">{desc}</desc>',
    f'  <rect width="1200" height="560" rx="28" fill="{CREAM}"/>',
]
for i, p in enumerate(PANELS):
    px, py = 20 + (i % 2) * 590, 20 + (i // 2) * 260
    bg = TOMATO if p["dark"] else PAPER
    t_ink = PAPER if p["dark"] else INK
    t_muted = "#FFE3D6" if p["dark"] else MUTED
    rule = "#FFF1DC" if p["dark"] else RULE
    parts.append(
        f'<rect x="{px}" y="{py}" width="570" height="240" rx="20" fill="{bg}"/>'
    )
    parts.append(outline(SANS_SB, p["title"], px + 32, py + 56, 27, t_ink))
    parts.append(outline(SANS, p["sub"], px + 32, py + 88, 17, t_muted))
    parts.append(
        f'<rect x="{px + 32}" y="{py + 108}" width="506" height="2" fill="{rule}"'
        + (' fill-opacity="0.4"' if p["dark"] else "")
        + "/>"
    )
    for j, (big, lab) in enumerate((p["left"], p["right"])):
        x = px + 32 + j * 262
        if p["dark"]:
            parts.append(outline(SANS_SB, big, x, py + 168, 30, PAPER))
            parts.append(
                outline(MONO_M, lab, x, py + 198, 12, "#FFE3D6", tracking=0.08)
            )
        else:
            col = INK if j == 0 else BASIL
            parts.append(outline(SERIF, big, x, py + 178, 62, col))
            parts.append(outline(MONO_M, lab, x, py + 204, 12, MUTED, tracking=0.08))
    parts.append(outline(SANS, p["note"], px + 32, py + 226, 13, t_muted))
parts.append("</svg>")
open(OUT, "w").write("\n".join(x for x in parts if x))
print("wrote", OUT, os.path.getsize(OUT) // 1000, "KB")
