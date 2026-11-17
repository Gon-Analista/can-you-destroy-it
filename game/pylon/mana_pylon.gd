class_name ManaPylon
extends Node3D
## El Pilón de Maná (GDD 4.2): columna de vidrio y bronce donde se entrega lo recogido.
## Se entrega con su trituradora (CrystalCrusher): echas los cristales a la tolva manteniendo F,
## tiras de la palanca y el maná de cada cristal triturado entra en el Pilón con una gota (cada
## una una nota más alta de la pentatónica): el líquido sube, la superficie se agita, el cristal
## de la cima brilla y el zumbido crece.
## El nivel que se ve es la raíz del progreso real (ver `display_fill`): así los primeros
## minutos ya se notan y las marcas del 10 %, 25 %, 50 %, 75 % y 100 % quedan repartidas.

const GLASS_SHADER: Shader = preload("res://pylon/pylon_glass.gdshader")
const SHELL_SHADER: Shader = preload("res://pylon/pylon_glass_shell.gdshader")
const TOON_SHADER: Shader = preload("res://fx/toon.gdshader")
const SHARD_SHADER: Shader = preload("res://crystal/shard.gdshader")
const DROP_SFX: Array[AudioStream] = [
	preload("res://audio/sfx/sfx_mana_drop_01.ogg"),
	preload("res://audio/sfx/sfx_mana_drop_02.ogg"),
	preload("res://audio/sfx/sfx_mana_drop_03.ogg"),
]
const HUM_SFX: AudioStream = preload("res://audio/sfx/amb_pylon_hum_loop.ogg")
const MILESTONE_SFX: AudioStream = preload("res://audio/sfx/sfx_pylon_milestone_01.ogg")
const MARKS: PackedFloat32Array = [0.1, 0.25, 0.5, 0.75, 1.0]
## Pentatónica de La en semitonos: cada gota seguida sube una nota (como la racha del cristal).
const DROP_LADDER: PackedInt32Array = [0, 2, 4, 7, 9, 12, 14, 16, 19, 21, 24]
const C_STONE := Color("#e6dddb")
const C_STONE_SHADE := Color("#b9aeb8")
const C_GOLD := Color("#d8a23a")
const C_GOLD_DARK := Color("#9c6b25")
const GLASS_RADIUS: float = 1.0
const GLASS_HEIGHT: float = 5.0
const GLASS_BASE: float = 0.85
const MOTES: int = 24

## Vuelo de cada fragmento desde la mano hasta la tolva (s).
@export var flight_sec: float = 0.5

var _glass_mat: ShaderMaterial
var _shown_fill: float = 0.0
var _wave: float = 0.0
var _pulse: float = 0.0
var _crown_crystal: MeshInstance3D
var _crown_mat: ShaderMaterial
var _mark_rings: Array[MeshInstance3D] = []
var _mark_lit_mat: StandardMaterial3D
var _light: OmniLight3D
var _hum: AudioStreamPlayer3D
var _drop_player: AudioStreamPlayer3D
var _drop_random: AudioStreamRandomizer
var _accent: AudioStreamPlayer
var _splash: GPUParticles3D
var _player: Node3D
var _crusher: CrystalCrusher
var _chain: int = 0
var _chain_timer: float = 0.0
var _t: float = 0.0
var _last_ratio: float = 0.0
var _night: float = 0.0
## Fragmentos en vuelo hacia la boca.
var _motes: Array[MeshInstance3D] = []
var _mote_trails: Array[SpellTrail] = []
var _mote_t: PackedFloat32Array = []
var _mote_from: Array[Vector3] = []
var _mote_type: Array[ShardType] = []
## Motas de la pantalla de carga: no entregan nada.
var _mote_warm: Array[bool] = []
var _mote_to: Array[Vector3] = []
## Vuelo de cada cristal: punto de control del arco, dónde cae en el borde de la tolva,
## giro propio y duración (todos distintos: salen en abanico y caen separándose).
var _mote_ctrl: Array[Vector3] = []
var _mote_land: Array[Vector3] = []
var _mote_spin: Array[Vector3] = []
var _mote_dur: PackedFloat32Array = []
var _mote_rng := RandomNumberGenerator.new()
var _drop_gap: float = 0.0
var _mote_target: Array[CrystalCrusher] = []
var _mote_meshes: Dictionary[ShardType, ArrayMesh] = {}
## Rama del Pilón: rayos al cristal (Resonancia del Pilón) y celebración de los hitos.
var _resonance: PylonResonance


