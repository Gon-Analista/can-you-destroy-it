class_name MeteorRock
extends Node3D
## Meteoro (`SpellVisualDef.meteor`), hijo de un `SparkProjectile`: lo que hace que la Bola de
## Fuego del cielo se lea como un meteorito y no como una bola de fuego.
## - Al salir: destello en el cielo donde aparece (con su campanilla) y silbido que se acerca.
## - En vuelo: roca de basalto que gira, con la cara de delante al rojo y grietas de lava, dentro
##   del fuego del orbe (que hace de cola de cometa), y un rastro de humo espeso y gotas de lava.
## - Al llegar: destello, dos ondas de choque, polvo que sale en anillo, cascotes al rojo que
##   saltan y caen, chispas, cráter encendido que se apaga despacio, luz, sacudida y estruendo.
## Todo se crea una vez (con el proyectil) y se reutiliza.

const ROCK_SHADER: Shader = preload("res://spells/vfx/meteor_rock.gdshader")
const GLINT_SFX: AudioStream = preload("res://audio/sfx/sfx_meteor_glint_01.ogg")
const WHISTLE_SFX: AudioStream = preload("res://audio/sfx/sfx_meteor_whistle_01.ogg")
const BOOM_SFX: AudioStream = preload("res://audio/sfx/sfx_meteor_boom_01.ogg")
## Radio de la roca (m) con Tamaño 1.
const ROCK_RADIUS: float = 2.4
## Lo que dura el impacto (el proyectil espera a que acabe antes de volver al pool).
const IMPACT_SEC: float = 3.2
const HOT := Color(1.0, 0.45, 0.14)

static var _rock_mesh: ArrayMesh

var _rock: MeshInstance3D
var _rock_mat: ShaderMaterial
var _spin_axis := Vector3.RIGHT
var _spin_speed: float = 2.0
var _prev_pos := Vector3.ZERO
var _smoke: GPUParticles3D
var _drips: GPUParticles3D
var _glint: MeshInstance3D
var _glint_mat: ShaderMaterial
var _glint_t: float = -1.0
var _impact: Node3D
var _flash: MeshInstance3D
var _flash_mat: ShaderMaterial
var _rings: Array[MeshInstance3D] = []
var _ring_mats: Array[ShaderMaterial] = []
var _crater: MeshInstance3D
var _blast: MeshInstance3D
var _blast_mat: ShaderMaterial
var _crater_mat: ShaderMaterial
var _dust: GPUParticles3D
var _debris: GPUParticles3D
var _sparks: GPUParticles3D
var _light: OmniLight3D
var _impact_t: float = -1.0
var _size: float = 1.0
var _flying: bool = false


func _ready() -> void:
	_build_rock()
	_build_trail()
	_build_glint()
	_build_impact()
	visible = false
	set_process(false)


## Empieza la caída desde `from` (en el cielo) hacia `to`. `warmup`: sin sonido ni sacudida.
func launch(from: Vector3, to: Vector3, size: float, warmup: bool) -> void:
	_size = size
	_flying = true
	_prev_pos = from
	visible = true
	_rock.visible = true
	_rock.scale = Vector3.ONE * ROCK_RADIUS * size
	_spin_axis = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized()
	_spin_speed = randf_range(1.5, 3.0)
	_rock_mat.set_shader_parameter("travel_dir", (to - from).normalized())
	_rock_mat.set_shader_parameter("heat", 1.0)
	_rock_mat.set_shader_parameter("seed", randf() * 10.0)
	HdFx.set_smoke_size(_smoke, 7.0 * size)
	_smoke.emitting = true
	_drips.emitting = true
	_glint.global_position = _entry_point(from, to)
	_glint.visible = true
	_glint_t = 0.0
	_impact_t = -1.0
	_impact.visible = false
	if not warmup:
		AudioDirector.play_sfx(GLINT_SFX, -10.0, randf_range(0.95, 1.05))
		AudioDirector.play_sfx(WHISTLE_SFX, -3.0, randf_range(0.95, 1.05))
	set_process(true)


## Dónde se ve aparecer la roca: el origen suele quedar por encima de la pantalla, así que el
## destello va al primer punto del camino que entra en cámara (algo hacia dentro del borde).
func _entry_point(from: Vector3, to: Vector3) -> Vector3:
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return from
	for i: int in 21:
		var p: Vector3 = from.lerp(to, float(i) / 20.0)
		if cam.is_position_in_frustum(p):
			return from.lerp(to, minf(float(i) / 20.0 + 0.06, 1.0))
	return from


