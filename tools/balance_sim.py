#!/usr/bin/env python3
"""Simulador de balance: juega una partida entera con un jugador eficiente y mide el ritmo.

Uso:
    python3 tools/balance_sim.py              # informe en texto
    python3 tools/balance_sim.py --csv out.csv  # además, la línea de tiempo en CSV
    python3 tools/balance_sim.py --log        # lista todas las compras

Lee los datos reales del juego (game/data/**.tres) y reproduce las reglas del código:
- Daño de los hechizos (`SpellCaster`): niveles de cada elemento (con `ElementDef.ensure_levels`), tamaño
  (`_sized_damage`), combinaciones (`SpellRecipe.damage_for` x potencia), resonancia (x3, sube un tamaño de
  fragmento y dobla la cuenta), Canalización (enfriamiento).
- Fragmentos (`MotherCrystal.receive_hit` + `ShardPool.pieces_for`): cuántos caen y de qué tipo; el maná es
  la suma de sus valores con la Pureza redondeada en cada pieza (`GameState.shard_value`); el Pilón suma el
  valor sin Pureza. La esencia que se quita es el daño del golpe (más el túnel de las lanzas).
- Lo que hace cada golpe en el cristal: saltos del Rayo y de las combinaciones, túnel de las lanzas, haz
  de Plasma, pulso de la Resonancia, ecos (con los efectos de la receta base), zona helada de la Escarcha
  (x2, Explosión de Vapor), Temple (Escarcha sobre quemadura), zona quebradiza del Choque Térmico (x3) y
  venas (x2 y Resonantes con tope por golpe). Ataques "frost+X" (una mano de cada) y "A->X" (preparar
  con A y lanzar X encima).
- Logística: recoger (Telequinesis en paralelo, Gravedad), bolsa, viaje a la trituradora, echar y triturar
  (Engranajes), Envío directo, viajes al Santuario para comprar.
- Capas: el Corazón (80-99 %) sólo cede a combinaciones; el Núcleo (último 1 %) es el final.
- Lágrimas del Núcleo (`TearDrops`, `CoreTears`): en el Corazón, los combinados sueltan una con
  probabilidad daño / tear_essence (x1,5 con el Ojo del Núcleo) y la piedad da una cada
  tear_pity_sec de juego como mucho; pagan los nodos del Núcleo (Fractura del Corazón: x daño de los
  combinados en el Corazón; Corazón Vidente: + golpes resonantes en el Corazón) y la Gran
  Convergencia, que se ve al 99 %: el informe dice si al llegar al Núcleo hay Lágrimas para ella.
- Nodos hito (GDD 7): Lanzamiento continuo (`AutoCast`: la ráfaga al mantener quita el tope de clics
  por segundo que un jugador aguanta a mano, `max_rate`; no lanza más deprisa que la recarga),
  Vórtice (`ManaVortex`: recoge solo hasta su ritmo, como la Telequinesis pero de todo el claro) y
  Rompefacetas (`FacetBreaker`: en un golpe resonante principal del mago, el cráter se queda con el
  daño de base y la losa se lleva lo que pone la resonancia más `facet_mult` veces la base, con
  fragmentos por su valor; en el Corazón, sólo combinados y por `facet_heart_scale`; los ecos, los ticks
  del haz y los golpes secundarios no rompen). Para la economía sólo cuenta ese extra.
- Báculo y triples (`StaffCombos`): el Báculo pide la Tierra y el Pilón al 10 %; una triple suma el
  daño de sus tres elementos, la Potencia del báculo (staff_mult) y su carga se acorta con el Foco
  (staff_focus). La Tormenta Elemental reparte su daño en descargas (rayo, granizo de 3 y fuego, cada
  una con sus saltos) durante `storm_sec` y, como sólo puede haber una, se juega en rotación: la
  tormenta y, mientras descarga, el mejor otro ataque (como la Resonancia Arcana).

- Runas (`RuneBook`, `RuneCaster`, data/runes/): se compran con maná desde el 10 % del Pilón y sólo
  cuentan inscritas (una ranura al abrir la mesa y dos más que se compran desde el 25 %); el jugador
  inscribe en cada momento las que más maná por segundo le dan. Multidisparo (chispas de más, sin
  resonancia), Rebote (golpes en cadena con daño x fracción), Perforación (túnel: esencia y
  fragmentos de una fracción del golpe), Eco (copia fantasma con su resonancia, con probabilidad) en
  los sueltos y, a `combo_scale`, en los combinados que salen de las manos (FRONT y LANCE, sin las
  triples); Cosecha: menos daño en todo lo que lanza el mago y más maná por fragmento (como la Pureza).

El jugador simulado elige siempre el ataque que más maná por segundo le da y compra la mejora con mejor
relación ganancia / coste (las de movimiento, cuando son baratas). No es un jugador real: es una cota
optimista. Las reglas de ritmo del GDD (sección 8) se comprueban al final:
- la primera mejora en < 30 s;
- algo comprable cada < 60 s durante la primera hora;
- nunca más de 3 minutos sin una mejora;
- partida completa en 2-3 horas.
"""
import argparse
import csv
import itertools
import json
import math
import re
from dataclasses import dataclass, field
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent / "game"
DATA = ROOT / "data"

# --- Logística (metros, segundos): ver core/world_layout.gd, player.gd y crystal_crusher.gd ---
# Dos jugadores: "eficiente" (cota optimista) y "normal" (mira, falla, pasea, lee el Grimorio).
# `max_rate`: clics por segundo y mano que aguanta a mano durante la partida (el normal, unos 2,5:
# cinco clics por segundo entre las dos manos durante horas); el Lanzamiento continuo lo quita.
PROFILES = {
    "eficiente": dict(speed=8.0, buy=3.0, pick=0.8, accuracy=0.9, max_rate=6.0, charge=1.0, focus=1.0),
    "normal": dict(speed=7.0, buy=6.0, pick=1.0, accuracy=0.8, max_rate=2.5, charge=0.9, focus=0.85),
}
P = dict(PROFILES["eficiente"])
# core/world_layout.gd: Pilón en (-46, 0, 52) y la trituradora 2,8 m a su derecha (mana_pylon.gd), con
# 3,8 m de radio de uso (crystal_crusher.gd). Desde la cara de delante del cristal (lado de la casucha,
# a unos 40 m del centro, la misma de SANCTUM_EXTRA) hay unos 41 m andando y unos 45 m de vuelo.
CRUSHER_DIST = 41.0  # del cristal a la trituradora
FAMILIAR_DIST = 45.0  # de la tolva a donde caen los fragmentos
FAMILIAR_MAX_CARRY = 6  # familiar.gd MAX_CARRY
SANCTUM_EXTRA = 94.0  # trituradora -> Santuario -> cristal, lo que se añade al viaje
FEED_START, FEED_MIN, FEED_RAMP = 0.4, 0.09, 2.4
LEVER_SEC = 1.0
NEW_SHARDS = True  # regla nueva: el maná de un golpe es más o menos su daño (ver hit_yield)
MAX_PIECES, MAX_EXTRA = 10, 3  # ShardPool
# Parte de la esencia de los combinados que llega por golpes que pasan por receive_hit (los que
# pueden soltar Lágrimas; el resto son saltos, túneles y pulsos).
TEAR_MAIN_FRACTION = 0.75
VEIN_FOCUS = 0.6  # parte de los golpes que el jugador da en la vena de su elemento (capa de venas)
VEIN_BONUS = None  # CrystalLayerDef.vein_bonus; None = el de data/crystal/layer_resonant_veins.tres
DIRECT_SEND_LEVER_EVERY = 90.0  # con Envío directo, se va a tirar de la palanca cada tanto
MOVEMENT_UPGRADES = {"double_jump", "levitation", "crystal_impulse"}
MILESTONE_STATS = {"autocast", "vortex_radius", "facet_mult"}  # Lanzamiento continuo, Vórtice, Rompefacetas
# Constantes del código del juego (no son datos de diseño), copiadas tal cual:
CHAIN_FRACTION = 0.2  # crystal_combos.gd chain: cada salto arranca maxf(1, daño x 0,2), sin bonus
PIERCE_EXTRA, PIERCE_PIECES = 0.9, 2  # crystal_combos.gd pierce: túnel de 0,9 x daño y 2 Fragmentos
PULSE_HITS, PULSE_FRACTION = 12, 0.1  # crystal_combos.gd resonance_pulse
BEAM_TICK = 0.09  # spell_caster.gd; se comprueba por fotograma (60 fps): un golpe cada 0,1 s
FRAME = 1.0 / 60.0
STEAM_MULT, STEAM_PIECES, STEAM_CLOSE = 1.5, 4, 0.3  # crystal_combos.gd steam; la zona se cierra en 0,3 s
TEMPER_MULT, TEMPER_PIECES = 1.8, 3  # crystal_combos.gd check_temper: 3 fragmentos grandes
BURN_HOT_SEC = 3.0  # mother_crystal.gd hot_burn_near: quemadura "al rojo"
TK_INTERVAL = 0.14  # player.gd telekinesis_interval_sec: un fragmento cada 0,14 s, sin dejar de lanzar
TK_FULL_REACH = 12.0  # radio con el que la Telequinesis alcanza todo lo que cae (el del último nivel)
POOL_SIZE, GRAVITY_BATCH = 128, 100  # shard_pool.gd pool_size; fragmentos que se juntan para la Gravedad
# SpellRecipe.Delivery
FRONT, SKY, RAIN, LANCE, BEAM, GROUND, MAGNET, GRAVITY, RESONANCE, STORM, NOVA = range(11)
HAIL_PER_VOLLEY = 2  # elemental_storm.gd: bolas de granizo de cada ráfaga
STORM_PARTNERS = 8  # combinaciones que se prueban junto a la Tormenta
STAFF_UPGRADE = "staff"  # StaffCombos.UNLOCK_UPGRADE
# StaffCombos.ENABLED: el báculo (y sus triples y mejoras) puede estar apagado.
STAFF_ENABLED = "const ENABLED: bool = true" in (ROOT / "spells" / "staff_combos.gd").read_text()
ZERO = (0.0, 0.0, 0.0, 0.0)
# RuneDef.Kind
MULTISHOT, BOUNCE, PIERCE, ECHO, HARVEST = range(5)
RUNE_MIN_SIZE = 0.65  # rune_caster.gd MIN_SIZE
RUNE_CURIOSITY = 0.05  # ganas de probar una runa nueva o de tener otra ranura (ver score)


def yadd(a, b, k: float = 1.0):
    """Suma de rendimientos (esencia, maná, fragmentos, valor sin Pureza): a + k x b."""
    return (a[0] + k * b[0], a[1] + k * b[1], a[2] + k * b[2], a[3] + k * b[3])


# --------------------------------------------------------------------------------------------
# Lectura de .tres
# --------------------------------------------------------------------------------------------
VAL_RE = re.compile(r"^(\w+) = (.+)$", re.M)


