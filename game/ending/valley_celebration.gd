class_name ValleyCelebration
extends Node3D
## El valle celebra el final (GDD 9): "el Pilón llega al 100 % y libera una columna de maná que
## atraviesa las nubes; el cielo entero se llena de auroras y la aldea celebra".
## - Columna de maná: el haz de los hitos del Pilón (pylon_pillar.gdshader), mucho más alto y
##   ancho, que sube y abre un agujero con un anillo de luz en las nubes (sky.gdshader).
## - Fuegos artificiales sobre los barrios de la aldea y el castillo (cohete con estela, palmera de
##   chispas de colores, destello, estallido y crepitar), en un pool.
## - Farolillos que suben al cielo desde la aldea, campanas que repican, coro y bichos que bailan.
## Se queda encendido para siempre (también al volver a cargar la partida terminada).

const PILLAR_SHADER: Shader = preload("res://pylon/pylon_pillar.gdshader")
const GLOW_SHADER: Shader = preload("res://fx/hd/hd_glow.gdshader")
const COLUMN_SFX: AudioStream = preload("res://audio/sfx/sfx_mana_column_01.ogg")
const LAUNCH_SFX: AudioStream = preload("res://audio/sfx/sfx_firework_launch_01.ogg")
const POP_SFX: Array[AudioStream] = [
	preload("res://audio/sfx/sfx_firework_pop_01.ogg"),
	preload("res://audio/sfx/sfx_firework_pop_02.ogg"),
	preload("res://audio/sfx/sfx_firework_pop_03.ogg"),
]
const BELLS_SFX: AudioStream = preload("res://audio/sfx/sfx_bells_peal_01.ogg")
const CHOIR_SFX: AudioStream = preload("res://audio/sfx/sfx_choir_celebrate_01.ogg")
const COLUMN_HEIGHT: float = 900.0
const CLOUD_HOLE_HEIGHT: float = 95.0
const FIREWORKS: int = 8
const ROCKET_SEC: float = 1.5
## Colores de las palmeras (los de la magia del juego).
const COLORS: PackedColorArray = [
	Color(2.2, 1.0, 2.4),
	Color(0.7, 1.8, 2.4),
	Color(2.4, 1.9, 0.6),
	Color(2.4, 0.9, 1.6),
	Color(1.0, 2.2, 1.3),
	Color(2.4, 1.3, 0.5),
]
## Dónde están los campanarios (los de ValleyMilestones) y desde dónde salen cohetes.
const LAUNCH_SITES: Array[Vector3] = [
	Vector3(-130, 0, -30), Vector3(-85, 0, -105), Vector3(75, 0, -135), Vector3(85, 0, -215)
]
## Más cohetes desde el borde del claro (se ven mires a donde mires).
const CLEARING_SITES: Array[Vector3] = [
	Vector3(-95, 0, 45), Vector3(95, 0, 20), Vector3(10, 0, -110), Vector3(-40, 0, 135)
]

var started: bool = false

var _column: MeshInstance3D
var _column_mat: ShaderMaterial
var _crown: MeshInstance3D
var _crown_mat: ShaderMaterial
var _column_t: float = -1.0
var _sky: ShaderMaterial
var _rockets: Array[MeshInstance3D] = []
var _rocket_trails: Array[SpellTrail] = []
var _bursts: Array[GPUParticles3D] = []
var _burst_glows: Array[MeshInstance3D] = []
var _fw_t: PackedFloat32Array = []
var _fw_from: PackedVector3Array = []
var _fw_to: PackedVector3Array = []
var _fw_next: int = 0
var _next_launch: float = 0.0
var _volley: int = 0
var _bells_t: float = 3.0
var _dance_t: float = 1.0
var _lanterns: Array[GPUParticles3D] = []
var _launch_player: AudioStreamPlayer3D
var _pop_players: Array[AudioStreamPlayer3D] = []
var _bell_players: Array[AudioStreamPlayer3D] = []
var _pylon_at: Vector3 = Vector3.ZERO
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_build_column()
	_build_fireworks()
	_build_lanterns()
	_build_audio()
	set_process(false)


## `pylon_top`: lo alto del Pilón (de ahí sale la columna); `sky`: material del cielo.
func setup(pylon_top: Vector3, sky: ShaderMaterial) -> void:
	_pylon_at = pylon_top
	_sky = sky
	_column.global_position = pylon_top + Vector3.UP * COLUMN_HEIGHT * 0.5
	_crown.global_position = pylon_top + Vector3.UP * 1.0


