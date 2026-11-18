class_name RankCeremony
extends Control
## La subida de rango (GDD 8): un momento grande. Destello, una franja oscura cruza la pantalla con
## el escudo del rango que crece a saltos de píxel entre rayos que giran, "¡ERES INICIADO!" en
## grande letra a letra, su frase y el rango x de 6; suena la fanfarria con coro (una por rango),
## la cámara se cierra de golpe y tiembla, una columna de luz envuelve al mago con un círculo mágico
## a sus pies (`RankAura`), la manga y la gema de las manos cambian (`HandRankStyle`), el escudo del
## HUD destella al cerrarse la franja (`RankBadge`; antes quedaría tapado por ella) y la música
## suma su capa (Main). Si se sube con un libro abierto (se despierta un elemento en el
## Grimorio), espera a que se cierre.

const RANK_SFX: Array[AudioStream] = [
	preload("res://audio/sfx/sfx_rank_up_01.ogg"),
	preload("res://audio/sfx/sfx_rank_up_02.ogg"),
	preload("res://audio/sfx/sfx_rank_up_03.ogg"),
	preload("res://audio/sfx/sfx_rank_up_04.ogg"),
	preload("res://audio/sfx/sfx_rank_up_05.ogg"),
]
const C_SHADOW := Color("#14183a")
const DURATION: float = 5.2
## Franja (y de arriba y de abajo) y centro del escudo.
const BAND_TOP: float = 50.0
const BAND_BOTTOM: float = 200.0
const CREST_CENTER := Vector2(320, 94)
const RAYS: int = 14
## Segundos antes del final en que el escudo del HUD toma el rango nuevo (la franja ya se cierra).
const BADGE_LEAD: float = 0.4

## Rango que se está celebrando (-1 = nada).
var rank: int = -1

var _age: float = 0.0
var _pending: int = -1
var _modal: bool = false
## El escudo del HUD aún no ha celebrado el rango de esta ceremonia.
var _badge_pending: bool = false
var _title: Label
var _motto: Label
var _count: Label
var _aura: RankAura
var _sparks: PackedVector3Array = []
## Triángulo de un rayo, reutilizado (sin asignar en cada fotograma).
var _tri := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_title = _label(UiFonts.TITLE, UiFonts.BIG, Rect2(0, 128, 640, 28))
	_title.pivot_offset = Vector2(320, 14)
	_motto = _label(UiFonts.BOLD, UiFonts.SMALL, Rect2(0, 160, 640, UiFonts.LINE))
	_count = _label(UiFonts.BOLD, UiFonts.SMALL, Rect2(0, 175, 640, UiFonts.LINE))
	for i: int in 24:
		_sparks.append(Vector3.ZERO)
	Events.rank_changed.connect(_on_rank_changed)
	Events.grimoire_opened.connect(func() -> void: _modal = true)
	Events.grimoire_closed.connect(
		func() -> void:
			_modal = false
			if _pending >= 0:
				play(_pending)
	)
	set_process(false)


func _label(font: Font, size_px: int, r: Rect2) -> Label:
	var l := Label.new()
	l.add_theme_font_override(&"font", font)
	l.add_theme_font_size_override(&"font_size", size_px)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.position = r.position
	l.size = r.size
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiFonts.outline(l, C_SHADOW)
	add_child(l)
	return l


func is_playing() -> bool:
	return rank >= 0


func _on_rank_changed(new_rank: int, _previous: int) -> void:
	if _modal:
		_pending = new_rank
		return
	play(new_rank)


## Celebra el rango `r` (también la demo y el menú de depuración).
func play(r: int) -> void:
	_pending = -1
	rank = clampi(r, 1, WizardRanks.last())
	var def: RankDef = WizardRanks.def_of(rank)
	_age = 0.0
	visible = true
	_title.text = tr("¡ERES %s!") % tr(def.display_name).to_upper()
	_title.add_theme_color_override(&"font_color", def.color_light)
	_title.visible_ratio = 0.0
	_motto.text = tr(def.motto)
	_motto.add_theme_color_override(&"font_color", def.color)
	_count.text = tr("RANGO %d DE %d") % [rank + 1, WizardRanks.RANKS.size()]
	_count.add_theme_color_override(&"font_color", def.rim)
	var rng := RandomNumberGenerator.new()
	rng.seed = rank * 17
	for i: int in _sparks.size():
		_sparks[i] = Vector3(rng.randf() * TAU, rng.randf_range(20.0, 80.0), rng.randf())
	AudioDirector.play_sfx(RANK_SFX[rank - 1], 0.0)
	HitStop.trigger(get_tree(), 0.25, 0.2)
	get_tree().call_group(&"hand_rank_style", &"celebrate", rank)
	_badge_pending = true
	_world_fx(def)
	set_process(true)


## La columna de luz alrededor del mago y el golpe de cámara.
func _world_fx(def: RankDef) -> void:
	var player: Player = get_tree().get_first_node_in_group(&"player") as Player
	if player == null:
		return
	if _aura == null or not is_instance_valid(_aura):
		_aura = RankAura.new()
		_aura.name = "RankAura"
		player.get_parent().add_child(_aura)
	_aura.target = player
	_aura.play(def)
	var cam: CameraRig = player.get_camera() as CameraRig
	if cam:
		cam.add_trauma(0.45)
		cam.punch_fov(-7.0)


