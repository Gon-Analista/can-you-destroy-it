class_name SpellOrb
extends Node3D
## Orbe de un hechizo en alta definición (capa de magia HD, ver MagicLayer), configurado por un
## `SpellVisualDef`:
## 1. Halo: luz radial aditiva con rayos que florece con el resplandor.
## 2. Cuerpo: bola de energía turbulenta (`hd_fire.gdshader`): fuego que lame hacia arriba o
##    remolino arcano, núcleo blanco ardiente y borde de color.
## 3. Cintas: órbitas de energía que pasan por delante y por detrás.
## 4. Brasas suaves que se desprenden y, mientras carga, partículas que se arremolinan hacia él.
## 5. Luz: tiñe lo que hay cerca (las manos, el valle).
## Se controla con `charge` (0..1), `appear()` y `release()` (estallido con destello, chispas
## con estela y onda de choque). Todo se crea una vez; nada se instancia en caliente.

signal released

const RIBBON_SHADER: Shader = preload("res://spells/vfx/spell_ribbon.gdshader")
const RING_SEGMENTS: int = 72

@export var def: SpellVisualDef
## 0..1. Con carga baja el orbe es pequeño y tenue; con carga completa, a tope.
@export_range(0.0, 1.0) var charge: float = 1.0:
	set(value):
		charge = clampf(value, 0.0, 1.0)
		if is_node_ready():
			_apply_charge()

var _body: MeshInstance3D
var _body_mat: ShaderMaterial
var _glow: MeshInstance3D
var _glow_mat: ShaderMaterial
var _ring: MeshInstance3D
var _ring_mat: ShaderMaterial
var _ribbon_pivot: Node3D
var _ribbons: Array[MeshInstance3D] = []
var _ribbon_mats: Array[ShaderMaterial] = []
var _ribbon_base_speed: PackedFloat32Array = []
var _embers: GPUParticles3D
var _converge: GPUParticles3D
var _sparks: GPUParticles3D
var _light: OmniLight3D
var _release_t: float = -1.0
var _precession: float = 0.0
var _t: float = 0.0


func _ready() -> void:
	assert(def != null, "SpellOrb necesita un SpellVisualDef")
	var seed_f: float = float(def.seed) * 1.37
	_glow = HdFx.quad(HdFx.GLOW_SHADER, 1.0, 3)
	_glow.name = "Glow"
	_glow_mat = _glow.material_override
	_glow_mat.set_shader_parameter("color", def.light_color)
	_glow_mat.set_shader_parameter("rays", def.glow_rays)
	_glow_mat.set_shader_parameter("seed", seed_f)
	add_child(_glow)
	_body = HdFx.quad(HdFx.FIRE_SHADER, 1.0, 5)
	_body.name = "Body"
	_body_mat = _body.material_override
	_body_mat.set_shader_parameter("ramp", HdFx.smooth_ramp(def.core_ramp))
	_body_mat.set_shader_parameter("style", def.style)
	_body_mat.set_shader_parameter("seed", seed_f)
	_body_mat.set_shader_parameter("intensity", def.body_intensity)
	add_child(_body)
	_ring = HdFx.quad(HdFx.RING_SHADER, 1.0, 8)
	_ring.name = "Shockwave"
	_ring_mat = _ring.material_override
	_ring_mat.set_shader_parameter("color", def.light_color)
	_ring_mat.set_shader_parameter("seed", seed_f)
	_ring.visible = false
	add_child(_ring)
	_build_ribbons()
	_build_particles()
	_light = OmniLight3D.new()
	_light.name = "Light"
	_light.light_color = def.light_color
	_light.omni_range = def.light_range
	_light.omni_attenuation = 1.4
	_light.shadow_enabled = false
	add_child(_light)
	_apply_charge()


## Vuelve a mostrar el orbe tras un `release()`.
func appear() -> void:
	_release_t = -1.0
	visible = true
	_body.visible = true
	_glow.visible = true
	_ribbon_pivot.visible = true
	_ring.visible = false
	_embers.emitting = true
	_body_mat.set_shader_parameter("burst", 0.0)
	_body_mat.set_shader_parameter("fade", 1.0)
	_ribbon_pivot.scale = Vector3.ONE
	for m: ShaderMaterial in _ribbon_mats:
		m.set_shader_parameter("fade", 1.0)
	_apply_charge()
	set_process(true)


## Estallido: el cuerpo se hincha y se deshace en llamas, destello de luz, onda de choque,
## chispas con estela y las órbitas se abren. Emite `released` al terminar.
func release() -> void:
	if _release_t >= 0.0:
		return
	_release_t = 0.0
	_embers.emitting = false
	_converge.emitting = false
	_sparks.amount_ratio = lerpf(0.4, 1.0, charge)
	_sparks.restart()
	_ring.visible = def.release_flash >= 0.5
	set_process(true)


func is_releasing() -> bool:
	return _release_t >= 0.0


