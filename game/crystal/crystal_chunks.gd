class_name CrystalChunks
extends Node3D
## Las mallas y colisiones del Cristal Madre, un trozo por cada `CrystalVolume.chunk`^3 celdas.
## Al excavar se marcan los trozos tocados y se rehacen en otro hilo (WorkerThreadPool) con una
## copia de la rejilla; el resultado se aplica en el hilo principal. Si un trozo se vuelve a
## tocar mientras se rehace, se rehace otra vez al terminar.

var volume: CrystalVolume
var material: Material
## Cuerpo estático con una forma por trozo (los hechizos y el jugador chocan con él).
var body: StaticBody3D

var _meshes: Dictionary[int, MeshInstance3D] = {}
## Copias en la capa de magia que sólo escriben profundidad (ver crystal_occluder.gdshader).
var _occluders: Dictionary[int, MeshInstance3D] = {}
var _occluder_material: ShaderMaterial
var _shapes: Dictionary[int, CollisionShape3D] = {}
var _running: Dictionary[int, bool] = {}
var _again: Dictionary[int, bool] = {}
var _mutex := Mutex.new()


func setup(p_volume: CrystalVolume, p_material: Material, p_body: StaticBody3D) -> void:
	volume = p_volume
	material = p_material
	body = p_body
	_occluder_material = ShaderMaterial.new()
	_occluder_material.shader = preload("res://crystal/crystal_occluder.gdshader")
	_occluder_material.render_priority = Material.RENDER_PRIORITY_MIN


## Malla inicial: todos los trozos con superficie a la vez, repartidos entre los hilos, y espera
## a que terminen (se llama tras la pantalla de carga).
func build_all(chunk_ids: PackedInt32Array) -> void:
	var results: Dictionary[int, Array] = {}
	var field: PackedFloat32Array = volume.sdf
	var v: CrystalVolume = volume
	var job := func(i: int) -> void:
		var ci: int = chunk_ids[i]
		var arrays: Array = CrystalVolume.mesh_chunk(
			field, v.depth, v.size, v.cell, v.origin, v.chunk, v.chunk_coords(ci)
		)
		_mutex.lock()
		results[ci] = arrays
		_mutex.unlock()
	var task: int = WorkerThreadPool.add_group_task(job, chunk_ids.size(), -1, true, "crystal")
	WorkerThreadPool.wait_for_group_task_completion(task)
	for ci: int in results:
		_apply(ci, results[ci])


## Todos los trozos que tengan algo (al cargar una partida con el cristal ya excavado).
func all_chunks() -> PackedInt32Array:
	var out := PackedInt32Array()
	for i: int in volume.chunks.x * volume.chunks.y * volume.chunks.z:
		out.append(i)
	return out


func mark_dirty(chunk_ids: Array) -> void:
	for ci: int in chunk_ids:
		if _running.has(ci):
			_again[ci] = true
		else:
			_start(ci)


func is_busy() -> bool:
	return not _running.is_empty()


func _start(ci: int) -> void:
	_running[ci] = true
	# Copia de la rejilla (COW): si el hilo principal sigue excavando, no se pisan.
	var field: PackedFloat32Array = volume.sdf
	var v: CrystalVolume = volume
	var coords: Vector3i = v.chunk_coords(ci)
	WorkerThreadPool.add_task(
		func() -> void:
			var arrays: Array = CrystalVolume.mesh_chunk(
				field, v.depth, v.size, v.cell, v.origin, v.chunk, coords
			)
			_finish.call_deferred(ci, arrays),
		true,
		"crystal_chunk"
	)


func _finish(ci: int, arrays: Array) -> void:
	_running.erase(ci)
	_apply(ci, arrays)
	if _again.has(ci):
		_again.erase(ci)
		_start(ci)


func _apply(ci: int, arrays: Array) -> void:
	if arrays.is_empty():
		if _meshes.has(ci):
			_meshes[ci].queue_free()
			_meshes.erase(ci)
			_occluders[ci].queue_free()
			_occluders.erase(ci)
			_shapes[ci].queue_free()
			_shapes.erase(ci)
		return
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi: MeshInstance3D = _meshes.get(ci)
	if mi == null:
		mi = MeshInstance3D.new()
		mi.name = "Chunk%d" % ci
		mi.material_override = material
		add_child(mi)
		_meshes[ci] = mi
		var occ := MeshInstance3D.new()
		occ.name = "Occluder%d" % ci
		occ.material_override = _occluder_material
		occ.layers = MagicLayer.MAGIC_LAYER
		occ.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(occ)
		_occluders[ci] = occ
		var col := CollisionShape3D.new()
		col.name = "Chunk%d" % ci
		body.add_child(col)
		_shapes[ci] = col
	mi.mesh = mesh
	_occluders[ci].mesh = mesh
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(arrays[Mesh.ARRAY_VERTEX])
	_shapes[ci].shape = shape


## Triángulos en total (para el informe de rendimiento).
func triangle_count() -> int:
	var n: int = 0
	for ci: int in _meshes:
		var m: ArrayMesh = _meshes[ci].mesh
		n += m.surface_get_array_len(0) / 3
	return n
