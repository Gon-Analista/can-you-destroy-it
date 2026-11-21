class_name CrystalVolume
extends RefCounted
## El volumen del Cristal Madre: una rejilla 3D con la distancia firmada a la superficie
## (`sdf`, negativa dentro) que cada golpe erosiona, y la profundidad bajo la superficie
## original (`depth`) que decide la capa. Horneado por `tools/crystal_volume.py`.
##
## La malla se rehace por trozos (`CHUNK`^3 celdas) con "surface nets": un vértice por celda
## que corta la superficie y un cuadrilátero por arista cortada. Las caras planas del cristal
## original se conservan; lo excavado queda facetado. `mesh_chunk` es estática y no toca nada
## compartido: se puede llamar desde otro hilo con una copia (COW) de la rejilla.

const PATH: String = "res://crystal/data/crystal_volume.bin"
## Vértices de las 12 aristas de una celda (índices de esquina 0..7, bit 0 = x, 1 = y, 2 = z).
const EDGES: PackedInt32Array = [
	0, 1, 2, 3, 4, 5, 6, 7, 0, 2, 1, 3, 4, 6, 5, 7, 0, 4, 1, 5, 2, 6, 3, 7
]

var size: Vector3i
var cell: float
var origin: Vector3
var chunk: int
var chunks: Vector3i
var sdf: PackedFloat32Array
var depth: PackedFloat32Array
## Por capa (de fuera a dentro): profundidad mínima, esencia por m3 e id.
var layer_min_depth: PackedFloat32Array = []
var layer_density: PackedFloat32Array = []
var layer_ids: Array[StringName] = []
var core_center: Vector3
var core_radius: float
var top: float
var geodes: Array[Dictionary] = []
var surface_chunks: PackedInt32Array = []


func load_baked(path: String = PATH) -> bool:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("CrystalVolume: no se puede abrir %s" % path)
		return false
	var header: Dictionary = JSON.parse_string(f.get_line())
	var saved_size: Array = header["size"]
	var s := PackedInt32Array(saved_size)
	size = Vector3i(s[0], s[1], s[2])
	cell = VariantCast.to_float(header["cell"])
	origin = _vec3(header["origin"])
	chunk = VariantCast.to_int(header["chunk"])
	@warning_ignore("integer_division")
	chunks = (size - Vector3i.ONE) / chunk
	core_center = _vec3(header["core_center"])
	core_radius = VariantCast.to_float(header["core_radius"])
	top = VariantCast.to_float(header["top"])
	for l: Dictionary in header["layers"]:
		layer_ids.append(StringName(str(l["id"])))
		layer_min_depth.append(VariantCast.to_float(l["min_depth"]))
		layer_density.append(VariantCast.to_float(l["density"]))
	for g: Dictionary in header["geodes"]:
		geodes.append({"center": _vec3(g["center"]), "radius": VariantCast.to_float(g["radius"])})
	var saved_chunks: Array = header["surface_chunks"]
	surface_chunks = PackedInt32Array(saved_chunks)
	var n: int = size.x * size.y * size.z
	var sb: PackedByteArray = f.get_buffer(VariantCast.to_int(header["sdf_bytes"]))
	var db: PackedByteArray = f.get_buffer(VariantCast.to_int(header["depth_bytes"]))
	sdf = _halfs(sb.decompress(n * 2, FileAccess.COMPRESSION_GZIP))
	depth = _halfs(db.decompress(n * 2, FileAccess.COMPRESSION_GZIP))
	return sdf.size() == n and depth.size() == n


## Un `[x, y, z]` del JSON del horneado como vector.
static func _vec3(xyz: Variant) -> Vector3:
	var a: Array = xyz
	var p := PackedFloat64Array(a)
	return Vector3(p[0], p[1], p[2])


## float16 -> float32 en C++ (con Image), mucho más rápido que decodificar en GDScript.
## Por lonchas de z: una imagen no puede pasar de 16384 píxeles de alto.
func _halfs(bytes: PackedByteArray) -> PackedFloat32Array:
	@warning_ignore("integer_division")
	var slab: int = maxi(1, 16384 / size.y)
	var out := PackedByteArray()
	var z: int = 0
	while z < size.z:
		var nz: int = mini(slab, size.z - z)
		var from: int = z * size.x * size.y * 2
		var part: PackedByteArray = bytes.slice(from, from + nz * size.x * size.y * 2)
		var img := Image.create_from_data(size.x, size.y * nz, false, Image.FORMAT_RH, part)
		img.convert(Image.FORMAT_RF)
		out.append_array(img.get_data())
		z += nz
	return out.to_float32_array()


