class_name SpellOrb
extends Node3D
## Orbe de un hechizo como pila de capas, todo configurado por un `SpellVisualDef`:
## 1. Núcleo: espiral en bandas + destello en cruz + halo tramado (`spell_core.gdshader`).
## 2. Cintas: órbitas con cometas que pasan por delante y por detrás (`spell_ribbon.gdshader`).
## 3. Destellos: estrellas pixel que parpadean (flipbook) alrededor del orbe.
## 4. Luz: tiñe de color lo que hay cerca (las manos), en bandas gracias al shader toon.
## Se coloca donde haga falta (entre las manos, en una palma, como proyectil) y se controla con
## `charge` (0..1), `appear()` y `release()`. Todo se crea una vez; nada se instancia en caliente.

signal released

const CORE_SHADER: Shader = preload("res://spells/vfx/spell_core.gdshader")
const RIBBON_SHADER: Shader = preload("res://spells/vfx/spell_ribbon.gdshader")
const TWINKLE: Texture2D = preload("res://fx/textures/particle_twinkle.png")
const TWINKLE_FRAMES: int = 7
const RING_SEGMENTS: int = 72

@export var def: SpellVisualDef
## 0..1. Con carga baja el orbe es pequeño y gira lento; con carga completa, a tope.
@export_range(0.0, 1.0) var charge: float = 1.0:
	set(value):
		charge = clampf(value, 0.0, 1.0)
		if is_node_ready():
			_apply_charge()

var _core: MeshInstance3D
var _core_mat: ShaderMaterial
var _ribbon_pivot: Node3D
var _ribbons: Array[MeshInstance3D] = []
## Dos materiales por cinta: [2 i] mitad trasera, [2 i + 1] mitad delantera (next_pass).
var _ribbon_mats: Array[ShaderMaterial] = []
var _ribbon_base_speed: PackedFloat32Array = []
var _sparkles: GPUParticles3D
var _burst: GPUParticles3D
var _light: OmniLight3D
var _release_t: float = -1.0
var _precession: float = 0.0
var _step_acc: float = 0.0
var _flicker: float = 1.0


func _ready() -> void:
	assert(def != null, "SpellOrb necesita un SpellVisualDef")
	_build_core()
	_build_ribbons()
	_build_sparkles()
	_build_light()
	_apply_charge()


## Vuelve a mostrar el orbe tras un `release()`.
func appear() -> void:
	_release_t = -1.0
	visible = true
	# Si el estallido se corta antes de terminar, el núcleo y las cintas siguen ocultos.
	_core.visible = true
	_ribbon_pivot.visible = true
	_sparkles.emitting = true
	_ribbon_pivot.scale = Vector3.ONE
	_core_mat.set_shader_parameter("burst", 0.0)
	for m: ShaderMaterial in _ribbon_mats:
		m.set_shader_parameter("fade", 1.0)
	_apply_charge()
	set_process(true)


## Estallido: el centro destella y se apaga, las órbitas se abren y se desvanecen
## y salta una lluvia de destellos. Emite `released` al terminar.
func release() -> void:
	if _release_t >= 0.0:
		return
	_release_t = 0.0
	_sparkles.emitting = false
	_burst.amount_ratio = lerpf(0.4, 1.0, charge)
	_burst.restart()
	set_process(true)


func is_releasing() -> bool:
	return _release_t >= 0.0


