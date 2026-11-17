#!/usr/bin/env python3
"""Paisaje sonoro del valle: pájaros de día, búho y grillos de noche.

Uso:
    python3 tools/sfx_ambience.py            # escribe en game/audio/sfx/
    python3 tools/sfx_ambience.py --out DIR

Sonidos suaves y espaciados, con reverberación de bosque: acompañan sin molestar. El juego los
reparte en 3D alrededor del jugador con tono y pausa al azar (ver world/day_night.gd), así que
nunca se repite el mismo patrón. Deterministas: semillas fijas. Requiere numpy, scipy y ffmpeg.
"""
import argparse
from pathlib import Path

import numpy as np

from sfx_synth import SR, bandpass, fade, highpass, loopable, lowpass, normalize, reverb, t_axis, write


def tone(freqs: np.ndarray, amp: np.ndarray) -> np.ndarray:
    """Oscilador con frecuencia variable (fase acumulada) y envolvente."""
    return np.sin(2 * np.pi * np.cumsum(freqs) / SR) * amp


def env(n: int, attack: float, release: float) -> np.ndarray:
    t = np.arange(n) / SR
    a = np.clip(t / max(attack, 1e-4), 0, 1)
    r = np.clip((t[-1] - t) / max(release, 1e-4), 0, 1)
    return np.minimum(a, r) ** 1.5


def forest(x: np.ndarray, rng: np.random.Generator, wet: float = 0.35) -> np.ndarray:
    """Distancia y bosque: quita graves, suaviza agudos y añade cola de reverberación."""
    x = highpass(x, 600, 2)
    x = lowpass(x, 7500, 2)
    return reverb(x, rng, 1.4, wet, 5000)


def bird_whistle(seed: int) -> np.ndarray:
    """Silbido de dos notas que baja ("fi-fiu"), como un carbonero lejano."""
    rng = np.random.default_rng(seed)
    out = np.zeros(int(1.4 * SR))
    pos = 0
    base = rng.uniform(3000, 3600)
    for k, (f0, f1, dur) in enumerate([(base * 1.12, base * 1.1, 0.16), (base, base * 0.86, 0.22)]):
        n = int(dur * SR)
        f = np.linspace(f0, f1, n) * (1 + 0.01 * np.sin(2 * np.pi * 28 * np.arange(n) / SR))
        out[pos:pos + n] += tone(f, env(n, 0.02, 0.06))
        pos += n + int(0.07 * SR)
    return normalize(fade(forest(out, rng), 0.001, 0.2), -12)


def bird_trill(seed: int) -> np.ndarray:
    """Trino: ráfaga de notas muy cortas que suben y bajan."""
    rng = np.random.default_rng(seed)
    out = np.zeros(int(1.6 * SR))
    pos = int(0.02 * SR)
    count = rng.integers(9, 15)
    base = rng.uniform(4200, 5200)
    for k in range(count):
        n = int(rng.uniform(0.025, 0.04) * SR)
        f = np.linspace(base * 1.15, base * 0.9, n) * (1 + 0.08 * np.sin(k * 0.9))
        out[pos:pos + n] += tone(f, env(n, 0.004, 0.012)) * (0.6 + 0.4 * np.sin(np.pi * k / count))
        pos += n + int(rng.uniform(0.012, 0.025) * SR)
    return normalize(fade(forest(out, rng), 0.001, 0.2), -14)


def bird_warble(seed: int) -> np.ndarray:
    """Gorjeo: frase de 5-7 notas deslizadas, distinta cada vez (como un petirrojo)."""
    rng = np.random.default_rng(seed)
    out = np.zeros(int(2.0 * SR))
    pos = 0
    for k in range(rng.integers(5, 8)):
        n = int(rng.uniform(0.06, 0.13) * SR)
        f0 = rng.uniform(2600, 4600)
        f1 = f0 * rng.uniform(0.8, 1.25)
        f = np.linspace(f0, f1, n) * (1 + 0.02 * np.sin(2 * np.pi * rng.uniform(30, 60) * np.arange(n) / SR))
        out[pos:pos + n] += tone(f, env(n, 0.01, 0.03)) * rng.uniform(0.5, 1.0)
        pos += n + int(rng.uniform(0.02, 0.07) * SR)
    return normalize(fade(forest(out, rng), 0.001, 0.25), -13)


