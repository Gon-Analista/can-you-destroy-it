class_name GrandConvergence
extends Node
## La Gran Convergencia (GDD 9): "hay que asignar los cinco elementos y cargar con ambas manos".
## Va bajo el SpellCaster (recibe la entrada antes que él) y lo sustituye mientras está armada:
## - Armada (inscrita en el Grimorio y el Núcleo a la vista): los cinco elementos se asignan uno a
##   uno, cada uno con su nota, y quedan girando alrededor de las dos manos (una mota por
##   elemento y mano, de su color).
## - Mantener los dos botones mirando al Núcleo carga en cinco etapas (una por elemento, cada una
##   con su círculo de su color y la nota de su acorde, ver ChargeFeedback): el valle tiembla, la
##   música se apaga y las manos se llenan de luz.
## - Soltar con la carga completa lanza un haz trenzado de cinco colores al Núcleo
##   (ConvergenceBeam, `struck` al llegar). Soltar antes la deshace sin gastar nada.
## Un clic suelto no lanza nada: recuerda que hacen falta las dos manos.

signal struck(at: Vector3)

enum State { IDLE, ASSIGNING, ARMED, CHARGING, FIRED }

const VISUAL: SpellVisualDef = preload("res://data/spells/vfx_grand_convergence.tres")
const GLOW_SHADER: Shader = preload("res://fx/hd/hd_glow.gdshader")
const ACTIONS: Array[StringName] = [&"cast_left", &"cast_right"]
## Chispa, Escarcha, Rayo, Tierra, Arcano (los mismos de las venas del cristal).
const ELEMENT_COLORS: PackedColorArray = [
	Color(1.6, 0.75, 0.25),
	Color(0.7, 1.35, 1.7),
	Color(1.7, 1.5, 0.45),
	Color(1.15, 0.85, 0.45),
	Color(1.25, 0.7, 1.8)
]
const ASSIGN_SFX: Array[AudioStream] = [
	preload("res://audio/sfx/sfx_vein_chime_01.ogg"),
	preload("res://audio/sfx/sfx_vein_chime_02.ogg"),
	preload("res://audio/sfx/sfx_vein_chime_03.ogg"),
	preload("res://audio/sfx/sfx_vein_chime_04.ogg"),
	preload("res://audio/sfx/sfx_vein_chime_05.ogg"),
]
const STAGE_SFX: Array[AudioStream] = [
	preload("res://audio/sfx/sfx_convergence_note_01.ogg"),
	preload("res://audio/sfx/sfx_convergence_note_02.ogg"),
	preload("res://audio/sfx/sfx_convergence_note_03.ogg"),
	preload("res://audio/sfx/sfx_convergence_note_04.ogg"),
	preload("res://audio/sfx/sfx_convergence_note_05.ogg"),
]
const LOOP_SFX: AudioStream = preload("res://audio/sfx/amb_convergence_charge_loop.ogg")
const RELEASE_SFX: AudioStream = preload("res://audio/sfx/sfx_convergence_release_01.ogg")
const FIZZLE_SFX: AudioStream = preload("res://audio/sfx/sfx_convergence_fizzle_01.ogg")
## Los mismos colores sin HDR para los círculos (con HDR se lavaban a blanco con tanta luz).
const CIRCLE_COLORS: PackedColorArray = [
	Color(1.0, 0.42, 0.1),
	Color(0.35, 0.85, 1.0),
	Color(1.0, 0.86, 0.15),
	Color(0.7, 0.45, 0.2),
	Color(0.78, 0.35, 1.0)
]
const STAGES: int = 5
## Segundos entre la asignación de un elemento y el siguiente.
const ASSIGN_GAP: float = 0.28
## El Núcleo tiene que estar delante (coseno del ángulo con la mirada) para empezar a cargar.
const AIM_DOT: float = 0.8
const MAX_DIST: float = 170.0
const HINT_GAP: float = 3.0
## Tras el primer botón, lo que se espera al otro antes de recordar que van los dos.
const PAIR_WAIT: float = 0.3

var camera: Camera3D
var hands: WizardHands
var reveal: CoreReveal
var state: int = State.IDLE
## Demo y depuración: carga sola al armarse y suelta al completar.
var auto: bool = false

