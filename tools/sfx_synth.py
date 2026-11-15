#!/usr/bin/env python3
"""Sintetiza los efectos de sonido del prototipo de forma procedural y reproducible.

Uso:
    python3 tools/sfx_synth.py            # escribe en game/audio/sfx/
    python3 tools/sfx_synth.py --out DIR

Requiere numpy y scipy. Cada sonido usa una semilla fija: ejecutar dos veces da los mismos archivos.
Son sonidos de prototipo; se sustituirán o pulirán con diseño de sonido profesional.
"""
import argparse
import shutil
import subprocess
from pathlib import Path

import numpy as np
from scipy import signal
from scipy.io import wavfile

SR = 44100


def t_axis(dur: float) -> np.ndarray:
    return np.arange(int(dur * SR)) / SR


def bandpass(x: np.ndarray, lo: float, hi: float, order: int = 4) -> np.ndarray:
    sos = signal.butter(order, [lo, hi], btype="band", fs=SR, output="sos")
    return signal.sosfilt(sos, x)


def lowpass(x: np.ndarray, f: float, order: int = 4) -> np.ndarray:
    return signal.sosfilt(signal.butter(order, f, btype="low", fs=SR, output="sos"), x)


def highpass(x: np.ndarray, f: float, order: int = 4) -> np.ndarray:
    return signal.sosfilt(signal.butter(order, f, btype="high", fs=SR, output="sos"), x)


def fade(x: np.ndarray, fin: float = 0.002, fout: float = 0.02) -> np.ndarray:
    n_in, n_out = max(1, int(fin * SR)), max(1, int(fout * SR))
    x = x.copy()
    x[:n_in] *= np.linspace(0, 1, n_in)
    x[-n_out:] *= np.linspace(1, 0, n_out)
    return x


def reverb(x: np.ndarray, rng: np.random.Generator, length: float = 0.7, mix: float = 0.18,
           tone: float = 6000) -> np.ndarray:
    n = int(length * SR)
    ir = rng.standard_normal(n) * np.exp(-np.arange(n) / SR * (6.0 / length))
    ir = lowpass(ir, tone, 2)
    ir /= np.sqrt(np.sum(ir ** 2))
    conv = signal.fftconvolve(x, ir)
    wet = np.zeros(len(x) + n)
    wet[: len(conv)] = conv[: len(x) + n]
    out = np.zeros(len(x) + n)
    out[: len(x)] += x
    return out * (1 - mix) + wet * mix


def normalize(x: np.ndarray, peak_db: float = -1.0) -> np.ndarray:
    peak = np.max(np.abs(x))
    return x if peak == 0 else x / peak * (10 ** (peak_db / 20))


def bell(t: np.ndarray, f0: float, ratios, amps, decays, rng: np.random.Generator,
         jitter: float = 0.004) -> np.ndarray:
    out = np.zeros_like(t)
    for r, a, d in zip(ratios, amps, decays):
        f = f0 * r * (1 + rng.uniform(-jitter, jitter))
        ph = rng.uniform(0, 2 * np.pi)
        out += a * np.sin(2 * np.pi * f * t + ph) * np.exp(-t / d)
    return out


GLASS_RATIOS = [1.0, 2.32, 4.25, 6.63, 9.38]
GLASS_AMPS = [1.0, 0.55, 0.35, 0.2, 0.12]


def crystal_tink(seed: int) -> np.ndarray:
    """Firma del juego: campana de cristal con transitorio de esquirla. Nota base A5 (880 Hz)."""
    rng = np.random.default_rng(seed)
    t = t_axis(1.4)
    f0 = 880 * (1 + rng.uniform(-0.012, 0.012))
    body = bell(t, f0, GLASS_RATIOS, GLASS_AMPS, [1.1, 0.7, 0.4, 0.25, 0.15], rng)
    click = highpass(rng.standard_normal(len(t)), 3500) * np.exp(-t / 0.004) * 0.9
    chip = bandpass(rng.standard_normal(len(t)), 2500, 7000) * np.exp(-t / 0.03) * 0.35
    x = body * 0.8 + click + chip
    return normalize(fade(reverb(x, rng, 0.9, 0.22), 0.0005, 0.08), -1.5)


def shard_clink(seed: int) -> np.ndarray:
    """Fragmento que rebota en el suelo: tintineo agudo y corto."""
    rng = np.random.default_rng(seed)
    t = t_axis(0.45)
    f0 = rng.uniform(2400, 3600)
    x = bell(t, f0, [1.0, 2.7, 5.1], [1.0, 0.4, 0.2], [0.12, 0.06, 0.03], rng, 0.01)
    x += highpass(rng.standard_normal(len(t)), 5000) * np.exp(-t / 0.002) * 0.5
    return normalize(fade(reverb(x, rng, 0.4, 0.12), 0.0005, 0.04), -3)


