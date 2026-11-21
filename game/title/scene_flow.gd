class_name SceneFlow
extends RefCounted
## Cambios de escena con pantalla de carga: del título (ligero, sin mundo 3D) al juego y de
## vuelta. El juego (`main.tscn`) se empieza a cargar en otro hilo en cuanto se ve el título
## (`preload_game`); al pulsar JUGAR se espera a que termine, se talla el cristal en los hilos
## (`CrystalPrebuild`) y se monta la escena. Lo que queda (precalentar efectos) lo hace
## `Main._warm_up`, que termina la misma pantalla de carga.

const GAME_SCENE: String = "res://main/main.tscn"
const TITLE_SCENE: String = "res://title/title_screen.tscn"

## Tramos de la barra de carga: escena, cristal y montaje (lo demás es de `Main._warm_up`).
const SCENE_SHARE: float = 0.3
const CRYSTAL_SHARE: float = 0.3
const MOUNT_AT: float = 0.62

static var _requested: bool = false
static var _busy: bool = false


## Empieza a cargar el juego en otro hilo (sin esperar). Se puede llamar varias veces.
static func preload_game() -> void:
	if _requested:
		return
	var err: Error = ResourceLoader.load_threaded_request(GAME_SCENE, "PackedScene", true)
	_requested = err == OK


## Al juego, con la pantalla de carga (desde el título, o desde el juego en "Nueva partida").
static func to_game(tree: SceneTree) -> void:
	if _busy:
		return
	_busy = true
	tree.paused = false
	var cover: LoadingCover = LoadingCover.open(tree, true)
	cover.set_progress(0.02, "CARGANDO EL VALLE")
	await _frames(tree, 2)
	var packed: PackedScene = await _wait_scene(tree, cover)
	# El cristal, en los hilos mientras la barra sigue viva.
	cover.set_progress(SCENE_SHARE, "TALLANDO EL CRISTAL")
	await tree.process_frame
	CrystalPrebuild.begin()
	while not CrystalPrebuild.is_done():
		cover.set_progress(SCENE_SHARE + CRYSTAL_SHARE * CrystalPrebuild.progress())
		await tree.process_frame
	# Montar la escena es un tirón en el hilo principal: que se vea la etapa antes.
	cover.set_progress(MOUNT_AT, "DESPERTANDO EL VALLE")
	await _frames(tree, 3)
	_swap(tree, packed.instantiate())
	_busy = false


## Al título (desde la pausa): la partida ya está guardada.
static func to_title(tree: SceneTree) -> void:
	if _busy:
		return
	_busy = true
	tree.paused = false
	var cover: LoadingCover = LoadingCover.open(tree, true)
	cover.set_progress(0.5, "VOLVIENDO AL TÍTULO")
	await _frames(tree, 8)
	AudioDirector.stop_world()
	var packed: PackedScene = load(TITLE_SCENE)
	_swap(tree, packed.instantiate())
	await _frames(tree, 2)
	cover.finish()
	_busy = false


static func _wait_scene(tree: SceneTree, cover: LoadingCover) -> PackedScene:
	preload_game()
	var progress: Array = []
	while _requested:
		var status: ResourceLoader.ThreadLoadStatus = ResourceLoader.load_threaded_get_status(
			GAME_SCENE, progress
		)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			break
		if status != ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			push_warning("SceneFlow: la carga en otro hilo falló (%d); se carga aquí." % status)
			_requested = false
			break
		var ratio: float = progress[0] if progress.size() > 0 else 0.0
		cover.set_progress(0.02 + (SCENE_SHARE - 0.02) * ratio)
		await tree.process_frame
	if _requested:
		_requested = false
		return ResourceLoader.load_threaded_get(GAME_SCENE) as PackedScene
	return load(GAME_SCENE) as PackedScene


## Cambia la escena actual por `scene` (la vieja se borra antes de montar la nueva).
static func _swap(tree: SceneTree, scene: Node) -> void:
	var old: Node = tree.current_scene
	if old != null:
		tree.root.remove_child(old)
		old.queue_free()
	tree.root.add_child(scene)
	tree.current_scene = scene


static func _frames(tree: SceneTree, n: int) -> void:
	for i: int in n:
		await tree.process_frame
