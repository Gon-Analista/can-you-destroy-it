class_name CrystalArcs
extends MeshInstance3D
## Rayos de energía y destellos sobre el Cristal Madre (capa de magia HD): al golpearlo, rayos
## quebrados recorren la superficie desde el impacto (más y más largos cuanto más fuerte el
## golpe), saltan destellos en estrella y, de vez en cuando, el cristal entero se resquebraja
## en una tormenta de rayos (ver MotherCrystal). Todo en una sola malla que se rehace sólo
## mientras hay rayos vivos.

const SHADER: Shader = preload("res://fx/hd/hd_arc.gdshader")
const MAX_BOLTS: int = 40
const SEGMENTS: int = 9

var _points: Array[PackedVector3Array] = []
var _life: PackedFloat32Array = []
var _total: PackedFloat32Array = []
var _width: PackedFloat32Array = []
var _color: PackedColorArray = []
var _next: int = 0
var _mesh := ImmediateMesh.new()
var _glints: GPUParticles3D
var _ambient: GPUParticles3D
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	top_level = true
	mesh = _mesh
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.render_priority = 9
	material_override = m
	layers = MagicLayer.MAGIC_LAYER
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = 200.0
	for i: int in MAX_BOLTS:
		_points.append(PackedVector3Array())
		_life.append(0.0)
		_total.append(1.0)
		_width.append(0.05)
		_color.append(Color.WHITE)
	_glints = _star_particles(30, 0.5, true)
	_glints.name = "Glints"
	add_child(_glints)
	set_process(false)


## Destellos que titilan sueltos por todo el cristal (volumen de la caja, en metros).
func setup_ambient(center: Vector3, size: Vector3) -> void:
	_ambient = _star_particles(36, 0.9, false)
	_ambient.name = "AmbientGlints"
	var pm: ParticleProcessMaterial = _ambient.process_material
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = size * 0.5
	pm.initial_velocity_min = 0.0
	pm.initial_velocity_max = 0.05
	_ambient.emitting = true
	add_child(_ambient)
	_ambient.global_position = center


## Rayos que salen de `at` por la superficie (perpendicular a `normal`). `power` (0..1+)
## decide cuántos, lo largos y lo gruesos.
func strike(at: Vector3, normal: Vector3, power: float, color: Color) -> void:
	var n: Vector3 = normal.normalized() if normal.length_squared() > 0.01 else Vector3.BACK
	var count: int = clampi(2 + roundi(power * 4.0), 2, 9)
	for k: int in count:
		var a: float = _rng.randf() * TAU
		var t1: Vector3 = n.cross(Vector3.UP if absf(n.y) < 0.9 else Vector3.RIGHT).normalized()
		var t2: Vector3 = n.cross(t1)
		var dir: Vector3 = (t1 * cos(a) + t2 * sin(a) + n * 0.15).normalized()
		var length: float = _rng.randf_range(0.8, 1.6) * (1.0 + power * 2.2)
		_bolt(at + n * 0.1, dir, length, 0.07 + power * 0.08, color, _rng.randf_range(0.16, 0.3))
	_glints.global_position = at + n * 0.3
	_glints.amount_ratio = clampf(0.3 + power * 0.5, 0.3, 1.0)
	_glints.restart()


## La tormenta de rayos de un "resquebrajo": rayos largos que trepan por todo el cristal.
## Un rayo quebrado de `from` a `to` (Trueno, rayos que saltan). Con `jag` pequeño y sin ramas
## sale casi recto (el Haz de Plasma).
func bolt_between(
	from: Vector3,
	to: Vector3,
	width: float,
	color: Color,
	life: float,
	jag: float = 0.45,
	branch: bool = true
) -> void:
	var d: Vector3 = to - from
	if d.length() < 0.05:
		return
	_bolt(from, d.normalized(), d.length(), width, color, life, jag, branch)
	set_process(true)


func storm(base: Vector3, height: float, radius: float, color: Color) -> void:
	for k: int in 16:
		var a: float = _rng.randf() * TAU
		var start: Vector3 = (
			base
			+ Vector3(
				cos(a) * radius * 0.6, _rng.randf_range(0.0, height * 0.3), sin(a) * radius * 0.6
			)
		)
		var dir := Vector3(cos(a) * 0.35, 1.0, sin(a) * 0.35).normalized()
		_bolt(
			start,
			dir,
			_rng.randf_range(height * 0.3, height * 0.75),
			0.3,
			color,
			_rng.randf_range(0.45, 0.8)
		)


