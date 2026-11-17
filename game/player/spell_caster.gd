class_name SpellCaster
extends Node
## Lanza los hechizos de las dos manos (GDD 5.2 y 10.1). Cada mano lleva un elemento y su
## propio enfriamiento: clic izquierdo lanza la izquierda, clic derecho la derecha. Pulsar los
## dos a la vez junta las manos y funde los dos elementos en un hechizo combinado (Chispa +
## Chispa = Bola de Fuego), que se carga mientras se mantiene y sale al soltar.
##
## Para no perder la combinación, un clic con las dos manos listas espera `combine_window_sec`
## por si llega el otro; si se suelta antes, sale en el acto. Enfriamiento con "buffer" (si
## pulsas un poco antes de tiempo, sale en cuanto se pueda), golpe resonante y pools.

const ELEMENT: ElementDef = preload("res://data/elements/spark.tres")
const RECIPE: SpellRecipe = preload("res://data/spells/recipe_fireball.tres")
const CAST_SFX: Array[AudioStream] = [
	preload("res://audio/sfx/sfx_spark_cast_01.ogg"),
	preload("res://audio/sfx/sfx_spark_cast_02.ogg"),
	preload("res://audio/sfx/sfx_spark_cast_03.ogg"),
]
const READY_SFX: AudioStream = preload("res://audio/sfx/sfx_spark_ready_01.ogg")
const FIZZLE_SFX: AudioStream = preload("res://audio/sfx/sfx_spark_fizzle_01.ogg")
const PROJECTILE_POOL: int = 12
const COMBO_PROJECTILE_POOL: int = 3
const RAY_LENGTH: float = 250.0
const ACTIONS: Array[StringName] = [&"cast_left", &"cast_right"]
## Lado que usan las señales y las manos para el hechizo combinado.
const BOTH_HANDS: int = 2

@export var camera: Camera3D
@export var hands: WizardHands

var tier_index: int = 0
var _cooldown: PackedFloat32Array = PackedFloat32Array([0.0, 0.0])
## Duración del último enfriamiento de cada mano (para la carga de 0 a 1).
var _cooldown_total: PackedFloat32Array = PackedFloat32Array([1.0, 1.0])
var _was_ready: Array[bool] = [true, true]
var _buffered: Array[bool] = [false, false]
var _buffer_time: PackedFloat32Array = PackedFloat32Array([0.0, 0.0])
## Clic que espera por si llega el de la otra mano.
var _pending_side: int = -1
var _pending_time: float = 0.0
var _combining: bool = false
var _combine_time: float = 0.0
var _combine_full_announced: bool = false
var _projectiles: Array[SparkProjectile] = []
var _combo_projectiles: Array[SparkProjectile] = []
var _cast_random: AudioStreamRandomizer
var _combo_cast_random: AudioStreamRandomizer
var _charge_player: AudioStreamPlayer
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	for i: int in PROJECTILE_POOL:
		_projectiles.append(_make_projectile("Spark%d" % i))
	for i: int in COMBO_PROJECTILE_POOL:
		_combo_projectiles.append(_make_projectile("Combo%d" % i))
	_cast_random = _randomizer(CAST_SFX, 1.15)
	_combo_cast_random = _randomizer(RECIPE.cast_sfx, 1.08)
	_charge_player = AudioStreamPlayer.new()
	_charge_player.name = "ComboChargeLoop"
	_charge_player.bus = &"SFX"
	_charge_player.stream = RECIPE.charge_loop_sfx  # bucle activado en la importación
	add_child(_charge_player)


func current_tier() -> SpellTier:
	return ELEMENT.tiers[tier_index]


func current_recipe() -> SpellRecipe:
	return RECIPE


## Carga de una mano: 0 = recién lanzada, 1 = lista. Sin `side`, la media de las dos
## (o la carga del hechizo combinado mientras se junta).
func charge_ratio(side: int = -1) -> float:
	if side < 0:
		if _combining:
			return combine_charge()
		return (charge_ratio(0) + charge_ratio(1)) * 0.5
	return 1.0 - clampf(_cooldown[side] / maxf(_cooldown_total[side], 0.001), 0.0, 1.0)


func combine_charge() -> float:
	return clampf(_combine_time / maxf(RECIPE.charge_sec, 0.001), 0.0, 1.0)


func is_combining() -> bool:
	return _combining


## `celebrate`: al subir de nivel comprando, las manos lo celebran (destello y chispas).
func set_tier(index: int, celebrate: bool = false) -> void:
	var changed: bool = index != tier_index
	tier_index = clampi(index, 0, ELEMENT.tiers.size() - 1)
	if hands:
		hands.set_flame_visual(current_tier().visual, celebrate and changed)


