class_name CritterRig
extends RefCounted
## Mallas y puntos de anclaje de una especie de bicho (`CritterDef.shape`), hechos una vez por
## especie y compartidos por todo el pool: cuerpo low-poly con colores por vértice para el toon
## (barriga clara, mofletes, rayas, pelo, hojas), boca, lengua, dientes, patas, antenas y el
## esqueleto que enseña el rayo. Delante es -Z y el origen está a ras del suelo, entre los pies.

const C_MOUTH := Color("#3a1026")
const C_MOUTH_IN := Color("#7a1f3d")
const C_TONGUE := Color("#ff6f9a")
const C_TOOTH := Color("#fffbea")
const C_BONE := Color("#f4f1e6")
const C_SOCKET := Color("#1d1424")

static var _cache: Dictionary[CritterDef, CritterRig] = {}

var body: ArrayMesh
var xray: ArrayMesh
var mouth: ArrayMesh
var tongue: ArrayMesh
## null si la especie no enseña dientes.
var teeth: ArrayMesh
## null si no tiene patas.
var leg: ArrayMesh
## null si los ojos no van en antenas.
var stalk: ArrayMesh
## Ancla de cada ojo (la base de la antena o el centro del ojo) y su radio (m).
var eye_pos: PackedVector3Array = []
var eye_r: PackedFloat32Array = []
## Largo de las antenas de los ojos (0 = ojos pegados a la cara).
var stalk_len: float = 0.0
var mouth_pos := Vector3.ZERO
## Cadera de cada pata.
var leg_pos: PackedVector3Array = []
var hit_center := Vector3.ZERO
var hit_radius: float = 0.4
var height: float = 1.0


## Pinta las caras de un torno: color de cuerpo, barriga delante y abajo, la base algo más oscura
## y rayas cada `stripe_every` anillos (si `stripe.a` > 0).
class Paint:
	var body: Color
	var belly: Color
	var belly_top: float = 0.0
	var bottom: Color
	var top: Color = Color(0, 0, 0, 0)
	var stripe: Color = Color(0, 0, 0, 0)
	var stripe_every: int = 2

	func _init(p_body: Color, p_belly: Color, p_belly_top: float) -> void:
		body = p_body
		belly = p_belly
		belly_top = p_belly_top
		bottom = p_body.darkened(0.22)


## La de esta especie (se construye la primera vez).
static func for_def(def: CritterDef) -> CritterRig:
	if not _cache.has(def):
		var rig := CritterRig.new()
		rig._build(def)
		_cache[def] = rig
	return _cache[def]


func _build(def: CritterDef) -> void:
	var st: SurfaceTool = MeshKit.begin()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(def.id)
	match def.shape:
		CritterDef.Shape.BLOB:
			_build_blob(st, def)
		CritterDef.Shape.TOOTHY:
			_build_toothy(st, def, rng)
		CritterDef.Shape.FUZZY:
			_build_fuzzy(st, def, rng)
		CritterDef.Shape.SLUG:
			_build_slug(st, def, rng)
		CritterDef.Shape.CYCLOPS:
			_build_cyclops(st, def, rng)
	body = MeshKit.commit(st)
	mouth = _mouth_mesh(def)
	tongue = _tongue_mesh(def)
	xray = _xray_mesh(def)


# --- Especies -------------------------------------------------------------------------------


## Gelatín: una gominola redonda que tiembla, con la cima brillante y una sonrisa enorme.
func _build_blob(st: SurfaceTool, def: CritterDef) -> void:
	var s: float = def.size
	var prof := PackedVector2Array(
		[
			Vector2(0.0, 0.0),
			Vector2(0.0, 0.3),
			Vector2(0.06, 0.45),
			Vector2(0.22, 0.5),
			Vector2(0.42, 0.47),
			Vector2(0.62, 0.39),
			Vector2(0.8, 0.25),
			Vector2(0.93, 0.1),
			Vector2(1.0, 0.0),
		]
	)
	var paint := Paint.new(def.body_color, def.belly_color, 0.42 * s)
	paint.top = def.belly_color.lightened(0.35)
	_lathe(st, _scaled(prof, s, s), 10, Transform3D.IDENTITY, paint)
	_cheeks(st, def, Vector3(0.3 * s, 0.4 * s, -0.36 * s), 0.07 * s)
	height = s
	eye_pos = PackedVector3Array([Vector3(-0.19, 0.64, -0.3) * s, Vector3(0.2, 0.62, -0.3) * s])
	eye_r = PackedFloat32Array([def.eye_radius, def.eye_radius * 0.88])
	mouth_pos = Vector3(0.0, 0.38, -0.45) * s
	hit_center = Vector3(0.0, 0.42 * s, 0.0)
	hit_radius = 0.5 * s


