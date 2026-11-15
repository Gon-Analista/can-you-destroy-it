extends Node
## SFX con pool de reproductores (sin instanciar en caliente) y polifonía limitada.

const SFX_POOL_SIZE: int = 24

var _pool: Array[AudioStreamPlayer] = []
var _next: int = 0


func _ready() -> void:
	for i: int in SFX_POOL_SIZE:
		var player := AudioStreamPlayer.new()
		player.bus = &"SFX"
		add_child(player)
		_pool.append(player)


## Reproduce un sonido. Usar AudioStreamRandomizer para variar tono y sample.
func play_sfx(stream: AudioStream, volume_db: float = 0.0) -> void:
	if stream == null:
		return
	var player: AudioStreamPlayer = _pool[_next]
	_next = (_next + 1) % SFX_POOL_SIZE
	player.stream = stream
	player.volume_db = volume_db
	player.play()
