class_name DayNight
extends Node
## Ciclo de día y noche del valle y su paisaje sonoro.
## `time_of_day`: 0 = medianoche, 0,25 = amanecer, 0,5 = mediodía, 0,75 = atardecer.
## Mueve el sol y la luna, y reparte en el tiempo los colores del cielo, la luz, la niebla y el
## tinte de lo que no usa la luz del motor (el cristal y los fragmentos, por un parámetro global
## de shader). De noche avisa a los nodos del grupo `night_listeners` (`set_night(0..1)`):
## faroles, Pilón y Santuario se encienden.
## Sonido: de día el viento con pájaros y cantos sueltos en 3D (más al amanecer); de noche
## grillos, brisa y algún búho lejano. Todo espaciado y al azar para que nunca se repita.

const DAY_LOOP: AudioStream = preload("res://audio/sfx/amb_valley_loop.ogg")
const NIGHT_LOOP: AudioStream = preload("res://audio/sfx/amb_night_loop.ogg")
const BIRDS: Array[AudioStream] = [
	preload("res://audio/sfx/amb_bird_whistle_01.ogg"),
	preload("res://audio/sfx/amb_bird_whistle_02.ogg"),
	preload("res://audio/sfx/amb_bird_whistle_03.ogg"),
	preload("res://audio/sfx/amb_bird_trill_01.ogg"),
	preload("res://audio/sfx/amb_bird_trill_02.ogg"),
	preload("res://audio/sfx/amb_bird_trill_03.ogg"),
	preload("res://audio/sfx/amb_bird_warble_01.ogg"),
	preload("res://audio/sfx/amb_bird_warble_02.ogg"),
	preload("res://audio/sfx/amb_bird_warble_03.ogg"),
	preload("res://audio/sfx/amb_dove_01.ogg"),
]
const OWLS: Array[AudioStream] = [
	preload("res://audio/sfx/amb_owl_01.ogg"),
	preload("res://audio/sfx/amb_owl_02.ogg"),
]
## Mediodía: hacia dónde está el sol (arriba a la izquierda, como en la referencia).
const NOON_SUN := Vector3(-0.55, 0.65, 0.52)
## Fotogramas clave del día: [hora, cielo arriba, cielo medio, horizonte, nubes, color del sol,
## energía del sol, luz ambiente, energía ambiente, niebla, tinte del cristal, estrellas, noche].
const KEYS: Array[Array] = [
	[
		0.0,
		"#0b1033",
		"#16205a",
		"#2b3b7a",
		"#5a6290",
		"#000000",
		0.0,
		"#5a6bcc",
		0.32,
		"#141a3a",
		"#6b7abf",
		1.0,
		1.0
	],
	[
		0.2,
		"#141a4a",
		"#3a2f6a",
		"#7a4f7a",
		"#8a7095",
		"#000000",
		0.0,
		"#6a6ab0",
		0.32,
		"#3a2f55",
		"#8a85b8",
		0.7,
		0.9
	],
	[
		0.26,
		"#3a4fa8",
		"#b86a9a",
		"#ffb37a",
		"#ffb7a5",
		"#ff9a66",
		0.7,
		"#b39ac9",
		0.36,
		"#d99a90",
		"#f2c2bf",
		0.15,
		0.45
	],
	[
		0.33,
		"#2a54c6",
		"#3978da",
		"#a7cbd3",
		"#ffffff",
		"#fff2d9",
		1.5,
		"#8c9ee6",
		0.36,
		"#a8c7e6",
		"#ffffff",
		0.0,
		0.0
	],
	[
		0.5,
		"#1f47b8",
		"#3374d6",
		"#a0c8d6",
		"#ffffff",
		"#fff7e6",
		1.75,
		"#8c9ee6",
		0.34,
		"#a8c7e6",
		"#ffffff",
		0.0,
		0.0
	],
	[
		0.68,
		"#2a54c6",
		"#3a78d8",
		"#b4cdd0",
		"#fff6ea",
		"#ffe6c2",
		1.5,
		"#9a9ee0",
		0.35,
		"#b4c4dc",
		"#fff8f0",
		0.0,
		0.0
	],
	[
		0.75,
		"#3a3f8f",
		"#c76a7a",
		"#ff9a4d",
		"#ffad85",
		"#ff8a40",
		0.85,
		"#c39ab8",
		0.36,
		"#e0957a",
		"#ffcfb0",
		0.1,
		0.5
	],
	[
		0.8,
		"#141a4f",
		"#4a2f6a",
		"#8a4f7a",
		"#806a95",
		"#7a3a50",
		0.1,
		"#6a6ab8",
		0.33,
		"#3a2f55",
		"#9a8fc4",
		0.6,
		0.9
	],
	[
		1.0,
		"#0b1033",
		"#16205a",
		"#2b3b7a",
		"#5a6290",
		"#000000",
		0.0,
		"#5a6bcc",
		0.32,
		"#141a3a",
		"#6b7abf",
		1.0,
		1.0
	],
]

