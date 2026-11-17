class_name ElementDef
extends Resource
## Un elemento base (Chispa, Escarcha, Rayo, Tierra, Arcano).

## Nivel máximo de todos los hechizos.
const MAX_LEVEL: int = 10
## Desde este nivel empiezan los efectos de nivel alto (círculos mágicos...).
const ASCENDED_LEVEL: int = 6

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
## Estadística de mejora del tamaño del hechizo (multiplicador, 1 = el de siempre).
@export var size_stat: StringName
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
## Rayos que saltan desde el impacto a otros puntos del cristal (Rayo).
@export var chain_count: int = 0
## Fragmentos un tamaño más grandes (Tierra).
@export var shard_bonus: int = 0
## Color de sus círculos de toque (nivel 6+).
@export var circle_color: Color = Color(1.0, 0.6, 0.2)


## Completa `tiers` hasta el nivel 10 a partir del último escrito a mano: cada nivel nuevo dobla
## el daño, es algo más rápido, más grande y de más área, y el color tira hacia el violeta arcano.
func ensure_levels() -> void:
	while tiers.size() < MAX_LEVEL and not tiers.is_empty():
		var prev: SpellTier = tiers[tiers.size() - 1]
		var t: SpellTier = prev.duplicate()
		var k: float = float(tiers.size() - 4) / float(MAX_LEVEL - 5)
		t.damage = prev.damage * 2
		t.cooldown_sec = maxf(0.1, prev.cooldown_sec * 0.9)
		t.speed = prev.speed + 4.0
		t.orb_scale = prev.orb_scale + 0.5
		t.crack_radius = prev.crack_radius * 1.04
		t.shards_max = prev.shards_max + 1
		t.shards_min = prev.shards_min + (1 if tiers.size() % 2 == 0 else 0)
		t.impact_particles = prev.impact_particles + 2
		t.light_energy = prev.light_energy
		t.shake = minf(prev.shake + 0.02, 0.3)
		t.trail_width = prev.trail_width * 1.06
		t.color_glow = prev.color_glow.lerp(Color(0.78, 0.45, 1.0), 0.12 + k * 0.1)
		tiers.append(t)
