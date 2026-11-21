extends SceneTree
## Arranque: el título es ligero (sin mundo 3D) y empieza a cargar el juego en otro hilo; NUEVA
## PARTIDA (con partida guardada, pide confirmación) abre la pantalla de carga, que avanza, monta
## el juego, lo precalienta y se va sola; desde la pausa, MENÚ PRINCIPAL vuelve al título y calla
## el valle; y otra vez al juego (dos partidas seguidas sin restos de la primera).
## godot --headless --path game --script res://tests/smoke/boot_smoke.gd

const TITLE: String = "res://title/title_screen.tscn"
const MAX_FRAMES: int = 3000

var _ok: bool = true


func _initialize() -> void:
	root.get_node(^"SaveSystem").set(&"enabled", false)
	var gs: Node = root.get_node(^"GameState")
	gs.call(&"reset")
	var main_scene: String = ProjectSettings.get_setting("application/run/main_scene")
	_check(main_scene == TITLE, "el título es la escena principal")
	change_scene_to_file(TITLE)
	await process_frame
	await process_frame
	var title: Control = current_scene as Control
	_check(title != null and title.name == "TitleScreen", "arranca en el título")
	_check(root.find_child("WorldViewport", true, false) == null, "el título no monta el mundo 3D")
	var buttons: Array[String] = _buttons(title)
	_check(buttons.has(TranslationServer.translate("NUEVA PARTIDA")), "NUEVA PARTIDA en el título")
	_check(
		not buttons.has(TranslationServer.translate("CONTINUAR")), "sin partida no hay CONTINUAR"
	)
	# Con algo de partida aparece CONTINUAR y NUEVA PARTIDA pide confirmación.
	var prog: Object = gs.get(&"progression")
	prog.set(&"pylon_progress", 10)
	title.call(&"_rebuild")
	await process_frame
	_check(
		_buttons(title).has(TranslationServer.translate("CONTINUAR")), "con partida hay CONTINUAR"
	)
	title.call(&"_ask_new_game")
	await process_frame
	_check(
		_buttons(title).has(TranslationServer.translate("SÍ, BORRAR LA PARTIDA")),
		"NUEVA PARTIDA pide confirmación"
	)
	title.call(&"_cancel_new")
	await process_frame
	gs.call(&"reset")
	# El juego ya se está cargando en otro hilo mientras se ve el título.
	var status: int = ResourceLoader.load_threaded_get_status("res://main/main.tscn")
	_check(
		status != ResourceLoader.THREAD_LOAD_INVALID_RESOURCE, "el juego se carga desde el título"
	)
	await _enter_game(title, "_play")
	# Pausa -> MENÚ PRINCIPAL -> título (con el valle callado).
	var menu: Node = current_scene.get_node(^"HUDLayer/Hud/GameMenu")
	menu.call(&"demo_open", "pause")
	await process_frame
	_check(paused, "la pausa para el juego")
	menu.call(&"_to_title")
	var frames: int = 0
	while (current_scene == null or current_scene.name != "TitleScreen") and frames < MAX_FRAMES:
		await process_frame
		frames += 1
	await process_frame
	_check(current_scene != null and current_scene.name == "TitleScreen", "vuelve al título")
	_check(not paused, "el título no queda en pausa")
	_check(root.find_child("WorldViewport", true, false) == null, "el juego viejo se ha borrado")
	while root.find_child("LoadingCover", true, false) != null and frames < MAX_FRAMES:
		await process_frame
		frames += 1
	_check(root.find_child("LoadingCover", true, false) == null, "la carga al título se va sola")
	# Y otra partida.
	await _enter_game(current_scene, "_new_game")
	print("boot_smoke: OK" if _ok else "boot_smoke: FAILED")
	quit(0 if _ok else 1)


func _enter_game(title: Node, action: String) -> void:
	title.call(action)
	await process_frame
	var cover: Object = root.find_child("LoadingCover", true, false)
	_check(cover != null, "%s abre la pantalla de carga" % action)
	var seen: Array[float] = []
	var frames: int = 0
	while frames < MAX_FRAMES:
		await process_frame
		frames += 1
		if not is_instance_valid(cover):
			break
		var target: float = cover.get(&"_target")
		seen.append(target)
	_check(not is_instance_valid(cover), "la pantalla de carga se va sola (%d frames)" % frames)
	var rising: bool = seen.size() > 3
	for i: int in range(1, seen.size()):
		rising = rising and seen[i] >= seen[i - 1]
	_check(rising and seen[seen.size() - 1] >= 0.99, "la barra sólo avanza y llega al final")
	_check(current_scene != null and current_scene.name == "Main", "el juego está montado")
	_check(root.find_child("TitleScreen", true, false) == null, "el título ya no está")
	_check(root.find_child("MotherCrystal", true, false) != null, "el cristal está montado")
	var crystal: Node = root.find_child("MotherCrystal", true, false)
	_check(
		crystal.find_child("Chunks", false, false).get_child_count() > 50,
		"el cristal tiene sus trozos (hechos en la carga)"
	)


func _buttons(screen: Node) -> Array[String]:
	var out: Array[String] = []
	for b: Node in screen.find_children("*", "Button", true, false):
		if (b as Button).is_visible_in_tree():
			out.append((b as Button).text)
	return out


func _check(cond: bool, what: String) -> void:
	if not cond:
		_ok = false
		printerr("FALLO: ", what)
