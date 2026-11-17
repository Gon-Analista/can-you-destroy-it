@tool
class_name Valley
extends Node3D
## El Valle del Cristal, construido por código: suelo ondulado, bosque de pinos (MultiMesh),
## montañas con nieve, colina con castillo y aldea de tejados rojos. Todo low-poly con colores
## de la paleta del GDD; el render a 640x360 y el contorno lo convierten en pixel art.

const C_GRASS_A := Color("#4fae3f")
const C_GRASS_B := Color("#3f9a3c")
const C_GRASS_C := Color("#5cbf48")
const C_DIRT := Color("#b98d5a")
const C_PINE_DARK := Color("#24663a")
const C_PINE_MID := Color("#2f8a3e")
const C_PINE_LIGHT := Color("#47a84a")
const C_TRUNK := Color("#6b4430")
const C_ROCK := Color("#7d86c9")
const C_ROCK_DARK := Color("#5d63a8")
const C_SNOW := Color("#f2f6ff")
const C_STONE := Color("#e6dddb")
const C_STONE_SHADE := Color("#c9bfc4")
const C_ROOF_BLUE := Color("#2a43a7")
const C_ROOF_BLUE_LIGHT := Color("#3d5fd0")
const C_ROOF_RED := Color("#c8423a")
const C_WALL := Color("#f1e8d8")
const C_BANNER := Color("#c8423a")

@export var seed_value: int = 7
@export var tree_count: int = 900
@export var rebuild: bool = false:
	set(value):
		if value:
			_build()

var _toon: ShaderMaterial


func _ready() -> void:
	_build()


## Altura del terreno: llano en el claro del cristal, sube hacia los bordes del valle.
static func ground_height(x: float, z: float) -> float:
	var r: float = Vector2(x, z).length()
	var rise: float = smoothstep(100.0, 210.0, r) * 24.0
	var waves: float = sin(x * 0.045) * cos(z * 0.05) * 2.2 + sin(x * 0.11 + z * 0.07) * 0.8
	return rise + waves * smoothstep(90.0, 130.0, r)


func _build() -> void:
	for child: Node in get_children():
		child.queue_free()
	_toon = ShaderMaterial.new()
	_toon.shader = preload("res://fx/toon.gdshader")
	_toon.set_shader_parameter("rim", 0.25)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var ground: MeshInstance3D = _add_mesh("Ground", _build_ground(rng))
	var ground_body := StaticBody3D.new()
	ground_body.name = "GroundBody"
	ground_body.collision_layer = 1
	ground_body.collision_mask = 0
	var ground_col := CollisionShape3D.new()
	ground_col.shape = ground.mesh.create_trimesh_shape()
	ground_body.add_child(ground_col)
	add_child(ground_body)
	_add_mesh("Mountains", _build_mountains(rng))
	_add_mesh("CastleHill", _build_castle(rng))
	_add_mesh("Village", _build_village(rng))
	_add_forest(rng)


func _add_mesh(node_name: String, mesh: ArrayMesh) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.material_override = _toon
	add_child(mi)
	return mi


func _build_ground(rng: RandomNumberGenerator) -> ArrayMesh:
	var st: SurfaceTool = MeshKit.begin()
	var size: float = 480.0
	var cells: int = 80
	var step_size: float = size / cells
	var noise := FastNoiseLite.new()
	noise.seed = rng.randi()
	noise.frequency = 0.03
	for iz: int in cells:
		for ix: int in cells:
			var x0: float = -size * 0.5 + ix * step_size
			var z0: float = -size * 0.5 + iz * step_size
			var p: Array[Vector3] = [
				Vector3(x0, 0, z0),
				Vector3(x0 + step_size, 0, z0),
				Vector3(x0 + step_size, 0, z0 + step_size),
				Vector3(x0, 0, z0 + step_size),
			]
			for i: int in 4:
				var q: Vector3 = p[i]
				q.y = ground_height(q.x, q.z)
				p[i] = q
			var center: Vector3 = (p[0] + p[2]) * 0.5
			var n: float = noise.get_noise_2d(center.x, center.z)
			var col: Color = C_GRASS_B
			if n > 0.25:
				col = C_GRASS_C
			elif n < -0.2:
				col = C_GRASS_A.darkened(0.05)
			# Claro alrededor del cristal: tierra pisada en anillo.
			var r: float = Vector2(center.x, center.z).length()
			if (
				r > WorldLayout.CRYSTAL_FOOTPRINT - 2.0
				and r < WorldLayout.CRYSTAL_FOOTPRINT + 3.0
				and rng.randf() < 0.55
			):
				col = C_DIRT
			var below: Vector3 = center - Vector3(0, 5, 0)
			MeshKit.add_tri(st, p[0], p[1], p[2], col, below)
			MeshKit.add_tri(st, p[0], p[2], p[3], col.lightened(0.02), below)
	return MeshKit.commit(st)


