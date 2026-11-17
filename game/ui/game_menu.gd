class_name GameMenu
extends Control
## Menú del juego: pantalla de título (sobre el valle vivo, al arrancar) y pausa (Esc).
## Título: CONTINUAR / NUEVA PARTIDA / OPCIONES / SALIR. Pausa: REANUDAR / OPCIONES / GUARDAR Y
## SALIR. Opciones: volúmenes, sensibilidad del ratón, sacudida de cámara y pantalla completa
## (se guardan en Settings). Todo a píxel entero con las fuentes del HUD.

enum Mode { HIDDEN, TITLE, PAUSE }

const FONT_SMALL: FontFile = preload("res://ui/fonts/silkscreen_regular.woff2")
const FONT_BOLD: FontFile = preload("res://ui/fonts/pixelify_sans_bold.woff2")
const TICK_SFX: AudioStream = preload("res://audio/sfx/sfx_ui_tick_01.ogg")
const OK_SFX: AudioStream = preload("res://audio/sfx/sfx_book_open_01.ogg")
const C_BG := Color("#14183a")
const C_PANEL := Color("#24184f")
const C_PANEL_LIGHT := Color("#3b2a7a")
const C_GOLD := Color("#d8a23a")
const C_GOLD_LIGHT := Color("#ffd27a")
const C_TEXT := Color("#f2f6ff")
const C_CYAN := Color("#a5dae5")
const C_PINK := Color("#ff7ad9")

## Al volver a cargar la escena tras "Nueva partida", no se enseña otra vez el título.
static var skip_title_once: bool = false

var mode: Mode = Mode.HIDDEN

var _main_box: VBoxContainer
var _options_box: VBoxContainer
var _logo: Label
var _subtitle: Label
var _t: float = 0.0
var _theme: Theme


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	_theme = _make_theme()
	theme = _theme
	_logo = _label("CAN YOU DESTROY IT?", FONT_BOLD, 32, C_GOLD_LIGHT)
	_logo.position = Vector2(0, 58)
	_logo.size = Vector2(640, 40)
	_subtitle = _label(
		"UN APRENDIZ, UNA CHISPITA Y UN CRISTAL DEL TAMAÑO DE UNA MONTAÑA", FONT_SMALL, 8, C_CYAN
	)
	_subtitle.position = Vector2(0, 100)
	_subtitle.size = Vector2(640, 10)
	_main_box = VBoxContainer.new()
	_main_box.position = Vector2(240, 150)
	_main_box.size = Vector2(160, 120)
	_main_box.add_theme_constant_override(&"separation", 6)
	add_child(_main_box)
	_options_box = VBoxContainer.new()
	_options_box.position = Vector2(190, 120)
	_options_box.size = Vector2(260, 200)
	_options_box.add_theme_constant_override(&"separation", 4)
	_options_box.visible = false
	add_child(_options_box)
	_build_options()
	visible = false


## Pantalla de título (al arrancar el juego).
func show_title() -> void:
	if skip_title_once:
		skip_title_once = false
		return
	mode = Mode.TITLE
	_open()


func _open() -> void:
	visible = true
	_options_box.visible = false
	_main_box.visible = true
	_rebuild_main()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Events.menu_opened.emit()
	if mode == Mode.PAUSE:
		get_tree().paused = true


func _close() -> void:
	visible = false
	mode = Mode.HIDDEN
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	Events.menu_closed.emit()


func is_open() -> bool:
	return mode != Mode.HIDDEN


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"ui_cancel"):
		return
	if mode == Mode.PAUSE:
		if _options_box.visible:
			_show_main()
		else:
			_close()
		get_viewport().set_input_as_handled()
	elif mode == Mode.HIDDEN and _can_pause():
		mode = Mode.PAUSE
		_open()
		get_viewport().set_input_as_handled()


func _can_pause() -> bool:
	var g: Grimoire = get_parent().get_node_or_null(^"Grimoire") as Grimoire
	return g == null or not g.is_open


