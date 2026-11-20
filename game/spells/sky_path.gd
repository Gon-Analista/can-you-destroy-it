class_name SkyPath
extends RefCounted
## De dónde cae un hechizo del cielo (Meteoro, Trueno) y dónde aterriza: a plomo, desde muy alto
## justo encima del blanco. Sus círculos se apilan en horizontal a lo largo de esa columna (ver
## `MagicCircles.charging_sky`), así se lee como algo que baja del cielo y no como una bola lanzada
## de lado.
## Si encima del blanco hay cristal (una punta que sobresale), lo que cae a plomo se para en lo
## primero que toca: el hechizo aterriza ahí (`landing`).

const MASK: int = 1 | (1 << 1)
## Margen (m) para no tomar como obstáculo la propia superficie del blanco.
const SURFACE_SLACK: float = 0.6


## Origen a `height` m sobre el blanco, a plomo.
static func origin(target: Vector3, height: float) -> Vector3:
	return target + Vector3.UP * height


## Dónde aterriza lo que cae a plomo sobre `target` (normal `normal`) desde `height` m: el blanco
## o lo primero que haya en la columna. Devuelve {"position", "normal", "collider"} (el
## colisionador sólo si cambió; si no, null).
static func landing(
	space: PhysicsDirectSpaceState3D, target: Vector3, normal: Vector3, height: float
) -> Dictionary:
	var out: Dictionary = {"position": target, "normal": normal, "collider": null}
	if space == null:
		return out
	var from: Vector3 = origin(target, height)
	var hit: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(from, target, MASK))
	if hit.is_empty():
		return out
	var p: Vector3 = hit["position"]
	if p.distance_to(target) <= SURFACE_SLACK:
		return out
	out["position"] = p
	out["normal"] = hit["normal"]
	out["collider"] = hit["collider"]
	return out