## La roca llega a `pos` (superficie con normal `normal`): estalla.
func impact(pos: Vector3, normal: Vector3, warmup: bool) -> void:
	_flying = false
	_rock.visible = false
	_smoke.emitting = false
	_drips.emitting = false
	var n: Vector3 = normal if normal.length_squared() > 0.01 else Vector3.UP
	# El nodo del impacto mira con su +Y por la normal: polvo y cascotes salen de la superficie.
	var side: Vector3 = n.cross(Vector3.FORWARD if absf(n.z) < 0.9 else Vector3.RIGHT).normalized()
	_impact.global_basis = Basis(side, n, side.cross(n)).orthonormalized()
	_impact.global_position = pos + n * 0.5
	_impact.visible = true
	_impact_t = 0.0
	var s: float = _size
	for i: int in _rings.size():
		_rings[i].scale = Vector3.ONE * (34.0 if i == 0 else 56.0) * s
		_ring_mats[i].set_shader_parameter("seed", randf() * 10.0)
	_flash.scale = Vector3.ONE * 30.0 * s
	_flash_mat.set_shader_parameter("seed", randf() * 10.0)
	_crater.scale = Vector3.ONE * 11.0 * s
	_blast_mat.set_shader_parameter("seed", randf() * 10.0)
	HdFx.set_smoke_size(_dust, 7.5 * s)
	(_dust.process_material as ParticleProcessMaterial).emission_sphere_radius = 2.0 * s
	_dust.restart()
	_debris.restart()
	_sparks.restart()
	_light.visible = true
	_animate_impact()
	if not warmup:
		AudioDirector.play_sfx(BOOM_SFX, 0.0, randf_range(0.94, 1.04))
		var cam: Camera3D = get_viewport().get_camera_3d()
		if cam is CameraRig:
			# Más fuerte cuanto más cerca (a 25 m, a tope).
			var near: float = clampf(40.0 / maxf(cam.global_position.distance_to(pos), 1.0), 0.4, 1)
			(cam as CameraRig).add_trauma(0.75 * near)
	set_process(true)


## Vuelve al pool: todo apagado.
func stop() -> void:
	_flying = false
	_impact_t = -1.0
	_glint_t = -1.0
	_smoke.emitting = false
	_drips.emitting = false
	_light.visible = false
	visible = false
	set_process(false)


func _process(delta: float) -> void:
	if _flying:
		_rock.rotate(_spin_axis, _spin_speed * delta)
		var p: Vector3 = global_position
		if p.distance_squared_to(_prev_pos) > 0.0001:
			_rock_mat.set_shader_parameter("travel_dir", (p - _prev_pos).normalized())
		_prev_pos = p
	if _glint_t >= 0.0:
		_glint_t += delta
		var g: float = clampf(_glint_t / 0.7, 0.0, 1.0)
		# Sube de golpe y se apaga: una estrella que se enciende donde nace el meteoro.
		var e: float = smoothstep(0.0, 0.08, _glint_t) * (1.0 - g) * (1.0 - g)
		_glint.scale = Vector3.ONE * lerpf(10.0, 22.0, g) * _size
		_glint_mat.set_shader_parameter("intensity", e * 1.6)
		if g >= 1.0:
			_glint_t = -1.0
			_glint.visible = false
	if _impact_t >= 0.0:
		_impact_t += delta
		_animate_impact()
		if _impact_t >= IMPACT_SEC:
			_impact_t = -1.0
			_impact.visible = false
			_light.visible = false
	if not _flying and _glint_t < 0.0 and _impact_t < 0.0:
		set_process(false)


func _animate_impact() -> void:
	var t: float = _impact_t
	var fk: float = clampf(t / 0.45, 0.0, 1.0)
	_flash.visible = fk < 1.0
	_flash_mat.set_shader_parameter("intensity", 0.55 * (1.0 - fk) * (1.0 - fk))
	for i: int in _rings.size():
		var dur: float = 0.7 if i == 0 else 1.25
		var k: float = clampf((t - 0.04 * i) / dur, 0.0, 1.0)
		_rings[i].visible = k > 0.0 and k < 1.0
		_ring_mats[i].set_shader_parameter("progress", k)
	# Bola de fuego del golpe: se hincha, sube y se deshace en jirones oscuros.
	var bk: float = clampf(t / 1.3, 0.0, 1.0)
	_blast.visible = bk < 1.0
	_blast.scale = Vector3.ONE * _size * lerpf(10.0, 27.0, 1.0 - pow(1.0 - bk, 3.0))
	_blast.position = Vector3.UP * lerpf(0.5, 5.0, bk) * _size
	_blast_mat.set_shader_parameter("burst", bk)
	_blast_mat.set_shader_parameter("fade", 1.0 - bk * bk)
	# Cráter: brilla al rojo, parpadea y se enfría despacio.
	var ck: float = clampf(t / IMPACT_SEC, 0.0, 1.0)
	var flick: float = 0.85 + 0.15 * sin(t * 17.0) * sin(t * 9.0)
	_crater_mat.set_shader_parameter(
		"intensity", smoothstep(0.0, 0.1, t) * (1.0 - ck) * (1.0 - ck) * 0.9 * flick
	)
	_light.light_energy = 14.0 * (1.0 - fk) + 3.0 * (1.0 - ck) * flick
	_light.omni_range = 34.0 * _size


