#!/usr/bin/env python3
"""Sonidos del bucle de juego (M1b): entregar al Pilón, bolsa llena, Grimorio, compras e interfaz.

Uso:
    python3 tools/sfx_loop.py            # escribe en game/audio/sfx/
    python3 tools/sfx_loop.py --out DIR

Reutiliza los bloques de `sfx_synth.py`. Todo afinado en La mayor (como el "tink" y la música) para
que las cadenas de sonidos (una gota por fragmento entregado) formen melodía y no ruido.
Deterministas: semillas fijas.
"""
import argparse
from pathlib import Path

import numpy as np

from sfx_synth import (SR, bandpass, bell, fade, highpass, loopable, lowpass, normalize, note,
                       reverb, t_axis, write)


def mana_drop(seed: int, n: int) -> np.ndarray:
    """Gota de maná: 'plip' líquido que cae hacia la nota `n` + campana de cristal y burbujas."""
    rng = np.random.default_rng(seed)
    t = t_axis(0.9)
    target = note(n) / 2
    f = target * (1 + 1.2 * np.exp(-t / 0.018))
    plip = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.06) * 0.7
    ring = bell(t, note(n), [1.0, 2.0, 3.0, 4.1], [1.0, 0.35, 0.12, 0.05], [0.45, 0.25, 0.12, 0.08], rng)
    ring *= 1 - np.exp(-t / 0.01)
    bubbles = np.zeros_like(t)
    for k in range(4):
        s = int((0.05 + k * rng.uniform(0.03, 0.06)) * SR)
        m = int(0.03 * SR)
        tt = np.arange(m) / SR
        fb = rng.uniform(900, 1600) * (1 + 2.0 * tt / tt[-1])
        bubbles[s:s + m] += np.sin(2 * np.pi * np.cumsum(fb) / SR) * np.hanning(m) * 0.12
    x = plip + ring * 0.55 + bubbles
    return normalize(fade(reverb(x, rng, 0.8, 0.25), 0.0005, 0.12), -4)


def pylon_hum(seed: int) -> np.ndarray:
    """Zumbido del Pilón: acorde de La con 9.ª y burbujeo suave. 8 s con ciclos enteros: empalma."""
    rng = np.random.default_rng(seed)
    dur = 8.0
    t = t_axis(dur)
    freqs = [110.0, 220.0, 277.125, 330.0, 440.0, 493.875, 660.0]
    amps = [0.7, 1.0, 0.45, 0.5, 0.35, 0.18, 0.12]
    x = np.zeros_like(t)
    for f, a in zip(freqs, amps):
        f = round(f * dur) / dur
        x += a * np.sin(2 * np.pi * f * t + rng.uniform(0, 2 * np.pi))
    shimmer = np.sin(2 * np.pi * t / 4.0) * 0.15 + 0.85
    air = bandpass(rng.standard_normal(len(t) + SR), 2500, 7000, 2) * 0.04
    x = x * shimmer + loopable(air, 1.0)[: len(t)]
    return normalize(x, -10)


def bag_full(seed: int) -> np.ndarray:
    """No cabe más: golpe sordo de bolsa + dos notas que bajan (Mi -> Do#), sin ser castigo."""
    rng = np.random.default_rng(seed)
    t = t_axis(0.6)
    thud = lowpass(rng.standard_normal(len(t)), 400) * np.exp(-t / 0.04) * 1.5
    x = thud.copy()
    for k, n in enumerate([-5, -8]):
        s = int(k * 0.09 * SR)
        tt = t[: len(t) - s]
        x[s:] += bell(tt, note(n), [1.0, 2.0, 3.0], [1.0, 0.2, 0.05], [0.2, 0.1, 0.05], rng) * 0.45
    return normalize(fade(reverb(x, rng, 0.4, 0.15), 0.001, 0.08), -6)


def upgrade_buy(seed: int) -> np.ndarray:
    """Comprar una mejora: acorde mágico (La add9) en arpa que sube + coro de campanas y brillo."""
    rng = np.random.default_rng(seed)
    t = t_axis(2.6)
    x = np.zeros_like(t)
    for i, n in enumerate([-12, -5, 0, 4, 7, 11, 12, 16]):
        s = int(i * 0.045 * SR)
        tt = t[: len(t) - s]
        x[s:] += bell(tt, note(n), [1.0, 2.0, 3.0, 4.0], [1.0, 0.4, 0.15, 0.06],
                      [1.4, 0.8, 0.4, 0.2], rng, 0.003) * (0.9 ** i) * 0.6
    pad = np.zeros_like(t)
    for n in [-24, -17, -12, -8]:
        pad += np.sin(2 * np.pi * note(n) * t) * 0.15
    pad *= np.minimum(t / 0.3, 1.0) * np.exp(-t / 0.9)
    sparkle = bandpass(rng.standard_normal(len(t)), 7000, 15000) * np.exp(-t / 0.6) * 0.05
    whoosh = bandpass(rng.standard_normal(len(t)), 300, 2500, 2) * np.exp(-((t - 0.15) / 0.12) ** 2) * 0.25
    x = x + pad + sparkle + whoosh
    return normalize(fade(reverb(x, rng, 1.6, 0.32), 0.002, 0.3), -2)


