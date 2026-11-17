class_name MagicCircles
extends Node3D
## Círculos mágicos con runas de los niveles 6 a 10 de los hechizos (capa de magia HD).
##
## - Hechizos que se cargan (Bola de Fuego, Choque Térmico): mientras cargas aparecen, uno a
##   uno según la carga, `nivel - 5` círculos cada vez más grandes y más lejos, alineados desde
##   las manos hacia donde apuntas y girando en sentidos alternos. Al lanzar, el hechizo los
##   atraviesa: cada uno destella y se abre.
## - Hechizos de toque (Chispa, Escarcha): al lanzar sale de la mano un círculo pequeño que gira
##   rápido y se apaga (dos a nivel 8, tres a nivel 10).

const SHADER: Shader = preload("res://fx/hd/hd_magic_circle.gdshader")
const POOL: int = 12
const MAX_CHARGE_CIRCLES: int = 5
## Distancia (m) del primer círculo y separación de los siguientes, que crece.
const FIRST_DIST: float = 1.4
const STEP_DIST: float = 0.75

var _quads: Array[MeshInstance3D] = []
var _mats: Array[ShaderMaterial] = []
## Estado por quad: 0 libre, 1 de carga, 2 soltándose (destello), 3 de toque.
var _state: PackedInt32Array = []
var _age: PackedFloat32Array = []
var _spin_speed: PackedFloat32Array = []
var _spin: PackedFloat32Array = []
var _base_scale: PackedFloat32Array = []
var _charge_ids: Array[int] = []
var _charge_count: int = 0
var _origin := Vector3.ZERO
var _dir := Vector3.FORWARD


func _ready() -> void:
	top_level = true
	for i: int in POOL:
		var mi := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(2.0, 2.0)
		mi.mesh = quad
		mi.layers = MagicLayer.MAGIC_LAYER
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mat := ShaderMaterial.new()
		mat.shader = SHADER
		mat.render_priority = 3
		mat.set_shader_parameter("rune_seed", float(i) * 1.7 + 0.3)
		mi.material_override = mat
		mi.visible = false
		add_child(mi)
		_quads.append(mi)
		_mats.append(mat)
		_state.append(0)
		_age.append(0.0)
		_spin_speed.append(0.0)
		_spin.append(0.0)
		_base_scale.append(1.0)


## Mientras se carga un hechizo combinado: `count` círculos (1..5) que aparecen con la carga `k`,
## de `origin` (las manos) hacia `aim`.
func charging(k: float, count: int, origin: Vector3, aim: Vector3, col: Color, hot: Color) -> void:
	count = clampi(count, 0, MAX_CHARGE_CIRCLES)
	_origin = origin
	_dir = (aim - origin).normalized() if aim.distance_to(origin) > 0.01 else _dir
	if _charge_ids.size() != count:
		_release_charge(false)
		_charge_count = count
		for c: int in count:
			var i: int = _free()
			if i < 0:
				break
			_charge_ids.append(i)
			_state[i] = 1
			_age[i] = 0.0
			_spin[i] = randf() * TAU
			_spin_speed[i] = (0.8 + c * 0.25) * (1.0 if c % 2 == 0 else -1.0)
			# Cada uno más grande también en pantalla: se abren en cono hacia el blanco.
			_base_scale[i] = 0.36 * pow(1.55, c)
			# Tonos alternos para distinguir cada anillo.
			_mats[i].set_shader_parameter("color", col if c % 2 == 0 else col.lerp(hot, 0.45))
			_mats[i].set_shader_parameter("color_hot", hot)
			_mats[i].set_shader_parameter("rune_count", 10.0 + c * 3.0)
	for c: int in _charge_ids.size():
		var i: int = _charge_ids[c]
		# Cada círculo aparece cuando la carga pasa su umbral y se dibuja barriendo.
		var start: float = float(c) / float(maxi(count, 1)) * 0.85
		var a: float = clampf((k - start) / 0.18, 0.0, 1.0)
		_mats[i].set_shader_parameter("appear", a)
		_mats[i].set_shader_parameter("intensity", 0.8 + k * 0.5)
		_mats[i].set_shader_parameter("fade", 1.0)
		_mats[i].set_shader_parameter("flash", 0.0)
		_quads[i].visible = a > 0.0
		var pulse: float = 1.0 + sin(Time.get_ticks_msec() * 0.006 + c) * 0.03 * k
		_place(i, _origin + _dir * _dist(c), _base_scale[i] * (0.7 + 0.3 * a) * pulse)


