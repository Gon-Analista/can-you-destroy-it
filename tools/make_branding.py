#!/usr/bin/env python3
"""Genera la imagen de marca del juego: icono y pantalla de arranque, en pixel art.

    python3 tools/make_branding.py

Salida (en game/branding/):
  icon.png        icono 32x32 ampliado x8 (256 px): ventana, editor y Linux (application/config/icon).
  icon.ico        icono de Windows (16 a 256 px) para el .exe y la ventana (windows_native_icon).
  splash.png      pantalla de arranque 640x360 x2 (1280x720), el logo del título sobre el cielo de noche.

El icono es el Cristal Madre (tres puntas de hielo con el corazón violeta) con la chispa rosa del aprendiz,
dibujado a mano por coordenadas: se retoca aquí y se vuelve a generar. Requiere Pillow, fontTools y brotli
(para leer la fuente Pixelify Sans del juego, que va en woff2).
"""
import io
import math
import pathlib
import random

from fontTools.ttLib import TTFont
from PIL import Image, ImageDraw, ImageFont

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "game" / "branding"
FONT_LOGO = ROOT / "game" / "ui" / "fonts" / "pixelify_sans_bold.woff2"

# Paleta del proyecto (project_context.md, sección 6, y ui/title_logo.gd).
BG = (20, 24, 58)  # #14183a
BG_TOP = (30, 38, 92)
BORDER = (42, 67, 167)  # #2a43a7
OUTLINE = (10, 12, 34)
ICE_HI = (201, 246, 255)  # #c9f6ff
ICE_LIGHT = (165, 218, 229)  # #a5dae5
ICE_MID = (69, 143, 184)  # #458fb8
ICE_DARK = (40, 75, 134)  # #284b86
VIOLET = (101, 79, 174)  # #654fae
VIOLET_LIGHT = (199, 155, 255)  # #c79bff
VIOLET_HOT = (240, 216, 255)
PINK = (255, 122, 217)  # #ff7ad9
GOLD = (255, 210, 122)  # #ffd27a
GOLD_DARK = (216, 162, 58)  # #d8a23a
SHADOW = (36, 24, 79)  # #24184f
CYAN = (165, 218, 229)
STAR = (201, 246, 255)

N = 32


def _shard(tip, base, half_w, shoulder):
    """Caras de una punta de cristal (prisma hexagonal visto de frente): izquierda, derecha y canto."""
    tx, ty = tip
    bx, by = base
    dx, dy = tx - bx, ty - by
    length = math.hypot(dx, dy)
    ux, uy = dx / length, dy / length
    nx, ny = -uy, ux  # perpendicular (hacia la derecha si la punta mira arriba)
    if nx < 0:
        nx, ny = -nx, -ny

    def p(along, side):
        return (bx + ux * along + nx * side, by + uy * along + ny * side)

    s = length - shoulder
    left = [tip, p(s, -half_w), p(0, -half_w), p(0, half_w * 0.15), p(s, half_w * 0.15)]
    right = [tip, p(s, half_w * 0.15), p(0, half_w * 0.15), p(0, half_w), p(s, half_w)]
    edge = [tip, p(s, half_w * 0.62), p(0, half_w * 0.62), p(0, half_w), p(s, half_w)]
    return left, right, edge


def _layer_shard(tip, base, half_w, shoulder, heart=False):
    img = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    left, right, edge = _shard(tip, base, half_w, shoulder)
    d.polygon(left, fill=ICE_LIGHT)
    d.polygon(right, fill=ICE_MID)
    d.polygon(edge, fill=ICE_DARK)
    px = img.load()
    # Brillo: la arista izquierda de la cara clara y la punta.
    for y in range(N):
        row = [x for x in range(N) if px[x, y][3] and px[x, y][:3] == ICE_LIGHT]
        if row:
            px[row[0], y] = ICE_HI
    tx, ty = int(round(tip[0])), int(round(tip[1]))
    for yy in range(ty, ty + 2):
        if 0 <= yy < N and px[tx, yy][3]:
            px[tx, yy] = ICE_HI + (255,)
    if heart:
        # Corazón violeta dentro de la punta grande, abajo (GDD: el Núcleo late dentro).
        hx, hy = base[0], base[1] - 5
        for y in range(N):
            for x in range(N):
                if not px[x, y][3]:
                    continue
                r = ((x - hx) / 3.6) ** 2 + ((y - hy) / 3.2) ** 2
                if r < 0.18:
                    px[x, y] = VIOLET_HOT + (255,)
                elif r < 0.5:
                    px[x, y] = VIOLET_LIGHT + (255,)
                elif r < 1.0:
                    px[x, y] = VIOLET + (255,)
    return img


def _outline(img):
    """Contorno de 1 px por fuera de lo opaco."""
    out = Image.new("RGBA", img.size, (0, 0, 0, 0))
    src = img.load()
    dst = out.load()
    w, h = img.size
    for y in range(h):
        for x in range(w):
            if src[x, y][3]:
                continue
            for ox, oy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                xx, yy = x + ox, y + oy
                if 0 <= xx < w and 0 <= yy < h and src[xx, yy][3]:
                    dst[x, y] = OUTLINE + (255,)
                    break
    out.alpha_composite(img)
    return out


def _spark(img, cx, cy):
    """Chispa rosa de cuatro puntas con el centro blanco."""
    px = img.load()
    for k in range(1, 3):
        for x, y in ((cx + k, cy), (cx - k, cy), (cx, cy + k), (cx, cy - k)):
            px[x, y] = (PINK if k == 1 else (196, 70, 160)) + (255,)
    px[cx, cy] = (255, 255, 255, 255)


