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
const C_LEAF_DARK := Color("#2f7d3a")
const C_LEAF_MID := Color("#46a046")
const C_LEAF_LIGHT := Color("#6cc152")
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

## Lado de los trozos del bosque (ver ChunkedMultiMesh).
const FOREST_CELL_M: float = 48.0

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
	# Toon con textura pixel art procedural (hierba, roca, hojas...; ver terrain.gdshader).
	_toon = ShaderMaterial.new()
	_toon.shader = preload("res://world/terrain.gdshader")
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
	var cells: int = 96
	var step_size: float = size / cells
	var grass: Color = MeshKit.tag(C_GRASS_B, MeshKit.PAT_GRASS)
	var dirt: Color = MeshKit.tag(C_DIRT, MeshKit.PAT_DIRT)
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
			var nrm: Array[Vector3] = []
			for i: int in 4:
				var q: Vector3 = p[i]
				q.y = ground_height(q.x, q.z)
				p[i] = q
				nrm.append(ground_normal(q.x, q.z))
			var center: Vector3 = (p[0] + p[2]) * 0.5
			# El color sólo dice qué dibujar: las manchas de hierba las pone el shader.
			var col: Color = grass
			# Claro alrededor del cristal: tierra pisada en anillo.
			var r: float = Vector2(center.x, center.z).length()
			if (
				r > WorldLayout.CRYSTAL_FOOTPRINT - 2.0
				and r < WorldLayout.CRYSTAL_FOOTPRINT + 3.0
				and rng.randf() < 0.55
			):
				col = dirt
			var below: Vector3 = center - Vector3(0, 5, 0)
			MeshKit.add_tri_smooth(st, p[0], p[1], p[2], nrm[0], nrm[1], nrm[2], col, below)
			MeshKit.add_tri_smooth(st, p[0], p[2], p[3], nrm[0], nrm[2], nrm[3], col, below)
	return MeshKit.commit(st)


## Normal suave del terreno (diferencias centradas): el suelo deja de verse a facetas.
static func ground_normal(x: float, z: float) -> Vector3:
	var e: float = 0.5
	var dx: float = ground_height(x + e, z) - ground_height(x - e, z)
	var dz: float = ground_height(x, z + e) - ground_height(x, z - e)
	return Vector3(-dx, 2.0 * e, -dz).normalized()


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


## Montaña de laderas suaves y cima redondeada (rejilla radial con normales suaves). La nieve
## la pinta el shader por encima de su `snow_line`, con el borde tramado.
func _add_mountain(
	st: SurfaceTool, base: Vector3, radius: float, height: float, rng: RandomNumberGenerator
) -> void:
	var rings: int = 8
	var segs: int = 16
	var noise := FastNoiseLite.new()
	noise.seed = rng.randi()
	noise.frequency = 0.9
	var apex_off := Vector3(rng.randf_range(-15, 15), 0.0, rng.randf_range(-15, 15))
	var rows: Array[PackedVector3Array] = []
	for k: int in rings + 1:
		var t: float = float(k) / float(rings)
		# Cima redonda (pendiente cero arriba) y pie que se abre, como una montaña gastada.
		var prof: float = lerpf(pow(cos(t * PI * 0.5), 1.7), pow(1.0 - t, 1.3), 0.6)
		var row := PackedVector3Array()
		for j: int in segs:
			var a: float = TAU * float(j) / float(segs)
			var dir := Vector3(cos(a), 0.0, sin(a))
			var wob: float = noise.get_noise_2d(cos(a) * 2.0, sin(a) * 2.0)
			var r: float = radius * t * (1.0 + wob * 0.35)
			var ridge: float = noise.get_noise_3d(dir.x * 3.0, t * 4.0, dir.z * 3.0)
			var y: float = height * prof + ridge * height * 0.12 * sin(t * PI)
			row.append(base + apex_off * (1.0 - t) + dir * r + Vector3(0.0, y, 0.0))
		rows.append(row)
	var rock: Color = MeshKit.tag(C_ROCK, MeshKit.PAT_SNOWY_ROCK)
	var rock_dark: Color = MeshKit.tag(C_ROCK_DARK, MeshKit.PAT_SNOWY_ROCK)
	var cols: Array[Color] = [rock, rock, rock, rock, rock, rock, rock_dark, rock_dark]
	var snow_y: float = base.y + height * rng.randf_range(0.6, 0.72)
	MeshKit.add_grid(
		st, rows, cols, base + Vector3(0.0, height * 0.2, 0.0), true, Vector2(snow_y, 0.0)
	)


