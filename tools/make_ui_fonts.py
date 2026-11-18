"""Genera las fuentes de la interfaz (game/ui/fonts/fusion_pixel_*.woff2).

Fuente: Fusion Pixel Font (TakWolf, OFL 1.1), proporcional de 10 y 12 px; sus letras latinas son
las de Ark Pixel Font. Se toma el paquete npm `@vp-tw/cjk-web-fonts-fusion-pixel-font` (subconjuntos
woff2 por bloque Unicode) y se juntan sólo los bloques que usa el juego: latín básico, Latin-1
(acentos, ñ, ¡, ¿, «») y puntuación general (…, —, comillas).

Además se crea una versión negrita "de píxel": cada glifo se rasteriza en su rejilla y cada trazo
crece un píxel a la derecha, salvo donde eso cerraría un hueco de 1 px (las patas de M, W, m, w,
N o la virgulilla de la ñ seguirían separadas); el avance crece un píxel. Así la negrita queda en
la misma rejilla que la normal a cualquier escala entera (el embolden del motor no lo garantiza
y convertía la M en un bloque).

Uso (requiere fonttools y brotli):

    npm pack @vp-tw/cjk-web-fonts-fusion-pixel-font
    tar xzf vp-tw-cjk-web-fonts-fusion-pixel-font-*.tgz
    python3 tools/make_ui_fonts.py package
"""

import sys
from pathlib import Path

from fontTools.fontBuilder import FontBuilder
from fontTools.merge import Merger
from fontTools.pens.boundsPen import BoundsPen
from fontTools.pens.pointInsidePen import PointInsidePen
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.ttLib import TTFont

OUT = Path(__file__).resolve().parent.parent / "game" / "ui" / "fonts"
BLOCKS = ["Basic-Latin", "Latin-1-Supplement", "General-Punctuation"]
SIZES = [10, 12]
# Tallas que el juego usa también en normal (de la de 12 sólo se usa la negrita, en títulos).
REGULAR_SIZES = [10]
# Unidades por píxel de la fuente (las dos tienen 100).
PX = 100


def merge_blocks(pkg: Path, size: int, tmp: Path) -> TTFont:
    """Junta los bloques de una talla en una sola fuente OpenType."""
    parts: list[str] = []
    for block in BLOCKS:
        src = (
            pkg
            / "dist"
            / f"{size}px"
            / "proportional"
            / "latin"
            / f"Fusion-Pixel-{size}px-Proportional-Latin.{block}.woff2"
        )
        f = TTFont(src)
        f.flavor = None
        part = tmp / f"part_{size}_{block}.otf"
        f.save(part)
        parts.append(str(part))
    return Merger().merge(parts)


def trim_metrics(font: TTFont, size: int) -> None:
    """Altura de línea justa: `size` px por encima (mayúsculas con tilde) y 2 por debajo.

    La original deja 1 px de más arriba y abajo (14 px de línea a 10 px): con tanto texto en
    mayúsculas, las líneas se veían separadas y los paneles crecían de más.
    """
    asc = size * PX
    desc = -2 * PX
    font["hhea"].ascent = asc
    font["hhea"].descent = desc
    font["hhea"].lineGap = 0
    os2 = font["OS/2"]
    os2.sTypoAscender = asc
    os2.sTypoDescender = desc
    os2.sTypoLineGap = 0
    os2.usWinAscent = asc
    os2.usWinDescent = -desc


