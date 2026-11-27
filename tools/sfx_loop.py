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
                       reverb, t_axis, write)  # noqa: F401


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
    """Comprar una mejora: tres notas suaves de caja de música (La, Do#, Mi) sobre un colchón cálido.

    Corto (~1 s) y sin agudos chillones: se oye muchas veces seguidas al comprar varias mejoras.
    Antes era un arpegio de 8 campanas brillantes con ruido de destellos y 4 s de cola (pedido del
    equipo: "el sonido al mejorar hechizos es muy molesto").
    """
    rng = np.random.default_rng(seed)
    t = t_axis(1.1)
    x = np.zeros_like(t)
    for i, n in enumerate([0, 4, 7]):
        s = int(i * 0.07 * SR)
        tt = t[: len(t) - s]
        x[s:] += bell(tt, note(n), [1.0, 2.0, 3.0], [1.0, 0.18, 0.04],
                      [0.55, 0.25, 0.12], rng, 0.002) * (0.85 ** i) * 0.5
    pad = np.zeros_like(t)
    for n in [-12, -8, -5]:
        pad += np.sin(2 * np.pi * note(n) * t) * 0.08
    pad *= np.minimum(t / 0.05, 1.0) * np.exp(-t / 0.35)
    x = lowpass(x + pad, 3200)
    return normalize(fade(reverb(x, rng, 0.6, 0.15, 4000), 0.004, 0.25), -6)


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


def footstep_grass(seed: int) -> np.ndarray:
    """Paso sobre hierba: roce suave de hojas + golpe sordo muy bajo. Sin agudos molestos."""
    rng = np.random.default_rng(seed)
    t = t_axis(0.22)
    swish = bandpass(rng.standard_normal(len(t)), 900, 4500, 2) * np.exp(-t / 0.045)
    swish *= 1 - np.exp(-t / 0.006)
    thump = lowpass(rng.standard_normal(len(t)), 220) * np.exp(-t / 0.03) * 2.0
    return normalize(fade(swish * 0.6 + thump, 0.001, 0.04), -14)


def jump_whoosh(seed: int) -> np.ndarray:
    """Salto: impulso de ropa y aire que sube."""
    rng = np.random.default_rng(seed)
    t = t_axis(0.3)
    noise = rng.standard_normal(len(t))
    x = bandpass(noise, 400, 2500, 2) * np.sin(np.pi * np.clip(t / 0.25, 0, 1)) ** 2
    x += lowpass(noise, 200) * np.exp(-t / 0.03) * 1.5
    return normalize(fade(x, 0.002, 0.05), -12)


def land_thud(seed: int) -> np.ndarray:
    """Aterrizar: golpe sordo en la hierba con un roce corto."""
    rng = np.random.default_rng(seed)
    t = t_axis(0.35)
    thud = lowpass(rng.standard_normal(len(t)), 180) * np.exp(-t / 0.05) * 2.5
    thud += np.sin(2 * np.pi * 70 * t) * np.exp(-t / 0.06) * 0.6
    swish = bandpass(rng.standard_normal(len(t)), 800, 4000, 2) * np.exp(-t / 0.06) * 0.4
    return normalize(fade(thud + swish, 0.001, 0.06), -9)


def frost_cast(seed: int) -> np.ndarray:
    """Escarcha al lanzar: soplo helado que sube + campanitas de hielo (Mi y La agudos)."""
    rng = np.random.default_rng(seed)
    t = t_axis(0.6)
    noise = rng.standard_normal(len(t))
    breath = bandpass(noise, 2500, 9000, 2) * np.sin(np.pi * np.clip(t / 0.35, 0, 1)) ** 2 * 0.5
    x = breath.copy()
    for k, n in enumerate([7, 12, 19]):
        s0 = int((0.03 + k * 0.04) * SR)
        tt = t[: len(t) - s0]
        x[s0:] += bell(tt, note(n), [1.0, 2.76, 5.4], [1.0, 0.4, 0.2], [0.25, 0.12, 0.06], rng) * 0.3
    return normalize(fade(reverb(x, rng, 0.7, 0.3), 0.001, 0.08), -5)


