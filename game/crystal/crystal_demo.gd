class_name CrystalDemo
extends RefCounted
## Túneles de depuración y demo en el Cristal Madre (tecla L, `--layer=N`, `--geode`).


## Debug y demo: excava un túnel desde el lado del claro (hacia el jugador) hasta la capa
## `idx`, quitando la esencia que corresponda.
static func tunnel_to_layer(c: MotherCrystal, idx: int) -> void:
	if idx >= GameState.LAYERS.size() - 1:
		idx = GameState.LAYERS.size() - 2
	var target: float = c.volume.layer_min_depth[idx] + 1.0
	var from: Vector3 = Vector3(0.0, 2.6, WorldLayout.CRYSTAL_FOOTPRINT + 4.0)
	var dir := Vector3(0.0, 0.0, -1.0)
	var t: float = 0.0
	while t < WorldLayout.CRYSTAL_FOOTPRINT + 4.0:
		var p: Vector3 = from + dir * t
		t += 0.8
		if not c.volume.is_solid(p):
			continue
		var depth: float = c.volume.sample(c.volume.depth, p, 0.0)
		c.apply_carve(c.volume.carve_sphere(p, 2.6, (1 << 4) - 1), p, 2.6)
		if depth >= target:
			break


## Demo: excava un túnel recto hasta la geoda más cercana a `from` (global) y la abre.
## Devuelve [boca del túnel, centro de la geoda] (global), para ponerse a mirarla.
static func tunnel_to_geode(c: MotherCrystal, from: Vector3) -> Array[Vector3]:
	var best: int = -1
	var best_d: float = INF
	var p0: Vector3 = c.to_local(from)
	for i: int in c.volume.geodes.size():
		var d: float = (c.volume.geodes[i]["center"] as Vector3).distance_to(p0)
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
