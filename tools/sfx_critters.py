#!/usr/bin/env python3
"""Sonidos de los bichos del valle (critters/): monstruitos graciosos que revientan.

Uso:
    python3 tools/sfx_critters.py            # escribe en game/audio/sfx
    python3 tools/sfx_critters.py --out DIR

- sfx_critter_squeak_01..04: chillido de juguete de goma (susto): tono que sube con armónicos y
  un poco de aire.
- sfx_critter_splorch_01..04: el reventón: golpe grave, chapoteo de ruido filtrado, "blorp" que
  cae y gotitas.
- sfx_critter_boing_01/02: muelle al salir del suelo ("doiiing" con vibrato que se apaga).
- sfx_critter_kazoo_01..03: kazoo de despedida ("wah-wah" que baja, con zumbido).
- sfx_critter_inflate_01/02: se hincha antes de reventar (globo que chirría y sube).
- sfx_critter_boink_01/02: un ojo que rebota en el suelo (goma pequeña).
- sfx_critter_splat_01/02: un trozo de baba que cae al suelo.
- sfx_critter_sneeze_01, sfx_critter_yawn_01, sfx_critter_giggle_01/02, sfx_critter_blep_01:
  sus gestos (estornudo, bostezo, risita, lengua fuera).
- sfx_critter_flatten_01: aplastado como una tortita (silbato que baja y "plaf").
- sfx_critter_confetti_01/02: sin sangre de caricatura: matasuegras, confeti y campanitas.
- sfx_critter_zap_01: el rayo le enseña el esqueleto (zumbido eléctrico que tiembla).
Deterministas: semillas fijas.
"""
import argparse
from pathlib import Path

import numpy as np

from sfx_synth import SR, bandpass, bell, fade, highpass, lowpass, normalize, note, reverb, t_axis, write


def _sweep(t: np.ndarray, f: np.ndarray) -> np.ndarray:
    return 2 * np.pi * np.cumsum(f) / SR


