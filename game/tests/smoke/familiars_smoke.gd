extends SceneTree
## Familiares: sin la mejora no hay jaula ni familiares; con "Familiar" nivel 2 aparecen la jaula y
## dos recolectores que recogen los fragmentos sueltos del suelo, los echan a la tolva y tiran de
## la palanca (la trituradora da maná); el Familiar hechicero lanza chispas de verdad que quitan
## esencia sin tocar la racha del mago; los que se compran con el Grimorio abierto aparecen al
## cerrarlo, delante del mago; y al volver a cargar la escena siguen ahí (salen de las
## mejoras compradas). No toca la partida guardada.
## godot --headless --path game --script res://tests/smoke/familiars_smoke.gd

const FLOCK_PATH: NodePath = ^"WorldView/WorldViewport/FamiliarFlock"

var _ok: bool = true


func _initialize() -> void:
	root.get_node(^"SaveSystem").set(&"enabled", false)
	var gs: Node = root.get_node(^"GameState")
	var events: Node = root.get_node(^"Events")
	gs.call(&"reset")
	change_scene_to_file("res://main/main.tscn")
	await process_frame
	await process_frame
	await _settle()
	var flock: Node3D = current_scene.get_node(FLOCK_PATH)
	var nest: Node3D = flock.get(&"nest")
	_check(int(flock.call(&"active_count")) == 0, "sin mejora no hay familiares")
	_check(not nest.visible, "sin mejora no hay jaula")
	var prog: RefCounted = gs.get(&"progression")
	var levels: Dictionary = prog.get(&"upgrade_levels")
	levels[&"familiar"] = 2
	events.emit_signal(&"upgrade_bought", &"familiar", 2)
	await process_frame
	_check(int(flock.call(&"active_count", 0)) == 2, "dos recolectores")
	_check(nest.visible, "la jaula aparece")
	# Fragmentos sueltos por el suelo, lejos del jugador: dos viajes llenos (uno por recolector) y
	# tres más, que quedan por debajo de `lever_at` y hay que triturar igual.
	var per_trip: int = mini(6, int(load("res://data/familiars/collector.tres").get(&"carry")))
	var loose: int = 2 * per_trip + 3
	var pool: Node3D = current_scene.get_tree().get_first_node_in_group(&"shard_pool")
	var shard_type: Resource = load("res://data/shards/shard.tres")
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i: int in loose:
		var p := Vector3(rng.randf_range(-26.0, -14.0), 1.5, rng.randf_range(46.0, 54.0))
		pool.call(&"spawn", p, Vector3.UP, shard_type, 1, 0.2)
	var mana0: int = int(prog.get(&"mana"))
	var crusher: Node3D = current_scene.get_tree().get_first_node_in_group(&"crystal_crusher")
	var t: float = 0.0
	var max_hopper: int = 0
	while t < 90.0:
		await process_frame
		t += current_scene.get_process_delta_time()
		max_hopper = maxi(max_hopper, int(crusher.call(&"queued_count")))
		if int(flock.get(&"pulls")) >= 1 and int(prog.get(&"mana")) > mana0:
			break
	_check(
		int(flock.get(&"dropped")) >= 6, "echan fragmentos a la tolva (%d)" % flock.get(&"dropped")
	)
	_check(max_hopper >= 6, "la tolva los recibe (%d)" % max_hopper)
	_check(int(flock.get(&"pulls")) >= 1, "tiran de la palanca")
	_check(int(prog.get(&"mana")) > mana0, "la trituradora da maná (%d)" % prog.get(&"mana"))
	print("  recolección en %.1f s" % t)
	# Los que sobran (menos de `lever_at`) también se trituran cuando ya no queda nada que
	# recoger: no se quedan en la tolva para siempre.
	t = 0.0
	while t < 90.0:
		await process_frame
		t += current_scene.get_process_delta_time()
		if (
			int(flock.get(&"dropped")) >= loose
			and int(crusher.call(&"queued_count")) == 0
			and not bool(crusher.call(&"is_busy"))
		):
			break
	_check(
		int(flock.get(&"dropped")) >= loose, "recogen los %d (%d)" % [loose, flock.get(&"dropped")]
	)
	_check(
		int(crusher.call(&"queued_count")) == 0 and int(flock.get(&"pulls")) >= 2,
		"y trituran los últimos aunque sean pocos (%d tirones)" % flock.get(&"pulls")
	)
	# Comprado con el Grimorio abierto: aparece al cerrarlo, delante del mago.
	events.emit_signal(&"grimoire_opened")
	levels[&"familiar"] = 3
	events.emit_signal(&"upgrade_bought", &"familiar", 3)
	await process_frame
	_check(int(flock.call(&"active_count", 0)) == 2, "con el Grimorio abierto aún no llega")
	events.emit_signal(&"grimoire_closed")
	await process_frame
	_check(int(flock.call(&"active_count", 0)) == 3, "al cerrarlo llega el tercero")
	var player: Node3D = current_scene.get_tree().get_first_node_in_group(&"player")
	var near: bool = false
	for f: Node3D in flock.call(&"familiars"):
		if (
			bool(f.call(&"is_active"))
			and f.global_position.distance_to(player.global_position) < 6.0
		):
			near = true
	_check(near, "y aparece delante del mago")
	# El hechicero: chispas que quitan esencia; la racha del mago no se mueve.
	var essence0: int = int(prog.get(&"essence"))
	var streaks: Array[int] = [0]
	var on_streak: Callable = func(s: int) -> void: streaks[0] = maxi(streaks[0], s)
	events.connect(&"streak_changed", on_streak)
	levels[&"familiar_caster"] = 1
	events.emit_signal(&"upgrade_bought", &"familiar_caster", 1)
	await process_frame
	_check(int(flock.call(&"active_count", 1)) == 1, "un hechicero")
	var caster: Node3D = null
	for f: Node3D in flock.call(&"familiars"):
		if bool(f.call(&"is_active")) and int(f.get(&"def").get(&"role")) == 1:
			caster = f
	t = 0.0
	while t < 40.0 and int(caster.get(&"casts")) < 2:
		await process_frame
		t += current_scene.get_process_delta_time()
	for i: int in 90:
		await process_frame
	_check(int(caster.get(&"casts")) >= 2, "el hechicero lanza (%d)" % caster.get(&"casts"))
	_check(int(prog.get(&"essence")) < essence0, "sus chispas quitan esencia")
	_check(streaks[0] == 0, "y no cuentan para la racha")
	events.disconnect(&"streak_changed", on_streak)
	# Al recargar la escena vuelven solos (salen de las mejoras compradas).
	change_scene_to_file("res://main/main.tscn")
	await process_frame
	await process_frame
	await _settle()
	var flock2: Node3D = current_scene.get_node(FLOCK_PATH)
	_check(int(flock2.call(&"active_count")) == 4, "al recargar siguen los cuatro familiares")
	_check((flock2.get(&"nest") as Node3D).visible, "y su jaula")
	# Sin la mejora (nueva partida) se retiran.
	levels[&"familiar"] = 0
	levels[&"familiar_caster"] = 0
	events.emit_signal(&"upgrade_bought", &"", 0)
	await process_frame
	_check(int(flock2.call(&"active_count")) == 0, "sin mejoras se retiran")
	# Que terminen los hilos que rehacen la malla del cristal antes de salir.
	for i: int in 120:
		await process_frame
	print("familiars_smoke: ", "OK" if _ok else "FALLO")
	quit(0 if _ok else 1)


## Espera a la pantalla de carga y cierra el título.
func _settle() -> void:
	for i: int in 240:
		await process_frame
	var menu: Node = current_scene.get_node(^"HUDLayer/Hud/GameMenu")
	if bool(menu.call(&"is_open")):
		menu.call(&"_close")
	await process_frame


func _check(cond: bool, what: String) -> void:
	print(("  ok  " if cond else "  FALLO  ") + what)
	if not cond:
		_ok = false
		push_error("FALLO: " + what)
