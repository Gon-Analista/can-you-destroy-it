class_name Grimoire
extends Control
## El Grimorio de Constelaciones (GDD 4.3 y 7): un libro que se abre a pantalla. A la izquierda,
## un cielo nocturno donde cada mejora es una estrella de la constelación (más grande y brillante
## con cada nivel; dorada y latiendo si se puede comprar). A la derecha, la página de pergamino de
## la estrella elegida, que se escribe sola: qué hace, cómo está ahora y cómo quedará, el coste y
## el botón INSCRIBIR. Se compra sólo junto al atril del Santuario; con Tab se puede consultar en
## cualquier sitio.
## Todo se dibuja a píxel entero con las fuentes pixel del HUD.

const FONT_SMALL: FontFile = preload("res://ui/fonts/silkscreen_regular.woff2")
const FONT_BOLD: FontFile = preload("res://ui/fonts/pixelify_sans_bold.woff2")
const OPEN_SFX: AudioStream = preload("res://audio/sfx/sfx_book_open_01.ogg")
const CLOSE_SFX: AudioStream = preload("res://audio/sfx/sfx_book_close_01.ogg")
const TICK_SFX: AudioStream = preload("res://audio/sfx/sfx_ui_tick_01.ogg")
const DENY_SFX: AudioStream = preload("res://audio/sfx/sfx_ui_deny_01.ogg")
const BUY_SFX: AudioStream = preload("res://audio/sfx/sfx_upgrade_buy_01.ogg")

const BOOK := Rect2i(70, 34, 500, 292)
const LEFT_PAGE := Rect2i(80, 42, 236, 276)
const RIGHT_PAGE := Rect2i(324, 42, 236, 276)
## Páginas del Grimorio: una constelación por elemento (y la del Mago, con lo general).
## [id del elemento ("" = Mago), nombre, color del título, cielo, cielo profundo, se abre con
## el Pilón al...].
# i18n
const PAGES: Array[Array] = [
	[&"", "MAGO", "#ffd27a", "#1b2a6b", "#141c4d", 0.0],
	[&"spark", "CHISPA", "#ff9a3a", "#3a1840", "#26102e", 0.0],
	[&"frost", "ESCARCHA", "#a5dae5", "#14305a", "#0d2042", 0.1],
	[&"bolt", "RAYO", "#ffe66b", "#2a2450", "#1b1838", 0.25],
	[&"earth", "TIERRA", "#c9a26b", "#2e2a24", "#1f1c18", 0.5],
	[&"arcane", "ARCANO", "#c79bff", "#24164a", "#170e33", 0.75],
]
# i18n
const PAGE_TITLES: PackedStringArray = [
	"CONSTELACIÓN DEL MAGO",
	"CONSTELACIÓN DE LA CHISPA",
	"CONSTELACIÓN DE LA ESCARCHA",
	"CONSTELACIÓN DEL RAYO",
	"CONSTELACIÓN DE LA TIERRA",
	"CONSTELACIÓN DEL ARCANO",
]
const TAB_W: int = 36

const C_INK := Color("#2a1d4a")
const C_INK_SOFT := Color("#6a5a86")
const C_PAGE := Color("#f1e8d8")
const C_PAGE_SHADE := Color("#e0d2bb")
const C_PAGE_EDGE := Color("#c9b693")
const C_SKY := Color("#1b2a6b")
const C_SKY_DEEP := Color("#141c4d")
const C_COVER := Color("#3b2a7a")
const C_COVER_DARK := Color("#24184f")
const C_GOLD := Color("#d8a23a")
const C_GOLD_LIGHT := Color("#ffd27a")
const C_CYAN := Color("#c9f6ff")
const C_DIM := Color("#8a95c9")
const C_LOCKED := Color("#4a4f80")
const C_PINK := Color("#ff7ad9")
const C_RED := Color("#c8423a")
const C_SHADOW := Color("#14183a")

