class_name GameMenu
extends Control
## Menú del juego: pantalla de título (sobre el valle vivo, al arrancar) y pausa (Esc).
## Título: CONTINUAR / NUEVA PARTIDA / OPCIONES / SALIR. Pausa: REANUDAR / OPCIONES / GUARDAR Y
## SALIR. Las opciones (en pestañas: vídeo, audio, controles y accesibilidad) son un
## `OptionsMenu`. Todo a píxel entero con las fuentes del HUD. El tema y el marco del panel los
## comparte el menú de depuración (`make_theme`, `draw_panel`).

enum Mode { HIDDEN, TITLE, PAUSE }

const TITLE_MUSIC: AudioStream = preload("res://audio/music/music_title.ogg")
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
## Agarrador de las barras en píxeles (el de Godot es un círculo suave que desentona).
## "#" contorno, "+" brillo, "=" cuerpo, "o" sombra.
const GRABBER: PackedStringArray = [
	".######.",
	"#+++++=#",
	"#+====o#",
	"#+====o#",
	"#+====o#",
	"#+====o#",
	"#+====o#",
	"#+====o#",
	"#+====o#",
	"#=ooooo#",
	".######.",
]

## Al volver a cargar la escena tras "Nueva partida", no se enseña otra vez el título.
static var skip_title_once: bool = false

var mode: Mode = Mode.HIDDEN

var _main_box: VBoxContainer
var _options_box: OptionsMenu
var _logo: TitleLogo
var _theme: Theme


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	_theme = make_theme()
	theme = _theme
	_logo = TitleLogo.new()
	_logo.name = "TitleLogo"
	add_child(_logo)
	_main_box = VBoxContainer.new()
	_main_box.position = Vector2(240, 150)
	_main_box.size = Vector2(160, 120)
	_main_box.add_theme_constant_override(&"separation", 6)
	add_child(_main_box)
	_options_box = OptionsMenu.new()
	_options_box.name = "Options"
	_options_box.position = Vector2(roundf((640.0 - OptionsMenu.W) * 0.5), 82)
	_options_box.visible = false
	add_child(_options_box)
	_options_box.back_requested.connect(_show_main)
	_options_box.locale_switched.connect(_relocalize)
	visible = false


## Pantalla de título (al arrancar el juego).
func show_title() -> void:
	mode = Mode.TITLE
	AudioDirector.play_theme(TITLE_MUSIC)
	_open()


## Modo demo (capturas): "title", "pause" u "options" (las opciones desde la pausa);
## "options2" abre la pestaña 2 (0 vídeo, 1 audio, 2 controles, 3 accesibilidad) y
## "options-tour" las recorre todas, una cada 0,5 s.
func demo_open(which: String) -> void:
	if which == "title":
		show_title()
		return
	mode = Mode.PAUSE
	_open()
	if which == "options-tour":
		_show_options()
		for i: int in range(1, OptionsMenu.TABS.size()):
			get_tree().create_timer(0.5 * i).timeout.connect(_options_box.select_tab.bind(i))
	elif which.begins_with("options"):
		_show_options()
		_options_box.select_tab(int(which.trim_prefix("options")))


func _open() -> void:
	visible = true
	_options_box.visible = false
	_main_box.visible = true
	_rebuild_main()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Events.menu_opened.emit()
	if mode == Mode.PAUSE:
		get_tree().paused = true
		# Ya sabe dónde está el menú: el HUD deja de enseñar "ESC: MENÚ".
		# En modo demo (no se guarda la partida) tampoco se tocan las opciones del jugador.
		if not Settings.menu_hint_seen:
			Settings.menu_hint_seen = true
			if SaveSystem.enabled:
				Settings.save_settings()


func _close() -> void:
	if mode == Mode.TITLE:
		AudioDirector.stop_theme()
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
	if mode != Mode.HIDDEN and _options_box.visible:
		AudioDirector.play_sfx(TICK_SFX, -10.0)
		_show_main()
		get_viewport().set_input_as_handled()
	elif mode == Mode.PAUSE:
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
	if mode == Mode.TITLE:
		var has_save: bool = (
			GameState.progression.pylon_progress > 0
			or GameState.total_upgrade_levels() > 0
			or GameState.progression.essence < GameState.progression.total_essence
		)
		if has_save:
			_button("CONTINUAR", _close, true)
		_button("NUEVA PARTIDA", new_game, not has_save)
	else:
		var pause: Label = _label("PAUSA", UiFonts.TITLE, UiFonts.HEAD, C_GOLD_LIGHT)
		pause.custom_minimum_size = Vector2(160, 20)
		remove_child(pause)
		_main_box.add_child(pause)
		_button("REANUDAR", _close, true)
	_button("OPCIONES", _show_options)
	_button(tr("GUARDAR Y SALIR") if mode == Mode.PAUSE else tr("SALIR"), _quit)
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


## Empieza de cero (la usa también el menú de depuración).
func new_game() -> void:
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
	_options_box.focus_first()


func _show_main() -> void:
	Settings.save_settings()
	_options_box.visible = false
	_main_box.visible = true
	_rebuild_main()


