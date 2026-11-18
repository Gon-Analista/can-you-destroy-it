extends SceneTree
## Menú de depuración: Alt+F1 lo abre (y suelta el ratón), "COMPRAR TODO Y HECHIZOS AL MÁXIMO"
## deja todas las mejoras al máximo, todos los elementos despiertos, todas las combinaciones
## descubiertas y todos los hechizos (elementos y combinados) a nivel 10; el maná, la bolsa, la
## velocidad del juego y el Pilón responden; Esc lo cierra. No toca la partida guardada.
## godot --headless --path game --script res://tests/smoke/debug_menu_smoke.gd

const MENU_PATH: NodePath = ^"HUDLayer/Hud/DebugMenu"
const PLAYER_PATH: NodePath = ^"WorldView/WorldViewport/Player"

var _ok: bool = true


func _initialize() -> void:
	root.get_node(^"SaveSystem").set(&"enabled", false)
	var gs: Node = root.get_node(^"GameState")
	gs.call(&"reset")
	change_scene_to_file("res://main/main.tscn")
	await process_frame
	await process_frame
	for i: int in 240:
		await process_frame
	var game_menu: Node = current_scene.get_node(^"HUDLayer/Hud/GameMenu")
	if bool(game_menu.call(&"is_open")):
		game_menu.call(&"_close")
	await process_frame
	var menu: Control = current_scene.get_node(MENU_PATH)
	_check(not bool(menu.call(&"is_open")), "empieza cerrado")
	_check(bool(menu.call(&"available")), "disponible en build de desarrollo")
	# Alt+F1 de verdad, por el bucle de entrada.
	var key := InputEventKey.new()
	key.keycode = KEY_F1
	key.alt_pressed = true
	key.pressed = true
	root.push_input(key)
	await process_frame
	_check(bool(menu.call(&"is_open")), "Alt+F1 lo abre")
	_check(Input.mouse_mode != Input.MOUSE_MODE_CAPTURED, "suelta el ratón")
	# El botón de comprarlo todo.
	var buy: Button = menu.find_child("BuyAll", true, false)
	_check(buy != null, "hay botón de comprarlo todo")
	var prog: RefCounted = gs.get(&"progression")
	var mana0: int = int(prog.get(&"mana"))
	buy.pressed.emit()
	await process_frame
	await process_frame
	var upgrades: Array = gs.get(&"UPGRADES")
	var maxed: int = 0
	for node: UpgradeNode in upgrades:
		var lv: int = int(prog.call(&"get_level", node.id))
		if lv >= node.get_max_level():
			maxed += 1
		else:
			_check(false, "%s al máximo (%d/%d)" % [node.id, lv, node.get_max_level()])
	_check(maxed == upgrades.size(), "todas las mejoras al máximo (%d)" % maxed)
	_check(int(prog.get(&"mana")) == mana0, "gratis: el maná no cambia")
	var player: Node = current_scene.get_node(PLAYER_PATH)
	var caster: Node = player.call(&"get_caster")
	var elements: Array = caster.get(&"ELEMENTS")
	var hands: Array = caster.get(&"hand_element")
	for i: int in elements.size():
		var el: ElementDef = elements[i]
		_check(bool(caster.call(&"is_unlocked", el)), "%s despierto" % el.id)
		hands[0] = i
		_check(int(caster.call(&"level_of", 0)) == 10, "%s a nivel 10" % el.id)
	hands[0] = 0
	var recipes: Array = caster.get(&"RECIPES")
	var discovered: Array = prog.get(&"discovered_recipes")
	for r: SpellRecipe in recipes:
		_check(discovered.has(r.id), "%s descubierta" % r.id)
		if not r.is_reaction:
			_check(int(caster.call(&"recipe_level", r)) == 10, "%s a nivel 10" % r.id)
	_check(int(gs.call(&"bag_capacity")) == 100, "bolsa grande (%d)" % gs.call(&"bag_capacity"))
	var flock: Node = current_scene.get_node(^"WorldView/WorldViewport/FamiliarFlock")
	await process_frame
	_check(int(flock.call(&"active_count")) >= 4, "familiares en juego")
	# Otros trucos.
	menu.call(&"_add_mana", 1000)
	_check(int(prog.get(&"mana")) == mana0 + 1000, "+1K de maná")
	menu.call(&"_fill_bag")
	_check(int(prog.call(&"bag_count")) == 100, "bolsa llena")
	menu.call(&"_empty_bag")
	_check(int(prog.call(&"bag_count")) == 0, "bolsa vacía")
	menu.call(&"_set_pylon", 0.5)
	_check(absf(float(prog.call(&"pylon_ratio")) - 0.5) < 0.001, "Pilón al 50 %")
	# Las subidas de rango de lo comprado y entregado traen su ceremonia con un hit-stop: se espera.
	for i: int in 600:
		if not HitStop.is_active():
			break
		await process_frame
	await create_timer(0.1, true, false, true).timeout
	menu.call(&"_set_speed", 2.0)
	await process_frame
	_check(is_equal_approx(Engine.time_scale, 2.0), "velocidad x2")
	menu.call(&"_set_speed", 1.0)
	menu.call(&"_toggle_god")
	_check(bool(caster.get(&"debug_no_cooldown")), "modo dios: sin recarga")
	menu.call(&"_toggle_god")
	menu.call(&"_warp", &"sanctum")
	var pos: Vector3 = (player as Node3D).global_position
	_check(pos.distance_to(WorldLayout.SANCTUM) < 14.0, "teletransporte al Santuario")
	# Esc lo cierra.
	var esc := InputEventAction.new()
	esc.action = &"ui_cancel"
	esc.pressed = true
	root.push_input(esc)
	await process_frame
	_check(not bool(menu.call(&"is_open")), "Esc lo cierra")
	_check(not bool(game_menu.call(&"is_open")), "y no abre la pausa")
	print("debug_menu_smoke: ", "OK" if _ok else "FALLO")
	quit(0 if _ok else 1)


func _check(cond: bool, what: String) -> void:
	if not cond:
		print("  FALLO  " + what)
		_ok = false
