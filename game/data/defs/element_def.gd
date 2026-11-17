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
## Estadística de mejora que da su nivel (índice en `tiers`), p. ej. &"spark_tier".
@export var power_stat: StringName
## Mejora que hay que tener para poder ponerlo en una mano (vacío = disponible desde el inicio).
@export var unlock_upgrade: StringName
## Sonido al lanzar (si está vacío, el crepitar de la Chispa) y su tono.
@export var cast_sfx: Array[AudioStream] = []
@export var cast_pitch: float = 1.0
## Sonido extra al impactar (además del "tink" del cristal); vacío = ninguno.
@export var impact_sfx: Array[AudioStream] = []

@export_group("Efecto en el cristal")
## La zona golpeada queda debilitada: los golpes de otros elementos hacen x`weaken_mult` durante
## `weaken_sec` (la Escarcha congela). 1 = nada.
@export var weaken_mult: float = 1.0
@export var weaken_sec: float = 0.0
