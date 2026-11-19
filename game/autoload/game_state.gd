extends Node
## Estado de la partida. Envuelve Progression y emite señales por Events.

const BALANCE: BalanceConfig = preload("res://data/balance/default_balance.tres")
## Las mejoras del Grimorio (M1b: una estrella por rama; el orden es el de la constelación).
const UPGRADES: Array[UpgradeNode] = [
	preload("res://data/upgrades/bag.tres"),
	preload("res://data/upgrades/purity.tres"),
	preload("res://data/upgrades/pylon_resonance.tres"),
	preload("res://data/upgrades/spark_power.tres"),
	preload("res://data/upgrades/channeling.tres"),
	# Nodo hito de la Canalización: mantener pulsado lanza en ráfaga (AutoCast).
	preload("res://data/upgrades/autocast.tres"),
	preload("res://data/upgrades/resonance.tres"),
	# Nodo hito de la Resonancia: los resonantes parten facetas enteras (FacetBreaker).
	preload("res://data/upgrades/facet_break.tres"),
	preload("res://data/upgrades/telekinesis.tres"),
	preload("res://data/upgrades/fireball_power.tres"),
	preload("res://data/upgrades/awaken_frost.tres"),
	preload("res://data/upgrades/frost_power.tres"),
	preload("res://data/upgrades/gears.tres"),
	preload("res://data/upgrades/direct_send.tres"),
	# Nodo hito de la Telequinesis: el remolino que aspira los fragmentos (ManaVortex).
	preload("res://data/upgrades/vortex.tres"),
	preload("res://data/upgrades/double_jump.tres"),
	preload("res://data/upgrades/levitation.tres"),
	preload("res://data/upgrades/crystal_impulse.tres"),
	preload("res://data/upgrades/spark_size.tres"),
	preload("res://data/upgrades/fireball_size.tres"),
	preload("res://data/upgrades/frost_size.tres"),
	preload("res://data/upgrades/thermal_size.tres"),
	preload("res://data/upgrades/thermal_power.tres"),
	preload("res://data/upgrades/awaken_bolt.tres"),
	preload("res://data/upgrades/bolt_power.tres"),
	preload("res://data/upgrades/awaken_earth.tres"),
	preload("res://data/upgrades/earth_power.tres"),
	preload("res://data/upgrades/awaken_arcane.tres"),
	preload("res://data/upgrades/arcane_power.tres"),
	preload("res://data/upgrades/staff.tres"),
	preload("res://data/upgrades/staff_power.tres"),
	preload("res://data/upgrades/staff_focus.tres"),
	preload("res://data/upgrades/familiar.tres"),
	preload("res://data/upgrades/familiar_wings.tres"),
	preload("res://data/upgrades/familiar_caster.tres"),
	# Página del Núcleo: se pagan con Lágrimas del Núcleo (GDD 6.1 y 8).
	preload("res://data/upgrades/core_eye.tres"),
	preload("res://data/upgrades/heart_fracture.tres"),
	preload("res://data/upgrades/grand_convergence.tres"),
	preload("res://data/upgrades/heart_seer.tres"),
]
## Nodo hito del final: al inscribirlo se puede lanzar la Gran Convergencia (GDD 9).
const GRAND_CONVERGENCE: StringName = &"grand_convergence"

## Capas del Cristal Madre, de fuera a dentro (GDD 6).
const LAYERS: Array[CrystalLayerDef] = [
	preload("res://data/crystal/layer_crust.tres"),
	preload("res://data/crystal/layer_geode_mantle.tres"),
	preload("res://data/crystal/layer_resonant_veins.tres"),
	preload("res://data/crystal/layer_crystal_heart.tres"),
	preload("res://data/crystal/layer_core.tres"),
]

## Estadísticas del Espejo del Archimago que se cuentan solas (`Progression.stats`).
## Segundos tras romper el Núcleo hasta la ceremonia de Leyenda.
const LEGEND_DELAY_SEC: float = 5.0
const STAT_SPELLS: StringName = &"spells_cast"
const STAT_SHARDS: StringName = &"shards_collected"
const STAT_MANA: StringName = &"mana_earned"
const STAT_STREAK: StringName = &"best_streak"
const STAT_GEODES: StringName = &"geodes_broken"
const STAT_VEINS: StringName = &"veins_hit"
const STAT_RESONANT: StringName = &"resonant_hits"
const STAT_DELIVERIES: StringName = &"deliveries"

