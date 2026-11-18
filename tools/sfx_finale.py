#!/usr/bin/env python3
"""Sonidos y música del final: el Núcleo expuesto, la Gran Convergencia y la fiesta del valle.

Uso:
    python3 tools/sfx_finale.py            # escribe en game/audio/sfx y game/audio/music
    python3 tools/sfx_finale.py --out DIR  # todo en DIR

- mus_core_tension_loop: capa tensa al quedar expuesto el Núcleo (84 BPM, 4 compases, bucle):
  pedal de La y Mi, latido grave en cada tiempo y cuerdas altas suspendidas (Si y Fa#, en la
  pentatónica de La: tensa sin desafinar con el "tink").
- amb_core_hum_loop: zumbido violeta del Núcleo (6 s, frecuencias con ciclos enteros: empalma).
- sfx_core_crack_01: el cristal se resquebraja entero (gemido grave, crujidos, cristal roto).
- sfx_core_peel_01..03: un trozo grande se desprende (crujido de roca, cristal y silbido).
- sfx_core_bounce_01..02: un golpe rebota en el Núcleo (ping de cristal y "dong" que cae).
- sfx_convergence_note_01..05: cada etapa de la carga: la nota de su elemento (Chispa La,
  Escarcha Si, Rayo Do#, Tierra Mi, Arcano Fa#) sobre las anteriores; la quinta es el acorde.
- amb_convergence_charge_loop: coro que vibra mientras se carga (bucle, sube de tono en código).
- sfx_convergence_release_01: la Gran Convergencia sale de las manos.
- sfx_convergence_fizzle_01: se suelta antes de tiempo y se deshace.
- sfx_core_explosion_01: el Núcleo estalla (subgrave, estallido y cola de campanas).
- sfx_mana_column_01: la columna de maná sube al cielo (rugido con coro).
- sfx_firework_launch_01, sfx_firework_pop_01..03: fuegos artificiales.
- sfx_bells_peal_01: los campanarios de la aldea repican.
- sfx_choir_celebrate_01: coro de celebración en La mayor.
- sfx_ending_fanfare_01: la pantalla final ("Yes, you could.").
Deterministas: semillas fijas.
"""
import argparse
from pathlib import Path

import numpy as np

from sfx_synth import (SR, bandpass, bell, fade, highpass, loopable, lowpass, normalize, note,
                       reverb, t_axis, write)

# Notas de los elementos (semitonos respecto a A5), las mismas de las venas.
ELEMENT_NOTES = [-12, -10, -8, -5, -3]
BPM = 84.0
BEAT = 60.0 / BPM


def crackle(rng, n, density=0.004, lo=2000, hi=9000):
    x = np.zeros(n)
    hits = rng.random(n) < density
    x[hits] = rng.uniform(-1, 1, hits.sum())
    return bandpass(x, lo, hi, 2) * 4.0


def voice(f, t, rng, vib=0.005):
    """Vocal "aa" suave (sierra filtrada por dos formantes)."""
    ph = 2 * np.pi * np.cumsum(f * (1 + vib * np.sin(2 * np.pi * 4.7 * t + rng.uniform(0, 6)))) / SR
    src = sum(np.sin(k * ph) / k for k in range(1, 16) if f * k < 7000)
    return bandpass(src, 600, 1150, 2) * 0.8 + bandpass(src, 2300, 3100, 2) * 0.3 + np.sin(ph) * 0.4


def tension_loop(seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    dur = BEAT * 16
    t = t_axis(dur)
    x = np.zeros_like(t)
    # Pedal grave (La1 + Mi2) con pulsación lenta.
    for f, a in [(55.0, 1.0), (82.5, 0.5), (110.0, 0.35)]:
        x += a * np.sin(2 * np.pi * f * t) * (0.8 + 0.2 * np.sin(2 * np.pi * t / (BEAT * 4)))
    x = lowpass(x, 300, 2) * 0.5
    # Latido: dos golpes graves por compás (lub-dub) que crecen hacia el final del bucle.
    for bar in range(4):
        for k, (off, a) in enumerate([(0.0, 1.0), (0.32, 0.6)]):
            s = int((bar * BEAT * 4 + off) * SR)
            n = int(0.5 * SR)
            tt = np.arange(n) / SR
            f = 52 + 40 * np.exp(-tt / 0.04)
            thump = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-tt / 0.16) * a
            x[s:s + n] += thump[: len(x) - s] * 0.9
    # Cuerdas altas suspendidas: Si4 y Fa#5 trémolo, entrando y saliendo.
    strings = np.zeros_like(t)
    for n0, a in [(-10, 0.5), (-3, 0.35), (2, 0.18)]:
        f = note(n0)
        trem = 0.65 + 0.35 * np.sin(2 * np.pi * (1.0 / BEAT * 2) * t)
        strings += voice(f, t, rng, 0.003) * a * trem
    swell = 0.5 - 0.5 * np.cos(2 * np.pi * t / dur)
    x += bandpass(strings, 300, 5000, 2) * (0.35 + 0.65 * swell) * 0.35
    # Aire oscuro.
    x += lowpass(rng.standard_normal(len(t)), 500, 2) * 0.04
    x = reverb(x, rng, 1.8, 0.28)[: len(t) + int(0.8 * SR)]
    return normalize(loopable(x, 0.8), -6)


