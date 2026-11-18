class_name Progression
extends RefCounted
## Reglas puras del progreso. Sin nodos ni escenas: se puede testear de forma aislada.
##
## - essence: lo que le queda al Cristal Madre. Sólo baja.
## - pylon_progress: total entregado al Pilón. Sólo sube. Es la barra de victoria.
## - mana: moneda gastable. Entregar suma a pylon_progress Y a mana.

var total_essence: int
var essence: int
var pylon_progress: int = 0
var mana: int = 0
var upgrade_levels: Dictionary[StringName, int] = {}
## Fragmentos recogidos y aún no entregados, por tipo (id de ShardType).
var bag: Dictionary[StringName, int] = {}
## Combinaciones de hechizos ya descubiertas (ids de SpellRecipe), en orden de descubrimiento.
var discovered_recipes: Array[StringName] = []
## Capa más profunda a la que se ha llegado excavando (0 = Corteza). Sólo sube.
var deepest_layer: int = 0
## Estado de cada geoda del Manto (índice en el volumen horneado): 1 = abierta, 2 = reventada.
var geodes: Dictionary[int, int] = {}
## La puerta de la casucha ya se abrió (el cristal ya se ha visto).
var hut_door_open: bool = false
## Paso del tutorial del principio (ver Tutorial.Step; 8 = terminado).
var tutorial_step: int = 0
## Veces que el jugador ya ha hecho cada acción con su tecla (recoger, echar a la tolva, palanca,
## abrir el Grimorio...). Con eso el HUD deja de repetir instrucciones que ya se saben.
var learned: Dictionary[StringName, int] = {}
## Mejoras pagables que el jugador ya ha visto en el Grimorio: id -> nivel que se ofrecía. La
## guía sólo lleva al Santuario por las que no ha visto (también tras volver a cargar).
var seen_upgrades: Dictionary[StringName, int] = {}
## Lágrimas del Núcleo (GDD 6.1): segunda moneda, sólo cae en el Corazón Cristalino y paga los
## nodos finales del Grimorio. `tears` es lo que hay para gastar; `tears_total`, las recogidas.
var tears: int = 0
var tears_total: int = 0
## Segundos de buen juego en el Corazón desde la última Lágrima (ver TearDrops): si llegan al
## tope, la siguiente sale seguro. Se guarda para que salir del juego no lo reinicie.
var tear_pity: float = 0.0
## Lágrimas que han caído y siguen flotando (posiciones globales): al volver a cargar, siguen ahí.
var loose_tears: PackedVector3Array = PackedVector3Array()
## Depuración ("comprar todo"): compra también lo que aún no se ve (la Gran Convergencia).
var reveal_all: bool = false
## Bichos del valle reventados (critters/).
var critters_popped: int = 0
## El final (GDD 9): la Gran Convergencia rompió el Núcleo. Al volver a cargar, el valle celebra.
var game_complete: bool = false
## Ya se vio la pantalla final (si se sale durante la fiesta, sale al volver a cargar).
var ending_seen: bool = false
## Estadísticas de la pantalla final: segundos jugados (sin menús ni pausa; se paran al acabar),
## hechizos lanzados (sueltos y combinados) y fragmentos recogidos.
var time_played: float = 0.0
var spells_cast: int = 0
var shards_collected: int = 0


func _init(p_total_essence: int) -> void:
	total_essence = p_total_essence
	essence = p_total_essence


## Aplica daño al cristal. Devuelve la esencia realmente arrancada (nunca más de la que queda).
func damage_crystal(amount: int) -> int:
	var removed: int = clampi(amount, 0, essence)
	essence -= removed
	return removed


## Entrega fragmentos al Pilón: `value` de maná y `pylon_value` de progreso del Pilón (-1 = el
## mismo). El Pilón nunca pasa de la esencia total; el maná sí (los bonus de valor pueden
## adelantar un poco el Pilón al cristal y no hay que dejar al jugador sin comprar).
func deliver(value: int, pylon_value: int = -1) -> void:
	var v: int = maxi(value, 0)
	var pv: int = v if pylon_value < 0 else maxi(pylon_value, 0)
	pylon_progress = mini(pylon_progress + pv, total_essence)
	mana += v