var progression: Progression = Progression.new(BALANCE.total_essence)
## Esencia que guarda el Núcleo (el último 1 %): ningún golpe baja de aquí; sólo la Gran
## Convergencia la rompe (ver EndingDirector).
var core_floor: int:
	get:
		return roundi(float(progression.total_essence) * (1.0 - BALANCE.core_exposed_ratio))
## True con el Núcleo expuesto: el cristal destruido al 99 % (`BalanceConfig.core_exposed_ratio`,
## GDD 9). Desde ahí se ve y se puede inscribir la Gran Convergencia (nodo `grand_convergence`;
## al inscribirlo, `Events.grand_convergence_unlocked` y `has_upgrade(GRAND_CONVERGENCE)`).
var core_exposed: bool:
	get:
		var left: float = float(progression.total_essence) * (1.0 - BALANCE.core_exposed_ratio)
		return float(progression.essence) <= left + 0.5

## Con un menú abierto (título o pausa) no cuenta el tiempo jugado.
var _menu_open: bool = false


func _ready() -> void:
	# Cifras del Espejo y de la pantalla final (en Progression.stats). Los hechizos lanzados los
	# cuenta el SpellCaster (sin los ecos del Arcano); los fragmentos, collect_shard.
	Events.menu_opened.connect(func() -> void: _menu_open = true)
	Events.menu_closed.connect(func() -> void: _menu_open = false)
	Events.streak_changed.connect(
		func(s: int) -> void: progression.stats.record_best(STAT_STREAK, s)
	)
	Events.geode_broken.connect(func(_at: Vector3) -> void: progression.stats.count(STAT_GEODES))
	Events.vein_hit.connect(
		func(_h: SpellHit, _e: StringName) -> void: progression.stats.count(STAT_VEINS)
	)
	Events.spell_impacted.connect(
		func(hit: SpellHit) -> void:
			if hit.resonant and hit.by_player:
				progression.stats.count(STAT_RESONANT)
	)
	# Romper el Núcleo hace Leyenda: su ceremonia entra con la fiesta, tras el estallido y antes
	# de la pantalla final (EndingDirector la abre a los `ending_screen_delay_sec`).
	Events.game_completed.connect(
		func() -> void:
			get_tree().create_timer(LEGEND_DELAY_SEC, false).timeout.connect(_check_rank)
	)


func _process(delta: float) -> void:
	if not _menu_open and not progression.game_complete and not get_tree().paused:
		# Tiempo real (sin hit-stop ni la velocidad de depuración).
		progression.time_played += delta / maxf(Engine.time_scale, 0.01)


## Sube de rango si ya se ha ganado el siguiente (o varios: se celebra el más alto). Se llama al
## entregar, comprar y golpear; no cuesta nada si no hay cambio.
func _check_rank() -> void:
	var r: int = WizardRanks.earned(progression, progression.rank)
	if r <= progression.rank:
		return
	var previous: int = progression.rank
	progression.rank = r
	Events.rank_changed.emit(r, previous)


## Fracción del cristal ya destruida (0..1).
func destroyed_ratio() -> float:
	return 1.0 - float(progression.essence) / float(progression.total_essence)


## Capa más profunda a la que se ha llegado excavando el cristal.
func layer_index() -> int:
	return clampi(progression.deepest_layer, 0, LAYERS.size() - 1)


func current_layer() -> CrystalLayerDef:
	return LAYERS[layer_index()]


func hit_crystal(damage: int, at: Vector3) -> int:
	var exposed: bool = core_exposed
	# El Núcleo no cede: lo que queda de él no lo quita ningún golpe (si el volumen y la cuenta no
	# cuadran del todo, la cuenta se para justo en el 99 %).
	var removed: int = progression.damage_crystal(
		mini(damage, maxi(0, progression.essence - core_floor))
	)
	if removed > 0:
		Events.crystal_hit.emit(removed, at)
		Events.essence_changed.emit(progression.essence, progression.total_essence)
		if not exposed and core_exposed:
			Events.grimoire_final_revealed.emit()
		if progression.is_crystal_destroyed():
			Events.crystal_destroyed.emit()
		_check_rank()
	return removed


