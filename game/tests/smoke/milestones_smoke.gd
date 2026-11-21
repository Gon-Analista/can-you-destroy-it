extends SceneTree
## Los tres nodos hito del Grimorio (GDD 7):
## - Lanzamiento continuo: mantener un botón lanza esa mano una y otra vez y para al soltar; sin
##   el nodo, sólo el primer clic. Dos clics a la vez siguen combinando y, con una mano en ráfaga,
##   pulsar la otra junta las manos (sin disparo suelto de por medio); "clic para cargar" igual.
## - Vórtice: aspira los fragmentos sueltos y los manda a la tolva; no toca las Lágrimas del
##   Núcleo ni lo que ya va a buscar un familiar.
## - Rompefacetas: un golpe resonante arranca mucho más cristal (y esencia) con el nodo; nunca
##   por debajo del 99 % (Núcleo) y en el Corazón un golpe suelto no parte faceta.
## - Las tres mejoras se guardan y se cargan.
## godot --headless --path game --script res://tests/smoke/milestones_smoke.gd

const SPARK: Resource = preload("res://data/elements/spark.tres")

var _ok: bool = true
var _casts: Array[int] = []


func _initialize() -> void:
	root.get_node(^"SaveSystem").set(&"enabled", false)
	var gs: Node = root.get_node(^"GameState")
	gs.call(&"reset")
	_save_load(gs)
	change_scene_to_file("res://main/main.tscn")
	for i: int in 240:
		await process_frame
	var main: Node = current_scene
	var menu: Node = main.get_node(^"HUDLayer/Hud/GameMenu")
	if VariantCast.to_bool(menu.call(&"is_open")):
		menu.call(&"_close")
	paused = false
	var tutorial: Node = main.get_node(^"HUDLayer/Hud").get(&"tutorial")
	if tutorial:
		tutorial.call(&"skip")
	root.get_node(^"Events").connect(
		&"spell_cast", func(_t: SpellTier, side: int) -> void: _casts.append(side)
	)
	var world: Node = main.get_node(^"WorldView/WorldViewport")
	await _autocast(gs, world)
	await _vortex(gs, world)
	await _facets(gs, world)
	# Que terminen de rehacerse los trozos del cristal (en otros hilos) antes de salir.
	await _wait(2.0)
	print("milestones_smoke: ", "OK" if _ok else "FALLO")
	quit(0 if _ok else 1)


func _save_load(gs: Node) -> void:
	var prog: Progression = gs.get(&"progression")
	for id: StringName in [&"autocast", &"vortex", &"facet_break"]:
		var found: bool = false
		for n: UpgradeNode in gs.get(&"UPGRADES"):
			found = found or n.id == id
		_check(found, "%s está en GameState.UPGRADES" % id)
		prog.upgrade_levels[id] = 1
	var copy := Progression.new(prog.total_essence)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(prog.to_dict()))
	copy.load_dict(saved)
	for id: StringName in [&"autocast", &"vortex", &"facet_break"]:
		_check(copy.get_level(id) == 1, "%s se guarda y se carga" % id)
	gs.call(&"reset")


