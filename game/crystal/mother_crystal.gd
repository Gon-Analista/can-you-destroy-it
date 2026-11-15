class_name MotherCrystal
extends Node3D
## El Cristal Madre. Recibe impactos y reacciona: destello y onda en la faceta, grieta que se
## queda, temblor, pulso del corazón violeta, fragmentos que saltan, partículas, luz y sonido
## ("tink") que sube de tono con la racha. Ver GDD 10.3.

const CRYSTAL_SHADER: Shader = preload("res://crystal/crystal.gdshader")
const MAX_HITS: int = 6
const MAX_CRACKS: int = 16
## Escala pentatónica (semitonos) que recorre el "tink" a medida que crece la racha.
const STREAK_LADDER: PackedInt32Array = [-5, -3, 0, 2, 4, 7, 9, 12, 14, 16]
const TINKS: Array[AudioStream] = [
	preload("res://audio/sfx/sfx_crystal_tink_01.ogg"),
	preload("res://audio/sfx/sfx_crystal_tink_02.ogg"),
	preload("res://audio/sfx/sfx_crystal_tink_03.ogg"),
	preload("res://audio/sfx/sfx_crystal_tink_04.ogg"),
]
const BREAKS: Array[AudioStream] = [
	preload("res://audio/sfx/sfx_shard_break_01.ogg"),
	preload("res://audio/sfx/sfx_shard_break_02.ogg"),
	preload("res://audio/sfx/sfx_shard_break_03.ogg"),
]
const RESONANT_SFX: AudioStream = preload("res://audio/sfx/sfx_resonant_hit_01.ogg")
const STREAK_SFX: AudioStream = preload("res://audio/sfx/sfx_streak_chime_01.ogg")
const HUM_SFX: AudioStream = preload("res://audio/sfx/amb_crystal_hum_loop.ogg")

@export var crystal_scale: float = 1.35
@export var seed_value: int = 11

var _material: ShaderMaterial
var _mesh_instance: MeshInstance3D
var _shards: ShardPool
var _fx: ImpactFx
var _streak: StreakTracker
var _hits: PackedVector4Array = []
var _hit_resonant: PackedFloat32Array = []
var _cracks: PackedVector4Array = []
var _hit_index: int = 0
var _crack_index: int = 0
var _now: float = 0.0
var _shudder: float = 0.0
var _core_pulse: float = 0.0
var _global_flash: float = 0.0
var _tink_players: Array[AudioStreamPlayer3D] = []
var _tink_next: int = 0
var _tink_random: AudioStreamRandomizer
var _break_player: AudioStreamPlayer3D
var _accent_player: AudioStreamPlayer
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_streak = StreakTracker.new(GameState.BALANCE.streak_window_sec)
	var builder := CrystalClusterBuilder.new()
	builder.build(crystal_scale, seed_value)
	_material = ShaderMaterial.new()
	_material.shader = CRYSTAL_SHADER
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "Mesh"
	_mesh_instance.mesh = builder.mesh
	_mesh_instance.material_override = _material
	add_child(_mesh_instance)
	var body := StaticBody3D.new()
	body.name = "Body"
	body.collision_layer = 1 << 1
	body.collision_mask = 0
	body.set_meta(&"mother_crystal", self)
	for hull: PackedVector3Array in builder.hulls:
		var shape := ConvexPolygonShape3D.new()
		shape.points = hull
		var col := CollisionShape3D.new()
		col.shape = shape
		body.add_child(col)
	add_child(body)
	_shards = ShardPool.new()
	_shards.name = "Shards"
	add_child(_shards)
	_fx = ImpactFx.new()
	_fx.name = "ImpactFx"
	add_child(_fx)
	_setup_audio()
	for i: int in MAX_HITS:
		_hits.append(Vector4(0, 0, 0, -1))
		_hit_resonant.append(0.0)
	for i: int in MAX_CRACKS:
		_cracks.append(Vector4.ZERO)
	_material.set_shader_parameter("hits", _hits)
	_material.set_shader_parameter("hit_resonant", _hit_resonant)
	_material.set_shader_parameter("cracks", _cracks)
	_material.set_shader_parameter("core_top", 4.5 * crystal_scale)
	_material.set_shader_parameter("core_bottom", -0.5)