## Duración de un día completo (s).
@export var day_length_sec: float = 600.0
## Hora al empezar (media mañana).
@export_range(0.0, 1.0) var time_of_day: float = 0.33

var night: float = 0.0

var _sun: DirectionalLight3D
var _moon: DirectionalLight3D
var _env: Environment
var _sky: ShaderMaterial
var _day_amb: AudioStreamPlayer
var _night_amb: AudioStreamPlayer
var _oneshots: Array[AudioStreamPlayer3D] = []
var _next_call: float = 4.0
var _rng := RandomNumberGenerator.new()


## `sun`: la luz principal del valle; `env`: su entorno (cielo, ambiente y niebla).
func setup(sun: DirectionalLight3D, env: Environment) -> void:
	_rng.randomize()
	_sun = sun
	_env = env
	_sky = env.sky.sky_material as ShaderMaterial
	_moon = DirectionalLight3D.new()
	_moon.name = "Moon"
	_moon.light_color = Color("#9fb4ff")
	_moon.shadow_enabled = false
	sun.get_parent().add_child(_moon)
	_day_amb = _loop_player(DAY_LOOP)
	_night_amb = _loop_player(NIGHT_LOOP)
	for i: int in 3:
		var p := AudioStreamPlayer3D.new()
		p.bus = &"Ambience"
		p.unit_size = 18.0
		p.max_distance = 120.0
		p.attenuation_filter_cutoff_hz = 6000.0
		add_child(p)
		_oneshots.append(p)
	_apply()


func _loop_player(stream: AudioStream) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = &"Ambience"
	p.stream = stream  # bucle activado en la importación
	p.volume_db = -60.0
	add_child(p)
	p.play()
	return p


func _process(delta: float) -> void:
	if _sun == null:
		return
	time_of_day = fposmod(time_of_day + delta / day_length_sec, 1.0)
	_apply()
	_update_sounds(delta)


func _unhandled_input(event: InputEvent) -> void:
	if (
		OS.is_debug_build()
		and event is InputEventKey
		and (event as InputEventKey).pressed
		and not (event as InputEventKey).echo
		and (event as InputEventKey).physical_keycode == KEY_N
	):
		# Debug: N adelanta la hora.
		time_of_day = fposmod(time_of_day + 0.05, 1.0)


