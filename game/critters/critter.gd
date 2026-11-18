class_name Critter
extends Node3D
## Un bicho del valle: monstruito gracioso de ojos saltones (ver `CritterDef` y `CritterRig`).
## Pasea un poco alrededor de donde salió, como un animal: respira estirándose y encogiéndose,
## da saltitos (o anda como un pato, corretea o se arrastra), mira al mago con las pupilas que
## bailan (muelle poco amortiguado: ojos locos), parpadea y a veces hace gestos (lengua fuera,
## estornudo, bostezo, baile). Si el mago se acerca o cae un hechizo cerca, chilla, salta y
## corretea lejos. Nunca ataca.
## Al darle un hechizo se le acaba la suerte (`doom`): se hincha con los ojos fuera (o se congela,
## o el rayo le enseña el esqueleto, o la tierra lo aplasta como una tortita) y el rebaño lo hace
## reventar (`CritterHerd`, `CritterGore`). Lo maneja el rebaño desde un pool: `tick()` cada
## frame mientras está fuera; escondido no gasta nada.

enum State { HIDDEN, EMERGE, IDLE, MOVE, EMOTE, STARTLED, DOOMED }
enum Emote { TONGUE, SNEEZE, YAWN, DANCE }
## Cómo revienta según el hechizo: baba, chamuscado (fuego), congelado (Escarcha), esqueleto
## (Rayo), tortita (Tierra) y confeti rosa con ecos (Arcano).
enum Flavor { GOO, FIRE, FROST, BOLT, EARTH, ARCANE }

## Capa de colisión de los bichos: la ven la mira y los hechizos del mago; no el mago al andar,
## ni los fragmentos, ni los familiares.
const LAYER: int = 1 << 4
const MAX_EYES: int = 2
const MAX_LEGS: int = 4
## Muelle de las pupilas (rigidez y amortiguación): poco amortiguado, para que bailen.
const PUPIL_K: float = 170.0
const PUPIL_DAMP: float = 7.0
const PUPIL_MAX: float = 0.62
## Muelle del cuerpo (gelatina): estirones y aplastones que rebotan.
const JIG_K: float = 210.0
const JIG_DAMP: float = 9.0
## Duración de la anticipación según el sabor (s), multiplicando la del rebaño.
const DOOM_SCALE: PackedFloat32Array = [1.0, 1.2, 1.7, 1.6, 1.0, 1.0]
const C_CHAR := Color("#2b1d1a")
const C_ICE := Color("#7fd0ff")
const SP_TINT: StringName = &"tint"
const SP_FLASH: StringName = &"flash"

static var _sphere: SphereMesh
static var _small_sphere: SphereMesh

var def: CritterDef
var rig: CritterRig
var state: State = State.HIDDEN
## Donde salió: sólo pasea alrededor.
var home := Vector3.ZERO
## Cómo va a reventar y si lo hizo el mago (cuenta para la estadística y los avisos); `explosive`
## salpica a los vecinos (área) y `push` es hacia dónde salen los trozos.
var flavor: Flavor = Flavor.GOO
var by_player: bool = true
var explosive: bool = false
var push := Vector3.ZERO
## Gestos y sustos que ha hecho (para los tests y la demo).
var emotes_done: int = 0
var startles: int = 0

