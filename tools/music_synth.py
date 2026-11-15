#!/usr/bin/env python3
"""Compone y sintetiza la música del valle ("Valle del Cristal") en capas que se suman con el rango del mago.

Uso:
    python3 tools/music_synth.py                 # escribe en game/audio/music/
    python3 tools/music_synth.py --out DIR --preview   # además, una mezcla completa para escuchar

Requiere numpy, scipy y ffmpeg. Determinista: mismas semillas, mismos archivos.

Teoría aplicada
---------------
- Tonalidad: La mayor, la misma del "tink" del cristal (A5) y de su escala pentatónica de racha, así cada golpe
  armoniza con la música. El zumbido del cristal también está en La.
- Color mágico: modo lidio prestado (acorde de II mayor, B/A, con el D# que es la #4 de La) y el iv menor prestado
  (Dm6) al final de la segunda frase, para un momento agridulce antes de volver.
- Forma: 16 compases a 84 BPM (~46 s), dos frases de 8 (pregunta que termina en semicadencia sobre E y respuesta
  más aguda). El compás 16 es dominante (E) y resuelve en el Amaj9 del compás 1: el bucle se siente como una vuelta,
  no como un corte.
- Melodía escrita a mano sobre la pentatónica de La (consonante con los "tinks"), con notas de color (G#, D#) sólo
  donde el acorde las contiene y apoyaturas que resuelven por grado conjunto (sus4 -> 3 en el compás 8).
- Pad y contramelodía con conducción de voces automática: de entre las inversiones posibles se elige la que menos
  mueve las voces respecto al acorde anterior. La contramelodía sigue las notas guía (3.ª y 7.ª) del acorde.
- Las colas de reverb que sobran al final se suman al principio: el bucle empalma sin clic ni hueco.

Capas (se reproducen sincronizadas con AudioStreamSynchronized; GDD: la música añade capas con cada rango):
    1 Aprendiz   pad + bajo + caja de música (melodía)
    2 Iniciado   arpa en corcheas
    3 Hechicero  percusión suave (bombo blando, shaker, bloque de madera)
    4 Magus      contramelodía de flauta
    5 Archimago  destellos de celesta aguda y coro etéreo
"""
import argparse
import shutil
import subprocess
from pathlib import Path

import numpy as np
from scipy import signal
from scipy.io import wavfile

SR = 44100
BPM = 84.0
BEAT = 60.0 / BPM
BEATS_PER_BAR = 4
BARS = 16
LOOP_SEC = BARS * BEATS_PER_BAR * BEAT
LOOP_N = int(round(LOOP_SEC * SR))
TAIL_SEC = 5.0

# Nombres de nota -> MIDI (A4 = 69).
_PC = {"C": 0, "C#": 1, "Db": 1, "D": 2, "D#": 3, "Eb": 3, "E": 4, "F": 5, "F#": 6, "Gb": 6,
       "G": 7, "G#": 8, "Ab": 8, "A": 9, "A#": 10, "Bb": 10, "B": 11}


def m(name: str) -> int:
    """'C#5' -> 73."""
    pitch, octave = name[:-1], int(name[-1])
    return 12 * (octave + 1) + _PC[pitch]


def hz(midi: float) -> float:
    return 440.0 * 2.0 ** ((midi - 69) / 12.0)


# ---------------------------------------------------------------------------------------------
# Armonía: (raíz, notas del acorde como clases de altura relativas a la raíz, bajo opcional)
# ---------------------------------------------------------------------------------------------
MAJ9 = [0, 4, 7, 11, 14]
MIN9 = [0, 3, 7, 10, 14]
MIN7 = [0, 3, 7, 10]
MAJ = [0, 4, 7]
SUS4 = [0, 5, 7]
MIN6 = [0, 3, 7, 9]