## La columna sube del Pilón al cielo. `instant`: ya está (partida cargada).
func raise_column(instant: bool = false) -> void:
	_column.visible = true
	_crown.visible = true
	_column_t = 10.0 if instant else 0.0
	if not instant:
		AudioDirector.play_sfx(COLUMN_SFX, 0.0)
	set_process(true)


## Empieza la fiesta: fuegos, farolillos, campanas, coro. `instant`: sin la primera traca.
func start(instant: bool = false) -> void:
	started = true
	for l: GPUParticles3D in _lanterns:
		l.emitting = true
		if instant:
			l.preprocess = 30.0
	_volley = 0 if instant else 6
	_next_launch = 0.0
	_bells_t = 0.0 if not instant else 4.0
	if not instant:
		AudioDirector.play_sfx(CHOIR_SFX, -3.0)
	set_process(true)


func _build_column() -> void:
	var cyl := CylinderMesh.new()
	cyl.top_radius = 16.0
	cyl.bottom_radius = 3.6
	cyl.height = COLUMN_HEIGHT
	cyl.radial_segments = 20
	cyl.rings = 1
	cyl.cap_top = false
	cyl.cap_bottom = false
	_column = MeshInstance3D.new()
	_column.name = "ManaColumn"
	_column.mesh = cyl
	_column_mat = ShaderMaterial.new()
	_column_mat.shader = PILLAR_SHADER
	_column_mat.render_priority = 3
	_column_mat.set_shader_parameter("height", COLUMN_HEIGHT)
	_column_mat.set_shader_parameter("color_core", Color(1.0, 0.88, 1.0))
	_column.material_override = _column_mat
	_column.layers = MagicLayer.MAGIC_LAYER
	_column.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_column.extra_cull_margin = 100.0
	_column.top_level = true
	_column.visible = false
	add_child(_column)
	_crown = HdFx.quad(GLOW_SHADER, 16.0, 4)
	_crown.name = "ColumnBase"
	_crown_mat = _crown.material_override
	_crown_mat.set_shader_parameter("color", Color(0.85, 0.65, 1.0))
	_crown_mat.set_shader_parameter("rays", 1.0)
	_crown_mat.set_shader_parameter("ray_count", 10.0)
	_crown_mat.set_shader_parameter("cover", 0.1)
	_crown.top_level = true
	_crown.visible = false
	add_child(_crown)


func _build_fireworks() -> void:
	for i: int in FIREWORKS:
		var rocket: MeshInstance3D = HdFx.quad(GLOW_SHADER, 2.2, 5)
		rocket.name = "Rocket%d" % i
		var rm: ShaderMaterial = rocket.material_override
		rm.set_shader_parameter("color", Color(1.0, 0.85, 0.6))
		rm.set_shader_parameter("intensity", 2.0)
		rocket.top_level = true
		rocket.visible = false
		add_child(rocket)
		_rockets.append(rocket)
		var trail := SpellTrail.new()
		trail.hd = true
		trail.name = "RocketTrail%d" % i
		trail.width = 0.7
		trail.length_sec = 0.5
		# La estela sigue sola a su padre (el cohete).
		rocket.add_child(trail)
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 1.0])
		g.colors = PackedColorArray([Color(2.0, 1.6, 1.0), Color(1.0, 0.4, 0.2, 0.0)])
		trail.set_ramp(g)
		_rocket_trails.append(trail)
		var burst: GPUParticles3D = HdFx.sparks(170, 34.0, 1.3, PackedColorArray([COLORS[0]]))
		burst.name = "Burst%d" % i
		burst.lifetime = 2.6
		burst.trail_lifetime = 0.35
		burst.top_level = true
		burst.visibility_aabb = AABB(Vector3(-100, -100, -100), Vector3(200, 200, 200))
		var pm: ParticleProcessMaterial = burst.process_material
		pm.gravity = Vector3(0, -5.0, 0)
		pm.damping_min = 6.0
		pm.damping_max = 9.0
		pm.initial_velocity_min = 28.0
		pm.initial_velocity_max = 36.0
		pm.emission_sphere_radius = 0.5
		add_child(burst)
		_bursts.append(burst)
		var glow: MeshInstance3D = HdFx.quad(GLOW_SHADER, 40.0, 4)
		glow.name = "BurstGlow%d" % i
		glow.top_level = true
		glow.visible = false
		(glow.material_override as ShaderMaterial).set_shader_parameter("cover", 0.05)
		add_child(glow)
		_burst_glows.append(glow)
		_fw_t.append(-1.0)
		_fw_from.append(Vector3.ZERO)
		_fw_to.append(Vector3.ZERO)