def book_open(seed: int, closing: bool = False) -> np.ndarray:
    """Abrir (o cerrar) el Grimorio: aleteo de páginas + una campanita (sube al abrir, baja al cerrar)."""
    rng = np.random.default_rng(seed)
    t = t_axis(0.8)
    flaps = np.zeros_like(t)
    for k in range(5):
        s = int((k * 0.035 + rng.uniform(0, 0.01)) * SR)
        m = int(rng.uniform(0.02, 0.04) * SR)
        flaps[s:s + m] += rng.standard_normal(m) * np.hanning(m) * (0.9 ** k)
    flaps = bandpass(flaps, 800, 6000, 2)
    n = [0, 7] if not closing else [7, 0]
    chime = np.zeros_like(t)
    for k, nn in enumerate(n):
        s = int((0.12 + k * 0.07) * SR)
        tt = t[: len(t) - s]
        chime[s:] += bell(tt, note(nn), [1.0, 2.0, 3.0], [1.0, 0.3, 0.1], [0.4, 0.2, 0.1], rng) * 0.35
    x = flaps + chime
    return normalize(fade(reverb(x, rng, 0.6, 0.2), 0.001, 0.1), -5)


def ui_tick(seed: int) -> np.ndarray:
    """Pasar por una estrella del Grimorio: 'tic' de cristal muy corto."""
    rng = np.random.default_rng(seed)
    t = t_axis(0.18)
    x = bell(t, note(19), [1.0, 2.7], [1.0, 0.3], [0.04, 0.02], rng)
    x += highpass(rng.standard_normal(len(t)), 6000) * np.exp(-t / 0.002) * 0.3
    return normalize(fade(x, 0.0005, 0.03), -12)


def ui_deny(seed: int) -> np.ndarray:
    """No hay maná suficiente: zumbido apagado de dos pulsos (Re y Do#: suave, no estridente)."""
    rng = np.random.default_rng(seed)
    t = t_axis(0.35)
    x = np.zeros_like(t)
    for k in range(2):
        s = int(k * 0.11 * SR)
        m = int(0.08 * SR)
        tt = np.arange(m) / SR
        tone = np.sin(2 * np.pi * 146.8 * tt) + 0.5 * np.sin(2 * np.pi * 277.2 * tt)
        x[s:s + m] += tone * np.hanning(m)
    x = lowpass(x, 1200)
    return normalize(fade(x, 0.002, 0.03), -9)


def telekinesis(seed: int) -> np.ndarray:
    """Un fragmento vuela solo hacia ti: soplo que sube + destello."""
    rng = np.random.default_rng(seed)
    t = t_axis(0.5)
    noise = rng.standard_normal(len(t))
    sweep = np.zeros_like(t)
    edges = np.geomspace(500, 5000, 10)
    seg = len(t) // 10
    for i in range(10):
        part = bandpass(noise, edges[i], edges[i] * 1.5, 2)
        sweep[i * seg:(i + 1) * seg] = part[i * seg:(i + 1) * seg]
    sweep *= np.sin(np.pi * np.clip(t / 0.35, 0, 1)) ** 2
    glint = bell(t, note(16), [1.0, 2.0], [1.0, 0.3], [0.15, 0.08], rng) * 0.3
    glint[: int(0.3 * SR)] = 0
    return normalize(fade(sweep * 0.6 + glint, 0.002, 0.05), -10)


def pylon_milestone(seed: int) -> np.ndarray:
    """El Pilón cruza una marca (10 %, 25 %...): campanas graves + arpegio largo hacia arriba."""
    rng = np.random.default_rng(seed)
    t = t_axis(3.2)
    x = np.zeros_like(t)
    for i, n in enumerate([-24, -12, -5, 0, 4, 7, 12, 16, 19, 24]):
        s = int(i * 0.07 * SR)
        tt = t[: len(t) - s]
        x[s:] += bell(tt, note(n), [1.0, 2.0, 3.0, 4.2], [1.0, 0.4, 0.15, 0.06],
                      [1.8, 1.0, 0.5, 0.25], rng) * 0.5
    return normalize(fade(reverb(x, rng, 2.0, 0.35), 0.002, 0.4), -2)


# Pentatónica de La (semitonos sobre A5) para la escala de gotas: cada entrega sube una nota.
DROP_NOTES = [-12, -10, -8, -5, -3, 0, 2, 4, 7, 9, 12]


def main() -> None:
    ap = argparse.ArgumentParser()
    root = Path(__file__).resolve().parent.parent
    ap.add_argument("--out", default=str(root / "game" / "audio" / "sfx"))
    out = Path(ap.parse_args().out)
    # Una sola gota (en La): el juego sube el tono por la escala con `pitch_scale`.
    for i in range(3):
        write(out, f"sfx_mana_drop_{i + 1:02d}", mana_drop(700 + i, 0))
    write(out, "amb_pylon_hum_loop", pylon_hum(710))
    write(out, "sfx_bag_full_01", bag_full(720))
    write(out, "sfx_upgrade_buy_01", upgrade_buy(730))
    write(out, "sfx_book_open_01", book_open(740))
    write(out, "sfx_book_close_01", book_open(741, closing=True))
    write(out, "sfx_ui_tick_01", ui_tick(750))
    write(out, "sfx_ui_deny_01", ui_deny(760))
    write(out, "sfx_telekinesis_01", telekinesis(770))
    write(out, "sfx_pylon_milestone_01", pylon_milestone(780))


if __name__ == "__main__":
    main()