## True si la mejora `id` tiene al menos un nivel (p. ej. &"grand_convergence": el hechizo final
## ya se puede lanzar).
func has_upgrade(id: StringName) -> bool:
	return progression.get_level(id) > 0


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
	progression.stats.count(STAT_SHARDS)
	Events.shard_collected.emit(type, count, at)
	Events.bag_changed.emit(progression.bag_count(), bag_capacity())
	return true


## Envío directo (mejora): el fragmento recogido vuela solo a la tolva de la trituradora en vez
## de a la bolsa. Devuelve false si no hay trituradora.
func send_direct(type: ShardType, at: Vector3) -> bool:
	var crusher: CrystalCrusher = (
		get_tree().get_first_node_in_group(&"crystal_crusher") as CrystalCrusher
	)
	if crusher == null:
		return false
	crusher.receive_direct(type, at)
	progression.stats.count(STAT_SHARDS)
	Events.shard_collected.emit(type, 0, at)
	return true


func has_direct_send() -> bool:
	return stat(&"direct_send", 0.0) > 0.5


## Saca de la bolsa el fragmento de más valor para entregarlo (el Pilón lo suma al llegar).
## Devuelve su tipo, o null si la bolsa está vacía.
func take_for_delivery() -> ShardType:
	for i: int in range(ShardPool.ALL_TYPES.size() - 1, -1, -1):
		var type: ShardType = ShardPool.ALL_TYPES[i]
		if progression.take_from_bag(type.id):
			Events.bag_changed.emit(progression.bag_count(), bag_capacity())
			return type
	return null


## Maná que da un fragmento al entregarlo: su valor por la Pureza (GDD 7). Es el único sitio
## donde se aplica el multiplicador. El Pilón suma su valor sin Pureza (lo que perdió el cristal),
## para que el Pilón y el cristal sigan yendo juntos.
## La Cosecha inscrita (RuneBook) también multiplica sólo el maná.
func shard_value(type: ShardType) -> int:
	var mult: float = stat(&"purity_mult", 1.0) * RuneBook.harvest_value(progression)
	return maxi(1, roundi(float(type.value) * mult))


func deliver(value: int, pylon_value: int = -1) -> void:
	var before: float = progression.pylon_ratio()
	progression.deliver(value, pylon_value)
	progression.stats.count(STAT_MANA, maxi(value, 0))
	progression.stats.count(STAT_DELIVERIES)
	Events.shard_delivered.emit(value)
	Events.mana_changed.emit(progression.mana)
	var ratio: float = progression.pylon_ratio()
	Events.pylon_changed.emit(progression.pylon_progress, ratio)
	# Hitos del Pilón: cada marca tallada se celebra una vez (el Pilón nunca baja).
	for i: int in ManaPylon.MARKS.size():
		if not ManaPylon.mark_reached(before, i) and ManaPylon.mark_reached(ratio, i):
			Events.pylon_milestone.emit(i, ManaPylon.MARKS[i])
	_check_rank()


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
	if node.pays_with_tears():
		Events.tears_changed.emit(progression.tears)
	if node.id == GRAND_CONVERGENCE:
		Events.grand_convergence_unlocked.emit()
	_check_rank()
	return true


## Mejora más barata que se puede comprar ahora mismo, o null. Los costes en Lágrimas no se
## comparan con los de maná: una estrella del Núcleo pagable que aún no se ha visto va primero (es
## rara); si ya se vio, sólo sale cuando no hay nada de maná que comprar.
func cheapest_affordable() -> UpgradeNode:
	var best: UpgradeNode = null
	var tear_node: UpgradeNode = null
	for node: UpgradeNode in UPGRADES:
		if progression.purchase_block(node) != &"":
			continue
		var lvl: int = progression.get_level(node.id)
		if node.pays_with_tears():
			if progression.seen_upgrades.get(node.id, -1) < lvl:
				return node
			if tear_node == null:
				tear_node = node
		elif (
			best == null
			or node.cost_for_level(lvl) < best.cost_for_level(progression.get_level(best.id))
		):
			best = node
	return best if best else tear_node


## Niveles comprados en total (objetos del Santuario, guía y Espejo).
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
	Events.tears_changed.emit(progression.tears)