def frost_impact(seed: int) -> np.ndarray:
    """Impacto helado: crujido de hielo que se agrieta + tintineo que se congela en el aire."""
    rng = np.random.default_rng(seed)
    t = t_axis(1.0)
    grains = np.zeros_like(t)
    for _ in range(26):
        s0 = int(rng.uniform(0, 0.18) * SR)
        n = int(rng.uniform(0.002, 0.01) * SR)
        grains[s0:s0 + n] += rng.standard_normal(n) * np.hanning(n) * rng.uniform(0.4, 1.0)
    grains = bandpass(grains, 1500, 10000)
    chime = bell(t, note(rng.choice([12, 16, 19])), [1.0, 2.76, 5.4], [1.0, 0.35, 0.15], [0.6, 0.3, 0.1], rng)
    x = grains + chime * 0.35
    return normalize(fade(reverb(x, rng, 1.0, 0.3), 0.001, 0.1), -3)


def steam_burst(seed: int) -> np.ndarray:
    """Choque Térmico: siseo de vapor violento + crujido grave del cristal al romperse."""
    rng = np.random.default_rng(seed)
    t = t_axis(1.4)
    hiss = highpass(rng.standard_normal(len(t)), 2500) * np.exp(-t / 0.35) * (1 - np.exp(-t / 0.01))
    crack = lowpass(rng.standard_normal(len(t)), 600) * np.exp(-t / 0.08) * 2.0
    sub = np.sin(2 * np.pi * (60 + 40 * np.exp(-t / 0.05)) * t) * np.exp(-t / 0.25)
    shards = bell(t, note(7), [1.0, 2.76, 5.4], [1.0, 0.4, 0.2], [0.8, 0.4, 0.15], rng) * 0.3
    x = hiss * 0.6 + crack + sub * 0.8 + shards
    return normalize(fade(reverb(x, rng, 1.2, 0.25), 0.001, 0.2), -1)


def hopper_clink(seed: int) -> np.ndarray:
    """Cristal que cae en la tolva de bronce: campana metálica inarmónica + tintineo de vidrio."""
    rng = np.random.default_rng(seed)
    t = t_axis(0.7)
    metal = bell(t, rng.uniform(520, 620), [1.0, 2.41, 3.87, 5.43], [1.0, 0.5, 0.3, 0.2],
                 [0.35, 0.2, 0.12, 0.08], rng, 0.01)
    glass = bell(t, rng.uniform(2600, 3400), [1.0, 2.7, 5.1], [1.0, 0.4, 0.2], [0.12, 0.06, 0.03], rng)
    click = highpass(rng.standard_normal(len(t)), 4000) * np.exp(-t / 0.002) * 0.6
    x = metal * 0.5 + glass * 0.5 + click
    return normalize(fade(reverb(x, rng, 0.5, 0.18), 0.0005, 0.08), -5)


def lever_pull(seed: int) -> np.ndarray:
    """Palanca: trinquete (clics que se aceleran) y golpe metálico grave al tope."""
    rng = np.random.default_rng(seed)
    t = t_axis(0.9)
    x = np.zeros_like(t)
    times = np.cumsum(np.linspace(0.06, 0.025, 6))
    for tt0 in times:
        s0 = int(tt0 * SR)
        n = int(0.012 * SR)
        x[s0:s0 + n] += bandpass(rng.standard_normal(n), 1500, 6000, 2) * np.hanning(n)
    s0 = int((times[-1] + 0.05) * SR)
    tt = t[: len(t) - s0]
    clunk = lowpass(rng.standard_normal(len(tt)), 400) * np.exp(-tt / 0.05) * 2.0
    clunk += bell(tt, 180, [1.0, 2.6, 4.1], [1.0, 0.5, 0.3], [0.25, 0.12, 0.06], rng) * 0.8
    x[s0:] += clunk
    return normalize(fade(reverb(x, rng, 0.5, 0.15), 0.001, 0.1), -3)


def machine_start(seed: int) -> np.ndarray:
    """Arranque: motor que sube de vueltas con un silbido mágico."""
    rng = np.random.default_rng(seed)
    t = t_axis(1.2)
    f = 40 + 70 * (1 - np.exp(-t / 0.35))
    motor = np.sin(2 * np.pi * np.cumsum(f) / SR) + 0.5 * np.sin(2 * np.pi * np.cumsum(f * 2) / SR)
    motor *= np.minimum(t / 0.2, 1.0)
    whine = np.sin(2 * np.pi * np.cumsum(300 + 500 * (1 - np.exp(-t / 0.4))) / SR) * 0.15
    x = (motor * 0.5 + whine) * np.minimum(1.0, (t[-1] - t) / 0.2)
    return normalize(fade(lowpass(x, 3000), 0.002, 0.1), -6)


