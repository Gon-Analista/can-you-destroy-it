class_name LoadingCover
extends Control
## Pantalla de carga: tapa el juego mientras se precalientan los efectos (ver Main._warm_up) y
## se desvanece al terminar. Título, estrella que gira y puntos que avanzan.

const FONT_SMALL: FontFile = preload("res://ui/fonts/silkscreen_regular.woff2")
const FONT_BOLD: FontFile = preload("res://ui/fonts/pixelify_sans_bold.woff2")
const C_BG := Color("#14183a")
const C_GOLD := Color("#ffd27a")
const C_PINK := Color("#ff7ad9")
const C_CYAN := Color("#a5dae5")

var _t: float = 0.0
var _fade: float = -1.0
var _title: Label
var _sub: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_title = _label("CAN YOU DESTROY IT?", FONT_BOLD, 32, C_GOLD, Rect2(0, 140, 640, 40))
	_sub = _label("PREPARANDO LA MAGIA", FONT_SMALL, 8, C_CYAN, Rect2(0, 190, 640, 10))


## Empieza a desvanecerse; se borra sola al terminar.
func finish() -> void:
	_fade = 1.0


func _process(delta: float) -> void:
	_t += delta
	var dots: int = int(_t * 3.0) % 4
	_sub.text = tr("PREPARANDO LA MAGIA") + ".".repeat(dots)
	if _fade >= 0.0:
		_fade -= delta * 2.5
		modulate.a = clampf(_fade, 0.0, 1.0)
		if _fade <= 0.0:
			queue_free()
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), C_BG)
	# Estrella de cuatro puntas que late, a píxel entero.
	var c := Vector2(320, 120)
	var r: int = 3 + int(2.0 + 2.0 * sin(_t * 5.0))
	var col: Color = C_PINK if fmod(_t, 0.6) < 0.3 else C_GOLD
	draw_rect(Rect2(c.x - r * 2, c.y, r * 4 + 1, 1), col)
	draw_rect(Rect2(c.x, c.y - r * 2, 1, r * 4 + 1), col)
	for k: int in range(-r, r + 1):
		var w: int = r - absi(k)
		draw_rect(Rect2(c.x - w, c.y + k, w * 2 + 1, 1), col)


func _label(text: String, font: FontFile, font_size: int, color: Color, r: Rect2) -> Label:
	var l := Label.new()
	l.text = tr(text)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override(&"font", font)
	l.add_theme_font_size_override(&"font_size", font_size)
	l.add_theme_color_override(&"font_color", color)
	l.position = r.position
	l.size = r.size
	add_child(l)
	return l
