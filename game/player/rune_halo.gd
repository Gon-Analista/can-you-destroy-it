class_name RuneHalo
extends Node2D
## Las runas inscritas se ven en las manos (GDD: "cada mejora se ve y se oye"): sus glifos pixel
## art giran alrededor de la llama de cada palma en una órbita inclinada (los de atrás, más
## oscuros) y, con las manos juntas, alrededor del orbe combinado. Al lanzar con una mano sus
## glifos destellan y se abren un momento; al inscribir una runa nueva entran girando deprisa.
## A píxel entero y sin escalar los sprites (texturas de RuneGlyphs). Vive en el HUD, por encima de
## la capa de magia HD (en las manos, el resplandor de las llamas lo tapaba).

## Órbita alrededor de cada llama (px de la pantalla de 640x360) y la del orbe combinado.
const ORBIT := Vector2(25.0, 7.0)
const ORBIT_COMBO := Vector2(36.0, 10.0)
## Vueltas por segundo (y más rápido tras lanzar o inscribir).
const SPIN: float = 0.32
const C_BACK := Color(0.55, 0.5, 0.7, 0.75)

var hands: WizardHands
var _runes: Array[RuneDef] = []
var _tex: Array[Texture2D] = []
var _tex_hot: Array[Texture2D] = []
var _angle: float = 0.0
var _flash: PackedFloat32Array = PackedFloat32Array([0.0, 0.0])
var _burst: float = 0.0
## Con un libro, la mesa o un menú abiertos no se ven (las manos tampoco).
var _covered: bool = false


func _ready() -> void:
	z_index = 2
	Events.runes_changed.connect(_on_runes_changed)
	Events.upgrade_bought.connect(func(_id: StringName, _l: int) -> void: refresh())
	Events.spell_cast.connect(_on_spell_cast)
	Events.grimoire_opened.connect(func() -> void: _covered = true)
	Events.grimoire_closed.connect(func() -> void: _covered = false)
	Events.menu_opened.connect(func() -> void: _covered = true)
	Events.menu_closed.connect(func() -> void: _covered = false)
	refresh()


## Vuelve a leer las runas inscritas (al inscribir, comprar o cargar).
func refresh() -> void:
	_runes = RuneBook.inscribed(GameState.progression)
	_tex.clear()
	_tex_hot.clear()
	for def: RuneDef in _runes:
		_tex.append(RuneGlyphs.texture(def.glyph, def.color))
		_tex_hot.append(RuneGlyphs.texture(def.glyph, Color.WHITE, def.color.darkened(0.2)))
	visible = not _runes.is_empty()
	set_process(visible)
	queue_redraw()


func _on_runes_changed() -> void:
	var before: int = _runes.size()
	refresh()
	if _runes.size() > before:
		_burst = 1.0


func _on_spell_cast(_tier: SpellTier, side: int) -> void:
	if _runes.is_empty():
		return
	if side >= 2:
		_flash[0] = 1.0
		_flash[1] = 1.0
	else:
		_flash[side] = 1.0


func _process(delta: float) -> void:
	_burst = maxf(0.0, _burst - delta * 1.2)
	for side: int in 2:
		_flash[side] = maxf(0.0, _flash[side] - delta * 4.0)
	_angle = fmod(_angle + delta * TAU * SPIN * (1.0 + 3.0 * _burst), TAU)
	queue_redraw()


func _draw() -> void:
	if hands == null or _runes.is_empty() or not hands.orb_enabled or _covered:
		return
	if hands.is_combining():
		_draw_orbit(hands.palm_screen_position(SpellCaster.BOTH_HANDS), ORBIT_COMBO, 0.0, 0)
		return
	for side: int in 2:
		var center: Vector2 = hands.palm_screen_position(side)
		var dir: float = 1.0 if side == 0 else -1.0
		_draw_orbit(center, ORBIT * (1.0 + 0.35 * _flash[side]), dir, side)


## Los glifos repartidos en una elipse alrededor de `center`; `dir` el sentido de giro (0: el de la
## izquierda). Los de la mitad de atrás, más oscuros y algo más arriba.
func _draw_orbit(center: Vector2, radius: Vector2, dir: float, side: int) -> void:
	var n: int = _runes.size()
	var spin: float = _angle * (dir if dir != 0.0 else 1.0)
	for i: int in n:
		var a: float = spin + TAU * float(i) / float(n) + (0.0 if side == 0 else PI * 0.5)
		var front: bool = sin(a) > 0.0
		var pos: Vector2 = center + Vector2(cos(a) * radius.x, sin(a) * radius.y - 2.0)
		pos = (pos - Vector2(5, 5)).round()
		var hot: bool = _flash[side] > 0.5 or _burst > 0.6
		var tex: Texture2D = _tex_hot[i] if hot else _tex[i]
		draw_texture(tex, pos, Color.WHITE if front else C_BACK)
