class_name OptionsMenu
extends VBoxContainer
## Opciones del juego en cuatro pestañas (Vídeo, Audio, Controles y Accesibilidad), con el valor
## de cada barra a la derecha y una fila fija abajo: idioma, restaurar valores y volver. Todo se
## aplica en vivo (el FOV se ve en el valle por detrás de la pausa) y se guarda en Settings al
## volver. Lo usa el menú del juego (título y pausa) y lo pinta dentro de su marco.

## El jugador pide volver al menú anterior.
signal back_requested
## Ha cambiado el idioma: el menú del juego rehace sus textos y avisa al resto.
signal locale_switched

const TICK_SFX: AudioStream = preload("res://audio/sfx/sfx_ui_tick_01.ogg")
const OK_SFX: AudioStream = preload("res://audio/sfx/sfx_book_open_01.ogg")
## Ancho del panel, de la columna de nombres y de la del valor de cada barra.
const W: float = 344.0
const LABEL_W: float = 150.0
const VALUE_W: float = 40.0
const ROW_H: float = 18.0
## Ancho del interruptor pixel art (GameMenu._switch_icon).
const SWITCH_W: float = 20.0
## Separación entre filas de una pestaña.
const ROW_GAP: int = 3
# i18n
const TABS: PackedStringArray = ["VÍDEO", "AUDIO", "CONTROLES", "ACCESIBILIDAD"]

var _tab: int = 0
var _tab_buttons: Array[Button] = []
var _pages: Array[VBoxContainer] = []


func _ready() -> void:
	add_theme_constant_override(&"separation", 6)
	_build()


## Abre la pestaña `index` (0 vídeo, 1 audio, 2 controles, 3 accesibilidad).
func select_tab(index: int, sound: bool = false) -> void:
	_tab = clampi(index, 0, TABS.size() - 1)
	for i: int in _pages.size():
		_pages[i].visible = i == _tab
		var on: bool = i == _tab
		_tab_buttons[i].add_theme_color_override(
			&"font_color", GameMenu.C_GOLD_LIGHT if on else GameMenu.C_CYAN
		)
		_tab_buttons[i].add_theme_stylebox_override(&"normal", _tab_style(on))
	if sound:
		AudioDirector.play_sfx(TICK_SFX, -10.0, 1.1)


## Foco en la pestaña abierta (para jugar con teclado o mando).
func focus_first() -> void:
	if _tab < _tab_buttons.size():
		_tab_buttons[_tab].grab_focus.call_deferred()


