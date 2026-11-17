extends Node
## Estado de la partida. Envuelve Progression y emite señales por Events.

const BALANCE: BalanceConfig = preload("res://data/balance/default_balance.tres")
## Las mejoras del Grimorio (M1b: una estrella por rama; el orden es el de la constelación).
const UPGRADES: Array[UpgradeNode] = [
	preload("res://data/upgrades/bag.tres"),
	preload("res://data/upgrades/spark_power.tres"),
	preload("res://data/upgrades/channeling.tres"),
	preload("res://data/upgrades/resonance.tres"),
	preload("res://data/upgrades/telekinesis.tres"),
	preload("res://data/upgrades/fireball_power.tres"),
	preload("res://data/upgrades/awaken_frost.tres"),
	preload("res://data/upgrades/frost_power.tres"),
]

var progression: Progression = Progression.new(BALANCE.total_essence)


func hit_crystal(damage: int, at: Vector3) -> int:
	var removed: int = progression.damage_crystal(damage)
	if removed > 0:
		Events.crystal_hit.emit(removed, at)
		Events.essence_changed.emit(progression.essence, progression.total_essence)
		if progression.is_crystal_destroyed():
			Events.crystal_destroyed.emit()
	return removed


## Valor actual de una estadística de mejora (p. ej. &"bag_capacity"), o `fallback`.
func stat(stat_id: StringName, fallback: float = 0.0) -> float:
	for node: UpgradeNode in UPGRADES:
		if node.stat == stat_id:
			return progression.stat_of(node)
	return fallback


func bag_capacity() -> int:
	return roundi(stat(&"bag_capacity", BALANCE.hand_capacity))


func is_bag_full() -> bool:
	return progression.bag_count() >= bag_capacity()


## Recoge un fragmento si cabe. Devuelve false (y avisa) si la bolsa está llena.
func collect_shard(type: ShardType, at: Vector3) -> bool:
	var count: int = progression.collect_shard(type.id, bag_capacity())
	if count == 0:
		Events.bag_full.emit()
		return false
	Events.shard_collected.emit(type, count, at)
	Events.bag_changed.emit(progression.bag_count(), bag_capacity())
	return true


## Saca de la bolsa el fragmento de más valor para entregarlo (el Pilón lo suma al llegar).
## Devuelve su tipo, o null si la bolsa está vacía.
func take_for_delivery() -> ShardType:
	for i: int in range(ShardPool.TYPES.size() - 1, -1, -1):
		var type: ShardType = ShardPool.TYPES[i]
		if progression.take_from_bag(type.id):
			Events.bag_changed.emit(progression.bag_count(), bag_capacity())
			return type
	return null


func deliver(value: int) -> void:
	progression.deliver(value)
	Events.shard_delivered.emit(value)
	Events.mana_changed.emit(progression.mana)
	Events.pylon_changed.emit(progression.pylon_progress, progression.pylon_ratio())


## Llamar cada vez que se lanza una combinación: la primera vez se celebra el descubrimiento.
func register_recipe_cast(recipe: SpellRecipe) -> bool:
	if not progression.discover_recipe(recipe.id):
		return false
	Events.recipe_discovered.emit(recipe)
	return true


func buy_upgrade(node: UpgradeNode) -> bool:
	if not progression.buy_upgrade(node):
		return false
	Events.upgrade_bought.emit(node.id, progression.get_level(node.id))
	Events.mana_changed.emit(progression.mana)
	Events.bag_changed.emit(progression.bag_count(), bag_capacity())
	return true


## Mejora más barata que se puede comprar ahora mismo, o null.
func cheapest_affordable() -> UpgradeNode:
	var best: UpgradeNode = null
	for node: UpgradeNode in UPGRADES:
		if progression.purchase_block(node) == &"":
			var lvl: int = progression.get_level(node.id)
			if (
				best == null
				or node.cost_for_level(lvl) < best.cost_for_level(progression.get_level(best.id))
			):
				best = node
	return best


## Niveles comprados en total (para el rango del mago y la música).
func total_upgrade_levels() -> int:
	var n: int = 0
	for node: UpgradeNode in UPGRADES:
		n += progression.get_level(node.id)
	return n


func reset() -> void:
	progression = Progression.new(BALANCE.total_essence)
	emit_all()


## Reenvía todo el estado (tras cargar partida o al abrir una escena).
func emit_all() -> void:
	Events.essence_changed.emit(progression.essence, progression.total_essence)
	Events.mana_changed.emit(progression.mana)
	Events.pylon_changed.emit(progression.pylon_progress, progression.pylon_ratio())
	Events.bag_changed.emit(progression.bag_count(), bag_capacity())
