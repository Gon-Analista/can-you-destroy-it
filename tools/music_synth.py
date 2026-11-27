#!/usr/bin/env python3
"""Compone y sintetiza la música del valle ("Valle del Cristal") en capas que se suman con el rango del mago.

Uso:
    python3 tools/music_synth.py                       # escribe en game/audio/music/
    python3 tools/music_synth.py --preview RUTA.ogg    # además, una mezcla donde las capas van entrando

Requiere numpy, scipy y ffmpeg. Determinista: mismas semillas, mismos archivos.

Por qué esta versión
--------------------
La primera era un bucle de 16 compases (46 s) con el mismo acompañamiento de principio a fin: a los pocos minutos
aburría. Esta es una pieza de 56 compases a 96 BPM (2 min 20 s) con forma de canción, estribillo pegadizo y
secciones que cambian de energía, de modo que incluso con una sola capa (rango Aprendiz) el oído tiene a dónde ir.

Teoría aplicada
---------------
- Tonalidad: La mayor, la del "tink" del cristal (A5) y su pentatónica de racha: cada golpe armoniza. Todo el
  material sale de la escala de La; el color mágico lo dan el II lidio (B/A, con D#) y el iv menor prestado (Dm6).
- Forma (compases): Intro 4 · A 8 · A' 8 · B 8 · B' 8 · C 8 · A'' 8 · Coda 4.
    Intro  pad y caja de música que anuncia el motivo.
    A      el estribillo: I - V/3 - vi - IV (A, E/G#, F#m7, Dmaj7), el giro más pegadizo que hay; motivo con
           anacrusa sincopada (E - C# E - A) que sube a la 8.ª y baja.
    A'     respuesta que cierra en La (Bm7 - E - A).
    B      aventura en F#m (vi - IV - I - V), registro grave, corcheas que empujan: sube la energía.
    B'     sube hacia el II lidio (B/A): la parte "mágica", con suspensión antes del puente.
    C      puente soñado a medio tiempo: Dmaj9 - Dm6 (agridulce), la flauta canta; la percusión casi desaparece
           y vuelve con un redoble que lanza el clímax.
    A''    el estribillo en su versión más grande (platillo, campanas a la octava, arpegio brillante).
    Coda   bloque de madera de la versión anterior, guiño; Esus4 -> E resuelve en el La del principio.
- Pad con conducción de voces automática (la inversión que menos mueve las voces); contramelodía sobre notas guía.
- Acompañamiento por patrones que cambian por sección (bajo sincopado en A, corcheas en B, notas largas en C) y
  un pequeño desvío humano de tiempo y fuerza en cada nota, para que no suene a metrónomo.
- Las colas de reverb que sobran al final se suman al principio: el bucle empalma sin clic ni hueco.

Capas (se reproducen sincronizadas con AudioStreamSynchronized; GDD: la música añade capas con cada rango):
    1 Aprendiz   pad + bajo + caja de música (melodía) + kalimba (ostinato rítmico)
    2 Iniciado   arpa por secciones y campanitas que contestan a la melodía
    3 Hechicero  batería suave (bombo, caja con escobilla, charles, shaker, toms) con redobles entre secciones
    4 Magus      flauta (contramelodía y melodía del puente) y cuerdas
    5 Archimago  coro etéreo, destellos de celesta, arpegio brillante y campanas que doblan el estribillo
"""
import argparse
import shutil
import subprocess
from collections import namedtuple
from itertools import combinations
from pathlib import Path

import numpy as np
from scipy import signal
from scipy.io import wavfile

SR = 44100
BPM = 96.0
BEAT = 60.0 / BPM
BEATS_PER_BAR = 4
TAIL_SEC = 6.0

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
# Armonía y forma
# ---------------------------------------------------------------------------------------------
MAJ = [0, 4, 7]
ADD9 = [0, 4, 7, 14]
MAJ7 = [0, 4, 7, 11]
MAJ9 = [0, 4, 7, 11, 14]
MIN7 = [0, 3, 7, 10]
MIN9 = [0, 3, 7, 10, 14]
SUS4 = [0, 5, 7]
MIN6 = [0, 3, 7, 9]


def c(root, ints, bass=None):
    return (root, ints, bass or root)


A9, E_G, FM7, DM7 = c("A", ADD9), c("E", MAJ, "G#"), c("F#", MIN7), c("D", MAJ7)
ESUS_E = [c("E", SUS4), c("E", MAJ)]