## Iconos de cada rama (8x8): '#' color, '+' brillo, '.' vacío.
const ICONS: Dictionary[StringName, PackedStringArray] = {
	&"bag":
	[
		"..##.#..",
		".#..#...",
		"..####..",
		".######.",
		"##+#####",
		"#+######",
		"########",
		".######."
	],
	&"spark_power":
	[
		"...#....",
		"...##...",
		"..###.#.",
		".#####..",
		".##+###.",
		"##+++###",
		"##+++##.",
		".#####.."
	],
	&"channeling":
	[
		"########",
		".#++++#.",
		"..#++#..",
		"...##...",
		"...##...",
		"..#..#..",
		".#.++.#.",
		"########"
	],
	&"resonance":
	[
		"...##...",
		"...##...",
		"..#++#..",
		"########",
		".##++##.",
		"..####..",
		".##..##.",
		"##....##"
	],
	&"fireball_power":
	[
		"..#..#..",
		".#.##.#.",
		"..####..",
		".##++##.",
		"#+++++##",
		"#+++++##",
		".##+###.",
		"..####.."
	],
	&"telekinesis":
	[
		".######.",
		"#......#",
		"#.####.#",
		"#.#..#.#",
		"#.#.+#.#",
		"#.#....#",
		"#.######",
		"#......."
	],
}
const PAGE_ICONS: Array[PackedStringArray] = [
	[
		"...#....",
		"..###...",
		".#####..",
		"########",
		"...#....",
		"..###...",
		".#...#..",
		"#.....#."
	],
	[
		"...#....",
		"...##...",
		"..###.#.",
		".#####..",
		".##+###.",
		"##+++###",
		"##+++##.",
		".#####.."
	],
	[
		"#..#..#.",
		".#.#.#..",
		"..###...",
		"#######.",
		"..###...",
		".#.#.#..",
		"#..#..#.",
		"........"
	],
	[
		"....##..",
		"...##...",
		"..##....",
		".######.",
		"....##..",
		"...##...",
		"..##....",
		".##....."
	],
	[
		"........",
		"..####..",
		".##++##.",
		"###++###",
		"########",
		".######.",
		"..####..",
		"........"
	],
	[
		"..####..",
		".#....#.",
		"#..##..#",
		"#.#++#.#",
		"#..##..#",
		".#....#.",
		"..####..",
		"........"
	],
]
const LOCK_ICON: PackedStringArray = [
	"..###...", ".#...#..", ".#...#..", "#######.", "##+++##.", "###+###.", "#######.", "........"
]
const MANA_ICON: PackedStringArray = [
	"...#....", "..###...", "..###...", ".##+##..", ".#+####.", ".#+####.", "..####..", "........"
]

var is_open: bool = false

var _at_sanctum: bool = false
var _selected: int = 0
var _page: int = 0
var _open_t: float = 0.0
var _closing: bool = false
var _t: float = 0.0
var _dust: PackedVector3Array = PackedVector3Array()
var _content: Control
var _title: Label
var _page_title: Label
var _level: Label
var _desc: Label
var _now: Label
var _next: Label
var _cost: Label
var _button: Label
var _footer: Label
var _mana: Label
var _star_labels: Array[Label] = []
var _write_t: float = 1.0
var _write_speed: float = 4.0
var _deny_t: float = 0.0
var _flash_t: PackedFloat32Array = PackedFloat32Array()
var _shown_mana: float = 0.0
## Partículas 2D propias (píxeles dorados al inscribir): pos, vel, vida.
var _parts_pos: PackedVector2Array = PackedVector2Array()
var _parts_vel: PackedVector2Array = PackedVector2Array()
var _parts_life: PackedFloat32Array = PackedFloat32Array()
var _parts_col: PackedColorArray = PackedColorArray()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	_flash_t.resize(GameState.UPGRADES.size())
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	for i: int in 70:
		_dust.append(
			Vector3(rng.randi_range(4, LEFT_PAGE.size.x - 4), rng.randi_range(18, 260), rng.randf())
		)
	_content = Control.new()
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.size = Vector2(640, 360)
	add_child(_content)
	_title = _label("", 8, C_GOLD_LIGHT, Rect2(80, 64, 236, 10), 1)
	for i: int in GameState.UPGRADES.size():
		var p: Vector2i = GameState.UPGRADES[i].star_pos + LEFT_PAGE.position
		_star_labels.append(_label("", 8, C_DIM, Rect2(p.x - 50, p.y + 12, 100, 10), 1))
	var rx: int = RIGHT_PAGE.position.x
	var ry: int = RIGHT_PAGE.position.y
	_page_title = _label("", 16, C_INK, Rect2(rx + 46, ry + 10, 180, 20), 0, true)
	_level = _label("", 8, C_INK_SOFT, Rect2(rx + 46, ry + 30, 180, 10), 0)
	_desc = _label("", 8, C_INK, Rect2(rx + 12, ry + 64, 212, 50), 0)
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_now = _label("", 8, C_INK_SOFT, Rect2(rx + 12, ry + 124, 212, 10), 0)
	_next = _label("", 8, Color("#7a3fae"), Rect2(rx + 12, ry + 138, 212, 10), 0)
	_cost = _label("", 16, C_INK, Rect2(rx + 36, ry + 176, 160, 20), 0, true)
	_button = _label("", 8, C_INK, Rect2(rx + 18, ry + 214, 200, 10), 1)
	_mana = _label("", 8, C_GOLD_LIGHT, Rect2(rx + 120, ry - 2 - 10 + 2, 112, 10), 2)
	_footer = _label(_footer_text(), 8, C_CYAN, Rect2(70, 330, 500, 10), 1)
	Events.grimoire_requested.connect(open)
	Events.mana_changed.connect(func(_m: int) -> void: _refresh())
	Events.locale_changed.connect(func() -> void: _footer.text = _footer_text())
	set_process(false)


