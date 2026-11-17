class_name ElementDef
extends Resource
## Un elemento base (Chispa, Escarcha, Rayo, Tierra, Arcano).

@export var id: StringName
@export var display_name: String
@export var color: Color = Color.WHITE
@export var base_damage: float = 1.0
@export var cooldown_sec: float = 1.5
@export var unlock_pylon_ratio: float = 0.0
## Niveles de poder del elemento (el índice 0 es el inicial).
@export var tiers: Array[SpellTier] = []
## Lo que flota sobre la palma de la mano que lleva este elemento.
@export var hand_visual: SpellVisualDef
