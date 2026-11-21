class_name MeshKit
extends RefCounted
## Utilidades para construir mallas low-poly con normales planas y colores por vértice.
## Godot usa orden horario para las caras frontales: add_tri() lo corrige solo a partir de un
## punto "interior" de referencia, así que nadie tiene que pensar en el winding.

## Dibujos de `world/terrain.gdshader` (ver tag()).
const PAT_GRASS: int = 1
const PAT_DIRT: int = 2
const PAT_ROCK: int = 3
const PAT_LEAVES: int = 4
const PAT_BARK: int = 5
const PAT_SNOWY_ROCK: int = 6


static func begin() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


## Añade un triángulo con normal plana orientada hacia fuera de `inside`.
static func add_tri(
	st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color, inside: Vector3
) -> void:
	var n: Vector3 = (b - a).cross(c - a)
	if n.length_squared() < 1e-12:
		return
	var outward: Vector3 = (a + b + c) / 3.0 - inside
	if n.dot(outward) > 0.0:
		# Godot considera frontal el orden horario visto desde fuera: invertimos.
		var tmp: Vector3 = b
		b = c
		c = tmp
		n = -n
	var normal: Vector3 = -n.normalized()
	st.set_color(color)
	st.set_normal(normal)
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)


static func add_quad(
	st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color, inside: Vector3
) -> void:
	add_tri(st, a, b, c, color, inside)
	add_tri(st, a, c, d, color, inside)


## Prisma de `sides` lados a lo largo de `axis` (normalizado), con punta piramidal opcional.
## `jitter` deforma el radio de cada vértice para que las facetas no sean idénticas.
## Devuelve los puntos usados (útil para la colisión convexa).
static func add_prism(
	st: SurfaceTool,
	base: Vector3,
	axis: Vector3,
	radius: float,
	height: float,
	tip: float,
	sides: int,
	color_side: Color,
	color_tip: Color,
	rng: RandomNumberGenerator,
	jitter: float = 0.0,
	top_radius_scale: float = 1.0
) -> PackedVector3Array:
	var up: Vector3 = axis.normalized()
	var side_ref: Vector3 = (
		Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	)
	var u: Vector3 = up.cross(side_ref).normalized()
	var v: Vector3 = up.cross(u).normalized()
	var top: Vector3 = base + up * height
	var apex: Vector3 = top + up * tip
	var center: Vector3 = base + up * (height + tip) * 0.4
	var bottom_ring: PackedVector3Array = []
	var top_ring: PackedVector3Array = []
	var phase: float = rng.randf() * TAU
	for i: int in sides:
		var ang: float = phase + TAU * float(i) / float(sides)
		var dir: Vector3 = u * cos(ang) + v * sin(ang)
		var r: float = radius * (1.0 + rng.randf_range(-jitter, jitter))
		bottom_ring.append(base + dir * r)
		top_ring.append(top + dir * r * top_radius_scale)
	for i: int in sides:
		var j: int = (i + 1) % sides
		add_quad(st, bottom_ring[i], bottom_ring[j], top_ring[j], top_ring[i], color_side, center)
		if tip > 0.0:
			add_tri(st, top_ring[i], top_ring[j], apex, color_tip, center)
		else:
			add_tri(st, top_ring[i], top_ring[j], top, color_tip, center)
		add_tri(st, bottom_ring[i], bottom_ring[j], base, color_side, center)
	var points: PackedVector3Array = bottom_ring.duplicate()
	points.append_array(top_ring)
	points.append(apex if tip > 0.0 else top)
	return points


## Cono / pirámide de base poligonal.
static func add_cone(
	st: SurfaceTool,
	base: Vector3,
	radius: float,
	height: float,
	sides: int,
	color: Color,
	rng: RandomNumberGenerator,
	jitter: float = 0.0
) -> void:
	add_prism(st, base, Vector3.UP, radius, 0.001, height, sides, color, color, rng, jitter)