def raster(gs, name: str) -> set[tuple[int, int]]:
    """Píxeles (x, y) encendidos del glifo, en unidades de píxel de la fuente."""
    bp = BoundsPen(gs)
    gs[name].draw(bp)
    if bp.bounds is None:
        return set()
    x0, y0, x1, y1 = (int(v // PX) for v in bp.bounds)
    on: set[tuple[int, int]] = set()
    for y in range(y0 - 1, y1 + 2):
        for x in range(x0 - 1, x1 + 2):
            pen = PointInsidePen(gs, ((x + 0.5) * PX, (y + 0.5) * PX))
            gs[name].draw(pen)
            if pen.getResult():
                on.add((x, y))
    return on


def embolden(on: set[tuple[int, int]]) -> set[tuple[int, int]]:
    """Cada trazo, un píxel más a la derecha, sin cerrar huecos de 1 px."""
    out = set(on)
    for x, y in on:
        if (x + 1, y) not in on and (x + 2, y) not in on:
            out.add((x + 1, y))
    return out


def draw_pixels(on: set[tuple[int, int]]):
    """Contornos TrueType de los píxeles: un rectángulo por tramo horizontal de cada fila."""
    pen = TTGlyphPen(None)
    for y in sorted({p[1] for p in on}):
        xs = sorted(p[0] for p in on if p[1] == y)
        start = xs[0]
        for i, x in enumerate(xs):
            if i + 1 < len(xs) and xs[i + 1] == x + 1:
                continue
            # Sentido horario (contorno exterior de TrueType).
            pen.moveTo((start * PX, y * PX))
            pen.lineTo((start * PX, (y + 1) * PX))
            pen.lineTo(((x + 1) * PX, (y + 1) * PX))
            pen.lineTo(((x + 1) * PX, y * PX))
            pen.closePath()
            if i + 1 < len(xs):
                start = xs[i + 1]
    return pen.glyph()


def make_bold(font: TTFont, family: str) -> TTFont:
    """Negrita de píxel: trazos un píxel más anchos y avance + 1 px."""
    gs = font.getGlyphSet()
    order = font.getGlyphOrder()
    cmap = font.getBestCmap()
    upm = font["head"].unitsPerEm
    glyphs = {}
    metrics = {}
    for name in order:
        on = raster(gs, name)
        if name != "space" and gs[name].width > 0 and on:
            on = embolden(on)
            if cmap.get(0xB7) == name:
                # El punto medio (separador "·") crece también hacia arriba: si no, parece un guion.
                on |= {(x, y + 1) for x, y in on}
        glyphs[name] = draw_pixels(on) if on else TTGlyphPen(None).glyph()
        adv = gs[name].width + (PX if gs[name].width > 0 else 0)
        metrics[name] = (adv, 0)
    fb = FontBuilder(upm, isTTF=True)
    fb.setupGlyphOrder(order)
    fb.setupCharacterMap(cmap)
    fb.setupGlyf(glyphs)
    fb.setupHorizontalMetrics(metrics)
    hhea = font["hhea"]
    fb.setupHorizontalHeader(ascent=hhea.ascent, descent=hhea.descent)
    fb.updateHead(macStyle=1)
    os2 = font["OS/2"]
    fb.setupOS2(
        sTypoAscender=os2.sTypoAscender,
        sTypoDescender=os2.sTypoDescender,
        sTypoLineGap=os2.sTypoLineGap,
        usWinAscent=os2.usWinAscent,
        usWinDescent=os2.usWinDescent,
        sxHeight=getattr(os2, "sxHeight", 0),
        sCapHeight=getattr(os2, "sCapHeight", 0),
        usWeightClass=700,
        fsSelection=0x20,
    )
    fb.setupNameTable(
        {
            "copyright": str(font["name"].getDebugName(0)),
            "familyName": family,
            "styleName": "Bold",
        }
    )
    fb.setupPost()
    return fb.font


def main() -> None:
    pkg = Path(sys.argv[1] if len(sys.argv) > 1 else "package")
    tmp = OUT / ".tmp_fonts"
    tmp.mkdir(exist_ok=True)
    for size in SIZES:
        regular = merge_blocks(pkg, size, tmp)
        trim_metrics(regular, size)
        regular.flavor = "woff2"
        if size in REGULAR_SIZES:
            regular.save(OUT / f"fusion_pixel_{size}.woff2")
        bold = make_bold(regular, f"Fusion Pixel {size}px Latin UI")
        bold.flavor = "woff2"
        bold.save(OUT / f"fusion_pixel_{size}_bold.woff2")
        print(f"fusion_pixel_{size}: {len(regular.getBestCmap())} caracteres")
    for p in tmp.iterdir():
        p.unlink()
    tmp.rmdir()


if __name__ == "__main__":
    main()
