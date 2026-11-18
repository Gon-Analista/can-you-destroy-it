#!/usr/bin/env python3
"""Sonidos de los elementos Rayo y Tierra y de sus combinaciones.

Uso:
    python3 tools/sfx_combos.py            # escribe en game/audio/sfx
    python3 tools/sfx_combos.py --out DIR

- sfx_bolt_cast_01/02: chasquido eléctrico seco con zumbido que sube.
- sfx_bolt_impact_01: crepitar de chispas.
- sfx_earth_cast_01/02: golpe sordo y piedra que rueda (lanzar una roca encantada).
- sfx_earth_impact_01: roca contra cristal: crujido grave y piedrecitas.
- sfx_thunder_01: el Juicio del Trueno: latigazo blanco, rasgado y un trueno que rueda largo.
- sfx_meteor_fall_01: el Meteoro cayendo: rugido que crece y baja de tono.
- sfx_quake_01: terremoto: retumbe grave con golpes de roca.
- sfx_magnet_01: magnetismo: barrido metálico que sube.
- sfx_ice_lance_01: lanza de hielo: silbido cortante con brillo cristalino.
- amb_plasma_loop: zumbido de plasma en bucle (Haz de Plasma).
- amb_sky_charge_loop: carga de los hechizos del cielo: coro grave, viento y un acorde que sube.
- amb_storm_charge_loop: carga eléctrica: crepitar y zumbido.
Deterministas: semillas fijas.
"""
import argparse
from pathlib import Path

import numpy as np

from sfx_synth import (SR, bandpass, bell, fade, highpass, loopable, lowpass, normalize, note, reverb,
                       t_axis, write)


def crackle(rng, n, density=0.004, lo=2000, hi=9000):
    x = np.zeros(n)
    hits = rng.random(n) < density
    x[hits] = rng.uniform(-1, 1, hits.sum())
    return bandpass(x, lo, hi, 2) * 4.0


def bolt_cast(seed):
    rng = np.random.default_rng(seed)
    t = t_axis(0.45)
    zap = crackle(rng, len(t), 0.03) * np.exp(-t / 0.06)
    buzz = np.sign(np.sin(2 * np.pi * (180 + 900 * t) * t)) * np.exp(-t / 0.12) * 0.25
    x = zap + bandpass(buzz, 300, 4000, 2)
    return normalize(fade(reverb(x, rng, 0.3, 0.15), 0.001, 0.05), -3)


def bolt_impact(seed):
    rng = np.random.default_rng(seed)
    t = t_axis(0.6)
    x = crackle(rng, len(t), 0.02) * np.exp(-t / 0.15)
    x += lowpass(rng.standard_normal(len(t)), 300) * np.exp(-t / 0.05) * 0.8
    return normalize(fade(reverb(x, rng, 0.4, 0.2), 0.001, 0.08), -3)


def earth_cast(seed):
    rng = np.random.default_rng(seed)
    t = t_axis(0.7)
    thud = lowpass(rng.standard_normal(len(t)), 160) * np.exp(-t / 0.07) * 2.5
    roll = bandpass(rng.standard_normal(len(t)), 200, 900, 2) * np.exp(-t / 0.3) * 0.5
    whoosh = bandpass(rng.standard_normal(len(t)), 300, 1500, 2) * np.sin(np.pi * np.clip(t / 0.5, 0, 1)) * 0.4
    return normalize(fade(thud + roll + whoosh, 0.002, 0.1), -3)


def earth_impact(seed):
    rng = np.random.default_rng(seed)
    t = t_axis(0.9)
    x = lowpass(rng.standard_normal(len(t)), 220) * np.exp(-t / 0.1) * 2.0
    for _ in range(18):
        s0 = rng.integers(0, int(0.5 * SR))
        n = int(rng.uniform(0.005, 0.02) * SR)
        x[s0:s0 + n] += bandpass(rng.standard_normal(n), 800, 3500, 2) * np.hanning(n) * rng.uniform(0.2, 0.6)
    return normalize(fade(reverb(x, rng, 0.5, 0.2), 0.001, 0.1), -3)


def thunder(seed):
    rng = np.random.default_rng(seed)
    dur = 4.5
    t = t_axis(dur)
    crack = crackle(rng, len(t), 0.08, 1500, 10000) * np.exp(-t / 0.05) * 1.2
    rip = bandpass(rng.standard_normal(len(t)), 800, 6000, 2) * np.exp(-t / 0.18)
    rumble_env = np.clip(t / 0.15, 0, 1) * np.exp(-t / 1.4) * (1 + 0.4 * np.sin(2 * np.pi * 3.1 * t) ** 2)
    rumble = lowpass(rng.standard_normal(len(t)), 120) * rumble_env * 3.0
    x = crack + rip + rumble
    return normalize(fade(reverb(x, rng, 1.8, 0.35), 0.001, 0.8), -1)


def meteor_fall(seed):
    rng = np.random.default_rng(seed)
    dur = 1.6
    t = t_axis(dur)
    env = np.clip(t / dur, 0, 1) ** 1.6
    hi = 3000 - 2200 * np.clip(t / dur, 0, 1)
    noise = rng.standard_normal(len(t))
    x = np.zeros_like(t)
    # Banda que baja: tres tramos filtrados mezclados por el tiempo.
    for k, (lo, h) in enumerate(((1200, 4000), (500, 1800), (150, 700))):
        w = np.clip(1 - np.abs(np.clip(t / dur, 0, 1) * 2 - k), 0, 1)
        x += bandpass(noise, lo, h, 2) * w
    x += lowpass(noise, 120) * env * 1.5
    x *= env
    del hi
    return normalize(fade(x, 0.05, 0.01), -2)


