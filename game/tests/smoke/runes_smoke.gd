extends SceneTree
## Las runas y la Mesa de Runas (GDD 4.3 y 5.3): la mesa está sellada hasta el 10 % del Pilón;
## en su pantalla se aprenden, se suben, se inscriben y se borran, con tantas activas como ranuras;
## cada runa cambia un lanzamiento de verdad por SpellCaster (chispas de más, rebote, túnel,
## eco, Cosecha con menos daño y más maná) y las chispas de más y los rebotes revientan bichos; las
## runas y las ranuras se guardan y se cargan. No toca la partida guardada.
## godot --headless --path game --script res://tests/smoke/runes_smoke.gd

const PLAYER_PATH: NodePath = ^"WorldView/WorldViewport/Player"
const HERD_PATH: NodePath = ^"WorldView/WorldViewport/CritterHerd"
const SCREEN_PATH: NodePath = ^"HUDLayer/Hud/RuneScreen"
## Scripts que nombran autoloads: se cargan (un test --script no puede nombrarlos).
const CASTER_SCRIPT: String = "res://spells/runes/rune_caster.gd"
const POOL_SCRIPT: String = "res://crystal/shard_pool.gd"

var _ok: bool = true
var _gs: Node
var _prog: RefCounted
var _caster: Node
var _runes: Node
var _herd: Node3D
## Golpes al cristal desde que se limpió: todos, los de las runas, los ecos y los que perforan.
var _hits: Array[RefCounted] = []


func _initialize() -> void:
	root.get_node(^"SaveSystem").set(&"enabled", false)
	_gs = root.get_node(^"GameState")
	_gs.call(&"reset")
	_prog = _gs.get(&"progression")
	_check_rules()
	change_scene_to_file("res://main/main.tscn")
	await process_frame
	await process_frame
	await _wait(4.0)
	var main: Node = current_scene
	var menu: Node = main.get_node(^"HUDLayer/Hud/GameMenu")
	if bool(menu.call(&"is_open")):
		menu.call(&"_close")
	var player: Node3D = main.get_node(PLAYER_PATH)
	_caster = player.call(&"get_caster")
	_runes = (_caster.get(&"_delivery") as Node).get(&"runes")
	_herd = main.get_node(HERD_PATH)
	root.get_node(^"Events").connect(
		&"spell_impacted", func(h: RefCounted) -> void: _hits.append(h)
	)
	await _check_table(player)
	await _check_screen(main)
	player.global_position = Vector3(0.0, 0.3, 60.0)
	player.rotation.y = 0.0
	(player.get_node(^"Head") as Node3D).rotation.x = deg_to_rad(10.0)
	_caster.call(&"set_debug_level", 4)
	_herd.call(&"debug_pop", 0, true)
	await _wait(1.0)
	await _check_multishot()
	await _check_bounce()
	await _check_pierce()
	await _check_echo()
	await _check_harvest()
	await _check_critters(player)
	_check_save()
	print("runes_smoke: OK" if _ok else "runes_smoke: FAILED")
	quit(0 if _ok else 1)


## Reglas puras: sellada antes del 10 %, una ranura al abrirse, no se inscribe sin comprar.
func _check_rules() -> void:
	var prog: Progression = _prog as Progression
	_check(not RuneBook.table_unlocked(prog), "la mesa empieza sellada")
	_check(RuneBook.slot_count(prog) == 0, "sin ranuras con la mesa sellada")
	var multi: RuneDef = RuneBook.RUNES[0]
	_check(prog.purchase_block(multi) == &"locked", "no se compra una runa antes del 10 %")
	prog.upgrade_levels[multi.id] = 1
	_check(not RuneBook.inscribe(prog, multi.id), "ni se inscribe con la mesa sellada")
	prog.upgrade_levels.erase(multi.id)
	_set_pylon(0.1)
	_check(RuneBook.table_unlocked(prog), "al 10 % se abre")
	_check(RuneBook.slot_count(prog) == 1, "con una ranura")
	_check(RuneBook.inscribe_block(prog, multi.id) == &"unbought", "hay que aprenderla antes")
	_check(RuneBook.harvest_damage(prog) == 1.0, "sin Cosecha, el daño de siempre")
	_set_pylon(0.0)