# Un acorde por compás; el 8 y el 16 se dividen (sus4 -> mayor) en dos mitades.
PROGRESSION = [
    # Frase A (pregunta)
    [("A", MAJ9, "A")],
    [("B", MAJ, "A")],  # II lidio sobre pedal de A: el "brillo mágico"
    [("F#", MIN9, "F#")],
    [("D", MAJ9, "D")],
    [("A", MAJ9, "A")],
    [("B", MAJ, "A")],
    [("C#", MIN7, "C#")],
    [("E", SUS4, "E"), ("E", MAJ, "E")],  # semicadencia con apoyatura sus4 -> 3
    # Frase B (respuesta, más aguda)
    [("D", MAJ9, "D")],
    [("E", MAJ, "D")],
    [("C#", MIN7, "C#")],
    [("F#", MIN9, "F#")],
    [("B", MIN9, "B")],
    [("D", MIN6, "D")],  # iv menor prestado: agridulce
    [("E", SUS4, "E")],
    [("E", MAJ, "E")],  # dominante: resuelve en el compás 1 al dar la vuelta
]


def chord_events():
    """[(inicio en pulsos, duración en pulsos, raíz pc, intervalos, bajo pc)]."""
    out = []
    for bar, chords in enumerate(PROGRESSION):
        span = BEATS_PER_BAR / len(chords)
        for i, (root, ints, bass) in enumerate(chords):
            out.append((bar * BEATS_PER_BAR + i * span, span, _PC[root], ints, _PC[bass]))
    return out


def pitch_classes(root: int, ints) -> set:
    return {(root + i) % 12 for i in ints}


def voice_lead(prev, pcs: set, n_voices: int, lo: int, hi: int):
    """Elige n_voices notas del acorde en [lo, hi] que menos se muevan respecto a `prev`.
    Prioriza contener 3.ª/7.ª (las da `pcs` ordenado por importancia) y evita clusters de semitono."""
    cands = [n for n in range(lo, hi + 1) if n % 12 in pcs]
    best, best_cost = None, 1e9
    rng = np.random.default_rng(0)
    # Búsqueda sencilla: combinaciones crecientes (pocos candidatos, es barato).
    from itertools import combinations
    for combo in combinations(cands, n_voices):
        gaps = np.diff(combo)
        if np.any(gaps < 2) or combo[-1] - combo[0] > 19:
            continue
        covered = len({c % 12 for c in combo})
        cost = (len(pcs) - covered) * 6.0
        if prev is not None:
            cost += sum(abs(a - b) for a, b in zip(combo, prev))
        else:
            cost += abs(np.mean(combo) - (lo + hi) / 2) * 0.5
        cost += rng.uniform(0, 1e-3)
        if cost < best_cost:
            best, best_cost = combo, cost
    return list(best)