func _unhandled_input(event: InputEvent) -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	for side: int in 2:
		if event.is_action_pressed(ACTIONS[side]):
			_on_press(side)
			return
		if event.is_action_released(ACTIONS[side]):
			_on_release(side)
			return
	if (
		OS.is_debug_build()
		and event is InputEventKey
		and event.is_pressed()
		and not event.is_echo()
	):
		var key: Key = (event as InputEventKey).physical_keycode
		if key >= KEY_1 and key <= KEY_5:
			set_tier(key - KEY_1, true)


## Lanza con una mano, sin esperar a la combinación (lo usa el modo demo).
func try_cast(side: int) -> void:
	_request_single(side)


## Junta las manos como si se pulsaran los dos botones (modo demo). Devuelve si empezó.
func try_begin_combine() -> bool:
	if _combining or not (_hand_ready(0) and _hand_ready(1)):
		return false
	_begin_combine()
	return true


## Suelta el hechizo combinado (modo demo).
func try_release_combine() -> void:
	if _combining:
		_launch_combine()


func _on_press(side: int) -> void:
	if _combining:
		return
	var other: int = 1 - side
	if _pending_side == other:
		# Llegó el segundo clic a tiempo: combinación.
		_pending_side = -1
		_begin_combine()
	elif _hand_ready(side) and _hand_ready(other):
		# Las dos manos listas: puede que el otro clic esté a punto de llegar.
		_pending_side = side
		_pending_time = GameState.BALANCE.combine_window_sec
	else:
		_request_single(side)


func _on_release(side: int) -> void:
	if _combining:
		_launch_combine()
	elif _pending_side == side:
		# Clic corto: no hay combinación, sale ya.
		_pending_side = -1
		_cast_single(side)


func _hand_ready(side: int) -> bool:
	return _cooldown[side] <= 0.0


func _request_single(side: int) -> void:
	if _combining:
		return
	if _hand_ready(side):
		_cast_single(side)
	elif _cooldown[side] <= GameState.BALANCE.cast_buffer_sec:
		_buffered[side] = true
		_buffer_time[side] = GameState.BALANCE.cast_buffer_sec


func _process(delta: float) -> void:
	for side: int in 2:
		if _cooldown[side] > 0.0:
			_cooldown[side] -= delta
		if _buffer_time[side] > 0.0:
			_buffer_time[side] -= delta
			if _buffered[side] and _hand_ready(side):
				_cast_single(side)
		else:
			_buffered[side] = false
	if _pending_side >= 0:
		_pending_time -= delta
		if _pending_time <= 0.0:
			var side: int = _pending_side
			_pending_side = -1
			_cast_single(side)
	if _combining:
		_update_combine(delta)
	for side: int in 2:
		var ready_now: bool = _hand_ready(side)
		if ready_now and not _was_ready[side] and not _combining:
			_on_hand_ready()
		_was_ready[side] = ready_now
	if hands:
		hands.charges[0] = charge_ratio(0)
		hands.charges[1] = charge_ratio(1)
		hands.combine_charge = combine_charge()


func _on_hand_ready() -> void:
	Events.spell_ready.emit()
	if hands:
		hands.play_ready()
	if _cooldown_for(current_tier()) >= 0.6:
		AudioDirector.play_sfx(READY_SFX, -8.0)


## Recarga con la Canalización aplicada.
func _cooldown_for(tier: SpellTier) -> float:
	return tier.cooldown_sec * GameState.stat(&"cooldown_mult", 1.0)


## Probabilidad de golpe resonante con la Resonancia aplicada.
func _resonant_chance() -> float:
	return GameState.stat(&"resonant_percent", GameState.BALANCE.resonant_chance * 100.0) / 100.0


func _cast_single(side: int) -> void:
	var tier: SpellTier = current_tier()
	_start_cooldown(side, _cooldown_for(tier))
	_buffered[side] = false
	_buffer_time[side] = 0.0
	var projectile: SparkProjectile = _free_projectile(_projectiles)
	if projectile == null:
		return
	var hit := SpellHit.new()
	hit.tier = tier
	hit.resonant = _rng.randf() < _resonant_chance()
	hit.damage = tier.damage * (GameState.BALANCE.resonant_damage_mult if hit.resonant else 1)
	hit.element = ELEMENT.id
	_launch(projectile, hit, side)
	if hands:
		hands.play_cast(side)
	# GDD 10: el crepitar suena más grave (y más fuerte) al subir de nivel.
	AudioDirector.play_sfx(_cast_random, -2.0 + tier_index * 0.8, 1.0 - tier_index * 0.07)
	Events.spell_cast.emit(tier, side)


func _begin_combine() -> void:
	_combining = true
	_combine_time = 0.0
	_combine_full_announced = false
	if hands:
		hands.begin_combine()
	AudioDirector.play_sfx(RECIPE.combine_sfx, -3.0)
	_charge_player.pitch_scale = 0.85
	_charge_player.volume_db = -18.0
	_charge_player.play()
	Events.spell_combine_started.emit(RECIPE)