def parse_value(raw: str):
    raw = raw.strip()
    m = re.match(r"Packed(?:Int32|Float32)Array\((.*)\)$", raw)
    if m:
        return [float(x) for x in m.group(1).split(",") if x.strip()]
    m = re.match(r"Array\[[^\]]*\]\(\[(.*)\]\)$", raw)
    if m and "SubResource" in m.group(1):
        return re.findall(r'SubResource\("([^"]+)"\)', m.group(1))
    if m:
        return re.findall(r'&"([^"]*)"', m.group(1))
    m = re.match(r'^&?"(.*)"$', raw)
    if m:
        return m.group(1)
    m = re.match(r'SubResource\("([^"]+)"\)$', raw)
    if m:
        return ("sub", m.group(1))
    m = re.match(r"\[(.*)\]$", raw)
    if m:
        return re.findall(r'SubResource\("([^"]+)"\)', m.group(1))
    try:
        return float(raw) if "." in raw or "e" in raw else int(raw)
    except ValueError:
        return raw


def parse_tres(path: Path) -> tuple[dict, dict]:
    text = path.read_text(encoding="utf-8")
    subs: dict[str, dict] = {}
    main: dict = {}
    for block in re.split(r"\n(?=\[)", text):
        head = block.split("\n", 1)[0]
        body = block.split("\n", 1)[1] if "\n" in block else ""
        fields = {k: parse_value(v) for k, v in VAL_RE.findall(body)}
        m = re.match(r'\[sub_resource type="Resource" id="([^"]+)"\]', head)
        if m:
            subs[m.group(1)] = fields
        elif head.startswith("[resource]"):
            main = fields
    return main, subs


@dataclass
class Tier:
    damage: int = 1
    cooldown: float = 1.5
    shards_min: int = 1
    shards_max: int = 1
    echoes: int = 0  # Arcano: ecos fantasma que repiten el golpe


def tier_from(d: dict) -> Tier:
    return Tier(
        int(d.get("damage", 1)),
        float(d.get("cooldown_sec", 1.5)),
        int(d.get("shards_min", 1)),
        int(d.get("shards_max", 1)),
        int(d.get("echoes", 0)),
    )


def gd_round(x: float) -> int:
    """roundi de Godot (la mitad se aleja del cero), no el redondeo bancario de Python."""
    return int(math.floor(x + 0.5)) if x >= 0 else -int(math.floor(-x + 0.5))


MAX_LEVEL, APEX_LEVEL = 11, 11  # ElementDef.MAX_LEVEL y APEX_LEVEL


def ensure_levels(
    tiers: list[Tier],
    max_level: int = MAX_LEVEL,
    growth: float = 1.38,
    cd_growth: float = 0.92,
    late: float = 1.0,
    apex: float = 1.0,
) -> list[Tier]:
    """Copia de ElementDef.ensure_levels (los niveles que faltan hasta el 11): los niveles 9 y 10
    crecen además x`late` y el 11 (Ascensión) x`apex`."""
    while len(tiers) < max_level and tiers:
        prev = tiers[-1]
        n = len(tiers)
        level = n + 1
        g = growth * (late if 9 <= level < APEX_LEVEL else apex if level == APEX_LEVEL else 1.0)
        echoes = prev.echoes + (1 if prev.echoes > 0 and level in (6, 9, APEX_LEVEL) else 0)
        tiers.append(
            Tier(
                max(prev.damage + 1, gd_round(prev.damage * g)),
                max(0.1, prev.cooldown * cd_growth),
                prev.shards_min + (1 if n % 2 == 0 else 0),
                prev.shards_max + 1,
                echoes,
            )
        )
    return tiers


@dataclass
class Element:
    id: str
    tiers: list[Tier]
    power_stat: str
    size_stat: str
    unlock: str
    shard_bonus: int = 0
    echo_damage: float = 0.0
    chain_count: int = 0  # Rayo: saltos de cada golpe suelto (mother_crystal.gd receive_hit)
    weaken_mult: float = 1.0  # Escarcha: zona helada (mother_crystal.gd _apply_element)
    weaken_sec: float = 0.0


@dataclass
class Recipe:
    id: str
    elements: list[str]
    mult: float
    cooldown: float
    charge: float
    tier: Tier
    power_stat: str
    size_stat: str
    area_hits: int
    rain: int
    chain: int
    shard_bonus: int
    echo_count: int = 0
    echo_damage: float = 0.0
    echo_of: str = ""
    # Lo que hace en el cristal (en un Eco de X, lo de X: spell_caster.gd hit.recipe = effect).
    effect_el: str = ""  # elements[0]: el elemento del golpe (hit.element)
    delivery: int = FRONT
    pierce: float = 0.0
    beam_sec: float = 0.0
    shatter_mult: float = 1.0
    shatter_sec: float = 0.0
    buff_sec: float = 0.0
    buff_lockout: float = 0.0
    storm_sec: float = 0.0  # Tormenta Elemental: segundos de descargas y cada cuánto
    storm_interval: float = 0.5
    # Carga (SpellRecipe): potencia sin cargar, premio de la carga completa (ChargeStages.bonus) y
    # la Potencia que da su nivel (vacía: la media de los niveles de las manos).
    min_power: float = 0.5
    payoff: float = 1.0
    power_upgrade: str = ""


@dataclass
class Upgrade:
    id: str
    costs: list[int]
    values: list[float]
    stat: str
    prereq: list[str]
    currency: int = 0  # UpgradeNode.Currency: 0 maná, 1 Lágrimas del Núcleo
    reveal: float = 0.0  # UpgradeNode.reveal_destroyed_ratio
    apex: float = 0.0  # UpgradeNode.apex_destroyed_ratio: el último nivel espera al cristal así de destruido
    # Runas (RuneDef): tipo (-1 = no es runa), daño por nivel y peso en los combinados.
    rune: int = -1
    rune_damage: list = field(default_factory=list)
    combo_scale: float = 0.0


@dataclass
class ShardT:
    id: str
    min_damage: int
    value: int


def load():
    elements: dict[str, Element] = {}
    for p in sorted((DATA / "elements").glob("*.tres")):
        main, subs = parse_tres(p)
        order = main.get("tiers", [])
        tiers = ensure_levels(
            [tier_from(subs[i]) for i in order],
            growth=float(main.get("damage_growth", 1.38)),
            cd_growth=float(main.get("cooldown_growth", 0.92)),
            late=float(main.get("late_growth", 1.0)),
            apex=float(main.get("apex_damage_mult", 1.0)),
        )
        elements[main["id"]] = Element(
            main["id"],
            tiers,
            main.get("power_stat", ""),
            main.get("size_stat", ""),
            main.get("unlock_upgrade", ""),
            int(main.get("shard_bonus", 0)),
            float(main.get("echo_damage", 0.0)),
            int(main.get("chain_count", 0)),
            float(main.get("weaken_mult", 1.0)),
            float(main.get("weaken_sec", 0.0)),
        )
    recipes: dict[str, Recipe] = {}
    for p in sorted((DATA / "spells").glob("recipe_*.tres")):
        main, subs = parse_tres(p)
        if main.get("is_reaction", "false") == "true" or not main.get("elements"):
            continue
        if len(main["elements"]) >= 3 and not STAFF_ENABLED:
            continue  # sin báculo no hay triples
        t = main.get("tier")
        tier = tier_from(subs[t[1]]) if isinstance(t, tuple) and t[1] in subs else Tier()
        recipes[main["id"]] = Recipe(
            main["id"],
            main["elements"],
            float(main.get("damage_multiplier", 2.5)),
            float(main.get("cooldown_sec", 2.0)),
            float(main.get("charge_sec", 0.7)),
            tier,
            main.get("power_stat", ""),
            main.get("size_stat", ""),
            int(main.get("area_hits", 0)) if float(main.get("area_radius", 0.0)) > 0 else 0,
            int(main.get("rain_count", 0)),
            int(main.get("chain_count", 0)),
            int(main.get("shard_bonus", 0)),
            int(main.get("echo_count", 0)) if main.get("echo_of") else 0,
            float(main.get("echo_damage", 0.0)),
            main.get("echo_of", ""),
            # spell_caster.gd: hit.element = elements[0], salvo la lluvia, cuyos golpes son de
            # `strike_element` (spell_delivery.gd _deliver_rain; vacío = Escarcha, las estalactitas).
            (main.get("strike_element") or "frost")
            if int(main.get("delivery", FRONT)) == RAIN
            else main["elements"][0],
            int(main.get("delivery", FRONT)),
            float(main.get("pierce_depth", 0.0)),
            float(main.get("beam_sec", 0.0)),
            float(main.get("shatter_mult", 1.0)),
            float(main.get("shatter_sec", 0.0)),
            float(main.get("buff_sec", 0.0)),
            float(main.get("buff_lockout_sec", 0.0)),
            float(main.get("storm_sec", 0.0)),
            float(main.get("storm_interval", 0.5)),
            float(main.get("min_power", 0.5)),
            float(main.get("charge_payoff", 1.0)),
            main.get("power_upgrade", ""),
        )
    # Eco de X (spell_caster.gd _launch_combine, spell_echoes.gd echo_recipe): el daño sale de la
    # receta del eco, la potencia y el tamaño también salvo que no los tenga (entonces los de X), y
    # en el cristal cada golpe (el principal y los ecos) hace lo que hace X (hit.recipe = X).
    for r in recipes.values():
        base = recipes.get(r.echo_of)
        if base is None:
            continue
        r.power_stat = r.power_stat or base.power_stat
        r.size_stat = r.size_stat or base.size_stat
        r.area_hits, r.rain, r.chain, r.shard_bonus = base.area_hits, base.rain, base.chain, base.shard_bonus
        r.effect_el, r.delivery, r.pierce, r.beam_sec = (
            base.effect_el,
            base.delivery,
            base.pierce,
            base.beam_sec,
        )
        r.shatter_mult, r.shatter_sec = base.shatter_mult, base.shatter_sec
    upgrades: dict[str, Upgrade] = {}
    for p in sorted((DATA / "upgrades").glob("*.tres")):
        main, _ = parse_tres(p)
        if main["id"].startswith(STAFF_UPGRADE) and not STAFF_ENABLED:
            continue  # el Báculo está apagado (StaffCombos.ENABLED)
        upgrades[main["id"]] = Upgrade(
            main["id"],
            [int(c) for c in main.get("costs", [])],
            main.get("values", []),
            main.get("stat", ""),
            main.get("prerequisites", []),
            int(main.get("currency", 0)),
            float(main.get("reveal_destroyed_ratio", 0.0)),
            float(main.get("apex_destroyed_ratio", 0.0)),
        )
    for p in sorted((DATA / "runes").glob("*.tres")) if (DATA / "runes").exists() else []:
        main, _ = parse_tres(p)
        u = Upgrade(
            main["id"],
            [int(c) for c in main.get("costs", [])],
            main.get("values", []),
            main.get("stat", ""),
            main.get("prerequisites", []),
        )
        if "kind" in main or "damage_values" in main:
            u.rune = int(main.get("kind", 0))
            u.rune_damage = main.get("damage_values", [])
            u.combo_scale = float(main.get("combo_scale", 0.5))
        upgrades[main["id"]] = u
    shards = []
    resonant = None
    for p in (DATA / "shards").glob("*.tres"):
        main, _ = parse_tres(p)
        st = ShardT(main["id"], int(main.get("min_damage", 0)), int(main.get("value", 1)))
        if st.id == "core_tear":
            continue  # la Lágrima del Núcleo no sale por daño (ver tear_rate)
        # ShardPool.TYPES (la escalera por daño) no lleva el Fragmento Resonante de las venas.
        if st.id == "resonant":
            resonant = st
        else:
            shards.append(st)
    shards.sort(key=lambda s: s.min_damage)
    balance, _ = parse_tres(DATA / "balance" / "default_balance.tres")
    balance["_resonant_value"] = resonant.value if resonant else 125
    balance["_veins"], _ = parse_tres(DATA / "crystal" / "layer_resonant_veins.tres")
    balance["_familiars"] = {}
    for p in sorted((DATA / "familiars").glob("*.tres")) if (DATA / "familiars").exists() else []:
        main, _ = parse_tres(p)
        balance["_familiars"][main["id"]] = main
    if TUNING is not None:
        apply_tuning(TUNING, elements, recipes, upgrades, balance)
    return elements, recipes, upgrades, shards, balance


