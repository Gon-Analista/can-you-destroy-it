extends SceneTree
## El báculo y las combinaciones triples (GDD 5.2): cada triple tiene tres elementos, textos,
## aspecto y se resuelve en cualquier orden (sin pisar a las parejas); el Báculo pide la Tierra
## y el Pilón al 10 %; al comprarlo aparece en primera persona con la gema en el Rayo; R cambia
## la gema entre los elementos despiertos; manos + gema = triple (si no, la pareja de siempre);
## la Tormenta Elemental se queda sobre el cristal y le quita esencia durante varios segundos;
## el Glaciar Tronante y la Supernova golpean y se descubren; el Libro enseña las triples en su
## propia página; la Vitrina del Báculo se enciende al comprarlo y abre su página. No toca la
## partida guardada.
## Con el báculo apagado (`StaffCombos.ENABLED`), sólo comprueba que no queda rastro de él.
## godot --headless --path game --script res://tests/smoke/staff_smoke.gd

const PLAYER_PATH: NodePath = ^"WorldView/WorldViewport/Player"
const BOOK_PATH: NodePath = ^"HUDLayer/Hud/SpellBook"
const GRIMOIRE_PATH: NodePath = ^"HUDLayer/Hud/Grimoire"
const HERD_PATH: NodePath = ^"WorldView/WorldViewport/CritterHerd"
const NOVA: Resource = preload("res://data/spells/recipe_supernova.tres")

var _ok: bool = true
var _caster: Node
var _prog: RefCounted