func _ready() -> void:
	add_to_group(&"mana_pylon")
	add_to_group(&"night_listeners")
	_build_body()
	_build_glass()
	_build_crown()
	_build_motes()
	_crusher = CrystalCrusher.new()
	_crusher.name = "Crusher"
	_crusher.pylon = self
	_crusher.position = Vector3(2.8, 0.0, 0.0)
	add_child(_crusher)
	for type: ShardType in ShardPool.ALL_TYPES:
		_mesh_for(type)
	_resonance = PylonResonance.new()
	_resonance.name = "Resonance"
	_resonance.pylon = self
	add_child(_resonance)
	_build_fx()
	_build_audio()
	Events.pylon_changed.connect(_on_pylon_changed)
	_last_ratio = GameState.progression.pylon_ratio()
	_shown_fill = display_fill(_last_ratio)
	_apply_fill()
	_update_marks(_last_ratio)


func set_night(k: float) -> void:
	_night = k


## Altura visible del maná (0..1) para un progreso real (0..1): raíz cuadrada, con un charco
## mínimo para que el Pilón nunca se vea vacío del todo.
static func display_fill(ratio: float) -> float:
	return lerpf(0.02, 1.0, sqrt(clampf(ratio, 0.0, 1.0)))


## Si un progreso real (0..1) ya llega a la marca `i` (con margen para el redondeo).
static func mark_reached(ratio: float, i: int) -> bool:
	return ratio + 1e-6 >= MARKS[i]


## Marcas ya alcanzadas (0..5) con un progreso real: lo que ha cambiado en el valle.
static func marks_reached(ratio: float) -> int:
	var n: int = 0
	for i: int in MARKS.size():
		if mark_reached(ratio, i):
			n += 1
	return n


## El cristal flotante de la cima (de donde sale el rayo de la Resonancia del Pilón).
func crown_position() -> Vector3:
	return _crown_crystal.global_position


## Rama del Pilón (rayos e hitos).
func resonance() -> PylonResonance:
	return _resonance


## Late y brilla (al cargar o disparar el rayo, en los hitos).
func pulse(amount: float) -> void:
	_pulse = maxf(_pulse, amount)
	_wave = minf(1.0, _wave + amount * 0.1)


## Punto por el que entran los fragmentos (la boca, sobre el vidrio).
func mouth_position() -> Vector3:
	return global_position + Vector3.UP * (GLASS_BASE + GLASS_HEIGHT + 0.6)


func _process(delta: float) -> void:
	_t += delta
	if _player == null:
		_player = get_tree().get_first_node_in_group(&"player") as Node3D
	_update_motes(delta)
	var target: float = display_fill(GameState.progression.pylon_ratio())
	_shown_fill = lerpf(_shown_fill, target, 1.0 - exp(-delta * 3.0))
	_wave = maxf(0.0, _wave - delta * 1.5)
	_pulse = maxf(0.0, _pulse - delta * 3.0)
	_apply_fill()
	# El cristal de la cima flota, gira y late con cada entrega.
	_crown_crystal.position.y = GLASS_BASE + GLASS_HEIGHT + 1.55 + sin(_t * 1.3) * 0.12
	_crown_crystal.rotation.y = floor(_t * 12.0) / 12.0 * 0.6
	_crown_crystal.scale = Vector3.ONE * (1.0 + _pulse * 0.25)
	# De noche el Pilón alumbra el valle (GDD 4.2).
	_light.light_energy = (0.8 + _shown_fill * 2.5 + _pulse * 3.0) * (1.0 + _night * 1.5)
	_light.omni_range = lerpf(9.0, 22.0, _night)
	_chain_timer = maxf(0.0, _chain_timer - delta)
	if _chain_timer <= 0.0:
		_chain = 0
	# El zumbido crece con el maná y con lo que estás entregando ahora mismo.
	_hum.volume_db = lerpf(-22.0, -8.0, _shown_fill) + _pulse * 4.0
	_hum.pitch_scale = 1.0 + _pulse * 0.03