func _update_combine(delta: float) -> void:
	_combine_time += delta
	var k: float = combine_charge()
	# El rugido del fuego sube de tono y de volumen con la carga.
	_charge_player.pitch_scale = lerpf(0.85, 1.25, k)
	_charge_player.volume_db = lerpf(-18.0, -6.0, k)
	# El mundo vibra un poco mientras se concentra el poder (pasa por Settings.screen_shake).
	if camera is CameraRig:
		(camera as CameraRig).add_trauma(delta * 0.35 * k)
	if k >= 1.0 and not _combine_full_announced:
		_combine_full_announced = true
		Events.spell_ready.emit()
		if hands:
			hands.play_ready()


func _launch_combine() -> void:
	var charge: float = combine_charge()
	_combining = false
	_charge_player.stop()
	var cd: float = maxf(
		RECIPE.cooldown_sec * GameState.stat(&"cooldown_mult", 1.0), _cooldown_for(current_tier())
	)
	_start_cooldown(0, cd)
	_start_cooldown(1, cd)
	if hands:
		hands.release_combine()
	var tier: SpellTier = RECIPE.tier
	var hit := SpellHit.new()
	hit.tier = tier
	hit.recipe = RECIPE
	hit.element = RECIPE.elements[0] if not RECIPE.elements.is_empty() else ELEMENT.id
	hit.resonant = _rng.randf() < _resonant_chance()
	var damage: int = RECIPE.damage_for(current_tier().damage, current_tier().damage, charge)
	hit.damage = damage * (GameState.BALANCE.resonant_damage_mult if hit.resonant else 1)
	var projectile: SparkProjectile = _free_projectile(_combo_projectiles)
	if projectile:
		# Misma carga que el orbe entre las manos (ver WizardHands): sale sin cambiar de tamaño.
		projectile.orb_charge = lerpf(0.15, 1.0, charge)
		_launch(projectile, hit, BOTH_HANDS)
	AudioDirector.play_sfx(_combo_cast_random, lerpf(-4.0, 0.0, charge))
	Events.spell_cast.emit(tier, BOTH_HANDS)
	GameState.register_recipe_cast(RECIPE)


func _start_cooldown(side: int, seconds: float) -> void:
	_cooldown[side] = seconds
	_cooldown_total[side] = maxf(seconds, 0.001)
	_was_ready[side] = false


## Apunta por el centro de la pantalla y lanza el proyectil desde la mano `side`.
func _launch(projectile: SparkProjectile, hit: SpellHit, side: int) -> void:
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
	var origin: Vector3 = camera.global_position + camera.global_basis * Vector3(0, -0.17, -0.6)
	if hands:
		origin = camera.project_position(hands.palm_screen_position(side), 0.85)
	projectile.launch(origin, target, hit, collider)


func _make_projectile(node_name: String) -> SparkProjectile:
	var p := SparkProjectile.new()
	p.name = node_name
	p.top_level = true
	p.arrived.connect(_on_projectile_arrived)
	add_child(p)
	return p


func _randomizer(streams: Array[AudioStream], pitch: float) -> AudioStreamRandomizer:
	var r := AudioStreamRandomizer.new()
	for s: AudioStream in streams:
		r.add_stream(-1, s)
	r.random_pitch = pitch
	r.random_volume_offset_db = 2.0
	return r


func _free_projectile(pool: Array[SparkProjectile]) -> SparkProjectile:
	for p: SparkProjectile in pool:
		if not p.active:
			return p
	return null


## Pantalla de carga: lanza un proyectil de cada nivel y la Bola de Fuego hacia `target` sin
## efecto de juego, para que el motor compile sus shaders y partículas antes de jugar.
func warm_up(target: Vector3) -> void:
	var from: Vector3 = camera.global_position + camera.global_basis * Vector3(0.0, -0.3, -1.5)
	var k: int = 0
	for tier: SpellTier in ELEMENT.tiers:
		var hit := SpellHit.new()
		hit.tier = tier
		hit.warmup = true
		hit.position = target
		hit.normal = Vector3.BACK
		_projectiles[k].launch(from, target, hit, null)
		k += 1
	var combo := SpellHit.new()
	combo.tier = RECIPE.tier
	combo.recipe = RECIPE
	combo.warmup = true
	combo.position = target
	combo.normal = Vector3.BACK
	_combo_projectiles[0].launch(from, target, combo, null)


func _on_projectile_arrived(projectile: SparkProjectile) -> void:
	if projectile.hit.warmup:
		return
	var collider: Object = projectile.target_collider
	if collider is Node and (collider as Node).has_meta(&"mother_crystal"):
		var crystal: MotherCrystal = (collider as Node).get_meta(&"mother_crystal")
		crystal.receive_hit(projectile.hit)
	else:
		AudioDirector.play_sfx(FIZZLE_SFX, -6.0)
		Events.spell_fizzled.emit(projectile.hit.position)