# Minuto en que el GDD 8 pone cada rango (inicio de su franja; Leyenda, al final).
GDD_RANK_MIN = {"apprentice": 0, "initiate": 5, "sorcerer": 20, "magus": 50, "archmage": 90, "legend": None}


def load_ranks() -> list[dict]:
    """Rangos del mago (data/ranks/rank_*.tres, RankDef), en orden."""
    ranks = []
    for p in sorted((DATA / "ranks").glob("rank_*.tres")):
        main, _ = parse_tres(p)
        ranks.append(main)
    return ranks


def rank_meets(r: dict, s: "State", total: float) -> bool:
    """WizardRanks.meets (core/wizard_ranks.gd)."""
    if r.get("or_finished") == "true" and s.essence <= 0:
        return True
    if 1 - s.essence / total < float(r.get("min_destroyed", 0.0)):
        return False
    pylon = s.pylon / total
    if pylon >= float(r.get("pylon_alone", 2.0)):
        return True
    key = r.get("key_upgrade", "")
    return (not key or s.levels.get(key, 0) > 0) and pylon >= float(r.get("key_pylon", 0.0))


def check_rank(game, s: "State") -> None:
    """GameState.check_rank: sube por orden mientras se cumpla el siguiente."""
    while s.rank + 1 < len(game.ranks) and rank_meets(game.ranks[s.rank + 1], s, game.total):
        s.rank += 1
        s.ranks.append((s.t / 60, game.ranks[s.rank]["id"]))


TUNING = None  # módulo con una propuesta de números (--tuning), para probar antes de tocar los .tres


def apply_tuning(t, elements, recipes, upgrades, balance) -> None:
    """Sobrescribe en memoria los datos con los de la propuesta (módulo Python con estos nombres,
    todos opcionales):
    - ELEMENTS = {"spark": {"tiers": [(daño, enfriamiento), ...], "growth": 1.38, "cd_growth": 0.92}}
      (los niveles escritos a mano, como en el .tres; el resto los completa ensure_levels).
    - RECIPES = {"fireball": {"mult": 2.7, "cooldown": 2.0, "charge": 0.7}}
    - UPGRADES = {"bag": {"costs": [...], "values": [...]}} (un id nuevo necesita "stat").
    - BALANCE = {"pylon_bolt_damage_max": 600, ...}  (BalanceConfig)
    - FAMILIARS = {"collector": {"carry": 3}, "caster": {"damage_mult": 0.6}}  (FamiliarDef)
    - CONSTANTS = {"VEIN_BONUS": 0.5}  (constantes de este simulador que copian datos del juego;
      VEIN_BONUS = None usa el de layer_resonant_veins.tres)
    """
    for eid, spec in getattr(t, "ELEMENTS", {}).items():
        el = elements[eid]
        old = list(el.tiers)
        base = []
        for i, row in enumerate(spec["tiers"]):
            ref = old[min(i, len(old) - 1)]
            if len(row) == 2:
                base.append(Tier(int(row[0]), float(row[1]), ref.shards_min, ref.shards_max, ref.echoes))
            else:
                base.append(Tier(*row, ref.echoes) if len(row) == 4 else Tier(*row))
        el.tiers = ensure_levels(
            base, growth=spec.get("growth", 1.38), cd_growth=spec.get("cd_growth", 0.92)
        )
    for rid, spec in getattr(t, "RECIPES", {}).items():
        for k, v in spec.items():
            setattr(recipes[rid], k, v)
    for uid, spec in getattr(t, "UPGRADES", {}).items():
        u = upgrades.get(uid)
        if u is None:
            u = upgrades[uid] = Upgrade(uid, [], [], spec["stat"], spec.get("prereq", []))
        for k, v in spec.items():
            setattr(u, k, v)
    balance.update(getattr(t, "BALANCE", {}))
    for fid, spec in getattr(t, "FAMILIARS", {}).items():
        balance.setdefault("_familiars", {}).setdefault(fid, {}).update(spec)
    for k, v in getattr(t, "CONSTANTS", {}).items():
        globals()[k] = v


# --------------------------------------------------------------------------------------------
# Reglas del juego
# --------------------------------------------------------------------------------------------
@dataclass
class State:
    levels: dict[str, int] = field(default_factory=dict)
    mana: float = 0.0
    essence: float = 1_000_000.0
    pylon: float = 0.0
    t: float = 0.0
    tears: float = 0.0
    tears_total: float = 0.0
    rank: int = 0
    # (minuto, nombre) de cada subida de rango (ver check_rank).
    ranks: list = field(default_factory=list)
    # Runas inscritas (ids), las que elige el jugador (Game.pick_runes).
    runes: tuple = ()
    mana_earned: float = 0.0


