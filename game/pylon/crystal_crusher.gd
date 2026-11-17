class_name CrystalCrusher
extends Node3D
## La trituradora del Pilón de Maná: así se entrega (GDD 2.2: la entrega es parte del juego).
## 1. Tolva: mantén F a su lado y los cristales de la bolsa salen de tus manos uno a uno, cada
##    vez más deprisa, y se amontonan dentro (se ven tras el cristal de la tolva). Cada uno
##    tintinea al caer, con un tono que sube.
## 2. Palanca: F (o con la bolsa vacía, F en cualquier punto junto a la máquina) tira de ella.
## 3. Trituración: la máquina arranca (motor, engranajes y rodillos que giran, vibración), cada
##    cristal cruje entre los rodillos con polvo y chispas, su maná viaja brillando por la
##    tubería y entra en el Pilón. Acelera mientras tritura y termina con un resoplido de vapor.
## El maná se gana al triturar (ManaPylon.receive_mana).

signal crushed(type: ShardType)

const TOON_SHADER: Shader = preload("res://fx/toon.gdshader")
const SHARD_SHADER: Shader = preload("res://crystal/shard.gdshader")
const SHELL_SHADER: Shader = preload("res://pylon/pylon_glass_shell.gdshader")
const CLINK_SFX: Array[AudioStream] = [
	preload("res://audio/sfx/sfx_hopper_clink_01.ogg"),
	preload("res://audio/sfx/sfx_hopper_clink_02.ogg"),
	preload("res://audio/sfx/sfx_hopper_clink_03.ogg"),
]
const CRUNCH_SFX: Array[AudioStream] = [
	preload("res://audio/sfx/sfx_crunch_01.ogg"),
	preload("res://audio/sfx/sfx_crunch_02.ogg"),
	preload("res://audio/sfx/sfx_crunch_03.ogg"),
	preload("res://audio/sfx/sfx_crunch_04.ogg"),
]
const LEVER_SFX: AudioStream = preload("res://audio/sfx/sfx_lever_pull_01.ogg")
const START_SFX: AudioStream = preload("res://audio/sfx/sfx_machine_start_01.ogg")
const LOOP_SFX: AudioStream = preload("res://audio/sfx/amb_crusher_loop.ogg")
const STEAM_SFX: AudioStream = preload("res://audio/sfx/sfx_steam_release_01.ogg")
## Escala pentatónica (semitonos) de los tintineos seguidos en la tolva.
const CLINK_LADDER: PackedInt32Array = [0, 2, 4, 7, 9, 12, 14, 16, 19, 21, 24]
const C_STONE := Color("#d9d0d4")
const C_IRON := Color("#5d6380")
const C_IRON_DARK := Color("#3b3f57")
const C_GOLD := Color("#d8a23a")
const C_GOLD_DARK := Color("#9c6b25")
const C_WOOD := Color("#7a4e33")
const C_RED := Color("#c8423a")
const PILE_MAX: int = 36
## Pulsación más corta que esto = tocar (palanca); más larga = mantener (echar cristales).
const TAP_SEC: float = 0.2
const BEADS: int = 10
const HOPPER_TOP: float = 2.15
const HOPPER_BOTTOM: float = 1.45

## Modo demo (capturas sin ratón): acepta F aunque el ratón no esté capturado.
static var demo_input: bool = false

## Distancia a la que se puede usar la máquina (m).
@export var use_radius: float = 3.8
## Intervalo entre cristales al empezar a mantener F, y el mínimo al que acelera.
@export var feed_interval_start: float = 0.4
@export var feed_interval_min: float = 0.09
## Segundos manteniendo F hasta llegar a la velocidad máxima.
@export var feed_ramp_sec: float = 2.4
## Cristales triturados por segundo al arrancar y a tope.
@export var crush_rate_start: float = 4.0
@export var crush_rate_max: float = 14.0
## Segundos del maná viajando por la tubería hasta el Pilón.
@export var pipe_sec: float = 0.35

