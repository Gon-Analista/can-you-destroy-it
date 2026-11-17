extends Node
## SFX con pool de reproductores (sin instanciar en caliente) y polifonía limitada.
## Música por capas sincronizadas que se suman con el rango del mago (GDD, dev guidelines 7).

const SFX_POOL_SIZE: int = 24
## Volumen de una capa apagada (silencio práctico sin parar la reproducción ni perder la sincronía).
const MUTED_DB: float = -60.0

var _pool: Array[AudioStreamPlayer] = []
var _next: int = 0
var _ambience: AudioStreamPlayer
var _music: AudioStreamPlayer
var _music_stream: AudioStreamSynchronized
var _music_layers: int = 0
var _music_tween: Tween


func _ready() -> void:
	for i: int in SFX_POOL_SIZE:
		var player := AudioStreamPlayer.new()
		player.bus = &"SFX"
		add_child(player)
		_pool.append(player)


## Reproduce un sonido. Usar AudioStreamRandomizer para variar tono y sample.
## `pitch` desplaza el tono (p. ej. un hechizo más grave cuanto más nivel tiene).
func play_sfx(stream: AudioStream, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if stream == null:
		return
	var player: AudioStreamPlayer = _pool[_next]
	_next = (_next + 1) % SFX_POOL_SIZE
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = pitch
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


## Música por capas: todas suenan a la vez y en sincronía exacta (AudioStreamSynchronized);
## sólo las `active_layers` primeras se oyen. Cada OGG necesita `loop=true` en su importación.
func play_music(
	layers: Array[AudioStream], active_layers: int = 1, volume_db: float = -8.0
) -> void:
	if _music == null:
		_music = AudioStreamPlayer.new()
		_music.bus = &"Music"
		add_child(_music)
	_music_stream = AudioStreamSynchronized.new()
	_music_stream.stream_count = layers.size()
	_music_layers = clampi(active_layers, 0, layers.size())
	for i: int in layers.size():
		_music_stream.set_sync_stream(i, layers[i])
		_music_stream.set_sync_stream_volume(i, 0.0 if i < _music_layers else MUTED_DB)
	_music.stream = _music_stream
	_music.volume_db = volume_db
	_music.play()


## Sube o baja el número de capas audibles con un fundido (p. ej. al subir de rango).
func set_music_layers(count: int, fade_sec: float = 3.0) -> void:
	if _music_stream == null:
		return
	count = clampi(count, 0, _music_stream.stream_count)
	if count == _music_layers:
		return
	var from: int = _music_layers
	_music_layers = count
	if _music_tween != null:
		_music_tween.kill()
	_music_tween = create_tween().set_parallel(true)
	for i: int in _music_stream.stream_count:
		var target: float = 0.0 if i < count else MUTED_DB
		var current: float = _music_stream.get_sync_stream_volume(i)
		if is_equal_approx(current, target):
			continue
		# Las capas que entran lo hacen con curva suave; las que salen, un poco más rápido.
		var dur: float = fade_sec if i >= from else fade_sec * 0.6
		_music_tween.tween_method(_set_layer_volume.bind(i), current, target, dur)


func get_music_layers() -> int:
	return _music_layers


func _set_layer_volume(db: float, index: int) -> void:
	_music_stream.set_sync_stream_volume(index, db)
