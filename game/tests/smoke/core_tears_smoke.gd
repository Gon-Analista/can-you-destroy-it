extends SceneTree
## Lágrimas del Núcleo (GDD 6.1):
## - la probabilidad va con el daño y tiene tope; la piedad da una seguro tras `tear_pity_sec` de
##   buen juego (pasear no cuenta) y con el Núcleo expuesto el Núcleo llora si faltan;
## - sólo brotan de combinados en el Corazón Cristalino (no en otras capas ni de golpes sueltos);
## - recogerla suma al contador (no a la bolsa), se guarda y la Telequinesis/Ojo las atrae;
## - los nodos del Núcleo se pagan con Lágrimas (no con maná) y la Gran Convergencia no se ve
##   hasta el 99 %; al inscribirla avisa (`grand_convergence_unlocked`).
## godot --headless --path game --script res://tests/smoke/core_tears_smoke.gd

var _ok: bool = true
var _demo: Script
var _unlocked: int = 0
var _collected: int = 0


func _initialize() -> void:
	root.get_node(^"SaveSystem").set(&"enabled", false)
	var gs: Node = root.get_node(^"GameState")
	gs.call(&"reset")
	_demo = load("res://crystal/crystal_demo.gd")
	var balance: BalanceConfig = gs.get(&"BALANCE")
	_rules(balance)
	_currency(gs)
	change_scene_to_file("res://main/main.tscn")
	for i: int in 240:
		await process_frame
	var main: Node = current_scene
	var menu: Node = main.get_node(^"HUDLayer/Hud/GameMenu")
	if VariantCast.to_bool(menu.call(&"is_open")):
		menu.call(&"_close")
	paused = false
	await _world(gs, main)
	await create_timer(1.5).timeout
	print("core_tears_smoke: ", "OK" if _ok else "FALLO")
	quit(0 if _ok else 1)


## Reglas puras de TearDrops: azar por daño, tope y piedad.
func _rules(balance: BalanceConfig) -> void:
	var drops := TearDrops.new(balance)
	var prog := Progression.new(balance.total_essence)
	var d: int = roundi(balance.tear_essence * 0.1)
	_check(is_equal_approx(drops.chance_for(d), 0.1), "probabilidad = daño / tear_essence")
	_check(is_equal_approx(drops.chance_for(d, 1.5), 0.15), "el Ojo del Núcleo la multiplica x1,5")
	_check(
		is_equal_approx(drops.chance_for(10_000_000), balance.tear_chance_max),
		"un golpe enorme no da una Lágrima segura (tope)"
	)
	_check(drops.chance_for(0) == 0.0, "sin daño, nada")
	# Piedad: golpes cada 5 s que nunca aciertan al azar (roll = 0,999).
	var hits_to_pity: int = ceili(balance.tear_pity_sec / 5.0)
	var first: int = -1
	for i: int in hits_to_pity + 3:
		if drops.register_heart_hit(prog, float(i) * 5.0, 10, 0.999):
			first = i
			break
	_check(
		first == hits_to_pity,
		"la piedad da una tras %d s de golpes (golpe %d)" % [roundi(balance.tear_pity_sec), first]
	)
	_check(prog.tear_pity == 0.0, "y la piedad vuelve a cero")
	# Pasear no carga la piedad: un minuto sin golpes cuenta como tear_active_gap_sec.
	var t0: float = 1000.0
	drops = TearDrops.new(balance)
	drops.register_heart_hit(prog, t0, 10, 0.999)
	drops.register_heart_hit(prog, t0 + 60.0, 10, 0.999)
	_check(
		is_equal_approx(prog.tear_pity, balance.tear_active_gap_sec),
		"un minuto paseando cuenta %.0f s" % balance.tear_active_gap_sec
	)
	prog.tear_pity = 0.0
	_check(drops.register_heart_hit(prog, t0 + 61.0, d, 0.05), "el azar también la da")
	# El Núcleo expuesto llora sólo si faltan Lágrimas para la Gran Convergencia.
	var core := TearDrops.new(balance)
	prog.tear_pity = 0.0
	var wept: bool = false
	for i: int in 20:
		wept = wept or core.register_core_hit(prog, float(i) * 5.0, 0)
	_check(not wept and prog.tear_pity == 0.0, "con Lágrimas de sobra el Núcleo no llora")
	var at: int = -1
	for i: int in 20:
		if core.register_core_hit(prog, 200.0 + float(i) * 3.0, 3):
			at = i
			break
	_check(at == ceili(balance.core_tear_pity_sec / 3.0), "si faltan, el Núcleo llora (%d)" % at)


