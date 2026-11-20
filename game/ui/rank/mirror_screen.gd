class_name MirrorScreen
extends Control
## Estadísticas del Espejo del Archimago (GDD 4.3): se abre con F junto al espejo del Santuario.
## Un espejo alto con marco de oro en arco; en el cristal, el escudo y el nombre del rango, qué
## pide el siguiente con su barra, y las cifras de la partida (tiempo jugado, combinaciones,
## mejoras, hechizos, fragmentos, maná, racha, geodas, venas, bichos...), que aparecen una a
## una con un tic; el tiempo jugado sigue corriendo mientras está abierto. Un brillo cruza el
## cristal cada pocos segundos. F, Esc o Tab lo cierran.

const OPEN_SFX: AudioStream = preload("res://audio/sfx/sfx_mirror_open_01.ogg")
const CLOSE_SFX: AudioStream = preload("res://audio/sfx/sfx_mirror_close_01.ogg")
const TICK_SFX: AudioStream = preload("res://audio/sfx/sfx_ui_tick_01.ogg")
const C_SHADOW := Color("#14183a")
const C_GLASS := Color("#10163f")
const C_GLASS_LIGHT := Color("#1d2a6b")
const C_GOLD := Color("#d8a23a")
const C_GOLD_LIGHT := Color("#ffd27a")
const C_GOLD_DARK := Color("#7a4f17")
const C_TEXT := Color("#f2f6ff")
const C_SOFT := Color("#a5b4e6")
## El espejo (marco por fuera) y el cristal.
const FRAME := Rect2(170, 8, 300, 344)
const GLASS := Rect2(178, 22, 284, 322)
const ROW_Y: float = 153.0
const ROW_H: float = 12.0
const ROWS: int = 14
const BAR := Rect2(232, 130, 176, 4)
## Segundos entre una fila y la siguiente al abrir.
const ROW_SEC: float = 0.045

var is_open: bool = false

var _t: float = 0.0
var _open_t: float = 0.0
var _closing: bool = false
var _rank: int = 0
var _progress: float = 0.0
var _title: Label
var _rank_name: Label
var _motto: Label
var _next: Label
var _req: Label
var _footer: Label
var _keys: Array[Label] = []
var _vals: Array[Label] = []
var _shown_rows: int = 0
## Segundo jugado que enseña la primera fila (sólo se reescribe al cambiar).
var _shown_sec: int = -1


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var cx: float = GLASS.position.x
	var w: float = GLASS.size.x
	_title = _label(UiFonts.TITLE, UiFonts.HEAD, C_GOLD_LIGHT, Rect2(cx, 26, w, 14), 1)
	_rank_name = _label(UiFonts.TITLE, UiFonts.HEAD, C_TEXT, Rect2(cx, 86, w, 14), 1)
	_motto = _label(UiFonts.BODY, UiFonts.SMALL, C_SOFT, Rect2(cx, 100, w, UiFonts.LINE), 1)
	_next = _label(UiFonts.BOLD, UiFonts.SMALL, C_TEXT, Rect2(cx, 115, w, UiFonts.LINE), 1)
	_req = _label(UiFonts.BODY, UiFonts.SMALL, C_SOFT, Rect2(cx, 137, w, UiFonts.LINE), 1)
	for i: int in ROWS:
		var y: float = ROW_Y + i * ROW_H
		_keys.append(_label(UiFonts.BOLD, UiFonts.SMALL, C_SOFT, Rect2(196, y, 160, 12), 0))
		_vals.append(_label(UiFonts.BOLD, UiFonts.SMALL, C_TEXT, Rect2(300, y, 144, 12), 2))
	_footer = _label(UiFonts.BOLD, UiFonts.SMALL, C_GOLD_LIGHT, Rect2(cx, 326, w, 12), 1)
	Events.mirror_requested.connect(open)
	Events.locale_changed.connect(
		func() -> void:
			if is_open:
				_refresh()
	)
	set_process(false)