def quake(seed):
    rng = np.random.default_rng(seed)
    dur = 2.8
    t = t_axis(dur)
    env = np.clip(t / 0.3, 0, 1) * np.exp(-t / 1.0)
    x = lowpass(rng.standard_normal(len(t)), 80) * env * 3.5
    for k in range(6):
        s0 = int((0.1 + k * 0.28 + rng.uniform(0, 0.08)) * SR)
        tt = t[: len(t) - s0]
        x[s0:] += lowpass(rng.standard_normal(len(tt)), 250) * np.exp(-tt / 0.08) * 1.2 * (1 - k * 0.12)
    return normalize(fade(x, 0.01, 0.5), -2)


def magnet(seed):
    rng = np.random.default_rng(seed)
    dur = 1.4
    t = t_axis(dur)
    f = 220 * 2 ** (2 * t / dur)
    ph = 2 * np.pi * np.cumsum(f) / SR
    x = (np.sin(ph) + 0.5 * np.sin(2 * ph) + 0.3 * np.sin(3.01 * ph)) * np.sin(np.pi * t / dur) * 0.5
    x += crackle(rng, len(t), 0.006) * 0.3
    return normalize(fade(reverb(x, rng, 0.6, 0.25), 0.02, 0.2), -4)


def ice_lance(seed):
    rng = np.random.default_rng(seed)
    t = t_axis(0.9)
    whistle = bandpass(rng.standard_normal(len(t)), 2500, 7000, 2) * np.exp(-t / 0.2)
    x = whistle * 0.8
    for i, n_ in enumerate((12, 16, 19, 24)):
        s0 = int(i * 0.03 * SR)
        tt = t[: len(t) - s0]
        x[s0:] += bell(tt, note(n_), [1.0, 2.76], [1.0, 0.3], [0.4, 0.15], rng) * 0.25
    return normalize(fade(reverb(x, rng, 0.6, 0.3), 0.001, 0.15), -3)


def plasma_loop(seed):
    rng = np.random.default_rng(seed)
    dur = 2.0
    t = t_axis(dur)
    buzz = np.sign(np.sin(2 * np.pi * 110 * t)) * 0.3 + np.sin(2 * np.pi * 220.7 * t) * 0.3
    x = bandpass(buzz, 150, 3000, 2) * (0.8 + 0.2 * np.sin(2 * np.pi * 9 * t))
    x += crackle(rng, len(t), 0.01) * 0.4
    return normalize(loopable(x, 0.4), -6)


def sky_charge_loop(seed):
    rng = np.random.default_rng(seed)
    dur = 4.0
    t = t_axis(dur)
    wind = bandpass(rng.standard_normal(len(t)), 200, 1200, 2) * (0.6 + 0.4 * np.sin(2 * np.pi * 0.5 * t))
    x = wind * 0.5
    for n_, a in ((-36, 0.4), (-29, 0.3), (-24, 0.25), (-17, 0.15)):
        f = note(n_)
        vib = 1 + 0.003 * np.sin(2 * np.pi * 4.8 * t + rng.uniform(0, 6))
        ph = 2 * np.pi * np.cumsum(f * vib) / SR
        x += (np.sin(ph) + 0.25 * np.sin(2 * ph)) * a
    return normalize(loopable(x, 0.8), -6)


def storm_charge_loop(seed):
    rng = np.random.default_rng(seed)
    dur = 3.0
    t = t_axis(dur)
    x = crackle(rng, len(t), 0.012) * 0.6
    x += bandpass(np.sign(np.sin(2 * np.pi * 60 * t)), 60, 600, 2) * 0.3
    x += lowpass(rng.standard_normal(len(t)), 100) * 0.5
    return normalize(loopable(x, 0.5), -6)


def main() -> None:
    ap = argparse.ArgumentParser()
    root = Path(__file__).resolve().parent.parent
    ap.add_argument("--out", default=str(root / "game" / "audio" / "sfx"))
    out = Path(ap.parse_args().out)
    write(out, "sfx_bolt_cast_01", bolt_cast(1201))
    write(out, "sfx_bolt_cast_02", bolt_cast(1202))
    write(out, "sfx_bolt_impact_01", bolt_impact(1203))
    write(out, "sfx_earth_cast_01", earth_cast(1211))
    write(out, "sfx_earth_cast_02", earth_cast(1212))
    write(out, "sfx_earth_impact_01", earth_impact(1213))
    write(out, "sfx_thunder_01", thunder(1221))
    write(out, "sfx_meteor_fall_01", meteor_fall(1231))
    write(out, "sfx_quake_01", quake(1241))
    write(out, "sfx_magnet_01", magnet(1251))
    write(out, "sfx_ice_lance_01", ice_lance(1261))
    write(out, "amb_plasma_loop", plasma_loop(1271))
    write(out, "amb_sky_charge_loop", sky_charge_loop(1281))
    write(out, "amb_storm_charge_loop", storm_charge_loop(1291))


if __name__ == "__main__":
    main()
