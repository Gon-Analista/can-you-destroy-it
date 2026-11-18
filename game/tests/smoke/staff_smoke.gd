extends SceneTree
## El báculo y las combinaciones triples (GDD 5.2): cada triple tiene tres elementos, textos,
## aspecto y se resuelve en cualquier orden (sin pisar a las parejas); el Báculo pide la Tierra
## y el Pilón al 10 %; al comprarlo aparece en primera persona con la gema en el Rayo; R cambia
## la gema entre los elementos despiertos; manos + gema = triple (si no, la pareja de siempre);
## la Tormenta Elemental se queda sobre el cristal y le quita esencia durante varios segundos;
## el Glaciar Tronante y la Supernova golpean y se descubren; el Libro enseña las triples en su
## propia página. No toca la partida guardada.
## godot --headless --path game --script res://tests/smoke/staff_smoke.gd

const PLAYER_PATH: NodePath = ^"WorldView/WorldViewport/Player"
const BOOK_PATH: NodePath = ^"HUDLayer/Hud/SpellBook"

var _ok: bool = true
var _caster: Node
var _prog: RefCounted


func _initialize() -> void:
	root.get_node(^"SaveSystem").set(&"enabled", false)
	var gs: Node = root.get_node(^"GameState")
	gs.call(&"reset")
	_check_data()
	change_scene_to_file("res://main/main.tscn")
	for i: int in 240:
		await process_frame
	var main: Node = current_scene
	var menu: Node = main.get_node(^"HUDLayer/Hud/GameMenu")
	if bool(menu.call(&"is_open")):
		menu.call(&"_close")
	var player: Node3D = main.get_node(PLAYER_PATH)
	_caster = player.call(&"get_caster")
	_prog = gs.get(&"progression")
	var levels: Dictionary = _prog.get(&"upgrade_levels")
	for id: String in ["awaken_frost", "awaken_bolt", "awaken_earth"]:
		levels[StringName(id)] = 1
	var staff_node: UpgradeNode = _upgrade(gs, &"staff")
	var book: Node = main.get_node(BOOK_PATH)
	var storm_recipe: Resource = load("res://data/spells/recipe_elemental_storm.tres")
	_check(book.call(&"state_of", storm_recipe) == &"locked", "sin báculo, la triple tiene candado")
	# El Báculo pide el Pilón al 10 %.
	_prog.set(&"mana", 1000000)
	_check(_prog.call(&"purchase_block", staff_node) == &"locked", "el Báculo pide el Pilón")
	_prog.set(&"pylon_progress", 100000)
	_check(_prog.call(&"purchase_block", staff_node) == &"", "con el Pilón al 10 %, se compra")
	var hands: Node = player.get_node(^"Hands")
	var view: Node = hands.get(&"staff")
	_check(view != null and not bool(view.call(&"is_shown")), "el báculo no se ve antes")
	_check(bool(gs.call(&"buy_upgrade", staff_node)), "se compra el Báculo")
	await process_frame
	var staff: RefCounted = _caster.get(&"staff")
	_check(bool(view.call(&"is_shown")), "el báculo aparece en primera persona")
	_check(int(staff.get(&"element_index")) == 2, "la gema empieza en el Rayo")
	# R: la gema recorre los elementos despiertos (el Arcano aún duerme).
	_caster.call(&"_cycle_staff", 1)
	_check(int(staff.get(&"element_index")) == 3, "R: la gema pasa a la Tierra")
	_caster.call(&"_cycle_staff", 1)
	_check(int(staff.get(&"element_index")) == 0, "R: salta el Arcano dormido y vuelve a la Chispa")
	_caster.call(&"_cycle_staff", -1)
	_check(int(staff.get(&"element_index")) == 3, "rueda abajo: vuelve a la Tierra")
	# Manos + gema = triple; si no, la pareja.
	_set_hands(0, 1, 0)
	var pair: Resource = _caster.call(&"recipe_for_hands")
	_check(pair != null and pair.get(&"id") == &"thermal_shock", "sin triple: la pareja de siempre")
	_set_hands(0, 1, 2)
	var triple: Resource = _caster.call(&"recipe_for_hands")
	_check(triple != null and triple.get(&"id") == &"elemental_storm", "Chispa+Escarcha+Rayo")
	# Tormenta Elemental contra el cristal: daña durante varios segundos.
	player.global_position = Vector3(0.0, 0.3, 60.0)
	player.rotation.y = 0.0
	(player.get_node(^"Head") as Node3D).rotation.x = deg_to_rad(8.0)
	await process_frame
	var before: int = int(_prog.get(&"essence"))
	_cast(storm_recipe)
	await create_timer(float(storm_recipe.get(&"charge_sec")) + 0.3).timeout
	_caster.call(&"try_release_combine")
	var delivery: Node = _caster.get_node(^"Delivery")
	var storm: Node = delivery.call(&"storm")
	await create_timer(2.4).timeout
	_check(bool(storm.call(&"is_raging")), "la nube se queda descargando")
	var samples: Array[int] = []
	for k: int in 4:
		samples.append(int(_prog.get(&"essence")))
		await create_timer(1.5).timeout
	samples.append(int(_prog.get(&"essence")))
	var drops: int = 0
	for k: int in samples.size() - 1:
		if samples[k + 1] < samples[k]:
			drops += 1
	_check(samples[0] < before, "la primera descarga (el rayo) ya ha quitado esencia")
	_check(drops >= 3, "sigue quitando esencia con el tiempo (%s)" % [samples])
	_check(int(storm.call(&"strikes_done")) >= 6, "descargas: %d" % storm.call(&"strikes_done"))
	_check(_found(&"elemental_storm"), "la Tormenta se descubre")
	_check(float(storm.call(&"lock_left")) > 0.0, "sólo una tormenta a la vez")
	_check(not bool(_caster.call(&"try_begin_combine")), "otra tormenta no se carga aún")
	# Otra triple: Glaciar Tronante (Escarcha + Tierra + Rayo).
	_set_hands(1, 3, 2)
	await _cast_and_wait(load("res://data/spells/recipe_thunder_glacier.tres"))
	# Supernova: despierta el Arcano (Chispa + Tierra en las manos, Arcano en la gema).
	levels[&"awaken_arcane"] = 1
	_set_hands(0, 3, 4)
	await _cast_and_wait(load("res://data/spells/recipe_supernova.tres"))
	for k: int in 30:
		if float(storm.call(&"lock_left")) <= 0.0:
			break
		await create_timer(0.5).timeout
	_check(float(storm.call(&"lock_left")) <= 0.0, "pasado el cierre, se puede lanzar otra")
	# El Libro enseña las triples en su página.
	book.call(&"open")
	book.call(&"open_page", 1)
	await process_frame
	var listed: Array = book.call(&"_list")
	_check(listed.size() == 5, "el Libro tiene 5 triples")
	var rows: Array = book.get(&"_rows")
	_check(
		String((rows[0] as Label).text) == "TORMENTA ELEMENTAL",
		"la Tormenta descubierta, con su nombre: %s" % (rows[0] as Label).text
	)
	_check(String((rows[3] as Label).text) == "???", "lo no descubierto, con acertijo")
	_check(book.call(&"state_of", listed[3]) == &"unknown", "con báculo ya no tiene candado")
	book.call(&"close")
	print("staff_smoke: ", "OK" if _ok else "FALLO")
	quit(0 if _ok else 1)


