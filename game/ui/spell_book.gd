class_name SpellBook
extends Control
## Libro de Combinaciones (tecla B): todas las combinaciones y reacciones del juego. Las que ya
## has descubierto, con su nombre, cómo se lanzan y qué hacen; las que no, como "???" con un
## acertijo de pista; y las que piden un elemento que aún no has despertado (o el báculo), con
## candado. Dos marcapáginas arriba: PAREJAS (las manos) y TRIPLES (las manos y el báculo).
## Mismo aspecto que el Grimorio (los dos libros son hermanos).

const OPEN_SFX: AudioStream = preload("res://audio/sfx/sfx_book_open_01.ogg")
const CLOSE_SFX: AudioStream = preload("res://audio/sfx/sfx_book_close_01.ogg")
const TICK_SFX: AudioStream = preload("res://audio/sfx/sfx_ui_tick_01.ogg")
const BOOK := Rect2(70, 34, 500, 292)
const LEFT := Rect2(80, 42, 236, 276)
const RIGHT := Rect2(324, 42, 236, 276)
const LIST_Y: float = 90.0
## Alto de cada fila de la lista: las 17 entradas caben en la página (90 + 17 x 13 < 318).
const ROW_H: float = 13.0
## Marcapáginas: las parejas (y reacciones) y las triples del báculo.
# i18n
const TABS: PackedStringArray = ["PAREJAS", "TRIPLES"]
## Estrechos: a la derecha asoma la Esencia del HUD y no la deben pisar.
const TAB_W: float = 72.0
const TAB_H: float = 16.0
## Página del Grimorio (y su icono) de cada elemento.
const ELEMENT_PAGE: Dictionary[StringName, int] = {
	&"spark": 1, &"frost": 2, &"bolt": 3, &"earth": 4, &"arcane": 5
}
## Cómo se lanza, según SpellRecipe.Delivery.
# i18n
const HOW: PackedStringArray = [
	"Junta las manos, carga y suelta: sale hacia delante.",
	"Carga mirando el blanco: se abren círculos en el cielo y cae desde arriba.",
	"Carga mirando el blanco: llueve del cielo sobre toda la zona.",
	"Carga y suelta: atraviesa el cristal y perfora un túnel hondo.",
	"Carga y suelta: un haz continuo que sigue tu mirilla.",
	"Carga y suelta: una onda corre por el suelo hasta el cristal.",
	"Carga y suelta: un pulso que atrae los fragmentos.",
	"Carga y suelta: se abre un pozo delante de ti que se traga los fragmentos del valle.",
	"Carga mirando el cristal: lo hace vibrar entero y tus golpes resuenan unos segundos.",
	"Carga y suelta: una nube de tormenta se queda sobre el blanco y descarga sola.",
	"Carga y suelta: una estrella vuela al blanco, se contrae y estalla.",
]
## Las triples piden la gema del báculo.
# i18n
const HOW_TRIPLE: String = "Pon el tercer elemento en la gema del báculo (R) y junta las manos."
## Los Ecos repiten otra combinación.
# i18n
const HOW_ECHO: String = "Carga y suelta: sale el hechizo y sus ecos fantasma lo repiten."
const C_INK := Color("#2a1d4a")
const C_INK_SOFT := Color("#6a5a86")
const C_PAGE := Color("#f1e8d8")
const C_PAGE_SHADE := Color("#e0d2bb")
const C_COVER := Color("#3b2a7a")
const C_COVER_DARK := Color("#24184f")
const C_SKY := Color("#1b2a6b")
const C_GOLD := Color("#d8a23a")
const C_GOLD_LIGHT := Color("#ffd27a")
const C_PINK := Color("#c0398f")
const C_LOCKED := Color("#4a4f80")
const C_SHADOW := Color("#14183a")
const C_CYAN := Color("#c9f6ff")

var is_open: bool = false