# ---------------------------------------------------------------------------------------------
# Melodía (compás 1-16, pulso dentro del compás, duración en pulsos, nota)
# ---------------------------------------------------------------------------------------------
MELODY = [
    # 1 Amaj9: el motivo (5 - 3 - 2 - 3)
    (1, 0, 1.5, "E5"), (1, 1.5, 0.5, "C#5"), (1, 2, 1, "B4"), (1, 3, 1, "C#5"),
    # 2 B/A: el D# lidio
    (2, 0, 1.5, "D#5"), (2, 1.5, 0.5, "F#5"), (2, 2, 0.5, "D#5"), (2, 2.5, 0.5, "C#5"), (2, 3, 1, "B4"),
    # 3 F#m9
    (3, 0, 1, "A4"), (3, 1, 1, "C#5"), (3, 2, 1.5, "E5"), (3, 3.5, 0.5, "F#5"),
    # 4 Dmaj9: nota larga sobre la 9.ª
    (4, 0, 3, "E5"), (4, 3, 1, "C#5"),
    # 5 Amaj9: el motivo vuelve
    (5, 0, 1.5, "E5"), (5, 1.5, 0.5, "C#5"), (5, 2, 1, "B4"), (5, 3, 1, "C#5"),
    # 6 B/A: ahora sube
    (6, 0, 1.5, "D#5"), (6, 1.5, 0.5, "F#5"), (6, 2, 1.5, "A5"), (6, 3.5, 0.5, "G#5"),
    # 7 C#m7: baja por arpegio
    (7, 0, 1, "G#5"), (7, 1, 1, "E5"), (7, 2, 1, "C#5"), (7, 3, 1, "B4"),
    # 8 Esus4 -> E: apoyatura A -> G#
    (8, 0, 1, "B4"), (8, 1, 1, "A4"), (8, 2, 2, "G#4"),
    # 9 Dmaj9: la respuesta empieza más aguda
    (9, 0, 1, "F#5"), (9, 1, 1, "A5"), (9, 2, 1, "E5"), (9, 3, 1, "F#5"),
    # 10 E/D
    (10, 0, 1.5, "G#5"), (10, 1.5, 0.5, "B5"), (10, 2, 1, "G#5"), (10, 3, 1, "E5"),
    # 11 C#m7: el punto más alto de la pieza
    (11, 0, 1, "E5"), (11, 1, 1, "G#5"), (11, 2, 1.5, "B5"), (11, 3.5, 0.5, "A5"),
    # 12 F#m9: la 9.ª (G#) como nota larga
    (12, 0, 2, "G#5"), (12, 2, 1, "F#5"), (12, 3, 1, "E5"),
    # 13 Bm9
    (13, 0, 1.5, "D5"), (13, 1.5, 0.5, "C#5"), (13, 2, 1, "B4"), (13, 3, 1, "D5"),
    # 14 Dm6: el F natural agridulce
    (14, 0, 2, "F5"), (14, 2, 1, "D5"), (14, 3, 1, "A4"),
    # 15 Esus4
    (15, 0, 1, "B4"), (15, 1, 1, "A4"), (15, 2, 1, "B4"), (15, 3, 1, "E5"),
    # 16 E: anacrusa hacia el E5 del compás 1
    (16, 0, 2, "G#4"), (16, 2, 1.5, "B4"), (16, 3.5, 0.5, "D5"),
]


# ---------------------------------------------------------------------------------------------
# Utilidades de síntesis
# ---------------------------------------------------------------------------------------------
def lowpass(x, f, order=2):
    return signal.sosfilt(signal.butter(order, f, btype="low", fs=SR, output="sos"), x)


def highpass(x, f, order=2):
    return signal.sosfilt(signal.butter(order, f, btype="high", fs=SR, output="sos"), x)


def bandpass(x, lo, hi, order=2):
    return signal.sosfilt(signal.butter(order, [lo, hi], btype="band", fs=SR, output="sos"), x)


def adsr(n, a, d, s, r, hold_n):
    """Envolvente de n muestras: ataque, caída, sostenido hasta hold_n y relajación."""
    env = np.zeros(n)
    a_n, d_n, r_n = max(1, int(a * SR)), max(1, int(d * SR)), max(1, int(r * SR))
    i = np.arange(n)
    env = np.where(i < a_n, i / a_n, 0.0)
    dec = (i >= a_n) & (i < a_n + d_n)
    env[dec] = 1.0 - (1.0 - s) * (i[dec] - a_n) / d_n
    env[(i >= a_n + d_n) & (i < hold_n)] = s
    rel = i >= hold_n
    level = env[min(hold_n, n) - 1] if hold_n > 0 else 0.0
    env[rel] = level * np.exp(-(i[rel] - hold_n) / r_n * 5.0)
    return env


class Track:
    """Pista estéreo del largo del bucle + cola; las notas se suman con paneo de potencia constante."""

    def __init__(self):
        self.buf = np.zeros((2, LOOP_N + int(TAIL_SEC * SR)))

    def add(self, start_sec, x, pan=0.0, gain=1.0):
        s = int(start_sec * SR)
        e = min(s + len(x), self.buf.shape[1])
        if e <= s:
            return
        ang = (pan + 1.0) * np.pi / 4.0
        self.buf[0, s:e] += x[: e - s] * np.cos(ang) * gain
        self.buf[1, s:e] += x[: e - s] * np.sin(ang) * gain