func _check_table(player: Node3D) -> void:
	var table: Node3D = get_first_node_in_group(&"rune_table")
	_check(table != null, "hay Mesa de Runas")
	if table == null:
		return
	var sanctum: Node3D = get_first_node_in_group(&"sanctum")
	var d: float = (
		Vector2(
			table.global_position.x - sanctum.global_position.x,
			table.global_position.z - sanctum.global_position.z
		)
		. length()
	)
	_check(d > 6.0 and d < 12.0, "junto al Santuario, sin pisar su atril (%.1f m)" % d)
	player.global_position = table.global_position + table.global_basis.z * 1.8 + Vector3.UP * 0.2
	await _wait(0.3)
	_check(bool(table.call(&"player_in_range")), "el jugador llega a la mesa")
	_check(not bool(table.call(&"is_unlocked")), "sellada al principio")
	var sealed: String = TranslationServer.translate(
		"MESA DE RUNAS: SELLADA HASTA EL PILÓN AL %d %%"
	)
	_check(String(table.call(&"prompt")) == sealed % 10, "el aviso dice que está sellada")
	_set_pylon(0.12)
	await _wait(0.8)
	_check(bool(table.call(&"is_unlocked")), "al pasar el 10 % la mesa despierta")


func _check_screen(main: Node) -> void:
	var screen: Control = main.get_node(SCREEN_PATH)
	var prog: Progression = _prog as Progression
	root.get_node(^"Events").emit_signal(&"rune_table_requested")
	await _wait(0.4)
	_check(bool(screen.get(&"is_open")), "F abre la pantalla de la mesa")
	prog.mana = 0
	_check(not bool(screen.call(&"buy", 0)), "sin maná no se aprende")
	prog.mana = 1_000_000
	_check(bool(screen.call(&"buy", 0)), "se aprende el Multidisparo")
	_check(RuneBook.is_inscribed(prog, &"rune_multishot"), "y se inscribe solo en la ranura libre")
	_check(bool(screen.call(&"buy", 0)), "se sube de nivel")
	_check(prog.get_level(&"rune_multishot") == 2, "a nivel 2")
	_check(bool(screen.call(&"buy", 1)), "se aprende el Rebote")
	_check(not RuneBook.is_inscribed(prog, &"rune_bounce"), "sin ranura libre no se inscribe")
	_check(not bool(screen.call(&"toggle", 1)), "ni a mano: sólo hay una ranura")
	_check(not bool(screen.call(&"buy_slot")), "la segunda ranura pide el Pilón al 25 %")
	_set_pylon(0.3)
	_check(bool(screen.call(&"buy_slot")), "se compra la segunda ranura")
	_check(RuneBook.slot_count(prog) == 2, "dos ranuras")
	_check(bool(screen.call(&"toggle", 1)), "ahora sí se inscribe el Rebote")
	_check(RuneBook.used_slots(prog) == 2, "dos runas activas")
	_check(bool(screen.call(&"buy", 2)), "se aprende la Perforación")
	_check(not bool(screen.call(&"toggle", 2)), "una tercera no cabe")
	_check(bool(screen.call(&"toggle", 0)), "se borra el Multidisparo")
	_check(not RuneBook.is_inscribed(prog, &"rune_multishot"), "ya no está inscrito")
	_check(prog.get_level(&"rune_multishot") == 2, "pero se queda aprendido")
	screen.call(&"close")
	await _wait(0.5)
	_check(not bool(screen.get(&"is_open")), "se cierra")
	# Para los lanzamientos: todas aprendidas a nivel 2 y tres ranuras.
	for def: RuneDef in RuneBook.RUNES:
		prog.upgrade_levels[def.id] = 2
	prog.upgrade_levels[RuneBook.SLOTS.id] = 2


## Sólo `ids` inscritas (en ese orden).
func _only(ids: Array[StringName]) -> void:
	var prog: Progression = _prog as Progression
	prog.inscribed_runes.clear()
	for id: StringName in ids:
		_check(RuneBook.inscribe(prog, id), "se inscribe %s" % id)
	root.get_node(^"Events").emit_signal(&"runes_changed")


## Lanza con la mano `side` (sin bichos cerca que se lleven el golpe) y espera `sec` s.
func _cast_and_wait(sec: float, side: int = 0, clear_critters: bool = true) -> void:
	if clear_critters:
		_hide_critters()
	_hits.clear()
	_caster.set(&"_cooldown", PackedFloat32Array([0.0, 0.0]))
	await process_frame
	_caster.call(&"try_cast", side)
	await _wait(sec)


