class_name Player
extends CharacterBody3D
## Mago en primera persona: mirar con el ratón, caminar con WASD. Monta cámara, manos 2D,
## lanzador de hechizos y el post-proceso de contorno.

const OUTLINE_SHADER: Shader = preload("res://fx/outline.gdshader")
const TELEKINESIS_SFX: AudioStream = preload("res://audio/sfx/sfx_telekinesis_01.ogg")
const STEP_SFX: Array[AudioStream] = [
	preload("res://audio/sfx/sfx_step_grass_01.ogg"),
	preload("res://audio/sfx/sfx_step_grass_02.ogg"),
	preload("res://audio/sfx/sfx_step_grass_03.ogg"),
	preload("res://audio/sfx/sfx_step_grass_04.ogg"),
]
const JUMP_SFX: AudioStream = preload("res://audio/sfx/sfx_jump_01.ogg")
const LAND_SFX: AudioStream = preload("res://audio/sfx/sfx_land_01.ogg")
const DOUBLE_JUMP_SFX: AudioStream = preload("res://audio/sfx/sfx_double_jump_01.ogg")
const LEVITATE_SFX: AudioStream = preload("res://audio/sfx/amb_levitate_loop.ogg")
const LEVITATE_EMPTY_SFX: AudioStream = preload("res://audio/sfx/sfx_levitate_empty_01.ogg")

@export var walk_speed: float = 4.5
@export var sprint_speed: float = 8.0
@export var jump_velocity: float = 5.4
## Margen para saltar justo después de dejar el suelo y para un salto pulsado antes de tocarlo.
@export var coyote_sec: float = 0.12
## Mejoras de movimiento (Grimorio, constelación del Mago). En este juego no hay daño por caída.
@export var double_jump_velocity: float = 6.2
## Velocidad de subida que busca la levitación y lo rápido que la alcanza.
@export var levitate_speed: float = 4.0
@export var levitate_accel: float = 20.0
## Segundos de suelo para recargar la levitación entera.
@export var levitate_recharge_sec: float = 1.1
@export var jump_buffer_sec: float = 0.12
## Distancia entre pasos (m) andando; corriendo los pasos se alargan.
@export var step_length: float = 1.7
@export var acceleration: float = 30.0
@export var mouse_sensitivity: float = 0.0022
@export var start_pitch_deg: float = 20.0
## Distancia máxima para recoger un fragmento apuntándolo.
@export var pickup_range: float = 4.5
## Si no apuntas a ninguno, se recoge el más cercano a este radio delante de ti.
@export var pickup_assist_radius: float = 1.6
## Mantener F recoge en cadena con este intervalo.
@export var pickup_repeat_sec: float = 0.12
## Cada cuánto la telequinesis atrae un fragmento cercano (s).
@export var telekinesis_interval_sec: float = 0.14

## Levitación (mejora): segundos de vuelo que caben y los que quedan.
var levitation_max: float = 0.0
var levitation_fuel: float = 0.0
var levitating: bool = false
## Destello de la barra al recargar con el Impulso del cristal (1 -> 0).
var refill_flash: float = 0.0

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _shards: ShardPool
var _target_shard: int = -1
var _pickup_cooldown: float = 0.0
var _grab_point: Marker3D
## Con el Grimorio abierto el mago no se mueve ni mira.
var _locked: bool = false
var _telekinesis_timer: float = 0.0
var _coyote: float = 0.0
var _jump_buffer: float = 0.0
var _was_on_floor: bool = true
var _fall_speed: float = 0.0
var _step_dist: float = 0.0
var _bob_phase: float = 0.0
var _steps: AudioStreamRandomizer
var _has_double_jump: bool = false
var _air_jumps: int = 0
var _double_jumped: bool = false
## Flanco de Espacio a mano: `is_action_just_pressed` se pierde a veces entre fotogramas de física.
var _jump_was_held: bool = false
var _jump_tap: bool = false
var _jet: GPUParticles3D
var _jump_burst: GPUParticles3D
var _jet_audio: AudioStreamPlayer

@onready var _head: Node3D = $Head
@onready var _camera: CameraRig = $Head/Camera
@onready var _hands: WizardHands = $Hands
@onready var _caster: SpellCaster = $SpellCaster


