#!/usr/bin/env python3
"""Hornea el volumen del Cristal Madre: campo de distancia con signo (SDF) en una rejilla 3D.

Uso:
    python3 tools/crystal_volume.py          # escribe game/crystal/data/crystal_volume.bin
    python3 tools/crystal_volume.py --info   # sólo imprime medidas y volúmenes

El cristal es destructible de verdad: el juego (crystal/crystal_volume.gd) parte de esta rejilla,
la erosiona en cada golpe y rehace la malla de los trozos tocados. Este script define la forma
(un racimo de prismas hexagonales con punta, fundidos en una base ancha) y calcula:

- `sdf`: distancia firmada a la superficie (negativa dentro), en metros, por punto de la rejilla.
  Incluye las geodas: bolsas huecas tapizadas de amatista en el Manto Geódico.
- `depth`: profundidad de cada punto bajo la superficie original (sin geodas), por transformada
  de distancia euclídea. Decide la capa: Corteza, Manto Geódico, Venas, Corazón y Núcleo.
- La esencia por m3 de cada capa, para que cada capa reparta su parte de 1.000.000 (GDD 6).

Formato (little endian): cabecera de texto JSON de una línea terminada en "\\n" y después dos
bloques float16 comprimidos con gzip (sdf y depth), con su tamaño en la cabecera.
Determinista: la forma está escrita a mano y las geodas usan una semilla fija.
"""
import argparse
import gzip
import json
import math
from pathlib import Path

import numpy as np
from scipy import ndimage

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "game" / "crystal" / "data" / "crystal_volume.bin"

H = 0.7  # tamaño de la celda (m)
CHUNK = 16  # celdas por lado de cada trozo de malla
LO = np.array([-36.0, -4.2, -36.0])
HI = np.array([36.0, 72.0, 36.0])

# Puntas: base (x, y, z), eje, radio (al vértice del hexágono), largo hasta el hombro, punta, giro.
SPIRES = [
    # La punta principal: ~38 veces la altura del mago.
    ((0.0, -4.0, 0.0), (0.05, 1.0, 0.03), 13.0, 46.0, 22.0, 0.0),
    ((-14.0, -4.0, 4.0), (-0.5, 1.0, 0.14), 7.5, 25.0, 10.0, 0.4),
    ((-6.0, -4.0, -13.0), (-0.22, 1.0, -0.55), 6.8, 23.0, 9.0, 0.9),
    ((10.0, -4.0, -11.0), (0.42, 1.0, -0.46), 6.2, 20.0, 8.0, 0.2),
    ((14.0, -4.0, 3.0), (0.62, 1.0, 0.1), 6.6, 21.0, 9.0, 0.7),
    ((-8.0, -4.0, 13.0), (-0.36, 1.0, 0.7), 5.2, 15.0, 7.0, 0.1),
    ((6.0, -4.0, 13.5), (0.2, 1.0, 0.8), 5.0, 14.0, 6.0, 0.5),
    ((15.0, -4.0, -6.0), (0.85, 1.0, -0.32), 4.0, 11.0, 5.0, 0.3),
    ((-16.0, -4.0, -6.0), (-0.8, 1.0, -0.3), 4.2, 10.0, 5.0, 0.8),
    # Racimos pequeños al pie.
    ((-21.0, -2.0, 9.0), (-1.0, 0.8, 0.45), 2.6, 5.5, 3.0, 0.2),
    ((-19.0, -2.0, 13.5), (-0.5, 0.7, 1.0), 2.1, 4.5, 2.5, 0.6),
    ((21.0, -2.0, 9.0), (1.0, 0.75, 0.35), 2.5, 5.5, 3.0, 0.1),
    ((19.5, -2.0, 13.0), (0.6, 0.8, 0.9), 1.9, 4.0, 2.2, 0.9),
    ((3.0, -2.0, -21.0), (0.1, 0.8, -1.0), 2.4, 5.0, 2.8, 0.4),
    ((-4.0, -2.0, -20.0), (-0.4, 0.9, -0.9), 1.8, 4.0, 2.2, 0.7),
    ((0.0, -2.0, 21.5), (0.05, 0.7, 1.0), 2.2, 4.5, 2.6, 0.3),
]
# Base: un zócalo hexagonal ancho y bajo que funde las puntas (se puede excavar a pie de suelo).
BASE = ((0.0, -4.0, 0.0), (0.0, 1.0, 0.0), 21.0, 4.5, 6.5, 0.26)