## Datos: cada triple tiene tres elementos, se resuelve en cualquier orden y no hay dos iguales.
func _check_data() -> void:
	var sc: Script = load("res://spells/staff_combos.gd")
	var triples: Array = sc.get(&"TRIPLES")
	_check(triples.size() >= 4, "al menos cuatro triples (%d)" % triples.size())
	for r: Resource in triples:
		var els: Array = r.get(&"elements")
		var id: StringName = r.get(&"id")
		_check(els.size() == 3 and bool(r.call(&"is_triple")), "%s: tres elementos" % id)
		_check(r.get(&"tier") != null and r.get(&"visual") != null, "%s: aspecto" % id)
		_check(String(r.get(&"riddle")) != "", "%s: acertijo" % id)
		_check(String(r.get(&"description")) != "", "%s: descripción" % id)
		_check(not (r.get(&"impact_sfx") as Array).is_empty(), "%s: sonido" % id)
		for order: Array in [[0, 1, 2], [2, 0, 1], [1, 2, 0]]:
			var got: Resource = sc.call(&"triple_for", els[order[0]], els[order[1]], els[order[2]])
			_check(got == r, "%s en el orden %s" % [id, order])
		_check(not bool(r.call(&"matches", els[0], els[1])), "%s no es una pareja" % id)
	_check(sc.call(&"triple_for", &"spark", &"spark", &"spark") == null, "tres chispas: nada")
	var storm: Resource = sc.call(&"triple_for", &"bolt", &"spark", &"frost")
	_check(storm != null and storm.get(&"id") == &"elemental_storm", "la Tormenta Elemental existe")
	_check(int(storm.get(&"delivery")) == 9 and float(storm.get(&"storm_sec")) > 3.0, "es tormenta")


func _upgrade(gs: Node, id: StringName) -> UpgradeNode:
	for n: UpgradeNode in gs.get(&"UPGRADES"):
		if n.id == id:
			return n
	return null


func _set_hands(left: int, right: int, gem: int) -> void:
	(_caster.get(&"hand_element") as Array)[0] = left
	(_caster.get(&"hand_element") as Array)[1] = right
	(_caster.get(&"staff") as RefCounted).set(&"element_index", gem)


func _cast(recipe: Resource) -> void:
	_caster.set(&"_cooldown", PackedFloat32Array([0.0, 0.0]))
	var now: Resource = _caster.call(&"recipe_for_hands")
	_check(now == recipe, "resuelve %s" % recipe.get(&"id"))
	_check(bool(_caster.call(&"try_begin_combine")), "%s: se juntan las manos" % recipe.get(&"id"))


func _cast_and_wait(recipe: Resource) -> void:
	await create_timer(0.3).timeout
	var before: int = int(_prog.get(&"essence"))
	_cast(recipe)
	await create_timer(float(recipe.get(&"charge_sec")) + 0.3).timeout
	_caster.call(&"try_release_combine")
	var waited: float = 0.0
	while int(_prog.get(&"essence")) >= before and waited < 9.0:
		await create_timer(0.2).timeout
		waited += 0.2
	_check(int(_prog.get(&"essence")) < before, "%s: quita esencia" % recipe.get(&"id"))
	_check(_found(recipe.get(&"id")), "%s: descubierta" % recipe.get(&"id"))


func _found(id: StringName) -> bool:
	return (_prog.get(&"discovered_recipes") as Array).has(id)


func _check(cond: bool, what: String) -> void:
	if not cond:
		_ok = false
		push_error("FALLO: " + what)
	else:
		print("  ok: ", what)