func _label(font: Font, size_px: int, col: Color, r: Rect2, align: int) -> Label:
	var l := Label.new()
	l.add_theme_font_override(&"font", font)
	l.add_theme_font_size_override(&"font_size", size_px)
	l.add_theme_color_override(&"font_color", col)
	l.horizontal_alignment = align as HorizontalAlignment
	l.position = r.position
	l.size = r.size
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiFonts.outline(l, C_SHADOW)
	add_child(l)
	return l


func open() -> void:
	if is_open:
		return
	is_open = true
	_closing = false
	visible = true
	_open_t = 0.0
	_t = 0.0
	_shown_rows = 0
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	AudioDirector.play_sfx(OPEN_SFX, -3.0)
	# Otro libro para el mago: bloquea manos y movimiento (la guía sabe que no es el Grimorio).
	Events.grimoire_opened.emit()
	_refresh()
	set_process(true)


func close() -> void:
	if not is_open or _closing:
		return
	_closing = true
	AudioDirector.play_sfx(CLOSE_SFX, -5.0)


## Rellena todas las cifras (al abrir y al cambiar de idioma).
func _refresh() -> void:
	var prog: Progression = GameState.progression
	_rank = prog.rank
	var def: RankDef = WizardRanks.def_of(_rank)
	_title.text = tr("ESPEJO DEL ARCHIMAGO")
	_rank_name.text = tr(def.display_name).to_upper()
	_rank_name.add_theme_color_override(&"font_color", def.color_light)
	_motto.text = tr(def.motto)
	_progress = WizardRanks.progress_to(_rank, prog)
	if _rank >= WizardRanks.last():
		_next.text = tr("NO HAY RANGO MÁS ALTO")
		_req.text = ""
	else:
		var nd: RankDef = WizardRanks.def_of(_rank + 1)
		_next.text = tr("SIGUIENTE: %s") % tr(nd.display_name).to_upper()
		_next.add_theme_color_override(&"font_color", nd.color)
		_req.text = requirement_text(nd)
	var found: int = 0
	var all: Array[SpellRecipe] = SpellCaster.RECIPES.duplicate()
	all.append_array(StaffCombos.triples())  # parejas y triples del báculo, como el HUD
	for r: SpellRecipe in all:
		if prog.discovered_recipes.has(r.id):
			found += 1
	var max_levels: int = 0
	for node: UpgradeNode in GameState.UPGRADES:
		max_levels += node.get_max_level()
	var destroyed: float = GameState.destroyed_ratio()
	# i18n
	var rows: Array[Array] = [
		[tr("TIEMPO JUGADO"), time_text(prog.stats.play_time)],
		[tr("COMBINACIONES"), "%d / %d" % [found, all.size()]],
		[tr("MEJORAS COMPRADAS"), "%d / %d" % [GameState.total_upgrade_levels(), max_levels]],
		[tr("HECHIZOS LANZADOS"), Hud.format_int(prog.stats.tally(GameState.STAT_SPELLS))],
		[tr("FRAGMENTOS RECOGIDOS"), Hud.format_int(prog.stats.tally(GameState.STAT_SHARDS))],
		[tr("MANÁ GANADO"), Hud.format_int(prog.stats.tally(GameState.STAT_MANA))],
		[tr("MEJOR RACHA"), "x%d" % prog.stats.tally(GameState.STAT_STREAK)],
		[tr("GOLPES RESONANTES"), Hud.format_int(prog.stats.tally(GameState.STAT_RESONANT))],
		[tr("GEODAS ROTAS"), Hud.format_int(prog.stats.tally(GameState.STAT_GEODES))],
		[tr("VENAS GOLPEADAS"), Hud.format_int(prog.stats.tally(GameState.STAT_VEINS))],
		[tr("BICHOS REVENTADOS"), Hud.format_int(prog.critters_popped)],
		[tr("CAPA MÁS PROFUNDA"), tr(GameState.current_layer().display_name).to_upper()],
		[tr("CRISTAL DESTRUIDO"), percent_text(destroyed)],
		[tr("PILÓN DE MANÁ"), percent_text(prog.pylon_ratio())],
	]
	_shown_sec = floori(prog.stats.play_time)
	for i: int in ROWS:
		_keys[i].text = rows[i][0]
		_vals[i].text = rows[i][1]
		_keys[i].visible = i < _shown_rows
		_vals[i].visible = i < _shown_rows
	_footer.text = tr("F / ESC CERRAR")
	queue_redraw()


