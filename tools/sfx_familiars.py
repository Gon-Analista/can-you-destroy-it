#!/usr/bin/env python3
"""Sonidos de los familiares (la Jaula de Familiares, el recolector y el hechicero).

Uso:
    python3 tools/sfx_familiars.py            # escribe en game/audio/sfx
    python3 tools/sfx_familiars.py --out DIR

- sfx_familiar_hoot_01/02: el "hu-hu" de un buhito mágico: dos sílabas sopladas que caen un poco,
  con una campanita de cristal encima. Afinado en La (pentatónica del juego).
- sfx_familiar_chirp_01..03: pío-píos cortos que suben (al recoger o al soltar fragmentos).
- sfx_familiar_flap_01/02: dos o tres aleteos suaves (ruido grave filtrado que respira).
- sfx_familiar_grab_01: coge un fragmento con las garras: "pip" y un tic de cristal.
- sfx_familiar_cast_01/02: el hechicero lanza su chispita: zumbido corto que sube y destello.
- sfx_familiar_summon_01: llega el primer familiar: arpegio de La mayor que sube, revoloteo de
  alas y un "hu-hu" al final.
Deterministas: semillas fijas.
"""
import argparse
from pathlib import Path

import numpy as np

from sfx_synth import SR, bandpass, bell, fade, lowpass, normalize, note, reverb, t_axis, write


def _syllable(t: np.ndarray, f0: float, dur: float, rng: np.random.Generator, bend: float) -> np.ndarray:
    """Una sílaba de búho: seno con un poco de armónico, soplo y caída de tono."""
    n = len(t)
    env = np.clip(t / 0.03, 0, 1) * np.exp(-np.clip(t - dur * 0.4, 0, None) / (dur * 0.35))
    env *= t < dur * 1.6
    f = f0 * (1.0 + bend * np.exp(-t / (dur * 0.5)) - bend * 0.6)
    ph = 2 * np.pi * np.cumsum(f) / SR
    vib = 1.0 + 0.04 * np.sin(2 * np.pi * 6.0 * t)
    tone = (np.sin(ph) + 0.18 * np.sin(2 * ph) + 0.05 * np.sin(3 * ph)) * vib
    breath = bandpass(rng.standard_normal(n), f0 * 0.8, f0 * 3.0, 2) * 0.25
    return (tone + breath) * env