func _build_mountains(rng: RandomNumberGenerator) -> ArrayMesh:
	var st: SurfaceTool = MeshKit.begin()
	var count: int = 22
	for i: int in count:
		var ang: float = TAU * float(i) / count + rng.randf_range(-0.08, 0.08)
		var dist: float = rng.randf_range(330.0, 430.0)
		var base := Vector3(cos(ang) * dist, -10.0, sin(ang) * dist)
		var height: float = rng.randf_range(110.0, 190.0)
		var radius: float = rng.randf_range(90.0, 140.0)
		_add_mountain(st, base, radius, height, rng)
	return MeshKit.commit(st)


func _add_mountain(
	st: SurfaceTool, base: Vector3, radius: float, height: float, rng: RandomNumberGenerator
) -> void:
	var sides: int = 7
	var apex: Vector3 = base + Vector3(rng.randf_range(-15, 15), height, rng.randf_range(-15, 15))
	var ring: PackedVector3Array = []
	var mid_ring: PackedVector3Array = []
	for i: int in sides:
		var a: float = TAU * float(i) / sides + rng.randf_range(-0.2, 0.2)
		var r: float = radius * rng.randf_range(0.75, 1.15)
		var p: Vector3 = base + Vector3(cos(a) * r, 0, sin(a) * r)
		ring.append(p)
		mid_ring.append(
			(
				p.lerp(apex, rng.randf_range(0.48, 0.62))
				+ Vector3(rng.randf_range(-8, 8), 0, rng.randf_range(-8, 8))
			)
		)
	var inside: Vector3 = base + Vector3(0, height * 0.3, 0)
	var snow_line: float = base.y + height * 0.62
	for i: int in sides:
		var j: int = (i + 1) % sides
		var shade: Color = C_ROCK if i % 2 == 0 else C_ROCK_DARK
		MeshKit.add_quad(st, ring[i], ring[j], mid_ring[j], mid_ring[i], shade, inside)
		var top_col: Color = (
			C_SNOW if (mid_ring[i].y + mid_ring[j].y + apex.y) / 3.0 > snow_line else shade
		)
		MeshKit.add_tri(st, mid_ring[i], mid_ring[j], apex, top_col, inside)


func _build_castle(rng: RandomNumberGenerator) -> ArrayMesh:
	var st: SurfaceTool = MeshKit.begin()
	var hill_base := Vector3(85.0, -5.0, -215.0)
	var hill_h: float = 62.0
	# Colina rocosa con laderas verdes.
	var sides: int = 9
	var top_center: Vector3 = hill_base + Vector3(0, hill_h, 0)
	var ring: PackedVector3Array = []
	var shoulder: PackedVector3Array = []
	var plateau: PackedVector3Array = []
	for i: int in sides:
		var a: float = TAU * float(i) / sides
		ring.append(hill_base + Vector3(cos(a), 0, sin(a)) * rng.randf_range(75, 90))
		shoulder.append(
			(
				hill_base
				+ Vector3(
					cos(a) * rng.randf_range(42, 52),
					hill_h * rng.randf_range(0.55, 0.7),
					sin(a) * rng.randf_range(42, 52)
				)
			)
		)
		plateau.append(top_center + Vector3(cos(a), 0, sin(a)) * rng.randf_range(22, 26))
	var inside: Vector3 = hill_base + Vector3(0, hill_h * 0.3, 0)
	for i: int in sides:
		var j: int = (i + 1) % sides
		MeshKit.add_quad(
			st,
			ring[i],
			ring[j],
			shoulder[j],
			shoulder[i],
			C_GRASS_B if i % 3 else C_PINE_MID,
			inside
		)
		MeshKit.add_quad(
			st,
			shoulder[i],
			shoulder[j],
			plateau[j],
			plateau[i],
			C_ROCK if i % 2 else C_STONE_SHADE,
			inside
		)
		MeshKit.add_tri(
			st, plateau[i], plateau[j], top_center, C_GRASS_A, inside - Vector3(0, 30, 0)
		)
	# Castillo: murallas, torres con tejados azules y torre del homenaje.
	var c: Vector3 = top_center
	MeshKit.add_box(st, c + Vector3(0, 4, 0), Vector3(30, 8, 22), C_STONE, C_STONE_SHADE)
	var towers: Array[Vector4] = [
		Vector4(-15, 0, -11, 14),
		Vector4(15, 0, -11, 16),
		Vector4(-15, 0, 11, 13),
		Vector4(15, 0, 11, 15),
		Vector4(-6, 0, -4, 26),
		Vector4(6, 0, 3, 22),
		Vector4(0, 0, -2, 38),
	]
	for t: Vector4 in towers:
		var base: Vector3 = c + Vector3(t.x, 0, t.z)
		var r: float = 3.2 if t.w < 30 else 4.0
		MeshKit.add_prism(st, base, Vector3.UP, r, t.w, 0.0, 8, C_STONE, C_STONE_SHADE, rng)
		var roof_col: Color = C_ROOF_BLUE if int(t.w) % 2 == 0 else C_ROOF_BLUE_LIGHT
		MeshKit.add_prism(
			st,
			base + Vector3(0, t.w, 0),
			Vector3.UP,
			r * 1.25,
			0.01,
			r * 2.6,
			8,
			roof_col,
			roof_col,
			rng
		)
		MeshKit.add_box(
			st, base + Vector3(0, t.w * 0.6, r + 0.05), Vector3(1.6, 4.0, 0.2), C_BANNER
		)
	return MeshKit.commit(st)


