#!/usr/bin/env python3
"""Sonidos de la Bola de Fuego (Chispa + Chispa, el primer hechizo "de verdad") y de descubrir una combinación.

Uso:
    python3 tools/sfx_fireball.py            # escribe en game/audio/sfx/
    python3 tools/sfx_fireball.py --out DIR

Reutiliza las utilidades de `sfx_synth.py`. Deterministas (semillas fijas). Requiere numpy, scipy y ffmpeg.

Sonidos y cómo usarlos en Godot (bus SFX):
    sfx_spell_combine_01         las manos se juntan: dos tonos a una 5.ª que se funden en unísono (La) + brillo.
    sfx_fireball_charge_loop     bucle de fuego mientras se carga (rugido grave + chisporroteo). Activar loop=true
                                 en la importación; subir pitch_scale de 0,85 a 1,25 y volumen con la carga.
    sfx_fireball_cast_01..03     lanzamiento: golpe grave + "fwoosh" de llamarada con barrido de filtro.
    sfx_fireball_impact_01..03   impacto: explosión (sub + estallido + crepitar de brasas) + lluvia de esquirlas de
                                 cristal afinadas en La mayor (A, C#, E) para que casen con la música y el "tink".
    sfx_combo_discovered_01      fanfarria corta al descubrir una combinación (GDD 10): IV - V - I en La mayor.
Para las variantes numeradas, usar un AudioStreamRandomizer (tono ±4 %), como el resto de SFX.
"""
import argparse
from pathlib import Path

import numpy as np
from sfx_synth import (SR, bandpass, bell, fade, highpass, lowpass, normalize, reverb, t_axis,
                       write)

A4 = 440.0


def semi(n: float, base: float = A4) -> float:
    return base * 2 ** (n / 12)


def filtered_sweep(noise: np.ndarray, f_start: float, f_end: float, q: float = 1.6, steps: int = 24) -> np.ndarray:
    """Barrido de filtro paso banda por tramos con fundido (sin clics entre tramos)."""
    n = len(noise)
    out = np.zeros(n)
    edges = np.geomspace(f_start, f_end, steps)
    seg = n / steps
    win_len = int(seg * 2)
    for i, f in enumerate(edges):
        lo, hi = f / q, min(f * q, SR / 2 - 100)
        part = bandpass(noise, max(lo, 20), hi, 2)
        s = int(i * seg - seg / 2)
        w = np.hanning(win_len)
        a, b = max(s, 0), min(s + win_len, n)
        out[a:b] += part[a:b] * w[a - s:b - s]
    return out


def crackle(t: np.ndarray, rng: np.random.Generator, rate: float, lo: float = 2500) -> np.ndarray:
    """Chasquidos de brasa: impulsos aleatorios filtrados."""
    x = np.zeros_like(t)
    count = int(rate * t[-1])
    for _ in range(count):
        p = int(rng.uniform(0, len(t) - 200))
        n = int(rng.uniform(8, 60))
        x[p:p + n] += rng.standard_normal(n) * np.hanning(n) * rng.uniform(0.3, 1.0)
    return highpass(x, lo)


def roar(t: np.ndarray, rng: np.random.Generator) -> np.ndarray:
    """Rugido de fuego: ruido grave modulado lentamente (turbulencia)."""
    base = lowpass(rng.standard_normal(len(t)), 500, 2)
    flutter = 0.7 + 0.3 * lowpass(rng.standard_normal(len(t)), 8, 1) / 0.05
    flutter = np.clip(flutter, 0.2, 1.5)
    mid = bandpass(rng.standard_normal(len(t)), 600, 2200, 2) * 0.35
    return (base + mid) * flutter


