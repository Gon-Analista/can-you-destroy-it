class_name SpellCaster
extends Node
## Lanza la chispa desde la mano que corresponde al botón. Enfriamiento con "buffer"
## (si pulsas un poco antes de tiempo, sale en cuanto se pueda), tirada de golpe resonante
## y pool de proyectiles.

const ELEMENT: ElementDef = preload("res://data/elements/spark.tres")
const CAST_SFX: Array[AudioStream] = [
	preload("res://audio/sfx/sfx_spark_cast_01.ogg"),
	preload("res://audio/sfx/sfx_spark_cast_02.ogg"),
	preload("res://audio/sfx/sfx_spark_cast_03.ogg"),
]
const READY_SFX: AudioStream = preload("res://audio/sfx/sfx_spark_ready_01.ogg")
const FIZZLE_SFX: AudioStream = preload("res://audio/sfx/sfx_spark_fizzle_01.ogg")
const PROJECTILE_POOL: int = 12
const RAY_LENGTH: float = 250.0

@export var camera: Camera3D
@export var hands: WizardHands

var tier_index: int = 0
var _cooldown: float = 0.0
var _buffered_side: int = -1
var _buffer_time: float = 0.0
var _was_ready: bool = true
var _projectiles: Array[SparkProjectile] = []
var _cast_random: AudioStreamRandomizer
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	for i: int in PROJECTILE_POOL:
		var p := SparkProjectile.new()
		p.name = "Spark%d" % i
		p.top_level = true
		p.arrived.connect(_on_projectile_arrived)
		add_child(p)
		_projectiles.append(p)
	_cast_random = AudioStreamRandomizer.new()
	for s: AudioStream in CAST_SFX:
		_cast_random.add_stream(-1, s)
	_cast_random.random_pitch = 1.15
	_cast_random.random_volume_offset_db = 2.0
	_apply_tier()


func current_tier() -> SpellTier:
	return ELEMENT.tiers[tier_index]


## 0 = recién lanzado, 1 = listo.
func charge_ratio() -> float:
	var cd: float = current_tier().cooldown_sec
	return 1.0 - clampf(_cooldown / cd, 0.0, 1.0)


func set_tier(index: int) -> void:
	tier_index = clampi(index, 0, ELEMENT.tiers.size() - 1)
	_apply_tier()


func _apply_tier() -> void:
	var tier: SpellTier = current_tier()
	if hands:
		hands.set_orb_colors(tier.color_core, tier.color_glow)


func _unhandled_input(event: InputEvent) -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event.is_action_pressed(&"cast_left"):
		_request_cast(0)
	elif event.is_action_pressed(&"cast_right"):
		_request_cast(1)
	elif (
		OS.is_debug_build()
		and event is InputEventKey
		and event.is_pressed()
		and not event.is_echo()
	):
		var key: Key = (event as InputEventKey).physical_keycode
		if key >= KEY_1 and key <= KEY_5:
			set_tier(key - KEY_1)


## Lanza como si se pulsara el botón de la mano `side` (lo usa el modo demo).
func try_cast(side: int) -> void:
	_request_cast(side)


func _request_cast(side: int) -> void:
	if _cooldown <= 0.0:
		_cast(side)
	elif _cooldown <= GameState.BALANCE.cast_buffer_sec:
		_buffered_side = side
		_buffer_time = GameState.BALANCE.cast_buffer_sec


func _process(delta: float) -> void:
	if _cooldown > 0.0:
		_cooldown -= delta
	if _buffer_time > 0.0:
		_buffer_time -= delta
		if _cooldown <= 0.0 and _buffered_side >= 0:
			_cast(_buffered_side)
	var ready_now: bool = _cooldown <= 0.0
	if ready_now and not _was_ready:
		Events.spell_ready.emit()
		if hands:
			hands.play_ready()
		if current_tier().cooldown_sec >= 0.6:
			AudioDirector.play_sfx(READY_SFX, -8.0)
	_was_ready = ready_now
	if hands:
		hands.charge_ratio = charge_ratio()


func _cast(side: int) -> void:
	var tier: SpellTier = current_tier()
	_cooldown = tier.cooldown_sec
	_buffered_side = -1
	_buffer_time = 0.0
	_was_ready = false
	var projectile: SparkProjectile = _free_projectile()
	if projectile == null:
		return
	var hit := SpellHit.new()
	hit.tier = tier
	hit.resonant = _rng.randf() < GameState.BALANCE.resonant_chance
	hit.damage = tier.damage * (GameState.BALANCE.resonant_damage_mult if hit.resonant else 1)
	var from_cam: Vector3 = camera.global_position
	var forward: Vector3 = -camera.global_basis.z
	var query := PhysicsRayQueryParameters3D.create(
		from_cam, from_cam + forward * RAY_LENGTH, 1 | (1 << 1)
	)
	var result: Dictionary = camera.get_world_3d().direct_space_state.intersect_ray(query)
	var target: Vector3 = from_cam + forward * 40.0
	var collider: Object = null
	if not result.is_empty():
		target = result["position"]
		hit.normal = result["normal"]
		collider = result["collider"]
	hit.position = target
	# La chispa sale de la palma que se ve en pantalla.
	var origin: Vector3 = (
		camera.global_position
		+ camera.global_basis * Vector3(0.28 if side == 1 else -0.28, -0.17, -0.6)
	)
	if hands:
		origin = camera.project_position(hands.palm_screen_position(side) + Vector2(0, -26), 0.7)
	projectile.launch(origin, target, hit, collider)
	if hands:
		hands.play_cast(side)
	AudioDirector.play_sfx(_cast_random, -2.0)
	Events.spell_cast.emit(tier, side)


func _free_projectile() -> SparkProjectile:
	for p: SparkProjectile in _projectiles:
		if not p.active:
			return p
	return null


func _on_projectile_arrived(projectile: SparkProjectile) -> void:
	var collider: Object = projectile.target_collider
	if collider is Node and (collider as Node).has_meta(&"mother_crystal"):
		var crystal: MotherCrystal = (collider as Node).get_meta(&"mother_crystal")
		crystal.receive_hit(projectile.hit)
	else:
		AudioDirector.play_sfx(FIZZLE_SFX, -6.0)
		Events.spell_fizzled.emit(projectile.hit.position)
