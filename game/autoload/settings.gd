extends Node
## Opciones del jugador (accesibilidad, audio). Se guardan en user://settings.cfg.

const PATH: String = "user://settings.cfg"
## Carpeta con los idiomas: `strings.csv` (una columna por idioma) que Godot importa como
## `strings.<código>.translation`. Se cargan todos los que haya: añadir un idioma es sólo añadir
## una columna al CSV (ver localization/README.md).
const LOCALIZATION_DIR: String = "res://localization"
const DEFAULT_LOCALE: String = "en"

var screen_shake: float = 1.0
var reduce_flashes: bool = false
var hold_to_charge: bool = true
## Multiplicador de la sensibilidad del ratón (1 = la de serie).
var mouse_sensitivity: float = 1.0
var fullscreen: bool = false
## Código del idioma elegido ("" = el del sistema si lo tenemos, si no inglés).
var locale: String = ""
var bus_volumes: Dictionary[String, float] = {
	"Master": 1.0, "Music": 0.8, "SFX": 1.0, "UI": 1.0, "Ambience": 0.8
}


func _ready() -> void:
	load_translations()
	load_settings()
	apply_locale()
	apply_audio()
	apply_video()


## Registra todos los `.translation` de la carpeta de idiomas.
func load_translations() -> void:
	var dir := DirAccess.open(LOCALIZATION_DIR)
	if dir == null:
		return
	for file: String in dir.get_files():
		var path: String = LOCALIZATION_DIR.path_join(file.trim_suffix(".remap"))
		if not path.ends_with(".translation"):
			continue
		var t := load(path) as Translation
		if t and not TranslationServer.get_loaded_locales().has(t.locale):
			TranslationServer.add_translation(t)


## Idiomas disponibles, en el orden del CSV no garantizado: ordenados por código.
func locales() -> PackedStringArray:
	var out := PackedStringArray(TranslationServer.get_loaded_locales())
	out.sort()
	return out


## Nombre de un idioma tal como se muestra en Opciones (la fila LANGUAGE_NAME del CSV).
func language_name(code: String) -> String:
	for t: Translation in _translations():
		if t.locale == code:
			return String(t.get_message(&"LANGUAGE_NAME"))
	return code.to_upper()


func apply_locale() -> void:
	var available: PackedStringArray = locales()
	if available.is_empty():
		return
	var code: String = locale
	# `-- --lang en` fuerza un idioma sin tocar las opciones guardadas (capturas, pruebas).
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var i: int = args.find("--lang")
	if i >= 0 and i + 1 < args.size():
		code = args[i + 1]
	if not available.has(code):
		code = _best_match(OS.get_locale(), available)
	TranslationServer.set_locale(code)


func set_locale(code: String) -> void:
	locale = code
	apply_locale()
	save_settings()


func current_locale() -> String:
	return TranslationServer.get_locale()


## El idioma del sistema si lo tenemos (es_AR -> es), si no inglés, si no el primero.
func _best_match(os_locale: String, available: PackedStringArray) -> String:
	if available.has(os_locale):
		return os_locale
	var lang: String = os_locale.get_slice("_", 0)
	if available.has(lang):
		return lang
	for code: String in available:
		if code.get_slice("_", 0) == lang:
			return code
	return DEFAULT_LOCALE if available.has(DEFAULT_LOCALE) else available[0]


func _translations() -> Array[Translation]:
	var out: Array[Translation] = []
	for code: String in TranslationServer.get_loaded_locales():
		var t: Translation = TranslationServer.get_translation_object(code)
		if t:
			out.append(t)
	return out


func apply_video() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var mode: DisplayServer.WindowMode = (
		DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	)
	if DisplayServer.window_get_mode() != mode:
		DisplayServer.window_set_mode(mode)


func apply_audio() -> void:
	for bus_name: String in bus_volumes:
		var idx: int = AudioServer.get_bus_index(bus_name)
		if idx >= 0:
			AudioServer.set_bus_volume_db(idx, linear_to_db(bus_volumes[bus_name]))


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("accessibility", "screen_shake", screen_shake)
	cfg.set_value("accessibility", "reduce_flashes", reduce_flashes)
	cfg.set_value("controls", "hold_to_charge", hold_to_charge)
	cfg.set_value("controls", "mouse_sensitivity", mouse_sensitivity)
	cfg.set_value("video", "fullscreen", fullscreen)
	cfg.set_value("general", "locale", locale)
	for bus_name: String in bus_volumes:
		cfg.set_value("audio", bus_name, bus_volumes[bus_name])
	cfg.save(PATH)


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	screen_shake = float(cfg.get_value("accessibility", "screen_shake", screen_shake))
	reduce_flashes = bool(cfg.get_value("accessibility", "reduce_flashes", reduce_flashes))
	hold_to_charge = bool(cfg.get_value("controls", "hold_to_charge", hold_to_charge))
	mouse_sensitivity = float(cfg.get_value("controls", "mouse_sensitivity", mouse_sensitivity))
	fullscreen = bool(cfg.get_value("video", "fullscreen", fullscreen))
	locale = String(cfg.get_value("general", "locale", locale))
	for bus_name: String in bus_volumes:
		bus_volumes[bus_name] = float(cfg.get_value("audio", bus_name, bus_volumes[bus_name]))
