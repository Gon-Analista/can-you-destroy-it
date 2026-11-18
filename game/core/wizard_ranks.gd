class_name WizardRanks
extends RefCounted
## Reglas puras de los rangos del mago (GDD 8). Sin nodos ni autoloads: se prueban solas.
## Qué pide cada rango vive en `data/ranks/*.tres` (`RankDef`); aquí sólo se comprueba.

## De Aprendiz a Leyenda. El índice es el rango (`Progression.rank`).
const RANKS: Array[RankDef] = [
	preload("res://data/ranks/rank_0_apprentice.tres"),
	preload("res://data/ranks/rank_1_initiate.tres"),
	preload("res://data/ranks/rank_2_sorcerer.tres"),
	preload("res://data/ranks/rank_3_magus.tres"),
	preload("res://data/ranks/rank_4_archmage.tres"),
	preload("res://data/ranks/rank_5_legend.tres"),
]


static func last() -> int:
	return RANKS.size() - 1


static func def_of(rank: int) -> RankDef:
	return RANKS[clampi(rank, 0, last())]


## True si la partida cumple lo que pide `def` (sin mirar los rangos anteriores).
static func meets(def: RankDef, prog: Progression) -> bool:
	if def.or_finished and prog.is_crystal_destroyed():
		return true
	var destroyed: float = 1.0 - float(prog.essence) / float(prog.total_essence)
	if destroyed < def.min_destroyed:
		return false
	var pylon: float = prog.pylon_ratio()
	if pylon >= def.pylon_alone:
		return true
	var has_key: bool = def.key_upgrade == &"" or prog.get_level(def.key_upgrade) > 0
	return has_key and pylon >= def.key_pylon


## Rango más alto que se ha ganado, empezando a contar desde `from` (los rangos van en orden:
## cada uno pide el anterior). Nunca baja de `from`.
static func earned(prog: Progression, from: int = 0) -> int:
	var r: int = clampi(from, 0, last())
	while r < last() and meets(RANKS[r + 1], prog):
		r += 1
	return r


## Cuánto se ha avanzado hacia el rango siguiente (0..1), para la barra del Espejo: lo mejor
## entre el camino de la mejora clave (media de lo que pide: mejora, Pilón y cristal) y el del
## Pilón solo.
static func progress_to(rank: int, prog: Progression) -> float:
	if rank >= last():
		return 1.0
	var def: RankDef = RANKS[rank + 1]
	if meets(def, prog):
		return 1.0
	var pylon: float = prog.pylon_ratio()
	var alone: float = clampf(pylon / def.pylon_alone, 0.0, 1.0) if def.pylon_alone <= 1.0 else 0.0
	var sum: float = 0.0
	var parts: int = 0
	if def.key_upgrade != &"":
		sum += 1.0 if prog.get_level(def.key_upgrade) > 0 else 0.0
		parts += 1
	if def.key_pylon > 0.0:
		sum += clampf(pylon / def.key_pylon, 0.0, 1.0)
		parts += 1
	if def.min_destroyed > 0.0:
		var destroyed: float = 1.0 - float(prog.essence) / float(prog.total_essence)
		sum += clampf(destroyed / def.min_destroyed, 0.0, 1.0)
		parts += 1
	var key: float = sum / float(parts) if parts > 0 else 0.0
	return clampf(maxf(alone, key), 0.0, 0.99)