def additive(f, n, harmonics, amps, decays=None, detune_cents=0.0, rng=None, max_f=9000.0):
    t = np.arange(n) / SR
    x = np.zeros(n)
    for k, (h, a) in enumerate(zip(harmonics, amps)):
        fk = f * h * 2 ** (detune_cents / 1200.0)
        if fk > max_f:
            break
        ph = rng.uniform(0, 2 * np.pi) if rng is not None else 0.0
        part = a * np.sin(2 * np.pi * fk * t + ph)
        if decays is not None:
            part *= np.exp(-t / decays[k])
        x += part
    return x


# ---------------------------------------------------------------------------------------------
# Instrumentos
# ---------------------------------------------------------------------------------------------
def inst_pad(f, dur, rng):
    """Pad cálido: tres "sierras" aditivas desafinadas, filtradas, ataque lento."""
    n = int((dur + 1.6) * SR)
    h = np.arange(1, 14)
    a = 1.0 / h
    x = sum(additive(f, n, h, a, detune_cents=c, rng=rng, max_f=5000) for c in (-7, 0, 6))
    x = lowpass(x, 1400, 2)
    t = np.arange(n) / SR
    x *= 1.0 + 0.08 * np.sin(2 * np.pi * 0.25 * t + rng.uniform(0, 6))
    return x * adsr(n, 0.6, 0.5, 0.75, 1.2, int(dur * SR)) * 0.08


def inst_bass(f, dur, rng):
    """Bajo redondo: seno + un poco de 2.º y 3.º armónico, ataque con "pluck" suave."""
    n = int((dur + 0.6) * SR)
    x = additive(f, n, [1, 2, 3], [1.0, 0.35, 0.12], rng=rng)
    x = lowpass(x, 700, 2)
    return x * adsr(n, 0.012, 0.35, 0.6, 0.35, int(dur * 0.92 * SR)) * 0.42


def inst_music_box(f, dur, rng):
    """Caja de música / celesta: parciales casi armónicos con caída larga y leve trémolo."""
    n = int((dur + 2.2) * SR)
    x = additive(f, n, [1, 2, 3.0, 4.07, 5.4], [1.0, 0.45, 0.16, 0.09, 0.04],
                 decays=[1.6, 0.8, 0.4, 0.25, 0.12], rng=rng)
    t = np.arange(n) / SR
    x *= 1.0 + 0.05 * np.sin(2 * np.pi * 5.5 * t)
    att = np.minimum(1.0, t / 0.003)
    # Apagado suave al llegar la siguiente nota larga, sin cortar la resonancia del todo.
    damp = np.where(t > dur + 0.4, np.exp(-(t - dur - 0.4) * 2.5), 1.0)
    return x * att * damp * 0.26


def inst_harp(f, dur, rng):
    """Arpa: pulsado aditivo, los armónicos agudos mueren antes (como Karplus-Strong)."""
    n = int(2.2 * SR)
    h = np.arange(1, 9)
    a = 1.0 / h ** 1.3
    d = 1.4 / h ** 0.8
    x = additive(f, n, h, a, decays=d, rng=rng)
    t = np.arange(n) / SR
    pluck = highpass(rng.standard_normal(n), 2000) * np.exp(-t / 0.004) * 0.15
    return (x + pluck) * np.minimum(1.0, t / 0.002) * 0.15


def inst_flute(f, dur, rng):
    """Flauta suave: casi seno, vibrato que entra tarde y soplo filtrado."""
    n = int((dur + 0.5) * SR)
    t = np.arange(n) / SR
    vib = 1.0 + 0.004 * np.sin(2 * np.pi * 5.0 * t) * np.clip((t - 0.35) / 0.5, 0, 1)
    phase = 2 * np.pi * np.cumsum(f * vib) / SR
    x = np.sin(phase) + 0.18 * np.sin(2 * phase) + 0.06 * np.sin(3 * phase)
    breath = bandpass(rng.standard_normal(n), f * 1.5, min(f * 6, 12000)) * 0.05
    return (x + breath) * adsr(n, 0.18, 0.2, 0.85, 0.3, int(dur * SR)) * 0.13


