class_name TitleScreen
extends Control
## Pantalla de título: ligera (sin mundo 3D) para que el juego arranque al instante. Fondo
## pintado del valle (`title_backdrop.png`, una captura del propio juego) con motas de maná que
## suben y destellos en el cristal, el logo (`TitleLogo`) y el menú CONTINUAR / NUEVA PARTIDA /
## OPCIONES / SALIR. Mientras se ve, el juego se carga en otro hilo (`SceneFlow.preload_game`).
## Tema, marco y opciones son los del menú del juego (`GameMenu`, `OptionsMenu`).

const BACKDROP_PATH: String = "res://title/title_backdrop.png"
## Zona del cristal en el fondo donde brillan los destellos.
const CRYSTAL_GLINTS := Rect2(280, 10, 230, 200)
const MOTES: int = 46

var _backdrop: Texture2D
var _logo: TitleLogo
var _main_box: VBoxContainer
var _options_box: OptionsMenu
var _t: float = 0.0
var _leaving: bool = false
var _confirm_new: bool = false
var _motes: Array[Vector4] = []
var _glints: Array[Vector3] = []
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	# Modo demo (capturas, sólo debug): directo al juego, como antes de existir el título.
	if OS.is_debug_build() and OS.get_cmdline_user_args().has("--autoplay"):
		get_tree().change_scene_to_file.call_deferred(SceneFlow.GAME_SCENE)
		visible = false
		set_process(false)
		return
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	theme = GameMenu.make_theme()
	_rng.randomize()
	if ResourceLoader.exists(BACKDROP_PATH):
		_backdrop = load(BACKDROP_PATH)
	for i: int in MOTES:
		_motes.append(_new_mote(true))
	for i: int in 5:
		_glints.append(_new_glint())
	_logo = TitleLogo.new()
	_logo.name = "TitleLogo"
	add_child(_logo)
	_main_box = VBoxContainer.new()
	_main_box.name = "Menu"
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
	AudioDirector.stop_world()
	AudioDirector.play_theme(GameMenu.TITLE_MUSIC)
	_rebuild()
	# El juego empieza a cargarse en otro hilo en cuanto el título ya se ve.
	get_tree().process_frame.connect(SceneFlow.preload_game, CONNECT_ONE_SHOT)
	# --title-play (sólo debug): pulsa JUGAR solo a los 1,5 s (capturas de la pantalla de carga).
	if OS.is_debug_build() and OS.get_cmdline_user_args().has("--title-play"):
		get_tree().create_timer(1.5).timeout.connect(_play)


## Hay partida que continuar.
static func has_save() -> bool:
	var prog: Progression = GameState.progression
	return (
		prog.pylon_progress > 0
		or GameState.total_upgrade_levels() > 0
		or prog.essence < prog.total_essence
		or prog.game_complete
	)


func _rebuild() -> void:
	for c: Node in _main_box.get_children():
		_main_box.remove_child(c)
		c.queue_free()
	_logo.visible = true
	if _confirm_new:
		var q: Label = _label("¿EMPEZAR DE CERO?")
		q.custom_minimum_size = Vector2(160, 20)
		_main_box.add_child(q)
		_button("SÍ, BORRAR LA PARTIDA", _new_game)
		_button("NO, VOLVER", _cancel_new, true)
	else:
		var save: bool = has_save()
		if save:
			_button("CONTINUAR", _play, true)
		_button("NUEVA PARTIDA", _ask_new_game, not save)
		_button("OPCIONES", _show_options)
		_button("SALIR", get_tree().quit)
	_focus_first.call_deferred()


func _focus_first() -> void:
	for c: Node in _main_box.get_children():
		if c is Button:
			(c as Button).grab_focus()
			return


func _button(text: String, action: Callable, primary: bool = false) -> Button:
	var b := Button.new()
	b.text = tr(text)
	b.custom_minimum_size = Vector2(160, 20)
	b.focus_mode = Control.FOCUS_ALL
	if primary:
		b.add_theme_color_override(&"font_color", GameMenu.C_GOLD_LIGHT)
	b.pressed.connect(
		func() -> void:
			if _leaving:
				return
			AudioDirector.play_sfx(GameMenu.OK_SFX, -10.0)
			action.call()
	)
	b.mouse_entered.connect(func() -> void: AudioDirector.play_sfx(GameMenu.TICK_SFX, -10.0))
	b.focus_entered.connect(func() -> void: AudioDirector.play_sfx(GameMenu.TICK_SFX, -14.0))
	_main_box.add_child(b)
	return b


func _label(text: String) -> Label:
	var l := Label.new()
	l.text = tr(text)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_override(&"font", UiFonts.TITLE)
	l.add_theme_font_size_override(&"font_size", UiFonts.HEAD)
	l.add_theme_color_override(&"font_color", GameMenu.C_GOLD_LIGHT)
	return l


