class_name SparkProjectile
extends Node3D
## La chispa en vuelo: rombo brillante con estela de chispitas y una luz cálida.
## Vuela hacia un punto fijo con un bamboleo torpe (más torpe cuanto más débil).
## Si tiene `visual`, en vez del rombo vuela un `SpellOrb` (p. ej. la Bola de Fuego) mirando
## siempre a la cámara, que estalla al llegar.

signal arrived(projectile: SparkProjectile)

const SPARK_SHADER: Shader = preload("res://spells/spark.gdshader")
## Distancia a la cámara a la que flotan los hechizos entre las manos.
const HANDS_DEPTH: float = 0.85

## Orbe que sustituye al rombo (opcional; se fija antes de añadir el nodo al árbol).
var visual: SpellVisualDef
## Escala del orbe en vuelo.
var orb_scale: float = 1.0
## Carga del orbe en vuelo (la que tenía entre las manos al soltarlo).
var orb_charge: float = 1.0
var active: bool = false
var hit: SpellHit
var target_collider: Object

var _quad: MeshInstance3D
var _mat: ShaderMaterial
var _trail: GPUParticles3D
var _light: OmniLight3D
var _orb: SpellOrb
var _from: Vector3
var _to: Vector3
var _duration: float = 1.0
var _t: float = 0.0
var _wobble: float = 0.0
var _wobble_phase: float = 0.0
var _linger: float = 0.0


func _ready() -> void:
	_quad = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	_quad.mesh = q
	_mat = ShaderMaterial.new()
	_mat.shader = SPARK_SHADER
	_mat.render_priority = 3
	_quad.material_override = _mat
	_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_quad)
	_trail = GPUParticles3D.new()
	_trail.amount = 28
	_trail.lifetime = 0.4
	_trail.local_coords = false
	_trail.emitting = false
	_trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_trail.visibility_aabb = AABB(Vector3(-40, -40, -40), Vector3(80, 80, 80))
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = 0.2
	pm.initial_velocity_max = 0.9
	pm.gravity = Vector3(0, -2.5, 0)
	pm.scale_min = 0.5
	pm.scale_max = 1.0
	var ramp := Gradient.new()
	ramp.set_color(0, Color("#fff4c2"))
	ramp.set_color(1, Color(1.0, 0.35, 0.2, 0.0))
	var rt := GradientTexture1D.new()
	rt.gradient = ramp
	pm.color_ramp = rt
	_trail.process_material = pm
	var dq := QuadMesh.new()
	dq.size = Vector2(0.09, 0.09)
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	dm.vertex_color_use_as_albedo = true
	dm.albedo_texture = PixelTextures.star()
	dm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	dm.disable_fog = true
	dm.render_priority = 2
	dq.material = dm
	_trail.draw_pass_1 = dq
	add_child(_trail)
	_light = OmniLight3D.new()
	_light.omni_range = 4.0
	_light.shadow_enabled = false
	add_child(_light)
	if visual:
		_orb = SpellOrb.new()
		_orb.name = "Orb"
		_orb.def = visual
		add_child(_orb)
		_orb.scale = Vector3.ONE * orb_scale
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
	_linger = -1.0
	global_position = from
	_quad.scale = Vector3.ONE * tier.size * (1.5 if p_hit.resonant else 1.0)
	_quad.visible = _orb == null
	if _orb:
		_orb.appear()
		_orb.charge = orb_charge
		_face_camera()
	_mat.set_shader_parameter("color_core", tier.color_core)
	_mat.set_shader_parameter("color_glow", Color("#ffd27a") if p_hit.resonant else tier.color_glow)
	_mat.set_shader_parameter("flicker_seed", randf() * 10.0)
	_light.light_color = tier.color_glow
	_light.light_energy = tier.light_energy * 0.5
	_light.visible = true
	_trail.amount_ratio = clampf(tier.size / 0.4, 0.35, 1.0)
	_trail.emitting = true
	active = true
	visible = true
	set_process(true)


func _process(delta: float) -> void:
	if _orb:
		_face_camera()
	if _linger >= 0.0:
		# Ya llegó: dejamos morir la estela (y el estallido del orbe) antes de volver al pool.
		_linger -= delta
		if _linger < 0.0:
			_deactivate()
		return
	_t += delta / _duration
	var k: float = clampf(_t, 0.0, 1.0)
	var pos: Vector3 = _from.lerp(_to, k)
	# Arco suave hacia arriba y bamboleo que se apaga al llegar.
	pos.y += sin(k * PI) * 0.6
	var fade_w: float = sin(k * PI)
	pos += (
		Vector3(sin(_t * 23.0 + _wobble_phase), cos(_t * 19.0 + _wobble_phase), 0.0)
		* _wobble
		* 0.35
		* fade_w
	)
	global_position = pos
	if k >= 1.0:
		_quad.visible = false
		_light.visible = false
		_trail.emitting = false
		_linger = _trail.lifetime
		if _orb:
			_orb.release()
			_linger = maxf(_linger, visual.release_time + visual.sparkle_lifetime)
		arrived.emit(self)


## El orbe se diseñó para verse de frente (sus órbitas giran en el plano de la cámara).
func _face_camera() -> void:
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam:
		# Mismo tamaño en pantalla que entre las manos (a 0,85 m) hasta alcanzar `orb_scale`;
		# a partir de ahí se aleja con perspectiva. Así la bola "sale" de las manos sin saltos.
		var dist: float = cam.global_position.distance_to(global_position)
		var s: float = clampf(dist / HANDS_DEPTH, 1.0, orb_scale)
		_orb.global_basis = cam.global_basis.scaled(Vector3.ONE * s)


func _deactivate() -> void:
	active = false
	visible = false
	_trail.emitting = false
	_linger = -1.0
	set_process(false)