def core_hum(seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    dur = 6.0
    t = t_axis(dur)
    freqs = [55.0, 82.5 + 1 / 6, 110.0, 164.0 + 1 / 3, 220.0 + 1 / 6, 329.0 + 1 / 3, 440.0]
    amps = [1.0, 0.45, 0.6, 0.25, 0.2, 0.1, 0.06]
    x = np.zeros_like(t)
    for f, a in zip(freqs, amps):
        x += a * np.sin(2 * np.pi * f * t + rng.uniform(0, 2 * np.pi))
    lfo = 0.75 + 0.25 * np.sin(2 * np.pi * t / 3.0)
    return normalize(x * lfo, -8)


def core_crack(seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    t = t_axis(4.5)
    groan_f = 45 + 30 * np.clip(t / 2.0, 0, 1)
    groan = np.sin(2 * np.pi * np.cumsum(groan_f) / SR) + 0.5 * np.sin(2 * np.pi * np.cumsum(groan_f * 1.5) / SR)
    groan = lowpass(groan, 400, 2) * np.clip(t / 0.4, 0, 1) * np.exp(-np.maximum(t - 2.4, 0) / 0.9)
    cracks = crackle(rng, len(t), 0.002 + 0.02 * np.clip(t / 1.2, 0, 1), 800, 7000)
    cracks *= np.exp(-np.maximum(t - 2.6, 0) / 0.6)
    glass = np.zeros_like(t)
    for _ in range(26):
        s0 = int(rng.uniform(0.2, 2.8) * SR)
        tt = t[: len(t) - s0]
        glass[s0:] += bell(tt, rng.uniform(1800, 5200), [1.0, 2.32, 4.25], [1.0, 0.5, 0.3],
                           [0.12, 0.08, 0.05], rng) * rng.uniform(0.1, 0.3)
    boom = lowpass(rng.standard_normal(len(t)), 120) * np.exp(-t / 0.5) * 2.0
    x = groan * 0.8 + cracks * 0.5 + glass * 0.6 + boom
    return normalize(fade(reverb(x, rng, 2.0, 0.3), 0.002, 0.3), -1)


def core_peel(seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    t = t_axis(1.6)
    crunch = crackle(rng, len(t), 0.05, 400, 5000) * np.exp(-t / 0.09)
    thud = lowpass(rng.standard_normal(len(t)), 180) * np.exp(-t / 0.18) * 2.0
    glass = np.zeros_like(t)
    for _ in range(8):
        s0 = int(rng.uniform(0.0, 0.25) * SR)
        tt = t[: len(t) - s0]
        glass[s0:] += bell(tt, rng.uniform(1500, 4500), [1.0, 2.32, 4.25], [1.0, 0.5, 0.3],
                           [0.15, 0.09, 0.05], rng) * 0.25
    whoosh = bandpass(rng.standard_normal(len(t)), 300, 2000, 2) * np.sin(np.pi * np.clip(t / 0.8, 0, 1)) * 0.5
    x = crunch * 0.6 + thud + glass * 0.6 + whoosh * 0.5
    return normalize(fade(reverb(x, rng, 1.2, 0.25), 0.001, 0.2), -2)


def core_bounce(seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    t = t_axis(1.4)
    ping = bell(t, note(7), [1.0, 2.32, 4.25, 6.63], [1.0, 0.5, 0.3, 0.15], [0.5, 0.3, 0.15, 0.08], rng)
    f = 140 * np.exp(-t / 0.6) + 70
    dong = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.35) * 0.8
    sparkle = np.zeros_like(t)
    for _ in range(6):
        s0 = int(rng.uniform(0.01, 0.3) * SR)
        tt = t[: len(t) - s0]
        sparkle[s0:] += np.sin(2 * np.pi * note(19 + int(rng.choice([0, 2, 4, 7]))) * tt) * np.exp(-tt / 0.06) * 0.15
    x = ping * 0.5 + dong + sparkle
    x *= 1 - np.exp(-t / 0.003)
    return normalize(fade(reverb(x, rng, 1.3, 0.3), 0.001, 0.2), -3)


def convergence_note(stage: int, seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    full = stage == 4
    t = t_axis(3.2 if full else 2.2)
    x = np.zeros_like(t)
    for k in range(stage + 1):
        n0 = ELEMENT_NOTES[k] - 12
        a = 1.0 if k == stage else 0.35
        x += bell(t, note(n0 + 12), [1.0, 2.0, 3.01, 4.2], [1.0, 0.3, 0.12, 0.06],
                  [1.4, 0.7, 0.35, 0.2], rng, 0.002) * a * 0.6
        x += voice(note(n0), t, rng) * a * np.clip(t / 0.25, 0, 1) * np.exp(-t / (1.4 if full else 0.9)) * 0.5
    thrum = np.sin(2 * np.pi * 55 * t) * np.exp(-t / 0.4) * (1.2 if full else 0.6)
    x += lowpass(thrum, 200, 2)
    if full:
        x += bandpass(rng.standard_normal(len(t)), 6000, 15000) * np.exp(-t / 0.8) * 0.15
    x *= 1 - np.exp(-t / 0.004)
    return normalize(fade(reverb(x, rng, 1.8, 0.35), 0.001, 0.3), -1 if full else -3)


def convergence_loop(seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    dur = 4.0
    t = t_axis(dur + 0.6)
    x = np.zeros_like(t)
    for n0, a in [(-24, 1.0), (-17, 0.6), (-12, 0.6), (-8, 0.4), (-5, 0.35)]:
        x += voice(note(n0), t, rng, 0.004) * a
    x = bandpass(x, 90, 5000, 2) * 0.4
    x += lowpass(np.sin(2 * np.pi * 55 * t), 200, 2) * 0.3
    x += bandpass(rng.standard_normal(len(t)), 5000, 12000) * 0.04
    return normalize(loopable(x, 0.6), -8)


def convergence_release(seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    t = t_axis(3.5)
    f = 200 + 2400 * (1 - np.exp(-t / 0.3))
    whoosh = bandpass(rng.standard_normal(len(t)), 200, 6000, 2) * np.exp(-t / 0.6)
    zap = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.25) * 0.4
    chord = np.zeros_like(t)
    for n0 in ELEMENT_NOTES:
        chord += bell(t, note(n0), [1.0, 2.0, 3.01], [1.0, 0.3, 0.1], [1.2, 0.6, 0.3], rng) * 0.3
    boom = lowpass(rng.standard_normal(len(t)), 150) * np.exp(-t / 0.3) * 1.5
    x = whoosh + zap + chord + boom
    return normalize(fade(reverb(x, rng, 2.0, 0.3), 0.001, 0.4), -1)


def convergence_fizzle(seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    t = t_axis(1.6)
    x = np.zeros_like(t)
    for k, n0 in enumerate(reversed(ELEMENT_NOTES)):
        s0 = int(k * 0.09 * SR)
        tt = t[: len(t) - s0]
        f = note(n0) * (1 - 0.25 * np.clip(tt / 0.6, 0, 1))
        x[s0:] += np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-tt / 0.25) * 0.3
    x += bandpass(rng.standard_normal(len(t)), 2000, 8000) * np.exp(-t / 0.3) * 0.2
    return normalize(fade(reverb(x, rng, 1.0, 0.3), 0.001, 0.2), -6)


def core_explosion(seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    t = t_axis(7.5)
    sub_f = 30 + 60 * np.exp(-t / 0.3)
    sub = np.sin(2 * np.pi * np.cumsum(sub_f) / SR) * np.exp(-t / 1.8) * 1.4
    blast = lowpass(rng.standard_normal(len(t)), 900) * np.exp(-t / 0.35) * 2.0
    rumble = lowpass(np.cumsum(rng.standard_normal(len(t))) * 0.01, 90) * np.exp(-t / 2.0) * 3.0
    glass = np.zeros_like(t)
    for _ in range(60):
        s0 = int(rng.uniform(0.05, 3.5) * SR)
        tt = t[: len(t) - s0]
        glass[s0:] += bell(tt, rng.uniform(1400, 6000), [1.0, 2.32, 4.25], [1.0, 0.5, 0.3],
                           [0.25, 0.14, 0.08], rng) * rng.uniform(0.04, 0.12)
    chord = np.zeros_like(t)
    for n0 in [-24, -17, -12, -8, -5, -3, 0, 4]:
        chord += bell(t, note(n0), [1.0, 2.0, 3.01, 4.2], [1.0, 0.3, 0.12, 0.06],
                      [3.0, 1.5, 0.8, 0.4], rng, 0.002) * 0.25
    chord *= np.clip((t - 0.15) / 0.4, 0, 1)
    x = sub + blast + rumble + glass + chord
    return normalize(fade(reverb(x, rng, 3.0, 0.35), 0.001, 0.8), -0.5)


def mana_column(seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    t = t_axis(6.0)
    rise = np.clip(t / 1.5, 0, 1)
    roar = bandpass(rng.standard_normal(len(t)), 100, 1200, 2) * rise * np.exp(-np.maximum(t - 2.5, 0) / 1.5)
    f = 110 * (1 + rise)
    tone = (np.sin(2 * np.pi * np.cumsum(f) / SR) + 0.5 * np.sin(2 * np.pi * np.cumsum(f * 1.5) / SR)) * rise
    choir = np.zeros_like(t)
    for n0, a in [(-24, 1.0), (-17, 0.6), (-12, 0.7), (-8, 0.5), (-5, 0.4), (0, 0.25)]:
        choir += voice(note(n0), t, rng) * a
    choir *= np.clip((t - 0.4) / 1.2, 0, 1) * np.exp(-np.maximum(t - 3.5, 0) / 1.0)
    x = roar * 0.8 + lowpass(tone, 600, 2) * 0.3 + choir * 0.2
    return normalize(fade(reverb(x, rng, 2.5, 0.35), 0.05, 0.8), -1)


def firework_launch(seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    t = t_axis(1.3)
    f = 700 + 1800 * (t / t[-1])
    whistle = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.clip(t / 0.1, 0, 1) * 0.2
    hiss = bandpass(rng.standard_normal(len(t)), 2000, 8000) * 0.3
    x = (whistle + hiss) * np.exp(-np.maximum(t - 1.0, 0) / 0.1)
    return normalize(fade(x, 0.01, 0.05), -10)


def firework_pop(seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    t = t_axis(2.6)
    bang = lowpass(rng.standard_normal(len(t)), 1500) * np.exp(-t / 0.06) * 2.0
    thump = lowpass(rng.standard_normal(len(t)), 120) * np.exp(-t / 0.25) * 1.5
    crack = crackle(rng, len(t), 0.02 * np.exp(-np.maximum(t - 0.25, 0) / 0.6) * (t > 0.25), 2500, 10000)
    x = bang + thump + crack * 0.5
    return normalize(fade(reverb(x, rng, 1.6, 0.3), 0.001, 0.3), -3)


def bells_peal(seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    t = t_axis(8.0)
    x = np.zeros_like(t)
    # Repique descendente en La mayor (pentatónica), tres vueltas.
    seq = [0, -3, -5, -8, -10, -12]
    k = 0
    for rnd in range(4):
        for i, n0 in enumerate(seq):
            s0 = int((0.05 + k * 0.28) * SR)
            k += 1
            if s0 >= len(t):
                break
            tt = t[: len(t) - s0]
            x[s0:] += bell(tt, note(n0 - 12), [0.5, 1.0, 1.19, 1.5, 2.0, 2.5, 3.0],
                           [0.6, 1.0, 0.45, 0.35, 0.3, 0.15, 0.1],
                           [2.5, 1.8, 1.0, 0.8, 0.6, 0.4, 0.3], rng, 0.003) * 0.25
    return normalize(fade(reverb(x, rng, 2.4, 0.3), 0.001, 0.8), -2)


def choir_celebrate(seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    t = t_axis(7.0)
    x = np.zeros_like(t)
    # A - D - E - A (I IV V I), una voz por nota.
    chords = [[-24, -17, -12, -8], [-19, -14, -10, -7], [-17, -13, -10, -5], [-24, -12, -8, -5]]
    for c, chord in enumerate(chords):
        s0 = int(c * 1.5 * SR)
        n = int(2.4 * SR)
        tt = np.arange(n) / SR
        env = np.clip(tt / 0.3, 0, 1) * np.exp(-np.maximum(tt - 1.4, 0) / 0.5)
        for n0 in chord:
            v = voice(note(n0), tt, rng) * env * 0.3
            end = min(len(x), s0 + n)
            x[s0:end] += v[: end - s0]
    x = bandpass(x, 100, 6000, 2)
    return normalize(fade(reverb(x, rng, 2.6, 0.38), 0.05, 1.0), -2)


def fanfare(seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    t = t_axis(7.0)
    x = np.zeros_like(t)

    def brass(f, tt):
        ph = 2 * np.pi * np.cumsum(f * (1 + 0.003 * np.sin(2 * np.pi * 5 * tt))) / SR
        src = sum(np.sin(k * ph) / (k ** 0.8) for k in range(1, 14) if f * k < 8000)
        bright = np.clip(tt / 0.08, 0, 1)
        return lowpass(src, 2500, 2) * bright

    # Llamada: La - Mi - La (octava) - Do# - Mi, y el acorde final largo.
    melody = [(-12, 0.0, 0.35), (-5, 0.35, 0.35), (0, 0.7, 0.5), (4, 1.2, 0.3), (7, 1.5, 2.6)]
    for n0, start, dur in melody:
        s0 = int(start * SR)
        n = int((dur + 0.6) * SR)
        tt = np.arange(n) / SR
        env = np.clip(tt / 0.03, 0, 1) * np.exp(-np.maximum(tt - dur, 0) / 0.2)
        v = brass(note(n0 - 12), tt) * env * 0.35
        end = min(len(x), s0 + n)
        x[s0:end] += v[: end - s0]
    s0 = int(1.5 * SR)
    tt = t[: len(t) - s0]
    for n0 in [-36, -24, -17, -12, -8]:
        env = np.clip(tt / 0.2, 0, 1) * np.exp(-np.maximum(tt - 2.4, 0) / 0.9)
        x[s0:] += brass(note(n0), tt) * env * 0.16
    for i, n0 in enumerate([12, 16, 19, 24]):
        s1 = int((1.55 + i * 0.09) * SR)
        tt2 = t[: len(t) - s1]
        x[s1:] += bell(tt2, note(n0), [1.0, 2.0, 3.01], [1.0, 0.3, 0.1], [1.2, 0.6, 0.3], rng) * 0.12
    timp = lowpass(rng.standard_normal(len(t)), 150) * np.exp(-np.maximum(t - 1.5, 0) / 0.6) * (t > 1.5) * 1.2
    x += timp
    return normalize(fade(reverb(x, rng, 2.2, 0.3), 0.005, 1.0), -1)


def main() -> None:
    ap = argparse.ArgumentParser()
    root = Path(__file__).resolve().parent.parent
    ap.add_argument("--out", default="")
    args = ap.parse_args()
    sfx = Path(args.out) if args.out else root / "game" / "audio" / "sfx"
    music = Path(args.out) if args.out else root / "game" / "audio" / "music"
    write(music, "mus_core_tension_loop", tension_loop(1801))
    write(sfx, "amb_core_hum_loop", core_hum(1802))
    write(sfx, "sfx_core_crack_01", core_crack(1803))
    for i in range(3):
        write(sfx, f"sfx_core_peel_{i + 1:02d}", core_peel(1810 + i))
    for i in range(2):
        write(sfx, f"sfx_core_bounce_{i + 1:02d}", core_bounce(1820 + i))
    for i in range(5):
        write(sfx, f"sfx_convergence_note_{i + 1:02d}", convergence_note(i, 1830 + i))
    write(sfx, "amb_convergence_charge_loop", convergence_loop(1840))
    write(sfx, "sfx_convergence_release_01", convergence_release(1841))
    write(sfx, "sfx_convergence_fizzle_01", convergence_fizzle(1842))
    write(sfx, "sfx_core_explosion_01", core_explosion(1850))
    write(sfx, "sfx_mana_column_01", mana_column(1851))
    write(sfx, "sfx_firework_launch_01", firework_launch(1860))
    for i in range(3):
        write(sfx, f"sfx_firework_pop_{i + 1:02d}", firework_pop(1861 + i))
    write(sfx, "sfx_bells_peal_01", bells_peal(1870))
    write(sfx, "sfx_choir_celebrate_01", choir_celebrate(1871))
    write(sfx, "sfx_ending_fanfare_01", fanfare(1872))


if __name__ == "__main__":
    main()