## Caja alineada a ejes.
static func add_box(
	st: SurfaceTool,
	center: Vector3,
	size: Vector3,
	color: Color,
	roof_color: Color = Color(0, 0, 0, 0)
) -> void:
	var h: Vector3 = size * 0.5
	var p: Array[Vector3] = []
	for x: float in [-h.x, h.x]:
		for y: float in [-h.y, h.y]:
			for z: float in [-h.z, h.z]:
				p.append(center + Vector3(x, y, z))
	# índices: x(0/1)*4 + y(0/1)*2 + z(0/1)
	var top_c: Color = roof_color if roof_color.a > 0.0 else color
	add_quad(st, p[0], p[1], p[3], p[2], color, center)  # -x
	add_quad(st, p[4], p[5], p[7], p[6], color, center)  # +x
	add_quad(st, p[0], p[1], p[5], p[4], color, center)  # -y
	add_quad(st, p[2], p[3], p[7], p[6], top_c, center)  # +y
	add_quad(st, p[0], p[2], p[6], p[4], color, center)  # -z
	add_quad(st, p[1], p[3], p[7], p[5], color, center)  # +z


## Tejado a dos aguas sobre una caja (para casas).
static func add_gable_roof(
	st: SurfaceTool, center: Vector3, size: Vector3, roof_h: float, color: Color
) -> void:
	var h: Vector3 = size * 0.5
	var y0: float = center.y
	var a := Vector3(center.x - h.x, y0, center.z - h.z)
	var b := Vector3(center.x + h.x, y0, center.z - h.z)
	var c := Vector3(center.x + h.x, y0, center.z + h.z)
	var d := Vector3(center.x - h.x, y0, center.z + h.z)
	var r1 := Vector3(center.x - h.x, y0 + roof_h, center.z)
	var r2 := Vector3(center.x + h.x, y0 + roof_h, center.z)
	var inside := Vector3(center.x, y0 + roof_h * 0.3, center.z)
	add_quad(st, a, b, r2, r1, color, inside)
	add_quad(st, d, c, r2, r1, color, inside)
	add_tri(st, a, d, r1, color, inside)
	add_tri(st, b, c, r2, color, inside)


## Triángulo con normales por vértice (sombreado suave). Corrige el orden igual que add_tri().
static func add_tri_smooth(
	st: SurfaceTool,
	a: Vector3,
	b: Vector3,
	c: Vector3,
	na: Vector3,
	nb: Vector3,
	nc: Vector3,
	color: Color,
	inside: Vector3
) -> void:
	var n: Vector3 = (b - a).cross(c - a)
	if n.length_squared() < 1e-12:
		return
	if n.dot((a + b + c) / 3.0 - inside) > 0.0:
		var tmp: Vector3 = b
		b = c
		c = tmp
		var tn: Vector3 = nb
		nb = nc
		nc = tn
	st.set_color(color)
	st.set_normal(na)
	st.add_vertex(a)
	st.set_normal(nb)
	st.add_vertex(b)
	st.set_normal(nc)
	st.add_vertex(c)


