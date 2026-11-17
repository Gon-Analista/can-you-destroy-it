#!/usr/bin/env python3
"""Sonidos de la casucha del aprendiz y de la revelación del cristal.

Uso:
    python3 tools/sfx_hut.py            # escribe en game/audio/sfx
    python3 tools/sfx_hut.py --out DIR

- sfx_door_open_01: pestillo de hierro y una puerta de madera vieja que cruje al abrirse (rozamiento
  "stick-slip": pulsos cuyo ritmo sube y baja, filtrados como madera).
- sfx_wind_gust_01: ráfaga de aire que entra al abrir.
- sfx_reveal_01: la revelación del Cristal Madre: acorde de La mayor que crece desde lejos, campanas de
  cristal que caen en cascada y un brillo agudo; deja claro que eso de ahí fuera es enorme.
- amb_hut_loop: dentro de la casucha: chisporroteo suave de la chimenea y un hervor lejano del caldero.
Deterministas: semillas fijas.
"""
import argparse
from pathlib import Path

import numpy as np

from sfx_synth import (SR, bandpass, bell, fade, highpass, loopable, lowpass, normalize, note,
                       reverb, t_axis, write)


def door_open(seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    t = t_axis(1.9)
    x = np.zeros_like(t)
    # Pestillo: dos clics metálicos.
    for t0, f in ((0.02, 2600), (0.11, 1900)):
        s0 = int(t0 * SR)
        tt = t[: int(0.12 * SR)]
        x[s0:s0 + len(tt)] += bell(tt, f, [1.0, 2.3, 3.9], [1.0, 0.5, 0.3], [0.03, 0.02, 0.01], rng) * 0.6
    # Crujido: pulsos de rozamiento con frecuencia que sube y baja (bisagra que se queja).
    start = 0.28
    dur = 1.45
    n = int(dur * SR)
    tt = np.arange(n) / SR
    rate = 38 + 26 * np.sin(np.pi * tt / dur) + 9 * np.sin(2 * np.pi * 2.3 * tt)
    phase = np.cumsum(rate / SR)
    pulses = (np.diff(np.floor(phase), prepend=0) > 0).astype(float)
    pulses *= rng.uniform(0.6, 1.0, n)
    body = np.zeros(n)
    k = np.exp(-np.arange(int(0.006 * SR)) / (0.0012 * SR))
    body = np.convolve(pulses, k)[:n]
    creak = bandpass(body, 450, 1700, 2) * 1.2 + bandpass(body, 2200, 3400, 2) * 0.35
    creak *= np.sin(np.pi * np.clip(tt / dur, 0, 1)) ** 0.6
    s0 = int(start * SR)
    x[s0:s0 + n] += creak
    # Golpe sordo de la puerta contra la pared al final.
    s1 = int((start + dur - 0.05) * SR)
    th = t[: len(t) - s1]
    x[s1:] += lowpass(rng.standard_normal(len(th)), 220) * np.exp(-th / 0.06) * 1.4
    return normalize(fade(reverb(x, rng, 0.35, 0.12), 0.001, 0.08), -3)


def wind_gust(seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    t = t_axis(2.6)
    env = np.sin(np.pi * np.clip(t / 2.6, 0, 1)) ** 1.5
    x = bandpass(rng.standard_normal(len(t)), 250, 1400, 2) * env
    x += bandpass(rng.standard_normal(len(t)), 1800, 4200, 2) * env ** 3 * 0.25
    return normalize(fade(x, 0.05, 0.4), -6)


def reveal(seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    dur = 6.5
    t = t_axis(dur)
    x = np.zeros_like(t)
    # Acorde que crece (La mayor abierto: La, Mi, La, Do#, Mi), cuerdas suaves con vibrato.
    swell = np.clip(t / 2.2, 0, 1) ** 2 * np.exp(-np.clip(t - 3.2, 0, None) / 1.6)
    for n_, a in ((-24, 0.8), (-17, 0.6), (-12, 0.6), (-8, 0.45), (-5, 0.4), (0, 0.25)):
        f = note(n_)
        vib = 1.0 + 0.004 * np.sin(2 * np.pi * 5.2 * t + rng.uniform(0, 6))
        ph = 2 * np.pi * np.cumsum(f * vib) / SR
        x += (np.sin(ph) + 0.3 * np.sin(2 * ph) + 0.12 * np.sin(3 * ph)) * a * swell
    # Cascada de campanas de cristal (pentatónica de La, de agudo a grave).
    casc = [24, 21, 19, 16, 14, 12, 9, 7, 4, 2, 0]
    for i, n_ in enumerate(casc):
        s0 = int((1.6 + i * 0.11) * SR)
        tt = t[: len(t) - s0]
        x[s0:] += bell(tt, note(n_), [1.0, 2.76, 5.4], [1.0, 0.35, 0.15], [1.4, 0.6, 0.25], rng) * 0.22
    # Brillo agudo que se abre.
    shim = highpass(rng.standard_normal(len(t)), 6000) * np.clip((t - 1.5) / 1.0, 0, 1) * np.exp(
        -np.clip(t - 2.5, 0, None) / 1.2) * 0.08
    x += shim
    x = reverb(x, rng, 2.5, 0.4)
    return normalize(fade(x, 0.02, 1.2), -2)


def hut_loop(seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    dur = 12.0
    t = t_axis(dur)
    x = lowpass(rng.standard_normal(len(t)), 300) * 0.05  # fuego de fondo
    # Chisporroteos: chasquidos cortos al azar.
    for _ in range(140):
        s0 = rng.integers(0, len(t) - 2000)
        n = int(rng.uniform(0.002, 0.012) * SR)
        x[s0:s0 + n] += bandpass(rng.standard_normal(n), 1200, 6000, 2) * np.hanning(n) * rng.uniform(0.1, 0.5)
    # Burbujas del caldero.
    for _ in range(40):
        s0 = rng.integers(0, len(t) - 6000)
        tt = t[: int(0.09 * SR)]
        f = rng.uniform(220, 420)
        x[s0:s0 + len(tt)] += np.sin(2 * np.pi * f * (1 + tt * 6) * tt) * np.exp(-tt / 0.025) * 0.12
    return normalize(loopable(x, 1.0), -10)


def main() -> None:
    ap = argparse.ArgumentParser()
    root = Path(__file__).resolve().parent.parent
    ap.add_argument("--out", default=str(root / "game" / "audio" / "sfx"))
    out = Path(ap.parse_args().out)
    write(out, "sfx_door_open_01", door_open(1001))
    write(out, "sfx_wind_gust_01", wind_gust(1002))
    write(out, "sfx_reveal_01", reveal(1003))
    write(out, "amb_hut_loop", hut_loop(1004))


if __name__ == "__main__":
    main()