## Guarda en la bolsa un fragmento recogido del suelo. Con `capacity` >= 0 no se pasa de ahí:
## devuelve 0 si la bolsa está llena; si no, cuántos hay ya de ese tipo.
func collect_shard(type_id: StringName, capacity: int = -1) -> int:
	if capacity >= 0 and bag_count() >= capacity:
		return 0
	bag[type_id] = bag.get(type_id, 0) + 1
	return bag[type_id]


## Fragmentos en la bolsa, de todos los tipos.
func bag_count() -> int:
	var n: int = 0
	for k: StringName in bag:
		n += bag[k]
	return n


## Saca un fragmento de ese tipo de la bolsa (para entregarlo). False si no había.
func take_from_bag(type_id: StringName) -> bool:
	var n: int = bag.get(type_id, 0)
	if n <= 0:
		return false
	bag[type_id] = n - 1
	return true


## Valor actual de la estadística de una mejora (según su nivel comprado).
func stat_of(node: UpgradeNode) -> float:
	return node.value_at(get_level(node.id))


## Registra una combinación lanzada. Devuelve true sólo la primera vez (descubrimiento).
func discover_recipe(recipe_id: StringName) -> bool:
	if recipe_id == &"" or discovered_recipes.has(recipe_id):
		return false
	discovered_recipes.append(recipe_id)
	return true


func can_afford(cost: int) -> bool:
	return mana >= cost


func spend(cost: int) -> bool:
	if cost < 0 or not can_afford(cost):
		return false
	mana -= cost
	return true


## Si la estrella ya se ve: las que piden el cristal destruido a cierta fracción (la Gran
## Convergencia, con el Núcleo expuesto) están ocultas hasta entonces. Medio punto de esencia de
## margen: al 99 % justo ya se ve.
func is_revealed(node: UpgradeNode) -> bool:
	if reveal_all or node.reveal_destroyed_ratio <= 0.0:
		return true
	return float(essence) <= float(total_essence) * (1.0 - node.reveal_destroyed_ratio) + 0.5


func get_level(upgrade_id: StringName) -> int:
	return upgrade_levels.get(upgrade_id, 0)


## Por qué no se puede comprar (o &"" si se puede): &"max", &"hidden" (aún no se ve),
## &"locked", &"mana" o &"tears" (faltan Lágrimas).
func purchase_block(node: UpgradeNode) -> StringName:
	var level: int = get_level(node.id)
	if level >= node.get_max_level():
		return &"max"
	if not is_revealed(node):
		return &"hidden"
	for req: StringName in node.prerequisites:
		if not _has_requirement(req):
			return &"locked"
	var funds: int = tears if node.pays_with_tears() else mana
	if funds < node.cost_for_level(level):
		return &"tears" if node.pays_with_tears() else &"mana"
	return &""


## Una mejora comprada, o "recipe:<id>": una combinación ya descubierta.
func _has_requirement(req: StringName) -> bool:
	var r: String = req
	if r.begins_with("recipe:"):
		return discovered_recipes.has(StringName(r.trim_prefix("recipe:")))
	return get_level(req) > 0


func buy_upgrade(node: UpgradeNode) -> bool:
	if purchase_block(node) != &"":
		return false
	var level: int = get_level(node.id)
	var cost: int = node.cost_for_level(level)
	if node.pays_with_tears():
		tears -= cost
	elif not spend(cost):
		return false
	upgrade_levels[node.id] = level + 1
	return true


func pylon_ratio() -> float:
	return float(pylon_progress) / float(total_essence)


## Suma una vez la acción `key` (ver `learned`) y devuelve cuántas van.
func learn(key: StringName) -> int:
	var n: int = learned.get(key, 0) + 1
	learned[key] = n
	return n