func _footer_text() -> String:
	return tr("Q/E ELEMENTO  ·  W/S ESTRELLA  ·  CLIC O ESPACIO: INSCRIBIR  ·  TAB / ESC CERRAR")


func open(at_sanctum: bool) -> void:
	if is_open and not _closing:
		_at_sanctum = at_sanctum or _at_sanctum
		_refresh()
		return
	is_open = true
	_closing = false
	_at_sanctum = at_sanctum
	visible = true
	_open_t = 0.0
	_shown_mana = GameState.progression.mana
	# Abre por la mejora más barata que se pueda comprar (o la primera sin completar).
	var best: UpgradeNode = GameState.cheapest_affordable()
	if best:
		_selected = GameState.UPGRADES.find(best)
	_page = _page_of(GameState.UPGRADES[_selected])
	_write_t = 0.0
	_write_speed = 2.5
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	AudioDirector.play_sfx(OPEN_SFX, -4.0)
	Events.grimoire_opened.emit()
	_refresh()
	set_process(true)


func close() -> void:
	if not is_open or _closing:
		return
	_closing = true
	AudioDirector.play_sfx(CLOSE_SFX, -6.0)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var hover: int = _star_at((event as InputEventMouseMotion).position)
		if hover >= 0 and hover != _selected:
			select(hover)
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		var mb: InputEventMouseButton = event
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		var tab: int = _tab_at(mb.position)
		var star: int = _star_at(mb.position)
		if tab >= 0:
			open_page(tab)
		elif star >= 0:
			select(star)
		elif _button_rect().has_point(mb.position - _ofs()):
			try_buy()
		accept_event()


func _unhandled_input(event: InputEvent) -> void:
	if not is_open:
		if event.is_action_pressed(&"open_grimoire"):
			var sanctum: Sanctum = get_tree().get_first_node_in_group(&"sanctum") as Sanctum
			open(sanctum != null and sanctum.player_in_range())
			get_viewport().set_input_as_handled()
		return
	if (
		event.is_action_pressed(&"open_grimoire")
		or event.is_action_pressed(&"ui_cancel")
		or event.is_action_pressed(&"interact")
	):
		close()
	elif event.is_action_pressed(&"ui_up") or event.is_action_pressed(&"move_forward"):
		_step_star(-1)
	elif event.is_action_pressed(&"ui_down") or event.is_action_pressed(&"move_back"):
		_step_star(1)
	elif event.is_action_pressed(&"cycle_element_left") or event.is_action_pressed(&"ui_left"):
		open_page(wrapi(_page - 1, 0, PAGES.size()))
	elif event.is_action_pressed(&"cycle_element_right") or event.is_action_pressed(&"ui_right"):
		open_page(wrapi(_page + 1, 0, PAGES.size()))
	elif event.is_action_pressed(&"ui_accept"):
		try_buy()
	else:
		return
	get_viewport().set_input_as_handled()


