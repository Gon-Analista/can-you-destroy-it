class_name SparkProjectile
extends Node3D
## Un hechizo en vuelo: el mismo `SpellOrb` que se veía en la mano (llama, Bola de Fuego...),
## siempre de cara a la cámara, con una estela de fuego de píxeles sólidos (`SpellTrail`), brasas
## que se quedan flotando y una luz que tiñe el valle a su paso. Todo lo decide el `SpellTier`
## del golpe: a más nivel, más grande, más rápido, menos torpe y de otro color.
## Vuela hacia un punto fijo con un arco y un bamboleo (más torpe cuanto más débil) y estalla al
## llegar. Se reutiliza desde un pool: nada se instancia en caliente salvo el orbe al cambiar de
## aspecto (al subir de nivel).

signal arrived(projectile: SparkProjectile)

## Distancia a la cámara a la que flotan los hechizos entre las manos.
const HANDS_DEPTH: float = 0.85
## Distancia recorrida a partir de la cual suelta brasas (m).
const EMBERS_FROM: float = 5.0

## Carga del orbe en vuelo (la que tenía en la mano al soltarlo).
var orb_charge: float = 1.0
var active: bool = false
var hit: SpellHit
var target_collider: Object

var _orb: SpellOrb
var _orb_def: SpellVisualDef
var _orb_scale: float = 1.0
var _trail: SpellTrail
var _embers: GPUParticles3D
var _ember_mat: ParticleProcessMaterial
var _sparks: GPUParticles3D
var _light: OmniLight3D
var _from: Vector3
var _to: Vector3
var _duration: float = 1.0
var _t: float = 0.0
var _wobble: float = 0.0
var _wobble_phase: float = 0.0
var _arc: float = 0.6
var _linger: float = 0.0


func _ready() -> void:
	_trail = SpellTrail.new()
	_trail.name = "Trail"
	_trail.hd = true
	add_child(_trail)
	_build_embers()
	_light = OmniLight3D.new()
	_light.omni_range = 5.0
	_light.shadow_enabled = false
	add_child(_light)
	_deactivate()


func launch(from: Vector3, to: Vector3, p_hit: SpellHit, collider: Object) -> void:
	var tier: SpellTier = p_hit.tier
	hit = p_hit
	target_collider = collider
	_from = from
	_to = to
	_duration = maxf(0.08, from.distance_to(to) / tier.speed)
	_t = 0.0
	_wobble = tier.wobble
	_wobble_phase = randf() * TAU
	_arc = 0.6 * (1.0 - tier.wobble * 0.5)
	_linger = -1.0
	global_position = from
	_set_orb(tier.visual)
	_orb_scale = tier.orb_scale * (1.35 if p_hit.resonant else 1.0)
	if _orb:
		_orb.appear()
		_orb.charge = orb_charge
		_face_camera()
	_trail.width = tier.trail_width * (1.35 if p_hit.resonant else 1.0)
	_trail.length_sec = tier.trail_length
	_trail.near_depth = HANDS_DEPTH
	_trail.max_scale = _orb_scale
	if tier.trail_ramp:
		_trail.set_ramp(tier.trail_ramp)
	_trail.start(from)
	_light.light_color = tier.color_glow
	_light.light_energy = tier.light_energy * 0.6
	_light.omni_range = 3.0 + tier.orb_scale * 0.4
	_light.visible = true
	var ember_cols := PackedColorArray([tier.color_core * 2.0, tier.color_glow * 1.4])
	_ember_mat.color_ramp = HdFx.color_ramp(ember_cols)
	(_sparks.process_material as ParticleProcessMaterial).color_ramp = HdFx.color_ramp(ember_cols)
	_embers.amount_ratio = clampf(tier.orb_scale / 10.0, 0.3, 1.0)
	_sparks.amount_ratio = clampf(tier.orb_scale / 10.0, 0.3, 1.0)
	active = true
	visible = true
	set_process(true)


func _process(delta: float) -> void:
	if _orb:
		_face_camera()
	if _linger >= 0.0:
		# Ya llegó: dejamos morir la estela, las brasas y el estallido antes de volver al pool.
		_linger -= delta
		if _linger < 0.0:
			_deactivate()
		return
	_t += delta / _duration
	var k: float = clampf(_t, 0.0, 1.0)
	var pos: Vector3 = _from.lerp(_to, k)
	# Arco suave hacia arriba y bamboleo que se apaga al llegar.
	pos.y += sin(k * PI) * _arc
	var fade_w: float = sin(k * PI)
	pos += (
		Vector3(sin(_t * 23.0 + _wobble_phase), cos(_t * 19.0 + _wobble_phase), 0.0)
		* _wobble
		* 0.35
		* fade_w
	)
	global_position = pos
	# Las brasas sólo cuando ya va lejos: pegadas a la cámara se verían como manchas enormes.
	_embers.emitting = k < 1.0 and _from.distance_to(pos) > EMBERS_FROM
	_sparks.emitting = _embers.emitting
	if k >= 1.0:
		_light.visible = false
		_trail.stop()
		_embers.emitting = false
		_sparks.emitting = false
		_linger = maxf(_embers.lifetime, _trail.length_sec)
		if _orb:
			_orb.release()
			_linger = maxf(_linger, _orb_def.release_time + _orb_def.sparkle_lifetime)
		arrived.emit(self)


## Cambia el aspecto del orbe sólo si es otro (al subir de nivel); si no, se reutiliza.
func _set_orb(def: SpellVisualDef) -> void:
	if def == _orb_def:
		return
	if _orb:
		_orb.queue_free()
		_orb = null
	_orb_def = def
	if def == null:
		return
	_orb = SpellOrb.new()
	_orb.name = "Orb"
	_orb.def = def
	add_child(_orb)


## El orbe se diseñó para verse de frente (sus órbitas giran en el plano de la cámara).
## Mantiene el tamaño en pantalla que tenía en la mano (a 0,85 m) hasta alcanzar su escala de
## vuelo; a partir de ahí se aleja con perspectiva. Así sale de la mano sin saltos.
func _face_camera() -> void:
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam:
		var dist: float = cam.global_position.distance_to(_orb.global_position)
		var s: float = clampf(dist / HANDS_DEPTH, 1.0, _orb_scale)
		_orb.global_basis = cam.global_basis.scaled(Vector3.ONE * s)


## Brasas suaves y chispas con estela que va soltando en vuelo (capa de magia HD).
func _build_embers() -> void:
	_embers = HdFx.embers(48, 0.09, PackedColorArray([Color(2, 1.7, 1.1), Color(1, 0.6, 0.2)]))
	_embers.name = "Embers"
	_embers.emitting = false
	_ember_mat = _embers.process_material
	_ember_mat.emission_sphere_radius = 0.15
	_ember_mat.initial_velocity_min = 0.5
	_ember_mat.initial_velocity_max = 2.0
	add_child(_embers)
	_sparks = HdFx.sparks(40, 2.5, 0.02, PackedColorArray([Color(2, 1.8, 1.2), Color(1, 0.5, 0.2)]))
	_sparks.name = "Sparks"
	_sparks.one_shot = false
	_sparks.explosiveness = 0.0
	_sparks.lifetime = 0.35
	_sparks.trail_lifetime = 0.07
	(_sparks.process_material as ParticleProcessMaterial).gravity = Vector3(0, -3.0, 0)
	add_child(_sparks)


func _deactivate() -> void:
	active = false
	visible = false
	_embers.emitting = false
	_sparks.emitting = false
	_trail.stop()
	_linger = -1.0
	set_process(false)