## Rejilla de puntos (filas x columnas) con normales suaves, para formas redondeadas: laderas,
## copas de árbol, rocas. `wrap` cierra las columnas en anillo. Las normales salen de las
## diferencias entre vecinos y se orientan hacia fuera de `inside`; en un polo (fila degenerada)
## usan la dirección desde `inside`. `colors` da un color por fila (o uno solo para todo).
## `uv` va en todos los vértices (terrain.gdshader lee en UV.x la altura de la nieve).
static func add_grid(
	st: SurfaceTool,
	rows: Array[PackedVector3Array],
	colors: Array[Color],
	inside: Vector3,
	wrap: bool = true,
	uv: Vector2 = Vector2.ZERO
) -> void:
	if uv != Vector2.ZERO:
		# Sólo si la malla entera lleva UV (SurfaceTool fija el formato con el primer vértice).
		st.set_uv(uv)
	var nr: int = rows.size()
	var nc: int = rows[0].size()
	var normals: Array[PackedVector3Array] = []
	for i: int in nr:
		var row_n := PackedVector3Array()
		row_n.resize(nc)
		for j: int in nc:
			var jl: int = (j - 1 + nc) % nc if wrap else maxi(j - 1, 0)
			var jr: int = (j + 1) % nc if wrap else mini(j + 1, nc - 1)
			var du: Vector3 = rows[i][jr] - rows[i][jl]
			var dv: Vector3 = rows[mini(i + 1, nr - 1)][j] - rows[maxi(i - 1, 0)][j]
			var p: Vector3 = rows[i][j]
			var nn: Vector3 = du.cross(dv)
			var out: Vector3 = p - inside
			if nn.length_squared() < 1e-10 or du.length_squared() < 1e-10:
				nn = out
			elif nn.dot(out) < 0.0:
				nn = -nn
			row_n[j] = nn.normalized()
		normals.append(row_n)
	var cols: int = nc if wrap else nc - 1
	for i: int in nr - 1:
		var col: Color = colors[mini(i, colors.size() - 1)]
		for j: int in cols:
			var k: int = (j + 1) % nc
			var a: Vector3 = rows[i][j]
			var b: Vector3 = rows[i][k]
			var c: Vector3 = rows[i + 1][k]
			var d: Vector3 = rows[i + 1][j]
			var na: Vector3 = normals[i][j]
			var nb: Vector3 = normals[i][k]
			var ncn: Vector3 = normals[i + 1][k]
			var nd: Vector3 = normals[i + 1][j]
			_tri_by_normal(st, a, b, c, na, nb, ncn, col)
			_tri_by_normal(st, a, c, d, na, ncn, nd, col)


## Como add_tri_smooth, pero orienta la cara según la media de sus normales (sirve para
## superficies abiertas o cóncavas donde un punto interior no basta).
static func _tri_by_normal(
	st: SurfaceTool,
	a: Vector3,
	b: Vector3,
	c: Vector3,
	na: Vector3,
	nb: Vector3,
	nc: Vector3,
	color: Color
) -> void:
	var avg: Vector3 = na + nb + nc
	add_tri_smooth(st, a, b, c, na, nb, nc, color, (a + b + c) / 3.0 - avg)


## Bola deformada (copa de árbol, roca): esfera UV de `rings` x `segs` con el radio movido por
## ruido y escalada por `squash`. El color va por fila, de arriba a abajo.
static func add_blob(
	st: SurfaceTool,
	center: Vector3,
	radius: float,
	squash: Vector3,
	rings: int,
	segs: int,
	colors: Array[Color],
	rng: RandomNumberGenerator,
	bump: float = 0.12
) -> void:
	var noise := FastNoiseLite.new()
	noise.seed = rng.randi()
	noise.frequency = 1.6
	var rows: Array[PackedVector3Array] = []
	for i: int in rings + 1:
		var lat: float = PI * float(i) / float(rings)
		var row := PackedVector3Array()
		for j: int in segs:
			var lon: float = TAU * float(j) / float(segs)
			var dir := Vector3(sin(lat) * cos(lon), cos(lat), sin(lat) * sin(lon))
			var r: float = radius * (1.0 + noise.get_noise_3dv(dir) * bump * 2.0)
			row.append(center + dir * squash * r)
		rows.append(row)
	var row_cols: Array[Color] = []
	for i: int in rings:
		var k: int = int(float(i) / float(rings) * colors.size())
		row_cols.append(colors[mini(k, colors.size() - 1)])
	add_grid(st, rows, row_cols, center)


## Color con el dibujo de `world/terrain.gdshader` codificado en el alfa (1 hierba, 2 tierra,
## 3 roca, 4 hojas, 5 corteza, 6 roca con nieve; 0 liso).
static func tag(color: Color, pattern: int) -> Color:
	return Color(color.r, color.g, color.b, 1.0 - float(pattern) * 0.1)


## Indexa (comparte los vértices repetidos: menos trabajo de vértices en la GPU) y crea la malla.
static func commit(st: SurfaceTool) -> ArrayMesh:
	st.index()
	return st.commit()