func _bolt(
	from: Vector3,
	dir: Vector3,
	length: float,
	width: float,
	color: Color,
	life: float,
	jag: float = 0.45,
	branch: bool = true
) -> void:
	var i: int = _next
	_next = (_next + 1) % MAX_BOLTS
	var pts := PackedVector3Array()
	var side: Vector3 = dir.cross(Vector3.UP if absf(dir.y) < 0.9 else Vector3.RIGHT).normalized()
	var up: Vector3 = dir.cross(side)
	var p: Vector3 = from
	pts.append(p)
	var seg: float = length / float(SEGMENTS)
	for s: int in SEGMENTS:
		var jitter: Vector3 = (
			(side * _rng.randf_range(-1, 1) + up * _rng.randf_range(-1, 1)) * seg * jag
		)
		p += dir * seg + jitter
		pts.append(p)
	_points[i] = pts
	_life[i] = life
	_total[i] = life
	_width[i] = width
	_color[i] = color
	# A veces el rayo se ramifica desde la mitad.
	if branch and _rng.randf() < 0.45 and length > 1.0:
		var j: int = _next
		_next = (_next + 1) % MAX_BOLTS
		var bpts := PackedVector3Array()
		@warning_ignore("integer_division")
		var bp: Vector3 = pts[SEGMENTS / 2]
		var bdir: Vector3 = (dir + side * _rng.randf_range(-1.2, 1.2)).normalized()
		bpts.append(bp)
		@warning_ignore("integer_division")
		for s: int in SEGMENTS / 2:
			bp += (
				bdir * seg * 0.8
				+ (side * _rng.randf_range(-1, 1) + up * _rng.randf_range(-1, 1)) * seg * 0.4
			)
			bpts.append(bp)
		_points[j] = bpts
		_life[j] = life * 0.8
		_total[j] = life * 0.8
		_width[j] = width * 0.6
		_color[j] = color
	set_process(true)


func _process(delta: float) -> void:
	_mesh.clear_surfaces()
	var cam: Camera3D = get_viewport().get_camera_3d()
	var any: bool = false
	for i: int in MAX_BOLTS:
		if _life[i] <= 0.0:
			continue
		_life[i] -= delta
		if _life[i] <= 0.0 or cam == null:
			continue
		any = true
		var k: float = _life[i] / _total[i]
		# Parpadea al morir, como un relámpago.
		var vis: float = k if k > 0.3 or fmod(_life[i] * 40.0, 1.0) > 0.4 else 0.0
		var pts: PackedVector3Array = _points[i]
		_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
		for s: int in pts.size():
			var a: Vector3 = pts[maxi(s - 1, 0)]
			var b: Vector3 = pts[mini(s + 1, pts.size() - 1)]
			var side: Vector3 = (b - a).cross(cam.global_position - pts[s]).normalized()
			var taper: float = 1.0 - float(s) / float(pts.size()) * 0.7
			var w: float = _width[i] * taper
			var c := Color(_color[i], vis)
			_mesh.surface_set_color(c)
			_mesh.surface_set_uv(Vector2(float(s) / float(pts.size()), 0.0))
			_mesh.surface_add_vertex(pts[s] + side * w)
			_mesh.surface_set_color(c)
			_mesh.surface_set_uv(Vector2(float(s) / float(pts.size()), 1.0))
			_mesh.surface_add_vertex(pts[s] - side * w)
		_mesh.surface_end()
	if not any:
		set_process(false)


func _star_particles(amount: int, lifetime: float, burst: bool) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.one_shot = burst
	p.explosiveness = 0.85 if burst else 0.0
	p.emitting = false
	p.local_coords = false
	p.top_level = true
	p.layers = MagicLayer.MAGIC_LAYER
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-40, -40, -40), Vector3(80, 120, 80))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 1.2
	pm.direction = Vector3.UP
	pm.spread = 180.0
	pm.initial_velocity_min = 0.5 if burst else 0.0
	pm.initial_velocity_max = 2.5 if burst else 0.1
	pm.gravity = Vector3.ZERO
	pm.damping_min = 2.0
	pm.damping_max = 4.0
	pm.scale_min = 0.6
	pm.scale_max = 1.4
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.0))
	curve.add_point(Vector2(0.25, 1.0))
	curve.add_point(Vector2(1.0, 0.0))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.scale_curve = ct
	pm.color_ramp = HdFx.color_ramp(
		PackedColorArray([Color(1.8, 1.9, 2.0), Color(0.8, 1.2, 1.8), Color(1.2, 0.8, 1.8)])
	)
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2.ONE * (0.35 if burst else 0.5)
	var m: StandardMaterial3D = HdFx.additive_particle_material(1.4)
	m.albedo_texture = HdFx.soft_star()
	q.material = m
	p.draw_pass_1 = q
	return p