var _stages := ChargeStages.new()
var _feedback: ChargeFeedback
var _circles: MagicCircles
var _beam: ConvergenceBeam
var _loop: AudioStreamPlayer
var _motes: Array[MeshInstance3D] = []
var _mote_mats: Array[ShaderMaterial] = []
var _assigned: int = 0
var _assign_t: float = 0.0
var _time: float = 0.0
var _now: float = 0.0
var _held: Array[bool] = [false, false]
var _wait: float = -1.0
var _hint_at: float = -100.0
var _gather: float = 0.0


func _ready() -> void:
	add_to_group(&"grand_convergence")
	_circles = MagicCircles.new()
	_circles.name = "ConvergenceCircles"
	add_child(_circles)
	_feedback = ChargeFeedback.new()
	_feedback.name = "ConvergenceFeedback"
	_feedback.camera = camera
	_feedback.hands = hands
	_feedback.stage_sfx = STAGE_SFX
	add_child(_feedback)
	_loop = AudioStreamPlayer.new()
	_loop.name = "ConvergenceLoop"
	_loop.bus = &"SFX"
	_loop.stream = LOOP_SFX  # bucle activado en la importación
	add_child(_loop)
	_beam = ConvergenceBeam.new()
	_beam.name = "ConvergenceBeam"
	add_child(_beam)
	_beam.arrived.connect(_on_beam_arrived)
	if camera:
		for i: int in STAGES * 2:
			var q: MeshInstance3D = HdFx.quad(GLOW_SHADER, 0.06, 6)
			q.name = "ElementMote%d" % i
			var m: ShaderMaterial = q.material_override
			m.set_shader_parameter("color", ELEMENT_COLORS[i % STAGES])
			m.set_shader_parameter("falloff", 1.6)
			m.set_shader_parameter("rays", 0.5)
			m.set_shader_parameter("ray_count", 4.0)
			q.visible = false
			camera.add_child(q)
			_motes.append(q)
			_mote_mats.append(m)
	Events.menu_opened.connect(_cancel)
	Events.grimoire_opened.connect(_cancel)


## Carga actual (0..1).
func charge_ratio() -> float:
	return _stages.charge_at(_time) if state == State.CHARGING else 0.0


func is_armed() -> bool:
	return state == State.ARMED or state == State.CHARGING


## Demo y depuración: mira al Núcleo, carga y suelta solo.
func auto_cast() -> void:
	auto = true
	if state == State.ARMED:
		_aim_at_core()
		begin_charge()


func _can_arm() -> bool:
	return (
		reveal != null
		and reveal.is_exposed()
		and GameState.has_upgrade(GameState.GRAND_CONVERGENCE)
		and not GameState.progression.game_complete
	)


func _unhandled_input(event: InputEvent) -> void:
	if state == State.IDLE or state == State.FIRED:
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not auto:
		return
	for side: int in 2:
		if event.is_action_pressed(ACTIONS[side]):
			get_viewport().set_input_as_handled()
			_on_press(side)
			return
		if event.is_action_released(ACTIONS[side]):
			get_viewport().set_input_as_handled()
			_on_release(side)
			return


func _on_press(side: int) -> void:
	_held[side] = true
	if state == State.CHARGING:
		# "Clic para cargar" (Opciones): el siguiente clic suelta.
		if not Settings.hold_to_charge:
			release()
		return
	if state != State.ARMED:
		return
	if _held[1 - side]:
		_wait = -1.0
		if _core_in_sight():
			begin_charge()
		else:
			_hint(tr("MIRA AL NÚCLEO Y JUNTA LAS MANOS"))
			AudioDirector.play_sfx(FIZZLE_SFX, -14.0, 1.3)
	else:
		_wait = PAIR_WAIT


func _on_release(side: int) -> void:
	_held[side] = false
	if state == State.CHARGING and Settings.hold_to_charge:
		release()


## Empieza a cargar (las dos manos juntas).
func begin_charge() -> void:
	if state != State.ARMED:
		return
	state = State.CHARGING
	_time = 0.0
	_stages.reset(STAGES, GameState.BALANCE.convergence_charge_sec, 0.0)
	_feedback.begin(STAGES)
	if hands:
		hands.begin_combine(VISUAL)
	_loop.pitch_scale = 0.8
	_loop.volume_db = -20.0
	_loop.play()
	AudioDirector.play_sfx(STAGE_SFX[0], -12.0, 0.5)
	# La música se apaga mientras se carga (GDD 9).
	AudioDirector.fade_theme(-60.0, GameState.BALANCE.convergence_charge_sec * 0.8)
	Events.convergence_charging.emit(true)