func _play() -> void:
	_leaving = true
	SceneFlow.to_game(get_tree())


func _ask_new_game() -> void:
	if has_save():
		_confirm_new = true
		_rebuild()
	else:
		_new_game()


func _cancel_new() -> void:
	_confirm_new = false
	_rebuild()


func _new_game() -> void:
	GameState.reset()
	SaveSystem.save_game()
	# El cristal excavado de la partida vieja ya no vale (lo protege la esencia, pero mejor no
	# dejarlo por ahí).
	if FileAccess.file_exists(CrystalPrebuild.STATE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(CrystalPrebuild.STATE_PATH))
	_play()


func _show_options() -> void:
	_main_box.visible = false
	_logo.visible = false
	_options_box.visible = true
	_options_box.focus_first()


func _show_main() -> void:
	Settings.save_settings()
	_options_box.visible = false
	_main_box.visible = true
	_rebuild()


func _relocalize() -> void:
	_rebuild()
	_logo.relocalize()
	Events.locale_changed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"ui_cancel") or _leaving:
		return
	if _options_box.visible:
		AudioDirector.play_sfx(GameMenu.TICK_SFX, -10.0)
		_show_main()
		get_viewport().set_input_as_handled()
	elif _confirm_new:
		_cancel_new()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	_t += delta
	for i: int in _motes.size():
		var m: Vector4 = _motes[i]
		m.y -= m.z * delta
		m.x += sin(_t * 0.7 + m.w * 6.0) * 4.0 * delta
		_motes[i] = m if m.y > 150.0 else _new_mote(false)
	for i: int in _glints.size():
		var g: Vector3 = _glints[i]
		g.z += delta * 1.6
		_glints[i] = g if g.z < 1.0 else _new_glint()
	queue_redraw()


## Mota de maná: x, y, velocidad, fase (y = 360 + algo al nacer, salvo al principio).
func _new_mote(anywhere: bool) -> Vector4:
	var y: float = _rng.randf_range(150.0, 360.0) if anywhere else _rng.randf_range(362.0, 380.0)
	return Vector4(_rng.randf_range(0.0, 640.0), y, _rng.randf_range(6.0, 16.0), _rng.randf())


## Destello sobre el cristal: x, y, edad (0..1; empieza escalonado).
func _new_glint() -> Vector3:
	var r: Rect2 = CRYSTAL_GLINTS
	return Vector3(
		_rng.randf_range(r.position.x, r.end.x),
		_rng.randf_range(r.position.y, r.end.y),
		-_rng.randf_range(0.0, 1.6)
	)


func _draw() -> void:
	if _backdrop:
		draw_texture(_backdrop, Vector2.ZERO)
	else:
		for y: int in range(0, 360, 4):
			var k: float = y / 360.0
			draw_rect(Rect2(0, y, 640, 4), GameMenu.C_BG.lerp(GameMenu.C_PANEL, k))
	# Motas de maná que suben del valle.
	for m: Vector4 in _motes:
		var a: float = clampf((360.0 - m.y) / 60.0, 0.0, 1.0) * clampf((m.y - 150.0) / 50.0, 0, 1)
		var col: Color = GameMenu.C_CYAN if m.w < 0.6 else GameMenu.C_PINK
		draw_rect(Rect2(roundf(m.x), roundf(m.y), 1, 1), Color(col, 0.75 * a))
	# Destellos en cruz sobre el cristal.
	for g: Vector3 in _glints:
		if g.z < 0.0:
			continue
		var r: int = roundi(sin(g.z * PI) * 3.0)
		var c := Vector2(roundf(g.x), roundf(g.y))
		var col := Color(1.0, 1.0, 1.0, sin(g.z * PI))
		draw_rect(Rect2(c.x - r, c.y, r * 2 + 1, 1), col)
		draw_rect(Rect2(c.x, c.y - r, 1, r * 2 + 1), col)
	# Velo arriba y abajo para que el logo y el menú se lean sobre el valle.
	for y: int in range(0, 160, 2):
		var a: float = 0.6 * pow(1.0 - y / 160.0, 1.5)
		draw_rect(Rect2(0, y, 640, 2), Color(GameMenu.C_BG, a))
	for y: int in range(290, 360, 2):
		draw_rect(Rect2(0, y, 640, 2), Color(GameMenu.C_BG, 0.5 * pow((y - 290) / 70.0, 1.5)))
	var box: Control = _options_box if _options_box.visible else _main_box
	var rect := Rect2(box.position - Vector2(12, 10), box.size + Vector2(24, 20))
	rect.size.y = box.get_combined_minimum_size().y + 20
	GameMenu.draw_panel(self, rect)
