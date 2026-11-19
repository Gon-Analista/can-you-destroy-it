class_name EndingScreen
extends Control
## Pantalla final (GDD 9): la pregunta respondida, "Yes, you could." (en inglés en todos los
## idiomas, como el título; debajo, el subtítulo traducido "Sí, pudiste."), y la partida en cifras:
## tiempo jugado, combinaciones descubiertas, mejoras compradas, fragmentos recogidos y hechizos
## lanzados (las cifras cuentan hacia arriba). Botones: Créditos, Seguir en el valle (se cierra y
## el valle sigue de fiesta) y Nueva partida (pide confirmación). El valle sigue vivo detrás.

signal continue_requested
signal new_game_requested

const ANSWER: String = "Yes, you could."
const FANFARE_SFX: AudioStream = preload("res://audio/sfx/sfx_ending_fanfare_01.ogg")
const TICK_SFX: AudioStream = preload("res://audio/sfx/sfx_ui_tick_01.ogg")
const OK_SFX: AudioStream = preload("res://audio/sfx/sfx_book_open_01.ogg")
const PANEL := Rect2(176, 128, 288, 98)
const TYPE_SEC: float = 0.07
const COUNT_SEC: float = 1.6
## Créditos (fuentes y arte de terceros, ver CREDITS.md).
# i18n
const CREDITS: PackedStringArray = [
	"CAN YOU DESTROY IT?",
	"Diseño, programación, arte 3D, música y sonido: el equipo del juego",
	"Manos y orbe mágico: Sprite AI",
	"Fuentes: Fusion Pixel (TakWolf, OFL) y Pixelify Sans (OFL)",
	"Hecho con Godot Engine (MIT)",
	"¡Gracias por jugar!",
]

var _t: float = -1.0
var _title: Label
var _subtitle: Label
var _rows: Array[Label] = []
var _values: Array[Label] = []
var _targets: Array[float] = []
var _formats: Array[int] = []
var _buttons: HBoxContainer
var _new_game: Button
var _credits: VBoxContainer
var _confirm: bool = false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = GameMenu.make_theme()
	_title = _label("", UiFonts.LOGO, 33, GameMenu.C_GOLD_LIGHT)
	_title.position = Vector2(0, 48)
	_title.size = Vector2(640, 44)
	_subtitle = _label("", UiFonts.TITLE, UiFonts.HEAD, GameMenu.C_PINK)
	_subtitle.position = Vector2(0, 98)
	_subtitle.size = Vector2(640, UiFonts.HEAD_LINE)
	for i: int in 5:
		var row: Label = _label("", UiFonts.BOLD, UiFonts.SMALL, GameMenu.C_CYAN)
		row.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.position = PANEL.position + Vector2(12, 10 + i * 16)
		row.size = Vector2(190, UiFonts.LINE)
		_rows.append(row)
		var val: Label = _label("", UiFonts.TITLE, UiFonts.HEAD, GameMenu.C_TEXT)
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		val.position = PANEL.position + Vector2(180, 9 + i * 16)
		val.size = Vector2(96, UiFonts.HEAD_LINE)
		_values.append(val)
		_targets.append(0.0)
		_formats.append(0)
	_credits = VBoxContainer.new()
	_credits.position = PANEL.position + Vector2(8, 8)
	_credits.size = PANEL.size - Vector2(16, 16)
	_credits.add_theme_constant_override(&"separation", 2)
	_credits.visible = false
	add_child(_credits)
	_buttons = HBoxContainer.new()
	_buttons.position = Vector2(140, 246)
	_buttons.size = Vector2(360, 20)
	_buttons.add_theme_constant_override(&"separation", 8)
	add_child(_buttons)
	_button("CRÉDITOS", _toggle_credits)
	var stay: Button = _button("SEGUIR EN EL VALLE", _continue)
	stay.add_theme_color_override(&"font_color", GameMenu.C_GOLD_LIGHT)
	_new_game = _button("NUEVA PARTIDA", _ask_new_game)
	visible = false
	Events.locale_changed.connect(_relocalize)
	Events.menu_closed.connect(_on_menu_closed)


func is_open() -> bool:
	return visible


## Se abre con las cifras de la partida y la fanfarria.
func open() -> void:
	var prog: Progression = GameState.progression
	_targets[0] = prog.time_played
	_targets[1] = float(prog.discovered_recipes.size())
	_targets[2] = float(GameState.total_upgrade_levels())
	_targets[3] = float(prog.shards_collected)
	_targets[4] = float(prog.spells_cast)
	_formats = [1, 2, 0, 0, 0]
	_confirm = false
	_credits.visible = false
	_relocalize()
	_t = 0.0
	visible = true
	modulate.a = 0.0
	AudioDirector.play_sfx(FANFARE_SFX, -1.0)
	_claim()
	if not prog.ending_seen:
		prog.ending_seen = true
		SaveSystem.save_game()


## Ratón suelto y el mago quieto mientras se ve la pantalla.
func _claim() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Events.menu_opened.emit()
	_focus_first.call_deferred()


## La pausa (Esc) se puede abrir encima; al cerrarla, la pantalla final sigue mandando (si no, el
## ratón se quedaba capturado sin poder pulsar los botones y el mago andaba por detrás).
func _on_menu_closed() -> void:
	if visible and _t >= 0.0:
		_claim.call_deferred()


## Con la pantalla abierta no se abren el Grimorio ni el Libro de Combinaciones por debajo (los
## botones ya han recibido sus teclas antes; Esc sí llega a la pausa).
func _unhandled_input(event: InputEvent) -> void:
	if not visible or event.is_action_pressed(&"ui_cancel"):
		return
	if event is InputEventKey or event is InputEventJoypadButton:
		get_viewport().set_input_as_handled()


