#!/usr/bin/env python3
"""Dibuja en pixel art el báculo del mago (primera persona) y su gema.

Uso:
    python3 tools/make_staff_sprite.py

Escribe:
- game/player/staff/staff.png: el báculo inclinado (de abajo a la derecha hacia arriba a la
  izquierda, como sostenido junto a la mano derecha): asta de madera oscura con una espiral de oro,
  un lazo violeta (el de las mangas) y una garra de oro que abraza el hueco de la gema.
- game/player/staff/staff_gem.png: la gema facetada en grises; el juego la tiñe con el color del
  elemento del báculo (modulate), así que sus luces y sombras sirven para todos.
- game/player/staff/staff_gem_shine.png: el brillo de la gema (sin teñir).
Mismo estilo que las manos de Sprite AI: contorno casi negro, luz de arriba a la izquierda y el oro
y el violeta de la pulsera y la manga. Se usa a 1:1 con filtro nearest.
"""
import math
from pathlib import Path

from PIL import Image

OUT = Path(__file__).resolve().parent.parent / "game" / "player" / "staff"

OUTLINE = (24, 10, 14, 255)
WOOD = [(58, 28, 20), (92, 50, 30), (128, 76, 42), (166, 106, 58), (204, 146, 86)]
GOLD = [(120, 62, 10), (173, 98, 11), (226, 148, 22), (245, 178, 24), (255, 232, 140)]
CLOTH = [(40, 4, 34), (61, 2, 46), (101, 30, 92), (146, 70, 140)]
W, H = 84, 236
# Línea central del asta: de abajo a la derecha hacia arriba a la izquierda.
BOTTOM = (60.0, H + 6.0)
TOP = (30.0, 70.0)
SHAFT_R = 4.6
GEM_C = (28.0, 42.0)


def shaft_frame(x, y):
    """(t a lo largo del asta 0 abajo..1 arriba, desplazamiento con signo a lo ancho)."""
    bx, by = BOTTOM
    tx, ty = TOP
    dx, dy = tx - bx, ty - by
    length = math.hypot(dx, dy)
    ux, uy = dx / length, dy / length
    px, py = x - bx, y - by
    t = (px * ux + py * uy) / length
    # Normal hacia la izquierda de la subida (lado de la luz).
    nx, ny = -uy, ux
    side = px * nx + py * ny
    return t, side, length


def draw_shaft(img):
    for y in range(H):
        for x in range(W):
            t, side, length = shaft_frame(x + 0.5, y + 0.5)
            if t < 0.0 or t > 1.04:
                continue
            # Se estrecha un poco hacia la punta (y se ensancha en el regatón de abajo).
            r = SHAFT_R * (1.0 - 0.18 * t)
            d = abs(side)
            if d > r + 1.0:
                continue
            if d > r:
                img.putpixel((x, y), OUTLINE)
                continue
            # Luz desde la izquierda (side < 0 es el lado de la luz).
            k = (-side / r) * 0.5 + 0.5
            band = min(4, max(0, int(k * 4.6)))
            col = WOOD[band]
            s = t * length
            # Vetas de la madera: alguna raya más oscura a lo largo.
            if (int(s * 0.5) + int(side * 2)) % 9 == 0 and band > 0:
                col = WOOD[band - 1]
            # Espiral de oro que sube por el asta.
            spiral = (s * 0.3 + side * 0.75) % 6.0
            if 60 < s < length - 34 and spiral < 2.1:
                g = 3 if side < 0 else (2 if side < r * 0.5 else 1)
                if spiral < 0.6 and side < 0:
                    g = 4
                col = GOLD[g]
            # Anillos de oro: arriba (bajo la garra) y uno a media altura.
            for ring_s, ring_w in ((length - 22, 3.2), (length - 30, 1.6), (112, 2.4)):
                if abs(s - ring_s) < ring_w:
                    g = 3 if band >= 3 else (2 if band >= 1 else 1)
                    if abs(s - ring_s) > ring_w - 1.0:
                        g = max(0, g - 2)
                    col = GOLD[g]
            img.putpixel((x, y), col + (255,))


def ring_pixel(x, y):
    """Garra de oro: un aro abierto por arriba con dos puntas que se curvan hacia la gema."""
    cx, cy = GEM_C
    dx, dy = x - cx, y - cy
    r = math.hypot(dx, dy)
    a = math.degrees(math.atan2(dy, dx))  # 0 a la derecha, 90 abajo, -90 arriba
    inside = 12.6 < r < 18.2
    gap = -118 < a < -62  # abierto por arriba
    # Puntas: cuernos que suben a cada lado de la abertura y se curvan hacia la gema.
    for side in (-1, 1):
        for i in range(24):
            u = i / 23.0
            hx = cx + side * (12.5 - 9.0 * u ** 1.6)
            hy = cy - 13.0 - 13.0 * u
            th = 3.0 * (1.0 - u) + 0.9
            if math.hypot(x - hx, y - hy) < th:
                return 2, math.hypot(x - hx, y - hy) / th
    # Pico de abajo que baja hacia el asta.
    if abs(dx + (dy - 17.0) * 0.18) < max(0.0, 5.4 - (dy - 15.0) * 0.45) and 15.0 < dy < 28.0:
        return 1, abs(dx) / 4.0
    if inside and not gap:
        return 0, (r - 12.6) / 5.6
    return None