func _process(delta: float) -> void:
	# Tiempo real: la ceremonia empieza con un hit-stop y no debe congelarse con él.
	_age += delta / maxf(Engine.time_scale, 0.01)
	var out: float = 1.0 - smoothstep(DURATION - 0.7, DURATION, _age)
	_title.visible_ratio = clampf((_age - 0.35) / 0.45, 0.0, 1.0)
	var pop: float = clampf((_age - 0.35) / 0.3, 0.0, 1.0)
	_title.scale = Vector2.ONE * snappedf(1.0 + 0.5 * (1.0 - pop) * cos(pop * PI * 1.5), 0.125)
	_title.modulate.a = out
	_motto.modulate.a = clampf((_age - 0.9) / 0.4, 0.0, 1.0) * out
	_count.modulate.a = clampf((_age - 1.2) / 0.4, 0.0, 1.0) * out
	if _badge_pending and _age >= DURATION - BADGE_LEAD:
		_badge_pending = false
		get_tree().call_group(&"rank_badge", &"celebrate", rank)
	if _age >= DURATION:
		rank = -1
		visible = false
		set_process(false)
		return
	queue_redraw()


## Escala entera del escudo: crece a saltos (1, 2, 3, 4, 5) y se asienta en 4.
func _crest_px() -> int:
	var k: float = (_age - 0.1) / 0.32
	if k <= 0.0:
		return 0
	if k < 1.0:
		return 1 + floori(k * 5.0)
	return 4


func _draw() -> void:
	if rank < 0:
		return
	var def: RankDef = WizardRanks.def_of(rank)
	var out: float = 1.0 - smoothstep(DURATION - 0.7, DURATION, _age)
	# Destello de pantalla (menos con "reducir destellos").
	var flash: float = maxf(0.0, 1.0 - _age / 0.35) * 0.55 * HdFx.flash_scale
	if flash > 0.0:
		draw_rect(Rect2(0, 0, 640, 360), Color(def.color_light, flash))
	# Franja: se abre desde el centro y se cierra al final.
	var open: float = 1.0 - pow(1.0 - clampf(_age / 0.25, 0.0, 1.0), 3.0)
	open *= 1.0 - smoothstep(DURATION - 0.5, DURATION, _age)
	var mid: float = (BAND_TOP + BAND_BOTTOM) * 0.5
	var half: float = floorf((BAND_BOTTOM - BAND_TOP) * 0.5 * open)
	if half >= 1.0:
		var band := Rect2(0, mid - half, 640, half * 2.0)
		draw_rect(band, Color(C_SHADOW, 0.62))
		for k: int in 4:
			var a: float = 0.62 * (1.0 - float(k + 1) / 5.0)
			draw_rect(Rect2(0, band.position.y - 2 * (k + 1), 640, 2), Color(C_SHADOW, a))
			draw_rect(Rect2(0, band.end.y + 2 * k, 640, 2), Color(C_SHADOW, a))
		draw_rect(Rect2(0, band.position.y, 640, 1), Color(def.rim, 0.9 * out))
		draw_rect(Rect2(0, band.end.y - 1, 640, 1), Color(def.rim, 0.9 * out))
	var px: int = _crest_px()
	if px <= 0:
		return
	_draw_rays(def, out)
	_draw_sparks(def, out)
	var size := Vector2(RankCrest.SIZE * px)
	RankCrest.draw(self, rank, (CREST_CENTER - size * 0.5).round(), px, Color(1, 1, 1, out))


## Rayos de luz que giran despacio detrás del escudo (triángulos a píxel entero).
func _draw_rays(def: RankDef, out: float) -> void:
	var spin: float = floorf(_age * 12.0) / 12.0 * 0.35
	var grow: float = clampf((_age - 0.15) / 0.4, 0.0, 1.0)
	for i: int in RAYS:
		var a: float = spin + TAU * float(i) / float(RAYS)
		var length: float = (70.0 + 18.0 * float(i % 2)) * grow
		var w: float = 0.09
		var p1: Vector2 = CREST_CENTER + Vector2(cos(a - w), sin(a - w)) * length
		var p2: Vector2 = CREST_CENTER + Vector2(cos(a + w), sin(a + w)) * length
		var col: Color = Color(def.color if i % 2 == 0 else def.color_light, 0.28 * out)
		_tri[0] = CREST_CENTER.round()
		_tri[1] = p1.round()
		_tri[2] = p2.round()
		draw_colored_polygon(_tri, col)


## Chispitas que salen del escudo hacia fuera (cuadrados de 1-2 px).
func _draw_sparks(def: RankDef, out: float) -> void:
	for s: Vector3 in _sparks:
		var life: float = fmod(_age * 0.6 + s.z, 1.0)
		var r: float = 10.0 + s.y * life
		var p: Vector2 = CREST_CENTER + Vector2(cos(s.x), sin(s.x)) * r
		var sz: float = 2.0 if life < 0.4 else 1.0
		var col: Color = def.color_light if life < 0.5 else def.color
		draw_rect(Rect2(p.round(), Vector2(sz, sz)), Color(col, (1.0 - life) * out))