func _focus_first() -> void:
	if _buttons.get_child_count() > 1:
		(_buttons.get_child(1) as Button).grab_focus()


func _relocalize() -> void:
	# i18n
	var names: PackedStringArray = [
		"TIEMPO JUGADO",
		"COMBINACIONES DESCUBIERTAS",
		"MEJORAS COMPRADAS",
		"FRAGMENTOS RECOGIDOS",
		"HECHIZOS LANZADOS",
	]
	for i: int in _rows.size():
		_rows[i].text = tr(names[i])
	var sub: String = tr("Sí, pudiste.")
	_subtitle.text = sub if sub != ANSWER else ""
	for c: Node in _credits.get_children():
		c.queue_free()
	for i: int in CREDITS.size():
		var l: Label = _label(
			CREDITS[i] if i == 0 else tr(CREDITS[i]),
			UiFonts.TITLE if i == 0 else UiFonts.BODY,
			UiFonts.HEAD if i == 0 else UiFonts.SMALL,
			GameMenu.C_GOLD_LIGHT if i == 0 or i == CREDITS.size() - 1 else GameMenu.C_TEXT
		)
		remove_child(l)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(PANEL.size.x - 16, 0)
		_credits.add_child(l)
	_refresh_buttons()


func _process(delta: float) -> void:
	if _t < 0.0 or not visible:
		return
	_t += delta
	modulate.a = clampf(_t / 0.8, 0.0, 1.0)
	# "Yes, you could." letra a letra, con un tic por letra.
	var n: int = clampi(floori((_t - 0.6) / TYPE_SEC), 0, ANSWER.length())
	if n != _title.text.length():
		_title.text = ANSWER.substr(0, n)
		if n > 0 and ANSWER[n - 1] != " ":
			AudioDirector.play_sfx(TICK_SFX, -16.0, 1.0 + 0.04 * n)
	_subtitle.visible = _t > 0.6 + TYPE_SEC * ANSWER.length() + 0.3
	# Las cifras cuentan hacia arriba; después ya no se rehacen los textos cada fotograma.
	var count_end: float = 1.8 + COUNT_SEC
	if _t - delta <= count_end + 0.1:
		var k: float = clampf((_t - 1.8) / COUNT_SEC, 0.0, 1.0)
		k = 1.0 - pow(1.0 - k, 3.0)
		for i: int in _values.size():
			_values[i].text = _format(i, _targets[i] * k)
	if _t - delta <= 0.6 + TYPE_SEC * ANSWER.length() + 0.1:
		queue_redraw()


func _format(i: int, v: float) -> String:
	match _formats[i]:
		1:
			var s: int = floori(v)
			return "%d:%02d:%02d" % [s / 3600, (s / 60) % 60, s % 60]
		2:
			return "%d / %d" % [roundi(v), SpellCaster.RECIPES.size() + StaffCombos.triples().size()]
	return Hud.format_int(roundi(v))


func _draw() -> void:
	if not visible:
		return
	# Velo de arriba abajo (el valle de fiesta se sigue viendo) y el panel de las cifras.
	for y: int in range(0, 360, 2):
		var a: float = 0.35 + 0.3 * pow(absf(y - 180.0) / 180.0, 1.4)
		draw_rect(Rect2(0, y, 640, 2), Color(GameMenu.C_BG, a))
	GameMenu.draw_panel(self, PANEL)
	# Filete dorado bajo la respuesta.
	var w: float = 200.0 * clampf((_t - 0.6) / (TYPE_SEC * ANSWER.length()), 0.0, 1.0)
	draw_rect(Rect2(320.0 - w * 0.5, 94, w, 1), GameMenu.C_GOLD)


func _toggle_credits() -> void:
	_credits.visible = not _credits.visible
	for i: int in _rows.size():
		_rows[i].visible = not _credits.visible
		_values[i].visible = not _credits.visible


func _continue() -> void:
	visible = false
	_t = -1.0
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	Events.menu_closed.emit()
	continue_requested.emit()


func _ask_new_game() -> void:
	if not _confirm:
		_confirm = true
		_refresh_buttons()
		return
	new_game_requested.emit()


func _refresh_buttons() -> void:
	# i18n
	var keys: PackedStringArray = ["CRÉDITOS", "SEGUIR EN EL VALLE", "NUEVA PARTIDA"]
	for i: int in mini(keys.size(), _buttons.get_child_count()):
		(_buttons.get_child(i) as Button).text = tr(keys[i])
	if _new_game and _confirm:
		_new_game.text = tr("¿SEGURO? OTRA VEZ")


func _button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = tr(text)
	b.custom_minimum_size = Vector2(114, 20)
	b.focus_mode = Control.FOCUS_ALL
	b.pressed.connect(
		func() -> void:
			AudioDirector.play_sfx(OK_SFX, -10.0)
			action.call()
	)
	b.mouse_entered.connect(func() -> void: AudioDirector.play_sfx(TICK_SFX, -10.0))
	_buttons.add_child(b)
	return b


func _label(text: String, font: Font, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override(&"font", font)
	l.add_theme_font_size_override(&"font_size", font_size)
	l.add_theme_color_override(&"font_color", color)
	l.add_theme_color_override(&"font_shadow_color", GameMenu.C_BG)
	l.add_theme_constant_override(&"shadow_offset_x", 1)
	l.add_theme_constant_override(&"shadow_offset_y", 1)
	add_child(l)
	return l
