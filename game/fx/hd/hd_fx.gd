class_name HdFx
extends RefCounted
## Piezas comunes de los efectos HD de magia: texturas suaves, rampas de color y sistemas de
## partículas (brasas suaves, chispas con estela, humo). Todo se crea una vez y se reutiliza.

const FIRE_SHADER: Shader = preload("res://fx/hd/hd_fire.gdshader")
const GLOW_SHADER: Shader = preload("res://fx/hd/hd_glow.gdshader")
const RING_SHADER: Shader = preload("res://fx/hd/hd_ring.gdshader")

## Cuánto queda de cada destello (1 entero; menos con "reducir destellos"). Lo pone `Settings`;
## vive aquí para que los efectos no nombren el autoload (los tests `--script` no lo ven).
static var flash_scale: float = 1.0
static var _dot: Texture2D
static var _billow: Texture2D
static var _star: Texture2D
static var _ramps: Dictionary[Gradient, GradientTexture1D] = {}


## Punto de luz suave (centro blanco que se desvanece): la base de brasas y chispas.
static func soft_dot() -> Texture2D:
	if _dot == null:
		# Luz pura para mezcla premultiplicada: el color es la máscara y el alfa es 0 (suma luz
		# sin tapar el fondo).
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.2, 1.0])
		g.colors = PackedColorArray(
			[Color(1, 1, 1, 0), Color(0.55, 0.55, 0.55, 0), Color(0, 0, 0, 0)]
		)
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 64
		t.height = 64
		_dot = t
	return _dot


## Destello en estrella de cuatro puntas, suave (luz pura: color = máscara, alfa 0).
static func soft_star() -> Texture2D:
	if _star == null:
		var size: int = 64
		var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
		var c: float = (size - 1) * 0.5
		for y: int in size:
			for x: int in size:
				var dx: float = absf(x - c) / c
				var dy: float = absf(y - c) / c
				var cross: float = maxf(
					pow(maxf(0.0, 1.0 - dx), 6.0) * pow(maxf(0.0, 1.0 - dy * 9.0), 2.0),
					pow(maxf(0.0, 1.0 - dy), 6.0) * pow(maxf(0.0, 1.0 - dx * 9.0), 2.0)
				)
				var core: float = pow(maxf(0.0, 1.0 - sqrt(dx * dx + dy * dy) * 2.2), 2.0)
				var v: float = clampf(cross + core, 0.0, 1.0)
				img.set_pixel(x, y, Color(v, v, v, 0.0))
		_star = ImageTexture.create_from_image(img)
	return _star


## Nube de humo con volumen: bolas pequeñas que se solapan, con el contorno roto por ruido (nada
## de discos) y luz de arriba a la izquierda (el color es la luz, el alfa la densidad).
static func soft_billow() -> Texture2D:
	if _billow == null:
		var size: int = 64
		var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
		var noise := FastNoiseLite.new()
		noise.seed = 77
		noise.frequency = 0.07
		noise.fractal_octaves = 3
		var blobs: Array[Vector3] = [
			Vector3(0.5, 0.56, 0.17),
			Vector3(0.37, 0.5, 0.13),
			Vector3(0.63, 0.47, 0.14),
			Vector3(0.52, 0.36, 0.13),
			Vector3(0.36, 0.66, 0.1),
			Vector3(0.64, 0.66, 0.11),
			Vector3(0.43, 0.33, 0.09),
		]
		var light := Vector2(-0.6, -0.8)
		for y: int in size:
			for x: int in size:
				var uv := Vector2((x + 0.5) / size, (y + 0.5) / size)
				var d: float = 0.0
				var grad := Vector2.ZERO
				for b: Vector3 in blobs:
					var off: Vector2 = uv - Vector2(b.x, b.y)
					var w: float = exp(-off.length_squared() / (b.z * b.z))
					d += w
					grad += off * w
				var n: float = noise.get_noise_2d(x, y) * 0.5 + 0.5
				d *= 0.45 + 1.1 * n
				# Ventana suave: el contorno lo deciden las bolas y el ruido, no un círculo.
				var win: float = 1.0 - smoothstep(0.28, 0.5, uv.distance_to(Vector2(0.5, 0.5)))
				var a: float = smoothstep(0.2, 1.0, d) * win * 0.9
				# Las caras que miran a la luz, más claras; abajo, algo más oscuro.
				var lit: float = 0.74 - grad.normalized().dot(light) * 0.2 + (n - 0.5) * 0.25
				lit = clampf(lit - uv.y * 0.12, 0.45, 1.0)
				img.set_pixel(x, y, Color(lit, lit, lit, a))
		_billow = ImageTexture.create_from_image(img)
	return _billow


## Rampa suave (lineal y HDR) a partir de un degradado cualquiera (aunque sea por bandas).
static func smooth_ramp(src: Gradient) -> GradientTexture1D:
	if _ramps.has(src):
		return _ramps[src]
	var g: Gradient = src.duplicate()
	g.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_LINEAR
	var t := GradientTexture1D.new()
	t.gradient = g
	t.use_hdr = true
	t.width = 128
	_ramps[src] = t
	return t


static func quad(shader: Shader, size: float, priority: int) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2.ONE * size
	mi.mesh = q
	var m := ShaderMaterial.new()
	m.shader = shader
	m.render_priority = priority
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 4.0
	mi.layers = MagicLayer.MAGIC_LAYER
	return mi


