class_name CritterVoices
extends Node
## Los sonidos de los bichos (tools/sfx_critters.py), en 3D y con variación de muestra y tono:
## chillidos, el ¡splorch! al reventar, el muelle al salir del suelo, el kazoo de despedida, los
## ojos que rebotan, la baba que cae y sus gestos. Pool de reproductores; cada sonido tiene un
## hueco mínimo para que un montón de bichos reventando a la vez no sea un muro de ruido.

enum Kind {
	SQUEAK,
	SPLORCH,
	BOING,
	KAZOO,
	INFLATE,
	BOINK,
	SPLAT,
	SNEEZE,
	YAWN,
	GIGGLE,
	BLEP,
	FLATTEN,
	CONFETTI,
	ZAP,
	CLINK,
}

const PLAYERS: int = 12
## Separación mínima (s) entre dos sonidos del mismo tipo.
const MIN_GAP: PackedFloat32Array = [
	0.05, 0.04, 0.08, 0.15, 0.06, 0.05, 0.04, 0.2, 0.2, 0.2, 0.2, 0.1, 0.06, 0.1, 0.04
]
const STREAMS: Array[Array] = [
	[
		preload("res://audio/sfx/sfx_critter_squeak_01.ogg"),
		preload("res://audio/sfx/sfx_critter_squeak_02.ogg"),
		preload("res://audio/sfx/sfx_critter_squeak_03.ogg"),
		preload("res://audio/sfx/sfx_critter_squeak_04.ogg"),
	],
	[
		preload("res://audio/sfx/sfx_critter_splorch_01.ogg"),
		preload("res://audio/sfx/sfx_critter_splorch_02.ogg"),
		preload("res://audio/sfx/sfx_critter_splorch_03.ogg"),
		preload("res://audio/sfx/sfx_critter_splorch_04.ogg"),
	],
	[
		preload("res://audio/sfx/sfx_critter_boing_01.ogg"),
		preload("res://audio/sfx/sfx_critter_boing_02.ogg"),
	],
	[
		preload("res://audio/sfx/sfx_critter_kazoo_01.ogg"),
		preload("res://audio/sfx/sfx_critter_kazoo_02.ogg"),
		preload("res://audio/sfx/sfx_critter_kazoo_03.ogg"),
	],
	[
		preload("res://audio/sfx/sfx_critter_inflate_01.ogg"),
		preload("res://audio/sfx/sfx_critter_inflate_02.ogg"),
	],
	[
		preload("res://audio/sfx/sfx_critter_boink_01.ogg"),
		preload("res://audio/sfx/sfx_critter_boink_02.ogg"),
	],
	[
		preload("res://audio/sfx/sfx_critter_splat_01.ogg"),
		preload("res://audio/sfx/sfx_critter_splat_02.ogg"),
	],
	[preload("res://audio/sfx/sfx_critter_sneeze_01.ogg")],
	[preload("res://audio/sfx/sfx_critter_yawn_01.ogg")],
	[
		preload("res://audio/sfx/sfx_critter_giggle_01.ogg"),
		preload("res://audio/sfx/sfx_critter_giggle_02.ogg"),
	],
	[preload("res://audio/sfx/sfx_critter_blep_01.ogg")],
	[preload("res://audio/sfx/sfx_critter_flatten_01.ogg")],
	[
		preload("res://audio/sfx/sfx_critter_confetti_01.ogg"),
		preload("res://audio/sfx/sfx_critter_confetti_02.ogg"),
	],
	[preload("res://audio/sfx/sfx_critter_zap_01.ogg")],
	[
		preload("res://audio/sfx/sfx_shard_clink_01.ogg"),
		preload("res://audio/sfx/sfx_shard_clink_03.ogg"),
	],
]

## Sonidos que han sonado (para los tests).
var played: int = 0

var _players: Array[AudioStreamPlayer3D] = []
var _random: Array[AudioStreamRandomizer] = []
var _last: PackedFloat64Array = []
var _next: int = 0


func _ready() -> void:
	for group: Array in STREAMS:
		var r := AudioStreamRandomizer.new()
		r.random_pitch = 1.08
		r.playback_mode = AudioStreamRandomizer.PLAYBACK_RANDOM_NO_REPEATS
		for s: AudioStream in group:
			r.add_stream(-1, s)
		_random.append(r)
		_last.append(-10.0)
	for i: int in PLAYERS:
		var p := AudioStreamPlayer3D.new()
		p.name = "Voice%d" % i
		p.bus = &"SFX"
		p.unit_size = 9.0
		p.max_distance = 90.0
		p.top_level = true
		add_child(p)
		_players.append(p)


## Suena `kind` en `at`. `pitch` multiplica la variación aleatoria.
func play(kind: Kind, at: Vector3, db: float = 0.0, pitch: float = 1.0) -> void:
	var now: float = Time.get_ticks_msec() / 1000.0
	if now - _last[kind] < MIN_GAP[kind]:
		return
	_last[kind] = now
	var p: AudioStreamPlayer3D = _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = _random[kind]
	p.global_position = at
	p.volume_db = db
	p.pitch_scale = clampf(pitch, 0.3, 3.0)
	p.play()
	played += 1