def draw_head(img):
    cx, cy = GEM_C
    # Hueco oscuro de la gema (detrás de la gema teñida).
    for y in range(H):
        for x in range(W):
            px, py = x + 0.5, y + 0.5
            if math.hypot(px - cx, (py - cy) * 0.86) < 13.0:
                img.putpixel((x, y), (30, 14, 40, 255))
    shape = {}
    for y in range(H):
        for x in range(W):
            hit = ring_pixel(x + 0.5, y + 0.5)
            if hit is not None:
                shape[(x, y)] = hit
    for (x, y), (_kind, k) in shape.items():
        # Luz de arriba a la izquierda sobre el aro.
        lx = (x - (cx - 8)) / 26.0 + (y - (cy - 10)) / 26.0
        g = 3 if lx < 0.45 else (2 if lx < 0.95 else 1)
        if k < 0.3 and lx < 0.5:
            g = 4
        if k > 0.8:
            g = max(0, g - 1)
        img.putpixel((x, y), GOLD[g] + (255,))
    # Contorno de la garra.
    for (x, y) in list(shape):
        for ox, oy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            q = (x + ox, y + oy)
            if q not in shape and 0 <= q[0] < W and 0 <= q[1] < H:
                cur = img.getpixel(q)
                if cur[3] == 0 or cur[:3] in WOOD or cur[:3] == (30, 14, 40):
                    if math.hypot(q[0] + 0.5 - cx, (q[1] + 0.5 - cy) * 0.86) >= 12.4:
                        img.putpixel(q, OUTLINE)
    # Gemitas azules engastadas en la garra (como las de la pulsera).
    for gx, gy in ((cx - 15.4, cy + 3.0), (cx + 15.4, cy + 3.0), (cx, cy + 18.0)):
        for y in range(int(gy) - 2, int(gy) + 3):
            for x in range(int(gx) - 2, int(gx) + 3):
                d = math.hypot(x + 0.5 - gx, y + 0.5 - gy)
                if d < 1.9:
                    col = (47, 151, 227) if (x + 0.5 - gx) + (y + 0.5 - gy) < 0 else (30, 80, 170)
                    if d < 0.8 and x + 0.5 < gx:
                        col = (190, 235, 255)
                    img.putpixel((x, y), col + (255,))


def draw_ribbon(img):
    """Lazo violeta atado bajo la garra, con dos cintas que cuelgan."""
    _t, _s, length = shaft_frame(0, 0)
    knot_s = length - 44.0
    bx, by = BOTTOM
    tx, ty = TOP
    ux, uy = (tx - bx) / length, (ty - by) / length
    kx, ky = bx + ux * knot_s, by + uy * knot_s
    pix = {}
    # Nudo.
    for y in range(int(ky) - 4, int(ky) + 5):
        for x in range(int(kx) - 5, int(kx) + 6):
            if ((x + 0.5 - kx) / 4.6) ** 2 + ((y + 0.5 - ky) / 3.2) ** 2 < 1.0:
                pix[(x, y)] = 2 if x + 0.5 < kx else 1
    # Cintas: caen hacia la derecha con una onda.
    for i, (amp, off) in enumerate(((2.2, 3.0), (1.6, -2.0))):
        for j in range(26 if i == 0 else 20):
            yy = ky + 3 + j
            xx = kx + off + j * 0.42 + math.sin(j * 0.45 + i) * amp
            w = 2.4 - j * 0.05
            for x in range(int(xx - w), int(xx + w) + 1):
                d = x + 0.5 - xx
                if abs(d) < w:
                    pix[(x, int(yy))] = 3 if d < -w * 0.4 else (2 if d < w * 0.3 else 1)
    for (x, y), c in pix.items():
        if 0 <= x < W and 0 <= y < H:
            img.putpixel((x, y), CLOTH[c] + (255,))
    for (x, y) in list(pix):
        for ox, oy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            q = (x + ox, y + oy)
            if q not in pix and 0 <= q[0] < W and 0 <= q[1] < H:
                cur = img.getpixel(q)
                if cur[3] == 0:
                    img.putpixel(q, OUTLINE)


def draw_gem():
    """Gema ovalada facetada en grises (se tiñe en el juego) y su brillo aparte."""
    gw, gh = 22, 26
    gem = Image.new("RGBA", (gw, gh), (0, 0, 0, 0))
    shine = Image.new("RGBA", (gw, gh), (0, 0, 0, 0))
    cx, cy = gw / 2.0, gh / 2.0
    for y in range(gh):
        for x in range(gw):
            px, py = x + 0.5 - cx, y + 0.5 - cy
            e = (px / 10.2) ** 2 + (py / 12.4) ** 2
            if e >= 1.0:
                continue
            if e > 0.78:
                gem.putpixel((x, y), (40, 40, 48, 255))
                continue
            # Facetas: tabla central y cuatro caras; la luz entra por arriba a la izquierda.
            if abs(px) < 3.8 and abs(py) < 5.0:
                v = 236 if px + py < 0 else 200
            elif px < 0 and py < 0:
                v = 255
            elif px >= 0 and py < 0:
                v = 186
            elif px < 0 and py >= 0:
                v = 150
            else:
                v = 104
            if e > 0.6:
                v = int(v * 0.72)
            gem.putpixel((x, y), (v, v, v, 255))
    for (x, y) in ((6, 5), (7, 5), (6, 6), (5, 7), (14, 16)):
        shine.putpixel((x, y), (255, 255, 255, 255))
    shine.putpixel((7, 6), (255, 255, 255, 160))
    return gem, shine


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    draw_shaft(img)
    draw_ribbon(img)
    draw_head(img)
    img.save(OUT / "staff.png")
    gem, shine = draw_gem()
    gem.save(OUT / "staff_gem.png")
    shine.save(OUT / "staff_gem_shine.png")
    print(f"báculo {img.size}, gema {gem.size} en {OUT}")


if __name__ == "__main__":
    main()
