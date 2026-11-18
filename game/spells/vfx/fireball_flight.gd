class_name FireballFlight
extends Node3D
## La Bola de Fuego en vuelo (`SpellVisualDef.fireball_flight`), hija de un `SparkProjectile`:
## lo que hace que se lea como una bola de fuego y no como una gota plana.
## - Cuerpo: esfera que hierve (`hd_fireball.gdshader`, capa 1) con el limbo rojo oscuro, un
##   núcleo blanco pequeño y lenguas que se escapan hacia atrás de la trayectoria en pantalla.
## - Corona de detrás (capa 0): más grande, lenta y roja; da profundidad y recorta el contorno.
## - Halo que tiñe el fondo (no lo quema a blanco) y luz cálida sobre el cristal (`FireGlow`).
## - Cola de cometa: bocanadas de fuego soltadas en el mundo (`hd_fire_puff.gdshader`) que se
##   enfrían de amarillo a rojo y acaban en una voluta de humo; las de cerca se ven más grandes.
## Con el nivel (0..1) es más grande, más caliente y más rabiosa; el color sale de la rampa del
## hechizo (el Eco de Fuego, rosa y violeta). Todo se crea una vez y se reutiliza.

const BALL_SHADER: Shader = preload("res://fx/hd/hd_fireball.gdshader")
const PUFF_SHADER: Shader = preload("res://fx/hd/hd_fire_puff.gdshader")
## Tamaño de la corona y del halo respecto al cuerpo.
const BACK_SIZE: float = 1.6
const GLOW_SIZE: float = 2.6
## Radio de la bola en unidades del quad del cuerpo (ver `hd_fireball`).
const BODY_RADIUS: float = 0.34
## Lo que dura la llegada (se hincha y se deshace antes de que lo tape el estallido).
const RELEASE_SEC: float = 0.16
## Lo que tarda en apagarse la cola tras la llegada (el proyectil espera antes de volver al pool).
const TAIL_SEC: float = 0.5
## Distancia (m) al blanco a la que su luz empieza a teñir el cristal.
const GLOW_FROM: float = 22.0
## Cuánto crece la bola de nivel 1 a nivel 10.
const LEVEL_GROWTH: float = 0.35
## Cuerpo respecto al orbe de la mano (las lenguas y la corona lo agrandan).
const BODY_SCALE: float = 0.8

var _ball: Node3D
var _body_mat: ShaderMaterial
var _back_mat: ShaderMaterial
var _glow_mat: ShaderMaterial
## Cuerpo y corona (se configuran igual).
var _mats: Array[ShaderMaterial] = []
var _puffs: GPUParticles3D
var _puff_pm: ParticleProcessMaterial
var _puff_mat: ShaderMaterial
var _base: float = 1.0
var _level: float = 0.0
var _color := Color(1.0, 0.5, 0.2)
var _glow_on: bool = false
var _puff_size: float = 0.0
var _release_t: float = -1.0


func _ready() -> void:
	_ball = Node3D.new()
	_ball.name = "Ball"
	add_child(_ball)
	var glow: MeshInstance3D = HdFx.quad(HdFx.GLOW_SHADER, GLOW_SIZE, 3)
	glow.name = "Glow"
	_glow_mat = glow.material_override
	_glow_mat.set_shader_parameter("falloff", 2.6)
	# Tiñe en vez de sumar: sobre el cielo y el cristal claros, un halo aditivo se lavaba a blanco.
	_glow_mat.set_shader_parameter("cover", 0.6)
	_ball.add_child(glow)
	var back: MeshInstance3D = HdFx.quad(BALL_SHADER, BACK_SIZE, 4)
	back.name = "Corona"
	_back_mat = back.material_override
	_back_mat.set_shader_parameter("layer", 0)
	_back_mat.set_shader_parameter("radius", BODY_RADIUS / BACK_SIZE)
	_ball.add_child(back)
	var body: MeshInstance3D = HdFx.quad(BALL_SHADER, 1.0, 5)
	body.name = "Body"
	_body_mat = body.material_override
	_body_mat.set_shader_parameter("radius", BODY_RADIUS)
	_ball.add_child(body)
	_mats = [_body_mat, _back_mat]
	_build_puffs()
	visible = false
	set_process(false)


## Colores del hechizo (la rampa del núcleo) y su luz.
func setup(def: SpellVisualDef) -> void:
	var ramp: GradientTexture1D = HdFx.smooth_ramp(def.core_ramp)
	_body_mat.set_shader_parameter("ramp", ramp)
	_back_mat.set_shader_parameter("ramp", ramp)
	_puff_mat.set_shader_parameter("ramp", ramp)
	_color = def.light_color
	_glow_mat.set_shader_parameter("color", def.light_color)
	# El humo, del color más frío de la rampa, apagado: gris rojizo (o violeta en el Eco).
	var cold: Color = def.core_ramp.sample(1.0)
	_puff_mat.set_shader_parameter(
		"smoke_color", Color(cold.r * 0.35 + 0.1, cold.g * 0.35 + 0.08, cold.b * 0.35 + 0.09)
	)


## Sale de la mano: `size` es el diámetro del cuerpo (m) a escala 1; `level` 0..1.
func launch(size: float, level: float) -> void:
	_base = size * BODY_SCALE
	_level = level
	_release_t = -1.0
	var seed_f: float = randf() * 10.0
	for m: ShaderMaterial in _mats:
		m.set_shader_parameter("seed", seed_f)
		m.set_shader_parameter("heat", level)
		m.set_shader_parameter("speed", lerpf(1.0, 1.6, level))
		m.set_shader_parameter("burst", 0.0)
		m.set_shader_parameter("fade", 1.0)
		m.set_shader_parameter("intensity", lerpf(1.0, 1.1, level))
	_puff_mat.set_shader_parameter("heat", level)
	_glow_mat.set_shader_parameter("intensity", lerpf(0.22, 0.36, level))
	_puffs.amount_ratio = lerpf(0.6, 1.0, level)
	_puffs.emitting = false
	_ball.visible = true
	_ball.scale = Vector3.ONE * size
	visible = true
	# Sólo procesa la llegada (ver `release`).
	set_process(false)