## Dientón: una zanahoria alta y bamboleante con hojas, rayas, dos paletas enormes y patitas.
func _build_toothy(st: SurfaceTool, def: CritterDef, rng: RandomNumberGenerator) -> void:
	var s: float = def.size
	var prof := PackedVector2Array(
		[
			Vector2(0.1, 0.0),
			Vector2(0.1, 0.09),
			Vector2(0.2, 0.2),
			Vector2(0.38, 0.27),
			Vector2(0.58, 0.31),
			Vector2(0.78, 0.32),
			Vector2(0.94, 0.3),
			Vector2(1.04, 0.22),
			Vector2(1.08, 0.0),
		]
	)
	var paint := Paint.new(def.body_color, def.belly_color, 0.5 * s)
	paint.stripe = def.body_color.darkened(0.18)
	paint.stripe_every = 2
	_lathe(st, _scaled(prof, s, s), 8, Transform3D.IDENTITY, paint)
	# Hojas de zanahoria en la cabeza.
	for k: int in 4:
		var a: float = TAU * float(k) / 4.0 + 0.4
		var out := Vector3(cos(a) * 0.35, 1.0, sin(a) * 0.35).normalized()
		MeshKit.add_prism(
			st,
			Vector3(0.0, 1.02, 0.0) * s,
			out,
			0.05 * s,
			0.08 * s,
			0.26 * s * rng.randf_range(0.8, 1.2),
			4,
			def.accent_color,
			def.accent_color.lightened(0.25),
			rng
		)
	_cheeks(st, def, Vector3(0.26 * s, 0.66 * s, -0.27 * s), 0.055 * s)
	height = 1.08 * s
	# Un ojo más grande y más alto que el otro: cara de despistado.
	eye_pos = PackedVector3Array([Vector3(-0.13, 0.9, -0.24) * s, Vector3(0.14, 0.86, -0.25) * s])
	eye_r = PackedFloat32Array([def.eye_radius, def.eye_radius * 0.78])
	mouth_pos = Vector3(0.0, 0.66, -0.32) * s
	var tst: SurfaceTool = MeshKit.begin()
	for side: float in [-1.0, 1.0]:
		MeshKit.add_box(
			tst, Vector3(0.05 * side, -0.07, -0.01) * s, Vector3(0.085, 0.12, 0.04) * s, C_TOOTH
		)
	teeth = MeshKit.commit(tst)
	leg = _leg_mesh(
		0.11 * s, 0.05 * s, Vector3(0.09, 0.05, 0.14) * s, def.accent_color.darkened(0.2)
	)
	leg_pos = PackedVector3Array([Vector3(-0.12, 0.12, 0.0) * s, Vector3(0.12, 0.12, 0.0) * s])
	hit_center = Vector3(0.0, 0.58 * s, 0.0)
	hit_radius = 0.42 * s


## Pelusín: un pompón de pelo sobre cuatro patitas, con dos ojazos muy juntos y un diente.
func _build_fuzzy(st: SurfaceTool, def: CritterDef, rng: RandomNumberGenerator) -> void:
	var s: float = def.size
	var r: float = 0.34 * s
	var c := Vector3(0.0, 0.52 * s, 0.0)
	var paint := Paint.new(def.body_color, def.belly_color, c.y)
	_lathe(st, _sphere_profile(r, 6), 10, Transform3D(Basis.IDENTITY, c - Vector3(0, r, 0)), paint)
	# Pelo: mechones en punta por toda la bola (menos en la cara).
	var tufts: int = 46
	for k: int in tufts:
		var y: float = 1.0 - 2.0 * (float(k) + 0.5) / float(tufts)
		var ring: float = sqrt(maxf(0.0, 1.0 - y * y))
		var a: float = float(k) * 2.39996
		var dir := Vector3(cos(a) * ring, y, sin(a) * ring)
		if dir.z < -0.55 and dir.y > -0.5 and dir.y < 0.7:
			continue
		var col: Color = def.accent_color if k % 3 == 0 else def.body_color.lightened(0.08)
		MeshKit.add_prism(
			st,
			c + dir * r * 0.82,
			dir,
			0.07 * s,
			0.02 * s,
			rng.randf_range(0.1, 0.17) * s,
			3,
			col,
			col.lightened(0.15),
			rng
		)
	_cheeks(st, def, Vector3(0.22 * s, 0.44 * s, -0.27 * s), 0.05 * s)
	height = 0.9 * s
	eye_pos = PackedVector3Array([Vector3(-0.11, 0.6, -0.27) * s, Vector3(0.11, 0.61, -0.27) * s])
	eye_r = PackedFloat32Array([def.eye_radius, def.eye_radius])
	mouth_pos = Vector3(0.0, 0.42, -0.32) * s
	var tst: SurfaceTool = MeshKit.begin()
	MeshKit.add_box(tst, Vector3(0.02, -0.05, -0.01) * s, Vector3(0.05, 0.07, 0.03) * s, C_TOOTH)
	teeth = MeshKit.commit(tst)
	leg = _leg_mesh(0.17 * s, 0.035 * s, Vector3(0.06, 0.035, 0.08) * s, def.accent_color)
	leg_pos = PackedVector3Array(
		[
			Vector3(-0.13, 0.2, -0.1) * s,
			Vector3(0.13, 0.2, -0.1) * s,
			Vector3(-0.13, 0.2, 0.1) * s,
			Vector3(0.13, 0.2, 0.1) * s,
		]
	)
	hit_center = c
	hit_radius = 0.45 * s


