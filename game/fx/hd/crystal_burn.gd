class_name CrystalBurn
extends Node3D
## Fuego que sigue ardiendo sobre el Cristal Madre tras una Bola de Fuego (capa de magia HD):
## lenguas de fuego que suben, brasas y humo, con un crepitar en 3D. Mientras arde, quema:
## cada `tick` hace daño y, de vez en cuando, suelta una astilla. Pool fijo de focos.

signal burned(damage: int, at: Vector3)

const SLOTS: int = 6
const FLAMES_PER_SLOT: int = 3
const CRACKLE_SFX: AudioStream = preload("res://audio/sfx/sfx_fireball_charge_loop.ogg")

var _roots: Array[Node3D] = []
var _flames: Array[Array] = []
var _embers: Array[GPUParticles3D] = []
var _smoke: Array[GPUParticles3D] = []
var _audio: Array[AudioStreamPlayer3D] = []
var _left: PackedFloat32Array = []
var _total: PackedFloat32Array = []
var _tick: PackedFloat32Array = []
var _tick_sec: PackedFloat32Array = []
var _damage: PackedInt32Array = []
var _size: PackedFloat32Array = []
var _next: int = 0
var _ramp: Gradient


func _ready() -> void:
	_ramp = Gradient.new()
	_ramp.offsets = PackedFloat32Array([0.0, 0.2, 0.45, 0.72, 1.0])
	_ramp.colors = PackedColorArray(
		[
			Color(2.2, 1.9, 1.3),
			Color(1.5, 0.85, 0.22),
			Color(1.15, 0.42, 0.07),
			Color(0.8, 0.17, 0.04),
			Color(0.45, 0.07, 0.03)
		]
	)
	for i: int in SLOTS:
		var root := Node3D.new()
		root.name = "Burn%d" % i
		root.top_level = true
		root.visible = false
		add_child(root)
		_roots.append(root)
		var flames: Array[MeshInstance3D] = []
		for k: int in FLAMES_PER_SLOT:
			var f: MeshInstance3D = HdFx.quad(HdFx.FIRE_SHADER, 1.0, 5)
			var m: ShaderMaterial = f.material_override
			m.set_shader_parameter("ramp", HdFx.smooth_ramp(_ramp))
			m.set_shader_parameter("seed", randf() * 10.0)
			m.set_shader_parameter("intensity", 1.2)
			m.set_shader_parameter("turbulence", 0.55)
			m.set_shader_parameter("flow_strength", 2.2)
			m.set_shader_parameter("speed", 2.4)
			root.add_child(f)
			flames.append(f)
		_flames.append(flames)
		var e: GPUParticles3D = HdFx.embers(
			30, 0.08, PackedColorArray([Color(2, 1.6, 1.0), Color(1, 0.4, 0.15)])
		)
		e.lifetime = 1.4
		(e.process_material as ParticleProcessMaterial).gravity = Vector3(0, 2.0, 0)
		e.emitting = false
		root.add_child(e)
		_embers.append(e)
		var sm: GPUParticles3D = HdFx.smoke(16, 1.6, Color(0.28, 0.2, 0.26))
		sm.one_shot = false
		sm.explosiveness = 0.0
		sm.lifetime = 2.0
		root.add_child(sm)
		_smoke.append(sm)
		var a := AudioStreamPlayer3D.new()
		a.bus = &"SFX"
		a.stream = CRACKLE_SFX
		a.unit_size = 8.0
		root.add_child(a)
		_audio.append(a)
		_left.append(0.0)
		_total.append(1.0)
		_tick.append(0.0)
		_tick_sec.append(0.5)
		_damage.append(1)
		_size.append(1.0)
	set_process(false)


## Prende un foco de fuego en `pos` (sobre la superficie, saliendo por `normal`).
func ignite(
	pos: Vector3, normal: Vector3, size: float, duration: float, tick_sec: float, damage: int
) -> void:
	var i: int = _next
	_next = (_next + 1) % SLOTS
	var root: Node3D = _roots[i]
	root.global_position = pos + normal * (size * 0.25)
	root.visible = true
	_size[i] = size
	_left[i] = duration
	_total[i] = duration
	_tick[i] = tick_sec
	_tick_sec[i] = tick_sec
	_damage[i] = damage
	var flames: Array = _flames[i]
	for k: int in flames.size():
		var f: MeshInstance3D = flames[k]
		var off := Vector3(randf_range(-0.4, 0.4), randf_range(-0.1, 0.3), randf_range(-0.4, 0.4))
		f.position = off * size
		f.set_meta(&"base", size * randf_range(0.6, 1.0))
	(_embers[i].process_material as ParticleProcessMaterial).emission_sphere_radius = size * 0.35
	_embers[i].emitting = true
	_smoke[i].emitting = true
	(_smoke[i].draw_pass_1 as QuadMesh).size = Vector2.ONE * size * 0.8
	_audio[i].volume_db = -8.0
	_audio[i].pitch_scale = randf_range(0.9, 1.1)
	_audio[i].play()
	set_process(true)


func _process(delta: float) -> void:
	var any: bool = false
	for i: int in SLOTS:
		if _left[i] <= 0.0:
			continue
		any = true
		_left[i] -= delta
		var life: float = clampf(_left[i] / _total[i], 0.0, 1.0)
		# Crece deprisa al prender y se apaga poco a poco.
		var grow: float = clampf((_total[i] - _left[i]) / 0.25, 0.0, 1.0)
		var k: float = grow * smoothstep(0.0, 0.35, life)
		for f: MeshInstance3D in _flames[i]:
			f.scale = Vector3.ONE * float(f.get_meta(&"base")) * k
			(f.material_override as ShaderMaterial).set_shader_parameter("fade", k)
		_audio[i].volume_db = lerpf(-30.0, -8.0, k)
		_tick[i] -= delta
		if _tick[i] <= 0.0 and life > 0.15:
			_tick[i] = _tick_sec[i]
			burned.emit(_damage[i], _roots[i].global_position)
		if _left[i] <= 0.0:
			_embers[i].emitting = false
			_smoke[i].emitting = false
			_audio[i].stop()
			_roots[i].visible = false
	if not any:
		set_process(false)