var pylon: ManaPylon
var _toon: ShaderMaterial
var _hopper: Array[ShardType] = []
## Cristales en vuelo hacia la tolva (para no pasarse del tope al contarlos).
var _incoming: int = 0
var _player: Node3D
var _hold_t: float = 0.0
## Tiempo que lleva pulsada F (-1: no se está pulsando junto a la máquina).
var _press_t: float = -1.0
var _clink_gap: float = 0.0
var _crunch_gap: float = 0.0
var _was_pressed: bool = false
var _feed_timer: float = 0.0
var _clink_chain: int = 0
var _clink_timer: float = 0.0
## Estado: 0 parada, 1 tirando de la palanca, 2 arrancando, 3 triturando, 4 parando.
var _state: int = 0
var _state_t: float = 0.0
var _crush_acc: float = 0.0
var _crushed_count: int = 0
var _spin: float = 0.0
var _spin_speed: float = 0.0
var _shake: float = 0.0
var _lever_angle: float = 0.0
var _body: Node3D
var _rollers: Array[Node3D] = []
var _gears: Array[Node3D] = []
var _lever: Node3D
var _pile: MultiMeshInstance3D
var _pile_meshes: Dictionary[ShardType, int] = {}
var _window_light: OmniLight3D
var _pipe_glow: StandardMaterial3D
var _beads: Array[MeshInstance3D] = []
var _bead_t: PackedFloat32Array = []
var _bead_value: Array[ShardType] = []
var _dust: GPUParticles3D
var _sparks: GPUParticles3D
var _steam: GPUParticles3D
var _clink_player: AudioStreamPlayer3D
var _crunch_player: AudioStreamPlayer3D
var _fx_player: AudioStreamPlayer3D
var _loop_player: AudioStreamPlayer3D
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	add_to_group(&"crystal_crusher")
	_rng.randomize()
	_toon = ShaderMaterial.new()
	_toon.shader = TOON_SHADER
	_toon.set_shader_parameter("rim", 0.3)
	_body = Node3D.new()
	_body.name = "Body"
	add_child(_body)
	_build_frame()
	_build_rollers_and_gears()
	_build_hopper()
	_build_lever()
	_build_pipe()
	_build_fx()
	_build_audio()
	_build_collision()


## Cuántos cristales hay en la tolva.
func hopper_count() -> int:
	return _hopper.size()


func is_busy() -> bool:
	return _state != 0


func player_in_range() -> bool:
	if _player == null:
		_player = get_tree().get_first_node_in_group(&"player") as Node3D
	if _player == null:
		return false
	var d: Vector3 = _player.global_position - global_position
	d.y = 0.0
	return d.length() <= use_radius


## Texto para el HUD según lo que se puede hacer ahora.
func prompt() -> String:
	if not player_in_range():
		return ""
	if _state != 0:
		return tr("TRITURANDO...  %d") % _hopper.size()
	var bag: int = GameState.progression.bag_count()
	var parts: PackedStringArray = []
	if bag > 0:
		parts.append(tr("MANTÉN [F] ECHAR (%d)") % bag)
	if _hopper.size() > 0:
		parts.append(tr("TOCA [F] PALANCA (%d)") % _hopper.size())
	if parts.is_empty():
		return tr("TRAE CRISTALES PARA TRITURAR")
	return "  ·  ".join(parts)


## Punto donde caen los cristales (la boca de la tolva).
func hopper_mouth() -> Vector3:
	return global_position + Vector3.UP * (HOPPER_TOP + 0.4)


## Punto al que apunta el marcador del HUD.
func marker_position() -> Vector3:
	return global_position + Vector3.UP * (HOPPER_TOP + 0.9)


## Envío directo: un fragmento recogido vuela desde `from` hasta la tolva.
func receive_direct(type: ShardType, from: Vector3) -> void:
	if pylon == null:
		add_to_hopper(type)
		return
	_incoming += 1
	pylon.launch_mote(type, hopper_mouth(), self, false, from)