## Cuántas veces se ha hecho la acción `key`.
func times(key: StringName) -> int:
	return learned.get(key, 0)


func is_crystal_destroyed() -> bool:
	return essence <= 0


func to_dict() -> Dictionary:
	return {
		"essence": essence,
		"pylon_progress": pylon_progress,
		"mana": mana,
		"upgrade_levels": upgrade_levels.duplicate(),
		"bag": bag.duplicate(),
		"discovered_recipes": discovered_recipes.map(func(r: StringName) -> String: return str(r)),
		"deepest_layer": deepest_layer,
		"geodes": geodes.duplicate(),
		"hut_door_open": hut_door_open,
		"tutorial_step": tutorial_step,
		"learned": learned.duplicate(),
		"seen_upgrades": seen_upgrades.duplicate(),
		"tears": tears,
		"tears_total": tears_total,
		"tear_pity": tear_pity,
		"loose_tears": _vec_list(loose_tears),
		"critters_popped": critters_popped,
		"game_complete": game_complete,
		"ending_seen": ending_seen,
		"time_played": time_played,
		"spells_cast": spells_cast,
		"shards_collected": shards_collected,
	}


func load_dict(data: Dictionary) -> void:
	essence = clampi(int(data.get("essence", total_essence)), 0, total_essence)
	pylon_progress = clampi(int(data.get("pylon_progress", 0)), 0, total_essence)
	mana = maxi(int(data.get("mana", 0)), 0)
	upgrade_levels.clear()
	var levels: Dictionary = data.get("upgrade_levels", {})
	for key: Variant in levels:
		upgrade_levels[StringName(str(key))] = int(levels[key])
	bag.clear()
	var saved_bag: Dictionary = data.get("bag", {})
	for key: Variant in saved_bag:
		bag[StringName(str(key))] = maxi(int(saved_bag[key]), 0)
	deepest_layer = maxi(int(data.get("deepest_layer", 0)), 0)
	hut_door_open = bool(data.get("hut_door_open", false))
	tutorial_step = int(data.get("tutorial_step", 8 if pylon_progress > 0 else 0))
	critters_popped = maxi(int(data.get("critters_popped", 0)), 0)
	game_complete = bool(data.get("game_complete", false))
	ending_seen = bool(data.get("ending_seen", game_complete))
	time_played = maxf(float(data.get("time_played", 0.0)), 0.0)
	spells_cast = maxi(int(data.get("spells_cast", 0)), 0)
	shards_collected = maxi(int(data.get("shards_collected", 0)), 0)
	learned.clear()
	var saved_learned: Dictionary = data.get("learned", {})
	for key: Variant in saved_learned:
		learned[StringName(str(key))] = maxi(int(saved_learned[key]), 0)
	seen_upgrades.clear()
	var saved_seen: Dictionary = data.get("seen_upgrades", {})
	for key: Variant in saved_seen:
		seen_upgrades[StringName(str(key))] = maxi(int(saved_seen[key]), 0)
	tears = maxi(int(data.get("tears", 0)), 0)
	tears_total = maxi(int(data.get("tears_total", tears)), tears)
	tear_pity = maxf(float(data.get("tear_pity", 0.0)), 0.0)
	loose_tears.clear()
	var saved_loose: Array = data.get("loose_tears", [])
	for v: Variant in saved_loose:
		var xyz: Array = v if v is Array else []
		if xyz.size() == 3:
			loose_tears.append(Vector3(float(xyz[0]), float(xyz[1]), float(xyz[2])))
	geodes.clear()
	var saved_geodes: Dictionary = data.get("geodes", {})
	for key: Variant in saved_geodes:
		geodes[int(str(key))] = int(saved_geodes[key])
	discovered_recipes.clear()
	var saved_recipes: Array = data.get("discovered_recipes", [])
	for r: Variant in saved_recipes:
		discover_recipe(StringName(str(r)))


static func _vec_list(points: PackedVector3Array) -> Array:
	var out: Array = []
	for p: Vector3 in points:
		out.append([p.x, p.y, p.z])
	return out
