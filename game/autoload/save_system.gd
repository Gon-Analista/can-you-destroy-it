extends Node
## Guardado en JSON con versión y escritura atómica. Autoguardado periódico.

const SAVE_PATH: String = "user://save.json"
const TMP_PATH: String = "user://save.json.tmp"
const SAVE_VERSION: int = 1

var _autosave: Timer
## En el modo demo (`-- --autoplay`) no se toca la partida guardada: las capturas empiezan de
## cero y sus trucos (--mana, --bag) no ensucian la partida del jugador.
var enabled: bool = not OS.get_cmdline_user_args().has("--autoplay")


func _ready() -> void:
	if not enabled:
		return
	load_game()
	_autosave = Timer.new()
	_autosave.wait_time = GameState.BALANCE.autosave_interval_sec
	_autosave.autostart = true
	_autosave.timeout.connect(save_game)
	add_child(_autosave)
	Events.upgrade_bought.connect(func(_id: StringName, _lvl: int) -> void: save_game())
	Events.recipe_discovered.connect(func(_r: SpellRecipe) -> void: save_game())


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_game()


func save_game() -> bool:
	if not enabled:
		return false
	var payload: Dictionary = {
		"version": SAVE_VERSION, "progression": GameState.progression.to_dict()
	}
	var file: FileAccess = FileAccess.open(TMP_PATH, FileAccess.WRITE)
	if file == null:
		push_error("No se pudo escribir el guardado: %s" % FileAccess.get_open_error())
		return false
	file.store_string(JSON.stringify(payload))
	file.close()
	var err: Error = DirAccess.rename_absolute(
		ProjectSettings.globalize_path(TMP_PATH), ProjectSettings.globalize_path(SAVE_PATH)
	)
	if err != OK:
		push_error("No se pudo reemplazar el guardado: %s" % error_string(err))
		return false
	return true


func load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if not parsed is Dictionary:
		push_warning("Guardado corrupto; se empieza partida nueva.")
		return
	var data: Dictionary = parsed
	# Aquí van las migraciones cuando SAVE_VERSION suba.
	GameState.progression.load_dict(data.get("progression", {}))
	GameState.emit_all()