## Abre la constelación de un elemento (pasa la página con su aleteo).
func open_page(page: int) -> void:
	if page == _page:
		return
	_page = page
	var nodes: Array[int] = _page_nodes()
	if not nodes.is_empty():
		_selected = nodes[0]
	_write_t = 0.0
	_write_speed = 4.0
	AudioDirector.play_sfx(OPEN_SFX, -10.0, 1.25)
	_refresh()


## Índices (en GameState.UPGRADES) de las estrellas de la página abierta.
func _page_nodes() -> Array[int]:
	var out: Array[int] = []
	var el: StringName = PAGES[_page][0]
	for i: int in GameState.UPGRADES.size():
		if GameState.UPGRADES[i].element == el:
			out.append(i)
	return out


func _page_of(node: UpgradeNode) -> int:
	for i: int in PAGES.size():
		if PAGES[i][0] == node.element:
			return i
	return 0


func _page_locked() -> bool:
	return _page_nodes().is_empty()


func _step_star(dir: int) -> void:
	var nodes: Array[int] = _page_nodes()
	if nodes.is_empty():
		return
	var at: int = maxi(nodes.find(_selected), 0)
	select(nodes[wrapi(at + dir, 0, nodes.size())])


## Elige una estrella (con sonido y la página que se reescribe).
func select(i: int) -> void:
	_selected = i
	_write_t = 0.0
	_write_speed = 5.0
	AudioDirector.play_sfx(TICK_SFX, -6.0)
	_refresh()


func try_buy() -> void:
	if _page_locked():
		_deny_t = 0.35
		AudioDirector.play_sfx(DENY_SFX, -2.0)
		return
	var node: UpgradeNode = GameState.UPGRADES[_selected]
	var block: StringName = GameState.progression.purchase_block(node)
	if block != &"" or not _at_sanctum:
		_deny_t = 0.35
		AudioDirector.play_sfx(DENY_SFX, -2.0)
		return
	if not GameState.buy_upgrade(node):
		return
	AudioDirector.play_sfx(BUY_SFX, -1.0)
	_flash_t[_selected] = 1.0
	_write_t = 0.0
	_write_speed = 1.6
	var star: Vector2 = Vector2(node.star_pos + LEFT_PAGE.position)
	_burst(star, 26, [C_GOLD_LIGHT, C_PINK, C_CYAN])
	_burst(_button_rect().get_center(), 18, [C_GOLD_LIGHT, C_GOLD])
	var lvl: int = GameState.progression.get_level(node.id)
	var title: String = tr("¡%s %s!") % [tr(node.display_name).to_upper(), _roman(lvl)]
	if lvl < node.level_names.size() and node.level_names[lvl] != "":
		# Mejoras que cambian la forma del hechizo: se anuncia la forma nueva.
		title = tr("¡%s!") % tr(node.level_names[lvl]).to_upper()
	Events.hint.emit(title, C_GOLD_LIGHT)
	_refresh()


func _process(delta: float) -> void:
	_t += delta
	if _closing:
		_open_t = maxf(0.0, _open_t - delta * 6.0)
		if _open_t <= 0.0:
			is_open = false
			_closing = false
			visible = false
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			Events.grimoire_closed.emit()
			set_process(false)
			return
	else:
		_open_t = minf(1.0, _open_t + delta * 5.0)
	_write_t = minf(1.0, _write_t + delta * _write_speed)
	_desc.visible_ratio = _write_t
	_deny_t = maxf(0.0, _deny_t - delta)
	for i: int in _flash_t.size():
		_flash_t[i] = maxf(0.0, _flash_t[i] - delta * 1.5)
	var target: float = GameState.progression.mana
	_shown_mana = lerpf(_shown_mana, target, 1.0 - exp(-delta * 12.0))
	if absf(_shown_mana - target) < 0.5:
		_shown_mana = target
	_mana.text = tr("MANÁ  %s") % Hud.format_int(roundi(_shown_mana))
	_update_particles(delta)
	_content.position = _ofs()
	# El coste tiembla en rojo si no se puede inscribir.
	var shake: float = sin(_deny_t * 70.0) * 3.0 * (_deny_t / 0.35)
	_cost.position.x = RIGHT_PAGE.position.x + 36 + roundi(shake)
	queue_redraw()


## Desplazamiento del libro mientras se abre o se cierra: sube desde abajo a píxel entero.
func _ofs() -> Vector2:
	var k: float = 1.0 - pow(1.0 - _open_t, 3.0)
	return Vector2(0, roundi((1.0 - k) * 260.0))