# Capas (GDD 6): profundidad mínima bajo la superficie original (m) y parte de la esencia.
LAYERS = [
    ("crust", 0.0, 0.10),
    ("geode_mantle", 1.6, 0.35),
    ("resonant_veins", 4.2, 0.35),
    ("crystal_heart", 7.2, 0.19),
    ("core", None, 0.01),
]
# El Núcleo: esfera violeta en la base del cristal.
CORE_CENTER = np.array([0.0, 5.0, 0.0])
CORE_RADIUS = 3.6
TOTAL_ESSENCE = 1_000_000
OUTSIDE_CLAMP = 3 * H
GEODE_COUNT = 26
GEODE_RADIUS = (1.3, 2.0)


def basis(axis, twist):
    y = np.asarray(axis, float)
    y /= np.linalg.norm(y)
    ref = np.array([0.0, 0.0, 1.0]) if abs(y[2]) < 0.9 else np.array([1.0, 0.0, 0.0])
    x = np.cross(y, ref)
    x /= np.linalg.norm(x)
    z = np.cross(x, y)
    c, s = math.cos(twist), math.sin(twist)
    return x * c + z * s, y, -x * s + z * c


def spire_sdf(p, base, axis, radius, length, tip, twist):
    """Prisma hexagonal con punta piramidal: intersección de planos (convexo)."""
    bx, by, bz = basis(axis, twist)
    q = p - np.asarray(base, float)
    lx, ly, lz = q @ bx, q @ by, q @ bz
    apo = radius * math.cos(math.pi / 6)  # apotema
    d = -ly  # suelo del prisma
    slope = apo / tip
    norm = math.hypot(1.0, slope)
    for k in range(6):
        a = k * math.pi / 3
        r = lx * math.cos(a) + lz * math.sin(a)
        d = np.maximum(d, r - apo)
        # Cara de la punta: pasa por el borde del hombro y por el vértice.
        d = np.maximum(d, (r + (ly - length) * slope - apo) / norm)
    return d


