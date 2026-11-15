extends SceneTree
## Música por capas: los OGG tienen el bucle activado, duran lo mismo (si no, se desincronizan)
## y `set_music_layers` sube y baja los volúmenes de las capas.
## godot --headless --path game --script res://tests/smoke/music_layers_smoke.gd

const NAMES: PackedStringArray = [
	"1_aprendiz", "2_iniciado", "3_hechicero", "4_magus", "5_archimago"
]

var _frames: int = 0
var _layers: Array[AudioStream] = []
var _ok: bool = true


func _initialize() -> void:
	for n: String in NAMES:
		var s: AudioStreamOggVorbis = load("res://audio/music/music_valley_%s.ogg" % n)
		_check(s.loop, "bucle activado en " + n)
		if _layers.size() > 0:
			var diff: float = absf(s.get_length() - _layers[0].get_length())
			_check(diff < 0.01, "misma duración en " + n)
		_layers.append(s)


func _process(_delta: float) -> bool:
	_frames += 1
	var director: Node = root.get_node(^"AudioDirector")
	if _frames == 2:
		director.call("play_music", _layers, 1)
		director.call("set_music_layers", 3, 0.05)
	elif _frames == 40:
		var stream: AudioStreamSynchronized = director.get("_music_stream")
		_check(int(director.call("get_music_layers")) == 3, "3 capas activas")
		for i: int in NAMES.size():
			var db: float = stream.get_sync_stream_volume(i)
			_check(
				db > -1.0 if i < 3 else db < -50.0, "volumen de la capa %d (%.1f dB)" % [i + 1, db]
			)
		print("music_layers_smoke: ", "OK" if _ok else "FALLO")
		quit(0 if _ok else 1)
	return false


func _check(cond: bool, what: String) -> void:
	if not cond:
		_ok = false
		push_error("FALLO: " + what)
