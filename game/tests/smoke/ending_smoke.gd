extends SceneTree
## El final (GDD 9):
## - las estadísticas de la pantalla final y el final se guardan (ida y vuelta por to_dict);
## - ningún golpe baja del 99 %: el Núcleo guarda su 1 %;
## - al llegar al 99 % el cristal se resquebraja, lo que queda se borra del volumen y el Núcleo
##   queda a la vista e inmune (los golpes rebotan, con su colisión propia);
## - la Gran Convergencia no se arma sin su nodo; soltar antes de tiempo la deshace sin coste;
##   con la carga completa rompe el Núcleo: partida terminada, cristal a cero, Pilón al 100 %,
##   columna de maná, auroras y la pantalla final;
## - al volver a cargar la partida terminada, el valle sigue de fiesta y sin cristal.
## godot --headless --path game --script res://tests/smoke/ending_smoke.gd

var _ok: bool = true
var _completed: int = 0


func _initialize() -> void:
	root.get_node(^"SaveSystem").set(&"enabled", false)
	var gs: Node = root.get_node(^"GameState")
	gs.call(&"reset")
	_rules(gs)
	gs.call(&"reset")
	change_scene_to_file("res://main/main.tscn")
	await _settle()
	await _world(gs, current_scene)
	await _reload(gs)
	await _fallback(gs)
	print("ending_smoke: ", "OK" if _ok else "FALLO")
	quit(0 if _ok else 1)


func _settle() -> void:
	for i: int in 240:
		await process_frame
	var menu: Node = current_scene.get_node(^"HUDLayer/Hud/GameMenu")
	if bool(menu.call(&"is_open")):
		menu.call(&"_close")
	paused = false


func _rules(gs: Node) -> void:
	var prog: Progression = gs.get(&"progression")
	prog.time_played = 4321.5
	prog.spells_cast = 77
	prog.shards_collected = 999
	prog.game_complete = true
	var back := Progression.new(prog.total_essence)
	back.load_dict(JSON.parse_string(JSON.stringify(prog.to_dict())))
	_check(back.game_complete, "el final se guarda")
	_check(
		is_equal_approx(back.time_played, 4321.5) and back.spells_cast == 77,
		"tiempo jugado y hechizos lanzados se guardan"
	)
	_check(back.shards_collected == 999, "fragmentos recogidos se guardan")
	prog.game_complete = false
	var floor_e: int = gs.get(&"core_floor")
	_check(floor_e == roundi(prog.total_essence * 0.01), "el Núcleo guarda el 1 %% (%d)" % floor_e)
	gs.call(&"hit_crystal", prog.total_essence * 2, Vector3.ZERO)
	_check(prog.essence == floor_e, "ningún golpe baja del 99 %% (%d)" % prog.essence)
	_check(bool(gs.get(&"core_exposed")), "y ahí el Núcleo queda expuesto")


