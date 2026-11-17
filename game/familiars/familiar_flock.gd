class_name FamiliarFlock
extends Node3D
## Los familiares del mago (GDD 4.3, 7 y 8): la Jaula de Familiares junto al Pilón y un pool fijo
## de familiares (4 recolectores y 2 hechiceros) que se activan según las mejoras compradas
## (`familiar_count`, `familiar_caster`). Como salen de la progresión, al cargar la partida
## vuelven solos. Reparte el trabajo (qué fragmento va a buscar cada uno, quién tira de la
## palanca) y pone las voces sin saturar: cada sonido tiene su hueco mínimo.

enum Voice { HOOT, CHIRP, FLAP, GRAB, CAST, SUMMON }

const DEFS: Array[FamiliarDef] = [
	preload("res://data/familiars/collector.tres"),
	preload("res://data/familiars/caster.tres"),
]
const TOON_SHADER: Shader = preload("res://fx/toon.gdshader")
const SHARD_SHADER: Shader = preload("res://crystal/shard.gdshader")
const HOOT_SFX: Array[AudioStream] = [
	preload("res://audio/sfx/sfx_familiar_hoot_01.ogg"),
	preload("res://audio/sfx/sfx_familiar_hoot_02.ogg"),
]
const CHIRP_SFX: Array[AudioStream] = [
	preload("res://audio/sfx/sfx_familiar_chirp_01.ogg"),
	preload("res://audio/sfx/sfx_familiar_chirp_02.ogg"),
	preload("res://audio/sfx/sfx_familiar_chirp_03.ogg"),
]
const FLAP_SFX: Array[AudioStream] = [
	preload("res://audio/sfx/sfx_familiar_flap_01.ogg"),
	preload("res://audio/sfx/sfx_familiar_flap_02.ogg"),
]
const GRAB_SFX: Array[AudioStream] = [preload("res://audio/sfx/sfx_familiar_grab_01.ogg")]
const CAST_SFX: Array[AudioStream] = [
	preload("res://audio/sfx/sfx_familiar_cast_01.ogg"),
	preload("res://audio/sfx/sfx_familiar_cast_02.ogg"),
]
const SUMMON_SFX: AudioStream = preload("res://audio/sfx/sfx_familiar_summon_01.ogg")
## Hueco mínimo entre dos sonidos de cada tipo (s) y su volumen.
const VOICE_GAP: PackedFloat32Array = [7.0, 0.9, 0.45, 0.15, 0.25, 0.0]
const VOICE_DB: PackedFloat32Array = [-4.0, -8.0, -10.0, -9.0, -6.0, 0.0]
const VOICE_PLAYERS: int = 5
const C_HINT := Color("#c9b8ff")

var crusher: CrystalCrusher
var shards: ShardPool
var crystal: MotherCrystal
var nest: FamiliarNest
## Fragmento que va a buscar cada familiar (índice en ShardPool, -1 = ninguno).
var claims: PackedInt32Array = PackedInt32Array()
var toon: ShaderMaterial
var shard_material: ShaderMaterial
## Contadores (tests y depuración).
var dropped: int = 0
var pulls: int = 0

var _familiars: Array[Familiar] = []
var _lever_by: Familiar
var _player: Node3D
var _voices: Array[AudioStreamPlayer3D] = []
var _voice_next: int = 0
var _voice_streams: Array[AudioStream] = []
var _voice_last: PackedFloat32Array = PackedFloat32Array()
var _shard_meshes: Dictionary[ShardType, ArrayMesh] = {}
var _now: float = 0.0
var _idle_t: float = 8.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	add_to_group(&"familiar_flock")
	_rng.seed = 91
	crusher = get_tree().get_first_node_in_group(&"crystal_crusher") as CrystalCrusher
	shards = get_tree().get_first_node_in_group(&"shard_pool") as ShardPool
	crystal = get_tree().get_first_node_in_group(&"mother_crystal") as MotherCrystal
	toon = ShaderMaterial.new()
	toon.shader = TOON_SHADER
	toon.set_shader_parameter("rim", 0.55)
	shard_material = ShaderMaterial.new()
	shard_material.shader = SHARD_SHADER
	for type: ShardType in ShardPool.TYPES:
		_shard_meshes[type] = CrystalClusterBuilder.build_shard_mesh(
			type, 90 + _shard_meshes.size()
		)
	nest = FamiliarNest.new()
	nest.name = "FamiliarNest"
	add_child(nest)
	var at: Vector3 = WorldLayout.FAMILIAR_NEST
	nest.global_position = Vector3(at.x, Valley.ground_height(at.x, at.z) - 0.05, at.z)
	# El lado abierto de las perchas mira al camino.
	var to_path: Vector3 = WorldLayout.PYLON + Vector3(5.6, 0.0, 0.0) - at
	nest.rotation.y = atan2(to_path.x, to_path.z)
	for d: FamiliarDef in DEFS:
		for k: int in d.max_count:
			var f := Familiar.new()
			f.name = "%s%d" % [String(d.id).capitalize(), k]
			add_child(f)
			f.setup(d, self, k)
			_familiars.append(f)
			claims.append(-1)
	_build_audio()
	# Al final del fotograma: la escena ya ha colocado al mago (los hechiceros vuelan hacia él).
	_sync.call_deferred(false)
	Events.upgrade_bought.connect(_on_upgrade_bought)