func _build() -> void:
	for c: Node in get_children():
		remove_child(c)
		c.queue_free()
	_tab_buttons.clear()
	_pages.clear()
	var title: Label = _label("OPCIONES", UiFonts.TITLE, UiFonts.HEAD, GameMenu.C_GOLD_LIGHT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.custom_minimum_size = Vector2(W, UiFonts.HEAD_LINE)
	add_child(title)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override(&"separation", 2)
	add_child(tabs)
	for i: int in TABS.size():
		var b := Button.new()
		b.text = tr(TABS[i])
		b.custom_minimum_size = Vector2(0, ROW_H)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.focus_mode = Control.FOCUS_ALL
		b.pressed.connect(select_tab.bind(i, true))
		b.mouse_entered.connect(func() -> void: AudioDirector.play_sfx(TICK_SFX, -16.0))
		tabs.add_child(b)
		_tab_buttons.append(b)
	for i: int in TABS.size():
		var page := VBoxContainer.new()
		page.add_theme_constant_override(&"separation", ROW_GAP)
		add_child(page)
		_pages.append(page)
	_build_video(_pages[0])
	_build_audio(_pages[1])
	_build_controls(_pages[2])
	_build_accessibility(_pages[3])
	# Todas las pestañas igual de altas: el panel no salta al cambiar.
	var h: float = 0.0
	for page: VBoxContainer in _pages:
		h = maxf(h, page.get_combined_minimum_size().y)
	for page: VBoxContainer in _pages:
		page.custom_minimum_size = Vector2(W, h)
	var line := ColorRect.new()
	line.color = Color(GameMenu.C_GOLD, 0.5)
	line.custom_minimum_size = Vector2(W, 1)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(line)
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override(&"separation", 4)
	add_child(bottom)
	_language_button(bottom)
	_bottom_button(bottom, tr("RESTAURAR VALORES"), _restore)
	var back: Button = _bottom_button(bottom, tr("VOLVER"), back_requested.emit)
	back.add_theme_color_override(&"font_color", GameMenu.C_GOLD_LIGHT)
	select_tab(_tab)


func _build_video(page: VBoxContainer) -> void:
	_slider(
		page,
		tr("CAMPO DE VISIÓN"),
		[Settings.FOV_MIN, Settings.FOV_MAX, 1.0, Settings.fov],
		func(v: float) -> String: return "%d°" % roundi(v),
		func(v: float) -> void:
			Settings.fov = v
			Settings.changed.emit()
	)
	_switch(
		page,
		tr("PANTALLA COMPLETA"),
		Settings.fullscreen,
		func(on: bool) -> void:
			Settings.fullscreen = on
			Settings.apply_video()
	)
	_switch(
		page,
		tr("SINCRONÍA VERTICAL (VSYNC)"),
		Settings.vsync,
		func(on: bool) -> void:
			Settings.vsync = on
			Settings.apply_video()
	)
	_fps_limit_row(page)
	_switch(
		page,
		tr("MOSTRAR FPS"),
		Settings.show_fps,
		func(on: bool) -> void:
			Settings.show_fps = on
			Settings.changed.emit()
	)


func _build_audio(page: VBoxContainer) -> void:
	for bus: Array in [
		[tr("VOLUMEN GENERAL"), "Master"],
		[tr("MÚSICA"), "Music"],
		[tr("EFECTOS"), "SFX"],
		[tr("AMBIENTE"), "Ambience"],
		[tr("INTERFAZ"), "UI"],
	]:
		var bus_label: String = bus[0]
		var bus_name: String = bus[1]
		_slider(
			page,
			bus_label,
			[0.0, 1.0, 0.05, Settings.bus_volumes.get(bus_name, 1.0)],
			_percent,
			func(v: float) -> void:
				Settings.bus_volumes[bus_name] = v
				Settings.apply_audio()
		)


func _build_controls(page: VBoxContainer) -> void:
	_slider(
		page,
		tr("SENSIBILIDAD DEL RATÓN"),
		[0.3, 2.5, 0.05, Settings.mouse_sensitivity],
		func(v: float) -> String: return "x%.2f" % v,
		func(v: float) -> void: Settings.mouse_sensitivity = v
	)
	_switch(
		page,
		tr("INVERTIR EJE Y"),
		Settings.invert_y,
		func(on: bool) -> void: Settings.invert_y = on
	)
	_key_list(page)


func _build_accessibility(page: VBoxContainer) -> void:
	_slider(
		page,
		tr("SACUDIDA DE CÁMARA"),
		[0.0, 1.0, 0.05, Settings.screen_shake],
		_percent,
		func(v: float) -> void: Settings.screen_shake = v
	)
	_switch(
		page,
		tr("REDUCIR DESTELLOS"),
		Settings.reduce_flashes,
		func(on: bool) -> void:
			Settings.reduce_flashes = on
			Settings.changed.emit()
	)
	_switch(
		page,
		tr("MANTENER CLIC PARA CARGAR"),
		Settings.hold_to_charge,
		func(on: bool) -> void: Settings.hold_to_charge = on
	)
	_switch(
		page,
		tr("NÚMEROS DE DAÑO"),
		Settings.damage_numbers,
		func(on: bool) -> void: Settings.damage_numbers = on
	)
	_switch(
		page,
		tr("SANGRE DE CARICATURA"),
		Settings.cartoon_gore,
		func(on: bool) -> void: Settings.cartoon_gore = on
	)


## Chuleta de las teclas (las mismas frases que la ayuda del HUD), en dos columnas.
func _key_list(page: VBoxContainer) -> void:
	# Las mismas frases que la ayuda del HUD, sin "CLIC PARA EMPEZAR".
	var first: String = tr("CLIC PARA EMPEZAR  ·  WASD MOVERSE  ·  SHIFT CORRER  ·  ESPACIO SALTAR")
	var items: PackedStringArray = first.split("  ·  ").slice(1)
	var second: String = tr(
		"CLIC IZQ / DER: CADA MANO  ·  LOS DOS A LA VEZ: COMBINAR  ·  F RECOGER  ·  TAB GRIMORIO"
	)
	items.append_array(second.split("  ·  "))
	items.append(tr("Q / E: ELEMENTO DE CADA MANO"))
	items.append(tr("R / RUEDA: ELEMENTO DEL BÁCULO"))
	items.append(tr("B: LIBRO DE COMBINACIONES"))
	items.append(tr("ESC: MENÚ Y OPCIONES"))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override(&"h_separation", 12)
	grid.add_theme_constant_override(&"v_separation", UiFonts.LINE_GAP)
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(W, 2)
	page.add_child(pad)
	page.add_child(grid)
	for item: String in items:
		var l: Label = _label("", UiFonts.BODY, UiFonts.SMALL, Color(GameMenu.C_TEXT, 0.85))
		l.text = item
		l.custom_minimum_size = Vector2((W - 12.0) * 0.5, UiFonts.LINE)
		grid.add_child(l)


static func _percent(v: float) -> String:
	return "%d %%" % roundi(v * 100.0)


## Fila con barra (`text` ya traducido): el nombre a la izquierda, la barra y su valor a la derecha.
## `range_value`: [mínimo, máximo, paso, valor actual].
func _slider(
	page: VBoxContainer, text: String, range_value: Array, fmt: Callable, on_change: Callable
) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 8)
	row.custom_minimum_size = Vector2(W, ROW_H)
	page.add_child(row)
	var l: Label = _label("", UiFonts.BOLD, UiFonts.SMALL, GameMenu.C_CYAN)
	l.text = text
	l.custom_minimum_size = Vector2(LABEL_W, UiFonts.LINE)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = range_value[0]
	s.max_value = range_value[1]
	s.step = range_value[2]
	s.value = clampf(VariantCast.to_float(range_value[3]), s.min_value, s.max_value)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.custom_minimum_size = Vector2(0, 10)
	row.add_child(s)
	var val: Label = _label("", UiFonts.BOLD, UiFonts.SMALL, GameMenu.C_TEXT)
	val.text = fmt.call(s.value)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val.custom_minimum_size = Vector2(VALUE_W, UiFonts.LINE)
	val.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(val)
	s.value_changed.connect(
		func(v: float) -> void:
			on_change.call(v)
			val.text = fmt.call(v)
			var k: float = inverse_lerp(s.min_value, s.max_value, v)
			AudioDirector.play_sfx(TICK_SFX, -14.0, lerpf(0.8, 1.4, k))
	)
	_focus_tint(s, l)


