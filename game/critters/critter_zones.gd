class_name CritterZones
extends RefCounted
## Dónde pueden estar los bichos: en la hierba del claro, nunca en el cristal, los caminos, la
## explanada, los edificios (Pilón, trituradora, Santuario, Espejo del Archimago, casucha, jaula
## de familiares). Las mismas reglas que `ValleyDetails._free` (donde se planta la hierba),
## sacadas de `WorldLayout`.

static var _paths: Array[PackedVector2Array] = []


## Donde se juntan los caminos (delante del cristal).
static func hub() -> Vector3:
	return Vector3(0.0, 0.0, WorldLayout.CRYSTAL_FOOTPRINT + 5.0)


## True si (x, z) está libre con `margin` metros de holgura.
static func is_free(x: float, z: float, margin: float) -> bool:
	var p := Vector2(x, z)
	if p.length() < WorldLayout.CRYSTAL_FOOTPRINT + 3.0 + margin:
		return false
	var pylon := Vector2(WorldLayout.PYLON.x, WorldLayout.PYLON.z)
	if p.distance_to(pylon) < 3.0 + margin:
		return false
	# La trituradora (al este del Pilón) y la explanada delante de ella.
	if p.distance_to(pylon + Vector2(2.8, 0.0)) < 2.4 + margin:
		return false
	if p.distance_to(pylon + Vector2(3.6, 0.0)) < 3.6 + margin:
		return false
	if p.distance_to(Vector2(WorldLayout.SANCTUM.x, WorldLayout.SANCTUM.z)) < 4.6 + margin:
		return false
	if p.distance_to(Vector2(WorldLayout.HUT.x, WorldLayout.HUT.z)) < 4.6 + margin:
		return false
	var mirror := Vector2(WorldLayout.ARCHMAGE_MIRROR.x, WorldLayout.ARCHMAGE_MIRROR.z)
	if p.distance_to(mirror) < 1.8 + margin:
		return false
	if p.distance_to(Vector2(WorldLayout.RUNE_TABLE.x, WorldLayout.RUNE_TABLE.z)) < 2.2 + margin:
		return false
	var vitrine := Vector2(WorldLayout.STAFF_VITRINE.x, WorldLayout.STAFF_VITRINE.z)
	if p.distance_to(vitrine) < 2.0 + margin:
		return false
	if (
		p.distance_to(Vector2(WorldLayout.FAMILIAR_NEST.x, WorldLayout.FAMILIAR_NEST.z))
		< 2.6 + margin
	):
		return false
	var h: Vector3 = hub()
	if p.distance_to(Vector2(h.x, h.z)) < 3.2 + margin:
		return false
	return not near_path(x, z, 1.6 + margin)


## True si (x, z) está a menos de `margin` m de un camino.
static func near_path(x: float, z: float, margin: float) -> bool:
	if _paths.is_empty():
		_build_paths()
	var p := Vector2(x, z)
	for seg: PackedVector2Array in _paths:
		var a: Vector2 = seg[0]
		var ab: Vector2 = seg[1] - a
		var t: float = clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		if p.distance_to(a + ab * t) < margin:
			return true
	return false


## Los tres caminos de tierra (como ValleyDetails._build_paths).
static func _build_paths() -> void:
	var h: Vector3 = hub()
	var ends: Array[Vector3] = [
		WorldLayout.HUT + Vector3(0, 0, -3.2),
		WorldLayout.PYLON + Vector3(5.6, 0.0, 0.0),
		WorldLayout.SANCTUM + (h - WorldLayout.SANCTUM).normalized() * 4.2,
	]
	for e: Vector3 in ends:
		_paths.append(PackedVector2Array([Vector2(h.x, h.z), Vector2(e.x, e.z)]))
