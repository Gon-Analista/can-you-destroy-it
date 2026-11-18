extends SceneTree
## La Bola de Fuego en vuelo (`FireballFlight`): la pantalla de carga crea en cada proyectil de
## combinación su bola y la roca del Meteoro (lanzar no instancia nada), la bola crece con el
## nivel, suelta su cola lejos de la mano, sus lenguas apuntan hacia la mano y se apaga al llegar.
## El Eco de Fuego la usa; el Meteoro no. El Meteoro suena con un solo estruendo.
## godot --headless --path game --script res://tests/smoke/fireball_flight_smoke.gd

var _ok: bool = true


func _initialize() -> void:
	_run()


func _run() -> void:
	root.get_node(^"SaveSystem").set(&"enabled", false)
	var fireball: SpellRecipe = load("res://data/spells/recipe_fireball.tres")
	var echo: SpellRecipe = load("res://data/spells/recipe_echo_fire.tres")
	var meteor: SpellRecipe = load("res://data/spells/recipe_meteor.tres")
	_check(fireball.tier.visual.fireball_flight, "la Bola de Fuego vuela como bola de fuego")
	_check(echo.tier.visual.fireball_flight, "y el Eco de Fuego también (en rosa)")
	_check(not meteor.tier.visual.fireball_flight, "el Meteoro no (lleva su roca)")
	_check(meteor.impact_sfx.is_empty(), "el Meteoro no suma un segundo sonido de impacto")
	var main: Node = (load("res://main/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	for i: int in 5:
		await process_frame
	var caster: Node = main.get_node(^"WorldView/WorldViewport/Player").call(&"get_caster")
	var combos: Array[Node3D] = []
	for c: Node in caster.get_children():
		if c is Node3D and c.name.begins_with("Combo") and c.has_method(&"prepare_combo"):
			combos.append(c as Node3D)
	_check(combos.size() > 0, "hay proyectiles de combinación")
	for p: Node3D in combos:
		_check(
			p.has_node(^"Meteor") and p.has_node(^"Fireball"), "%s ya lleva bola y roca" % p.name
		)
	var p: Node3D = combos[0]
	var cam: Camera3D = caster.get(&"camera")
	for i: int in 200:
		if not p.get(&"active"):
			break
		await process_frame
	var nodes_before: int = _count(p)
	var from: Vector3 = cam.global_position + cam.global_basis * Vector3(0.0, -0.3, -0.85)
	var to: Vector3 = cam.global_position - cam.global_basis.z * 40.0
	var scales: Array[float] = []
	for level: int in [1, 10]:
		p.call(&"launch", from, to, _hit(fireball, level, to), null)
		var ball: Node3D = p.get_node(^"Fireball")
		_check(ball.visible, "nivel %d: la bola sale" % level)
		var tail: GPUParticles3D = ball.get_node(^"Tail")
		var tail_seen: bool = false
		for i: int in 60:
			await process_frame
			tail_seen = tail_seen or tail.emitting
			if float(p.get(&"_t")) > 0.75:
				break
		_check(tail_seen, "nivel %d: suelta su cola de bocanadas lejos de la mano" % level)
		var flow: Vector2 = p.get(&"_flow")
		_check(flow.y > 0.3, "nivel %d: las lenguas van hacia la mano (%s)" % [level, flow])
		scales.append((ball.get_node(^"Ball") as Node3D).scale.x)
		for i: int in 40:
			if not p.get(&"active"):
				break
			await create_timer(0.1).timeout
		_check(not p.get(&"active") and not ball.visible, "nivel %d: llega y se apaga" % level)
	_check(scales[1] > scales[0] * 1.2, "a nivel 10 es más grande (%s)" % [scales])
	p.call(&"launch", from, to, _hit(echo, 4, to), null)
	_check(_count(p) == nodes_before, "lanzar no crea nodos (%d -> %d)" % [nodes_before, _count(p)])
	var rock: Node = p.get_node(^"Meteor")
	p.call(&"launch", from, to, _hit(meteor, 1, to), null)
	_check(p.get_node(^"Meteor") == rock, "el Meteoro usa la roca de la pantalla de carga")
	print("fireball_flight_smoke: ", "OK" if _ok else "FALLO")
	quit(0 if _ok else 1)


func _hit(r: SpellRecipe, level: int, at: Vector3) -> SpellHit:
	var h := SpellHit.new()
	h.tier = r.tier
	h.recipe = r
	h.level = level
	h.warmup = true
	h.position = at
	h.normal = Vector3.BACK
	return h


func _count(n: Node) -> int:
	var k: int = 1
	for c: Node in n.get_children():
		k += _count(c)
	return k


func _check(cond: bool, what: String) -> void:
	if not cond:
		_ok = false
		push_error("FALLO: " + what)
