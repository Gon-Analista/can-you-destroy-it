class_name SpellRecipe
extends Resource
## Combinación de elementos que produce un hechizo (p. ej. Chispa + Chispa = Bola de Fuego).
## Se lanza pulsando las dos manos a la vez y manteniendo para cargar (GDD 5.2 y 10.1).
## También describe las reacciones (un elemento sobre la huella de otro en el cristal): ésas no se
## lanzan, se descubren al provocarlas (`is_reaction`).

## Cómo llega al cristal:
## FRONT: proyectil desde las manos. SKY: círculos en el cielo sobre el blanco y cae desde arriba
## (Meteoro, Trueno). RAIN: lluvia desde el cielo sobre una zona. LANCE: perfora un túnel hondo.
## BEAM: rayo continuo que sigue la mirilla. GROUND: onda por el suelo que hace estallar la base.
## MAGNET: utilidad, atrae los fragmentos. GRAVITY: pozo de gravedad que se traga en espiral
## todos los fragmentos sueltos del valle. RESONANCE: golpe que hace vibrar el cristal entero y
## deja unos segundos en los que todo golpe es resonante.
## STORM (triple): una nube de tormenta sobre el blanco que descarga rayos, granizo y fuego
## durante `storm_sec`. NOVA (triple): una estrella vuela al blanco, se contrae y estalla.
## Los Ecos no son una entrega: usan la de la receta que repiten (`echo_of`).
enum Delivery { FRONT, SKY, RAIN, LANCE, BEAM, GROUND, MAGNET, GRAVITY, RESONANCE, STORM, NOVA }

@export var id: StringName
@export var display_name: String
## Qué hace (Libro de Combinaciones, cuando ya se ha descubierto).
@export_multiline var description: String
## Pista antes de descubrirla (un acertijo).
@export var riddle: String
## Reacción: no se lanza; se descubre al golpear con un elemento la huella de otro.
@export var is_reaction: bool = false
@export var delivery: Delivery = Delivery.FRONT
## Ids de ElementDef. El orden no importa. Dos: pareja (las manos); tres: combinación triple
## (las dos manos y el báculo, GDD 5.2).
@export var elements: Array[StringName] = []
## Daño = (daño mano izquierda + daño mano derecha [+ daño del báculo]) x multiplicador x
## potencia de la carga.
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
## Mejora de Potencia que da su nivel (1 + nivel comprado, hasta 10); vacía = siempre nivel 1.
@export var power_upgrade: StringName

@export_group("Entrega")
## SKY / RAIN: altura (m) sobre el blanco de la que cae y donde se abren los círculos.
@export var sky_height: float = 40.0
## SKY: segundos de caída desde el cielo.
@export var fall_sec: float = 1.0
## Círculos mágicos (en el cielo para SKY/RAIN) a nivel 1; suben con el nivel.
@export var sky_circles: int = 3
## RAIN: proyectiles que caen y radio de la zona (m).
@export var rain_count: int = 0
@export var rain_radius: float = 4.0
## RAIN: elemento de cada golpe de la lluvia (vacío = Escarcha, las estalactitas).
@export var strike_element: StringName
## LANCE: profundidad del túnel (m); `freeze_trail` congela las paredes.
@export var pierce_depth: float = 0.0
@export var freeze_trail: bool = false
## Rayos que saltan del impacto a otros puntos del cristal.
@export var chain_count: int = 0
## BEAM: segundos que dura el haz.
@export var beam_sec: float = 0.0
## Fragmentos un tamaño más grandes (Tierra, Lanza Cargada).
@export var shard_bonus: int = 0
## Color de sus círculos mágicos.
@export var circle_color: Color = Color(1.0, 0.6, 0.2)
@export var circle_hot: Color = Color(1.0, 0.95, 0.75)

@export_group("Arcano")
## Eco de X (GDD 5.2): id de la receta que repite. Sale X como siempre (con este aspecto) y
## después `echo_count` copias fantasma, una cada `echo_delay` s, con `echo_damage` del daño y
## saliendo de círculos arcanos. Vacío = no es un eco.
@export var echo_of: StringName
@export var echo_count: int = 0
@export var echo_delay: float = 0.3
@export_range(0.0, 1.0) var echo_damage: float = 0.6
@export var echo_sfx: Array[AudioStream] = []
## RESONANCE: segundos en los que cada golpe es resonante y cuánto tarda en poder repetirse
## desde que se lanzó.
@export var buff_sec: float = 0.0
@export var buff_lockout_sec: float = 0.0
## GRAVITY: segundos hasta que el pozo se cierra (los fragmentos tardan eso en llegar).
@export var gravity_sec: float = 2.5

@export_group("Triples")
## STORM: segundos que dura la tormenta, cada cuánto descarga y radio de la zona (m). Las
## descargas se reparten el daño y van por turno por sus elementos (rayo, granizo, fuego).
## Sólo puede haber una: `buff_lockout_sec` es lo que tarda en poder repetirse.
@export var storm_sec: float = 0.0
@export var storm_interval: float = 0.5
@export var storm_radius: float = 7.0
## NOVA: segundos que la estrella se contrae en el blanco antes de estallar.
@export var nova_sec: float = 0.0

@export_group("Carga")
## Tiempo manteniendo las dos manos juntas hasta la carga completa (s).
@export var charge_sec: float = 0.7
## Potencia si se suelta nada más juntar las manos (con carga completa es 1).
@export_range(0.0, 1.0) var min_power: float = 0.5
## Cuánto premia cargarlo a tope (`BalanceConfig.full_charge_bonus_by_level`): 1 = se carga (cada
## círculo multiplica el daño, a nivel 11 hasta x6); 0 = de toque (sale casi entero sin cargar y
## cargarlo no da más que la potencia de siempre). Ver `ChargeStages.bonus`.
@export_range(0.0, 1.0) var charge_payoff: float = 1.0
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


## Daño de la combinación según el daño de cada mano (y del báculo, en las triples) y la carga
## (0..1). Nunca menos de 1.
## `bonus`: el premio de la carga (`ChargeStages.bonus`, 1 = ninguno).
func damage_for(
	left_damage: int, right_damage: int, charge: float, staff_damage: int = 0, bonus: float = 1.0
) -> int:
	var power: float = lerpf(min_power, 1.0, clampf(charge, 0.0, 1.0)) * maxf(bonus, 1.0)
	var total: int = left_damage + right_damage + (staff_damage if is_triple() else 0)
	return maxi(1, roundi(float(total) * damage_multiplier * power))


## True si sale mejor de toque que cargado (lo dice el Libro de Combinaciones).
func is_tap_spell() -> bool:
	return charge_payoff < 0.5 and min_power >= 0.75


## Combinación triple: dos manos y el báculo.
func is_triple() -> bool:
	return elements.size() == 3 and not is_reaction


## True si estos tres elementos (en cualquier orden, con repeticiones) forman esta triple.
func matches_triple(element_a: StringName, element_b: StringName, element_c: StringName) -> bool:
	if not is_triple():
		return false
	var want: Array[StringName] = elements.duplicate()
	for e: StringName in [element_a, element_b, element_c]:
		var at: int = want.find(e)
		if at < 0:
			return false
		want.remove_at(at)
	return true


## True si estos dos elementos (en cualquier orden) forman esta receta.
func matches(element_a: StringName, element_b: StringName) -> bool:
	if is_reaction or elements.size() != 2:
		return false
	return (
		(elements[0] == element_a and elements[1] == element_b)
		or (elements[0] == element_b and elements[1] == element_a)
	)