## Llega un cristal a la tolva (lo llama el Pilón al terminar su vuelo).
func add_to_hopper(type: ShardType) -> void:
	_incoming = maxi(0, _incoming - 1)
	_hopper.append(type)
	_update_pile()
	var step: int = CLINK_LADDER[mini(_clink_chain, CLINK_LADDER.size() - 1)]
	_clink_chain += 1
	_clink_timer = 0.7
	# Un tintineo cada poco (si llegan muy seguidos se saltan: así no se acoplan).
	if _clink_gap <= 0.0:
		_clink_gap = 0.11
		_clink_player.pitch_scale = pow(2.0, float(step) / 12.0) * type.pickup_pitch
		_clink_player.play()
	_dust.global_position = hopper_mouth() + Vector3.DOWN * 0.3
	_dust.amount_ratio = 0.3
	_dust.restart()


## Tira de la palanca: arranca la trituración si hay algo en la tolva.
func pull_lever() -> bool:
	if _state != 0 or _hopper.is_empty() or _incoming > 0:
		return false
	_state = 1
	_state_t = 0.0
	_crushed_count = 0
	_fx_player.stream = LEVER_SFX
	_fx_player.play()
	return true


func _process(delta: float) -> void:
	_clink_gap = maxf(0.0, _clink_gap - delta)
	_crunch_gap = maxf(0.0, _crunch_gap - delta)
	_update_input(delta)
	_update_machine(delta)
	_update_beads(delta)
	_clink_timer = maxf(0.0, _clink_timer - delta)
	if _clink_timer <= 0.0:
		_clink_chain = 0


func _update_input(delta: float) -> void:
	var usable: bool = (
		player_in_range()
		and (Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or demo_input)
		and _state == 0
	)
	var pressed: bool = Input.is_action_pressed(&"interact")
	var just_pressed: bool = pressed and not _was_pressed
	_was_pressed = pressed
	if not usable:
		_press_t = -1.0
		_hold_t = 0.0
		return
	if just_pressed:
		_press_t = 0.0
		_feed_timer = 0.0
	if _press_t < 0.0:
		return
	if pressed:
		_press_t += delta
		# Mantener F: tras un instante, los cristales salen cada vez más deprisa.
		if _press_t >= TAP_SEC and GameState.progression.bag_count() > 0:
			_hold_t += delta
			_feed_timer -= delta
			if _feed_timer <= 0.0:
				var k: float = smoothstep(0.0, feed_ramp_sec, _hold_t)
				_feed_timer = (
					lerpf(feed_interval_start, feed_interval_min, k)
					/ GameState.stat(&"crusher_speed", 1.0)
				)
				var type: ShardType = GameState.take_for_delivery()
				if type and pylon:
					_incoming += 1
					pylon.launch_mote(type, hopper_mouth(), self)
					Events.shard_sent_to_pylon.emit(type)
					_toss_hands()
	else:
		# Tocar F (soltar enseguida): tirar de la palanca.
		if _press_t < TAP_SEC:
			pull_lever()
		_press_t = -1.0
		_hold_t = 0.0


func _toss_hands() -> void:
	var hands: WizardHands = get_tree().get_first_node_in_group(&"wizard_hands") as WizardHands
	if hands:
		hands.play_toss()


