class_name SpellTrail
extends MeshInstance3D
## Estela de un hechizo en vuelo: guarda las últimas posiciones del proyectil y dibuja con ellas
## una cinta que mira a la cámara (`spell_trail.gdshader`). Se crea una vez por proyectil y se
## reutiliza; la malla es una `ImmediateMesh` que se rehace sólo mientras hay estela.

const SHADER: Shader = preload("res://spells/vfx/spell_trail.gdshader")
const HD_SHADER: Shader = preload("res://fx/hd/hd_trail.gdshader")
const MAX_POINTS: int = 32

## Duración de la estela (s): cuánto tarda un punto en llegar a la cola.
var length_sec: float = 0.18
## Ancho en la cabeza (m) cuando el hechizo ya va lejos.
var width: float = 0.3
## true: estela suave en la capa de magia HD (hechizos); false: pixel art (fragmentos al Pilón).
## Se fija antes de añadir el nodo al árbol.
var hd: bool = false
## Cerca de la cámara la estela se estrecha igual que el orbe (ver `SparkProjectile`): a
## `near_depth` m mide `width / max_scale` y alcanza `width` a `near_depth * max_scale` m.
var near_depth: float = 0.85
var max_scale: float = 1.0

var _points: PackedVector3Array = PackedVector3Array()
var _times: PackedFloat32Array = PackedFloat32Array()
var _head: int = 0
var _count: int = 0
var _now: float = 0.0
var _emitting: bool = false
var _mesh := ImmediateMesh.new()
var _mat := ShaderMaterial.new()


func _ready() -> void:
	top_level = true
	mesh = _mesh
	_mat.shader = HD_SHADER if hd else SHADER
	_mat.render_priority = 2
	if hd:
		layers = MagicLayer.MAGIC_LAYER
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = 64.0
	_points.resize(MAX_POINTS)
	_times.resize(MAX_POINTS)
	set_process(false)


## Rampa de colores de la estela (de caliente a frío; alfa < 1 se trama).
func set_ramp(gradient: Gradient) -> void:
	if hd:
		_mat.set_shader_parameter("ramp", HdFx.smooth_ramp(gradient))
		return
	var tex := GradientTexture1D.new()
	tex.gradient = gradient
	tex.use_hdr = true
	tex.width = 64
	_mat.set_shader_parameter("ramp", tex)


func start(at: Vector3) -> void:
	_count = 0
	_head = 0
	_now = 0.0
	_emitting = true
	_mat.set_shader_parameter("fade", 0.0)
	_mat.set_shader_parameter("seed", randf() * 10.0)
	add_point(at)
	visible = true
	set_process(true)


## La cabeza deja de avanzar: la cola la alcanza y la estela desaparece sola.
func stop() -> void:
	_emitting = false


func add_point(at: Vector3) -> void:
	_points[_head] = at
	_times[_head] = _now
	_head = (_head + 1) % MAX_POINTS
	_count = mini(_count + 1, MAX_POINTS)


func _process(delta: float) -> void:
	_now += delta
	if _emitting:
		add_point(get_parent().global_position if get_parent() is Node3D else global_position)
	_rebuild()


func _rebuild() -> void:
	_mesh.clear_surfaces()
	var cam: Camera3D = get_viewport().get_camera_3d()
	# Puntos vivos, de la cabeza (más nuevo) a la cola.
	var alive: int = 0
	for k: int in _count:
		var i: int = (_head - 1 - k + MAX_POINTS) % MAX_POINTS
		if _now - _times[i] > length_sec:
			break
		alive += 1
	if alive < 2 or cam == null:
		if not _emitting:
			visible = false
			set_process(false)
		return
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var cam_pos: Vector3 = cam.global_position
	for k: int in alive:
		var i: int = (_head - 1 - k + MAX_POINTS) % MAX_POINTS
		var j: int = (_head - 1 - mini(k + 1, alive - 1) + MAX_POINTS) % MAX_POINTS
		var h: int = (_head - 1 - maxi(k - 1, 0) + MAX_POINTS) % MAX_POINTS
		var p: Vector3 = _points[i]
		var tangent: Vector3 = _points[h] - _points[j]
		if tangent.length_squared() < 0.000001:
			tangent = Vector3.UP
		var side: Vector3 = tangent.cross(cam_pos - p).normalized()
		var age: float = clampf((_now - _times[i]) / length_sec, 0.0, 1.0)
		if k == alive - 1:
			age = 1.0
		var near: float = clampf(cam_pos.distance_to(p) / near_depth, 1.0, max_scale) / max_scale
		var w: float = width * near * (1.0 - age * 0.6)
		_mesh.surface_set_uv(Vector2(age, 0.0))
		_mesh.surface_add_vertex(p + side * w)
		_mesh.surface_set_uv(Vector2(age, 1.0))
		_mesh.surface_add_vertex(p - side * w)
	_mesh.surface_end()