# Cada sección: nombre, estilo (elige los patrones de acompañamiento), acordes por compás (uno o dos por compás)
# y melodía como (compás de la sección, pulso, duración en pulsos, nota).
SECTIONS = [
    ("intro", "calma", [[c("A", MAJ9)], [c("D", MAJ9)], [c("A", MAJ9)], ESUS_E], [
        (3, 2, 1, "E5"), (3, 3, 1, "C#5"),
        (4, 0, 2, "B4"), (4, 2, 1, "G#4"), (4, 3, 1, "B4"),
    ]),
    ("A", "estribillo", [[A9], [E_G], [FM7], [DM7], [A9], [E_G], [DM7], ESUS_E], [
        (1, 0, 1, "E5"), (1, 1, 0.5, "C#5"), (1, 1.5, 0.5, "E5"), (1, 2, 1.5, "A5"), (1, 3.5, 0.5, "G#5"),
        (2, 0, 1.5, "G#5"), (2, 1.5, 0.5, "E5"), (2, 2, 2, "B4"),
        (3, 0, 1, "C#5"), (3, 1, 0.5, "E5"), (3, 1.5, 0.5, "F#5"), (3, 2, 1.5, "A5"), (3, 3.5, 0.5, "G#5"),
        (4, 0, 2, "F#5"), (4, 2, 1, "E5"), (4, 3, 1, "C#5"),
        (5, 0, 1, "E5"), (5, 1, 0.5, "C#5"), (5, 1.5, 0.5, "E5"), (5, 2, 1.5, "A5"), (5, 3.5, 0.5, "G#5"),
        (6, 0, 1.5, "G#5"), (6, 1.5, 0.5, "B5"), (6, 2, 1, "G#5"), (6, 3, 1, "E5"),
        (7, 0, 1, "F#5"), (7, 1, 1, "A5"), (7, 2, 1, "C#6"), (7, 3, 1, "B5"),
        (8, 0, 1, "A5"), (8, 1, 1, "B5"), (8, 2, 2, "G#5"),
    ]),
    ("A2", "estribillo", [[A9], [E_G], [FM7], [DM7], [c("B", MIN7)], [c("E", MAJ)], [A9],
                          [c("A", MAJ9), c("C#", MIN7)]], [
        (1, 0, 1, "E5"), (1, 1, 0.5, "C#5"), (1, 1.5, 0.5, "E5"), (1, 2, 1.5, "A5"), (1, 3.5, 0.5, "G#5"),
        (2, 0, 1.5, "G#5"), (2, 1.5, 0.5, "E5"), (2, 2, 2, "B4"),
        (3, 0, 1, "C#5"), (3, 1, 0.5, "E5"), (3, 1.5, 0.5, "F#5"), (3, 2, 1.5, "A5"), (3, 3.5, 0.5, "G#5"),
        (4, 0, 1, "F#5"), (4, 1, 1, "A5"), (4, 2, 2, "E5"),
        (5, 0, 1.5, "D5"), (5, 1.5, 0.5, "F#5"), (5, 2, 1, "A5"), (5, 3, 1, "F#5"),
        (6, 0, 1.5, "G#5"), (6, 1.5, 0.5, "E5"), (6, 2, 1, "D5"), (6, 3, 1, "B4"),
        (7, 0, 3.5, "C#5"),
        (8, 2.5, 0.5, "C#5"), (8, 3, 0.5, "E5"), (8, 3.5, 0.5, "G#4"),
    ]),
    ("B", "aventura", [[c("F#", MIN7)], [c("D", ADD9)], [c("A", MAJ)], [c("E", MAJ)],
                       [c("F#", MIN7)], [c("D", MAJ)], [c("B", MIN7)], ESUS_E], [
        (1, 0, 0.5, "F#4"), (1, 0.5, 0.5, "A4"), (1, 1, 1, "C#5"), (1, 2, 0.5, "B4"), (1, 2.5, 0.5, "A4"),
        (1, 3, 1, "C#5"),
        (2, 0, 1.5, "D5"), (2, 1.5, 0.5, "C#5"), (2, 2, 1, "A4"), (2, 3, 1, "F#4"),
        (3, 0, 0.5, "E5"), (3, 0.5, 0.5, "E5"), (3, 1, 1, "C#5"), (3, 2, 0.5, "E5"), (3, 2.5, 0.5, "F#5"),
        (3, 3, 1, "E5"),
        (4, 0, 2, "B4"), (4, 2, 1, "G#4"), (4, 3, 1, "B4"),
        (5, 0, 0.5, "F#4"), (5, 0.5, 0.5, "A4"), (5, 1, 1, "C#5"), (5, 2, 0.5, "B4"), (5, 2.5, 0.5, "A4"),
        (5, 3, 1, "C#5"),
        (6, 0, 1.5, "D5"), (6, 1.5, 0.5, "E5"), (6, 2, 1, "F#5"), (6, 3, 1, "A5"),
        (7, 0, 1.5, "F#5"), (7, 1.5, 0.5, "D5"), (7, 2, 1, "B4"), (7, 3, 1, "D5"),
        (8, 0, 2, "E5"), (8, 2, 0.5, "D5"), (8, 2.5, 0.5, "B4"), (8, 3, 1, "G#4"),
    ]),
    ("B2", "aventura", [[c("D", MAJ)], [c("E", MAJ)], [c("C#", MIN7)], [c("F#", MIN7)],
                        [c("D", MAJ)], [c("E", MAJ)], [c("B", MAJ, "A")], [c("B", MAJ, "A")]], [
        (1, 0, 0.5, "A4"), (1, 0.5, 0.5, "D5"), (1, 1, 1, "F#5"), (1, 2, 0.5, "E5"), (1, 2.5, 0.5, "D5"),
        (1, 3, 1, "E5"),
        (2, 0, 0.5, "B4"), (2, 0.5, 0.5, "E5"), (2, 1, 1, "G#5"), (2, 2, 0.5, "F#5"), (2, 2.5, 0.5, "E5"),
        (2, 3, 1, "F#5"),
        (3, 0, 1.5, "G#5"), (3, 1.5, 0.5, "E5"), (3, 2, 1, "C#5"), (3, 3, 1, "B4"),
        (4, 0, 3, "C#5"), (4, 3.5, 0.5, "C#5"),
        (5, 0, 0.5, "A4"), (5, 0.5, 0.5, "D5"), (5, 1, 1, "F#5"), (5, 2, 1, "A5"), (5, 3, 1, "F#5"),
        (6, 0, 1, "G#5"), (6, 1, 1, "B5"), (6, 2, 1, "G#5"), (6, 3, 1, "E5"),
        (7, 0, 1.5, "D#5"), (7, 1.5, 0.5, "F#5"), (7, 2, 2, "B5"),
        (8, 0, 1, "A5"), (8, 1, 1, "F#5"), (8, 2, 2, "D#5"),
    ]),
    ("C", "puente", [[c("D", MAJ9)], [c("D", MIN6)], [c("A", MAJ9, "C#")], [c("F#", MIN9)],
                     [c("D", MAJ9)], [c("D", MIN6)], [c("B", MIN9)], ESUS_E], [
        (1, 0, 2, "F#5"), (1, 2, 2, "E5"),
        (2, 0, 2, "F5"), (2, 2, 2, "D5"),
        (3, 0, 3, "E5"), (3, 3, 1, "C#5"),
        (4, 0, 2, "G#5"), (4, 2, 1, "A5"), (4, 3, 1, "F#5"),
        (5, 0, 2, "A5"), (5, 2, 1, "F#5"), (5, 3, 1, "E5"),
        (6, 0, 2, "F5"), (6, 2, 1, "A5"), (6, 3, 1, "D5"),
        (7, 0, 2, "C#5"), (7, 2, 1, "D5"), (7, 3, 1, "F#5"),
        (8, 0, 2, "A5"), (8, 2, 2, "G#5"),
    ]),
    ("A3", "clímax", [[A9], [E_G], [FM7], [DM7], [A9], [E_G], [DM7, c("E", MAJ)], [A9]], [
        (1, 0, 1, "E5"), (1, 1, 0.5, "C#5"), (1, 1.5, 0.5, "E5"), (1, 2, 1.5, "A5"), (1, 3.5, 0.5, "G#5"),
        (2, 0, 1.5, "G#5"), (2, 1.5, 0.5, "E5"), (2, 2, 2, "B4"),
        (3, 0, 1, "C#5"), (3, 1, 0.5, "E5"), (3, 1.5, 0.5, "F#5"), (3, 2, 1.5, "A5"), (3, 3.5, 0.5, "G#5"),
        (4, 0, 2, "F#5"), (4, 2, 1, "E5"), (4, 3, 1, "C#5"),
        (5, 0, 1, "E5"), (5, 1, 0.5, "C#5"), (5, 1.5, 0.5, "E5"), (5, 2, 1.5, "A5"), (5, 3.5, 0.5, "G#5"),
        (6, 0, 1.5, "G#5"), (6, 1.5, 0.5, "B5"), (6, 2, 1, "G#5"), (6, 3, 1, "E5"),
        (7, 0, 1, "F#5"), (7, 1, 1, "A5"), (7, 2, 1, "B5"), (7, 3, 1, "G#5"),
        (8, 0, 3, "A5"),
    ]),
    ("coda", "calma", [[c("D", MAJ9)], [c("B", MAJ, "A")], [c("D", MAJ9)], ESUS_E], [
        (1, 0, 2, "F#5"), (1, 2, 2, "E5"),
        (2, 0, 2, "D#5"), (2, 2, 2, "F#5"),
        (3, 0, 2, "A5"), (3, 2, 1, "F#5"), (3, 3, 1, "E5"),
        (4, 0, 2, "B4"), (4, 2, 1, "G#4"), (4, 3, 1, "D5"),
    ]),
]