func _world(gs: Node, main: Node) -> void:
	var events: Node = root.get_node(^"Events")
	events.connect(&"game_completed", func() -> void: _completed += 1)
	var prog: Progression = gs.get(&"progression")
	var world: Node = main.get_node(^"WorldView/WorldViewport")
	var crystal: Node3D = world.get_node(^"MotherCrystal")
	var reveal: Node3D = crystal.get_node(^"CoreReveal")
	var director: Node = main.get_node(^"EndingDirector")
	var gc: Node = director.call(&"convergence")
	var volume: RefCounted = crystal.get(&"volume")
	_check(int(reveal.get(&"state")) == 0, "al empezar, el Núcleo no se ve")
	_check(int(gc.get(&"state")) == 0, "la Gran Convergencia no está armada")
	var t0: float = prog.time_played
	await create_timer(0.5).timeout
	_check(prog.time_played > t0, "el tiempo jugado corre")
	# Al 99 %: el cristal se resquebraja y se desprende.
	director.call(&"debug_core")
	var waited: float = 0.0
	while int(reveal.get(&"state")) == 0 and waited < 30.0:
		await process_frame
		waited += 1.0 / 60.0
	_check(int(reveal.get(&"state")) == 1, "al 99 %: el cristal se resquebraja")
	_check(prog.essence == int(gs.get(&"core_floor")), "la cuenta se para en el 99 %")
	waited = 0.0
	while int(reveal.get(&"state")) != 2 and waited < 60.0:
		await create_timer(0.5).timeout
		waited += 0.5
	_check(int(reveal.get(&"state")) == 2, "el Núcleo queda expuesto (%.1f s)" % waited)
	var core_c: Vector3 = volume.get(&"core_center")
	var core_r: float = volume.get(&"core_radius")
	_check(bool(volume.call(&"is_solid", core_c)), "el Núcleo sigue ahí")
	var stray: int = 0
	for p: Vector3 in [
		Vector3(0, 60, 0),
		Vector3(0, 20, 0),
		Vector3(12, 4, 0),
		Vector3(0, 4, -14),
		core_c + Vector3(core_r + 1.5, 0, 0),
		Vector3(-20, 2, 10)
	]:
		if bool(volume.call(&"is_solid", p)):
			stray += 1
	_check(stray == 0, "no queda cristal fuera del Núcleo (%d puntos)" % stray)
	# Inmune: un golpe enorme rebota y la esencia no baja.
	var center: Vector3 = reveal.call(&"core_position")
	var radius: float = reveal.call(&"core_radius")
	var fireball: SpellRecipe = load("res://data/spells/recipe_fireball.tres")
	var hit := SpellHit.new()
	hit.position = center + Vector3.BACK * radius
	hit.normal = Vector3.BACK
	hit.direction = Vector3.FORWARD
	hit.damage = 50_000
	hit.element = &"spark"
	hit.recipe = fireball
	hit.tier = fireball.tier
	var before: int = prog.essence
	crystal.call(&"receive_hit", hit)
	_check(prog.essence == before, "el Núcleo no recibe daño (%d)" % prog.essence)
	_check(int(crystal.call(&"hit_layer")) == 4, "el golpe da en el Núcleo")
	var space: PhysicsDirectSpaceState3D = crystal.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(center + Vector3.BACK * 40.0, center, 1 << 1)
	var r: Dictionary = space.intersect_ray(q)
	_check(
		not r.is_empty() and (r["collider"] as Node).has_meta(&"mother_crystal"),
		"la mira y los hechizos dan en el Núcleo"
	)
	# Sin el nodo no se arma.
	await create_timer(0.5).timeout
	_check(int(gc.get(&"state")) == 0, "sin la Gran Convergencia inscrita no se arma")
	gc.call(&"begin_charge")
	_check(int(gc.get(&"state")) == 0, "ni se carga")
	# Inscrita (3 Lágrimas): los cinco elementos acuden a las manos.
	var node: UpgradeNode = load("res://data/upgrades/grand_convergence.tres")
	prog.tears = 3
	_check(bool(gs.call(&"buy_upgrade", node)), "se inscribe con el Núcleo expuesto")
	waited = 0.0
	while int(gc.get(&"state")) != 2 and waited < 6.0:
		await create_timer(0.25).timeout
		waited += 0.25
	_check(int(gc.get(&"state")) == 2, "armada: los cinco elementos en las manos")
	# Soltar antes de tiempo: se deshace sin coste.
	gc.call(&"_aim_at_core")
	gc.call(&"begin_charge")
	_check(int(gc.get(&"state")) == 3, "mantener los dos botones: carga")
	await create_timer(1.5).timeout
	var k: float = gc.call(&"charge_ratio")
	_check(k > 0.15 and k < 0.6, "la carga sube despacio (%.2f)" % k)
	gc.call(&"release")
	_check(int(gc.get(&"state")) == 2, "soltar antes: se deshace")
	_check(not prog.game_complete and prog.essence == before, "y no pasa nada")
	_check(bool(gs.call(&"has_upgrade", &"grand_convergence")), "sin coste (sigue inscrita)")
	# Carga completa: cinco etapas.
	var stages: Array[int] = []
	var on_stage := func(s: int, _total: int) -> void:
		if s > 0:
			stages.append(s)
	events.connect(&"spell_charge_stage", on_stage)
	var casts: int = prog.spells_cast
	gc.call(&"begin_charge")
	await create_timer((gs.get(&"BALANCE") as BalanceConfig).convergence_charge_sec + 0.4).timeout
	events.disconnect(&"spell_charge_stage", on_stage)
	_check(stages == [1, 2, 3, 4, 5], "cinco etapas, una por elemento (%s)" % str(stages))
	gc.call(&"release")
	_check(int(gc.get(&"state")) == 4, "con la carga completa, sale")
	_check(prog.spells_cast == casts + 1, "cuenta como hechizo lanzado")
	waited = 0.0
	while not prog.game_complete and waited < 4.0:
		await create_timer(0.1).timeout
		waited += 0.1
	_check(prog.game_complete and _completed == 1, "el Núcleo estalla: fin de la partida")
	_check(prog.essence == 0, "el cristal a cero")
	_check(int(reveal.get(&"state")) == 3, "el Núcleo ya no está")
	_check(not bool(volume.call(&"is_solid", core_c)), "ni en el volumen (se guarda así)")
	await create_timer(2.5).timeout
	_check(prog.pylon_progress == prog.total_essence, "el Pilón llega al 100 %")
	var celebration: Node = world.get_node(^"ValleyCelebration")
	_check((celebration.get_node(^"ManaColumn") as Node3D).visible, "columna de maná")
	await create_timer(5.0).timeout
	var day: Node = world.get_node(^"DayNight")
	_check(float(day.get(&"finale")) > 0.9, "el cielo de auroras")
	_check(bool(celebration.get(&"started")), "la aldea celebra")
	var herd: Node = world.get_node(^"CritterHerd")
	_check(int(herd.call(&"alive_count")) >= 0, "los bichos siguen ahí (bailan)")
	var screen: Node = director.call(&"screen")
	waited = 0.0
	while not bool(screen.call(&"is_open")) and waited < 15.0:
		await create_timer(0.5).timeout
		waited += 0.5
	_check(bool(screen.call(&"is_open")), "la pantalla final")
	await create_timer(2.5).timeout
	var title: Label = screen.get(&"_title")
	_check(title.text == "Yes, you could.", "Yes, you could. (%s)" % title.text)
	screen.call(&"_continue")
	_check(not bool(screen.call(&"is_open")), "seguir en el valle")