func _count(prop: StringName) -> int:
	var n: int = 0
	for h: RefCounted in _hits:
		if bool(h.get(prop)):
			n += 1
	return n


func _check_multishot() -> void:
	_only([&"rune_multishot"])
	_hide_critters()
	_hits.clear()
	_caster.set(&"_cooldown", PackedFloat32Array([0.0, 0.0]))
	await process_frame
	_caster.call(&"try_cast", 0)
	var flying: int = 0
	for p: Node in _runes.get(&"_multi_pool"):
		if bool(p.get(&"active")):
			flying += 1
	_check(flying == 2, "Multidisparo 2: salen dos chispas de más (%d)" % flying)
	await _wait(2.0)
	var extra: int = _count(&"rune_spawn")
	_check(extra >= 1, "las chispas de más golpean el cristal (%d)" % extra)
	_check(_hits.size() >= 2, "más golpes que sin la runa (%d)" % _hits.size())


func _check_bounce() -> void:
	_only([&"rune_bounce"])
	await _cast_and_wait(2.6)
	var carried: bool = false
	for h: RefCounted in _hits:
		if int(h.get(&"rune_bounces")) == 2 and not bool(h.get(&"rune_spawn")):
			carried = true
	_check(carried, "el golpe lleva sus dos rebotes")
	var bounces: int = _count(&"rune_spawn")
	_check(bounces >= 1, "rebota y vuelve a golpear (%d rebotes)" % bounces)
	for h: RefCounted in _hits:
		if bool(h.get(&"rune_spawn")):
			_check(float(h.get(&"size")) >= 0.6, "un rebote no es un golpe flojo")
			break


func _check_pierce() -> void:
	_only([&"rune_pierce"])
	_caster.call(&"set_debug_level", 9)
	var essence0: int = int(_prog.get(&"essence"))
	await _cast_and_wait(1.6)
	var main_hit: RefCounted = null
	for h: RefCounted in _hits:
		if float(h.get(&"rune_pierce")) > 0.0:
			main_hit = h
	_check(main_hit != null, "el golpe perfora")
	if main_hit == null:
		_caster.call(&"set_debug_level", 4)
		return
	var dmg: int = int(main_hit.get(&"damage"))
	var lost: int = essence0 - int(_prog.get(&"essence"))
	var want: float = float(dmg) * (1.0 + float(main_hit.get(&"rune_pierce")) * 0.7)
	_check(float(lost) >= want, "el túnel arranca más cristal (%d de %d)" % [lost, dmg])
	_caster.call(&"set_debug_level", 4)


func _check_echo() -> void:
	_only([&"rune_echo"])
	var def: RuneDef = RuneBook.def_of(&"rune_echo")
	var values: PackedFloat32Array = def.values
	def.values = PackedFloat32Array([0, 100, 100, 100])
	await _cast_and_wait(2.0)
	_check(_count(&"echo") >= 1, "con eco seguro sale la copia fantasma y golpea")
	var spells: int = int(_prog.get(&"spells_cast"))
	_check(spells > 0, "se cuentan los hechizos")
	def.values = values


func _check_harvest() -> void:
	_only([])
	var plain: int = await _plain_cast()
	var shard: Resource = (load(POOL_SCRIPT).get(&"TYPES") as Array)[2]
	var value0: int = int(_gs.call(&"shard_value", shard))
	_only([&"rune_harvest"])
	var reaped: int = await _plain_cast()
	var def: RuneDef = RuneBook.def_of(&"rune_harvest")
	var want: int = maxi(1, roundi(float(plain) * def.damage_at(2)))
	_check(plain > 0 and reaped == want, "Cosecha: menos daño (%d -> %d)" % [plain, reaped])
	var value1: int = int(_gs.call(&"shard_value", shard))
	var want_v: int = maxi(1, roundi(float(shard.get(&"value")) * def.value_at(2)))
	_check(
		value1 == want_v and value1 > value0,
		"y más maná por fragmento (%d -> %d)" % [value0, value1]
	)


## Lanza hasta tener un golpe no resonante en el cristal (como mucho cuatro veces); su daño.
func _plain_cast() -> int:
	for attempt: int in 4:
		await _cast_and_wait(1.4)
		var d: int = _plain_damage()
		if d > 0:
			return d
	return -1