## Estado actual para la partida guardada (sólo cambia `sdf`).
func state_bytes() -> PackedByteArray:
	return sdf.to_byte_array().compress(FileAccess.COMPRESSION_ZSTD)


func load_state(bytes: PackedByteArray) -> bool:
	var raw: PackedByteArray = bytes.decompress(
		size.x * size.y * size.z * 4, FileAccess.COMPRESSION_ZSTD
	)
	var values: PackedFloat32Array = raw.to_float32_array()
	if values.size() != sdf.size():
		return false
	sdf = values
	return true


func index(x: int, y: int, z: int) -> int:
	return x + size.x * (y + size.y * z)


## Punto de la rejilla más cercano (puede caer fuera).
func to_grid(p: Vector3) -> Vector3:
	return (p - origin) / cell


## Valor interpolado de `arr` en `p` (local al cristal). Fuera de la rejilla: `outside`.
func sample(arr: PackedFloat32Array, p: Vector3, outside: float) -> float:
	var g: Vector3 = to_grid(p)
	var i: Vector3i = Vector3i(floori(g.x), floori(g.y), floori(g.z))
	if i.x < 0 or i.y < 0 or i.z < 0 or i.x >= size.x - 1 or i.y >= size.y - 1 or i.z >= size.z - 1:
		return outside
	var f: Vector3 = g - Vector3(i)
	var b: int = index(i.x, i.y, i.z)
	var sx: int = 1
	var sy: int = size.x
	var sz: int = size.x * size.y
	var c00: float = lerpf(arr[b], arr[b + sx], f.x)
	var c10: float = lerpf(arr[b + sy], arr[b + sy + sx], f.x)
	var c01: float = lerpf(arr[b + sz], arr[b + sz + sx], f.x)
	var c11: float = lerpf(arr[b + sz + sy], arr[b + sz + sy + sx], f.x)
	return lerpf(lerpf(c00, c10, f.y), lerpf(c01, c11, f.y), f.z)


## Capa de un punto: por profundidad bajo la superficie original, salvo el Núcleo (esfera).
func layer_at(p: Vector3) -> int:
	return _layer_of(sample(depth, p, 0.0), p)


func _layer_of(d: float, p: Vector3) -> int:
	if p.distance_squared_to(core_center) < core_radius * core_radius:
		return layer_density.size() - 1
	var idx: int = 0
	for i: int in layer_density.size() - 1:
		if d >= layer_min_depth[i]:
			idx = i
	return idx


## ¿Hay cristal en `p`?
func is_solid(p: Vector3) -> bool:
	return sample(sdf, p, 1.0) < 0.0


