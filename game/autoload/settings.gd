extends Node
## Opciones del jugador (accesibilidad, audio). Se guardan en user://settings.cfg.

const PATH: String = "user://settings.cfg"

var screen_shake: float = 1.0
var reduce_flashes: bool = false
var hold_to_charge: bool = true
var bus_volumes: Dictionary[String, float] = {"Master": 1.0, "Music": 0.8, "SFX": 1.0, "UI": 1.0, "Ambience": 0.8}


func _ready() -> void:
	load_settings()
	apply_audio()


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
	for bus_name: String in bus_volumes:
		bus_volumes[bus_name] = float(cfg.get_value("audio", bus_name, bus_volumes[bus_name]))