def shard_break(seed: int) -> np.ndarray:
    """Se desprende un fragmento: crujido de hielo + tintineos."""
    rng = np.random.default_rng(seed)
    t = t_axis(0.6)
    grains = np.zeros_like(t)
    for _ in range(14):
        start = int(rng.uniform(0, 0.09) * SR)
        n = int(rng.uniform(0.002, 0.008) * SR)
        g = rng.standard_normal(n) * np.hanning(n) * rng.uniform(0.4, 1.0)
        grains[start:start + n] += g
    grains = bandpass(grains, 1800, 9000)
    sparkle = bell(t, rng.uniform(1900, 2400), [1.0, 2.6, 4.9], [0.6, 0.3, 0.15], [0.25, 0.12, 0.06], rng)
    x = grains * 1.2 + sparkle * 0.5
    return normalize(fade(reverb(x, rng, 0.5, 0.15), 0.0005, 0.05), -2)


def spark_cast(seed: int) -> np.ndarray:
    """La chispita: un 'pff' débil con chisporroteo. Tiene que sonar humilde."""
    rng = np.random.default_rng(seed)
    t = t_axis(0.35)
    noise = rng.standard_normal(len(t))
    # barrido de filtro hacia arriba (soplido)
    puff = np.zeros_like(t)
    edges = np.linspace(400, 3200, 8)
    seg = len(t) // 8
    for i in range(8):
        part = bandpass(noise, edges[i], edges[i] * 1.8, 2)
        puff[i * seg:(i + 1) * seg] = part[i * seg:(i + 1) * seg]
    puff *= np.exp(-t / 0.08) * (1 - np.exp(-t / 0.006))
    crackle = np.zeros_like(t)
    for _ in range(9):
        p = int(rng.uniform(0.01, 0.25) * SR)
        crackle[p] = rng.uniform(0.5, 1.0) * rng.choice([-1, 1])
    crackle = highpass(crackle, 3000) * 3.0
    chirp_f = 700 + 900 * t / t[-1]
    chirp = np.sin(2 * np.pi * np.cumsum(chirp_f) / SR) * np.exp(-t / 0.05) * 0.25
    x = puff + crackle + chirp
    return normalize(fade(x, 0.001, 0.05), -4)


def spark_fizzle(seed: int) -> np.ndarray:
    """La chispa se apaga sin tocar nada."""
    rng = np.random.default_rng(seed)
    t = t_axis(0.4)
    x = lowpass(rng.standard_normal(len(t)), 2500) * np.exp(-t / 0.09) * (1 - np.exp(-t / 0.01))
    x += highpass(rng.standard_normal(len(t)), 4000) * np.exp(-t / 0.03) * 0.3
    return normalize(fade(x, 0.002, 0.05), -6)


def note(n: int) -> float:
    """Semitonos respecto a A5 (880 Hz)."""
    return 880 * 2 ** (n / 12)


def arpeggio(notes, gap: float, dur: float, seed: int, shimmer: float = 0.3) -> np.ndarray:
    rng = np.random.default_rng(seed)
    t = t_axis(dur)
    x = np.zeros_like(t)
    for i, n in enumerate(notes):
        start = int(i * gap * SR)
        tt = t[: len(t) - start]
        x[start:] += bell(tt, note(n), [1.0, 2.0, 3.01, 4.2], [1.0, 0.3, 0.12, 0.06],
                          [0.9, 0.5, 0.3, 0.2], rng, 0.002) * (0.85 ** i)
    x += bandpass(rng.standard_normal(len(t)), 6000, 14000) * np.exp(-t / 0.4) * shimmer * 0.2
    return normalize(fade(reverb(x, rng, 1.2, 0.3), 0.001, 0.15), -2)


def spark_ready(seed: int) -> np.ndarray:
    """La mano vuelve a estar cargada: campanita suave y baja de volumen."""
    rng = np.random.default_rng(seed)
    t = t_axis(0.7)
    x = bell(t, note(12), [1.0, 2.0, 3.0], [1.0, 0.25, 0.08], [0.35, 0.2, 0.1], rng)
    x *= 1 - np.exp(-t / 0.015)
    return normalize(fade(reverb(x, rng, 0.6, 0.25), 0.002, 0.1), -10)


