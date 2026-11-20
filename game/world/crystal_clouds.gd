class_name CrystalClouds
extends Node3D
## Nubes de verdad (3D, low-poly y con contorno como el resto del valle) a la altura de la punta
## del Cristal Madre: unas pocas abrazan la punta y otras forman un techo lejano que da escala.
## El cielo (sky.gdshader) sigue pintando las nubes del fondo; éstas son las que se ven pasar
## por delante del cristal. Todo es una sola malla por nube, creada una vez con semilla fija;
## cada fotograma sólo gira el conjunto muy despacio alrededor del cristal.
## Las de fuera quedan lejos de la columna del Pilón (radio ~69 m), que agujerea las del cielo.

const CLOUD_SHADER: Shader = preload("res://world/cloud.gdshader")
const C_LIGHT := Color("#ffffff")
const C_MID := Color("#e8edfc")
const C_SHADOW := Color("#c4c7e8")
## Vuelta completa alrededor del cristal (s).
const ORBIT_SEC: float = 1500.0
## Nubes que rodean la punta: (ángulo en grados, radio al eje, altura, largo de la nube). La
## punta principal mide ~28 m de radio en el hombro (~89 m) y se afila hasta ~134 m: a ~31 m
## del eje, el lado de dentro de cada nube roza la punta.
const TIP: Array[Vector4] = [
	Vector4(0.0, 31.0, 104.0, 44.0),
	Vector4(52.0, 33.0, 118.0, 40.0),
	Vector4(104.0, 30.0, 98.0, 46.0),
	Vector4(156.0, 32.0, 112.0, 42.0),
	Vector4(208.0, 31.0, 124.0, 36.0),
	Vector4(260.0, 30.0, 101.0, 46.0),
	Vector4(312.0, 33.0, 115.0, 40.0),
]
## Techo lejano: cuántas nubes, entre qué radios y alturas.
const FAR_COUNT: int = 11
const FAR_RADIUS := Vector2(115.0, 230.0)
const FAR_HEIGHT := Vector2(96.0, 150.0)

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 2611
	var mat := ShaderMaterial.new()
	mat.shader = CLOUD_SHADER
	for i: int in TIP.size():
		var t: Vector4 = TIP[i]
		_add_cloud(mat, "TipCloud%d" % i, t.x, t.y, t.z, t.w)
	for i: int in FAR_COUNT:
		var ang: float = 360.0 * (float(i) + _rng.randf_range(-0.3, 0.3)) / float(FAR_COUNT)
		_add_cloud(
			mat,
			"FarCloud%d" % i,
			ang,
			_rng.randf_range(FAR_RADIUS.x, FAR_RADIUS.y),
			_rng.randf_range(FAR_HEIGHT.x, FAR_HEIGHT.y),
			_rng.randf_range(40.0, 70.0)
		)


func _process(delta: float) -> void:
	rotation.y = fposmod(rotation.y + delta * TAU / ORBIT_SEC, TAU)


func _add_cloud(
	mat: ShaderMaterial, node_name: String, ang_deg: float, radius: float, h: float, length: float
) -> void:
	var a: float = deg_to_rad(ang_deg)
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = _cloud_mesh(length)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(cos(a) * radius, h, sin(a) * radius)
	# A lo largo de la órbita (tangente), como si las llevara el viento.
	mi.rotation.y = -a + _rng.randf_range(-0.4, 0.4)
	add_child(mi)


## Una nube: bollos achatados en fila (el del medio más alto), con la base plana.
func _cloud_mesh(length: float) -> ArrayMesh:
	var st: SurfaceTool = MeshKit.begin()
	var n: int = maxi(3, int(length / 8.0))
	for k: int in n:
		var u: float = (float(k) / float(n - 1)) - 0.5
		var mid: float = 1.0 - absf(u) * 1.2
		var r: float = length * 0.2 * (0.6 + 0.45 * mid) * _rng.randf_range(0.85, 1.15)
		var c := Vector3(u * length, r * 0.15 * mid, _rng.randf_range(-0.12, 0.12) * length * 0.3)
		_add_puff(st, c, r)
	return MeshKit.commit(st)


## Bollo: icosaedro subdividido una vez, achatado y con los vértices algo movidos. Lo que queda
## por debajo de la base se aplasta (las nubes de buen tiempo tienen el fondo plano).
func _add_puff(st: SurfaceTool, center: Vector3, r: float) -> void:
	var verts: Array[Vector3] = []
	var t: float = (1.0 + sqrt(5.0)) / 2.0
	for p: Vector3 in [
		Vector3(-1, t, 0),
		Vector3(1, t, 0),
		Vector3(-1, -t, 0),
		Vector3(1, -t, 0),
		Vector3(0, -1, t),
		Vector3(0, 1, t),
		Vector3(0, -1, -t),
		Vector3(0, 1, -t),
		Vector3(t, 0, -1),
		Vector3(t, 0, 1),
		Vector3(-t, 0, -1),
		Vector3(-t, 0, 1),
	]:
		verts.append(p.normalized())
	var faces: Array[Vector3i] = [
		Vector3i(0, 11, 5),
		Vector3i(0, 5, 1),
		Vector3i(0, 1, 7),
		Vector3i(0, 7, 10),
		Vector3i(0, 10, 11),
		Vector3i(1, 5, 9),
		Vector3i(5, 11, 4),
		Vector3i(11, 10, 2),
		Vector3i(10, 7, 6),
		Vector3i(7, 1, 8),
		Vector3i(3, 9, 4),
		Vector3i(3, 4, 2),
		Vector3i(3, 2, 6),
		Vector3i(3, 6, 8),
		Vector3i(3, 8, 9),
		Vector3i(4, 9, 5),
		Vector3i(2, 4, 11),
		Vector3i(6, 2, 10),
		Vector3i(8, 6, 7),
		Vector3i(9, 8, 1),
	]
	# Una subdivisión: cada cara en cuatro (los puntos medios se comparten por arista).
	var mids: Dictionary[int, int] = {}
	var fine: Array[Vector3i] = []
	for f: Vector3i in faces:
		var ab: int = _midpoint(verts, mids, f.x, f.y)
		var bc: int = _midpoint(verts, mids, f.y, f.z)
		var ca: int = _midpoint(verts, mids, f.z, f.x)
		fine.append_array(
			[
				Vector3i(f.x, ab, ca),
				Vector3i(f.y, bc, ab),
				Vector3i(f.z, ca, bc),
				Vector3i(ab, bc, ca)
			]
		)
	var pts: Array[Vector3] = []
	for v: Vector3 in verts:
		var q: Vector3 = v * r * _rng.randf_range(0.9, 1.1)
		q.y *= 0.62
		q.y = maxf(q.y, -r * 0.22)
		pts.append(center + q)
	for f: Vector3i in fine:
		var a: Vector3 = pts[f.x]
		var b: Vector3 = pts[f.y]
		var c: Vector3 = pts[f.z]
		var ny: float = ((a + b + c) / 3.0 - center).normalized().y
		var col: Color = C_LIGHT
		if ny < -0.15:
			col = C_SHADOW
		elif ny < 0.35:
			col = C_MID
		MeshKit.add_tri(st, a, b, c, col, center)


static func _midpoint(verts: Array[Vector3], mids: Dictionary[int, int], i: int, j: int) -> int:
	var key: int = mini(i, j) * 1024 + maxi(i, j)
	if mids.has(key):
		return mids[key]
	verts.append(((verts[i] + verts[j]) * 0.5).normalized())
	mids[key] = verts.size() - 1
	return verts.size() - 1
