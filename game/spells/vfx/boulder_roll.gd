class_name BoulderRoll
extends Node3D
## Terremoto (`SpellVisualDef.boulder`), hijo de un `SparkProjectile`: un peñasco que brota del
## suelo delante del mago, rueda hacia el cristal dando botes y revienta contra él. Antes era la
## piedrecita del orbe de la mano, que no se correspondía con lo que destroza un Terremoto cargado.
## - Al salir: brota del suelo unos metros por delante (crece desde abajo).
## - En vuelo: rueda sobre sí mismo (sin resbalar) con las vetas doradas encendidas, levanta una
##   cortina de polvo y va soltando gravilla; cada bote sacude un poco la cámara.
## - Al llegar: se hace pedazos (cascotes que saltan, polvo en anillo). El golpe en el cristal lo
##   pone el estallido de siempre.
## El tamaño lo dan el Tamaño del hechizo y lo cargado que salió (`SpellHit.fx_scale`).
## Todo se crea una vez (con el proyectil) y se reutiliza.

## Radio del peñasco (m) con Tamaño 1 y sin carga.
const RADIUS: float = 1.6
## Lo que tarda en brotar del suelo (s).
const RISE_SEC: float = 0.22
## Lo que dura el estallido al llegar (el proyectil espera a que acabe).
const IMPACT_SEC: float = 1.8
## Botes por metro recorrido y su altura (fracción del radio).
const BOUNCE_PER_M: float = 0.09
const BOUNCE_HEIGHT: float = 0.35

var _rock: MeshInstance3D
var _rock_mat: ShaderMaterial
var _dust_trail: GPUParticles3D
var _gravel: GPUParticles3D
var _burst_dust: GPUParticles3D
var _burst_debris: GPUParticles3D
var _burst: Node3D
var _radius: float = 1.0
var _flying: bool = false
var _age: float = 0.0
var _impact_t: float = -1.0
var _prev := Vector3.ZERO
var _travelled: float = 0.0
var _last_bounce: int = 0
var _warmup: bool = false


func _ready() -> void:
	_rock = MeteorRock.make_rock()
	_rock.name = "Boulder"
	_rock_mat = _rock.material_override
	_rock_mat.set_shader_parameter("rock_color", Color(0.3, 0.22, 0.15))
	_rock_mat.set_shader_parameter("rock_light", Color(0.7, 0.55, 0.38))
	_rock_mat.set_shader_parameter("hot_color", Color(0.95, 0.68, 0.28))
	_rock_mat.set_shader_parameter("crack_color", Color(1.0, 0.86, 0.42))
	_rock_mat.set_shader_parameter("crack_energy", 2.2)
	add_child(_rock)
	_dust_trail = HdFx.smoke(70, 3.0, Color(0.62, 0.5, 0.38))
	_dust_trail.name = "DustTrail"
	_dust_trail.one_shot = false
	_dust_trail.explosiveness = 0.0
	_dust_trail.lifetime = 1.4
	var dpm: ParticleProcessMaterial = _dust_trail.process_material
	dpm.direction = Vector3.UP
	dpm.spread = 70.0
	dpm.initial_velocity_min = 0.6
	dpm.initial_velocity_max = 2.4
	dpm.gravity = Vector3(0, 0.3, 0)
	add_child(_dust_trail)
	_gravel = _make_debris(48, 0.35, Color(0.62, 0.48, 0.32), Color(0.32, 0.24, 0.17))
	_gravel.name = "Gravel"
	_gravel.one_shot = false
	_gravel.explosiveness = 0.0
	_gravel.lifetime = 0.9
	add_child(_gravel)
	_burst = Node3D.new()
	_burst.name = "Burst"
	_burst.top_level = true
	add_child(_burst)
	_burst_dust = HdFx.smoke(40, 5.0, Color(0.6, 0.5, 0.4))
	_burst_dust.name = "BurstDust"
	_burst_dust.lifetime = 1.8
	_burst_dust.explosiveness = 0.95
	var bpm: ParticleProcessMaterial = _burst_dust.process_material
	bpm.spread = 90.0
	bpm.initial_velocity_min = 5.0
	bpm.initial_velocity_max = 14.0
	bpm.damping_min = 6.0
	bpm.damping_max = 10.0
	bpm.gravity = Vector3(0, -0.4, 0)
	_burst.add_child(_burst_dust)
	_burst_debris = _make_debris(40, 1.0, Color(0.7, 0.55, 0.36), Color(0.28, 0.2, 0.14))
	_burst_debris.name = "BurstDebris"
	_burst.add_child(_burst_debris)
	visible = false
	set_process(false)


## Empieza a rodar desde `from` (a ras de suelo) hacia `to`. `size`: escala (Tamaño x carga).
func launch(from: Vector3, to: Vector3, size: float, heat: float, warmup: bool) -> void:
	_radius = RADIUS * size
	_flying = true
	_warmup = warmup
	_age = 0.0
	_impact_t = -1.0
	_prev = from
	_travelled = 0.0
	_last_bounce = 0
	visible = true
	_rock.visible = true
	_rock.scale = Vector3.ONE * 0.01
	_rock_mat.set_shader_parameter("heat", heat)
	_rock_mat.set_shader_parameter("seed", randf() * 10.0)
	_rock_mat.set_shader_parameter("travel_dir", (to - from).normalized())
	HdFx.set_smoke_size(_dust_trail, 1.5 * size)
	(_dust_trail.process_material as ParticleProcessMaterial).emission_sphere_radius = _radius * 0.6
	(_gravel.process_material as ParticleProcessMaterial).emission_sphere_radius = _radius * 0.7
	_dust_trail.emitting = true
	_gravel.emitting = true
	set_process(true)


