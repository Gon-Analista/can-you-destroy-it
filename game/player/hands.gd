class_name WizardHands
extends CanvasLayer
## Manos del mago en primera persona: sprites pixel art 2D (generados con Sprite AI, ver
## docs/sprite_ai.md) en 4 poses. Los sprites son de la mano IZQUIERDA (palma hacia la cámara,
## pulgar hacia la izquierda); la derecha es su reflejo.
## La animación es por código y siempre a píxel entero (sin rotar ni escalar los sprites):
##   lista (cargada)  -> CHARGE con el orbe brillando entre los dedos
##   lanzar           -> CAST + empujón hacia el centro, y retroceso elástico
##   recargando       -> REST y luego OPEN mientras el orbe vuelve a formarse

enum Pose { OPEN, CHARGE, CAST, REST }

const TEXTURES: Array[Texture2D] = [
	preload("res://player/hands/hand_l_open.png"),
	preload("res://player/hands/hand_l_charge.png"),
	preload("res://player/hands/hand_l_cast.png"),
	preload("res://player/hands/hand_l_rest.png"),
]
## Centro de la palma de la mano izquierda (píxeles del sprite de 192x192) en cada pose.
const PALM: Array[Vector2] = [Vector2(90, 76), Vector2(100, 68), Vector2(92, 84), Vector2(100, 70)]
const ORB_TEXTURE: Texture2D = preload("res://fx/textures/magic_orb.png")
const SPRITE_SIZE: float = 192.0
## Esquina superior izquierda de la mano derecha en reposo, en una pantalla de 640x360.
const REST_RIGHT := Vector2(404, 198)
## Empujón al lanzar: hacia el centro y hacia arriba.
const CAST_PUSH := Vector2(-22, -26)
const CAST_POSE_SEC: float = 0.13

var charge_ratio: float = 1.0
var move_speed: float = 0.0

var _sprites: Array[Sprite2D] = []
var _orbs: Array[Sprite2D] = []
var _poses: Array[Pose] = [Pose.CHARGE, Pose.CHARGE]
var _cast_timer: PackedFloat32Array = [0.0, 0.0]
var _kick: PackedFloat32Array = [0.0, 0.0]
var _kick_vel: PackedFloat32Array = [0.0, 0.0]
var _ready_pop: float = 0.0
var _orb_tint := Color.WHITE
var _t: float = 0.0
var _walk_phase: float = 0.0


func _ready() -> void:
	layer = 0
	for side: int in 2:
		var s := Sprite2D.new()
		s.name = "HandL" if side == 0 else "HandR"
		s.centered = false
		s.flip_h = side == 1
		s.texture = TEXTURES[Pose.CHARGE]
		add_child(s)
		var orb := Sprite2D.new()
		orb.texture = ORB_TEXTURE
		var mat := CanvasItemMaterial.new()
		mat.blend_mode = CanvasItemMaterial.BLEND_MODE_MIX
		orb.material = mat
		add_child(orb)
		_sprites.append(s)
		_orbs.append(orb)


## La mano `side` (0 izquierda, 1 derecha) lanza.
func play_cast(side: int) -> void:
	_cast_timer[side] = CAST_POSE_SEC
	_kick_vel[side] = 16.0


## Al recoger un fragmento: la mano izquierda da un tirón hacia abajo (lo atrapa).
func play_grab() -> void:
	_kick_vel[0] = -9.0


func play_ready() -> void:
	_ready_pop = 1.0


func set_orb_colors(_core: Color, glow: Color) -> void:
	_orb_tint = Color.WHITE.lerp(glow, 0.25)


## Punto de la pantalla (640x360) donde está la palma de la mano `side`.
func palm_screen_position(side: int) -> Vector2:
	var palm: Vector2 = PALM[_poses[side]]
	if side == 1:
		palm.x = SPRITE_SIZE - palm.x
	return _sprites[side].position + palm


func _process(delta: float) -> void:
	_t += delta
	_walk_phase += delta * move_speed * 1.7
	_ready_pop = maxf(0.0, _ready_pop - delta * 3.0)
	var screen_w: float = get_viewport().get_visible_rect().size.x
	for side: int in 2:
		_cast_timer[side] = maxf(0.0, _cast_timer[side] - delta)
		# Muelle amortiguado para el empujón y su rebote.
		var acc: float = -_kick[side] * 240.0 - _kick_vel[side] * 20.0
		_kick_vel[side] += acc * delta
		_kick[side] += _kick_vel[side] * delta
		var pose: Pose = _pose_for(side)
		_poses[side] = pose
		var sprite: Sprite2D = _sprites[side]
		sprite.texture = TEXTURES[pose]
		var sgn: float = -1.0 if side == 0 else 1.0
		var base := REST_RIGHT
		if side == 0:
			base.x = screen_w - REST_RIGHT.x - SPRITE_SIZE
		var breathe := Vector2(0, sin(_t * 1.6 + side * 0.9) * 1.5)
		var walk := (
			Vector2(cos(_walk_phase + side * PI) * 3.0, absf(sin(_walk_phase + side * PI)) * 4.0)
			* minf(move_speed / 4.0, 1.0)
		)
		var push := Vector2(CAST_PUSH.x * sgn, CAST_PUSH.y) * _kick[side]
		sprite.position = (base + breathe + walk + push).round()
		_update_orb(side, pose)


func _pose_for(side: int) -> Pose:
	if _cast_timer[side] > 0.0:
		return Pose.CAST
	if charge_ratio >= 1.0:
		return Pose.CHARGE
	if charge_ratio < 0.45:
		return Pose.REST
	return Pose.OPEN


func _update_orb(side: int, pose: Pose) -> void:
	var orb: Sprite2D = _orbs[side]
	var visible_amount: float = (
		0.0 if pose == Pose.CAST else clampf((charge_ratio - 0.15) / 0.85, 0.0, 1.0)
	)
	orb.visible = visible_amount > 0.02
	if not orb.visible:
		return
	var palm: Vector2 = palm_screen_position(side)
	var hover: float = sin(_t * 3.2 + side) * 1.5
	orb.position = (palm + Vector2(0, -26 + hover)).round()
	var bright: float = 1.0 + _ready_pop * 1.2
	orb.modulate = Color(
		_orb_tint.r * bright, _orb_tint.g * bright, _orb_tint.b * bright, visible_amount
	)