func _process(delta: float) -> void:
	# Animación escalonada a `anim_fps`, igual que los shaders.
	_step_acc += delta
	var step: float = 1.0 / def.anim_fps
	if _step_acc < step:
		return
	var dt: float = _step_acc
	_step_acc = 0.0
	var spin_mul: float = lerpf(1.0, def.charge_spin_boost, charge)
	_precession = wrapf(_precession + deg_to_rad(def.precession_deg) * spin_mul * dt, 0.0, TAU)
	# Sólo alrededor del eje de la vista: las elipses giran como un remolino sin ponerse de canto.
	_ribbon_pivot.basis = Basis(Vector3.BACK, _precession)
	_flicker = 0.85 + randf() * 0.3
	if _release_t < 0.0:
		_light.light_energy = _light_energy() * _flicker
		return
	_release_t += dt
	var k: float = clampf(_release_t / def.release_time, 0.0, 1.0)
	var ease_out: float = 1.0 - (1.0 - k) * (1.0 - k)
	_core_mat.set_shader_parameter("burst", k)
	_ribbon_pivot.scale = Vector3.ONE * lerpf(1.0, def.release_ring_scale, ease_out)
	for m: ShaderMaterial in _ribbon_mats:
		m.set_shader_parameter("fade", 1.0 - k)
	# Flash de luz al soltar y luego se apaga.
	_light.light_energy = _light_energy() * (2.5 * (1.0 - k))
	if k >= 1.0:
		_light.light_energy = 0.0
		_core.visible = false
		_ribbon_pivot.visible = false
		# Esperamos a que caigan los destellos del estallido antes de apagar el nodo.
		if _release_t >= def.release_time + def.sparkle_lifetime:
			_release_t = -1.0
			visible = false
			_core.visible = true
			_ribbon_pivot.visible = true
			set_process(false)
			released.emit()


func _light_energy() -> float:
	return def.light_energy * lerpf(0.35, 1.0, charge)


func _apply_charge() -> void:
	var s: float = lerpf(def.charge_min_scale, 1.0, charge)
	_core.scale = Vector3.ONE * def.core_radius * 2.0 * s
	_core_mat.set_shader_parameter("charge", charge)
	var spin_mul: float = lerpf(1.0, def.charge_spin_boost, charge)
	for i: int in _ribbons.size():
		var r: MeshInstance3D = _ribbons[i]
		r.scale = Vector3.ONE * float(r.get_meta(&"radius")) * s
		_ribbon_mats[2 * i].set_shader_parameter("speed", _ribbon_base_speed[i] * spin_mul)
		_ribbon_mats[2 * i + 1].set_shader_parameter("speed", _ribbon_base_speed[i] * spin_mul)
	_sparkles.amount_ratio = lerpf(0.3, 1.0, charge)
	(_sparkles.process_material as ParticleProcessMaterial).emission_sphere_radius = (
		def.sparkle_radius * s
	)
	_light.light_energy = _light_energy()


func _build_core() -> void:
	_core = MeshInstance3D.new()
	_core.name = "Core"
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	_core.mesh = q
	_core_mat = ShaderMaterial.new()
	_core_mat.shader = CORE_SHADER
	_core_mat.render_priority = 5
	var ramp := GradientTexture1D.new()
	ramp.gradient = def.core_ramp
	ramp.use_hdr = true
	ramp.width = 128
	_core_mat.set_shader_parameter("ramp", ramp)
	_core_mat.set_shader_parameter("arms", def.core_arms)
	_core_mat.set_shader_parameter("twist", def.core_twist)
	_core_mat.set_shader_parameter("spin", def.core_spin)
	_core_mat.set_shader_parameter("swirl", def.core_swirl)
	_core_mat.set_shader_parameter("flare_length", def.flare_length)
	_core_mat.set_shader_parameter("flare_color", def.flare_color)
	_core_mat.set_shader_parameter("anim_fps", def.anim_fps)
	_core_mat.set_shader_parameter("spin_boost", def.charge_spin_boost)
	_core_mat.set_shader_parameter("seed", float(def.seed) * 1.37)
	_core.material_override = _core_mat
	_core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_core)


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
		# El ancho de la cinta se añade en el shader: margen para que no la recorte el culling.
		ring.extra_cull_margin = 0.05
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var f: float = 0.0 if n <= 1 else float(i) / float(n - 1)
		ring.set_meta(&"radius", lerpf(def.ribbon_radius_min, def.ribbon_radius_max, f))
		# Órbitas repartidas: cada una inclinada distinto alrededor de la dirección de la cámara.
		var tilt: float = deg_to_rad(rng.randf_range(0.45, 1.0) * def.ribbon_tilt_max_deg)
		var roll: float = TAU * float(i) / float(maxi(n, 1)) + rng.randf_range(-0.3, 0.3)
		ring.basis = Basis(Vector3.BACK, roll) * Basis(Vector3.RIGHT, PI * 0.5 - tilt)
		var m := ShaderMaterial.new()
		m.shader = RIBBON_SHADER
		# Mitad trasera antes del núcleo (5); la delantera, después.
		m.render_priority = 4
		var col: Color = (
			def.ribbon_colors[i % def.ribbon_colors.size()]
			if def.ribbon_colors.size() > 0
			else def.light_color
		)
		m.set_shader_parameter("color", col)
		m.set_shader_parameter("hdr", def.ribbon_hdr)
		m.set_shader_parameter("dashes", float(def.ribbon_dashes))
		m.set_shader_parameter("tail", def.ribbon_tail)
		m.set_shader_parameter("width", def.ribbon_width)
		m.set_shader_parameter("phase", rng.randf())
		m.set_shader_parameter("anim_fps", def.anim_fps)
		# Las órbitas interiores giran más rápido (como un remolino); alternan sentido.
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


