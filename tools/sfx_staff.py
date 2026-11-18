#!/usr/bin/env python3
"""Sonidos del báculo y de las combinaciones triples.

Uso:
    python3 tools/sfx_staff.py            # escribe en game/audio/sfx
    python3 tools/sfx_staff.py --out DIR

- sfx_staff_summon_01: el báculo aparece en la mano: barrido que sube, campanas en La y un golpe
  de gong grave con brillo.
- sfx_staff_cycle_01/02: la gema cambia de elemento: clic de engaste y campanita (dos alturas).
- sfx_triple_combine_01: las manos y el báculo se juntan: tres notas que se abren en acorde (La,
  Mi, Do#) sobre un zumbido que crece.
- amb_storm_cloud_loop: la nube de la Tormenta Elemental: retumbe grave, lluvia y viento (bucle).
- sfx_storm_strike_01/02/03: descargas de la tormenta: chasquido de rayo con cola de trueno.
- sfx_hail_01: granizo: tintineos de hielo que caen.
- sfx_nova_gather_01: la Supernova se contrae: aspiración que sube de tono con campanas al revés.
- sfx_nova_blast_01: la Supernova estalla: bombo subgrave, destello de campanas y retumbe largo.
- sfx_glacier_crash_01: el Glaciar Tronante: hielo que se parte y un trueno encima.
- sfx_star_rain_01: Lluvia de Estrellas: silbidos que caen y destellos en pentatónica.
- sfx_eruption_01: Erupción: retumbe de tierra, borbotón de lava y rocas.
Deterministas: semillas fijas. Notas en La mayor / pentatónica de La (como el resto).
"""
import argparse
from pathlib import Path

import numpy as np

from sfx_synth import (
    SR,
    bandpass,
    bell,
    fade,
    highpass,
    loopable,
    lowpass,
    normalize,
    note,
    reverb,
    t_axis,
    write,
)


def _sweep(t, f0, f1, curve=1.0):
    u = np.clip(t / t[-1], 0, 1) ** curve
    f = f0 + (f1 - f0) * u
    return np.sin(2 * np.pi * np.cumsum(f) / SR)


def summon(seed):
    rng = np.random.default_rng(seed)
    t = t_axis(2.6)
    rise = bandpass(rng.standard_normal(len(t)), 900, 7000, 2) * np.clip(t / 0.5, 0, 1)
    rise *= np.exp(-np.clip(t - 0.5, 0, None) / 0.15) * 0.35
    x = rise + _sweep(t, 220, 880, 0.6) * np.clip(t / 0.5, 0, 1) * np.exp(-t / 0.6) * 0.15
    # Gong grave al llegar (La2) con campanas en La mayor encima.
    s = int(0.48 * SR)
    tt = t[: len(t) - s]
    gong = bell(tt, 110.0, [1.0, 1.48, 2.0, 2.76, 3.9], [1.0, 0.6, 0.5, 0.3, 0.2],
                [1.8, 1.2, 0.9, 0.6, 0.4], rng, 0.003)
    x[s:] += gong * 0.8
    for k, n in enumerate((0, 4, 7, 12)):
        s2 = s + int(k * 0.07 * SR)
        tt2 = t[: len(t) - s2]
        x[s2:] += bell(tt2, note(n), [1.0, 2.0, 3.0], [1.0, 0.3, 0.1], [0.9, 0.5, 0.25], rng) * 0.35
    return normalize(fade(reverb(x, rng, 1.8, 0.35), 0.002, 0.4), -2)


def cycle(seed, pitch):
    rng = np.random.default_rng(seed)
    t = t_axis(0.6)
    click = highpass(rng.standard_normal(len(t)), 2500) * np.exp(-t / 0.006) * 0.5
    clack = bandpass(rng.standard_normal(len(t)), 600, 2400, 2) * np.exp(-t / 0.02) * 0.4
    chime = bell(t, note(pitch), [1.0, 2.0, 3.0, 4.1], [1.0, 0.35, 0.15, 0.05],
                 [0.35, 0.2, 0.12, 0.08], rng) * 0.6
    whoosh = bandpass(rng.standard_normal(len(t)), 1500, 6000, 2) * np.sin(np.pi * np.clip(t / 0.18, 0, 1)) * 0.12
    x = click + clack + np.roll(chime, int(0.015 * SR)) + whoosh
    return normalize(fade(reverb(x, rng, 0.7, 0.25), 0.001, 0.08), -5)