var _selected: int = 0
## Página abierta: 0 parejas, 1 triples.
var _page: int = 0
var _tab_labels: Array[Label] = []
var _t: float = 0.0
var _open_t: float = 0.0
var _closing: bool = false
var _title: Label
var _count: Label
var _rows: Array[Label] = []
var _name: Label
var _elements: Label
var _how: Label
var _desc: Label
var _footer: Label
var _write_t: float = 1.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_title = _label(
		"LIBRO DE COMBINACIONES",
		UiFonts.TITLE,
		UiFonts.HEAD,
		C_GOLD_LIGHT,
		Rect2(LEFT.position + Vector2(0, 10), Vector2(LEFT.size.x, UiFonts.HEAD_LINE)),
		1
	)
	_count = _label(
		"",
		UiFonts.BOLD,
		UiFonts.SMALL,
		C_CYAN,
		Rect2(LEFT.position + Vector2(0, 28), Vector2(LEFT.size.x, UiFonts.LINE)),
		1
	)
	for i: int in TABS.size():
		var tr_rect: Rect2 = _tab_rect(i)
		_tab_labels.append(
			_label(
				TABS[i],
				UiFonts.BOLD,
				UiFonts.SMALL,
				C_GOLD_LIGHT,
				Rect2(tr_rect.position + Vector2(0, 3), Vector2(tr_rect.size.x, UiFonts.LINE)),
				1
			)
		)
	for i: int in maxi(SpellCaster.RECIPES.size(), StaffCombos.TRIPLES.size()):
		var r := Rect2(
			LEFT.position.x + 43,
			LIST_Y + i * ROW_H + floorf((ROW_H - UiFonts.LINE) * 0.5),
			LEFT.size.x - 51,
			UiFonts.LINE
		)
		_rows.append(_label("", UiFonts.BOLD, UiFonts.SMALL, C_CYAN, r, 0))
	var rx: float = RIGHT.position.x + 14
	var rw: float = RIGHT.size.x - 28
	var big := UiFonts.HEAD_LINE
	_name = _label("", UiFonts.TITLE, UiFonts.HEAD, C_INK, Rect2(rx, 60, rw - 56, big), 0, true)
	_elements = _label("", UiFonts.BOLD, UiFonts.SMALL, C_INK_SOFT, Rect2(rx, 80, rw, 12), 0)
	_how = _label("", UiFonts.BODY, UiFonts.SMALL, Color("#7a3fae"), Rect2(rx, 104, rw, 48), 0)
	_desc = _label("", UiFonts.BODY, UiFonts.SMALL, C_INK, Rect2(rx, 158, rw, 144), 0)
	_footer = _label("", UiFonts.BOLD, UiFonts.SMALL, C_CYAN, Rect2(10, 329, 620, 12), 1)
	Events.recipe_discovered.connect(func(_r: SpellRecipe) -> void: _refresh())
	Events.locale_changed.connect(_refresh)
	set_process(false)


func _label(
	text: String, font: Font, size_px: int, col: Color, r: Rect2, align: int, wrap: bool = false
) -> Label:
	var l := Label.new()
	l.text = tr(text)
	l.add_theme_font_override(&"font", font)
	l.add_theme_font_size_override(&"font_size", size_px)
	l.add_theme_color_override(&"font_color", col)
	l.horizontal_alignment = align as HorizontalAlignment
	l.position = r.position
	l.size = r.size
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if wrap or r.size.y > 14.0:
		UiFonts.paragraph(l)
	add_child(l)
	return l


func open() -> void:
	if is_open:
		return
	is_open = true
	_closing = false
	visible = true
	_open_t = 0.0
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	AudioDirector.play_sfx(OPEN_SFX, -4.0, 0.9)
	Events.grimoire_opened.emit()
	_refresh()
	set_process(true)


func close() -> void:
	if not is_open or _closing:
		return
	_closing = true
	AudioDirector.play_sfx(CLOSE_SFX, -6.0, 0.9)