func _build_rock() -> void:
	_rock = make_rock()
	_rock_mat = _rock.material_override
	add_child(_rock)


## Una roca fundida lista para la capa de magia (también la que se forma entre las manos al
## cargar el Meteoro, ver `SpellOrb`). Comparte la malla.
static func make_rock() -> MeshInstance3D:
	if _rock_mesh == null:
		_rock_mesh = _make_rock_mesh()
	var rock := MeshInstance3D.new()
	rock.name = "Rock"
	rock.mesh = _rock_mesh
	var mat := ShaderMaterial.new()
	mat.shader = ROCK_SHADER
	# Por delante del fuego del orbe (5) y de sus cintas: el fuego la envuelve por detrás.
	mat.render_priority = 7
	rock.material_override = mat
	rock.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rock.layers = MagicLayer.MAGIC_LAYER
	return rock


## Roca baja en polígonos: icosaedro subdividido dos veces, abollado con ruido y caras planas.
static func _make_rock_mesh() -> ArrayMesh:
	var t: float = (1.0 + sqrt(5.0)) * 0.5
	var verts: Array[Vector3] = [
		Vector3(-1, t, 0),
		Vector3(1, t, 0),
		Vector3(-1, -t, 0),
		Vector3(1, -t, 0),
		Vector3(0, -1, t),
		Vector3(0, 1, t),
		Vector3(0, -1, -t),
		Vector3(0, 1, -t),
		Vector3(t, 0, -1),
		Vector3(t, 0, 1),
		Vector3(-t, 0, -1),
		Vector3(-t, 0, 1),
	]
	var faces: Array[Vector3i] = [
		Vector3i(0, 11, 5),
		Vector3i(0, 5, 1),
		Vector3i(0, 1, 7),
		Vector3i(0, 7, 10),
		Vector3i(0, 10, 11),
		Vector3i(1, 5, 9),
		Vector3i(5, 11, 4),
		Vector3i(11, 10, 2),
		Vector3i(10, 7, 6),
		Vector3i(7, 1, 8),
		Vector3i(3, 9, 4),
		Vector3i(3, 4, 2),
		Vector3i(3, 2, 6),
		Vector3i(3, 6, 8),
		Vector3i(3, 8, 9),
		Vector3i(4, 9, 5),
		Vector3i(2, 4, 11),
		Vector3i(6, 2, 10),
		Vector3i(8, 6, 7),
		Vector3i(9, 8, 1),
	]
	for i: int in verts.size():
		verts[i] = verts[i].normalized()
	for _level: int in 2:
		var mids: Dictionary[int, int] = {}
		var next: Array[Vector3i] = []
		for f: Vector3i in faces:
			var a: int = _mid(verts, mids, f.x, f.y)
			var b: int = _mid(verts, mids, f.y, f.z)
			var c: int = _mid(verts, mids, f.z, f.x)
			next.append(Vector3i(f.x, a, c))
			next.append(Vector3i(f.y, b, a))
			next.append(Vector3i(f.z, c, b))
			next.append(Vector3i(a, b, c))
		faces = next
	var noise := FastNoiseLite.new()
	noise.seed = 4217
	noise.frequency = 0.9
	for i: int in verts.size():
		var v: Vector3 = verts[i]
		# Algo achatada y con bultos: una piedra, no una bola.
		var r: float = 1.0 + noise.get_noise_3dv(v * 1.7) * 0.32
		verts[i] = Vector3(v.x * 1.1, v.y * 0.85, v.z) * r
	var st: SurfaceTool = MeshKit.begin()
	for f: Vector3i in faces:
		MeshKit.add_tri(st, verts[f.x], verts[f.y], verts[f.z], Color.WHITE, Vector3.ZERO)
	return st.commit()


