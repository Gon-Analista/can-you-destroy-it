extends Node
## SFX con pool de reproductores (sin instanciar en caliente) y polifonía limitada.

const SFX_POOL_SIZE: int = 24

var _pool: Array[AudioStreamPlayer] = []
var _next: int = 0
var _ambience: AudioStreamPlayer


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


## Ambiente en bucle (bus Ambience). Llamar de nuevo cambia la pista.
func play_ambience(stream: AudioStream, volume_db: float = -6.0) -> void:
	if _ambience == null:
		_ambience = AudioStreamPlayer.new()
		_ambience.bus = &"Ambience"
		add_child(_ambience)
	# El bucle se activa en la importación del OGG (loop=true), no aquí.
	_ambience.stream = stream
	_ambience.volume_db = volume_db
	_ambience.play()