## Estado de una receta: &"found" (descubierta), &"locked" (falta un elemento o el báculo) o
## &"unknown".
static func state_of(recipe: SpellRecipe) -> StringName:
	if GameState.progression.discovered_recipes.has(recipe.id):
		return &"found"
	if recipe.is_triple() and not StaffCombos.owned():
		return &"locked"
	for e: StringName in recipe.elements:
		for el: ElementDef in SpellCaster.ELEMENTS:
			if el.id == e and el.unlock_upgrade != &"":
				if GameState.progression.get_level(el.unlock_upgrade) == 0:
					return &"locked"
	return &"unknown"


func _element_name(id: StringName) -> String:
	for el: ElementDef in SpellCaster.ELEMENTS:
		if el.id == id:
			return tr(el.display_name).to_upper()
	return String(id).to_upper()


## Las recetas de la página abierta.
func _list() -> Array[SpellRecipe]:
	return StaffCombos.TRIPLES if _page == 1 else SpellCaster.RECIPES


## Abre una página del libro (0 parejas, 1 triples).
func open_page(page: int) -> void:
	page = clampi(page, 0, TABS.size() - 1)
	if page == _page:
		return
	_page = page
	_selected = 0
	AudioDirector.play_sfx(OPEN_SFX, -10.0, 1.25)
	_refresh()


func _tab_rect(i: int) -> Rect2:
	return Rect2(LEFT.position.x + 10.0 + i * (TAB_W + 6.0), BOOK.position.y - TAB_H, TAB_W, TAB_H)


func _refresh() -> void:
	var list: Array[SpellRecipe] = _list()
	var found: int = 0
	for i: int in _rows.size():
		_rows[i].visible = i < list.size()
	for i: int in TABS.size():
		_tab_labels[i].text = tr(TABS[i])
		_tab_labels[i].add_theme_color_override(
			&"font_color", C_GOLD_LIGHT if i == _page else C_LOCKED.lightened(0.45)
		)
	for i: int in list.size():
		var r: SpellRecipe = list[i]
		var st: StringName = state_of(r)
		if st == &"found":
			found += 1
		_rows[i].text = (tr(r.display_name).to_upper() if st == &"found" else "???")
		_rows[i].add_theme_color_override(
			&"font_color",
			(
				C_GOLD_LIGHT
				if i == _selected
				else (C_CYAN if st == &"found" else C_LOCKED.lightened(0.3))
			)
		)
	_count.text = tr("%d / %d DESCUBIERTAS") % [found, list.size()]
	var sel: SpellRecipe = list[_selected]
	var s: StringName = state_of(sel)
	var pair: String = "  +  ".join(
		sel.elements.map(func(e: StringName) -> String: return _element_name(e))
	)
	_name.text = tr(sel.display_name).to_upper() if s == &"found" else "???"
	_elements.text = pair if s == &"found" else ("?  +  ?  +  ?" if sel.is_triple() else "?  +  ?")
	if sel.is_reaction:
		_how.text = tr(
			"Reacción: no se lanza. Pasa en el cristal cuando un elemento toca la huella de otro."
		)
	else:
		var how: String = HOW_ECHO if sel.echo_of != &"" else HOW[sel.delivery]
		_how.text = tr(how) if s == &"found" else ""
		if sel.is_triple():
			_how.text = (tr(HOW_TRIPLE) + " " + _how.text).strip_edges()
	match s:
		&"found":
			_desc.text = tr(sel.description)
			_desc.add_theme_color_override(&"font_color", C_INK)
		&"locked":
			var missing: PackedStringArray = []
			for e: StringName in sel.elements:
				missing.append(_element_name(e))
			_desc.text = tr("Pide un elemento que aún duerme. Despiértalo en el Grimorio.")
			if sel.is_triple() and not StaffCombos.owned():
				_desc.text = tr(
					"Pide el báculo: búscalo en la constelación del Báculo del Grimorio."
				)
			_desc.add_theme_color_override(&"font_color", C_INK_SOFT)
		_:
			_desc.text = tr("PISTA: %s") % tr(sel.riddle)
			_desc.add_theme_color_override(&"font_color", C_PINK)
	_footer.text = tr("A/D PÁGINA  ·  W/S ELEGIR  ·  B / ESC CERRAR")
	_write_t = 0.0
	queue_redraw()


