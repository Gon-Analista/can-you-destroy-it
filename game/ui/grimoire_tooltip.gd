class_name GrimoireTooltip
extends Control
## Ficha flotante del Grimorio: al pasar el ratón por una mejora dice qué hace sin tener que
## elegirla ni mirar la otra página. Nombre con su icono, nivel, qué hace, cómo está ahora y
## cómo quedará, y el coste (o lo que le falta). Pergamino con borde de tinta, a píxel entero.

const W: int = 156
const PAD: int = 5
const ICON_BOX: int = 20
## Alto de la cabecera (icono, nombre y nivel) hasta el separador.
const HEAD_H: int = PAD + ICON_BOX + 5
const C_INK := Color("#2a1d4a")
const C_INK_SOFT := Color("#6a5a86")
const C_NEXT := Color("#7a3fae")
const C_PAGE := Color("#f1e8d8")
const C_PAGE_EDGE := Color("#c9b693")
const C_SHADOW := Color("#14183a")
const C_GOLD := Color("#d8a23a")
const C_GOLD_LIGHT := Color("#ffd27a")
const C_PINK := Color("#ff7ad9")
const C_RED := Color("#c8423a")
const C_TEAR := Color("#8a4fe0")
const C_CYAN_DARK := Color("#2f7f96")

var _node: UpgradeNode
var _accent: Color = C_GOLD
var _name: Label
var _level: Label
var _desc: Label
var _now: Label
var _next: Label
var _cost: Label
var _cost_icon: PackedStringArray = PackedStringArray()
var _cost_icon_col: Color = C_PINK
var _cost_y: int = 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	var tx: int = PAD + ICON_BOX + 4
	_name = _label(UiFonts.BOLD, C_INK, Rect2(tx, PAD, W - tx - PAD, UiFonts.LINE))
	_level = _label(UiFonts.BODY, C_INK_SOFT, Rect2(tx, PAD + 12, W - tx - PAD, UiFonts.LINE))
	_desc = _label(UiFonts.BODY, C_INK, Rect2(PAD, 0, W - PAD * 2, UiFonts.LINE))
	_now = _label(UiFonts.BODY, C_INK_SOFT, Rect2(PAD, 0, W - PAD * 2, UiFonts.LINE))
	_next = _label(UiFonts.BODY, C_NEXT, Rect2(PAD, 0, W - PAD * 2, UiFonts.LINE))
	_cost = _label(UiFonts.BOLD, C_INK, Rect2(PAD + 14, 0, W - PAD * 2 - 14, UiFonts.LINE))
	for l: Label in [_desc, _now, _next, _cost]:
		UiFonts.paragraph(l)


## Muestra la ficha de `node` junto a `anchor` (centro de su medallón, en coordenadas del padre).
func show_for(node: UpgradeNode, anchor: Vector2, accent: Color) -> void:
	_node = node
	_accent = accent
	var prog: Progression = GameState.progression
	var level: int = prog.get_level(node.id)
	var max_level: int = node.get_max_level()
	var block: StringName = prog.purchase_block(node)
	_name.text = tr(node.display_name).to_upper()
	_level.text = tr("NIVEL %d DE %d") % [level, max_level]
	_desc.text = first_sentence(tr(node.description))
	_now.text = tr("AHORA: %s") % tr(node.describe_level(level))
	_next.text = (
		tr("SIGUIENTE: %s") % tr(node.describe_level(level + 1)) if level < max_level else ""
	)
	_cost_icon = PackedStringArray()
	_cost.add_theme_color_override(&"font_color", C_INK)
	match block:
		&"max":
			_cost.text = tr("¡CONSTELACIÓN COMPLETA!")
			_cost.add_theme_color_override(&"font_color", C_CYAN_DARK)
		&"locked":
			_cost.text = tr("NECESITA: %s") % _prereqs(node)
			_cost.add_theme_color_override(&"font_color", C_INK_SOFT)
		&"apex":
			_cost.text = (
				tr("ASCENSIÓN: CON EL CRISTAL AL %d %%") % roundi(node.apex_destroyed_ratio * 100.0)
			)
			_cost.add_theme_color_override(&"font_color", C_INK_SOFT)
		_:
			var cost: int = node.cost_for_level(level)
			_cost.text = Hud.format_int(cost)
			if block == &"mana" or block == &"tears":
				_cost.add_theme_color_override(&"font_color", C_RED)
			_cost_icon = (
				GrimoireIcons.TEAR_ICON if node.pays_with_tears() else GrimoireIcons.MANA_ICON
			)
			_cost_icon_col = C_TEAR if node.pays_with_tears() else C_PINK
	_cost.position.x = PAD + (14 if not _cost_icon.is_empty() else 0)
	_cost.size.x = W - PAD - _cost.position.x
	# Las líneas se colocan según lo que ocupe cada texto.
	var y: int = HEAD_H + 3
	for l: Label in [_desc, _now, _next, _cost]:
		l.visible = l.text != ""
		if not l.visible:
			continue
		l.position.y = y
		l.size.y = UiFonts.LINE
		var lines: int = maxi(1, l.get_line_count())
		l.size.y = lines * UiFonts.PITCH
		if l == _cost:
			_cost_y = y
		y += lines * UiFonts.PITCH + (4 if l == _desc or l == _next else 1)
	size = Vector2(W, y + PAD - 1)
	# A un lado del medallón (al que tenga sitio), dentro de la pantalla.
	var screen := Vector2(640, 360)
	var x: float = anchor.x + 16.0
	if anchor.x > screen.x * 0.33 and anchor.x - 16.0 - W >= 2.0:
		x = anchor.x - 16.0 - W
	x = clampf(x, 2.0, screen.x - W - 2.0)
	var top: float = clampf(anchor.y - 14.0, 2.0, screen.y - size.y - 2.0)
	position = Vector2(roundf(x), roundf(top))
	visible = true
	queue_redraw()


