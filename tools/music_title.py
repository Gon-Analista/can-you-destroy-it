#!/usr/bin/env python3
"""Tema del menú de título: "¿Puedes destruirlo?" (vals mágico y con un punto de humor).

Uso:
    python3 tools/music_title.py            # escribe game/audio/music/music_title.ogg
    python3 tools/music_title.py --out DIR

Reutiliza los instrumentos de `music_synth.py` (caja de música, arpa, bajo, flauta, coro,
celesta) y compone otra pieza, en La mayor como el resto (el "tink" del cristal no desafina):

- **Vals** a 3/4, 108 BPM, 24 compases (40 s), en bucle sin costura (la cola se suma al
  principio). Acompañamiento "um-pa-pa": bajo pizzicato en el 1, arpa en el 2 y el 3.
- **Tres frases de 8 compases**:
  A) la pregunta: la melodía sube y se queda colgada en la dominante (Mi), sin resolver,
     como un "¿...?"; un bloque de madera hace "¿toc?" al final de cada media frase.
  B) la respuesta: entra la flauta y el coro; Re menor prestado (iv) para el toque mágico y
     agridulce; cadencia completa a La con un destello que sube.
  C) la duda otra vez: la caja de música más aguda, celesta, y Mi sus4 -> Mi que devuelve al
     principio: el bucle siempre termina preguntando.
Determinista: semillas fijas.
"""
import argparse
from pathlib import Path

import numpy as np

import music_synth as ms
from music_synth import (SR, highpass, hz, inst_bass, inst_celesta_high, inst_choir, inst_flute,
                         inst_harp, inst_music_box, inst_pad, m, pitch_classes, reverb_stereo,
                         voice_lead, write)

BPM = 108.0
BEAT = 60.0 / BPM
BEATS_PER_BAR = 3
BARS = 24
LOOP_SEC = BARS * BEATS_PER_BAR * BEAT
LOOP_N = int(round(LOOP_SEC * SR))
TAIL_SEC = 5.0

MAJ = [0, 4, 7]
MIN = [0, 3, 7]
MIN7 = [0, 3, 7, 10]
SUS4 = [0, 5, 7]
DOM7 = [0, 4, 7, 10]

# Un acorde por compás (raíz, intervalos, bajo). El 24 se parte: Mi sus4 -> Mi.
PROGRESSION = [
    # A: la pregunta
    [("A", MAJ, "A")], [("F#", MIN, "F#")], [("D", MAJ, "D")], [("E", MAJ, "E")],
    [("A", MAJ, "A")], [("F#", MIN, "F#")], [("B", MIN7, "B")], [("E", DOM7, "E")],
    # B: la respuesta (Re menor prestado)
    [("D", MAJ, "D")], [("D", MIN, "D")], [("A", MAJ, "C#")], [("F#", MIN, "F#")],
    [("B", MIN, "B")], [("E", MAJ, "E")], [("A", MAJ, "A")], [("A", MAJ, "A")],
    # C: la duda otra vez
    [("F#", MIN, "F#")], [("D", MAJ, "D")], [("A", MAJ, "A")], [("E", MAJ, "E")],
    [("F#", MIN, "F#")], [("D", MAJ, "D")], [("B", MIN, "B")], [("E", SUS4, "E"), ("E", MAJ, "E")],
]

# (compás 1-24, pulso, duración en pulsos, nota)
MELODY_BOX = [
    (1, 0, 1, "E5"), (1, 1, 1, "A5"), (1, 2, 1, "C#6"),
    (2, 0, 2, "C#6"), (2, 2, 1, "A5"),
    (3, 0, 1, "F#5"), (3, 1, 1, "A5"), (3, 2, 1, "D6"),
    (4, 0, 3, "B5"),
    (5, 0, 1, "E5"), (5, 1, 1, "A5"), (5, 2, 1, "C#6"),
    (6, 0, 1, "E6"), (6, 1, 1, "C#6"), (6, 2, 1, "A5"),
    (7, 0, 1, "D6"), (7, 1, 1, "B5"), (7, 2, 1, "F#5"),
    (8, 0, 2, "E5"), (8, 2, 1, "G#5"),
    # C, una octava de brillo más
    (17, 0, 1, "C#6"), (17, 1, 1, "A5"), (17, 2, 1, "F#5"),
    (18, 0, 2, "F#5"), (18, 2, 1, "A5"),
    (19, 0, 1, "E5"), (19, 1, 1, "A5"), (19, 2, 1, "C#6"),
    (20, 0, 3, "B5"),
    (21, 0, 1, "A5"), (21, 1, 1, "C#6"), (21, 2, 1, "F#6"),
    (22, 0, 2, "F#6"), (22, 2, 1, "E6"),
    (23, 0, 1, "D6"), (23, 1, 1, "B5"), (23, 2, 1, "D6"),
    (24, 0, 1, "E6"), (24, 1, 1, "D6"), (24, 2, 1, "B5"),
]
MELODY_FLUTE = [
    (9, 0, 2, "F#5"), (9, 2, 1, "A5"),
    (10, 0, 2, "F5"), (10, 2, 1, "A5"),
    (11, 0, 1, "E5"), (11, 1, 1, "C#5"), (11, 2, 1, "E5"),
    (12, 0, 3, "F#5"),
    (13, 0, 1, "D5"), (13, 1, 1, "F#5"), (13, 2, 1, "B5"),
    (14, 0, 2, "G#5"), (14, 2, 1, "B5"),
    (15, 0, 3, "A5"),
]
# Destello que sube al resolver la respuesta (compás 16).
SPARKLE = [(16, 0.0, "C#6"), (16, 0.5, "E6"), (16, 1.0, "A6"), (16, 1.5, "C#7"), (16, 2.0, "E7")]