func _select(i: int) -> void:
	i = wrapi(i, 0, _list().size())
	if i == _selected:
		return
	_selected = i
	AudioDirector.play_sfx(TICK_SFX, -12.0)
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if not is_open:
		if event.is_action_pressed(&"open_spellbook") and not _grimoire_open():
			open()
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"open_spellbook") or event.is_action_pressed(&"ui_cancel"):
		close()
	elif event.is_action_pressed(&"ui_up") or event.is_action_pressed(&"move_forward"):
		_select(_selected - 1)
	elif event.is_action_pressed(&"ui_down") or event.is_action_pressed(&"move_back"):
		_select(_selected + 1)
	elif event.is_action_pressed(&"move_left") or event.is_action_pressed(&"cycle_element_left"):
		open_page(_page - 1)
	elif event.is_action_pressed(&"move_right") or event.is_action_pressed(&"cycle_element_right"):
		open_page(_page + 1)
	else:
		return
	get_viewport().set_input_as_handled()


func _gui_input(event: InputEvent) -> void:
	var pos := Vector2(-1, -1)
	if event is InputEventMouseMotion:
		pos = (event as InputEventMouseMotion).position
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		pos = (event as InputEventMouseButton).position
	if pos.x < 0.0:
		return
	var local: Vector2 = pos - _ofs()
	if event is InputEventMouseButton:
		for t: int in TABS.size():
			if _tab_rect(t).has_point(local):
				open_page(t)
	if local.x > LEFT.position.x and local.x < LEFT.end.x:
		var i: int = floori((local.y - LIST_Y) / ROW_H)
		if i >= 0 and i < _list().size():
			_select(i)
	accept_event()


func _grimoire_open() -> bool:
	var g: Grimoire = get_parent().get_node_or_null(^"Grimoire") as Grimoire
	return g != null and g.is_open


func _ofs() -> Vector2:
	var k: float = clampf(_open_t / 0.25, 0.0, 1.0)
	return Vector2(0, (1.0 - k * k * (3.0 - 2.0 * k)) * 40.0)


func _process(delta: float) -> void:
	_t += delta
	_write_t = minf(1.0, _write_t + delta * 3.0)
	_desc.visible_ratio = _write_t
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
		_open_t = minf(0.25, _open_t + delta)
	var o: Vector2 = _ofs()
	for c: Node in get_children():
		if c is Label:
			(c as Label).modulate.a = clampf(_open_t / 0.2, 0.0, 1.0)
	position = o
	queue_redraw()