func _setup_audio() -> void:
	_tink_random = AudioStreamRandomizer.new()
	for s: AudioStream in TINKS:
		_tink_random.add_stream(-1, s)
	_tink_random.random_pitch = 1.0
	_tink_random.random_volume_offset_db = 1.5
	for i: int in 6:
		var p := AudioStreamPlayer3D.new()
		p.bus = &"SFX"
		p.stream = _tink_random
		p.unit_size = 30.0
		p.max_polyphony = 1
		add_child(p)
		_tink_players.append(p)
	var breaks := AudioStreamRandomizer.new()
	for s: AudioStream in BREAKS:
		breaks.add_stream(-1, s)
	breaks.random_pitch = 1.1
	_break_player = AudioStreamPlayer3D.new()
	_break_player.bus = &"SFX"
	_break_player.stream = breaks
	_break_player.unit_size = 30.0
	_break_player.volume_db = -4.0
	_break_player.max_polyphony = 3
	add_child(_break_player)
	_accent_player = AudioStreamPlayer.new()
	_accent_player.bus = &"SFX"
	_accent_player.max_polyphony = 2
	add_child(_accent_player)
	var hum := AudioStreamPlayer3D.new()
	hum.name = "Hum"
	hum.bus = &"Ambience"
	hum.stream = HUM_SFX  # bucle activado en la importación
	hum.unit_size = 14.0
	hum.volume_db = -6.0
	hum.position = Vector3(0, 4, 0)
	hum.autoplay = true
	add_child(hum)


## Punto de entrada de los hechizos: aplica el daño y dispara toda la reacción.
func receive_hit(hit: SpellHit) -> void:
	var balance: BalanceConfig = GameState.BALANCE
	hit.streak = _streak.register_hit(_now)
	GameState.hit_crystal(hit.damage, hit.position)
	var tier: SpellTier = hit.tier

	_hits[_hit_index] = Vector4(hit.position.x, hit.position.y, hit.position.z, _now)
	_hit_resonant[_hit_index] = 1.0 if hit.resonant else 0.0
	_hit_index = (_hit_index + 1) % MAX_HITS
	_cracks[_crack_index] = Vector4(
		hit.position.x,
		hit.position.y,
		hit.position.z,
		tier.crack_radius * (1.6 if hit.resonant else 1.0) * _rng.randf_range(0.85, 1.15)
	)
	_crack_index = (_crack_index + 1) % MAX_CRACKS
	_material.set_shader_parameter("hits", _hits)
	_material.set_shader_parameter("hit_resonant", _hit_resonant)
	_material.set_shader_parameter("cracks", _cracks)

	_shudder = minf(1.0, _shudder + 0.35 + tier.shake * 2.0 + (0.5 if hit.resonant else 0.0))
	_core_pulse = 1.0
	if hit.resonant:
		_global_flash = 0.55
	var count: int = _rng.randi_range(tier.shards_min, tier.shards_max) * (2 if hit.resonant else 1)
	_shards.spawn(hit.position, hit.normal, count, tier.shard_scale, 1.25 if hit.resonant else 1.0)
	_fx.play(hit.position, hit.normal, tier, hit.resonant)
	_play_tink(hit)
	if hit.resonant:
		HitStop.trigger(get_tree(), 0.09)
		_accent_player.stream = RESONANT_SFX
		_accent_player.volume_db = -3.0
		_accent_player.play()
	elif tier.damage >= 5:
		HitStop.trigger(get_tree(), 0.025)
	if balance.streak_milestones.has(hit.streak):
		_accent_player.stream = STREAK_SFX
		_accent_player.volume_db = -5.0
		_accent_player.play()
		Events.streak_milestone.emit(hit.streak)
	Events.streak_changed.emit(hit.streak)
	Events.spell_impacted.emit(hit)
	set_process(true)


func _play_tink(hit: SpellHit) -> void:
	var step: int = STREAK_LADDER[mini(hit.streak - 1, STREAK_LADDER.size() - 1)]
	var p: AudioStreamPlayer3D = _tink_players[_tink_next]
	_tink_next = (_tink_next + 1) % _tink_players.size()
	p.global_position = hit.position
	p.pitch_scale = pow(2.0, float(step) / 12.0) * _rng.randf_range(0.99, 1.01)
	p.volume_db = -1.0 if hit.resonant else -4.0
	p.play()
	_break_player.global_position = hit.position
	_break_player.play()


func _process(delta: float) -> void:
	_now += delta
	_material.set_shader_parameter("now", _now)
	if _streak.expire(_now):
		Events.streak_broken.emit(_streak.streak)
		Events.streak_changed.emit(0)
	# Temblor: el cristal es enorme, así que se mueve muy poco (centímetros) y muy rápido.
	if _shudder > 0.0:
		_shudder = maxf(0.0, _shudder - delta * 4.0)
		var a: float = _shudder * _shudder * 0.09
		_mesh_instance.position = Vector3(
			_rng.randf_range(-a, a), _rng.randf_range(-a, a) * 0.5, _rng.randf_range(-a, a)
		)
	else:
		_mesh_instance.position = Vector3.ZERO
	_core_pulse = maxf(0.0, _core_pulse - delta * 2.5)
	_material.set_shader_parameter("core_pulse", 0.5 + 0.5 * sin(_now * 1.4) + _core_pulse * 2.0)
	_global_flash = maxf(0.0, _global_flash - delta * 5.0)
	_material.set_shader_parameter("global_flash", _global_flash)
