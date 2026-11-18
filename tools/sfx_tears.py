#!/usr/bin/env python3
"""Sonidos de las Lágrimas del Núcleo (GDD 6.1: el fragmento especial del Corazón Cristalino).

Uso:
    python3 tools/sfx_tears.py            # escribe en game/audio/sfx
    python3 tools/sfx_tears.py --out DIR

- sfx_tear_drop_01: brota una Lágrima: latido grave doble ("lub-dub"), campana de cristal oscura
  en La menor-mayor (La, Do#, Mi) que se abre y un velo agudo que cae.
- sfx_tear_beat_01/02: el latido de la Lágrima mientras flota (corto, grave, sin tono que choque).
- sfx_tear_pickup_01: recogerla: arpegio de campanas que sube (La, Do#, Mi, La, Do#), coro suave y
  un brillo largo. Tiene que sentirse como un premio, distinto del "pling" de los fragmentos.
- sfx_tear_spend_01: inscribir con Lágrimas en el Grimorio: un acorde grave que se ilumina.
Deterministas: semillas fijas. Todo en La mayor (como el "tink" del cristal y la música).
"""
import argparse
from pathlib import Path

import numpy as np

from sfx_synth import SR, bandpass, bell, fade, lowpass, normalize, note, reverb, t_axis, write

GLASS = [1.0, 2.0, 3.01, 4.2, 5.4]
GLASS_AMPS = [1.0, 0.4, 0.2, 0.1, 0.05]


def thump(t: np.ndarray, f0: float, decay: float) -> np.ndarray:
    """Golpe grave de latido: seno que baja de tono con un poco de cuerpo."""
    f = f0 * (1.0 + 1.2 * np.exp(-t / 0.02))
    x = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / decay)
    return x * (1 - np.exp(-t / 0.002))


def heartbeat(t: np.ndarray, rng, at: float = 0.0, gain: float = 1.0) -> np.ndarray:
    out = np.zeros_like(t)
    for k, (dt, a, f) in enumerate([(0.0, 1.0, 58.0), (0.19, 0.7, 52.0)]):
        s0 = int((at + dt) * SR)
        if s0 >= len(t):
            continue
        tt = t[: len(t) - s0]
        body = thump(tt, f * rng.uniform(0.98, 1.02), 0.11)
        knock = lowpass(rng.standard_normal(len(tt)), 260, 2) * np.exp(-tt / 0.03) * 0.6
        out[s0:] += (body + knock) * a * gain
    return out


def tear_drop(seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    t = t_axis(2.6)
    x = heartbeat(t, rng, 0.0, 1.0) * 0.9
    # Campana oscura: La3 con su tercera y su quinta, entrando una tras otra.
    for k, (n, a) in enumerate([(-24, 1.0), (-20, 0.6), (-17, 0.5), (-12, 0.35)]):
        s0 = int((0.05 + k * 0.07) * SR)
        tt = t[: len(t) - s0]
        x[s0:] += bell(tt, note(n), GLASS, GLASS_AMPS, [1.6, 1.0, 0.6, 0.35, 0.2], rng, 0.002) * a * 0.5
    # Velo agudo que cae (la lágrima "resbala").
    s0 = int(0.12 * SR)
    tt = t[: len(t) - s0]
    f = note(19) * (1.0 - 0.35 * np.clip(tt / 0.9, 0, 1))
    x[s0:] += np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-tt / 0.5) * 0.12
    x += bandpass(rng.standard_normal(len(t)), 5000, 12000) * np.exp(-np.maximum(t - 0.1, 0) / 0.4) * (t > 0.1) * 0.05
    return normalize(fade(reverb(x, rng, 1.6, 0.35), 0.001, 0.3), -1.5)


def tear_beat(seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    t = t_axis(0.75)
    x = heartbeat(t, rng, 0.0, 1.0)
    # Un resplandor de cristal muy suave encima (La4), para que no sea sólo un bombo.
    x += bell(t, note(-12), [1.0, 2.0, 3.0], [1.0, 0.3, 0.1], [0.35, 0.2, 0.1], rng, 0.002) * 0.08
    return normalize(fade(reverb(x, rng, 0.8, 0.25), 0.001, 0.15), -4)


def tear_pickup(seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    t = t_axis(3.0)
    x = heartbeat(t, rng, 0.0, 0.7) * 0.6
    bells = np.zeros_like(t)
    for i, n in enumerate([-12, -8, -5, 0, 4, 7, 12]):
        s0 = int((0.04 + i * 0.075) * SR)
        tt = t[: len(t) - s0]
        bells[s0:] += bell(tt, note(n), GLASS, GLASS_AMPS, [1.4, 0.9, 0.5, 0.3, 0.2], rng, 0.002) * (0.92 ** i)
    choir = np.zeros_like(t)
    for n, a in [(-24, 0.8), (-17, 0.6), (-12, 0.5), (-8, 0.4)]:
        f = note(n)
        vib = 1 + 0.004 * np.sin(2 * np.pi * 5.0 * t + rng.uniform(0, 6))
        choir += a * np.sin(2 * np.pi * np.cumsum(f * vib) / SR)
    choir *= np.clip(t / 0.35, 0, 1) * np.exp(-np.maximum(t - 0.8, 0) / 0.9)
    shimmer = bandpass(rng.standard_normal(len(t)), 6000, 14000) * np.clip(t / 0.3, 0, 1) * np.exp(-t / 1.0) * 0.1
    x += bells * 0.55 + bandpass(choir, 90, 2500, 2) * 0.22 + shimmer
    return normalize(fade(reverb(x, rng, 1.8, 0.35), 0.001, 0.5), -1)


def tear_spend(seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    t = t_axis(2.2)
    x = np.zeros_like(t)
    for k, (n, a) in enumerate([(-36, 1.0), (-29, 0.7), (-24, 0.6), (-20, 0.45), (-17, 0.4)]):
        f = note(n)
        env = np.clip(t / (0.08 + k * 0.05), 0, 1) * np.exp(-t / 1.1)
        x += np.sin(2 * np.pi * f * t + rng.uniform(0, 6)) * env * a * 0.5
    for i, n in enumerate([0, 4, 7, 12]):
        s0 = int((0.25 + i * 0.09) * SR)
        tt = t[: len(t) - s0]
        x[s0:] += bell(tt, note(n), GLASS, GLASS_AMPS, [1.2, 0.7, 0.4, 0.25, 0.15], rng, 0.002) * 0.3
    return normalize(fade(reverb(x, rng, 1.5, 0.3), 0.002, 0.4), -1.5)


def main() -> None:
    ap = argparse.ArgumentParser()
    root = Path(__file__).resolve().parent.parent
    ap.add_argument("--out", default=str(root / "game" / "audio" / "sfx"))
    out = Path(ap.parse_args().out)
    write(out, "sfx_tear_drop_01", tear_drop(1601))
    write(out, "sfx_tear_beat_01", tear_beat(1611))
    write(out, "sfx_tear_beat_02", tear_beat(1612))
    write(out, "sfx_tear_pickup_01", tear_pickup(1621))
    write(out, "sfx_tear_spend_01", tear_spend(1631))


if __name__ == "__main__":
    main()