## La trituradora del Pilón (tolva, palanca y rodillos).
func crusher() -> CrystalCrusher:
	return _crusher


## Pantalla de carga: un fragmento de cada tamaño vuela a la boca (sin entregar nada).
func warm_up() -> void:
	if _player == null:
		_player = get_tree().get_first_node_in_group(&"player") as Node3D
	for type: ShardType in ShardPool.ALL_TYPES:
		_mesh_for(type)
		launch_mote(type, _crusher.hopper_mouth(), null, true)


## Un cristal sale de la mano y vuela en arco hasta `to`; al llegar se lo da a `target` (la
## tolva). Con `warm` (pantalla de carga) sólo salpica.
func launch_mote(
	type: ShardType,
	to: Vector3,
	target: CrystalCrusher,
	warm: bool = false,
	from_override: Variant = null
) -> void:
	for i: int in MOTES:
		if _mote_t[i] < 0.0:
			var cam: Camera3D = get_viewport().get_camera_3d()
			if _player == null:
				_player = get_tree().get_first_node_in_group(&"player") as Node3D
			var from: Vector3 = _player.global_position + Vector3.UP * 1.1
			if cam:
				from = cam.global_position + cam.global_basis * Vector3(0.0, -0.5, -1.6)
			if from_override is Vector3:
				from = from_override
			else:
				# Salen en abanico de las manos, no todos del mismo punto.
				from += (
					cam.global_basis.x * _mote_rng.randf_range(-0.35, 0.35) if cam else Vector3.ZERO
				)
			_mote_from[i] = from
			_mote_t[i] = 0.0
			_mote_type[i] = type
			_mote_warm[i] = warm
			_mote_to[i] = to
			_mote_target[i] = target
			# Cada uno cae en un punto distinto del borde de la tolva, con su arco y su giro.
			var land_a: float = _mote_rng.randf() * TAU
			_mote_land[i] = (
				to + Vector3(cos(land_a), 0.0, sin(land_a)) * _mote_rng.randf_range(0.2, 0.55)
			)
			var side: Vector3 = (to - from).cross(Vector3.UP).normalized()
			_mote_ctrl[i] = (
				(from + _mote_land[i]) * 0.5
				+ Vector3.UP * _mote_rng.randf_range(1.2, 2.8)
				+ side * _mote_rng.randf_range(-1.4, 1.4)
			)
			_mote_spin[i] = Vector3(
				_mote_rng.randf_range(-9, 9),
				_mote_rng.randf_range(-12, 12),
				_mote_rng.randf_range(-6, 6)
			)
			_mote_dur[i] = _mote_rng.randf_range(0.75, 1.05)
			var mote: MeshInstance3D = _motes[i]
			mote.mesh = _mesh_for(type)
			mote.global_position = from
			mote.visible = true
			# Sin estela: tan cerca de la cámara se vería como una tabla blanca.
			return
	# Sin huecos (muchísimos a la vez): cae directamente en la tolva.
	if target:
		target.add_to_hopper(type)


func _update_motes(delta: float) -> void:
	_drop_gap = maxf(0.0, _drop_gap - delta)
	for i: int in MOTES:
		if _mote_t[i] < 0.0:
			continue
		# Dos fases: vuelo en arco hasta el borde (0..1) y caída al fondo de la tolva (1..1,3).
		_mote_t[i] += delta / _mote_dur[i]
		var mote: MeshInstance3D = _motes[i]
		var t: float = _mote_t[i]
		if t <= 1.0:
			var k: float = t
			var from: Vector3 = _mote_from[i]
			var a: Vector3 = from.lerp(_mote_ctrl[i], k)
			var b: Vector3 = _mote_ctrl[i].lerp(_mote_land[i], k)
			mote.global_position = a.lerp(b, k)
			mote.rotation = _mote_spin[i] * k
			# Sale pequeño de la mano (pegado a la cámara se vería enorme) y crece al alejarse.
			mote.scale = Vector3.ONE * lerpf(0.2, 1.0, smoothstep(0.0, 0.5, k))
		else:
			# Resbala hacia el centro de la tolva y se hunde.
			var d: float = clampf((t - 1.0) / 0.3, 0.0, 1.0)
			var sink: Vector3 = _mote_to[i] + Vector3.DOWN * 0.6
			mote.global_position = _mote_land[i].lerp(sink, d * d)
			mote.rotation = _mote_spin[i] * (1.0 + d * 0.3)
			mote.scale = Vector3.ONE * lerpf(1.0, 0.5, d)
		if t >= 1.3:
			_mote_t[i] = -1.0
			mote.visible = false
			_mote_trails[i].stop()
			if _mote_warm[i]:
				_splash.restart()
			elif _mote_target[i]:
				_mote_target[i].add_to_hopper(_mote_type[i])