def inst_celesta_high(f, dur, rng):
    n = int(2.0 * SR)
    x = additive(f, n, [1, 2, 3.0, 4.2], [1.0, 0.3, 0.1, 0.05], decays=[0.9, 0.4, 0.2, 0.1], rng=rng)
    t = np.arange(n) / SR
    return x * np.minimum(1.0, t / 0.002) * 0.09


def inst_choir(f, dur, rng):
    """Coro etéreo: vocal "aa" aproximada con dos formantes sobre una sierra suave."""
    n = int((dur + 1.5) * SR)
    t = np.arange(n) / SR
    vib = 1.0 + 0.005 * np.sin(2 * np.pi * 4.6 * t + rng.uniform(0, 6))
    phase = 2 * np.pi * np.cumsum(f * vib) / SR
    src = sum(np.sin(k * phase) / k for k in range(1, 20) if f * k < 8000)
    x = bandpass(src, 650, 1100) * 0.8 + bandpass(src, 2400, 3200) * 0.3 + np.sin(phase) * 0.3
    return x * adsr(n, 1.0, 0.5, 0.8, 1.2, int(dur * SR)) * 0.05


def drum_kick(rng):
    n = int(0.45 * SR)
    t = np.arange(n) / SR
    f = 48 + 70 * np.exp(-t / 0.035)
    x = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.16)
    return lowpass(x, 400) * 0.55


def drum_shaker(rng, accent):
    n = int(0.12 * SR)
    t = np.arange(n) / SR
    x = bandpass(rng.standard_normal(n), 5000, 11000) * (t / 0.012).clip(0, 1) * np.exp(-t / 0.035)
    return x * (0.07 if accent else 0.04)


def drum_block(rng):
    n = int(0.25 * SR)
    t = np.arange(n) / SR
    x = np.sin(2 * np.pi * 1250 * t) * np.exp(-t / 0.035) + 0.4 * np.sin(2 * np.pi * 1870 * t) * np.exp(-t / 0.02)
    return x * 0.08


# ---------------------------------------------------------------------------------------------
# Efectos y mezcla
# ---------------------------------------------------------------------------------------------
def reverb_stereo(buf, seed, length=2.6, mix=0.3, predelay=0.02, tone=5500):
    rng = np.random.default_rng(seed)
    n = int(length * SR)
    out = np.empty_like(buf)
    for ch in range(2):
        ir = rng.standard_normal(n) * np.exp(-np.arange(n) / SR * (6.9 / length))
        ir = lowpass(ir, tone, 1)
        ir = np.concatenate([np.zeros(int(predelay * SR)), ir])
        ir /= np.sqrt(np.sum(ir ** 2))
        wet = signal.fftconvolve(buf[ch], ir)[: buf.shape[1]]
        out[ch] = buf[ch] * (1 - mix) + wet * mix
    return out


def fold_loop(buf):
    """Suma la cola (reverb, notas que se pasan) al principio: bucle sin costura."""
    out = buf[:, :LOOP_N].copy()
    tail = buf[:, LOOP_N:]
    k = min(tail.shape[1], LOOP_N)
    out[:, :k] += tail[:, :k]
    return out


def sec(beats):
    return beats * BEAT


