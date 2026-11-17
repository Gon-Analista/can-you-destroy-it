extends Node
## Opciones del jugador (accesibilidad, audio). Se guardan en user://settings.cfg.

const PATH: String = "user://settings.cfg"

var screen_shake: float = 1.0
var reduce_flashes: bool = false
var hold_to_charge: bool = true
## Multiplicador de la sensibilidad del ratón (1 = la de serie).
var mouse_sensitivity: float = 1.0
var fullscreen: bool = false
var bus_volumes: Dictionary[String, float] = {
	"Master": 1.0, "Music": 0.8, "SFX": 1.0, "UI": 1.0, "Ambience": 0.8
}


func _ready() -> void:
	load_settings()
	apply_audio()
	apply_video()


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
	for bus_name: String in bus_volumes:
		bus_volumes[bus_name] = float(cfg.get_value("audio", bus_name, bus_volumes[bus_name]))