## Qué pide el rango `def`: "Despierta la Tierra (Pilón 9 %)  ·  o Pilón 12 %".
func requirement_text(def: RankDef) -> String:
	var txt: String = tr(def.requirement) if def.requirement != "" else ""
	if def.key_upgrade != &"" and def.key_pylon > 0.0:
		txt += " " + tr("(Pilón %s)") % percent_text(def.key_pylon)
	if def.pylon_alone <= 1.0:
		txt += "  ·  " + tr("o Pilón %s") % percent_text(def.pylon_alone)
	return txt


## 3723 s -> "1 h 02 min"; 95 s -> "1 min 35 s".
static func time_text(sec: float) -> String:
	var s: int = floori(sec)
	if s >= 3600:
		return "%d h %02d min" % [s / 3600, (s % 3600) / 60]
	return "%d min %02d s" % [s / 60, s % 60]


## 0.0008 -> "0,08 %"; 0.123 -> "12,3 %"; 0.5 -> "50 %".
static func percent_text(ratio: float) -> String:
	var pct: float = ratio * 100.0
	var decimals: int = 2 if pct < 1.0 else (1 if pct < 10.0 else 0)
	var txt: String = String.num(pct, decimals)
	if txt.contains("."):
		txt = txt.rstrip("0").rstrip(".")
	return txt.replace(".", ",") + " %"


func _unhandled_input(event: InputEvent) -> void:
	if not is_open:
		return
	if (
		event.is_action_pressed(&"interact")
		or event.is_action_pressed(&"ui_cancel")
		or event.is_action_pressed(&"open_grimoire")
	):
		close()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"open_spellbook"):
		# El Libro de Hechizos no se abre encima del espejo.
		get_viewport().set_input_as_handled()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		accept_event()


func _process(delta: float) -> void:
	_t += delta
	if _closing:
		_open_t -= delta
		if _open_t <= 0.0:
			is_open = false
			_closing = false
			visible = false
			set_process(false)
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			Events.grimoire_closed.emit()
			return
	else:
		_open_t = minf(0.3, _open_t + delta)
	var sec: int = floori(GameState.progression.stats.play_time)
	if sec != _shown_sec:
		_shown_sec = sec
		_vals[0].text = time_text(GameState.progression.stats.play_time)
	# Las cifras aparecen una a una, con un tic.
	var rows: int = clampi(floori((_t - 0.25) / ROW_SEC), 0, ROWS)
	if rows > _shown_rows and not _closing:
		for i: int in range(_shown_rows, rows):
			_keys[i].visible = true
			_vals[i].visible = true
		_shown_rows = rows
		AudioDirector.play_sfx(TICK_SFX, -16.0, 1.0 + 0.04 * rows)
	var a: float = clampf(_open_t / 0.25, 0.0, 1.0)
	for c: Node in get_children():
		if c is Label:
			(c as Label).modulate.a = a
	position.y = roundf((1.0 - a) * (1.0 - a) * 24.0)
	queue_redraw()


func _draw() -> void:
	var a: float = clampf(_open_t / 0.25, 0.0, 1.0)
	draw_rect(Rect2(Vector2(-10, -40), Vector2(660, 440)), Color(C_SHADOW, 0.6 * a))
	var def: RankDef = WizardRanks.def_of(_rank)
	_draw_frame(def)
	_draw_glass(def)
	# Escudo del rango (x2) y la barra hacia el siguiente.
	var crest := Vector2(RankCrest.SIZE * 2)
	RankCrest.draw(self, _rank, Vector2(320 - crest.x * 0.5, 44), 2)
	if _rank < WizardRanks.last():
		var nd: RankDef = WizardRanks.def_of(_rank + 1)
		draw_rect(BAR.grow(1), C_SHADOW)
		draw_rect(BAR, nd.color_dark.darkened(0.4))
		var w: float = floorf(BAR.size.x * _progress * clampf((_t - 0.2) / 0.6, 0.0, 1.0))
		if w >= 1.0:
			draw_rect(Rect2(BAR.position, Vector2(w, BAR.size.y)), nd.color)
			draw_rect(Rect2(BAR.position, Vector2(w, 1)), nd.color_light)
	# Separadores de las filas.
	for i: int in mini(_shown_rows, ROWS):
		var y: float = ROW_Y + i * ROW_H + ROW_H - 1
		draw_rect(Rect2(196, y, 248, 1), Color(C_GLASS_LIGHT, 0.8))