BARS = sum(len(s[2]) for s in SECTIONS)
LOOP_SEC = BARS * BEATS_PER_BAR * BEAT
LOOP_N = int(round(LOOP_SEC * SR))

# Un acorde en el tiempo. `bar0` es el pulso donde empieza su compás; `beat` el pulso dentro del compás.
Ev = namedtuple("Ev", "start dur root ints bass sec style bar nbars bar0 beat")


def chord_events():
    out = []
    bar_g = 0
    for name, style, bars, _mel in SECTIONS:
        for i, chords in enumerate(bars):
            span = BEATS_PER_BAR / len(chords)
            bar0 = bar_g * BEATS_PER_BAR
            for k, (root, ints, bass) in enumerate(chords):
                out.append(Ev(bar0 + k * span, span, _PC[root], ints, _PC[bass], name, style, i + 1, len(bars), bar0,
                              k * span))
            bar_g += 1
    return out


def melody_events():
    """[(inicio en pulsos, duración, nota, sección)]."""
    out = []
    bar_g = 0
    for name, _style, bars, mel in SECTIONS:
        for bar, beat, dur, note in mel:
            out.append(((bar_g + bar - 1) * BEATS_PER_BAR + beat, dur, note, name))
        bar_g += len(bars)
    return out


def section_bars():
    """[(primer pulso, nombre, estilo, compases)]."""
    out, bar_g = [], 0
    for name, style, bars, _ in SECTIONS:
        out.append((bar_g * BEATS_PER_BAR, name, style, len(bars)))
        bar_g += len(bars)
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
        if s < 0:  # un adelanto "humano" en el pulso 0: lo que cae antes del inicio va al final del bucle
            self.add(LOOP_N / SR + start_sec, x[:-s], pan, gain)
            x, s = x[-s:], 0
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
# Instrumentos nuevos
# ---------------------------------------------------------------------------------------------
def inst_kalimba(f, dur, rng):
    """Kalimba: parciales inarmónicos que mueren rápido y un "clic" de lengüeta."""
    n = int(1.6 * SR)
    t = np.arange(n) / SR
    x = additive(f, n, [1, 2.01, 4.15, 6.3], [1.0, 0.22, 0.1, 0.04], decays=[0.7, 0.25, 0.09, 0.05], rng=rng)
    click = bandpass(rng.standard_normal(n), 2500, 7000) * np.exp(-t / 0.003) * 0.12
    return (x + click) * np.minimum(1.0, t / 0.0015) * 0.12