class Track:
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


def sec(beats: float) -> float:
    return beats * BEAT


def chord_events():
    out = []
    for bar, chords in enumerate(PROGRESSION):
        span = BEATS_PER_BAR / len(chords)
        for i, (root, ints, bass) in enumerate(chords):
            out.append((bar * BEATS_PER_BAR + i * span, span, ms._PC[root], ints, ms._PC[bass]))
    return out


def block_tock(rng, pitch=1.0):
    """Bloque de madera: "¿toc?" (dos golpes, el segundo más agudo, como una pregunta)."""
    n = int(0.25 * SR)
    t = np.arange(n) / SR
    f = 900 * pitch
    x = np.sin(2 * np.pi * f * t) * np.exp(-t / 0.03) + 0.4 * np.sin(2 * np.pi * f * 1.5 * t) * np.exp(-t / 0.02)
    return x * 0.09


def compose() -> np.ndarray:
    rng = np.random.default_rng(321)
    bass, harp, pad, box, flute, choir, sparkle, perc = (Track() for _ in range(8))
    prev = None
    for start, dur, root, ints, bass_pc in chord_events():
        pcs = pitch_classes(root, ints)
        voicing = voice_lead(prev, pcs, 3, m("E4"), m("E5"))
        prev = voicing
        bar = int(start // BEATS_PER_BAR)
        # Bajo pizzicato en el 1 (corto y redondo).
        b = 33 + (bass_pc - 9) % 12
        if start % BEATS_PER_BAR == 0:
            bass.add(sec(start), inst_bass(hz(b), sec(0.8), rng))
        # "Pa-pa": arpa con el acorde en los pulsos 2 y 3.
        for beat in (1, 2):
            t0 = bar * BEATS_PER_BAR + beat
            if t0 < start or t0 >= start + dur:
                continue
            for i, note in enumerate(voicing):
                harp.add(sec(t0), inst_harp(hz(note), sec(0.5), rng), pan=-0.4 + i * 0.4,
                         gain=0.75 if beat == 1 else 0.6)
        # Pad muy suave de fondo, y coro en la respuesta (compases 9-16).
        for i, note in enumerate(voicing):
            pad.add(sec(start), inst_pad(hz(note - 12), sec(dur), rng), pan=-0.5 + i * 0.5, gain=0.5)
            if 8 <= bar < 16:
                choir.add(sec(start), inst_choir(hz(note), sec(dur), rng), pan=-0.3 + i * 0.3)
    for bar, beat, dur, name in MELODY_BOX:
        start = (bar - 1) * BEATS_PER_BAR + beat
        box.add(sec(start), inst_music_box(hz(m(name)), sec(dur), rng), pan=0.15)
    for bar, beat, dur, name in MELODY_FLUTE:
        start = (bar - 1) * BEATS_PER_BAR + beat
        flute.add(sec(start), inst_flute(hz(m(name)), sec(dur), rng), pan=-0.15)
        # La caja de música hace eco de la flauta una octava arriba, muy bajito.
        box.add(sec(start + 0.5), inst_music_box(hz(m(name) + 12), sec(dur * 0.5), rng), pan=0.4, gain=0.35)
    for bar, beat, name in SPARKLE:
        sparkle.add(sec((bar - 1) * BEATS_PER_BAR + beat), inst_celesta_high(hz(m(name)), 1.0, rng), pan=0.3)
    # Celesta salpicada en la tercera frase.
    for bar in range(17, 25):
        if bar % 2 == 0:
            name = ["A6", "C#7", "E7", "F#6"][(bar // 2) % 4]
            sparkle.add(sec((bar - 1) * BEATS_PER_BAR + 2.5), inst_celesta_high(hz(m(name)), 0.6, rng),
                        pan=-0.3, gain=0.7)
    # "¿Toc? ¿toc?" al final de cada media frase de la pregunta y la duda.
    for bar in (4, 8, 20, 24):
        base = (bar - 1) * BEATS_PER_BAR
        perc.add(sec(base + 2.0), block_tock(rng, 1.0), pan=0.5)
        perc.add(sec(base + 2.5), block_tock(rng, 1.33), pan=0.5)
    mix = (bass.buf * 0.9 + harp.buf * 0.8 + pad.buf * 0.6 + box.buf + flute.buf * 1.1
           + choir.buf * 0.8 + sparkle.buf + perc.buf)
    return reverb_stereo(mix, 9, length=2.8, mix=0.3)


def fold_loop(buf: np.ndarray) -> np.ndarray:
    out = buf[:, :LOOP_N].copy()
    tail = buf[:, LOOP_N:]
    k = min(tail.shape[1], LOOP_N)
    out[:, :k] += tail[:, :k]
    return out


def main() -> None:
    ap = argparse.ArgumentParser()
    root = Path(__file__).resolve().parent.parent
    ap.add_argument("--out", default=str(root / "game" / "audio" / "music"))
    out = Path(ap.parse_args().out)
    x = highpass(fold_loop(compose()), 35, 2)
    x *= 10 ** (-2.0 / 20) / np.max(np.abs(x))
    write(out, "music_title", x)
    print(f"Tema del título escrito en {out} ({LOOP_SEC:.1f} s, {BPM:.0f} BPM, 3/4)")


if __name__ == "__main__":
    main()