def spell_combine(seed: int) -> np.ndarray:
    """Dos tonos (E5 y A4, una 5.ª) que se deslizan hasta el unísono en A4 al juntar las manos, con brillo."""
    rng = np.random.default_rng(seed)
    t = t_axis(1.3)
    glide = np.clip(t / 0.45, 0, 1)
    glide = glide * glide * (3 - 2 * glide)  # suavizado
    f_hi = semi(7) + (semi(0) - semi(7)) * glide
    f_lo = semi(-5) + (semi(0) - semi(-5)) * glide
    x = np.zeros_like(t)
    for f in (f_hi, f_lo):
        ph = 2 * np.pi * np.cumsum(f) / SR
        x += np.sin(ph) + 0.3 * np.sin(2 * ph) + 0.12 * np.sin(3 * ph)
    env = np.clip(t / 0.08, 0, 1) * np.exp(-np.clip(t - 0.5, 0, None) / 0.25)
    x *= env * 0.4
    # "Clic" de fusión al llegar al unísono: campana A5 + brillo.
    s = int(0.45 * SR)
    tt = t[: len(t) - s]
    x[s:] += bell(tt, 880, [1.0, 2.0, 3.0, 4.2], [1.0, 0.35, 0.12, 0.06], [0.6, 0.3, 0.15, 0.1], rng) * 0.5
    x[s:] += bandpass(rng.standard_normal(len(tt)), 5000, 12000) * np.exp(-tt / 0.25) * 0.12
    return normalize(fade(reverb(x, rng, 1.0, 0.28), 0.002, 0.15), -3)


def fireball_charge_loop(seed: int) -> np.ndarray:
    """Fuego cargándose: bucle de 2 s (empalma con crossfade)."""
    rng = np.random.default_rng(seed)
    dur, xf = 2.0, 0.4
    t = t_axis(dur + xf)
    x = roar(t, rng) + crackle(t, rng, 26) * 0.2
    # Compresión suave: el rugido manda y los chasquidos no disparan los picos.
    x = np.tanh(x / (np.std(x) * 2.5))
    # Leve "respiración" de la llama, con ciclos enteros en 2 s.
    x *= 0.85 + 0.15 * np.sin(2 * np.pi * t / 1.0)
    n = int(xf * SR)
    body = x[: int(dur * SR)].copy()
    ramp = np.linspace(0, 1, n)
    body[:n] = x[int(dur * SR):int(dur * SR) + n] * (1 - ramp) + body[:n] * ramp
    return normalize(body, -4)


def fireball_cast(seed: int) -> np.ndarray:
    """Lanzamiento: golpe grave + llamarada que barre de grave a agudo y se aleja."""
    rng = np.random.default_rng(seed)
    t = t_axis(1.1)
    noise = rng.standard_normal(len(t))
    fwoosh = filtered_sweep(noise, 180, rng.uniform(2600, 3400), 1.7)
    fwoosh *= (1 - np.exp(-t / 0.02)) * np.exp(-t / 0.28)
    f = 110 * np.exp(-t / 0.08) + 45
    thump = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.12) * 0.9
    burst = roar(t, rng) * np.exp(-t / 0.2) * 0.4
    x = fwoosh * 1.2 + thump + burst + crackle(t, rng, 30) * np.exp(-t / 0.35) * 0.4
    return normalize(fade(reverb(x, rng, 0.8, 0.18, 4000), 0.001, 0.1), -1.5)


def fireball_impact(seed: int) -> np.ndarray:
    """Impacto en el cristal: explosión con cuerpo + esquirlas afinadas en La mayor."""
    rng = np.random.default_rng(seed)
    t = t_axis(2.4)
    # Sub: caída de tono rápida (el "bum" que se siente).
    f = 90 * np.exp(-t / 0.05) + 38
    sub = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.35)
    # Estallido: ruido con ataque seco y cola oscura.
    noise = rng.standard_normal(len(t))
    blast = lowpass(noise, 1800, 2) * np.exp(-t / 0.22) + highpass(noise, 2500) * np.exp(-t / 0.05) * 0.5
    blast *= 1 - np.exp(-t / 0.002)
    embers = crackle(t, rng, 45) * np.exp(-t / 0.7) * 0.35
    # Esquirlas de cristal: notas de la tríada de La (A, C#, E) en varias octavas, desparramadas en el tiempo.
    shards = np.zeros_like(t)
    triad = [0, 4, 7, 12, 16, 19, 24]
    for _ in range(12):
        n = int(rng.choice(triad))
        start = rng.uniform(0.02, 0.35)
        s = int(start * SR)
        tt = t[: len(t) - s]
        shards[s:] += bell(tt, semi(n, 880), [1.0, 2.32, 4.25], [1.0, 0.45, 0.2], [0.5, 0.25, 0.1], rng, 0.003) \
            * rng.uniform(0.25, 0.6)
    x = sub * 1.1 + blast * 0.9 + embers + shards * 0.45
    return normalize(fade(reverb(x, rng, 1.4, 0.22, 5000), 0.0005, 0.25), -1.0)