## Erosiona alrededor de `center`: sube la distancia hasta `amount` metros en el centro, con
## caída parabólica hasta `radius`. Las capas con su bit a 0 en `allowed` no se tocan (Núcleo...).
## Devuelve {"essence": esencia quitada, "by_layer": PackedFloat32Array, "chunks": índices de
## trozo tocados}. La esencia sale del volumen sólido perdido (fracción de celda llena) por la
## densidad de su capa: la misma cuenta con la que se repartió el 1.000.000.
## Con `apply` = false sólo calcula cuánto quitaría (para ajustar `amount` antes); con
## `stride` > 1 lo estima mirando una de cada `stride` celdas por eje (cráteres grandes).
func carve(
	center: Vector3, radius: float, amount: float, allowed: int, apply: bool = true, stride: int = 1
) -> Dictionary:
	var by_layer := PackedFloat32Array()
	by_layer.resize(layer_density.size())
	var touched: Dictionary[int, bool] = {}
	var g: Vector3 = to_grid(center)
	var r_cells: float = radius / cell
	var lo := Vector3i(
		maxi(0, floori(g.x - r_cells)),
		maxi(0, floori(g.y - r_cells)),
		maxi(0, floori(g.z - r_cells))
	)
	var hi := Vector3i(
		mini(size.x - 1, ceili(g.x + r_cells)),
		mini(size.y - 1, ceili(g.y + r_cells)),
		mini(size.z - 1, ceili(g.z + r_cells))
	)
	if apply:
		stride = 1
	var vol: float = cell * cell * cell * float(stride * stride * stride)
	var total: float = 0.0
	# Es el bucle más caliente del juego (un cráter grande pasa por decenas de miles de celdas en
	# el hilo principal): sólo recorre las celdas dentro de la esfera (cuerda de cada fila), sin
	# raíces (k^2 = d^2 / r^2) y con `_layer_of`, `_fill` y `_touch` metidos a mano.
	var r2: float = r_cells * r_cells
	var inv_r2: float = 1.0 / r2
	var inv_cell: float = 1.0 / cell
	var core_r2: float = core_radius * core_radius / (cell * cell)
	var core_g: Vector3 = to_grid(core_center)
	var core_layer: int = layer_density.size() - 1
	var top_layer: int = layer_density.size() - 2
	var mins: PackedFloat32Array = layer_min_depth
	var dens: PackedFloat32Array = layer_density
	var sx: int = size.x
	var sxy: int = size.x * size.y
	for z: int in range(lo.z, hi.z + 1, stride):
		var dz: float = float(z) - g.z
		var dz2: float = dz * dz
		var cdz: float = float(z) - core_g.z
		for y: int in range(lo.y, hi.y + 1, stride):
			var dy: float = float(y) - g.y
			var dyz2: float = dy * dy + dz2
			if dyz2 >= r2:
				continue
			# Cuerda de la esfera en esta fila, alineada a la rejilla del muestreo.
			var w: float = sqrt(r2 - dyz2)
			var x0: int = maxi(lo.x, ceili(g.x - w))
			if stride > 1:
				x0 = lo.x + ceili(float(x0 - lo.x) / float(stride)) * stride
			var x1: int = mini(hi.x, floori(g.x + w))
			var cdy: float = float(y) - core_g.y
			var core_yz2: float = cdy * cdy + cdz * cdz
			var row: int = sx * y + sxy * z
			var mx0: int = -1
			var mx1: int = -1
			for x: int in range(x0, x1 + 1, stride):
				var i: int = row + x
				var old: float = sdf[i]
				if old > cell:
					continue  # ya es aire
				var dx: float = float(x) - g.x
				var d2: float = dx * dx + dyz2
				if d2 >= r2:
					continue
				var cdx: float = float(x) - core_g.x
				var layer: int = 0
				if cdx * cdx + core_yz2 < core_r2:
					layer = core_layer
				else:
					var dep: float = depth[i]
					layer = top_layer
					while layer > 0 and dep < mins[layer]:
						layer -= 1
				if (allowed >> layer) & 1 == 0:
					continue
				var nv: float = old + amount * (1.0 - d2 * inv_r2)
				var lost: float = (
					clampf(0.5 - old * inv_cell, 0.0, 1.0) - clampf(0.5 - nv * inv_cell, 0.0, 1.0)
				)
				if lost > 0.0:
					var e: float = lost * vol * dens[layer]
					by_layer[layer] += e
					total += e
				if apply:
					sdf[i] = nv
					if mx0 < 0:
						mx0 = x
					mx1 = x
			if mx0 >= 0:
				_touch_row(touched, mx0, mx1, y, z)
	return {"essence": total, "by_layer": by_layer, "chunks": touched.keys()}


## Hueco esférico de golpe (radio `radius`): para túneles de depuración y demos. Mismo
## resultado que `carve`.
func carve_sphere(center: Vector3, radius: float, allowed: int) -> Dictionary:
	var by_layer := PackedFloat32Array()
	by_layer.resize(layer_density.size())
	var touched: Dictionary[int, bool] = {}
	var g: Vector3 = to_grid(center)
	var r_cells: float = radius / cell + 1.0
	var vol: float = cell * cell * cell
	var total: float = 0.0
	for z: int in range(maxi(0, floori(g.z - r_cells)), mini(size.z, ceili(g.z + r_cells) + 1)):
		for y: int in range(maxi(0, floori(g.y - r_cells)), mini(size.y, ceili(g.y + r_cells) + 1)):
			for x: int in range(
				maxi(0, floori(g.x - r_cells)), mini(size.x, ceili(g.x + r_cells) + 1)
			):
				var i: int = index(x, y, z)
				var wp: Vector3 = origin + Vector3(x, y, z) * cell
				var nv: float = radius - wp.distance_to(center)
				var old: float = sdf[i]
				if nv <= old:
					continue
				var layer: int = _layer_of(depth[i], wp)
				if (allowed >> layer) & 1 == 0:
					continue
				sdf[i] = nv
				var lost: float = _fill(old) - _fill(nv)
				if lost > 0.0:
					by_layer[layer] += lost * vol * layer_density[layer]
					total += lost * vol * layer_density[layer]
				_touch(touched, x, y, z)
	return {"essence": total, "by_layer": by_layer, "chunks": touched.keys()}


