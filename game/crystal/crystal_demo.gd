class_name CrystalDemo
extends RefCounted
## Túneles de depuración y demo en el Cristal Madre (tecla L, `--layer=N`, `--geode`, `--vein=N`).


## Debug y demo: excava un túnel desde el lado del claro (hacia el jugador) hasta la capa
## `idx`, quitando la esencia que corresponda.
static func tunnel_to_layer(c: MotherCrystal, idx: int) -> void:
	if idx >= GameState.LAYERS.size() - 1:
		idx = GameState.LAYERS.size() - 2
	var target: float = c.volume.layer_min_depth[idx] + 1.0
	var ray: Array[Vector3] = tunnel_ray(c, idx)
	var from: Vector3 = ray[0]
	var dir: Vector3 = ray[1]
	var t: float = 0.0
	while t < (WorldLayout.CRYSTAL_FOOTPRINT + 4.0) / maxf(-dir.z, 0.1):
		var p: Vector3 = from + dir * t
		t += 0.8
		if not c.volume.is_solid(p):
			continue
		var depth: float = c.volume.sample(c.volume.depth, p, 0.0)
		c.apply_carve(c.volume.carve_sphere(p, 2.6, (1 << 4) - 1), p, 2.6)
		if depth >= target:
			break


## Demo (`--vein=N`): túnel corto desde el lado de la vena `sector` (ver CrystalVeins) hasta la
## capa de las Venas, sin pasar por geodas. Prueba varios ángulos del sector y se queda con el
## túnel más corto. Devuelve [donde ponerse fuera, boca del túnel, fondo] (global).
static func tunnel_to_vein(c: MotherCrystal, sector: int) -> Array[Vector3]:
	var v: CrystalVolume = c.volume
	var width: float = TAU / float(CrystalVeins.SECTORS)
	var center_a: float = -PI + (float(sector) + 0.5) * width
	var aim := Vector3(0.0, v.layer_min_depth[2] + 4.2, 0.0)
	var best: Array[Vector3] = []
	var best_len: float = INF
	for i: int in 15:
		var a: float = center_a + (float(i) / 14.0 - 0.5) * width * 0.8
		var from := Vector3(cos(a) * 60.0, 2.6, sin(a) * 60.0)
		var dir: Vector3 = (aim - from).normalized()
		if _path_hits_geode(c, from, dir, 70.0):
			continue
		var mouth: float = -1.0
		var t: float = 0.0
		while t < 70.0:
			var p: Vector3 = from + dir * t
			if mouth < 0.0 and v.is_solid(p):
				mouth = t
			if mouth > 0.0 and v.layer_at(p) == 2:
				if t - mouth < best_len:
					best_len = t - mouth
					best = [from, dir, Vector3(mouth, t, 0.0)]
				break
			t += 0.4
	if best.is_empty():
		return [c.to_global(Vector3(0, 0, 60)), c.to_global(Vector3(0, 2.6, 44)), c.to_global(aim)]
	var o: Vector3 = best[0]
	var d: Vector3 = best[1]
	var t0: float = best[2].x
	var t1: float = best[2].y + 1.5
	var k: float = t0
	while k <= t1:
		var q: Vector3 = o + d * k
		c.apply_carve(v.carve_sphere(q, 2.6, (1 << 4) - 1), q, 2.6)
		k += 0.8
	# Donde ponerse: hacia fuera por el túnel hasta pisar suelo libre.
	var stand: Vector3 = o
	var back: float = t0 - 1.5
	while back > 0.0:
		var s: Vector3 = o + d * back
		if not v.is_solid(Vector3(s.x, 0.4, s.z)) and not v.is_solid(Vector3(s.x, 1.8, s.z)):
			stand = s
			break
		back -= 1.0
	return [c.to_global(stand), c.to_global(o + d * t0), c.to_global(o + d * best[2].y)]


static func _path_hits_geode(c: MotherCrystal, from: Vector3, dir: Vector3, length: float) -> bool:
	for g: Dictionary in c.volume.geodes:
		var gc: Vector3 = g["center"]
		var radius: float = g["radius"]
		var k: float = clampf((gc - from).dot(dir), 0.0, length)
		if (from + dir * k).distance_to(gc) < radius + 4.0:
			return true
	return false


## Boca y dirección (local) del túnel de demo hasta la capa `idx`: entra por delante a ras de
## suelo y sube un poco hacia el eje, porque la profundidad cuenta también desde la base (cerca
## del suelo nunca se pasa de unos metros y no se llegaría a las Venas).
static func tunnel_ray(c: MotherCrystal, idx: int) -> Array[Vector3]:
	var from: Vector3 = Vector3(0.0, 2.6, WorldLayout.CRYSTAL_FOOTPRINT + 4.0)
	var aim_y: float = maxf(from.y, c.volume.layer_min_depth[idx] + 4.0)
	return [from, (Vector3(0.0, aim_y, 0.0) - from).normalized()]


## Demo: excava un túnel recto hasta la geoda más cercana a `from` (global) y la abre.
## Devuelve [boca del túnel, centro de la geoda] (global), para ponerse a mirarla.
static func tunnel_to_geode(c: MotherCrystal, from: Vector3) -> Array[Vector3]:
	var best: int = -1
	var best_d: float = INF
	var p0: Vector3 = c.to_local(from)
	for i: int in c.volume.geodes.size():
		var center: Vector3 = c.volume.geodes[i]["center"]
		var d: float = center.distance_to(p0)
		if d < best_d:
			best_d = d
			best = i
	if best < 0:
		return [from, from]
	var gc: Vector3 = c.volume.geodes[best]["center"]
	# Rampa desde el suelo de fuera hasta la bolsa, para poder mirar dentro desde la boca.
	var flat: Vector3 = Vector3(p0.x - gc.x, 0.0, p0.z - gc.z).normalized()
	var out: Vector3 = gc + flat * 14.0
	out.y = 1.4
	var mouth: Vector3 = out
	for k: int in 60:
		var q: Vector3 = gc.lerp(out, float(k) / 59.0)
		c.apply_carve(c.volume.carve_sphere(q, 2.0, (1 << 4) - 1), q, 2.0)
		if not c.volume.is_solid(q) and c.volume.sample(c.volume.depth, q, 0.0) <= 0.0 and k > 6:
			mouth = q
			break
	return [c.to_global(mouth + flat * 2.0), c.to_global(gc)]