class Game:
    def __init__(self) -> None:
        self.elements, self.recipes, self.upgrades, self.shards, self.balance = load()
        self.ranks = load_ranks()
        self.total = float(self.balance.get("total_essence", 1_000_000))
        self.res_mult = int(self.balance.get("resonant_damage_mult", 3))
        self.familiars = self.balance.get("_familiars", {})
        self.resonant_value = float(self.balance.get("_resonant_value", 125))
        self.chunk = next(st for st in self.shards if st.id == "chunk")
        veins = self.balance.get("_veins", {})
        self.vein_mult = float(veins.get("vein_damage_mult", 2.0))
        self.vein_shards = int(veins.get("vein_shards", 8))
        self.vein_bonus = float(VEIN_BONUS if VEIN_BONUS is not None else veins.get("vein_bonus", 0.5))
        # Contexto del estado que se está midiendo (ver _begin) y caché de attacks().
        self._purity = 1.0
        self._veins = False
        self._heart = False
        self._cache: dict = {}

    # -- estadísticas --
    def stat(self, s: State, stat: str, fallback: float) -> float:
        for u in self.upgrades.values():
            if u.stat == stat:
                lv = s.levels.get(u.id, 0)
                return u.values[min(lv, len(u.values) - 1)] if u.values else fallback
        return fallback

    # -- runas (core/rune_book.gd, spells/runes/rune_caster.gd) --
    def rune(self, s: State, kind: int):
        """(nivel, Upgrade) de la runa de ese tipo si está inscrita; (0, None) si no."""
        for uid in s.runes:
            u = self.upgrades[uid]
            if u.rune == kind:
                return s.levels.get(uid, 0), u
        return 0, None

    @staticmethod
    def rune_value(u: Upgrade, lv: int) -> float:
        return u.values[min(lv, len(u.values) - 1)] if u.values else 0.0

    @staticmethod
    def rune_dmg(u: Upgrade, lv: int) -> float:
        return u.rune_damage[min(lv, len(u.rune_damage) - 1)] if u.rune_damage else 0.0

    def rune_slots(self, s: State) -> int:
        """RuneBook.slot_count: 0 con la mesa sellada; si no, lo que den las ranuras compradas."""
        if s.pylon / self.total + 1e-6 < float(self.balance.get("rune_table_pylon", 0.1)):
            return 0
        return int(round(self.stat(s, "rune_slots", 1.0)))

    def pick_runes(self, s: State) -> None:
        """Inscribe las runas aprendidas que más maná por segundo dan (todas las combinaciones)."""
        owned = [u.id for u in self.upgrades.values() if u.rune >= 0 and s.levels.get(u.id, 0) > 0]
        n = min(self.rune_slots(s), len(owned))
        if n <= 0:
            s.runes = ()
            return
        best, best_rate = s.runes, -1.0
        for combo in itertools.combinations(sorted(owned), n):
            s.runes = combo
            rate = self.effective(s)[0]
            if rate > best_rate + 1e-9:
                best, best_rate = combo, rate
        s.runes = best

    def harvest(self, s: State) -> tuple[float, float]:
        """Cosecha inscrita: (x daño de los hechizos del mago, x maná de cada fragmento)."""
        lv, u = self.rune(s, HARVEST)
        if not lv:
            return 1.0, 1.0
        return self.rune_dmg(u, lv), self.rune_value(u, lv)

    def harvested(self, s: State, dmg: int) -> int:
        """RuneCaster.harvested."""
        mult = self.harvest(s)[0]
        return dmg if dmg <= 0 or mult >= 1.0 else max(1, gd_round(dmg * mult))

    def rune_extras(self, s: State, dmg: int, size: float, res_p: float, mult: float, combo,
                    sub_tier, sub_el: Element, main_hits):
        """Lo que suman las runas inscritas a un lanzamiento (RuneCaster.on_launch y _on_impacted):
        `dmg` es el daño sin resonancia, `main_hits` la lista (probabilidad, daño con resonancia) del
        golpe que llega, `combo` la receta (o None en un suelto) y `sub_tier` / `sub_el` lo que sale
        de más (la llama de la mano). Devuelve (rendimiento medio, (receta, daño, probabilidad) del eco
        de un combinado o (None, 0, 0))."""
        def scale_of(u):
            return 1.0 if combo is None else u.combo_scale
        out = ZERO
        chain = sub_el.chain_count
        lv, u = self.rune(s, MULTISHOT)
        if lv:
            de = max(1, gd_round(dmg * self.rune_dmg(u, lv) * scale_of(u)))
            n = int(round(self.rune_value(u, lv)))
            y = self._receive(de, sub_tier, max(RUNE_MIN_SIZE, size * 0.72), sub_el.shard_bonus, chain=chain)
            out = yadd(out, y, n)
        lv, u = self.rune(s, BOUNCE)
        if lv and not (combo is not None and self._heart):
            frac = self.rune_dmg(u, lv) * scale_of(u)
            n = int(round(self.rune_value(u, lv)))
            for p, hd in main_hits:
                d, sz = float(hd), size
                for _ in range(n):
                    d = max(1, gd_round(d * frac))
                    sz = max(RUNE_MIN_SIZE, sz * 0.82)
                    out = yadd(out, self._receive(d, sub_tier, sz, sub_el.shard_bonus, chain=chain), p)
        lv, u = self.rune(s, PIERCE)
        if lv:
            frac = self.rune_dmg(u, lv) * scale_of(u)
            for p, hd in main_hits:
                # Túnel: esencia y fragmentos por su valor, sin bonus ni venas (spawn_worth).
                out = yadd(out, self._dig(hd * frac, sub_tier, size, 0), p)
        echo = (None, 0, 0.0)
        lv, u = self.rune(s, ECHO)
        if lv:
            chance = min(1.0, self.rune_value(u, lv) / 100.0 * scale_of(u))
            de = max(1, gd_round(dmg * self.rune_dmg(u, lv)))
            if combo is None:
                for res, p in ((False, 1.0 - res_p), (True, res_p)):
                    hd = de * (self.res_mult if res else 1)
                    y = self._receive(hd, sub_tier, size, sub_el.shard_bonus, mult, chain=chain)
                    out = yadd(out, y, p * chance)
            else:
                echo = (combo, de, chance)
        return out, echo

    def awake(self, s: State, el: Element) -> bool:
        return not el.unlock or s.levels.get(el.unlock, 0) > 0

    def tier(self, s: State, el: Element) -> Tier:
        return el.tiers[self.level_of(s, el) - 1]

    def level_of(self, s: State, el: Element) -> int:
        """Nivel (1..11) del elemento según su Potencia."""
        idx = int(round(self.stat(s, el.power_stat, 0.0)))
        return max(0, min(idx, len(el.tiers) - 1)) + 1

    def piece_for(self, per_piece: float) -> int:
        """Índice del tipo más grande cuyo valor cabe en `per_piece`."""
        idx = 0
        for i, st in enumerate(self.shards):
            if st.value <= per_piece:
                idx = i
        return idx

    def shard_type(self, damage: float, steps_up: int) -> ShardT:
        idx = 0
        for i, st in enumerate(self.shards):
            if damage >= st.min_damage:
                idx = i
        return self.shards[min(idx + steps_up, len(self.shards) - 1)]

    @staticmethod
    def sized(damage: int, size: float) -> int:
        return max(damage, round(damage * (1.0 + (size - 1.0) * 0.5)))

    def _begin(self, s: State) -> None:
        """Contexto del estado: Pureza y capa (venas, Corazón)."""
        done = 1.0 - s.essence / self.total
        self._purity = self.stat(s, "purity_mult", 1.0) * self.harvest(s)[1]
        self._veins = 0.45 <= done < 0.8
        self._heart = s.essence / self.total < 0.2

    def pv(self, st: ShardT) -> int:
        """Maná de un fragmento: GameState.shard_value redondea la Pureza pieza a pieza."""
        return max(1, gd_round(st.value * self._purity))

    def pieces(self, st: ShardT, count: float):
        """Rendimiento de `count` fragmentos de un tipo (sin esencia)."""
        return (0.0, count * self.pv(st), count, count * st.value)

    def pieces_for(self, worth: float) -> list[tuple[ShardT, int]]:
        """Copia de ShardPool.pieces_for: el tipo sale del daño (umbral `min_damage`), hasta
        MAX_PIECES piezas (si no, un tamaño más; del mayor, el doble) y MAX_EXTRA trocitos."""
        out: list[tuple[ShardT, int]] = []
        if worth < 1.0:
            return out
        idx = 0
        for i, st in enumerate(self.shards):
            if worth >= st.min_damage:
                idx = i
        while idx < len(self.shards) - 1 and math.floor(worth / self.shards[idx].value) > MAX_PIECES:
            idx += 1
        top = MAX_PIECES * (2 if idx == len(self.shards) - 1 else 1)
        c = max(1, min(int(math.floor(worth / self.shards[idx].value)), top))
        out.append((self.shards[idx], c))
        rest = worth - c * self.shards[idx].value
        extra = 0
        for j in range(idx - 1, -1, -1):
            n = 0
            while rest >= self.shards[j].value and extra < MAX_EXTRA:
                rest -= self.shards[j].value
                n += 1
                extra += 1
            if n:
                out.append((self.shards[j], n))
        return out

    def _dig(self, d: float, tier: Tier, size: float, bonus: int):
        """Un golpe que arranca `d` de esencia y suelta sus fragmentos (MotherCrystal.receive_hit)."""
        if size < 0.6:
            return yadd((d, 0.0, 0.0, 0.0), self.pieces(self.shards[0], 1))  # golpe flojo: una astilla
        if not NEW_SHARDS:
            # Regla antigua (aproximada): cuenta por nivel y tipo por daño.
            count = math.ceil((tier.shards_min + tier.shards_max) / 2.0 * (1.0 + (size - 1.0) * 0.6))
            return yadd((d, 0.0, 0.0, 0.0), self.pieces(self.shard_type(d, bonus), count))
        # Tierra y Lanza Cargada (bonus): +25 % de valor por paso.
        out = (d, 0.0, 0.0, 0.0)
        for st, c in self.pieces_for(d * (1.0 + 0.25 * bonus)):
            out = yadd(out, self.pieces(st, c))
        return out

    def _landed(self, d: float, tier: Tier, size: float, bonus: int, vein: str | None):
        """Golpe con daño final `d`; en la capa de venas, VEIN_FOCUS de ellos caen en la vena de su
        elemento (CrystalVeins.apply: x vein_damage_mult). Los golpes que pasan por receive_hit
        ("main") sueltan además Resonantes por vein_bonus del daño, como mucho vein_shards
        (CrystalVeins.react); los saltos y el pulso ("chain") sólo llevan el x2."""
        y = self._dig(d, tier, size, bonus)
        if not (self._veins and vein):
            return y
        d2 = max(1, gd_round(d * self.vein_mult))
        yv = self._dig(d2, tier, size, bonus)
        if vein == "main":
            c = min(float(self.vein_shards), d2 * self.vein_bonus / self.resonant_value)
            yv = yadd(
                yv,
                (0.0, c * max(1, gd_round(self.resonant_value * self._purity)), c, c * self.resonant_value),
            )
        return yadd(yadd(ZERO, y, 1.0 - VEIN_FOCUS), yv, VEIN_FOCUS)

    def hit_yield(
        self, damage: float, tier: Tier, size: float, bonus: int, res_p: float, vein: str | None = "main"
    ):
        """(esencia, maná, fragmentos, valor sin Pureza) medios de un golpe, con la resonancia."""
        if damage <= 0:
            return ZERO
        out = ZERO
        for res, p in ((False, 1.0 - res_p), (True, res_p)):
            if p > 0:
                out = yadd(
                    out, self._landed(damage * (self.res_mult if res else 1), tier, size, bonus, vein), p
                )
        return out

    def _receive(
        self,
        hd: float,
        tier: Tier,
        size: float,
        bonus: int,
        mult: float = 1.0,
        steam: bool = False,
        temper: bool = False,
        chain: int = 0,
        pierce: float = 0.0,
        area: int = 0,
        pulse: bool = False,
        facet: float = 0.0,
    ):
        """Un golpe que llega a MotherCrystal.receive_hit con daño `hd` (ya con la resonancia), en
        su orden: zona debilitada (`mult`, _apply_weakness) con Explosión de Vapor si es fuego
        sobre hielo, Temple, vena, y después área, perforación, saltos y pulso."""
        extra = ZERO
        if mult != 1.0:
            hd = gd_round(hd * mult)
        if steam:
            hd = gd_round(hd * STEAM_MULT)
            extra = yadd(extra, self.pieces(self.shards[1], STEAM_PIECES))
        if temper:
            # crystal_combos.gd check_temper: x1,8 y 3 Fragmentos grandes (ShardPool.CHUNK).
            hd = gd_round(hd * TEMPER_MULT)
            extra = yadd(extra, self.pieces(self.chunk, TEMPER_PIECES))
        main = self._landed(hd, tier, size, bonus, "main")
        out = yadd(main, extra)
        if facet > 0 and size >= 0.6:
            # Rompefacetas (facet_breaker.gd): la losa añade `facet` veces el daño del golpe
            # resonante (la base por facet_mult), con fragmentos por su valor (sin bonus).
            out = yadd(out, self._dig(hd * facet, tier, size, 0))
        if area and size >= 0.6:
            out = yadd(out, self.pieces(self.shards[0], area))  # _area_blast: astillas
        if pierce > 0:
            # Túnel: 0,9 x daño más de esencia, sin fragmentos, y 2 Fragmentos al final.
            out = yadd(
                out, yadd((PIERCE_EXTRA * main[0], 0.0, 0.0, 0.0), self.pieces(self.shards[1], PIERCE_PIECES))
            )
        if chain:
            out = yadd(out, self._landed(max(1.0, hd * CHAIN_FRACTION), tier, 1.0, 0, "chain"), chain)
        if pulse:
            out = yadd(out, self._landed(max(1.0, hd * PULSE_FRACTION), tier, 1.0, 0, "chain"), PULSE_HITS)
        return out

    def single_yield(
        self,
        s: State,
        el: Element,
        res_p: float,
        mult: float = 1.0,
        steam: bool = False,
        temper: bool = False,
    ):
        """Rendimiento medio de un disparo suelto (SpellCaster._cast_single), con sus ecos."""
        t = self.tier(s, el)
        size = self.stat(s, el.size_stat, 1.0) if el.size_stat else 1.0
        dmg = self.harvested(s, self.sized(t.damage, size))
        if dmg <= 0:
            return ZERO  # la chispita del tutorial no hace nada
        out = ZERO
        fm = self.facet_mult(s, False)
        for res, p in ((False, 1.0 - res_p), (True, res_p)):
            hd = dmg * (self.res_mult if res else 1)
            out = yadd(
                out,
                self._receive(
                    hd, t, size, el.shard_bonus, mult, steam, temper, el.chain_count, facet=fm if res else 0.0
                ),
                p,
            )
        if s.runes:
            hits = [(1.0 - res_p, dmg), (res_p, dmg * self.res_mult)]
            extra, _ = self.rune_extras(s, dmg, size, res_p, mult, None, t, el, hits)
            out = yadd(out, extra)
        if t.echoes and el.echo_damage > 0:
            de = max(1, gd_round(dmg * el.echo_damage))
            for res, p in ((False, 1.0 - res_p), (True, res_p)):
                hd = de * (self.res_mult if res else 1)
                out = yadd(
                    out, self._receive(hd, t, size, el.shard_bonus, mult, chain=el.chain_count), p * t.echoes
                )
        return out

    def facet_mult(self, s: State, combo: bool) -> float:
        """Rompefacetas: esencia de más de la losa, en veces el daño del golpe resonante (0 sin el
        nodo): facet_mult veces la base, que es el golpe / resonant_damage_mult. En el Corazón sólo
        con combinados y por facet_heart_scale (facet_breaker.gd prepare)."""
        m = self.stat(s, "facet_mult", 0.0) / self.res_mult
        if m <= 0 or not self._heart:
            return m
        return m * float(self.balance.get("facet_heart_scale", 0.4)) if combo else 0.0

    def recipe_level(self, s: State, r: Recipe) -> int:
        """SpellCaster.charge_level: 1 + Potencia de la receta o la media de las manos."""
        if r.power_upgrade:
            return 1 + s.levels.get(r.power_upgrade, 0)
        lv = [self.level_of(s, self.elements[x]) for x in r.elements[:2]]
        return int((lv[0] + lv[1]) * 0.5)

    def charge_bonus(self, s: State, r: Recipe) -> float:
        """ChargeStages.full_bonus: premio de soltar con la carga completa."""
        table = self.balance.get("full_charge_bonus_by_level") or [1.0]
        lv = self.recipe_level(s, r)
        full = float(table[max(1, min(lv, len(table))) - 1])
        return max(1.0, 1.0 + (full - 1.0) * max(0.0, min(1.0, r.payoff)))

    def _combo_damage(self, s: State, r: Recipe, tap: bool = False):
        """(daño sin resonancia, tamaño, enfriamiento del ciclo) de una combinación cargada (o de
        toque, `tap`: sin carga, a `min_power` y sin premio). Las triples suman el daño del
        elemento de la gema (SpellRecipe.damage_for)."""
        els = [self.elements[x] for x in r.elements]
        t0, t1 = self.tier(s, els[0]), self.tier(s, els[1])
        gem = self.tier(s, els[2]).damage if len(els) == 3 else 0
        if t0.damage <= 0 and t1.damage <= 0:
            dmg, size = 1, 0.45  # tutorial: juntar sin daño hace 1
        else:
            if tap:
                power = r.min_power
            else:
                # El jugador normal suelta algo antes (P["charge"]): pierde parte del premio.
                k = P["charge"]
                power = (r.min_power + (1.0 - r.min_power) * k) * self.charge_bonus(s, r) ** k
            dmg = max(1, round((t0.damage + t1.damage + gem) * r.mult * power))
            if r.power_stat:
                dmg = round(dmg * self.stat(s, r.power_stat, 1.0))
            size = self.stat(s, r.size_stat, 1.0) if r.size_stat else 1.0
            dmg = self.harvested(s, self.sized(dmg, size))
            if self._heart:
                # Fractura del Corazón (CoreTears.apply): x daño de los combinados en el Corazón.
                dmg = max(1, gd_round(dmg * self.stat(s, "heart_combo_mult", 1.0)))
        cdm = self.stat(s, "cooldown_mult", 1.0)
        return dmg, size, max(r.cooldown * cdm, t0.cooldown * cdm)

    def cast_yield(
        self,
        s: State,
        r: Recipe,
        res_p: float,
        zone: tuple[str, float] | None = None,
        temper: bool = False,
        tap: bool = False,
    ):
        """(rendimiento medio de un lanzamiento, ciclo en s). `zone`: zona en la que cae
        ("frost", x) o ("shatter", x); `temper`: cae sobre una quemadura al rojo; `tap`: de
        toque, sin cargar (el ciclo es sólo la recarga)."""
        dmg, size, cd = self._combo_damage(s, r, tap)
        charge = 0.0 if tap else self.charge_sec(s, r)
        if size < 0.6:
            res_p = 0.0  # las dos chispitas del tutorial nunca resuenan
        elif r.delivery == RESONANCE:
            res_p = 1.0  # spell_caster.gd: la Resonancia Arcana siempre es resonante
        # Zona helada: x2 a todo golpe que no sea de Escarcha (no se gasta); si es fuego, Explosión
        # de Vapor y la zona se cierra en 0,3 s (el haz, con un golpe cada 0,1 s, la mantiene).
        frost = zone is not None and zone[0] == "frost" and r.effect_el != "frost"
        steam = frost and r.effect_el == "spark"
        all_mult = zone[1] if frost else 1.0
        # Zona quebradiza (Choque Térmico): x3 al primer golpe, y se gasta.
        first_mult = zone[1] if zone is not None and zone[0] == "shatter" else 1.0
        kw = dict(chain=r.chain, pierce=r.pierce, area=r.area_hits, pulse=r.delivery == RESONANCE)
        fm = self.facet_mult(s, True)

        def delivered(h: float, mult_all: float, stm: bool, first: float, tmp: bool, fct: float = 0.0):
            if r.storm_sec > 0:
                # Tormenta (elemental_storm.gd): n descargas de h / n por turno de elementos; el
                # granizo, en HAIL_PER_VOLLEY bolas. Cada una con los saltos de la receta.
                n = max(1, math.floor(r.storm_sec / max(r.storm_interval, 0.05)))
                each = max(1, gd_round(h / n))
                y = ZERO
                for k in range(n):
                    first = r.elements.index("bolt") if "bolt" in r.elements else 0
                    el = r.elements[(k + first) % len(r.elements)]  # empieza por el rayo
                    # Sólo la primera descarga es resonante (elemental_storm.gd): sólo ella parte faceta.
                    f0 = fct if k == 0 else 0.0
                    if el == "frost":
                        hail = max(1, gd_round(each / HAIL_PER_VOLLEY))
                        for _ in range(HAIL_PER_VOLLEY):
                            y = yadd(y, self._receive(hail, r.tier, size, r.shard_bonus, mult_all, **kw, facet=f0))
                            f0 = 0.0
                    else:
                        y = yadd(y, self._receive(each, r.tier, size, r.shard_bonus, mult_all, **kw, facet=f0))
                return y
            if r.beam_sec > 0:
                # Haz: un golpe cada 0,1 s durante beam_sec, de daño x BEAM_TICK / beam_sec.
                tick = math.ceil(BEAM_TICK / FRAME - 1e-9) * FRAME
                parts = math.ceil(r.beam_sec / tick - 1e-9)
                each = max(1, gd_round(h * BEAM_TICK / max(r.beam_sec, 0.1)))
            elif r.rain > 0:
                parts = r.rain
                each = max(1, gd_round(h / parts))
            else:
                parts, each = 1, h
            # Los ticks del haz son golpes menores sin resonancia: no parten faceta. En la lluvia,
            # sólo la primera piedra es resonante (spell_delivery.gd).
            f1 = 0.0 if r.beam_sec > 0 else fct
            y = self._receive(each, r.tier, size, r.shard_bonus, mult_all * first, stm, tmp, **kw, facet=f1)
            if parts > 1:
                y = yadd(y, self._receive(each, r.tier, size, r.shard_bonus, mult_all, stm, **kw), parts - 1)
            return y

        out = ZERO
        for res, p in ((False, 1.0 - res_p), (True, res_p)):
            if p > 0:
                out = yadd(
                    out,
                    delivered(
                        dmg * (self.res_mult if res else 1), all_mult, steam, first_mult, temper, fm if res else 0.0
                    ),
                    p,
                )
        if r.echo_count:
            # Ecos (spell_echoes.gd): max(1, daño x echo_damage), cada uno con su resonancia. Llegan
            # 0,3 s después o más: ya no hay Vapor ni zona quebradiza, pero sí la zona helada.
            de = max(1, gd_round(dmg * r.echo_damage))
            emult = 1.0 if steam else all_mult
            for res, p in ((False, 1.0 - res_p), (True, res_p)):
                if p > 0:
                    out = yadd(
                        out,
                        delivered(de * (self.res_mult if res else 1), emult, False, 1.0, False),
                        p * r.echo_count,
                    )
        if s.runes and size >= 0.6 and r.delivery in (FRONT, LANCE) and len(r.elements) < 3:
            # Runas en los combinados que salen de las manos (lo de más sale de la llama izquierda).
            el0 = self.elements[r.elements[0]]
            hits = [(1.0 - res_p, dmg), (res_p, dmg * self.res_mult)]
            extra, (er, de, chance) = self.rune_extras(
                s, dmg, size, res_p, all_mult, r, self.tier(s, el0), el0, hits
            )
            out = yadd(out, extra)
            if er is not None:
                emult = 1.0 if steam else all_mult
                for res, p in ((False, 1.0 - res_p), (True, res_p)):
                    hd = de * (self.res_mult if res else 1)
                    out = yadd(out, delivered(hd, emult, False, 1.0, False), p * chance)
        return out, charge + cd

    def charge_sec(self, s: State, r: Recipe) -> float:
        """StaffCombos.charge_sec: el Foco del báculo acorta la carga de las triples."""
        return r.charge * (self.stat(s, "staff_focus", 1.0) if len(r.elements) == 3 else 1.0)

    def attacks(self, s: State):
        """Lista de (nombre, esencia/s, maná/s, fragmentos/s, valor/s, sólo_combinación, grupo)."""
        self._begin(s)
        key = (tuple(sorted(s.levels.items())), self._veins, self._heart, s.runes)
        if key not in self._cache:
            self._cache[key] = self._attacks(s)
        return self._cache[key]

    def _attacks(self, s: State):
        res_p = self.stat(s, "resonant_percent", float(self.balance.get("resonant_chance", 0.07)) * 100) / 100
        if self._heart:
            # Corazón Vidente (CoreTears.apply): los combinados que no resonaban, con esa probabilidad.
            seer = self.stat(s, "heart_resonant_percent", 0.0) / 100
            res_p = res_p + (1.0 - res_p) * seer
        out = self._attack_list(s, res_p)
        # Resonancia Arcana (spell_caster.gd _start_resonance): un golpe siempre resonante con pulso,
        # y buff_sec s en los que todo golpe del mago es resonante; no se puede repetir hasta
        # buff_lockout_sec s después de lanzarla. Rotación: la Resonancia y, en el resto del
        # periodo, el mejor otro ataque (resonante mientras dure el efecto).
        cdm = self.stat(s, "cooldown_mult", 1.0)
        boosted = None
        for r in self.recipes.values():
            if r.delivery != RESONANCE or r.buff_sec <= 0 or not self._recipe_awake(s, r):
                continue
            if boosted is None:
                boosted = self._attack_list(s, 1.0)
            y, _ = self.cast_yield(s, r, 1.0)
            _, _, c_r = self._combo_damage(s, r)
            period = r.charge + max(r.buff_lockout, c_r)
            t_buff = max(0.0, r.buff_sec - c_r)
            t_rest = max(r.buff_lockout, c_r) - max(r.buff_sec, c_r)
            ok = lambda a: a[5] or not self._heart  # noqa: E731 (en el Corazón, sólo combinaciones)
            b1 = max((a for a in boosted if ok(a)), key=lambda a: a[2], default=None)
            b0 = max((a for a in out if ok(a)), key=lambda a: a[2], default=None)
            tot = yadd(ZERO, y, P["accuracy"])
            if b1:
                tot = yadd(tot, b1[1:5], t_buff)
            if b0:
                tot = yadd(tot, b0[1:5], t_rest)
            tot = yadd(ZERO, tot, 1.0 / period)
            out.append((f"{r.id}[{b1[0] if b1 else '-'}]",) + tot + (True, r.id))
        # Tormenta Elemental (elemental_storm.gd): sólo una a la vez (buff_lockout_sec). Rotación:
        # cargar y soltar la tormenta y, mientras descarga sola, otra combinación. Se prueban las
        # mejores (la logística, que se aplica en rates(), decide cuál sale mejor).
        base = list(out)
        for r in self.recipes.values():
            if r.storm_sec <= 0 or not self._recipe_awake(s, r):
                continue
            y, cycle = self.cast_yield(s, r, res_p)
            period = max(r.buff_lockout, cycle)
            # Mientras descarga, las manos siguen con combinaciones (no con disparos sueltos).
            others = sorted((a for a in base if a[5]), key=lambda a: -a[2])[:STORM_PARTNERS]
            for b0 in others or [None]:
                tot = yadd(ZERO, y, P["accuracy"])
                if b0:
                    tot = yadd(tot, b0[1:5], period - cycle)
                tot = yadd(ZERO, tot, 1.0 / period)
                out.append((f"{r.id}[{b0[0] if b0 else '-'}]",) + tot + (True, r.id))
        return out

    def _recipe_awake(self, s: State, r: Recipe) -> bool:
        if len(r.elements) == 3 and s.levels.get(STAFF_UPGRADE, 0) <= 0:
            return False  # las triples piden el báculo
        return all(x in self.elements and self.awake(s, self.elements[x]) for x in r.elements)

    def _attack_list(self, s: State, res_p: float):
        cdm = self.stat(s, "cooldown_mult", 1.0)
        acc = P["accuracy"]
        heart = self._heart
        out = []

        def add(name, y, rate, combo, group):
            out.append((name, y[0] * rate, y[1] * rate, y[2] * rate, y[3] * rate, combo, group))

        # Lanzamiento continuo: manteniendo, cada mano sale al recargar (sin el tope de clics a mano).
        cap = math.inf if self.stat(s, "autocast", 0.0) > 0.5 else P["max_rate"]

        def shots(el: Element) -> float:
            return min(1.0 / (self.tier(s, el).cooldown * cdm), cap) * acc

        awake = [e for e in self.elements.values() if self.awake(s, e)]
        for el in awake:
            add(el.id, self.single_yield(s, el, res_p), 2.0 * shots(el), False, el.id)
        # Escarcha en una mano y otro elemento en la otra, a la misma mirilla (mother_crystal.gd
        # _apply_element y _apply_weakness): los golpes del otro hacen x weaken_mult en la zona
        # helada. Con Chispa, Explosión de Vapor (x1,5 y 4 Fragmentos) y cada chispa deja una
        # quemadura que la Escarcha siguiente templa (crystal_combos.gd check_temper).
        frost = self.elements.get("frost")
        frost_ok = frost is not None and self.awake(s, frost) and frost.weaken_mult > 1.0
        if frost_ok:
            wm = frost.weaken_mult
            rf = shots(frost)
            for el in awake:
                if el.id == frost.id:
                    continue
                rx = shots(el)
                if el.id == "spark":
                    lit = self.single_yield(s, el, res_p) != ZERO
                    fast = self.tier(s, el).cooldown * cdm < STEAM_CLOSE
                    steam_r = (rx if fast else min(rx, rf)) if lit else 0.0
                    temper_r = min(rx, rf) if lit else 0.0
                    y = yadd(ZERO, self.single_yield(s, el, res_p, wm, steam=True), steam_r)
                    y = yadd(y, self.single_yield(s, el, res_p), rx - steam_r)
                    y = yadd(y, self.single_yield(s, frost, res_p, temper=True), temper_r)
                    y = yadd(y, self.single_yield(s, frost, res_p), rf - temper_r)
                else:
                    y = yadd(
                        yadd(ZERO, self.single_yield(s, el, res_p, wm), rx),
                        self.single_yield(s, frost, res_p),
                        rf,
                    )
                add(f"frost+{el.id}", y, 1.0, False, el.id)
        # Combinaciones (la carga completa).
        combos = [
            r
            for r in self.recipes.values()
            if r.mult > 0
            and self._recipe_awake(s, r)
            and not (r.delivery == RESONANCE and r.buff_sec > 0)
            and r.storm_sec <= 0
        ]  # mult 0: utilidades (Gravedad, Magnetismo); la Resonancia Arcana y la Tormenta, aparte
        alone = {}
        for r in combos:
            y, cycle = self.cast_yield(s, r, res_p)
            if r.shatter_mult > 1.0 and cycle < r.shatter_sec:
                # Choque Térmico seguido en el mismo sitio: cae en la zona quebradiza del anterior.
                y, cycle = self.cast_yield(s, r, res_p, ("shatter", r.shatter_mult))
            alone[r.id] = (y, cycle)
            add(r.id, y, acc / cycle, True, r.id)
            if r.payoff < 0.5:
                # De toque (charge_payoff bajo): juntar y soltar en el acto.
                ty, tcycle = self.cast_yield(s, r, res_p, tap=True)
                if r.shatter_mult > 1.0 and tcycle < r.shatter_sec:
                    ty, tcycle = self.cast_yield(s, r, res_p, ("shatter", r.shatter_mult), tap=True)
                add(f"{r.id}(toque)", ty, acc / tcycle, True, r.id)
        spark = self.elements.get("spark")
        spark_ok = spark is not None and self.awake(s, spark) and self.single_yield(s, spark, res_p) != ZERO
        for x in combos:
            _, _, cd_x = self._combo_damage(s, x)
            if frost_ok and x.effect_el != "frost":
                # Escarcha suelta y luego la combinación X sobre la zona helada (las manos esperan
                # a que la Escarcha recargue). Si X deja quemadura, la Escarcha siguiente la templa;
                # si X es el Choque Térmico, la Escarcha cae además en su zona quebradiza.
                hot = x.effect_el == "spark" and cd_x < BURN_HOT_SEC
                fmult = x.shatter_mult if x.shatter_mult > 1.0 and cd_x < x.shatter_sec else 1.0
                if heart:
                    # La Escarcha suelta rebota en el Corazón (no hay zona), pero el Temple paga antes.
                    fy = self.pieces(self.chunk, TEMPER_PIECES) if hot else ZERO
                    xy, xc = alone[x.id]
                else:
                    fy = self.single_yield(s, frost, res_p, fmult, temper=hot)
                    xy, xc = self.cast_yield(s, x, res_p, ("frost", frost.weaken_mult))
                add(
                    f"frost->{x.id}",
                    yadd(fy, xy),
                    acc / (self.tier(s, frost).cooldown * cdm + xc),
                    True,
                    x.id,
                )
            if spark_ok and not heart and x.effect_el == "frost":
                # Chispa suelta (deja quemadura) y la combinación de Escarcha encima: Temple.
                xy, xc = self.cast_yield(s, x, res_p, temper=True)
                y = yadd(self.single_yield(s, spark, res_p), xy)
                add(f"spark->{x.id}", y, acc / (self.tier(s, spark).cooldown * cdm + xc), True, x.id)
        for ts in combos:
            if ts.shatter_mult <= 1.0:
                continue
            ty, _ = self.cast_yield(s, ts, res_p)
            _, _, cd_ts = self._combo_damage(s, ts)
            tc = ts.charge + cd_ts
            for x in combos:
                if x is ts or cd_ts + x.charge >= ts.shatter_sec:
                    continue
                # Choque Térmico y luego X en su zona quebradiza (x3 al primer golpe); su quemadura
                # templa una combinación de Escarcha que llegue antes de 3 s.
                hot = x.effect_el == "frost" and cd_ts + x.charge < BURN_HOT_SEC
                xy, xc = self.cast_yield(s, x, res_p, ("shatter", ts.shatter_mult), temper=hot)
                add(f"{ts.id}->{x.id}", yadd(ty, xy), acc / (tc + xc), True, x.id)
        return out

    def feed_time(self, n: float, gears: float) -> float:
        t, held, sent = 0.0, 0.0, 0
        while sent < n:
            k = min(1.0, held / FEED_RAMP)
            k = k * k * (3 - 2 * k)
            dt = (FEED_START + (FEED_MIN - FEED_START) * k) / gears
            t += dt
            held += dt
            sent += 1
        return t + 0.2

    def effective(self, s: State) -> tuple[float, float, float, str]:
        """(maná/s, esencia/s, Pilón/s, ataque) del mejor ataque, contando la logística."""
        rates = self.rates(s)
        return max(rates, key=lambda r: r[0])[:4] if rates else (0.0, 0.0, 0.0, "-")

    def value(self, s: State) -> float:
        """Lo que vale el arsenal para el jugador: media cuadrática de todos sus ataques (un
        jugador de verdad también mejora los hechizos que no son el mejor; el mejor pesa más).
        Cada hechizo cuenta una vez, con su mejor uso (solo o preparado con otro)."""
        best: dict[str, float] = {}
        for r in self.rates(s):
            best[r[4]] = max(best.get(r[4], 0.0), r[0])
        if not best:
            return 0.0
        return (sum(x**2 for x in best.values()) / len(best)) ** 0.5

    def familiar_rates(self, s: State) -> tuple[float, float, float, float, float]:
        """(fragmentos/s que llevan los recolectores, y esencia/s, maná/s, fragmentos/s y valor/s
        que sueltan los hechiceros) según data/familiars/ y familiar.gd."""
        collectors = int(self.stat(s, "familiar_count", 0.0))
        casters = int(self.stat(s, "familiar_caster", 0.0))
        wings = self.stat(s, "familiar_speed", 1.0)
        wing_lv = s.levels.get("familiar_wings", 0)
        carry_rate = 0.0
        if collectors:
            f = self.familiars.get("collector", {})
            # familiar.gd capacity(): carry + nivel de Alas, como mucho MAX_CARRY (6).
            carry = min(FAMILIAR_MAX_CARRY, int(f.get("carry", 3)) + wing_lv)
            speed = float(f.get("fly_speed", 7.0)) * wings
            # Ida y vuelta tolva <-> cristal (en arco, un 20 % más largo) y recoger/soltar cada uno.
            trip = 2 * FAMILIAR_DIST * 1.2 / speed
            per = carry * (float(f.get("grab_sec", 0.3)) + float(f.get("drop_gap_sec", 0.16)) + 0.5)
            carry_rate = collectors * carry / (trip + per)
        y = ZERO
        if casters:
            f = self.familiars.get("caster", {})
            spark = self.elements["spark"]
            idx = max(0, int(round(self.stat(s, spark.power_stat, 0.0))) + int(f.get("tier_offset", -1)))
            t = spark.tiers[min(idx, len(spark.tiers) - 1)]
            dmg = max(1, gd_round(t.damage * float(f.get("damage_mult", 0.6))))
            period = float(f.get("cast_interval", 3.2)) + float(f.get("cast_charge_sec", 0.9))
            res_p = self.stat(s, "resonant_percent", 7.0) / 100
            k = casters * 0.85 / period  # alguno falla
            y = yadd(ZERO, self.hit_yield(dmg, t, 1.0, 0, res_p, vein=None), k)
        return (carry_rate,) + y

    def pylon_bolt_rates(self, s: State) -> tuple[float, float, float, float]:
        """Resonancia del Pilón: un rayo cada `pylon_bolt_sec` s con daño de 25 a 600 según lo lleno
        que se vea el Pilón (raíz del progreso, ManaPylon.display_fill). Lleva el elemento Rayo
        (pylon_resonance.gd), así que salta como un Rayo suelto (chain_count)."""
        every = self.stat(s, "pylon_bolt_sec", 0.0)
        if every <= 0:
            return ZERO
        lo = float(self.balance.get("pylon_bolt_damage_min", 25))
        hi = float(self.balance.get("pylon_bolt_damage_max", 600))
        dmg = gd_round(lo + (hi - lo) * math.sqrt(s.pylon / self.total))
        bolt = self.elements["bolt"]
        y = self.hit_yield(dmg, bolt.tiers[0], 1.0, 0, 0.0, vein=None)
        if bolt.chain_count:
            y = yadd(
                y,
                self.hit_yield(max(1.0, dmg * CHAIN_FRACTION), bolt.tiers[0], 1.0, 0, 0.0, vein=None),
                bolt.chain_count,
            )
        k = 1.0 / (every + float(self.balance.get("pylon_bolt_charge_sec", 0.9)))
        return yadd(ZERO, y, k)

    def rates(self, s: State) -> list[tuple[float, float, float, str, str]]:
        """(maná/s, esencia/s, Pilón/s, ataque, grupo) de cada ataque, contando la logística."""
        attacks = self.attacks(s)  # también fija el contexto (_begin)
        heart = self._heart
        out: list[tuple[float, float, float, str, str]] = []
        cap = self.stat(s, "bag_capacity", float(self.balance.get("hand_capacity", 3)))
        tk = self.stat(s, "telekinesis_radius", 0.0)
        # Telequinesis (player.gd _update_telekinesis): atrae sola un fragmento cada 0,14 s dentro de
        # su radio mientras el mago sigue lanzando; el resto se recoge a mano.
        tk_rate = (1.0 / TK_INTERVAL) * min(1.0, tk / TK_FULL_REACH) if tk > 0 else 0.0
        if self.stat(s, "vortex_radius", 0.0) > 0:
            # Vórtice (mana_vortex.gd): atrapa uno cada vortex_interval_sec, con un tope de los que giran
            # a la vez (la espiral dura de media lo que marca vortex_spiral_*), en todo el claro.
            b = self.balance
            spiral = (float(b.get("vortex_spiral_min_sec", 1.2)) + float(b.get("vortex_spiral_max_sec", 2.8))) / 2
            tk_rate += min(1.0 / float(b.get("vortex_interval_sec", 0.05)), int(b.get("vortex_max_in_flight", 30)) / spiral)
        pick = P["pick"]
        grav = next(
            (r for r in self.recipes.values() if r.delivery == GRAVITY and self._recipe_awake(s, r)), None
        )
        if grav is not None:
            # Gravedad (shard_pool.gd gravity_pull): recoge todo el valle de una vez (hasta el pool),
            # a cambio de la carga y de las manos bloqueadas (spell_caster.gd _launch_combine).
            _, _, cd_g = self._combo_damage(s, grav)
            pick = min(pick, (grav.charge + cd_g) / min(POOL_SIZE, GRAVITY_BATCH))
        trip = CRUSHER_DIST / P["speed"]
        gears = self.stat(s, "crusher_speed", 1.0)
        direct = self.stat(s, "direct_send", 0.0) > 0.5
        carry_rate, *fam = self.familiar_rates(s)
        passive = yadd(tuple(fam), self.pylon_bolt_rates(s))
        if heart:
            # El Corazón sólo cede ante combinaciones (mother_crystal.gd _allowed_mask): los golpes
            # de los hechiceros y del rayo del Pilón no llevan receta y rebotan.
            passive = ZERO
        for name, e, m, n, v, combo, group in attacks:
            if heart and not combo:
                continue
            if n <= 0 or m <= 0:
                continue
            # Los hechiceros y el rayo del Pilón suman lo suyo mientras el mago ataca. La Pureza ya
            # va en el maná de cada fragmento (pv); el Pilón suma el valor sin ella (v).
            e, m, n, v = yadd((e, m, n, v), passive)
            # Segundos de logística del mago por cada fragmento que le toca a él.
            if direct:
                # Vuelan solos a la tolva: recogerlos y, de vez en cuando, ir a la palanca (si no
                # hay familiares que tiren de ella).
                lever = 0.0 if carry_rate > 0 else (2 * trip + LEVER_SEC) / DIRECT_SEND_LEVER_EVERY
                travel = 0.0
                fixed = lever
            else:
                travel = (2 * trip + self.feed_time(cap, gears) + LEVER_SEC) / cap
                fixed = 0.0
            # Los recolectores se llevan una parte de los fragmentos (los que caen al suelo) y la
            # Telequinesis, otra; sólo los que quedan cuestan tiempo de recogida al mago.
            mine = max(0.0, n - carry_rate)
            manual = max(0.0, mine - tk_rate)
            k = 1.0 / (1.0 + manual * pick + mine * travel + fixed)
            f = k * P["focus"]
            out.append((m * f, e * f, v * f, name, group))
        return out

    def tear_rate(self, s: State, ess_rate: float) -> float:
        """Lágrimas por segundo en el Corazón (TearDrops): azar por esencia de los golpes que pasan por
        receive_hit y piedad cada tear_pity_sec (los viajes a la trituradora, de menos de
        tear_active_gap_sec, también cuentan). Intervalo medio con piedad T: (1 - e^-λT) / λ."""
        if s.essence / self.total >= 0.2 or ess_rate <= 0:
            return 0.0
        e = float(self.balance.get("tear_essence", 12000.0))
        eye = self.stat(s, "tear_eye", 1.0)  # Ojo del Núcleo: x probabilidad (core_eye.tres)
        lam = ess_rate * TEAR_MAIN_FRACTION / e * eye
        pity = float(self.balance.get("tear_pity_sec", 100.0))
        return lam / max(1e-9, 1.0 - math.exp(-lam * pity))

    # -- mejoras --
    def available(self, s: State, u: Upgrade) -> bool:
        if s.levels.get(u.id, 0) >= len(u.costs):
            return False
        if u.reveal > 0 and 1.0 - s.essence / self.total < u.reveal - 1e-9:
            return False
        lv = s.levels.get(u.id, 0)
        if u.apex > 0 and lv == len(u.costs) - 1 and 1.0 - s.essence / self.total < u.apex - 1e-9:
            return False  # Progression.purchase_block: &"apex"
        for pr in u.prereq:
            if pr.startswith("pylon:"):
                # Progression._has_requirement: el Pilón (progreso real) hasta esa marca.
                if s.pylon / self.total + 1e-6 < float(pr[6:]):
                    return False
                continue
            if pr.startswith("recipe:"):
                r = self.recipes.get(pr[7:])
                if r is None or any(not self.awake(s, self.elements[x]) for x in r.elements):
                    return False
            elif s.levels.get(pr, 0) <= 0:
                return False
        return True

    def cost(self, s: State, u: Upgrade) -> int:
        return u.costs[s.levels.get(u.id, 0)]

    def funds(self, s: State, u: Upgrade) -> float:
        return math.floor(s.tears + 1e-9) if u.currency == 1 else s.mana

    def score(self, s: State, u: Upgrade, base: float) -> float:
        s2 = State(dict(s.levels), s.mana, s.essence, s.pylon, s.t)
        s2.runes = s.runes
        s2.levels[u.id] = s2.levels.get(u.id, 0) + 1
        if u.rune >= 0 or u.stat == "rune_slots":
            self.pick_runes(s2)  # con la runa nueva (o la ranura), las mejores inscritas
        gain = self.value(s2) / max(base, 1e-9) - 1.0
        if u.id in MOVEMENT_UPGRADES:
            gain = max(gain, 0.04)  # gusto por moverse: se compran cuando salen baratas
        # Desbloqueos (despertar un elemento): curiosidad, aunque al principio rinda poco.
        if u.stat.endswith("_awake") or u.stat == "staff_owned":
            gain = max(gain, 0.15)
        # Nodos hito (cambian la forma de jugar): también se compran por curiosidad.
        if u.stat in MILESTONE_STATS:
            gain = max(gain, 0.15)
        # Runas nuevas y ranuras: curiosidad por probar la runa (aunque la ranura esté ocupada) y
        # una ranura más en cuanto haya una runa aprendida que no cabe.
        if u.rune >= 0 and s.levels.get(u.id, 0) == 0:
            gain = max(gain, RUNE_CURIOSITY)
        if u.stat == "rune_slots" and self.owned_runes(s) > self.rune_slots(s):
            gain = max(gain, RUNE_CURIOSITY)
        return gain / self.cost(s, u)

    def owned_runes(self, s: State) -> int:
        return sum(1 for u in self.upgrades.values() if u.rune >= 0 and s.levels.get(u.id, 0) > 0)