## Suelta: con las cinco etapas, sale; antes, se deshace sin coste.
func release() -> void:
	if state != State.CHARGING:
		return
	if not _stages.is_full():
		_fizzle()
		return
	state = State.FIRED
	_loop.stop()
	_feedback.end()
	_circles.release()
	if hands:
		hands.release_combine()
	var from: Vector3 = _hand_origin()
	_beam.launch(from, reveal.core_position(), reveal.core_radius(), ELEMENT_COLORS, VISUAL)
	AudioDirector.play_sfx(RELEASE_SFX, 0.0)
	if camera is CameraRig:
		(camera as CameraRig).add_trauma(0.7)
		(camera as CameraRig).punch_fov(8.0)
	_hide_motes()
	Events.convergence_charging.emit(false)
	GameState.progression.spells_cast += 1


func _fizzle() -> void:
	state = State.ARMED
	_loop.stop()
	_feedback.end()
	_circles.cancel()
	if hands:
		hands.cancel_combine()
	AudioDirector.play_sfx(FIZZLE_SFX, -4.0)
	AudioDirector.fade_theme(-7.0, 1.2)
	_hint(tr("LA CONVERGENCIA SE DESHACE: CARGA LOS CINCO ELEMENTOS"))
	Events.convergence_charging.emit(false)


## Un menú o el Grimorio a media carga: se deshace en silencio.
func _cancel() -> void:
	_held = [false, false]
	if state != State.CHARGING:
		return
	state = State.ARMED
	_loop.stop()
	_feedback.end()
	_circles.cancel()
	if hands:
		hands.cancel_combine()
	AudioDirector.fade_theme(-7.0, 1.0)
	Events.convergence_charging.emit(false)


func _process(delta: float) -> void:
	_now += delta
	match state:
		State.IDLE:
			if _can_arm():
				_begin_assign()
		State.ASSIGNING:
			_update_assign(delta)
		State.ARMED:
			if not _can_arm():
				_disarm()
				return
			if _wait >= 0.0:
				_wait -= delta
				if _wait < 0.0 and not (_held[0] and _held[1]):
					_hint(tr("MANTÉN LOS DOS BOTONES A LA VEZ"))
					AudioDirector.play_sfx(ASSIGN_SFX[0], -16.0, 1.5)
			if auto:
				_aim_at_core()
				begin_charge()
		State.CHARGING:
			_update_charge(delta)
	if state != State.IDLE and state != State.FIRED:
		_update_motes(delta)


func _begin_assign() -> void:
	state = State.ASSIGNING
	_assigned = 0
	_assign_t = 0.4
	Events.hint.emit(tr("LOS CINCO ELEMENTOS ACUDEN A TUS MANOS"), Color("#ffd27a"))


## Los elementos llegan a las manos uno a uno (Chispa, Escarcha, Rayo, Tierra, Arcano).
func _update_assign(delta: float) -> void:
	_assign_t -= delta
	if _assign_t > 0.0:
		return
	if _assigned >= STAGES:
		state = State.ARMED
		Events.hint.emit(tr("MANTÉN LOS DOS BOTONES MIRANDO AL NÚCLEO"), Color("#e3b6ff"))
		return
	AudioDirector.play_sfx(ASSIGN_SFX[_assigned], -8.0)
	if hands:
		hands.play_switch(_assigned % 2)
	_mote_mats[_assigned].set_shader_parameter("intensity", 4.0)
	_mote_mats[_assigned + STAGES].set_shader_parameter("intensity", 4.0)
	_assigned += 1
	_assign_t = ASSIGN_GAP


func _disarm() -> void:
	state = State.IDLE
	_hide_motes()