## Fila con interruptor: todo el ancho es el botón (nombre a la izquierda, interruptor a la
## derecha).
func _switch(page: VBoxContainer, text: String, on: bool, on_toggle: Callable) -> void:
	var c := CheckButton.new()
	c.text = text
	c.button_pressed = on
	c.custom_minimum_size = Vector2(W, ROW_H)
	c.focus_mode = Control.FOCUS_ALL
	_row_style(c)
	# "SÍ" / "NO" junto al interruptor, en la columna de valores de las barras: el estado se lee
	# de un vistazo aunque el interruptor sea pequeño.
	var val: Label = _label("", UiFonts.BOLD, UiFonts.SMALL, GameMenu.C_TEXT)
	val.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	val.offset_right = -SWITCH_W - 6.0
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	c.add_child(val)
	var paint: Callable = func(v: bool) -> void:
		val.text = tr("SÍ") if v else tr("NO")
		val.add_theme_color_override(&"font_color", GameMenu.C_TEXT if v else GameMenu.C_CYAN)
	paint.call(on)
	c.toggled.connect(
		func(v: bool) -> void:
			on_toggle.call(v)
			paint.call(v)
			AudioDirector.play_sfx(TICK_SFX, -10.0, 1.25 if v else 0.9)
	)
	page.add_child(c)


## Límite de FPS: botón que recorre 30 / 60 / 120 / 144 / sin límite (clic, o izquierda y
## derecha con el foco en él).
func _fps_limit_row(page: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 8)
	row.custom_minimum_size = Vector2(W, ROW_H)
	page.add_child(row)
	var l: Label = _label("LÍMITE DE FPS", UiFonts.BOLD, UiFonts.SMALL, GameMenu.C_CYAN)
	l.custom_minimum_size = Vector2(LABEL_W, UiFonts.LINE)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(l)
	var b := Button.new()
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.focus_mode = Control.FOCUS_ALL
	b.text = _fps_text()
	row.add_child(b)
	var step: Callable = func(dir: int) -> void:
		var i: int = Settings.FPS_LIMITS.find(Settings.fps_limit)
		Settings.fps_limit = Settings.FPS_LIMITS[wrapi(i + dir, 0, Settings.FPS_LIMITS.size())]
		Settings.apply_video()
		b.text = _fps_text()
		AudioDirector.play_sfx(
			TICK_SFX, -10.0, 1.0 + 0.08 * Settings.FPS_LIMITS.find(Settings.fps_limit)
		)
	b.pressed.connect(step.bind(1))
	b.gui_input.connect(
		func(e: InputEvent) -> void:
			if e.is_action_pressed(&"ui_right"):
				step.call(1)
				b.accept_event()
			elif e.is_action_pressed(&"ui_left"):
				step.call(-1)
				b.accept_event()
	)
	_focus_tint(b, l)