def inst_strings(f, dur, rng):
    """Cuerdas: sierras aditivas más brillantes que el pad, ataque lento y vibrato."""
    n = int((dur + 1.2) * SR)
    t = np.arange(n) / SR
    h = np.arange(1, 16)
    x = np.zeros(n)
    for cents in (-9, -2, 5, 11):
        vib = 1.0 + 0.003 * np.sin(2 * np.pi * (5.0 + rng.uniform(-0.4, 0.4)) * t + rng.uniform(0, 6))
        phase = 2 * np.pi * np.cumsum(f * 2 ** (cents / 1200.0) * vib) / SR + rng.uniform(0, 6)
        for k in h:
            if f * k > 7000:
                break
            x += np.sin(k * phase) / k
    x = lowpass(x, 2600, 2)
    return x * adsr(n, 0.45, 0.3, 0.85, 0.9, int(dur * SR)) * 0.018


def inst_bright_pluck(f, dur, rng):
    """Pulsado brillante (onda cuadrada suave filtrada) para el arpegio de las capas altas."""
    n = int(0.9 * SR)
    t = np.arange(n) / SR
    x = additive(f, n, [1, 3, 5, 7], [1.0, 0.3, 0.12, 0.05], decays=[0.35, 0.18, 0.1, 0.06], rng=rng)
    return x * np.minimum(1.0, t / 0.002) * 0.06


def drum_snare(rng, gain=1.0):
    """Caja con escobilla: ruido filtrado y un cuerpo grave breve; suave, nada de rock."""
    n = int(0.3 * SR)
    t = np.arange(n) / SR
    noise = bandpass(rng.standard_normal(n), 1400, 7000) * np.exp(-t / 0.075)
    body = np.sin(2 * np.pi * 185 * t) * np.exp(-t / 0.045) * 0.6
    return (noise * 0.6 + body) * np.minimum(1.0, t / 0.002) * 0.14 * gain