func _ready() -> void:
	add_to_group(&"player")
	_steps = AudioStreamRandomizer.new()
	for st: AudioStream in STEP_SFX:
		_steps.add_stream(-1, st)
	_steps.random_pitch = 1.12
	_steps.random_volume_offset_db = 2.0
	Events.grimoire_opened.connect(func() -> void: _locked = true)
	Events.grimoire_closed.connect(func() -> void: _locked = false)
	Events.menu_opened.connect(func() -> void: _locked = true)
	Events.menu_closed.connect(func() -> void: _locked = false)
	Events.upgrade_bought.connect(func(_id: StringName, _l: int) -> void: _apply_upgrades(true))
	_head.rotation.x = deg_to_rad(start_pitch_deg)
	_caster.camera = _camera
	_hands.attach_camera(_camera, SpellCaster.ELEMENT.hand_visual, SpellCaster.RECIPE.visual)
	_caster.hands = _hands
	_add_outline()
	_build_jet()
	Events.spell_impacted.connect(_on_spell_impacted)
	_grab_point = Marker3D.new()
	_grab_point.position = Vector3(-0.18, -0.32, -0.55)
	_camera.add_child(_grab_point)
	_shards = get_tree().get_first_node_in_group(&"shard_pool") as ShardPool
	_apply_upgrades()


## Las mejoras que tocan los hechizos: el nivel de la Chispa sale de la Potencia.
func _apply_upgrades(celebrate: bool = false) -> void:
	_caster.set_tier(roundi(GameState.stat(&"spark_tier", 0.0)), celebrate)
	_has_double_jump = GameState.stat(&"double_jump", 0.0) > 0.5
	var lev: float = GameState.stat(&"levitation_sec", 0.0)
	if lev > levitation_max:
		levitation_fuel = lev
	levitation_max = lev


## Impulso del cristal (mejora): cada golpe que llega al cristal estando en el aire devuelve
## carga de levitación. Así se sube hasta la punta golpeando.
func _on_spell_impacted(_hit: SpellHit) -> void:
	if is_on_floor() or levitation_max <= 0.0:
		return
	var refill: float = GameState.stat(&"levitation_refill", 0.0)
	if refill > 0.0:
		levitation_fuel = minf(levitation_max, levitation_fuel + refill)
		refill_flash = 1.0


## Carga de levitación (0..1) para el HUD.
func fuel_ratio() -> float:
	return levitation_fuel / levitation_max if levitation_max > 0.0 else 0.0


## Chorro de magia bajo los pies al levitar y estallido del doble salto (capa de magia HD).
func _build_jet() -> void:
	var cols := PackedColorArray([Color(1.4, 1.9, 2.2), Color(0.9, 0.5, 1.8), Color(0.5, 0.3, 1.2)])
	_jet = HdFx.embers(70, 0.12, cols)
	_jet.name = "Jet"
	_jet.lifetime = 0.55
	var pm: ParticleProcessMaterial = _jet.process_material
	pm.direction = Vector3.DOWN
	pm.spread = 22.0
	pm.initial_velocity_min = 3.0
	pm.initial_velocity_max = 5.5
	pm.gravity = Vector3(0, -2.0, 0)
	pm.emission_sphere_radius = 0.22
	_jet.emitting = false
	_jet.position = Vector3(0, 0.05, 0)
	add_child(_jet)
	_jump_burst = HdFx.sparks(36, 4.5, 0.035, cols)
	_jump_burst.name = "JumpBurst"
	(_jump_burst.process_material as ParticleProcessMaterial).direction = Vector3.DOWN
	(_jump_burst.process_material as ParticleProcessMaterial).spread = 70.0
	_jump_burst.position = Vector3(0, 0.05, 0)
	add_child(_jump_burst)
	_jet_audio = AudioStreamPlayer.new()
	_jet_audio.name = "JetAudio"
	_jet_audio.bus = &"SFX"
	_jet_audio.stream = LEVITATE_SFX  # bucle activado en la importación
	_jet_audio.volume_db = -60.0
	add_child(_jet_audio)


