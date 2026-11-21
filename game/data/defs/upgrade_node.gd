class_name UpgradeNode
extends Resource
## Nodo del Grimorio: una estrella de una constelación (rama). Cada nivel tiene su coste y el
## valor que da a una estadística (`stat`). Todo número de diseño vive en el `.tres`.

enum Branch { POWER, CHANNELING, ELEMENTS, TELEKINESIS, FAMILIARS, PYLON, RESONANCE }
## Con qué se paga: maná o Lágrimas del Núcleo (los nodos finales, GDD 6.1 y 8).
enum Currency { MANA, TEARS }

@export var id: StringName
@export var display_name: String
## Qué hace, en una frase (se muestra en el Grimorio).
@export_multiline var description: String
@export var branch: Branch = Branch.POWER
## Elemento de su constelación en el Grimorio (id de ElementDef); vacío = página del Mago.
@export var element: StringName = &""
## Posición de la estrella en la página de su constelación (px, página de 236x276).
@export var star_pos: Vector2i = Vector2i(118, 140)
## Coste de cada nivel (el índice 0 es el primer nivel comprado). Si está vacío se usa
## `base_cost` x `cost_growth` ^ nivel hasta `max_level`.
@export var costs: PackedInt32Array = PackedInt32Array()
@export var base_cost: int = 5
@export var cost_growth: float = 1.2
@export var max_level: int = 1
## Moneda de los costes: maná (casi todo) o Lágrimas del Núcleo (página del Núcleo).
@export var currency: Currency = Currency.MANA
## > 0: la estrella no se ve ni se puede comprar hasta que el cristal esté destruido a esa
## fracción (la Gran Convergencia, con el Núcleo expuesto al 99 %).
@export_range(0.0, 1.0) var reveal_destroyed_ratio: float = 0.0
## > 0: el último nivel (la Ascensión de los hechizos, nivel 11) no se puede inscribir hasta que el
## cristal esté destruido a esa fracción: con él, tres o cuatro combinados cargados lo deshacen.
@export_range(0.0, 1.0) var apex_destroyed_ratio: float = 0.0
## Ids de mejoras que hay que tener, o "recipe:<id>" para una combinación ya descubierta.
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


func pays_with_tears() -> bool:
	return currency == Currency.TEARS


func cost_for_level(level: int) -> int:
	if not costs.is_empty():
		return costs[clampi(level, 0, costs.size() - 1)]
	return roundi(base_cost * pow(cost_growth, level))


func value_at(level: int) -> float:
	if values.is_empty():
		return 0.0
	return values[clampi(level, 0, values.size() - 1)]


## Texto del valor en un nivel, para el Grimorio.
func describe_level(level: int) -> String:
	if level < level_names.size() and level_names[level] != "":
		return tr(level_names[level])
	var v: float = value_at(level)
	var fmt: String = tr(value_format)
	if fmt.contains("%d"):
		return fmt % roundi(v)
	return fmt % v