func _rebuild_main() -> void:
	for c: Node in _main_box.get_children():
		c.queue_free()
	_logo.visible = mode == Mode.TITLE
	_subtitle.visible = mode == Mode.TITLE
	if mode == Mode.TITLE:
		var has_save: bool = (
			GameState.progression.pylon_progress > 0
			or GameState.total_upgrade_levels() > 0
			or GameState.progression.essence < GameState.progression.total_essence
		)
		if has_save:
			_button("CONTINUAR", _close, true)
		_button("NUEVA PARTIDA", _new_game, not has_save)
	else:
		var pause: Label = _label("PAUSA", FONT_BOLD, 16, C_GOLD_LIGHT)
		pause.custom_minimum_size = Vector2(160, 22)
		remove_child(pause)
		_main_box.add_child(pause)
		_button("REANUDAR", _close, true)
	_button("OPCIONES", _show_options)
	_button("GUARDAR Y SALIR" if mode == Mode.PAUSE else "SALIR", _quit)
	await get_tree().process_frame
	if _main_box.get_child_count() > 0:
		for c: Node in _main_box.get_children():
			if c is Button:
				(c as Button).grab_focus()
				break


func _button(text: String, action: Callable, primary: bool = false) -> Button:
	var b := Button.new()
	b.text = tr(text)
	b.custom_minimum_size = Vector2(160, 20)
	b.focus_mode = Control.FOCUS_ALL
	if primary:
		b.add_theme_color_override(&"font_color", C_GOLD_LIGHT)
	b.pressed.connect(
		func() -> void:
			AudioDirector.play_sfx(OK_SFX, -10.0)
			action.call()
	)
	b.mouse_entered.connect(func() -> void: AudioDirector.play_sfx(TICK_SFX, -10.0))
	b.focus_entered.connect(func() -> void: AudioDirector.play_sfx(TICK_SFX, -14.0))
	_main_box.add_child(b)
	return b


func _new_game() -> void:
	GameState.reset()
	SaveSystem.save_game()
	skip_title_once = true
	get_tree().paused = false
	Events.menu_closed.emit()
	get_tree().reload_current_scene()


func _quit() -> void:
	SaveSystem.save_game()
	get_tree().quit()


func _show_options() -> void:
	_main_box.visible = false
	_options_box.visible = true
	_logo.visible = false
	_subtitle.visible = false
	for c: Node in _options_box.get_children():
		if c is HSlider:
			(c as HSlider).grab_focus()
			break


func _show_main() -> void:
	Settings.save_settings()
	_options_box.visible = false
	_main_box.visible = true
	_rebuild_main()


func _build_options() -> void:
	var title: Label = _label("OPCIONES", FONT_BOLD, 16, C_GOLD_LIGHT)
	remove_child(title)
	title.custom_minimum_size = Vector2(260, 22)
	_options_box.add_child(title)
	for bus: Array in [
		["VOLUMEN GENERAL", "Master"],
		["MÚSICA", "Music"],
		["EFECTOS", "SFX"],
		["AMBIENTE", "Ambience"]
	]:
		var bus_name: String = bus[1]
		_slider(
			bus[0],
			Settings.bus_volumes.get(bus_name, 1.0),
			func(v: float) -> void:
				Settings.bus_volumes[bus_name] = v
				Settings.apply_audio()
		)
	_slider(
		"SENSIBILIDAD DEL RATÓN",
		inverse_lerp(0.3, 2.5, Settings.mouse_sensitivity),
		func(v: float) -> void: Settings.mouse_sensitivity = lerpf(0.3, 2.5, v)
	)
	_slider(
		"SACUDIDA DE CÁMARA",
		Settings.screen_shake,
		func(v: float) -> void: Settings.screen_shake = v
	)
	var fs := CheckButton.new()
	fs.text = tr("PANTALLA COMPLETA")
	fs.button_pressed = Settings.fullscreen
	fs.toggled.connect(
		func(on: bool) -> void:
			Settings.fullscreen = on
			Settings.apply_video()
	)
	_options_box.add_child(fs)
	var back := Button.new()
	back.text = tr("VOLVER")
	back.custom_minimum_size = Vector2(260, 20)
	back.pressed.connect(_show_main)
	_options_box.add_child(back)


func _slider(text: String, value: float, on_change: Callable) -> void:
	var l: Label = _label(text, FONT_SMALL, 8, C_CYAN)
	remove_child(l)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_options_box.add_child(l)
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.05
	s.value = clampf(value, 0.0, 1.0)
	s.custom_minimum_size = Vector2(260, 10)
	s.value_changed.connect(
		func(v: float) -> void:
			on_change.call(v)
			AudioDirector.play_sfx(TICK_SFX, -14.0, lerpf(0.8, 1.4, v))
	)
	_options_box.add_child(s)


