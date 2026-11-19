class_name ManaVortex
extends Node3D
## El Vórtice (nodo hito de la Telequinesis, GDD 2.2 y 7: "atraer fragmentos -> envío directo al
## Pilón -> Vórtice"). Con `vortex` inscrito, un remolino de maná gira alrededor del mago: cada
## `vortex_interval_sec` atrapa el fragmento suelto más cercano dentro de `vortex_radius` (que ya
## haya caído y que no vaya a buscar un familiar) y lo sube en espiral hasta el mago
## (`ShardPool.vortex_pull`); al llegar va a la tolva por el envío directo, como lo que se recoge
## (`Player.gravity_collect`). Las Lágrimas del Núcleo no son fragmentos del pool: el Vórtice no
## las toca (se recogen a mano, como pide el GDD 6.1).
##
## Se ve y se oye: un disco de luz en espiral a los pies que gira más deprisa cuanto más aspira,
## motas que corren hacia el centro, los fragmentos brillando en su espiral, una luz cian y un
## viento que gira; cada fragmento que entra, un "fwip" con campanita que sube por la pentatónica.
## Lo crea el mago (Player) y va con él (top_level, sigue su posición).

const UPGRADE: StringName = &"vortex"
const STAT: StringName = &"vortex_radius"
const SHADER: Shader = preload("res://fx/hd/hd_vortex.gdshader")
const LOOP_SFX: AudioStream = preload("res://audio/sfx/amb_vortex_loop.ogg")
const AWAKEN_SFX: AudioStream = preload("res://audio/sfx/sfx_vortex_awaken_01.ogg")
const CATCH_SFX: Array[AudioStream] = [
	preload("res://audio/sfx/sfx_vortex_catch_01.ogg"),
	preload("res://audio/sfx/sfx_vortex_catch_02.ogg"),
	preload("res://audio/sfx/sfx_vortex_catch_03.ogg"),
]
## Pentatónica de La (semitonos) por la que suben los "fwip" seguidos.
const CATCH_LADDER: PackedInt32Array = [0, 2, 4, 7, 9, 12, 14, 16]
const CATCH_GAP_SEC: float = 0.07
## Diámetro del disco de luz a los pies (m) y su giro (rad/s) en reposo y aspirando.
const DISC_SIZE: float = 11.0
const SPIN_SPEED := Vector2(0.6, 4.2)
const LOOP_DB := Vector2(-40.0, -9.0)
const C_CYAN := Color(0.45, 0.85, 1.0)
const C_PINK := Color(1.0, 0.5, 0.95)

## Fragmentos que ha llevado el Vórtice (pruebas y demo).
var caught_total: int = 0

var _player: Node3D
var _shards: ShardPool
var _flock: FamiliarFlock
var _no_claims := PackedInt32Array()
var _timer: float = 0.0
var _recount: float = 0.0
var _in_flight: int = 0
## 0..1: cuánto aspira ahora (suaviza el disco, la luz y el viento).
var _activity: float = 0.0
var _spin: float = 0.0
var _awake_seen: bool = false
var _catch_at: float = -1.0
var _catch_step: int = 0
var _now: float = 0.0
var _disc: MeshInstance3D
var _disc_mat: ShaderMaterial
var _swirl: GPUParticles3D
var _light: OmniLight3D
var _loop: AudioStreamPlayer
var _catch_random: AudioStreamRandomizer
var _catch_player: AudioStreamPlayer


func _ready() -> void:
	top_level = true
	_player = get_parent() as Node3D
	_disc = HdFx.quad(SHADER, DISC_SIZE, 1)
	_disc.name = "Disc"
	_disc.rotation.x = -PI * 0.5
	_disc.position = Vector3.UP * 0.06
	_disc_mat = _disc.material_override
	add_child(_disc)
	_swirl = _make_swirl()
	add_child(_swirl)
	_light = OmniLight3D.new()
	_light.name = "Light"
	_light.light_color = Color(0.55, 0.85, 1.0)
	_light.omni_range = 9.0
	_light.shadow_enabled = false
	_light.position = Vector3.UP * 1.2
	add_child(_light)
	_loop = AudioStreamPlayer.new()
	_loop.name = "WindLoop"
	_loop.bus = &"SFX"
	_loop.stream = LOOP_SFX  # bucle activado en la importación
	_loop.volume_db = LOOP_DB.x
	add_child(_loop)
	_catch_random = AudioStreamRandomizer.new()
	for s: AudioStream in CATCH_SFX:
		_catch_random.add_stream(-1, s)
	_catch_random.random_pitch = 1.03
	_catch_player = AudioStreamPlayer.new()
	_catch_player.name = "Catch"
	_catch_player.bus = &"SFX"
	_catch_player.stream = _catch_random
	_catch_player.max_polyphony = 4
	_catch_player.volume_db = -9.0
	add_child(_catch_player)
	# Ya inscrito al cargar la partida: despierto sin ceremonia.
	_awake_seen = GameState.has_upgrade(UPGRADE)
	Events.upgrade_bought.connect(_on_upgrade_bought)
	_set_visible(false)


## True con el Vórtice inscrito.
func is_active() -> bool:
	return GameState.stat(STAT, 0.0) > 0.0


