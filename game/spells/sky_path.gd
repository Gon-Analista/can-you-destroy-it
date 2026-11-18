class_name SkyPath
extends RefCounted
## De dónde cae un hechizo del cielo (Meteoro, Trueno) para que se lea como algo que cae: alto,
## por encima del blanco y algo a un lado, de modo que cruza la pantalla en diagonal de arriba
## abajo. Antes nacía casi encima del mago: se veía desde debajo, alejándose, y parecía una bola
## de fuego lanzada desde el suelo.
## Prueba varios puntos y se queda con el primero cuyo camino hasta el blanco no atraviese el
## cristal (ni el suelo): primero desde detrás del blanco (cae del cielo que hay sobre el
## cristal), luego de lado y, por último, desde el lado del mago.

const MASK: int = 1 | (1 << 1)
## Puntos que prueba: detrás del blanco, de lado y del lado del mago.
const CANDIDATES: int = 3


## `side` (+1 o -1) elige el lado por el que entra; `normal`, la de la superficie del blanco.
static func origin(
	space: PhysicsDirectSpaceState3D,
	cam_pos: Vector3,
	target: Vector3,
	normal: Vector3,
	height: float,
	side: float
) -> Vector3:
	var flat: Vector3 = target - cam_pos
	flat.y = 0.0
	var fwd: Vector3 = flat.normalized() if flat.length() > 0.5 else Vector3.FORWARD
	var right: Vector3 = fwd.cross(Vector3.UP).normalized() * side
	var up := Vector3.UP * height
	var dist: float = flat.length()
	var start: Vector3 = target + (normal if normal.length_squared() > 0.01 else Vector3.UP) * 1.5
	# Sin arrays: se llama en cada frame mientras se carga (los círculos siguen el camino).
	for i: int in CANDIDATES:
		var c: Vector3 = target + up + right * height * (0.5 if i == 1 else 0.4)
		if i == 0:
			c += fwd * height * 0.3
		elif i == 2:
			c -= fwd * minf(height * 0.25, dist * 0.5)
		# El último se usa aunque choque (o si no hay física para comprobarlo).
		if i == CANDIDATES - 1:
			return c
		if (
			space
			and space.intersect_ray(PhysicsRayQueryParameters3D.create(start, c, MASK)).is_empty()
		):
			return c
	return target + up