## Rompefacetas: arranca de golpe una losa con forma de faceta. `p0` es el punto de la superficie
## y `frame` su base local (x, z: el plano de la faceta; y: la normal hacia fuera), todo local.
## La losa es el prisma de `poly` (polígono convexo en x-z, en metros, antihorario) desde fuera
## hasta `depth_m` por debajo del plano, con el fondo algo inclinado (`tilt`, por metro en x-z):
## un corte plano, como una cara del cristal que se desprende. Misma salida que `carve` (y
## `apply` / `stride` para probar antes cuánto quitaría).
func carve_facet(
	p0: Vector3,
	frame: Basis,
	poly: PackedVector2Array,
	depth_m: float,
	tilt: Vector2,
	allowed: int,
	apply: bool = true,
	stride: int = 1
) -> Dictionary:
	var by_layer := PackedFloat32Array()
	by_layer.resize(layer_density.size())
	var touched: Dictionary[int, bool] = {}
	# Bordes del polígono: normal hacia fuera y distancia al origen de cada uno.
	var edge_n := PackedVector2Array()
	var edge_d := PackedFloat32Array()
	var reach: float = 0.0
	for k: int in poly.size():
		var a: Vector2 = poly[k]
		var b: Vector2 = poly[(k + 1) % poly.size()]
		var en := Vector2(b.y - a.y, a.x - b.x).normalized()
		edge_n.append(en)
		edge_d.append(a.dot(en))
		reach = maxf(reach, a.length())
	var u: Vector3 = frame.x
	var nrm: Vector3 = frame.y
	var v: Vector3 = frame.z
	var bound: float = reach + depth_m * 1.5 + cell
	var g: Vector3 = to_grid(p0)
	var r_cells: float = bound / cell
	if apply:
		stride = 1
	var vol: float = cell * cell * cell * float(stride * stride * stride)
	var total: float = 0.0
	for z: int in range(
		maxi(0, floori(g.z - r_cells)), mini(size.z, ceili(g.z + r_cells) + 1), stride
	):
		for y: int in range(
			maxi(0, floori(g.y - r_cells)), mini(size.y, ceili(g.y + r_cells) + 1), stride
		):
			for x: int in range(
				maxi(0, floori(g.x - r_cells)), mini(size.x, ceili(g.x + r_cells) + 1), stride
			):
				var i: int = index(x, y, z)
				var old: float = sdf[i]
				if old > cell:
					continue  # ya es aire
				var wp: Vector3 = origin + Vector3(x, y, z) * cell
				var rel: Vector3 = wp - p0
				var inward: float = -rel.dot(nrm)
				# Lo que sobresale muy por fuera del plano (otra punta delante) no es de la losa.
				if inward < -depth_m * 1.5:
					continue
				var uv := Vector2(rel.dot(u), rel.dot(v))
				var side: float = -INF
				for k: int in edge_n.size():
					side = maxf(side, uv.dot(edge_n[k]) - edge_d[k])
				var floor_at: float = depth_m * maxf(0.35, 1.0 + tilt.dot(uv))
				# Distancia firmada a la losa (negativa dentro): el aire nuevo es su contrario.
				var nv: float = -maxf(side, inward - floor_at)
				if nv <= old:
					continue
				var layer: int = _layer_of(depth[i], wp)
				if (allowed >> layer) & 1 == 0:
					continue
				if apply:
					sdf[i] = nv
					_touch(touched, x, y, z)
				var lost: float = _fill(old) - _fill(nv)
				if lost > 0.0:
					var e: float = lost * vol * layer_density[layer]
					by_layer[layer] += e
					total += e
	return {"essence": total, "by_layer": by_layer, "chunks": touched.keys()}


