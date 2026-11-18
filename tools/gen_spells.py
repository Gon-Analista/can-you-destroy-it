#!/usr/bin/env python3
"""Genera los elementos Rayo, Tierra y Arcano, sus aspectos y las combinaciones nuevas (data-driven).

Uso:
    python3 tools/gen_spells.py

Escribe en game/data/:
- spells/vfx_*.tres: aspectos (orbe en la mano y en vuelo) clonando uno existente con otra paleta.
- elements/bolt.tres, elements/earth.tres, elements/arcane.tres: tres niveles escritos (el juego
  completa hasta el 10).
- spells/recipe_*.tres: Lanza de Hielo, Juicio del Trueno, Meteoro, Lluvia de Estalactitas, Haz de
  Plasma, Lanza Cargada, Terremoto, Magnetismo, los Ecos (Fuego, Hielo, Trueno: repiten otra
  receta con `echo_of`), Gravedad, Resonancia Arcana y las reacciones Vapor y Temple.
Los números (daño, áreas, tiempos) y los textos se ajustan aquí y se vuelve a generar. La Bola de
Fuego y el Choque Térmico siguen escritos a mano.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent / "game"
SPELLS = ROOT / "data" / "spells"
ELEMENTS = ROOT / "data" / "elements"


def c(*v):
    return "Color(%s)" % ", ".join("%g" % x for x in v)


def colors(seq):
    """Lista de colores RGB(A) -> PackedColorArray (alfa 1 si falta)."""
    flat = []
    for col in seq:
        col = tuple(col) + ((1.0,) if len(col) == 3 else ())
        flat += col
    return "PackedColorArray(%s)" % ", ".join("%g" % x for x in flat)


# ---------------------------------------------------------------- aspectos

def clone_visual(base, name, core, sparkle, ribbons, overrides):
    """Copia data/spells/<base>.tres con otra rampa del núcleo, destellos y cintas."""
    text = (SPELLS / f"{base}.tres").read_text()
    lines = text.split("\n")
    out = []
    gradient = 0
    present = {ln.split(" = ")[0] for ln in lines}
    for ln in lines:
        if ln.startswith("[sub_resource type=\"Gradient\""):
            gradient += 1
        if ln.startswith("colors = ") and gradient == 1:
            ln = "colors = " + colors(core)
        elif ln.startswith("colors = ") and gradient == 2:
            ln = "colors = " + colors(sparkle)
        elif ln.startswith("offsets = ") and gradient == 1:
            ln = "offsets = PackedFloat32Array(0, 0.2, 0.45, 0.72, 1)"
        elif ln.startswith("offsets = ") and gradient == 2:
            ln = "offsets = PackedFloat32Array(0, 0.3, 0.6, 0.85)"
        elif ln.startswith("ribbon_colors = "):
            ln = "ribbon_colors = " + colors(ribbons)
        else:
            key = ln.split(" = ")[0]
            if key in overrides:
                ln = f"{key} = {overrides[key]}"
        out.append(ln)
    # Propiedades que la plantilla no tiene (p. ej. `meteor`): al final del [resource].
    while out and out[-1] == "":
        out.pop()
    out += [f"{key} = {val}" for key, val in overrides.items() if key not in present] + [""]
    (SPELLS / f"{name}.tres").write_text("\n".join(out))


VISUALS = {
    # Rayo: blanco eléctrico, amarillo y violeta; estilo arcano (más nítido).
    "vfx_bolt": ("vfx_frost_2", [(2.4, 2.4, 2.6), (1.8, 1.7, 0.7), (1.1, 0.95, 0.3), (0.55, 0.4, 1.0), (0.15, 0.1, 0.45)],
                 [(2.2, 2.2, 2.4), (1.4, 1.3, 0.5), (1.0, 0.8, 1.4), (0.7, 0.6, 1.4)],
                 [(1, 1, 0.6), (1, 0.95, 0.4), (0.8, 0.7, 1), (1, 1, 1)],
                 {"flare_color": c(2.4, 2.3, 1.5, 1), "light_color": c(1, 0.95, 0.6, 1), "light_energy": "0.5",
                  "core_spin": "1.6", "core_swirl": "0.4", "ribbon_speed": "2.2", "seed": "53", "style": "1"}),
    # Tierra: roca fundida (núcleo naranja, bordes marrón oscuro).
    "vfx_earth": ("vfx_flame", [(2.0, 1.45, 0.7), (1.25, 0.62, 0.2), (0.62, 0.32, 0.12), (0.32, 0.18, 0.08), (0.14, 0.08, 0.04)],
                  [(1.6, 1.2, 0.6), (0.9, 0.6, 0.3), (0.6, 0.4, 0.2), (0.4, 0.28, 0.16)],
                  [(0.85, 0.6, 0.3), (0.6, 0.42, 0.22), (1, 0.75, 0.35), (0.5, 0.35, 0.2)],
                  {"flare_color": c(1.8, 1.3, 0.7, 1), "light_color": c(1, 0.7, 0.35, 1), "core_spin": "0.25",
                   "core_swirl": "0.08", "ribbon_speed": "0.3", "seed": "61"}),
    "vfx_ice_lance": ("vfx_frost_3", [(2.0, 2.3, 2.6), (0.7, 1.5, 2.1), (0.3, 0.85, 1.6), (0.14, 0.4, 1.0), (0.06, 0.15, 0.5)],
                      [(2.0, 2.2, 2.4), (0.9, 1.2, 1.4), (0.6, 0.95, 1.3), (0.5, 0.8, 1.2)],
                      [(0.8, 1, 1), (0.5, 0.85, 1), (1, 1, 1), (0.6, 0.75, 1)],
                      {"core_spin": "1.4", "seed": "71"}),
    "vfx_thunder": ("vfx_frost_3", [(2.6, 2.6, 2.8), (2.0, 1.9, 0.9), (1.2, 1.0, 0.4), (0.6, 0.4, 1.2), (0.2, 0.1, 0.5)],
                    [(2.4, 2.4, 2.6), (1.6, 1.5, 0.6), (1.0, 0.8, 1.6), (0.8, 0.6, 1.6)],
                    [(1, 1, 0.7), (1, 0.9, 0.4), (0.85, 0.7, 1), (1, 1, 1)],
                    {"flare_color": c(2.6, 2.5, 1.6, 1), "light_color": c(1, 0.95, 0.6, 1), "light_energy": "0.8",
                     "core_spin": "2.0", "ribbon_speed": "2.6", "seed": "73", "style": "1"}),
    "vfx_meteor": ("vfx_fireball", [(2.4, 1.8, 1.0), (1.7, 0.8, 0.2), (1.1, 0.38, 0.06), (0.8, 0.2, 0.05), (0.42, 0.1, 0.05)],
                   [(1.3, 0.8, 0.35), (1.1, 0.5, 0.15), (0.8, 0.35, 0.12), (0.5, 0.22, 0.1)],
                   [(1, 0.6, 0.25), (0.8, 0.35, 0.12), (1, 0.85, 0.4), (0.55, 0.28, 0.15)],
                   {"seed": "79", "meteor": "true"}),
    "vfx_stalactite": ("vfx_frost_2", [(1.9, 2.1, 2.6), (0.8, 1.2, 2.0), (0.45, 0.6, 1.5), (0.25, 0.3, 1.0), (0.1, 0.1, 0.5)],
                       [(2.0, 2.1, 2.5), (1.0, 1.1, 1.6), (0.8, 0.8, 1.5), (0.6, 0.6, 1.4)],
                       [(0.85, 0.9, 1), (0.6, 0.7, 1), (0.9, 0.8, 1), (1, 1, 1)],
                       {"seed": "83"}),
    "vfx_plasma": ("vfx_magic_flame", [(2.6, 2.0, 2.6), (2.0, 0.8, 1.8), (1.2, 0.35, 1.3), (0.6, 0.18, 0.9), (0.25, 0.06, 0.45)],
                   [(2.4, 2.0, 2.4), (1.6, 0.8, 1.6), (1.2, 0.5, 1.5), (0.9, 0.4, 1.4)],
                   [(1, 0.6, 1), (0.9, 0.4, 1), (1, 0.9, 1), (0.7, 0.4, 1)],
                   {"core_spin": "1.8", "seed": "89"}),
    "vfx_charged_lance": ("vfx_frost_3", [(2.4, 2.6, 2.6), (1.4, 2.0, 1.6), (0.6, 1.3, 1.6), (0.3, 0.6, 1.2), (0.1, 0.2, 0.55)],
                          [(2.2, 2.4, 2.4), (1.4, 1.6, 1.0), (0.9, 1.3, 1.5), (0.7, 1.0, 1.5)],
                          [(0.9, 1, 0.6), (0.6, 0.95, 1), (1, 1, 1), (0.7, 0.85, 1)],
                          {"core_spin": "1.9", "ribbon_speed": "2.2", "seed": "97", "style": "1"}),
    "vfx_quake": ("vfx_flame", [(2.0, 1.7, 1.0), (1.3, 0.85, 0.35), (0.7, 0.45, 0.18), (0.38, 0.24, 0.1), (0.16, 0.1, 0.05)],
                  [(1.8, 1.5, 0.9), (1.0, 0.75, 0.35), (0.7, 0.5, 0.25), (0.45, 0.32, 0.18)],
                  [(1, 0.8, 0.4), (0.7, 0.5, 0.25), (0.9, 0.7, 0.35), (0.5, 0.36, 0.2)],
                  {"core_spin": "0.5", "seed": "101"}),
    "vfx_magnet": ("vfx_arcane_orb", [(2.2, 2.2, 2.6), (1.8, 0.6, 0.6), (0.6, 0.6, 1.8), (0.35, 0.3, 0.9), (0.12, 0.1, 0.35)],
                   [(2.2, 2.2, 2.4), (1.6, 0.6, 0.6), (0.6, 0.7, 1.6), (0.8, 0.8, 1.2)],
                   [(1, 0.4, 0.4), (0.4, 0.55, 1), (1, 1, 1), (0.8, 0.8, 1)],
                   {"seed": "103"}),
    # Arcano: blanco, rosa y violeta; remolino nítido (estilo arcano).
    "vfx_arcane": ("vfx_frost_2", [(2.6, 2.3, 2.8), (2.0, 0.9, 2.0), (1.1, 0.45, 1.7), (0.55, 0.22, 1.1), (0.2, 0.07, 0.45)],
                   [(2.4, 2.2, 2.6), (1.8, 0.8, 1.7), (1.0, 0.6, 1.8), (0.8, 0.5, 1.6)],
                   [(1, 0.55, 0.95), (0.8, 0.55, 1), (1, 0.9, 1), (0.65, 0.45, 1)],
                   {"flare_color": c(2.4, 2.0, 2.6, 1), "light_color": c(0.85, 0.6, 1, 1), "core_spin": "0.9",
                    "core_swirl": "0.28", "core_arms": "4.0", "ribbon_speed": "1.3", "seed": "107", "style": "1",
                    "glow_rays": "0.8", "ribbon_count": "6", "ribbon_dashes": "3", "ribbon_tail": "0.3",
                    "precession_deg": "70.0"}),
    # Ecos: el hechizo de siempre, pero teñido de violeta arcano.
    "vfx_echo_fire": ("vfx_fireball", [(2.6, 2.0, 2.6), (2.0, 0.75, 1.5), (1.3, 0.3, 1.1), (0.55, 0.12, 0.75), (0.2, 0.05, 0.35)],
                      [(2.4, 1.9, 2.4), (1.8, 0.7, 1.5), (1.3, 0.5, 1.6), (0.9, 0.4, 1.4)],
                      [(1, 0.45, 0.85), (0.85, 0.35, 1), (1, 0.8, 0.95), (0.6, 0.3, 0.9)],
                      {"light_color": c(1, 0.5, 0.9, 1), "seed": "109"}),
    "vfx_echo_ice": ("vfx_frost_3", [(2.3, 2.2, 2.8), (1.3, 1.1, 2.3), (0.75, 0.55, 1.8), (0.38, 0.25, 1.1), (0.12, 0.08, 0.5)],
                     [(2.2, 2.1, 2.6), (1.2, 1.0, 1.9), (0.9, 0.7, 1.7), (0.7, 0.55, 1.6)],
                     [(0.8, 0.75, 1), (0.6, 0.55, 1), (1, 0.95, 1), (0.85, 0.6, 1)],
                     {"light_color": c(0.75, 0.7, 1, 1), "core_spin": "1.4", "seed": "113"}),
    "vfx_echo_thunder": ("vfx_frost_3", [(2.7, 2.5, 2.9), (2.0, 1.3, 2.3), (1.3, 0.6, 1.8), (0.6, 0.28, 1.2), (0.2, 0.08, 0.5)],
                         [(2.5, 2.3, 2.7), (1.8, 1.1, 2.0), (1.2, 0.7, 1.8), (0.9, 0.6, 1.7)],
                         [(1, 0.8, 1), (0.95, 0.6, 1), (0.8, 0.7, 1), (1, 1, 1)],
                         {"flare_color": c(2.6, 2.3, 2.8, 1), "light_color": c(0.9, 0.7, 1, 1), "light_energy": "0.8",
                          "core_spin": "2.0", "ribbon_speed": "2.6", "seed": "127", "style": "1"}),
    # Gravedad: un agujero oscuro con el borde rosa encendido que gira deprisa.
    "vfx_gravity": ("vfx_arcane_orb", [(0.06, 0.02, 0.14), (2.4, 1.3, 2.7), (1.3, 0.35, 1.6), (0.55, 0.15, 0.9), (0.18, 0.05, 0.38)],
                    [(2.2, 1.8, 2.6), (1.6, 0.6, 1.8), (1.0, 0.5, 1.8), (0.7, 0.4, 1.5)],
                    [(1, 0.4, 0.9), (0.7, 0.4, 1), (1, 0.85, 1), (0.5, 0.3, 0.9)],
                    {"flare_color": c(2.0, 1.4, 2.4, 1), "light_color": c(0.8, 0.45, 1, 1), "core_spin": "1.6",
                     "core_swirl": "0.35", "core_arms": "4.0", "core_twist": "10.0", "ribbon_speed": "2.0",
                     "seed": "131", "style": "1", "converge_amount": "90", "glow_rays": "0.9",
                     "body_intensity": "0.9", "glow_intensity": "0.22", "glow_scale": "2.2"}),
    "vfx_resonance": ("vfx_arcane_orb", [(2.9, 2.7, 3.0), (2.3, 1.3, 2.5), (1.5, 0.65, 2.0), (0.75, 0.3, 1.3), (0.25, 0.1, 0.55)],
                      [(2.6, 2.4, 2.8), (2.0, 1.0, 2.2), (1.3, 0.8, 2.0), (1.0, 0.7, 1.8)],
                      [(1, 0.7, 1), (0.85, 0.6, 1), (1, 1, 1), (0.7, 0.5, 1)],
                      {"flare_color": c(2.8, 2.5, 3.0, 1), "light_color": c(0.9, 0.7, 1, 1), "core_spin": "1.2",
                       "core_swirl": "0.3", "ribbon_speed": "1.6", "seed": "137", "style": "1", "glow_rays": "1.0"}),
}


# ---------------------------------------------------------------- niveles y recetas

def tier_block(tid, t, visual_id, ramp_id):
    lines = [f'[sub_resource type="Resource" id="{tid}"]', 'script = ExtResource("tier")']
    for k, v in t.items():
        lines.append(f"{k} = {v}")
    lines.append(f'visual = ExtResource("{visual_id}")')
    lines.append(f'trail_ramp = SubResource("{ramp_id}")')
    return "\n".join(lines)


def ramp_block(rid, cols):
    return (f'[sub_resource type="Gradient" id="{rid}"]\n'
            "offsets = PackedFloat32Array(0, 0.2, 0.45, 0.72, 1)\n"
            f"colors = {colors(cols)}")


def sfx_list(names, ext):
    return "Array[AudioStream]([%s])" % ", ".join(f'ExtResource("{ext[n]}")' for n in names)


def write_resource(path, script_class, script_path, sub_blocks, res_lines, ext_paths):
    ext = {}
    head = []
    for key, (typ, p) in ext_paths.items():
        ext[key] = key
        head.append(f'[ext_resource type="{typ}" path="{p}" id="{key}"]')
    text = [f'[gd_resource type="Resource" script_class="{script_class}" format=3]', ""]
    text += [f'[ext_resource type="Script" path="{script_path}" id="main"]'] + head + [""]
    for b in sub_blocks:
        text += [b, ""]
    text += ["[resource]", 'script = ExtResource("main")'] + res_lines + [""]
    path.write_text("\n".join(text))


def sfx(name):
    return ("AudioStream", f"res://audio/sfx/{name}.ogg")


ELEMENT_SPECS = {
    "bolt": {
        "display": "Rayo", "color": c(1, 0.92, 0.42, 1), "visual": "vfx_bolt", "power": "bolt_tier",
        "unlock": "awaken_bolt", "chain": 1, "shard_bonus": 0, "circle": c(1.4, 1.3, 0.5, 1),
        "ramp": [(2.4, 2.4, 2.6), (1.8, 1.6, 0.6), (1.0, 0.8, 0.3), (0.5, 0.35, 1.0), (0.15, 0.1, 0.4)],
        "cast": ["sfx_bolt_cast_01", "sfx_bolt_cast_02"], "impact": ["sfx_bolt_impact_01"], "pitch": 1.0,
        "tiers": [
            dict(cooldown_sec=1.35, damage=3, speed=90.0, wobble=0.05, shards_min=1, shards_max=1, impact_particles=26,
                 light_energy=3.0, crack_radius=0.8, shake=0.06, orb_scale=4.0, trail_width=0.1, trail_length=0.06),
            dict(cooldown_sec=0.9, damage=6, speed=110.0, wobble=0.04, shards_min=1, shards_max=2, impact_particles=30,
                 light_energy=3.2, crack_radius=1.0, shake=0.08, orb_scale=5.0, trail_width=0.14, trail_length=0.07),
            dict(cooldown_sec=0.77, damage=9, speed=130.0, wobble=0.03, shards_min=2, shards_max=3, impact_particles=36,
                 light_energy=3.5, crack_radius=1.3, shake=0.11, orb_scale=6.0, trail_width=0.18, trail_length=0.08),
        ],
        "core": c(1, 1, 0.9, 1), "glow": c(1, 0.85, 0.35, 1), "tint": c(1, 0.95, 0.6, 1),
    },
    "earth": {
        "display": "Tierra", "color": c(0.85, 0.62, 0.36, 1), "visual": "vfx_earth", "power": "earth_tier",
        "unlock": "awaken_earth", "chain": 0, "shard_bonus": 1, "circle": c(1.2, 0.8, 0.35, 1),
        "ramp": [(2.0, 1.5, 0.8), (1.2, 0.65, 0.25), (0.6, 0.35, 0.14), (0.3, 0.18, 0.08), (0.12, 0.07, 0.04)],
        "cast": ["sfx_earth_cast_01", "sfx_earth_cast_02"], "impact": ["sfx_earth_impact_01"], "pitch": 0.9,
        "tiers": [
            dict(cooldown_sec=2.25, damage=7, speed=15.0, wobble=0.1, shards_min=1, shards_max=2, impact_particles=30,
                 light_energy=2.0, crack_radius=1.2, shake=0.16, orb_scale=6.0, trail_width=0.3, trail_length=0.25,
                 trail_smoke=0.6),
            dict(cooldown_sec=1.5, damage=14, speed=17.0, wobble=0.08, shards_min=2, shards_max=3, impact_particles=36,
                 light_energy=2.2, crack_radius=1.5, shake=0.2, orb_scale=7.5, trail_width=0.4, trail_length=0.3,
                 trail_smoke=0.7),
            dict(cooldown_sec=1.28, damage=21, speed=19.0, wobble=0.06, shards_min=2, shards_max=4, impact_particles=44,
                 light_energy=2.4, crack_radius=1.9, shake=0.25, orb_scale=9.0, trail_width=0.5, trail_length=0.35,
                 trail_smoke=0.8),
        ],
        "core": c(1, 0.85, 0.6, 1), "glow": c(0.95, 0.5, 0.2, 1), "tint": c(0.9, 0.65, 0.35, 1),
    },
    "arcane": {
        "display": "Arcano", "color": c(0.8, 0.6, 1, 1), "visual": "vfx_arcane", "power": "arcane_tier",
        "unlock": "awaken_arcane", "chain": 0, "shard_bonus": 0, "circle": c(1.4, 0.7, 1.9, 1),
        "ramp": [(2.6, 2.3, 2.8), (2.0, 0.9, 2.0), (1.1, 0.45, 1.7), (0.55, 0.22, 1.1), (0.2, 0.07, 0.45)],
        "cast": ["sfx_arcane_cast_01", "sfx_arcane_cast_02"], "impact": ["sfx_arcane_impact_01"], "pitch": 1.0,
        # Cada disparo deja `echoes` ecos fantasma que repiten el golpe en el mismo sitio.
        "echo": ["sfx_arcane_echo_01", "sfx_arcane_echo_02"],
        "extra": {"echo_delay": "0.24", "echo_damage": "0.45", "resonant_bonus": "0.06"},
        "tiers": [
            dict(cooldown_sec=1.5, damage=10, speed=34.0, wobble=0.12, shards_min=1, shards_max=1, impact_particles=28,
                 light_energy=3.0, crack_radius=0.9, shake=0.08, orb_scale=4.5, trail_width=0.16, trail_length=0.16,
                 echoes=1),
            dict(cooldown_sec=1.0, damage=20, speed=38.0, wobble=0.08, shards_min=1, shards_max=2, impact_particles=32,
                 light_energy=3.2, crack_radius=1.1, shake=0.1, orb_scale=5.5, trail_width=0.2, trail_length=0.18,
                 echoes=1),
            dict(cooldown_sec=0.85, damage=30, speed=44.0, wobble=0.05, shards_min=2, shards_max=3, impact_particles=38,
                 light_energy=3.5, crack_radius=1.4, shake=0.13, orb_scale=6.5, trail_width=0.24, trail_length=0.2,
                 echoes=2),
        ],
        "core": c(1, 0.92, 1, 1), "glow": c(0.85, 0.45, 1, 1), "tint": c(0.95, 0.65, 1, 1),
    },
}


def write_element(eid, spec):
    ext = {"tier": ("Script", "res://data/defs/spell_tier.gd"),
           "vis": ("Resource", f"res://data/spells/{spec['visual']}.tres")}
    for n in spec["cast"] + spec["impact"] + spec.get("echo", []):
        ext[n] = sfx(n)
    subs = [ramp_block("ramp", spec["ramp"])]
    for i, t in enumerate(spec["tiers"]):
        t = dict(t)
        t.update(color_core=spec["core"], color_glow=spec["glow"], impact_tint=spec["tint"], size="0.2")
        subs.append(tier_block(f"tier_{i + 1}", t, "vis", "ramp"))
    res = [
        f'id = &"{eid}"', f'display_name = "{spec["display"]}"', f"color = {spec['color']}",
        "tiers = Array[ExtResource(\"tier\")]([%s])" % ", ".join(f'SubResource("tier_{i + 1}")' for i in range(len(spec["tiers"]))),
        'hand_visual = ExtResource("vis")', f'power_stat = &"{spec["power"]}"', f'unlock_upgrade = &"{spec["unlock"]}"',
        f"cast_sfx = {sfx_list(spec['cast'], {n: n for n in spec['cast']})}", f"cast_pitch = {spec['pitch']}",
        f"impact_sfx = {sfx_list(spec['impact'], {n: n for n in spec['impact']})}",
        f"chain_count = {spec['chain']}", f"shard_bonus = {spec['shard_bonus']}", f"circle_color = {spec['circle']}",
    ]
    if spec.get("echo"):
        res.append(f"echo_sfx = {sfx_list(spec['echo'], {n: n for n in spec['echo']})}")
    for k, v in spec.get("extra", {}).items():
        res.append(f"{k} = {v}")
    write_resource(ELEMENTS / f"{eid}.tres", "ElementDef", "res://data/defs/element_def.gd", subs, res, ext)


# Una receta: elementos, textos, entrega, números, aspecto y sonidos.
RECIPES = [
    dict(id="ice_lance", name="Lanza de Hielo", elements=["frost", "frost"], delivery=3,
         description="Una lanza de hielo que perfora un túnel hondo en el cristal y deja sus paredes congeladas.",
         riddle="El frío que se junta con el frío no rompe: atraviesa.",
         dmg=3.0, pierce=7.0, freeze=True, charge=0.8, cooldown=2.2, visual="vfx_ice_lance",
         circle=(0.6, 0.9, 1.4), hot=(1.2, 1.4, 1.6), cast=["sfx_ice_lance_01"], impact=["sfx_frost_impact_01", "sfx_frost_impact_02"],
         loop="sfx_fireball_charge_loop",
         tier=dict(damage=5, speed=70.0, wobble=0.0, shards_min=2, shards_max=3, impact_particles=40, light_energy=4.0,
                   crack_radius=1.2, shake=0.18, orb_scale=6.0, trail_width=0.5, trail_length=0.3,
                   core=(0.9, 1, 1), glow=(0.45, 0.85, 1), tint=(0.7, 0.95, 1),
                   ramp=[(2.0, 2.3, 2.6), (0.7, 1.5, 2.1), (0.3, 0.85, 1.6), (0.14, 0.4, 1.0), (0.06, 0.15, 0.5)])),
    dict(id="thunder", name="Juicio del Trueno", elements=["bolt", "bolt"], delivery=1,
         description="Abre círculos en el cielo sobre el blanco y descarga un rayo colosal que salta a su alrededor.",
         riddle="Dos chispas del cielo, si las sostienes, llaman a su madre.",
         dmg=2.85, chain=4, sky_height=46.0, fall=0.12, sky_circles=3, charge=1.1, cooldown=3.0, visual="vfx_thunder",
         circle=(1.5, 1.4, 0.6), hot=(1.8, 1.8, 1.6), cast=["sfx_thunder_01"], impact=["sfx_bolt_impact_01"],
         loop="amb_storm_charge_loop",
         tier=dict(damage=8, speed=400.0, wobble=0.0, shards_min=3, shards_max=5, impact_particles=60, light_energy=8.0,
                   crack_radius=2.2, shake=0.45, orb_scale=10.0, trail_width=1.6, trail_length=0.12,
                   core=(1, 1, 0.9), glow=(1, 0.85, 0.4), tint=(1, 0.95, 0.6),
                   ramp=[(2.6, 2.6, 2.8), (2.0, 1.8, 0.8), (1.2, 0.9, 0.4), (0.6, 0.4, 1.2), (0.2, 0.1, 0.5)])),
    dict(id="meteor", name="Meteoro", elements=["spark", "earth"], delivery=1,
         description="Círculos mágicos se abren en el cielo, uno sobre otro. Al soltar, una roca ardiendo cae del cielo y "
                     "abre un cráter enorme.",
         riddle="El fuego solo vuela. Dale un cuerpo de piedra y caerá del cielo.",
         dmg=7.8, area=3.0, area_hits=7, burn=5.0, sky_height=70.0, fall=1.4, sky_circles=4, charge=1.4, cooldown=4.0,
         visual="vfx_meteor", circle=(1.6, 0.7, 0.25), hot=(1.9, 1.5, 0.9), cast=["sfx_meteor_fall_01"],
         impact=["sfx_meteor_impact_01"], loop="amb_sky_charge_loop",
         tier=dict(damage=10, speed=60.0, wobble=0.0, shards_min=4, shards_max=6, shard_scale=1.4, impact_particles=90,
                   light_energy=4.0, crack_radius=3.0, shake=0.6, orb_scale=26.0, trail_width=5.0, trail_length=0.7,
                   trail_smoke=1.0, core=(1, 0.9, 0.6), glow=(1, 0.4, 0.1), tint=(1, 0.6, 0.25),
                   ramp=[(2.4, 1.8, 1.0), (1.7, 0.8, 0.2), (1.0, 0.35, 0.06), (0.45, 0.14, 0.05), (0.18, 0.06, 0.04)])),
    dict(id="stalactites", name="Lluvia de Estalactitas", elements=["earth", "frost"], delivery=2,
         description="Un círculo en el cielo y del cielo cae una lluvia de estalactitas de hielo sobre toda la zona.",
         riddle="La piedra pesa, el hielo corta. Juntos, llueven.",
         dmg=6.1, rain=14, rain_radius=5.0, sky_height=32.0, sky_circles=2, charge=1.0, cooldown=3.2,
         visual="vfx_stalactite", circle=(0.7, 0.8, 1.5), hot=(1.3, 1.4, 1.7), cast=["sfx_ice_lance_01"],
         impact=["sfx_frost_impact_01", "sfx_frost_impact_02"], loop="amb_sky_charge_loop",
         tier=dict(damage=3, speed=45.0, wobble=0.0, shards_min=1, shards_max=2, impact_particles=24, light_energy=2.5,
                   crack_radius=1.0, shake=0.08, orb_scale=4.5, trail_width=0.35, trail_length=0.2,
                   core=(0.9, 0.95, 1), glow=(0.55, 0.65, 1), tint=(0.8, 0.85, 1),
                   ramp=[(1.9, 2.1, 2.6), (0.8, 1.2, 2.0), (0.45, 0.6, 1.5), (0.25, 0.3, 1.0), (0.1, 0.1, 0.5)])),
    dict(id="plasma", name="Haz de Plasma", elements=["spark", "bolt"], delivery=4,
         description="Un haz continuo de plasma que sigue tu mirilla durante un segundo y medio: barre el cristal.",
         riddle="El fuego que no se apaga y el rayo que no se va: mantenlos y no sueltes la mirada.",
         dmg=5.4, beam=1.6, charge=0.9, cooldown=3.4, visual="vfx_plasma", circle=(1.5, 0.5, 1.4), hot=(1.8, 1.4, 1.8),
         cast=["sfx_bolt_cast_01"], impact=["sfx_bolt_impact_01"], loop="amb_storm_charge_loop",
         tier=dict(damage=4, speed=200.0, wobble=0.0, shards_min=1, shards_max=1, impact_particles=18, light_energy=3.0,
                   crack_radius=0.9, shake=0.05, orb_scale=6.0, trail_width=0.3, trail_length=0.1,
                   core=(1, 0.9, 1), glow=(1, 0.4, 0.9), tint=(1, 0.6, 1),
                   ramp=[(2.6, 2.0, 2.6), (2.0, 0.8, 1.8), (1.2, 0.35, 1.3), (0.6, 0.18, 0.9), (0.25, 0.06, 0.45)])),
    dict(id="charged_lance", name="Lanza Cargada", elements=["frost", "bolt"], delivery=3,
         description="Hielo cargado de rayo: perfora muy hondo, salta en chispas por el túnel y suelta fragmentos mayores.",
         riddle="Si el hielo atraviesa, ¿qué hará con un rayo dentro?",
         dmg=3.4, pierce=11.0, chain=2, shard_bonus=1, charge=1.0, cooldown=2.8, visual="vfx_charged_lance",
         circle=(0.8, 1.4, 1.2), hot=(1.5, 1.7, 1.5), cast=["sfx_ice_lance_01", "sfx_bolt_cast_02"],
         impact=["sfx_bolt_impact_01"], loop="amb_storm_charge_loop",
         tier=dict(damage=6, speed=90.0, wobble=0.0, shards_min=2, shards_max=3, impact_particles=44, light_energy=5.0,
                   crack_radius=1.3, shake=0.22, orb_scale=7.0, trail_width=0.6, trail_length=0.3,
                   core=(1, 1, 0.9), glow=(0.6, 0.95, 1), tint=(0.85, 1, 0.8),
                   ramp=[(2.4, 2.6, 2.6), (1.4, 2.0, 1.6), (0.6, 1.3, 1.6), (0.3, 0.6, 1.2), (0.1, 0.2, 0.55)])),
    dict(id="earthquake", name="Terremoto", elements=["earth", "earth"], delivery=5,
         description="Golpeas el suelo: una onda corre hasta el cristal y su base revienta desde abajo.",
         riddle="Piedra contra piedra no vuela: hace temblar.",
         dmg=7.0, area=3.5, area_hits=8, charge=1.2, cooldown=3.6, visual="vfx_quake", circle=(1.3, 0.9, 0.4),
         hot=(1.7, 1.4, 0.9), cast=["sfx_quake_01"], impact=["sfx_earth_impact_01"], loop="amb_sky_charge_loop",
         tier=dict(damage=8, speed=26.0, wobble=0.0, shards_min=3, shards_max=5, shard_scale=1.3, impact_particles=60,
                   light_energy=3.0, crack_radius=2.4, shake=0.5, orb_scale=9.0, trail_width=1.4, trail_length=0.4,
                   trail_smoke=1.0, core=(1, 0.9, 0.7), glow=(0.9, 0.6, 0.25), tint=(0.95, 0.75, 0.45),
                   ramp=[(2.0, 1.7, 1.0), (1.3, 0.85, 0.35), (0.7, 0.45, 0.18), (0.38, 0.24, 0.1), (0.16, 0.1, 0.05)])),
    dict(id="magnetism", name="Magnetismo", elements=["earth", "bolt"], delivery=6,
         description="Utilidad: un pulso magnético atrae hacia ti todos los fragmentos del suelo que te quepan.",
         riddle="El rayo empuja, la tierra atrae. ¿Y si atraen lo que has roto?",
         dmg=0.0, charge=0.6, cooldown=6.0, visual="vfx_magnet", circle=(1.4, 0.5, 0.5), hot=(0.7, 0.8, 1.6),
         cast=["sfx_magnet_01"], impact=["sfx_bolt_impact_01"], loop="amb_storm_charge_loop",
         tier=dict(damage=1, speed=40.0, wobble=0.0, shards_min=0, shards_max=0, impact_particles=10, light_energy=2.0,
                   crack_radius=0.6, shake=0.1, orb_scale=6.0, trail_width=0.3, trail_length=0.2,
                   core=(1, 1, 1), glow=(0.6, 0.6, 1), tint=(0.8, 0.8, 1),
                   ramp=[(2.2, 2.2, 2.6), (1.8, 0.6, 0.6), (0.6, 0.6, 1.8), (0.35, 0.3, 0.9), (0.12, 0.1, 0.35)])),
    # Arcano: los Ecos repiten otra receta (`echo_of`) con copias fantasma violeta que salen de
    # círculos arcanos; Gravedad atrae todos los fragmentos; Resonancia hace resonante cada golpe.
    dict(id="echo_fire", name="Eco de Fuego", elements=["arcane", "spark"], delivery=0,
         description="La Bola de Fuego sale y, tras ella, dos ecos fantasma brotan de círculos arcanos y vuelven a "
                     "estallar donde mires.",
         riddle="Lo arcano no crea: repite. Pídele que repita tu primer fuego.",
         dmg=3.0, echo_of="fireball", echo_count=2, echo_delay=0.32, echo_damage=0.6, charge=0.9, cooldown=3.0,
         visual="vfx_echo_fire", circle=(1.5, 0.6, 1.8), hot=(2.0, 1.5, 2.0), cast=["sfx_echo_cast_01"],
         impact=["sfx_arcane_impact_01"], loop="amb_arcane_charge_loop", flight="sfx_fireball_charge_loop",
         echo_sfx=["sfx_arcane_echo_01", "sfx_arcane_echo_02"],
         tier=dict(damage=5, speed=20.0, wobble=0.04, shards_min=2, shards_max=3, shard_scale=1.3, impact_particles=60,
                   light_energy=3.0, crack_radius=1.8, shake=0.3, orb_scale=8.0, trail_width=1.1, trail_length=0.4,
                   trail_smoke=0.5, core=(1, 0.9, 1), glow=(1, 0.35, 0.8), tint=(1, 0.55, 0.95),
                   ramp=[(2.6, 2.0, 2.6), (2.0, 0.75, 1.5), (1.3, 0.3, 1.1), (0.55, 0.12, 0.75), (0.2, 0.05, 0.35)])),
    dict(id="echo_ice", name="Eco de Hielo", elements=["arcane", "frost"], delivery=3,
         description="Una Lanza de Hielo y dos ecos que la siguen por el mismo túnel (o por el que mires): el cristal se "
                     "congela por dentro.",
         riddle="Lo que atraviesa una vez, ¿por qué no tres? Pregúntale al eco del frío.",
         dmg=2.9, echo_of="ice_lance", echo_count=2, echo_delay=0.3, echo_damage=0.6, charge=0.9, cooldown=2.8,
         visual="vfx_echo_ice", circle=(0.9, 0.7, 1.8), hot=(1.6, 1.5, 2.2), cast=["sfx_echo_cast_01"],
         impact=["sfx_arcane_impact_01"], loop="amb_arcane_charge_loop", flight="sfx_fireball_charge_loop",
         echo_sfx=["sfx_arcane_echo_01", "sfx_arcane_echo_02"],
         tier=dict(damage=5, speed=70.0, wobble=0.0, shards_min=2, shards_max=3, impact_particles=40, light_energy=4.0,
                   crack_radius=1.2, shake=0.18, orb_scale=6.0, trail_width=0.5, trail_length=0.3,
                   core=(0.95, 0.95, 1), glow=(0.6, 0.55, 1), tint=(0.8, 0.75, 1),
                   ramp=[(2.3, 2.2, 2.8), (1.3, 1.1, 2.3), (0.75, 0.55, 1.8), (0.38, 0.25, 1.1), (0.12, 0.08, 0.5)])),
    dict(id="echo_thunder", name="Eco del Trueno", elements=["arcane", "bolt"], delivery=1,
         description="Cae el Juicio del Trueno y el cielo lo repite: tres descargas fantasma más, cada una allí donde "
                     "mires.",
         riddle="Dicen que un rayo nunca cae dos veces en el mismo sitio. Lo arcano no ha leído ese refrán.",
         dmg=2.3, echo_of="thunder", echo_count=3, echo_delay=0.42, echo_damage=0.55, chain=4, sky_height=46.0,
         fall=0.12, sky_circles=3, charge=1.1, cooldown=3.6, visual="vfx_echo_thunder", circle=(1.3, 0.7, 1.9),
         hot=(2.0, 1.8, 2.4), cast=["sfx_thunder_01"], impact=["sfx_bolt_impact_01"], loop="amb_storm_charge_loop",
         echo_sfx=["sfx_thunder_01"],
         tier=dict(damage=8, speed=400.0, wobble=0.0, shards_min=3, shards_max=5, impact_particles=60, light_energy=8.0,
                   crack_radius=2.2, shake=0.45, orb_scale=10.0, trail_width=1.6, trail_length=0.12,
                   core=(1, 0.95, 1), glow=(0.85, 0.55, 1), tint=(0.95, 0.75, 1),
                   ramp=[(2.7, 2.5, 2.9), (2.0, 1.3, 2.3), (1.3, 0.6, 1.8), (0.6, 0.28, 1.2), (0.2, 0.08, 0.5)])),
    dict(id="gravity", name="Gravedad", elements=["arcane", "earth"], delivery=7,
         description="Utilidad: abre un pozo de gravedad delante de ti y todos los fragmentos sueltos del valle vuelan en "
                     "espiral hacia él. Lo que no quepa en la bolsa va derecho a la tolva.",
         riddle="La piedra siempre cae. Con lo arcano, cae hacia ti... desde todo el valle.",
         dmg=0.0, gravity=2.5, charge=0.8, cooldown=5.0, visual="vfx_gravity", circle=(1.2, 0.4, 1.8),
         hot=(1.9, 1.2, 2.3), cast=["sfx_gravity_01"], impact=["sfx_arcane_impact_01"], loop="amb_arcane_charge_loop",
         tier=dict(damage=1, speed=40.0, wobble=0.0, shards_min=0, shards_max=0, impact_particles=10, light_energy=3.0,
                   crack_radius=0.6, shake=0.1, orb_scale=12.0, trail_width=0.3, trail_length=0.2,
                   core=(1, 0.9, 1), glow=(0.7, 0.3, 1), tint=(0.85, 0.5, 1),
                   ramp=[(2.4, 1.3, 2.7), (1.3, 0.35, 1.6), (0.55, 0.15, 0.9), (0.18, 0.05, 0.38), (0.06, 0.02, 0.14)])),
    dict(id="resonance", name="Resonancia Arcana", elements=["arcane", "arcane"], delivery=8,
         description="El cristal entero vibra con tu golpe: saltan rayos resonantes por la superficie y, durante cinco "
                     "segundos, cada golpe que des es resonante.",
         riddle="Lo puro con lo puro ni quema ni corta: hace cantar al cristal.",
         dmg=2.9, area=2.5, area_hits=6, chain=6, buff=5.0, lockout=8.0, charge=1.2, cooldown=2.5,
         visual="vfx_resonance", circle=(1.4, 0.7, 1.9), hot=(2.2, 1.8, 2.4), cast=["sfx_resonance_01"],
         impact=["sfx_arcane_impact_01"], loop="amb_arcane_charge_loop",
         tier=dict(damage=6, speed=80.0, wobble=0.0, shards_min=3, shards_max=5, impact_particles=70, light_energy=5.0,
                   crack_radius=1.3, shake=0.4, orb_scale=7.0, trail_width=0.8, trail_length=0.3,
                   core=(1, 0.95, 1), glow=(0.85, 0.5, 1), tint=(0.95, 0.7, 1),
                   ramp=[(2.9, 2.7, 3.0), (2.3, 1.3, 2.5), (1.5, 0.65, 2.0), (0.75, 0.3, 1.3), (0.25, 0.1, 0.55)])),
    # Reacciones: no se lanzan; se descubren al provocarlas en el cristal.
    dict(id="steam", name="Explosión de Vapor", elements=["spark", "frost"], reaction=True,
         description="Reacción: el fuego sobre cristal congelado lo hace estallar en vapor: más daño y una lluvia de "
                     "fragmentos.",
         riddle="Reacción: lo que hiela, el fuego lo hace explotar.", visual=None),
    dict(id="temper", name="Temple", elements=["frost", "spark"], reaction=True,
         description="Reacción: la escarcha sobre cristal ardiendo lo templa de golpe y se parte en fragmentos grandes.",
         riddle="Reacción: lo que arde, enfríalo de golpe.", visual=None),
]


def write_recipe(r):
    ext = {"tier": ("Script", "res://data/defs/spell_tier.gd"),
           "combine": sfx("sfx_spell_combine_01")}
    res = [f'id = &"{r["id"]}"', f'display_name = "{r["name"]}"',
           "elements = Array[StringName]([%s])" % ", ".join(f'&"{e}"' for e in r["elements"]),
           f'description = "{r["description"]}"', f'riddle = "{r["riddle"]}"']
    subs = []
    if r.get("reaction"):
        res.append("is_reaction = true")
        write_resource(SPELLS / f"recipe_{r['id']}.tres", "SpellRecipe", "res://data/defs/spell_recipe.gd", subs, res,
                       {})
        return
    ext["vis"] = ("Resource", f"res://data/spells/{r['visual']}.tres")
    ext["loop"] = sfx(r["loop"])
    if r.get("flight"):
        ext["flight"] = sfx(r["flight"])
    for n in r["cast"] + r["impact"] + r.get("echo_sfx", []):
        ext[n] = sfx(n)
    t = dict(r["tier"])
    subs.append(ramp_block("ramp", t.pop("ramp")))
    core, glow, tint = t.pop("core"), t.pop("glow"), t.pop("tint")
    t.update(color_core=c(*core, 1), color_glow=c(*glow, 1), impact_tint=c(*tint, 1), size="0.5",
             cooldown_sec=r["cooldown"])
    lines = [f'[sub_resource type="Resource" id="t"]', 'script = ExtResource("tier")']
    for k, v in t.items():
        lines.append(f"{k} = {v}")
    lines += ['visual = ExtResource("vis")', 'trail_ramp = SubResource("ramp")', 'flight_sfx = ExtResource("%s")' % ("flight" if r.get("flight") else "loop")]
    subs.append("\n".join(lines))
    res += [
        f"delivery = {r['delivery']}", f"damage_multiplier = {r['dmg']}",
        f"area_radius = {r.get('area', 0.0)}", f"area_hits = {r.get('area_hits', 0)}",
        f"burn_sec = {r.get('burn', 0.0)}", "burn_damage = 2", "burn_tick_sec = 0.4",
        f"sky_height = {r.get('sky_height', 40.0)}", f"fall_sec = {r.get('fall', 1.0)}",
        f"sky_circles = {r.get('sky_circles', 3)}", f"rain_count = {r.get('rain', 0)}",
        f"rain_radius = {r.get('rain_radius', 4.0)}", f"pierce_depth = {r.get('pierce', 0.0)}",
        f"freeze_trail = {'true' if r.get('freeze') else 'false'}", f"chain_count = {r.get('chain', 0)}",
        f"beam_sec = {r.get('beam', 0.0)}", f"shard_bonus = {r.get('shard_bonus', 0)}",
        f"circle_color = {c(*r['circle'], 1)}", f"circle_hot = {c(*r['hot'], 1)}",
        f"charge_sec = {r['charge']}", "min_power = 0.5", f"cooldown_sec = {r['cooldown']}",
        'tier = SubResource("t")', 'visual = ExtResource("vis")', 'combine_sfx = ExtResource("combine")',
        'charge_loop_sfx = ExtResource("loop")',
        f"cast_sfx = {sfx_list(r['cast'], {n: n for n in r['cast']})}",
        f"impact_sfx = {sfx_list(r['impact'], {n: n for n in r['impact']})}",
    ]
    if r.get("echo_of"):
        res += [f'echo_of = &"{r["echo_of"]}"', f"echo_count = {r['echo_count']}",
                f"echo_delay = {r['echo_delay']}", f"echo_damage = {r['echo_damage']}",
                f"echo_sfx = {sfx_list(r['echo_sfx'], {n: n for n in r['echo_sfx']})}"]
    if r.get("buff"):
        res += [f"buff_sec = {r['buff']}", f"buff_lockout_sec = {r['lockout']}"]
    if r.get("gravity"):
        res.append(f"gravity_sec = {r['gravity']}")
    write_resource(SPELLS / f"recipe_{r['id']}.tres", "SpellRecipe", "res://data/defs/spell_recipe.gd", subs, res, ext)


def main():
    for name, (base, core, sparkle, ribbons, ov) in VISUALS.items():
        clone_visual(base, name, core, sparkle, ribbons, ov)
    for eid, spec in ELEMENT_SPECS.items():
        write_element(eid, spec)
    for r in RECIPES:
        write_recipe(r)
    print(f"{len(VISUALS)} aspectos, {len(ELEMENT_SPECS)} elementos y {len(RECIPES)} recetas escritos en {ROOT / 'data'}")


if __name__ == "__main__":
    main()
