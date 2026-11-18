#!/usr/bin/env python3
"""Sonidos propios del Meteoro (además de sfx_meteor_fall_01 de sfx_combos.py).

Uso:
    python3 tools/sfx_meteor.py            # escribe en game/audio/sfx
    python3 tools/sfx_meteor.py --out DIR

- sfx_meteor_glint_01: destello en el cielo donde aparece la roca: campanilla alta y brillo.
- sfx_meteor_whistle_01: la roca que llega: silbido que baja de tono (Doppler) sobre un rugido de
  fuego y aire que crece hasta el golpe.
- sfx_meteor_boom_01: el golpe en el cráter, un solo sonido (antes sonaban dos a la vez, este y el
  impacto de la receta): chasquido y estallido de fuego arriba, bombo subgrave que cae de tono,
  crujido de roca, rugido del fuego que se abre, retumbe largo que rueda por el valle y cascotes
  (brillantes al principio, pesados después). Saturación suave para que todo pegue.
Deterministas: semillas fijas.
"""
import argparse
from pathlib import Path

import numpy as np

from sfx_synth import SR, bandpass, bell, fade, highpass, lowpass, normalize, reverb, t_axis, write


def glint(seed):
    rng = np.random.default_rng(seed)
    t = t_axis(1.2)
    # La en dos octavas (A6 y E7): no desafina con el "tink" pentatónico del cristal.
    x = bell(t, 1760.0, [1.0, 1.5, 2.0, 3.0], [1.0, 0.5, 0.35, 0.15], [0.5, 0.35, 0.25, 0.12], rng)
    shimmer = highpass(rng.standard_normal(len(t)), 6000) * np.exp(-t / 0.25) * 0.12
    x = x * 0.5 + shimmer
    return normalize(fade(reverb(x, rng, 1.4, 0.4), 0.001, 0.2), -8)


def whistle(seed):
    rng = np.random.default_rng(seed)
    dur = 1.7
    t = t_axis(dur)
    u = np.clip(t / dur, 0, 1)
    # Silbido: tono que cae de 2200 a 420 Hz cada vez más deprisa (se acerca y pasa).
    f = 420 + 1780 * (1 - u) ** 1.8
    phase = 2 * np.pi * np.cumsum(f) / SR
    vib = 1 + 0.004 * np.sin(2 * np.pi * 7 * t)
    tone = np.sin(phase * vib) + 0.3 * np.sin(2 * phase * vib)
    tone *= (0.25 + 0.75 * u ** 1.2) * 0.35
    # Aire rasgado alrededor del tono (ruido filtrado que sigue al silbido).
    air = np.zeros_like(t)
    noise = rng.standard_normal(len(t))
    for k, (lo, hi) in enumerate(((1500, 4500), (700, 2200), (250, 900))):
        w = np.clip(1 - np.abs(u * 2 - k), 0, 1)
        air += bandpass(noise, lo, hi, 2) * w * 0.5
    # Rugido grave del fuego que crece hasta el final.
    roar = lowpass(rng.standard_normal(len(t)), 160) * u ** 2.5 * 2.2
    x = (tone + air * (0.3 + 0.7 * u) + roar) * np.clip(t / 0.25, 0, 1)
    return normalize(fade(x, 0.02, 0.03), -2)


def boom(seed):
    rng = np.random.default_rng(seed)
    dur = 4.6
    t = t_axis(dur)
    noise = rng.standard_normal(len(t))
    # Ataque: chasquido seco y el estallido del fuego (medios brillantes que caen deprisa).
    click = highpass(rng.standard_normal(len(t)), 1500) * np.exp(-t / 0.008) * 0.7
    blast = bandpass(noise, 200, 3000, 2) * np.exp(-t / 0.22) * 1.3
    # Bombo: seno que cae de 75 a 28 Hz.
    f = 28 + 47 * np.exp(-t / 0.18)
    kick = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.9) * 1.7
    # Cuerpo de la explosión, crujido de roca y el rugido del fuego que se abre.
    body = lowpass(rng.standard_normal(len(t)), 200) * np.exp(-t / 0.5) * 2.4
    crack = bandpass(rng.standard_normal(len(t)), 400, 2500, 2) * np.exp(-t / 0.12) * 0.8
    roar = bandpass(rng.standard_normal(len(t)), 250, 1200, 2) * np.clip(t / 0.05, 0, 1)
    roar *= np.exp(-t / 0.7) * 0.5
    # Retumbe que rueda: ruido muy grave modulado lentamente.
    rumble = lowpass(rng.standard_normal(len(t)), 60) * (0.6 + 0.4 * np.sin(2 * np.pi * 1.3 * t))
    rumble *= np.clip(t / 0.2, 0, 1) * np.exp(-t / 1.6) * 3.0
    # Cascotes: brillantes y rápidos al principio, pesados y espaciados después.
    debris = np.zeros_like(t)
    for _ in range(70):
        late = rng.random() < 0.45
        s0 = rng.integers(int((0.25 if late else 0.08) * SR), int((3.0 if late else 1.4) * SR))
        n = int(rng.uniform(0.01, 0.05) * SR) if late else int(rng.uniform(0.004, 0.02) * SR)
        lo, hi = (300, 2200) if late else (900, 5000)
        if s0 + n < len(t):
            hit = bandpass(rng.standard_normal(n), lo, hi, 2) * np.hanning(n)
            debris[s0:s0 + n] += hit * rng.uniform(0.05, 0.3) * np.exp(-s0 / SR / 1.2)
    x = click + blast + kick + body + crack + roar + rumble + debris
    x = np.tanh(x / np.max(np.abs(x)) * 1.6)
    return normalize(fade(reverb(x, rng, 2.6, 0.3, 3000), 0.001, 1.2), -1)


def main() -> None:
    ap = argparse.ArgumentParser()
    root = Path(__file__).resolve().parent.parent
    ap.add_argument("--out", default=str(root / "game" / "audio" / "sfx"))
    out = Path(ap.parse_args().out)
    write(out, "sfx_meteor_glint_01", glint(1301))
    write(out, "sfx_meteor_whistle_01", whistle(1302))
    write(out, "sfx_meteor_boom_01", boom(1303))


if __name__ == "__main__":
    main()
