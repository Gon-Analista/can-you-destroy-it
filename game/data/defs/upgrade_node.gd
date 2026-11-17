class_name UpgradeNode
extends Resource
## Nodo del Grimorio: una estrella de una constelación (rama). Cada nivel tiene su coste y el
## valor que da a una estadística (`stat`). Todo número de diseño vive en el `.tres`.

enum Branch { POWER, CHANNELING, ELEMENTS, TELEKINESIS, FAMILIARS, PYLON, RESONANCE }

@export var id: StringName
@export var display_name: String
## Qué hace, en una frase (se muestra en el Grimorio).
@export_multiline var description: String
@export var branch: Branch = Branch.POWER
## Coste de cada nivel (el índice 0 es el primer nivel comprado). Si está vacío se usa
## `base_cost` x `cost_growth` ^ nivel hasta `max_level`.
@export var costs: PackedInt32Array = PackedInt32Array()
@export var base_cost: int = 5
@export var cost_growth: float = 1.2
@export var max_level: int = 1
@export var prerequisites: Array[StringName] = []
## Estadística que modifica (p. ej. &"bag_capacity").
@export var stat: StringName
## Valor de la estadística en cada nivel: [sin comprar, nivel 1, nivel 2...].
@export var values: PackedFloat32Array = PackedFloat32Array()
## Cómo se muestra el valor en el Grimorio ("%d fragmentos", "x%.2f"...).
@export var value_format: String = "%s"
## Nombre de cada nivel cuando cambia la forma del hechizo ("Llama", "Llama mágica"...).
## Opcional; si está vacío se muestra el valor con `value_format`.
@export var level_names: PackedStringArray = PackedStringArray()


func get_max_level() -> int:
	return costs.size() if not costs.is_empty() else max_level


func cost_for_level(level: int) -> int:
	if not costs.is_empty():
		return costs[clampi(level, 0, costs.size() - 1)]
	return int(round(base_cost * pow(cost_growth, level)))


func value_at(level: int) -> float:
	if values.is_empty():
		return 0.0
	return values[clampi(level, 0, values.size() - 1)]


## Texto del valor en un nivel, para el Grimorio.
func describe_level(level: int) -> String:
	if level < level_names.size() and level_names[level] != "":
		return level_names[level]
	var v: float = value_at(level)
	if value_format.contains("%d"):
		return value_format % roundi(v)
	return value_format % v
