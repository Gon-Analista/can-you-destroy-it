class_name DebugMenu
extends Control
## Menú de depuración (Alt+F1): un panel a la derecha, sin pausar el juego (los trucos se ven
## en vivo detrás), con lo más útil para probar: comprarlo todo con los hechizos a nivel 11,
## maná, bolsa, nivel de los hechizos, Pilón, capas y geodas del cristal, hora, velocidad del
## juego, FPS, modo dios, teletransportes y la partida. Arriba, datos en vivo.
##
## Sólo en builds de desarrollo, o con `-- --debug-menu` (o la etiqueta de exportación
## "debug_menu") en una build final. Abrirlo suelta el ratón; cerrarlo (Alt+F1 o Esc) lo vuelve
## a capturar. Reutiliza los trucos de `Main` (`debug_*`) y `SpellCaster.set_debug_level`.

const OPEN_SFX: AudioStream = preload("res://audio/sfx/sfx_book_open_01.ogg")
const CLOSE_SFX: AudioStream = preload("res://audio/sfx/sfx_book_close_01.ogg")
const TICK_SFX: AudioStream = preload("res://audio/sfx/sfx_ui_tick_01.ogg")
const BUY_SFX: AudioStream = preload("res://audio/sfx/sfx_upgrade_buy_01.ogg")
const BIG_SFX: AudioStream = preload("res://audio/sfx/sfx_combo_discovered_01.ogg")
const DENY_SFX: AudioStream = preload("res://audio/sfx/sfx_ui_deny_01.ogg")
const MANA_SFX: AudioStream = preload("res://audio/sfx/sfx_mana_drop_01.ogg")
const PICKUP_SFX: AudioStream = preload("res://audio/sfx/sfx_shard_pickup_01.ogg")
const WARP_SFX: AudioStream = preload("res://audio/sfx/sfx_telekinesis_01.ogg")
const CRYSTAL_SFX: AudioStream = preload("res://audio/sfx/sfx_crystal_surge_01.ogg")
const REVEAL_SFX: AudioStream = preload("res://audio/sfx/sfx_reveal_01.ogg")
const PANEL_W: float = 280.0
const MARGIN: float = 10.0
## Ancho de la columna con el nombre de cada fila.
const LABEL_W: float = 62.0
const BUTTON_H: float = 16.0
const MAX_LEVEL: int = ElementDef.MAX_LEVEL
const MANA_STEPS: PackedInt32Array = [100, 1000, 100000, 1000000]
const MANA_NAMES: PackedStringArray = ["+100", "+1K", "+100K", "+1M"]
const PYLON_STEPS: PackedFloat32Array = [0.25, 0.5, 0.75, 0.99]
const SPEEDS: PackedFloat32Array = [1.0, 2.0, 5.0]
## Segundos para pulsar otra vez "REINICIAR" y confirmar.
const RESET_CONFIRM_SEC: float = 3.0
const INFO_SEC: float = 0.25
const TOAST_SEC: float = 2.6
const C_RED := Color("#ff6b6b")
## Estrella del botón de comprarlo todo ("#" contorno, "+" brillo, "=" cuerpo).
const STAR: PackedStringArray = [
	"....#....",
	"...#+#...",
	"...#+#...",
	"####=####",
	"#++====o#",
	".#=====#.",
	"..#=o=#..",
	".#=#.#o#.",
	".##...##.",
]

## ¿Hay menú en esta build? (Se mira una vez: `_input` lo consulta con cada evento.)
static var _available: int = -1

## Modo dios: recarga instantánea y levitación infinita (si se tiene).
var god_mode: bool = false

var _open: bool = false
## 0 cerrado ... 1 abierto: el panel entra deslizándose desde la derecha.
var _slide: float = 0.0
var _main: Main
var _player: Player
var _day_night: DayNight
var _hut: ApprenticeHut
var _holder: Control
var _scroll: ScrollContainer
var _info: Label
var _toast: Label
var _toast_t: float = 0.0
var _info_t: float = 0.0
var _reset_button: Button
var _reset_armed: float = 0.0
var _fps_button: Button
var _god_button: Button
var _speed_buttons: Array[Button] = []
var _level_buttons: Array[Button] = []
var _star: ImageTexture


