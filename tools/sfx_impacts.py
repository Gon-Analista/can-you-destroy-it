#!/usr/bin/env python3
"""Cuerpo del golpe de cada elemento: la capa grave y con carácter que suena bajo el "tink".

Uso:
    python3 tools/sfx_impacts.py            # escribe en game/audio/sfx
    python3 tools/sfx_impacts.py --out DIR

Tres variantes de cada uno (sfx_hit_<estilo>_01..03), en el orden de `ImpactStyle`:
- fire: "fuuumf" de llamarada que se traga el aire y chisporroteo de brasas.
- arcane: "vuuum" que cae de tono, campana mágica y su eco (como la segunda onda que se ve).
- ice: cristal que revienta: esquirlas agudas que tintinean y crujido de escarcha.
- bolt: chasquido seco de relámpago, zumbido eléctrico que parpadea y trueno corto.
- rock: golpe sordo y grave de peñasco y gravilla que cae.
- wind: ráfaga que baja de tono ("fuuum") con un silbido al final.
Deterministas: semillas fijas.
"""
import argparse
from pathlib import Path

import numpy as np

from sfx_synth import SR, bandpass, fade, highpass, lowpass, normalize, note, reverb, t_axis, write


def sweep(t, f0, f1, tau):
    """Seno cuyo tono va de f0 a f1 con constante de tiempo tau."""
    f = f1 + (f0 - f1) * np.exp(-t / tau)
    return np.sin(2 * np.pi * np.cumsum(f) / SR)


def thump(t, f0, f1, decay, tau=0.04):
    return sweep(t, f0, f1, tau) * np.exp(-t / decay) * np.clip(t / 0.002, 0, 1)


def crackle(rng, t, rate, decay, lo, hi):
    """Chasquidos sueltos cada vez más escasos (brasas, gravilla)."""
    x = np.zeros_like(t)
    dens = rate * np.exp(-t / decay) / SR
    hits = rng.random(len(t)) < dens
    x[hits] = rng.uniform(-1, 1, hits.sum())
    return bandpass(x, lo, hi, 2)


def fire(seed, pitch):
    rng = np.random.default_rng(seed)
    t = t_axis(1.0)
    body = thump(t, 120 * pitch, 48 * pitch, 0.16) * 1.0
    whoosh = lowpass(rng.standard_normal(len(t)), 700 * pitch) * np.exp(-t / 0.11) * np.clip(t / 0.01, 0, 1)
    roar = bandpass(rng.standard_normal(len(t)), 300, 1800, 2) * np.exp(-t / 0.22) * 0.35
    pops = crackle(rng, t, 900, 0.25, 1800, 7000) * 2.2
    return normalize(fade(reverb(fade(body + whoosh * 1.4 + roar + pops, 0.0005, 0.15), rng, 0.6, 0.18, 6000), 0.001, 0.15), -2)


def arcane(seed, pitch):
    rng = np.random.default_rng(seed)
    t = t_axis(1.3)
    vwom = sweep(t, 700 * pitch, 140 * pitch, 0.07) * np.exp(-t / 0.2) * 0.8
    sub = thump(t, 110 * pitch, 60 * pitch, 0.18) * 0.7
    bell = np.zeros_like(t)
    for n, a in ((0, 0.35), (4, 0.25), (7, 0.22), (12, 0.12)):
        f = note(n - 12) * pitch * (1 + rng.uniform(-0.003, 0.003))
        bell += np.sin(2 * np.pi * f * t) * a * np.exp(-t / 0.45)
    x = vwom + sub + bell * np.clip(t / 0.01, 0, 1)
    # Eco: el golpe vuelve 0,16 s después, más débil y un poco más agudo.
    d = int(0.16 * SR)
    echo = np.zeros_like(x)
    echo[d:] = highpass(x, 300, 2)[: len(x) - d] * 0.45
    return normalize(fade(reverb(fade(x + echo, 0.0005, 0.15), rng, 1.0, 0.3, 8000), 0.001, 0.25), -2)