## Material aditivo para partículas suaves (el color sale del degradado de la partícula).
static func additive_particle_material(hdr: float = 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_PREMULT_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(hdr, hdr, hdr, 0.0)
	m.albedo_texture = soft_dot()
	m.disable_fog = true
	m.no_depth_test = true
	m.render_priority = 6
	return m


static func color_ramp(colors: PackedColorArray, alpha_out: bool = true) -> GradientTexture1D:
	var g := Gradient.new()
	var n: int = colors.size()
	var offs := PackedFloat32Array()
	var cols := PackedColorArray()
	for i: int in n:
		offs.append(float(i) / float(maxi(n - 1, 1)))
		cols.append(colors[i])
	if alpha_out:
		cols[n - 1] = Color(cols[n - 1], 0.0)
	g.offsets = offs
	g.colors = cols
	var t := GradientTexture1D.new()
	t.gradient = g
	t.use_hdr = true
	return t


## Brasas / motas suaves que flotan (sin estela).
static func embers(amount: int, size: float, colors: PackedColorArray) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = 0.8
	p.local_coords = false
	p.layers = MagicLayer.MAGIC_LAYER
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-60, -60, -60), Vector3(120, 120, 120))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.1
	pm.direction = Vector3.UP
	pm.spread = 180.0
	pm.initial_velocity_min = 0.2
	pm.initial_velocity_max = 0.8
	pm.gravity = Vector3(0, 0.8, 0)
	pm.damping_min = 0.5
	pm.damping_max = 1.5
	pm.scale_min = 0.4
	pm.scale_max = 1.0
	pm.color_ramp = color_ramp(colors)
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1))
	curve.add_point(Vector2(1, 0))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.scale_curve = ct
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.4
	pm.turbulence_noise_scale = 2.0
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2.ONE * size
	q.material = additive_particle_material(1.0)
	p.draw_pass_1 = q
	return p


## Chispas con estela (rayas de luz que salen disparadas y caen): de un solo disparo.
static func sparks(
	amount: int, speed: float, size: float, colors: PackedColorArray
) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = 0.7
	p.one_shot = true
	p.explosiveness = 0.95
	p.emitting = false
	p.local_coords = false
	p.layers = MagicLayer.MAGIC_LAYER
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-60, -60, -60), Vector3(120, 120, 120))
	p.trail_enabled = true
	p.trail_lifetime = 0.12
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.1
	pm.direction = Vector3.UP
	pm.spread = 180.0
	pm.initial_velocity_min = speed * 0.4
	pm.initial_velocity_max = speed
	pm.gravity = Vector3(0, -9.0, 0)
	pm.damping_min = speed * 0.3
	pm.damping_max = speed * 0.8
	pm.color_ramp = color_ramp(colors)
	p.process_material = pm
	var ribbon := RibbonTrailMesh.new()
	ribbon.shape = RibbonTrailMesh.SHAPE_CROSS
	ribbon.size = size
	ribbon.sections = 4
	ribbon.section_length = 0.1
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0))
	curve.add_point(Vector2(0.3, 1))
	curve.add_point(Vector2(1, 0.2))
	ribbon.curve = curve
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_PREMULT_ALPHA
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(1.6, 1.6, 1.6, 0.0)
	m.use_particle_trails = true
	m.disable_fog = true
	m.no_depth_test = true
	m.render_priority = 7
	ribbon.material = m
	p.draw_pass_1 = ribbon
	return p


## Humo suave que sube y se abre (alfa normal, para dar volumen y contraste al fuego).
static func smoke(amount: int, size: float, color: Color) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = 1.4
	p.one_shot = true
	p.explosiveness = 0.8
	p.emitting = false
	p.local_coords = false
	p.layers = MagicLayer.MAGIC_LAYER
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-60, -60, -60), Vector3(120, 120, 120))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = size * 0.3
	pm.direction = Vector3.UP
	pm.spread = 60.0
	pm.initial_velocity_min = 0.6
	pm.initial_velocity_max = 1.8
	pm.gravity = Vector3(0, 0.6, 0)
	pm.damping_min = 1.0
	pm.damping_max = 2.0
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	pm.scale_min = 0.6
	pm.scale_max = 1.2
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.4))
	curve.add_point(Vector2(1, 1.6))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.scale_curve = ct
	# Humo sutil: nunca más de un tercio de opaco (si no, una mancha gris tapa el fuego).
	pm.color_ramp = color_ramp(PackedColorArray([Color(color, 0.0), Color(color, 0.32), color]))
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2.ONE * size
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = soft_billow()
	m.disable_fog = true
	m.no_depth_test = true
	m.render_priority = 2
	# Pegado a la cámara se desvanece: si no, una bocanada cercana vela toda la pantalla.
	m.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	q.material = m
	p.draw_pass_1 = q
	set_smoke_size(p, size)
	return p


## Cambia el tamaño de las bocanadas de un `smoke()` (y a qué distancia de la cámara se apagan).
static func set_smoke_size(p: GPUParticles3D, size: float) -> void:
	var q: QuadMesh = p.draw_pass_1
	q.size = Vector2.ONE * size
	var m: StandardMaterial3D = q.material
	m.distance_fade_min_distance = size * 0.4
	m.distance_fade_max_distance = size * 1.6