func _update_machine(delta: float) -> void:
	_state_t += delta
	var target_lever: float = 0.0
	match _state:
		1:
			# Palanca abajo.
			target_lever = 1.0
			if _state_t > 0.35:
				_state = 2
				_state_t = 0.0
				_fx_player.stream = START_SFX
				_fx_player.play()
				_loop_player.volume_db = -30.0
				_loop_player.play()
		2:
			target_lever = 1.0
			_spin_speed = lerpf(0.0, 6.0, clampf(_state_t / 0.6, 0.0, 1.0))
			_loop_player.volume_db = lerpf(-30.0, -6.0, clampf(_state_t / 0.6, 0.0, 1.0))
			if _state_t > 0.6:
				_state = 3
				_state_t = 0.0
				_crush_acc = 0.0
		3:
			target_lever = 1.0
			# Acelera mientras tritura: cada vez más deprisa, como al echarlos.
			var rate: float = lerpf(
				crush_rate_start, crush_rate_max, smoothstep(0.0, 2.5, _state_t)
			)
			_spin_speed = lerpf(
				6.0, 22.0, (rate - crush_rate_start) / (crush_rate_max - crush_rate_start)
			)
			_loop_player.pitch_scale = lerpf(1.0, 1.35, _spin_speed / 22.0)
			_crush_acc += rate * delta
			while _crush_acc >= 1.0 and not _hopper.is_empty():
				_crush_acc -= 1.0
				_crush_one()
			if _hopper.is_empty():
				_state = 4
				_state_t = 0.0
				_fx_player.stream = STEAM_SFX
				_fx_player.play()
				_steam.restart()
		4:
			_spin_speed = lerpf(_spin_speed, 0.0, 1.0 - exp(-delta * 3.0))
			_loop_player.volume_db = lerpf(-6.0, -40.0, clampf(_state_t / 0.8, 0.0, 1.0))
			if _state_t > 0.9:
				_loop_player.stop()
				_state = 0
				_spin_speed = 0.0
				if _crushed_count > 0:
					Events.hint.emit(
						tr("¡%d CRISTALES TRITURADOS!") % _crushed_count, Color("#ff7ad9")
					)
	# Palanca: baja deprisa y vuelve con rebote.
	_lever_angle = lerpf(
		_lever_angle, target_lever, 1.0 - exp(-delta * (18.0 if target_lever > 0.5 else 6.0))
	)
	_lever.rotation.z = lerpf(deg_to_rad(35.0), deg_to_rad(-50.0), _lever_angle)
	# Engranajes y rodillos.
	_spin += _spin_speed * delta
	_rollers[0].rotation.x = _spin
	_rollers[1].rotation.x = -_spin
	_gears[0].rotation.z = _spin * 0.5
	_gears[1].rotation.z = -_spin * 0.9
	# La máquina tiembla mientras trabaja (centímetros).
	_shake = maxf(_shake - delta * 6.0, (_spin_speed / 22.0) * 0.4)
	var a: float = _shake * 0.025
	_body.position = Vector3(
		_rng.randf_range(-a, a), _rng.randf_range(0.0, a), _rng.randf_range(-a, a)
	)
	_window_light.light_energy = 0.3 + _spin_speed / 22.0 * 1.5 + _shake


func _crush_one() -> void:
	var type: ShardType = _hopper.pop_back()
	_crushed_count += 1
	_update_pile()
	if _crunch_gap <= 0.0:
		_crunch_gap = 0.1
		_crunch_player.pitch_scale = _rng.randf_range(0.9, 1.15) * lerpf(1.0, 0.8, type.radius)
		_crunch_player.play()
	_shake = 1.0
	_dust.global_position = global_position + Vector3(0.85, 0.95, 0.0)
	_dust.amount_ratio = 1.0
	_dust.restart()
	_sparks.restart()
	# Vibración de la cámara si estás al lado (respeta la opción de accesibilidad).
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam is CameraRig and player_in_range():
		(cam as CameraRig).add_trauma(0.025)
	_launch_bead(type)
	crushed.emit(type)


## El maná de un cristal recorre la tubería brillando y entra en el Pilón.
func _launch_bead(type: ShardType) -> void:
	for i: int in BEADS:
		if _bead_t[i] < 0.0:
			_bead_t[i] = 0.0
			_bead_value[i] = type
			_beads[i].visible = true
			return
	if pylon:
		pylon.receive_mana(type)


