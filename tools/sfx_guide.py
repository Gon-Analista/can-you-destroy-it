#!/usr/bin/env python3
"""Sonidos de la guía de objetivos (el rombo que te dice adónde ir).

Uso:
    python3 tools/sfx_guide.py            # escribe en game/audio/sfx
    python3 tools/sfx_guide.py --out DIR

- sfx_guide_new_01: aparece un objetivo nuevo: dos notas de cristal que suben (Mi, La) con un
  soplo de polvo de estrellas. Muy suave: no debe tapar el "tink" del cristal.
- sfx_guide_arrive_01: llegas al objetivo: un destello corto de tres notas (La, Do#, Mi) que se
  resuelve, más bajo todavía.
Deterministas: semillas fijas. En La mayor, como todo lo demás.
"""
import argparse
from pathlib import Path

import numpy as np

from sfx_synth import SR, bandpass, bell, fade, normalize, note, reverb, t_axis, write

RATIOS = [1.0, 2.0, 3.01, 5.1]
AMPS = [1.0, 0.28, 0.1, 0.04]


def guide_new(seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    t = t_axis(1.1)
    x = np.zeros_like(t)
    for i, (n_, gain) in enumerate(((-5, 0.8), (0, 1.0))):
        s0 = int(i * 0.085 * SR)
        tt = t[: len(t) - s0]
        x[s0:] += bell(tt, note(n_), RATIOS, AMPS, [0.5, 0.28, 0.14, 0.06], rng, 0.002) * gain
    # Polvo de estrellas que sube con las notas.
    dust = bandpass(rng.standard_normal(len(t)), 5500, 12000, 2)
    x += dust * np.clip(t / 0.08, 0, 1) * np.exp(-t / 0.22) * 0.12
    x *= 1 - np.exp(-t / 0.004)
    return normalize(fade(reverb(x, rng, 0.9, 0.3), 0.001, 0.2), -9)


def guide_arrive(seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    t = t_axis(0.9)
    x = np.zeros_like(t)
    for i, n_ in enumerate((12, 16, 19)):
        s0 = int(i * 0.05 * SR)
        tt = t[: len(t) - s0]
        x[s0:] += bell(tt, note(n_), RATIOS, AMPS, [0.3, 0.16, 0.08, 0.04], rng, 0.002) * (
            0.9 ** i
        )
    x += bandpass(rng.standard_normal(len(t)), 7000, 14000, 2) * np.exp(-t / 0.12) * 0.08
    x *= 1 - np.exp(-t / 0.003)
    return normalize(fade(reverb(x, rng, 0.7, 0.28), 0.001, 0.15), -12)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", type=Path,
                    default=Path(__file__).resolve().parent.parent / "game" / "audio" / "sfx")
    args = ap.parse_args()
    write(args.out, "sfx_guide_new_01", guide_new(7101))
    write(args.out, "sfx_guide_arrive_01", guide_arrive(7102))
    print("ok:", args.out)


if __name__ == "__main__":
    main()
