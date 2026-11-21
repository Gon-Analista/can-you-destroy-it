extends SceneTree
## El Arcano (GDD 5.1 y 5.2): niveles hasta 10 con ecos que crecen, sus mejoras, la versión
## fantasma de los hechizos, y en la escena: un disparo suelto deja ecos que golpean otra vez,
## la Resonancia Arcana hace resonante el golpe siguiente (y no se puede encadenar) y la
## Gravedad se traga todos los fragmentos sueltos (a la bolsa o a la tolva).
## godot --headless --path game --script res://tests/smoke/arcane_smoke.gd

var _ok: bool = true


func _initialize() -> void:
	root.get_node(^"SaveSystem").set(&"enabled", false)
	var gs: Node = root.get_node(^"GameState")
	gs.call(&"reset")
	var caster_script: Script = load("res://player/spell_caster.gd")
	var elements: Array = caster_script.get(&"ELEMENTS")
	var arcane: Resource = elements[4]
	_check(VariantCast.to_bool(arcane.get(&"id") == &"arcane"), "el Arcano es el elemento 4")
	_check(
		VariantCast.to_bool(arcane.get(&"power_stat") == &"arcane_tier"),
		"su Potencia es arcane_tier"
	)
	_check(
		VariantCast.to_bool(arcane.get(&"unlock_upgrade") == &"awaken_arcane"),
		"se despierta con awaken_arcane"
	)
	arcane.call(&"ensure_levels")
	var tiers: Array = arcane.get(&"tiers")
	_check(tiers.size() == 11, "llega a nivel 11")
	var echoes: Array[int] = []
	for t: Resource in tiers:
		echoes.append(VariantCast.to_int(t.get(&"echoes")))
	_check(echoes == [1, 1, 2, 2, 2, 3, 3, 3, 4, 4, 5], "ecos por nivel %s" % str(echoes))
	var ghost_script: GDScript = load("res://spells/spell_ghost.gd")
	var ghosts: RefCounted = ghost_script.new()
	var ghost: Resource = ghosts.call(&"tier", tiers[0])
	_check(VariantCast.to_bool(ghost != null and ghost != tiers[0]), "hay versión fantasma")
	_check(
		VariantCast.to_bool(ghosts.call(&"tier", tiers[0]) == ghost),
		"la versión fantasma se guarda"
	)
	var first: Resource = tiers[0]
	_check(
		VariantCast.to_bool(ghost.get(&"visual") != first.get(&"visual")),
		"el fantasma tiene otro aspecto"
	)
	_check(VariantCast.to_int(ghost.get(&"echoes")) == 0, "un eco no deja ecos")
	var ups: Dictionary[StringName, Resource] = {}
	for u: Resource in gs.get(&"UPGRADES"):
		ups[u.get(&"id")] = u
	_check(ups.has(&"awaken_arcane") and ups.has(&"arcane_power"), "mejoras del Arcano")
	if ups.has(&"arcane_power"):
		var power: Resource = ups[&"arcane_power"]
		var costs: PackedInt32Array = power.get(&"costs")
		var level_names: PackedStringArray = power.get(&"level_names")
		_check(costs.size() == 10, "Potencia: 10 compras")
		_check(level_names.size() == 11, "11 nombres")
		_check(VariantCast.to_bool(power.get(&"element") == &"arcane"), "en la página del Arcano")
		var wake: Resource = ups[&"awaken_arcane"]
		var prerequisites: Array = wake.get(&"prerequisites")
		_check(prerequisites.has(&"awaken_earth"), "pide la Tierra")
	await _scene_checks(gs)
	print("arcane_smoke: ", "OK" if _ok else "FALLO")
	quit(0 if _ok else 1)