func _build_sparkles() -> void:
	var draw := StandardMaterial3D.new()
	draw.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	draw.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	draw.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	draw.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	draw.particles_anim_h_frames = TWINKLE_FRAMES
	draw.particles_anim_v_frames = 1
	draw.particles_anim_loop = false
	draw.vertex_color_use_as_albedo = true
	draw.albedo_texture = TWINKLE
	draw.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	draw.disable_fog = true
	draw.render_priority = 7
	var quad := QuadMesh.new()
	# 9 texels por frame, 1 texel ≈ 1 píxel: sin escalado aleatorio para no crear mixels.
	quad.size = Vector2.ONE * def.sparkle_texel * 9.0
	quad.material = draw

	var colors := GradientTexture1D.new()
	colors.gradient = def.sparkle_colors
	colors.use_hdr = true

	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE_SURFACE
	pm.emission_sphere_radius = def.sparkle_radius
	pm.direction = Vector3.UP
	pm.spread = 180.0
	pm.initial_velocity_min = 0.01
	pm.initial_velocity_max = 0.05
	pm.gravity = Vector3(0.0, def.sparkle_rise, 0.0)
	pm.anim_speed_min = 1.0
	pm.anim_speed_max = 1.0
	pm.color_initial_ramp = colors
	_sparkles = GPUParticles3D.new()
	_sparkles.name = "Sparkles"
	_sparkles.amount = maxi(def.sparkle_amount, 1)
	_sparkles.lifetime = def.sparkle_lifetime
	_sparkles.randomness = 0.5
	_sparkles.local_coords = true
	_sparkles.process_material = pm
	_sparkles.draw_pass_1 = quad
	_sparkles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_sparkles.visibility_aabb = AABB(Vector3.ONE * -1.0, Vector3.ONE * 2.0)
	_sparkles.fixed_fps = int(def.anim_fps)
	_sparkles.interpolate = false
	add_child(_sparkles)

	var bm := ParticleProcessMaterial.new()
	bm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	bm.emission_sphere_radius = def.core_radius * 0.5
	bm.direction = Vector3.FORWARD
	bm.spread = 180.0
	bm.initial_velocity_min = def.burst_speed * 0.4
	bm.initial_velocity_max = def.burst_speed
	bm.damping_min = def.burst_speed * 1.5
	bm.damping_max = def.burst_speed * 2.5
	bm.gravity = Vector3(0.0, -0.4, 0.0)
	bm.anim_speed_min = 1.0
	bm.anim_speed_max = 1.0
	bm.color_initial_ramp = colors
	_burst = GPUParticles3D.new()
	_burst.name = "Burst"
	_burst.amount = maxi(def.burst_amount, 1)
	_burst.lifetime = def.sparkle_lifetime
	_burst.one_shot = true
	_burst.explosiveness = 0.9
	_burst.emitting = false
	_burst.local_coords = false
	_burst.process_material = bm
	_burst.draw_pass_1 = quad
	_burst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_burst.visibility_aabb = AABB(Vector3.ONE * -2.0, Vector3.ONE * 4.0)
	_burst.fixed_fps = int(def.anim_fps)
	_burst.interpolate = false
	add_child(_burst)


func _build_light() -> void:
	_light = OmniLight3D.new()
	_light.name = "Light"
	_light.light_color = def.light_color
	_light.omni_range = def.light_range
	_light.omni_attenuation = 1.4
	_light.shadow_enabled = false
	add_child(_light)