func _build_village(rng: RandomNumberGenerator) -> ArrayMesh:
	var st: SurfaceTool = MeshKit.begin()
	var clusters: Array[Vector3] = [
		Vector3(-85, 0, -105), Vector3(-130, 0, -30), Vector3(75, 0, -135)
	]
	for cl: Vector3 in clusters:
		for i: int in 6:
			var p: Vector3 = cl + Vector3(rng.randf_range(-16, 16), 0, rng.randf_range(-12, 12))
			p.y = ground_height(p.x, p.z)
			var size := Vector3(
				rng.randf_range(4, 7), rng.randf_range(3, 4.5), rng.randf_range(4, 6)
			)
			MeshKit.add_box(st, p + Vector3(0, size.y * 0.5, 0), size, C_WALL)
			MeshKit.add_gable_roof(
				st,
				p + Vector3(0, size.y, 0),
				size * Vector3(1.15, 1, 1.15),
				size.x * 0.45,
				C_ROOF_RED
			)
		# Campanario de la aldea.
		var bell_pos: Vector3 = cl + Vector3(0, ground_height(cl.x, cl.z), 0)
		MeshKit.add_box(st, bell_pos + Vector3(0, 5, 0), Vector3(3, 10, 3), C_WALL)
		MeshKit.add_prism(
			st,
			bell_pos + Vector3(0, 10, 0),
			Vector3.UP,
			2.4,
			0.01,
			4.5,
			4,
			C_ROOF_RED,
			C_ROOF_RED,
			rng
		)
	return MeshKit.commit(st)


func _build_pine_mesh() -> ArrayMesh:
	var st: SurfaceTool = MeshKit.begin()
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	MeshKit.add_box(st, Vector3(0, 0.6, 0), Vector3(0.45, 1.2, 0.45), C_TRUNK)
	MeshKit.add_cone(st, Vector3(0, 1.0, 0), 1.9, 2.6, 7, C_PINE_DARK, rng, 0.08)
	MeshKit.add_cone(st, Vector3(0, 2.4, 0), 1.5, 2.3, 7, C_PINE_MID, rng, 0.08)
	MeshKit.add_cone(st, Vector3(0, 3.7, 0), 1.0, 2.1, 7, C_PINE_LIGHT, rng, 0.08)
	return MeshKit.commit(st)


func _add_forest(rng: RandomNumberGenerator) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _build_pine_mesh()
	var noise := FastNoiseLite.new()
	noise.seed = rng.randi()
	noise.frequency = 0.02
	var xforms: Array[Transform3D] = []
	var attempts: int = 0
	while xforms.size() < tree_count and attempts < tree_count * 8:
		attempts += 1
		var ang: float = rng.randf() * TAU
		var r: float = rng.randf_range(98.0, 215.0)
		var x: float = cos(ang) * r
		var z: float = sin(ang) * r
		# El bosque se agrupa en manchas y deja libre la vista hacia el castillo y el cristal.
		if noise.get_noise_2d(x, z) < -0.05:
			continue
		if z > 10.0 and absf(x) < 60.0:
			continue
		# Ni encima del Pilón ni del Santuario.
		if (
			Vector2(x - WorldLayout.PYLON.x, z - WorldLayout.PYLON.z).length() < 9.0
			or Vector2(x - WorldLayout.SANCTUM.x, z - WorldLayout.SANCTUM.z).length() < 10.0
		):
			continue
		var s: float = rng.randf_range(1.6, 3.2)
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(
			Vector3(s, s * rng.randf_range(0.9, 1.25), s)
		)
		xforms.append(Transform3D(basis, Vector3(x, ground_height(x, z) - 0.2, z)))
	mm.instance_count = xforms.size()
	for i: int in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Forest"
	mmi.multimesh = mm
	mmi.material_override = _toon
	add_child(mmi)