def simulate(game: Game, verbose: bool = False, max_hours: float = 6.0):
    s = State()
    game._cache.clear()  # attacks() depende del perfil (P)
    log: list[tuple[float, str, int, int]] = []
    runes_log: list[tuple[float, tuple]] = []
    timeline: list[tuple[float, float, float, float, str]] = []
    step = 2.0
    next_sample = 0.0
    layer_ctx = None
    while s.essence > game.total * 0.01 and s.t < max_hours * 3600:
        # Al cambiar de capa (venas, Corazón) el jugador vuelve a elegir sus runas.
        done = 1.0 - s.essence / game.total
        ctx = (0.45 <= done < 0.8, done > 0.8)
        if ctx != layer_ctx:
            layer_ctx = ctx
            game.pick_runes(s)
        rate, ess_rate, pylon_rate, attack = game.effective(s)
        if rate <= 0:
            break
        # Avanza `step` segundos de juego.
        # El Pilón no pasa de la esencia total; el maná sí se sigue ganando (Progression.deliver).
        # El Pilón suma el valor de los fragmentos sin la Pureza (mana_pylon.gd receive_mana).
        gain = rate * step
        s.mana += gain
        s.mana_earned += gain
        dt_tears = game.tear_rate(s, ess_rate) * step
        s.tears += dt_tears
        s.tears_total += dt_tears
        s.pylon = min(game.total, s.pylon + pylon_rate * step)
        s.essence = max(0.0, s.essence - ess_rate * step)
        s.t += step
        check_rank(game, s)
        if s.t >= next_sample:
            timeline.append((s.t, s.mana, s.essence, s.pylon, f"{attack} {rate:.0f}/s"))
            next_sample += 30.0
        # ¿Toca ir al Santuario? (también con Lágrimas para un nodo del Núcleo)
        tear_ready = any(
            u.currency == 1 and game.available(s, u) and game.cost(s, u) <= game.funds(s, u)
            for u in game.upgrades.values()
        )
        cands = [u for u in game.upgrades.values() if u.currency == 0 and game.available(s, u)]
        if not cands and not tear_ready:
            continue
        v = game.value(s)
        scored = sorted(((game.score(s, u, v), u) for u in cands), key=lambda x: -x[0])
        target = scored[0][1] if scored else None
        if tear_ready:
            pass
        elif s.mana < game.cost(s, target):
            # Compra impulsiva: algo barato y útil mientras se ahorra.
            cheap = [u for sc, u in scored if game.cost(s, u) <= s.mana and sc >= scored[0][0] * 0.5]
            if not cheap:
                continue
            target = cheap[0]
        s.t += SANCTUM_EXTRA / P["speed"]
        bought = 0
        while True:
            # Los nodos del Núcleo se pagan con Lágrimas (no compiten con el maná): el mejor primero.
            cands = [
                u
                for u in game.upgrades.values()
                if game.available(s, u) and game.cost(s, u) <= game.funds(s, u)
            ]
            if not cands:
                break
            base = game.effective(s)[0]
            v = game.value(s)
            tear_cands = [u for u in cands if u.currency == 1]
            best = max(tear_cands or cands, key=lambda u: game.score(s, u, v))
            if bought and best.currency == 0 and game.score(s, best, v) <= 0:
                break
            c = game.cost(s, best)
            if best.currency == 1:
                s.tears -= c
            else:
                s.mana -= c
            s.levels[best.id] = s.levels.get(best.id, 0) + 1
            s.t += P["buy"]
            bought += 1
            log.append((s.t, best.id, s.levels[best.id], c, base))
            if best.rune >= 0 or best.stat == "rune_slots":
                game.pick_runes(s)
                runes_log.append((s.t / 60, s.runes))
        check_rank(game, s)
    # Leyenda: el final (la simulación para con el cristal abierto hasta el Núcleo).
    check_rank(game, s)
    game.runes_log = runes_log
    return s, log, timeline


