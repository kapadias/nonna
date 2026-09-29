#!/usr/bin/env python3
"""Regenerate space-grotesk.json, the glyph outlines assets/build.py lays text out from.

Run it by hand, and rarely: only to add a weight or a character. It needs fontTools, which nothing
else in this repo does, so `build.py --check` and CI never run it.

usage: python3 assets/font/make_glyphs.py 'SpaceGrotesk[wght].ttf'
       (the variable font from https://github.com/google/fonts/tree/main/ofl/spacegrotesk)

The JSON keeps, per weight and character, the advance width and the outline in font units (y up;
the SVG path commands M L H V Q Z, absolute), which build.py scales and flips. Each weight is
instanced from the variable font and compiled once, as a static font would be, so its outlines are
whole font units: that is what makes the text match the banner's outlines to the digit.
The font is SIL OFL 1.1: OFL.txt sits beside the JSON.
"""

from __future__ import annotations

import hashlib
import io
import json
import sys
from pathlib import Path

from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

WEIGHTS = (400, 500, 600, 700)
# ASCII, the typographic quotes, the ellipsis, the middle dot and the dashes.
CHARS = [chr(c) for c in range(0x20, 0x7F)] + list("“”‘’…·–—")
OUT = Path(__file__).with_name("space-grotesk.json")
SOURCE = "https://github.com/google/fonts/tree/main/ofl/spacegrotesk"


def static_instance(variable_font: Path, weight: int) -> TTFont:
    inst = instancer.instantiateVariableFont(TTFont(variable_font), {"wght": weight})
    buf = io.BytesIO()
    inst.save(buf)  # compiling rounds every outline to whole font units
    buf.seek(0)
    return TTFont(buf)


def glyphs_at(variable_font: Path, weight: int) -> dict[str, list[object]]:
    font = static_instance(variable_font, weight)
    glyph_set, cmap = font.getGlyphSet(), font.getBestCmap()
    out: dict[str, list[object]] = {}
    for ch in CHARS:
        if ord(ch) not in cmap:
            sys.exit(f"the font has no glyph for {ch!r} (U+{ord(ch):04X})")
        name = cmap[ord(ch)]
        pen = SVGPathPen(glyph_set, ntos=lambda v: f"{v:g}")
        glyph_set[name].draw(pen)
        out[ch] = [font["hmtx"][name][0], pen.getCommands()]
    return out


def dump(head: dict[str, object], glyphs: dict[int, dict[str, list[object]]]) -> str:
    """One glyph per line, so a change to one shows as one line in a diff."""
    lines = ["{"] + [f" {json.dumps(k)}: {json.dumps(v)}," for k, v in head.items()]
    lines.append(' "glyphs": {')
    blocks = []
    for weight, table in glyphs.items():
        rows = [
            f"   {json.dumps(ch)}: {json.dumps(g, separators=(',', ':'))}"
            for ch, g in table.items()
        ]
        blocks.append(f'  "{weight}": {{\n' + ",\n".join(rows) + "\n  }")
    lines.append(",\n".join(blocks))
    return "\n".join(lines + [" }", "}"]) + "\n"


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print(__doc__, file=sys.stderr)
        return 2
    src = Path(argv[1])
    head = {
        "family": "Space Grotesk",
        "license": "SIL Open Font License 1.1, see OFL.txt",
        "source": SOURCE,
        "source_sha256": hashlib.sha256(src.read_bytes()).hexdigest(),
        "upm": 1000,
    }
    OUT.write_text(
        dump(head, {w: glyphs_at(src, w) for w in WEIGHTS}), encoding="utf-8"
    )
    print(f"wrote {OUT} ({OUT.stat().st_size} bytes)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