def drum_hat(rng, open_=False):
    n = int((0.35 if open_ else 0.08) * SR)
    t = np.arange(n) / SR
    x = highpass(rng.standard_normal(n), 7500, 2) * np.exp(-t / (0.12 if open_ else 0.022))
    return x * (0.05 if open_ else 0.035)


def drum_tom(rng, f0):
    n = int(0.5 * SR)
    t = np.arange(n) / SR
    f = f0 * (1 + 0.5 * np.exp(-t / 0.03))
    x = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.2)
    return lowpass(x, 900) * 0.32


def drum_crash(rng):
    """Platillo suave: ruido agudo con caída larga (marca la llegada del clímax)."""
    n = int(2.5 * SR)
    t = np.arange(n) / SR
    x = bandpass(rng.standard_normal(n), 3500, 12000) * np.exp(-t / 0.9) * np.minimum(1.0, t / 0.004)
    return x * 0.07


def riser(beats):
    """Ruido que crece y se abre hasta el compás siguiente: anuncia que algo llega."""
    rng = np.random.default_rng(99)
    n = int(sec(beats) * SR)
    ramp = np.linspace(0, 1, n) ** 2.2
    x = highpass(rng.standard_normal(n), 1500) * ramp
    return lowpass(x, 9000) * 0.06


def human(rng, ms=5.0):
    """Pequeño desvío de tiempo (en segundos), como un intérprete."""
    return float(np.clip(rng.normal(0.0, ms / 1000.0), -0.012, 0.012)) + 0.002


def vel(rng, lo=0.84):
    return float(rng.uniform(lo, 1.0))


def in_event(ev, pattern):
    """Entradas de un patrón (pulsos dentro del compás) que caen dentro del acorde `ev`."""
    return [p for p in pattern if ev.beat <= p[0] < ev.beat + ev.dur]


def chord_tones(ev, lo, hi):
    pcs = pitch_classes(ev.root, ev.ints)
    return [n for n in range(lo, hi + 1) if n % 12 in pcs]


# ---------------------------------------------------------------------------------------------
# Patrones de acompañamiento por estilo de sección (pulso dentro del compás, duración, nota, fuerza)
# Nota del bajo: "r" raíz del bajo, "o" su octava, "q" quinta (u octava si el bajo es otra nota del acorde).
# ---------------------------------------------------------------------------------------------
BASS_PATTERNS = {
    "calma": [(0, 3.8, "r", 1.0)],
    "estribillo": [(0, 1.0, "r", 1.0), (1.5, 0.5, "r", 0.7), (2.5, 0.5, "o", 0.6), (3, 1.0, "q", 0.85)],
    "aventura": [(k * 0.5, 0.42, "o" if k == 3 else ("q" if k == 7 else "r"), 1.0 if k % 2 == 0 else 0.72)
                 for k in range(8)],
    "puente": [(0, 1.9, "r", 0.9), (2, 1.9, "q", 0.7)],
    "clímax": [(0, 1.0, "r", 1.0), (1.5, 0.5, "r", 0.75), (2, 0.5, "o", 0.6), (2.5, 0.5, "r", 0.7),
               (3, 1.0, "q", 0.85)],
}

# Kalimba: (pulso, índice en las notas del acorde, fuerza).
KALIMBA_PATTERNS = {
    "calma": [(0, 0, 0.8), (1.5, 2, 0.6), (3, 1, 0.6)],
    "estribillo": [(0, 0, 1.0), (0.5, 2, 0.6), (1, 1, 0.75), (1.5, 3, 0.6), (2.5, 2, 0.7), (3, 1, 0.75),
                   (3.5, 3, 0.6)],
    "aventura": [(k * 0.5, [0, 2, 1, 3, 2, 4, 3, 1][k], 1.0 if k % 2 == 0 else 0.65) for k in range(8)],
    "puente": [],
    "clímax": [(0, 0, 1.0), (0.5, 2, 0.6), (1, 1, 0.75), (1.5, 3, 0.6), (2, 4, 0.7), (2.5, 2, 0.7),
               (3, 1, 0.75), (3.5, 3, 0.6)],
}

PAD_GAIN = {"calma": 1.0, "estribillo": 0.75, "aventura": 0.8, "puente": 1.15, "clímax": 0.85}

