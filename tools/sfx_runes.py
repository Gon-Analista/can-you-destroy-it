#!/usr/bin/env python3
"""Sonidos de las runas (GDD 5.3) y de la Mesa de Runas (GDD 4.3).

Uso:
    python3 tools/sfx_runes.py            # escribe en game/audio/sfx
    python3 tools/sfx_runes.py --out DIR

- sfx_rune_multishot_01/02: abanico de chispas: tres o cuatro silbidos cortos seguidos, cada uno
  con una campanita dorada un poco más aguda.
- sfx_rune_bounce_01..03: rebote en una faceta: "ping" de cristal muy corto con un glissando
  que sube (la chispa sale despedida) y un chasquido.
- sfx_rune_pierce_01/02: perforación: golpe sordo que entra, crujido de cristal que se abre por
  dentro y un zumbido que baja (atraviesa capas).
- sfx_rune_echo_01/02: el eco: un soplo que crece al revés y una campana con dos repeticiones.
- sfx_rune_harvest_01/02: la Cosecha: un susurro de hojas y dos notas de moneda que suben.
- sfx_rune_inscribe_01: inscribir una runa: cincel en la piedra y el glifo que se enciende.
- sfx_rune_erase_01: borrarla: un barrido suave y dos notas que bajan.
- sfx_rune_buy_01: subir de nivel una runa: campanas que suben con el cincel.
- sfx_rune_table_open_01 / sfx_rune_table_close_01: la losa de la mesa se aparta (o se cierra).
- sfx_rune_unseal_01: la mesa despierta al 10 % del Pilón: cadenas que saltan y un acorde.
- amb_rune_table_hum_loop: zumbido de la mesa (ciclos enteros: empalma solo).
Todo en La mayor / pentatónica de La. Deterministas: semillas fijas.
"""
import argparse
from pathlib import Path

import numpy as np

from sfx_synth import SR, bandpass, bell, fade, highpass, lowpass, normalize, note, reverb, t_axis, write

# Pentatónica de La (semitonos sobre A5).
PENTA = [0, 2, 4, 7, 9, 12, 14, 16, 19, 21, 24]


def _place(x: np.ndarray, y: np.ndarray, at: float, gain: float = 1.0) -> None:
    start = int(at * SR)
    n = min(len(y), len(x) - start)
    if n > 0:
        x[start:start + n] += y[:n] * gain


def whoosh(dur: float, lo: float, hi: float, rng, rise: bool = True) -> np.ndarray:
    """Soplo de ruido filtrado cuya banda sube (o baja)."""
    t = t_axis(dur)
    noise = rng.standard_normal(len(t))
    out = np.zeros_like(t)
    steps = 12
    for k in range(steps):
        a, b = k / steps, (k + 1) / steps
        f = lo + (hi - lo) * (a if rise else 1 - a)
        seg = slice(int(a * len(t)), int(b * len(t)))
        out[seg] = bandpass(noise, max(80.0, f * 0.6), min(18000.0, f * 1.6), 2)[seg]
    env = np.sin(np.pi * np.clip(t / dur, 0, 1)) ** 1.5
    return out * env