func _build_castle(rng: RandomNumberGenerator) -> ArrayMesh:
	var st: SurfaceTool = MeshKit.begin()
	var hill_base := Vector3(85.0, -5.0, -215.0)
	var hill_h: float = 62.0
	# Colina redondeada: meseta llana para el castillo y laderas de hierba que el shader vuelve
	# roca donde la cuesta es fuerte.
	var top_center: Vector3 = hill_base + Vector3(0, hill_h, 0)
	var radii: Array[float] = [0.0, 12.0, 22.0, 27.0, 36.0, 46.0, 58.0, 70.0, 82.0, 92.0]
	var heights: Array[float] = [1.0, 1.0, 1.0, 0.97, 0.84, 0.64, 0.42, 0.22, 0.07, 0.0]
	var noise := FastNoiseLite.new()
	noise.seed = rng.randi()
	noise.frequency = 0.8
	var segs: int = 18
	var rows: Array[PackedVector3Array] = []
	for k: int in radii.size():
		var row := PackedVector3Array()
		for j: int in segs:
			var a: float = TAU * float(j) / float(segs)
			var wob: float = 1.0 + noise.get_noise_2d(cos(a) * 2.0, sin(a) * 2.0) * 0.18
			var r: float = radii[k] * (wob if k > 2 else 1.0)
			row.append(hill_base + Vector3(cos(a) * r, hill_h * heights[k], sin(a) * r))
		rows.append(row)
	var hill_col: Array[Color] = [MeshKit.tag(C_GRASS_B, MeshKit.PAT_GRASS)]
	MeshKit.add_grid(st, rows, hill_col, hill_base + Vector3(0, hill_h * 0.3, 0))
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


## Abeto de copa blanda: pisos redondeados con el borde ondulado (no conos de punta), punta roma
## y normales suaves para que la luz en bandas lo modele. Hojas y corteza con textura del shader.
func _build_pine_mesh(variant: int) -> ArrayMesh:
	var st: SurfaceTool = MeshKit.begin()
	var rng := RandomNumberGenerator.new()
	rng.seed = 3 + variant * 17
	_add_trunk(st, 0.24, 0.17, 1.6, rng)
	var greens: Array[Color] = [C_PINE_DARK, C_PINE_MID, C_PINE_MID, C_PINE_LIGHT]
	# (base, alto, radio) de cada piso, de abajo a arriba.
	var tiers: Array[Vector3] = [
		Vector3(0.9, 2.2, 1.95),
		Vector3(2.0, 2.0, 1.55),
		Vector3(3.0, 1.8, 1.15),
		Vector3(3.9, 1.7, 0.75)
	]
	if variant == 1:
		tiers = [
			Vector3(0.8, 2.0, 1.7),
			Vector3(1.8, 2.0, 1.4),
			Vector3(2.9, 1.9, 1.0),
			Vector3(3.8, 1.5, 0.6)
		]
	for i: int in tiers.size():
		var t: Vector3 = tiers[i]
		_add_fir_tier(st, t.x, t.y, t.z, i == tiers.size() - 1, greens[i], rng)
	return ChunkedMultiMesh.with_lods(st)


func _add_trunk(
	st: SurfaceTool, r0: float, r1: float, h: float, rng: RandomNumberGenerator
) -> void:
	var rows: Array[PackedVector3Array] = []
	for k: int in 3:
		var t: float = float(k) / 2.0
		var row := PackedVector3Array()
		for j: int in 7:
			var a: float = TAU * float(j) / 7.0
			var r: float = lerpf(r0, r1, t) * (1.0 + rng.randf_range(-0.08, 0.08))
			row.append(Vector3(cos(a) * r, -0.3 + h * t, sin(a) * r))
		rows.append(row)
	var bark: Array[Color] = [MeshKit.tag(C_TRUNK, MeshKit.PAT_BARK)]
	MeshKit.add_grid(st, rows, bark, Vector3(0.0, h * 0.5, 0.0))


## Un piso del abeto: falda redondeada (perfil curvo) con el borde en ondas suaves y el bajo
## cerrado y oscuro. El de arriba acaba en una punta roma.
func _add_fir_tier(
	st: SurfaceTool,
	y0: float,
	h: float,
	radius: float,
	top: bool,
	col: Color,
	rng: RandomNumberGenerator
) -> void:
	var segs: int = 14
	var phase: float = rng.randf() * TAU
	var waves: float = 4.0 if radius > 1.0 else 3.0
	var rows: Array[PackedVector3Array] = []
	# Perfil: (fracción del radio, fracción de la altura) de arriba a abajo.
	var prof: Array[Vector2] = [
		Vector2(0.0, 1.0),
		Vector2(0.3, 0.93),
		Vector2(0.55, 0.72),
		Vector2(0.8, 0.4),
		Vector2(1.0, 0.0)
	]
	if top:
		prof = [
			Vector2(0.0, 1.0),
			Vector2(0.38, 0.9),
			Vector2(0.62, 0.68),
			Vector2(0.84, 0.36),
			Vector2(1.0, 0.0)
		]
	var hem := PackedVector3Array()
	for pk: int in prof.size():
		var row := PackedVector3Array()
		for j: int in segs:
			var a: float = phase + TAU * float(j) / float(segs)
			var wave: float = cos(a * waves) * prof[pk].x
			var r: float = radius * prof[pk].x * (1.0 + wave * 0.09)
			var y: float = y0 + h * prof[pk].y - (0.12 + wave * 0.1) * prof[pk].x * h * 0.5
			row.append(Vector3(cos(a) * r, y, sin(a) * r))
		rows.append(row)
		if pk == prof.size() - 1:
			hem = row
	var leaf: Color = MeshKit.tag(col, MeshKit.PAT_LEAVES)
	MeshKit.add_grid(st, rows, [leaf], Vector3(0.0, y0 + h * 0.2, 0.0))
	# Bajo del piso: del borde hacia el tronco, un poco hacia arriba (sombra bajo las ramas).
	var under := PackedVector3Array()
	for j: int in segs:
		var a: float = phase + TAU * float(j) / float(segs)
		under.append(Vector3(cos(a) * radius * 0.25, y0 + h * 0.18, sin(a) * radius * 0.25))
	var under_rows: Array[PackedVector3Array] = [hem, under]
	var shade: Color = MeshKit.tag(col.darkened(0.35), MeshKit.PAT_LEAVES)
	MeshKit.add_grid(st, under_rows, [shade], Vector3(0.0, y0 + h * 0.8, 0.0))