def build_grid():
    n = np.ceil((HI - LO) / H).astype(int) + 1
    n = ((n - 1 + CHUNK - 1) // CHUNK) * CHUNK + 1  # trozos completos
    xs = LO[0] + np.arange(n[0]) * H
    ys = LO[1] + np.arange(n[1]) * H
    zs = LO[2] + np.arange(n[2]) * H
    # Orden de memoria: x más rápido, luego y, luego z (igual que en GDScript).
    Z, Y, X = np.meshgrid(zs, ys, xs, indexing="ij")
    p = np.stack([X, Y, Z], axis=-1)
    d = spire_sdf(p, *BASE)
    for s in SPIRES:
        d = np.minimum(d, spire_sdf(p, *s))
    return n, p, d


def place_geodes(p, depth):
    rng = np.random.default_rng(7)
    lo, hi = LAYERS[1][1] + 0.6, LAYERS[2][1] - 0.4
    cand = np.argwhere((depth > lo) & (depth < hi) & (p[..., 1] > 0.5))
    rng.shuffle(cand)
    geodes = []
    for idx in cand:
        c = p[tuple(idx)]
        if all(np.linalg.norm(c - np.array(g["center"])) > 9.0 for g in geodes):
            geodes.append({"center": [round(float(v), 3) for v in c],
                           "radius": round(float(rng.uniform(*GEODE_RADIUS)), 3)})
        if len(geodes) >= GEODE_COUNT:
            break
    return geodes


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--info", action="store_true")
    args = ap.parse_args()
    n, p, sdf = build_grid()
    inside = sdf < 0.0
    # Profundidad real bajo la superficie (donde se juntan dos puntas el SDF analítico se queda corto).
    depth = ndimage.distance_transform_edt(inside) * H
    depth = np.where(inside, np.maximum(depth - H * 0.5, -sdf), 0.0)
    geodes = place_geodes(p, depth)
    for g in geodes:
        c, r = np.array(g["center"]), g["radius"]
        hole = r - np.linalg.norm(p - c, axis=-1)
        sdf = np.maximum(sdf, hole)
    # Fuera del cristal la "profundidad" es la distancia negativa (útil para el shader).
    depth = np.where(sdf < 0.0, depth, np.minimum(-sdf, 0.0))
    core = np.linalg.norm(p - CORE_CENTER, axis=-1) < CORE_RADIUS
    # Volumen sólido de cada capa (fracción de celda llena, igual que en el juego).
    fill = np.clip(0.5 - sdf / H, 0.0, 1.0) * H ** 3
    layer = np.zeros(sdf.shape, int)
    for i, (_, d0, _) in enumerate(LAYERS[:-1]):
        layer[depth >= d0] = i
    layer[core] = len(LAYERS) - 1
    layers = []
    for i, (lid, d0, share) in enumerate(LAYERS):
        vol = float(fill[layer == i].sum())
        layers.append({"id": lid, "min_depth": d0 if d0 is not None else -1.0, "share": share,
                       "volume": round(vol, 1), "density": round(TOTAL_ESSENCE * share / vol, 4)})
    # Trozos con superficie al empezar (los demás no se mallan hasta que se excave en ellos).
    c = (n - 1) // CHUNK
    surface = []
    for cz in range(c[2]):
        for cy in range(c[1]):
            for cx in range(c[0]):
                blk = sdf[cz * CHUNK:cz * CHUNK + CHUNK + 1, cy * CHUNK:cy * CHUNK + CHUNK + 1,
                          cx * CHUNK:cx * CHUNK + CHUNK + 1]
                if blk.min() < 0.0 < blk.max():
                    surface.append(int(cx + c[0] * (cy + c[1] * cz)))
    top = float(p[..., 1][sdf < 0].max())
    print(f"rejilla {n.tolist()} ({int(np.prod(n)):,} puntos, celda {H} m), trozos {c.tolist()}, "
          f"con superficie {len(surface)}; altura {top:.1f} m; geodas {len(geodes)}")
    for l in layers:
        print(f"  {l['id']:15s} vol {l['volume']:9.0f} m3  esencia/m3 {l['density']:8.2f}")
    if args.info:
        return
    # Lejos de la superficie, fuera, el valor exacto no importa: se recorta (comprime mucho mejor).
    sdf_out = np.minimum(sdf, OUTSIDE_CLAMP)
    sdf_b = gzip.compress(sdf_out.astype("<f2").tobytes(), 9)
    depth_b = gzip.compress(np.maximum(depth, 0.0).astype("<f2").tobytes(), 9)
    header = {
        "size": n.tolist(), "cell": H, "origin": LO.tolist(), "chunk": CHUNK,
        "core_center": CORE_CENTER.tolist(), "core_radius": CORE_RADIUS, "top": round(top, 2),
        "layers": layers, "geodes": geodes, "surface_chunks": surface,
        "sdf_bytes": len(sdf_b), "depth_bytes": len(depth_b),
    }
    OUT.parent.mkdir(parents=True, exist_ok=True)
    with OUT.open("wb") as f:
        f.write(json.dumps(header, separators=(",", ":")).encode() + b"\n")
        f.write(sdf_b)
        f.write(depth_b)
    print(f"escrito {OUT.relative_to(ROOT)} ({OUT.stat().st_size / 1e6:.2f} MB)")


if __name__ == "__main__":
    main()
