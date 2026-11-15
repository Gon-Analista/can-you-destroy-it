class_name Crosshair
extends Control
## Mira pixel art: cruz central, anillo de 12 puntos que muestra la carga del hechizo y
## marcador de impacto (4 diagonales) que destella al acertar. Todo dibujado a píxel entero.

const DOTS: int = 12
const C_MAIN := Color("#f2f6ff")
const C_SHADOW := Color("#14183a")
const C_CHARGE := Color("#ffd27a")
const C_HIT := Color("#c9f6ff")
const C_RESONANT := Color("#ffd27a")

var charge: float = 1.0
var _hit_flash: float = 0.0
var _hit_resonant: bool = false
var _cast_kick: float = 0.0
var _ready_flash: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	Events.spell_impacted.connect(_on_impact)
	Events.spell_cast.connect(func(_t: SpellTier, _s: int) -> void: _cast_kick = 1.0)
	Events.spell_ready.connect(func() -> void: _ready_flash = 1.0)


func _on_impact(hit: SpellHit) -> void:
	_hit_flash = 1.0
	_hit_resonant = hit.resonant


func _process(delta: float) -> void:
	_hit_flash = maxf(0.0, _hit_flash - delta * 5.0)
	_cast_kick = maxf(0.0, _cast_kick - delta * 8.0)
	_ready_flash = maxf(0.0, _ready_flash - delta * 4.0)
	queue_redraw()


func _px(p: Vector2, c: Color) -> void:
	draw_rect(Rect2(p.floor(), Vector2.ONE), c)


func _draw() -> void:
	var c: Vector2 = (size * 0.5).floor()
	var gap: int = 2 + int(round(_cast_kick * 3.0))
	# Cruz con sombra de 1 píxel para leerse sobre el cielo y el cristal.
	for i: int in range(gap, gap + 3):
		for d: Vector2 in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
			_px(c + d * i + Vector2(1, 1), C_SHADOW)
			_px(c + d * i, C_MAIN)
	_px(c, C_MAIN)
	# Anillo de carga: sólo visible mientras se recarga (y un destello al completarse).
	if charge < 1.0 or _ready_flash > 0.0:
		var lit: int = int(floor(charge * DOTS))
		for i: int in DOTS:
			var a: float = -PI * 0.5 + TAU * float(i) / DOTS
			var p: Vector2 = c + Vector2(cos(a), sin(a)) * 9.0
			var col: Color = C_CHARGE if i < lit else Color(C_SHADOW, 0.6)
			if _ready_flash > 0.0:
				col = Color(1, 1, 1, _ready_flash)
			_px(p.round(), col)
	# Marcador de impacto.
	if _hit_flash > 0.0:
		var hc: Color = C_RESONANT if _hit_resonant else C_HIT
		hc.a = _hit_flash
		var r: int = 5 + int(round((1.0 - _hit_flash) * 3.0)) + (2 if _hit_resonant else 0)
		for d: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			for i: int in 3:
				_px(c + d * (r + i), hc)
