extends Node
## Opciones del jugador (vídeo, audio, controles, accesibilidad). Se guardan en
## user://settings.cfg. Quien cambie una opción llama a `apply_all()` (o a la de su grupo) y
## `changed` avisa a lo que la lee de forma diferida (resplandor de la magia, FPS del HUD...).

signal changed

const PATH: String = "user://settings.cfg"
## Carpeta con los idiomas: `strings.csv` (una columna por idioma) que Godot importa como
## `strings.<código>.translation`. Se cargan todos los que haya: añadir un idioma es sólo añadir
## una columna al CSV (ver localization/README.md).
const LOCALIZATION_DIR: String = "res://localization"
const DEFAULT_LOCALE: String = "en"
## Campo de visión vertical de la cámara (grados) y sus límites en Opciones.
const DEFAULT_FOV: float = 70.0
const FOV_MIN: float = 60.0
const FOV_MAX: float = 110.0
## Límites de FPS que ofrece Opciones (0 = sin límite).
const FPS_LIMITS: PackedInt32Array = [30, 60, 120, 144, 0]
## Con "reducir destellos", cuánto queda de cada destello (luz de impacto, cristal, resplandor).
const REDUCED_FLASH: float = 0.35

## Archivo de opciones (los tests lo cambian para no tocar el del jugador).
var path: String = PATH
var screen_shake: float = 1.0
## Los efectos leen la escala de destellos de `HdFx.flash_scale` (no pueden nombrar el autoload).
var reduce_flashes: bool = false:
	set(value):
		reduce_flashes = value
		HdFx.flash_scale = REDUCED_FLASH if value else 1.0
## Números de daño que saltan del cristal.
var damage_numbers: bool = true
## true: se mantiene el clic para cargar el combinado y sale al soltar; false: un clic lo
## empieza a cargar y el siguiente lo lanza.
var hold_to_charge: bool = true
## Multiplicador de la sensibilidad del ratón (1 = la de serie).
var mouse_sensitivity: float = 1.0
var invert_y: bool = false
var fullscreen: bool = false
var vsync: bool = true
## FPS máximos (0 = sin límite).
var fps_limit: int = 0
var show_fps: bool = false
var fov: float = DEFAULT_FOV
## Ya se abrió alguna vez el menú con Esc (deja de enseñarse la ayuda "ESC: MENÚ").
var menu_hint_seen: bool = false
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


## Vuelve a los valores de serie (menos el idioma) y los aplica.
func restore_defaults() -> void:
	screen_shake = 1.0
	reduce_flashes = false
	damage_numbers = true
	hold_to_charge = true
	mouse_sensitivity = 1.0
	invert_y = false
	fullscreen = false
	vsync = true
	fps_limit = 0
	show_fps = false
	fov = DEFAULT_FOV
	bus_volumes = {"Master": 1.0, "Music": 0.8, "SFX": 1.0, "UI": 1.0, "Ambience": 0.8}
	apply_all()


func apply_all() -> void:
	apply_audio()
	apply_video()
	changed.emit()


## Cuánto queda de un destello con la opción de accesibilidad (1 = entero).
func flash_scale() -> float:
	return REDUCED_FLASH if reduce_flashes else 1.0


func apply_video() -> void:
	Engine.max_fps = maxi(fps_limit, 0)
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED
	)
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
	cfg.set_value("accessibility", "damage_numbers", damage_numbers)
	cfg.set_value("controls", "hold_to_charge", hold_to_charge)
	cfg.set_value("controls", "mouse_sensitivity", mouse_sensitivity)
	cfg.set_value("controls", "invert_y", invert_y)
	cfg.set_value("video", "fullscreen", fullscreen)
	cfg.set_value("video", "vsync", vsync)
	cfg.set_value("video", "fps_limit", fps_limit)
	cfg.set_value("video", "show_fps", show_fps)
	cfg.set_value("video", "fov", fov)
	cfg.set_value("general", "locale", locale)
	cfg.set_value("general", "menu_hint_seen", menu_hint_seen)
	for bus_name: String in bus_volumes:
		cfg.set_value("audio", bus_name, bus_volumes[bus_name])
	cfg.save(path)


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return
	screen_shake = float(cfg.get_value("accessibility", "screen_shake", screen_shake))
	reduce_flashes = bool(cfg.get_value("accessibility", "reduce_flashes", reduce_flashes))
	damage_numbers = bool(cfg.get_value("accessibility", "damage_numbers", damage_numbers))
	hold_to_charge = bool(cfg.get_value("controls", "hold_to_charge", hold_to_charge))
	mouse_sensitivity = float(cfg.get_value("controls", "mouse_sensitivity", mouse_sensitivity))
	invert_y = bool(cfg.get_value("controls", "invert_y", invert_y))
	fullscreen = bool(cfg.get_value("video", "fullscreen", fullscreen))
	vsync = bool(cfg.get_value("video", "vsync", vsync))
	fps_limit = maxi(int(cfg.get_value("video", "fps_limit", fps_limit)), 0)
	show_fps = bool(cfg.get_value("video", "show_fps", show_fps))
	fov = clampf(float(cfg.get_value("video", "fov", fov)), FOV_MIN, FOV_MAX)
	locale = String(cfg.get_value("general", "locale", locale))
	menu_hint_seen = bool(cfg.get_value("general", "menu_hint_seen", menu_hint_seen))
	for bus_name: String in bus_volumes:
		bus_volumes[bus_name] = float(cfg.get_value("audio", bus_name, bus_volumes[bus_name]))