func _process(delta: float) -> void:
	_t += delta
	if visible and _logo.visible:
		# El título late y brilla a saltos, como pixel art.
		var k: float = floor(_t * 6.0) / 6.0
		_logo.position.y = 58 + roundi(sin(k * 1.4) * 2.0)
		_logo.add_theme_color_override(
			&"font_color",
			(
				C_GOLD_LIGHT.lerp(C_PINK, 0.5 + 0.5 * sin(k * 0.9))
				if fmod(k, 3.0) < 0.5
				else C_GOLD_LIGHT
			)
		)
	queue_redraw()


func _draw() -> void:
	if not visible:
		return
	if mode == Mode.TITLE:
		# Velo suave arriba y abajo para que el título se lea sobre el valle.
		draw_rect(Rect2(0, 0, 640, 130), Color(C_BG, 0.55))
		draw_rect(Rect2(0, 300, 640, 60), Color(C_BG, 0.45))
	else:
		draw_rect(Rect2(Vector2.ZERO, size), Color(C_BG, 0.7))
	# Marco del panel.
	var box: Control = _options_box if _options_box.visible else _main_box
	var r := Rect2(box.position - Vector2(12, 10), box.size + Vector2(24, 20))
	if box == _main_box:
		r.size.y = _main_box.get_combined_minimum_size().y + 20
	draw_rect(r.grow(2), C_BG)
	draw_rect(r, C_PANEL)
	draw_rect(Rect2(r.position, Vector2(r.size.x, 2)), C_GOLD)
	draw_rect(Rect2(r.position + Vector2(0, r.size.y - 2), Vector2(r.size.x, 2)), C_GOLD)
	for corner: Vector2 in [
		r.position,
		r.position + Vector2(r.size.x - 6, 0),
		r.position + Vector2(0, r.size.y - 6),
		r.end - Vector2(6, 6)
	]:
		draw_rect(Rect2(corner, Vector2(6, 6)), C_GOLD_LIGHT)


func _label(text: String, font: FontFile, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = tr(text)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override(&"font", font)
	l.add_theme_font_size_override(&"font_size", font_size)
	l.add_theme_color_override(&"font_color", color)
	l.add_theme_color_override(&"font_shadow_color", C_BG)
	l.add_theme_constant_override(&"shadow_offset_x", 1)
	l.add_theme_constant_override(&"shadow_offset_y", 1)
	add_child(l)
	return l


## Tema pixel: botones de panel violeta con borde dorado al pasar por encima.
func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font = FONT_SMALL
	t.default_font_size = 8
	var normal := StyleBoxFlat.new()
	normal.bg_color = C_PANEL_LIGHT
	normal.set_border_width_all(1)
	normal.border_color = C_BG
	normal.set_content_margin_all(4)
	var hover: StyleBoxFlat = normal.duplicate()
	hover.bg_color = Color("#4d3a9a")
	hover.border_color = C_GOLD_LIGHT
	var pressed: StyleBoxFlat = normal.duplicate()
	pressed.bg_color = C_GOLD
	for type: StringName in [&"Button", &"CheckButton"]:
		t.set_stylebox(&"normal", type, normal)
		t.set_stylebox(&"hover", type, hover)
		t.set_stylebox(&"focus", type, hover)
		t.set_stylebox(&"pressed", type, pressed)
		t.set_color(&"font_color", type, C_TEXT)
		t.set_color(&"font_hover_color", type, C_GOLD_LIGHT)
		t.set_color(&"font_focus_color", type, C_GOLD_LIGHT)
	var track := StyleBoxFlat.new()
	track.bg_color = C_BG
	track.content_margin_top = 2
	track.content_margin_bottom = 2
	var fill := StyleBoxFlat.new()
	fill.bg_color = C_PINK
	fill.content_margin_top = 2
	fill.content_margin_bottom = 2
	t.set_stylebox(&"slider", &"HSlider", track)
	t.set_stylebox(&"grabber_area", &"HSlider", fill)
	t.set_stylebox(&"grabber_area_highlight", &"HSlider", fill)
	return t
