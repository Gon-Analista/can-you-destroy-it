extends SceneTree
## Tutorial del principio: la chispita de cada mano no hace nada ("clink"), juntar las manos
## hace 1 de daño y suelta un pedacito, se recoge, se tritura, con 5 de maná se compra la
## primera mejora y entonces la magia hace daño de verdad (2 con las manos juntas).
## godot --headless --path game --script res://tests/smoke/tutorial_smoke.gd

var _ok: bool = true


func _initialize() -> void:
	root.get_node(^"SaveSystem").set(&"enabled", false)
	var gs: Node = root.get_node(^"GameState")
	gs.call(&"reset")
	var prog: RefCounted = gs.get(&"progression")
	prog.set(&"tutorial_step", 0)
	prog.set(&"hut_door_open", false)
	change_scene_to_file("res://main/main.tscn")
	for i: int in 240:
		await process_frame
	var main: Node = current_scene
	var menu: Node = main.get_node(^"HUDLayer/Hud/GameMenu")
	if bool(menu.call(&"is_open")):
		menu.call(&"_close")
	var tut: Node = main.get_node(^"HUDLayer/Hud/Tutorial")
	var player: Node3D = main.get_node(^"WorldView/WorldViewport/Player")
	var caster: Node = player.call(&"get_caster")
	_check(int(tut.get(&"step")) == 0, "empieza esperando la puerta")
	var hut: Node = root.find_child("ApprenticeHut", true, false)
	hut.call(&"open_door")
	await create_timer(2.2).timeout
	_check(
		int(tut.get(&"step")) == 1,
		"al abrir la puerta: clic izquierdo (%d)" % int(tut.get(&"step"))
	)
	player.global_position = Vector3(0.0, 0.3, 62.0)
	player.rotation.y = 0.0
	(player.get_node(^"Head") as Node3D).rotation.x = deg_to_rad(6.0)
	await physics_frame
	var e0: int = int(prog.get(&"essence"))
	caster.call(&"_cast_single", 0)
	await create_timer(2.5).timeout
	_check(int(tut.get(&"step")) == 2, "clic izquierdo hecho")
	_check(int(prog.get(&"essence")) == e0, "la chispita no hace daño")
	caster.set(&"_cooldown", PackedFloat32Array([0.0, 0.0]))
	caster.call(&"_cast_single", 1)
	await create_timer(2.5).timeout
	_check(int(tut.get(&"step")) == 3, "clic derecho hecho")
	_check(int(prog.get(&"essence")) == e0, "la otra tampoco")
	caster.set(&"_cooldown", PackedFloat32Array([0.0, 0.0]))
	caster.call(&"try_begin_combine")
	await create_timer(0.8).timeout
	caster.call(&"try_release_combine")
	await create_timer(3.0).timeout
	_check(int(tut.get(&"step")) == 4, "juntar las manos (%d)" % int(tut.get(&"step")))
	_check(
		int(prog.get(&"essence")) == e0 - 1,
		"juntas hacen 1 de daño (%d)" % (e0 - int(prog.get(&"essence")))
	)
	# Recoger el pedacito.
	var pool: Node = root.find_child("Shards", true, false)
	var idx: int = int(pool.call(&"nearest", player.global_position, 80.0))
	_check(idx >= 0, "cayó un pedacito")
	if idx >= 0:
		player.call(&"_collect", idx)
	await process_frame
	_check(int(tut.get(&"step")) == 5, "recogido: a la trituradora")
	# Triturar (equivale a entregar).
	gs.call(&"deliver", 1)
	await process_frame
	_check(int(tut.get(&"step")) == 6, "triturado: juntar maná")
	gs.call(&"deliver", 4)
	await process_frame
	_check(int(tut.get(&"step")) == 7, "con 5 de maná: al Santuario")
	var power: Resource = load("res://data/upgrades/spark_power.tres")
	_check(int(power.call(&"cost_for_level", 0)) == 5, "la primera mejora cuesta 5")
	_check(bool(gs.call(&"buy_upgrade", power)), "se compra")
	await process_frame
	_check(int(tut.get(&"step")) == 8, "tutorial terminado")
	var tier: Resource = caster.call(&"tier_for", 0)
	_check(int(tier.get(&"damage")) == 1, "ahora la chispa hace 1")
	var recipe: Resource = caster.call(&"recipe_for_hands")
	_check(int(recipe.call(&"damage_for", 1, 1, 1.0)) == 2, "y juntas hacen 2")
	print("tutorial_smoke: ", "OK" if _ok else "FALLO")
	quit(0 if _ok else 1)


func _check(cond: bool, what: String) -> void:
	if not cond:
		_ok = false
		push_error("FALLO: " + what)
	else:
		print("  ok: ", what)