## Daño del primer golpe no resonante que no sale de una runa (-1 si no hay).
func _plain_damage() -> int:
	for h: RefCounted in _hits:
		if not bool(h.get(&"resonant")) and not bool(h.get(&"rune_spawn")):
			return int(h.get(&"damage"))
	return -1


## Las chispas de más revientan bichos (en el suelo a los lados de la mira) y un rebote salta a
## un bicho que esté cerca del golpe.
func _check_critters(player: Node3D) -> void:
	_herd.call(&"debug_pop", 0, true)
	await _wait(1.2)
	var def: Resource = (_herd.get(&"config") as Resource).get(&"species")[0]
	var cam: Camera3D = _caster.get(&"camera")
	var head: Node3D = player.get_node(^"Head")
	head.rotation.x = deg_to_rad(-16.0)
	await physics_frame
	await process_frame
	var fwd: Vector3 = -cam.global_basis.z
	var up: Vector3 = cam.global_basis.y
	var ground: Vector3 = _caster.call(&"_aim")["position"]
	var dist: float = cam.global_position.distance_to(ground)
	var fan: float = deg_to_rad(float(load(CASTER_SCRIPT).get(&"FAN_DEG")))
	for s: float in [-1.0, 1.0]:
		var dir: Vector3 = fwd.rotated(up, fan * s)
		var at: Vector3 = cam.global_position + dir * dist
		_herd.call(&"_spawn_at", def, at, false, cam.global_position)
	await physics_frame
	_only([&"rune_multishot"])
	var popped0: int = int(_prog.get(&"critters_popped"))
	await _cast_and_wait(1.5, 0, false)
	var popped: int = int(_prog.get(&"critters_popped")) - popped0
	_check(popped >= 1, "las chispas de más revientan bichos (%d)" % popped)
	# Rebote hacia un bicho junto al golpe en el cristal.
	_herd.call(&"debug_pop", 0, true)
	await _wait(1.2)
	head.rotation.x = deg_to_rad(4.0)
	await physics_frame
	await process_frame
	var aim: Dictionary = _caster.call(&"_aim")
	var flat: Vector3 = aim["normal"]
	flat.y = 0.0
	var spot: Vector3 = (aim["position"] as Vector3) + flat.normalized() * 3.0
	var c: Node3D = _herd.call(&"_spawn_at", def, spot, false, cam.global_position)
	await physics_frame
	var reach: float = float(load(CASTER_SCRIPT).get(&"BOUNCE_CRITTER_RADIUS"))
	var near: bool = (
		c != null and (c.call(&"center") as Vector3).distance_to(aim["position"]) < reach
	)
	_check(near, "hay un bicho junto al golpe")
	_only([&"rune_bounce"])
	popped0 = int(_prog.get(&"critters_popped"))
	await _cast_and_wait(2.0, 0, false)
	_check(int(_prog.get(&"critters_popped")) > popped0, "el rebote salta al bicho y lo revienta")
	head.rotation.x = deg_to_rad(4.0)


## Esconde los bichos al momento (sin reventarlos: no cuentan) para que no se lleven el golpe.
func _hide_critters() -> void:
	for c: Node in _herd.call(&"critters"):
		if bool(c.call(&"is_alive")):
			c.call(&"hide_now")


## Las runas aprendidas, las ranuras y las inscritas se guardan y se cargan.
func _check_save() -> void:
	var prog: Progression = _prog as Progression
	_only([&"rune_echo", &"rune_harvest"])
	var data: Dictionary = JSON.parse_string(JSON.stringify(prog.to_dict()))
	var fresh := Progression.new(prog.total_essence)
	fresh.load_dict(data)
	_check(fresh.get_level(&"rune_pierce") == 2, "el nivel de las runas se guarda")
	_check(RuneBook.slot_count(fresh) == 3, "y las ranuras")
	var ids: Array[StringName] = []
	for r: RuneDef in RuneBook.inscribed(fresh):
		ids.append(r.id)
	_check(ids == [&"rune_echo", &"rune_harvest"], "y las inscritas, en orden (%s)" % str(ids))


func _set_pylon(ratio: float) -> void:
	var prog: Progression = _prog as Progression
	prog.pylon_progress = ceili(ratio * float(prog.total_essence))


func _wait(sec: float) -> void:
	var t: float = 0.0
	while t < sec:
		await process_frame
		t += current_scene.get_process_delta_time() if current_scene else 0.016


func _check(cond: bool, what: String) -> void:
	if not cond:
		_ok = false
		printerr("  FALLA: " + what)
