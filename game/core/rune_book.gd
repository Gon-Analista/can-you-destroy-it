class_name RuneBook
extends RefCounted
## Reglas puras de la Mesa de Runas (GDD 4.3 y 5.3), sin nodos: qué runas hay, cuándo se abre la
## mesa, cuántas ranuras tiene y cuáles están inscritas. Las runas se compran como estrellas
## (`GameState.buy_upgrade`, sus niveles van en `Progression.upgrade_levels`) pero sólo cuentan
## inscritas (`Progression.inscribed_runes`, en orden de ranura). Lo que hacen al lanzar está en
## RuneCaster.

const BALANCE: BalanceConfig = preload("res://data/balance/default_balance.tres")
## Las runas, en el orden de la mesa.
const RUNES: Array[RuneDef] = [
	preload("res://data/runes/rune_multishot.tres"),
	preload("res://data/runes/rune_bounce.tres"),
	preload("res://data/runes/rune_pierce.tres"),
	preload("res://data/runes/rune_echo.tres"),
	preload("res://data/runes/rune_harvest.tres"),
]
## Ranuras de más (la primera llega con la mesa): `values` = ranuras por nivel comprado.
const SLOTS: UpgradeNode = preload("res://data/runes/rune_slots.tres")
## Ranuras como mucho (las de `SLOTS` al máximo).
const MAX_SLOTS: int = 3


## True si la mesa ya está abierta: el Pilón (progreso real) llegó a su marca.
static func table_unlocked(prog: Progression) -> bool:
	return prog.pylon_ratio() + 1e-6 >= BALANCE.rune_table_pylon


## Ranuras para inscribir (0 con la mesa sellada).
static func slot_count(prog: Progression) -> int:
	if not table_unlocked(prog):
		return 0
	return mini(roundi(prog.stat_of(SLOTS)), MAX_SLOTS)


static func def_of(id: StringName) -> RuneDef:
	for r: RuneDef in RUNES:
		if r.id == id:
			return r
	return null


static func def_of_kind(kind: RuneDef.Kind) -> RuneDef:
	for r: RuneDef in RUNES:
		if r.kind == kind:
			return r
	return null


## True si la runa `id` está en una ranura que cuenta (comprada y dentro de las ranuras que hay).
static func is_inscribed(prog: Progression, id: StringName) -> bool:
	var slots: int = slot_count(prog)
	var used: int = 0
	for rid: StringName in prog.inscribed_runes:
		if used >= slots:
			return false
		if prog.get_level(rid) <= 0 or def_of(rid) == null:
			continue
		if rid == id:
			return true
		used += 1
	return false


## Runas inscritas que cuentan, en orden de ranura.
static func inscribed(prog: Progression) -> Array[RuneDef]:
	var out: Array[RuneDef] = []
	for r: RuneDef in RUNES:
		if is_inscribed(prog, r.id):
			out.append(r)
	out.sort_custom(
		func(a: RuneDef, b: RuneDef) -> bool:
			return prog.inscribed_runes.find(a.id) < prog.inscribed_runes.find(b.id)
	)
	return out


## Nivel con el que actúa una runa: el comprado si está inscrita; si no, 0.
static func active_level(prog: Progression, kind: RuneDef.Kind) -> int:
	var def: RuneDef = def_of_kind(kind)
	if def == null or not is_inscribed(prog, def.id):
		return 0
	return prog.get_level(def.id)


## Ranura (0..MAX_SLOTS-1) en la que cuenta la runa `id` (las que no cuentan no ocupan ranura).
static func slot_index(prog: Progression, id: StringName) -> int:
	var n: int = 0
	for rid: StringName in prog.inscribed_runes:
		if rid == id:
			return n
		if is_inscribed(prog, rid):
			n += 1
	return n


## Ranuras ocupadas por runas que cuentan.
static func used_slots(prog: Progression) -> int:
	var n: int = 0
	for r: RuneDef in RUNES:
		if is_inscribed(prog, r.id):
			n += 1
	return n


## Inscribe la runa `id` en la primera ranura libre. False si no se puede (sellada, sin comprar,
## ya inscrita o sin ranura libre).
static func inscribe(prog: Progression, id: StringName) -> bool:
	if inscribe_block(prog, id) != &"":
		return false
	_prune(prog)
	prog.inscribed_runes.append(id)
	return true


## Por qué no se puede inscribir (o &"" si se puede): &"sealed", &"unknown", &"unbought",
## &"inscribed" o &"full".
static func inscribe_block(prog: Progression, id: StringName) -> StringName:
	if not table_unlocked(prog):
		return &"sealed"
	if def_of(id) == null:
		return &"unknown"
	if prog.get_level(id) <= 0:
		return &"unbought"
	if is_inscribed(prog, id):
		return &"inscribed"
	if used_slots(prog) >= slot_count(prog):
		return &"full"
	return &""


## Borra la runa `id` de su ranura. False si no estaba.
static func erase(prog: Progression, id: StringName) -> bool:
	if not prog.inscribed_runes.has(id):
		return false
	prog.inscribed_runes.erase(id)
	return true


## Cosecha inscrita: multiplicador del daño de los hechizos del mago (1 = sin Cosecha).
static func harvest_damage(prog: Progression) -> float:
	var lv: int = active_level(prog, RuneDef.Kind.HARVEST)
	return def_of_kind(RuneDef.Kind.HARVEST).damage_at(lv) if lv > 0 else 1.0


## Cosecha inscrita: multiplicador del maná de cada fragmento triturado (1 = sin Cosecha).
static func harvest_value(prog: Progression) -> float:
	var lv: int = active_level(prog, RuneDef.Kind.HARVEST)
	return def_of_kind(RuneDef.Kind.HARVEST).value_at(lv) if lv > 0 else 1.0


## Quita de la lista lo que no cuenta (runas desconocidas, sin comprar o repetidas).
static func _prune(prog: Progression) -> void:
	var keep: Array[StringName] = []
	for rid: StringName in prog.inscribed_runes:
		if def_of(rid) != null and prog.get_level(rid) > 0 and not keep.has(rid):
			keep.append(rid)
	prog.inscribed_runes = keep