func _apply() -> void:
	var k: Array = _sample(time_of_day)
	var sun_to: Vector3 = _sun_dir(time_of_day)
	var moon_to: Vector3 = -sun_to
	# Luces: el sol se apaga bajo el horizonte; la luna toma el relevo.
	_sun.light_color = k[5]
	_sun.light_energy = float(k[6]) * smoothstep(-0.05, 0.12, sun_to.y)
	_sun.visible = _sun.light_energy > 0.01
	if _sun.visible:
		_sun.look_at_from_position(Vector3.ZERO, -sun_to, Vector3.UP)
	_moon.light_energy = 0.32 * smoothstep(-0.05, 0.2, moon_to.y)
	_moon.visible = _moon.light_energy > 0.01
	if _moon.visible:
		_moon.look_at_from_position(Vector3.ZERO, -moon_to, Vector3.UP)
	_env.ambient_light_color = k[7]
	_env.ambient_light_energy = k[8]
	_env.fog_light_color = k[9]
	_sky.set_shader_parameter("top_color", k[1])
	_sky.set_shader_parameter("mid_color", k[2])
	_sky.set_shader_parameter("horizon_color", k[3])
	_sky.set_shader_parameter("cloud_tint", k[4])
	_sky.set_shader_parameter("sun_dir", sun_to)
	_sky.set_shader_parameter("sun_color", (k[5] as Color).lightened(0.3))
	_sky.set_shader_parameter("moon_dir", moon_to)
	_sky.set_shader_parameter("stars", k[11])
	RenderingServer.global_shader_parameter_set(&"world_tint", k[10])
	var n: float = k[12]
	if absf(n - night) > 0.005:
		night = n
		get_tree().call_group(&"night_listeners", &"set_night", night)


## Dirección hacia el sol: gira alrededor de un eje horizontal y pasa a mediodía por NOON_SUN.
func _sun_dir(t: float) -> Vector3:
	var noon: Vector3 = NOON_SUN.normalized()
	var flat := Vector3(noon.x, 0.0, noon.z).normalized()
	var axis: Vector3 = flat.cross(Vector3.UP).normalized()
	return noon.rotated(axis, (t - 0.5) * TAU)


## Interpola los fotogramas clave en `t`. Devuelve los valores ya convertidos.
func _sample(t: float) -> Array:
	var a: Array = KEYS[0]
	var b: Array = KEYS[KEYS.size() - 1]
	for i: int in KEYS.size() - 1:
		if t >= float(KEYS[i][0]) and t <= float(KEYS[i + 1][0]):
			a = KEYS[i]
			b = KEYS[i + 1]
			break
	var f: float = inverse_lerp(float(a[0]), float(b[0]), t)
	f = f * f * (3.0 - 2.0 * f)
	var out: Array = [t]
	for j: int in range(1, a.size()):
		if a[j] is String:
			out.append(Color(a[j] as String).lerp(Color(b[j] as String), f))
		else:
			out.append(lerpf(float(a[j]), float(b[j]), f))
	return out


func _update_sounds(delta: float) -> void:
	# Bucles: el viento con pájaros de día y los grillos de noche, con fundido cruzado.
	_day_amb.volume_db = lerpf(-10.0, -40.0, night)
	_night_amb.volume_db = lerpf(-40.0, -9.0, night)
	_next_call -= delta
	if _next_call > 0.0:
		return
	var player: Node3D = get_tree().get_first_node_in_group(&"player") as Node3D
	if player == null:
		_next_call = 2.0
		return
	var dawn: float = 1.0 - clampf(absf(time_of_day - 0.28) / 0.08, 0.0, 1.0)
	var stream: AudioStream
	var volume: float
	if night > 0.6:
		# Noche: algún búho, muy de vez en cuando.
		stream = OWLS[_rng.randi() % OWLS.size()]
		volume = _rng.randf_range(-12.0, -6.0)
		_next_call = _rng.randf_range(14.0, 32.0)
	else:
		stream = BIRDS[_rng.randi() % BIRDS.size()]
		volume = _rng.randf_range(-16.0, -7.0)
		# Al amanecer, el coro: más cantos y más seguidos.
		_next_call = _rng.randf_range(2.5, 8.0) * lerpf(1.0, 0.4, dawn) * lerpf(1.0, 2.5, night)
	var p: AudioStreamPlayer3D = _oneshots[_rng.randi() % _oneshots.size()]
	if p.playing:
		return
	var a: float = _rng.randf() * TAU
	var dist: float = _rng.randf_range(22.0, 45.0)
	p.global_position = (
		player.global_position + Vector3(cos(a) * dist, _rng.randf_range(6.0, 12.0), sin(a) * dist)
	)
	p.stream = stream
	p.volume_db = volume
	p.pitch_scale = _rng.randf_range(0.93, 1.07)
	p.play()