def triple_combine(seed):
    rng = np.random.default_rng(seed)
    t = t_axis(1.8)
    hum = np.zeros_like(t)
    for f, a in ((110.0, 1.0), (165.0, 0.6), (220.0, 0.4)):
        hum += np.sin(2 * np.pi * f * t + rng.uniform(0, 6)) * a
    hum *= np.clip(t / 0.6, 0, 1) * np.exp(-np.clip(t - 0.8, 0, None) / 0.5) * 0.25
    x = hum
    for k, n in enumerate((-12, -5, 4)):  # La, Mi, Do#: se abren una tras otra
        s = int(k * 0.12 * SR)
        tt = t[: len(t) - s]
        x[s:] += bell(tt, note(n), [1.0, 2.0, 3.0, 4.0], [1.0, 0.4, 0.2, 0.1],
                      [1.0, 0.6, 0.35, 0.2], rng, 0.01) * 0.45
    x += bandpass(rng.standard_normal(len(t)), 5000, 12000) * np.exp(-t / 0.5) * 0.06
    return normalize(fade(reverb(x, rng, 1.4, 0.35), 0.004, 0.3), -3)


def storm_loop(seed):
    rng = np.random.default_rng(seed)
    dur = 8.0
    t = t_axis(dur + 0.6)
    rumble = lowpass(rng.standard_normal(len(t)), 70) * (0.7 + 0.3 * np.sin(2 * np.pi * t / 2.7))
    rain = bandpass(rng.standard_normal(len(t)), 2500, 9000, 2) * 0.12
    drops = np.zeros_like(t)
    for _ in range(900):
        s = rng.integers(0, len(t) - 400)
        n = rng.integers(60, 300)
        drops[s:s + n] += bandpass(rng.standard_normal(n), 3000, 8000, 2) * np.hanning(n) * rng.uniform(0.02, 0.1)
    wind = bandpass(rng.standard_normal(len(t)), 300, 1200, 2) * (0.5 + 0.5 * np.sin(2 * np.pi * t / 4.1)) * 0.25
    # Retumbos lejanos dentro de la nube.
    roll = np.zeros_like(t)
    for c in (1.2, 4.1, 6.6):
        s = int(c * SR)
        n = int(1.4 * SR)
        tt = np.arange(n) / SR
        roll[s:s + n] += lowpass(rng.standard_normal(n), 120) * np.exp(-tt / 0.5) * np.clip(tt / 0.1, 0, 1) * 1.6
    x = rumble * 2.0 + rain + drops + wind + roll
    return normalize(loopable(x, 0.6), -5)


def strike(seed):
    rng = np.random.default_rng(seed)
    t = t_axis(2.2)
    crack = highpass(rng.standard_normal(len(t)), 1800) * np.exp(-t / 0.035) * 1.2
    zap = bandpass(rng.standard_normal(len(t)), 900, 5000, 2) * np.exp(-t / 0.12)
    zap *= 0.6 + 0.4 * np.sign(np.sin(2 * np.pi * 37 * t))
    boom = lowpass(rng.standard_normal(len(t)), 140) * np.clip((t - 0.05) / 0.1, 0, 1) * np.exp(-t / 0.7) * 2.6
    x = crack + zap * 0.7 + boom
    return normalize(fade(reverb(x, rng, 1.6, 0.3, 3500), 0.001, 0.5), -2)


def hail(seed):
    rng = np.random.default_rng(seed)
    t = t_axis(1.2)
    x = np.zeros_like(t)
    for _ in range(26):
        s = rng.integers(0, int(0.8 * SR))
        tt = t[: len(t) - s]
        x[s:] += bell(tt, rng.uniform(2200, 5200), [1.0, 2.3], [1.0, 0.3], [0.05, 0.03], rng) * rng.uniform(0.1, 0.4)
        n = int(0.01 * SR)
        x[s:s + n] += highpass(rng.standard_normal(n), 3000) * np.hanning(n) * 0.3
    return normalize(fade(reverb(x, rng, 0.8, 0.25), 0.001, 0.1), -4)


def nova_gather(seed):
    rng = np.random.default_rng(seed)
    dur = 1.1
    t = t_axis(dur)
    u = t / dur
    suck = bandpass(rng.standard_normal(len(t)), 400, 6000, 2) * u ** 2.2 * 0.6
    tone = _sweep(t, 110, 880, 2.0) * u ** 1.5 * 0.4
    x = suck + tone
    # Campanas "al revés": crecen hasta el final.
    for n in (0, 7, 12, 16):
        b = bell(t, note(n), [1.0, 2.0], [1.0, 0.3], [0.5, 0.3], rng)[::-1]
        x += b * 0.18
    return normalize(fade(x, 0.02, 0.01), -3)


def nova_blast(seed):
    rng = np.random.default_rng(seed)
    t = t_axis(4.5)
    f = 26 + 60 * np.exp(-t / 0.15)
    kick = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 1.0) * 1.8
    body = lowpass(rng.standard_normal(len(t)), 300) * np.exp(-t / 0.5) * 1.8
    sizzle = highpass(rng.standard_normal(len(t)), 4000) * np.exp(-t / 0.6) * 0.25
    chord = np.zeros_like(t)
    for k, n in enumerate((-12, -5, 0, 4, 7, 12)):
        chord += bell(t, note(n), [1.0, 2.0, 3.0], [1.0, 0.3, 0.1], [2.0, 1.2, 0.6], rng) * (0.22 - k * 0.02)
    rumble = lowpass(rng.standard_normal(len(t)), 55) * np.clip(t / 0.3, 0, 1) * np.exp(-t / 1.8) * 3.0
    x = kick + body + sizzle + chord + rumble
    return normalize(fade(reverb(x, rng, 2.8, 0.35, 3000), 0.001, 1.2), -1)