## Babosín: una babosa rechoncha con lunares y los ojos en la punta de dos antenas.
func _build_slug(st: SurfaceTool, def: CritterDef, rng: RandomNumberGenerator) -> void:
	var s: float = def.size
	var prof := PackedVector2Array(
		[
			Vector2(0.0, 0.0),
			Vector2(0.03, 0.12),
			Vector2(0.16, 0.2),
			Vector2(0.4, 0.24),
			Vector2(0.66, 0.24),
			Vector2(0.88, 0.2),
			Vector2(1.02, 0.12),
			Vector2(1.08, 0.0),
		]
	)
	var paint := Paint.new(def.body_color, def.belly_color, 0.12 * s)
	# El torno va a lo largo de -Z (de la cola a la cabeza) y algo aplastado.
	var basis := Basis(Vector3.RIGHT, -PI * 0.5).scaled(Vector3(1.0, 0.8, 1.0))
	_lathe(st, _scaled(prof, s * 1.1, s), 9, Transform3D(basis, Vector3(0.0, 0.2, 0.6) * s), paint)
	# Cabeza que se levanta delante.
	var head := Vector3(0.0, 0.36, -0.42) * s
	var hp := Paint.new(def.body_color, def.belly_color, head.y)
	var hr: float = 0.24 * s
	_lathe(st, _sphere_profile(hr, 5), 9, Transform3D(Basis.IDENTITY, head - Vector3(0, hr, 0)), hp)
	# Lunares en el lomo.
	for k: int in 6:
		var z: float = lerpf(-0.2, 0.42, float(k) / 5.0) * s
		var x: float = (0.09 if k % 2 == 0 else -0.08) * s
		MeshKit.add_prism(
			st,
			Vector3(x, 0.38 * s - absf(z) * 0.15, z),
			Vector3(x * 0.6, 1.0, 0.0).normalized(),
			0.06 * s,
			0.03 * s,
			0.0,
			6,
			def.accent_color,
			def.accent_color.lightened(0.1),
			rng
		)
	_cheeks(st, def, Vector3(0.17 * s, 0.33 * s, -0.6 * s), 0.045 * s)
	height = 0.95 * s
	stalk_len = 0.3 * s
	eye_pos = PackedVector3Array([Vector3(-0.09, 0.54, -0.5) * s, Vector3(0.09, 0.54, -0.5) * s])
	eye_r = PackedFloat32Array([def.eye_radius, def.eye_radius * 0.92])
	mouth_pos = Vector3(0.0, 0.31, -0.64) * s
	var sst: SurfaceTool = MeshKit.begin()
	MeshKit.add_prism(
		sst,
		Vector3.ZERO,
		Vector3.UP,
		0.028 * s,
		stalk_len,
		0.0,
		5,
		def.body_color,
		def.body_color,
		rng
	)
	stalk = MeshKit.commit(sst)
	hit_center = Vector3(0.0, 0.3 * s, -0.05 * s)
	hit_radius = 0.5 * s


