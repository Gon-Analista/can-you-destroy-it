class_name FamiliarNest
extends Node3D
## La Jaula de Familiares (GDD 4.3): una pajarera mágica junto al Pilón. Zócalo de piedra, un
## poste de madera con seis perchas en espiral, un nido con un huevo de cristal arriba y una
## cúpula de varillas doradas rematada por un tejadito azul y un cristal que late. Aparece de
## golpe (con destello y sonido) al comprar el primer familiar; los familiares descansan en las
## perchas entre viaje y viaje.

const TOON_SHADER: Shader = preload("res://fx/toon.gdshader")
const SHARD_SHADER: Shader = preload("res://crystal/shard.gdshader")
const C_STONE := Color("#d9d0d4")
const C_STONE_SHADE := Color("#b9aeb8")
const C_WOOD := Color("#8a5a3b")
const C_WOOD_DARK := Color("#5e3a26")
const C_TWIG := Color("#a8774a")
const C_GOLD := Color("#d8a23a")
const C_GOLD_LIGHT := Color("#ffd27a")
const C_ROOF := Color("#2a43a7")
const C_ROOF_LIGHT := Color("#3d5fd0")
const C_VIOLET := Color("#654fae")
const PERCHES: int = 6
const BASE_R: float = 1.5
const DOME_TOP: float = 3.6
const POP_SEC: float = 0.7

var _toon: ShaderMaterial
var _rng := RandomNumberGenerator.new()
var _perch_points: PackedVector3Array = PackedVector3Array()
var _gem: MeshInstance3D
var _light: OmniLight3D
var _col: CollisionShape3D
var _poof: GPUParticles3D
var _sparkle: GPUParticles3D
var _pop_t: float = -1.0
var _t: float = 0.0
var _night: float = 0.0


func _ready() -> void:
	add_to_group(&"night_listeners")
	_rng.seed = 61
	_toon = ShaderMaterial.new()
	_toon.shader = TOON_SHADER
	_toon.set_shader_parameter("rim", 0.3)
	_build_base_and_post()
	_build_dome()
	_build_gem()
	_build_fx()
	_build_collision()
	visible = false
	set_process(false)


func set_night(k: float) -> void:
	_night = k


## Punto de la percha `i` (global): donde se posa un familiar.
func perch(i: int) -> Vector3:
	return to_global(_perch_points[i % PERCHES])


## Dirección (global, horizontal) hacia fuera de la percha `i`: hacia donde mira el familiar.
func perch_out(i: int) -> Vector3:
	var p: Vector3 = _perch_points[i % PERCHES]
	return (global_basis * Vector3(p.x, 0.0, p.z)).normalized()


## El nido de arriba (de donde salen los familiares nuevos).
func top() -> Vector3:
	return to_global(Vector3(0.0, 2.95, 0.0))


## Se enseña ya montada (partida cargada).
func show_now() -> void:
	visible = true
	_col.disabled = false
	scale = Vector3.ONE
	set_process(true)


## Aparece con un salto elástico, destello de estrellas y chispas HD.
func pop_in() -> void:
	visible = true
	_col.disabled = false
	scale = Vector3.ONE * 0.05
	_pop_t = 0.0
	_poof.restart()
	_sparkle.restart()
	set_process(true)


## Destello de "familiar nuevo" en el nido (sin el salto).
func celebrate() -> void:
	_sparkle.restart()


## Pantalla de carga: el destello una vez para compilar sus materiales.
func warm_up() -> void:
	_poof.restart()
	_sparkle.restart()


func _process(delta: float) -> void:
	_t += delta
	if _pop_t >= 0.0:
		_pop_t += delta
		var k: float = clampf(_pop_t / POP_SEC, 0.0, 1.0)
		# Rebote elástico: se pasa un poco y vuelve.
		var s: float = 1.0 + sin(k * PI * 2.5) * (1.0 - k) * 0.35
		scale = (
			Vector3.ONE
			* maxf(0.05, s * smoothstep(0.0, 0.35, k) + (1.0 - smoothstep(0.0, 0.35, k)) * 0.05)
		)
		if k >= 1.0:
			scale = Vector3.ONE
			_pop_t = -1.0
	# El cristal del remate late a 12 fps (y alumbra más de noche).
	var step: float = floor(_t * 12.0) / 12.0
	var pulse: float = 0.5 + 0.5 * sin(step * 2.4)
	_light.light_energy = (0.5 + pulse * 0.4) * (1.0 + _night * 1.6)
	_gem.rotation.y = step * 0.9