static func _mid(verts: Array[Vector3], mids: Dictionary[int, int], a: int, b: int) -> int:
	var key: int = mini(a, b) * 100000 + maxi(a, b)
	if mids.has(key):
		return mids[key]
	verts.append(((verts[a] + verts[b]) * 0.5).normalized())
	mids[key] = verts.size() - 1
	return verts.size() - 1


## Rastro: humo espeso que se queda en el aire (calentado por debajo) y gotas de lava.
func _build_trail() -> void:
	_smoke = HdFx.smoke(110, 7.0, Color(0.24, 0.19, 0.2))
	_smoke.name = "SmokeTrail"
	_smoke.one_shot = false
	_smoke.explosiveness = 0.0
	_smoke.lifetime = 2.6
	var spm: ParticleProcessMaterial = _smoke.process_material
	spm.emission_sphere_radius = 1.2
	spm.initial_velocity_min = 0.2
	spm.initial_velocity_max = 1.2
	spm.gravity = Vector3(0, 0.4, 0)
	# Nace naranja (lo ilumina el fuego), se oscurece y se deshace.
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.08, 0.3, 1.0])
	g.colors = PackedColorArray(
		[
			Color(1.0, 0.5, 0.2, 0.0),
			Color(0.75, 0.36, 0.18, 0.75),
			Color(0.3, 0.22, 0.22, 0.6),
			Color(0.24, 0.21, 0.26, 0.0)
		]
	)
	var ramp := GradientTexture1D.new()
	ramp.gradient = g
	spm.color_ramp = ramp
	add_child(_smoke)
	_drips = HdFx.sparks(
		60, 6.0, 0.1, PackedColorArray([Color(0.9, 0.42, 0.12), Color(0.6, 0.15, 0.04)])
	)
	_drips.name = "LavaDrips"
	_drips.one_shot = false
	_drips.explosiveness = 0.0
	_drips.lifetime = 0.9
	_drips.trail_lifetime = 0.2
	var dpm: ParticleProcessMaterial = _drips.process_material
	dpm.emission_sphere_radius = 1.6
	dpm.gravity = Vector3(0, -12.0, 0)
	(_drips.draw_pass_1 as RibbonTrailMesh).section_length = 0.5
	add_child(_drips)


func _build_glint() -> void:
	_glint = HdFx.quad(HdFx.GLOW_SHADER, 1.0, 3)
	_glint.name = "SkyGlint"
	_glint.top_level = true
	_glint_mat = _glint.material_override
	_glint_mat.set_shader_parameter("color", Color(1.0, 0.75, 0.4))
	_glint_mat.set_shader_parameter("rays", 1.4)
	_glint_mat.set_shader_parameter("ray_count", 4.0)
	_glint_mat.set_shader_parameter("falloff", 3.0)
	_glint.visible = false
	add_child(_glint)


