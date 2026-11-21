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
## Tema aparte (el del título) que suena por encima de la música del valle, que se silencia.
var _theme: AudioStreamPlayer
var _theme_tween: Tween
var _music_base_db: float = -8.0
## Filtro de paso bajo en el bus de música: la música "se oye desde dentro" de la casucha.
var _muffle: AudioEffectLowPassFilter
var _muffle_tween: Tween


func _ready() -> void:
	for i: int in SFX_POOL_SIZE:
		var player := AudioStreamPlayer.new()
		player.bus = &"SFX"
		add_child(player)
		_pool.append(player)
	var bus: int = AudioServer.get_bus_index(&"Music")
	if bus >= 0:
		_muffle = AudioEffectLowPassFilter.new()
		_muffle.cutoff_hz = 20000.0
		AudioServer.add_bus_effect(bus, _muffle)


## Música amortiguada (dentro de un sitio cerrado) o abierta, con un fundido.
func muffle_music(on: bool, fade_sec: float = 2.0) -> void:
	if _muffle == null:
		return
	if _muffle_tween:
		_muffle_tween.kill()
	_muffle_tween = create_tween()
	(
		_muffle_tween
		. tween_property(_muffle, "cutoff_hz", 700.0 if on else 20000.0, fade_sec)
		. set_trans(Tween.TRANS_EXPO)
	)


## Calla el valle (música por capas y ambiente) y quita el amortiguado: al volver al título.
func stop_world() -> void:
	if _music_tween:
		_music_tween.kill()
	if _music:
		_music.stop()
	_music_stream = null
	_music_layers = 0
	if _ambience:
		_ambience.stop()
	if _muffle_tween:
		_muffle_tween.kill()
	if _muffle:
		_muffle.cutoff_hz = 20000.0


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
	_music_base_db = volume_db
	_music.volume_db = volume_db if _theme == null or not _theme.playing else -60.0
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


## Tema propio (p. ej. el del título): suena solo y la música del valle se calla mientras.
func play_theme(stream: AudioStream, volume_db: float = -6.0) -> void:
	if _theme == null:
		_theme = AudioStreamPlayer.new()
		_theme.bus = &"Music"
		_theme.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(_theme)
	if _theme_tween:
		_theme_tween.kill()
	if _theme.playing and _theme.stream == stream:
		_theme.volume_db = volume_db
		return
	_theme.stream = stream  # bucle activado en la importación
	_theme.volume_db = volume_db
	_theme.play()
	if _music:
		_music.volume_db = -60.0


## Sube o baja el tema (sin cambiar la música del valle, que sigue callada): la Gran Convergencia
## apaga la música mientras se carga.
func fade_theme(volume_db: float, fade_sec: float = 1.0) -> void:
	if _theme == null or not _theme.playing:
		return
	if _theme_tween:
		_theme_tween.kill()
	_theme_tween = create_tween()
	_theme_tween.tween_property(_theme, "volume_db", volume_db, maxf(fade_sec, 0.01))


## Funde el tema con la música del valle.
func stop_theme(fade_sec: float = 2.5) -> void:
	if _theme == null or not _theme.playing:
		return
	if _theme_tween:
		_theme_tween.kill()
	_theme_tween = create_tween().set_parallel(true)
	_theme_tween.tween_property(_theme, "volume_db", -60.0, fade_sec)
	if _music:
		_theme_tween.tween_property(_music, "volume_db", _music_base_db, fade_sec * 1.2)
	_theme_tween.chain().tween_callback(_theme.stop)