# Arpa: forma del arpegio (índices en las notas del acorde) y paso en pulsos.
HARP_PATTERNS = {
    "calma": ([0, 2, 4, 6], 1.0),
    "estribillo": ([0, 2, 4, 5, 6, 5, 4, 2], 0.5),
    "aventura": ([0, 2, 4, 2, 5, 2, 4, 2], 0.5),
    "puente": ([0, 2, 4, 6, 7, 6, 4, 2], 0.5),
    "clímax": ([0, 2, 4, 5, 7, 5, 4, 2], 0.5),
}


# ---------------------------------------------------------------------------------------------
# Composición de cada capa
# ---------------------------------------------------------------------------------------------
def layer_aprendiz():
    rng = np.random.default_rng(11)
    pad, bass, box, kal = Track(), Track(), Track(), Track()
    prev = None
    for ev in chord_events():
        pcs = pitch_classes(ev.root, ev.ints)
        voicing = voice_lead(prev, pcs, 4, m("E3"), m("D5"))
        prev = voicing
        for i, note in enumerate(voicing):
            pad.add(sec(ev.start), inst_pad(hz(note), sec(ev.dur), rng), pan=-0.5 + i / 3.0,
                    gain=PAD_GAIN[ev.style])
        # Bajo: entre A1 y G#2.
        b = 33 + (ev.bass - 9) % 12
        notes = {"r": b, "o": b + 12, "q": b + 7 if ev.bass == ev.root else b + 12}
        for beat, dur, kind, v in in_event(ev, BASS_PATTERNS[ev.style]):
            dur = min(dur, ev.beat + ev.dur - beat)
            bass.add(sec(ev.bar0 + beat) + human(rng, 3), inst_bass(hz(notes[kind]), sec(dur * 0.95), rng),
                     gain=v * vel(rng, 0.9))
        # Kalimba por debajo de la melodía.
        tones = chord_tones(ev, m("A3"), m("E5"))
        for beat, idx, v in in_event(ev, KALIMBA_PATTERNS[ev.style]):
            note = tones[min(idx + 1, len(tones) - 1)]
            kal.add(sec(ev.bar0 + beat) + human(rng), inst_kalimba(hz(note), 0.5, rng),
                    pan=0.35 if idx % 2 else -0.15, gain=v * vel(rng))
    for start, dur, name, sec_name in melody_events():
        box.add(sec(start) + human(rng), inst_music_box(hz(m(name)), sec(dur), rng), pan=0.1,
                gain=vel(rng, 0.88) * (1.1 if sec_name == "A3" else 1.0))
    mix = pad.buf * 0.85 + bass.buf + box.buf + kal.buf
    return reverb_stereo(mix, 1, mix=0.26)


def layer_iniciado():
    rng = np.random.default_rng(22)
    harp, bells = Track(), Track()
    for ev in chord_events():
        tones = chord_tones(ev, 45 + (ev.root - 9) % 12, m("E5"))
        shape, step = HARP_PATTERNS[ev.style]
        if ev.style == "puente":
            tones = chord_tones(ev, m("A3"), m("A5"))
        steps = int(round(ev.dur / step))
        k0 = int(round(ev.beat / step))
        for k in range(steps):
            idx = shape[(k0 + k) % len(shape)] % len(tones)
            accent = 1.0 if (k0 + k) % 2 == 0 else 0.72
            if ev.style == "puente" and ev.bar <= 2:
                accent *= 0.6
            harp.add(sec(ev.start + k * step) + human(rng, 4), inst_harp(hz(tones[idx]), 0.5, rng),
                     pan=-0.4 + 0.15 * (idx % 4), gain=accent * vel(rng))
    # Campanitas que contestan a la melodía en sus huecos (final de los compases 2, 4 y 8 de los estribillos).
    for start, name, style, nbars in section_bars():
        if style not in ("estribillo", "clímax"):
            continue
        for bar, answer in ((2, ["B5", "G#5", "E5"]), (4, ["A5", "F#5", "C#6"]), (8, ["E6", "B5", "G#5"])):
            if name == "A2" and bar == 8:
                continue
            for j, note in enumerate(answer):
                t0 = start + (bar - 1) * BEATS_PER_BAR + 2.5 + j * 0.5
                bells.add(sec(t0) + human(rng), inst_celesta_high(hz(m(note)), 0.6, rng), pan=0.45,
                          gain=1.4 - 0.2 * j)
    return reverb_stereo(harp.buf + bells.buf, 2, mix=0.32)