func _process(delta: float) -> void:
	_now += delta
	var radius: float = GameState.stat(STAT, 0.0)
	if radius <= 0.0 or _player == null:
		if _disc.visible:
			_set_visible(false)
		return
	if not _disc.visible:
		_set_visible(true)
	global_position = _player.global_position
	if _shards == null:
		_bind()
	if _shards:
		_catch_shards(radius, delta)
	_activity = move_toward(_activity, 1.0 if _in_flight > 0 else 0.0, delta * 2.2)
	_spin += delta * lerpf(SPIN_SPEED.x, SPIN_SPEED.y, _activity)
	_disc_mat.set_shader_parameter("spin", _spin)
	_disc_mat.set_shader_parameter("activity", _activity)
	_disc.scale = Vector3.ONE * lerpf(0.75, 1.0, _activity)
	_swirl.emitting = _activity > 0.05
	_swirl.amount_ratio = clampf(_activity, 0.05, 1.0)
	_light.light_energy = _activity * (1.4 + 0.3 * sin(_now * 9.0))
	_light.visible = _activity > 0.02
	_loop.volume_db = lerpf(LOOP_DB.x, LOOP_DB.y, sqrt(_activity))
	_loop.pitch_scale = lerpf(0.9, 1.12, _activity)
	if _activity > 0.01 and not _loop.playing:
		_loop.play()
	elif _activity <= 0.01 and _loop.playing:
		_loop.stop()


func _bind() -> void:
	_shards = get_tree().get_first_node_in_group(&"shard_pool") as ShardPool
	_flock = get_tree().get_first_node_in_group(&"familiar_flock") as FamiliarFlock
	if _shards == null:
		return
	_shards.vortex_target = _player
	if not _shards.vortexed.is_connected(_on_vortexed):
		_shards.vortexed.connect(_on_vortexed)


## Atrapa fragmentos sueltos a su ritmo, sin pasar del tope de los que giran a la vez.
func _catch_shards(radius: float, delta: float) -> void:
	var bal: BalanceConfig = GameState.BALANCE
	_recount -= delta
	if _recount <= 0.0:
		# Un fragmento reciclado por el pool a media espiral no avisa: se recuenta a veces.
		_recount = 0.5
		_in_flight = _shards.orbiting_count(1)
	_timer -= delta
	var claims: PackedInt32Array = _flock.claims if _flock else _no_claims
	while _timer <= 0.0 and _in_flight < bal.vortex_max_in_flight:
		_timer += bal.vortex_interval_sec
		var i: int = _shards.loose_near(global_position, radius, claims, bal.vortex_settle_sec)
		if i < 0:
			_timer = maxf(_timer, 0.0)
			return
		var d: float = _shards.position_of(i).distance_to(global_position)
		var k: float = clampf(d / radius, 0.0, 1.0)
		var sec: float = lerpf(bal.vortex_spiral_min_sec, bal.vortex_spiral_max_sec, sqrt(k))
		if _shards.vortex_pull(i, sec * randf_range(0.9, 1.1)):
			_in_flight += 1


## Un fragmento terminó la espiral: a la tolva (o a la bolsa) como lo que recoge el mago.
func _on_vortexed(index: int) -> void:
	_in_flight = maxi(0, _in_flight - 1)
	caught_total += 1
	if _player and _player.has_method(&"gravity_collect"):
		_player.call(&"gravity_collect", index)
	if _now - _catch_at < CATCH_GAP_SEC:
		return
	_catch_step = _catch_step + 1 if _now - _catch_at < 0.6 else 0
	_catch_at = _now
	var semis: int = CATCH_LADDER[_catch_step % CATCH_LADDER.size()]
	_catch_player.pitch_scale = pow(2.0, float(semis) / 12.0)
	_catch_player.play()


## Al inscribirlo: el remolino despierta con su ráfaga, el acorde y un aviso.
func _on_upgrade_bought(id: StringName, _level: int) -> void:
	if id != UPGRADE or _awake_seen:
		return
	_awake_seen = true
	AudioDirector.play_sfx(AWAKEN_SFX, -2.0)
	_activity = 1.0
	Events.hint.emit(tr("¡VÓRTICE! LOS FRAGMENTOS SUELTOS VUELAN SOLOS A LA TOLVA"), C_CYAN)


func _set_visible(on: bool) -> void:
	_disc.visible = on
	_swirl.emitting = on and _activity > 0.05
	_light.visible = on and _activity > 0.02
	if not on:
		_loop.stop()


## Motas que giran hacia el centro desde un anillo grande (un remolino de viento con luz).
func _make_swirl() -> GPUParticles3D:
	var cols := PackedColorArray(
		[Color(2.0, 2.4, 2.6), Color(0.6, 1.5, 2.2), Color(1.6, 0.6, 1.8), Color(0.4, 0.5, 1.4)]
	)
	var p: GPUParticles3D = HdFx.embers(180, 0.16, cols)
	p.name = "Swirl"
	p.lifetime = 1.6
	p.local_coords = true
	p.emitting = false
	var pm: ParticleProcessMaterial = p.process_material
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	pm.emission_ring_axis = Vector3.UP
	pm.emission_ring_height = 3.0
	pm.emission_ring_radius = 9.0
	pm.emission_ring_inner_radius = 6.0
	pm.gravity = Vector3(0, 0.6, 0)
	pm.initial_velocity_min = 0.0
	pm.initial_velocity_max = 0.4
	pm.radial_accel_min = -7.0
	pm.radial_accel_max = -4.0
	pm.tangential_accel_min = 9.0
	pm.tangential_accel_max = 15.0
	pm.damping_min = 0.0
	pm.damping_max = 0.3
	pm.turbulence_enabled = false
	p.position = Vector3.UP * 1.2
	return p
