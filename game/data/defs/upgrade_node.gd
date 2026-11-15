class_name UpgradeNode
extends Resource
## Nodo del Grimorio.

enum Branch { POWER, CHANNELING, ELEMENTS, TELEKINESIS, FAMILIARS, PYLON, RESONANCE }

@export var id: StringName
@export var display_name: String
@export var branch: Branch = Branch.POWER
@export var base_cost: int = 5
@export var cost_growth: float = 1.2
@export var max_level: int = 1
@export var prerequisites: Array[StringName] = []
## Estadística que modifica (p. ej. &"spark_damage") y cuánto por nivel.
@export var stat: StringName
@export var value_per_level: float = 0.0


func cost_for_level(level: int) -> int:
	return int(round(base_cost * pow(cost_growth, level)))
