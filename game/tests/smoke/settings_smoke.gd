extends SceneTree
## Opciones: todas (FOV, VSync, límite de FPS, FPS en pantalla, invertir Y, reducir destellos,
## mantener para cargar, volúmenes...) se guardan y se vuelven a leer igual; "Restaurar valores"
## vuelve a los de serie; el FOV se aplica en vivo a la cámara del mago y la capa de magia HD lo
## copia; el menú de opciones tiene sus cuatro pestañas. No toca el archivo de opciones del
## jugador (usa otro).
## godot --headless --path game --script res://tests/smoke/settings_smoke.gd

const TEST_PATH: String = "user://settings_smoke.cfg"
const SETTINGS_SCRIPT: String = "res://autoload/settings.gd"

var _ok: bool = true


func _initialize() -> void:
	root.get_node(^"SaveSystem").set(&"enabled", false)
	_check_persistence()
	await _check_live_fov()
	print("settings_smoke: ", "OK" if _ok else "FALLO")
	quit(0 if _ok else 1)


func _check_persistence() -> void:
	var script: GDScript = load(SETTINGS_SCRIPT)
	var a: Node = script.new()
	a.set(&"path", TEST_PATH)
	a.set(&"fov", 97.0)
	a.set(&"vsync", false)
	a.set(&"fps_limit", 144)
	a.set(&"show_fps", true)
	a.set(&"invert_y", true)
	a.set(&"reduce_flashes", true)
	a.set(&"hold_to_charge", false)
	a.set(&"damage_numbers", false)
	a.set(&"screen_shake", 0.25)
	a.set(&"mouse_sensitivity", 1.7)
	a.set(&"menu_hint_seen", true)
	var vols: Dictionary = a.get(&"bus_volumes")
	vols["Music"] = 0.35
	vols["UI"] = 0.5
	a.call(&"save_settings")
	var b: Node = script.new()
	b.set(&"path", TEST_PATH)
	b.call(&"load_settings")
	_check(is_equal_approx(VariantCast.to_float(b.get(&"fov")), 97.0), "FOV guardado")
	_check(not VariantCast.to_bool(b.get(&"vsync")), "VSync guardado")
	_check(VariantCast.to_int(b.get(&"fps_limit")) == 144, "límite de FPS guardado")
	_check(VariantCast.to_bool(b.get(&"show_fps")), "mostrar FPS guardado")
	_check(VariantCast.to_bool(b.get(&"invert_y")), "invertir Y guardado")
	_check(VariantCast.to_bool(b.get(&"reduce_flashes")), "reducir destellos guardado")
	_check(not VariantCast.to_bool(b.get(&"hold_to_charge")), "mantener para cargar guardado")
	_check(not VariantCast.to_bool(b.get(&"damage_numbers")), "números de daño guardados")
	_check(is_equal_approx(VariantCast.to_float(b.get(&"screen_shake")), 0.25), "sacudida guardada")
	_check(
		is_equal_approx(VariantCast.to_float(b.get(&"mouse_sensitivity")), 1.7),
		"sensibilidad guardada"
	)
	_check(VariantCast.to_bool(b.get(&"menu_hint_seen")), "ayuda del menú vista guardada")
	var vb: Dictionary = b.get(&"bus_volumes")
	_check(is_equal_approx(VariantCast.to_float(vb["Music"]), 0.35), "volumen de música guardado")
	_check(is_equal_approx(VariantCast.to_float(vb["UI"]), 0.5), "volumen de interfaz guardado")
	_check(VariantCast.to_float(b.call(&"flash_scale")) < 1.0, "reducir destellos los baja")
	# Un FOV fuera de rango en el archivo se recorta.
	var cfg := ConfigFile.new()
	cfg.load(TEST_PATH)
	cfg.set_value("video", "fov", 400.0)
	cfg.save(TEST_PATH)
	b.call(&"load_settings")
	_check(
		(
			VariantCast.to_float(b.get(&"fov"))
			<= VariantCast.to_float(script.get_script_constant_map()["FOV_MAX"])
		),
		"FOV acotado"
	)
	b.call(&"restore_defaults")
	_check(is_equal_approx(VariantCast.to_float(b.get(&"fov")), 70.0), "restaurar: FOV de serie")
	_check(
		VariantCast.to_bool(b.get(&"vsync")) and VariantCast.to_int(b.get(&"fps_limit")) == 0,
		"restaurar: vídeo de serie"
	)
	_check(
		(
			not VariantCast.to_bool(b.get(&"invert_y"))
			and VariantCast.to_bool(b.get(&"hold_to_charge"))
		),
		"restaurar: controles"
	)
	_check(
		(
			not VariantCast.to_bool(b.get(&"reduce_flashes"))
			and VariantCast.to_bool(b.get(&"damage_numbers"))
		),
		"restaurar: accesibilidad"
	)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))
	a.free()
	b.free()


func _check_live_fov() -> void:
	var settings: Node = root.get_node(^"Settings")
	var fov0: float = settings.get(&"fov")
	change_scene_to_file("res://main/main.tscn")
	for i: int in 30:
		await process_frame
	var cam: Camera3D = current_scene.get_node(^"WorldView/WorldViewport/Player/Head/Camera")
	var magic: Camera3D = current_scene.find_child("MagicCamera", true, false)
	for fov: float in [60.0, 110.0]:
		settings.set(&"fov", fov)
		for i: int in 30:
			await process_frame
		_check(absf(cam.fov - fov) < 1.5, "FOV %d en la cámara (%.1f)" % [fov, cam.fov])
		_check(is_equal_approx(magic.fov, cam.fov), "la capa de magia copia el FOV %d" % fov)
	# Desde la pausa (Opciones): el FOV se ve en vivo detrás del menú.
	paused = true
	settings.set(&"fov", 90.0)
	settings.emit_signal(&"changed")
	for i: int in 3:
		await process_frame
	_check(absf(cam.fov - 90.0) < 1.5, "FOV en vivo con el juego en pausa (%.1f)" % cam.fov)
	_check(is_equal_approx(magic.fov, cam.fov), "la capa de magia lo copia en pausa")
	paused = false
	settings.set(&"fov", fov0)
	var options: Node = current_scene.find_child("Options", true, false)
	var pages: Array = []
	if options != null:
		pages = options.get(&"_pages")
	_check(options != null and pages.size() == 4, "opciones en 4 pestañas")
	options.call(&"select_tab", 2)
	pages = options.get(&"_pages")
	_check(VariantCast.to_bool(pages[2].visible and not pages[0].visible), "cambia de pestaña")


func _check(cond: bool, what: String) -> void:
	if not cond:
		print("  FALLO  " + what)
		_ok = false
