extends SceneTree
## Mejoras de movimiento: sin ellas no hay doble salto; con Doble salto se sube más; con
## Levitación, manteniendo Espacio tras el doble salto se sigue subiendo y se gasta la carga, que
## se recarga al pisar suelo. Sin daño por caída.
## godot --headless --path game --script res://tests/smoke/movement_smoke.gd

var _ok: bool = true


func _initialize() -> void:
	# Sin tocar la partida guardada del jugador y desde cero.
	root.get_node(^"SaveSystem").set(&"enabled", false)
	root.get_node(^"GameState").call(&"reset")
	change_scene_to_file("res://main/main.tscn")
	await process_frame
	await process_frame
	var main: Node = current_scene
	var player: CharacterBody3D = main.get_node(^"WorldView/WorldViewport/Player")
	var prog: RefCounted = root.get_node(^"GameState").get(&"progression")
	# Tras la pantalla de carga sale el título: se cierra para poder moverse.
	for i: int in 240:
		await process_frame
	var menu: Node = main.get_node(^"HUDLayer/Hud/GameMenu")
	if bool(menu.call(&"is_open")):
		menu.call(&"_close")
	await process_frame
	var start := Vector3(0.0, 0.3, 66.0)
	# Sin mejoras: dos pulsaciones de Espacio = un solo salto.
	var peak: float = await _jump_test(player, start, 2, 1.6)
	_check(peak > 0.8 and peak < 2.4, "salto normal (%.2f m)" % peak)
	var levels: Dictionary = prog.get(&"upgrade_levels")
	levels[&"double_jump"] = 1
	root.get_node(^"Events").emit_signal(&"upgrade_bought", &"double_jump", 1)
	await physics_frame
	var peak2: float = await _jump_test(player, start, 2, 1.6)
	_check(peak2 > peak + 0.8, "el doble salto sube más (%.2f m)" % peak2)
	levels[&"levitation"] = 2
	root.get_node(^"Events").emit_signal(&"upgrade_bought", &"levitation", 2)
	await physics_frame
	_check(
		float(player.get(&"levitation_max")) > 2.5,
		"levitación nivel 2 (%.1f s)" % float(player.get(&"levitation_max"))
	)
	var peak3: float = await _jump_test(player, start, 2, 4.0)
	_check(peak3 > peak2 + 3.0, "levitando se sigue subiendo (%.2f m)" % peak3)
	_check(float(player.call(&"fuel_ratio")) < 0.6, "y se gasta la carga")
	for i: int in 160:
		await physics_frame
	_check(float(player.call(&"fuel_ratio")) > 0.99, "en el suelo se recarga")
	# Impulso del cristal: un golpe al cristal en el aire devuelve carga.
	levels[&"crystal_impulse"] = 2
	player.global_position = start + Vector3(0.0, 20.0, 0.0)
	player.set(&"levitation_fuel", 0.5)
	await physics_frame
	var hit := SpellHit.new()
	hit.tier = (load("res://data/elements/spark.tres").get(&"tiers") as Array)[0]
	hit.position = player.global_position + Vector3(0, 0, -10)
	hit.normal = Vector3.BACK
	hit.damage = 1
	root.get_node(^"Events").emit_signal(&"spell_impacted", hit)
	_check(float(player.get(&"levitation_fuel")) > 0.9, "un golpe en el aire recarga levitación")
	for i: int in 400:
		await physics_frame
		if player.is_on_floor():
			break
	_check(player.is_on_floor(), "cae 20 m y aterriza sin daño")
	_check(player.is_on_floor(), "aterriza sin problema (sin daño por caída)")
	print("movement_smoke: ", "OK" if _ok else "FALLO")
	quit(0 if _ok else 1)


## Pone al mago en `start`, pulsa Espacio `taps` veces (la última se mantiene `hold` s) y devuelve
## la altura máxima alcanzada sobre el punto de partida.
func _jump_test(player: CharacterBody3D, start: Vector3, taps: int, hold: float) -> float:
	player.global_position = start
	player.velocity = Vector3.ZERO
	for i: int in 30:
		await physics_frame
	var y0: float = player.global_position.y
	var peak: float = 0.0
	for k: int in taps:
		Input.action_press(&"jump")
		var frames: int = 8 if k < taps - 1 else int(hold * 60.0)
		for i: int in frames:
			await physics_frame
			peak = maxf(peak, player.global_position.y - y0)
		Input.action_release(&"jump")
		for i: int in 18 if k < taps - 1 else 0:
			await physics_frame
			peak = maxf(peak, player.global_position.y - y0)
	for i: int in 200:
		await physics_frame
		peak = maxf(peak, player.global_position.y - y0)
		if player.is_on_floor() and i > 10:
			break
	return peak


func _check(cond: bool, what: String) -> void:
	if not cond:
		_ok = false
		push_error("FALLO: " + what)
	else:
		print("  ok: ", what)