func _update_beads(delta: float) -> void:
	var glow: float = 0.0
	for i: int in BEADS:
		if _bead_t[i] < 0.0:
			continue
		_bead_t[i] += delta / pipe_sec
		var k: float = clampf(_bead_t[i], 0.0, 1.0)
		_beads[i].position = Vector3(lerpf(-0.75, -1.85, k), 0.62 + sin(k * PI) * 0.05, 0.0)
		glow = maxf(glow, 1.0 - absf(k - 0.5))
		if k >= 1.0:
			_bead_t[i] = -1.0
			_beads[i].visible = false
			if pylon:
				pylon.receive_mana(_bead_value[i])
	_pipe_glow.albedo_color = Color(0.8, 0.5, 1.2).lerp(Color(1.6, 1.0, 2.0), glow)


func _update_pile() -> void:
	# El montón crece desde el fondo de la tolva: anillos que se van llenando.
	var shown: int = mini(_hopper.size(), PILE_MAX)
	_pile.multimesh.visible_instance_count = shown


## Coloca de antemano las piezas del montón (la tolva se llena de abajo arriba).
func _layout_pile() -> void:
	var mm: MultiMesh = _pile.multimesh
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i: int in PILE_MAX:
		var f: float = float(i) / float(PILE_MAX)
		var y: float = HOPPER_BOTTOM + 0.05 + f * (HOPPER_TOP - HOPPER_BOTTOM) * 0.55
		var r: float = lerpf(0.2, 0.62, (y - HOPPER_BOTTOM) / (HOPPER_TOP - HOPPER_BOTTOM))
		var a: float = rng.randf() * TAU
		var p := Vector3(cos(a), 0.0, sin(a)) * r * sqrt(rng.randf()) + Vector3.UP * y
		var basis := Basis.from_euler(
			Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU)
		)
		mm.set_instance_transform(
			i, Transform3D(basis.scaled(Vector3.ONE * rng.randf_range(0.7, 1.4)), p)
		)
	mm.visible_instance_count = 0


