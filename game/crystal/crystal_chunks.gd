class_name CrystalChunks
extends Node3D
## Las mallas y colisiones del Cristal Madre, un trozo por cada `CrystalVolume.chunk`^3 celdas.
## Al excavar se marcan los trozos tocados y se rehacen en otro hilo (WorkerThreadPool) con una
## copia de la rejilla; el resultado se aplica en el hilo principal. Si un trozo se vuelve a
## tocar mientras se rehace, se rehace otra vez al terminar.

## Milisegundos por fotograma para aplicar trozos rehechos (ver `_process`).
const APPLY_BUDGET_MS: float = 3.0

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
## Mallas ya hechas que esperan a aplicarse (índice de trozo -> arrays), por orden de llegada.
var _pending: Dictionary[int, Array] = {}
var _order: Array[int] = []
## Tarea del WorkerThreadPool de cada trozo en marcha: hay que esperarlas todas (al terminar cada
## una y al salir del árbol), o un hilo puede seguir con el nodo ya borrado.
var _tasks: Dictionary[int, int] = {}


func setup(p_volume: CrystalVolume, p_material: Material, p_body: StaticBody3D) -> void:
	volume = p_volume
	material = p_material
	body = p_body
	_occluder_material = ShaderMaterial.new()
	_occluder_material.shader = preload("res://crystal/crystal_occluder.gdshader")
	_occluder_material.render_priority = Material.RENDER_PRIORITY_MIN
	set_process(false)


## Malla inicial: aplica las mallas que dejó hechas `CrystalPrebuild` (índice de trozo ->
## arrays de la malla).
func apply_all(meshes: Dictionary[int, Array]) -> void:
	for ci: int in meshes:
		_apply(ci, meshes[ci])


func mark_dirty(chunk_ids: Array) -> void:
	for ci: int in chunk_ids:
		if _running.has(ci):
			_again[ci] = true
		else:
			_start(ci)


func is_busy() -> bool:
	return not _running.is_empty() or not _pending.is_empty()


func _start(ci: int) -> void:
	_running[ci] = true
	# Copia de la rejilla (COW): si el hilo principal sigue excavando, no se pisan.
	# Prioridad baja: un golpe enorme rehace decenas de trozos y, con prioridad alta, ocupaban
	# todos los núcleos y el render (hilo principal y driver) se quedaba sin CPU (tirones de
	# 100 ms). En baja usan sólo una parte de los hilos del pool.
	var field: PackedFloat32Array = volume.sdf
	var v: CrystalVolume = volume
	var coords: Vector3i = v.chunk_coords(ci)
	_tasks[ci] = WorkerThreadPool.add_task(
		func() -> void:
			var arrays: Array = CrystalVolume.mesh_chunk(
				field, v.depth, v.size, v.cell, v.origin, v.chunk, coords
			)
			_finish.call_deferred(ci, arrays),
		false,
		"crystal_chunk"
	)


## Un trozo rehecho en el hilo: no se aplica en el acto, se pone en cola (ver `_process`). Si lo
## volvieron a tocar mientras tanto, se rehace ya; el resultado nuevo sustituye al de la cola.
func _finish(ci: int, arrays: Array) -> void:
	if _tasks.has(ci):
		WorkerThreadPool.wait_for_task_completion(_tasks[ci])
		_tasks.erase(ci)
	_running.erase(ci)
	if not _pending.has(ci):
		_order.append(ci)
	_pending[ci] = arrays
	set_process(true)
	if _again.has(ci):
		_again.erase(ci)
		_start(ci)


## Al borrar el cristal (salir, volver al título, nueva partida) se esperan los hilos que queden.
func _exit_tree() -> void:
	for ci: int in _tasks:
		WorkerThreadPool.wait_for_task_completion(_tasks[ci])
	_tasks.clear()


## Aplicar un trozo (malla, oclusor y colisión) cuesta hasta varios ms en el hilo principal y un
## golpe enorme rehace decenas a la vez: se aplican por orden de llegada hasta gastar
## `APPLY_BUDGET_MS` por fotograma (al menos uno), y la cola se vacía en unos pocos fotogramas.
func _process(_delta: float) -> void:
	var t0: int = Time.get_ticks_usec()
	while not _order.is_empty():
		var ci: int = _order.pop_front()
		var arrays: Array = _pending[ci]
		_pending.erase(ci)
		_apply(ci, arrays)
		if Time.get_ticks_usec() - t0 >= APPLY_BUDGET_MS * 1000.0:
			break
	if _order.is_empty():
		set_process(false)


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
	var faces: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	shape.set_faces(faces)
	_shapes[ci].shape = shape


## Triángulos en total (para el informe de rendimiento).
func triangle_count() -> int:
	var n: int = 0
	for ci: int in _meshes:
		var m: ArrayMesh = _meshes[ci].mesh
		@warning_ignore("integer_division")
		n += m.surface_get_array_len(0) / 3
	return n
