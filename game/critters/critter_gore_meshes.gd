class_name CritterGoreMeshes
extends RefCounted
## Mallas del reventón de los bichos (`CritterGore`): pegotes de baba, manchas, esquirlas de hielo,
## dientes, huesitos y los ojos en X de la almita. Blancas o con su color por vértice; el color de
## cada trozo lo pone el tinte por instancia de `critter_toon.gdshader`.


## Pegote de baba: esfera low-poly abollada (`k` cambia la abolladura).
static func blob_mesh(k: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 50 + k
	var st: SurfaceTool = MeshKit.begin()
	var rings: int = 4
	var sides: int = 6
	var pts: Array[PackedVector3Array] = []
	for r: int in rings + 1:
		var a: float = PI * float(r) / float(rings)
		var ring := PackedVector3Array()
		for i: int in sides:
			var b: float = TAU * float(i) / float(sides) + float(r) * 0.5
			var rad: float = sin(a) * rng.randf_range(0.75, 1.15)
			ring.append(
				Vector3(cos(b) * rad, -cos(a) * rng.randf_range(0.8, 1.1), sin(b) * rad) * 0.5
			)
		pts.append(ring)
	for r: int in rings:
		for i: int in sides:
			var j: int = (i + 1) % sides
			MeshKit.add_quad(
				st, pts[r][i], pts[r][j], pts[r + 1][j], pts[r + 1][i], Color.WHITE, Vector3.ZERO
			)
	return MeshKit.commit(st)


## Mancha: disco irregular con salpicaduras alrededor, a ras del suelo (radio 1 m).
static func splat_mesh(k: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 90 + k
	var st: SurfaceTool = MeshKit.begin()
	var below := Vector3(0.0, -1.0, 0.0)
	var n: int = 12
	var rim := PackedVector3Array()
	for i: int in n:
		var a: float = TAU * float(i) / float(n)
		var r: float = rng.randf_range(0.55, 1.0) if i % 2 else rng.randf_range(0.35, 0.6)
		rim.append(Vector3(cos(a) * r, 0.0, sin(a) * r) * 0.5)
	for i: int in n:
		MeshKit.add_tri(st, Vector3.ZERO, rim[i], rim[(i + 1) % n], Color.WHITE, below)
	for d: int in 4:
		var a: float = rng.randf() * TAU
		var c := Vector3(cos(a), 0.0, sin(a)) * rng.randf_range(0.6, 0.85)
		var r: float = rng.randf_range(0.05, 0.1)
		for i: int in 6:
			var a0: float = TAU * float(i) / 6.0
			var a1: float = TAU * float(i + 1) / 6.0
			MeshKit.add_tri(
				st,
				c,
				c + Vector3(cos(a0), 0, sin(a0)) * r,
				c + Vector3(cos(a1), 0, sin(a1)) * r,
				Color.WHITE,
				c + below
			)
	return MeshKit.commit(st)


static func ice_shard_mesh() -> ArrayMesh:
	var st: SurfaceTool = MeshKit.begin()
	var rng := RandomNumberGenerator.new()
	rng.seed = 12
	MeshKit.add_prism(
		st, Vector3(0, -0.4, 0), Vector3.UP, 0.22, 0.5, 0.35, 4, Color.WHITE, Color.WHITE, rng, 0.2
	)
	return MeshKit.commit(st)


static func tooth() -> ArrayMesh:
	var st: SurfaceTool = MeshKit.begin()
	MeshKit.add_box(st, Vector3.ZERO, Vector3(0.07, 0.09, 0.035), CritterRig.C_TOOTH)
	return MeshKit.commit(st)


static func bone() -> ArrayMesh:
	var st: SurfaceTool = MeshKit.begin()
	var c: Color = CritterRig.C_BONE
	MeshKit.add_box(st, Vector3.ZERO, Vector3(0.2, 0.035, 0.035), c)
	for x: float in [-0.11, 0.11]:
		for z: float in [-0.025, 0.025]:
			MeshKit.add_box(st, Vector3(x, 0.0, z), Vector3(0.05, 0.05, 0.045), c)
	return MeshKit.commit(st)


## Dos "X" pequeñas (los ojos de la almita), mirando a -Z, a los lados del centro.
static func x_eyes_mesh() -> ArrayMesh:
	var st: SurfaceTool = MeshKit.begin()
	for side: float in [-1.0, 1.0]:
		var c := Vector3(0.12 * side, 0.0, 0.0)
		for a: float in [PI * 0.25, -PI * 0.25]:
			var d := Vector3(cos(a), sin(a), 0.0) * 0.06
			var w := Vector3(-sin(a), cos(a), 0.0) * 0.015
			var f := Vector3(0, 0, -0.01)
			MeshKit.add_quad(
				st,
				c - d - w + f,
				c + d - w + f,
				c + d + w + f,
				c - d + w + f,
				Color.WHITE,
				c - f * 3.0
			)
	return MeshKit.commit(st)