## Moneda de los nodos del Núcleo y Gran Convergencia oculta hasta el 99 %.
func _currency(gs: Node) -> void:
	var events: Node = root.get_node(^"Events")
	events.connect(&"grand_convergence_unlocked", func() -> void: _unlocked += 1)
	var prog: Progression = gs.get(&"progression")
	var eye: UpgradeNode = load("res://data/upgrades/core_eye.tres")
	var gc: UpgradeNode = load("res://data/upgrades/grand_convergence.tres")
	var upgrades: Array = gs.get(&"UPGRADES")
	_check(upgrades.has(eye), "los nodos del Núcleo están en UPGRADES")
	prog.mana = 1_000_000
	_check(prog.purchase_block(eye) == &"tears", "sin Lágrimas no se compra (aunque sobre maná)")
	_check(not VariantCast.to_bool(gs.call(&"buy_upgrade", eye)), "no se inscribe")
	prog.tears = 2
	_check(VariantCast.to_bool(gs.call(&"buy_upgrade", eye)), "con Lágrimas, sí")
	_check(prog.tears == 1 and prog.mana == 1_000_000, "gasta Lágrimas, no maná")
	_check(VariantCast.to_bool(gs.call(&"has_upgrade", &"core_eye")), "has_upgrade")
	# El Grimorio se abre por una estrella del Núcleo nueva, pero una ya vista no tapa las de maná
	# (un coste de 1 Lágrima no es "más barato" que 5 de maná).
	var cheapest: UpgradeNode = gs.call(&"cheapest_affordable")
	_check(cheapest != null and cheapest.pays_with_tears(), "abre por la estrella del Núcleo nueva")
	prog.seen_upgrades[cheapest.id] = prog.get_level(cheapest.id)
	cheapest = gs.call(&"cheapest_affordable")
	_check(cheapest != null and not cheapest.pays_with_tears(), "ya vista: abre por la de maná")
	prog.seen_upgrades.clear()
	prog.tears = 10
	_check(prog.purchase_block(gc) == &"hidden", "la Gran Convergencia no se ve antes del 99 %")
	_check(not VariantCast.to_bool(gs.get(&"core_exposed")), "Núcleo tapado")
	prog.essence = roundi(prog.total_essence * 0.0105)
	_check(prog.purchase_block(gc) == &"hidden", "al 98,95 % tampoco")
	var revealed: Array[int] = [0]
	events.connect(&"grimoire_final_revealed", func() -> void: revealed[0] += 1)
	gs.call(&"hit_crystal", roundi(prog.total_essence * 0.0005), Vector3.ZERO)
	_check(
		VariantCast.to_bool(gs.get(&"core_exposed")) and revealed[0] == 1,
		"al 99 %: Núcleo expuesto, aviso"
	)
	_check(prog.purchase_block(gc) == &"", "y se puede inscribir")
	_check(VariantCast.to_bool(gs.call(&"buy_upgrade", gc)), "Gran Convergencia inscrita")
	_check(_unlocked == 1, "avisa grand_convergence_unlocked")
	_check(
		VariantCast.to_bool(gs.call(&"has_upgrade", &"grand_convergence")),
		"has_upgrade(grand_convergence)"
	)
	# Se guarda: ida y vuelta por to_dict / load_dict.
	prog.tears_total = 9
	prog.tear_pity = 37.5
	prog.loose_tears = PackedVector3Array([Vector3(1, 2, 3)])
	var data: Dictionary = JSON.parse_string(JSON.stringify(prog.to_dict()))
	var back := Progression.new(prog.total_essence)
	back.load_dict(data)
	_check(back.tears == prog.tears and back.tears_total == 9, "Lágrimas guardadas")
	_check(is_equal_approx(back.tear_pity, 37.5), "piedad guardada")
	_check(
		back.loose_tears.size() == 1 and back.loose_tears[0].is_equal_approx(Vector3(1, 2, 3)),
		"Lágrimas flotando guardadas"
	)
	gs.call(&"reset")