def objective(s: State, log) -> float:
    """Cuánto se aleja una partida de las reglas: huecos de más y duración fuera de 2-3 h."""
    times = [0.0] + [e[0] for e in log]
    bad = 0.0
    for a, b in zip(times, times[1:]):
        limit = 60.0 if a < 3600 else 180.0
        bad += max(0.0, (b - a) - limit) ** 1.5
    if s.essence > 0.011 * 1_000_000:
        bad += 1e7  # no se acaba
    bad += (abs(s.t - GOAL_SEC) / 60.0) ** 2 * 50
    return bad


GOAL_SEC = 150 * 60


def summary(game: Game, s: State, log, timeline, name: str) -> dict:
    """Resumen comparable de una partida (para --json)."""
    times = [0.0] + [e[0] for e in log]
    gaps = [(b - a, a) for a, b in zip(times, times[1:])]
    hour = [g for g, at in gaps if at < 3600]
    income = {}
    for t, _m, _e, _p, a in timeline:
        for mark in (5, 15, 30, 45, 60, 90, 120, 150):
            if abs(t - mark * 60) < 16:
                income[str(mark)] = round(float(a.split()[-1][:-2]), 1)
    return {
        "perfil": name,
        "minutos": round(s.t / 60, 1),
        "compras": len(log),
        "primera_mejora_s": round(log[0][0]) if log else None,
        "hueco_max_1h_s": round(max(hour, default=0)),
        "hueco_max_s": round(max((g for g, _ in gaps), default=0)),
        "huecos_largos": sum(1 for g, at in gaps if g > (60 if at < 3600 else 180)),
        "mana_sin_gastar": round(s.mana),
        "mana_sin_gastar_pct": round(s.mana / max(s.mana_earned, 1.0) * 100, 1),
        "pilon_final_pct": round(s.pylon / game.total * 100, 1),
        # Cristal destruido (%) cuando el Pilón se llena (None: no llega a llenarse).
        "cristal_con_pilon_lleno": next(
            (round(100 - e / game.total * 100, 1) for _t, _m, e, p, _a in timeline if p >= game.total - 0.5),
            None,
        ),
        "nota": round(objective(s, log)),
        "rangos_min": {rid: round(m, 1) for m, rid in s.ranks},
        "maná_por_s": income,
        "lagrimas": tear_summary(game, s, log),
        "runas": rune_summary(game, s, log),
        "sin_comprar": sorted(
            f"{u.id} {s.levels.get(u.id, 0)}/{len(u.costs)}"
            for u in game.upgrades.values()
            if s.levels.get(u.id, 0) < len(u.costs)
        ),
    }


