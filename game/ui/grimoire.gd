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
## Posición de cada estrella en la página izquierda (mismo orden que GameState.UPGRADES).
const STAR_POS: Array[Vector2i] = [
	Vector2i(48, 84), Vector2i(120, 58), Vector2i(194, 102), Vector2i(150, 176), Vector2i(58, 186)
]
## Trazos de la constelación (índices de estrellas).
const LINES: Array[Vector2i] = [
	Vector2i(0, 1), Vector2i(1, 2), Vector2i(2, 3), Vector2i(3, 4), Vector2i(4, 0)
]

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
const MANA_ICON: PackedStringArray = [
	"...#....", "..###...", "..###...", ".##+##..", ".#+####.", ".#+####.", "..####..", "........"
]

var is_open: bool = false

var _at_sanctum: bool = false
var _selected: int = 0
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
var _flash_t: PackedFloat32Array = PackedFloat32Array([0, 0, 0, 0, 0])
var _shown_mana: float = 0.0
## Partículas 2D propias (píxeles dorados al inscribir): pos, vel, vida.
var _parts_pos: PackedVector2Array = PackedVector2Array()
var _parts_vel: PackedVector2Array = PackedVector2Array()
var _parts_life: PackedFloat32Array = PackedFloat32Array()
var _parts_col: PackedColorArray = PackedColorArray()


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
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
	_title = _label("GRIMORIO DE CONSTELACIONES", 8, C_GOLD_LIGHT, Rect2(80, 48, 236, 10), 1)
	for i: int in GameState.UPGRADES.size():
		var p: Vector2i = STAR_POS[i] + LEFT_PAGE.position
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
	_footer = _label(
		"W/S ELEGIR  ·  CLIC O ESPACIO: INSCRIBIR  ·  TAB / ESC CERRAR",
		8,
		C_CYAN,
		Rect2(70, 330, 500, 10),
		1
	)
	Events.grimoire_requested.connect(open)
	Events.mana_changed.connect(func(_m: int) -> void: _refresh())
	set_process(false)


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
			_select(hover)
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		var mb: InputEventMouseButton = event
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		var star: int = _star_at(mb.position)
		if star >= 0:
			_select(star)
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
		_select(wrapi(_selected - 1, 0, GameState.UPGRADES.size()))
	elif event.is_action_pressed(&"ui_down") or event.is_action_pressed(&"move_back"):
		_select(wrapi(_selected + 1, 0, GameState.UPGRADES.size()))
	elif event.is_action_pressed(&"ui_accept"):
		try_buy()
	else:
		return
	get_viewport().set_input_as_handled()


func _select(i: int) -> void:
	_selected = i
	_write_t = 0.0
	_write_speed = 5.0
	AudioDirector.play_sfx(TICK_SFX, -6.0)
	_refresh()


func try_buy() -> void:
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
	var star: Vector2 = Vector2(STAR_POS[_selected] + LEFT_PAGE.position)
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
	for i: int in GameState.UPGRADES.size():
		var n: UpgradeNode = GameState.UPGRADES[i]
		var lvl: int = prog.get_level(n.id)
		var label: Label = _star_labels[i]
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
		for n: UpgradeNode in GameState.UPGRADES:
			if n.id == req:
				names.append(tr(n.display_name).to_upper())
	return ", ".join(names)


func _star_at(p: Vector2) -> int:
	var local: Vector2 = p - _ofs()
	for i: int in STAR_POS.size():
		if local.distance_to(Vector2(STAR_POS[i] + LEFT_PAGE.position)) < 14.0:
			return i
	return -1


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
	var page := Rect2(Vector2(LEFT_PAGE.position) + o, Vector2(LEFT_PAGE.size))
	draw_rect(page, C_SKY)
	# Franja más profunda abajo, separada con tramado de 1 px.
	var deep_y: float = page.position.y + 200.0
	draw_rect(Rect2(page.position.x, deep_y, page.size.x, page.end.y - deep_y), C_SKY_DEEP)
	for x: int in range(0, int(page.size.x), 2):
		draw_rect(Rect2(page.position.x + x + 0.0, deep_y - 1.0, 1, 1), C_SKY_DEEP)
	# Polvo de estrellas que titila.
	var step: float = floor(_t * 6.0)
	for d: Vector3 in _dust:
		var on: bool = fmod(d.z * 13.0 + step * 0.37, 1.0) > 0.25
		if on:
			draw_rect(Rect2(page.position + Vector2(d.x, d.y), Vector2(1, 1)), Color(C_CYAN, 0.75))
	# Trazos de la constelación: punteados; dorados entre estrellas ya despiertas.
	var prog: Progression = GameState.progression
	for l: Vector2i in LINES:
		var a := Vector2(STAR_POS[l.x] + LEFT_PAGE.position) + o
		var b := Vector2(STAR_POS[l.y] + LEFT_PAGE.position) + o
		var lit: bool = (
			prog.get_level(GameState.UPGRADES[l.x].id) > 0
			and prog.get_level(GameState.UPGRADES[l.y].id) > 0
		)
		var n: int = int(a.distance_to(b) / 3.0)
		for k: int in n:
			if k % 2 == 0:
				var p: Vector2 = a.lerp(b, float(k) / float(n)).round()
				draw_rect(Rect2(p, Vector2(1, 1)), C_GOLD if lit else C_LOCKED)
	for i: int in GameState.UPGRADES.size():
		_draw_star(i, Vector2(STAR_POS[i] + LEFT_PAGE.position) + o)


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
