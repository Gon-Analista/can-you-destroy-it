class_name SpellRecipe
extends Resource
## Combinación de elementos que produce un hechizo (p. ej. Chispa + Chispa = Bola de Fuego).
## Se lanza pulsando las dos manos a la vez y manteniendo para cargar (GDD 5.2 y 10.1).

@export var id: StringName
@export var display_name: String
## Ids de ElementDef. El orden no importa.
@export var elements: Array[StringName] = []
## Daño = (daño mano izquierda + daño mano derecha) x multiplicador x potencia de la carga.
@export var damage_multiplier: float = 1.0
## Radio de la explosión en el cristal (m). 0 = golpe puntual.
@export var area_radius: float = 0.0
## Golpes secundarios repartidos por el área (cada uno agrieta y suelta fragmentos).
@export var area_hits: int = 0

@export_group("Fuego que queda")
## Segundos que sigue ardiendo el cristal donde impacta (0 = nada).
@export var burn_sec: float = 0.0
## Daño de cada golpe de quemadura y cada cuánto.
@export var burn_damage: int = 1
@export var burn_tick_sec: float = 0.5

@export_group("Efecto en el cristal")
## La zona queda quebradiza: el siguiente golpe hace x`shatter_mult` (Choque Térmico). 1 = nada.
@export var shatter_mult: float = 1.0
@export var shatter_sec: float = 6.0
## Estadística de mejora que multiplica su daño (p. ej. &"fireball_mult"); vacía = ninguna.
@export var power_stat: StringName
## Estadística de mejora del tamaño del hechizo (multiplicador, 1 = el de siempre).
@export var size_stat: StringName

@export_group("Carga")
## Tiempo manteniendo las dos manos juntas hasta la carga completa (s).
@export var charge_sec: float = 0.7
## Potencia si se suelta nada más juntar las manos (con carga completa es 1).
@export_range(0.0, 1.0) var min_power: float = 0.5
## Enfriamiento de las dos manos tras lanzar la combinación (s).
@export var cooldown_sec: float = 2.0

@export_group("Aspecto")
## Proyectil, impacto, grietas, fragmentos y sacudida (el daño lo calcula la receta).
@export var tier: SpellTier
## Orbe que se forma entre las manos y que vuela como proyectil.
@export var visual: SpellVisualDef

@export_group("Sonido")
@export var combine_sfx: AudioStream
## Bucle mientras se carga (sube de tono y volumen con la carga).
@export var charge_loop_sfx: AudioStream
@export var cast_sfx: Array[AudioStream] = []
@export var impact_sfx: Array[AudioStream] = []


## Daño de la combinación según el daño de cada mano y la carga (0..1). Nunca menos de 1.
func damage_for(left_damage: int, right_damage: int, charge: float) -> int:
	var power: float = lerpf(min_power, 1.0, clampf(charge, 0.0, 1.0))
	return maxi(1, roundi(float(left_damage + right_damage) * damage_multiplier * power))


## True si estos dos elementos (en cualquier orden) forman esta receta.
func matches(element_a: StringName, element_b: StringName) -> bool:
	if elements.size() != 2:
		return false
	return (
		(elements[0] == element_a and elements[1] == element_b)
		or (elements[0] == element_b and elements[1] == element_a)
	)
