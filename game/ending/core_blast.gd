class_name CoreBlast
extends Node3D
## El Núcleo estalla (GDD 9): un destello blanco y violeta enorme que crece y se apaga, dos ondas
## de choque, una luz que baña todo el valle y lo que quedaba del cristal deshecho en una lluvia de
## fragmentos brillantes (pixel art en el mundo y chispas HD por encima). Todo se crea una vez.

const GLOW_SHADER: Shader = preload("res://fx/hd/hd_glow.gdshader")
const RING_SHADER: Shader = preload("res://fx/hd/hd_ring.gdshader")
const TOON_SHADER: Shader = preload("res://fx/toon.gdshader")
const LIFE_SEC: float = 6.0

var _flash: MeshInstance3D
var _flash_mat: ShaderMaterial
var _rings: Array[MeshInstance3D] = []
var _ring_mats: Array[ShaderMaterial] = []
var _light: OmniLight3D
var _rain: GPUParticles3D
var _sparks: GPUParticles3D
var _motes: GPUParticles3D
var _t: float = -1.0


func _ready() -> void:
	_flash = HdFx.quad(GLOW_SHADER, 1.0, 5)
	_flash.name = "Flash"
	_flash_mat = _flash.material_override
	_flash_mat.set_shader_parameter("color", Color(1.0, 0.85, 1.0))
	_flash_mat.set_shader_parameter("rays", 1.0)
	_flash_mat.set_shader_parameter("ray_count", 12.0)
	_flash_mat.set_shader_parameter("falloff", 1.8)
	_flash_mat.set_shader_parameter("cover", 0.35)
	_flash.visible = false
	add_child(_flash)
	for i: int in 2:
		var ring: MeshInstance3D = HdFx.quad(RING_SHADER, 1.0, 4)
		ring.name = "Shockwave%d" % i
		var m: ShaderMaterial = ring.material_override
		m.set_shader_parameter("color", Color(0.95, 0.7, 1.0) if i == 0 else Color(0.6, 0.9, 1.0))
		m.set_shader_parameter("cover", 0.2)
		ring.visible = false
		add_child(ring)
		_rings.append(ring)
		_ring_mats.append(m)
	_light = OmniLight3D.new()
	_light.name = "BlastLight"
	_light.light_color = Color(0.92, 0.8, 1.0)
	_light.omni_range = 140.0
	_light.shadow_enabled = false
	_light.visible = false
	add_child(_light)
	_build_rain()
	_sparks = HdFx.sparks(
		160,
		42.0,
		0.35,
		PackedColorArray([Color(2.6, 2.5, 2.8), Color(1.6, 1.0, 2.4), Color(0.6, 1.4, 2.2)])
	)
	_sparks.name = "BlastSparks"
	_sparks.lifetime = 2.4
	_sparks.visibility_aabb = AABB(Vector3(-150, -40, -150), Vector3(300, 220, 300))
	var spm: ParticleProcessMaterial = _sparks.process_material
	spm.emission_sphere_radius = 5.0
	spm.gravity = Vector3(0, -6.0, 0)
	spm.damping_min = 4.0
	spm.damping_max = 10.0
	add_child(_sparks)
	_motes = HdFx.embers(
		220, 0.9, PackedColorArray([Color(2.2, 2.0, 2.4), Color(1.4, 0.7, 2.2), Color(0.5, 1.2, 2)])
	)
	_motes.name = "BlastMotes"
	_motes.one_shot = true
	_motes.explosiveness = 0.85
	_motes.lifetime = 5.0
	_motes.emitting = false
	_motes.visibility_aabb = AABB(Vector3(-150, -40, -150), Vector3(300, 220, 300))
	var mpm: ParticleProcessMaterial = _motes.process_material
	mpm.emission_sphere_radius = 8.0
	mpm.initial_velocity_min = 6.0
	mpm.initial_velocity_max = 22.0
	mpm.gravity = Vector3(0, -2.5, 0)
	add_child(_motes)
	set_process(false)