func _build_impact() -> void:
	_impact = Node3D.new()
	_impact.name = "Impact"
	_impact.top_level = true
	_impact.visible = false
	add_child(_impact)
	_flash = HdFx.quad(HdFx.GLOW_SHADER, 1.0, 3)
	_flash_mat = _flash.material_override
	_flash_mat.set_shader_parameter("color", Color(1.0, 0.62, 0.3))
	_flash_mat.set_shader_parameter("rays", 1.2)
	_flash_mat.set_shader_parameter("ray_count", 10.0)
	# Tiñe de naranja en vez de sumar: sobre el cristal claro, sumado, era un disco blanco.
	_flash_mat.set_shader_parameter("cover", 0.7)
	_impact.add_child(_flash)
	_crater = HdFx.quad(HdFx.GLOW_SHADER, 1.0, 3)
	_crater_mat = _crater.material_override
	_crater_mat.set_shader_parameter("color", HOT)
	_crater_mat.set_shader_parameter("falloff", 1.6)
	# Brasa que tiñe el suelo de naranja (sumada, sobre el cristal claro se quedaba blanca).
	_crater_mat.set_shader_parameter("cover", 0.6)
	_impact.add_child(_crater)
	_blast = HdFx.quad(HdFx.FIRE_SHADER, 1.0, 5)
	_blast.name = "Blast"
	_blast_mat = _blast.material_override
	var g0 := Gradient.new()
	g0.offsets = PackedFloat32Array([0.0, 0.2, 0.45, 0.72, 1.0])
	g0.colors = PackedColorArray(
		[
			Color(2.2, 1.8, 1.1),
			Color(1.6, 0.8, 0.22),
			Color(1.05, 0.36, 0.07),
			Color(0.55, 0.14, 0.05),
			Color(0.22, 0.07, 0.05)
		]
	)
	_blast_mat.set_shader_parameter("ramp", HdFx.smooth_ramp(g0))
	_blast_mat.set_shader_parameter("flow_strength", 1.6)
	_blast_mat.set_shader_parameter("turbulence", 0.5)
	_blast_mat.set_shader_parameter("charge", 1.0)
	_impact.add_child(_blast)
	for i: int in 2:
		var ring: MeshInstance3D = HdFx.quad(HdFx.RING_SHADER, 1.0, 8)
		var m: ShaderMaterial = ring.material_override
		m.set_shader_parameter("color", Color(1.0, 0.6, 0.3) if i == 0 else Color(1.0, 0.85, 0.6))
		m.set_shader_parameter("intensity", 0.9 if i == 0 else 0.5)
		# Ondas de calor y polvo que tiñen: sumadas, sobre el cielo claro eran donuts blancos.
		m.set_shader_parameter("cover", 0.7 if i == 0 else 0.5)
		_impact.add_child(ring)
		_rings.append(ring)
		_ring_mats.append(m)
	# Polvo: sale de la superficie en anillo, se frena y se queda flotando.
	_dust = HdFx.smoke(46, 7.5, Color(0.5, 0.42, 0.42))
	_dust.name = "Dust"
	_dust.lifetime = 2.6
	_dust.explosiveness = 0.95
	var dpm: ParticleProcessMaterial = _dust.process_material
	dpm.spread = 85.0
	dpm.initial_velocity_min = 8.0
	dpm.initial_velocity_max = 20.0
	dpm.damping_min = 7.0
	dpm.damping_max = 11.0
	dpm.gravity = Vector3(0, -0.5, 0)
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.1, 0.5, 1.0])
	g.colors = PackedColorArray(
		[
			Color(1.0, 0.55, 0.25, 0.0),
			Color(0.58, 0.42, 0.32, 0.75),
			Color(0.45, 0.39, 0.36, 0.55),
			Color(0.4, 0.38, 0.4, 0.0)
		]
	)
	var ramp := GradientTexture1D.new()
	ramp.gradient = g
	dpm.color_ramp = ramp
	_impact.add_child(_dust)
	_debris = _make_debris()
	_impact.add_child(_debris)
	_sparks = HdFx.sparks(
		140, 26.0, 0.12, PackedColorArray([Color(2.4, 1.6, 0.7), Color(1.3, 0.4, 0.1)])
	)
	_sparks.lifetime = 1.1
	_sparks.trail_lifetime = 0.16
	var spm: ParticleProcessMaterial = _sparks.process_material
	spm.spread = 80.0
	spm.emission_sphere_radius = 1.5
	spm.gravity = Vector3(0, -16.0, 0)
	(_sparks.draw_pass_1 as RibbonTrailMesh).section_length = 0.35
	_impact.add_child(_sparks)
	_light = OmniLight3D.new()
	_light.light_color = HOT
	_light.shadow_enabled = false
	_light.visible = false
	_impact.add_child(_light)


## Cascotes de roca al rojo que saltan del cráter, giran, caen y se enfrían.
func _make_debris() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "Debris"
	p.amount = 36
	p.lifetime = 1.9
	p.one_shot = true
	p.explosiveness = 0.97
	p.emitting = false
	p.local_coords = false
	p.layers = MagicLayer.MAGIC_LAYER
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-60, -60, -60), Vector3(120, 120, 120))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 1.5
	pm.direction = Vector3.UP
	pm.spread = 70.0
	pm.initial_velocity_min = 9.0
	pm.initial_velocity_max = 24.0
	pm.gravity = Vector3(0, -22.0, 0)
	pm.scale_min = 0.25
	pm.scale_max = 0.85
	pm.particle_flag_rotate_y = true
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	pm.angular_velocity_min = -360.0
	pm.angular_velocity_max = 360.0
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	g.colors = PackedColorArray(
		[Color(2.0, 0.8, 0.25), Color(0.7, 0.22, 0.08), Color(0.16, 0.11, 0.1)]
	)
	var ramp := GradientTexture1D.new()
	ramp.gradient = g
	ramp.use_hdr = true
	pm.color_ramp = ramp
	p.process_material = pm
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.9, 0.6, 0.75)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.disable_fog = true
	m.render_priority = 6
	mesh.material = m
	p.draw_pass_1 = mesh
	return p
