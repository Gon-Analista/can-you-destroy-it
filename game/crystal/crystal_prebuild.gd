class_name CrystalPrebuild
extends RefCounted
## Prepara el Cristal Madre antes de que exista: la rejilla (horneada más la partida guardada) y
## las mallas de todos sus trozos, en los hilos del WorkerThreadPool mientras se ve la pantalla
## de carga (`SceneFlow`). `MotherCrystal._ready` se lo queda con `take()`; si nadie lo empezó
## (las pruebas, el modo demo o la escena abierta desde el editor), `take()` lo hace allí mismo y
## espera, como antes.

## Rejilla guardada de la partida en curso (la escribe `MotherCrystal.save_state`).
const STATE_PATH: String = "user://crystal_volume.bin"

static var _volume: CrystalVolume
static var _resumed: bool = false
static var _ids := PackedInt32Array()
static var _results: Array[Array] = []
static var _task: int = -1
static var _done: int = 0
static var _mutex := Mutex.new()


## Lee la rejilla (≈0,1 s en el hilo principal) y reparte el mallado entre los hilos. No espera.
static func begin() -> void:
	if _volume != null:
		return
	_volume = CrystalVolume.new()
	_volume.load_baked()
	_resumed = _load_state(_volume)
	_ids = _all_chunks(_volume) if _resumed else _volume.surface_chunks
	_results.clear()
	_results.resize(_ids.size())
	_done = 0
	var field: PackedFloat32Array = _volume.sdf
	var v: CrystalVolume = _volume
	var ids: PackedInt32Array = _ids
	var job := func(i: int) -> void:
		var arrays: Array = CrystalVolume.mesh_chunk(
			field, v.depth, v.size, v.cell, v.origin, v.chunk, v.chunk_coords(ids[i])
		)
		_mutex.lock()
		_results[i] = arrays
		_done += 1
		_mutex.unlock()
	_task = WorkerThreadPool.add_group_task(job, _ids.size(), -1, true, "crystal_prebuild")


## 0..1: trozos ya mallados (1 si no hay nada en marcha).
static func progress() -> float:
	if _task < 0 or _ids.is_empty():
		return 1.0
	_mutex.lock()
	var n: int = _done
	_mutex.unlock()
	return float(n) / float(_ids.size())


static func is_done() -> bool:
	return _task < 0 or WorkerThreadPool.is_group_task_completed(_task)


## Lo que necesita el cristal: `volume`, `resumed` y `meshes` (índice de trozo -> arrays de la
## malla, vacío si el trozo no tiene superficie). Lo empieza y espera si hacía falta; después se
## olvida de todo (la próxima partida empieza de cero).
static func take() -> Dictionary:
	begin()
	WorkerThreadPool.wait_for_group_task_completion(_task)
	var meshes: Dictionary[int, Array] = {}
	for i: int in _ids.size():
		meshes[_ids[i]] = _results[i]
	var out: Dictionary = {&"volume": _volume, &"resumed": _resumed, &"meshes": meshes}
	_volume = null
	_task = -1
	_ids = PackedInt32Array()
	_results.clear()
	return out


static func _load_state(volume: CrystalVolume) -> bool:
	var prog: Progression = GameState.progression
	if not SaveSystem.enabled or prog.essence >= prog.total_essence:
		return false
	if not FileAccess.file_exists(STATE_PATH):
		return false
	return volume.load_state(FileAccess.get_file_as_bytes(STATE_PATH))


static func _all_chunks(volume: CrystalVolume) -> PackedInt32Array:
	var out := PackedInt32Array()
	for i: int in volume.chunks.x * volume.chunks.y * volume.chunks.z:
		out.append(i)
	return out
