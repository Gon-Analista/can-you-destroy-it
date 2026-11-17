class_name Geode
extends Node3D
## Geoda (GDD 6, Manto Geódico): una bolsa de cristales violetas que asoma en la superficie del
## Cristal Madre, brilla y late. Un golpe cerca la revienta (lo decide MotherCrystal) y suelta
## de golpe muchos fragmentos grandes. Se reutiliza: `place()` la pone en otro sitio.

const SHARD_SHADER: Shader = preload("res://crystal/shard.gdshader")

var active: bool = false

var _cluster: MeshInstance3D
var _glow: MeshInstance3D
var _glow_mat: ShaderMaterial
var _light: OmniLight3D
var _sparkles: GPUParticles3D
var _t: float = 0.0
var _pop: float = 0.0


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var st: SurfaceTool = MeshKit.begin()
	for k: int in 7:
		var a: float = TAU * float(k) / 7.0 + rng.randf_range(-0.3, 0.3)
		var axis := (Vector3(cos(a) * 0.6, 1.0, sin(a) * 0.6)).normalized()
		if k == 0:
			axis = Vector3.UP
		var h: float = rng.randf_range(0.35, 0.7) * (1.4 if k == 0 else 1.0)
		MeshKit.add_prism(
			st,
			Vector3(cos(a), 0.0, sin(a)) * 0.15 * float(k > 0),
			axis,
			h * 0.28,
			h,
			h * 0.45,
			6,
			Color.WHITE,
			Color.WHITE,
			rng,
			0.08,
			0.85
		)
	_cluster = MeshInstance3D.new()
	_cluster.name = "Cluster"
	_cluster.mesh = MeshKit.commit(st)
	var m := ShaderMaterial.new()
	m.shader = SHARD_SHADER
	# Paleta violeta y rosa de geoda (el resto del cristal es azul).
	m.set_shader_parameter("col_highlight", Color(1.0, 0.85, 1.0))
	m.set_shader_parameter("col_light", Color(0.86, 0.55, 1.0))
	m.set_shader_parameter("col_mid", Color(0.6, 0.32, 0.9))
	m.set_shader_parameter("col_dark", Color(0.35, 0.15, 0.6))
	_cluster.material_override = m
	_cluster.set_instance_shader_parameter("glint_seed", 0.3)
	add_child(_cluster)
	_glow = HdFx.quad(HdFx.GLOW_SHADER, 3.0, 2)
	_glow.name = "Glow"
	_glow_mat = _glow.material_override
	_glow_mat.set_shader_parameter("color", Color(1.0, 0.45, 1.0))
	_glow_mat.set_shader_parameter("rays", 0.6)
	_glow_mat.set_shader_parameter("ray_count", 6.0)
	_glow.position = Vector3.UP * 0.35
	add_child(_glow)
	_light = OmniLight3D.new()
	_light.light_color = Color(0.85, 0.45, 1.0)
	_light.omni_range = 4.0
	_light.light_energy = 1.2
	_light.shadow_enabled = false
	_light.position = Vector3.UP * 0.5
	add_child(_light)
	_sparkles = HdFx.embers(
		14, 0.08, PackedColorArray([Color(1.8, 1.2, 2.0), Color(1.0, 0.5, 1.6)])
	)
	_sparkles.position = Vector3.UP * 0.4
	(_sparkles.process_material as ParticleProcessMaterial).emission_sphere_radius = 0.5
	_sparkles.emitting = false
	add_child(_sparkles)
	visible = false
	set_process(false)


## Pone la geoda en la superficie, saliendo por `normal`, y la enciende con un pequeño "pop".
func place(at: Vector3, normal: Vector3) -> void:
	global_position = at - normal * 0.1
	var up: Vector3 = normal.normalized()
	var side: Vector3 = up.cross(Vector3.UP if absf(up.y) < 0.95 else Vector3.RIGHT).normalized()
	global_basis = Basis(side, up, side.cross(up)).orthonormalized()
	active = true
	visible = true
	_pop = 1.0
	_sparkles.emitting = true
	set_process(true)


## Revienta: se apaga (el estallido y los fragmentos los pone MotherCrystal).
func break_open() -> void:
	active = false
	visible = false
	_sparkles.emitting = false
	set_process(false)


func _process(delta: float) -> void:
	_t += delta
	_pop = maxf(0.0, _pop - delta * 2.0)
	# Late como un corazón: llama la atención sin gritar.
	var beat: float = pow(maxf(0.0, sin(_t * 2.4)), 6.0)
	_cluster.scale = Vector3.ONE * (1.0 + beat * 0.06 + _pop * 0.4)
	_glow_mat.set_shader_parameter("intensity", 0.35 + beat * 0.5 + _pop)
	_light.light_energy = 1.0 + beat * 1.5
