extends Node
## Estado de la partida. Envuelve Progression y emite señales por Events.

const BALANCE: BalanceConfig = preload("res://data/balance/default_balance.tres")

var progression: Progression = Progression.new(BALANCE.total_essence)


func hit_crystal(damage: int, at: Vector3) -> int:
	var removed: int = progression.damage_crystal(damage)
	if removed > 0:
		Events.crystal_hit.emit(removed, at)
		Events.essence_changed.emit(progression.essence, progression.total_essence)
		if progression.is_crystal_destroyed():
			Events.crystal_destroyed.emit()
	return removed


func deliver(value: int) -> void:
	progression.deliver(value)
	Events.shard_delivered.emit(value)
	Events.mana_changed.emit(progression.mana)
	Events.pylon_changed.emit(progression.pylon_progress, progression.pylon_ratio())


func collect_shard(type: ShardType, at: Vector3) -> void:
	var count: int = progression.collect_shard(type.id)
	Events.shard_collected.emit(type, count, at)


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
	return true


func reset() -> void:
	progression = Progression.new(BALANCE.total_essence)
	emit_all()


## Reenvía todo el estado (tras cargar partida o al abrir una escena).
func emit_all() -> void:
	Events.essence_changed.emit(progression.essence, progression.total_essence)
	Events.mana_changed.emit(progression.mana)
	Events.pylon_changed.emit(progression.pylon_progress, progression.pylon_ratio())