func _refresh() -> void:
	if not is_open:
		return
	var prog: Progression = GameState.progression
	var page: Array = PAGES[_page]
	_title.text = tr(PAGE_TITLES[_page])
	_title.add_theme_color_override(&"font_color", Color(page[2] as String))
	for i: int in GameState.UPGRADES.size():
		var n: UpgradeNode = GameState.UPGRADES[i]
		var lvl: int = prog.get_level(n.id)
		var label: Label = _star_labels[i]
		label.visible = n.element == page[0]
		var block: StringName = prog.purchase_block(n)
		label.text = tr(n.display_name).to_upper() if block != &"locked" else "?"
		var c: Color = C_DIM
		if block == &"max":
			c = C_CYAN
		elif block == &"":
			c = C_GOLD_LIGHT
		elif block == &"locked":
			c = C_LOCKED
		elif lvl > 0:
			c = Color("#c79bff")
		label.add_theme_color_override(&"font_color", c)
	if _page_locked():
		_page_title.text = tr(page[1] as String)
		_level.text = tr("ELEMENTO DORMIDO")
		_desc.text = (
			tr("Su constelación aún no brilla. Despertará cuando el Pilón de Maná llegue al %d %%.")
			% roundi(float(page[5]) * 100.0)
		)
		_now.text = ""
		_next.text = ""
		_cost.text = ""
		_button.text = tr("SELLADO")
		_button.add_theme_color_override(&"font_color", C_INK_SOFT)
		return
	var node: UpgradeNode = GameState.UPGRADES[_selected]
	var level: int = prog.get_level(node.id)
	var max_level: int = node.get_max_level()
	var block_sel: StringName = prog.purchase_block(node)
	_page_title.text = tr(node.display_name).to_upper()
	_level.text = tr("NIVEL %d DE %d") % [level, max_level]
	_desc.text = tr(node.description)
	_now.text = tr("AHORA: %s") % tr(node.describe_level(level))
	if level < max_level:
		_next.text = tr("SIGUIENTE: %s") % tr(node.describe_level(level + 1))
		var cost: int = node.cost_for_level(level)
		_cost.text = Hud.format_int(cost)
		_cost.add_theme_color_override(&"font_color", C_INK if prog.can_afford(cost) else C_RED)
	else:
		_next.text = ""
		_cost.text = ""
	match block_sel:
		&"max":
			_button.text = tr("¡CONSTELACIÓN COMPLETA!")
		&"locked":
			_button.text = tr("NECESITA: %s") % _prereq_names(node)
		&"mana":
			_button.text = (
				tr("TE FALTAN %s DE MANÁ") % Hud.format_int(node.cost_for_level(level) - prog.mana)
			)
		_:
			_button.text = (
				tr("INSCRIBIR  [CLIC]") if _at_sanctum else tr("VE AL ATRIL DEL SANTUARIO")
			)
	var can_buy: bool = block_sel == &"" and _at_sanctum
	_button.add_theme_color_override(&"font_color", C_INK if can_buy else C_INK_SOFT)


func _prereq_names(node: UpgradeNode) -> String:
	var names: PackedStringArray = []
	for req: StringName in node.prerequisites:
		if String(req).begins_with("recipe:"):
			names.append(tr("DESCUBRIR LA BOLA DE FUEGO"))
		for n: UpgradeNode in GameState.UPGRADES:
			if n.id == req:
				names.append(tr(n.display_name).to_upper())
	return ", ".join(names)


func _star_at(p: Vector2) -> int:
	var local: Vector2 = p - _ofs()
	for i: int in _page_nodes():
		if local.distance_to(Vector2(GameState.UPGRADES[i].star_pos + LEFT_PAGE.position)) < 14.0:
			return i
	return -1


## Pestaña bajo el puntero (o -1).
func _tab_at(p: Vector2) -> int:
	var local: Vector2 = p - _ofs()
	for i: int in PAGES.size():
		if _tab_rect(i).has_point(local):
			return i
	return -1


func _tab_rect(i: int) -> Rect2:
	return Rect2(LEFT_PAGE.position.x + 4 + i * (TAB_W + 2), LEFT_PAGE.position.y + 2, TAB_W, 14)