## Rehace los textos de los menús con el idioma nuevo y avisa al resto (HUD, Grimorio...).
func _relocalize() -> void:
	_rebuild_main()
	_logo.relocalize()
	Events.locale_changed.emit()


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if not visible:
		return
	if mode == Mode.TITLE:
		# Velo suave arriba y abajo para que el título se lea sobre el valle.
		for y: int in range(0, 160, 2):
			var a: float = 0.6 * pow(1.0 - y / 160.0, 1.5)
			draw_rect(Rect2(0, y, 640, 2), Color(C_BG, a))
		for y: int in range(290, 360, 2):
			draw_rect(Rect2(0, y, 640, 2), Color(C_BG, 0.5 * pow((y - 290) / 70.0, 1.5)))
	else:
		draw_rect(Rect2(Vector2.ZERO, size), Color(C_BG, 0.7))
	# Marco del panel.
	var box: Control = _options_box if _options_box.visible else _main_box
	var r := Rect2(box.position - Vector2(12, 10), box.size + Vector2(24, 20))
	r.size.y = box.get_combined_minimum_size().y + 20
	draw_panel(self, r)


## Marco de los paneles del juego: violeta con filetes y esquinas doradas.
static func draw_panel(ci: CanvasItem, r: Rect2) -> void:
	ci.draw_rect(r.grow(2), C_BG)
	ci.draw_rect(r, C_PANEL)
	ci.draw_rect(Rect2(r.position, Vector2(r.size.x, 2)), C_GOLD)
	ci.draw_rect(Rect2(r.position + Vector2(0, r.size.y - 2), Vector2(r.size.x, 2)), C_GOLD)
	for corner: Vector2 in [
		r.position,
		r.position + Vector2(r.size.x - 6, 0),
		r.position + Vector2(0, r.size.y - 6),
		r.end - Vector2(6, 6)
	]:
		ci.draw_rect(Rect2(corner, Vector2(6, 6)), C_GOLD_LIGHT)


func _label(text: String, font: Font, font_size: int, color: Color) -> Label:
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
static func make_theme() -> Theme:
	var t := Theme.new()
	t.default_font = UiFonts.BOLD
	t.default_font_size = UiFonts.SMALL
	t.set_constant(&"line_spacing", &"Label", UiFonts.LINE_GAP)
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
	t.set_icon(&"grabber", &"HSlider", _grabber_icon(C_GOLD_LIGHT, C_GOLD, Color("#9a6a24")))
	t.set_icon(&"grabber_highlight", &"HSlider", _grabber_icon(C_TEXT, C_GOLD_LIGHT, C_GOLD))
	t.set_icon(&"checked", &"CheckButton", _switch_icon(true))
	t.set_icon(&"unchecked", &"CheckButton", _switch_icon(false))
	# Barra de desplazamiento fina: carril oscuro y agarrador dorado.
	var rail := StyleBoxFlat.new()
	rail.bg_color = C_BG
	rail.content_margin_left = 2
	rail.content_margin_right = 2
	var thumb := StyleBoxFlat.new()
	thumb.bg_color = C_GOLD
	var thumb_hi: StyleBoxFlat = thumb.duplicate()
	thumb_hi.bg_color = C_GOLD_LIGHT
	t.set_stylebox(&"scroll", &"VScrollBar", rail)
	t.set_stylebox(&"grabber", &"VScrollBar", thumb)
	t.set_stylebox(&"grabber_highlight", &"VScrollBar", thumb_hi)
	t.set_stylebox(&"grabber_pressed", &"VScrollBar", thumb_hi)
	return t


## Agarrador pixel art de las barras (ver GRABBER) con los colores dados.
static func _grabber_icon(light: Color, body: Color, shade: Color) -> ImageTexture:
	var img := Image.create(GRABBER[0].length(), GRABBER.size(), false, Image.FORMAT_RGBA8)
	for y: int in GRABBER.size():
		for x: int in GRABBER[y].length():
			match GRABBER[y][x]:
				"#":
					img.set_pixel(x, y, C_BG)
				"+":
					img.set_pixel(x, y, light)
				"=":
					img.set_pixel(x, y, body)
				"o":
					img.set_pixel(x, y, shade)
	return ImageTexture.create_from_image(img)


## Interruptor pixel art de "pantalla completa": carril con contorno y botón a un lado.
static func _switch_icon(on: bool) -> ImageTexture:
	var img := Image.create(20, 10, false, Image.FORMAT_RGBA8)
	img.fill_rect(Rect2i(1, 0, 18, 10), C_BG)
	img.fill_rect(Rect2i(0, 1, 20, 8), C_BG)
	img.fill_rect(Rect2i(1, 1, 18, 8), Color("#b0479a") if on else C_PANEL)
	var kx: int = 11 if on else 1
	img.fill_rect(Rect2i(kx, 1, 8, 8), C_BG)
	img.fill_rect(Rect2i(kx + 1, 2, 6, 6), C_GOLD if on else Color("#8a7fb8"))
	img.fill_rect(Rect2i(kx + 1, 2, 5, 1), C_GOLD_LIGHT if on else C_CYAN)
	img.fill_rect(Rect2i(kx + 1, 2, 1, 5), C_GOLD_LIGHT if on else C_CYAN)
	return ImageTexture.create_from_image(img)
