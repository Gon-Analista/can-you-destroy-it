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
- Fragmentos (`MotherCrystal.receive_hit` + `ShardPool.type_for_hit`): cuántos caen y de qué tipo; el maná es
  la suma de sus valores. La esencia que se quita es el daño del golpe.
- Logística: recoger (o Telequinesis), bolsa, viaje a la trituradora, echar y triturar (Engranajes), Envío
  directo, viajes al Santuario para comprar.
- Capas: el Corazón (80-99 %) sólo cede a combinaciones; el Núcleo (último 1 %) es el final.

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
import json
import math
import re
from dataclasses import dataclass, field
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent / "game"
DATA = ROOT / "data"

# --- Logística (metros, segundos): ver core/world_layout.gd, player.gd y crystal_crusher.gd ---
# Dos jugadores: "eficiente" (cota optimista) y "normal" (mira, falla, pasea, lee el Grimorio).
PROFILES = {
    "eficiente": dict(speed=8.0, buy=3.0, pick=0.8, accuracy=0.9, max_rate=6.0, charge=1.0, focus=1.0),
    "normal": dict(speed=7.0, buy=6.0, pick=1.0, accuracy=0.8, max_rate=4.0, charge=0.9, focus=0.85),
}
P = dict(PROFILES["eficiente"])
CRUSHER_DIST = 50.0  # del cristal a la trituradora
FAMILIAR_DIST = 55.0  # de la tolva a donde caen los fragmentos
SANCTUM_EXTRA = 94.0  # trituradora -> Santuario -> cristal, lo que se añade al viaje
FEED_START, FEED_MIN, FEED_RAMP = 0.4, 0.09, 2.4
LEVER_SEC = 1.0
NEW_SHARDS = True  # regla nueva: el maná de un golpe es más o menos su daño (ver hit_yield)
MAX_PIECES, MAX_EXTRA = 10, 3  # ShardPool
VEIN_FOCUS = 0.6  # parte de los golpes que el jugador da en la vena de su elemento (capa de venas)
VEIN_BONUS = 0.5  # CrystalLayerDef.vein_bonus
DIRECT_SEND_LEVER_EVERY = 90.0  # con Envío directo, se va a tirar de la palanca cada tanto
MOVEMENT_UPGRADES = {"double_jump", "levitation", "crystal_impulse"}


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


def ensure_levels(
    tiers: list[Tier], max_level: int = 10, growth: float = 1.38, cd_growth: float = 0.92
) -> list[Tier]:
    """Copia de ElementDef.ensure_levels (los niveles que faltan hasta el 10)."""
    while len(tiers) < max_level and tiers:
        prev = tiers[-1]
        n = len(tiers)
        echoes = prev.echoes + (1 if prev.echoes > 0 and n + 1 in (6, 9) else 0)
        tiers.append(
            Tier(
                max(prev.damage + 1, gd_round(prev.damage * growth)),
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


@dataclass
class Upgrade:
    id: str
    costs: list[int]
    values: list[float]
    stat: str
    prereq: list[str]


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
        )
        elements[main["id"]] = Element(
            main["id"],
            tiers,
            main.get("power_stat", ""),
            main.get("size_stat", ""),
            main.get("unlock_upgrade", ""),
            int(main.get("shard_bonus", 0)),
            float(main.get("echo_damage", 0.0)),
        )
    recipes: dict[str, Recipe] = {}
    for p in sorted((DATA / "spells").glob("recipe_*.tres")):
        main, subs = parse_tres(p)
        if main.get("is_reaction", "false") == "true" or not main.get("elements"):
            continue
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
        )
    upgrades: dict[str, Upgrade] = {}
    for p in sorted((DATA / "upgrades").glob("*.tres")):
        main, _ = parse_tres(p)
        upgrades[main["id"]] = Upgrade(
            main["id"],
            [int(c) for c in main.get("costs", [])],
            main.get("values", []),
            main.get("stat", ""),
            main.get("prerequisites", []),
        )
    shards = []
    for p in (DATA / "shards").glob("*.tres"):
        main, _ = parse_tres(p)
        shards.append(ShardT(main["id"], int(main.get("min_damage", 0)), int(main.get("value", 1))))
    shards.sort(key=lambda s: s.min_damage)
    balance, _ = parse_tres(DATA / "balance" / "default_balance.tres")
    balance["_familiars"] = {}
    for p in sorted((DATA / "familiars").glob("*.tres")) if (DATA / "familiars").exists() else []:
        main, _ = parse_tres(p)
        balance["_familiars"][main["id"]] = main
    if TUNING is not None:
        apply_tuning(TUNING, elements, recipes, upgrades, balance)
    return elements, recipes, upgrades, shards, balance


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
    - CONSTANTS = {"VEIN_BONUS": 0.5}  (constantes de este simulador que copian datos del juego)
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


