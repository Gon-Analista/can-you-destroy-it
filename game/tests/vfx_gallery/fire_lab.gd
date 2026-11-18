extends Node3D
## Laboratorio de fuego: escena mínima (sin el valle) con varios fuegos HD lado a lado sobre
## un fondo claro y otro oscuro, para ajustar `hd_fire.gdshader` deprisa.
##
## godot --path game res://tests/vfx_gallery/fire_lab.tscn --write-movie /tmp/f/f.png
##   --fixed-fps 30 --quit-after 60
## Fila de arriba: orbe de la Bola de Fuego a carga 0,3 y 1, llama en vuelo (flujo de lado) y
## fuego del cristal (flujo hacia arriba, lenguas largas). Fila de abajo: estallido, carga del
## Meteoro (roca en el fuego), Llama de la mano y Eco de Fuego. Con `--meteor`: la roca del
## Meteoro en llamas (izquierda) y su impacto (derecha).

const DEFS: Array[String] = [
	"res://data/spells/vfx_fireball.tres",
	"res://data/spells/vfx_earth.tres",
	"res://data/spells/vfx_flame.tres",
	"res://data/spells/vfx_echo_fire.tres",
]

var _burst_mat: ShaderMaterial
var _mover: Node3D
var _t: float = 0.0


func _ready() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.25, 0.45, 0.85)
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_strength = 1.0
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 1.2
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	var levels: PackedFloat32Array = [0.0, 1.0, 0.8, 0.45, 0.0, 0.0, 0.0]
	for i: int in 7:
		env.set_glow_level(i, levels[i])
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 0, 4.0)
	cam.fov = 60.0
	add_child(cam)
	if OS.get_cmdline_user_args().has("--meteor"):
		_meteor_lab()
		return
	# Fondo: mitad clara (cielo, cristal) y franja oscura abajo.
	_backdrop(Vector3(0, 0.9, -1.0), Vector2(12, 2.2), Color(0.75, 0.88, 1.0))
	_backdrop(Vector3(0, -1.2, -1.0), Vector2(12, 2.0), Color(0.1, 0.16, 0.12))
	var ramp: GradientTexture1D = HdFx.smooth_ramp((load(DEFS[0]) as SpellVisualDef).core_ramp)
	_orb(DEFS[0], Vector3(-2.4, 0.9, 0), 0.3, 3.0)
	_orb(DEFS[0], Vector3(-0.8, 0.9, 0), 1.0, 3.0)
	var fly: ShaderMaterial = _fire(Vector3(0.8, 0.9, 0), 1.6, ramp)
	fly.set_shader_parameter("flow", Vector2(1.0, -0.3).normalized())
	fly.set_shader_parameter("flow_strength", 2.6)
	var burn: ShaderMaterial = _fire(Vector3(2.4, 0.9, 0), 1.6, ramp)
	burn.set_shader_parameter("intensity", 1.0)
	burn.set_shader_parameter("turbulence", 0.55)
	burn.set_shader_parameter("flow_strength", 2.2)
	burn.set_shader_parameter("speed", 2.4)
	_burst_mat = _fire(Vector3(-2.4, -1.0, 0), 1.6, ramp)
	_orb("res://data/spells/vfx_meteor.tres", Vector3(-0.8, -1.0, 0), 1.0, 3.0)
	_orb(DEFS[2], Vector3(0.8, -1.0, 0), 1.0, 3.0)
	_orb(DEFS[3], Vector3(2.4, -1.0, 0), 1.0, 3.0)
	# Estela de la Bola de Fuego: un punto que da vueltas por la franja oscura y la clara.
	_mover = Node3D.new()
	add_child(_mover)
	var trail := SpellTrail.new()
	trail.hd = true
	_mover.add_child(trail)
	trail.width = 0.16
	trail.length_sec = 0.5
	var recipe: SpellRecipe = load("res://data/spells/recipe_fireball.tres")
	trail.set_ramp(recipe.tier.trail_ramp)
	trail.start(Vector3.ZERO)


func _process(delta: float) -> void:
	_t += delta
	if _mover:
		_mover.position = Vector3(cos(_t * 2.4) * 2.6, sin(_t * 4.8) * 0.5 - 0.1, 0.4)
	if _burst_mat == null:
		return
	var k: float = fmod(_t, 1.2)
	_burst_mat.set_shader_parameter("burst", k / 0.6 if k < 0.6 else 0.0)


func _backdrop(pos: Vector3, size: Vector2, col: Color) -> void:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = size
	mi.mesh = q
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col
	mi.material_override = m
	mi.position = pos
	add_child(mi)


func _fire(pos: Vector3, size: float, ramp: Texture2D) -> ShaderMaterial:
	var mi: MeshInstance3D = HdFx.quad(HdFx.FIRE_SHADER, size, 5)
	mi.position = pos
	add_child(mi)
	var m: ShaderMaterial = mi.material_override
	m.set_shader_parameter("ramp", ramp)
	m.set_shader_parameter("seed", randf() * 10.0)
	m.set_shader_parameter("intensity", 1.15)
	return m


func _orb(path: String, pos: Vector3, charge: float, s: float) -> SpellOrb:
	var o := SpellOrb.new()
	o.def = load(path) as SpellVisualDef
	o.charge = charge
	o.position = pos
	o.scale = Vector3.ONE * s
	add_child(o)
	return o


func _meteor_lab() -> void:
	# A la distancia del juego: cámara a 45 m, fondo grande.
	(get_viewport().get_camera_3d()).position = Vector3(0, 0, 45.0)
	if OS.get_cmdline_user_args().has("--close"):
		# --close: la roca de cerca.
		(get_viewport().get_camera_3d()).position = Vector3(-12, 6, 14.0)
	_backdrop(Vector3(0, 10, -2.0), Vector2(140, 26), Color(0.75, 0.88, 1.0))
	_backdrop(Vector3(0, -14, -2.0), Vector2(140, 22), Color(0.1, 0.16, 0.12))
	var at := Vector3(-12.0, 6.0, 0.0)
	var orb := _orb("res://data/spells/vfx_meteor.tres", at, 1.0, 26.0)
	orb.set_flow(Vector2(0.4, -1.0).normalized(), 2.4)
	orb.set_center_shift(0.0)
	orb.rock_enabled = false
	var rock := MeteorRock.new()
	rock.position = at
	add_child(rock)
	rock.launch(at + Vector3(-20, 50, 0), at, 1.0, true)
	var boom := MeteorRock.new()
	add_child(boom)
	var hit_at := Vector3(10, -8.0, 0)
	boom.launch(hit_at + Vector3(0, 50, 0), hit_at, 1.0, true)
	get_tree().create_timer(0.1).timeout.connect(
		func() -> void: boom.impact(hit_at, Vector3(0, 1, 0.3).normalized(), true)
	)