## Farolillos de papel que suben desde cada barrio de la aldea.
func _build_lanterns() -> void:
	for site: Vector3 in LAUNCH_SITES:
		var p := GPUParticles3D.new()
		p.name = "SkyLanterns"
		p.amount = 40
		p.lifetime = 45.0
		p.local_coords = false
		p.emitting = false
		p.layers = MagicLayer.MAGIC_LAYER
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		p.visibility_aabb = AABB(Vector3(-60, -10, -60), Vector3(120, 200, 120))
		var pm := ParticleProcessMaterial.new()
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		pm.emission_box_extents = Vector3(26, 1, 26)
		pm.direction = Vector3.UP
		pm.spread = 12.0
		pm.initial_velocity_min = 1.6
		pm.initial_velocity_max = 3.0
		pm.gravity = Vector3(0.6, 0.15, 0.2)
		pm.turbulence_enabled = true
		pm.turbulence_noise_strength = 0.6
		pm.turbulence_noise_scale = 6.0
		pm.color_ramp = HdFx.color_ramp(
			PackedColorArray(
				[
					Color(2.2, 1.2, 0.5),
					Color(2.2, 1.1, 0.6),
					Color(2.0, 0.8, 1.2),
					Color(1, 0.5, 0.6)
				]
			)
		)
		p.process_material = pm
		var q := QuadMesh.new()
		q.size = Vector2.ONE * 2.2
		q.material = HdFx.additive_particle_material(1.4)
		p.draw_pass_1 = q
		p.position = Vector3(site.x, Valley.ground_height(site.x, site.z) + 6.0, site.z)
		add_child(p)
		_lanterns.append(p)


func _build_audio() -> void:
	_launch_player = AudioStreamPlayer3D.new()
	_launch_player.bus = &"SFX"
	_launch_player.stream = LAUNCH_SFX
	_launch_player.unit_size = 60.0
	_launch_player.max_distance = 600.0
	_launch_player.max_polyphony = 3
	add_child(_launch_player)
	var pops := AudioStreamRandomizer.new()
	for s: AudioStream in POP_SFX:
		pops.add_stream(-1, s)
	pops.random_pitch = 1.15
	for i: int in 3:
		var p := AudioStreamPlayer3D.new()
		p.bus = &"SFX"
		p.stream = pops
		p.unit_size = 90.0
		p.max_distance = 900.0
		p.max_polyphony = 2
		add_child(p)
		_pop_players.append(p)
	for site: Vector3 in LAUNCH_SITES:
		var b := AudioStreamPlayer3D.new()
		b.bus = &"Ambience"
		b.stream = BELLS_SFX
		b.unit_size = 70.0
		b.max_distance = 800.0
		b.volume_db = -2.0
		b.position = site + Vector3.UP * 10.0
		add_child(b)
		_bell_players.append(b)


func _process(delta: float) -> void:
	_update_column(delta)
	if not started:
		return
	_update_fireworks(delta)
	_bells_t -= delta
	if _bells_t <= 0.0:
		_bells_t = _rng.randf_range(18.0, 30.0)
		var b: AudioStreamPlayer3D = _bell_players[_rng.randi() % _bell_players.size()]
		b.pitch_scale = _rng.randf_range(0.97, 1.03)
		b.play()
	_dance_t -= delta
	if _dance_t <= 0.0:
		_dance_t = _rng.randf_range(0.8, 2.2)
		var herd: CritterHerd = CritterHerd.instance()
		if herd:
			var list: Array[Critter] = herd.critters()
			if not list.is_empty():
				list[_rng.randi() % list.size()].force_emote(Critter.Emote.DANCE)