## Doble salto y levitación (mejoras del Grimorio).
func _air_moves(on_floor: bool, delta: float) -> void:
	if on_floor:
		_air_jumps = 1 if _has_double_jump else 0
		_double_jumped = false
		levitation_fuel = minf(
			levitation_max, levitation_fuel + levitation_max / levitate_recharge_sec * delta
		)
	elif not _locked and _coyote <= 0.0 and _air_jumps > 0 and _jump_tap:
		_air_jumps -= 1
		_double_jumped = true
		velocity.y = double_jump_velocity
		_jump_buffer = 0.0
		_fall_speed = 0.0
		_jump_burst.restart()
		AudioDirector.play_sfx(DOUBLE_JUMP_SFX, -5.0)
		_camera.add_trauma(0.08)
	# Levitar: tras el doble salto, mantener Espacio cuando el impulso ya se acaba.
	var want: bool = (
		not on_floor
		and not _locked
		and _double_jumped
		and levitation_max > 0.0
		and levitation_fuel > 0.0
		and Input.is_action_pressed(&"jump")
		and (levitating or velocity.y < 2.0)
	)
	if want:
		velocity.y = move_toward(velocity.y, levitate_speed, levitate_accel * delta)
		levitation_fuel = maxf(0.0, levitation_fuel - delta)
		_fall_speed = 0.0
		if levitation_fuel <= 0.0:
			AudioDirector.play_sfx(LEVITATE_EMPTY_SFX, -6.0)
			want = false
	if want != levitating:
		levitating = want
		_jet.emitting = want
		var tw := create_tween()
		if want:
			if not _jet_audio.playing:
				_jet_audio.play()
			tw.tween_property(_jet_audio, "volume_db", -6.0, 0.15)
		else:
			tw.tween_property(_jet_audio, "volume_db", -60.0, 0.35)
			tw.tween_callback(_jet_audio.stop)
	refill_flash = maxf(0.0, refill_flash - delta * 4.0)
	if levitating:
		# Más agudo cuanto menos carga queda: se nota que se acaba.
		_jet_audio.pitch_scale = lerpf(1.25, 0.95, fuel_ratio())


func get_caster() -> SpellCaster:
	return _caster


func get_camera() -> Camera3D:
	return _camera


func _unhandled_input(event: InputEvent) -> void:
	if (
		OS.is_debug_build()
		and event is InputEventKey
		and (event as InputEventKey).pressed
		and not (event as InputEventKey).echo
		and (event as InputEventKey).physical_keycode == KEY_G
	):
		# Debug: maná gratis para probar el Grimorio.
		GameState.deliver(100)
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if _locked:
			return
		var motion: InputEventMouseMotion = event
		var sens: float = mouse_sensitivity * Settings.mouse_sensitivity
		rotate_y(-motion.relative.x * sens)
		_head.rotation.x = clampf(
			_head.rotation.x - motion.relative.y * sens, deg_to_rad(-80), deg_to_rad(80)
		)


