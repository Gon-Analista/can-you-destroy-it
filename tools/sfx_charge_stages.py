#!/usr/bin/env python3
"""Sonidos de la carga por etapas de los hechizos combinados (un círculo mágico por etapa).

Uso:
    python3 tools/sfx_charge_stages.py            # escribe en game/audio/sfx
    python3 tools/sfx_charge_stages.py --out DIR

- sfx_charge_stage_01..04: un círculo encaja. "Clac" de sello, un zumbido grave que golpea
  (thrum), una subida rápida y una campana de cristal con su quinta. Cada etapa suena más
  aguda, subiendo por la pentatónica de La (La4, Do#5, Mi5, Fa#5): la última antes de la
  potencia completa es siempre el Fa#, que pide resolver en La.
- sfx_charge_full_01: potencia completa (última etapa). Golpe grave, acorde de La que se abre
  (La5, Mi6, La6, Do#7), soplo que sube y una cola de destellos.
Deterministas: semillas fijas.
"""
import argparse
from pathlib import Path

import numpy as np

from sfx_synth import (SR, bandpass, bell, fade, highpass, lowpass, normalize, note, reverb, t_axis,
                       write)

# Semitonos respecto a A5 de cada etapa (pentatónica de La, como el "tink" del cristal).
STAGE_NOTES = [-12, -8, -5, -3]
GLASS = [1.0, 2.0, 3.01, 4.2, 5.4]
GLASS_AMPS = [1.0, 0.32, 0.16, 0.08, 0.04]


def sweep(t: np.ndarray, f0: float, f1: float, dur: float) -> np.ndarray:
    """Seno que sube de f0 a f1 en `dur` s (curva exponencial) y se apaga."""
    k = np.clip(t / dur, 0, 1)
    f = f0 * (f1 / f0) ** k
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-np.maximum(t - dur, 0) / 0.03)


def snap(t: np.ndarray, rng: np.random.Generator, f: float) -> np.ndarray:
    """El sello que encaja: un chasquido corto con un ping metálico."""
    click = highpass(rng.standard_normal(len(t)), 2500) * np.exp(-t / 0.004)
    ping = np.sin(2 * np.pi * f * 3.0 * t) * np.exp(-t / 0.025)
    return click * 0.5 + ping * 0.25


def stage(n0: int, idx: int, seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    t = t_axis(1.1)
    f = note(n0)
    x = snap(t, rng, f)
    # Thrum: golpe grave que cae un poco, más agudo en cada etapa.
    fs = note(n0 - 24)
    thrum_f = fs * (1.0 + 0.6 * np.exp(-t / 0.03))
    thrum = np.sin(2 * np.pi * np.cumsum(thrum_f) / SR) * np.exp(-t / (0.16 + 0.02 * idx))
    thrum += 0.35 * np.sin(2 * np.pi * np.cumsum(thrum_f * 2.0) / SR) * np.exp(-t / 0.08)
    x += lowpass(thrum, 900) * 0.9
    # Subida rápida hacia la nota (la energía "sube" al círculo).
    x += sweep(t, f * 0.5, f, 0.06) * 0.18
    # Campana de cristal con su quinta, que entra justo después del chasquido.
    s0 = int(0.012 * SR)
    tt = t[: len(t) - s0]
    decays = [0.55, 0.35, 0.22, 0.14, 0.1]
    x[s0:] += bell(tt, f, GLASS, GLASS_AMPS, decays, rng, 0.002) * 0.75
    x[s0:] += bell(tt, note(n0 + 7), GLASS, GLASS_AMPS, [d * 0.7 for d in decays], rng, 0.002) * 0.3
    # Destello de aire.
    x += bandpass(rng.standard_normal(len(t)), 6000, 13000) * np.exp(-t / 0.09) * 0.08
    x *= 1 - np.exp(-t / 0.0015)
    return normalize(fade(reverb(x, rng, 0.9, 0.22), 0.001, 0.15), -2)


def full(seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    t = t_axis(2.4)
    x = snap(t, rng, note(0)) * 1.4
    # Golpe grave: La1 que cae y retumba.
    boom_f = 55.0 * (1.0 + 1.2 * np.exp(-t / 0.04))
    boom = np.sin(2 * np.pi * np.cumsum(boom_f) / SR) * np.exp(-t / 0.45)
    boom += lowpass(rng.standard_normal(len(t)), 160) * np.exp(-t / 0.18) * 1.2
    x += lowpass(boom, 400) * 1.1
    # Acorde de La que se abre de abajo arriba.
    for k, (n, a) in enumerate([(0, 1.0), (7, 0.6), (12, 0.55), (16, 0.35), (19, 0.25)]):
        s0 = int((0.01 + k * 0.022) * SR)
        tt = t[: len(t) - s0]
        x[s0:] += bell(tt, note(n), GLASS, GLASS_AMPS, [1.3, 0.8, 0.5, 0.3, 0.2], rng, 0.002) * a * 0.6
    # Soplo que sube (el poder se completa).
    noise = rng.standard_normal(len(t))
    env = np.clip(t / 0.05, 0, 1) * np.exp(-t / 0.35)
    whoosh = np.zeros_like(t)
    for i, lo in enumerate(np.linspace(900, 7000, 10)):
        s0 = int(i * 0.022 * SR)
        n = int(0.09 * SR)
        whoosh[s0:s0 + n] += bandpass(noise[s0:s0 + n], lo, lo * 1.5, 2) * np.hanning(n)
    x += whoosh * env * 0.5
    # Cola de destellos agudos.
    for _ in range(10):
        s0 = int(rng.uniform(0.05, 0.9) * SR)
        tt = t[: len(t) - s0]
        n = rng.choice([24, 28, 31, 36])
        x[s0:] += np.sin(2 * np.pi * note(n) * tt) * np.exp(-tt / 0.07) * 0.08
    x *= 1 - np.exp(-t / 0.0015)
    return normalize(fade(reverb(x, rng, 1.6, 0.3), 0.001, 0.3), -1)


def main() -> None:
    ap = argparse.ArgumentParser()
    root = Path(__file__).resolve().parent.parent
    ap.add_argument("--out", default=str(root / "game" / "audio" / "sfx"))
    out = Path(ap.parse_args().out)
    for i, n in enumerate(STAGE_NOTES):
        write(out, f"sfx_charge_stage_{i + 1:02d}", stage(n, i, 1601 + i))
    write(out, "sfx_charge_full_01", full(1611))


if __name__ == "__main__":
    main()