## Normal de la superficie en `p` (gradiente de la distancia).
func normal_at(p: Vector3) -> Vector3:
	var e: float = cell
	var n := Vector3(
		sample(sdf, p + Vector3(e, 0, 0), 1.0) - sample(sdf, p - Vector3(e, 0, 0), 1.0),
		sample(sdf, p + Vector3(0, e, 0), 1.0) - sample(sdf, p - Vector3(0, e, 0), 1.0),
		sample(sdf, p + Vector3(0, 0, e), 1.0) - sample(sdf, p - Vector3(0, 0, e), 1.0)
	)
	return n.normalized() if n.length_squared() > 1e-8 else Vector3.UP


## Fracción llena de la celda de un punto con distancia `d` (igual que en el horneado).
func _fill(d: float) -> float:
	return clampf(0.5 - d / cell, 0.0, 1.0)


## Un punto pertenece a su trozo y, si está en el borde, también a los vecinos de abajo.
func _touch(touched: Dictionary[int, bool], x: int, y: int, z: int) -> void:
	# La división entera es a propósito: el índice del trozo de una celda.
	@warning_ignore_start("integer_division")
	var cx0: int = clampi((x - 1) / chunk, 0, chunks.x - 1)
	var cy0: int = clampi((y - 1) / chunk, 0, chunks.y - 1)
	var cz0: int = clampi((z - 1) / chunk, 0, chunks.z - 1)
	var cx1: int = clampi((x + 1) / chunk, 0, chunks.x - 1)
	var cy1: int = clampi((y + 1) / chunk, 0, chunks.y - 1)
	var cz1: int = clampi((z + 1) / chunk, 0, chunks.z - 1)
	@warning_ignore_restore("integer_division")
	for cz: int in range(cz0, cz1 + 1):
		for cy: int in range(cy0, cy1 + 1):
			for cx: int in range(cx0, cx1 + 1):
				touched[cx + chunks.x * (cy + chunks.y * cz)] = true


## `_touch` para un tramo de fila (x de `x0` a `x1`, en `y`, `z`): los mismos trozos que marcar
## cada celda, con una sola pasada por fila.
func _touch_row(touched: Dictionary[int, bool], x0: int, x1: int, y: int, z: int) -> void:
	var cx0: int = clampi((x0 - 1) / chunk, 0, chunks.x - 1)
	var cy0: int = clampi((y - 1) / chunk, 0, chunks.y - 1)
	var cz0: int = clampi((z - 1) / chunk, 0, chunks.z - 1)
	var cx1: int = clampi((x1 + 1) / chunk, 0, chunks.x - 1)
	var cy1: int = clampi((y + 1) / chunk, 0, chunks.y - 1)
	var cz1: int = clampi((z + 1) / chunk, 0, chunks.z - 1)
	for cz: int in range(cz0, cz1 + 1):
		for cy: int in range(cy0, cy1 + 1):
			for cx: int in range(cx0, cx1 + 1):
				touched[cx + chunks.x * (cy + chunks.y * cz)] = true


func chunk_coords(chunk_index: int) -> Vector3i:
	@warning_ignore("integer_division")
	return Vector3i(
		chunk_index % chunks.x,
		(chunk_index / chunks.x) % chunks.y,
		chunk_index / (chunks.x * chunks.y)
	)


