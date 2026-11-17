class_name HdImpact
extends Node3D
## Impacto de un hechizo en la capa de magia HD (pool, nada se instancia en caliente):
## destello con rayos, bola de fuego que se hincha y se deshace en llamas, onda de choque,
## chispas con estela, brasas y humo que sube. Colores de la estela del hechizo; tamaño según
## el radio de grieta del nivel (un golpe resonante o una Bola de Fuego, mucho más).

const DURATION: float = 0.55

@export var pool_size: int = 8

var _slots: Array[Node3D] = []
var _fire: Array[ShaderMaterial] = []
var _fire_mi: Array[MeshInstance3D] = []
var _flash: Array[ShaderMaterial] = []
var _flash_mi: Array[MeshInstance3D] = []
var _ring: Array[ShaderMaterial] = []
var _sparks: Array[GPUParticles3D] = []
var _embers: Array[GPUParticles3D] = []
var _smoke: Array[GPUParticles3D] = []
var _age: PackedFloat32Array = []
var _size: PackedFloat32Array = []
var _peak: PackedFloat32Array = []
var _next: int = 0
var _default_ramp: Gradient


func _ready() -> void:
	_default_ramp = Gradient.new()
	_default_ramp.offsets = PackedFloat32Array([0.0, 0.3, 0.6, 1.0])
	_default_ramp.colors = PackedColorArray(
		[Color(2.0, 2.0, 2.0), Color("#c9f6ff"), Color("#458fb8"), Color(0.16, 0.29, 0.53, 0.0)]
	)
	for i: int in pool_size:
		var slot := Node3D.new()
		slot.name = "Impact%d" % i
		slot.top_level = true
		add_child(slot)
		var flash: MeshInstance3D = HdFx.quad(HdFx.GLOW_SHADER, 1.0, 3)
		slot.add_child(flash)
		var fire: MeshInstance3D = HdFx.quad(HdFx.FIRE_SHADER, 1.0, 5)
		slot.add_child(fire)
		var ring: MeshInstance3D = HdFx.quad(HdFx.RING_SHADER, 1.0, 8)
		slot.add_child(ring)
		var sparks: GPUParticles3D = HdFx.sparks(
			60, 9.0, 0.05, PackedColorArray([Color(2, 1.8, 1.2), Color(1, 0.5, 0.2)])
		)
		slot.add_child(sparks)
		var embers: GPUParticles3D = HdFx.embers(
			40, 0.14, PackedColorArray([Color(2, 1.6, 1.0), Color(1, 0.4, 0.15)])
		)
		embers.one_shot = true
		embers.explosiveness = 0.9
		embers.emitting = false
		embers.lifetime = 1.2
		var epm: ParticleProcessMaterial = embers.process_material
		epm.initial_velocity_min = 1.0
		epm.initial_velocity_max = 4.0
		epm.emission_sphere_radius = 0.6
		slot.add_child(embers)
		var smoke: GPUParticles3D = HdFx.smoke(14, 2.2, Color(0.32, 0.24, 0.36))
		slot.add_child(smoke)
		_slots.append(slot)
		_fire.append(fire.material_override as ShaderMaterial)
		_fire_mi.append(fire)
		_flash.append(flash.material_override as ShaderMaterial)
		_flash_mi.append(flash)
		_ring.append(ring.material_override as ShaderMaterial)
		_sparks.append(sparks)
		_embers.append(embers)
		_smoke.append(smoke)
		_age.append(-1.0)
		_size.append(1.0)
		_peak.append(1.0)
		slot.visible = false
	set_process(false)


