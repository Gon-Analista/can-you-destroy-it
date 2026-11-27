extends SceneTree
## Estaciones: se sube andando al suelo del Santuario (no se atraviesa) y el atril es sólido;
## la palanca de la Trituradora se puede tirar sin apuntarla al milímetro (mirando cerca de ella
## o desde su lado). No toca la partida guardada.
## godot --headless --path game --script res://tests/smoke/stations_smoke.gd

const PLAYER_PATH: NodePath = ^"WorldView/WorldViewport/Player"
const SANCTUM_PATH: NodePath = ^"WorldView/WorldViewport/Sanctum"

var _ok: bool = true


func _initialize() -> void:
	root.get_node(^"SaveSystem").set(&"enabled", false)
	root.get_node(^"GameState").call(&"reset")
	change_scene_to_file("res://main/main.tscn")
	await process_frame
	await process_frame
	var main: Node = current_scene
	for i: int in 240:
		await process_frame
	var menu: Node = main.get_node(^"HUDLayer/Hud/GameMenu")
	if VariantCast.to_bool(menu.call(&"is_open")):
		menu.call(&"_close")
	await process_frame
	var player: CharacterBody3D = main.get_node(PLAYER_PATH)
	var sanctum: Node3D = main.get_node(SANCTUM_PATH)
	await _walk_into_sanctum(main, player, sanctum)
	await _crusher_lever(main)
	print("stations_smoke: ", "OK" if _ok else "FALLO")
	quit(0 if _ok else 1)


func _walk_into_sanctum(main: Node, player: CharacterBody3D, sanctum: Node3D) -> void:
	var center: Vector3 = sanctum.global_position
	var floor_y: float = center.y + VariantCast.to_float(sanctum.get(&"FLOOR_TOP"))
	# Desde fuera, por el lado abierto (el que mira al cristal), andando hacia el atril.
	var out: Vector3 = Vector3(-center.x, 0.0, -center.z).normalized()
	var start: Vector3 = center + out * 8.0
	start.y = Valley.ground_height(start.x, start.z) + 0.2
	main.call(&"debug_teleport", start, center + Vector3.UP * 1.6)
	for i: int in 10:
		await physics_frame
	Input.action_press(&"move_forward")
	var min_d: float = INF
	var y_at_min: float = 0.0
	for i: int in 240:
		await physics_frame
		var flat: Vector3 = player.global_position - center
		flat.y = 0.0
		if flat.length() < min_d:
			min_d = flat.length()
			y_at_min = player.global_position.y
	Input.action_release(&"move_forward")
	for i: int in 20:
		await physics_frame
	_check(min_d > 0.3, "el atril para al jugador (llega a %.2f m del centro)" % min_d)
	_check(min_d < 1.2, "se llega hasta el atril (%.2f m)" % min_d)
	_check(
		absf(y_at_min - floor_y) < 0.08,
		"de pie sobre el suelo del templete (%.2f, suelo %.2f)" % [y_at_min, floor_y]
	)
	_check(player.is_on_floor(), "en el suelo, no cayendo")


func _crusher_lever(main: Node) -> void:
	var crusher: Node3D = main.get_tree().get_first_node_in_group(&"crystal_crusher")
	_check(crusher != null, "hay Trituradora")
	if crusher == null:
		return
	var lever: Vector3 = crusher.call(&"lever_tip")
	var hopper: Vector3 = crusher.call(&"hopper_mouth")
	# Desde el lado de la palanca, mirando un poco al lado de la manivela (a ~0,6 m).
	var side: Vector3 = lever - hopper
	side.y = 0.0
	side = side.normalized()
	var stand: Vector3 = lever + side * 2.0
	stand.y = Valley.ground_height(stand.x, stand.z) + 0.2
	var miss: Vector3 = lever + side.cross(Vector3.UP) * 0.4
	main.call(&"debug_teleport", stand, miss)
	for i: int in 10:
		await physics_frame
	_check(
		VariantCast.to_bool(crusher.call(&"lever_targeted")),
		"la palanca se elige sin clavar la mira"
	)
	# Con cristales en la tolva, un clic mirándola tira de ella (y no lanza un hechizo).
	crusher.call(&"add_to_hopper", load("res://data/shards/shard.tres"))
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	crusher.get_script().set(&"demo_input", true)
	var click := InputEventAction.new()
	click.action = &"cast_left"
	click.pressed = true
	root.push_input(click)
	await process_frame
	_check(VariantCast.to_bool(crusher.call(&"is_busy")), "un clic en la palanca tritura")
	click = click.duplicate()
	click.pressed = false
	root.push_input(click)
	crusher.get_script().set(&"demo_input", false)
	for i: int in 400:
		await process_frame
		if not VariantCast.to_bool(crusher.call(&"is_busy")):
			break
	# Mirando a la tolva desde lejos, la tolva sigue siendo la tolva.
	var front: Vector3 = hopper + (hopper - lever).normalized() * 2.5
	front = crusher.global_position + (front - crusher.global_position).limit_length(3.0)
	front.y = Valley.ground_height(front.x, front.z) + 0.2
	main.call(&"debug_teleport", front, hopper + Vector3.UP * 0.6)
	for i: int in 10:
		await physics_frame
	_check(
		not VariantCast.to_bool(crusher.call(&"lever_targeted")),
		"mirando la tolva no se elige la palanca"
	)


func _check(cond: bool, what: String) -> void:
	print(("  ok  " if cond else "  FALLO  ") + what)
	if not cond:
		_ok = false
