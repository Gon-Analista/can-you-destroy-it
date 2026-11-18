class_name RankAura
extends Node3D
## La subida de rango alrededor del mago (capa de magia HD): una columna de luz con los colores del
## rango que sube al cielo y lo envuelve, un círculo mágico que se dibuja en el suelo a sus pies y
## gira, motas que suben en espiral y una luz que baña el valle cercano. Sigue al mago mientras
## dura (`DURATION`). Se crea una vez (RankCeremony) y se reutiliza.

const PILLAR_SHADER: Shader = preload("res://pylon/pylon_pillar.gdshader")
const CIRCLE_SHADER: Shader = preload("res://fx/hd/hd_magic_circle.gdshader")
const HEIGHT: float = 90.0
const RADIUS: float = 1.7
const DURATION: float = 4.6

## El mago (el aura va a sus pies).
var target: Node3D

var _t: float = -1.0
var _pillar: MeshInstance3D
var _pillar_mat: ShaderMaterial
var _circle: MeshInstance3D
var _circle_mat: ShaderMaterial
var _embers: GPUParticles3D
var _burst: GPUParticles3D
var _light: OmniLight3D


func _ready() -> void:
	top_level = true
	_build()
	visible = false
	set_process(false)


## Enciende el aura con los colores de `def`.
func play(def: RankDef) -> void:
	_pillar_mat.set_shader_parameter("color_core", def.color_light)
	_pillar_mat.set_shader_parameter("color_edge", def.color)
	_pillar_mat.set_shader_parameter("color_top", def.color_light.lerp(Color.WHITE, 0.4))
	_circle_mat.set_shader_parameter("color", def.color)
	_circle_mat.set_shader_parameter("color_hot", def.color_light)
	_circle_mat.set_shader_parameter("rune_seed", float(def.emblem) + 3.0)
	var ramp: PackedColorArray = [
		Color(def.color_light * 2.0, 1.0), Color(def.color * 1.6, 1.0), Color(def.color, 1.0)
	]
	for p: GPUParticles3D in [_embers, _burst]:
		(p.process_material as ParticleProcessMaterial).color_ramp = HdFx.color_ramp(ramp)
	_light.light_color = def.color_light
	_t = 0.0
	visible = true
	_follow()
	_embers.restart()
	_burst.restart()
	set_process(true)


func is_playing() -> bool:
	return _t >= 0.0


func _process(delta: float) -> void:
	_t += delta
	_follow()
	var k: float = _t / DURATION
	# La columna sube de golpe y se apaga despacio; el círculo se dibuja, gira y se desvanece.
	var rise: float = clampf(_t / 0.35, 0.0, 1.0)
	var fade: float = 1.0 - smoothstep(0.55, 1.0, k)
	_pillar_mat.set_shader_parameter("reach", rise)
	_pillar_mat.set_shader_parameter("intensity", (0.55 + 0.45 * (1.0 - rise)) * fade)
	_pillar.scale = Vector3(1.0 + 0.6 * (1.0 - rise), 1.0, 1.0 + 0.6 * (1.0 - rise))
	_circle_mat.set_shader_parameter("appear", clampf(_t / 0.6, 0.0, 1.0))
	_circle_mat.set_shader_parameter("spin", _t * 0.9)
	_circle_mat.set_shader_parameter("flash", maxf(0.0, 1.0 - _t * 2.0))
	_circle_mat.set_shader_parameter("fade", fade)
	_circle.scale = Vector3.ONE * (0.6 + 0.4 * (1.0 - pow(1.0 - clampf(_t / 0.5, 0.0, 1.0), 3.0)))
	_light.light_energy = (6.0 * maxf(0.0, 1.0 - _t * 1.5) + 2.0) * fade * HdFx.flash_scale
	if k >= 1.0:
		_t = -1.0
		visible = false
		set_process(false)


func _follow() -> void:
	if target and is_instance_valid(target):
		global_position = target.global_position


func _build() -> void:
	var cyl := CylinderMesh.new()
	cyl.top_radius = RADIUS * 1.6
	cyl.bottom_radius = RADIUS
	cyl.height = HEIGHT
	cyl.radial_segments = 20
	cyl.rings = 1
	cyl.cap_top = false
	cyl.cap_bottom = false
	_pillar = MeshInstance3D.new()
	_pillar.name = "Pillar"
	_pillar.mesh = cyl
	_pillar_mat = ShaderMaterial.new()
	_pillar_mat.shader = PILLAR_SHADER
	_pillar_mat.render_priority = 3
	_pillar_mat.set_shader_parameter("height", HEIGHT)
	_pillar.material_override = _pillar_mat
	_pillar.layers = MagicLayer.MAGIC_LAYER
	_pillar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_pillar.position.y = HEIGHT * 0.5 - 0.2
	add_child(_pillar)
	_circle = HdFx.quad(CIRCLE_SHADER, 5.2, 4)
	_circle.name = "Circle"
	_circle_mat = _circle.material_override
	_circle_mat.set_shader_parameter("intensity", 1.6)
	_circle_mat.set_shader_parameter("rune_count", 14.0)
	_circle.rotation.x = -PI * 0.5
	_circle.position.y = 0.08
	add_child(_circle)
	_embers = HdFx.embers(80, 0.16, PackedColorArray([Color.WHITE, Color.WHITE]))
	_embers.name = "Motes"
	_embers.one_shot = true
	_embers.explosiveness = 0.15
	_embers.lifetime = 3.2
	var pm: ParticleProcessMaterial = _embers.process_material
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	pm.emission_ring_axis = Vector3.UP
	pm.emission_ring_radius = RADIUS * 1.1
	pm.emission_ring_inner_radius = RADIUS * 0.7
	pm.emission_ring_height = 0.4
	pm.direction = Vector3.UP
	pm.spread = 8.0
	pm.initial_velocity_min = 2.0
	pm.initial_velocity_max = 6.0
	pm.orbit_velocity_min = 0.25
	pm.orbit_velocity_max = 0.45
	pm.gravity = Vector3(0.0, 1.2, 0.0)
	_embers.position.y = 0.2
	add_child(_embers)
	_burst = HdFx.embers(48, 0.22, PackedColorArray([Color.WHITE, Color.WHITE]))
	_burst.name = "Burst"
	_burst.one_shot = true
	_burst.explosiveness = 0.95
	_burst.lifetime = 1.4
	var bm: ParticleProcessMaterial = _burst.process_material
	bm.emission_sphere_radius = 0.6
	bm.direction = Vector3.UP
	bm.spread = 75.0
	bm.initial_velocity_min = 4.0
	bm.initial_velocity_max = 9.0
	bm.damping_min = 3.0
	bm.damping_max = 5.0
	bm.gravity = Vector3(0.0, -2.0, 0.0)
	_burst.position.y = 1.0
	add_child(_burst)
	_light = OmniLight3D.new()
	_light.name = "Light"
	_light.omni_range = 14.0
	_light.shadow_enabled = false
	_light.position.y = 2.5
	add_child(_light)
