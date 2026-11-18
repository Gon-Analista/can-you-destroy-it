class_name GuideTrail
extends Node3D
## Parte del mundo de la guía de objetivos (capa de magia HD): una estela de destellos que fluye
## por el suelo desde el mago hacia el objetivo y una columna de luz suave encima de él, que se
## ve desde lejos. La estela rodea el Cristal Madre en vez de atravesarlo. Todo en un pool fijo
## de nodos creado una vez; cada fotograma sólo se mueven y se ajustan sus parámetros.

const SHADER: Shader = preload("res://fx/hd/hd_guide.gdshader")
const MOTES: int = 22
## Distancia entre destellos (m) y velocidad a la que fluyen hacia el objetivo (m/s).
const SPACING: float = 1.15
const FLOW: float = 2.4
## Altura de los destellos sobre el suelo (m).
const LIFT: float = 0.32
const MOTE_SIZE: float = 0.42
const PILLAR_W: float = 1.5
const PILLAR_H: float = 9.0
const P_TINT: StringName = &"tint"
const P_FADE: StringName = &"fade"
const P_SEED: StringName = &"seed"

## Metros de estela por delante del mago (`GuidanceDef.trail_length_m`).
var trail_length: float = 18.0

var _motes: Array[MeshInstance3D] = []
var _pillar: MeshInstance3D
var _base: MeshInstance3D
var _t: float = 0.0
var _trail_k: float = 0.0
var _beacon_k: float = 0.0
var _beacon_h: float = 1.0


func _ready() -> void:
	var mote_mat := ShaderMaterial.new()
	mote_mat.shader = SHADER
	mote_mat.set_shader_parameter(&"mode", 0)
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	for i: int in MOTES:
		var m: MeshInstance3D = _quad(quad, mote_mat, "Mote%d" % i)
		m.scale = Vector3.ONE * MOTE_SIZE
		m.set_instance_shader_parameter(P_SEED, float(i) * 0.37)
		_motes.append(m)
	var pillar_mat := ShaderMaterial.new()
	pillar_mat.shader = SHADER
	pillar_mat.set_shader_parameter(&"mode", 1)
	pillar_mat.set_shader_parameter(&"intensity", 2.2)
	_pillar = _quad(quad, pillar_mat, "Pillar")
	_pillar.scale = Vector3(PILLAR_W, PILLAR_H, 1.0)
	_base = _quad(quad, mote_mat, "Base")
	_base.scale = Vector3.ONE * 2.2
	_base.set_instance_shader_parameter(P_SEED, 3.3)


func _quad(mesh: QuadMesh, mat: ShaderMaterial, node_name: String) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.name = node_name
	m.mesh = mesh
	m.material_override = mat
	m.layers = MagicLayer.MAGIC_LAYER
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	m.extra_cull_margin = 2.0
	m.visible = false
	add_child(m)
	return m


## Coloca la guía de este fotograma. `trail` y `beacon` (0..1) son lo que se quiere ver de la
## estela y de la columna; suben y bajan suaves aquí. `height` escala la columna (1 = 9 m).
func guide(
	from: Vector3, to: Vector3, col: Color, trail: float, beacon: float, height: float, delta: float
) -> void:
	_t += delta
	_beacon_h = height
	_trail_k = move_toward(_trail_k, trail, delta * 2.5)
	_beacon_k = move_toward(_beacon_k, beacon, delta * 2.5)
	_update_trail(from, to, col)
	_update_beacon(to, col)


## Sin objetivo: todo se apaga solo.
func hide_all(delta: float) -> void:
	guide(Vector3.ZERO, Vector3.ZERO, Color.WHITE, 0.0, 0.0, _beacon_h, delta)


func _update_trail(from: Vector3, to: Vector3, col: Color) -> void:
	var flat := Vector3(to.x - from.x, 0.0, to.z - from.z)
	var dist: float = flat.length()
	var length: float = minf(trail_length, dist - 1.5)
	var on: bool = _trail_k > 0.001 and length > 2.0
	var dir: Vector3 = flat / maxf(dist, 0.001)
	# La estela rodea el cristal (sólo si el mago está fuera de su base).
	var avoid: float = WorldLayout.CRYSTAL_FOOTPRINT + 3.0
	var outside: bool = Vector2(from.x, from.z).length() > avoid
	var flow: float = fmod(_t * FLOW, SPACING)
	for i: int in MOTES:
		var m: MeshInstance3D = _motes[i]
		var d: float = float(i) * SPACING + flow + 1.2
		if not on or d > length:
			m.visible = false
			continue
		# Serpentea un poco (un camino de polvo mágico, no una pista de aterrizaje).
		var side := Vector3(-dir.z, 0.0, dir.x)
		var wiggle: float = sin(d * 0.45 + _t * 0.8) * 0.45 + sin(d * 1.3 + float(i)) * 0.12
		var p: Vector3 = from + dir * d + side * wiggle * smoothstep(1.0, 5.0, d)
		if outside:
			var xz := Vector2(p.x, p.z)
			if xz.length() < avoid:
				xz = xz.normalized() * avoid
				p.x = xz.x
				p.z = xz.y
		var bob: float = sin(_t * 3.0 + float(i) * 0.9) * 0.06
		p.y = Valley.ground_height(p.x, p.z) + LIFT + bob
		m.global_position = p
		# Aparece delante del mago, se apaga al final de la estela y respira con el flujo.
		var k: float = smoothstep(2.2, 4.8, d) * (1.0 - smoothstep(length - 4.0, length, d))
		m.scale = Vector3.ONE * MOTE_SIZE * (0.75 + 0.35 * absf(sin(float(i) * 2.17)))
		m.set_instance_shader_parameter(P_FADE, k * _trail_k)
		m.set_instance_shader_parameter(P_TINT, col)
		m.visible = true


func _update_beacon(to: Vector3, col: Color) -> void:
	var on: bool = _beacon_k > 0.001
	_pillar.visible = on
	_base.visible = on
	if not on:
		return
	var ground: float = Valley.ground_height(to.x, to.z)
	var h: float = PILLAR_H * _beacon_h
	# Más ancha de lejos: se lee igual a 10 m que a 60 m.
	var far: float = clampf(_cam_dist(to) * 0.035, 0.0, 2.2)
	_pillar.scale = Vector3((PILLAR_W + far) * sqrt(_beacon_h), h, 1.0)
	_pillar.global_position = Vector3(to.x, ground + h * 0.5, to.z)
	_pillar.set_instance_shader_parameter(P_FADE, _beacon_k * (0.8 + 0.2 * sin(_t * 2.2)))
	_pillar.set_instance_shader_parameter(P_TINT, col)
	_base.scale = Vector3.ONE * 2.2 * sqrt(_beacon_h)
	_base.global_position = Vector3(to.x, ground + 0.5 * sqrt(_beacon_h), to.z)
	_base.set_instance_shader_parameter(P_FADE, _beacon_k * 0.7)
	_base.set_instance_shader_parameter(P_TINT, col)


func _cam_dist(to: Vector3) -> float:
	var cam: Camera3D = get_viewport().get_camera_3d()
	return cam.global_position.distance_to(to) if cam else 10.0