## ¿Hay menú de depuración en esta build?
static func available() -> bool:
	if _available < 0:
		_available = (
			1
			if (
				OS.is_debug_build()
				or OS.has_feature("debug_menu")
				or OS.get_cmdline_user_args().has("--debug-menu")
			)
			else 0
		)
	return _available == 1


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = _make_theme()
	_star = _star_icon()
	_holder = Control.new()
	_holder.name = "Panel"
	_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_holder.position = Vector2(640.0 - PANEL_W - MARGIN, MARGIN)
	_holder.size = Vector2(PANEL_W, 360.0 - MARGIN * 2.0)
	add_child(_holder)
	_build()
	visible = false
	set_process(false)
	Events.locale_changed.connect(_build)
	# El Grimorio (Tab en el Santuario) se abre encima: el panel se aparta y le deja el ratón.
	Events.grimoire_opened.connect(close)


## Lo llama Main: los trucos necesitan el mago, el día y la noche y la casucha.
func bind(main: Main, player: Player, day_night: DayNight, hut: ApprenticeHut) -> void:
	_main = main
	_player = player
	_day_night = day_night
	_hut = hut


func is_open() -> bool:
	return _open


func open() -> void:
	if _open or not available():
		return
	_open = true
	visible = true
	set_process(true)
	_refresh_states()
	_update_info()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	AudioDirector.play_sfx(OPEN_SFX, -8.0, 1.25)


func close() -> void:
	if not _open:
		return
	_open = false
	_reset_armed = 0.0
	_reset_button.text = tr("REINICIAR")
	AudioDirector.play_sfx(CLOSE_SFX, -8.0, 1.25)
	if not _other_overlay_open():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func toggle() -> void:
	if _open:
		close()
	elif not _other_overlay_open():
		open()