def squeak(seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    dur = rng.uniform(0.18, 0.28)
    t = t_axis(dur + 0.25)
    f0 = rng.uniform(900, 1300)
    k = np.clip(t / dur, 0, 1)
    # Sube deprisa, se queda arriba y cae un poco al final (como apretar un pato de goma).
    f = f0 * (1.0 + 0.9 * np.sin(k * np.pi * 0.62) ** 0.8) * (1.0 + 0.03 * np.sin(2 * np.pi * 28 * t))
    ph = _sweep(t, f)
    env = np.clip(t / 0.012, 0, 1) * (t < dur) * (1.0 - k * 0.4)
    env = lowpass(env, 80, 1)
    tone = np.sin(ph) + 0.5 * np.sin(2 * ph) + 0.28 * np.sin(3 * ph) + 0.12 * np.sin(5 * ph)
    air = bandpass(rng.standard_normal(len(t)), 2500, 7000, 2) * env * 0.18
    x = tone * env * 0.6 + air
    return normalize(fade(reverb(x, rng, 0.3, 0.12), 0.001, 0.05), -4)


def splorch(seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    t = t_axis(1.1)
    n = len(t)
    # Golpe grave (el globo de baba que revienta).
    thump_f = 140 * np.exp(-t / 0.06) + 45
    thump = np.sin(_sweep(t, thump_f)) * np.exp(-t / 0.09)
    # Chapoteo: ruido que se abre y se cierra (wah) muy rápido.
    noise = rng.standard_normal(n)
    wet = bandpass(noise, 300, 2400, 2) * np.exp(-t / 0.12)
    wet += bandpass(noise, 1800, 6000, 2) * np.exp(-t / 0.05) * 0.5
    # "Blorp": burbuja que cae de tono.
    bf = rng.uniform(520, 700) * np.exp(-t / 0.08) + 160
    blorp = np.sin(_sweep(t, bf)) * np.clip(t / 0.01, 0, 1) * np.exp(-t / 0.11) * 0.6
    x = thump * 0.9 + wet * 0.8 + blorp
    # Gotitas que caen después.
    for _ in range(int(rng.integers(5, 9))):
        s0 = int(rng.uniform(0.12, 0.7) * SR)
        m = int(0.05 * SR)
        tt = np.arange(m) / SR
        df = rng.uniform(900, 1800) * (1.0 + 1.2 * tt / tt[-1])
        drop = np.sin(_sweep(tt, df)) * np.exp(-tt / 0.012) * rng.uniform(0.12, 0.3)
        x[s0:s0 + m] += drop
    return normalize(fade(reverb(lowpass(x, 9000, 2), rng, 0.4, 0.14), 0.001, 0.1), -1.5)


def boing(seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    t = t_axis(0.9)
    f0 = rng.uniform(170, 230)
    # Muelle: el tono sube y tiembla (vibrato que se va calmando).
    vib = 1.0 + 0.22 * np.sin(2 * np.pi * 11.0 * t) * np.exp(-t / 0.35)
    f = f0 * (1.0 + 1.4 * (1 - np.exp(-t / 0.08))) * vib
    ph = _sweep(t, f)
    env = np.clip(t / 0.005, 0, 1) * np.exp(-t / 0.3)
    x = (np.sin(ph) + 0.35 * np.sin(2.01 * ph) + 0.15 * np.sin(3.02 * ph)) * env
    x += bandpass(rng.standard_normal(len(t)), 200, 900, 2) * np.exp(-t / 0.03) * 0.4
    return normalize(fade(reverb(x, rng, 0.3, 0.1), 0.001, 0.08), -5)


def kazoo(seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    t = t_axis(1.3)
    base = note(int(rng.choice([-5, -3, 0])))
    # Dos o tres notas que bajan ("wah... wah... waaah").
    steps = [(0.0, 0.22, 1.0), (0.26, 0.22, 0.94), (0.52, 0.6, 0.89)]
    f = np.zeros_like(t)
    env = np.zeros_like(t)
    for s, d, k in steps:
        m = (t >= s) & (t < s + d)
        tt = t[m] - s
        f[m] = base * k * (1.0 - 0.07 * (tt / d) ** 2 * (1.0 if d > 0.3 else 0.3))
        env[m] = np.clip(tt / 0.02, 0, 1) * np.clip((d - tt) / 0.04, 0, 1)
    f = np.where(f > 0, f, base)
    f *= 1.0 + 0.015 * np.sin(2 * np.pi * 5.5 * t)
    ph = _sweep(t, f)
    saw = 2.0 * ((ph / (2 * np.pi)) % 1.0) - 1.0
    # Membrana del kazoo: formantes y zumbido.
    buzz = bandpass(saw, 400, 1400, 2) + bandpass(saw, 2000, 3500, 2) * 0.5
    buzz += np.tanh(saw * 3.0) * 0.2
    x = buzz * lowpass(env, 60, 1)
    return normalize(fade(reverb(x, rng, 0.35, 0.12), 0.002, 0.1), -6)


def inflate(seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    dur = 0.34
    t = t_axis(dur + 0.05)
    k = np.clip(t / dur, 0, 1)
    f = 300 + 1500 * k ** 1.6
    ph = _sweep(t, f)
    env = np.clip(t / 0.02, 0, 1) * (0.4 + 0.6 * k) * (t < dur)
    x = (np.sin(ph) + 0.4 * np.sin(2 * ph)) * env * 0.5
    x += bandpass(rng.standard_normal(len(t)), 800, 4000, 2) * env * 0.25
    return normalize(fade(x, 0.001, 0.01), -7)


def boink(seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    t = t_axis(0.3)
    f = rng.uniform(500, 700) * (1.0 + 0.6 * np.exp(-t / 0.02))
    x = np.sin(_sweep(t, f)) * np.exp(-t / 0.05)
    x += bandpass(rng.standard_normal(len(t)), 400, 2000, 2) * np.exp(-t / 0.008) * 0.3
    return normalize(fade(x, 0.001, 0.04), -8)


def splat(seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    t = t_axis(0.35)
    noise = rng.standard_normal(len(t))
    x = bandpass(noise, 250, 1800, 2) * np.exp(-t / 0.04)
    x += np.sin(_sweep(t, 220 * np.exp(-t / 0.03) + 70)) * np.exp(-t / 0.05) * 0.5
    return normalize(fade(lowpass(x, 5000, 2), 0.001, 0.05), -8)


def sneeze(seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    t = t_axis(1.0)
    x = np.zeros_like(t)
    # "A-a-": dos inspiraciones agudas que suben.
    for k, s in enumerate((0.0, 0.18)):
        m = int(0.12 * SR)
        tt = np.arange(m) / SR
        f = (700 + k * 150) * (1.0 + 0.5 * tt / tt[-1])
        ph = _sweep(tt, f)
        e = np.sin(np.pi * tt / tt[-1]) ** 1.5
        s0 = int(s * SR)
        x[s0:s0 + m] += (np.sin(ph) + 0.3 * np.sin(2 * ph)) * e * 0.35
        x[s0:s0 + m] += bandpass(rng.standard_normal(m), 1500, 5000, 2) * e * 0.12
    # "¡CHÚ!": ráfaga de ruido con un tono que cae.
    s0 = int(0.42 * SR)
    m = len(t) - s0
    tt = np.arange(m) / SR
    burst = bandpass(rng.standard_normal(m), 900, 7000, 2) * np.exp(-tt / 0.09)
    tone = np.sin(_sweep(tt, 900 * np.exp(-tt / 0.1) + 300)) * np.exp(-tt / 0.08) * 0.5
    x[s0:] += burst + tone
    return normalize(fade(reverb(x, rng, 0.3, 0.12), 0.001, 0.08), -5)


def yawn(seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    dur = 0.9
    t = t_axis(dur + 0.2)
    k = np.clip(t / dur, 0, 1)
    f = 320 * (1.0 + 0.45 * np.sin(k * np.pi)) - 120 * k ** 2
    ph = _sweep(t, f)
    env = np.sin(np.clip(k, 0, 1) * np.pi) ** 0.7 * (t < dur)
    tone = np.sin(ph) + 0.5 * np.sin(2 * ph) + 0.25 * np.sin(3 * ph)
    vowel = bandpass(tone, 300, 1200, 2) + bandpass(tone, 1600, 2600, 2) * 0.3 * k
    x = vowel * env + bandpass(rng.standard_normal(len(t)), 500, 3000, 2) * env * 0.06
    return normalize(fade(reverb(x, rng, 0.4, 0.15), 0.01, 0.1), -7)


def giggle(seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    t = t_axis(0.8)
    x = np.zeros_like(t)
    n = int(rng.integers(4, 7))
    for k in range(n):
        s0 = int(k * rng.uniform(0.075, 0.095) * SR)
        m = int(0.06 * SR)
        tt = np.arange(m) / SR
        f = rng.uniform(1100, 1500) * (1.0 - 0.15 * k / n) * (1.0 + 0.2 * np.sin(np.pi * tt / tt[-1]))
        ph = _sweep(tt, f)
        e = np.sin(np.pi * tt / tt[-1]) ** 2
        x[s0:s0 + m] += (np.sin(ph) + 0.3 * np.sin(2 * ph)) * e * (1.0 - 0.1 * k)
    return normalize(fade(reverb(x, rng, 0.3, 0.12), 0.001, 0.05), -8)


def blep(seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    t = t_axis(0.25)
    f = 300 + 900 * np.exp(-t / 0.02)
    x = np.sin(_sweep(t, f)) * np.clip(t / 0.003, 0, 1) * np.exp(-t / 0.04)
    x += bandpass(rng.standard_normal(len(t)), 1000, 4000, 2) * np.exp(-t / 0.01) * 0.2
    return normalize(fade(x, 0.001, 0.04), -8)


def flatten(seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    t = t_axis(1.0)
    x = np.zeros_like(t)
    # Silbato de émbolo que baja.
    m = int(0.42 * SR)
    tt = np.arange(m) / SR
    f = 1500 * np.exp(-tt / 0.3) + 350
    ph = _sweep(tt, f)
    e = np.clip(tt / 0.02, 0, 1) * np.clip((tt[-1] - tt) / 0.03, 0, 1)
    x[:m] += (np.sin(ph) + 0.08 * np.sin(2 * ph)) * e * 0.5
    x[:m] += bandpass(rng.standard_normal(m), 1000, 5000, 2) * e * 0.05
    # "¡Plaf!"
    s0 = int(0.4 * SR)
    rest = len(t) - s0
    tt = np.arange(rest) / SR
    x[s0:] += bandpass(rng.standard_normal(rest), 120, 2500, 2) * np.exp(-tt / 0.06) * 1.2
    x[s0:] += np.sin(_sweep(tt, 90 * np.exp(-tt / 0.05) + 40)) * np.exp(-tt / 0.1)
    return normalize(fade(reverb(x, rng, 0.3, 0.1), 0.001, 0.08), -3)


def confetti(seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    t = t_axis(1.4)
    n = len(t)
    # Matasuegras: "¡pop!" seco.
    x = bandpass(rng.standard_normal(n), 600, 6000, 2) * np.exp(-t / 0.015) * 1.2
    x += np.sin(_sweep(t, 600 * np.exp(-t / 0.01) + 200)) * np.exp(-t / 0.02) * 0.5
    # Papelitos que caen (crujido suave).
    rustle = highpass(rng.standard_normal(n), 4000, 2) * (rng.random(n) < 0.03)
    x += lowpass(rustle, 9000, 2) * np.clip((t - 0.05) / 0.1, 0, 1) * np.exp(-t / 0.6) * 0.6
    # Campanitas en La mayor.
    for i, n_ in enumerate((12, 16, 19, 24)):
        s0 = int((0.04 + i * 0.07) * SR)
        x[s0:] += bell(t[: n - s0], note(n_), [1.0, 2.0, 3.01], [1.0, 0.3, 0.1],
                       [0.3, 0.12, 0.05], rng) * 0.18
    return normalize(fade(reverb(x, rng, 0.6, 0.2), 0.001, 0.15), -3)


def zap(seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    t = t_axis(0.6)
    gate = (np.sin(2 * np.pi * 16.0 * t) > -0.2).astype(float)
    gate = lowpass(gate, 300, 1)
    f = 110 * (1.0 + 0.05 * rng.standard_normal(len(t)).cumsum() / 200.0)
    ph = _sweep(t, f)
    saw = 2.0 * ((ph / (2 * np.pi)) % 1.0) - 1.0
    x = np.tanh(saw * 4.0) * 0.4 + bandpass(rng.standard_normal(len(t)), 2000, 9000, 2) * 0.5
    x *= gate * np.clip(t / 0.01, 0, 1) * np.clip((0.5 - t) / 0.05, 0, 1)
    return normalize(fade(x, 0.001, 0.05), -6)


def main() -> None:
    ap = argparse.ArgumentParser()
    root = Path(__file__).resolve().parent.parent
    ap.add_argument("--out", default=str(root / "game" / "audio" / "sfx"))
    out = Path(ap.parse_args().out)
    for i in range(4):
        write(out, f"sfx_critter_squeak_{i + 1:02d}", squeak(2100 + i))
        write(out, f"sfx_critter_splorch_{i + 1:02d}", splorch(2110 + i))
    for i in range(3):
        write(out, f"sfx_critter_kazoo_{i + 1:02d}", kazoo(2120 + i))
    for i in range(2):
        write(out, f"sfx_critter_boing_{i + 1:02d}", boing(2130 + i))
        write(out, f"sfx_critter_inflate_{i + 1:02d}", inflate(2140 + i))
        write(out, f"sfx_critter_boink_{i + 1:02d}", boink(2150 + i))
        write(out, f"sfx_critter_splat_{i + 1:02d}", splat(2160 + i))
        write(out, f"sfx_critter_giggle_{i + 1:02d}", giggle(2170 + i))
        write(out, f"sfx_critter_confetti_{i + 1:02d}", confetti(2180 + i))
    write(out, "sfx_critter_sneeze_01", sneeze(2190))
    write(out, "sfx_critter_yawn_01", yawn(2191))
    write(out, "sfx_critter_blep_01", blep(2192))
    write(out, "sfx_critter_flatten_01", flatten(2193))
    write(out, "sfx_critter_zap_01", zap(2194))


if __name__ == "__main__":
    main()
