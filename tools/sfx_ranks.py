#!/usr/bin/env python3
"""Sonidos de los rangos del mago y del Espejo del Archimago.

Uso:
    python3 tools/sfx_ranks.py            # escribe en game/audio/sfx
    python3 tools/sfx_ranks.py --out DIR

- sfx_rank_up_01..05: subida de rango (Iniciado ... Leyenda). Golpe grave de timbal, coro que
  crece sobre La mayor, fanfarria de metales (sierra filtrada) con un motivo que sube, arpegio de
  campanas y destellos. Cada rango suma voces, una nota más al motivo y dura un poco más.
- sfx_mirror_open_01 / sfx_mirror_close_01: el Espejo del Archimago se enciende (cristal que
  vibra y sube) o se apaga (lo mismo, hacia abajo y más corto).
- amb_mirror_hum_loop: zumbido suave del espejo (frecuencias con ciclos enteros: empalma solo).
Todo en La mayor / pentatónica de La, como la música y el "tink". Deterministas: semillas fijas.
"""
import argparse
from pathlib import Path

import numpy as np

from sfx_synth import SR, bandpass, bell, fade, lowpass, normalize, note, reverb, t_axis, write

# Motivo de la fanfarria (semitonos sobre A4 = note(-12)): La, Mi, La, Do#, Mi, La.
FANFARE = [0, 7, 12, 16, 19, 24]


def brass(t: np.ndarray, f: float, rng, bright: float = 2500.0) -> np.ndarray:
    """Metal sintetizado: sierra con vibrato que se abre al atacar (filtro que barre)."""
    vib = 1 + 0.003 * np.sin(2 * np.pi * 5.5 * t + rng.uniform(0, 6)) * np.clip(t / 0.3, 0, 1)
    ph = np.cumsum(f * vib) / SR
    saw = 2 * (ph - np.floor(ph + 0.5))
    saw2 = 2 * (ph * 1.003 - np.floor(ph * 1.003 + 0.5))
    x = (saw + saw2) * 0.5
    return lowpass(x, bright, 2)


def choir(t: np.ndarray, notes, rng) -> np.ndarray:
    out = np.zeros_like(t)
    for n, a in notes:
        f = note(n)
        for det in (-0.004, 0.0, 0.004):
            vib = 1 + det + 0.005 * np.sin(2 * np.pi * 5.0 * t + rng.uniform(0, 6))
            ph = 2 * np.pi * np.cumsum(f * vib) / SR
            out += a * (np.sin(ph) + 0.35 * np.sin(2 * ph) + 0.12 * np.sin(3 * ph)) / 3
    return bandpass(out, 120, 3500, 2)