var _herd: CritterHerd
var _rng := RandomNumberGenerator.new()
var _model: Node3D
var _body: MeshInstance3D
var _xray: MeshInstance3D
var _mouth: Node3D
var _mouth_mi: MeshInstance3D
var _tongue: MeshInstance3D
var _teeth: MeshInstance3D
var _eye_bases: Array[Node3D] = []
var _eyes: Array[Node3D] = []
var _stalks: Array[MeshInstance3D] = []
var _scleras: Array[MeshInstance3D] = []
var _pupils: Array[MeshInstance3D] = []
var _glints: Array[MeshInstance3D] = []
var _legs: Array[Node3D] = []
var _leg_mis: Array[MeshInstance3D] = []
var _tintables: Array[GeometryInstance3D] = []
var _hitbox: StaticBody3D
var _shape: SphereShape3D
var _eye_count: int = 2
var _t: float = 0.0
var _state_t: float = 0.0
var _dur: float = 1.0
var _yaw: float = 0.0
var _target_yaw: float = 0.0
var _move_to := Vector3.ZERO
var _speed: float = 0.7
var _fleeing: bool = false
var _cycle: float = 0.0
var _phase: float = 0.0
var _emote: Emote = Emote.TONGUE
var _startle_cool: float = 0.0
var _next_gaze: float = 0.0
var _gaze := Vector2.ZERO
var _look_player: bool = false
var _blink_t: float = 2.0
var _blink: float = 0.0
var _bulge: float = 1.0
var _pupil_scale: float = 1.0
var _pupil := PackedVector2Array([Vector2.ZERO, Vector2.ZERO])
var _pupil_v := PackedVector2Array([Vector2.ZERO, Vector2.ZERO])
var _jig: float = 0.0
var _jig_v: float = 0.0
var _seed_t: float = 0.0
## Pose de este frame (la ponen los estados y la aplica `_apply_pose`).
var _py: float = 0.0
var _sx: float = 1.0
var _sy: float = 1.0
var _sz: float = 1.0
var _roll: float = 0.0
var _pitch: float = 0.0
var _lean_z: float = 0.0
var _legs_swing: float = 0.0
var _mouth_open: float = 1.0
var _tongue_k: float = 0.0
var _bulge_to: float = 1.0
var _pupil_to: float = 1.0
var _blink_force: float = 0.0
var _cross_eyed: float = 0.0
var _frozen: bool = false
## Cosas que ya pasaron en este estado (ver `_once`).
var _marks: int = 0


## Lo monta el rebaño una vez (nodos genéricos; la especie se pone en `spawn`).
func setup(herd: CritterHerd, index: int) -> void:
	_herd = herd
	_rng.seed = 4100 + index * 97
	top_level = true
	if _sphere == null:
		_sphere = SphereMesh.new()
		_sphere.radius = 1.0
		_sphere.height = 2.0
		_sphere.radial_segments = 10
		_sphere.rings = 6
		_small_sphere = SphereMesh.new()
		_small_sphere.radius = 1.0
		_small_sphere.height = 2.0
		_small_sphere.radial_segments = 6
		_small_sphere.rings = 3
	_model = Node3D.new()
	_model.name = "Model"
	add_child(_model)
	_body = _mesh_child(_model, "Body", herd.body_material)
	_xray = _mesh_child(_model, "Xray", herd.body_material)
	_xray.visible = false
	_mouth = Node3D.new()
	_mouth.name = "Mouth"
	_model.add_child(_mouth)
	_mouth_mi = _mesh_child(_mouth, "Smile", herd.body_material)
	_mouth_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Lengua y dientes no se estiran al abrir la boca: van aparte, en el mismo sitio.
	_tongue = _mesh_child(_model, "Tongue", herd.body_material)
	_teeth = _mesh_child(_model, "Teeth", herd.body_material)
	_teeth.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_tongue.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for i: int in MAX_EYES:
		var base := Node3D.new()
		base.name = "EyeBase%d" % i
		_model.add_child(base)
		_stalks.append(_mesh_child(base, "Stalk", herd.body_material))
		var eye := Node3D.new()
		eye.name = "Eye"
		base.add_child(eye)
		var sclera: MeshInstance3D = _mesh_child(eye, "Sclera", herd.sclera_material)
		sclera.mesh = _sphere
		var pupil: MeshInstance3D = _mesh_child(eye, "Pupil", herd.pupil_material)
		pupil.mesh = _sphere
		pupil.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var glint: MeshInstance3D = _mesh_child(eye, "Glint", herd.glint_material)
		glint.mesh = _small_sphere
		glint.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_eye_bases.append(base)
		_eyes.append(eye)
		_scleras.append(sclera)
		_pupils.append(pupil)
		_glints.append(glint)
	for i: int in MAX_LEGS:
		var hip := Node3D.new()
		hip.name = "Leg%d" % i
		_model.add_child(hip)
		_legs.append(hip)
		_leg_mis.append(_mesh_child(hip, "Mesh", herd.body_material))
	_tintables = [_body, _stalks[0], _stalks[1], _teeth]
	_tintables.append_array(_leg_mis)
	_hitbox = StaticBody3D.new()
	_hitbox.name = "Hitbox"
	_hitbox.collision_layer = 0
	_hitbox.collision_mask = 0
	_hitbox.set_meta(&"critter", self)
	var col := CollisionShape3D.new()
	_shape = SphereShape3D.new()
	col.shape = _shape
	_hitbox.add_child(col)
	add_child(_hitbox)
	hide_now()