class Game:
    def __init__(self) -> None:
        self.elements, self.recipes, self.upgrades, self.shards, self.balance = load()
        self.total = float(self.balance.get("total_essence", 1_000_000))
        self.res_mult = int(self.balance.get("resonant_damage_mult", 3))
        self.familiars = self.balance.get("_familiars", {})

    # -- estadísticas --
    def stat(self, s: State, stat: str, fallback: float) -> float:
        for u in self.upgrades.values():
            if u.stat == stat:
                lv = s.levels.get(u.id, 0)
                return u.values[min(lv, len(u.values) - 1)] if u.values else fallback
        return fallback

    def awake(self, s: State, el: Element) -> bool:
        return not el.unlock or s.levels.get(el.unlock, 0) > 0

    def tier(self, s: State, el: Element) -> Tier:
        idx = int(round(self.stat(s, el.power_stat, 0.0)))
        return el.tiers[max(0, min(idx, len(el.tiers) - 1))]

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

    def hit_yield(self, damage: int, tier: Tier, size: float, bonus: int, res_p: float):
        """(esencia, maná, fragmentos) medios de un golpe, con la resonancia."""
        if damage <= 0:
            return 0.0, 0.0, 0.0
        count = (tier.shards_min + tier.shards_max) / 2.0 * (1.0 + (size - 1.0) * 0.6)
        weak = size < 0.6
        if weak:
            count = 1.0
        out = [0.0, 0.0, 0.0]
        if NEW_SHARDS:
            # Cada golpe suelta fragmentos por valor de su daño: el tipo sale del daño (umbral
            # `min_damage`) y la cuenta, daño / valor; lo que sobra, en trocitos.
            # Tierra y Lanza Cargada (bonus): +25 % de valor por paso.
            for res, p in ((False, 1.0 - res_p), (True, res_p)):
                d = damage * (self.res_mult if res else 1)
                worth = d * (1.0 + 0.25 * bonus)
                if weak:
                    out[0] += p * d
                    out[1] += p * self.shards[0].value
                    out[2] += p
                    continue
                else:
                    # ShardPool.pieces_for: tipo por daño (umbral `min_damage`, el doble de su
                    # valor), hasta 8 piezas (si no, un tamaño más) y 2 trocitos para el resto.
                    idx = 0
                    for i, st_i in enumerate(self.shards):
                        if worth >= st_i.min_damage:
                            idx = i
                    while idx < len(self.shards) - 1 and worth // self.shards[idx].value > MAX_PIECES:
                        idx += 1
                    st = self.shards[idx]
                    top = MAX_PIECES * (2 if idx == len(self.shards) - 1 else 1)
                    c = max(1, min(int(worth // st.value), top))
                    rest = worth - c * st.value
                    extra_v, extra_n = 0.0, 0
                    for j in range(idx - 1, -1, -1):
                        while rest >= self.shards[j].value and extra_n < MAX_EXTRA:
                            rest -= self.shards[j].value
                            extra_v += self.shards[j].value
                            extra_n += 1
                    out[0] += p * d
                    out[1] += p * (c * st.value + extra_v)
                    out[2] += p * (c + extra_n)
                    continue
                out[0] += p * d
                out[1] += p * c * st.value
                out[2] += p * c
            return tuple(out)
        for res, p in ((False, 1.0 - res_p), (True, res_p)):
            d = damage * (self.res_mult if res else 1)
            c = math.ceil(count * (2 if res else 1)) if not weak else 1
            st = self.shard_type(d, (1 if res else 0) + bonus)
            out[0] += p * d
            out[1] += p * c * st.value
            out[2] += p * c
        return tuple(out)

    def attacks(self, s: State):
        """Lista de (nombre, esencia/s, maná/s, fragmentos/s, sólo_combinación)."""
        res_p = self.stat(s, "resonant_percent", float(self.balance.get("resonant_chance", 0.07)) * 100) / 100
        cd_mult = self.stat(s, "cooldown_mult", 1.0)
        out = []
        awake = [e for e in self.elements.values() if self.awake(s, e)]
        for el in awake:
            t = self.tier(s, el)
            size = self.stat(s, el.size_stat, 1.0) if el.size_stat else 1.0
            dmg = self.sized(t.damage, size)
            e, m, n = self.hit_yield(dmg, t, size, el.shard_bonus, res_p)
            if t.echoes and el.echo_damage > 0:
                ee, em, en = self.hit_yield(max(1, round(dmg * el.echo_damage)), t, size, 0, res_p)
                e, m, n = e + ee * t.echoes, m + em * t.echoes, n + en * t.echoes
            rate = 2.0 * min(1.0 / (t.cooldown * cd_mult), P["max_rate"]) * P["accuracy"]
            out.append((el.id, e * rate, m * rate, n * rate, False))
        # Combinaciones (la carga completa).
        for r in self.recipes.values():
            els = [self.elements.get(x) for x in r.elements]
            if any(x is None or not self.awake(s, x) for x in els):
                continue
            t0, t1 = self.tier(s, els[0]), self.tier(s, els[1])
            if t0.damage <= 0 and t1.damage <= 0:
                dmg, size = 1, 0.45  # tutorial: juntar sin daño hace 1
            else:
                dmg = max(1, round((t0.damage + t1.damage) * r.mult * P["charge"]))
                if r.power_stat:
                    dmg = round(dmg * self.stat(s, r.power_stat, 1.0))
                size = self.stat(s, r.size_stat, 1.0) if r.size_stat else 1.0
                dmg = self.sized(dmg, size)
            if r.mult <= 0:
                continue  # utilidad (Magnetismo)
            parts = max(1, r.rain + (1 if r.rain == 0 else 0))
            each = max(1, round(dmg / parts))
            e, m, n = self.hit_yield(each, r.tier, size, r.shard_bonus, res_p)
            e, m, n = e * parts, m * parts, n * parts
            if r.chain:
                # CrystalCombos.chain: cada salto arranca el 20 % del daño.
                ce, cm, cn = self.hit_yield(max(1, round(dmg * 0.2)), r.tier, 1.0, r.shard_bonus, res_p)
                e, m, n = e + ce * r.chain, m + cm * r.chain, n + cn * r.chain
            if r.echo_count:
                k = 1.0 + r.echo_count * r.echo_damage
                e, m, n = e * k, m * k, n * k
            if r.area_hits and size >= 0.6:
                m += r.area_hits  # astillas de los golpes en área
                n += r.area_hits
            cycle = r.charge + max(r.cooldown * cd_mult, t0.cooldown * cd_mult)
            rate = P["accuracy"] / cycle
            out.append((r.id, e * rate, m * rate, n * rate, True))
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

    def effective(self, s: State) -> tuple[float, float, str]:
        """(maná/s, esencia/s, ataque) del mejor ataque, contando la logística."""
        rates = self.rates(s)
        return max(rates, key=lambda r: r[0]) if rates else (0.0, 0.0, "-")

    def value(self, s: State) -> float:
        """Lo que vale el arsenal para el jugador: media cuadrática de todos sus ataques (un
        jugador de verdad también mejora los hechizos que no son el mejor; el mejor pesa más)."""
        rates = [r[0] for r in self.rates(s)]
        if not rates:
            return 0.0
        return (sum(x**2 for x in rates) / len(rates)) ** 0.5

    def familiar_rates(self, s: State) -> tuple[float, float, float, float]:
        """(fragmentos/s que llevan los recolectores, y esencia/s, maná/s y fragmentos/s que sueltan
        los hechiceros) según data/familiars/ y familiar.gd."""
        collectors = int(self.stat(s, "familiar_count", 0.0))
        casters = int(self.stat(s, "familiar_caster", 0.0))
        wings = self.stat(s, "familiar_speed", 1.0)
        wing_lv = s.levels.get("familiar_wings", 0)
        carry_rate = 0.0
        if collectors:
            f = self.familiars.get("collector", {})
            carry = int(f.get("carry", 3)) + wing_lv
            speed = float(f.get("fly_speed", 7.0)) * wings
            # Ida y vuelta tolva <-> cristal (en arco, un 20 % más largo) y recoger/soltar cada uno.
            trip = 2 * FAMILIAR_DIST * 1.2 / speed
            per = carry * (float(f.get("grab_sec", 0.3)) + float(f.get("drop_gap_sec", 0.16)) + 0.5)
            carry_rate = collectors * carry / (trip + per)
        ce = cm = cn = 0.0
        if casters:
            f = self.familiars.get("caster", {})
            spark = self.elements["spark"]
            idx = max(0, int(round(self.stat(s, spark.power_stat, 0.0))) + int(f.get("tier_offset", -1)))
            t = spark.tiers[min(idx, len(spark.tiers) - 1)]
            dmg = max(1, gd_round(t.damage * float(f.get("damage_mult", 0.6))))
            period = float(f.get("cast_interval", 3.2)) + float(f.get("cast_charge_sec", 0.9))
            res_p = self.stat(s, "resonant_percent", 7.0) / 100
            e, m, n = self.hit_yield(dmg, t, 1.0, 0, res_p)
            k = casters * 0.85 / period  # alguno falla
            ce, cm, cn = e * k, m * k, n * k
        return carry_rate, ce, cm, cn

    def pylon_bolt_rates(self, s: State) -> tuple[float, float, float]:
        """Resonancia del Pilón: un rayo cada `pylon_bolt_sec` s con daño de 25 a 600 según lo lleno
        que se vea el Pilón (raíz del progreso, ManaPylon.display_fill)."""
        every = self.stat(s, "pylon_bolt_sec", 0.0)
        if every <= 0:
            return 0.0, 0.0, 0.0
        lo = float(self.balance.get("pylon_bolt_damage_min", 25))
        hi = float(self.balance.get("pylon_bolt_damage_max", 600))
        dmg = gd_round(lo + (hi - lo) * math.sqrt(s.pylon / self.total))
        e, m, n = self.hit_yield(dmg, self.elements["bolt"].tiers[0], 1.0, 0, 0.0)
        k = 1.0 / (every + float(self.balance.get("pylon_bolt_charge_sec", 0.9)))
        return e * k, m * k, n * k

    def rates(self, s: State) -> list[tuple[float, float, str]]:
        heart = s.essence / self.total < 0.2
        out: list[tuple[float, float, str]] = []
        cap = self.stat(s, "bag_capacity", float(self.balance.get("hand_capacity", 3)))
        tk = self.stat(s, "telekinesis_radius", 0.0)
        pick = P["pick"] if tk <= 0 else max(0.08, 0.3 / (tk / 3.5))
        trip = CRUSHER_DIST / P["speed"]
        gears = self.stat(s, "crusher_speed", 1.0)
        direct = self.stat(s, "direct_send", 0.0) > 0.5
        carry_rate, fe, fm, fn = self.familiar_rates(s)
        be, bm, bn = self.pylon_bolt_rates(s)
        fe, fm, fn = fe + be, fm + bm, fn + bn
        done = 1.0 - s.essence / self.total
        veins = 0.45 <= done < 0.8
        purity = self.stat(s, "purity_mult", 1.0)
        for name, e, m, n, combo in self.attacks(s):
            if heart and not combo:
                continue
            if n <= 0 or m <= 0:
                continue
            if veins:
                # CrystalVeins: VEIN_FOCUS de los golpes caen en su vena débil: x2 de daño y
                # Fragmentos Resonantes por la mitad de ese daño (vein_bonus).
                e, m = e * (1 + VEIN_FOCUS), m * (1 + VEIN_FOCUS) + e * 2 * VEIN_FOCUS * VEIN_BONUS
                n = n * (1 + VEIN_FOCUS) + e * VEIN_FOCUS * VEIN_BONUS / 125.0
            # Los hechiceros y el rayo del Pilón suman lo suyo mientras el mago ataca.
            e, m, n = e + fe, m + fm, n + fn
            # La Pureza sube el maná (no el Pilón: ver simulate).
            m *= purity
            # Segundos de logística del mago por cada fragmento que le toca a él.
            if direct:
                # Vuelan solos a la tolva: recogerlos y, de vez en cuando, ir a la palanca (si no
                # hay familiares que tiren de ella).
                lever = 0.0 if carry_rate > 0 else (2 * trip + LEVER_SEC) / DIRECT_SEND_LEVER_EVERY
                per_shard = pick
                fixed = lever
            else:
                per_shard = pick + (2 * trip + self.feed_time(cap, gears) + LEVER_SEC) / cap
                fixed = 0.0
            # Los recolectores se llevan una parte de los fragmentos (los que caen al suelo).
            mine = max(0.0, n - carry_rate)
            k = 1.0 / (1.0 + mine * per_shard + fixed)
            out.append((m * k * P["focus"], e * k * P["focus"], name))
        return out

    # -- mejoras --
    def available(self, s: State, u: Upgrade) -> bool:
        if s.levels.get(u.id, 0) >= len(u.costs):
            return False
        for pr in u.prereq:
            if pr.startswith("recipe:"):
                r = self.recipes.get(pr[7:])
                if r is None or any(not self.awake(s, self.elements[x]) for x in r.elements):
                    return False
            elif s.levels.get(pr, 0) <= 0:
                return False
        return True

    def cost(self, s: State, u: Upgrade) -> int:
        return u.costs[s.levels.get(u.id, 0)]

    def score(self, s: State, u: Upgrade, base: float) -> float:
        s2 = State(dict(s.levels), s.mana, s.essence, s.pylon, s.t)
        s2.levels[u.id] = s2.levels.get(u.id, 0) + 1
        gain = self.value(s2) / max(base, 1e-9) - 1.0
        if u.id in MOVEMENT_UPGRADES:
            gain = max(gain, 0.04)  # gusto por moverse: se compran cuando salen baratas
        # Desbloqueos (despertar un elemento): curiosidad, aunque al principio rinda poco.
        if u.stat.endswith("_awake"):
            gain = max(gain, 0.15)
        return gain / self.cost(s, u)


def simulate(game: Game, verbose: bool = False, max_hours: float = 6.0):
    s = State()
    log: list[tuple[float, str, int, int]] = []
    timeline: list[tuple[float, float, float, float, str]] = []
    step = 2.0
    next_sample = 0.0
    while s.essence > game.total * 0.01 and s.t < max_hours * 3600:
        rate, ess_rate, attack = game.effective(s)
        if rate <= 0:
            break
        # Avanza `step` segundos de juego.
        # El Pilón no pasa de la esencia total; el maná sí se sigue ganando (Progression.deliver).
        gain = rate * step
        s.mana += gain
        s.pylon = min(game.total, s.pylon + gain / game.stat(s, "purity_mult", 1.0))
        s.essence = max(0.0, s.essence - ess_rate * step)
        s.t += step
        if s.t >= next_sample:
            timeline.append((s.t, s.mana, s.essence, s.pylon, f"{attack} {rate:.0f}/s"))
            next_sample += 30.0
        # ¿Toca ir al Santuario?
        cands = [u for u in game.upgrades.values() if game.available(s, u)]
        if not cands:
            continue
        v = game.value(s)
        scored = sorted(((game.score(s, u, v), u) for u in cands), key=lambda x: -x[0])
        target = scored[0][1]
        if s.mana < game.cost(s, target):
            # Compra impulsiva: algo barato y útil mientras se ahorra.
            cheap = [u for sc, u in scored if game.cost(s, u) <= s.mana and sc >= scored[0][0] * 0.5]
            if not cheap:
                continue
            target = cheap[0]
        s.t += SANCTUM_EXTRA / P["speed"]
        bought = 0
        while True:
            cands = [u for u in game.upgrades.values() if game.available(s, u) and game.cost(s, u) <= s.mana]
            if not cands:
                break
            base = game.effective(s)[0]
            v = game.value(s)
            best = max(cands, key=lambda u: game.score(s, u, v))
            if bought and game.score(s, best, v) <= 0:
                break
            c = game.cost(s, best)
            s.mana -= c
            s.levels[best.id] = s.levels.get(best.id, 0) + 1
            s.t += P["buy"]
            bought += 1
            log.append((s.t, best.id, s.levels[best.id], c, base))
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
        "pilon_final_pct": round(s.pylon / game.total * 100, 1),
        "nota": round(objective(s, log)),
        "maná_por_s": income,
        "sin_comprar": sorted(
            f"{u.id} {s.levels.get(u.id, 0)}/{len(u.costs)}"
            for u in game.upgrades.values()
            if s.levels.get(u.id, 0) < len(u.costs)
        ),
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