def brass(f: float, dur: float, rng: np.random.Generator) -> np.ndarray:
    """Metal sintético: sierra aditiva con "filtro" que se abre al atacar (brillo de metal)."""
    n = int((dur + 0.4) * SR)
    t = np.arange(n) / SR
    vib = 1 + 0.004 * np.sin(2 * np.pi * 5.5 * t) * np.clip((t - 0.15) / 0.2, 0, 1)
    ph = 2 * np.pi * np.cumsum(f * vib) / SR
    bright = 0.35 + 0.65 * np.exp(-t / 0.18)  # más armónicos al principio
    x = np.zeros(n)
    for k in range(1, 16):
        if f * k > 9000:
            break
        x += np.sin(k * ph) / k * bright ** (k * 0.35)
    env = np.clip(t / 0.03, 0, 1) * np.where(t < dur, 1.0, np.exp(-(t - dur) / 0.12))
    return x * env


def combo_discovered(seed: int) -> np.ndarray:
    """Fanfarria corta: D - E - A (IV - V - I en La mayor), voces con conducción mínima, arpegio de remate."""
    rng = np.random.default_rng(seed)
    beat = 60 / 132
    # (inicio en pulsos, duración, notas en semitonos desde A4)
    chords = [
        (0.0, 0.5, [-7, -3, 0, 5]),     # D: D4 F#4 A4 D5
        (0.5, 0.5, [-5, -1, 2, 7]),     # E: E4 G#4 B4 E5
        (1.0, 2.5, [-12, -5, 0, 4, 7]),  # A: A3 E4 A4 C#5 E5 (resolución, nota larga)
    ]
    total = (3.5 * beat) + 1.8
    x = np.zeros(int(total * SR) + SR)
    for start, dur, notes in chords:
        s = int(start * beat * SR)
        for nt in notes:
            v = brass(semi(nt), dur * beat, rng)
            x[s:s + len(v)] += v * 0.16
    # Arpegio de campanas sobre la resolución: A5 C#6 E6 A6.
    s0 = int(1.0 * beat * SR)
    for i, nt in enumerate([0, 4, 7, 12]):
        s = s0 + int(i * 0.07 * SR)
        tt = np.arange(len(x) - s) / SR
        x[s:] += bell(tt, semi(nt, 880), [1.0, 2.0, 3.01], [1.0, 0.3, 0.1], [0.9, 0.45, 0.2], rng, 0.002) \
            * 0.22 * 0.85 ** i
    # Golpe de timbal en la resolución.
    tt = np.arange(len(x) - s0) / SR
    f = 110 * np.exp(-tt / 0.06) + 55
    x[s0:] += np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-tt / 0.4) * 0.5
    x = x[: int(total * SR)]
    return normalize(fade(reverb(x, rng, 1.6, 0.3), 0.001, 0.3), -1.5)


def main() -> None:
    ap = argparse.ArgumentParser()
    root = Path(__file__).resolve().parent.parent
    ap.add_argument("--out", default=str(root / "game" / "audio" / "sfx"))
    out = Path(ap.parse_args().out)
    write(out, "sfx_spell_combine_01", spell_combine(2000))
    write(out, "sfx_fireball_charge_loop", fireball_charge_loop(2100))
    for i in range(3):
        write(out, f"sfx_fireball_cast_{i + 1:02d}", fireball_cast(2200 + i))
        write(out, f"sfx_fireball_impact_{i + 1:02d}", fireball_impact(2300 + i))
    write(out, "sfx_combo_discovered_01", combo_discovered(2400))
    print(f"SFX de la Bola de Fuego escritos en {out}")


if __name__ == "__main__":
    main()