## Cíclope saltarín: una bola con un ojo gigante, cuerno, sonrisa de dientes y patas de muelle.
func _build_cyclops(st: SurfaceTool, def: CritterDef, rng: RandomNumberGenerator) -> void:
	var s: float = def.size
	var prof := PackedVector2Array(
		[
			Vector2(0.24, 0.0),
			Vector2(0.24, 0.14),
			Vector2(0.3, 0.28),
			Vector2(0.44, 0.36),
			Vector2(0.6, 0.37),
			Vector2(0.76, 0.32),
			Vector2(0.88, 0.2),
			Vector2(0.94, 0.0),
		]
	)
	var paint := Paint.new(def.body_color, def.belly_color, 0.5 * s)
	_lathe(st, _scaled(prof, s, s), 10, Transform3D.IDENTITY, paint)
	# Cuerno torcido en la coronilla.
	MeshKit.add_prism(
		st,
		Vector3(0.04, 0.9, 0.02) * s,
		Vector3(0.25, 1.0, 0.1).normalized(),
		0.06 * s,
		0.04 * s,
		0.2 * s,
		5,
		def.accent_color,
		def.accent_color.lightened(0.3),
		rng
	)
	_cheeks(st, def, Vector3(0.27 * s, 0.42 * s, -0.27 * s), 0.05 * s)
	height = 1.05 * s
	eye_pos = PackedVector3Array([Vector3(0.0, 0.64, -0.28) * s])
	eye_r = PackedFloat32Array([def.eye_radius])
	mouth_pos = Vector3(0.0, 0.4, -0.34) * s
	var tst: SurfaceTool = MeshKit.begin()
	for k: int in 4:
		var x: float = (float(k) - 1.5) * 0.06 * s
		MeshKit.add_box(
			tst, Vector3(x, -0.01 * s, -0.012 * s), Vector3(0.04, 0.05, 0.03) * s, C_TOOTH
		)
	teeth = MeshKit.commit(tst)
	leg = _leg_mesh(0.24 * s, 0.04 * s, Vector3(0.08, 0.04, 0.12) * s, def.accent_color)
	leg_pos = PackedVector3Array([Vector3(-0.13, 0.24, 0.0) * s, Vector3(0.13, 0.24, 0.0) * s])
	hit_center = Vector3(0.0, 0.58 * s, 0.0)
	hit_radius = 0.45 * s


# --- Piezas ---------------------------------------------------------------------------------


## Boca en forma de "D" (sonrisa), oscura con el fondo más rojo; mira a -Z. Origen en su centro.
func _mouth_mesh(def: CritterDef) -> ArrayMesh:
	var st: SurfaceTool = MeshKit.begin()
	var w: float = 0.13 * def.size * (1.4 if def.shape == CritterDef.Shape.CYCLOPS else 1.0)
	var h: float = 0.08 * def.size
	var depth: float = 0.03 * def.size
	var rim := PackedVector3Array()
	var n: int = 8
	for i: int in n + 1:
		var a: float = PI * float(i) / float(n)
		rim.append(Vector3(cos(a) * w, -sin(a) * h, 0.0))
	var front := Vector3(0.0, -h * 0.35, -depth)
	var back := Vector3(0.0, -h * 0.35, depth)
	for i: int in n:
		MeshKit.add_tri(st, rim[i], rim[i + 1], front + Vector3(0, 0, -0.001), C_MOUTH, back)
		MeshKit.add_tri(st, rim[i], rim[i + 1], back, C_MOUTH_IN, front)
	return MeshKit.commit(st)


## Lengua rosa que sale hacia delante y cuelga (escala 0 = dentro).
func _tongue_mesh(def: CritterDef) -> ArrayMesh:
	var st: SurfaceTool = MeshKit.begin()
	var s: float = def.size
	MeshKit.add_box(st, Vector3(0.0, -0.03, -0.06) * s, Vector3(0.08, 0.025, 0.12) * s, C_TONGUE)
	MeshKit.add_box(
		st, Vector3(0.0, -0.06, -0.12) * s, Vector3(0.075, 0.06, 0.03) * s, C_TONGUE.darkened(0.1)
	)
	return MeshKit.commit(st)


## Pata: un palito que cuelga de la cadera (el origen) con un pie que apunta a -Z.
static func _leg_mesh(length: float, thick: float, foot: Vector3, col: Color) -> ArrayMesh:
	var st: SurfaceTool = MeshKit.begin()
	MeshKit.add_box(st, Vector3(0.0, -length * 0.5, 0.0), Vector3(thick, length, thick), col)
	MeshKit.add_box(
		st, Vector3(0.0, -length + foot.y * 0.5, -foot.z * 0.3), foot, col.darkened(0.15)
	)
	return MeshKit.commit(st)