func _autocast(gs: Node, world: Node) -> void:
	var prog: Progression = gs.get(&"progression")
	var caster: Node = world.get_node(^"Player").call(&"get_caster")
	caster.set_process_unhandled_input(false)
	caster.call(&"set_tier", 4)
	var balance: BalanceConfig = gs.get(&"BALANCE")
	var hold: float = balance.autocast_hold_sec
	# Sin el nodo: mantener pulsado sólo lanza una vez.
	await _wait(1.5)
	_casts.clear()
	caster.call(&"_on_press", 0)
	await _wait(2.6)
	caster.call(&"_on_release", 0)
	_check(_casts == [0], "sin el nodo, mantener lanza una vez (%s)" % [_casts])
	# Con el nodo: ráfaga mientras se mantiene, y para al soltar.
	prog.upgrade_levels[&"autocast"] = 1
	await _wait(1.5)
	_casts.clear()
	caster.call(&"_on_press", 0)
	await _wait(0.1)
	_check(_casts == [0], "el primer clic sale como siempre")
	await _wait(3.0)
	var n_held: int = _casts.size()
	_check(n_held >= 3 and not _casts.has(1), "manteniendo, la mano lanza sola (%d)" % n_held)
	var auto: Node = caster.get_node(^"AutoCast")
	var channeling: Array = auto.get(&"channeling")
	_check(VariantCast.to_bool(channeling[0]), "la mano está en ráfaga")
	var hands: Node = world.get_node(^"Player/Hands")
	var tremble: PackedFloat32Array = hands.get(&"tremble")
	_check(tremble[0] > 0.5, "la mano tiembla")
	caster.call(&"_on_release", 0)
	await _wait(2.0)
	_check(_casts.size() == n_held, "al soltar para (%d -> %d)" % [n_held, _casts.size()])
	channeling = auto.get(&"channeling")
	_check(not VariantCast.to_bool(channeling[0]), "y deja de crepitar")
	# Un clic corto no se vuelve ráfaga (menos que el umbral).
	_casts.clear()
	caster.call(&"_on_press", 1)
	await _wait(hold * 0.5)
	caster.call(&"_on_release", 1)
	await _wait(2.0)
	_check(_casts == [1], "un clic corto sigue siendo un disparo (%s)" % [_casts])
	# Dos clics a la vez: combinación, como siempre.
	_casts.clear()
	caster.call(&"_on_press", 0)
	await process_frame
	caster.call(&"_on_press", 1)
	_check(VariantCast.to_bool(caster.call(&"is_combining")), "dos clics a la vez juntan las manos")
	await _wait(0.6)
	caster.call(&"_on_release", 0)
	_check(_casts == [2], "sale el combinado (%s)" % [_casts])
	await _wait(1.0)
	_check(_casts == [2], "el botón que sigue pulsado no vuelve a la ráfaga solo")
	caster.call(&"_on_release", 1)
	# Con una mano en ráfaga, pulsar la otra junta las dos (sin disparo suelto de la otra).
	await _wait(3.0)
	_casts.clear()
	caster.call(&"_on_press", 0)
	await _wait(1.2)
	caster.call(&"_on_press", 1)
	var joined: bool = false
	for i: int in 200:
		await process_frame
		if VariantCast.to_bool(caster.call(&"is_combining")):
			joined = true
			break
	_check(joined, "con una mano en ráfaga, la otra junta las manos")
	_check(not _casts.has(1), "sin disparo suelto de la otra mano (%s)" % [_casts])
	caster.call(&"_on_release", 1)
	caster.call(&"_on_release", 0)
	_check(_casts.has(2), "y sale el combinado al soltar")
	# Clic para cargar (accesibilidad): el siguiente clic suelta, aunque se tenga el nodo.
	var settings: Node = root.get_node(^"Settings")
	var hold_mode: bool = settings.get(&"hold_to_charge")
	settings.set(&"hold_to_charge", false)
	await _wait(3.0)
	_casts.clear()
	caster.call(&"_on_press", 0)
	await process_frame
	caster.call(&"_on_press", 1)
	caster.call(&"_on_release", 0)
	caster.call(&"_on_release", 1)
	_check(VariantCast.to_bool(caster.call(&"is_combining")), "clic para cargar: soltar no lanza")
	await _wait(0.5)
	caster.call(&"_on_press", 0)
	caster.call(&"_on_release", 0)
	_check(_casts == [2], "clic para cargar: el siguiente clic suelta (%s)" % [_casts])
	settings.set(&"hold_to_charge", hold_mode)
	prog.upgrade_levels.erase(&"autocast")


func _vortex(gs: Node, world: Node) -> void:
	var prog: Progression = gs.get(&"progression")
	var crystal: Node3D = world.get_node(^"MotherCrystal")
	var shards: Node = crystal.get_node(^"Shards")
	var tears: Node = crystal.get_node(^"CoreTears")
	var player: Node3D = world.get_node(^"Player")
	var vortex: Node = player.get_node(^"ManaVortex")
	var crusher: Node = world.get_tree().get_first_node_in_group(&"crystal_crusher")
	var flock: Node = world.get_tree().get_first_node_in_group(&"familiar_flock")
	var shard_t: ShardType = load("res://data/shards/shard.tres")
	# Lejos del cristal y de lo que ha soltado: fragmentos sueltos alrededor y una Lágrima.
	player.global_position = Vector3(-26.0, 1.0, 88.0)
	await _wait(0.3)
	var base: Vector3 = player.global_position
	# Se cuentan los de alrededor (no todos los del valle: los de los golpes de antes aún se
	# recogen o caducan y movían la cuenta).
	var before: int = _loose_around(shards, base, 40.0)
	for k: int in 10:
		var a: float = TAU * float(k) / 10.0
		var at: Vector3 = base + Vector3(cos(a), 0.0, sin(a)) * (10.0 + float(k) * 2.0)
		shards.call(&"spawn", at + Vector3.UP * 2.0, Vector3.UP, shard_t, 1, 0.2)
	tears.call(&"drop", base + Vector3(6, 3, 0), Vector3.UP)
	await _wait(2.0)
	_check(
		_loose_around(shards, base, 40.0) - before == 10,
		"sin el Vórtice, siguen en el suelo (%d)" % (_loose_around(shards, base, 40.0) - before)
	)
	# Un familiar ya va a por uno: el Vórtice no se lo quita.
	var claimed: int = VariantCast.to_int(
		shards.call(&"loose_near", base, 60.0, PackedInt32Array(), 0.0)
	)
	var claims_before: PackedInt32Array = flock.get(&"claims")
	flock.set(&"claims", PackedInt32Array([claimed]))
	prog.upgrade_levels[&"direct_send"] = 1
	prog.upgrade_levels[&"vortex"] = 1
	var hopper0: int = VariantCast.to_int(crusher.call(&"queued_count"))
	var caught0: int = vortex.get(&"caught_total")
	await _wait(7.0)
	var caught: int = VariantCast.to_int(vortex.get(&"caught_total")) - caught0
	_check(caught >= 9, "el Vórtice aspira los sueltos (%d)" % caught)
	_check(
		VariantCast.to_bool(shards.call(&"is_loose", claimed)),
		"el que va a buscar un familiar sigue en el suelo"
	)
	var sent: int = VariantCast.to_int(crusher.call(&"queued_count")) - hopper0
	_check(sent == caught, "y van a la tolva (%d)" % sent)
	_check(
		VariantCast.to_int(tears.call(&"loose_count")) == 1,
		"la Lágrima sigue ahí (la recoge el mago)"
	)
	flock.set(&"claims", claims_before)
	prog.upgrade_levels.erase(&"vortex")
	prog.upgrade_levels.erase(&"direct_send")