# ---------------------------------------------------------------------------------------------
# Composición de cada capa
# ---------------------------------------------------------------------------------------------
def layer_aprendiz():
    rng = np.random.default_rng(11)
    pad, bass, box = Track(), Track(), Track()
    prev = None
    for start, dur, root, ints, bass_pc in chord_events():
        pcs = pitch_classes(root, ints)
        voicing = voice_lead(prev, pcs, 4, m("E3"), m("D5"))
        prev = voicing
        for i, note in enumerate(voicing):
            pad.add(sec(start), inst_pad(hz(note), sec(dur), rng), pan=-0.5 + i / 3.0)
        # Bajo: raíz en el pulso 1 y quinta (u octava) en el 3; pedal en los acordes sobre otra nota.
        b = 33 + (bass_pc - 9) % 12  # entre A1 y G#2
        if dur >= 4:
            second = b + 7 if bass_pc == root else b + 12
            bass.add(sec(start), inst_bass(hz(b), sec(2.5), rng))
            bass.add(sec(start + 2.5), inst_bass(hz(b), sec(0.5), rng), gain=0.6)
            bass.add(sec(start + 3), inst_bass(hz(second), sec(1), rng), gain=0.8)
        else:
            bass.add(sec(start), inst_bass(hz(b), sec(dur), rng))
    for bar, beat, dur, name in MELODY:
        start = (bar - 1) * BEATS_PER_BAR + beat
        box.add(sec(start), inst_music_box(hz(m(name)), sec(dur), rng), pan=0.1)
    mix = pad.buf * 0.9 + bass.buf + box.buf
    return reverb_stereo(mix, 1, mix=0.28)


def layer_iniciado():
    rng = np.random.default_rng(22)
    harp = Track()
    # Arpegio en corcheas: sube por notas del acorde y baja, cruzando dos octavas.
    shape = [0, 2, 4, 5, 6, 5, 4, 2]
    for start, dur, root, ints, _bass in chord_events():
        pcs = sorted(pitch_classes(root, ints), key=lambda p: (p - root) % 12)
        notes = []
        base = 45 + (root - 9) % 12  # raíz entre A2 y G#3
        for octv in range(3):
            for p in pcs:
                n = base + 12 * octv + (p - root) % 12
                if m("A2") <= n <= m("E5"):
                    notes.append(n)
        notes = sorted(set(notes))
        steps = int(dur * 2)
        for k in range(steps):
            idx = shape[k % len(shape)] % len(notes)
            vel = 1.0 if k % 2 == 0 else 0.75
            t0 = start + k * 0.5
            harp.add(sec(t0) + rng.uniform(0, 0.006), inst_harp(hz(notes[idx]), 0.5, rng),
                     pan=-0.35 + 0.1 * (idx % 3), gain=vel)
    return reverb_stereo(harp.buf, 2, mix=0.32)


def layer_hechicero():
    rng = np.random.default_rng(33)
    perc = Track()
    total_beats = BARS * BEATS_PER_BAR
    for b in range(BARS):
        s = b * BEATS_PER_BAR
        perc.add(sec(s), drum_kick(rng))
        perc.add(sec(s + 2.5), drum_kick(rng), gain=0.6)
        perc.add(sec(s + 1), drum_block(rng), pan=0.35)
        perc.add(sec(s + 3), drum_block(rng), pan=0.35, gain=0.8)
    for k in range(int(total_beats * 2)):
        # Swing ligero en las corcheas a contratiempo.
        t0 = k * 0.5 + (0.06 if k % 2 else 0.0)
        perc.add(sec(t0), drum_shaker(rng, k % 2 == 1), pan=-0.3)
    return reverb_stereo(perc.buf, 3, length=1.2, mix=0.18)