func _process(delta: float) -> void:
	_t += delta
	var spin_mul: float = lerpf(1.0, def.charge_spin_boost, charge)
	_precession = wrapf(_precession + deg_to_rad(def.precession_deg) * spin_mul * delta, 0.0, TAU)
	_ribbon_pivot.basis = Basis(Vector3.BACK, _precession)
	# Las partículas que se arremolinan sólo mientras se está cargando.
	_converge.emitting = _release_t < 0.0 and def.converge_amount > 0 and charge < 0.98
	var flicker: float = 0.9 + 0.1 * sin(_t * 23.0) * sin(_t * 17.0)
	if _release_t < 0.0:
		_light.light_energy = _light_energy() * flicker
		_glow_mat.set_shader_parameter("intensity", _glow_intensity() * flicker)
		return
	_release_t += delta
	var k: float = clampf(_release_t / def.release_time, 0.0, 1.0)
	var ease_out: float = 1.0 - (1.0 - k) * (1.0 - k)
	_body_mat.set_shader_parameter("burst", k)
	_body_mat.set_shader_parameter("fade", 1.0 - k * k)
	_ribbon_pivot.scale = Vector3.ONE * lerpf(1.0, def.release_ring_scale, ease_out)
	for m: ShaderMaterial in _ribbon_mats:
		m.set_shader_parameter("fade", 1.0 - k)
	_ring_mat.set_shader_parameter("progress", k)
	# Destello: el halo se hincha y se apaga.
	var flash: float = (1.0 - k) * (1.0 - k)
	var f: float = def.release_flash
	_glow.scale = Vector3.ONE * _glow_size() * (1.0 + ease_out * 0.8 * f)
	_glow_mat.set_shader_parameter(
		"intensity", _glow_intensity() * (1.0 + 2.5 * flash * f) * (1.0 - k)
	)
	_light.light_energy = _light_energy() * (1.0 + 2.0 * f) * flash
	if k >= 1.0:
		_light.light_energy = 0.0
		_body.visible = false
		_glow.visible = false
		_ribbon_pivot.visible = false
		_ring.visible = false
		# Esperamos a que caigan las chispas antes de apagar el nodo.
		if _release_t >= def.release_time + _sparks.lifetime + _sparks.trail_lifetime:
			_release_t = -1.0
			visible = false
			set_process(false)
			released.emit()


func _scale() -> float:
	return lerpf(def.charge_min_scale, 1.0, charge)


func _glow_size() -> float:
	return def.core_radius * 2.0 * def.glow_scale * _scale()


func _glow_intensity() -> float:
	return def.glow_intensity * lerpf(0.35, 1.0, charge)


func _light_energy() -> float:
	return def.light_energy * lerpf(0.35, 1.0, charge)


func _apply_charge() -> void:
	var s: float = _scale()
	_body.scale = Vector3.ONE * def.core_radius * 2.0 * def.body_scale * s
	_glow.scale = Vector3.ONE * _glow_size()
	_ring.scale = Vector3.ONE * def.core_radius * 2.0 * def.release_ring_scale * 2.0
	_body_mat.set_shader_parameter("charge", charge)
	_glow_mat.set_shader_parameter("intensity", _glow_intensity())
	var spin_mul: float = lerpf(1.0, def.charge_spin_boost, charge)
	for i: int in _ribbons.size():
		var r: MeshInstance3D = _ribbons[i]
		r.scale = Vector3.ONE * float(r.get_meta(&"radius")) * s
		_ribbon_mats[2 * i].set_shader_parameter("speed", _ribbon_base_speed[i] * spin_mul)
		_ribbon_mats[2 * i + 1].set_shader_parameter("speed", _ribbon_base_speed[i] * spin_mul)
	_embers.amount_ratio = lerpf(0.3, 1.0, charge)
	(_embers.process_material as ParticleProcessMaterial).emission_sphere_radius = (
		def.core_radius * s
	)
	_light.light_energy = _light_energy()


func _build_particles() -> void:
	var cols: PackedColorArray = []
	var g: Gradient = def.sparkle_colors
	for i: int in g.get_point_count():
		cols.append(g.get_color(i))
	var dot: float = def.core_radius * 0.35
	_embers = HdFx.embers(def.sparkle_amount, dot, cols)
	_embers.name = "Embers"
	_embers.lifetime = def.sparkle_lifetime
	var epm: ParticleProcessMaterial = _embers.process_material
	epm.gravity = Vector3(0.0, def.sparkle_rise * 4.0, 0.0)
	epm.initial_velocity_min = def.core_radius * 0.5
	epm.initial_velocity_max = def.core_radius * 2.5
	epm.turbulence_noise_scale = def.core_radius * 20.0
	add_child(_embers)
	# Remolino de carga: nacen en una cáscara amplia y caen girando hacia el centro.
	_converge = HdFx.embers(maxi(def.converge_amount, 1), dot * 0.6, cols)
	_converge.name = "Converge"
	_converge.lifetime = 0.6
	_converge.local_coords = true
	var cpm: ParticleProcessMaterial = _converge.process_material
	cpm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE_SURFACE
	cpm.emission_sphere_radius = def.core_radius * 2.4
	cpm.initial_velocity_min = 0.0
	cpm.initial_velocity_max = 0.0
	cpm.gravity = Vector3.ZERO
	cpm.radial_accel_min = -def.core_radius * 22.0
	cpm.radial_accel_max = -def.core_radius * 14.0
	cpm.tangential_accel_min = def.core_radius * 12.0
	cpm.tangential_accel_max = def.core_radius * 20.0
	cpm.turbulence_enabled = false
	_converge.emitting = false
	add_child(_converge)
	_sparks = HdFx.sparks(def.spark_amount, def.burst_speed * 2.5, def.core_radius * 0.18, cols)
	_sparks.name = "Sparks"
	(_sparks.process_material as ParticleProcessMaterial).gravity = Vector3(0, -def.burst_speed, 0)
	(_sparks.process_material as ParticleProcessMaterial).emission_sphere_radius = (
		def.core_radius * 0.5
	)
	(_sparks.draw_pass_1 as RibbonTrailMesh).section_length = def.core_radius * 0.6
	add_child(_sparks)


