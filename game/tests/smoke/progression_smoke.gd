extends SceneTree
## Test rápido sin addons de las reglas de Progression. Sustituir por gdUnit4 cuando se integre.
## godot --headless --path game --script res://tests/smoke/progression_smoke.gd

var _failures: int = 0


func _init() -> void:
	var p := Progression.new(1000)
	_check(p.damage_crystal(5) == 5, "daño normal")
	_check(p.essence == 995, "esencia baja")
	_check(p.damage_crystal(5000) == 995, "el daño no pasa de la esencia restante")
	_check(p.is_crystal_destroyed(), "cristal destruido")

	p = Progression.new(1000)
	p.deliver(10)
	_check(p.pylon_progress == 10 and p.mana == 10, "entregar suma a Pilón y maná")
	_check(p.spend(4) and p.mana == 6 and p.pylon_progress == 10, "gastar no baja el Pilón")
	_check(not p.spend(100), "no se gasta lo que no hay")
	p.deliver(5000)
	_check(p.pylon_progress == 1000, "el Pilón no pasa del total")

	var node := UpgradeNode.new()
	node.id = &"spark_power"
	node.base_cost = 5
	node.max_level = 2
	p = Progression.new(1000)
	p.deliver(5)
	_check(p.buy_upgrade(node) and p.get_level(&"spark_power") == 1, "comprar mejora")
	_check(not p.buy_upgrade(node), "sin maná no se compra")

	p.collect_shard(&"splinter")
	_check(
		p.collect_shard(&"splinter") == 2 and p.bag[&"splinter"] == 2, "la bolsa cuenta por tipo"
	)

	_check(p.discover_recipe(&"fireball"), "primera Bola de Fuego: descubrimiento")
	_check(not p.discover_recipe(&"fireball"), "la segunda vez ya no es descubrimiento")

	var bag := Progression.new(1000)
	_check(bag.collect_shard(&"splinter", 1) == 1, "con capacidad 1 cabe uno")
	_check(bag.collect_shard(&"shard", 1) == 0, "la bolsa llena no acepta más")
	_check(bag.bag_count() == 1, "la bolsa cuenta todos los tipos")
	_check(bag.take_from_bag(&"splinter") and bag.bag_count() == 0, "entregar saca de la bolsa")
	_check(not bag.take_from_bag(&"splinter"), "no se saca lo que no hay")

	var bag_node: UpgradeNode = load("res://data/upgrades/bag.tres")
	_check(bag.stat_of(bag_node) == 5.0, "sin comprar, la bolsa lleva 5")
	_check(bag.purchase_block(bag_node) == &"mana", "sin maná no se puede")
	bag.deliver(15)
	_check(bag.buy_upgrade(bag_node) and bag.stat_of(bag_node) == 15.0, "la bolsa sube a 15")
	_check(bag_node.cost_for_level(1) == 45, "el coste sale del .tres")
	var tk: UpgradeNode = load("res://data/upgrades/telekinesis.tres")
	var fresh := Progression.new(1000)
	fresh.deliver(100)
	_check(fresh.purchase_block(tk) == &"locked", "la telequinesis pide la bolsa")
	for i: int in 3:
		bag.deliver(10000)
		bag.buy_upgrade(bag_node)
	_check(bag.purchase_block(bag_node) == &"max", "no se pasa del último nivel")

	var fb: UpgradeNode = load("res://data/upgrades/fireball_power.tres")
	var fresh_fb := Progression.new(1000)
	fresh_fb.deliver(500)
	_check(
		fresh_fb.purchase_block(fb) == &"locked", "la mejora de la Bola de Fuego pide descubrirla"
	)
	fresh_fb.discover_recipe(&"fireball")
	_check(fresh_fb.buy_upgrade(fb), "descubierta, ya se puede comprar")

	var restored := Progression.new(1000)
	restored.load_dict(p.to_dict())
	_check(restored.to_dict() == p.to_dict(), "guardar y cargar conserva el estado")

	_check(
		restored.discovered_recipes == ([&"fireball"] as Array[StringName]),
		"las combinaciones descubiertas se guardan"
	)

	var recipe := SpellRecipe.new()
	recipe.elements = [&"spark", &"spark"] as Array[StringName]
	recipe.damage_multiplier = 2.5
	recipe.min_power = 0.4
	_check(recipe.matches(&"spark", &"spark"), "Chispa + Chispa forma la receta")
	_check(not recipe.matches(&"spark", &"frost"), "Chispa + Escarcha no")
	_check(recipe.damage_for(1, 1, 1.0) == 5, "carga completa: (1 + 1) x 2,5")
	_check(recipe.damage_for(1, 1, 0.0) == 2, "sin carga: potencia mínima")
	_check(recipe.damage_for(0, 0, 0.0) == 1, "nunca menos de 1")

	# Fragmentos por valor del daño (ShardPool.pieces_for): el maná que suelta un golpe cuadra con
	# la esencia que quita, con pocas piezas y más grandes cuanto más fuerte.
	for dmg: int in [1, 2, 7, 11, 49, 50, 333, 999, 1000, 4321, 12000]:
		var pieces: Array[Vector2i] = ShardPool.pieces_for(float(dmg))
		var worth: int = 0
		var count: int = 0
		for pc: Vector2i in pieces:
			worth += ShardPool.TYPES[pc.x].value * pc.y
			count += pc.y
		_check(worth <= dmg, "un golpe de %d no da más de lo que vale" % dmg)
		_check(
			worth >= dmg * 0.75 or dmg < 4,
			"un golpe de %d da casi todo su valor (%d)" % [dmg, worth]
		)
		_check(
			count <= 2 * ShardPool.MAX_PIECES + ShardPool.MAX_EXTRA, "piezas acotadas (%d)" % dmg
		)
	_check(
		ShardPool.pieces_for(1.0) == ([Vector2i(0, 1)] as Array[Vector2i]), "1 de daño: una astilla"
	)
	_check(ShardPool.pieces_for(60.0)[0].x == 2, "60 de daño: fragmentos grandes")

	var streak := StreakTracker.new(2.0)
	_check(streak.register_hit(0.0) == 1, "primer golpe: racha 1")
	_check(streak.register_hit(1.5) == 2, "golpe dentro de la ventana suma racha")
	_check(not streak.expire(3.0), "la racha sigue viva dentro de la ventana")
	_check(streak.expire(3.6) and streak.streak == 0, "la racha caduca fuera de la ventana")
	_check(streak.register_hit(10.0) == 1, "tras caducar se empieza de nuevo")

	# Nivel 11 (Ascensión): la última compra de Potencia espera a que el cristal esté casi roto.
	var apex := Progression.new(1000)
	var power: UpgradeNode = load("res://data/upgrades/spark_power.tres")
	apex.upgrade_levels[power.id] = power.get_max_level() - 1
	apex.mana = 10_000_000
	_check(apex.purchase_block(power) == &"apex", "Ascensión: espera con el cristal entero")
	apex.essence = 150
	_check(apex.purchase_block(power) == &"", "Ascensión: se abre con el cristal al 85 %")

	# Cargar a tope vale la pena (y más a nivel 11); los hechizos "de toque" no premian la carga.
	var bal: BalanceConfig = load("res://data/balance/default_balance.tres")
	var table: PackedFloat32Array = bal.full_charge_bonus_by_level
	_check(table.size() == 11, "premio de carga: uno por nivel")
	_check(ChargeStages.full_bonus(11, table, 1.0) >= 10.0, "nivel 11 cargado: x10 o más")
	_check(is_equal_approx(ChargeStages.full_bonus(11, table, 0.0), 1.0), "de toque: sin premio")
	_check(is_equal_approx(ChargeStages.bonus(0.0, 10.0), 1.0), "sin cargar: sin premio")
	var fireball: SpellRecipe = load("res://data/spells/recipe_fireball.tres")
	var lance: SpellRecipe = load("res://data/spells/recipe_ice_lance.tres")
	_check(not fireball.is_tap_spell(), "la Bola de Fuego se carga")
	_check(lance.is_tap_spell(), "la Lanza de Hielo es de toque")

	print("progression_smoke: %s" % ("OK" if _failures == 0 else "%d fallos" % _failures))
	quit(1 if _failures > 0 else 0)


func _check(cond: bool, label: String) -> void:
	if not cond:
		_failures += 1
		printerr("FALLO: " + label)