## Malla de un trozo: arrays listos para `ArrayMesh.add_surface_from_arrays` (o [] si no hay
## superficie). Caras planas (normal por triángulo) y la profundidad original en UV.x para que
## el shader pinte la capa. Estática y sin estado compartido: se puede llamar desde otro hilo.
## La normal de cada triángulo sale del gradiente de la distancia en sus tres vértices, no de su
## geometría: en una cara plana del cristal los vértices de "surface nets" bailan un poco y la
## normal geométrica cambiaba de triángulo a triángulo, lo que pintaba hileras de dientes
## oscuros en las bandas del shader. El gradiente es el mismo en toda la cara.
static func mesh_chunk(
	field: PackedFloat32Array,
	depth_field: PackedFloat32Array,
	dims: Vector3i,
	cell_size: float,
	grid_origin: Vector3,
	chunk_size: int,
	coords: Vector3i
) -> Array:
	var c0: Vector3i = coords * chunk_size
	# Celdas con vértice: de c0 - 1 a c0 + chunk - 1 (las del borde inferior las comparte).
	var lo := Vector3i(maxi(c0.x - 1, 0), maxi(c0.y - 1, 0), maxi(c0.z - 1, 0))
	var hi := Vector3i(
		mini(c0.x + chunk_size, dims.x - 1),
		mini(c0.y + chunk_size, dims.y - 1),
		mini(c0.z + chunk_size, dims.z - 1)
	)
	var span := Vector3i(hi.x - lo.x, hi.y - lo.y, hi.z - lo.z)
	var verts := PackedVector3Array()
	verts.resize(span.x * span.y * span.z)
	var vdepth := PackedFloat32Array()
	vdepth.resize(verts.size())
	var vgrad := PackedVector3Array()
	vgrad.resize(verts.size())
	var has := PackedByteArray()
	has.resize(verts.size())
	var sx: int = 1
	var sy: int = dims.x
	var sz: int = dims.x * dims.y
	var off: PackedInt32Array = [0, sx, sy, sx + sy, sz, sz + sx, sz + sy, sz + sy + sx]
	var corner_pos: PackedVector3Array = [
		Vector3(0, 0, 0),
		Vector3(1, 0, 0),
		Vector3(0, 1, 0),
		Vector3(1, 1, 0),
		Vector3(0, 0, 1),
		Vector3(1, 0, 1),
		Vector3(0, 1, 1),
		Vector3(1, 1, 1)
	]
	var vals := PackedFloat32Array()
	vals.resize(8)
	var any_vertex: bool = false
	for z: int in range(lo.z, hi.z):
		for y: int in range(lo.y, hi.y):
			for x: int in range(lo.x, hi.x):
				var b: int = x + sy * y + sz * z
				var neg: int = 0
				for k: int in 8:
					var v: float = field[b + off[k]]
					vals[k] = v
					if v < 0.0:
						neg += 1
				if neg == 0 or neg == 8:
					continue
				var acc := Vector3.ZERO
				var cnt: int = 0
				for e: int in 12:
					var a: int = EDGES[e * 2]
					var bb: int = EDGES[e * 2 + 1]
					var va: float = vals[a]
					var vb: float = vals[bb]
					if (va < 0.0) != (vb < 0.0):
						var t: float = va / (va - vb)
						acc += corner_pos[a].lerp(corner_pos[bb], t)
						cnt += 1
				var li: int = (x - lo.x) + span.x * ((y - lo.y) + span.y * (z - lo.z))
				verts[li] = grid_origin + (Vector3(x, y, z) + acc / float(cnt)) * cell_size
				var dsum: float = 0.0
				for k: int in 8:
					dsum += depth_field[b + off[k]]
				vdepth[li] = dsum * 0.125
				# Gradiente de la celda (diferencias de sus 8 esquinas): exacto en un campo lineal.
				vgrad[li] = Vector3(
					vals[1] - vals[0] + vals[3] - vals[2] + vals[5] - vals[4] + vals[7] - vals[6],
					vals[2] - vals[0] + vals[3] - vals[1] + vals[6] - vals[4] + vals[7] - vals[5],
					vals[4] - vals[0] + vals[5] - vals[1] + vals[6] - vals[2] + vals[7] - vals[3]
				)
				has[li] = 1
				any_vertex = true
	if not any_vertex:
		return []
	var out_v := PackedVector3Array()
	var out_n := PackedVector3Array()
	var out_uv := PackedVector2Array()
	# Aristas propias del trozo: las que salen de puntos en [c0, c0 + chunk) en cada eje.
	var end := Vector3i(
		mini(c0.x + chunk_size, dims.x - 1),
		mini(c0.y + chunk_size, dims.y - 1),
		mini(c0.z + chunk_size, dims.z - 1)
	)
	for axis: int in 3:
		var step: int = [sx, sy, sz][axis]
		for z: int in range(c0.z, end.z):
			for y: int in range(c0.y, end.y):
				for x: int in range(c0.x, end.x):
					var p := Vector3i(x, y, z)
					# Las 4 celdas que comparten la arista quedan en -1 en los otros dos ejes.
					var u_axis: int = (axis + 1) % 3
					var w_axis: int = (axis + 2) % 3
					if p[u_axis] < 1 or p[w_axis] < 1:
						continue
					var b: int = x + sy * y + sz * z
					var va: float = field[b]
					var vb: float = field[b + step]
					if (va < 0.0) == (vb < 0.0):
						continue
					var cells: Array[Vector3i] = []
					var ok: bool = true
					for q: int in 4:
						var c := p
						c[u_axis] -= 1 if (q == 1 or q == 2) else 0
						c[w_axis] -= 1 if q >= 2 else 0
						if c.x < lo.x or c.y < lo.y or c.z < lo.z:
							ok = false
							break
						if c.x >= hi.x or c.y >= hi.y or c.z >= hi.z:
							ok = false
							break
						var li: int = (c.x - lo.x) + span.x * ((c.y - lo.y) + span.y * (c.z - lo.z))
						if has[li] == 0:
							ok = false
							break
						cells.append(c)
					if not ok:
						continue
					var q4: Array[int] = []
					for c: Vector3i in cells:
						q4.append((c.x - lo.x) + span.x * ((c.y - lo.y) + span.y * (c.z - lo.z)))
					# Hacia fuera = hacia donde la distancia crece (de dentro a fuera por la arista).
					var outward := Vector3.ZERO
					outward[axis] = 1.0 if va < 0.0 else -1.0
					_quad(out_v, out_n, out_uv, verts, vdepth, vgrad, q4, outward)
	if out_v.is_empty():
		return []
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = out_v
	arrays[Mesh.ARRAY_NORMAL] = out_n
	arrays[Mesh.ARRAY_TEX_UV] = out_uv
	return arrays