## Fragmentos de cristal que salen disparados y llueven sobre el claro, brillando.
func _build_rain() -> void:
	var st: SurfaceTool = MeshKit.begin()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	MeshKit.add_prism(
		st,
		Vector3(0, -0.4, 0),
		Vector3.UP,
		0.22,
		0.55,
		0.3,
		5,
		Color("#8fd8ff"),
		Color("#f2d6ff"),
		rng,
		0.3
	)
	var mat := ShaderMaterial.new()
	mat.shader = TOON_SHADER
	mat.set_shader_parameter("self_light", 1.4)
	mat.set_shader_parameter("rim", 0.5)
	mat.set_shader_parameter("rim_color", Color(1.0, 0.85, 1.0))
	var mesh: ArrayMesh = MeshKit.commit(st)
	mesh.surface_set_material(0, mat)
	_rain = GPUParticles3D.new()
	_rain.name = "ShardRain"
	_rain.amount = 300
	_rain.lifetime = LIFE_SEC
	_rain.one_shot = true
	_rain.explosiveness = 0.9
	_rain.emitting = false
	_rain.local_coords = false
	_rain.draw_pass_1 = mesh
	_rain.visibility_aabb = AABB(Vector3(-150, -40, -150), Vector3(300, 220, 300))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 6.0
	pm.direction = Vector3.UP
	pm.spread = 70.0
	pm.initial_velocity_min = 14.0
	pm.initial_velocity_max = 40.0
	pm.gravity = Vector3(0, -13.0, 0)
	pm.damping_min = 0.1
	pm.damping_max = 0.6
	pm.particle_flag_rotate_y = true
	pm.angular_velocity_min = -360.0
	pm.angular_velocity_max = 360.0
	pm.scale_min = 0.5
	pm.scale_max = 2.4
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(0.75, 1.0))
	curve.add_point(Vector2(1.0, 0.0))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.scale_curve = ct
	_rain.process_material = pm
	add_child(_rain)


## Estalla en `at` (el centro del Núcleo).
func play(at: Vector3) -> void:
	global_position = at
	_t = 0.0
	_flash.visible = true
	_light.visible = true
	for r: MeshInstance3D in _rings:
		r.visible = true
	_rain.restart()
	_sparks.restart()
	_motes.restart()
	set_process(true)


## Pantalla de carga: un fotograma de cada pieza para compilar sus shaders.
func warm_up(at: Vector3) -> void:
	play(at)
	_t = LIFE_SEC - 0.2


func _process(delta: float) -> void:
	if _t < 0.0:
		return
	_t += delta
	var fs: float = HdFx.flash_scale
	# Destello: crece deprisa, se queda un instante y se apaga.
	var grow: float = 1.0 - pow(1.0 - clampf(_t / 0.35, 0.0, 1.0), 3.0)
	var fade: float = 1.0 - smoothstep(0.25, 2.2, _t)
	# Grande pero sin fundir la pantalla entera a blanco (antes, medio segundo todo blanco).
	_flash.scale = Vector3.ONE * lerpf(12.0, 64.0, grow)
	_flash_mat.set_shader_parameter("intensity", (1.2 * fade + 0.2 * fade * fade) * fs)
	for i: int in _rings.size():
		var k: float = clampf((_t - 0.12 * i) / (1.6 + 0.6 * i), 0.0, 1.0)
		_rings[i].scale = Vector3.ONE * lerpf(20.0, 260.0 + 80.0 * i, k)
		_ring_mats[i].set_shader_parameter("progress", k)
		_ring_mats[i].set_shader_parameter("intensity", 1.8 * fs)
		_rings[i].visible = k < 1.0
	_light.light_energy = 18.0 * fade * fade
	if _t >= LIFE_SEC:
		_t = -1.0
		_flash.visible = false
		_light.visible = false
		set_process(false)