## Esqueleto de dibujos animados (el rayo lo enseña): calavera con cuencas, columna y costillas.
func _xray_mesh(def: CritterDef) -> ArrayMesh:
	var st: SurfaceTool = MeshKit.begin()
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var eye_y: float = eye_pos[0].y
	var skull_r: float = hit_radius * 0.55
	var skull := Vector3(0.0, eye_y - skull_r * 0.2, eye_pos[0].z * 0.5)
	var sp := Paint.new(C_BONE, C_BONE, 0.0)
	sp.bottom = C_BONE.darkened(0.1)
	_lathe(
		st,
		_sphere_profile(skull_r, 4),
		8,
		Transform3D(Basis.IDENTITY, skull - Vector3(0, skull_r, 0)),
		sp
	)
	for side: float in [-1.0, 1.0]:
		MeshKit.add_box(
			st,
			skull + Vector3(0.35 * side * skull_r, 0.05 * skull_r, -0.85 * skull_r),
			Vector3(0.36, 0.36, 0.2) * skull_r,
			C_SOCKET
		)
	var neck: float = skull.y - skull_r
	var spine_len: float = maxf(neck - 0.08 * def.size, 0.05)
	MeshKit.add_box(
		st,
		Vector3(0.0, neck - spine_len * 0.5, skull.z * 0.5),
		Vector3(0.06, spine_len, 0.06) * maxf(def.size, 0.5),
		C_BONE
	)
	for k: int in 3:
		var y: float = neck - spine_len * (0.25 + 0.22 * float(k))
		MeshKit.add_box(
			st,
			Vector3(0.0, y, skull.z * 0.5),
			Vector3(hit_radius * (1.0 - 0.15 * float(k)), 0.035 * def.size, 0.05 * def.size),
			C_BONE
		)
	return MeshKit.commit(st)


## Mofletes rosas a los dos lados de la cara (`at` es el derecho).
static func _cheeks(st: SurfaceTool, def: CritterDef, at: Vector3, r: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for side: float in [-1.0, 1.0]:
		var p := Vector3(at.x * side, at.y, at.z)
		var out := Vector3(p.x * 0.6, 0.0, p.z).normalized()
		MeshKit.add_prism(st, p, out, r, r * 0.4, 0.0, 6, def.cheek_color, def.cheek_color, rng)


# --- Torno ----------------------------------------------------------------------------------


## Perfil de torno (x = altura, y = radio) multiplicado.
static func _scaled(
	prof: PackedVector2Array, k_height: float, k_radius: float
) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p: Vector2 in prof:
		out.append(Vector2(p.x * k_height, p.y * k_radius))
	return out


## Esfera de radio `r` como perfil de torno (de abajo arriba, base en 0).
static func _sphere_profile(r: float, rings: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k: int in rings + 1:
		var a: float = PI * float(k) / float(rings)
		out.append(Vector2(r - cos(a) * r, sin(a) * r))
	return out


## Superficie de revolución alrededor del eje Y local (perfil x = altura, y = radio), llevada al
## modelo con `xf`. Las caras se pintan con `paint` mirando su normal ya en el modelo.
static func _lathe(
	st: SurfaceTool, prof: PackedVector2Array, sides: int, xf: Transform3D, paint: Paint
) -> void:
	var rings: Array[PackedVector3Array] = []
	for p: Vector2 in prof:
		var ring := PackedVector3Array()
		for i: int in sides:
			var a: float = TAU * (float(i) + 0.5) / float(sides)
			ring.append(xf * Vector3(sin(a) * p.y, p.x, -cos(a) * p.y))
		rings.append(ring)
	# Las caras miran hacia fuera del centro del cuerpo (también las tapas de arriba y abajo).
	var center: Vector3 = xf * Vector3(0.0, (prof[0].x + prof[prof.size() - 1].x) * 0.5, 0.0)
	for r: int in prof.size() - 1:
		var axis_mid: Vector3 = xf * Vector3(0.0, (prof[r].x + prof[r + 1].x) * 0.5, 0.0)
		for i: int in sides:
			var j: int = (i + 1) % sides
			var a: Vector3 = rings[r][i]
			var b: Vector3 = rings[r][j]
			var c: Vector3 = rings[r + 1][j]
			var d: Vector3 = rings[r + 1][i]
			var mid: Vector3 = (a + b + c + d) * 0.25
			var n: Vector3 = (mid - axis_mid).normalized()
			var col: Color = paint.body
			if r == 0:
				col = paint.bottom
			elif paint.top.a > 0.0 and n.y > 0.75:
				col = paint.top
			elif n.z < -0.45 and mid.y < paint.belly_top:
				col = paint.belly
			elif paint.stripe.a > 0.0 and r % paint.stripe_every == 0:
				col = paint.stripe
			# En los polos el anillo es un punto: add_tri descarta el triángulo vacío.
			MeshKit.add_quad(st, a, b, c, d, col, center)
