class_name ShardPool
extends Node3D
## Pool de fragmentos físicos. Nada se instancia durante el juego: los fragmentos se reciclan
## (el más antiguo primero). Tras unos segundos quietos se congelan para no gastar física.

const SHARD_MATERIAL_SHADER: Shader = preload("res://crystal/shard.gdshader")
const CLINK_STREAMS: Array[AudioStream] = [
	preload("res://audio/sfx/sfx_shard_clink_01.ogg"),
	preload("res://audio/sfx/sfx_shard_clink_02.ogg"),
	preload("res://audio/sfx/sfx_shard_clink_03.ogg"),
	preload("res://audio/sfx/sfx_shard_clink_04.ogg"),
]

@export var pool_size: int = 64
@export var freeze_after_sec: float = 5.0
@export var clink_players: int = 8
## Separación mínima entre dos tintineos (evita un muro de sonido).
@export var clink_min_gap_sec: float = 0.035

var _shards: Array[RigidBody3D] = []
var _meshes: Array[MeshInstance3D] = []
var _cols: Array[CollisionShape3D] = []
var _spawn_time: PackedFloat64Array = []
var _flash: PackedFloat32Array = []
var _next: int = 0
var _clinks: Array[AudioStreamPlayer3D] = []
var _clink_next: int = 0
var _last_clink: float = -1.0
var _clink_random: AudioStreamRandomizer
var _time: float = 0.0


func _ready() -> void:
	var material := ShaderMaterial.new()
	material.shader = SHARD_MATERIAL_SHADER
	var meshes: Array[ArrayMesh] = []
	var shapes: Array[ConvexPolygonShape3D] = []
	for i: int in 4:
		var m: ArrayMesh = CrystalClusterBuilder.build_shard_mesh(40 + i)
		meshes.append(m)
		shapes.append(m.create_convex_shape(true, true) as ConvexPolygonShape3D)
	for i: int in pool_size:
		var body := RigidBody3D.new()
		body.name = "Shard%d" % i
		body.add_to_group(&"shards")
		body.collision_layer = 1 << 3
		body.collision_mask = 1 | (1 << 1) | (1 << 3)
		body.contact_monitor = true
		body.max_contacts_reported = 1
		body.continuous_cd = false
		body.mass = 0.2
		var phys := PhysicsMaterial.new()
		phys.bounce = 0.35
		phys.friction = 0.6
		body.physics_material_override = phys
		var col := CollisionShape3D.new()
		col.shape = shapes[i % shapes.size()]
		body.add_child(col)
		var mi := MeshInstance3D.new()
		mi.mesh = meshes[i % meshes.size()]
		mi.material_override = material
		mi.set_instance_shader_parameter("glint_seed", randf())
		body.add_child(mi)
		body.body_entered.connect(_on_shard_contact.bind(i))
		_deactivate(body)
		add_child(body)
		_shards.append(body)
		_meshes.append(mi)
		_cols.append(col)
		_spawn_time.append(-1.0)
		_flash.append(0.0)
	_clink_random = AudioStreamRandomizer.new()
	for s: AudioStream in CLINK_STREAMS:
		_clink_random.add_stream(-1, s)
	_clink_random.random_pitch = 1.12
	_clink_random.random_volume_offset_db = 3.0
	for i: int in clink_players:
		var p := AudioStreamPlayer3D.new()
		p.bus = &"SFX"
		p.stream = _clink_random
		p.unit_size = 8.0
		p.max_db = -2.0
		add_child(p)
		_clinks.append(p)


## Lanza `count` fragmentos desde `origin`, saliendo según `normal`.
func spawn(origin: Vector3, normal: Vector3, count: int, size_scale: float, power: float) -> void:
	for n: int in count:
		var i: int = _next
		_next = (_next + 1) % pool_size
		var body: RigidBody3D = _shards[i]
		_deactivate(body)
		var s: float = size_scale * randf_range(0.8, 1.3)
		_meshes[i].scale = Vector3.ONE * s
		_cols[i].scale = Vector3.ONE * s
		body.global_transform = Transform3D(
			Basis.from_euler(Vector3(randf() * TAU, randf() * TAU, randf() * TAU)),
			origin + normal * 0.25
		)
		body.freeze = false
		body.visible = true
		body.process_mode = Node.PROCESS_MODE_INHERIT
		var spread := Vector3(randf_range(-1, 1), randf_range(0.2, 1.0), randf_range(-1, 1)) * 0.6
		var dir: Vector3 = (normal + Vector3.UP * 0.6 + spread).normalized()
		body.linear_velocity = dir * randf_range(4.0, 8.0) * power
		body.angular_velocity = (
			Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 14.0
		)
		_spawn_time[i] = _time
		_flash[i] = 1.0
		_meshes[i].set_instance_shader_parameter("spawn_flash", 1.0)
	set_physics_process(true)


func _physics_process(delta: float) -> void:
	_time += delta
	var any_active: bool = false
	for i: int in pool_size:
		if _spawn_time[i] < 0.0:
			continue
		if _flash[i] > 0.0:
			_flash[i] = maxf(0.0, _flash[i] - delta * 4.0)
			_meshes[i].set_instance_shader_parameter("spawn_flash", 1.0 if _flash[i] > 0.6 else 0.0)
		var body: RigidBody3D = _shards[i]
		if not body.freeze:
			any_active = true
			if (
				_time - _spawn_time[i] > freeze_after_sec
				and body.linear_velocity.length_squared() < 0.04
			):
				body.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
				body.freeze = true
				body.contact_monitor = false
	if not any_active:
		set_physics_process(false)


func _deactivate(body: RigidBody3D) -> void:
	body.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	body.freeze = true
	body.visible = false
	body.contact_monitor = true
	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO


func _on_shard_contact(_other: Node, index: int) -> void:
	var body: RigidBody3D = _shards[index]
	var speed: float = body.linear_velocity.length()
	if speed < 0.8 or _time - _last_clink < clink_min_gap_sec:
		return
	_last_clink = _time
	var p: AudioStreamPlayer3D = _clinks[_clink_next]
	_clink_next = (_clink_next + 1) % _clinks.size()
	p.global_position = body.global_position
	p.volume_db = linear_to_db(clampf(speed / 6.0, 0.15, 1.0))
	p.play()