func _build_ribbons() -> void:
	_ribbon_pivot = Node3D.new()
	_ribbon_pivot.name = "Ribbons"
	add_child(_ribbon_pivot)
	var mesh: ArrayMesh = _build_ring_mesh()
	var rng := RandomNumberGenerator.new()
	rng.seed = def.seed
	var n: int = maxi(def.ribbon_count, 0)
	for i: int in n:
		var ring := MeshInstance3D.new()
		ring.name = "Ribbon%d" % i
		ring.mesh = mesh
		ring.extra_cull_margin = 0.05
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ring.layers = MagicLayer.MAGIC_LAYER
		var f: float = 0.0 if n <= 1 else float(i) / float(n - 1)
		ring.set_meta(&"radius", lerpf(def.ribbon_radius_min, def.ribbon_radius_max, f))
		var tilt: float = deg_to_rad(rng.randf_range(0.45, 1.0) * def.ribbon_tilt_max_deg)
		var roll: float = TAU * float(i) / float(maxi(n, 1)) + rng.randf_range(-0.3, 0.3)
		ring.basis = Basis(Vector3.BACK, roll) * Basis(Vector3.RIGHT, PI * 0.5 - tilt)
		var m := ShaderMaterial.new()
		m.shader = RIBBON_SHADER
		m.render_priority = 4
		var col: Color = (
			def.ribbon_colors[i % def.ribbon_colors.size()]
			if def.ribbon_colors.size() > 0
			else def.light_color
		)
		m.set_shader_parameter("color", col)
		m.set_shader_parameter("hdr", def.ribbon_hdr * 1.6)
		m.set_shader_parameter("dashes", float(def.ribbon_dashes))
		m.set_shader_parameter("tail", def.ribbon_tail)
		m.set_shader_parameter("width", def.ribbon_width)
		m.set_shader_parameter("phase", rng.randf())
		# En HD la animación va fluida (60 fps), no escalonada.
		m.set_shader_parameter("anim_fps", 60.0)
		m.set_shader_parameter("smooth_hd", true)
		var dir: float = 1.0 if i % 2 == 0 else -1.0
		_ribbon_base_speed.append(def.ribbon_speed * lerpf(1.5, 0.8, f) * dir)
		var front: ShaderMaterial = m.duplicate()
		front.render_priority = 6
		front.set_shader_parameter("front", true)
		m.next_pass = front
		ring.material_override = m
		_ribbon_pivot.add_child(ring)
		_ribbons.append(ring)
		_ribbon_mats.append(m)
		_ribbon_mats.append(front)


## Anillo de radio 1 en el plano XZ hecho de pares de vértices en el mismo punto:
## el shader los separa hacia la cámara. NORMAL guarda la tangente; UV.x la posición en la órbita.
func _build_ring_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i: int in RING_SEGMENTS:
		var a0: float = TAU * float(i) / float(RING_SEGMENTS)
		var a1: float = TAU * float(i + 1) / float(RING_SEGMENTS)
		var p0 := Vector3(cos(a0), 0.0, sin(a0))
		var p1 := Vector3(cos(a1), 0.0, sin(a1))
		var t0 := Vector3(-sin(a0), 0.0, cos(a0))
		var t1 := Vector3(-sin(a1), 0.0, cos(a1))
		var u0: float = float(i) / float(RING_SEGMENTS)
		var u1: float = float(i + 1) / float(RING_SEGMENTS)
		_ring_vertex(st, p0, t0, Vector2(u0, 0.0))
		_ring_vertex(st, p1, t1, Vector2(u1, 0.0))
		_ring_vertex(st, p1, t1, Vector2(u1, 1.0))
		_ring_vertex(st, p0, t0, Vector2(u0, 0.0))
		_ring_vertex(st, p1, t1, Vector2(u1, 1.0))
		_ring_vertex(st, p0, t0, Vector2(u0, 1.0))
	return st.commit()


func _ring_vertex(st: SurfaceTool, p: Vector3, tangent: Vector3, uv: Vector2) -> void:
	st.set_normal(tangent)
	st.set_uv(uv)
	st.add_vertex(p)