func _initialize() -> void:
	root.get_node(^"SaveSystem").set(&"enabled", false)
	var gs: Node = root.get_node(^"GameState")
	gs.call(&"reset")
	var staff_script: Script = load("res://spells/staff_combos.gd")
	if not VariantCast.to_bool(staff_script.get(&"ENABLED")):
		await _check_disabled(gs)
		return
	_check_data(staff_script)
	change_scene_to_file("res://main/main.tscn")
	for i: int in 240:
		await process_frame
	var main: Node = current_scene
	var menu: Node = main.get_node(^"HUDLayer/Hud/GameMenu")
	if VariantCast.to_bool(menu.call(&"is_open")):
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
	_check(
		VariantCast.to_bool(book.call(&"state_of", storm_recipe) == &"locked"),
		"sin báculo, la triple tiene candado"
	)
	# El Báculo pide el Pilón al 10 %.
	_prog.set(&"mana", 1000000)
	_check(
		VariantCast.to_bool(_prog.call(&"purchase_block", staff_node) == &"locked"),
		"el Báculo pide el Pilón"
	)
	_prog.set(&"pylon_progress", 100000)
	_check(
		VariantCast.to_bool(_prog.call(&"purchase_block", staff_node) == &""),
		"con el Pilón al 10 %, se compra"
	)
	var hands: Node = player.get_node(^"Hands")
	var view: Node = hands.get(&"staff")
	_check(
		view != null and not VariantCast.to_bool(view.call(&"is_shown")), "el báculo no se ve antes"
	)
	var vitrine: Node = main.get_tree().get_first_node_in_group(&"staff_vitrine")
	_check(vitrine != null, "la Vitrina del Báculo está junto al Santuario")
	_check(
		vitrine != null and not VariantCast.to_bool(vitrine.call(&"is_owned")),
		"la vitrina empieza apagada"
	)
	_check(VariantCast.to_bool(gs.call(&"buy_upgrade", staff_node)), "se compra el Báculo")
	await process_frame
	_check(
		vitrine != null and VariantCast.to_bool(vitrine.call(&"is_owned")),
		"al comprarlo, la vitrina se enciende"
	)
	# La vitrina abre el Grimorio por la constelación del Báculo.
	var grimoire: Node = main.get_node(GRIMOIRE_PATH)
	root.get_node(^"Events").emit_signal(&"grimoire_page_requested", &"staff")
	var page: Array = grimoire.get(&"PAGES")[VariantCast.to_int(grimoire.get(&"_page"))]
	_check(
		VariantCast.to_bool(VariantCast.to_bool(grimoire.get(&"is_open")) and page[0] == &"staff"),
		"la vitrina abre el Báculo"
	)
	grimoire.call(&"close")
	for i: int in 30:
		await process_frame
	var staff: RefCounted = _caster.get(&"staff")
	_check(VariantCast.to_bool(view.call(&"is_shown")), "el báculo aparece en primera persona")
	_check(VariantCast.to_int(staff.get(&"element_index")) == 2, "la gema empieza en el Rayo")
	# R: la gema recorre los elementos despiertos (el Arcano aún duerme).
	_caster.call(&"_cycle_staff", 1)
	_check(VariantCast.to_int(staff.get(&"element_index")) == 3, "R: la gema pasa a la Tierra")
	_caster.call(&"_cycle_staff", 1)
	_check(
		VariantCast.to_int(staff.get(&"element_index")) == 0,
		"R: salta el Arcano dormido y vuelve a la Chispa"
	)
	_caster.call(&"_cycle_staff", -1)
	_check(VariantCast.to_int(staff.get(&"element_index")) == 3, "rueda abajo: vuelve a la Tierra")
	# Girar la gema varias veces no deja una cola de avisos viejos: sólo queda el último (Tierra),
	# a la vista o esperando su turno.
	var loop: Node = main.get_node(^"HUDLayer/Hud/Loop")
	var hint: Label = loop.get(&"_hint")
	var topic: String = TranslationServer.translate("BÁCULO")
	var gem_hints: Array[String] = []
	if hint.visible and hint.text.get_slice(":", 0) == topic:
		gem_hints.append(hint.text)
	for h: Array in loop.get(&"_hint_queue"):
		if str(h[0]).get_slice(":", 0) == topic:
			gem_hints.append(str(h[0]))
	var earth: Resource = load("res://data/elements/earth.tres")
	var earth_name: String = TranslationServer.translate(str(earth.get(&"display_name")))
	_check(
		gem_hints.size() == 1 and gem_hints[0].contains(earth_name.to_upper()),
		"un solo aviso de la gema, el de ahora: %s" % [gem_hints]
	)
	# Manos + gema = triple; si no, la pareja.
	_set_hands(0, 1, 0)
	var pair: Resource = _caster.call(&"recipe_for_hands")
	_check(
		VariantCast.to_bool(pair != null and pair.get(&"id") == &"thermal_shock"),
		"sin triple: la pareja de siempre"
	)
	_set_hands(0, 1, 2)
	var triple: Resource = _caster.call(&"recipe_for_hands")
	_check(
		VariantCast.to_bool(triple != null and triple.get(&"id") == &"elemental_storm"),
		"Chispa+Escarcha+Rayo"
	)
	# Tormenta Elemental contra el cristal: daña durante varios segundos. Se apunta por encima de
	# la puntita del pie del cristal (con el cristal más grande llega casi al cruce de caminos y
	# la nube, encima de ella, mandaba casi todo a la hierba).
	player.global_position = Vector3(0.0, 0.3, 70.0)
	player.rotation.y = 0.0
	(player.get_node(^"Head") as Node3D).rotation.x = deg_to_rad(18.0)
	await process_frame
	var before: int = VariantCast.to_int(_prog.get(&"essence"))
	_cast(storm_recipe)
	await create_timer(VariantCast.to_float(storm_recipe.get(&"charge_sec")) + 0.3).timeout
	_caster.call(&"try_release_combine")
	var delivery: Node = _caster.get_node(^"Delivery")
	var storm: Node = delivery.call(&"storm")
	await create_timer(2.4).timeout
	_check(VariantCast.to_bool(storm.call(&"is_raging")), "la nube se queda descargando")
	var samples: Array[int] = []
	for k: int in 4:
		samples.append(VariantCast.to_int(_prog.get(&"essence")))
		await create_timer(1.5).timeout
	samples.append(VariantCast.to_int(_prog.get(&"essence")))
	var drops: int = 0
	for k: int in samples.size() - 1:
		if samples[k + 1] < samples[k]:
			drops += 1
	_check(samples[0] < before, "la primera descarga (el rayo) ya ha quitado esencia")
	_check(drops >= 3, "sigue quitando esencia con el tiempo (%s)" % [samples])
	_check(
		VariantCast.to_int(storm.call(&"strikes_done")) >= 6,
		"descargas: %d" % storm.call(&"strikes_done")
	)
	_check(_found(&"elemental_storm"), "la Tormenta se descubre")
	_check(VariantCast.to_float(storm.call(&"lock_left")) > 0.0, "sólo una tormenta a la vez")
	var meanwhile: Resource = _caster.call(&"recipe_for_hands")
	_check(
		meanwhile != null and VariantCast.to_bool(meanwhile.get(&"id") == &"thermal_shock"),
		"mientras ruge, las manos siguen con su pareja"
	)
	# Otra triple: Glaciar Tronante (Escarcha + Tierra + Rayo).
	_set_hands(1, 3, 2)
	await _cast_and_wait(load("res://data/spells/recipe_thunder_glacier.tres"))
	# Supernova: despierta el Arcano (Chispa + Tierra en las manos, Arcano en la gema).
	levels[&"awaken_arcane"] = 1
	_set_hands(0, 3, 4)
	await _cast_and_wait(NOVA)
	for k: int in 30:
		if VariantCast.to_float(storm.call(&"lock_left")) <= 0.0:
			break
		await create_timer(0.5).timeout
	_check(
		VariantCast.to_float(storm.call(&"lock_left")) <= 0.0,
		"pasado el cierre, se puede lanzar otra"
	)
	# El Libro enseña las triples en su página.
	book.call(&"open")
	# SpellBook usa los autoloads: no se puede nombrar en un test `--script` (no compilaría).
	var book_script: Script = book.get_script()
	var triples_page: int = book_script.get_script_constant_map()["TRIPLES_PAGE"]
	book.call(&"open_page", triples_page)
	await process_frame
	var listed: Array = book.call(&"_list")
	_check(listed.size() == 5, "el Libro tiene 5 triples")
	var rows: Array = book.get(&"_rows")
	var storm_row: Label = rows[0]
	var hidden_row: Label = rows[3]
	_check(
		storm_row.text == TranslationServer.translate("Tormenta Elemental").to_upper(),
		"la Tormenta descubierta, con su nombre: %s" % storm_row.text
	)
	_check(hidden_row.text == "???", "lo no descubierto, con acertijo")
	_check(
		VariantCast.to_bool(book.call(&"state_of", listed[3]) == &"unknown"),
		"con báculo ya no tiene candado"
	)
	book.call(&"close")
	# Las dos triples que faltan, contra el cristal.
	_set_hands(4, 4, 0)
	await _cast_and_wait(load("res://data/spells/recipe_star_rain.tres"))
	_set_hands(0, 3, 3)
	await _cast_and_wait(load("res://data/spells/recipe_eruption.tres"))
	# Las triples de área también revientan bichos (critters/).
	await _check_critters(main, player, storm_recipe)
	print("staff_smoke: ", "OK" if _ok else "FALLO")
	quit(0 if _ok else 1)