func _button_rect() -> Rect2:
	return Rect2(RIGHT_PAGE.position.x + 14, RIGHT_PAGE.position.y + 208, 208, 22)


func _draw() -> void:
	var o: Vector2 = _ofs()
	# Velo sobre el valle (tramado, como el resto de transparencias pixel art).
	var veil: float = _open_t * 0.6
	draw_rect(Rect2(Vector2.ZERO, size), Color(C_SHADOW, veil))
	# Tapas de cuero con esquinas de oro.
	var book := Rect2(Vector2(BOOK.position) + o, Vector2(BOOK.size))
	draw_rect(book.grow(2), C_SHADOW)
	draw_rect(book, C_COVER_DARK)
	draw_rect(book.grow(-2), C_COVER)
	for corner: Vector2 in [
		book.position,
		book.position + Vector2(book.size.x - 10, 0),
		book.position + Vector2(0, book.size.y - 10),
		book.end - Vector2(10, 10)
	]:
		draw_rect(Rect2(corner, Vector2(10, 10)), C_GOLD)
		draw_rect(Rect2(corner + Vector2(3, 3), Vector2(4, 4)), C_GOLD_LIGHT)
	_draw_left_page(o)
	_draw_right_page(o)
	# Lomo.
	draw_rect(Rect2(Vector2(316, 40) + o, Vector2(8, 280)), C_COVER_DARK)
	draw_rect(Rect2(Vector2(319, 40) + o, Vector2(2, 280)), C_GOLD)
	for i: int in _parts_pos.size():
		if _parts_life[i] > 0.0:
			draw_rect(Rect2(_parts_pos[i].round() + o, Vector2(2, 2)), _parts_col[i])


func _draw_left_page(o: Vector2) -> void:
	var page_def: Array = PAGES[_page]
	var sky := Color(page_def[3] as String)
	var deep := Color(page_def[4] as String)
	var page := Rect2(Vector2(LEFT_PAGE.position) + o, Vector2(LEFT_PAGE.size))
	draw_rect(page, sky)
	# Franja más profunda abajo, separada con tramado de 1 px.
	var deep_y: float = page.position.y + 200.0
	draw_rect(Rect2(page.position.x, deep_y, page.size.x, page.end.y - deep_y), deep)
	for x: int in range(0, int(page.size.x), 2):
		draw_rect(Rect2(page.position.x + x + 0.0, deep_y - 1.0, 1, 1), deep)
	# Polvo de estrellas que titila.
	var step: float = floor(_t * 6.0)
	for d: Vector3 in _dust:
		var on: bool = fmod(d.z * 13.0 + step * 0.37, 1.0) > 0.25
		if on and d.y > 20.0:
			draw_rect(Rect2(page.position + Vector2(d.x, d.y), Vector2(1, 1)), Color(C_CYAN, 0.75))
	_draw_tabs(o)
	if _page_locked():
		# Elemento dormido: un sello grande en el centro.
		_draw_icon(LOCK_ICON, page.get_center() - Vector2(16, 24), 4, C_LOCKED)
		return
	# Trazos de la constelación: punteados; dorados entre estrellas ya despiertas.
	var prog: Progression = GameState.progression
	var nodes: Array[int] = _page_nodes()
	for k: int in nodes.size():
		if nodes.size() < 2 or (nodes.size() == 2 and k == 1):
			break
		var na: UpgradeNode = GameState.UPGRADES[nodes[k]]
		var nb: UpgradeNode = GameState.UPGRADES[nodes[(k + 1) % nodes.size()]]
		var a := Vector2(na.star_pos + LEFT_PAGE.position) + o
		var b := Vector2(nb.star_pos + LEFT_PAGE.position) + o
		var lit: bool = prog.get_level(na.id) > 0 and prog.get_level(nb.id) > 0
		var n: int = int(a.distance_to(b) / 3.0)
		for j: int in n:
			if j % 2 == 0:
				var p: Vector2 = a.lerp(b, float(j) / float(n)).round()
				draw_rect(Rect2(p, Vector2(1, 1)), C_GOLD if lit else C_LOCKED)
	for i: int in nodes:
		_draw_star(i, Vector2(GameState.UPGRADES[i].star_pos + LEFT_PAGE.position) + o)


