class_name Player
extends CharacterBody3D
## Mago en primera persona: mirar con el ratón, caminar con WASD. Monta cámara, manos,
## lanzador de hechizos y el post-proceso de contorno.

const OUTLINE_SHADER: Shader = preload("res://fx/outline.gdshader")

@export var walk_speed: float = 4.5
@export var acceleration: float = 30.0
@export var mouse_sensitivity: float = 0.0022
@export var start_pitch_deg: float = 20.0

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

@onready var _head: Node3D = $Head
@onready var _camera: CameraRig = $Head/Camera
@onready var _hands: WizardHands = $Head/Camera/Hands
@onready var _caster: SpellCaster = $SpellCaster


func _ready() -> void:
	_head.rotation.x = deg_to_rad(start_pitch_deg)
	_caster.camera = _camera
	_caster.hands = _hands
	_caster.set_tier(0)
	_add_outline()


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
