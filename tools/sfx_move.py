#!/usr/bin/env python3
"""Sonidos de las mejoras de movimiento: doble salto y levitación.

Uso:
    python3 tools/sfx_move.py            # escribe en game/audio/sfx
    python3 tools/sfx_move.py --out DIR

- sfx_double_jump_01: un "fuuum" de aire hacia arriba con un destello de dos notas que suben (La, Mi).
- amb_levitate_loop: en bucle mientras levitas: soplo de aire mágico (ruido filtrado que respira) y un
  acorde suave de La con trémolo, como un motor encantado. Se le sube el tono con la carga.
- sfx_levitate_empty_01: se acaba la carga: tres "pff" que se apagan, cada uno más grave.
Deterministas: semillas fijas.
"""
import argparse
from pathlib import Path

import numpy as np

from sfx_synth import SR, bandpass, bell, fade, loopable, normalize, note, reverb, t_axis, write


def double_jump(seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    t = t_axis(0.8)
    env = np.exp(-t / 0.18) * np.clip(t / 0.02, 0, 1)
    # Barrido de aire hacia arriba: ruido con banda que sube.
    noise = rng.standard_normal(len(t))
    lo = bandpass(noise, 300, 1200, 2)
    hi = bandpass(noise, 1500, 5000, 2)
    sweep = np.clip(t / 0.3, 0, 1)
    x = (lo * (1 - sweep) + hi * sweep) * env * 0.8
    for i, n_ in enumerate((-12, -5)):
        s0 = int((0.03 + i * 0.07) * SR)
        tt = t[: len(t) - s0]
        x[s0:] += bell(tt, note(n_), [1.0, 2.76, 5.4], [1.0, 0.3, 0.12], [0.35, 0.15, 0.06], rng) * 0.3
    return normalize(fade(reverb(x, rng, 0.5, 0.2), 0.002, 0.1), -4)


def levitate_loop(seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    dur = 4.0
    t = t_axis(dur)
    breath = 0.75 + 0.25 * np.sin(2 * np.pi * 1.5 * t)
    x = bandpass(rng.standard_normal(len(t)), 500, 2600, 2) * 0.35 * breath
    trem = 0.8 + 0.2 * np.sin(2 * np.pi * 6.0 * t)
    for n_, a in ((-24, 0.25), (-17, 0.18), (-12, 0.14), (-8, 0.08)):
        f = note(n_)
        x += (np.sin(2 * np.pi * f * t) + 0.25 * np.sin(2 * np.pi * f * 1.003 * t)) * a * trem
    # Destellos sueltos (polvo de estrellas).
    for _ in range(10):
        s0 = rng.integers(0, len(t) - SR // 2)
        tt = t[: SR // 2]
        x[s0:s0 + len(tt)] += bell(tt, note(rng.choice([7, 12, 16, 19])), [1.0, 2.76], [1.0, 0.3],
                                   [0.15, 0.06], rng) * 0.05
    return normalize(loopable(x, 0.8), -8)


def levitate_empty(seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    t = t_axis(0.9)
    x = np.zeros_like(t)
    for i in range(3):
        s0 = int(i * 0.18 * SR)
        n = int(0.14 * SR)
        tt = np.arange(n) / SR
        puff = bandpass(rng.standard_normal(n), 300 - i * 60, 1600 - i * 300, 2) * np.exp(-tt / 0.04)
        x[s0:s0 + n] += puff * (1.0 - i * 0.3)
    return normalize(fade(x, 0.002, 0.1), -6)


def main() -> None:
    ap = argparse.ArgumentParser()
    root = Path(__file__).resolve().parent.parent
    ap.add_argument("--out", default=str(root / "game" / "audio" / "sfx"))
    out = Path(ap.parse_args().out)
    write(out, "sfx_double_jump_01", double_jump(1101))
    write(out, "amb_levitate_loop", levitate_loop(1102))
    write(out, "sfx_levitate_empty_01", levitate_empty(1103))


if __name__ == "__main__":
    main()