## Partida terminada al volver a cargar: el valle de fiesta y sin cristal.
func _reload(gs: Node) -> void:
	var prog: Progression = gs.get(&"progression")
	_check(prog.game_complete, "la partida sigue terminada")
	reload_current_scene()
	await _settle()
	var world: Node = current_scene.get_node(^"WorldView/WorldViewport")
	var crystal: Node3D = world.get_node(^"MotherCrystal")
	_check(not (crystal.get_node(^"Chunks") as Node3D).visible, "al cargar: sin cristal")
	_check(int(crystal.get_node(^"CoreReveal").get(&"state")) == 3, "ni Núcleo")
	var celebration: Node = world.get_node(^"ValleyCelebration")
	_check(bool(celebration.get(&"started")), "el valle sigue de fiesta")
	_check(float(world.get_node(^"DayNight").get(&"finale")) > 0.99, "con auroras")
	_check(
		int((current_scene.get_node(^"EndingDirector").call(&"convergence")).get(&"state")) == 0,
		"la Gran Convergencia ya no se arma"
	)
	gs.call(&"reset")


## Red de seguridad: si ya no queda nada a tiro fuera del Núcleo pero la cuenta no llega al 99 %
## (el volumen y la cuenta no cuadran del todo), el Núcleo queda expuesto igual.
func _fallback(gs: Node) -> void:
	var prog: Progression = gs.get(&"progression")
	var balance: BalanceConfig = gs.get(&"BALANCE")
	var scan_sec: float = balance.core_reveal_scan_sec
	balance.core_reveal_scan_sec = 0.5
	reload_current_scene()
	await _settle()
	var crystal: Node3D = current_scene.get_node(^"WorldView/WorldViewport/MotherCrystal")
	var reveal: Node3D = crystal.get_node(^"CoreReveal")
	var volume: RefCounted = crystal.get(&"volume")
	var reveal_script: Script = reveal.get_script()
	var full: float = reveal_script.call(&"reachable_shell", volume, volume.get(&"sdf"))
	_check(full > prog.total_essence * 0.5, "cristal entero: casi todo a tiro (%.0f)" % full)
	var done: Array[bool] = [false]
	reveal.call(&"debug_trim", 0.0, func() -> void: done[0] = true)
	var waited: float = 0.0
	while not done[0] and waited < 30.0:
		await create_timer(0.25).timeout
		waited += 0.25
	var left: float = reveal_script.call(&"reachable_shell", volume, volume.get(&"sdf"))
	_check(
		left < prog.total_essence * balance.core_reveal_leftover,
		"sin cristal fuera del Núcleo: nada a tiro (%.0f)" % left
	)
	prog.essence = roundi(prog.total_essence * 0.04)
	_check(not bool(gs.get(&"core_exposed")), "la cuenta se ha quedado en el 96 %")
	waited = 0.0
	while int(reveal.get(&"state")) == 0 and waited < 20.0:
		await create_timer(0.25).timeout
		waited += 0.25
	_check(int(reveal.get(&"state")) != 0, "el Núcleo queda expuesto igual (%.1f s)" % waited)
	_check(bool(gs.get(&"core_exposed")), "y la cuenta pasa al 99 %%")
	balance.core_reveal_scan_sec = scan_sec
	gs.call(&"reset")


func _check(cond: bool, what: String) -> void:
	if not cond:
		_ok = false
		push_error("FALLO: " + what)
	else:
		print("  ok: ", what)