func _mesh(node_name: String, st: SurfaceTool) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = MeshKit.commit(st)
	mi.material_override = _toon
	add_child(mi)
	return mi


func _build_base_and_post() -> void:
	var st: SurfaceTool = MeshKit.begin()
	MeshKit.add_prism(
		st, Vector3.ZERO, Vector3.UP, BASE_R + 0.15, 0.18, 0.0, 10, C_STONE_SHADE, C_STONE, _rng
	)
	MeshKit.add_prism(
		st, Vector3.UP * 0.18, Vector3.UP, BASE_R - 0.1, 0.14, 0.0, 10, C_STONE, C_STONE, _rng
	)
	# Poste central y nido arriba (cono invertido de ramitas con un borde más claro).
	MeshKit.add_prism(
		st, Vector3.UP * 0.3, Vector3.UP, 0.13, 2.5, 0.0, 6, C_WOOD, C_WOOD_DARK, _rng
	)
	MeshKit.add_prism(
		st, Vector3.UP * 2.95, Vector3.DOWN, 0.42, 0.001, 0.3, 8, C_TWIG, C_TWIG, _rng, 0.15
	)
	MeshKit.add_prism(
		st, Vector3.UP * 2.88, Vector3.UP, 0.46, 0.1, 0.0, 9, C_WOOD_DARK, C_TWIG, _rng, 0.12
	)
	# Perchas en espiral: un brazo de madera con un tope dorado; el familiar se posa al final.
	for i: int in PERCHES:
		var a: float = TAU * float(i) / float(PERCHES) + 0.4
		var h: float = 1.05 + 0.3 * float(i)
		var dir := Vector3(cos(a), 0.0, sin(a))
		var tip: Vector3 = dir * (BASE_R - 0.35) + Vector3.UP * h
		MeshKit.add_prism(
			st, Vector3.UP * h, dir, 0.045, BASE_R - 0.35, 0.0, 5, C_WOOD, C_WOOD, _rng
		)
		MeshKit.add_prism(st, tip - dir * 0.05, dir, 0.07, 0.1, 0.0, 6, C_GOLD, C_GOLD, _rng)
		_perch_points.append(tip - dir * 0.2 + Vector3.UP * 0.4)
	# Comedero de cristalitos al pie.
	for k: int in 5:
		var a: float = TAU * float(k) / 5.0
		var p := Vector3(cos(a), 0.0, sin(a)) * 0.35 + Vector3.UP * 0.32
		MeshKit.add_prism(
			st,
			p,
			Vector3(cos(a) * 0.4, 1.0, sin(a) * 0.4),
			0.06,
			0.12,
			0.1,
			5,
			C_VIOLET,
			C_ROOF_LIGHT,
			_rng
		)
	_mesh("BaseAndPost", st)


## Cúpula de varillas doradas, abierta abajo por el lado del camino, con tejadito y remate.
func _build_dome() -> void:
	var st: SurfaceTool = MeshKit.begin()
	var bars: int = 10
	var ring_h: float = 0.32
	for i: int in bars:
		var a: float = TAU * float(i) / float(bars)
		var segs: int = 5
		var prev := Vector3(cos(a), 0.0, sin(a)) * (BASE_R - 0.08) + Vector3.UP * ring_h
		for s: int in range(1, segs + 1):
			var f: float = float(s) / float(segs)
			# Arco de cúpula: radio que se cierra y altura que sube (cuarto de elipse).
			var r: float = (BASE_R - 0.08) * cos(f * PI * 0.5) + 0.32 * f
			var y: float = ring_h + (DOME_TOP - 0.25 - ring_h) * sin(f * PI * 0.5)
			var p := Vector3(cos(a) * r, y, sin(a) * r)
			MeshKit.add_prism(
				st, prev, p - prev, 0.05, prev.distance_to(p), 0.0, 4, C_GOLD_LIGHT, C_GOLD, _rng
			)
			prev = p
	# Aros horizontales: abajo, a media altura y arriba.
	for ring: Array in [[ring_h, BASE_R - 0.08], [1.95, (BASE_R - 0.08) * 0.82 + 0.1]]:
		var y: float = ring[0]
		var r: float = ring[1]
		var n: int = 16
		for i: int in n:
			var a0: float = TAU * float(i) / float(n)
			var a1: float = TAU * float(i + 1) / float(n)
			var p0 := Vector3(cos(a0) * r, y, sin(a0) * r)
			var p1 := Vector3(cos(a1) * r, y, sin(a1) * r)
			MeshKit.add_prism(
				st, p0, p1 - p0, 0.03, p0.distance_to(p1), 0.0, 4, C_GOLD_LIGHT, C_GOLD, _rng
			)
	# Tejadito cónico azul cobalto, como el Santuario, y un aro de madera debajo.
	MeshKit.add_prism(
		st, Vector3.UP * (DOME_TOP - 0.3), Vector3.UP, 0.42, 0.12, 0.0, 8, C_WOOD_DARK, C_WOOD, _rng
	)
	MeshKit.add_prism(
		st,
		Vector3.UP * (DOME_TOP - 0.18),
		Vector3.UP,
		0.62,
		0.06,
		0.62,
		8,
		C_ROOF,
		C_ROOF_LIGHT,
		_rng
	)
	_mesh("Dome", st)


