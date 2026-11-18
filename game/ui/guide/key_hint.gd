class_name KeyHint
extends Control
## Tecla pequeña en pixel art ("F") que sustituye al texto entero de una acción que el jugador
## ya conoce (ver `Guidance.prompt_mode`): dice "aquí se puede" sin repetir cómo. Entra con un
## pequeño salto y late despacio. Se coloca con `position` (esquina superior izquierda).

const C_SHADOW := Color("#14183a")
const C_KEY := Color("#f2f6ff")
const C_EDGE := Color("#a5dae5")
const C_GOLD := Color("#ffd27a")
const KEY_W: float = 11.0

## Letra de la tecla.
var key: String = "F"
## Si se está mostrando (se desvanece solo al apagarse).
var shown: bool = false:
	set(v):
		if v and not shown:
			_pop = 1.0
		shown = v

var _alpha: float = 0.0
var _pop: float = 0.0
var _t: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(KEY_W + 2.0, KEY_W + 3.0)


func _process(delta: float) -> void:
	_t += delta
	_pop = maxf(0.0, _pop - delta * 5.0)
	_alpha = move_toward(_alpha, 1.0 if shown else 0.0, delta * 8.0)
	visible = _alpha > 0.0
	if visible:
		queue_redraw()


func _draw() -> void:
	var lift: float = roundf(_pop * 2.0)
	var at := Vector2(1.0, 1.0 - lift)
	var a: float = _alpha * (0.8 + 0.2 * float(int(_t * 2.0) % 2))
	# Sombra, borde, cara y canto inferior (tecla con volumen).
	draw_rect(Rect2(at + Vector2(-1, -1), Vector2(KEY_W + 2, KEY_W + 3)), Color(C_SHADOW, a))
	draw_rect(Rect2(at, Vector2(KEY_W, KEY_W + 1)), Color(C_EDGE.darkened(0.35), a))
	draw_rect(Rect2(at, Vector2(KEY_W, KEY_W - 1)), Color(C_KEY, a))
	draw_rect(Rect2(at + Vector2(1, 1), Vector2(KEY_W - 2, 1)), Color(Color.WHITE, a))
	var w: float = UiFonts.BOLD.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, UiFonts.SMALL).x
	draw_string(
		UiFonts.BOLD,
		at + Vector2(roundf((KEY_W - w) * 0.5), 9),
		key,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		UiFonts.SMALL,
		Color(C_SHADOW, a)
	)
	if _pop > 0.0:
		draw_rect(
			Rect2(at + Vector2(-2, -2), Vector2(KEY_W + 4, KEY_W + 5)),
			Color(C_GOLD, _pop * a),
			false,
			1.0
		)