## Pestañas de los elementos, arriba de la página: la abierta, unida a la página.
func _draw_tabs(o: Vector2) -> void:
	for i: int in PAGES.size():
		var r := Rect2(_tab_rect(i).position + o, _tab_rect(i).size)
		var col := Color(PAGES[i][2] as String)
		var open_tab: bool = i == _page
		var empty: bool = not _has_nodes(i)
		draw_rect(r.grow(1), C_SHADOW)
		draw_rect(r, Color(PAGES[i][3] as String) if open_tab else C_COVER_DARK)
		if open_tab:
			draw_rect(Rect2(r.position + Vector2(0, r.size.y - 2), Vector2(r.size.x, 2)), col)
		var icon: PackedStringArray = LOCK_ICON if empty else PAGE_ICONS[i]
		var ic: Color = col if not empty else C_LOCKED
		if not open_tab and not empty:
			ic = col.darkened(0.35)
		_draw_icon(icon, r.position + Vector2(r.size.x * 0.5 - 4, 3), 1, ic)


func _has_nodes(page: int) -> bool:
	for n: UpgradeNode in GameState.UPGRADES:
		if n.element == PAGES[page][0]:
			return true
	return false


func _draw_star(i: int, c: Vector2) -> void:
	var node: UpgradeNode = GameState.UPGRADES[i]
	var prog: Progression = GameState.progression
	var level: int = prog.get_level(node.id)
	var block: StringName = prog.purchase_block(node)
	var col: Color = C_DIM
	if block == &"max":
		col = C_CYAN
	elif block == &"":
		col = C_GOLD_LIGHT if fmod(_t, 0.8) < 0.5 else C_GOLD
	elif block == &"locked":
		col = C_LOCKED
	elif level > 0:
		col = Color("#c79bff")
	var r: int = 2 + level
	var flash: float = _flash_t[i]
	if flash > 0.0:
		col = col.lerp(Color.WHITE, flash)
		r += roundi(flash * 4.0)
	# Estrella de 4 puntas: cruz larga + rombo central.
	draw_rect(Rect2(c.x - r * 2, c.y, r * 4 + 1, 1), col)
	draw_rect(Rect2(c.x, c.y - r * 2, 1, r * 4 + 1), col)
	for k: int in range(-r, r + 1):
		var w: int = r - absi(k)
		draw_rect(Rect2(c.x - w, c.y + k, w * 2 + 1, 1), col)
	draw_rect(Rect2(c.x, c.y, 1, 1), Color.WHITE)
	# Anillo giratorio de la estrella elegida (8 puntos que avanzan a 8 fps).
	if i == _selected:
		var rr: float = r * 2.0 + 6.0
		var rot: float = floor(_t * 8.0) * TAU / 32.0
		for k: int in 8:
			var a: float = rot + TAU * float(k) / 8.0
			draw_rect(
				Rect2((c + Vector2(cos(a), sin(a)) * rr).round(), Vector2(2, 2)), C_GOLD_LIGHT
			)
	# Destello expansivo al inscribir.
	if flash > 0.0:
		var rr2: float = (1.0 - flash) * 28.0 + 6.0
		for k: int in 16:
			var a: float = TAU * float(k) / 16.0
			draw_rect(
				Rect2((c + Vector2(cos(a), sin(a)) * rr2).round(), Vector2(1, 1)),
				Color(C_GOLD_LIGHT, flash)
			)


