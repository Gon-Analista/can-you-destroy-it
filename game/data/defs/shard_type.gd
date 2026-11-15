class_name ShardType
extends Resource
## Tipo de fragmento que suelta el Cristal Madre. El tamaño depende del daño del golpe:
## se usa el tipo de mayor `min_damage` que el golpe alcance (un golpe resonante sube uno).

@export var id: StringName
@export var display_name: String
## Plural para el HUD ("3 astillas").
@export var display_name_plural: String
## Daño mínimo del golpe para soltar este tipo.
@export var min_damage: int = 0
## Valor del fragmento al entregarlo al Pilón (aún no se usa: M1b).
@export var value: int = 1
@export_group("Forma")
@export var radius: float = 0.25
@export var height: float = 0.45
@export var tip: float = 0.3
@export var sides: int = 5
@export_group("Sensación")
## Tono del sonido al recogerlo (más grande = más grave).
@export var pickup_pitch: float = 1.0
@export var launch_speed: float = 1.0