def rune_summary(game: Game, s: State, log) -> dict:
    """Runas: cuándo se compró cada nivel (min), las inscritas al final y el maná/s del mejor ataque
    al final con y sin ellas."""
    ids = {u.id for u in game.upgrades.values() if u.rune >= 0 or u.stat == "rune_slots"}
    bought = {f"{uid} {lv}": round(t / 60, 1) for t, uid, lv, *_ in log if uid in ids}
    with_runes = game.effective(s)[0]
    kept = s.runes
    s.runes = ()
    without = game.effective(s)[0]
    s.runes = kept
    return {
        "compras_min": bought,
        "inscritas": list(kept),
        "maná_por_s_con_sin": [round(with_runes), round(without)],
        "cambios": [(round(m, 1), list(r)) for m, r in getattr(game, "runes_log", [])][-6:],
    }


def tear_summary(game: Game, s: State, log) -> dict:
    """Lágrimas del Núcleo: cuántas cayeron, cuándo se compró cada nodo del Núcleo (min) y si la Gran
    Convergencia quedó inscrita al llegar al Núcleo (si no, cuántas faltaban)."""
    tear_ids = {u.id for u in game.upgrades.values() if u.currency == 1}
    bought = {f"{uid} {lv}": round(t / 60, 1) for t, uid, lv, *_ in log if uid in tear_ids}
    gc = game.upgrades.get("grand_convergence")
    missing = 0
    if gc is not None and s.levels.get(gc.id, 0) < len(gc.costs):
        missing = max(0, gc.costs[0] - math.floor(s.tears + 1e-9))
    pending = sorted(
        u.id for u in game.upgrades.values() if u.currency == 1 and s.levels.get(u.id, 0) < len(u.costs)
    )
    return {
        "total": round(s.tears_total, 1),
        "sobrantes": round(s.tears, 1),
        "compras_min": bought,
        "sin_comprar": pending,
        "faltan_para_convergencia": missing,
    }