def layer_magus():
    """Contramelodía: notas guía (3.ª o 7.ª) en registro de alto, blancas, con conducción mínima."""
    rng = np.random.default_rng(44)
    fl = Track()
    prev = m("C#5")
    for start, dur, root, ints, _bass in chord_events():
        guide_pcs = {(root + i) % 12 for i in ints if i in (3, 4, 10, 11, 14)} or pitch_classes(root, ints)
        halves = max(1, int(dur // 2))
        for h in range(halves):
            cands = [n for n in range(m("F#4"), m("E5") + 1) if n % 12 in guide_pcs and n != prev]
            cands = cands or [prev]
            # En el segundo tiempo, una nota distinta (movimiento), cerca de la anterior.
            note = min(cands, key=lambda n: abs(n - prev) + rng.uniform(0, 0.5))
            fl.add(sec(start + h * 2), inst_flute(hz(note), sec(min(2, dur)), rng), pan=-0.25)
            prev = note
    return reverb_stereo(fl.buf, 4, mix=0.35)


def layer_archimago():
    rng = np.random.default_rng(55)
    sp, ch = Track(), Track()
    penta = {9, 11, 1, 4, 6}  # A B C# E F#: la escala de los "tinks"
    for start, dur, root, ints, _bass in chord_events():
        pcs = pitch_classes(root, ints) & penta or pitch_classes(root, ints)
        pool = [n for n in range(m("A5"), m("E7") + 1) if n % 12 in pcs]
        # Destellos a contratiempo, escasos y deterministas.
        for k in range(int(dur * 2)):
            if k % 2 == 1 and rng.random() < 0.45:
                ch_n = pool[rng.integers(len(pool))]
                sp.add(sec(start + k * 0.5), inst_celesta_high(hz(ch_n), 0.5, rng), pan=rng.uniform(-0.8, 0.8))
        # Coro: dos voces (raíz y quinta) dos octavas arriba del bajo.
        for iv in (0, 7):
            ch.add(sec(start), inst_choir(hz(57 + (root - 9) % 12 + iv), sec(dur), rng), pan=-0.4 if iv else 0.4)
    mix = sp.buf + ch.buf
    return reverb_stereo(mix, 5, length=3.5, mix=0.45)


LAYERS = [
    ("music_valley_1_aprendiz", layer_aprendiz, 0.0),
    ("music_valley_2_iniciado", layer_iniciado, 0.0),
    ("music_valley_3_hechicero", layer_hechicero, 2.0),
    ("music_valley_4_magus", layer_magus, 4.0),
    ("music_valley_5_archimago", layer_archimago, 4.0),
]


def write(out: Path, name: str, x: np.ndarray) -> None:
    out.mkdir(parents=True, exist_ok=True)
    if not np.all(np.isfinite(x)):
        raise ValueError(f"{name}: muestras no finitas")
    data = (np.clip(x.T, -1, 1) * 32767).astype(np.int16)
    wav = out / f"{name}.wav"
    wavfile.write(wav, SR, data)
    if shutil.which("ffmpeg"):
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(wav), "-c:a", "libvorbis",
                        "-q:a", "5", str(out / f"{name}.ogg")], check=True)
        wav.unlink()


def main() -> None:
    ap = argparse.ArgumentParser()
    root = Path(__file__).resolve().parent.parent
    ap.add_argument("--out", default=str(root / "game" / "audio" / "music"))
    ap.add_argument("--preview", default="", help="ruta de una mezcla completa (2 vueltas) para escuchar")
    args = ap.parse_args()
    out = Path(args.out)
    stems = []
    for name, fn, gain_db in LAYERS:
        # Filtro de subgraves: nada por debajo de 35 Hz (sólo ocupa margen y retumba en altavoces pequeños).
        x = highpass(fold_loop(fn()), 35, 2) * 10 ** (gain_db / 20)
        stems.append((name, x))
    # Un solo factor de normalización para todas: el balance entre capas se conserva.
    full = sum(x for _, x in stems)
    k = 10 ** (-1.5 / 20) / np.max(np.abs(full))
    for name, x in stems:
        write(out, name, x * k)
    print(f"Música escrita en {out} ({LOOP_SEC:.1f} s por vuelta, {BPM:.0f} BPM)")
    if args.preview:
        # Vista previa: 4 vueltas seguidas; cada media vuelta entra una capa nueva (con fundido corto),
        # como pasaría al subir de rango.
        loops = 4
        half = LOOP_N // 2
        fade_n = int(1.5 * SR)
        prev = np.zeros((2, LOOP_N * loops))
        for i, (_, x) in enumerate(stems):
            tiled = np.tile(x, (1, loops))
            gate = np.zeros(LOOP_N * loops)
            s = i * half
            gate[s:] = 1.0
            if s > 0:
                gate[s:s + fade_n] = np.linspace(0, 1, fade_n)
            prev += tiled * gate
        prev *= k
        p = Path(args.preview)
        write(p.parent, p.stem, prev)
        print(f"Vista previa en {p.parent / (p.stem + '.ogg')}")


if __name__ == "__main__":
    main()