def crusher_loop(seed: int) -> np.ndarray:
    """Maquinaria en marcha: motor grave, engranajes que golpean a ritmo y cadena. 2 s exactos."""
    rng = np.random.default_rng(seed)
    dur = 2.0
    t = t_axis(dur)
    hum = np.sin(2 * np.pi * 55 * t) * 0.5 + np.sin(2 * np.pi * 110 * t) * 0.25 + np.sin(2 * np.pi * 165 * t) * 0.1
    x = hum * (0.8 + 0.2 * np.sin(2 * np.pi * 8 * t))
    # Dientes de engranaje: 16 golpes por vuelta, con acento cada 4.
    for k in range(16):
        s0 = int(k * dur / 16 * SR)
        n = int(0.03 * SR)
        hit = bandpass(rng.standard_normal(n), 800, 3500, 2) * np.exp(-np.arange(n) / SR / 0.008)
        x[s0:s0 + n] += hit * (1.0 if k % 4 == 0 else 0.45)
    # Cadena: tictac fino y continuo.
    for k in range(48):
        s0 = int(k * dur / 48 * SR)
        n = int(0.006 * SR)
        x[s0:s0 + n] += highpass(rng.standard_normal(n), 5000) * 0.25
    return normalize(lowpass(x, 6000), -8)


def crunch(seed: int) -> np.ndarray:
    """Cristal triturado: crujido de vidrio entre rodillos + golpe sordo + destello agudo."""
    rng = np.random.default_rng(seed)
    t = t_axis(0.5)
    grains = np.zeros_like(t)
    for _ in range(40):
        s0 = int(rng.uniform(0, 0.12) * SR)
        n = int(rng.uniform(0.001, 0.006) * SR)
        grains[s0:s0 + n] += rng.standard_normal(n) * np.hanning(n) * rng.uniform(0.3, 1.0)
    grains = bandpass(grains, 1200, 11000)
    thump = lowpass(rng.standard_normal(len(t)), 250) * np.exp(-t / 0.03) * 1.5
    glint = bell(t, rng.uniform(1800, 2600), [1.0, 2.7], [1.0, 0.3], [0.1, 0.05], rng) * 0.3
    x = grains * 1.2 + thump + glint
    return normalize(fade(reverb(x, rng, 0.4, 0.12), 0.0005, 0.06), -2)


def steam_release(seed: int) -> np.ndarray:
    """Fin de la trituración: resoplido de vapor que se apaga + campanita de "listo"."""
    rng = np.random.default_rng(seed)
    t = t_axis(1.6)
    hiss = bandpass(rng.standard_normal(len(t)), 1500, 9000, 2)
    hiss *= np.minimum(t / 0.03, 1.0) * np.exp(-t / 0.45)
    ding = bell(t, note(12), [1.0, 2.0, 3.0], [1.0, 0.3, 0.1], [0.8, 0.4, 0.2], rng) * 0.25
    ding[: int(0.4 * SR)] = 0
    return normalize(fade(reverb(hiss * 0.7 + ding, rng, 0.8, 0.2), 0.002, 0.2), -4)


def crystal_hit(seed: int, n: int, timbre: str) -> np.ndarray:
    """Golpe al cristal, versión suave: ataque redondo (sin chasquido agudo), cuerpo grave y
    colas cortas. Tres timbres para variar: cuenco, cristal y mazo. `n`: semitonos sobre A5."""
    rng = np.random.default_rng(seed)
    t = t_axis(1.3)
    f0 = note(n) * (1 + rng.uniform(-0.006, 0.006))
    if timbre == "bowl":
        body = bell(t, f0 / 2, [1.0, 2.71, 5.1], [1.0, 0.35, 0.12], [0.9, 0.4, 0.15], rng, 0.003)
    elif timbre == "glass":
        body = bell(t, f0, [1.0, 2.32, 4.25], [1.0, 0.3, 0.1], [0.5, 0.25, 0.1], rng, 0.003)
    else:
        body = bell(t, f0 / 2, [1.0, 3.93, 9.2], [1.0, 0.3, 0.08], [0.35, 0.08, 0.03], rng, 0.003)
    # Ataque suave: unos milisegundos de subida en vez de un clic.
    body *= 1 - np.exp(-t / 0.004)
    thud = lowpass(rng.standard_normal(len(t)), 300) * np.exp(-t / 0.025) * 0.6
    grit = bandpass(rng.standard_normal(len(t)), 1500, 4500, 2) * np.exp(-t / 0.012) * 0.15
    x = lowpass(body + thud + grit, 6500, 2)
    return normalize(fade(reverb(x, rng, 0.9, 0.2, 4500), 0.001, 0.12), -6)


