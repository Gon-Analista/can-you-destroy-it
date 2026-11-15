class_name Player
extends CharacterBody3D
## Mago en primera persona: mirar con el ratón, caminar con WASD. Monta cámara, manos 2D,
## lanzador de hechizos y el post-proceso de contorno.

const OUTLINE_SHADER: Shader = preload("res://fx/outline.gdshader")

@export var walk_speed: float = 4.5
@export var acceleration: float = 30.0
@export var mouse_sensitivity: float = 0.0022
@export var start_pitch_deg: float = 20.0
## Distancia máxima para recoger un fragmento apuntándolo.
@export var pickup_range: float = 4.5
## Si no apuntas a ninguno, se recoge el más cercano a este radio delante de ti.
@export var pickup_assist_radius: float = 1.6
## Mantener F recoge en cadena con este intervalo.
@export var pickup_repeat_sec: float = 0.12

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _shards: ShardPool
var _target_shard: int = -1
var _pickup_cooldown: float = 0.0
var _grab_point: Marker3D

@onready var _head: Node3D = $Head
@onready var _camera: CameraRig = $Head/Camera
@onready var _hands: WizardHands = $Hands
@onready var _caster: SpellCaster = $SpellCaster


func _ready() -> void:
	_head.rotation.x = deg_to_rad(start_pitch_deg)
	_caster.camera = _camera
	_caster.hands = _hands
	_caster.set_tier(0)
	_add_outline()
	_grab_point = Marker3D.new()
	_grab_point.position = Vector3(-0.18, -0.32, -0.55)
	_camera.add_child(_grab_point)
	_shards = get_tree().get_first_node_in_group(&"shard_pool") as ShardPool


func get_caster() -> SpellCaster:
	return _caster


func get_camera() -> Camera3D:
	return _camera


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion: InputEventMouseMotion = event
		rotate_y(-motion.relative.x * mouse_sensitivity)
		_head.rotation.x = clampf(
			_head.rotation.x - motion.relative.y * mouse_sensitivity,
			deg_to_rad(-80),
			deg_to_rad(80)
		)


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta
	var input: Vector2 = Input.get_vector(
		&"move_left", &"move_right", &"move_forward", &"move_back"
	)
	var wish: Vector3 = (global_basis * Vector3(input.x, 0.0, input.y)).normalized() * walk_speed
	var horizontal := Vector3(velocity.x, 0.0, velocity.z).move_toward(wish, acceleration * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	move_and_slide()
	_hands.move_speed = horizontal.length()
	_update_pickup(delta)


## Resalta el fragmento al que apuntas (o el más cercano delante) y lo recoge con F.
func _update_pickup(delta: float) -> void:
	if _shards == null:
		_shards = get_tree().get_first_node_in_group(&"shard_pool") as ShardPool
		if _shards == null:
			return
	var from: Vector3 = _camera.global_position
	var forward: Vector3 = -_camera.global_basis.z
	var query := PhysicsRayQueryParameters3D.create(
		from, from + forward * pickup_range, ShardPool.SHARD_LAYER | 1 | (1 << 1)
	)
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	var target: int = -1
	if not hit.is_empty():
		target = _shards.index_of(hit["collider"])
	if target < 0:
		var ahead: Vector3 = global_position + Vector3(forward.x, 0.0, forward.z).normalized() * 1.2
		target = _shards.nearest(ahead, pickup_assist_radius)
	if target != _target_shard:
		_target_shard = target
		_shards.set_highlight(target)
		Events.shard_targeted.emit(_shards.type_of(target) if target >= 0 else null)
	_pickup_cooldown = maxf(0.0, _pickup_cooldown - delta)
	if target >= 0 and _pickup_cooldown <= 0.0 and Input.is_action_pressed(&"interact"):
		_pickup_cooldown = pickup_repeat_sec
		var pos: Vector3 = _shards.position_of(target)
		var type: ShardType = _shards.collect(target, _grab_point)
		GameState.collect_shard(type, pos)
		_hands.play_grab()
		_target_shard = -1
		Events.shard_targeted.emit(null)


func _add_outline() -> void:
	var quad := MeshInstance3D.new()
	quad.name = "OutlinePost"
	var mesh := QuadMesh.new()
	mesh.size = Vector2.ONE
	quad.mesh = mesh
	var mat := ShaderMaterial.new()
	mat.shader = OUTLINE_SHADER
	# Antes que el resto de transparentes: así las partículas quedan por encima del contorno.
	mat.render_priority = -100
	quad.material_override = mat
	quad.extra_cull_margin = 16384.0
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_camera.add_child(quad)
