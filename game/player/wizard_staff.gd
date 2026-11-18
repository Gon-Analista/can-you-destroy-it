class_name WizardStaff
extends Node2D
## El báculo en primera persona (GDD 5.2, tercer "espacio" de combinación). Pixel art a 1:1 que
## asoma por la derecha, detrás de la mano derecha, inclinado hacia el centro; su gema lleva el
## elemento del báculo: el sprite se tiñe con su color y encima arde, en la capa de magia HD, la
## llama de ese elemento (la misma de las manos, más pequeña).
##   aparecer (al comprarlo) -> sube desde abajo con rebote, destello y un gong
##   cambiar de elemento     -> la gema destella, el báculo da un tirón y suena el engaste
##   triple                  -> el báculo se acerca al centro y tiembla con la carga; su llama
##                              viaja al orbe de las manos y se funde con las otras dos
##   lanzar la triple        -> empujón hacia el blanco y la gema estalla
## Hijo de WizardHands (antes que los sprites de las manos: queda detrás).

const STAFF_TEX: Texture2D = preload("res://player/staff/staff.png")
const GEM_TEX: Texture2D = preload("res://player/staff/staff_gem.png")
const SHINE_TEX: Texture2D = preload("res://player/staff/staff_gem_shine.png")
const SUMMON_SFX: AudioStream = preload("res://audio/sfx/sfx_staff_summon_01.ogg")
## Esquina superior izquierda del sprite en reposo y durante una triple (pantalla 640x360).
const REST_POS := Vector2(490, 138)
const TRIPLE_POS := Vector2(438, 108)
## Centro de la gema dentro del sprite (ver tools/make_staff_sprite.py).
const GEM_IN_SPRITE := Vector2(28, 42)
## Tamaño de la llama de la gema (la de las manos es 1).
const GEM_ORB_CHARGE: float = 0.5
## A partir de esta mezcla de la triple, la llama de la gema ya está en el orbe de las manos.
const MERGED_AT: float = 0.85
const NIGHT_TINT := Color(0.5, 0.55, 0.85)
const GLOW := Color(1.5, 1.3, 1.1)

var hands: WizardHands
var _camera: Camera3D
var _staff: Sprite2D
var _gem: Sprite2D
var _shine: Sprite2D
var _orb: SpellOrb
var _element: ElementDef
var _shown: bool = false
## 0 = escondido abajo, 1 = en su sitio (con rebote al aparecer).
var _rise: float = 0.0
var _rise_vel: float = 0.0
var _triple: bool = false
var _join: float = 0.0
var _kick: float = 0.0
var _kick_vel: float = 0.0
var _glow: float = 0.0
var _t: float = 0.0
var _night: float = 0.0
var _orb_spent: bool = false
var _spent_t: float = 0.0


func setup(owner_hands: WizardHands, camera: Camera3D) -> void:
	hands = owner_hands
	_camera = camera
	add_to_group(&"night_listeners")
	_staff = _sprite("Staff", STAFF_TEX)
	_gem = _sprite("Gem", GEM_TEX)
	_shine = _sprite("Shine", SHINE_TEX)
	visible = false
	set_process(false)


func _sprite(node_name: String, tex: Texture2D) -> Sprite2D:
	var s := Sprite2D.new()
	s.name = node_name
	s.texture = tex
	s.centered = false
	add_child(s)
	return s


## Pone el elemento de la gema (null = sin báculo). Con `celebrate`, destello y tirón.
func set_element(el: ElementDef, celebrate: bool = false) -> void:
	if el == null:
		_shown = false
		visible = false
		if _orb:
			_orb.visible = false
		set_process(false)
		return
	var changed: bool = el != _element
	_element = el
	_gem.modulate = Color(el.color.r, el.color.g, el.color.b) * 1.15
	if changed and el.hand_visual:
		if _orb:
			_orb.name = "OldStaffGem"
			_orb.queue_free()
		_orb = SpellOrb.new()
		_orb.name = "StaffGemFlame"
		_orb.def = el.hand_visual
		_orb.charge = GEM_ORB_CHARGE
		_camera.add_child(_orb)
		_orb_spent = false
	if not _shown:
		_appear(celebrate)
	elif celebrate and changed:
		_kick_vel = -14.0
		_glow = 1.0
		if _orb:
			_orb.flare(0.6)
	set_process(true)
	_place_orb()