def hoot(seed: int, base: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    t = t_axis(1.1)
    x = np.zeros_like(t)
    f0 = note(base) / 2.0
    for i, (off, d, k) in enumerate(((0.0, 0.16, 1.0), (0.24, 0.26, 0.85))):
        s0 = int(off * SR)
        tt = t[: len(t) - s0]
        x[s0:] += _syllable(tt, f0 * (1.0 if i == 0 else 0.94), d, rng, 0.08) * k
    tt = t[: len(t) - int(0.05 * SR)]
    x[int(0.05 * SR):] += bell(tt, note(base + 12), [1.0, 2.76], [1.0, 0.25], [0.3, 0.1], rng) * 0.08
    return normalize(fade(reverb(lowpass(x, 5000, 2), rng, 0.6, 0.22), 0.002, 0.12), -5)


def chirp(seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    t = t_axis(0.5)
    x = np.zeros_like(t)
    count = int(rng.integers(2, 4))
    for k in range(count):
        s0 = int((k * rng.uniform(0.07, 0.1)) * SR)
        n = int(rng.uniform(0.045, 0.07) * SR)
        tt = np.arange(n) / SR
        lo = rng.uniform(2400, 3000)
        f = lo + rng.uniform(1200, 1900) * (tt / tt[-1]) ** 0.7
        x[s0:s0 + n] += np.sin(2 * np.pi * np.cumsum(f) / SR) * np.hanning(n) * (0.9 - k * 0.15)
    x += bell(t, note(int(rng.choice([12, 16, 19]))), [1.0, 2.0], [1.0, 0.2], [0.12, 0.05], rng) * 0.12
    return normalize(fade(reverb(x, rng, 0.4, 0.2), 0.001, 0.05), -7)


def flap(seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    t = t_axis(0.55)
    x = np.zeros_like(t)
    beats = int(rng.integers(2, 4))
    for k in range(beats):
        s0 = int(k * 0.13 * SR)
        n = int(0.11 * SR)
        tt = np.arange(n) / SR
        env = np.sin(np.pi * tt / tt[-1]) ** 2 * np.exp(-tt / 0.06)
        whoosh = bandpass(rng.standard_normal(n), 180, 1400, 2) * env
        x[s0:s0 + n] += whoosh * (1.0 - k * 0.2)
    return normalize(fade(x, 0.002, 0.05), -9)


def grab(seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    t = t_axis(0.4)
    n = int(0.06 * SR)
    tt = np.arange(n) / SR
    x = np.zeros_like(t)
    f = 2200 + 1600 * tt / tt[-1]
    x[:n] += np.sin(2 * np.pi * np.cumsum(f) / SR) * np.hanning(n) * 0.6
    s0 = int(0.04 * SR)
    x[s0:] += bell(t[: len(t) - s0], note(19), [1.0, 2.32, 4.25], [1.0, 0.5, 0.25],
                   [0.12, 0.06, 0.03], rng) * 0.5
    return normalize(fade(reverb(x, rng, 0.35, 0.15), 0.001, 0.05), -6)


def cast(seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    t = t_axis(0.6)
    env = np.clip(t / 0.01, 0, 1) * np.exp(-t / 0.12)
    f = 500 + 1500 * (1 - np.exp(-t / 0.06))
    zap = np.sin(2 * np.pi * np.cumsum(f) / SR) * env * 0.5
    fizz = bandpass(rng.standard_normal(len(t)), 3000, 9000, 2) * np.exp(-t / 0.08) * 0.35
    x = zap + fizz
    for k, n_ in enumerate((7, 12)):
        s0 = int((0.03 + k * 0.05) * SR)
        x[s0:] += bell(t[: len(t) - s0], note(n_), [1.0, 2.0, 3.0], [1.0, 0.3, 0.1],
                       [0.15, 0.08, 0.04], rng) * 0.3
    return normalize(fade(reverb(x, rng, 0.5, 0.2), 0.001, 0.08), -5)


def summon(seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    t = t_axis(2.6)
    x = np.zeros_like(t)
    for i, n_ in enumerate((-12, -8, -5, 0, 4, 7, 12)):
        s0 = int(i * 0.075 * SR)
        x[s0:] += bell(t[: len(t) - s0], note(n_), [1.0, 2.0, 3.01], [1.0, 0.3, 0.1],
                       [0.9, 0.4, 0.2], rng, 0.002) * 0.35 * (0.92 ** i)
    x += bandpass(rng.standard_normal(len(t)), 6000, 14000) * np.exp(-t / 0.6) * 0.04
    # Revoloteo de alas que llega.
    for k in range(5):
        s0 = int((0.45 + k * 0.11) * SR)
        n = int(0.1 * SR)
        tt = np.arange(n) / SR
        env = np.sin(np.pi * tt / tt[-1]) ** 2
        x[s0:s0 + n] += bandpass(rng.standard_normal(n), 200, 1500, 2) * env * 0.35
    h = hoot(seed + 7, 0)
    s0 = int(1.25 * SR)
    m = min(len(h), len(x) - s0)
    x[s0:s0 + m] += h[:m] * 0.55
    return normalize(fade(reverb(x, rng, 1.1, 0.28), 0.002, 0.3), -3)


def main() -> None:
    ap = argparse.ArgumentParser()
    root = Path(__file__).resolve().parent.parent
    ap.add_argument("--out", default=str(root / "game" / "audio" / "sfx"))
    out = Path(ap.parse_args().out)
    write(out, "sfx_familiar_hoot_01", hoot(1301, 0))
    write(out, "sfx_familiar_hoot_02", hoot(1302, -3))
    for i in range(3):
        write(out, f"sfx_familiar_chirp_{i + 1:02d}", chirp(1310 + i))
    for i in range(2):
        write(out, f"sfx_familiar_flap_{i + 1:02d}", flap(1320 + i))
        write(out, f"sfx_familiar_cast_{i + 1:02d}", cast(1330 + i))
    write(out, "sfx_familiar_grab_01", grab(1340))
    write(out, "sfx_familiar_summon_01", summon(1350))


if __name__ == "__main__":
    main()