func _draw() -> void:
	draw_rect(
		Rect2(Vector2(-10, -50), Vector2(660, 460)),
		Color(C_SHADOW, 0.55 * clampf(_open_t / 0.25, 0, 1))
	)
	# Tapas y páginas (como el Grimorio, pero con lomo dorado: es otro libro).
	draw_rect(BOOK.grow(3), C_SHADOW)
	draw_rect(BOOK, C_COVER)
	draw_rect(Rect2(BOOK.position + Vector2(246, 0), Vector2(8, BOOK.size.y)), C_GOLD)
	draw_rect(LEFT, C_SKY)
	draw_rect(RIGHT, C_PAGE)
	draw_rect(Rect2(RIGHT.position, Vector2(4, RIGHT.size.y)), C_PAGE_SHADE)
	for corner: Vector2 in [
		BOOK.position,
		BOOK.position + Vector2(BOOK.size.x - 8, 0),
		BOOK.position + Vector2(0, BOOK.size.y - 8),
		BOOK.end - Vector2(8, 8)
	]:
		draw_rect(Rect2(corner, Vector2(8, 8)), C_GOLD)
	# Marcapáginas: cintas que asoman por arriba del libro (la abierta, más alta y dorada).
	for t: int in TABS.size():
		var tab: Rect2 = _tab_rect(t)
		var open_tab: bool = t == _page
		if not open_tab:
			tab = Rect2(tab.position + Vector2(0, 3), tab.size - Vector2(0, 3))
		draw_rect(tab.grow(1), C_SHADOW)
		draw_rect(tab, C_COVER if open_tab else C_COVER_DARK)
		draw_rect(Rect2(tab.position, Vector2(tab.size.x, 2)), C_GOLD if open_tab else C_LOCKED)
	# Lista: un icono de elemento por elemento de la receta (o "?").
	var list: Array[SpellRecipe] = _list()
	for i: int in list.size():
		var r: SpellRecipe = list[i]
		var st: StringName = state_of(r)
		var y: float = LIST_Y + i * ROW_H
		var row := Rect2(LEFT.position.x + 6, y, LEFT.size.x - 12, ROW_H - 2)
		if i == _selected:
			draw_rect(row, Color(C_GOLD, 0.25))
			draw_rect(Rect2(row.position, Vector2(2, row.size.y)), C_GOLD_LIGHT)
		# Tres iconos (triples) más juntos, para que no pisen el nombre.
		var triple: bool = r.elements.size() >= 3
		var step: float = 10.0 if triple else 14.0
		var x0: float = row.position.x + (3.0 if triple else 6.0)
		for k: int in mini(r.elements.size(), 3):
			var at := Vector2(x0 + k * step, y + floorf((ROW_H - 9.0) * 0.5))
			var page: int = ELEMENT_PAGE.get(r.elements[k], 0)
			var col := Color(Grimoire.PAGES[page][2] as String)
			if st == &"found":
				_icon(GrimoireIcons.PAGE_ICONS[page], at, col)
			elif st == &"locked":
				_icon(GrimoireIcons.LOCK_ICON, at, C_LOCKED)
			else:
				_icon(GrimoireIcons.PAGE_ICONS[page], at, Color(col, 0.35))
		if r.is_reaction:
			draw_rect(Rect2(row.end.x - 6, y + floorf(ROW_H * 0.5) - 2, 4, 4), C_PINK)
	# Estrellita que late en lo descubierto (detalle del libro).
	var sel_y: float = LIST_Y + _selected * ROW_H + floorf(ROW_H * 0.5)
	var blink: float = 0.5 + 0.5 * sin(_t * 5.0)
	draw_rect(Rect2(LEFT.end.x - 16, sel_y - 2, 4, 4), Color(C_GOLD_LIGHT, blink))
	# Página derecha: viñeta de los dos elementos en grande si está descubierta.
	var sel: SpellRecipe = list[_selected]
	if state_of(sel) == &"found":
		var first_x: float = RIGHT.end.x - (52.0 if sel.elements.size() < 3 else 70.0)
		for k: int in mini(sel.elements.size(), 3):
			var page: int = ELEMENT_PAGE.get(sel.elements[k], 0)
			_icon(
				GrimoireIcons.PAGE_ICONS[page],
				Vector2(first_x + k * 22, 58),
				Color(Grimoire.PAGES[page][2] as String),
				2
			)
	draw_rect(Rect2(RIGHT.position.x + 14, 96, RIGHT.size.x - 28, 1), C_PAGE_SHADE)


func _icon(rows: PackedStringArray, at: Vector2, col: Color, px: int = 1) -> void:
	for y: int in rows.size():
		for x: int in rows[y].length():
			if rows[y][x] != ".":
				draw_rect(
					Rect2(at + Vector2(x * px, y * px), Vector2(px, px)),
					col.lightened(0.4) if rows[y][x] == "+" else col
				)