func _fps_text() -> String:
	var v: String = tr("SIN LÍMITE") if Settings.fps_limit <= 0 else str(Settings.fps_limit)
	return "<  %s  >" % v


## "IDIOMA: ESPAÑOL": cada clic pasa al siguiente idioma cargado y rehace los menús.
func _language_button(parent: HBoxContainer) -> void:
	var codes: PackedStringArray = Settings.locales()
	if codes.size() < 2:
		return
	var text: String = tr("IDIOMA: %s") % Settings.language_name(Settings.current_locale())
	var lang: Button = _bottom_button(parent, text, func() -> void: pass)
	lang.add_theme_color_override(&"font_color", GameMenu.C_GOLD_LIGHT)
	lang.pressed.connect(
		func() -> void:
			var i: int = codes.find(Settings.current_locale())
			Settings.set_locale(codes[wrapi(i + 1, 0, codes.size())])
			_build()
			locale_switched.emit()
			focus_first()
	)


func _restore() -> void:
	Settings.restore_defaults()
	Settings.save_settings()
	_build()
	focus_first()


func _bottom_button(parent: HBoxContainer, text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, ROW_H)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.focus_mode = Control.FOCUS_ALL
	b.pressed.connect(
		func() -> void:
			AudioDirector.play_sfx(OK_SFX, -10.0)
			action.call()
	)
	b.mouse_entered.connect(func() -> void: AudioDirector.play_sfx(TICK_SFX, -16.0))
	parent.add_child(b)
	return b


## El nombre de la fila se pone dorado mientras su control tiene el foco.
static func _focus_tint(control: Control, label: Label) -> void:
	control.focus_entered.connect(
		func() -> void: label.add_theme_color_override(&"font_color", GameMenu.C_GOLD_LIGHT)
	)
	control.focus_exited.connect(
		func() -> void: label.add_theme_color_override(&"font_color", GameMenu.C_CYAN)
	)


## Interruptores como filas: sin fondo, con un borde dorado al pasar o con el foco.
static func _row_style(c: CheckButton) -> void:
	var flat := StyleBoxEmpty.new()
	flat.content_margin_left = 0
	flat.content_margin_right = 0
	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(GameMenu.C_PANEL_LIGHT, 0.6)
	hover.border_color = Color(GameMenu.C_GOLD_LIGHT, 0.7)
	hover.border_width_bottom = 1
	hover.content_margin_left = 0
	hover.content_margin_right = 0
	for s: StringName in [&"normal", &"pressed", &"hover_pressed"]:
		c.add_theme_stylebox_override(s, flat)
	for s: StringName in [&"hover", &"focus"]:
		c.add_theme_stylebox_override(s, hover)
	c.add_theme_color_override(&"font_color", GameMenu.C_CYAN)
	c.add_theme_color_override(&"font_pressed_color", GameMenu.C_CYAN)
	c.add_theme_color_override(&"font_hover_pressed_color", GameMenu.C_GOLD_LIGHT)


## Pestaña: la abierta en violeta claro con filete dorado abajo; las otras, oscuras.
static func _tab_style(on: bool) -> StyleBoxFlat:
	var st := StyleBoxFlat.new()
	st.bg_color = GameMenu.C_PANEL_LIGHT if on else Color("#1c1440")
	st.set_border_width_all(1)
	st.border_color = GameMenu.C_BG
	if on:
		st.border_width_bottom = 2
		st.border_color = GameMenu.C_GOLD
	st.set_content_margin_all(3)
	return st


func _label(text: String, font: Font, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = tr(text)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override(&"font", font)
	l.add_theme_font_size_override(&"font_size", font_size)
	l.add_theme_color_override(&"font_color", color)
	l.add_theme_color_override(&"font_shadow_color", GameMenu.C_BG)
	l.add_theme_constant_override(&"shadow_offset_x", 1)
	l.add_theme_constant_override(&"shadow_offset_y", 1)
	return l
