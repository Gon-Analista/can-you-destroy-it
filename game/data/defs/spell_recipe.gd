class_name SpellRecipe
extends Resource
## Combinación de elementos que produce un hechizo (p. ej. Chispa + Chispa = Bola de Fuego).

@export var id: StringName
@export var display_name: String
## Ids de ElementDef. El orden no importa.
@export var elements: Array[StringName] = []
@export var damage_multiplier: float = 1.0
@export var area_radius: float = 0.0
