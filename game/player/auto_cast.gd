class_name AutoCast
extends Node
## Lanzamiento continuo (nodo hito de la Canalización, GDD 7: "lanzamiento continuo al mantener
## pulsado"). Con `autocast` inscrito, mantener un botón más de `autocast_hold_sec` deja esa mano
## en ráfaga: lanza sola cada vez que recarga (la recarga y el buffer de siempre marcan el
## ritmo, así que no lanza más deprisa que el mejor clic) hasta que se suelta. El primer clic
## sale como siempre: clicar no cambia nada.
##
## Mientras dura, la mano tiembla, crepita (bucle de chasquidos y chispas HD en su llama) y el
## orbe late con cada lanzamiento.
##
## Combinar no se estropea: dos clics a la vez siguen juntando las manos (SpellCaster); con una
## mano en ráfaga, pulsar la otra junta las dos en cuanto estén listas (`JOIN`) en vez de soltar
## un disparo; y un botón que sigue pulsado tras un combinado no vuelve a la ráfaga hasta que se
## pulsa otra vez. "Clic para cargar" (Opciones) no cambia: la ráfaga es de los disparos sueltos.
## Lo crea SpellCaster, que le pasa los botones y lo consulta en su _process (`tick`).

## Bits que devuelve `tick`: la mano izquierda, la derecha (lanzar en cuanto se pueda) y juntar.
const LEFT: int = 1
const RIGHT: int = 2
const JOIN: int = 4
const UPGRADE: StringName = &"autocast"
const LOOP_SFX: AudioStream = preload("res://audio/sfx/amb_autocast_crackle_loop.ogg")
const START_SFX: AudioStream = preload("res://audio/sfx/sfx_autocast_start_01.ogg")
const PULSE_SFX: Array[AudioStream] = [
	preload("res://audio/sfx/sfx_autocast_pulse_01.ogg"),
	preload("res://audio/sfx/sfx_autocast_pulse_02.ogg"),
	preload("res://audio/sfx/sfx_autocast_pulse_03.ogg"),
]
## Volumen del crepitar: apagado, una mano y las dos.
const LOOP_DB := Vector3(-36.0, -12.0, -9.0)
const LOOP_GLIDE_DB: float = 60.0
## Lo que tarda el temblor en llegar (1/s) y lo que lanza la mano en el aire (empujón).
const TREMBLE_RISE: float = 6.0

var caster: SpellCaster
var camera: Camera3D
var hands: WizardHands
## Mano en ráfaga ahora mismo (mirilla, pruebas y demo).
var channeling: Array[bool] = [false, false]

var _held: Array[bool] = [false, false]
## Un botón vale para la ráfaga desde que se pulsa hasta que se suelta o entra en un combinado.
var _armed: Array[bool] = [false, false]
var _held_t: PackedFloat32Array = PackedFloat32Array([0.0, 0.0])
var _loop: AudioStreamPlayer
var _pulse_random: AudioStreamRandomizer
## Chispas continuas en cada llama y estallido pequeño al lanzar (capa de magia HD).
var _crackle: Array[GPUParticles3D] = []
var _burst: Array[GPUParticles3D] = []


func _ready() -> void:
	_loop = AudioStreamPlayer.new()
	_loop.name = "CrackleLoop"
	_loop.bus = &"SFX"
	_loop.stream = LOOP_SFX  # bucle activado en la importación
	_loop.volume_db = LOOP_DB.x
	add_child(_loop)
	_pulse_random = AudioStreamRandomizer.new()
	for s: AudioStream in PULSE_SFX:
		_pulse_random.add_stream(-1, s)
	_pulse_random.random_pitch = 1.1
	Events.spell_cast.connect(_on_spell_cast)
	Events.spell_combine_started.connect(func(_r: SpellRecipe) -> void: _disarm())
	Events.menu_opened.connect(clear)
	Events.grimoire_opened.connect(clear)
	_build_fx.call_deferred()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		clear()


## Se pulsa el botón de una mano (0 izquierda, 1 derecha).
func press(side: int) -> void:
	_held[side] = true
	_armed[side] = true
	_held_t[side] = 0.0


func release(side: int) -> void:
	_held[side] = false
	_armed[side] = false


## Se sueltan los dos (menú, Grimorio, foco perdido: el botón se suelta fuera del juego).
func clear() -> void:
	for side: int in 2:
		release(side)


## True si al pulsar `side` la otra mano ya se mantiene: se juntarán en cuanto estén listas, así
## que no hay que lanzar `side` suelta.
func joins(side: int) -> bool:
	return GameState.has_upgrade(UPGRADE) and _held[1 - side] and _armed[1 - side]