## Sólo la primera frase de la descripción: la ficha es para leerla de un vistazo (la página
## derecha tiene la entera).
static func first_sentence(text: String) -> String:
	var cut: int = text.find(". ")
	return text if cut < 0 else text.substr(0, cut + 1)


func hide_tip() -> void:
	visible = false
	_node = null


func shown_node() -> UpgradeNode:
	return _node if visible else null


func _draw() -> void:
	if _node == null:
		return
	var r := Rect2(Vector2.ZERO, size)
	# Sombra dura de 2 px, borde de tinta y pergamino con el canto del color de la constelación.
	draw_rect(Rect2(r.position + Vector2(2, 2), r.size), Color(C_SHADOW, 0.8))
	draw_rect(r.grow(1), C_INK)
	draw_rect(r, C_PAGE)
	draw_rect(Rect2(r.position, Vector2(r.size.x, 2)), _accent)
	draw_rect(Rect2(Vector2(0, r.size.y - 2), Vector2(r.size.x, 2)), C_PAGE_EDGE)
	# Medallón con el icono de la mejora.
	var at := Vector2(PAD, PAD)
	draw_rect(Rect2(at, Vector2(ICON_BOX, ICON_BOX)), C_GOLD)
	draw_rect(Rect2(at + Vector2(1, 1), Vector2(ICON_BOX - 2, ICON_BOX - 2)), C_SHADOW)
	var icon: PackedStringArray = GrimoireIcons.icon_for(_node)
	_draw_icon(icon, at + Vector2(2, 2), 2, _accent)
	# Separador de puntos bajo la cabecera.
	for x: int in range(PAD, W - PAD, 4):
		draw_rect(Rect2(x, HEAD_H, 2, 1), C_PAGE_EDGE)
	if not _cost_icon.is_empty():
		_draw_icon(_cost_icon, Vector2(PAD + 2, _cost_y + 2), 1, _cost_icon_col)


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


func _prereqs(node: UpgradeNode) -> String:
	var names: PackedStringArray = []
	for req: StringName in node.prerequisites:
		if String(req).begins_with("recipe:"):
			names.append(tr("DESCUBRIR LA BOLA DE FUEGO"))
		elif String(req).begins_with("pylon:"):
			names.append(
				tr("EL PILÓN AL %d %%") % roundi(float(String(req).get_slice(":", 1)) * 100.0)
			)
		for n: UpgradeNode in GameState.UPGRADES:
			if n.id == req:
				names.append(tr(n.display_name).to_upper())
	return ", ".join(names)


func _label(font: Font, color: Color, r: Rect2) -> Label:
	var l := Label.new()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override(&"font", font)
	l.add_theme_font_size_override(&"font_size", UiFonts.SMALL)
	l.add_theme_color_override(&"font_color", color)
	l.position = r.position
	l.size = r.size
	add_child(l)
	return l
