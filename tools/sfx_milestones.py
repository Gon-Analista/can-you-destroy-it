#!/usr/bin/env python3
"""Sonidos de los tres nodos hito del Grimorio (GDD 7): Canalización, Vórtice y Facetas.

Uso:
    python3 tools/sfx_milestones.py            # escribe en game/audio/sfx
    python3 tools/sfx_milestones.py --out DIR

- amb_autocast_crackle_loop: el crepitar sostenido de la mano que lanza en ráfaga (mantener
  pulsado): chasquidos eléctricos al azar sobre un zumbido en La (La3 + Mi4) que tiembla. 4 s,
  empalma solo (activar loop en la importación).
- sfx_autocast_start_01: la mano entra en ráfaga: "zzzip" que sube y una chispa aguda.
- sfx_autocast_pulse_01/02/03: el latido del orbe en cada lanzamiento en ráfaga (corto, suave;
  suena encima del lanzamiento de siempre sin taparlo).
- amb_vortex_loop: el Vórtice de maná girando: viento en espiral (ruido con el centro que da
  vueltas), un remolino grave y destellos de cristal en la pentatónica de La. 6 s en bucle.
- sfx_vortex_catch_01/02/03: un fragmento entra en el remolino ("fwip" con campanita).
- sfx_vortex_awaken_01: el Vórtice despierta (primera vez tras inscribirlo): ráfaga que sube y
  acorde de La mayor que se abre.
- sfx_facet_break_01/02: un golpe resonante rompe una faceta entera: crujido grave y profundo,
  chasquidos que corren por la grieta y la losa que se desliza rascando.
- sfx_facet_crash_01: la losa cae y revienta en el suelo: estruendo de cristal y cascada de
  esquirlas.
Deterministas: semillas fijas. Todo en La mayor o su pentatónica (como el "tink" del cristal).
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

GLASS = [1.0, 2.0, 3.01, 4.2, 5.4]
GLASS_AMPS = [1.0, 0.4, 0.2, 0.1, 0.05]
PENTA = [0, 2, 4, 7, 9, 12, 14, 16, 19]


def crackle_pops(n_samples: int, rng, rate: float, gain: float, lo: float = 1800.0) -> np.ndarray:
    """Chasquidos eléctricos: ráfagas cortísimas de ruido filtrado, al azar (Poisson)."""
    x = np.zeros(n_samples)
    n = rng.poisson(rate * n_samples / SR)
    for _ in range(n):
        s0 = rng.integers(0, max(1, n_samples - 600))
        ln = int(rng.uniform(0.002, 0.012) * SR)
        burst = rng.standard_normal(ln) * np.exp(-np.arange(ln) / (ln * 0.25))
        x[s0 : s0 + ln] += burst * rng.uniform(0.3, 1.0)
    return highpass(x, lo, 2) * gain


def autocast_loop(seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    dur = 4.0
    t = t_axis(dur + 0.5)
    # Zumbido en La con ciclos casi enteros y temblor rápido (la mano tiembla).
    hum = np.zeros_like(t)
    for f, a in [(220.0, 1.0), (330.0, 0.5), (440.0, 0.25), (660.0, 0.12)]:
        hum += np.sin(2 * np.pi * f * t + rng.uniform(0, 6)) * a
    trem = 0.7 + 0.3 * np.sin(2 * np.pi * 9.0 * t) * np.sin(2 * np.pi * 0.5 * t + 1.0)
    hum *= trem * 0.12
    # Chasquidos densos y una "lluvia" fina de electricidad.
    pops = crackle_pops(len(t), rng, 38.0, 0.55)
    fizz = bandpass(rng.standard_normal(len(t)), 3500, 9000, 2) * 0.05
    fizz *= 0.6 + 0.4 * np.abs(np.sin(2 * np.pi * 3.3 * t))
    x = hum + pops + fizz
    return normalize(loopable(x, 0.5), -6)


def autocast_start(seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    t = t_axis(0.8)
    f = 180 + 1400 * (t / 0.35) ** 1.6
    f = np.minimum(f, 1580)
    zip_ = np.sign(np.sin(2 * np.pi * np.cumsum(f) / SR)) * np.exp(-t / 0.3) * 0.12
    zip_ = lowpass(zip_, 4000, 2)
    x = zip_ + crackle_pops(len(t), rng, 60.0, 0.5) * np.exp(-t / 0.25)
    s0 = int(0.3 * SR)
    tt = t[: len(t) - s0]
    x[s0:] += bell(tt, note(7), GLASS, GLASS_AMPS, [0.4, 0.25, 0.15, 0.1, 0.05], rng, 0.001) * 0.35
    return normalize(fade(reverb(x, rng, 0.6, 0.25), 0.002, 0.1), -3)


def autocast_pulse(seed: int, n: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    t = t_axis(0.35)
    # Golpe suave de aire y un "tic" eléctrico; nota de la pentatónica que cambia por variante.
    thump = np.sin(2 * np.pi * (140 + 160 * np.exp(-t / 0.02)) * t) * np.exp(-t / 0.05) * 0.5
    tick = crackle_pops(len(t), rng, 40.0, 0.4) * np.exp(-t / 0.06)
    x = thump + tick
    x += bell(t, note(PENTA[n] - 12), [1.0, 2.0, 3.0], [1.0, 0.25, 0.1], [0.12, 0.07, 0.04], rng, 0.001) * 0.18
    return normalize(fade(x, 0.001, 0.05), -6)


def whirl(t: np.ndarray, rng, period: float, lo: float, hi: float) -> np.ndarray:
    """Viento que gira: ruido por bancos cuyo peso da vueltas (el centro sube y baja)."""
    noise = rng.standard_normal(len(t))
    out = np.zeros_like(t)
    bands = [(lo * (hi / lo) ** (k / 5), lo * (hi / lo) ** ((k + 1) / 5)) for k in range(5)]
    for k, (a, b) in enumerate(bands):
        w = 0.5 + 0.5 * np.cos(2 * np.pi * (t / period - k / 5))
        out += bandpass(noise, a, b, 2) * w ** 2
    return out


def vortex_loop(seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    dur = 6.0
    t = t_axis(dur + 0.6)
    wind = whirl(t, rng, 1.5, 250, 4200) * 0.9
    # Remolino grave: un seno que respira (un ciclo entero cada 3 s) y su quinta.
    low = (np.sin(2 * np.pi * 55.0 * t) + 0.5 * np.sin(2 * np.pi * 82.5 * t)) * 0.18
    low *= 0.7 + 0.3 * np.sin(2 * np.pi * t / 3.0)
    x = wind / (np.max(np.abs(wind)) + 1e-9) * 0.7 + low
    # Destellos de cristal sueltos (pentatónica de La, aguda y suave).
    for _ in range(9):
        s0 = int(rng.uniform(0.2, dur) * SR)
        tt = t[: len(t) - s0]
        n = PENTA[rng.integers(0, len(PENTA))]
        x[s0:] += bell(tt, note(n), [1.0, 2.0, 3.0], [1.0, 0.2, 0.08], [0.5, 0.3, 0.15], rng, 0.003) * 0.06
    return normalize(loopable(reverb(x, rng, 1.0, 0.2), 0.6), -7)


def vortex_catch(seed: int, n: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    t = t_axis(0.5)
    env = np.exp(-((t - 0.08) / 0.06) ** 2)
    f = 900 + 2200 * np.clip(t / 0.15, 0, 1)
    fwip = bandpass(rng.standard_normal(len(t)), 700, 5000, 2) * env * 0.8
    fwip += np.sin(2 * np.pi * np.cumsum(f) / SR) * env * 0.05
    s0 = int(0.09 * SR)
    tt = t[: len(t) - s0]
    fwip[s0:] += bell(tt, note(PENTA[n + 3]), [1.0, 2.0, 3.0], [1.0, 0.3, 0.1], [0.22, 0.12, 0.06], rng, 0.001) * 0.3
    return normalize(fade(reverb(fwip, rng, 0.5, 0.2), 0.002, 0.08), -4)


def vortex_awaken(seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    t = t_axis(3.2)
    rise = whirl(t, rng, 0.45, 200, 6000)
    rise = rise / (np.max(np.abs(rise)) + 1e-9) * np.clip(t / 1.2, 0, 1) ** 1.5 * np.exp(-np.maximum(t - 1.3, 0) / 0.6)
    x = rise * 0.8
    for k, (n, a) in enumerate([(-24, 1.0), (-20, 0.7), (-17, 0.6), (-12, 0.5), (-8, 0.4), (-5, 0.35)]):
        s0 = int((1.15 + k * 0.06) * SR)
        tt = t[: len(t) - s0]
        x[s0:] += bell(tt, note(n), GLASS, GLASS_AMPS, [1.6, 1.0, 0.6, 0.35, 0.2], rng, 0.002) * a * 0.35
    s0 = int(1.15 * SR)
    tt = t[: len(t) - s0]
    x[s0:] += np.sin(2 * np.pi * 55.0 * tt) * np.exp(-tt / 0.6) * 0.5
    return normalize(fade(reverb(x, rng, 1.8, 0.35), 0.002, 0.4), -1.5)


def facet_break(seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    t = t_axis(2.4)
    # Crujido grave: golpe de 45-60 Hz que baja de tono, con cuerpo de roca.
    f = 48 * (1.0 + 1.6 * np.exp(-t / 0.03))
    boom = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.45) * 1.0
    boom += lowpass(rng.standard_normal(len(t)), 180, 2) * np.exp(-t / 0.25) * 1.4
    # La grieta corre: chasquidos que se aceleran y se alejan (de grave a agudo).
    crack = np.zeros_like(t)
    tk = 0.0
    k = 0
    while tk < 0.7:
        s0 = int(tk * SR)
        ln = int(rng.uniform(0.004, 0.02) * SR)
        burst = rng.standard_normal(ln) * np.exp(-np.arange(ln) / (ln * 0.3))
        crack[s0 : s0 + ln] += burst * (1.0 - tk) * rng.uniform(0.5, 1.0)
        tk += rng.uniform(0.008, 0.05) * (1.0 - 0.6 * tk)
        k += 1
    crack = bandpass(crack, 900, 7000, 2) * 0.9
    # La losa se desliza rascando (ruido grave modulado) y tintineo de cristal al despegarse.
    s0 = int(0.25 * SR)
    tt = t[: len(t) - s0]
    scrape = bandpass(rng.standard_normal(len(tt)), 120, 900, 2)
    scrape *= np.clip(tt / 0.2, 0, 1) * np.exp(-tt / 0.9) * (0.7 + 0.3 * np.sin(2 * np.pi * 13 * tt))
    x = boom + crack
    x[s0:] += scrape * 0.7
    for i, n in enumerate([-24, -17, -12]):
        s1 = int((0.03 + i * 0.05) * SR)
        tt = t[: len(t) - s1]
        x[s1:] += bell(tt, note(n), GLASS, GLASS_AMPS, [1.2, 0.8, 0.5, 0.3, 0.2], rng, 0.002) * 0.25
    return normalize(fade(reverb(x, rng, 1.6, 0.3), 0.001, 0.4), -1.0)


def facet_crash(seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    t = t_axis(2.2)
    thud = lowpass(rng.standard_normal(len(t)), 220, 2) * np.exp(-t / 0.18) * 1.6
    thud += np.sin(2 * np.pi * 62 * t) * np.exp(-t / 0.3) * 0.6
    # Cascada de esquirlas: muchas campanitas cortas y agudas que caen en el tiempo.
    shards = np.zeros_like(t)
    for i in range(70):
        s0 = int(abs(rng.normal(0.0, 0.25)) * SR)
        if s0 >= len(t) - 100:
            continue
        tt = t[: len(t) - s0]
        n = PENTA[rng.integers(0, len(PENTA))] + 12 * int(rng.integers(0, 2))
        shards[s0:] += bell(tt, note(n) * rng.uniform(0.99, 1.01), [1.0, 2.3, 3.7], [1.0, 0.4, 0.2], [0.12, 0.06, 0.03], rng, 0.0005) * rng.uniform(0.1, 0.3)
    smash = highpass(rng.standard_normal(len(t)), 2500, 2) * np.exp(-t / 0.12) * 0.6
    x = thud + shards + smash
    return normalize(fade(reverb(x, rng, 1.3, 0.3), 0.001, 0.4), -1.0)


def main() -> None:
    ap = argparse.ArgumentParser()
    root = Path(__file__).resolve().parent.parent
    ap.add_argument("--out", default=str(root / "game" / "audio" / "sfx"))
    out = Path(ap.parse_args().out)
    write(out, "amb_autocast_crackle_loop", autocast_loop(1701))
    write(out, "sfx_autocast_start_01", autocast_start(1711))
    for i in range(3):
        write(out, f"sfx_autocast_pulse_{i + 1:02d}", autocast_pulse(1721 + i, i))
    write(out, "amb_vortex_loop", vortex_loop(1731))
    for i in range(3):
        write(out, f"sfx_vortex_catch_{i + 1:02d}", vortex_catch(1741 + i, i))
    write(out, "sfx_vortex_awaken_01", vortex_awaken(1751))
    for i in range(2):
        write(out, f"sfx_facet_break_{i + 1:02d}", facet_break(1761 + i))
    write(out, "sfx_facet_crash_01", facet_crash(1771))


if __name__ == "__main__":
    main()