func _mesh(node_name: String, st: SurfaceTool, parent: Node3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = MeshKit.commit(st)
	mi.material_override = _toon
	parent.add_child(mi)
	return mi


func _build_frame() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var st: SurfaceTool = MeshKit.begin()
	# Peana de piedra, cuerpo de hierro con bandas de bronce y ventana de los rodillos.
	MeshKit.add_box(st, Vector3(0, 0.15, 0), Vector3(2.0, 0.3, 1.8), C_STONE)
	MeshKit.add_box(st, Vector3(0, 0.85, 0), Vector3(1.5, 1.1, 1.35), C_IRON, C_IRON_DARK)
	MeshKit.add_box(st, Vector3(0, 0.38, 0), Vector3(1.6, 0.1, 1.45), C_GOLD_DARK, C_GOLD)
	MeshKit.add_box(st, Vector3(0, 1.36, 0), Vector3(1.6, 0.1, 1.45), C_GOLD_DARK, C_GOLD)
	MeshKit.add_box(st, Vector3(0.76, 0.95, 0), Vector3(0.04, 0.62, 1.0), C_IRON_DARK)
	# Remaches.
	for z: float in [-0.6, -0.2, 0.2, 0.6]:
		MeshKit.add_box(st, Vector3(0.77, 1.36, z), Vector3(0.06, 0.06, 0.06), C_GOLD)
	# Chimenea de vapor.
	MeshKit.add_prism(
		st, Vector3(-0.5, 1.4, -0.42), Vector3.UP, 0.13, 1.25, 0.0, 8, C_IRON_DARK, C_IRON, rng
	)
	MeshKit.add_prism(
		st, Vector3(-0.5, 2.62, -0.42), Vector3.UP, 0.19, 0.12, 0.0, 8, C_GOLD_DARK, C_GOLD, rng
	)
	_mesh("Frame", st, _body)
	_window_light = OmniLight3D.new()
	_window_light.light_color = Color("#c79bff")
	_window_light.omni_range = 2.5
	_window_light.shadow_enabled = false
	_window_light.position = Vector3(1.1, 0.95, 0.0)
	_body.add_child(_window_light)


## Gear: disco con dientes alrededor (eje Z local).
func _gear_mesh(radius: float, teeth: int, thick: float, col: Color, col2: Color) -> SurfaceTool:
	var rng := RandomNumberGenerator.new()
	rng.seed = teeth
	var st: SurfaceTool = MeshKit.begin()
	MeshKit.add_prism(
		st, Vector3(0, 0, -thick * 0.5), Vector3.BACK, radius, thick, 0.0, 16, col, col2, rng
	)
	for k: int in teeth:
		var a: float = TAU * float(k) / float(teeth)
		var p := Vector3(cos(a), sin(a), 0.0) * (radius + 0.04)
		MeshKit.add_box(st, p, Vector3(0.08, 0.08, thick * 0.9), col)
	MeshKit.add_prism(
		st,
		Vector3(0, 0, -thick * 0.7),
		Vector3.BACK,
		radius * 0.25,
		thick * 1.4,
		0.0,
		8,
		C_IRON_DARK,
		C_GOLD,
		rng
	)
	return st


func _build_rollers_and_gears() -> void:
	# Rodillos dentados en la ventana delantera (eje X: se ven de frente, girando opuestos).
	for i: int in 2:
		var holder := Node3D.new()
		holder.name = "Roller%d" % i
		holder.position = Vector3(0.82, 0.95, -0.26 + i * 0.52)
		_body.add_child(holder)
		var st: SurfaceTool = _gear_mesh(0.22, 10, 0.18, Color("#8a90b0"), Color("#b6bbd6"))
		var mi: MeshInstance3D = _mesh("Mesh", st, holder)
		mi.rotation.y = PI * 0.5
		_rollers.append(holder)
	# Engranajes en el costado.
	for g: Array in [[Vector3(-0.1, 0.95, 0.72), 0.42, 14], [Vector3(0.42, 1.28, 0.72), 0.24, 9]]:
		var holder := Node3D.new()
		holder.name = "Gear"
		holder.position = g[0]
		_body.add_child(holder)
		_mesh("Mesh", _gear_mesh(float(g[1]), int(g[2]), 0.1, C_GOLD_DARK, C_GOLD), holder)
		_gears.append(holder)


func _build_hopper() -> void:
	# Tolva: pirámide invertida de bronce con la cara delantera de cristal (se ve el montón).
	var st: SurfaceTool = MeshKit.begin()
	var top: float = 0.7
	var bot: float = 0.28
	var yt: float = HOPPER_TOP
	var yb: float = HOPPER_BOTTOM
	var c := Vector3(0, (yt + yb) * 0.5, 0)
	var t0 := Vector3(-top, yt, -top)
	var t1 := Vector3(top, yt, -top)
	var t2 := Vector3(top, yt, top)
	var t3 := Vector3(-top, yt, top)
	var b0 := Vector3(-bot, yb, -bot)
	var b1 := Vector3(bot, yb, -bot)
	var b2 := Vector3(bot, yb, bot)
	var b3 := Vector3(-bot, yb, bot)
	MeshKit.add_quad(st, b0, b1, t1, t0, C_GOLD_DARK, c + Vector3(0, 0, 0.5))
	MeshKit.add_quad(st, b3, b0, t0, t3, C_GOLD_DARK, c + Vector3(0.5, 0, 0))
	MeshKit.add_quad(st, b2, b3, t3, t2, C_GOLD, c - Vector3(0, 0, 0.5))
	# Borde superior.
	MeshKit.add_box(st, Vector3(0, yt, -top), Vector3(top * 2.0 + 0.1, 0.08, 0.08), C_GOLD)
	MeshKit.add_box(st, Vector3(0, yt, top), Vector3(top * 2.0 + 0.1, 0.08, 0.08), C_GOLD)
	MeshKit.add_box(st, Vector3(-top, yt, 0), Vector3(0.08, 0.08, top * 2.0), C_GOLD)
	MeshKit.add_box(st, Vector3(top, yt, 0), Vector3(0.08, 0.08, top * 2.0), C_GOLD)
	var walls: MeshInstance3D = _mesh("Hopper", st, _body)
	walls.material_override = _toon.duplicate()
	(walls.material_override as ShaderMaterial).render_priority = 0
	# Cara delantera de cristal (transparente: no la perfila el contorno).
	var gst: SurfaceTool = MeshKit.begin()
	MeshKit.add_quad(gst, b1, b2, t2, t1, Color.WHITE, c - Vector3(0.5, 0, 0))
	MeshKit.add_quad(gst, b1, b2, t2, t1, Color.WHITE, c + Vector3(2.0, 0, 0))
	var glass := MeshInstance3D.new()
	glass.name = "HopperGlass"
	glass.mesh = MeshKit.commit(gst)
	var gm := ShaderMaterial.new()
	gm.shader = SHELL_SHADER
	glass.material_override = gm
	_body.add_child(glass)
	# El montón de cristales (un MultiMesh con piezas ya colocadas; se ven las primeras N).
	_pile = MultiMeshInstance3D.new()
	_pile.name = "Pile"
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = CrystalClusterBuilder.build_shard_mesh(ShardPool.TYPES[0], 5)
	mm.instance_count = PILE_MAX
	_pile.multimesh = mm
	var pm := ShaderMaterial.new()
	pm.shader = SHARD_SHADER
	_pile.material_override = pm
	_pile.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_body.add_child(_pile)
	_layout_pile()


func _build_lever() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var st: SurfaceTool = MeshKit.begin()
	MeshKit.add_box(st, Vector3(0.45, 0.95, -0.78), Vector3(0.3, 0.3, 0.12), C_IRON_DARK, C_GOLD)
	_mesh("LeverBase", st, _body)
	_lever = Node3D.new()
	_lever.name = "Lever"
	_lever.position = Vector3(0.45, 0.95, -0.86)
	_body.add_child(_lever)
	var lst: SurfaceTool = MeshKit.begin()
	MeshKit.add_prism(lst, Vector3.ZERO, Vector3.UP, 0.04, 0.75, 0.0, 6, C_WOOD, C_WOOD, rng)
	MeshKit.add_prism(lst, Vector3.UP * 0.72, Vector3.UP, 0.09, 0.12, 0.08, 8, C_RED, C_RED, rng)
	_mesh("Arm", lst, _lever)


func _build_pipe() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var st: SurfaceTool = MeshKit.begin()
	# Tubería de bronce de la máquina a la base del Pilón, con abrazaderas.
	MeshKit.add_prism(
		st, Vector3(-0.74, 0.62, 0), Vector3.LEFT, 0.12, 1.2, 0.0, 8, C_GOLD_DARK, C_GOLD, rng
	)
	for x: float in [-0.95, -1.4, -1.8]:
		MeshKit.add_prism(
			st, Vector3(x, 0.62, 0), Vector3.LEFT, 0.15, 0.06, 0.0, 8, C_GOLD, C_GOLD, rng
		)
	_mesh("Pipe", st, self)
	# Veta brillante de la tubería (late al pasar el maná) y gotas de maná que la recorren.
	var gst: SurfaceTool = MeshKit.begin()
	MeshKit.add_box(gst, Vector3(-1.32, 0.75, 0), Vector3(1.15, 0.03, 0.06), Color.WHITE)
	var glow := MeshInstance3D.new()
	glow.mesh = MeshKit.commit(gst)
	_pipe_glow = StandardMaterial3D.new()
	_pipe_glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_pipe_glow.albedo_color = Color(0.8, 0.5, 1.2)
	glow.material_override = _pipe_glow
	add_child(glow)
	var bead_mat := StandardMaterial3D.new()
	bead_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bead_mat.albedo_color = Color(1.6, 1.0, 2.2)
	var bead_mesh := SphereMesh.new()
	bead_mesh.radius = 0.09
	bead_mesh.height = 0.18
	bead_mesh.radial_segments = 6
	bead_mesh.rings = 3
	for i: int in BEADS:
		var b := MeshInstance3D.new()
		b.mesh = bead_mesh
		b.material_override = bead_mat
		b.visible = false
		b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(b)
		_beads.append(b)
		_bead_t.append(-1.0)
		_bead_value.append(null)


func _particles(
	amount: int, lifetime: float, colors: PackedColorArray, size: float
) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.one_shot = true
	p.explosiveness = 0.9
	p.emitting = false
	p.fixed_fps = 24
	p.local_coords = false
	p.top_level = true
	p.visibility_aabb = AABB(Vector3(-4, -4, -4), Vector3(8, 8, 8))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.15
	pm.direction = Vector3(1, 0.4, 0)
	pm.spread = 50.0
	pm.initial_velocity_min = 1.0
	pm.initial_velocity_max = 3.0
	pm.gravity = Vector3(0, -6.0, 0)
	var g := Gradient.new()
	g.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	var offs := PackedFloat32Array()
	for i: int in colors.size():
		offs.append(float(i) / float(colors.size()))
	g.offsets = offs
	g.colors = colors
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_initial_ramp = gt
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2.ONE * size
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = PixelTextures.star()
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	q.material = m
	p.draw_pass_1 = q
	add_child(p)
	return p


func _build_fx() -> void:
	# Polvo de cristal (cian y violeta) que salta de los rodillos.
	_dust = _particles(
		24, 0.6, PackedColorArray([Color("#c9f6ff"), Color("#a5dae5"), Color("#c79bff")]), 0.12
	)
	# Chispas naranjas del metal.
	_sparks = _particles(10, 0.35, PackedColorArray([Color("#ffd27a"), Color("#ff9a3a")]), 0.08)
	_sparks.global_position = global_position + Vector3(0.85, 0.95, 0.0)
	(_sparks.process_material as ParticleProcessMaterial).initial_velocity_max = 5.0
	# Vapor que sale de la chimenea al terminar.
	_steam = _particles(30, 1.4, PackedColorArray([Color("#f2f6ff"), Color("#d6dcf0")]), 0.45)
	_steam.global_position = global_position + Vector3(-0.5, 2.75, -0.42)
	var spm: ParticleProcessMaterial = _steam.process_material
	spm.direction = Vector3.UP
	spm.spread = 15.0
	spm.gravity = Vector3(0, 1.5, 0)
	spm.initial_velocity_min = 1.5
	spm.initial_velocity_max = 3.0
	spm.damping_min = 1.0
	spm.damping_max = 2.0
	_steam.explosiveness = 0.5


func _build_audio() -> void:
	for p: Array in [["Clink", 10.0], ["Crunch", 12.0], ["Fx", 14.0], ["Loop", 10.0]]:
		var a := AudioStreamPlayer3D.new()
		a.name = p[0]
		a.bus = &"SFX"
		a.unit_size = float(p[1])
		a.position = Vector3(0.5, 1.2, 0)
		add_child(a)
		match p[0]:
			"Clink":
				_clink_player = a
				var r := AudioStreamRandomizer.new()
				for s: AudioStream in CLINK_SFX:
					r.add_stream(-1, s)
				a.stream = r
				a.max_polyphony = 2
				a.volume_db = -11.0
			"Crunch":
				_crunch_player = a
				var r2 := AudioStreamRandomizer.new()
				for s: AudioStream in CRUNCH_SFX:
					r2.add_stream(-1, s)
				r2.random_volume_offset_db = 2.0
				a.stream = r2
				a.max_polyphony = 2
				a.volume_db = -8.0
			"Fx":
				_fx_player = a
				a.max_polyphony = 2
			"Loop":
				_loop_player = a
				a.stream = LOOP_SFX  # bucle activado en la importación


func _build_collision() -> void:
	var sb := StaticBody3D.new()
	sb.name = "Collision"
	sb.collision_layer = 1
	sb.collision_mask = 0
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.8, 2.2, 1.6)
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position.y = 1.1
	sb.add_child(col)
	add_child(sb)