def loopable(x: np.ndarray, xfade: float = 0.5) -> np.ndarray:
    """Hace el final empalmar con el principio (crossfade)."""
    n = int(xfade * SR)
    head, body, tail = x[:n], x[n:-n], x[-n:]
    ramp = np.linspace(0, 1, n)
    joined = tail * (1 - ramp) + head * ramp
    return np.concatenate([body, joined])


def amb_valley(seed: int) -> np.ndarray:
    """Ambiente del valle: viento suave con ráfagas y algún pájaro lejano."""
    rng = np.random.default_rng(seed)
    dur = 16.0
    t = t_axis(dur + 0.5)
    wind = lowpass(np.cumsum(rng.standard_normal(len(t))) * 0.02, 900, 2)
    wind = highpass(wind, 60, 2)
    gust = 0.55 + 0.45 * np.sin(2 * np.pi * t / 7.3 + 1.0) * np.sin(2 * np.pi * t / 3.1)
    air = bandpass(rng.standard_normal(len(t)), 1500, 5000, 2) * 0.05 * gust
    x = wind / (np.max(np.abs(wind)) + 1e-9) * gust * 0.6 + air
    for _ in range(5):
        start = rng.uniform(0.5, dur - 1.0)
        for k in range(rng.integers(2, 4)):
            s = int((start + k * 0.13) * SR)
            n = int(0.09 * SR)
            tt = np.arange(n) / SR
            f = rng.uniform(3200, 4200) + 1400 * np.sin(np.pi * tt / tt[-1])
            chirp = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.hanning(n) * 0.06
            x[s:s + n] += chirp
    return normalize(loopable(x), -8)


def crystal_hum(seed: int) -> np.ndarray:
    """Zumbido armónico del Cristal Madre. Frecuencias con ciclos enteros en 6 s: empalma solo."""
    rng = np.random.default_rng(seed)
    dur = 6.0
    t = t_axis(dur)
    freqs = [110.0, 165.0, 220.0, 330.0, 440.0 + 1 / 6, 660.0 - 1 / 6, 880.0 + 1 / 3]
    amps = [1.0, 0.6, 0.5, 0.25, 0.18, 0.1, 0.06]
    x = np.zeros_like(t)
    for f, a in zip(freqs, amps):
        x += a * np.sin(2 * np.pi * f * t + rng.uniform(0, 2 * np.pi))
    lfo = 0.8 + 0.2 * np.sin(2 * np.pi * t / 3.0)
    return normalize(x * lfo, -9)


def write(out: Path, name: str, x: np.ndarray) -> None:
    """Escribe OGG Vorbis (vía ffmpeg) para no inflar el repo; si no hay ffmpeg, WAV."""
    out.mkdir(parents=True, exist_ok=True)
    if not np.all(np.isfinite(x)):
        raise ValueError(f"{name}: muestras no finitas")
    data = (np.clip(x, -1, 1) * 32767).astype(np.int16)
    wav = out / f"{name}.wav"
    wavfile.write(wav, SR, data)
    if shutil.which("ffmpeg"):
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(wav), "-c:a", "libvorbis",
                        "-q:a", "6", str(out / f"{name}.ogg")], check=True)
        wav.unlink()


def main() -> None:
    ap = argparse.ArgumentParser()
    root = Path(__file__).resolve().parent.parent
    ap.add_argument("--out", default=str(root / "game" / "audio" / "sfx"))
    out = Path(ap.parse_args().out)
    for i in range(4):
        write(out, f"sfx_crystal_tink_{i + 1:02d}", crystal_tink(100 + i))
        write(out, f"sfx_shard_clink_{i + 1:02d}", shard_clink(200 + i))
    for i in range(3):
        write(out, f"sfx_shard_break_{i + 1:02d}", shard_break(300 + i))
        write(out, f"sfx_spark_cast_{i + 1:02d}", spark_cast(400 + i))
    write(out, "sfx_spark_fizzle_01", spark_fizzle(500))
    write(out, "sfx_spark_ready_01", spark_ready(600))
    # A mayor pentatónica, en semitonos desde A5
    write(out, "sfx_resonant_hit_01", arpeggio([0, 4, 7, 12, 16], 0.035, 1.6, 700, 0.6))
    write(out, "sfx_streak_chime_01", arpeggio([7, 12, 16], 0.06, 1.2, 800, 0.3))
    write(out, "amb_valley_loop", amb_valley(900))
    write(out, "amb_crystal_hum_loop", crystal_hum(1000))
    print(f"SFX escritos en {out}")


if __name__ == "__main__":
    main()
