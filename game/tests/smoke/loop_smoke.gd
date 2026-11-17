extends SceneTree
## El bucle completo (GDD 2): la bolsa tiene tope, al acercarte al Pilón se vacía y sube el maná,
## en el Santuario se compra y la mejora cambia el hechizo.
## godot --headless --path game --script res://tests/smoke/loop_smoke.gd

var _failures: int = 0


func _initialize() -> void:
	_run()


func _run() -> void:
	# Primero que los autoloads terminen de arrancar (SaveSystem carga la partida guardada).
	await process_frame
	# Los autoloads no existen al compilar un script de --script: se buscan en el árbol y las
	# clases que los usan se tratan sin tipo.
	var gs: Node = root.get_node(^"GameState")
	var events: Node = root.get_node(^"Events")
	var prog: Progression = gs.get(&"progression")
	var state_before: Dictionary = prog.to_dict()
	gs.set(&"progression", Progression.new(1_000_000))
	prog = gs.get(&"progression")
	var main: Node = (load("res://main/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	for i: int in 20:
		await process_frame
	var player: Node3D = main.get_node(^"WorldView/WorldViewport/Player")
	var pylon: Node3D = main.get_node(^"WorldView/WorldViewport/ManaPylon")
	var splinter: ShardType = load("res://data/shards/splinter.tres")
	var full_events: Array[int] = [0]
	events.connect(&"bag_full", func() -> void: full_events[0] += 1)

	# Bolsa de 3 al empezar: el cuarto no cabe.
	for k: int in 3:
		_check(gs.call(&"collect_shard", splinter, Vector3.ZERO), "cabe el %d" % (k + 1))
	_check(not gs.call(&"collect_shard", splinter, Vector3.ZERO), "el cuarto no cabe")
	_check(full_events[0] == 1, "avisa de bolsa llena")

	# Junto a la trituradora, mantener F echa los cristales a la tolva; la palanca los tritura
	# y su maná entra en el Pilón. (La bolsa ya lleva 3 de antes.)
	var crusher: Node3D = pylon.call(&"crusher")
	player.global_position = crusher.global_position + Vector3(2.2, 0.3, 0.0)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var captured: bool = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if captured:
		Input.action_press(&"interact")
		await create_timer(1.8).timeout
		Input.action_release(&"interact")
		# El vuelo hasta la tolva dura hasta 1,4 s.
		await create_timer(1.6).timeout
	else:
		# Sin ventana no se captura el ratón: se echan a mano por la misma vía.
		for k: int in 3:
			pylon.call(
				&"launch_mote",
				gs.call(&"take_for_delivery"),
				crusher.call(&"hopper_mouth"),
				crusher
			)
		await create_timer(1.8).timeout
	_check(prog.bag_count() == 0, "mantener F vacía la bolsa en la tolva")
	_check(int(crusher.call(&"hopper_count")) == 3, "los cristales caen en la tolva")
	_check(prog.mana == 0, "en la tolva todavía no dan maná")
	_check(crusher.call(&"pull_lever"), "la palanca arranca la trituradora")
	await create_timer(3.0).timeout
	_check(int(crusher.call(&"hopper_count")) == 0, "la trituradora vacía la tolva")
	_check(
		prog.mana == 3 and prog.pylon_progress == 3,
		"cada astilla triturada da 1 de maná y de Pilón"
	)

	# Lejos del Pilón no se entrega.
	prog.collect_shard(&"splinter")
	player.global_position = Vector3(0, 0.3, 22)
	await create_timer(1.0).timeout
	_check(prog.bag_count() == 1, "lejos de la trituradora la bolsa no se toca")

	# Comprar Potencia cambia la Chispa (nivel y aspecto de la llama).
	prog.deliver(100)
	var power: UpgradeNode = load("res://data/upgrades/spark_power.tres")
	var caster: Node = player.call(&"get_caster")
	_check(int(caster.get(&"tier_index")) == 0, "se empieza con la Chispa")
	_check(gs.call(&"buy_upgrade", power), "se compra la Potencia")
	await process_frame
	_check(int(caster.get(&"tier_index")) == 1, "la Potencia sube el nivel de la Chispa")

	# El Grimorio sólo inscribe junto al atril.
	var grimoire: Node = main.get_node(^"HUDLayer/Hud/Grimoire")
	var bag: UpgradeNode = load("res://data/upgrades/bag.tres")
	events.emit_signal(&"grimoire_requested", false)
	grimoire.set(&"_selected", 0)
	grimoire.call(&"try_buy")
	_check(prog.get_level(&"bag") == 0, "lejos del atril no se inscribe")
	grimoire.set(&"_at_sanctum", true)
	grimoire.call(&"try_buy")
	_check(prog.get_level(&"bag") == 1, "junto al atril se inscribe")
	_check(gs.call(&"bag_capacity") == 10, "la bolsa sube a 10")
	_check(bag.cost_for_level(0) == 5, "la primera mejora cuesta 5 (GDD 8.1)")

	grimoire.call(&"close")
	# Saltar: con el jugador en el suelo, Espacio lo levanta y vuelve a caer.
	player.global_position = Vector3(0, 0.5, 32)
	await create_timer(0.8).timeout
	var y0: float = player.global_position.y
	Input.action_press(&"jump")
	await physics_frame
	await physics_frame
	Input.action_release(&"jump")
	await create_timer(0.25).timeout
	_check(player.global_position.y > y0 + 0.4, "Espacio salta")
	await create_timer(1.2).timeout
	_check(absf(player.global_position.y - y0) < 0.2, "y vuelve al suelo")

	gs.set(&"progression", Progression.new(1_000_000))
	(gs.get(&"progression") as Progression).load_dict(state_before)
	root.get_node(^"SaveSystem").call(&"save_game")
	print("loop_smoke: %s" % ("OK" if _failures == 0 else "%d fallos" % _failures))
	quit(1 if _failures > 0 else 0)


func _check(cond: bool, label: String) -> void:
	if not cond:
		_failures += 1
		printerr("FALLO: " + label)
