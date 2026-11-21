#!/usr/bin/env python3
"""Sonidos del Viento y de sus combinaciones.

Uso:
    python3 tools/sfx_wind.py            # escribe en game/audio/sfx
    python3 tools/sfx_wind.py --out DIR

- sfx_wind_cast_01/02: "fsshh" corto: ráfaga de aire que sube de tono, con un silbido.
- sfx_wind_impact_01: golpe de aire contra el cristal: soplo que se abre y un tintineo.
- sfx_tornado_01: el Tornado y sus parientes: remolino que gira cada vez más rápido.
- amb_wind_charge_loop: carga de los hechizos de viento: aire que gira (bucle).
Deterministas: semillas fijas.
"""
import argparse
from pathlib import Path

import numpy as np

from sfx_synth import SR, bandpass, fade, highpass, loopable, lowpass, normalize, note, reverb, t_axis, write


def gust(rng, t, lo, hi, rate):
    """Ruido de aire cuya banda sube y baja `rate` veces por segundo (remolino)."""
    noise = rng.standard_normal(len(t))
    x = np.zeros_like(t)
    for k, (a, b) in enumerate(((lo, lo * 2.2), (lo * 2.0, hi * 0.6), (hi * 0.5, hi))):
        w = 0.5 + 0.5 * np.sin(2 * np.pi * np.cumsum(np.full_like(t, rate)) / SR + k * 2.1)
        x += bandpass(noise, a, b, 2) * w
    return x


def wind_cast(seed, pitch):
    rng = np.random.default_rng(seed)
    t = t_axis(0.6)
    env = np.clip(t / 0.03, 0, 1) * np.exp(-t / 0.16)
    x = bandpass(rng.standard_normal(len(t)), 900 * pitch, 7000, 2) * env
    # Silbido que sube (el aire sale de la mano).
    f = note(-12) * pitch * 2 ** np.clip(t / 0.15, 0, 1.2)
    x += np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.1) * 0.18
    return normalize(fade(reverb(x, rng, 0.6, 0.25, 9000), 0.001, 0.12), -4)


def wind_impact(seed):
    rng = np.random.default_rng(seed)
    t = t_axis(0.9)
    puff = lowpass(rng.standard_normal(len(t)), 900) * np.exp(-t / 0.07) * 1.2
    air = bandpass(rng.standard_normal(len(t)), 2000, 9000, 2) * np.exp(-t / 0.2) * 0.5
    ting = sum(np.sin(2 * np.pi * note(n) * t) * np.exp(-t / 0.25) * a for n, a in ((7, 0.25), (14, 0.12)))
    return normalize(fade(reverb(puff + air + ting, rng, 0.9, 0.3, 8000), 0.001, 0.2), -4)


def tornado(seed):
    rng = np.random.default_rng(seed)
    t = t_axis(2.2)
    up = np.clip(t / 1.2, 0, 1)
    x = np.zeros_like(t)
    noise = rng.standard_normal(len(t))
    for k, (lo, hi) in enumerate(((200, 700), (600, 1800), (1500, 5000))):
        rate = 2 + 9 * up
        w = 0.5 + 0.5 * np.sin(2 * np.pi * np.cumsum(rate) / SR + k * 2.1)
        x += bandpass(noise, lo, hi, 2) * w
    x *= np.clip(t / 0.15, 0, 1) * np.exp(-np.clip(t - 1.4, 0, None) / 0.3)
    x += lowpass(rng.standard_normal(len(t)), 140) * np.exp(-t / 0.15) * 1.2
    return normalize(fade(reverb(x, rng, 1.2, 0.3, 7000), 0.002, 0.3), -2)


def charge_loop(seed):
    rng = np.random.default_rng(seed)
    t = t_axis(4.5)
    x = gust(rng, t, 300, 4000, 1.6) * 0.8
    x = highpass(x, 150, 2)
    return normalize(loopable(reverb(x, rng, 0.8, 0.2, 7000), 0.5), -8)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", type=Path, default=Path(__file__).resolve().parent.parent / "game" / "audio" / "sfx")
    out = ap.parse_args().out
    write(out, "sfx_wind_cast_01", wind_cast(901, 1.0))
    write(out, "sfx_wind_cast_02", wind_cast(902, 1.15))
    write(out, "sfx_wind_impact_01", wind_impact(903))
    write(out, "sfx_tornado_01", tornado(904))
    write(out, "amb_wind_charge_loop", charge_loop(905))


if __name__ == "__main__":
    main()
