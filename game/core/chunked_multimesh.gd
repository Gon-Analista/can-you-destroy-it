class_name ChunkedMultiMesh
extends RefCounted
## Reparte instancias (árboles, hierba, flores) en trozos de una rejilla del suelo, un
## `MultiMeshInstance3D` por trozo. Un solo MultiMesh para todo el valle tenía una caja que lo
## abarcaba todo: el motor lo dibujaba entero (y en cada cascada de sombra) aunque la cámara
## mirase a otro lado. Por trozos, la cámara y las sombras descartan los que no ven, el LOD de la
## malla se elige por trozo según su distancia y se puede cortar por distancia (`vis_end`).


## Crea los trozos como hijos de `parent`. `colors` puede ir vacío (sin color por instancia).
## `vis_end` > 0 oculta los trozos más lejos que eso (medido al centro del trozo: se le suma
## media diagonal para no cortar nada que aún se vea). Devuelve los nodos creados.
static func build(
	parent: Node3D,
	base_name: String,
	mesh: Mesh,
	xforms: Array,
	colors: Array,
	material: Material,
	cell: float,
	cast_shadow: GeometryInstance3D.ShadowCastingSetting,
	vis_end: float = 0.0
) -> Array[MultiMeshInstance3D]:
	var buckets: Dictionary = {}
	for i: int in xforms.size():
		var t: Transform3D = xforms[i]
		var key := Vector2i(floori(t.origin.x / cell), floori(t.origin.z / cell))
		if not buckets.has(key):
			buckets[key] = []
		var bucket: Array = buckets[key]
		bucket.append(i)
	var out: Array[MultiMeshInstance3D] = []
	var use_colors: bool = not colors.is_empty()
	for key: Vector2i in buckets:
		var ids: Array = buckets[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = use_colors
		mm.mesh = mesh
		mm.instance_count = ids.size()
		for k: int in ids.size():
			var idx: int = ids[k]
			var xform: Transform3D = xforms[idx]
			mm.set_instance_transform(k, xform)
			if use_colors:
				var col: Color = colors[idx]
				mm.set_instance_color(k, col)
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "%s_%d_%d" % [base_name, key.x, key.y]
		mmi.multimesh = mm
		mmi.material_override = material
		mmi.cast_shadow = cast_shadow
		if vis_end > 0.0:
			mmi.visibility_range_end = vis_end + cell * 0.75
		parent.add_child(mmi)
		out.append(mmi)
	return out


## Malla indexada (vértices compartidos) con niveles de detalle automáticos para la distancia.
## El motor cambia de nivel cuando la diferencia ocupa menos de un píxel
## (`mesh_lod_threshold`), así que de cerca se ve igual.
static func with_lods(st: SurfaceTool) -> ArrayMesh:
	st.index()
	var arrays: Array = st.commit_to_arrays()
	var im := ImporterMesh.new()
	im.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays)
	im.generate_lods(60.0, 25.0, [])
	return im.get_mesh()