func _update_column(delta: float) -> void:
	if _column_t < 0.0:
		return
	_column_t += delta
	var rise: float = smoothstep(0.0, 1.6, _column_t)
	_column_mat.set_shader_parameter("reach", rise)
	var shimmer: float = 0.9 + 0.1 * sin(_column_t * 3.0)
	_column_mat.set_shader_parameter(
		"intensity", lerpf(1.4, 0.85, smoothstep(0.0, 4.0, _column_t)) * shimmer
	)
	_crown_mat.set_shader_parameter("intensity", (1.2 + 0.3 * sin(_column_t * 2.0)) * rise)
	# El agujero en las nubes, en la dirección en la que se ve la columna desde la cámara.
	var cam: Camera3D = get_viewport().get_camera_3d()
	if _sky and cam:
		# Las nubes del cielo están "en el infinito": el agujero va donde la columna se ve a la
		# altura de las nubes bajas.
		var top: Vector3 = _pylon_at + Vector3.UP * CLOUD_HOLE_HEIGHT
		_sky.set_shader_parameter("hole_dir", (top - cam.global_position).normalized())
		var open: float = smoothstep(1.0, 2.4, _column_t)
		_sky.set_shader_parameter("hole_size", lerpf(1.0, 0.982, open) if open > 0.0 else 0.0)


func _update_fireworks(delta: float) -> void:
	_next_launch -= delta
	if _next_launch <= 0.0:
		_launch()
		if _volley > 0:
			_volley -= 1
			_next_launch = _rng.randf_range(0.15, 0.4)
		else:
			_next_launch = _rng.randf_range(1.2, 3.2)
	for i: int in FIREWORKS:
		if _fw_t[i] < 0.0:
			continue
		_fw_t[i] += delta
		var t: float = _fw_t[i]
		if t < ROCKET_SEC:
			var k: float = t / ROCKET_SEC
			var p: Vector3 = _fw_from[i].lerp(_fw_to[i], 1.0 - (1.0 - k) * (1.0 - k))
			_rockets[i].global_position = p
		elif _rockets[i].visible:
			_explode(i)
		else:
			var g: float = clampf((t - ROCKET_SEC) / 0.7, 0.0, 1.0)
			var gm: ShaderMaterial = _burst_glows[i].material_override
			gm.set_shader_parameter("intensity", 1.4 * (1.0 - g) * (1.0 - g) * HdFx.flash_scale)
			_burst_glows[i].visible = g < 1.0
			if t > ROCKET_SEC + 3.0:
				_fw_t[i] = -1.0


func _launch() -> void:
	var i: int = _fw_next
	_fw_next = (_fw_next + 1) % FIREWORKS
	if _fw_t[i] >= 0.0 and _fw_t[i] < ROCKET_SEC + 1.0:
		return
	var site: Vector3 = (
		LAUNCH_SITES[_rng.randi() % LAUNCH_SITES.size()]
		if _rng.randf() < 0.55
		else CLEARING_SITES[_rng.randi() % CLEARING_SITES.size()]
	)
	var from := site + Vector3(_rng.randf_range(-20, 20), 0.0, _rng.randf_range(-20, 20))
	from.y = Valley.ground_height(from.x, from.z) + 2.0
	_fw_from[i] = from
	_fw_to[i] = (
		from
		+ Vector3(
			_rng.randf_range(-12, 12), _rng.randf_range(70.0, 120.0), _rng.randf_range(-12, 12)
		)
	)
	_fw_t[i] = 0.0
	_rockets[i].visible = true
	_rockets[i].global_position = from
	_rocket_trails[i].start(from)
	_launch_player.global_position = from
	_launch_player.pitch_scale = _rng.randf_range(0.9, 1.15)
	_launch_player.play()


func _explode(i: int) -> void:
	_rockets[i].visible = false
	_rocket_trails[i].stop()
	var at: Vector3 = _fw_to[i]
	var col: Color = COLORS[_rng.randi() % COLORS.size()]
	var col2: Color = COLORS[_rng.randi() % COLORS.size()]
	var b: GPUParticles3D = _bursts[i]
	b.global_position = at
	var pm: ParticleProcessMaterial = b.process_material
	pm.color_ramp = HdFx.color_ramp(PackedColorArray([Color(2.6, 2.5, 2.6), col, col2]))
	b.restart()
	var glow: MeshInstance3D = _burst_glows[i]
	glow.global_position = at
	glow.visible = true
	(glow.material_override as ShaderMaterial).set_shader_parameter("color", col * 0.5)
	var p: AudioStreamPlayer3D = _pop_players[i % _pop_players.size()]
	p.global_position = at
	p.play()
