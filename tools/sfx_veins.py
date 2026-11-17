#!/usr/bin/env python3
"""Sonidos de las Venas Resonantes y de la rama del Pilón.

Uso:
    python3 tools/sfx_veins.py            # escribe en game/audio/sfx
    python3 tools/sfx_veins.py --out DIR

- sfx_vein_chime_01..05: golpe en la vena con su elemento débil. Cada vena canta su nota de la
  pentatónica de La (Chispa La, Escarcha Si, Rayo Do#, Tierra Mi, Arcano Fa#): campana de cristal
  con quinta y octava, un barrido que "resuena" y destellos agudos.
- sfx_pylon_charge_01: el Pilón carga su rayo (zumbido que sube con crepitar).
- sfx_pylon_bolt_01/02: el rayo del Pilón: latigazo eléctrico y trueno corto.
- sfx_pylon_ascend_01: hito del Pilón: crecida grave, coro y arpegio de campanas que sube.
Deterministas: semillas fijas.
"""
import argparse
from pathlib import Path

import numpy as np

from sfx_synth import SR, bandpass, bell, fade, lowpass, normalize, note, reverb, t_axis, write

# Semitonos respecto a A5 de la nota de cada vena (pentatónica de La, como el "tink").
VEIN_NOTES = [-12, -10, -8, -5, -3]


def crackle(rng, n, density=0.004, lo=2000, hi=9000):
    x = np.zeros(n)
    hits = rng.random(n) < density
    x[hits] = rng.uniform(-1, 1, hits.sum())
    return bandpass(x, lo, hi, 2) * 4.0


def vein_chime(n0: int, seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    t = t_axis(1.9)
    glass = [1.0, 2.0, 3.01, 4.2, 5.4]
    amps = [1.0, 0.35, 0.18, 0.1, 0.05]
    decays = [1.1, 0.7, 0.45, 0.3, 0.2]
    x = np.zeros_like(t)
    for k, (dn, a) in enumerate([(0, 1.0), (7, 0.55), (12, 0.45)]):
        start = int(k * 0.03 * SR)
        tt = t[: len(t) - start]
        x[start:] += bell(tt, note(n0 + dn), glass, amps, decays, rng, 0.002) * a
    # Barrido resonante: un filtro que sube por el ruido (la vena "vibra").
    sweep = np.zeros_like(t)
    noise = rng.standard_normal(len(t))
    for i, lo in enumerate(np.linspace(600, 5000, 12)):
        s0 = int(i * 0.04 * SR)
        n = int(0.12 * SR)
        if s0 + n < len(t):
            sweep[s0:s0 + n] += bandpass(noise[s0:s0 + n], lo, lo * 1.4, 2) * np.hanning(n)
    x += sweep * 0.25
    # Destellos agudos que caen.
    for _ in range(7):
        s0 = int(rng.uniform(0.02, 0.5) * SR)
        tt = t[: len(t) - s0]
        x[s0:] += np.sin(2 * np.pi * note(n0 + 24 + rng.choice([0, 7, 12])) * tt) * np.exp(-tt / 0.08) * 0.12
    x *= 1 - np.exp(-t / 0.004)
    return normalize(fade(reverb(x, rng, 1.4, 0.32), 0.001, 0.2), -2)


def pylon_charge(seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    t = t_axis(0.9)
    f = 90 + 260 * (t / t[-1]) ** 2
    hum = np.sin(2 * np.pi * np.cumsum(f) / SR) + 0.4 * np.sin(2 * np.pi * np.cumsum(f * 2.01) / SR)
    hum *= np.clip(t / 0.7, 0, 1) ** 1.5
    x = lowpass(hum, 1600) * 0.6 + crackle(rng, len(t), 0.004 + 0.03 * t / t[-1]) * 0.35
    return normalize(fade(x, 0.02, 0.03), -4)


def pylon_bolt(seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    t = t_axis(2.2)
    crack = crackle(rng, len(t), 0.09, 1500, 11000) * np.exp(-t / 0.06) * 1.3
    snap = lowpass(rng.standard_normal(len(t)), 900) * np.exp(-t / 0.03) * 1.5
    roll_env = np.exp(-np.maximum(t - 0.08, 0) / 0.7) * np.clip((t - 0.05) / 0.1, 0, 1)
    roll = lowpass(rng.standard_normal(len(t)), 140) * roll_env * 2.4
    rumble = lowpass(np.cumsum(rng.standard_normal(len(t))) * 0.01, 80) * roll_env * 3.0
    zing = np.sin(2 * np.pi * np.cumsum(1800 - 1200 * np.clip(t / 0.3, 0, 1)) / SR) * np.exp(-t / 0.12) * 0.2
    x = crack + snap + roll + rumble + zing
    return normalize(fade(reverb(x, rng, 1.0, 0.25, 3000), 0.001, 0.2), -1)


def pylon_ascend(seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    dur = 4.2
    t = t_axis(dur)
    swell = lowpass(rng.standard_normal(len(t)), 400) * np.clip(t / 1.2, 0, 1) * np.exp(-np.maximum(t - 1.2, 0) / 0.8)
    choir = np.zeros_like(t)
    for n, a in [(-24, 1.0), (-17, 0.6), (-12, 0.7), (-8, 0.4), (-5, 0.35)]:
        f = note(n)
        vib = 1 + 0.004 * np.sin(2 * np.pi * 5.2 * t + rng.uniform(0, 6))
        choir += a * (np.sin(2 * np.pi * np.cumsum(f * vib) / SR) + 0.3 * np.sin(2 * np.pi * np.cumsum(2 * f * vib) / SR))
    choir *= np.clip(t / 0.9, 0, 1) * np.exp(-np.maximum(t - 1.6, 0) / 1.2)
    bells = np.zeros_like(t)
    for i, n in enumerate([0, 2, 4, 7, 9, 12, 16, 19]):
        start = int((0.55 + i * 0.11) * SR)
        tt = t[: len(t) - start]
        bells[start:] += bell(tt, note(n), [1.0, 2.0, 3.01, 4.2], [1.0, 0.3, 0.12, 0.06],
                              [1.2, 0.6, 0.35, 0.2], rng, 0.002) * (0.9 ** i)
    shimmer = bandpass(rng.standard_normal(len(t)), 7000, 15000) * np.clip((t - 0.5) / 0.5, 0, 1) * np.exp(-np.maximum(t - 1.5, 0) / 0.8) * 0.15
    x = swell * 0.8 + bandpass(choir, 100, 3000, 2) * 0.25 + bells * 0.5 + shimmer
    return normalize(fade(reverb(x, rng, 1.8, 0.35), 0.01, 0.4), -1)


def main() -> None:
    ap = argparse.ArgumentParser()
    root = Path(__file__).resolve().parent.parent
    ap.add_argument("--out", default=str(root / "game" / "audio" / "sfx"))
    out = Path(ap.parse_args().out)
    for i, n in enumerate(VEIN_NOTES):
        write(out, f"sfx_vein_chime_{i + 1:02d}", vein_chime(n, 1401 + i))
    write(out, "sfx_pylon_charge_01", pylon_charge(1411))
    write(out, "sfx_pylon_bolt_01", pylon_bolt(1421))
    write(out, "sfx_pylon_bolt_02", pylon_bolt(1422))
    write(out, "sfx_pylon_ascend_01", pylon_ascend(1431))


if __name__ == "__main__":
    main()
