class_name ElementDef
extends Resource
## Un elemento base (Chispa, Escarcha, Rayo, Tierra, Arcano).

@export var id: StringName
@export var display_name: String
@export var color: Color = Color.WHITE
@export var base_damage: float = 1.0
@export var cooldown_sec: float = 1.5
@export var unlock_pylon_ratio: float = 0.0