## Al lanzar el combinado: los círculos destellan y se abren mientras el hechizo los cruza.
func release() -> void:
	_release_charge(true)


## Cancelado (se separan las manos sin lanzar): se apagan.
func cancel() -> void:
	_release_charge(false)


## Círculos de toque al lanzar con una mano.
func muzzle(origin: Vector3, aim: Vector3, count: int, col: Color, hot: Color) -> void:
	var dir: Vector3 = (aim - origin).normalized()
	for c: int in count:
		var i: int = _free()
		if i < 0:
			return
		_state[i] = 3
		_age[i] = -c * 0.05
		_spin[i] = randf() * TAU
		_spin_speed[i] = (7.0 + c * 2.0) * (1.0 if c % 2 == 0 else -1.0)
		_base_scale[i] = 0.12 + c * 0.07
		_mats[i].set_shader_parameter("color", col)
		_mats[i].set_shader_parameter("color_hot", hot)
		_mats[i].set_shader_parameter("rune_count", 12.0)
		_mats[i].set_shader_parameter("appear", 1.0)
		_mats[i].set_shader_parameter("flash", 0.6)
		_mats[i].set_shader_parameter("intensity", 1.1)
		_quads[i].set_meta(&"pos", origin + dir * (0.25 + c * 0.35))
		_quads[i].set_meta(&"dir", dir)
		_quads[i].visible = false


func _process(delta: float) -> void:
	for i: int in POOL:
		if _state[i] == 0:
			continue
		_age[i] += delta
		_spin[i] += _spin_speed[i] * delta
		_mats[i].set_shader_parameter("spin", _spin[i])
		match _state[i]:
			2:
				# Destello y apertura: 0,45 s.
				var t: float = _age[i] / 0.45
				_mats[i].set_shader_parameter("flash", maxf(0.0, 1.0 - t * 1.5))
				_mats[i].set_shader_parameter("fade", clampf(1.0 - t, 0.0, 1.0))
				_quads[i].scale = Vector3.ONE * _base_scale[i] * (1.0 + t * 0.8)
				if t >= 1.0:
					_free_quad(i)
			3:
				if _age[i] < 0.0:
					continue
				var t: float = _age[i] / 0.38
				_quads[i].visible = true
				_mats[i].set_shader_parameter("fade", clampf(1.0 - t, 0.0, 1.0))
				_mats[i].set_shader_parameter("flash", maxf(0.0, 0.6 - t))
				var pos: Vector3 = _quads[i].get_meta(&"pos")
				var dir: Vector3 = _quads[i].get_meta(&"dir")
				_dir = dir
				_place(i, pos + dir * t * 0.4, _base_scale[i] * (0.6 + t * 0.9))
				if t >= 1.0:
					_free_quad(i)


func _dist(c: int) -> float:
	return FIRST_DIST + STEP_DIST * c


## Pone el quad `i` en `pos`, de cara a lo largo de `_dir` (se ve casi de frente desde la cámara).
func _place(i: int, pos: Vector3, s: float) -> void:
	var z: Vector3 = -_dir
	var up: Vector3 = Vector3.UP if absf(z.y) < 0.95 else Vector3.RIGHT
	var x: Vector3 = up.cross(z).normalized()
	var y: Vector3 = z.cross(x).normalized()
	_quads[i].global_transform = Transform3D(Basis(x, y, z).scaled(Vector3.ONE * s), pos)


func _release_charge(burst: bool) -> void:
	for i: int in _charge_ids:
		if burst and _quads[i].visible:
			_state[i] = 2
			_age[i] = 0.0
		else:
			_free_quad(i)
	_charge_ids.clear()


func _free() -> int:
	for i: int in POOL:
		if _state[i] == 0:
			return i
	return -1


func _free_quad(i: int) -> void:
	_state[i] = 0
	_quads[i].visible = false