## Entra en el Pilón el maná de un cristal triturado.
func receive_mana(type: ShardType) -> void:
	# El valor (con la Pureza) se calcula en un solo sitio: GameState.shard_value.
	GameState.deliver(GameState.shard_value(type))
	_wave = minf(1.0, _wave + 0.35)
	_pulse = 1.0
	_splash.restart()
	var step: int = DROP_LADDER[mini(_chain, DROP_LADDER.size() - 1)]
	_chain += 1
	_chain_timer = 0.6
	# Con la trituradora a tope llegan muchas gotas: una nota cada poco, no un muro de sonido.
	if _drop_gap <= 0.0:
		_drop_gap = 0.09
		_drop_player.pitch_scale = pow(2.0, float(step) / 12.0) * type.pickup_pitch / 1.0
		_drop_player.play()


## Las marcas se celebran en PylonResonance (Events.pylon_milestone); aquí suena la campana y se
## enciende el anillo tallado.
func _on_pylon_changed(_progress: int, ratio: float) -> void:
	for i: int in MARKS.size():
		if not mark_reached(_last_ratio, i) and mark_reached(ratio, i):
			_accent.stream = MILESTONE_SFX
			_accent.play()
	_last_ratio = ratio
	_update_marks(ratio)


func _apply_fill() -> void:
	_glass_mat.set_shader_parameter("fill", _shown_fill)
	_glass_mat.set_shader_parameter("wave", _wave)
	_glass_mat.set_shader_parameter("pulse", _pulse)


func _update_marks(ratio: float) -> void:
	for i: int in MARKS.size():
		if mark_reached(ratio, i):
			_mark_rings[i].material_override = _mark_lit_mat


func _mesh_for(type: ShardType) -> ArrayMesh:
	if not _mote_meshes.has(type):
		_mote_meshes[type] = CrystalClusterBuilder.build_shard_mesh(type, 99)
	return _mote_meshes[type]


func _toon() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = TOON_SHADER
	m.set_shader_parameter("rim", 0.3)
	return m