def glacier_crash(seed):
    rng = np.random.default_rng(seed)
    t = t_axis(3.0)
    crack = bandpass(rng.standard_normal(len(t)), 1500, 7000, 2) * np.exp(-t / 0.08) * 1.2
    shards = np.zeros_like(t)
    for _ in range(40):
        s = rng.integers(int(0.02 * SR), int(1.4 * SR))
        tt = t[: len(t) - s]
        shards[s:] += bell(tt, rng.uniform(1800, 4500), [1.0, 2.7], [1.0, 0.4], [0.12, 0.06], rng) * rng.uniform(0.05, 0.25)
    boom = lowpass(rng.standard_normal(len(t)), 120) * np.exp(-t / 0.8) * 2.4
    thunder = highpass(rng.standard_normal(len(t)), 1200) * np.exp(-np.clip(t - 0.1, 0, None) / 0.05)
    thunder *= (t > 0.1) * 0.8
    x = crack + shards + boom + thunder
    return normalize(fade(reverb(x, rng, 2.2, 0.35, 4000), 0.001, 0.8), -1)


def star_rain(seed):
    rng = np.random.default_rng(seed)
    t = t_axis(2.4)
    x = np.zeros_like(t)
    penta = (0, 2, 4, 7, 9, 12, 14, 16)
    for k in range(14):
        s = int((k * 0.11 + rng.uniform(0, 0.04)) * SR)
        n = int(0.35 * SR)
        tt = np.arange(n) / SR
        f = rng.uniform(2600, 3600) * np.exp(-tt / 0.4)
        whistle = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.hanning(n) * 0.08
        if s + n < len(t):
            x[s:s + n] += whistle
        tt2 = t[: len(t) - s]
        x[s:] += bell(tt2, note(penta[k % len(penta)]), [1.0, 2.0, 3.0], [1.0, 0.3, 0.1],
                      [0.4, 0.25, 0.1], rng) * 0.25
    return normalize(fade(reverb(x, rng, 1.6, 0.4), 0.002, 0.4), -3)


def eruption(seed):
    rng = np.random.default_rng(seed)
    t = t_axis(3.4)
    rumble = lowpass(rng.standard_normal(len(t)), 80) * np.clip(t / 0.15, 0, 1) * np.exp(-t / 1.2) * 3.0
    f = 32 + 40 * np.exp(-t / 0.2)
    kick = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.7) * 1.4
    bloops = np.zeros_like(t)
    for _ in range(14):
        s = rng.integers(int(0.1 * SR), int(2.4 * SR))
        n = int(rng.uniform(0.08, 0.2) * SR)
        tt = np.arange(n) / SR
        ff = rng.uniform(70, 160) * (1 + 1.5 * tt / tt[-1])
        if s + n < len(t):
            bloops[s:s + n] += np.sin(2 * np.pi * np.cumsum(ff) / SR) * np.hanning(n) * rng.uniform(0.2, 0.5)
    hiss = bandpass(rng.standard_normal(len(t)), 2000, 8000, 2) * np.exp(-t / 0.9) * 0.25
    rocks = np.zeros_like(t)
    for _ in range(30):
        s = rng.integers(int(0.2 * SR), int(2.8 * SR))
        n = int(0.03 * SR)
        if s + n < len(t):
            rocks[s:s + n] += bandpass(rng.standard_normal(n), 400, 2500, 2) * np.hanning(n) * rng.uniform(0.1, 0.3)
    x = rumble + kick + bloops + hiss + rocks
    return normalize(fade(reverb(x, rng, 2.0, 0.3, 3000), 0.001, 0.8), -1)


def main() -> None:
    ap = argparse.ArgumentParser()
    root = Path(__file__).resolve().parent.parent
    ap.add_argument("--out", default=str(root / "game" / "audio" / "sfx"))
    out = Path(ap.parse_args().out)
    write(out, "sfx_staff_summon_01", summon(2101))
    write(out, "sfx_staff_cycle_01", cycle(2102, 7))
    write(out, "sfx_staff_cycle_02", cycle(2103, 12))
    write(out, "sfx_triple_combine_01", triple_combine(2104))
    write(out, "amb_storm_cloud_loop", storm_loop(2105))
    for i in range(3):
        write(out, f"sfx_storm_strike_{i + 1:02d}", strike(2110 + i))
    write(out, "sfx_hail_01", hail(2120))
    write(out, "sfx_nova_gather_01", nova_gather(2130))
    write(out, "sfx_nova_blast_01", nova_blast(2131))
    write(out, "sfx_glacier_crash_01", glacier_crash(2140))
    write(out, "sfx_star_rain_01", star_rain(2150))
    write(out, "sfx_eruption_01", eruption(2160))


if __name__ == "__main__":
    main()