## Tormenta sobre la hierba con bichos debajo: descarga en el suelo y los revienta. La
## Supernova sobre un bicho revienta a los de alrededor.
func _check_critters(main: Node, player: Node3D, storm_recipe: Resource) -> void:
	var herd: Node = main.get_node(HERD_PATH)
	herd.set(&"ambient", false)
	var delivery: Node = _caster.get_node(^"Delivery")
	var storm: Node = delivery.call(&"storm")
	# Que aterrice todo lo de antes (la onda de la Erupción revienta lo que pille por el camino):
	# así lo que reviente aquí es de la triple que se prueba.
	await create_timer(3.0).timeout
	await _storm_over(storm)
	for c: Node in herd.call(&"critters"):
		c.call(&"hide_now")
	(player.get_node(^"Head") as Node3D).rotation.x = deg_to_rad(-15.0)
	await physics_frame
	await process_frame
	var ground: Vector3 = _caster.call(&"_aim")["position"]
	var cam: Camera3D = _caster.get(&"camera")
	var config: Resource = herd.get(&"config")
	var def: Resource = config.get(&"species")[0]
	var made: Array[Node] = []
	for off: Vector3 in [Vector3(-2.5, 0, 0.5), Vector3(2.5, 0, -0.5), Vector3(0, 0, -2.5)]:
		made.append(herd.call(&"_spawn_at", def, ground + off, false, cam.global_position))
	for i: int in 30:
		await physics_frame
	_check(_alive(made) == 3, "tres bichos bajo la nube (%d vivos)" % _alive(made))
	var popped0: int = VariantCast.to_int(_prog.get(&"critters_popped"))
	_set_hands(0, 1, 2)
	_cast(storm_recipe)
	await create_timer(VariantCast.to_float(storm_recipe.get(&"charge_sec")) + 0.3).timeout
	_check(
		VariantCast.to_int(_prog.get(&"critters_popped")) == popped0,
		"nada revienta antes de la Tormenta"
	)
	_caster.call(&"try_release_combine")
	var waited: float = 0.0
	while VariantCast.to_int(_prog.get(&"critters_popped")) < popped0 + 2 and waited < 12.0:
		await create_timer(0.25).timeout
		waited += 0.25
	var popped: int = VariantCast.to_int(_prog.get(&"critters_popped")) - popped0
	_check(
		popped >= 2,
		(
			"la Tormenta sobre la hierba revienta bichos (%d; descargas %d)"
			% [popped, VariantCast.to_int(storm.call(&"strikes_done"))]
		)
	)
	_check(not VariantCast.to_bool(storm.get(&"_on_crystal")), "y descarga en la hierba")
	# Supernova: el golpe da en un bicho y revienta a los de alrededor (con la nube ya ida).
	await _storm_over(storm)
	for c: Node in herd.call(&"critters"):
		c.call(&"hide_now")
	await create_timer(1.0).timeout
	made.clear()
	for off: Vector3 in [Vector3.ZERO, Vector3(3.0, 0, 0.5), Vector3(-3.0, 0, -0.5)]:
		made.append(herd.call(&"_spawn_at", def, ground + off, false, cam.global_position))
	for i: int in 30:
		await physics_frame
	_check(_alive(made) == 3, "tres bichos para la Supernova (%d vivos)" % _alive(made))
	popped0 = VariantCast.to_int(_prog.get(&"critters_popped"))
	_set_hands(0, 3, 4)
	var nova: Resource = NOVA
	_cast(nova)
	await create_timer(VariantCast.to_float(nova.get(&"charge_sec")) + 0.3).timeout
	_check(
		VariantCast.to_int(_prog.get(&"critters_popped")) == popped0,
		"nada revienta antes de la Supernova"
	)
	_caster.call(&"try_release_combine")
	waited = 0.0
	while VariantCast.to_int(_prog.get(&"critters_popped")) < popped0 + 3 and waited < 6.0:
		await create_timer(0.25).timeout
		waited += 0.25
	popped = VariantCast.to_int(_prog.get(&"critters_popped")) - popped0
	_check(popped >= 3, "la Supernova revienta a todos los de alrededor (%d)" % popped)
	(player.get_node(^"Head") as Node3D).rotation.x = deg_to_rad(8.0)


