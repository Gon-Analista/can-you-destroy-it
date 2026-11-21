class_name Fireflies
extends GPUParticles3D
## Luciérnagas de noche: puntitos amarillo verdoso que flotan sobre la hierba alrededor del mago,
## se encienden y se apagan despacio y vagan sin rumbo. Sólo salen de noche (grupo
## `night_listeners`). Son píxeles sólidos (sin transparencia): parpadean creciendo y menguando,
## y brillan con HDR > 1 para que el glow les dé un halo suave.

const AMOUNT: int = 140
## Mitad del lado de la caja donde nacen, alrededor del mago (m).
const SPREAD: float = 18.0

var _player: Node3D


func _ready() -> void:
	add_to_group(&"night_listeners")
	amount = AMOUNT
	lifetime = 6.0
	preprocess = 6.0
	randomness = 1.0
	local_coords = false
	emitting = false
	amount_ratio = 0.0
	var side: float = SPREAD * 2.0 + 12.0
	visibility_aabb = AABB(Vector3(-side * 0.5, -4.0, -side * 0.5), Vector3(side, 12.0, side))
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	process_material = _process_mat()
	draw_pass_1 = _mesh()
	# Si ya es de noche al aparecer, salen sin esperar al próximo cambio de hora.
	var dn: DayNight = get_tree().get_first_node_in_group(&"day_night") as DayNight
	if dn != null:
		set_night(dn.night)


## `k` (0..1): cuánta noche es. Empiezan a salir con el crepúsculo avanzado.
func set_night(k: float) -> void:
	var r: float = smoothstep(0.55, 0.95, k)
	amount_ratio = r
	emitting = r > 0.01


func _process(_delta: float) -> void:
	if not emitting:
		return
	if _player == null:
		_player = get_tree().get_first_node_in_group(&"player") as Node3D
		if _player == null:
			return
	var p: Vector3 = _player.global_position
	global_position = Vector3(p.x, Valley.ground_height(p.x, p.z), p.z)


func _process_mat() -> ParticleProcessMaterial:
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	m.emission_box_extents = Vector3(SPREAD, 0.9, SPREAD)
	m.emission_shape_offset = Vector3(0.0, 1.3, 0.0)
	m.direction = Vector3.UP
	m.spread = 180.0
	m.initial_velocity_min = 0.05
	m.initial_velocity_max = 0.25
	m.gravity = Vector3.ZERO
	m.damping_min = 0.1
	m.damping_max = 0.3
	# Vuelo errático y lento.
	m.turbulence_enabled = true
	m.turbulence_noise_strength = 1.2
	m.turbulence_noise_scale = 3.0
	m.turbulence_noise_speed = Vector3(0.1, 0.05, 0.1)
	m.turbulence_influence_min = 0.05
	m.turbulence_influence_max = 0.12
	# Se enciende y se apaga (dos destellos por vida).
	var c := Curve.new()
	c.add_point(Vector2(0.0, 0.0))
	c.add_point(Vector2(0.15, 1.0))
	c.add_point(Vector2(0.35, 0.15))
	c.add_point(Vector2(0.55, 0.15))
	c.add_point(Vector2(0.7, 1.0))
	c.add_point(Vector2(1.0, 0.0))
	var ct := CurveTexture.new()
	ct.curve = c
	m.scale_curve = ct
	m.scale_min = 0.7
	m.scale_max = 1.2
	# Unas más verdes y otras más amarillas.
	var g := Gradient.new()
	g.set_color(0, Color(2.2, 2.6, 0.7))
	g.set_color(1, Color(2.8, 2.3, 0.5))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	gt.use_hdr = true
	m.color_initial_ramp = gt
	return m


func _mesh() -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(0.12, 0.12)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.disable_fog = true
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	q.material = mat
	return q