func _build_body() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var st: SurfaceTool = MeshKit.begin()
	# Peana de piedra en dos escalones y anillo de bronce donde apoya el vidrio.
	MeshKit.add_prism(st, Vector3.ZERO, Vector3.UP, 1.75, 0.35, 0.0, 8, C_STONE_SHADE, C_STONE, rng)
	MeshKit.add_prism(st, Vector3.UP * 0.35, Vector3.UP, 1.45, 0.3, 0.0, 8, C_STONE, C_STONE, rng)
	MeshKit.add_prism(
		st, Vector3.UP * 0.65, Vector3.UP, 1.18, 0.22, 0.0, 12, C_GOLD_DARK, C_GOLD, rng
	)
	# Cuatro costillas de bronce que abrazan el vidrio.
	for i: int in 4:
		var a: float = TAU * (float(i) + 0.5) / 4.0
		var p := Vector3(cos(a), 0.0, sin(a)) * (GLASS_RADIUS + 0.06)
		MeshKit.add_box(
			st,
			p + Vector3.UP * (GLASS_BASE + GLASS_HEIGHT * 0.5),
			Vector3(0.14, GLASS_HEIGHT, 0.14),
			C_GOLD_DARK,
			C_GOLD
		)
	# Corona: anillo superior y cuatro puntas.
	var top: float = GLASS_BASE + GLASS_HEIGHT
	MeshKit.add_prism(
		st, Vector3.UP * top, Vector3.UP, 1.2, 0.25, 0.0, 12, C_GOLD_DARK, C_GOLD, rng
	)
	for i: int in 4:
		var a: float = TAU * (float(i) + 0.5) / 4.0
		var p := Vector3(cos(a), 0.0, sin(a)) * 1.0 + Vector3.UP * (top + 0.25)
		MeshKit.add_prism(st, p, Vector3.UP, 0.12, 0.35, 0.45, 4, C_GOLD, C_GOLD, rng)
	var body := MeshInstance3D.new()
	body.name = "Body"
	body.mesh = MeshKit.commit(st)
	body.material_override = _toon()
	add_child(body)
	# Colisión: el jugador no atraviesa el Pilón.
	var sb := StaticBody3D.new()
	sb.name = "Collision"
	sb.collision_layer = 1
	sb.collision_mask = 0
	var shape := CylinderShape3D.new()
	shape.radius = 1.5
	shape.height = top + 0.5
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position.y = shape.height * 0.5
	sb.add_child(col)
	add_child(sb)
	# Marcas talladas: anillos que se encienden al alcanzarlas.
	var mark_mat := _toon()
	_mark_lit_mat = StandardMaterial3D.new()
	_mark_lit_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mark_lit_mat.albedo_color = Color(1.6, 1.3, 0.6)
	for m: float in MARKS:
		var rst: SurfaceTool = MeshKit.begin()
		var y: float = GLASS_BASE + GLASS_HEIGHT * display_fill(m)
		MeshKit.add_prism(
			rst,
			Vector3.UP * (y - 0.04),
			Vector3.UP,
			GLASS_RADIUS + 0.09,
			0.08,
			0.0,
			12,
			C_GOLD_DARK,
			C_GOLD,
			rng
		)
		var ring := MeshInstance3D.new()
		ring.mesh = MeshKit.commit(rst)
		ring.material_override = mark_mat
		add_child(ring)
		_mark_rings.append(ring)


func _build_glass() -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = GLASS_RADIUS
	mesh.bottom_radius = GLASS_RADIUS
	mesh.height = GLASS_HEIGHT
	mesh.radial_segments = 16
	mesh.rings = 1
	mesh.cap_top = false
	mesh.cap_bottom = false
	var glass := MeshInstance3D.new()
	glass.name = "Glass"
	glass.mesh = mesh
	# El cilindro de Godot va centrado: el shader suma media altura para medir desde la base.
	var holder := Node3D.new()
	holder.position.y = GLASS_BASE + GLASS_HEIGHT * 0.5
	add_child(holder)
	holder.add_child(glass)
	_glass_mat = ShaderMaterial.new()
	_glass_mat.shader = GLASS_SHADER
	_glass_mat.set_shader_parameter("height", GLASS_HEIGHT)
	glass.material_override = _glass_mat
	glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	glass.scale = Vector3(0.92, 1.0, 0.92)
	# Vidrio exterior transparente.
	var shell := MeshInstance3D.new()
	shell.name = "Shell"
	shell.mesh = mesh
	var shell_mat := ShaderMaterial.new()
	shell_mat.shader = SHELL_SHADER
	shell.material_override = shell_mat
	shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(shell)


func _build_crown() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	var st: SurfaceTool = MeshKit.begin()
	MeshKit.add_prism(
		st, Vector3.DOWN * 0.45, Vector3.UP, 0.32, 0.6, 0.5, 6, Color.WHITE, Color.WHITE, rng
	)
	MeshKit.add_prism(
		st, Vector3.DOWN * 0.45, Vector3.DOWN, 0.32, 0.01, 0.45, 6, Color.WHITE, Color.WHITE, rng
	)
	_crown_crystal = MeshInstance3D.new()
	_crown_crystal.name = "CrownCrystal"
	_crown_crystal.mesh = MeshKit.commit(st)
	_crown_mat = ShaderMaterial.new()
	_crown_mat.shader = SHARD_SHADER
	_crown_crystal.material_override = _crown_mat
	_crown_crystal.set_instance_shader_parameter("spawn_flash", 0.0)
	add_child(_crown_crystal)
	_light = OmniLight3D.new()
	_light.name = "Light"
	_light.light_color = Color("#c79bff")
	_light.omni_range = 9.0
	_light.shadow_enabled = false
	_light.position.y = GLASS_BASE + GLASS_HEIGHT + 1.4
	add_child(_light)