## Espera a que la Tormenta Elemental se haya ido del todo y se pueda lanzar otra.
func _storm_over(storm: Node) -> void:
	for k: int in 60:
		if (
			not VariantCast.to_bool(storm.call(&"is_raging"))
			and VariantCast.to_float(storm.call(&"lock_left")) <= 0.0
		):
			break
		await create_timer(0.5).timeout
	await create_timer(1.5).timeout


## Cuántos de estos bichos siguen vivos.
func _alive(critters: Array[Node]) -> int:
	var n: int = 0
	for c: Node in critters:
		if c != null and VariantCast.to_bool(c.call(&"is_alive")):
			n += 1
	return n


## Datos: cada triple tiene tres elementos, se resuelve en cualquier orden y no hay dos iguales.
func _check_data(sc: Script) -> void:
	var triples: Array = sc.get(&"TRIPLES")
	_check(triples.size() >= 4, "al menos cuatro triples (%d)" % triples.size())
	for r: Resource in triples:
		var els: Array = r.get(&"elements")
		var id: StringName = r.get(&"id")
		_check(
			els.size() == 3 and VariantCast.to_bool(r.call(&"is_triple")), "%s: tres elementos" % id
		)
		_check(r.get(&"tier") != null and r.get(&"visual") != null, "%s: aspecto" % id)
		_check(str(r.get(&"riddle")) != "", "%s: acertijo" % id)
		_check(str(r.get(&"description")) != "", "%s: descripción" % id)
		var sfx: Array = r.get(&"impact_sfx")
		_check(not sfx.is_empty(), "%s: sonido" % id)
		for order: Array in [[0, 1, 2], [2, 0, 1], [1, 2, 0]]:
			var got: Resource = sc.call(&"triple_for", els[order[0]], els[order[1]], els[order[2]])
			_check(got == r, "%s en el orden %s" % [id, order])
		_check(
			not VariantCast.to_bool(r.call(&"matches", els[0], els[1])), "%s no es una pareja" % id
		)
	_check(sc.call(&"triple_for", &"spark", &"spark", &"spark") == null, "tres chispas: nada")
	var storm: Resource = sc.call(&"triple_for", &"bolt", &"spark", &"frost")
	_check(
		VariantCast.to_bool(storm != null and storm.get(&"id") == &"elemental_storm"),
		"la Tormenta Elemental existe"
	)
	_check(
		(
			VariantCast.to_int(storm.get(&"delivery")) == 9
			and VariantCast.to_float(storm.get(&"storm_sec")) > 3.0
		),
		"es tormenta"
	)