def multishot(seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    t = t_axis(0.75)
    x = np.zeros_like(t)
    count = 3 + seed % 2
    for k in range(count):
        at = 0.012 + k * 0.055
        _place(x, whoosh(0.16, 1500 + 400 * k, 5200 + 600 * k, rng), at, 0.55)
        tt = t_axis(0.5)
        n = PENTA[3 + k] + 12
        _place(x, bell(tt, note(n - 12), [1.0, 2.0, 3.01], [1.0, 0.35, 0.12], [0.22, 0.1, 0.05], rng), at + 0.02, 0.32)
    x += highpass(rng.standard_normal(len(t)), 6000) * np.exp(-t / 0.01) * 0.25
    return normalize(fade(reverb(x, rng, 0.6, 0.2), 0.001, 0.08), -3)


def bounce(seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    t = t_axis(0.5)
    f0 = note(PENTA[2 + seed % 3])
    # "Ping" con glissando hacia arriba: la chispa sale despedida.
    glide = f0 * (1.0 + 0.35 * (1 - np.exp(-t / 0.06)))
    ph = 2 * np.pi * np.cumsum(glide) / SR
    ping = (np.sin(ph) + 0.4 * np.sin(2.32 * ph) + 0.15 * np.sin(4.25 * ph)) * np.exp(-t / 0.09)
    click = highpass(rng.standard_normal(len(t)), 4000) * np.exp(-t / 0.003) * 0.8
    chip = bandpass(rng.standard_normal(len(t)), 3000, 9000) * np.exp(-t / 0.02) * 0.3
    x = ping * 0.7 + click + chip
    return normalize(fade(reverb(x, rng, 0.45, 0.18), 0.0005, 0.06), -3)


def pierce(seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    t = t_axis(1.1)
    # Golpe sordo que entra.
    thump_f = 70 * (1 + 1.2 * np.exp(-t / 0.03))
    thump = np.sin(2 * np.pi * np.cumsum(thump_f) / SR) * np.exp(-t / 0.12)
    x = thump * 0.9
    x += lowpass(rng.standard_normal(len(t)), 900) * np.exp(-t / 0.05) * 0.5
    # Crujido de cristal por dentro: granos a lo largo del túnel.
    grains = np.zeros_like(t)
    for k in range(26):
        at = 0.03 + k * 0.012 + rng.uniform(0, 0.01)
        n = int(rng.uniform(0.002, 0.007) * SR)
        g = rng.standard_normal(n) * np.hanning(n) * (1.0 - k / 30)
        _place(grains, g, at)
    x += bandpass(grains, 1200, 7000) * 1.1
    # Zumbido que baja: atraviesa capas.
    hum_f = note(-12) * (1.4 - 0.5 * np.clip(t / 0.7, 0, 1))
    hum = np.sin(2 * np.pi * np.cumsum(hum_f) / SR)
    hum += 0.5 * np.sin(2 * np.pi * np.cumsum(hum_f * 1.5) / SR)
    x += hum * np.clip(t / 0.04, 0, 1) * np.exp(-t / 0.35) * 0.35
    return normalize(fade(reverb(x, rng, 0.8, 0.22, 4000), 0.0005, 0.12), -2)


def echo(seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    t = t_axis(1.3)
    x = np.zeros_like(t)
    # Soplo que crece "al revés" (el fantasma que llega).
    sw = whoosh(0.32, 600, 3800, rng)
    sw *= np.linspace(0.2, 1.0, len(sw)) ** 2
    _place(x, sw, 0.0, 0.6)
    n = PENTA[4 + seed % 2]
    tt = t_axis(0.9)
    b = bell(tt, note(n - 12), [1.0, 2.0, 3.01, 4.2], [1.0, 0.3, 0.12, 0.05], [0.6, 0.3, 0.15, 0.08], rng)
    for k, (at, g) in enumerate([(0.3, 0.55), (0.48, 0.28), (0.66, 0.14)]):
        _place(x, b * (0.85 ** k), at, g)
    return normalize(fade(reverb(x, rng, 1.0, 0.32), 0.003, 0.15), -4)


def harvest(seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    t = t_axis(0.8)
    x = np.zeros_like(t)
    # Susurro de hojas: ráfagas de ruido de banda media.
    rustle = np.zeros_like(t)
    for _ in range(18):
        at = rng.uniform(0.0, 0.25)
        n = int(rng.uniform(0.01, 0.03) * SR)
        _place(rustle, rng.standard_normal(n) * np.hanning(n) * rng.uniform(0.3, 1.0), at)
    x += bandpass(rustle, 2500, 9000) * 0.5
    # Dos notas de moneda que suben (Mi, La).
    tt = t_axis(0.6)
    for i, n in enumerate([7 + (seed % 2) * 2, 12 + (seed % 2) * 2]):
        coin = bell(tt, note(n), [1.0, 2.76, 5.4], [1.0, 0.4, 0.2], [0.25, 0.1, 0.05], rng, 0.002)
        _place(x, coin, 0.05 + i * 0.09, 0.45)
    return normalize(fade(reverb(x, rng, 0.5, 0.2), 0.001, 0.08), -5)


def chisel(dur: float, rng, hits: int = 5) -> np.ndarray:
    t = t_axis(dur)
    x = np.zeros_like(t)
    for k in range(hits):
        at = 0.01 + k * dur / (hits + 1) + rng.uniform(0, 0.01)
        n = int(0.025 * SR)
        g = rng.standard_normal(n) * np.exp(-np.arange(n) / SR / 0.006)
        _place(x, g, at, rng.uniform(0.6, 1.0))
    return bandpass(x, 1500, 8000)


def inscribe(seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    t = t_axis(1.4)
    x = np.zeros_like(t)
    _place(x, chisel(0.28, rng), 0.0, 0.8)
    # El glifo se enciende: acorde de La que sube con brillo.
    tt = t_axis(1.1)
    for i, n in enumerate([0, 4, 7, 12]):
        b = bell(tt, note(n - 12), [1.0, 2.0, 3.01], [1.0, 0.3, 0.1], [0.9, 0.4, 0.2], rng)
        _place(x, b, 0.26 + i * 0.05, 0.3)
    shimmer = bandpass(rng.standard_normal(len(t)), 7000, 15000) * np.exp(-np.maximum(t - 0.3, 0) / 0.35)
    x += shimmer * np.clip((t - 0.25) / 0.05, 0, 1) * 0.12
    return normalize(fade(reverb(x, rng, 1.1, 0.3), 0.001, 0.15), -3)


def erase(seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    t = t_axis(0.9)
    x = np.zeros_like(t)
    _place(x, whoosh(0.35, 4200, 900, rng, rise=False), 0.0, 0.5)
    tt = t_axis(0.7)
    for i, n in enumerate([7, 0]):
        b = bell(tt, note(n - 12), [1.0, 2.0, 3.01], [1.0, 0.3, 0.1], [0.4, 0.2, 0.1], rng)
        _place(x, b, 0.08 + i * 0.12, 0.32)
    return normalize(fade(reverb(x, rng, 0.8, 0.25), 0.002, 0.12), -5)


def buy(seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    t = t_axis(1.5)
    x = np.zeros_like(t)
    _place(x, chisel(0.2, rng, 3), 0.0, 0.6)
    tt = t_axis(1.0)
    for i, n in enumerate([0, 4, 7, 12, 16]):
        b = bell(tt, note(n - 12), [1.0, 2.0, 3.01, 4.2], [1.0, 0.3, 0.12, 0.05], [0.7, 0.35, 0.15, 0.08], rng)
        _place(x, b, 0.12 + i * 0.06, 0.3)
    return normalize(fade(reverb(x, rng, 1.2, 0.3), 0.001, 0.2), -3)


def slab(up: bool, seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    dur = 1.1 if up else 0.7
    t = t_axis(dur)
    # Piedra que se arrastra.
    grind = lowpass(rng.standard_normal(len(t)), 700) * (0.6 + 0.4 * np.sin(2 * np.pi * 23 * t))
    env = np.clip(t / 0.05, 0, 1) * np.exp(-t / (0.35 if up else 0.2))
    x = grind * env * 0.7
    # Destellos de las runas al despertar (o apagarse).
    tt = t_axis(0.8)
    notes = [0, 7, 12, 19] if up else [12, 7, 0]
    for i, n in enumerate(notes):
        b = bell(tt, note(n - 12), [1.0, 2.0, 3.01], [1.0, 0.3, 0.1], [0.6, 0.3, 0.15], rng)
        _place(x, b, (0.15 if up else 0.02) + i * 0.07, 0.28)
    return normalize(fade(reverb(x, rng, 1.0, 0.3), 0.003, 0.15), -4)


def unseal(seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    t = t_axis(3.2)
    x = np.zeros_like(t)
    # Cadenas que saltan: eslabones metálicos.
    for k in range(9):
        at = 0.05 + k * 0.045 + rng.uniform(0, 0.02)
        tt = t_axis(0.25)
        link = bell(tt, rng.uniform(1800, 3200), [1.0, 2.4, 3.9], [1.0, 0.5, 0.3], [0.06, 0.04, 0.02], rng, 0.02)
        _place(x, link, at, 0.5)
    # Golpe y acorde de La mayor que crece (coro sintético).
    boom_f = 55 * (1 + 0.8 * np.exp(-t / 0.04))
    x += np.sin(2 * np.pi * np.cumsum(boom_f) / SR) * np.exp(-t / 0.4) * 0.7
    chord = np.zeros_like(t)
    for n, a in [(-36, 1.0), (-29, 0.7), (-24, 0.8), (-20, 0.55), (-17, 0.45)]:
        f = note(n)
        for det in (-0.004, 0.0, 0.004):
            vib = 1 + det + 0.005 * np.sin(2 * np.pi * 5.0 * t + rng.uniform(0, 6))
            ph = 2 * np.pi * np.cumsum(f * vib) / SR
            chord += a * (np.sin(ph) + 0.35 * np.sin(2 * ph)) / 3
    env = np.clip((t - 0.3) / 0.7, 0, 1) * np.exp(-np.maximum(t - 1.8, 0) / 0.7)
    x += bandpass(chord, 120, 3500, 2) * env * 0.5
    tt = t_axis(1.4)
    for i, n in enumerate([0, 4, 7, 12, 16, 19]):
        b = bell(tt, note(n - 12), [1.0, 2.0, 3.01], [1.0, 0.3, 0.1], [0.8, 0.4, 0.2], rng)
        _place(x, b, 0.55 + i * 0.08, 0.25)
    return normalize(fade(reverb(x, rng, 1.6, 0.35), 0.002, 0.3), -2)


def table_hum(seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    dur = 6.0
    t = t_axis(dur)
    # Ciclos enteros en 6 s: La grave y Mi, con un batido lento y motas que titilan.
    freqs = [110.0, 165.0, 220.0 + 1 / 6, 330.0 - 1 / 6, 1760.0 + 1 / 3]
    amps = [0.5, 0.4, 0.3, 0.18, 0.03]
    x = np.zeros_like(t)
    for f, a in zip(freqs, amps):
        x += a * np.sin(2 * np.pi * f * t + rng.uniform(0, 2 * np.pi))
    lfo = 0.8 + 0.2 * np.sin(2 * np.pi * t / 2.0)
    return normalize(x * lfo, -14)


def main() -> None:
    ap = argparse.ArgumentParser()
    root = Path(__file__).resolve().parent.parent
    ap.add_argument("--out", default=str(root / "game" / "audio" / "sfx"))
    out = Path(ap.parse_args().out)
    for i in range(2):
        write(out, f"sfx_rune_multishot_{i + 1:02d}", multishot(1601 + i))
    for i in range(3):
        write(out, f"sfx_rune_bounce_{i + 1:02d}", bounce(1611 + i))
    for i in range(2):
        write(out, f"sfx_rune_pierce_{i + 1:02d}", pierce(1621 + i))
    for i in range(2):
        write(out, f"sfx_rune_echo_{i + 1:02d}", echo(1631 + i))
    for i in range(2):
        write(out, f"sfx_rune_harvest_{i + 1:02d}", harvest(1641 + i))
    write(out, "sfx_rune_inscribe_01", inscribe(1651))
    write(out, "sfx_rune_erase_01", erase(1652))
    write(out, "sfx_rune_buy_01", buy(1653))
    write(out, "sfx_rune_table_open_01", slab(True, 1654))
    write(out, "sfx_rune_table_close_01", slab(False, 1655))
    write(out, "sfx_rune_unseal_01", unseal(1656))
    write(out, "amb_rune_table_hum_loop", table_hum(1657))


if __name__ == "__main__":
    main()