## Árbol de hoja ancha: tronco corto y copa de varias bolas blandas (más clara arriba).
func _build_broadleaf_mesh(variant: int) -> ArrayMesh:
	var st: SurfaceTool = MeshKit.begin()
	var rng := RandomNumberGenerator.new()
	rng.seed = 41 + variant * 23
	_add_trunk(st, 0.3, 0.2, 2.9, rng)
	var dark: Color = MeshKit.tag(C_LEAF_DARK if variant == 0 else C_PINE_MID, MeshKit.PAT_LEAVES)
	var mid: Color = MeshKit.tag(C_LEAF_MID if variant == 0 else C_GRASS_B, MeshKit.PAT_LEAVES)
	var light: Color = MeshKit.tag(C_LEAF_LIGHT if variant == 0 else C_GRASS_C, MeshKit.PAT_LEAVES)
	# (x, y, z, radio) de cada bola de la copa.
	var blobs: Array[Vector4] = [
		Vector4(0.0, 3.5, 0.0, 1.75),
		Vector4(1.05, 3.0, 0.45, 1.15),
		Vector4(-0.95, 3.1, -0.4, 1.2),
		Vector4(0.15, 3.0, -1.0, 1.05),
		Vector4(-0.2, 4.5, 0.25, 1.2),
	]
	if variant == 1:
		blobs = [
			Vector4(0.0, 3.8, 0.0, 1.6),
			Vector4(0.9, 3.2, -0.3, 1.1),
			Vector4(-0.7, 3.3, 0.7, 1.1),
			Vector4(0.1, 4.9, 0.0, 1.05),
		]
	for b: Vector4 in blobs:
		var cols: Array[Color] = [light, mid, mid, dark]
		if b.y < 3.2:
			cols = [mid, mid, dark, dark]
		MeshKit.add_blob(
			st, Vector3(b.x, b.y, b.z), b.w, Vector3(1.0, 0.86, 1.0), 5, 10, cols, rng, 0.1
		)
	return ChunkedMultiMesh.with_lods(st)


func _add_forest(rng: RandomNumberGenerator) -> void:
	# Cuatro modelos: dos abetos y dos árboles de copa redonda, cada uno en su MultiMesh.
	var meshes: Array[ArrayMesh] = [
		_build_pine_mesh(0), _build_pine_mesh(1), _build_broadleaf_mesh(0), _build_broadleaf_mesh(1)
	]
	var xforms: Array[Array] = [[], [], [], []]
	var tints: Array[Array] = [[], [], [], []]
	var noise := FastNoiseLite.new()
	noise.seed = rng.randi()
	noise.frequency = 0.02
	var placed: int = 0
	var attempts: int = 0
	while placed < tree_count and attempts < tree_count * 8:
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
		# Copas redondas sobre todo en el linde del claro; abetos más adentro y monte arriba.
		var broad_chance: float = lerpf(0.6, 0.15, smoothstep(110.0, 190.0, r))
		var kind: int = (2 if rng.randf() < broad_chance else 0) + rng.randi_range(0, 1)
		var s: float = rng.randf_range(1.6, 3.0) if kind < 2 else rng.randf_range(1.3, 2.1)
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(
			Vector3(s, s * rng.randf_range(0.9, 1.2), s)
		)
		var list: Array = xforms[kind]
		list.append(Transform3D(basis, Vector3(x, ground_height(x, z) - 0.2, z)))
		var v: float = rng.randf_range(0.88, 1.08)
		var tint_list: Array = tints[kind]
		tint_list.append(Color(v, v * rng.randf_range(0.97, 1.03), v * 0.97, 1.0))
		placed += 1
	# Por trozos de 48 m: la cámara y las sombras descartan los que no ven.
	for k: int in meshes.size():
		ChunkedMultiMesh.build(
			self,
			"Forest%d" % k,
			meshes[k],
			xforms[k],
			tints[k],
			_toon,
			FOREST_CELL_M,
			GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		)