## El báculo sube desde abajo (al comprarlo, con gong; al cargar partida, sin ruido).
func _appear(celebrate: bool) -> void:
	_shown = true
	visible = true
	_rise = 0.0 if celebrate else 1.0
	_rise_vel = 0.0
	if celebrate:
		_glow = 1.0
		AudioDirector.play_sfx(SUMMON_SFX, -2.0)
		if _orb:
			_orb.flare(1.0)


## Las manos se juntan con el báculo: triple en marcha.
func begin_triple() -> void:
	_triple = true
	_glow = 0.6
	if _orb:
		_orb.flare(0.4)


## Sale la triple: empujón y la llama de la gema (ya en el orbe) se gasta hasta la recarga.
func release_triple() -> void:
	_triple = false
	_kick_vel = 22.0
	_glow = 1.0
	if _orb and _orb.visible:
		_orb.visible = false
	_orb_spent = true
	_spent_t = 0.0


func cancel_triple() -> void:
	_triple = false
	_kick_vel = -6.0


func set_night(k: float) -> void:
	_night = k


func is_shown() -> bool:
	return _shown


## Punto de la pantalla de la gema (de ahí sale su llama).
func gem_screen_position() -> Vector2:
	return _staff_pos() + GEM_IN_SPRITE


func _staff_pos() -> Vector2:
	var join: float = smoothstep(0.0, 1.0, _join)
	var pos: Vector2 = REST_POS.lerp(TRIPLE_POS, join)
	pos.y += (1.0 - _rise) * 220.0
	pos += Vector2(-10, -24) * _kick
	pos.y += sin(_t * 1.4 + 0.8) * 1.5
	if hands:
		var walk: float = minf(hands.move_speed / 4.0, 1.0)
		pos += Vector2(cos(_t * 6.0) * 1.5, absf(sin(_t * 6.0)) * 3.0) * walk
		if _triple:
			var amp: float = hands.combine_charge * 2.0
			pos += Vector2(randf_range(-amp, amp), randf_range(-amp, amp) * 0.5)
	return pos.round()


func _process(delta: float) -> void:
	_t += delta
	# Muelle del rebote al aparecer y del empujón.
	_rise_vel += ((1.0 - _rise) * 140.0 - _rise_vel * 11.0) * delta
	_rise += _rise_vel * delta
	_kick_vel += (-_kick * 240.0 - _kick_vel * 20.0) * delta
	_kick += _kick_vel * delta
	_glow = maxf(0.0, _glow - delta * 2.2)
	_join = move_toward(_join, 1.0 if _triple else 0.0, delta * (7.0 if _triple else 4.0))
	var pos: Vector2 = _staff_pos()
	_staff.position = pos
	var gem_at: Vector2 = pos + GEM_IN_SPRITE - Vector2(GEM_TEX.get_size()) * 0.5
	_gem.position = gem_at.round()
	_shine.position = _gem.position
	var base: Color = Color.WHITE.lerp(NIGHT_TINT, _night)
	var warm: float = _glow + (hands.combine_charge * 0.6 if _triple and hands else 0.0)
	_staff.modulate = base.lerp(GLOW, clampf(warm, 0.0, 1.0))
	_shine.modulate.a = 0.6 + 0.4 * sin(_t * 3.0)
	if _orb_spent:
		_spent_t += delta
		# La llama de la gema vuelve a encenderse cuando las manos han recargado.
		if _spent_t > 0.4 and hands and hands.charges[0] > 0.6 and not hands.is_combining():
			_orb_spent = false
			if _orb:
				_orb.appear()
				_orb.charge = GEM_ORB_CHARGE
	_place_orb()


func _place_orb() -> void:
	if _orb == null or _camera == null or not _orb.is_inside_tree():
		return
	var screen: Vector2 = gem_screen_position()
	var merge: float = smoothstep(0.0, MERGED_AT, _join) if _triple else 0.0
	if hands and merge > 0.0:
		screen = screen.lerp(hands.palm_screen_position(2), merge)
	var world: Vector3 = _camera.project_position(screen, WizardHands.orb_depth(_camera))
	_orb.position = _camera.to_local(world)
	if not _orb_spent and not _orb.is_releasing():
		_orb.visible = hands == null or hands.orb_enabled
		_orb.charge = GEM_ORB_CHARGE * (1.0 - 0.7 * merge) * (1.0 + 0.4 * _glow)
		if merge >= 0.98:
			_orb.visible = false