func play(
	pos: Vector3, normal: Vector3, tier: SpellTier, resonant: bool, big: bool = false
) -> void:
	var i: int = _next
	_next = (_next + 1) % pool_size
	var slot: Node3D = _slots[i]
	var cam: Camera3D = get_viewport().get_camera_3d()
	var toward: Vector3 = (cam.global_position - pos).normalized() if cam else normal
	slot.global_position = pos + normal * 0.3 + toward * 0.6
	slot.visible = true
	var size: float = tier.crack_radius * 2.6 * (1.6 if resonant else 1.0) * (1.4 if big else 1.0)
	_size[i] = size
	_peak[i] = 0.7 + (0.6 if resonant else 0.0) - (0.3 if big else 0.0)
	var ramp: Gradient = tier.trail_ramp if tier.trail_ramp else _default_ramp
	var glow: Color = Color("#ffd27a") if resonant else tier.color_glow
	_fire[i].set_shader_parameter("ramp", HdFx.smooth_ramp(ramp))
	_fire[i].set_shader_parameter("seed", randf() * 10.0)
	_fire[i].set_shader_parameter("style", 0)
	_fire[i].set_shader_parameter("turbulence", 0.5)
	_fire[i].set_shader_parameter("intensity", 1.15)
	_flash[i].set_shader_parameter("color", glow)
	_flash[i].set_shader_parameter("rays", 1.0)
	_flash[i].set_shader_parameter("ray_count", 8.0)
	_flash[i].set_shader_parameter("seed", randf() * 10.0)
	_ring[i].set_shader_parameter("color", glow)
	_ring[i].set_shader_parameter("seed", randf() * 10.0)
	var cols := PackedColorArray([tier.color_core * 2.2, glow * 1.5])
	(_sparks[i].process_material as ParticleProcessMaterial).color_ramp = HdFx.color_ramp(cols)
	(_embers[i].process_material as ParticleProcessMaterial).color_ramp = HdFx.color_ramp(cols)
	var power: float = clampf(size / 3.0, 0.4, 3.0)
	_sparks[i].amount_ratio = clampf(power * 0.5, 0.25, 1.0)
	var spm: ParticleProcessMaterial = _sparks[i].process_material
	spm.initial_velocity_max = 6.0 + power * 5.0
	spm.emission_sphere_radius = size * 0.15
	_sparks[i].restart()
	_embers[i].amount_ratio = clampf(power * 0.4, 0.2, 1.0)
	_embers[i].restart()
	_smoke[i].amount_ratio = clampf(power * 0.35, 0.15, 1.0)
	(_smoke[i].draw_pass_1 as QuadMesh).size = Vector2.ONE * size * 0.7
	_smoke[i].restart()
	_age[i] = 0.0
	_animate(i)
	set_process(true)


func _process(delta: float) -> void:
	var any: bool = false
	for i: int in pool_size:
		if _age[i] < 0.0:
			continue
		_age[i] += delta
		_animate(i)
		if _age[i] > 2.0:
			_age[i] = -1.0
			_slots[i].visible = false
		else:
			any = true
	if not any:
		set_process(false)


func _animate(i: int) -> void:
	var k: float = clampf(_age[i] / DURATION, 0.0, 1.0)
	var e: float = 1.0 - pow(1.0 - k, 3.0)
	var s: float = _size[i]
	_fire_mi[i].visible = k < 1.0
	_fire_mi[i].scale = Vector3.ONE * s * lerpf(0.4, 1.1, e)
	_fire[i].set_shader_parameter("burst", k)
	_fire[i].set_shader_parameter("fade", 1.0 - k * k)
	_fire[i].set_shader_parameter("charge", 1.0)
	var fk: float = clampf(_age[i] / 0.3, 0.0, 1.0)
	_flash_mi[i].visible = fk < 1.0
	_flash_mi[i].scale = Vector3.ONE * s * lerpf(0.9, 1.7, fk)
	_flash[i].set_shader_parameter("intensity", _peak[i] * (1.0 - fk) * (1.0 - fk))
	_ring[i].set_shader_parameter("progress", k)
	_slots[i].get_child(2).set(&"scale", Vector3.ONE * s * 2.4)
	_slots[i].get_child(2).set(&"visible", k < 1.0)
