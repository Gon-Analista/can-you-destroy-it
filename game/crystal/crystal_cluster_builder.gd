class_name CrystalClusterBuilder
extends RefCounted
## Genera la malla del Cristal Madre: un racimo de prismas hexagonales con punta, inspirado en
## docs/referencias/cristal_referencia.png (punta principal enorme, puntas secundarias inclinadas
## hacia fuera y un racimo pequeño en la base). Devuelve la malla y un casco convexo por punta.

## base (x, y, z), eje (x, y, z), radio, altura, punta
const SPIRES: Array[Array] = [
	[Vector3(0.0, -1.0, 0.0), Vector3(0.1, 1.0, 0.04), 3.1, 19.0, 6.0],
	[Vector3(-3.4, -1.0, 0.9), Vector3(-0.6, 1.0, 0.18), 2.0, 8.5, 3.2],
	[Vector3(-1.6, -1.0, -2.8), Vector3(-0.3, 1.0, -0.55), 1.7, 7.5, 2.6],
	[Vector3(1.9, -1.0, -2.5), Vector3(0.4, 1.0, -0.5), 1.4, 6.0, 2.2],
	[Vector3(3.1, -1.0, 0.6), Vector3(0.75, 1.0, 0.12), 1.5, 5.2, 2.3],
	[Vector3(3.8, -1.0, -1.3), Vector3(0.95, 1.0, -0.35), 0.95, 3.4, 1.6],
	[Vector3(-2.1, -1.0, 2.7), Vector3(-0.45, 1.0, 0.85), 1.25, 4.2, 1.9],
	[Vector3(0.9, -1.0, 2.9), Vector3(0.18, 1.0, 0.95), 1.05, 3.3, 1.5],
	[Vector3(2.6, -1.0, 2.2), Vector3(0.7, 1.0, 0.7), 0.8, 2.6, 1.2],
	# Racimo pequeño de la base (abajo a la izquierda en la referencia).
	[Vector3(-4.6, -0.6, 2.2), Vector3(-1.0, 0.8, 0.5), 0.6, 1.8, 0.9],
	[Vector3(-4.0, -0.6, 3.2), Vector3(-0.5, 0.7, 1.0), 0.5, 1.5, 0.8],
	[Vector3(-5.2, -0.6, 1.0), Vector3(-1.0, 0.6, -0.1), 0.45, 1.4, 0.7],
	[Vector3(-3.2, -0.6, 3.8), Vector3(-0.2, 0.9, 1.0), 0.4, 1.2, 0.6],
	[Vector3(4.6, -0.6, 0.9), Vector3(1.0, 0.7, 0.3), 0.5, 1.6, 0.8],
	[Vector3(4.2, -0.6, 2.0), Vector3(0.8, 0.8, 0.9), 0.4, 1.2, 0.6],
]

var mesh: ArrayMesh
var hulls: Array[PackedVector3Array] = []


func build(scale: float, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var st: SurfaceTool = MeshKit.begin()
	hulls.clear()
	for spec: Array in SPIRES:
		var base: Vector3 = spec[0]
		var axis: Vector3 = spec[1]
		var radius: float = spec[2]
		var height: float = spec[3]
		var tip: float = spec[4]
		var pts: PackedVector3Array = MeshKit.add_prism(
			st,
			base * scale,
			axis,
			radius * scale,
			height * scale,
			tip * scale,
			6,
			Color.WHITE,
			Color.WHITE,
			rng,
			0.08,
			rng.randf_range(0.82, 0.95)
		)
		hulls.append(pts)
	mesh = MeshKit.commit(st)


## Malla de un fragmento suelto: prisma pentagonal irregular con punta.
static func build_shard_mesh(seed_value: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var st: SurfaceTool = MeshKit.begin()
	var r: float = rng.randf_range(0.22, 0.32)
	var h: float = rng.randf_range(0.35, 0.55)
	var axis := Vector3(rng.randf_range(-0.2, 0.2), 1.0, rng.randf_range(-0.2, 0.2)).normalized()
	MeshKit.add_prism(
		st, Vector3.ZERO, axis, r, h * 0.5, h * 0.6, 5, Color.WHITE, Color.WHITE, rng, 0.2, 0.9
	)
	return MeshKit.commit(st)