func _upgrade(gs: Node, id: StringName) -> UpgradeNode:
	for n: UpgradeNode in gs.get(&"UPGRADES"):
		if n.id == id:
			return n
	return null


func _set_hands(left: int, right: int, gem: int) -> void:
	var hand: Array = _caster.get(&"hand_element")
	hand[0] = left
	hand[1] = right
	var staff: RefCounted = _caster.get(&"staff")
	staff.set(&"element_index", gem)


func _cast(recipe: Resource) -> void:
	_caster.set(&"_cooldown", PackedFloat32Array([0.0, 0.0]))
	var now: Resource = _caster.call(&"recipe_for_hands")
	_check(now == recipe, "resuelve %s" % recipe.get(&"id"))
	_check(
		VariantCast.to_bool(_caster.call(&"try_begin_combine")),
		"%s: se juntan las manos" % recipe.get(&"id")
	)


func _cast_and_wait(recipe: Resource) -> void:
	await create_timer(0.3).timeout
	var before: int = VariantCast.to_int(_prog.get(&"essence"))
	_cast(recipe)
	await create_timer(VariantCast.to_float(recipe.get(&"charge_sec")) + 0.3).timeout
	_caster.call(&"try_release_combine")
	var waited: float = 0.0
	while VariantCast.to_int(_prog.get(&"essence")) >= before and waited < 9.0:
		await create_timer(0.2).timeout
		waited += 0.2
	_check(
		VariantCast.to_int(_prog.get(&"essence")) < before, "%s: quita esencia" % recipe.get(&"id")
	)
	var recipe_id: StringName = recipe.get(&"id")
	_check(_found(recipe_id), "%s: descubierta" % recipe_id)


## Con el báculo apagado (StaffCombos.ENABLED): ni mejoras, ni página del Grimorio, ni triples,
## ni vitrina, ni báculo en pantalla, aunque una partida guardada lo tuviera comprado; R no hace
## nada y las parejas siguen como siempre.
func _check_disabled(gs: Node) -> void:
	var staff_ids: Array[String] = []
	for n: UpgradeNode in gs.get(&"UPGRADES"):
		if String(n.id).begins_with("staff"):
			staff_ids.append(String(n.id))
	_check(staff_ids.is_empty(), "sin mejoras del báculo en el Grimorio %s" % [staff_ids])
	_prog = gs.get(&"progression")
	# Como una partida guardada que ya lo tenía comprado.
	var levels: Dictionary = _prog.get(&"upgrade_levels")
	levels[&"staff"] = 1
	change_scene_to_file("res://main/main.tscn")
	for i: int in 240:
		await process_frame
	var main: Node = current_scene
	var menu: Node = main.get_node(^"HUDLayer/Hud/GameMenu")
	if VariantCast.to_bool(menu.call(&"is_open")):
		menu.call(&"_close")
	var grimoire: Node = main.get_node(GRIMOIRE_PATH)
	for page: Array in grimoire.get(&"PAGES"):
		_check(VariantCast.to_bool(page[0] != &"staff"), "el Grimorio no tiene página %s" % page[0])
	_check(main.get_tree().get_first_node_in_group(&"staff_vitrine") == null, "no hay vitrina")
	var player: Node3D = main.get_node(PLAYER_PATH)
	_caster = player.call(&"get_caster")
	var view: Node = player.get_node(^"Hands").get(&"staff")
	_caster.call(&"_cycle_staff", 1)
	await process_frame
	_check(not VariantCast.to_bool(view.call(&"is_shown")), "el báculo no sale en pantalla")
	var staff: RefCounted = _caster.get(&"staff")
	_check(VariantCast.to_int(staff.get(&"element_index")) < 0, "R no enciende ninguna gema")
	var book: Node = main.get_node(BOOK_PATH)
	# Sin báculo se ven los marcapáginas de antes de TRIPLES (PAREJAS y VIENTO).
	var book_script: Script = book.get_script()
	var triples_page: int = book_script.get_script_constant_map()["TRIPLES_PAGE"]
	_check(
		VariantCast.to_int(book.call(&"_tab_count")) == triples_page,
		"el Libro no tiene TRIPLES (%d marcapáginas)" % triples_page
	)
	print("staff_smoke: ", "OK" if _ok else "FALLO")
	quit(0 if _ok else 1)


func _found(id: StringName) -> bool:
	var discovered: Array = _prog.get(&"discovered_recipes")
	return discovered.has(id)


func _check(cond: bool, what: String) -> void:
	if not cond:
		_ok = false
		push_error("FALLO: " + what)
	else:
		print("  ok: ", what)
