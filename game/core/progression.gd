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


func _init(p_total_essence: int) -> void:
	total_essence = p_total_essence
	essence = p_total_essence


## Aplica daño al cristal. Devuelve la esencia realmente arrancada (nunca más de la que queda).
func damage_crystal(amount: int) -> int:
	var removed: int = clampi(amount, 0, essence)
	essence -= removed
	return removed


## Entrega fragmentos al Pilón. El progreso del Pilón nunca supera la esencia total.
func deliver(value: int) -> void:
	var accepted: int = clampi(value, 0, total_essence - pylon_progress)
	pylon_progress += accepted
	mana += accepted


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


func get_level(upgrade_id: StringName) -> int:
	return upgrade_levels.get(upgrade_id, 0)


## Por qué no se puede comprar (o &"" si se puede): &"max", &"locked" o &"mana".
func purchase_block(node: UpgradeNode) -> StringName:
	var level: int = get_level(node.id)
	if level >= node.get_max_level():
		return &"max"
	for req: StringName in node.prerequisites:
		if not _has_requirement(req):
			return &"locked"
	if not can_afford(node.cost_for_level(level)):
		return &"mana"
	return &""


## Una mejora comprada, o "recipe:<id>": una combinación ya descubierta.
func _has_requirement(req: StringName) -> bool:
	var r: String = req
	if r.begins_with("recipe:"):
		return discovered_recipes.has(StringName(r.trim_prefix("recipe:")))
	return get_level(req) > 0


func buy_upgrade(node: UpgradeNode) -> bool:
	var level: int = get_level(node.id)
	if level >= node.get_max_level():
		return false
	for req: StringName in node.prerequisites:
		if not _has_requirement(req):
			return false
	if not spend(node.cost_for_level(level)):
		return false
	upgrade_levels[node.id] = level + 1
	return true


func pylon_ratio() -> float:
	return float(pylon_progress) / float(total_essence)


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
	geodes.clear()
	var saved_geodes: Dictionary = data.get("geodes", {})
	for key: Variant in saved_geodes:
		geodes[int(str(key))] = int(saved_geodes[key])
	discovered_recipes.clear()
	var saved_recipes: Array = data.get("discovered_recipes", [])
	for r: Variant in saved_recipes:
		discover_recipe(StringName(str(r)))