func _mesh_child(parent: Node3D, node_name: String, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.material_override = mat
	parent.add_child(mi)
	return mi


## Sale como `p_def` en `at` mirando hacia `face`. `emerge`: brota del suelo con un ¡boing!.
func spawn(p_def: CritterDef, at: Vector3, emerge: bool, face: Vector3) -> void:
	if p_def != def:
		_set_species(p_def)
	home = at
	global_position = _on_ground(at)
	var d: Vector3 = face - at
	_yaw = atan2(-d.x, -d.z) if d.length_squared() > 0.01 else _rng.randf() * TAU
	_target_yaw = _yaw
	rotation = Vector3(0.0, _yaw, 0.0)
	visible = true
	_hitbox.collision_layer = LAYER
	_set_tint(Color(1, 1, 1, 0), 0.0)
	_body.visible = true
	_xray.visible = false
	_frozen = false
	_fleeing = false
	_jig = 0.0
	_jig_v = 0.0
	_bulge = 1.0
	_pupil_scale = 1.0
	_seed_t = _rng.randf() * 10.0
	_blink_t = _rng.randf_range(1.0, 3.0)
	for i: int in MAX_EYES:
		_pupil[i] = Vector2.ZERO
		_pupil_v[i] = Vector2.ZERO
		_eyes[i].visible = i < _eye_count
	_set_state(State.EMERGE if emerge else State.IDLE, 0.75 if emerge else _idle_time())
	_apply_pose(0.0)


## Fuera de juego: invisible, sin colisión y sin procesar.
func hide_now() -> void:
	state = State.HIDDEN
	visible = false
	if _hitbox:
		_hitbox.collision_layer = 0


func is_alive() -> bool:
	return state != State.HIDDEN and state != State.DOOMED


## Punto central del cuerpo (donde apunta la mira y salen los trozos).
func center() -> Vector3:
	return global_transform * rig.hit_center if rig else global_position


func eye_count() -> int:
	return _eye_count


## Dónde está el ojo `i` (y su radio): de ahí salen volando al reventar.
func eye_position(i: int) -> Vector3:
	return _eyes[i].global_position


## El mago o un hechizo lo asustan desde `from`: chilla, salta con los ojos fuera y corretea lejos.
func startle(from: Vector3) -> void:
	if not is_alive() or state == State.EMERGE or _startle_cool > 0.0:
		return
	_startle_cool = 2.5
	startles += 1
	var away: Vector3 = global_position - from
	away.y = 0.0
	if away.length_squared() < 0.01:
		away = Vector3(_rng.randf_range(-1, 1), 0.0, _rng.randf_range(-1, 1))
	_move_to = _herd.flee_target(self, away.normalized())
	_set_state(State.STARTLED, 0.38)
	_herd.voices.play(
		CritterVoices.Kind.SQUEAK, center(), 2.0, def.voice_pitch * _rng.randf_range(1.05, 1.25)
	)
	_kick_pupils(1.6)


## Un hechizo sin fuerza le da en la cabeza: aplastón, ojos locos y a correr (aunque acabe de
## asustarse).
func bonk(from: Vector3) -> void:
	if not is_alive():
		return
	if state == State.EMERGE:
		_set_state(State.IDLE, _idle_time())
	_startle_cool = 0.0
	_jig_v -= 6.0
	startle(from)


## Se le acabó la suerte: anticipación según el sabor y, al terminar, el rebaño lo revienta.
## `delay`: segundos antes de empezar (reacciones en cadena, ondas de área).
func doom(
	p_flavor: Flavor, delay: float, p_by_player: bool, p_explosive: bool, p_push: Vector3
) -> void:
	if not is_alive():
		return
	flavor = p_flavor
	by_player = p_by_player
	explosive = p_explosive
	push = p_push
	_hitbox.collision_layer = 0
	_set_state(State.DOOMED, _herd.config.anticipation_sec * DOOM_SCALE[flavor])
	_state_t = -delay
	_kick_pupils(2.2)


## Hace un gesto ya (demo y capturas).
func force_emote(e: Emote) -> void:
	if is_alive():
		_start_emote(e)


func tick(delta: float, cam: Vector3, player: Vector3) -> void:
	_t += delta
	_state_t += delta
	_startle_cool -= delta
	_reset_pose()
	var dist: float = Vector2(player.x - global_position.x, player.z - global_position.z).length()
	match state:
		State.EMERGE:
			_tick_emerge()
		State.IDLE:
			_tick_idle(dist, player)
		State.MOVE:
			_tick_move(delta)
		State.EMOTE:
			_tick_emote()
		State.STARTLED:
			_tick_startled()
		State.DOOMED:
			_tick_doomed()
			if _state_t >= _dur and state == State.DOOMED:
				_herd.burst(self)
				return
	# El mago no los atraviesa: los aparta con suavidad.
	if dist < 0.9 and state != State.DOOMED:
		var away: Vector3 = global_position - player
		away.y = 0.0
		if away.length_squared() > 0.0001:
			global_position = _on_ground(global_position + away.normalized() * (0.9 - dist) * 0.5)
	_tick_blink(delta)
	_look_player = dist < 16.0 or state == State.STARTLED
	_tick_eyes(delta, cam)
	_yaw = lerp_angle(_yaw, _target_yaw, minf(delta * (10.0 if _fleeing else 5.0), 1.0))
	rotation.y = _yaw
	_apply_pose(delta)


# --- Estados --------------------------------------------------------------------------------


func _set_state(s: State, duration: float) -> void:
	state = s
	_marks = 0
	_state_t = 0.0
	_dur = maxf(duration, 0.01)


func _idle_time() -> float:
	return _rng.randf_range(def.idle_min_sec, def.idle_max_sec)


func _tick_emerge() -> void:
	var k: float = _state_t / _dur
	if k < 0.4:
		var u: float = k / 0.4
		_py = lerpf(-rig.height * 1.1, 0.12, 1.0 - pow(1.0 - u, 3.0))
		_sy = 1.3
		_sx = 0.8
		_sz = 0.8
		_bulge_to = 1.3
	elif _once(1):
		# ¡Boing!: sale estirado y rebota.
		_jig_v = 7.0
		_kick_pupils(1.4)
	if _state_t >= _dur:
		_set_state(State.IDLE, _idle_time())


func _tick_idle(dist: float, player: Vector3) -> void:
	_breathe()
	if dist < 11.0:
		# Curioso: se vuelve hacia el mago.
		var d: Vector3 = player - global_position
		_target_yaw = atan2(-d.x, -d.z)
	if _state_t < _dur:
		return
	if _rng.randf() < 0.3 and not def.emotes.is_empty():
		_start_emote(def.emotes[_rng.randi() % def.emotes.size()] as Emote)
		return
	_move_to = _herd.wander_target(self)
	_speed = def.walk_speed
	_fleeing = false
	_set_state(State.MOVE, 12.0)


func _tick_move(delta: float) -> void:
	var to: Vector3 = _move_to - global_position
	to.y = 0.0
	var dist: float = to.length()
	if dist > 0.05:
		_target_yaw = atan2(-to.x, -to.z)
	var dir: Vector3 = to / maxf(dist, 0.001)
	var step: float = 0.0
	var speed: float = _speed
	match def.gait:
		CritterDef.Gait.HOP:
			var period: float = def.hop_sec * (0.6 if _fleeing else 1.0)
			_cycle += delta / period
			var c: float = fmod(_cycle, 1.0)
			if c < 0.2:
				_sy = 1.0 - 0.22 * sin(PI * c / 0.2)
				_sx = 1.0 + 0.11 * sin(PI * c / 0.2)
				_sz = _sx
			elif c < 0.85:
				var u: float = (c - 0.2) / 0.65
				_py = def.hop_height * (1.3 if _fleeing else 1.0) * sin(PI * u)
				_sy = 1.0 + 0.16 * cos(PI * u)
				_sx = 1.0 - 0.07 * cos(PI * u)
				_sz = _sx
				step = speed / 0.65 * delta
				_legs_swing = -0.5 * cos(PI * u)
			if c >= 0.85 and fmod(_cycle - delta / period, 1.0) < 0.85:
				# Aterriza: aplastón de gelatina y pupilas que botan.
				_jig_v -= 4.0
				_kick_pupils(0.8)
			if dist < 0.15 and (c < 0.05 or c >= 0.85):
				_end_move()
				return
		CritterDef.Gait.WADDLE:
			_phase += delta * speed * 9.0
			_roll = sin(_phase) * 0.17
			_py = absf(sin(_phase)) * 0.05
			_legs_swing = sin(_phase) * 0.6
			step = speed * delta
		CritterDef.Gait.SCURRY:
			_phase += delta * (30.0 if _fleeing else 20.0)
			_py = absf(sin(_phase)) * 0.04
			_pitch = 0.12
			_legs_swing = sin(_phase) * 0.9
			step = speed * 1.3 * delta
		CritterDef.Gait.SLIDE:
			_phase += delta * (10.0 if _fleeing else 6.0)
			_sz = 1.0 + 0.14 * sin(_phase)
			_sy = 1.0 - 0.07 * sin(_phase)
			step = speed * (0.3 + 0.9 * maxf(0.0, sin(_phase))) * delta
	if def.gait != CritterDef.Gait.HOP and dist < 0.1:
		_end_move()
		return
	global_position = _on_ground(global_position + dir * minf(step, dist))
	if _state_t >= _dur:
		_end_move()


func _end_move() -> void:
	_fleeing = false
	_cycle = 0.0
	_set_state(State.IDLE, _idle_time())


func _start_emote(e: Emote) -> void:
	_emote = e
	emotes_done += 1
	var at: Vector3 = center()
	var p: float = def.voice_pitch
	match e:
		Emote.TONGUE:
			_set_state(State.EMOTE, 1.6)
			_herd.voices.play(CritterVoices.Kind.BLEP, at, -4.0, p)
		Emote.SNEEZE:
			_set_state(State.EMOTE, 1.5)
			_herd.voices.play(CritterVoices.Kind.SNEEZE, at, -2.0, p * _rng.randf_range(0.95, 1.1))
		Emote.YAWN:
			_set_state(State.EMOTE, 1.5)
			_herd.voices.play(CritterVoices.Kind.YAWN, at, -4.0, p)
		Emote.DANCE:
			_set_state(State.EMOTE, 1.8)
			_herd.voices.play(CritterVoices.Kind.GIGGLE, at, -3.0, p)


func _tick_emote() -> void:
	var k: float = _state_t / _dur
	match _emote:
		Emote.TONGUE:
			_breathe()
			_tongue_k = smoothstep(0.0, 0.12, k) * (1.0 - smoothstep(0.85, 1.0, k))
			_mouth_open = 1.4
			_cross_eyed = _tongue_k
			_tongue.rotation.y = sin(_t * 15.0) * 0.45
		Emote.SNEEZE:
			if k < 0.47:
				var u: float = k / 0.47
				_pitch = -0.28 * u
				_sy = 1.0 + 0.12 * u
				_blink_force = u * 0.8
				_mouth_open = 1.0 + u * 0.8
			elif k < 0.55:
				if _once(1):
					_jig_v -= 7.0
					_kick_pupils(2.0)
					var fwd: Vector3 = -global_basis.z
					_herd.dust(center() + fwd * rig.hit_radius * 1.3, 0.5)
				_pitch = 0.35
				_lean_z = -0.08
				_sy = 0.8
				_mouth_open = 2.0
			else:
				_pitch = lerpf(0.35, 0.0, (k - 0.55) / 0.45)
				_bulge_to = 1.25
		Emote.YAWN:
			var o: float = sin(clampf(k / 0.85, 0.0, 1.0) * PI)
			_mouth_open = 1.0 + o * 1.9
			_blink_force = o * 0.85
			_sy = 1.0 + o * 0.12
			_sx = 1.0 - o * 0.05
			_sz = _sx
			_pitch = -0.14 * o
			if k > 0.85:
				_roll = sin(_t * 40.0) * 0.04
		Emote.DANCE:
			_roll = sin(_t * 12.0) * 0.26
			_py = absf(sin(_t * 6.0)) * 0.14
			_sy = 1.0 + absf(sin(_t * 6.0)) * 0.1
			_legs_swing = sin(_t * 12.0) * 0.8
			_gaze = Vector2(cos(_t * 6.0), sin(_t * 6.0)) * 0.5
			_mouth_open = 1.3
	if _state_t >= _dur:
		_tongue.rotation.y = 0.0
		_set_state(State.IDLE, _idle_time())


func _tick_startled() -> void:
	var k: float = _state_t / _dur
	_py = 0.55 * sin(PI * minf(k, 1.0))
	_sy = 1.0 + 0.3 * (1.0 - k)
	_sx = 1.0 - 0.12 * (1.0 - k)
	_sz = _sx
	_bulge_to = 1.45
	_pupil_to = 0.55
	_mouth_open = 2.0
	_legs_swing = sin(_t * 30.0) * 0.9
	if _state_t >= _dur:
		_jig_v -= 4.0
		_speed = def.flee_speed
		_fleeing = true
		_set_state(State.MOVE, 3.0)


func _tick_doomed() -> void:
	if _state_t < 0.0:
		# Aún no le toca (cadena u onda): sigue como estaba, algo nervioso.
		_breathe()
		_bulge_to = 1.2
		return
	if _once(1):
		_doom_voice()
	var k: float = clampf(_state_t / _dur, 0.0, 1.0)
	match flavor:
		Flavor.FROST:
			# Congelado al instante: sin moverse (ni los ojos), tiritando al final.
			_frozen = true
			_set_tint(Color(C_ICE, 0.78), 0.04 + 0.12 * k)
			_lean_z = sin(_t * 70.0) * 0.012 * k
			if k > 0.5 and _once(2):
				_herd.voices.play(CritterVoices.Kind.CLINK, center(), -6.0, 2.0)
		Flavor.BOLT:
			# Rayo: parpadea entre el bicho y su esqueleto (rayos X de dibujos animados).
			var on: bool = int(_state_t * 22.0) % 2 == 0
			_body.visible = not on
			_xray.visible = on
			_set_tint(Color(C_CHAR, 0.6 * k), 0.9 if on else 0.0)
			for i: int in _eye_count:
				_eyes[i].visible = not on
			_lean_z = sin(_t * 90.0) * 0.03
			_bulge_to = 1.5
			_pupil_to = 0.35
			_mouth_open = 2.2
		Flavor.EARTH:
			# Una losa invisible: ¡plaf! Tortita.
			var u: float = smoothstep(0.0, 0.18, k)
			_sy = lerpf(1.0, 0.1, u)
			_sx = lerpf(1.0, 1.85, u)
			_sz = _sx
			_bulge_to = 1.0 + u * 0.5
		_:
			# Se hincha temblando, ojos fuera, pupilas diminutas; destello blanco al final.
			var inflate: float = pow(k, 1.4)
			var shake: float = sin(_t * 55.0) * 0.06 * k
			_sx = 1.0 + 0.5 * inflate + shake
			_sz = _sx
			_sy = 1.0 + 0.32 * inflate - shake
			_bulge_to = 1.0 + 0.7 * k
			_pupil_to = 0.45
			_mouth_open = 1.0 + 1.3 * k
			_legs_swing = sin(_t * 40.0) * 0.7 * k
			var char_a: float = 0.9 * k if flavor == Flavor.FIRE else 0.0
			var pink_a: float = 0.4 * k if flavor == Flavor.ARCANE else 0.0
			var tint := Color(C_CHAR, char_a) if char_a > 0.0 else Color(Color("#ff9be0"), pink_a)
			_set_tint(tint, smoothstep(0.82, 1.0, k) * 1.4)


## La voz de la anticipación: se hincha chirriando, zumba con el rayo o silba al aplastarse.
func _doom_voice() -> void:
	var at: Vector3 = center()
	var p: float = def.voice_pitch * _rng.randf_range(0.95, 1.15)
	match flavor:
		Flavor.FROST:
			_herd.voices.play(CritterVoices.Kind.CLINK, at, -2.0, 1.2)
		Flavor.BOLT:
			_herd.voices.play(CritterVoices.Kind.ZAP, at, -2.0, 1.0)
			_herd.voices.play(CritterVoices.Kind.SQUEAK, at, 0.0, p * 1.4)
		Flavor.EARTH:
			_herd.voices.play(CritterVoices.Kind.FLATTEN, at, 0.0, p)
		_:
			_herd.voices.play(CritterVoices.Kind.INFLATE, at, -3.0, p)
			_herd.voices.play(CritterVoices.Kind.SQUEAK, at, -1.0, p * 1.3)


## True la primera vez que se pregunta por `bit` en este estado.
func _once(bit: int) -> bool:
	if _marks & bit:
		return false
	_marks |= bit
	return true


# --- Pose -----------------------------------------------------------------------------------


func _reset_pose() -> void:
	_py = 0.0
	_sx = 1.0
	_sy = 1.0
	_sz = 1.0
	_roll = 0.0
	_pitch = 0.0
	_lean_z = 0.0
	_legs_swing = 0.0
	_mouth_open = 1.0
	_tongue_k = 0.0
	_bulge_to = 1.0
	_pupil_to = 1.0
	_blink_force = 0.0
	_cross_eyed = 0.0


## Respira: se estira y se encoge (la gelatina más).
func _breathe() -> void:
	var amp: float = 0.06 if def.shape == CritterDef.Shape.BLOB else 0.035
	var b: float = sin((_t + _seed_t) * 2.6) * amp
	_sy *= 1.0 + b
	_sx *= 1.0 - b * 0.5
	_sz *= 1.0 - b * 0.5


func _apply_pose(delta: float) -> void:
	if _frozen:
		_model.position.x = _lean_z
		return
	# Muelle de gelatina encima de la pose.
	_jig_v += (-_jig * JIG_K - _jig_v * JIG_DAMP) * delta
	_jig += _jig_v * delta
	var j: float = clampf(_jig, -0.45, 0.6)
	_model.position = Vector3(0.0, _py, _lean_z)
	_model.rotation = Vector3(_pitch, 0.0, _roll)
	_model.scale = Vector3(_sx * (1.0 - j * 0.5), _sy * (1.0 + j), _sz * (1.0 - j * 0.5))
	for i: int in _legs.size():
		var side: float = 1.0 if i % 2 == 0 else -1.0
		_legs[i].rotation.x = _legs_swing * side * (1.0 if i < 2 else -1.0)
	_mouth.scale = Vector3(1.0, _mouth_open, 1.0)
	_tongue.visible = _tongue_k > 0.02
	if _tongue.visible:
		_tongue.scale = Vector3(1.0, 1.0, _tongue_k)
	if rig.stalk_len > 0.0:
		for i: int in _eye_count:
			_eye_bases[i].rotation = Vector3(
				sin(_t * 1.3 + float(i) * 2.0) * 0.14,
				0.0,
				(0.22 if i == 0 else -0.22) + sin(_t * 1.7 + float(i)) * 0.16
			)


func _tick_blink(delta: float) -> void:
	_blink_t -= delta
	if _blink_t <= 0.0:
		_blink = 0.14
		_blink_t = _rng.randf_range(1.6, 4.5)
	_blink = maxf(0.0, _blink - delta)
	var closed: float = maxf(_blink_force, 1.0 if _blink > 0.0 else 0.0)
	var k: float = minf(delta * 12.0, 1.0)
	_bulge = lerpf(_bulge, _bulge_to, k)
	_pupil_scale = lerpf(_pupil_scale, _pupil_to, k)
	var sy: float = lerpf(1.0, 0.12, closed)
	for i: int in _eye_count:
		_eyes[i].scale = Vector3(_bulge, _bulge * sy, _bulge)


## Pupilas: miran al mago (o a donde se les antoje) con un muelle que las hace bailar.
func _tick_eyes(delta: float, cam: Vector3) -> void:
	if not _look_player:
		_next_gaze -= delta
		if _next_gaze <= 0.0:
			_next_gaze = _rng.randf_range(0.7, 2.4)
			_gaze = Vector2(_rng.randf_range(-0.55, 0.55), _rng.randf_range(-0.35, 0.4))
	var wob: float = def.eye_wobble
	for i: int in _eye_count:
		var eye: Node3D = _eyes[i]
		var target: Vector2 = _gaze
		if _look_player:
			var gb: Basis = eye.global_basis.orthonormalized()
			var local: Vector3 = ((cam - eye.global_position) * gb).normalized()
			target = Vector2(local.x, local.y)
		if _cross_eyed > 0.0:
			var inward: float = 0.5 if i == 0 else -0.5
			if _eye_count == 1:
				inward = 0.0
			target = target.lerp(Vector2(inward, -0.25), _cross_eyed)
		target = target.limit_length(PUPIL_MAX)
		var acc: Vector2 = (target - _pupil[i]) * PUPIL_K - _pupil_v[i] * (PUPIL_DAMP / wob)
		_pupil_v[i] += acc * delta
		_pupil[i] = (_pupil[i] + _pupil_v[i] * delta).limit_length(PUPIL_MAX + 0.08)
		_place_pupil(i)


func _place_pupil(i: int) -> void:
	var p2: Vector2 = _pupil[i]
	var n := Vector3(p2.x, p2.y, -sqrt(maxf(0.0, 1.0 - p2.length_squared())))
	var r: float = rig.eye_r[i]
	var pr: float = r * def.pupil_ratio * _pupil_scale
	var b := Basis.looking_at(n, Vector3.UP)
	_pupils[i].transform = Transform3D(Basis(b.x * pr, b.y * pr, b.z * (pr * 0.4)), n * (r * 0.9))
	var g: float = pr * 0.3
	_glints[i].transform = Transform3D(
		Basis.from_scale(Vector3.ONE * g),
		n * (r * 0.9 + pr * 0.42) + (b.y * 0.38 - b.x * 0.32) * pr
	)


## Las pupilas saltan (aterrizajes, sustos): ojos locos.
func _kick_pupils(power: float) -> void:
	for i: int in MAX_EYES:
		_pupil_v[i] += Vector2(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * 3.0 * power


func _set_tint(c: Color, flash: float) -> void:
	for g: GeometryInstance3D in _tintables:
		g.set_instance_shader_parameter(SP_TINT, c)
		g.set_instance_shader_parameter(SP_FLASH, flash)


func _on_ground(p: Vector3) -> Vector3:
	return Vector3(p.x, Valley.ground_height(p.x, p.z), p.z)


## Pone las mallas y los anclajes de otra especie (al reciclarlo del pool).
func _set_species(p_def: CritterDef) -> void:
	def = p_def
	rig = CritterRig.for_def(def)
	_body.mesh = rig.body
	_xray.mesh = rig.xray
	_mouth.position = rig.mouth_pos
	_tongue.position = rig.mouth_pos
	_teeth.position = rig.mouth_pos
	_mouth_mi.mesh = rig.mouth
	_tongue.mesh = rig.tongue
	_teeth.mesh = rig.teeth
	_teeth.visible = rig.teeth != null
	_eye_count = mini(rig.eye_pos.size(), MAX_EYES)
	for i: int in MAX_EYES:
		var on: bool = i < _eye_count
		_eye_bases[i].visible = on
		if not on:
			continue
		_eye_bases[i].position = rig.eye_pos[i]
		_eye_bases[i].rotation = Vector3.ZERO
		_stalks[i].mesh = rig.stalk
		_stalks[i].visible = rig.stalk != null
		_eyes[i].position = Vector3(0.0, rig.stalk_len, 0.0)
		_scleras[i].scale = Vector3.ONE * rig.eye_r[i]
	for i: int in MAX_LEGS:
		var on: bool = rig.leg != null and i < rig.leg_pos.size()
		_legs[i].visible = on
		if on:
			_legs[i].position = rig.leg_pos[i]
			_leg_mis[i].mesh = rig.leg
	_shape.radius = rig.hit_radius
	(_hitbox.get_child(0) as CollisionShape3D).position = rig.hit_center
