class_name Guidance
extends RefCounted
## Reglas puras de la guía (sin nodos ni autoloads, se prueban solas):
## - adónde hay que ir ahora (`pick`): cristal, fragmentos, trituradora o Santuario, según el
##   tutorial, la bolsa, la tolva y las mejoras nuevas que se pueden pagar;
## - si ese objetivo es urgente (`is_urgent`): marcador grande con estela en el suelo, o discreto;
## - cuánto se explica una tecla (`prompt_mode`): entera las primeras veces, luego un icono y al
##   final nada, para no repetir lo que el jugador ya sabe.
## La usa `ObjectiveGuide` (ui/guide/) cada fotograma con un `Situation` reutilizado.

## Objetivos de la guía.
enum Kind { NONE, CRYSTAL, SHARD, CRUSHER, SANCTUM }
## Fase del tutorial que importa a la guía (traducida desde `Tutorial.Step` por quien llama).
enum Phase { DONE, DOOR, CAST, PICKUP, CRUSH, EARN, BUY }
## Cómo se enseña una tecla: texto entero, icono pequeño o nada.
enum Prompt { FULL, ICON, NONE }


## Lo que la guía necesita saber de la partida. Se rellena y se reutiliza (sin asignaciones).
class Situation:
	extends RefCounted
	var phase: int = Phase.DONE
	var bag: int = 0
	var capacity: int = 1
	var hopper: int = 0
	var crushing: bool = false
	## Envío directo (los fragmentos van solos a la tolva): la bolsa no se llena.
	var direct_send: bool = false
	## Hay un fragmento suelto cerca (`GuidanceDef.shard_radius_m`).
	var shard_near: bool = false
	## Hay una mejora pagable que el jugador aún no ha visto en el Grimorio.
	var new_upgrade: bool = false
	## Ya sabe recoger (no hace falta llevarlo a cada fragmento).
	var pickup_learned: bool = false
	## Hay familiares recolectores: ellos tiran de la palanca cuando la tolva tiene bastante.
	var auto_lever: bool = false

	func bag_full() -> bool:
		return not direct_send and bag >= capacity

	## Echó cristales a la tolva y se fue sin tirar de la palanca. Con envío directo la tolva se
	## llena sola al recoger: sólo se le recuerda cuando ya no queda nada que recoger cerca.
	func lever_forgotten() -> bool:
		if hopper <= 0 or bag > 0 or crushing or auto_lever:
			return false
		return not (direct_send and shard_near)


## Adónde guiar ahora.
static func pick(s: Situation) -> int:
	match s.phase:
		Phase.DOOR:
			return Kind.NONE
		Phase.CAST:
			return Kind.CRYSTAL
		Phase.PICKUP:
			return Kind.SHARD if s.shard_near else Kind.CRYSTAL
		Phase.BUY:
			return Kind.SANCTUM
		Phase.CRUSH:
			if s.bag > 0 or s.hopper > 0 or s.crushing:
				return Kind.CRUSHER
			return Kind.SHARD if s.shard_near else Kind.CRYSTAL
		Phase.EARN:
			if s.bag_full() or (s.bag > 0 and not s.shard_near):
				return Kind.CRUSHER
			if s.lever_forgotten():
				return Kind.CRUSHER
			if s.shard_near:
				return Kind.SHARD
			return Kind.CRYSTAL
	# Partida normal: lo urgente primero; si no hay nada que hacer fuera del cristal, nada.
	if s.bag_full():
		return Kind.CRUSHER
	if s.new_upgrade:
		return Kind.SANCTUM
	if s.lever_forgotten():
		return Kind.CRUSHER
	if s.bag > 0 and not s.shard_near:
		return Kind.CRUSHER
	if s.shard_near and not s.pickup_learned:
		return Kind.SHARD
	return Kind.NONE


## Urgente: marcador grande con etiqueta y estela en el suelo. Si no, discreto (sólo distancia).
static func is_urgent(kind: int, s: Situation) -> bool:
	if kind == Kind.NONE:
		return false
	if s.phase != Phase.DONE:
		return true
	match kind:
		Kind.CRUSHER:
			return s.bag_full() or s.lever_forgotten()
		Kind.SANCTUM:
			return true
	return false


## Cuánto se explica una acción que ya se ha hecho `times` veces.
static func prompt_mode(times: int, learn_at: int, forget_at: int) -> int:
	if times < learn_at:
		return Prompt.FULL
	if times < forget_at:
		return Prompt.ICON
	return Prompt.NONE