func _draw_right_page(o: Vector2) -> void:
	var page := Rect2(Vector2(RIGHT_PAGE.position) + o, Vector2(RIGHT_PAGE.size))
	draw_rect(page, C_PAGE)
	draw_rect(Rect2(page.position, Vector2(4, page.size.y)), C_PAGE_SHADE)
	draw_rect(
		Rect2(page.position + Vector2(0, page.size.y - 3), Vector2(page.size.x, 3)), C_PAGE_EDGE
	)
	if _page_locked():
		var lock_at: Vector2 = page.position + Vector2(10, 8)
		draw_rect(Rect2(lock_at - Vector2(2, 2), Vector2(32, 32)), C_PAGE_EDGE)
		draw_rect(Rect2(lock_at, Vector2(28, 28)), C_COVER_DARK)
		_draw_icon(PAGE_ICONS[_page], lock_at + Vector2(2, 2), 3, Color(PAGES[_page][2] as String))
		return
	var node: UpgradeNode = GameState.UPGRADES[_selected]
	var prog: Progression = GameState.progression
	var level: int = prog.get_level(node.id)
	var max_level: int = node.get_max_level()
	# Icono de la rama en un medallón.
	var icon_at: Vector2 = page.position + Vector2(10, 8)
	draw_rect(Rect2(icon_at - Vector2(2, 2), Vector2(32, 32)), C_GOLD)
	draw_rect(Rect2(icon_at, Vector2(28, 28)), C_SKY)
	_draw_icon(ICONS.get(node.id, ICONS[&"resonance"]), icon_at + Vector2(2, 2), 3, C_GOLD_LIGHT)
	# Pips de nivel.
	for k: int in max_level:
		var p: Vector2 = page.position + Vector2(46 + k * 9, 44)
		draw_rect(Rect2(p, Vector2(7, 5)), C_INK_SOFT)
		draw_rect(Rect2(p + Vector2(1, 1), Vector2(5, 3)), C_PINK if k < level else C_PAGE)
	# Separador ornamental.
	for x: int in range(12, 224, 4):
		draw_rect(Rect2(page.position + Vector2(x, 56), Vector2(2, 1)), C_PAGE_EDGE)
	# Coste con la gota de maná.
	if level < max_level:
		var cost_at: Vector2 = page.position + Vector2(14, 178)
		_draw_icon(MANA_ICON, cost_at, 2, C_PINK)
	# Botón.
	var b := Rect2(_button_rect().position + o, _button_rect().size)
	var block: StringName = prog.purchase_block(node)
	var can_buy: bool = block == &"" and _at_sanctum
	var face: Color = C_GOLD_LIGHT if can_buy else C_PAGE_SHADE
	if can_buy and fmod(_t, 1.0) < 0.5:
		face = C_GOLD_LIGHT.lightened(0.15)
	draw_rect(b.grow(1), C_INK if can_buy else C_PAGE_EDGE)
	draw_rect(b, face)
	draw_rect(
		Rect2(b.position + Vector2(0, b.size.y - 2), Vector2(b.size.x, 2)),
		C_GOLD if can_buy else C_PAGE_EDGE
	)


func _draw_icon(rows: PackedStringArray, at: Vector2, px: int, col: Color) -> void:
	var hi: Color = col.lightened(0.5)
	for y: int in rows.size():
		var row: String = rows[y]
		for x: int in row.length():
			var ch: String = row[x]
			if ch == ".":
				continue
			draw_rect(
				Rect2(at + Vector2(x * px, y * px), Vector2(px, px)), hi if ch == "+" else col
			)


func _burst(at: Vector2, n: int, colors: Array[Color]) -> void:
	for k: int in n:
		var a: float = randf() * TAU
		_parts_pos.append(at)
		_parts_vel.append(Vector2(cos(a), sin(a)) * randf_range(40.0, 120.0) + Vector2(0, -40))
		_parts_life.append(randf_range(0.4, 0.9))
		_parts_col.append(colors[k % colors.size()])


func _update_particles(delta: float) -> void:
	var i: int = 0
	while i < _parts_pos.size():
		_parts_life[i] -= delta
		if _parts_life[i] <= 0.0:
			_parts_pos.remove_at(i)
			_parts_vel.remove_at(i)
			_parts_life.remove_at(i)
			_parts_col.remove_at(i)
			continue
		_parts_vel[i] += Vector2(0, 160.0) * delta
		_parts_pos[i] += _parts_vel[i] * delta
		i += 1


static func _roman(n: int) -> String:
	var numerals: PackedStringArray = ["", "I", "II", "III", "IV", "V", "VI", "VII", "VIII"]
	return numerals[clampi(n, 0, numerals.size() - 1)]


func _label(
	text: String, font_size: int, color: Color, r: Rect2, align: int, bold: bool = false
) -> Label:
	var l := Label.new()
	l.text = tr(text)
	l.horizontal_alignment = align as HorizontalAlignment
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override(&"font", FONT_BOLD if bold else FONT_SMALL)
	l.add_theme_font_size_override(&"font_size", font_size)
	l.add_theme_color_override(&"font_color", color)
	l.position = r.position
	l.size = r.size
	_content.add_child(l)
	return l