def layer_hechicero():
    rng = np.random.default_rng(33)
    perc = Track()

    def hit(beat, x, pan=0.0, gain=1.0):
        perc.add(sec(beat) + human(rng, 3), x, pan=pan, gain=gain * vel(rng, 0.88))

    def shaker_8ths(b0, gain=1.0, swing=0.05):
        for k in range(8):
            hit(b0 + k * 0.5 + (swing if k % 2 else 0.0), drum_shaker(rng, k % 2 == 1), pan=-0.3, gain=gain)

    def tom_fill(b0):
        for k, f0 in enumerate((210, 180, 150, 120)):
            hit(b0 + 3 + k * 0.25, drum_tom(rng, f0), pan=0.4 - 0.25 * k, gain=0.7 + 0.1 * k)

    for start, name, style, nbars in section_bars():
        for bar in range(1, nbars + 1):
            b0 = start + (bar - 1) * BEATS_PER_BAR
            last = bar == nbars
            if style == "calma":
                shaker_8ths(b0, 0.7)
                if name == "intro":
                    if bar >= 3:
                        hit(b0, drum_kick(rng), gain=0.7)
                    if last:
                        tom_fill(b0)
                else:  # coda: el bloque de madera de la versión anterior, de guiño
                    hit(b0, drum_kick(rng), gain=0.7)
                    hit(b0 + 1, drum_block(rng), pan=0.35)
                    hit(b0 + 3, drum_block(rng), pan=0.35, gain=0.8)
                    if last:
                        hit(b0 + 3.5, drum_block(rng), pan=0.35, gain=0.7)
            elif style in ("estribillo", "clímax"):
                if style == "clímax" and bar == 1:
                    hit(b0, drum_crash(rng), pan=-0.2)
                hit(b0, drum_kick(rng))
                hit(b0 + 2.5, drum_kick(rng), gain=0.7)
                if name == "A2" and bar % 2 == 0:
                    hit(b0 + 1.75, drum_kick(rng), gain=0.5)
                hit(b0 + 1, drum_snare(rng), pan=0.1)
                shaker_8ths(b0, 0.8)
                if style == "clímax":
                    for k in range(8):
                        hit(b0 + k * 0.5, drum_hat(rng, k == 7), pan=0.3, gain=1.0 if k % 2 == 0 else 0.7)
                if last:
                    tom_fill(b0)
                else:
                    hit(b0 + 3, drum_snare(rng), pan=0.1)
            elif style == "aventura":
                if name == "B2" and last:
                    # Corte: un golpe con platillo y silencio, la música respira antes del puente.
                    hit(b0, drum_kick(rng))
                    hit(b0, drum_crash(rng), pan=0.2, gain=0.7)
                    continue
                hit(b0, drum_kick(rng))
                hit(b0 + 1.5, drum_kick(rng), gain=0.6)
                hit(b0 + 2.5, drum_kick(rng), gain=0.75)
                hit(b0 + 1, drum_snare(rng), pan=0.1)
                hit(b0 + 3, drum_snare(rng), pan=0.1)
                for k in range(8):
                    hit(b0 + k * 0.5 + (0.04 if k % 2 else 0.0), drum_hat(rng, k == 7), pan=0.3,
                        gain=1.0 if k % 2 == 0 else 0.65)
                if name == "B" and last:
                    tom_fill(b0)
            elif style == "puente":
                if bar <= 4:
                    for k in range(4):
                        hit(b0 + k, drum_shaker(rng, k % 2 == 1), pan=-0.3, gain=0.6)
                elif not last:
                    hit(b0, drum_kick(rng), gain=0.8)
                    hit(b0 + 2, drum_snare(rng, 0.7), pan=0.1)
                    shaker_8ths(b0, 0.6)
                else:
                    # Redoble que crece y lanza el clímax.
                    hit(b0, drum_kick(rng), gain=0.8)
                    for k in range(16):
                        hit(b0 + k * 0.25, drum_snare(rng, 0.25 + 0.75 * (k / 15) ** 1.5), pan=0.1)
                    perc.add(sec(b0), riser(4.0), gain=1.0)
    return reverb_stereo(perc.buf, 3, length=1.2, mix=0.18)


