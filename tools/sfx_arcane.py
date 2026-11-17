#!/usr/bin/env python3
"""Sonidos del Arcano (GDD 5.1: "puro, extraño; amplifica y duplica") y de sus combinaciones.

Uso:
    python3 tools/sfx_arcane.py            # escribe en game/audio/sfx
    python3 tools/sfx_arcane.py --out DIR

- sfx_arcane_cast_01/02: "fiiing" de cristal: campanas que suben en quintas con un soplo de aire.
- sfx_arcane_impact_01: campanada clara con un golpe suave y un brillo que se queda.
- sfx_arcane_echo_01/02: el eco fantasma: un "ping" lejano, desafinado a propósito y con mucha cola.
- sfx_echo_cast_01: los Ecos (Fuego, Hielo, Trueno): golpe de aire y tres notas que rebotan.
- sfx_gravity_01: Gravedad: el pozo se abre (zumbido grave que cae), remolino que sube de tono y
  la implosión final ("thwump") con destellos.
- sfx_resonance_01: Resonancia Arcana: un acorde de campanas enorme en La mayor que vibra largo.
- amb_arcane_charge_loop: carga de los hechizos arcanos: coro de vidrio con trémolo (bucle).
Todo afinado en La mayor pentatónica (como el "tink" del cristal). Deterministas: semillas fijas.
"""
import argparse
from pathlib import Path

import numpy as np

from sfx_synth import SR, bandpass, bell, fade, highpass, loopable, lowpass, normalize, note, reverb, t_axis, write

# Pentatónica de La (semitonos sobre A5): La, Si, Do#, Mi, Fa#.
PENTA = [0, 2, 4, 7, 9]
GLASS = [1.0, 2.0, 3.01, 4.2, 5.43]
GLASS_A = [1.0, 0.35, 0.18, 0.08, 0.05]


def glass(t, n, rng, decay=0.6, amp=1.0, detune=0.0):
    """Campana de vidrio en la nota `n` (semitonos sobre A5)."""
    f = note(n) * (1 + detune)
    return bell(t, f, GLASS, GLASS_A, [decay, decay * 0.6, decay * 0.4, decay * 0.25, decay * 0.18], rng, 0.002) * amp


def air(rng, n, lo=2000, hi=9000):
    return bandpass(rng.standard_normal(n), lo, hi, 2)


def arcane_cast(seed, root):
    rng = np.random.default_rng(seed)
    t = t_axis(0.9)
    x = np.zeros_like(t)
    # Tres campanas que suben (raíz, quinta, octava), muy seguidas: "fiiing".
    for k, n in enumerate((root, root + 7, root + 12)):
        s0 = int(k * 0.035 * SR)
        tt = t[: len(t) - s0]
        x[s0:] += glass(tt, n, rng, 0.35, 0.6 * (0.85 ** k))
    # Soplo de aire que sube (el hechizo sale de la mano).
    sweep = air(rng, len(t), 1500, 8000) * np.exp(-t / 0.09) * 0.6
    # Barrido de seno que sube una octava: lo "extraño" del arcano.
    f = note(root - 12) * 2 ** np.clip(t / 0.18, 0, 1)
    swoop = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.12) * 0.35
    x += sweep + swoop
    return normalize(fade(reverb(x, rng, 0.9, 0.35, 8000), 0.001, 0.15), -3)


def arcane_impact(seed):
    rng = np.random.default_rng(seed)
    t = t_axis(1.4)
    thump = lowpass(rng.standard_normal(len(t)), 260) * np.exp(-t / 0.05) * 1.6
    x = thump + glass(t, -5, rng, 0.8, 0.8) + glass(t, 2, rng, 0.6, 0.45) + glass(t, 9, rng, 0.4, 0.25)
    x += air(rng, len(t), 5000, 14000) * np.exp(-t / 0.3) * 0.15
    return normalize(fade(reverb(x, rng, 1.2, 0.35, 9000), 0.001, 0.2), -3)


def arcane_echo(seed, n):
    rng = np.random.default_rng(seed)
    t = t_axis(1.3)
    # Dos campanas casi iguales (batido fantasma) que entran suaves.
    x = glass(t, n, rng, 0.5, 0.6) + glass(t, n, rng, 0.5, 0.5, 0.006)
    x *= 1 - np.exp(-t / 0.02)
    x += air(rng, len(t), 3000, 10000) * np.exp(-t / 0.15) * 0.25
    x = highpass(x, 300, 2)
    return normalize(fade(reverb(x, rng, 1.4, 0.55, 7000), 0.002, 0.25), -6)


def echo_cast(seed):
    rng = np.random.default_rng(seed)
    t = t_axis(1.8)
    whoosh = air(rng, len(t), 400, 5000) * np.sin(np.pi * np.clip(t / 0.35, 0, 1)) * 0.7
    x = whoosh + lowpass(rng.standard_normal(len(t)), 150) * np.exp(-t / 0.08) * 1.4
    # Tres notas que rebotan, cada una más baja de volumen y más lejana (eco).
    for k, n in enumerate((7, 12, 16, 19)):
        s0 = int((0.05 + k * 0.17) * SR)
        tt = t[: len(t) - s0]
        x[s0:] += glass(tt, n, rng, 0.45, 0.55 * (0.72 ** k))
    return normalize(fade(reverb(x, rng, 1.5, 0.45, 8000), 0.001, 0.3), -2)