def crystal_surge(seed: int) -> np.ndarray:
    """El cristal se resquebraja: retumbe grave de cristal enorme, brillo que sube y un crujido."""
    rng = np.random.default_rng(seed)
    t = t_axis(3.5)
    boom = bell(t, 110, [1.0, 2.32, 4.25, 6.63], [1.0, 0.5, 0.3, 0.15], [2.2, 1.2, 0.6, 0.3], rng)
    sub = np.sin(2 * np.pi * (45 + 20 * np.exp(-t / 0.2)) * t) * np.exp(-t / 0.8)
    shimmer = np.zeros_like(t)
    for k, nn in enumerate([0, 4, 7, 12, 16, 19]):
        s0 = int((0.25 + k * 0.08) * SR)
        tt = t[: len(t) - s0]
        shimmer[s0:] += bell(tt, note(nn), [1.0, 2.0], [1.0, 0.3], [0.6, 0.3], rng) * 0.12
    crack = np.zeros_like(t)
    for _ in range(30):
        s0 = int(rng.uniform(0, 0.35) * SR)
        m = int(rng.uniform(0.002, 0.01) * SR)
        crack[s0:s0 + m] += rng.standard_normal(m) * np.hanning(m)
    crack = bandpass(crack, 800, 7000) * 0.7
    x = boom * 0.7 + sub * 0.8 + shimmer + crack
    return normalize(fade(reverb(x, rng, 2.5, 0.35, 4000), 0.002, 0.5), -1)


def arc_crackle(seed: int) -> np.ndarray:
    """Rayos de energía sobre el cristal: chisporroteo eléctrico corto y suave."""
    rng = np.random.default_rng(seed)
    t = t_axis(0.4)
    x = np.zeros_like(t)
    for _ in range(rng.integers(10, 18)):
        s0 = int(rng.uniform(0, 0.22) * SR)
        m = int(rng.uniform(0.001, 0.004) * SR)
        x[s0:s0 + m] += rng.standard_normal(m) * rng.uniform(0.3, 1.0)
    x = bandpass(x, 2000, 9000, 2)
    hum = np.sin(2 * np.pi * 120 * t) * np.exp(-t / 0.1) * 0.15
    return normalize(fade(x + hum, 0.001, 0.05), -14)


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
    for i in range(4):
        write(out, f"sfx_step_grass_{i + 1:02d}", footstep_grass(790 + i))
    write(out, "sfx_jump_01", jump_whoosh(800))
    write(out, "sfx_land_01", land_thud(810))
    for i in range(2):
        write(out, f"sfx_frost_cast_{i + 1:02d}", frost_cast(820 + i))
        write(out, f"sfx_frost_impact_{i + 1:02d}", frost_impact(830 + i))
    write(out, "sfx_steam_burst_01", steam_burst(840))
    for i in range(3):
        write(out, f"sfx_hopper_clink_{i + 1:02d}", hopper_clink(850 + i))
    write(out, "sfx_lever_pull_01", lever_pull(860))
    write(out, "sfx_machine_start_01", machine_start(870))
    write(out, "amb_crusher_loop", crusher_loop(880))
    for i in range(4):
        write(out, f"sfx_crunch_{i + 1:02d}", crunch(890 + i))
    write(out, "sfx_steam_release_01", steam_release(900))
    hits = [(-12, "bowl"), (-8, "bowl"), (-5, "bowl"), (-3, "glass"), (0, "glass"),
            (2, "glass"), (-12, "mallet"), (-10, "mallet"), (-5, "mallet"), (-8, "glass")]
    for i, (nn, timbre) in enumerate(hits):
        write(out, f"sfx_crystal_hit_{i + 1:02d}", crystal_hit(910 + i, nn, timbre))
    write(out, "sfx_crystal_surge_01", crystal_surge(930))
    for i in range(3):
        write(out, f"sfx_arc_crackle_{i + 1:02d}", arc_crackle(940 + i))


if __name__ == "__main__":
    main()