func _scene_checks(gs: Node) -> void:
	change_scene_to_file("res://main/main.tscn")
	for i: int in 240:
		await process_frame
	var main: Node = current_scene
	var menu: Node = main.get_node(^"HUDLayer/Hud/GameMenu")
	if VariantCast.to_bool(menu.call(&"is_open")):
		menu.call(&"_close")
	var player: Node3D = main.get_node(^"WorldView/WorldViewport/Player")
	var caster: Node = player.call(&"get_caster")
	var prog: RefCounted = gs.get(&"progression")
	var levels: Dictionary = prog.get(&"upgrade_levels")
	for id: String in ["awaken_frost", "awaken_bolt", "awaken_earth", "awaken_arcane"]:
		levels[StringName(id)] = 1
	player.global_position = Vector3(0.0, 0.3, 60.0)
	player.rotation.y = 0.0
	(player.get_node(^"Head") as Node3D).rotation.x = deg_to_rad(8.0)
	var events: Node = root.get_node(^"Events")
	var impacts: Array[int] = [0, 0, 0]  # golpes, ecos, resonantes
	events.connect(
		&"spell_impacted",
		func(hit: RefCounted) -> void:
			impacts[0] += 1
			if VariantCast.to_bool(hit.get(&"echo")):
				impacts[1] += 1
			if VariantCast.to_bool(hit.get(&"resonant")):
				impacts[2] += 1
	)
	var hands: Array = caster.get(&"hand_element")
	# 1. Un disparo de Arcano: el golpe y su eco.
	hands[0] = 4
	hands[1] = 4
	_ready_hands(caster)
	await process_frame
	caster.call(&"try_cast", 0)
	await create_timer(2.5).timeout
	_check(impacts[0] >= 2 and impacts[1] >= 1, "un disparo arcano deja eco (%s)" % str(impacts))
	# 2. Resonancia Arcana: el golpe siguiente es resonante y no se puede repetir enseguida.
	_ready_hands(caster)
	await process_frame
	_check(
		VariantCast.to_bool(caster.call(&"try_begin_combine")), "Resonancia: se juntan las manos"
	)
	await create_timer(1.4).timeout
	caster.call(&"try_release_combine")
	await create_timer(0.3).timeout
	_check(VariantCast.to_float(caster.get(&"_resonance_left")) > 0.0, "Resonancia activa")
	_ready_hands(caster)
	await process_frame
	_check(
		not VariantCast.to_bool(caster.call(&"try_begin_combine")), "la Resonancia no se encadena"
	)
	var res_before: int = impacts[2]
	_ready_hands(caster)
	caster.call(&"try_cast", 1)
	await create_timer(1.6).timeout
	_check(impacts[2] > res_before, "durante la Resonancia los golpes son resonantes")
	# 3. Gravedad: fragmentos sueltos alrededor; todos acaban en la bolsa o camino de la tolva.
	await create_timer(4.0).timeout
	var pool: Node3D = main.get_node(^"WorldView/WorldViewport").find_child("Shards", true, false)
	_check(pool != null, "hay pool de fragmentos")
	var types: Array = load("res://crystal/shard_pool.gd").get(&"TYPES")
	for i: int in 10:
		var at: Vector3 = player.global_position + Vector3(randf_range(-12, 12), 2.0, -8.0 - i)
		pool.call(&"spawn", at, Vector3.UP, types[i % 3], 1, 0.3)
	await create_timer(1.5).timeout
	var collected: Array[int] = [0]
	events.connect(
		&"shard_collected", func(_t: Resource, _c: int, _at: Vector3) -> void: collected[0] += 1
	)
	hands[0] = 4
	hands[1] = 3
	_ready_hands(caster)
	await process_frame
	_check(VariantCast.to_bool(caster.call(&"try_begin_combine")), "Gravedad: se juntan las manos")
	await create_timer(1.0).timeout
	caster.call(&"try_release_combine")
	await create_timer(0.5).timeout
	_check(
		VariantCast.to_int(pool.call(&"orbiting_count")) >= 10, "los fragmentos giran hacia el pozo"
	)
	await create_timer(3.2).timeout
	_check(VariantCast.to_int(pool.call(&"orbiting_count")) == 0, "el pozo se cierra")
	_check(collected[0] >= 10, "la Gravedad se traga todo (%d)" % collected[0])
	_check(
		VariantCast.to_int(pool.call(&"nearest", player.global_position, 500.0)) == -1,
		"no queda nada suelto"
	)
	var found: Array = prog.get(&"discovered_recipes")
	_check(found.has(&"gravity") and found.has(&"resonance"), "se descubren")


func _ready_hands(caster: Node) -> void:
	caster.set(&"_cooldown", PackedFloat32Array([0.0, 0.0]))


func _check(cond: bool, what: String) -> void:
	if not cond:
		_ok = false
		push_error("FALLO: " + what)
	else:
		print("  ok: ", what)