func _build_motes() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = SHARD_SHADER
	var ramp := Gradient.new()
	ramp.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	ramp.offsets = PackedFloat32Array([0.0, 0.2, 0.45, 0.7, 0.88])
	ramp.colors = PackedColorArray(
		[
			Color(1.4, 1.8, 2.0),
			Color("#7fe3ff"),
			Color("#ff7ad9"),
			Color("#a36bff"),
			Color(0.4, 0.31, 0.68, 0.4),
		]
	)
	for i: int in MOTES:
		var mote := MeshInstance3D.new()
		mote.name = "Mote%d" % i
		mote.top_level = true
		mote.material_override = mat
		mote.visible = false
		mote.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mote.set_instance_shader_parameter("spawn_flash", 0.0)
		mote.set_instance_shader_parameter("glint_seed", float(i) / float(MOTES))
		add_child(mote)
		var trail := SpellTrail.new()
		trail.length_sec = 0.16
		# Pegada a la cámara al salir: se estrecha como la de los hechizos.
		trail.near_depth = 0.7
		trail.max_scale = 6.0
		mote.add_child(trail)
		trail.set_ramp(ramp)
		_motes.append(mote)
		_mote_trails.append(trail)
		_mote_t.append(-1.0)
		_mote_from.append(Vector3.ZERO)
		_mote_type.append(null)
		_mote_warm.append(false)
		_mote_to.append(Vector3.ZERO)
		_mote_ctrl.append(Vector3.ZERO)
		_mote_land.append(Vector3.ZERO)
		_mote_spin.append(Vector3.ZERO)
		_mote_dur.append(1.0)
		_mote_target.append(null)


func _build_fx() -> void:
	_splash = GPUParticles3D.new()
	_splash.name = "Splash"
	_splash.one_shot = true
	_splash.emitting = false
	_splash.amount = 14
	_splash.lifetime = 0.7
	_splash.explosiveness = 0.9
	_splash.fixed_fps = 24
	_splash.local_coords = false
	_splash.position = Vector3.UP * (GLASS_BASE + GLASS_HEIGHT + 0.5)
	_splash.visibility_aabb = AABB(Vector3(-4, -4, -4), Vector3(8, 8, 8))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.3
	pm.direction = Vector3.UP
	pm.spread = 50.0
	pm.initial_velocity_min = 2.0
	pm.initial_velocity_max = 4.0
	pm.gravity = Vector3(0, -7.0, 0)
	var colors := Gradient.new()
	colors.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	colors.offsets = PackedFloat32Array([0.0, 0.35, 0.7])
	colors.colors = PackedColorArray([Color("#c9f6ff"), Color("#ff7ad9"), Color("#c79bff")])
	var ctex := GradientTexture1D.new()
	ctex.gradient = colors
	pm.color_initial_ramp = ctex
	_splash.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.16, 0.16)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = PixelTextures.star()
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	q.material = m
	_splash.draw_pass_1 = q
	add_child(_splash)


func _build_audio() -> void:
	_hum = AudioStreamPlayer3D.new()
	_hum.name = "Hum"
	_hum.bus = &"Ambience"
	_hum.stream = HUM_SFX  # bucle activado en la importación
	_hum.unit_size = 6.0
	_hum.position.y = 3.0
	_hum.autoplay = true
	add_child(_hum)
	_drop_random = AudioStreamRandomizer.new()
	for s: AudioStream in DROP_SFX:
		_drop_random.add_stream(-1, s)
	_drop_random.random_pitch = 1.0
	_drop_player = AudioStreamPlayer3D.new()
	_drop_player.bus = &"SFX"
	_drop_player.stream = _drop_random
	_drop_player.unit_size = 14.0
	_drop_player.max_polyphony = 2
	_drop_player.volume_db = -8.0
	_drop_player.position.y = GLASS_BASE + GLASS_HEIGHT
	add_child(_drop_player)
	_accent = AudioStreamPlayer.new()
	_accent.bus = &"SFX"
	add_child(_accent)