## En la escena: sólo brotan en el Corazón con combinados; recogerlas suma y se guarda.
func _world(gs: Node, main: Node) -> void:
	var events: Node = root.get_node(^"Events")
	events.connect(&"tear_collected", func(_at: Vector3) -> void: _collected += 1)
	var saves: bool = false
	for c: Dictionary in events.get_signal_connection_list(&"tear_collected"):
		var callable: Callable = c["callable"]
		if callable.get_object() == root.get_node(^"SaveSystem"):
			saves = true
	_check(saves, "recoger una Lágrima guarda la partida")
	var prog: Progression = gs.get(&"progression")
	var world: Node = main.get_node(^"WorldView/WorldViewport")
	var crystal: Node3D = world.get_node(^"MotherCrystal")
	var tears: Node = crystal.get_node(^"CoreTears")
	var shards: Node = crystal.get_node(^"Shards")
	var player: Node3D = world.get_node(^"Player")
	var fireball: SpellRecipe = load("res://data/spells/recipe_fireball.tres")
	var tear_type: Resource = load("res://data/shards/core_tear.tres")
	# Otras capas: ni con la piedad llena.
	_demo.call(&"tunnel_to_layer", crystal, 2)
	prog.tear_pity = 10_000.0
	var veins_hit: SpellHit = _tunnel_hit(crystal, 2, fireball)
	crystal.call(&"receive_hit", veins_hit)
	_check(veins_hit.layer == 2, "golpe en las Venas")
	_check(VariantCast.to_int(tears.call(&"loose_count")) == 0, "fuera del Corazón no brotan")
	# El Corazón: un golpe suelto rebota y no da nada.
	_demo.call(&"tunnel_to_layer", crystal, 3)
	var single: SpellHit = _tunnel_hit(crystal, 3, null)
	crystal.call(&"receive_hit", single)
	_check(
		VariantCast.to_int(tears.call(&"loose_count")) == 0, "un golpe suelto en el Corazón: nada"
	)
	# Fractura del Corazón: más daño a los combinados en el Corazón.
	var levels: Dictionary = prog.get(&"upgrade_levels")
	levels[&"heart_fracture"] = 3
	var probe: SpellHit = _tunnel_hit(crystal, 3, fireball)
	probe.resonant = true
	tears.call(&"apply", probe)
	_check(probe.damage == 29, "Fractura del Corazón III: x1,45 (%d)" % probe.damage)
	levels.erase(&"heart_fracture")
	# Un combinado en el Corazón con la piedad llena: brota una.
	var combo: SpellHit = _tunnel_hit(crystal, 3, fireball)
	crystal.call(&"receive_hit", combo)
	_check(combo.layer == 3, "golpe combinado en el Corazón")
	_check(VariantCast.to_int(tears.call(&"loose_count")) == 1, "brota una Lágrima del Núcleo")
	_check(prog.loose_tears.size() == 1, "se apunta dónde flota (para guardarla)")
	_check(
		VariantCast.to_int(shards.call(&"count_of", tear_type)) == 0,
		"no es un fragmento (familiares no)"
	)
	await create_timer(3.2).timeout
	# Recogerla: vuela a la mano y suma al contador, no a la bolsa.
	var bag0: int = prog.bag_count()
	var grab: Node3D = player.call(&"grab_point")
	tears.call(&"collect", 0, grab)
	await create_timer(0.8).timeout
	_check(prog.tears == 1 and prog.tears_total == 1, "suma al contador (%d)" % prog.tears)
	_check(_collected == 1, "aviso tear_collected")
	_check(prog.bag_count() == bag0, "no ocupa la bolsa")
	_check(
		VariantCast.to_int(tears.call(&"loose_count")) == 0 and prog.loose_tears.is_empty(),
		"ya no flota"
	)
	# El Ojo del Núcleo: vuelan solas desde lejos.
	levels[&"core_eye"] = 1
	prog.tear_pity = 10_000.0
	var again: SpellHit = _tunnel_hit(crystal, 3, fireball)
	crystal.call(&"receive_hit", again)
	_check(VariantCast.to_int(tears.call(&"loose_count")) == 1, "otra Lágrima")
	var tear_at: Vector3 = tears.call(&"position_of", 0)
	player.global_position = tear_at + Vector3(0, 0, 12)
	await create_timer(3.5).timeout
	_check(prog.tears == 2, "con el Ojo del Núcleo vuela sola al mago (%d)" % prog.tears)
	# Sin plazas libres nunca se pierde una: la más vieja (o la nueva) cuenta sola.
	levels.erase(&"core_eye")
	player.global_position += Vector3(0, 0, 200)
	var max_tears: int = tears.get(&"MAX_TEARS")
	for i: int in max_tears + 2:
		tears.call(&"drop", crystal.global_position + Vector3(0, 30, 0), Vector3.UP)
	_check(
		VariantCast.to_int(tears.call(&"loose_count")) == max_tears,
		"pool lleno: %d flotando" % max_tears
	)
	_check(prog.tears == 4, "y las que no caben cuentan solas (%d)" % prog.tears)


## Golpe en el fondo del túnel de demo hasta la capa `layer` (daño 20).
func _tunnel_hit(crystal: Node3D, layer: int, recipe: SpellRecipe) -> SpellHit:
	var volume: RefCounted = crystal.get(&"volume")
	var ray: Array = _demo.call(&"tunnel_ray", crystal, layer)
	var p: Vector3 = ray[0]
	var dir: Vector3 = ray[1]
	var t: float = 0.0
	while t < 80.0 and not VariantCast.to_bool(volume.call(&"is_solid", p + dir * t)):
		t += 0.2
	var spark: Resource = load("res://data/elements/spark.tres")
	var hit := SpellHit.new()
	hit.position = p + dir * (t - 0.3)
	hit.normal = -dir
	hit.direction = dir
	hit.damage = 20
	hit.element = &"spark"
	hit.element_def = spark if recipe == null else null
	hit.recipe = recipe
	var spark_tiers: Array = spark.get(&"tiers")
	hit.tier = spark_tiers[0] if recipe == null else recipe.tier
	return hit


func _check(cond: bool, what: String) -> void:
	if not cond:
		_ok = false
		push_error("FALLO: " + what)
	else:
		print("  ok: ", what)