def gravity(seed):
    rng = np.random.default_rng(seed)
    dur = 4.2
    t = t_axis(dur)
    collapse = 2.5  # segundos hasta la implosión (como el pozo del juego)
    pre = np.clip(t / collapse, 0, 1)
    before = (t < collapse).astype(float)
    # Zumbido grave que cae al abrirse el pozo y vibra cada vez más rápido.
    f = 110 * 2 ** (-pre * 1.0)
    trem = 1 + 0.5 * np.sin(2 * np.pi * np.cumsum(2 + 10 * pre ** 2) / SR)
    drone = (np.sin(2 * np.pi * np.cumsum(f) / SR) + 0.4 * np.sin(4 * np.pi * np.cumsum(f) / SR))
    drone *= np.clip(t / 0.25, 0, 1) * trem * (0.5 + 0.5 * pre) * before * 0.9
    # Remolino: ruido filtrado que gira (barrido de banda) y sube de tono.
    noise = rng.standard_normal(len(t))
    swirl = np.zeros_like(t)
    for k, (lo, hi) in enumerate(((300, 900), (800, 2200), (2000, 5000))):
        w = 0.5 + 0.5 * np.sin(2 * np.pi * np.cumsum(1.5 + 7 * pre) / SR + k * 2.1)
        swirl += bandpass(noise, lo, hi, 2) * w * (pre ** (1 + k * 0.5))
    swirl *= before * 0.55
    # Silbido que sube justo antes de la implosión.
    fw = 400 + 2400 * pre ** 3
    whine = np.sin(2 * np.pi * np.cumsum(fw) / SR) * pre ** 4 * before * 0.25
    x = drone + swirl + whine
    # Implosión: "thwump" grave + campanas que caen en cascada.
    s0 = int(collapse * SR)
    tt = t[: len(t) - s0]
    boom = lowpass(rng.standard_normal(len(tt)), 110) * np.exp(-tt / 0.25) * 3.0
    fb = 90 * 2 ** (-tt * 2.5)
    boom += np.sin(2 * np.pi * np.cumsum(fb) / SR) * np.exp(-tt / 0.35) * 1.4
    x[s0:] += boom
    for k, n in enumerate((19, 16, 12, 9, 4, 0)):
        s1 = s0 + int((0.05 + k * 0.07) * SR)
        t1 = t[: len(t) - s1]
        x[s1:] += glass(t1, n, rng, 0.5, 0.35 * (0.9 ** k))
    return normalize(fade(reverb(x, rng, 1.6, 0.35, 7000), 0.02, 0.6), -1)


def resonance(seed):
    rng = np.random.default_rng(seed)
    dur = 5.0
    t = t_axis(dur)
    x = lowpass(rng.standard_normal(len(t)), 180) * np.exp(-t / 0.12) * 2.2
    # Acorde de La mayor en campanas, abierto en tres octavas, con batido lento (vibra).
    for k, (n, a) in enumerate(((-24, 0.9), (-17, 0.7), (-12, 0.8), (-8, 0.6), (-5, 0.6), (0, 0.5), (4, 0.35),
                                (7, 0.3), (12, 0.2))):
        s0 = int(k * 0.012 * SR)
        tt = t[: len(t) - s0]
        beat = 1 + 0.25 * np.sin(2 * np.pi * (1.3 + k * 0.4) * tt)
        x[s0:] += glass(tt, n, rng, 1.8 - k * 0.1, a) * beat
    x += air(rng, len(t), 6000, 15000) * np.exp(-t / 0.8) * 0.12
    return normalize(fade(reverb(x, rng, 2.2, 0.4, 8000), 0.001, 1.0), -1)


def arcane_charge_loop(seed):
    rng = np.random.default_rng(seed)
    dur = 3.0
    t = t_axis(dur)
    x = np.zeros_like(t)
    # Frecuencias con ciclos enteros en 3 s: empalma solo.
    for n, a in ((-24, 0.5), (-17, 0.35), (-12, 0.35), (-5, 0.25), (0, 0.15), (4, 0.1)):
        f = round(note(n) * dur) / dur
        trem = 0.75 + 0.25 * np.sin(2 * np.pi * (4.0 + abs(n) * 0.0) * t + rng.uniform(0, 6))
        x += (np.sin(2 * np.pi * f * t) + 0.2 * np.sin(4 * np.pi * f * t)) * a * trem
    x += air(rng, len(t), 3000, 9000) * 0.06
    return normalize(loopable(x, 0.4), -6)


def main() -> None:
    ap = argparse.ArgumentParser()
    root = Path(__file__).resolve().parent.parent
    ap.add_argument("--out", default=str(root / "game" / "audio" / "sfx"))
    out = Path(ap.parse_args().out)
    write(out, "sfx_arcane_cast_01", arcane_cast(1501, 0))
    write(out, "sfx_arcane_cast_02", arcane_cast(1502, 4))
    write(out, "sfx_arcane_impact_01", arcane_impact(1503))
    write(out, "sfx_arcane_echo_01", arcane_echo(1511, 12))
    write(out, "sfx_arcane_echo_02", arcane_echo(1512, 16))
    write(out, "sfx_echo_cast_01", echo_cast(1521))
    write(out, "sfx_gravity_01", gravity(1531))
    write(out, "sfx_resonance_01", resonance(1541))
    write(out, "amb_arcane_charge_loop", arcane_charge_loop(1551))


if __name__ == "__main__":
    main()