def ice(seed, pitch):
    rng = np.random.default_rng(seed)
    t = t_axis(1.0)
    x = thump(t, 160 * pitch, 80 * pitch, 0.07) * 0.8
    crunch = highpass(rng.standard_normal(len(t)), 2500) * np.exp(-t / 0.05) * 0.7
    x += crunch
    # Esquirlas: tintineos agudos repartidos en el primer cuarto de segundo.
    for _ in range(22):
        t0 = rng.uniform(0.0, 0.28) ** 1.6
        f = rng.uniform(2200, 7500) * pitch
        tt = np.clip(t - t0, 0, None)
        on = (t >= t0).astype(float)
        x += np.sin(2 * np.pi * f * tt) * np.exp(-tt / rng.uniform(0.03, 0.12)) * on * rng.uniform(0.08, 0.22)
    frost = bandpass(rng.standard_normal(len(t)), 4000, 12000, 2) * np.exp(-t / 0.35) * 0.12
    return normalize(fade(reverb(fade(x + frost, 0.0005, 0.15), rng, 0.9, 0.25, 11000), 0.0005, 0.2), -2)


def bolt(seed, pitch):
    rng = np.random.default_rng(seed)
    t = t_axis(1.1)
    crack = highpass(rng.standard_normal(len(t)), 1500) * np.exp(-t / 0.012) * 1.6
    # Zumbido que parpadea a la vez que el destello (on 0-0,04, 0,07-0,11, 0,15-0,18 s).
    gate = ((t < 0.04) | ((t > 0.07) & (t < 0.11)) | ((t > 0.15) & (t < 0.18))).astype(float)
    gate = lowpass(gate, 200, 1) * 0.85 + 0.15
    f = 110 * pitch * (1 + 0.04 * rng.standard_normal(len(t)).cumsum() / np.sqrt(SR))
    buzz = np.sign(np.sin(2 * np.pi * np.cumsum(f) / SR)) * 0.5
    buzz = bandpass(buzz, 150, 4000, 2) * gate * np.exp(-t / 0.18) * 0.6
    boom = lowpass(rng.standard_normal(len(t)), 160) * np.exp(-np.clip(t - 0.02, 0, None) / 0.3) * 2.0
    boom *= np.clip((t - 0.01) / 0.03, 0, 1)
    return normalize(fade(reverb(fade(crack + buzz + boom, 0.0005, 0.15), rng, 1.0, 0.25, 7000), 0.0003, 0.2), -2)


def rock(seed, pitch):
    rng = np.random.default_rng(seed)
    t = t_axis(1.1)
    body = thump(t, 95 * pitch, 38 * pitch, 0.22, 0.05) * 1.3
    smack = lowpass(rng.standard_normal(len(t)), 500) * np.exp(-t / 0.06) * 1.2
    gravel = crackle(rng, t, 1400, 0.3, 500, 3500) * 2.0
    dust = bandpass(rng.standard_normal(len(t)), 200, 1200, 2) * np.exp(-t / 0.35) * 0.18
    return normalize(fade(reverb(fade(body + smack + gravel + dust, 0.0005, 0.15), rng, 0.7, 0.15, 4000), 0.001, 0.2), -1.5)


def wind(seed, pitch):
    rng = np.random.default_rng(seed)
    t = t_axis(0.9)
    noise = rng.standard_normal(len(t))
    # Banda que baja de 3 kHz a 400 Hz: "fuuum".
    x = np.zeros_like(t)
    centers = 400 * pitch + 2600 * pitch * np.exp(-t / 0.12)
    for k, (lo, hi) in enumerate(((300, 900), (800, 2200), (1800, 5000))):
        band = bandpass(noise, lo * pitch, hi * pitch, 2)
        mid = np.sqrt(lo * hi) * pitch
        w = np.exp(-((np.log(centers) - np.log(mid)) ** 2) / 0.35)
        x += band * w
    x *= np.clip(t / 0.015, 0, 1) * np.exp(-t / 0.22) * 1.4
    puff = thump(t, 90 * pitch, 50 * pitch, 0.1) * 0.6
    whistle = sweep(t, note(-5) * pitch * 2, note(-12) * pitch, 0.2) * np.exp(-t / 0.25) * 0.12
    return normalize(fade(reverb(fade(x + puff + whistle, 0.0005, 0.15), rng, 0.8, 0.3, 9000), 0.001, 0.2), -2)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", type=Path, default=Path(__file__).resolve().parent.parent / "game" / "audio" / "sfx")
    out = ap.parse_args().out
    makers = (("fire", fire), ("arcane", arcane), ("ice", ice), ("bolt", bolt), ("rock", rock), ("wind", wind))
    for s, (name, fn) in enumerate(makers):
        for v, pitch in enumerate((1.0, 0.9, 1.12)):
            write(out, f"sfx_hit_{name}_{v + 1:02d}", fn(1300 + s * 10 + v, pitch))


if __name__ == "__main__":
    main()
