class_name Crosshair
extends Control
## Mira pixel art: cruz central, anillo de 12 puntos que muestra la carga del hechizo y
## marcador de impacto (4 diagonales) que destella al acertar. Con la carga por etapas de un
## combinado, una fila de rombos debajo (uno por círculo) que se encienden al encajar cada etapa,
## con un latido del anillo; con la última, una onda. Todo dibujado a píxel entero.

const DOTS: int = 12
const C_MAIN := Color("#f2f6ff")
const C_SHADOW := Color("#14183a")
const C_CHARGE := Color("#ffd27a")
const C_HIT := Color("#c9f6ff")
const C_RESONANT := Color("#ffd27a")
## Rombo de 5 píxeles de cada etapa.
const PIP: Array[Vector2] = [
	Vector2(0, 0), Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)
]
## Contorno oscuro del rombo (se lee también sobre el fuego del orbe, que es amarillo).
const PIP_RIM: Array[Vector2] = [
	Vector2(-2, 0),
	Vector2(2, 0),
	Vector2(0, -2),
	Vector2(0, 2),
	Vector2(-1, -1),
	Vector2(1, -1),
	Vector2(-1, 1),
	Vector2(1, 1),
]

var charge: float = 1.0
var _hit_flash: float = 0.0
var _hit_resonant: bool = false
var _cast_kick: float = 0.0
var _ready_flash: float = 0.0
## Etapas de la carga en curso (0 = sin etapas) y cuántas van; latido al encajar y onda final.
var _stage_total: int = 0
var _stage_lit: int = 0
var _stage_kick: float = 0.0
var _stage_wave: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	Events.spell_impacted.connect(_on_impact)
	Events.spell_cast.connect(func(_t: SpellTier, _s: int) -> void: _cast_kick = 1.0)
	Events.spell_ready.connect(func() -> void: _ready_flash = 1.0)
	Events.spell_charge_stage.connect(_on_charge_stage)


func _on_charge_stage(stage: int, total: int) -> void:
	if stage < 0:
		_stage_total = 0
		return
	_stage_total = total
	_stage_lit = stage
	if stage > 0:
		_stage_kick = 1.0
		if stage >= total:
			_stage_wave = 1.0


func _on_impact(hit: SpellHit) -> void:
	if not hit.by_player:
		return
	_hit_flash = 1.0
	_hit_resonant = hit.resonant


func _process(delta: float) -> void:
	_hit_flash = maxf(0.0, _hit_flash - delta * 5.0)
	_cast_kick = maxf(0.0, _cast_kick - delta * 8.0)
	_ready_flash = maxf(0.0, _ready_flash - delta * 4.0)
	_stage_kick = maxf(0.0, _stage_kick - delta * 6.0)
	_stage_wave = maxf(0.0, _stage_wave - delta * 2.8)
	queue_redraw()


func _px(p: Vector2, c: Color) -> void:
	draw_rect(Rect2(p.floor(), Vector2.ONE), c)


func _draw() -> void:
	var c: Vector2 = (size * 0.5).floor()
	var gap: int = 2 + roundi(_cast_kick * 3.0)
	# Cruz con sombra de 1 píxel para leerse sobre el cielo y el cristal.
	for i: int in range(gap, gap + 3):
		for d: Vector2 in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
			_px(c + d * i + Vector2(1, 1), C_SHADOW)
			_px(c + d * i, C_MAIN)
	_px(c, C_MAIN)
	# Anillo de carga: sólo visible mientras se recarga (y un destello al completarse).
	if charge < 1.0 or _ready_flash > 0.0:
		var lit: int = floori(charge * DOTS)
		var radius: float = 9.0 + roundf(_stage_kick * 2.0)
		for i: int in DOTS:
			var a: float = -PI * 0.5 + TAU * float(i) / DOTS
			var p: Vector2 = c + Vector2(cos(a), sin(a)) * radius
			var col: Color = C_CHARGE if i < lit else Color(C_SHADOW, 0.6)
			if i < lit and _stage_kick > 0.0:
				col = C_CHARGE.lerp(Color.WHITE, _stage_kick)
			if _ready_flash > 0.0:
				col = Color(1, 1, 1, _ready_flash)
			_px(p.round(), col)
	if _stage_total > 0:
		_draw_stages(c)
	# Marcador de impacto.
	if _hit_flash > 0.0:
		var hc: Color = C_RESONANT if _hit_resonant else C_HIT
		hc.a = _hit_flash
		var r: int = 5 + roundi((1.0 - _hit_flash) * 3.0) + (2 if _hit_resonant else 0)
		for d: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			for i: int in 3:
				_px(c + d * (r + i), hc)


## Rombos de las etapas bajo la mira (el recién encendido, en blanco) y la onda de la última.
func _draw_stages(c: Vector2) -> void:
	var step: float = 5.0
	var x0: float = c.x - step * float(_stage_total - 1) * 0.5
	var y: float = c.y + 15.0 + roundf(_stage_kick)
	for i: int in _stage_total:
		var p := Vector2(roundf(x0 + step * i), y)
		var on: bool = i < _stage_lit
		var col: Color = C_CHARGE if on else Color(C_SHADOW, 0.7)
		if on and i == _stage_lit - 1 and _stage_kick > 0.0:
			col = C_CHARGE.lerp(Color.WHITE, _stage_kick)
		for d: Vector2 in PIP_RIM:
			_px(p + d, Color(C_SHADOW, 0.85))
		for d: Vector2 in PIP:
			_px(p + d, col)
	if _stage_wave > 0.0:
		var r: float = 10.0 + (1.0 - _stage_wave) * 14.0
		var wc := Color(C_CHARGE.lerp(Color.WHITE, 0.5), _stage_wave)
		for i: int in 24:
			var a: float = TAU * float(i) / 24.0
			_px((c + Vector2(cos(a), sin(a)) * r).round(), wc)