def rank_up(rank: int, seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    dur = 3.4 + 0.3 * rank
    t = t_axis(dur)
    x = np.zeros_like(t)
    # Timbal: golpe grave que baja de tono.
    boom_f = 55 * (1 + 0.6 * np.exp(-t / 0.05))
    boom = np.sin(2 * np.pi * np.cumsum(boom_f) / SR) * np.exp(-t / (0.35 + 0.05 * rank))
    boom += lowpass(rng.standard_normal(len(t)), 300) * np.exp(-t / 0.08) * 0.6
    x += boom * 0.9
    # Coro: La mayor que crece; cada rango añade una voz más aguda.
    voices = [(-36, 1.0), (-29, 0.7), (-24, 0.8), (-20, 0.55), (-17, 0.5), (-12, 0.4)][: 2 + rank]
    ch = choir(t, voices, rng)
    env = np.clip((t - 0.05) / 0.6, 0, 1) * np.exp(-np.maximum(t - (1.4 + 0.2 * rank), 0) / 0.9)
    x += ch * env * 0.55
    # Fanfarria: el motivo sube, una nota más por rango; la última se sostiene.
    motif = FANFARE[: min(len(FANFARE), 2 + rank)]
    gap = 0.13
    for i, n in enumerate(motif):
        start = int((0.12 + i * gap) * SR)
        last = i == len(motif) - 1
        length = (1.2 + 0.2 * rank) if last else gap * 1.3
        nn = int(length * SR)
        if start + nn > len(t):
            nn = len(t) - start
        tt = t[:nn]
        e = np.clip(tt / 0.02, 0, 1) * (np.exp(-np.maximum(tt - length * 0.6, 0) / 0.25) if last else
                                        np.exp(-tt / 0.18))
        for octv, a in ((-12, 1.0), (0, 0.45)):
            x[start:start + nn] += brass(tt, note(n + octv), rng, 1800 + 300 * rank) * e * a * 0.32
    # Campanas que suben al final del motivo.
    b0 = 0.12 + len(motif) * gap
    for i, n in enumerate([0, 4, 7, 12, 16, 19, 24][: 3 + rank]):
        start = int((b0 + i * 0.08) * SR)
        tt = t[: len(t) - start]
        x[start:] += bell(tt, note(n), [1.0, 2.0, 3.01, 4.2], [1.0, 0.3, 0.12, 0.06],
                          [1.3, 0.6, 0.35, 0.2], rng, 0.002) * 0.35 * (0.92 ** i)
    # Destellos agudos.
    sh_env = np.clip((t - b0) / 0.3, 0, 1) * np.exp(-np.maximum(t - b0 - 0.6, 0) / 0.7)
    x += bandpass(rng.standard_normal(len(t)), 7000, 15000) * sh_env * (0.08 + 0.02 * rank)
    return normalize(fade(reverb(x, rng, 2.2, 0.32), 0.002, 0.5), -1)


def mirror(up: bool, seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    dur = 1.6 if up else 0.9
    t = t_axis(dur)
    # Cristal que vibra: glissando de armónicos.
    f0 = note(-12)
    sweep = np.linspace(0.0, 1.0, len(t)) if up else np.linspace(1.0, 0.0, len(t))
    x = np.zeros_like(t)
    for k, a in [(1, 1.0), (1.5, 0.5), (2, 0.6), (3, 0.3), (4, 0.2)]:
        f = f0 * k * (1 + 0.5 * sweep)
        x += a * np.sin(2 * np.pi * np.cumsum(f) / SR) * (0.6 + 0.4 * np.sin(2 * np.pi * 7 * t))
    x *= np.clip(t / (0.4 if up else 0.05), 0, 1) * np.exp(-t / (0.9 if up else 0.35))
    # Campanita (Mi, Do#) y brillo.
    for i, n in enumerate([7, 16] if up else [16, 7]):
        start = int((0.25 + i * 0.12 if up else 0.02 + i * 0.1) * SR)
        tt = t[: len(t) - start]
        x[start:] += bell(tt, note(n), [1.0, 2.0, 3.01], [1.0, 0.3, 0.1], [0.9, 0.4, 0.2], rng) * 0.5
    x += bandpass(rng.standard_normal(len(t)), 6000, 14000) * np.exp(-t / 0.5) * 0.08
    return normalize(fade(reverb(x * 0.6, rng, 1.4, 0.35), 0.003, 0.2), -4)


def mirror_hum(seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    dur = 6.0
    t = t_axis(dur)
    # Ciclos enteros en 6 s: La y Mi con un batido lento.
    freqs = [220.0, 330.0, 440.0 + 1 / 6, 660.0 - 1 / 6, 1320.0 + 1 / 3]
    amps = [0.6, 0.5, 0.35, 0.2, 0.06]
    x = np.zeros_like(t)
    for f, a in zip(freqs, amps):
        x += a * np.sin(2 * np.pi * f * t + rng.uniform(0, 2 * np.pi))
    lfo = 0.75 + 0.25 * np.sin(2 * np.pi * t / 3.0)
    return normalize(x * lfo, -12)


def main() -> None:
    ap = argparse.ArgumentParser()
    root = Path(__file__).resolve().parent.parent
    ap.add_argument("--out", default=str(root / "game" / "audio" / "sfx"))
    out = Path(ap.parse_args().out)
    for r in range(1, 6):
        write(out, f"sfx_rank_up_{r:02d}", rank_up(r, 1501 + r))
    write(out, "sfx_mirror_open_01", mirror(True, 1511))
    write(out, "sfx_mirror_close_01", mirror(False, 1512))
    write(out, "amb_mirror_hum_loop", mirror_hum(1513))


if __name__ == "__main__":
    main()