def layer_magus():
    """Flauta (contramelodía sobre notas guía, y la melodía en el puente) y cuerdas en las partes grandes."""
    rng = np.random.default_rng(44)
    fl, st = Track(), Track()
    prev = m("C#5")
    prev_st = None
    for ev in chord_events():
        if ev.style in ("estribillo", "aventura", "clímax") and not (ev.sec == "B"):
            guide = {(ev.root + i) % 12 for i in ev.ints if i in (3, 4, 10, 11, 14)} or \
                pitch_classes(ev.root, ev.ints)
            for h in range(max(1, int(ev.dur // 2))):
                cands = [n for n in range(m("F#4"), m("E5") + 1) if n % 12 in guide and n != prev] or [prev]
                note = min(cands, key=lambda n: abs(n - prev) + rng.uniform(0, 0.5))
                fl.add(sec(ev.start + h * 2) + human(rng), inst_flute(hz(note), sec(min(2, ev.dur)), rng),
                       pan=-0.25, gain=vel(rng, 0.9))
                prev = note
        if ev.style in ("aventura", "puente", "clímax"):
            pcs = pitch_classes(ev.root, ev.ints)
            voicing = voice_lead(prev_st, pcs, 3, m("A4"), m("A5"))
            prev_st = voicing
            g = 0.7 if ev.sec == "B" else 1.0
            for i, note in enumerate(voicing):
                st.add(sec(ev.start), inst_strings(hz(note), sec(ev.dur), rng), pan=-0.6 + 0.6 * i, gain=g)
        else:
            prev_st = None
    for start, dur, name, sec_name in melody_events():
        if sec_name == "C":
            fl.add(sec(start) + human(rng), inst_flute(hz(m(name)), sec(dur), rng), pan=-0.1, gain=1.3)
    return reverb_stereo(fl.buf + st.buf, 4, mix=0.35)


def layer_archimago():
    rng = np.random.default_rng(55)
    sp, ch, arp, bell = Track(), Track(), Track(), Track()
    penta = {9, 11, 1, 4, 6}  # A B C# E F#: la escala de los "tinks"
    for ev in chord_events():
        pcs = pitch_classes(ev.root, ev.ints) & penta or pitch_classes(ev.root, ev.ints)
        pool = [n for n in range(m("A5"), m("E7") + 1) if n % 12 in pcs]
        if ev.style in ("calma", "estribillo", "puente"):
            for k in range(int(ev.dur * 2)):
                if k % 2 == 1 and rng.random() < 0.45:
                    sp.add(sec(ev.start + k * 0.5), inst_celesta_high(hz(pool[rng.integers(len(pool))]), 0.5, rng),
                           pan=rng.uniform(-0.8, 0.8))
        # Coro: raíz y quinta, más presente en el puente y el clímax.
        cg = {"puente": 1.4, "clímax": 1.2}.get(ev.style, 0.9)
        for iv in (0, 7):
            ch.add(sec(ev.start), inst_choir(hz(57 + (ev.root - 9) % 12 + iv), sec(ev.dur), rng),
                   pan=-0.4 if iv else 0.4, gain=cg)
        # Arpegio brillante en semicorcheas en B' y el clímax (sube y baja dos octavas).
        if ev.sec in ("B2", "A3"):
            tones = chord_tones(ev, m("A4"), m("A6"))
            shape = list(range(len(tones))) + list(range(len(tones) - 2, 0, -1))
            for k in range(int(ev.dur * 4)):
                kk = int(ev.beat * 4) + k
                note = tones[shape[kk % len(shape)]]
                arp.add(sec(ev.start + k * 0.25) + human(rng, 2), inst_bright_pluck(hz(note), 0.25, rng),
                        pan=0.5 if k % 2 else -0.5, gain=(1.0 if k % 4 == 0 else 0.7) * vel(rng))
    # Campanas que doblan el estribillo a la octava en el clímax.
    for start, dur, name, sec_name in melody_events():
        if sec_name == "A3":
            bell.add(sec(start) + human(rng), inst_celesta_high(hz(m(name) + 12), max(0.5, sec(dur)), rng),
                     pan=0.2, gain=1.6)
    mix = sp.buf + ch.buf + arp.buf * 0.9 + bell.buf
    return reverb_stereo(mix, 5, length=3.5, mix=0.42)


LAYERS = [
    ("music_valley_1_aprendiz", layer_aprendiz, 0.0),
    ("music_valley_2_iniciado", layer_iniciado, 0.0),
    ("music_valley_3_hechicero", layer_hechicero, 2.0),
    ("music_valley_4_magus", layer_magus, 3.0),
    ("music_valley_5_archimago", layer_archimago, 3.0),
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
    ap.add_argument("--preview", default="", help="ruta de una mezcla de 2 vueltas donde van entrando las capas")
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
    print(f"Música escrita en {out} ({LOOP_SEC:.1f} s por vuelta, {BARS} compases a {BPM:.0f} BPM)")
    if args.preview:
        # Vista previa: 2 vueltas; cada capa entra un tercio de vuelta después de la anterior (con fundido),
        # como pasaría al subir de rango.
        loops = 2
        step = LOOP_N // 3
        fade_n = int(1.5 * SR)
        prev = np.zeros((2, LOOP_N * loops))
        for i, (_, x) in enumerate(stems):
            tiled = np.tile(x, (1, loops))
            gate = np.zeros(LOOP_N * loops)
            s = i * step
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