## Alt+F1 abre y cierra; Esc cierra (antes de que el menú de pausa lo vea).
func _input(event: InputEvent) -> void:
	if not available():
		return
	var key := event as InputEventKey
	if key and key.pressed and not key.echo and key.keycode == KEY_F1 and key.alt_pressed:
		toggle()
		get_viewport().set_input_as_handled()
	elif _open and event.is_action_pressed(&"ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _other_overlay_open() -> bool:
	var hud: Hud = get_parent() as Hud
	if hud == null:
		return false
	var book: Grimoire = hud.get_node_or_null(^"Grimoire") as Grimoire
	var spells: SpellBook = hud.get_node_or_null(^"SpellBook") as SpellBook
	return (
		(hud.menu != null and hud.menu.is_open())
		or (book != null and book.is_open)
		or (spells != null and spells.is_open)
	)


func _process(delta: float) -> void:
	# Modo dios: la levitación nunca se acaba (también con el menú cerrado).
	if god_mode and _player and _player.levitation_max > 0.0:
		_player.levitation_fuel = _player.levitation_max
	var real: float = delta / maxf(Engine.time_scale, 0.01)
	var target: float = 1.0 if _open else 0.0
	if _slide != target:
		_slide = move_toward(_slide, target, real * 7.0)
		var k: float = 1.0 - pow(1.0 - _slide, 3.0)
		_holder.position.x = roundf(640.0 - (PANEL_W + MARGIN) * k)
		modulate.a = clampf(_slide * 2.0, 0.0, 1.0)
		if _slide <= 0.0:
			visible = false
	if not _open and _slide <= 0.0:
		set_process(god_mode)
		return
	if _reset_armed > 0.0:
		_reset_armed -= real
		if _reset_armed <= 0.0:
			_reset_button.text = tr("REINICIAR")
	if _toast_t > 0.0:
		_toast_t -= real
		_toast.modulate.a = clampf(_toast_t / 0.4, 0.0, 1.0)
	_info_t -= real
	if _info_t <= 0.0:
		_info_t = INFO_SEC
		_update_info()
	queue_redraw()


func _draw() -> void:
	var r := Rect2(_holder.position, _holder.size).grow(-2)
	GameMenu.draw_panel(self, r)


# --- Construcción ---


func _build() -> void:
	for c: Node in _holder.get_children():
		_holder.remove_child(c)
		c.queue_free()
	_speed_buttons.clear()
	_level_buttons.clear()
	_scroll = ScrollContainer.new()
	_scroll.position = Vector2(10, 9)
	_scroll.size = _holder.size - Vector2(16, 18)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_holder.add_child(_scroll)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(_scroll.size.x - 6, 0)
	box.add_theme_constant_override(&"separation", 3)
	_scroll.add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	var title: Label = _label("DEPURACIÓN", UiFonts.TITLE, UiFonts.HEAD, GameMenu.C_GOLD_LIGHT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var keys: Label = _label("ALT+F1 · ESC", UiFonts.BODY, UiFonts.SMALL, GameMenu.C_CYAN)
	keys.size_flags_vertical = Control.SIZE_SHRINK_END
	head.add_child(keys)
	_info = _label("", UiFonts.BODY, UiFonts.SMALL, GameMenu.C_TEXT)
	_info.custom_minimum_size = Vector2(1, UiFonts.PITCH * 3)
	_info.clip_text = true
	box.add_child(_info)
	var all: Button = _button(box, tr("COMPRAR TODO Y HECHIZOS AL MÁXIMO"), buy_everything)
	all.name = "BuyAll"
	all.icon = _star
	all.custom_minimum_size = Vector2(0, 20)
	# En otros idiomas el texto es más largo que el panel: que baje de línea.
	all.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	all.add_theme_color_override(&"font_color", GameMenu.C_GOLD_LIGHT)
	var row: Container = _row(box, tr("MANÁ"))
	for i: int in MANA_STEPS.size():
		_button(row, MANA_NAMES[i], _add_mana.bind(MANA_STEPS[i]))
	row = _row(box, tr("BOLSA"))
	_button(row, tr("LLENAR"), _fill_bag)
	_button(row, tr("VACIAR"), _empty_bag)
	_button(row, tr("+3 LÁGRIMAS"), _add_tears)
	# Niveles 1-5 y AUTO arriba, 6-11 debajo, en la misma rejilla.
	row = _row(box, tr("HECHIZOS"))
	var grid := GridContainer.new()
	grid.columns = 6
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override(&"h_separation", 2)
	grid.add_theme_constant_override(&"v_separation", 3)
	row.add_child(grid)
	for lv: int in range(1, 6):
		_level_buttons.append(_button(grid, str(lv), _set_spell_level.bind(lv)))
	_level_buttons.append(_button(grid, tr("AUTO"), _set_spell_level.bind(0)))
	for lv: int in range(6, MAX_LEVEL + 1):
		_level_buttons.append(_button(grid, str(lv), _set_spell_level.bind(lv)))
	row = _row(box, tr("PILÓN"))
	for r: float in PYLON_STEPS:
		_button(row, "%d %%" % roundi(r * 100.0), _set_pylon.bind(r))
	row = _row(box, tr("CRISTAL"))
	_button(row, tr("SIGUIENTE CAPA"), _next_layer)
	_button(row, tr("REVELAR GEODA"), _reveal_geode)
	row = _row(box, tr("FINAL"))
	_button(row, tr("IR AL NÚCLEO (99 %)"), _go_to_core)
	_button(row, tr("LANZAR GRAN CONVERGENCIA"), _cast_convergence)
	row = _row(box, tr("HORA"))
	_button(row, "+3 H", _add_hours.bind(3.0))
	_button(row, tr("DÍA"), _set_time.bind(0.5))
	_button(row, tr("NOCHE"), _set_time.bind(0.0))
	row = _row(box, tr("VELOCIDAD"))
	for s: float in SPEEDS:
		_speed_buttons.append(_button(row, "x%d" % roundi(s), _set_speed.bind(s)))
	row = _row(box, tr("TRUCOS"))
	_fps_button = _button(row, tr("MOSTRAR FPS"), _toggle_fps)
	_god_button = _button(row, tr("MODO DIOS"), _toggle_god)
	_button(row, tr("SUBIR DE RANGO"), _rank_up)
	for b: Button in [_fps_button, _god_button]:
		b.toggle_mode = true
	row = _row(box, tr("RUNAS"))
	_button(row, tr("DESBLOQUEAR TODAS"), _unlock_runes)
	row = _row(box, tr("BICHOS"))
	_button(row, tr("APARECER 5"), _spawn_critters)
	row = _row(box, tr("IR A"))
	_button(row, tr("SANTUARIO"), _warp.bind(&"sanctum"))
	_button(row, tr("PILÓN"), _warp.bind(&"pylon"))
	_button(row, tr("CRISTAL"), _warp.bind(&"crystal"))
	row = _row(box, tr("PARTIDA"))
	_button(row, tr("GUARDAR AHORA"), _save_now)
	_reset_button = _button(row, tr("REINICIAR"), _reset_game)
	_reset_button.add_theme_color_override(&"font_color", C_RED)
	_toast = _label("", UiFonts.BOLD, UiFonts.SMALL, GameMenu.C_GOLD_LIGHT)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Dos líneas reservadas: el panel no cambia de alto ni de ancho con avisos largos.
	UiFonts.paragraph(_toast)
	_toast.custom_minimum_size = Vector2(1, UiFonts.LINE + UiFonts.PITCH)
	box.add_child(_toast)
	_refresh_states()
	# El panel tan alto como su contenido (con barra de desplazamiento si no cabe).
	var h: float = box.get_combined_minimum_size().y + 18.0
	_holder.size.y = minf(h, 360.0 - MARGIN * 2.0)
	_scroll.size = _holder.size - Vector2(16, 18)


## Fila: el nombre a la izquierda y sus botones repartidos a lo ancho. Los botones van en un
## contenedor que salta de línea: si no caben (textos largos, otros idiomas) bajan a la
## siguiente en vez de ensanchar el panel y salirse de la pantalla.
func _row(box: VBoxContainer, text: String) -> Container:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 2)
	box.add_child(row)
	var l: Label = _label("", UiFonts.BOLD, UiFonts.SMALL, GameMenu.C_CYAN)
	l.text = text
	l.custom_minimum_size = Vector2(LABEL_W, BUTTON_H)
	l.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(l)
	var flow := HFlowContainer.new()
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flow.add_theme_constant_override(&"h_separation", 2)
	flow.add_theme_constant_override(&"v_separation", 3)
	row.add_child(flow)
	return flow


## Botón de una fila (`text` ya traducido).
func _button(parent: Container, text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, BUTTON_H)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(action)
	b.mouse_entered.connect(func() -> void: AudioDirector.play_sfx(TICK_SFX, -18.0, 1.2))
	parent.add_child(b)
	return b


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


## El tema de los menús con botones más bajos (caben más filas).
static func _make_theme() -> Theme:
	var t: Theme = GameMenu.make_theme()
	for state: StringName in [&"normal", &"hover", &"pressed", &"focus"]:
		var st: StyleBoxFlat = (t.get_stylebox(state, &"Button") as StyleBoxFlat).duplicate()
		st.content_margin_top = 1
		st.content_margin_bottom = 1
		st.content_margin_left = 3
		st.content_margin_right = 3
		t.set_stylebox(state, &"Button", st)
	t.set_stylebox(&"hover_pressed", &"Button", t.get_stylebox(&"pressed", &"Button"))
	t.set_color(&"font_pressed_color", &"Button", GameMenu.C_BG)
	t.set_color(&"font_hover_pressed_color", &"Button", GameMenu.C_BG)
	t.set_constant(&"h_separation", &"Button", 3)
	return t


static func _star_icon() -> ImageTexture:
	var img := Image.create(STAR[0].length(), STAR.size(), false, Image.FORMAT_RGBA8)
	for y: int in STAR.size():
		for x: int in STAR[y].length():
			match STAR[y][x]:
				"#":
					img.set_pixel(x, y, GameMenu.C_BG)
				"+":
					img.set_pixel(x, y, Color.WHITE)
				"=":
					img.set_pixel(x, y, GameMenu.C_GOLD_LIGHT)
				"o":
					img.set_pixel(x, y, GameMenu.C_GOLD)
	return ImageTexture.create_from_image(img)


## Botones que llevan estado: nivel forzado, velocidad, FPS y modo dios.
func _refresh_states() -> void:
	var lv: int = maxi(_caster().debug_recipe_level, 0) if _player else 0
	for i: int in _level_buttons.size():
		var b_lv: int = i + 1 if i < 5 else (0 if i == 5 else i)
		_mark(_level_buttons[i], b_lv == lv)
	for i: int in _speed_buttons.size():
		_mark(_speed_buttons[i], is_equal_approx(SPEEDS[i], HitStop.base_scale))
	_fps_button.set_pressed_no_signal(Settings.show_fps)
	_god_button.set_pressed_no_signal(god_mode)


static func _mark(b: Button, on: bool) -> void:
	if on:
		b.add_theme_color_override(&"font_color", GameMenu.C_GOLD_LIGHT)
		b.add_theme_color_override(&"font_hover_color", GameMenu.C_GOLD_LIGHT)
	else:
		b.remove_theme_color_override(&"font_color")
		b.remove_theme_color_override(&"font_hover_color")


func _update_info() -> void:
	var prog: Progression = GameState.progression
	var shards: int = 0
	var pool: ShardPool = get_tree().get_first_node_in_group(&"shard_pool") as ShardPool
	if pool:
		for type: ShardType in ShardPool.ALL_TYPES:
			shards += pool.count_of(type)
	var layer: String = tr(GameState.current_layer().display_name).to_upper()
	_info.text = (
		(
			"%d FPS  ·  x%d  ·  %s %s\n"
			% [
				roundi(Engine.get_frames_per_second()),
				roundi(HitStop.base_scale),
				tr("MANÁ"),
				Hud.format_int(prog.mana)
			]
		)
		+ "%s %.1f %%  ·  %s\n" % [tr("PILÓN"), prog.pylon_ratio() * 100.0, layer]
		+ (
			"%s %d  ·  %s %d/%d"
			% [tr("FRAGMENTOS"), shards, tr("BOLSA"), prog.bag_count(), GameState.bag_capacity()]
		)
	)


## Aviso al pie del panel (y su sonido).
func _feedback(text: String, sfx: AudioStream, color: Color = GameMenu.C_GOLD_LIGHT) -> void:
	_toast.text = text
	_toast.add_theme_color_override(&"font_color", color)
	_toast.modulate.a = 1.0
	_toast_t = TOAST_SEC
	if sfx:
		AudioDirector.play_sfx(sfx, -6.0)
	_refresh_states()
	_update_info()


func _caster() -> SpellCaster:
	return _player.get_caster()


# --- Trucos ---


## Compra todas las mejoras hasta su nivel máximo (pagando el maná justo, por GameState, así
## pasan todas sus consecuencias: elementos, familiares, telequinesis, bolsa, Santuario...),
## descubre todas las combinaciones y pone todos los hechizos a nivel 11 (la Ascensión).
func buy_everything() -> void:
	var prog: Progression = GameState.progression
	# Sin tutorial ni casucha: se pasa directamente a jugar con todo.
	if _hut and not _hut.is_open:
		_hut.set_open()
		(get_parent() as Hud).set_intro(false)
	var hud: Hud = get_parent() as Hud
	if hud and hud.tutorial:
		hud.tutorial.skip()
	for r: SpellRecipe in SpellCaster.RECIPES:
		prog.discover_recipe(r.id)
	for r: SpellRecipe in StaffCombos.triples():
		prog.discover_recipe(r.id)
	# Mejoras que piden el Pilón a cierta altura (el Báculo): sube hasta ahí.
	for node: UpgradeNode in GameState.UPGRADES:
		for req: StringName in node.prerequisites:
			if String(req).begins_with("pylon:"):
				var need: int = ceili(float(String(req).get_slice(":", 1)) * prog.total_essence)
				prog.pylon_progress = maxi(prog.pylon_progress, need)
	# Un solo guardado al final (no uno por nivel comprado).
	var saving: bool = SaveSystem.enabled
	SaveSystem.enabled = false
	var bought: int = 0
	var progress: bool = true
	# También la página del Núcleo (con Lágrimas) y la Gran Convergencia aunque aún no se vea.
	prog.reveal_all = true
	while progress:
		progress = false
		for node: UpgradeNode in GameState.UPGRADES:
			while prog.purchase_block(node) in [&"mana", &"tears", &""]:
				var cost: int = node.cost_for_level(prog.get_level(node.id))
				var tears: bool = node.pays_with_tears()
				prog.tears += cost if tears else 0
				prog.mana += 0 if tears else cost
				if not GameState.buy_upgrade(node):
					prog.tears -= cost if tears else 0
					prog.mana -= 0 if tears else cost
					break
				bought += 1
				progress = true
	prog.reveal_all = false
	# Y las runas de la Mesa de Runas (con sus ranuras).
	if _main:
		_main.debug_runes({})
	SaveSystem.enabled = saving
	SaveSystem.save_game()
	if _player:
		_caster().set_debug_level(MAX_LEVEL, true)
	Events.mana_changed.emit(prog.mana)
	GameState.emit_all()
	var msg: String = tr("¡TODO COMPRADO! (%d NIVELES) · HECHIZOS A NIVEL %d") % [bought, MAX_LEVEL]
	_feedback(msg, BIG_SFX)
	AudioDirector.play_sfx(BUY_SFX, -4.0)


## Maná para gastar (no llena el Pilón).
func _add_mana(amount: int) -> void:
	GameState.progression.mana += amount
	Events.mana_changed.emit(GameState.progression.mana)
	_feedback(tr("+%s MANÁ") % Hud.format_int(amount), MANA_SFX)


## Lágrimas del Núcleo para probar la página del Núcleo.
func _add_tears() -> void:
	GameState.progression.tears += 3
	GameState.progression.tears_total += 3
	Events.tears_changed.emit(GameState.progression.tears)
	_feedback(tr("+3 LÁGRIMAS DEL NÚCLEO"), MANA_SFX)


func _fill_bag() -> void:
	var prog: Progression = GameState.progression
	var cap: int = GameState.bag_capacity()
	var guard: int = 0
	while prog.bag_count() < cap and guard < 1000:
		prog.collect_shard(ShardPool.SHARD.id, cap)
		guard += 1
	Events.bag_changed.emit(prog.bag_count(), cap)
	_feedback(tr("BOLSA LLENA (%d)") % cap, PICKUP_SFX)


func _empty_bag() -> void:
	GameState.progression.bag.clear()
	Events.bag_changed.emit(0, GameState.bag_capacity())
	_feedback(tr("BOLSA VACÍA"), TICK_SFX)


## Todos los hechizos a nivel `level` (1..11); 0 vuelve a los niveles comprados.
func _set_spell_level(level: int) -> void:
	if _player == null:
		return
	_caster().set_debug_level(level, true)
	var msg: String = (
		tr("HECHIZOS A NIVEL %d") % level if level > 0 else tr("HECHIZOS: NIVELES COMPRADOS")
	)
	_feedback(msg, TICK_SFX)


## Pilón a `ratio`; si sube, celebra la marca más alta que cruza (columna de luz y coro).
func _set_pylon(ratio: float) -> void:
	if _main == null:
		return
	var before: float = GameState.progression.pylon_ratio()
	_main.debug_set_pylon(ratio)
	var after: float = GameState.progression.pylon_ratio()
	for i: int in range(ManaPylon.MARKS.size() - 1, -1, -1):
		if not ManaPylon.mark_reached(before, i) and ManaPylon.mark_reached(after, i):
			Events.pylon_milestone.emit(i, ManaPylon.MARKS[i])
			break
	_feedback(tr("PILÓN AL %d %%") % roundi(ratio * 100.0), MANA_SFX)


func _next_layer() -> void:
	if _main == null:
		return
	var idx: int = _main.debug_next_layer()
	_feedback(
		tr("TÚNEL HASTA: %s") % tr(GameState.LAYERS[idx].display_name).to_upper(), CRYSTAL_SFX
	)


## El final (EndingDirector): el cristal al 99 % con su momento y el mago delante del Núcleo.
func _go_to_core() -> void:
	var ending: EndingDirector = get_tree().get_first_node_in_group(&"ending_director")
	if ending == null or GameState.progression.game_complete:
		_feedback(tr("LA PARTIDA YA ESTÁ TERMINADA"), DENY_SFX)
		return
	_feedback(tr("EL NÚCLEO QUEDA EXPUESTO"), CRYSTAL_SFX)
	close()
	ending.debug_core()


## Inscribe la Gran Convergencia si hace falta y la carga y suelta sola contra el Núcleo.
func _cast_convergence() -> void:
	var ending: EndingDirector = get_tree().get_first_node_in_group(&"ending_director")
	if ending == null or GameState.progression.game_complete:
		_feedback(tr("LA PARTIDA YA ESTÁ TERMINADA"), DENY_SFX)
		return
	_feedback(tr("GRAN CONVERGENCIA"), BIG_SFX)
	close()
	ending.debug_convergence()


func _reveal_geode() -> void:
	if _main == null:
		return
	_main.debug_geode()
	_feedback(tr("GEODA ABIERTA"), REVEAL_SFX)


func _add_hours(hours: float) -> void:
	if _day_night:
		_set_time(fposmod(_day_night.time_of_day + hours / 24.0, 1.0))


## `t`: 0 medianoche, 0,5 mediodía.
func _set_time(t: float) -> void:
	if _day_night == null:
		return
	_day_night.time_of_day = t
	var minutes: int = roundi(t * 24.0 * 60.0) % (24 * 60)
	@warning_ignore("integer_division")
	_feedback(tr("HORA: %02d:%02d") % [minutes / 60, minutes % 60], TICK_SFX)


func _set_speed(speed: float) -> void:
	HitStop.base_scale = speed
	if not HitStop.is_active():
		Engine.time_scale = speed
	_feedback(tr("VELOCIDAD DEL JUEGO x%d") % roundi(speed), TICK_SFX)


func _toggle_fps() -> void:
	Settings.show_fps = not Settings.show_fps
	Settings.save_settings()
	Settings.changed.emit()
	_feedback(tr("FPS: SÍ") if Settings.show_fps else tr("FPS: NO"), TICK_SFX)


func _toggle_god() -> void:
	god_mode = not god_mode
	if _player:
		_caster().debug_no_cooldown = god_mode
	_feedback(
		tr("MODO DIOS: SIN RECARGA Y VUELO INFINITO") if god_mode else tr("MODO DIOS: NO"),
		BUY_SFX if god_mode else TICK_SFX
	)


## Mesa de Runas abierta, todas las runas al máximo, las tres ranuras y tres runas inscritas.
func _unlock_runes() -> void:
	if _main == null:
		return
	_main.debug_runes({})
	var n: int = RuneBook.used_slots(GameState.progression)
	_feedback(tr("¡RUNAS AL MÁXIMO! %d INSCRITAS") % n, BIG_SFX)


## Cinco bichos delante del mago (critters/), con su ¡boing!.
func _spawn_critters() -> void:
	var herd: CritterHerd = CritterHerd.instance()
	var n: int = herd.spawn_in_front(5) if herd else 0
	_feedback(tr("¡%d BICHOS!") % n, PICKUP_SFX if n > 0 else DENY_SFX)


## Teletransporte delante del Santuario, del Pilón o del cristal, mirándolo.
func _warp(where: StringName) -> void:
	if _main == null:
		return
	var target: Vector3 = Vector3(0.0, 14.0, 0.0)
	var at: Vector3 = Vector3(0.0, 0.0, WorldLayout.CRYSTAL_FOOTPRINT + 12.0)
	var name_key: String = "CRISTAL"
	if where == &"sanctum" or where == &"pylon":
		var spot: Vector3 = WorldLayout.SANCTUM if where == &"sanctum" else WorldLayout.PYLON
		var toward_crystal: Vector3 = Vector3(-spot.x, 0.0, -spot.z).normalized()
		at = spot + toward_crystal * 7.0 + Vector3(0.0, 0.0, 3.0)
		target = spot + Vector3.UP * 1.6
		name_key = "SANTUARIO" if where == &"sanctum" else "PILÓN"
	at.y = Valley.ground_height(at.x, at.z) + 0.2
	_main.debug_teleport(at, target)
	_feedback(tr("TELETRANSPORTE: %s") % tr(name_key), WARP_SFX)


## El rango siguiente con su ceremonia (se cierra el menú para verla).
func _rank_up() -> void:
	if _main == null or GameState.progression.rank >= WizardRanks.last():
		_feedback(tr("NO HAY RANGO MÁS ALTO"), TICK_SFX)
		return
	close()
	_main.debug_set_rank(GameState.progression.rank + 1, true)


func _save_now() -> void:
	if SaveSystem.save_game():
		_feedback(tr("PARTIDA GUARDADA"), BUY_SFX)
	else:
		_feedback(tr("NO SE GUARDA EN MODO DEMO"), DENY_SFX, C_RED)


## Partida nueva: hay que pulsar dos veces (la segunda en menos de RESET_CONFIRM_SEC).
func _reset_game() -> void:
	if _reset_armed <= 0.0:
		_reset_armed = RESET_CONFIRM_SEC
		_reset_button.text = tr("¿SEGURO?")
		_feedback(tr("PULSA OTRA VEZ PARA BORRAR LA PARTIDA"), DENY_SFX, C_RED)
		return
	var hud: Hud = get_parent() as Hud
	_open = false
	god_mode = false
	HitStop.base_scale = 1.0
	Engine.time_scale = 1.0
	if hud and hud.menu:
		hud.menu.new_game()