## Marco de oro con arco (escalones de píxel) y una gema del color del rango arriba.
func _draw_frame(def: RankDef) -> void:
	var f: Rect2 = FRAME
	draw_rect(Rect2(f.position + Vector2(0, 14), f.size - Vector2(0, 14)).grow(2), C_SHADOW)
	_arch(f, 2.0, C_SHADOW)
	_arch(f, 0.0, C_GOLD_DARK)
	_arch(f.grow(-2), 0.0, C_GOLD)
	_arch(f.grow(-4), 0.0, C_GOLD_LIGHT)
	_arch(f.grow(-6), 0.0, C_GOLD_DARK)
	# Gema arriba y volutas a los lados.
	var top := Vector2(320, f.position.y + 2)
	draw_rect(Rect2(top + Vector2(-5, -3), Vector2(10, 9)), C_SHADOW)
	draw_rect(Rect2(top + Vector2(-4, -2), Vector2(8, 7)), def.color)
	draw_rect(Rect2(top + Vector2(-3, -1), Vector2(3, 2)), def.color_light)
	for side: int in 2:
		var x: float = f.position.x - 4 if side == 0 else f.end.x
		for k: int in 3:
			var y: float = f.position.y + 60 + k * 100
			draw_rect(Rect2(x, y, 4, 14), C_SHADOW)
			draw_rect(Rect2(x + 1, y + 1, 2, 12), C_GOLD)


## Rectángulo con la parte de arriba en arco de medio punto, hecho con franjas de píxel.
func _arch(r: Rect2, grow: float, col: Color) -> void:
	var g: Rect2 = r.grow(grow)
	var radius: float = g.size.x * 0.5
	var arch_h: float = 30.0 + grow
	draw_rect(Rect2(g.position + Vector2(0, arch_h), g.size - Vector2(0, arch_h)), col)
	var cx: float = g.position.x + radius
	for y: int in int(arch_h):
		var k: float = 1.0 - float(y) / arch_h
		var half: float = floorf(radius * sqrt(maxf(0.0, 1.0 - k * k)))
		draw_rect(Rect2(cx - half, g.position.y + y, half * 2.0, 1), col)


## Cristal oscuro con estrellas tramadas, el color del rango abajo y un brillo que lo cruza.
func _draw_glass(def: RankDef) -> void:
	var g: Rect2 = GLASS
	_arch(g, 0.0, C_GLASS)
	# Degradado del rango desde abajo, en bandas de 4 px.
	for k: int in 12:
		var y: float = g.end.y - (k + 1) * 8
		draw_rect(
			Rect2(g.position.x, y, g.size.x, 8), Color(def.color_dark, 0.35 * (1.0 - k / 12.0))
		)
	# Estrellas que titilan a saltos.
	var step: int = floori(_t * 6.0)
	for i: int in 40:
		var h: int = (i * 7919 + 104729) % 9973
		var p := Vector2(g.position.x + 6 + (h % 271), g.position.y + 34 + (h / 271) % 280)
		var on: bool = ((h + step * (i % 3 + 1)) % 7) != 0
		if on:
			draw_rect(Rect2(p, Vector2.ONE), Color(C_SOFT, 0.35 + 0.3 * float(i % 3) / 2.0))
	# Brillo diagonal que cruza el cristal cada 4 s.
	var sweep: float = fmod(_t, 4.0) / 1.2
	if sweep < 1.0:
		var x0: float = g.position.x - 60.0 + sweep * (g.size.x + 120.0)
		for y: int in range(int(g.position.y) + 32, int(g.end.y), 2):
			var x: float = x0 + (y - g.position.y) * 0.35
			if x > g.position.x and x + 6.0 < g.end.x:
				draw_rect(Rect2(roundf(x), y, 6, 2), Color(1, 1, 1, 0.06))