## Escala en vuelo (la que tendría el orbe: igual en la mano y crece al alejarse).
func set_view_scale(s: float, final_scale: float) -> void:
	# Con el nivel, hasta un tercio más grande.
	var lv: float = 1.0 + _level * LEVEL_GROWTH
	_ball.scale = Vector3.ONE * _base * s * lv
	# Las bocanadas nacen casi del tamaño de la bola ya lejos y menguan: la cola se afila.
	var puff: float = _base * final_scale * lv * BODY_RADIUS * 2.0
	# Sólo si cambia (al salir de la mano): tocar el material cada fotograma lo rehace.
	if absf(puff - _puff_size) > _puff_size * 0.02:
		_puff_size = puff
		_puff_pm.scale_min = puff * 0.4
		_puff_pm.scale_max = puff * 0.6


## Hacia dónde se escapan las lenguas en pantalla (UV, y hacia abajo) y lo largas que son.
func set_flow(dir: Vector2, strength: float) -> void:
	var s: float = strength * lerpf(1.0, 1.3, _level)
	for m: ShaderMaterial in _mats:
		m.set_shader_parameter("flow", dir)
		m.set_shader_parameter("flow_strength", s)


## Cola de cometa: bocanadas mientras vuela lejos del origen `from`. Salen hacia atrás y, en el
## plano de la pantalla, hacia donde se ve el origen: casi siempre se aleja de frente (de la mano
## a la mira) y así la cola cae hacia la mano en vez de quedarse escondida detrás de la bola.
func set_tail(on: bool, from: Vector3) -> void:
	if on and not _puffs.emitting:
		var back: Vector3 = (from - global_position).normalized()
		var cam: Camera3D = get_viewport().get_camera_3d()
		var fwd: Vector3 = -cam.global_basis.z if cam else Vector3.FORWARD
		var side: Vector3 = back - fwd * back.dot(fwd)
		if side.length_squared() > 0.000001:
			side = side.normalized()
		_puff_pm.direction = (back + side).normalized()
	_puffs.emitting = on


## Luz cálida en el cristal: crece al acercarse a `target`.
func glow_crystal(target: Vector3) -> void:
	var d: float = global_position.distance_to(target)
	var k: float = 1.0 - smoothstep(4.0, GLOW_FROM, d)
	var radius: float = _base * lerpf(14.0, 22.0, _level)
	FireGlow.put(global_position, radius, _color, k * lerpf(0.65, 1.0, _level))
	_glow_on = true


## Llega al blanco: se hincha y se deshace (el estallido lo pone `HdImpact`).
func release() -> void:
	_puffs.emitting = false
	_release_t = 0.0
	_glow_off()
	set_process(true)


func stop() -> void:
	_puffs.emitting = false
	_ball.visible = false
	_release_t = -1.0
	_glow_off()
	visible = false
	set_process(false)


func _process(delta: float) -> void:
	if _release_t < 0.0:
		return
	_release_t += delta
	var k: float = clampf(_release_t / RELEASE_SEC, 0.0, 1.0)
	for m: ShaderMaterial in _mats:
		m.set_shader_parameter("burst", k)
		m.set_shader_parameter("fade", 1.0 - k * k)
	_glow_mat.set_shader_parameter("intensity", lerpf(0.5, 0.0, k) * (1.0 + _level))
	if k >= 1.0:
		_ball.visible = false
		_release_t = -1.0
		set_process(false)


func _glow_off() -> void:
	if _glow_on:
		FireGlow.put(global_position, 1.0, _color, 0.0)
		_glow_on = false


func _build_puffs() -> void:
	_puffs = GPUParticles3D.new()
	_puffs.name = "Tail"
	_puffs.amount = 72
	_puffs.lifetime = 0.38
	_puffs.local_coords = false
	_puffs.emitting = false
	_puffs.fixed_fps = 0
	_puffs.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	_puffs.layers = MagicLayer.MAGIC_LAYER
	_puffs.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_puffs.visibility_aabb = AABB(Vector3(-80, -80, -80), Vector3(160, 160, 160))
	_puff_pm = ParticleProcessMaterial.new()
	_puff_pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	_puff_pm.emission_sphere_radius = 0.25
	_puff_pm.direction = Vector3.BACK
	_puff_pm.spread = 30.0
	_puff_pm.initial_velocity_min = 5.0
	_puff_pm.initial_velocity_max = 9.0
	# El calor sube: la cola se curva un poco hacia arriba.
	_puff_pm.gravity = Vector3(0.0, 2.5, 0.0)
	_puff_pm.damping_min = 1.0
	_puff_pm.damping_max = 3.0
	# El ángulo al azar hace de semilla del ruido de cada bocanada (CUSTOM.x).
	_puff_pm.angle_min = -180.0
	_puff_pm.angle_max = 180.0
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.85))
	curve.add_point(Vector2(0.15, 1.0))
	curve.add_point(Vector2(1.0, 0.3))
	var ct := CurveTexture.new()
	ct.curve = curve
	_puff_pm.scale_curve = ct
	_puffs.process_material = _puff_pm
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	_puff_mat = ShaderMaterial.new()
	_puff_mat.shader = PUFF_SHADER
	_puff_mat.render_priority = 2
	q.material = _puff_mat
	_puffs.draw_pass_1 = q
	add_child(_puffs)