## El peñasco llega a `pos` (superficie con normal `normal`): se hace pedazos.
func impact(pos: Vector3, normal: Vector3) -> void:
	_flying = false
	_rock.visible = false
	_dust_trail.emitting = false
	_gravel.emitting = false
	_play_burst(pos, normal, _radius / RADIUS)


func stop() -> void:
	_flying = false
	_impact_t = -1.0
	_dust_trail.emitting = false
	_gravel.emitting = false
	visible = false
	set_process(false)


func _process(delta: float) -> void:
	if _flying:
		_age += delta
		var p: Vector3 = global_position
		var step: Vector3 = p - _prev
		_prev = p
		var rise: float = smoothstep(0.0, RISE_SEC, _age)
		_rock.scale = Vector3.ONE * maxf(_radius * rise, 0.01)
		var dist: float = step.length()
		if dist > 0.0001:
			_travelled += dist
			var dir: Vector3 = step / dist
			# Rueda sin resbalar: gira lo que avanza dividido por el radio.
			var axis: Vector3 = Vector3.UP.cross(dir)
			if axis.length_squared() > 0.0001:
				_rock.global_rotate(axis.normalized(), dist / maxf(_radius, 0.1))
			_rock_mat.set_shader_parameter("travel_dir", dir)
		# Se apoya en el suelo (el centro, un radio por encima) y da botes cada tantos metros.
		var hop: float = absf(sin(_travelled * BOUNCE_PER_M * PI)) * BOUNCE_HEIGHT
		var ground: float = maxf(Valley.ground_height(p.x, p.z), p.y - 0.6)
		_rock.global_position = Vector3(
			p.x, ground + _radius * (lerpf(-1.0, 0.85, rise) + hop * rise), p.z
		)
		var bounce: int = floori(_travelled * BOUNCE_PER_M)
		if bounce > _last_bounce:
			_last_bounce = bounce
			_land_shake()
	if _impact_t >= 0.0:
		_impact_t += delta
		if _impact_t >= IMPACT_SEC:
			_impact_t = -1.0
			_burst.visible = false
	if not _flying and _impact_t < 0.0:
		visible = false
		set_process(false)


func _play_burst(pos: Vector3, normal: Vector3, size: float) -> void:
	var n: Vector3 = normal if normal.length_squared() > 0.01 else Vector3.UP
	var side: Vector3 = n.cross(Vector3.FORWARD if absf(n.z) < 0.9 else Vector3.RIGHT).normalized()
	_burst.global_basis = Basis(side, n, side.cross(n)).orthonormalized()
	_burst.global_position = pos + n * 0.4
	_burst.visible = true
	HdFx.set_smoke_size(_burst_dust, 4.5 * size)
	(_burst_dust.process_material as ParticleProcessMaterial).emission_sphere_radius = 1.2 * size
	(_burst_debris.process_material as ParticleProcessMaterial).emission_sphere_radius = size
	(_burst_debris.process_material as ParticleProcessMaterial).scale_max = 0.9 * size
	_burst_dust.restart()
	_burst_debris.restart()
	_impact_t = 0.0


## Cada bote retumba (sólo si va cerca: lejos ni se nota).
func _land_shake() -> void:
	if _warmup:
		return
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam is CameraRig:
		var d: float = cam.global_position.distance_to(global_position)
		(cam as CameraRig).add_trauma(clampf(6.0 / maxf(d, 1.0), 0.0, 0.18) * _radius / RADIUS)


## Gravilla y cascotes de piedra (cajas que giran y caen).
func _make_debris(amount: int, size: float, light: Color, dark: Color) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = 1.6
	p.one_shot = true
	p.explosiveness = 0.95
	p.emitting = false
	p.local_coords = false
	p.layers = MagicLayer.MAGIC_LAYER
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-40, -40, -40), Vector3(80, 80, 80))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 1.0
	pm.direction = Vector3.UP
	pm.spread = 65.0
	pm.initial_velocity_min = 4.0
	pm.initial_velocity_max = 13.0
	pm.gravity = Vector3(0, -22.0, 0)
	pm.scale_min = 0.25
	pm.scale_max = 0.9
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	pm.angular_velocity_min = -360.0
	pm.angular_velocity_max = 360.0
	pm.particle_flag_rotate_y = true
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 1.0])
	g.colors = PackedColorArray([light, dark])
	var ramp := GradientTexture1D.new()
	ramp.gradient = g
	pm.color_ramp = ramp
	p.process_material = pm
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.9, 0.6, 0.75) * size
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.disable_fog = true
	m.render_priority = 6
	mesh.material = m
	p.draw_pass_1 = mesh
	return p