def fmt(t: float) -> str:
    return f"{int(t // 60):3d}:{int(t % 60):02d}"


def report(game: Game, s: State, log, timeline, show_log: bool) -> None:
    times = [0.0] + [t for t, *_ in log]
    gaps = [(times[i + 1] - times[i], times[i]) for i in range(len(times) - 1)]
    first = log[0][0] if log else float("inf")
    hour_gaps = [g for g, at in gaps if at < 3600]
    max_gap = max(gaps, default=(0, 0))
    print(f"Partida: {fmt(s.t)} (min:s) hasta el Núcleo · {len(log)} compras · maná sin gastar {int(s.mana)}")
    print(f"Pilón al llegar al Núcleo: {s.pylon / game.total * 100:.1f} %")
    print(f"Primera mejora: {fmt(first)}")
    ts = tear_summary(game, s, log)
    print(
        f"Lágrimas del Núcleo: {ts['total']:.1f} recogidas, {ts['sobrantes']:.1f} sin gastar; nodos sin "
        f"comprar: {', '.join(ts['sin_comprar']) or 'ninguno'}"
    )
    rs = rune_summary(game, s, log)
    print(
        f"Runas: inscritas al final {', '.join(rs['inscritas']) or 'ninguna'}; maná/s con y sin ellas "
        f"{rs['maná_por_s_con_sin'][0]} / {rs['maná_por_s_con_sin'][1]}"
    )
    if hour_gaps:
        print(f"1.ª hora: hueco medio {sum(hour_gaps) / len(hour_gaps):.0f} s, máximo {max(hour_gaps):.0f} s")
    print(f"Hueco máximo: {max_gap[0]:.0f} s (a los {fmt(max_gap[1]).strip()})")
    print("\nCapas (esencia quitada) y ataque:")
    marks = [0.1, 0.45, 0.8, 0.99]
    names = ["Manto Geódico", "Venas Resonantes", "Corazón Cristalino", "Núcleo"]
    for t, mana, ess, pylon, attack in timeline:
        done = 1 - ess / game.total
        while marks and done >= marks[0]:
            print(f"  {fmt(t)}  {names[0]:<20} pilón {pylon / game.total * 100:5.1f} %  ({attack})")
            marks.pop(0)
            names.pop(0)
    print("\nRangos (GDD 8):")
    for m, rid in s.ranks:
        gdd = GDD_RANK_MIN.get(rid)
        print(f"  {fmt(m * 60)}  {rid:<10} (GDD: {'final' if gdd is None else f'{gdd} min'})")
    print("\nCada 15 min:")
    for t, mana, ess, pylon, attack in timeline:
        if int(t) % 900 < 30 and t >= 30:
            print(
                f"  {fmt(t)}  esencia {100 - ess / game.total * 100:5.1f} %  pilón "
                f"{pylon / game.total * 100:5.1f} %  ataque {attack}"
            )
    problems = []
    if first > 30:
        problems.append(f"la primera mejora llega a los {first:.0f} s (GDD: < 30 s)")
    if hour_gaps and max(hour_gaps) > 60:
        problems.append(f"en la 1.ª hora hay un hueco de {max(hour_gaps):.0f} s (GDD: < 60 s)")
    if max_gap[0] > 180:
        problems.append(f"hueco de {max_gap[0]:.0f} s (GDD: nunca > 3 min)")
    if ts["sin_comprar"]:
        problems.append(f"al llegar al Núcleo faltan nodos del Núcleo: {', '.join(ts['sin_comprar'])}")
    if not 2 * 3600 <= s.t <= 3 * 3600:
        problems.append(f"la partida dura {s.t / 3600:.2f} h (GDD: 2-3 h)")
    print(f"Nota (0 = perfecto; huecos de más y duración lejos de 2,5 h): {objective(s, log):.0f}")
    print("\nReglas del GDD: " + ("todo bien" if not problems else ""))
    for p in problems:
        print("  - " + p)
    long_gaps = [
        (b[0] - a[0], a[0], b[1], b[2], b[3])
        for a, b in zip([(0.0, "-", 0, 0)] + log, log)
        if b[0] - a[0] > (60 if a[0] < 3600 else 180)
    ]
    if long_gaps:
        print("Huecos largos (se ahorraba para...):")
        for g, at, uid, lv, c in long_gaps:
            print(f"  {fmt(at)}  {g:4.0f} s  -> {uid} {lv} ({c})")
    if show_log:
        print("\nCompras:")
        for t, uid, lv, c, *_ in log:
            print(f"  {fmt(t)}  {uid} {lv}  ({c})")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--log", action="store_true", help="lista todas las compras")
    ap.add_argument("--csv", help="escribe la línea de tiempo (cada 30 s)")
    ap.add_argument("--perfil", choices=list(PROFILES), help="sólo un jugador")
    ap.add_argument("--json", action="store_true", help="sólo un resumen en JSON por jugador")
    ap.add_argument("--old-shards", action="store_true", help="regla antigua de fragmentos")
    ap.add_argument("--tuning", help="archivo .py con una propuesta de números (ver apply_tuning)")
    args = ap.parse_args()
    global NEW_SHARDS, TUNING
    NEW_SHARDS = not args.old_shards
    if args.tuning:
        import importlib.util

        spec = importlib.util.spec_from_file_location("tuning", args.tuning)
        TUNING = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(TUNING)
    game = Game()
    for name in [args.perfil] if args.perfil else list(PROFILES):
        P.clear()
        P.update(PROFILES[name])
        s, log, timeline = simulate(game)
        if args.json:
            print(json.dumps(summary(game, s, log, timeline, name), ensure_ascii=False))
            continue
        print(f"===== Jugador {name} =====")
        report(game, s, log, timeline, args.log)
        print()
    if args.csv:
        with open(args.csv, "w", newline="") as f:
            w = csv.writer(f)
            w.writerow(["t", "mana", "essence", "pylon", "attack"])
            w.writerows(timeline)


if __name__ == "__main__":
    main()