## Un fotograma: qué manos lanzan solas (LEFT, RIGHT) y si toca juntarlas (JOIN).
func tick(delta: float, combining: bool) -> int:
	var owned: bool = GameState.has_upgrade(UPGRADE)
	var both: bool = _held[0] and _held[1] and _armed[0] and _armed[1]
	var out: int = 0
	for side: int in 2:
		if _held[side]:
			_held_t[side] += delta
		var on: bool = (
			owned
			and _armed[side]
			and _held_t[side] >= GameState.BALANCE.autocast_hold_sec
			and not combining
			and not both
		)
		if on and not channeling[side]:
			AudioDirector.play_sfx(START_SFX, -9.0, 1.0 + 0.06 * side)
		channeling[side] = on
		if on:
			out |= LEFT if side == 0 else RIGHT
	if owned and both and not combining:
		out |= JOIN
	_feedback(delta)
	return out


func _disarm() -> void:
	for side: int in 2:
		_armed[side] = false
		channeling[side] = false


## Cada lanzamiento en ráfaga: el orbe late, chispas en la mano y un "tic" eléctrico suave.
func _on_spell_cast(_tier: SpellTier, side: int) -> void:
	if side > 1 or not channeling[side]:
		return
	AudioDirector.play_sfx(_pulse_random, -14.0, 1.0 + 0.08 * side)
	if side < _burst.size():
		_place(_burst[side], side)
		_burst[side].restart()
	if camera is CameraRig:
		(camera as CameraRig).punch_fov(-0.35)


func _feedback(delta: float) -> void:
	if hands == null and caster:
		hands = caster.hands  # el mago se las da al SpellCaster después de crearlo
	var n: int = int(channeling[0]) + int(channeling[1])
	var target: float = LOOP_DB.x if n == 0 else (LOOP_DB.y if n == 1 else LOOP_DB.z)
	_loop.volume_db = move_toward(_loop.volume_db, target, delta * LOOP_GLIDE_DB)
	if n > 0 and not _loop.playing:
		_loop.play()
	elif n == 0 and _loop.playing and _loop.volume_db <= LOOP_DB.x + 0.1:
		_loop.stop()
	_loop.pitch_scale = 1.0 + 0.08 * float(n - 1)
	for side: int in 2:
		if hands:
			var k: float = 1.0 if channeling[side] else 0.0
			hands.tremble[side] = move_toward(hands.tremble[side], k, delta * TREMBLE_RISE)
		if side < _crackle.size():
			var p: GPUParticles3D = _crackle[side]
			p.emitting = channeling[side]
			if channeling[side]:
				_place(p, side)
				_tint(p, side)


## La llama de la mano en el mundo (las partículas van con la cámara).
func _place(p: GPUParticles3D, side: int) -> void:
	if hands == null or camera == null:
		return
	var depth: float = WizardHands.orb_depth(camera)
	var world: Vector3 = camera.project_position(hands.palm_screen_position(side), depth)
	p.position = camera.to_local(world)


## Las chispas llevan el color del hechizo de esa mano.
func _tint(p: GPUParticles3D, side: int) -> void:
	if caster == null:
		return
	var glow: Color = caster.tier_for(side).color_glow
	var pm: ParticleProcessMaterial = p.process_material
	pm.color = Color(glow.r * 1.6, glow.g * 1.6, glow.b * 1.6)


func _build_fx() -> void:
	if camera == null:
		return
	var cols := PackedColorArray([Color(2.4, 2.3, 2.6), Color(1.6, 1.4, 2.2), Color(0.7, 0.6, 1.6)])
	for side: int in 2:
		var c: GPUParticles3D = HdFx.sparks(40, 0.7, 0.007, cols)
		c.name = "Crackle%d" % side
		c.one_shot = false
		c.explosiveness = 0.0
		c.lifetime = 0.18
		c.local_coords = true
		c.trail_lifetime = 0.04
		var pm: ParticleProcessMaterial = c.process_material
		pm.gravity = Vector3.ZERO
		pm.emission_sphere_radius = 0.05
		pm.turbulence_enabled = true
		pm.turbulence_noise_strength = 6.0
		pm.turbulence_noise_scale = 0.4
		camera.add_child(c)
		_crackle.append(c)
		var b: GPUParticles3D = HdFx.sparks(20, 0.9, 0.009, cols)
		b.name = "CastPulse%d" % side
		b.lifetime = 0.2
		b.trail_lifetime = 0.05
		b.local_coords = true
		(b.process_material as ParticleProcessMaterial).gravity = Vector3.ZERO
		camera.add_child(b)
		_burst.append(b)
