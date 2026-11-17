extends SceneTree
## Combinaciones: cada pareja de los cinco elementos (15) tiene exactamente una receta lanzable
## (las reacciones no se lanzan), los Ecos repiten una receta que existe, y cada combinación
## lanzada de verdad contra el cristal se descubre y le quita esencia (salvo las de utilidad:
## Magnetismo y Gravedad, que atraen fragmentos).
## godot --headless --path game --script res://tests/smoke/combos_smoke.gd

var _ok: bool = true


func _initialize() -> void:
	root.get_node(^"SaveSystem").set(&"enabled", false)
	root.get_node(^"GameState").call(&"reset")
	var caster_script: Script = load("res://player/spell_caster.gd")
	var elements: Array = caster_script.get(&"ELEMENTS")
	var recipes: Array = caster_script.get(&"RECIPES")
	_check(elements.size() == 5, "cinco elementos")
	_check(elements[4].get(&"id") == &"arcane", "el quinto es el Arcano")
	var pairs: int = 0
	for i: int in elements.size():
		for j: int in range(i, elements.size()):
			var a: StringName = elements[i].get(&"id")
			var b: StringName = elements[j].get(&"id")
			var n: int = 0
			for r: Resource in recipes:
				if bool(r.call(&"matches", a, b)):
					n += 1
			_check(n == 1, "%s + %s: una combinación (%d)" % [a, b, n])
			pairs += 1
	_check(pairs == 15, "15 parejas")
	for r: Resource in recipes:
		if bool(r.get(&"is_reaction")):
			_check(not bool(r.call(&"matches", &"spark", &"frost")), "la reacción no se lanza")
		else:
			_check(
				r.get(&"tier") != null and r.get(&"visual") != null,
				"%s tiene aspecto" % r.get(&"id")
			)
			_check(String(r.get(&"riddle")) != "", "%s tiene acertijo" % r.get(&"id"))
			_check(String(r.get(&"description")) != "", "%s tiene descripción" % r.get(&"id"))
			var echo_of: StringName = r.get(&"echo_of")
			if echo_of != &"":
				var base: Resource = load("res://spells/spell_echoes.gd").call(&"base_of", r)
				_check(
					base != null and int(r.get(&"echo_count")) > 0,
					"%s repite %s" % [r.get(&"id"), echo_of]
				)
	change_scene_to_file("res://main/main.tscn")
	for i: int in 240:
		await process_frame
	var main: Node = current_scene
	var menu: Node = main.get_node(^"HUDLayer/Hud/GameMenu")
	if bool(menu.call(&"is_open")):
		menu.call(&"_close")
	var player: Node3D = main.get_node(^"WorldView/WorldViewport/Player")
	var caster: Node = player.call(&"get_caster")
	var gs: Node = root.get_node(^"GameState")
	var prog: RefCounted = gs.get(&"progression")
	var levels: Dictionary = prog.get(&"upgrade_levels")
	for id: String in ["awaken_frost", "awaken_bolt", "awaken_earth", "awaken_arcane"]:
		levels[StringName(id)] = 1
	player.global_position = Vector3(0.0, 0.3, 60.0)
	player.rotation.y = 0.0
	(player.get_node(^"Head") as Node3D).rotation.x = deg_to_rad(8.0)
	for r: Resource in recipes:
		if bool(r.get(&"is_reaction")):
			continue
		var els: Array = r.get(&"elements")
		var idx: Array[int] = []
		for e: StringName in els:
			for k: int in elements.size():
				if elements[k].get(&"id") == e:
					idx.append(k)
		(caster.get(&"hand_element") as Array)[0] = idx[0]
		(caster.get(&"hand_element") as Array)[1] = idx[1]
		caster.set(&"_cooldown", PackedFloat32Array([0.0, 0.0]))
		await process_frame
		var before: int = int(prog.get(&"essence"))
		var began: bool = caster.call(&"try_begin_combine")
		_check(began, "%s: se juntan las manos" % r.get(&"id"))
		await create_timer(float(r.get(&"charge_sec")) + 0.2).timeout
		caster.call(&"try_release_combine")
		# 6 Magnetismo y 7 Gravedad: utilidad, no dañan.
		var damages: bool = int(r.get(&"delivery")) < 6 or int(r.get(&"delivery")) > 7
		# Lo lento (Bola de Fuego) tarda más cuanto más hondo es el túnel: se espera al golpe.
		var waited: float = 0.0
		while (
			waited < 2.6 + float(r.get(&"beam_sec"))
			or (damages and int(prog.get(&"essence")) >= before and waited < 9.0)
		):
			await create_timer(0.2).timeout
			waited += 0.2
		var found: Array = prog.get(&"discovered_recipes")
		_check(found.has(r.get(&"id")), "%s: descubierta" % r.get(&"id"))
		if damages:
			_check(int(prog.get(&"essence")) < before, "%s: quita esencia" % r.get(&"id"))
	print("combos_smoke: ", "OK" if _ok else "FALLO")
	quit(0 if _ok else 1)


func _check(cond: bool, what: String) -> void:
	if not cond:
		_ok = false
		push_error("FALLO: " + what)
	else:
		print("  ok: ", what)
