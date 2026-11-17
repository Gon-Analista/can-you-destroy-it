class_name SpellTier
extends Resource
## Cómo se ve, suena y pega un hechizo en un nivel de poder concreto.
## El mismo hechizo a nivel 1 y a nivel 5 tiene que verse distinto (dev guidelines 5.2).

@export var cooldown_sec: float = 1.5
@export var damage: int = 1
@export var speed: float = 26.0
## Tamaño visual del proyectil (m).
@export var size: float = 0.18
## Amplitud del bamboleo del proyectil (la chispa débil vuela torpe).
@export var wobble: float = 0.35
@export var shards_min: int = 1
@export var shards_max: int = 1
@export var shard_scale: float = 1.0
@export var impact_particles: int = 14
@export var light_energy: float = 2.0
@export var crack_radius: float = 0.9
## Trauma de cámara (0 a 1) que añade cada impacto.
@export var shake: float = 0.08
@export var color_core: Color = Color("#fff4c2")
@export var color_glow: Color = Color("#ffa53a")
## Color de las partículas, anillo y luz del impacto. Alfa 0 = los de siempre (cian / oro).
@export var impact_tint: Color = Color(0, 0, 0, 0)

@export_group("Aspecto en vuelo")
## Orbe que flota en la mano y vuela como proyectil (Chispa, Llama, Llama mágica...).
@export var visual: SpellVisualDef
## Escala del orbe en vuelo respecto a como se ve en la mano.
@export var orb_scale: float = 6.0
## Rampa de color de la estela, de caliente a frío (interpolación constante, alfa < 1 tramado).
@export var trail_ramp: Gradient
## Ancho de la estela en la cabeza (m).
@export var trail_width: float = 0.2
## Duración de la estela (s): cuanto más, más larga.
@export var trail_length: float = 0.14