func _physics_process(delta: float) -> void:
	var on_floor: bool = is_on_floor()
	if not on_floor:
		velocity.y -= _gravity * delta
		_fall_speed = maxf(_fall_speed, -velocity.y)
	_coyote = coyote_sec if on_floor else maxf(0.0, _coyote - delta)
	_jump_buffer = maxf(0.0, _jump_buffer - delta)
	var held: bool = Input.is_action_pressed(&"jump")
	_jump_tap = held and not _jump_was_held and not _locked
	_jump_was_held = held
	if _jump_tap:
		_jump_buffer = jump_buffer_sec
	if _jump_buffer > 0.0 and _coyote > 0.0:
		velocity.y = jump_velocity
		_jump_buffer = 0.0
		_coyote = 0.0
		_fall_speed = 0.0
		AudioDirector.play_sfx(JUMP_SFX, -6.0)
	_air_moves(on_floor, delta)
	var input: Vector2 = (
		Vector2.ZERO
		if _locked
		else Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	)
	# Correr: sólo hacia delante (como en casi todos los FPS) y con las manos libres de carga.
	var sprinting: bool = (
		not _locked and Input.is_action_pressed(&"sprint") and input.y < -0.3 and on_floor
	)
	var speed: float = sprint_speed if sprinting else walk_speed
	var wish: Vector3 = (global_basis * Vector3(input.x, 0.0, input.y)).normalized() * speed
	# En el aire se controla menos (levitando, algo más).
	var accel: float = acceleration * (1.0 if on_floor else (0.7 if levitating else 0.35))
	var horizontal := Vector3(velocity.x, 0.0, velocity.z).move_toward(wish, accel * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	move_and_slide()
	_land_and_steps(horizontal.length(), sprinting, delta)
	_hands.move_speed = horizontal.length() if is_on_floor() else 0.0
	_update_pickup(delta)


## Pasos sobre la hierba, cabeceo de cámara, campo de visión al correr y caída al aterrizar.
func _land_and_steps(speed: float, sprinting: bool, delta: float) -> void:
	var on_floor: bool = is_on_floor()
	if on_floor and not _was_on_floor:
		var strength: float = clampf((_fall_speed - 2.0) / 8.0, 0.0, 1.0)
		if _fall_speed > 2.5:
			_camera.land(strength)
			AudioDirector.play_sfx(LAND_SFX, lerpf(-10.0, -2.0, strength))
			_hands.play_grab()
		_fall_speed = 0.0
		_step_dist = 0.0
	_was_on_floor = on_floor
	_camera.sprint = move_toward(_camera.sprint, 1.0 if sprinting else 0.0, delta * 4.0)
	if on_floor and speed > 0.5:
		_step_dist += speed * delta
		_bob_phase += speed * delta * PI / step_length
		var stride: float = step_length * (1.25 if sprinting else 1.0)
		if _step_dist >= stride:
			_step_dist = 0.0
			AudioDirector.play_sfx(_steps, -8.0 if sprinting else -11.0)
	var amp: float = clampf(speed / walk_speed, 0.0, 1.8) if on_floor else 0.0
	_camera.bob = Vector2(cos(_bob_phase) * 0.012, absf(sin(_bob_phase)) * 0.02) * amp


## Resalta el fragmento al que apuntas (o el más cercano delante) y lo recoge con F.
func _update_pickup(delta: float) -> void:
	if _shards == null:
		_shards = get_tree().get_first_node_in_group(&"shard_pool") as ShardPool
		if _shards == null:
			return
	var from: Vector3 = _camera.global_position
	var forward: Vector3 = -_camera.global_basis.z
	var query := PhysicsRayQueryParameters3D.create(
		from, from + forward * pickup_range, ShardPool.SHARD_LAYER | 1 | (1 << 1)
	)
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	var target: int = -1
	if not hit.is_empty():
		target = _shards.index_of(hit["collider"])
	if target < 0:
		var ahead: Vector3 = global_position + Vector3(forward.x, 0.0, forward.z).normalized() * 1.2
		target = _shards.nearest(ahead, pickup_assist_radius)
	if target != _target_shard:
		_target_shard = target
		_shards.set_highlight(target)
		Events.shard_targeted.emit(_shards.type_of(target) if target >= 0 else null)
	_pickup_cooldown = maxf(0.0, _pickup_cooldown - delta)
	if (
		target >= 0
		and not _locked
		and _pickup_cooldown <= 0.0
		and Input.is_action_pressed(&"interact")
	):
		_pickup_cooldown = pickup_repeat_sec
		if GameState.is_bag_full() and not GameState.has_direct_send():
			# No cabe: el fragmento se queda en el suelo y el HUD avisa.
			Events.bag_full.emit()
			_pickup_cooldown = 0.4
		else:
			_collect(target)
	_update_telekinesis(delta)


func _collect(index: int) -> void:
	var pos: Vector3 = _shards.position_of(index)
	if GameState.has_direct_send():
		# Envío directo: el fragmento desaparece del suelo y vuela solo a la tolva.
		var t: ShardType = _shards.collect(index, null)
		GameState.send_direct(t, pos)
		if index == _target_shard:
			_target_shard = -1
			Events.shard_targeted.emit(null)
		return
	var type: ShardType = _shards.collect(index, _grab_point)
	GameState.collect_shard(type, pos)
	_hands.play_grab()
	if index == _target_shard:
		_target_shard = -1
		Events.shard_targeted.emit(null)


## Telequinesis (mejora): los fragmentos cercanos vuelan solos a la mano mientras quepan.
func _update_telekinesis(delta: float) -> void:
	var radius: float = GameState.stat(&"telekinesis_radius", 0.0)
	if radius <= 0.0 or _locked or (GameState.is_bag_full() and not GameState.has_direct_send()):
		return
	_telekinesis_timer = maxf(0.0, _telekinesis_timer - delta)
	if _telekinesis_timer > 0.0:
		return
	var i: int = _shards.nearest(global_position, radius)
	if i >= 0:
		_telekinesis_timer = telekinesis_interval_sec
		AudioDirector.play_sfx(TELEKINESIS_SFX, -8.0)
		_collect(i)


func _add_outline() -> void:
	var quad := MeshInstance3D.new()
	quad.name = "OutlinePost"
	var mesh := QuadMesh.new()
	mesh.size = Vector2.ONE
	quad.mesh = mesh
	var mat := ShaderMaterial.new()
	mat.shader = OUTLINE_SHADER
	# Antes que el resto de transparentes: así las partículas quedan por encima del contorno.
	mat.render_priority = -100
	quad.material_override = mat
	quad.extra_cull_margin = 16384.0
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_camera.add_child(quad)