def dove(seed: int) -> np.ndarray:
    """Paloma torcaz: arrullo grave y suave ("uu-UU-u")."""
    rng = np.random.default_rng(seed)
    out = np.zeros(int(2.2 * SR))
    pos = 0
    for f0, dur, a in [(480, 0.25, 0.6), (560, 0.45, 1.0), (500, 0.3, 0.7)]:
        n = int(dur * SR)
        t = np.arange(n) / SR
        f = f0 * (1 + 0.05 * np.sin(np.pi * t / t[-1]))
        voice = tone(f, env(n, 0.06, 0.1)) + 0.25 * tone(f * 2, env(n, 0.06, 0.1))
        breath = bandpass(rng.standard_normal(n), 300, 900, 2) * env(n, 0.06, 0.1) * 0.15
        out[pos:pos + n] += (voice + breath) * a
        pos += n + int(0.12 * SR)
    x = lowpass(out, 2500, 2)
    return normalize(fade(reverb(x, rng, 1.5, 0.35, 3000), 0.002, 0.3), -14)


def owl(seed: int) -> np.ndarray:
    """Búho: "uu... u-uuu" grave, con aire y mucha reverberación de bosque nocturno."""
    rng = np.random.default_rng(seed)
    out = np.zeros(int(3.2 * SR))
    pos = 0
    f0 = rng.uniform(360, 410)
    for dur, a, gap in [(0.42, 1.0, 0.45), (0.16, 0.6, 0.06), (0.55, 0.9, 0.0)]:
        n = int(dur * SR)
        t = np.arange(n) / SR
        f = f0 * (1.04 - 0.07 * t / t[-1])
        voice = tone(f, env(n, 0.05, 0.15)) + 0.18 * tone(f * 2, env(n, 0.05, 0.15))
        breath = lowpass(rng.standard_normal(n), 900) * env(n, 0.05, 0.15) * 0.12
        out[pos:pos + n] += (voice + breath) * a
        pos += n + int(gap * SR)
    x = lowpass(out, 1800, 2)
    return normalize(fade(reverb(x, rng, 2.2, 0.45, 2500), 0.002, 0.4), -13)


def night_loop(seed: int) -> np.ndarray:
    """Noche: grillos a distintas distancias y brisa suave. 12 s, empalma sin costura."""
    rng = np.random.default_rng(seed)
    dur = 12.0
    t = t_axis(dur + 1.0)
    x = np.zeros_like(t)
    for c in range(6):
        carrier = rng.uniform(4100, 5400)
        period = rng.uniform(0.55, 0.95)
        pulses = rng.integers(3, 5)
        level = rng.uniform(0.15, 0.6)
        phase = rng.uniform(0, period)
        start = phase
        while start < dur + 1.0:
            for p in range(pulses):
                s = int((start + p * 0.028) * SR)
                n = int(0.018 * SR)
                if s + n >= len(t):
                    break
                x[s:s + n] += np.sin(2 * np.pi * carrier * np.arange(n) / SR) * np.hanning(n) * level
            start += period * rng.uniform(0.92, 1.08)
            # De vez en cuando un grillo calla un rato.
            if rng.random() < 0.08:
                start += rng.uniform(1.0, 3.0)
    x = bandpass(x, 3000, 7000, 2)
    wind = lowpass(np.cumsum(rng.standard_normal(len(t))) * 0.01, 500, 2)
    wind = highpass(wind, 50, 2)
    wind = wind / (np.max(np.abs(wind)) + 1e-9) * 0.25
    x = reverb(x * 0.6 + wind, rng, 1.2, 0.3, 5000)[: len(t)]
    return normalize(loopable(x, 1.0), -14)


def main() -> None:
    ap = argparse.ArgumentParser()
    root = Path(__file__).resolve().parent.parent
    ap.add_argument("--out", default=str(root / "game" / "audio" / "sfx"))
    out = Path(ap.parse_args().out)
    for i in range(3):
        write(out, f"amb_bird_whistle_{i + 1:02d}", bird_whistle(900 + i))
        write(out, f"amb_bird_trill_{i + 1:02d}", bird_trill(910 + i))
        write(out, f"amb_bird_warble_{i + 1:02d}", bird_warble(920 + i))
    write(out, "amb_dove_01", dove(930))
    for i in range(2):
        write(out, f"amb_owl_{i + 1:02d}", owl(940 + i))
    write(out, "amb_night_loop", night_loop(950))


if __name__ == "__main__":
    main()