## Familiares en juego de un tipo (o de todos con `role` = -1).
func active_count(role: int = -1) -> int:
	var n: int = 0
	for f: Familiar in _familiars:
		if f.is_active() and (role < 0 or int(f.def.role) == role):
			n += 1
	return n


func familiars() -> Array[Familiar]:
	return _familiars


func claim_index(f: Familiar) -> int:
	return _familiars.find(f)


func shard_mesh(type: ShardType) -> ArrayMesh:
	return _shard_meshes[type]


## Dónde se pone cada familiar sobre la tolva (en corro, para no pisarse).
func hopper_spot(slot: int) -> Vector3:
	var a: float = TAU * float(slot) / 4.0 + 0.6
	return crusher.hopper_mouth() + Vector3(cos(a) * 0.7, 1.2 + 0.15 * float(slot), sin(a) * 0.7)


## Un familiar quiere tirar de la palanca: sólo uno a la vez, con la máquina parada y bastantes
## cristales en la tolva.
func wants_lever(f: Familiar) -> bool:
	if crusher == null or crusher.is_busy():
		return false
	if _lever_by != null and _lever_by != f:
		return false
	if crusher.queued_count() < f.def.lever_at:
		return false
	_lever_by = f
	return true


func release_lever(f: Familiar) -> void:
	if _lever_by == f:
		_lever_by = null


func player_position() -> Vector3:
	if _player == null:
		_player = get_tree().get_first_node_in_group(&"player") as Node3D
	return _player.global_position if _player else WorldLayout.PLAYER_START


## Sonido 3D de un familiar en `at`, si su tipo no ha sonado hace nada.
func voice(kind: Voice, at: Vector3) -> void:
	var k: int = int(kind)
	if _now - _voice_last[k] < VOICE_GAP[k]:
		return
	_voice_last[k] = _now
	var p: AudioStreamPlayer3D = _voices[_voice_next]
	_voice_next = (_voice_next + 1) % _voices.size()
	p.stream = _voice_streams[k]
	p.volume_db = VOICE_DB[k]
	p.unit_size = 3.0 if kind == Voice.FLAP else 7.0
	p.global_position = at
	p.play()


## Pantalla de carga: enseña la jaula y un familiar en `at` para compilar sus materiales.
func warm_up(at: Vector3) -> void:
	if active_count() > 0:
		return
	var was: bool = nest.visible
	nest.visible = true
	nest.warm_up()
	_familiars[0].warm_up(at)
	_familiars[_familiars.size() - 1].warm_up(at + Vector3.RIGHT)
	await get_tree().create_timer(0.4).timeout
	nest.visible = was or active_count() > 0


func _process(delta: float) -> void:
	_now += delta
	# De vez en cuando, un "hu-hu" de alguno que descansa en la jaula.
	_idle_t -= delta
	if _idle_t <= 0.0:
		_idle_t = _rng.randf_range(9.0, 16.0)
		for f: Familiar in _familiars:
			if f.state == Familiar.State.PERCHED:
				voice(Voice.HOOT, f.global_position)
				break


func _on_upgrade_bought(id: StringName, _level: int) -> void:
	_sync(id == &"familiar" or id == &"familiar_caster")


## Activa (o retira) familiares hasta lo que dicen las mejoras. `announce`: recién comprado.
func _sync(announce: bool) -> void:
	var had: int = active_count()
	var arrived: Array[Familiar] = []
	for f: Familiar in _familiars:
		var want: int = clampi(roundi(GameState.stat(f.def.count_stat, 0.0)), 0, f.def.max_count)
		if f.slot < want and not f.is_active():
			arrived.append(f)
		elif f.slot >= want and f.is_active():
			f.hide_now()
	if arrived.is_empty():
		if active_count() == 0:
			nest.visible = false
		return
	if had == 0 and announce:
		nest.pop_in()
	elif not nest.visible:
		nest.show_now()
	for f: Familiar in arrived:
		f.activate(nest.top() + Vector3.UP * 0.4, announce)
	set_process(true)
	if not announce:
		return
	nest.celebrate()
	AudioDirector.play_sfx(SUMMON_SFX, -3.0)
	var first: Familiar = arrived[0]
	if first.def.role == FamiliarDef.Role.CASTER:
		Events.hint.emit(tr("¡FAMILIAR HECHICERO! LANZA CHISPAS AL CRISTAL"), C_HINT)
	elif had == 0:
		Events.hint.emit(tr("¡TU PRIMER FAMILIAR! VIVE JUNTO AL PILÓN"), C_HINT)
		Events.hint.emit(tr("RECOGE FRAGMENTOS Y LOS ECHA A LA TOLVA"), C_HINT)
	else:
		Events.hint.emit(tr("¡OTRO FAMILIAR! YA SON %d") % active_count(0), C_HINT)


func _build_audio() -> void:
	var sets: Array[Array] = [HOOT_SFX, CHIRP_SFX, FLAP_SFX, GRAB_SFX, CAST_SFX, [SUMMON_SFX]]
	for streams: Array in sets:
		var r := AudioStreamRandomizer.new()
		for s: AudioStream in streams:
			r.add_stream(-1, s)
		r.random_pitch = 1.1
		r.random_volume_offset_db = 2.0
		_voice_streams.append(r)
		_voice_last.append(-100.0)
	for i: int in VOICE_PLAYERS:
		var p := AudioStreamPlayer3D.new()
		p.name = "Voice%d" % i
		p.bus = &"SFX"
		p.max_distance = 70.0
		add_child(p)
		_voices.append(p)