## Fragmentos sueltos a menos de `radius` m de `at`.
func _loose_around(shards: Node, at: Vector3, radius: float) -> int:
	var seen := PackedInt32Array()
	while true:
		var i: int = VariantCast.to_int(shards.call(&"loose_near", at, radius, seen, 0.0))
		if i < 0:
			return seen.size()
		seen.append(i)
	return seen.size()


func _facets(gs: Node, world: Node) -> void:
	var prog: Progression = gs.get(&"progression")
	var crystal: Node3D = world.get_node(^"MotherCrystal")
	var facets: Node = crystal.get_node(^"FacetBreaker")
	var spark: ElementDef = SPARK
	# Sin el nodo: un golpe resonante de 300.
	var e0: int = prog.essence
	crystal.call(&"receive_hit", _surface_hit(crystal, 0.0, 300))
	var plain: int = e0 - prog.essence
	_check(
		plain > 0 and VariantCast.to_int(facets.get(&"broken")) == 0,
		"resonante normal (%d)" % plain
	)
	prog.upgrade_levels[&"facet_break"] = 1
	await _wait(0.3)
	var e1: int = prog.essence
	crystal.call(&"receive_hit", _surface_hit(crystal, 1.3, 300))
	var big: int = e1 - prog.essence
	var slab: int = roundi(VariantCast.to_float(facets.get(&"last_essence")))
	_check(VariantCast.to_int(facets.get(&"broken")) == 1, "con el nodo, la faceta se rompe")
	_check(big > plain * 1.25, "arranca bastante más esencia (%d frente a %d)" % [big, plain])
	_check(
		slab >= (big - slab) * 3,
		"la losa es mucho mayor que el cráter (%d, %d)" % [slab, big - slab]
	)
	await _wait(3.0)
	# Nunca por debajo del 99 %.
	var floor_e: int = gs.get(&"core_floor")
	prog.essence = floor_e + 40
	crystal.call(&"receive_hit", _surface_hit(crystal, 2.6, 300))
	_check(prog.essence >= floor_e, "nunca baja del Núcleo (%d >= %d)" % [prog.essence, floor_e])
	prog.essence = prog.total_essence
	# En el Corazón, un golpe suelto no parte faceta (rebota); sólo un combinado.
	var heart := SpellHit.new()
	heart.resonant = true
	heart.by_player = true
	heart.damage = 300
	heart.layer = 3
	heart.tier = spark.tiers[0]
	_check(
		VariantCast.to_float(facets.call(&"try_break", heart)) == 0.0,
		"en el Corazón, suelto no rompe"
	)
	prog.upgrade_levels.erase(&"facet_break")


## Golpe resonante del mago en la cara del cristal hacia el mago, girando `turn` rad alrededor.
func _surface_hit(crystal: Node3D, turn: float, damage: int) -> SpellHit:
	var spark: ElementDef = SPARK
	var from: Vector3 = crystal.global_position + Vector3(sin(turn), 0.0, cos(turn)) * 120.0
	from.y = crystal.global_position.y + 22.0
	var s: Dictionary = crystal.call(&"surface_toward", from)
	var hit := SpellHit.new()
	hit.position = s["position"]
	var normal: Vector3 = s["normal"]
	hit.normal = normal.normalized()
	hit.direction = -hit.normal
	hit.damage = damage
	hit.resonant = true
	hit.by_player = true
	hit.element = &"spark"
	hit.element_def = spark
	hit.tier = spark.tiers[2]
	return hit


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout


func _check(cond: bool, what: String) -> void:
	if not cond:
		_ok = false
		push_error("FALLO: " + what)
	else:
		print("  ok: ", what)