def make_crystal():
    """El Cristal Madre solo (fondo transparente): tres puntas y la chispa del aprendiz."""
    img = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    back_l = _outline(_layer_shard((6.5, 11.0), (11.5, 28.0), 3.0, 6.0))
    back_r = _outline(_layer_shard((26.0, 9.0), (20.5, 28.0), 3.2, 6.5))
    front = _outline(_layer_shard((16.0, 2.0), (16.0, 28.5), 4.8, 9.0, heart=True))
    for layer in (back_l, back_r, front):
        img.alpha_composite(layer)
    _spark(img, 5, 5)
    return img


def make_icon(crystal):
    icon = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    d = ImageDraw.Draw(icon)
    # Baldosa redondeada: cielo de noche, más claro arriba (tramado en la transición) y borde azul.
    d.rounded_rectangle((0, 0, N - 1, N - 1), radius=6, fill=BORDER)
    d.rounded_rectangle((1, 1, N - 2, N - 2), radius=5, fill=BG)
    px = icon.load()
    for y in range(2, 16):
        for x in range(2, N - 2):
            if px[x, y][:3] == BG and (y < 10 or (x + y) % 2 == 0):
                px[x, y] = BG_TOP + (255,)
    for x, y in ((25, 4), (28, 15), (3, 18), (10, 3)):
        px[x, y] = STAR + (255,)
    # Suelo: un montículo oscuro donde nace el cristal.
    d.ellipse((4, 25, 27, 32), fill=SHADOW)
    icon.alpha_composite(crystal)
    # Recorta a la baldosa (esquinas transparentes) y vuelve a pintar el borde encima.
    mask = Image.new("L", (N, N), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, N - 1, N - 1), radius=6, fill=255)
    clipped = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    clipped.paste(icon, (0, 0), mask)
    ImageDraw.Draw(clipped).rounded_rectangle((0, 0, N - 1, N - 1), radius=6, outline=BORDER)
    return clipped


def _font(size):
    tt = TTFont(str(FONT_LOGO))
    tt.flavor = None
    buf = io.BytesIO()
    tt.save(buf)
    buf.seek(0)
    return ImageFont.truetype(buf, size)


def _text(draw, xy, text, font, fill, outline=None, shadow=None, shadow_off=2):
    x, y = xy
    if shadow:
        draw.text((x + shadow_off, y + shadow_off), text, font=font, fill=shadow)
    if outline:
        for ox in (-1, 0, 1):
            for oy in (-1, 0, 1):
                if ox or oy:
                    draw.text((x + ox, y + oy), text, font=font, fill=outline)
    draw.text((x, y), text, font=font, fill=fill)


def make_splash(crystal):
    w, h = 640, 360
    img = Image.new("RGB", (w, h), BG)
    d = ImageDraw.Draw(img)
    d.fontmode = "1"  # sin suavizado: píxeles enteros como en el juego
    rng = random.Random(7)
    for _ in range(70):
        x, y = rng.randrange(w), rng.randrange(h)
        img.putpixel((x, y), STAR if rng.random() < 0.3 else (80, 96, 150))
    # Mismo bloque que el logo del título: "CAN YOU" / "DESTROY IT" + "?" de cristal gigante.
    f_small, f_big, f_q = _font(22), _font(33), _font(77)
    big = "DESTROY IT"
    bb_big = d.textbbox((0, 0), big, font=f_big)
    bb_small = d.textbbox((0, 0), "CAN YOU", font=f_small)
    bb_q = d.textbbox((0, 0), "?", font=f_q)
    big_w = bb_big[2] - bb_big[0]
    q_w = bb_q[2] - bb_q[0]
    gap = 10
    x0 = round((w - big_w - q_w - gap) * 0.5)
    base_y = 262  # pie de "DESTROY IT"
    y_big = base_y - bb_big[3]
    y_small = base_y - (bb_big[3] - bb_big[1]) - 10 - bb_small[3]
    _text(d, (x0 - bb_small[0], y_small), "CAN YOU", f_small, CYAN, outline=SHADOW, shadow=BG)
    _text(d, (x0 - bb_big[0], y_big), big, f_big, GOLD, outline=SHADOW, shadow=BG)
    q_x = x0 + big_w + gap - bb_q[0]
    q_y = base_y - bb_q[3]
    d.text((q_x + 3, q_y + 3), "?", font=f_q, fill=ICE_MID)
    d.text((q_x, q_y), "?", font=f_q, fill=ICE_HI)
    # El Cristal Madre encima del bloque, x3.
    big_c = crystal.resize((96, 96), Image.NEAREST)
    img.paste(big_c, (w // 2 - 48, 84), big_c)
    return img.resize((w * 2, h * 2), Image.NEAREST)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    crystal = make_crystal()
    icon = make_icon(crystal)
    icon.resize((256, 256), Image.NEAREST).save(OUT / "icon.png")
    # Windows: cada tamaño a escala entera de los 32 px (los pequeños, reducidos con filtro).
    sizes = {
        256: icon.resize((256, 256), Image.NEAREST),
        128: icon.resize((128, 128), Image.NEAREST),
        64: icon.resize((64, 64), Image.NEAREST),
        48: icon.resize((96, 96), Image.NEAREST).resize((48, 48), Image.LANCZOS),
        32: icon,
        24: icon.resize((24, 24), Image.LANCZOS),
        16: icon.resize((16, 16), Image.LANCZOS),
    }
    base = sizes[256]
    others = [sizes[s] for s in (128, 64, 48, 32, 24, 16)]
    base.save(
        OUT / "icon.ico",
        sizes=[(s, s) for s in (256, 128, 64, 48, 32, 24, 16)],
        append_images=others,
    )
    make_splash(crystal).save(OUT / "splash.png")
    print("branding: icon.png, icon.ico, splash.png en", OUT)


if __name__ == "__main__":
    main()
