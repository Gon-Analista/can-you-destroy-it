extends SceneTree
## Regresión: el Grimorio medía 0x0 y los clics no le llegaban (no se podía comprar con el ratón).
## Abre el Grimorio junto al atril, hace clic en INSCRIBIR y en una pestaña de elemento.
## Necesita ventana (el modo headless no reparte clics a la interfaz):
## xvfb-run godot --path game --script res://tests/smoke/grimoire_click_smoke.gd

var _failures: int = 0


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	var gs: Node = root.get_node(^"GameState")
	var state_before: Dictionary = (gs.get(&"progression") as Progression).to_dict()
	gs.set(&"progression", Progression.new(1_000_000))
	var prog: Progression = gs.get(&"progression")
	var main: Node = (load("res://main/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	for i: int in 160:
		await process_frame
	prog.deliver(50)
	root.get_node(^"Events").emit_signal(&"grimoire_requested", true)
	for i: int in 30:
		await process_frame
	var g: Control = main.get_node(^"HUDLayer/Hud/Grimoire")
	_check(g.size == root.get_visible_rect().size, "el Grimorio ocupa toda la pantalla")
	# De coordenadas del juego (640x360) a las de la ventana.
	var scale: Vector2 = Vector2(root.size) / root.get_visible_rect().size
	g.call(&"select", 0)
	_click((g.call(&"_button_rect") as Rect2).get_center() * scale)
	await process_frame
	_check(prog.get_level(&"bag") == 1, "clic en INSCRIBIR compra")
	_click((g.call(&"_tab_rect", 1) as Rect2).get_center() * scale)
	await process_frame
	_check(int(g.get(&"_page")) == 1, "clic en una pestaña cambia de elemento")
	gs.set(&"progression", Progression.new(1_000_000))
	(gs.get(&"progression") as Progression).load_dict(state_before)
	root.get_node(^"SaveSystem").call(&"save_game")
	print("grimoire_click_smoke: %s" % ("OK" if _failures == 0 else "%d fallos" % _failures))
	quit(1 if _failures > 0 else 0)


func _click(pos: Vector2) -> void:
	for pressed: bool in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = pos
		ev.global_position = pos
		root.push_input(ev)


func _check(cond: bool, label: String) -> void:
	if not cond:
		_failures += 1
		printerr("FALLO: " + label)
