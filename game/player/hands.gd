class_name WizardHands
extends CanvasLayer
## Manos del mago en primera persona que se juntan para formar el hechizo.
## Sprites pixel art 2D de Sprite AI (ver docs/sprite_ai.md): una tira de 7 frames de la mano
## IZQUIERDA pasando de abierta a ahuecada; la derecha es su reflejo. Entre las palmas vive el
## hechizo de verdad: un `SpellOrb` 3D (capas de núcleo, cintas, destellos y luz).
##
## La carga lo gobierna todo, siempre a píxel entero (sin rotar ni escalar los sprites):
##   recargando  -> las manos se acercan al centro y se van cerrando; el orbe crece
##   lista       -> manos ahuecadas sujetando el orbe a tope (latido al completarse)
##   lanzar      -> el orbe estalla (`release`) y las manos se abren hacia fuera con rebote

const STRIP: Texture2D = preload("res://player/hands/hand_l_cup_strip.png")
const FRAMES: int = 7
const FRAME_SIZE := Vector2(322, 192)
const ORB_DEF: SpellVisualDef = preload("res://data/spells/vfx_arcane_orb.tres")
## Esquina superior izquierda de la mano izquierda con las manos juntas (pantalla de 640x360).
const JOINED_POS := Vector2(0, 176)
## Cuánto se separan las manos cuando están abiertas (recién lanzado).
const OPEN_SPREAD: float = 44.0
## Centro del hueco entre las palmas, donde se forma el hechizo.
const ORB_SCREEN := Vector2(320, 258)
const ORB_DEPTH: float = 0.85
## Retroceso al lanzar: hacia fuera y un poco hacia arriba.
const CAST_PUSH := Vector2(-26, -8)

var charge_ratio: float = 1.0
var move_speed: float = 0.0
## Si es false no se muestra el orbe propio (la galería de VFX pone el suyo).
var orb_enabled: bool = true:
	set(value):
		orb_enabled = value
		if _orb:
			_orb.visible = value

var _sprites: Array[Sprite2D] = []
var _orb: SpellOrb
var _camera: Camera3D
var _kick: float = 0.0
var _kick_vel: float = 0.0
var _grab: float = 0.0
var _grab_vel: float = 0.0
var _ready_pop: float = 0.0
var _t: float = 0.0
var _walk_phase: float = 0.0
var _orb_spent: bool = false


func _ready() -> void:
	layer = 0
	for side: int in 2:
		var s := Sprite2D.new()
		s.name = "HandL" if side == 0 else "HandR"
		s.texture = STRIP
		s.hframes = FRAMES
		s.centered = false
		s.flip_h = side == 1
		add_child(s)
		_sprites.append(s)


## La cámara a la que se ancla el orbe del hechizo (lo llama el jugador).
func attach_camera(camera: Camera3D) -> void:
	_camera = camera
	_orb = SpellOrb.new()
	_orb.name = "HandsSpellOrb"
	_orb.def = ORB_DEF
	_orb.charge = charge_ratio
	_orb.visible = orb_enabled
	camera.add_child(_orb)
	_place_orb()


## Lanzar (cualquier mano): el orbe estalla y las manos se abren.
func play_cast(_side: int) -> void:
	_kick_vel = 15.0
	if _orb and not _orb.is_releasing():
		_orb.release()
		_orb_spent = true


## Al recoger un fragmento: tirón hacia abajo (lo atrapa).
func play_grab() -> void:
	_grab_vel = 10.0


func play_ready() -> void:
	_ready_pop = 1.0


## Compatibilidad con el lanzador: los colores del hechizo vienen de su SpellVisualDef.
func set_orb_colors(_core: Color, _glow: Color) -> void:
	pass


## Punto de la pantalla desde el que sale el hechizo: el centro entre las palmas.
func palm_screen_position(_side: int) -> Vector2:
	return ORB_SCREEN + Vector2(0, _bob().y)


func _process(delta: float) -> void:
	_t += delta
	_walk_phase += delta * move_speed * 1.7
	_ready_pop = maxf(0.0, _ready_pop - delta * 3.0)
	_kick = _spring(_kick, delta, true)
	_grab = _spring(_grab, delta, false)
	var closed: float = _ease(charge_ratio)
	var frame: int = clampi(int(round(closed * (FRAMES - 1))), 0, FRAMES - 1)
	var spread: float = (1.0 - closed) * OPEN_SPREAD
	var screen_w: float = get_viewport().get_visible_rect().size.x
	var bob: Vector2 = _bob()
	for side: int in 2:
		var sprite: Sprite2D = _sprites[side]
		sprite.frame = frame
		var sgn: float = -1.0 if side == 0 else 1.0
		var x: float = JOINED_POS.x - spread + CAST_PUSH.x * _kick
		var pos := Vector2(x, JOINED_POS.y + CAST_PUSH.y * _kick + 6.0 * _grab) + bob
		if side == 1:
			pos.x = screen_w - FRAME_SIZE.x - x
		# Latido al completar la carga: las palmas se cierran un píxel más.
		pos.x -= sgn * _ready_pop * 2.0
		sprite.position = pos.round()
	_update_orb()


func _bob() -> Vector2:
	var breathe := Vector2(0, sin(_t * 1.6) * 1.5)
	var walk := (
		Vector2(cos(_walk_phase) * 2.0, absf(sin(_walk_phase)) * 4.0) * minf(move_speed / 4.0, 1.0)
	)
	return breathe + walk


## La mano se cierra deprisa al principio y se asienta al final.
static func _ease(x: float) -> float:
	return 1.0 - pow(1.0 - clampf(x, 0.0, 1.0), 2.0)


## Muelle amortiguado. `is_kick` elige el estado del empujón o el del tirón de recoger.
func _spring(value: float, delta: float, is_kick: bool) -> float:
	var vel: float = _kick_vel if is_kick else _grab_vel
	vel += (-value * 240.0 - vel * 20.0) * delta
	value += vel * delta
	if is_kick:
		_kick_vel = vel
	else:
		_grab_vel = vel
	return value


func _update_orb() -> void:
	if _orb == null:
		return
	_place_orb()
	if _orb_spent and not _orb.is_releasing() and charge_ratio > 0.02:
		_orb_spent = false
		_orb.appear()
	if not _orb.is_releasing():
		_orb.charge = maxf(charge_ratio, 0.05)


func _place_orb() -> void:
	var world: Vector3 = _camera.project_position(palm_screen_position(0), ORB_DEPTH)
	_orb.position = _camera.to_local(world)