## Remate: un cristal violeta que gira despacio y alumbra la jaula.
func _build_gem() -> void:
	var st: SurfaceTool = MeshKit.begin()
	MeshKit.add_prism(
		st, Vector3.ZERO, Vector3.UP, 0.12, 0.16, 0.16, 6, Color.WHITE, Color.WHITE, _rng
	)
	MeshKit.add_prism(
		st, Vector3.ZERO, Vector3.DOWN, 0.12, 0.001, 0.12, 6, Color.WHITE, Color.WHITE, _rng
	)
	_gem = MeshInstance3D.new()
	_gem.name = "Gem"
	_gem.mesh = MeshKit.commit(st)
	var mat := ShaderMaterial.new()
	mat.shader = SHARD_SHADER
	_gem.material_override = mat
	_gem.position = Vector3.UP * (DOME_TOP + 0.62)
	add_child(_gem)
	_light = OmniLight3D.new()
	_light.name = "Light"
	_light.light_color = Color("#c79bff")
	_light.omni_range = 4.5
	_light.shadow_enabled = false
	_light.position = Vector3.UP * 2.6
	add_child(_light)


func _build_fx() -> void:
	# Estrellas pixel art al aparecer (como los objetos nuevos del Santuario).
	_poof = GPUParticles3D.new()
	_poof.name = "Poof"
	_poof.one_shot = true
	_poof.emitting = false
	_poof.amount = 40
	_poof.lifetime = 1.1
	_poof.explosiveness = 0.95
	_poof.fixed_fps = 24
	_poof.local_coords = false
	_poof.visibility_aabb = AABB(Vector3(-5, -2, -5), Vector3(10, 8, 10))
	_poof.position = Vector3.UP * 1.6
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 1.2
	pm.direction = Vector3.UP
	pm.spread = 180.0
	pm.initial_velocity_min = 1.5
	pm.initial_velocity_max = 3.5
	pm.damping_min = 2.0
	pm.damping_max = 3.0
	pm.gravity = Vector3(0, 0.6, 0)
	var colors := Gradient.new()
	colors.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	colors.offsets = PackedFloat32Array([0.0, 0.4, 0.7])
	colors.colors = PackedColorArray([Color("#ffd27a"), Color("#a5dae5"), Color("#c79bff")])
	var ctex := GradientTexture1D.new()
	ctex.gradient = colors
	pm.color_initial_ramp = ctex
	_poof.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.2, 0.2)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = PixelTextures.star()
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	q.material = m
	_poof.draw_pass_1 = q
	add_child(_poof)
	# Chispas HD que suben en espiral (capa de magia).
	_sparkle = HdFx.sparks(
		36, 6.0, 0.03, PackedColorArray([Color(2.2, 2.0, 1.4), Color(1.2, 0.7, 2.0)])
	)
	_sparkle.name = "Sparkle"
	_sparkle.lifetime = 1.0
	(_sparkle.process_material as ParticleProcessMaterial).gravity = Vector3(0, -2.0, 0)
	(_sparkle.process_material as ParticleProcessMaterial).emission_sphere_radius = 0.6
	_sparkle.position = Vector3.UP * 3.0
	# Con prueba de profundidad: el cristal la tapa (regla de la capa de magia).
	(_sparkle.draw_pass_1 as RibbonTrailMesh).material.set(&"no_depth_test", false)
	add_child(_sparkle)


func _build_collision() -> void:
	var sb := StaticBody3D.new()
	sb.name = "Collision"
	sb.collision_layer = 1
	sb.collision_mask = 0
	var shape := CylinderShape3D.new()
	shape.radius = BASE_R
	shape.height = DOME_TOP
	_col = CollisionShape3D.new()
	_col.shape = shape
	_col.position = Vector3.UP * DOME_TOP * 0.5
	# Sin colisión mientras no exista (antes del primer familiar).
	_col.disabled = true
	sb.add_child(_col)
	add_child(sb)