func _update_charge(delta: float) -> void:
	_time += delta
	var k: float = _stages.charge_at(_time)
	var stage: int = _stages.advance(k)
	if stage > 0:
		_feedback.stage(stage, STAGES, false)
		_mote_mats[stage - 1].set_shader_parameter("intensity", 6.0)
		_mote_mats[stage - 1 + STAGES].set_shader_parameter("intensity", 6.0)
	_loop.pitch_scale = lerpf(0.8, 1.35, float(_stages.reached) / STAGES + k * 0.1)
	_loop.volume_db = lerpf(-20.0, -4.0, k)
	if hands:
		hands.combine_charge = k
	if reveal:
		reveal.charge = k
	# El valle tiembla cada vez más.
	if camera is CameraRig:
		(camera as CameraRig).add_trauma(delta * (0.25 + 0.9 * k))
	_circles.charging(
		k,
		STAGES,
		_hand_origin(),
		reveal.core_position() if reveal else _hand_origin() - camera.global_basis.z,
		CIRCLE_COLORS[4],
		Color(1.4, 1.3, 1.5),
		STAGES,
		CIRCLE_COLORS
	)
	if auto and _stages.is_full() and _time >= _stages.duration + 0.35:
		release()


## Las motas de cada elemento giran alrededor de cada mano; al cargar se juntan en el orbe y las
## de las etapas ya completas se quedan pegadas a él, girando cada vez más deprisa.
func _update_motes(delta: float) -> void:
	if camera == null or hands == null:
		return
	var charging: bool = state == State.CHARGING
	_gather = move_toward(_gather, 1.0 if charging else 0.0, delta * 2.5)
	var depth: float = WizardHands.orb_depth(camera)
	var k: float = charge_ratio()
	for i: int in _motes.size():
		var e: int = i % STAGES
		var side: int = i / STAGES
		var q: MeshInstance3D = _motes[i]
		q.visible = e < _assigned or state != State.ASSIGNING
		if not q.visible:
			continue
		var locked: bool = charging and e < _stages.reached
		var speed: float = 2.2 + (5.0 if locked else 0.0) + k * 3.0
		var a: float = _now * speed * (1.0 if side == 0 else -1.0) + TAU * float(e) / STAGES
		var center: Vector2 = hands.palm_screen_position(side).lerp(
			hands.palm_screen_position(2), _gather
		)
		var rad: float = lerpf(22.0, 11.0 if locked else 16.0, _gather) * (1.0 - 0.25 * k)
		var off := Vector2(cos(a), sin(a) * 0.45) * rad
		# Por detrás de la mano (seno negativo) se ve más pequeña: la órbita se lee en 3D.
		var front: float = 0.5 + 0.5 * sin(a)
		var world: Vector3 = camera.project_position(center + off, depth * (1.0 + 0.08 * front))
		q.position = camera.to_local(world)
		q.scale = Vector3.ONE * lerpf(0.65, 1.15, front) * (1.0 + 0.6 * k)
		var m: ShaderMaterial = _mote_mats[i]
		var it: float = float(m.get_shader_parameter("intensity"))
		m.set_shader_parameter("intensity", move_toward(it, 1.6 + 1.6 * k, delta * 6.0))


func _hide_motes() -> void:
	for q: MeshInstance3D in _motes:
		q.visible = false


func _on_beam_arrived(at: Vector3) -> void:
	struck.emit(at)


func _core_in_sight() -> bool:
	if reveal == null or camera == null:
		return false
	var to: Vector3 = reveal.core_position() - camera.global_position
	if to.length() > MAX_DIST:
		return false
	return (-camera.global_basis.z).dot(to.normalized()) >= AIM_DOT


func _aim_at_core() -> void:
	var player: Node3D = get_tree().get_first_node_in_group(&"player") as Node3D
	if player == null or reveal == null or camera == null:
		return
	var to: Vector3 = reveal.core_position() - camera.global_position
	player.rotation.y = atan2(-to.x, -to.z)
	var head: Node3D = camera.get_parent() as Node3D
	if head:
		head.rotation.x = atan2(to.y, Vector2(to.x, to.z).length())


## Entre las palmas (donde se forma el orbe).
func _hand_origin() -> Vector3:
	if hands and camera:
		return camera.project_position(hands.palm_screen_position(2), WizardHands.orb_depth(camera))
	return camera.global_position - camera.global_basis.z


func _hint(text: String) -> void:
	if _now - _hint_at < HINT_GAP:
		return
	_hint_at = _now
	Events.hint.emit(text, Color("#e3b6ff"))