## Dos triángulos por cuadrilátero, por la diagonal más corta, de cara hacia `outward`.
static func _quad(
	out_v: PackedVector3Array,
	out_n: PackedVector3Array,
	out_uv: PackedVector2Array,
	verts: PackedVector3Array,
	vdepth: PackedFloat32Array,
	vgrad: PackedVector3Array,
	q: Array[int],
	outward: Vector3
) -> void:
	var a: Vector3 = verts[q[0]]
	var b: Vector3 = verts[q[1]]
	var c: Vector3 = verts[q[2]]
	var d: Vector3 = verts[q[3]]
	var tris: Array[PackedInt32Array] = []
	if a.distance_squared_to(c) <= b.distance_squared_to(d):
		tris = [PackedInt32Array([0, 1, 2]), PackedInt32Array([0, 2, 3])]
	else:
		tris = [PackedInt32Array([0, 1, 3]), PackedInt32Array([1, 2, 3])]
	var pts: Array[Vector3] = [a, b, c, d]
	for t: PackedInt32Array in tris:
		var p0: Vector3 = pts[t[0]]
		var p1: Vector3 = pts[t[1]]
		var p2: Vector3 = pts[t[2]]
		var i0: int = q[t[0]]
		var i1: int = q[t[1]]
		var i2: int = q[t[2]]
		var n: Vector3 = (p1 - p0).cross(p2 - p0)
		if n.length_squared() < 1e-10:
			continue
		# Godot: frontal en orden horario visto desde fuera (la normal del producto, hacia dentro).
		if n.dot(outward) > 0.0:
			var tmp: Vector3 = p1
			p1 = p2
			p2 = tmp
			var ti: int = i1
			i1 = i2
			i2 = ti
			n = -n
		var nn: Vector3 = -n.normalized()
		# Normal suave del campo (ver `mesh_chunk`); la geométrica si no sirve o se da la vuelta.
		var g: Vector3 = vgrad[i0] + vgrad[i1] + vgrad[i2]
		if g.length_squared() > 1e-12:
			g = g.normalized()
			if g.dot(nn) > 0.3:
				nn = g
		out_v.append(p0)
		out_v.append(p1)
		out_v.append(p2)
		out_n.append(nn)
		out_n.append(nn)
		out_n.append(nn)
		out_uv.append(Vector2(vdepth[i0], 0.0))
		out_uv.append(Vector2(vdepth[i1], 0.0))
		out_uv.append(Vector2(vdepth[i2], 0.0))
