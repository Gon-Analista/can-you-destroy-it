class_name ValleyDetails
extends Node3D
## Detalle cercano del claro, todo por código y barato de dibujar (cada capa es una sola malla
## o un `MultiMesh`): caminos de tierra con losas entre el cristal, el Pilón y el Santuario;
## hierba y flores; rocas; cristales que brotan del suelo alrededor del Cristal Madre; setas,
## tocones y faroles en los caminos; y motas mágicas flotando alrededor del cristal.

const TOON_SHADER: Shader = preload("res://fx/toon.gdshader")
const SHARD_SHADER: Shader = preload("res://crystal/shard.gdshader")
const C_DIRT := Color("#b98d5a")
const C_DIRT_DARK := Color("#9c7247")
const C_STONE := Color("#bdb3bf")
const C_STONE_DARK := Color("#968aa3")
const C_ROCK := Color("#8b92c9")
const C_ROCK_DARK := Color("#6a6fae")
const C_GRASS_DARK := Color("#2f8a3e")
const C_GRASS := Color("#47a84a")
const C_GRASS_LIGHT := Color("#7ccf55")
const C_WOOD := Color("#8a5a3b")
const C_WOOD_DARK := Color("#5e3a26")
const C_MUSH_CAP := Color("#c8423a")
const C_MUSH_STEM := Color("#f1e8d8")
const C_LANTERN := Color("#ffd27a")
const FLOWER_COLORS: Array[Color] = [
	Color("#ff7ad9"), Color("#ffd27a"), Color("#f2f6ff"), Color("#c79bff"), Color("#7fe3ff")
]

@export var seed_value: int = 17
@export var grass_count: int = 5200
@export var flower_count: int = 900

var _toon: ShaderMaterial
var _rng := RandomNumberGenerator.new()
## Tramos de camino (pares de puntos) para no plantar hierba encima.
var _paths: Array[PackedVector2Array] = []
var _lamp_mat: StandardMaterial3D
var _lamp_lights: Array[OmniLight3D] = []


func _ready() -> void:
	add_to_group(&"night_listeners")
	_rng.seed = seed_value
	_toon = ShaderMaterial.new()
	_toon.shader = TOON_SHADER
	_toon.set_shader_parameter("rim", 0.2)
	_build_paths()
	_build_rocks_and_props()
	_build_crystal_outcrops()
	_build_grass()
	_build_flowers()
	_build_motes()


## De noche los faroles brillan más y alumbran el camino.
func set_night(k: float) -> void:
	_lamp_mat.albedo_color = Color(1.5, 1.3, 0.9) * (1.0 + k * 1.2)
	for l: OmniLight3D in _lamp_lights:
		l.light_energy = k * 1.6
		l.visible = k > 0.05


## Puntos del claro.
func _hub() -> Vector3:
	# Donde se juntan los caminos: delante del cristal, a la vista desde el inicio.
	return Vector3(0.0, 0.0, WorldLayout.CRYSTAL_FOOTPRINT + 5.0)


func _ground(x: float, z: float) -> float:
	return Valley.ground_height(x, z)


func _near_path(x: float, z: float, margin: float) -> bool:
	var p := Vector2(x, z)
	for seg: PackedVector2Array in _paths:
		var a: Vector2 = seg[0]
		var b: Vector2 = seg[1]
		var ab: Vector2 = b - a
		var t: float = clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		if p.distance_to(a + ab * t) < margin:
			return true
	return false


## True si (x, z) está libre para plantar algo (no en el cristal, caminos ni edificios).
func _free(x: float, z: float, margin: float) -> bool:
	if Vector2(x, z).length() < WorldLayout.CRYSTAL_FOOTPRINT + 1.0:
		return false
	if Vector2(x - WorldLayout.PYLON.x, z - WorldLayout.PYLON.z).length() < 3.0 + margin:
		return false
	# La trituradora, al este del Pilón.
	if Vector2(x - WorldLayout.PYLON.x - 2.8, z - WorldLayout.PYLON.z).length() < 2.4 + margin:
		return false
	if Vector2(x - WorldLayout.SANCTUM.x, z - WorldLayout.SANCTUM.z).length() < 4.6 + margin:
		return false
	if Vector2(x - WorldLayout.HUT.x, z - WorldLayout.HUT.z).length() < 4.6 + margin:
		return false
	# El Espejo del Archimago, junto al Santuario.
	var mirror := Vector2(WorldLayout.ARCHMAGE_MIRROR.x, WorldLayout.ARCHMAGE_MIRROR.z)
	if Vector2(x, z).distance_to(mirror) < 1.6 + margin:
		return false
	# La Jaula de Familiares, detrás del Pilón.
	var nest := Vector2(WorldLayout.FAMILIAR_NEST.x, WorldLayout.FAMILIAR_NEST.z)
	return Vector2(x, z).distance_to(nest) >= 2.2 + margin and not _near_path(x, z, 1.6 + margin)


func _build_paths() -> void:
	var hub: Vector3 = _hub()
	var ends: Array[Vector3] = [
		# Desde la puerta de la casucha.
		WorldLayout.HUT + Vector3(0, 0, -3.2),
		# El camino del Pilón llega delante de la trituradora (al este del Pilón).
		WorldLayout.PYLON + Vector3(5.6, 0.0, 0.0),
		WorldLayout.SANCTUM + (hub - WorldLayout.SANCTUM).normalized() * 4.2,
	]
	var dirt: SurfaceTool = MeshKit.begin()
	var stones: SurfaceTool = MeshKit.begin()
	for e: Vector3 in ends:
		_paths.append(PackedVector2Array([Vector2(hub.x, hub.z), Vector2(e.x, e.z)]))
		_add_path(dirt, stones, hub, e)
	# Explanada de tierra donde se cruzan.
	_add_patch(dirt, hub, 3.2)
	_add_patch(dirt, WorldLayout.PYLON + Vector3(3.6, 0.0, 0.0), 3.6)
	var d := MeshInstance3D.new()
	d.name = "Paths"
	d.mesh = MeshKit.commit(dirt)
	d.material_override = _toon
	d.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(d)
	var s := MeshInstance3D.new()
	s.name = "Stones"
	s.mesh = MeshKit.commit(stones)
	s.material_override = _toon
	add_child(s)


## Camino de tierra con bordes irregulares y losas planas de piedra salteadas.
func _add_path(dirt: SurfaceTool, stones: SurfaceTool, a: Vector3, b: Vector3) -> void:
	var flat: Vector3 = Vector3(b.x - a.x, 0.0, b.z - a.z)
	var length: float = flat.length()
	var dir: Vector3 = flat / length
	var side := Vector3(-dir.z, 0.0, dir.x)
	var step: float = 1.2
	var n: int = int(length / step)
	var prev_l := Vector3.ZERO
	var prev_r := Vector3.ZERO
	for i: int in n + 1:
		var c: Vector3 = a + dir * (float(i) * step)
		var w: float = 1.1 + _rng.randf_range(-0.25, 0.3)
		var l: Vector3 = c + side * w
		var r: Vector3 = c - side * w
		l.y = _ground(l.x, l.z) + 0.04
		r.y = _ground(r.x, r.z) + 0.04
		if i > 0:
			var col: Color = C_DIRT if i % 3 else C_DIRT_DARK
			MeshKit.add_quad(dirt, prev_l, l, r, prev_r, col, c + Vector3.DOWN * 3.0)
		prev_l = l
		prev_r = r
		if i % 2 == 0 and _rng.randf() < 0.75:
			var off: Vector3 = side * _rng.randf_range(-0.5, 0.5)
			var p: Vector3 = c + off
			p.y = _ground(p.x, p.z) + 0.02
			MeshKit.add_prism(
				stones,
				p,
				Vector3.UP,
				_rng.randf_range(0.2, 0.32),
				0.06,
				0.0,
				6,
				C_STONE_DARK,
				C_STONE,
				_rng,
				0.15
			)


func _add_patch(dirt: SurfaceTool, center: Vector3, radius: float) -> void:
	var sides: int = 12
	var ring: PackedVector3Array = []
	for i: int in sides:
		var a: float = TAU * float(i) / float(sides)
		var p: Vector3 = (
			center + Vector3(cos(a), 0.0, sin(a)) * radius * _rng.randf_range(0.85, 1.15)
		)
		p.y = _ground(p.x, p.z) + 0.035
		ring.append(p)
	var c: Vector3 = center
	c.y = _ground(c.x, c.z) + 0.035
	for i: int in sides:
		MeshKit.add_tri(dirt, c, ring[i], ring[(i + 1) % sides], C_DIRT, c + Vector3.DOWN * 3.0)


func _build_rocks_and_props() -> void:
	var st: SurfaceTool = MeshKit.begin()
	# Rocas: grupos en el borde del claro y alguna suelta.
	for g: int in 16:
		var ang: float = _rng.randf() * TAU
		var r: float = _rng.randf_range(24.0, 46.0)
		var center := Vector3(cos(ang) * r, 0.0, sin(ang) * r)
		for k: int in _rng.randi_range(1, 4):
			var p: Vector3 = (
				center + Vector3(_rng.randf_range(-2.5, 2.5), 0, _rng.randf_range(-2.5, 2.5))
			)
			if not _free(p.x, p.z, 1.0):
				continue
			p.y = _ground(p.x, p.z) - 0.2
			var size: float = _rng.randf_range(0.4, 1.4) * (1.5 if k == 0 else 1.0)
			MeshKit.add_prism(
				st,
				p,
				Vector3(_rng.randf_range(-0.3, 0.3), 1.0, _rng.randf_range(-0.3, 0.3)),
				size,
				size * _rng.randf_range(0.5, 0.9),
				size * 0.5,
				_rng.randi_range(5, 7),
				C_ROCK_DARK,
				C_ROCK,
				_rng,
				0.25,
				0.7
			)
	# Setas rojas en corros cerca del bosque.
	for g: int in 12:
		var ang: float = _rng.randf() * TAU
		var r: float = _rng.randf_range(20.0, 40.0)
		for k: int in _rng.randi_range(2, 5):
			var p := (
				Vector3(cos(ang) * r, 0, sin(ang) * r)
				+ Vector3(_rng.randf_range(-1.0, 1.0), 0, _rng.randf_range(-1.0, 1.0))
			)
			if not _free(p.x, p.z, 0.3):
				continue
			p.y = _ground(p.x, p.z)
			var h: float = _rng.randf_range(0.15, 0.35)
			MeshKit.add_prism(st, p, Vector3.UP, 0.05, h, 0.0, 5, C_MUSH_STEM, C_MUSH_STEM, _rng)
			MeshKit.add_prism(
				st,
				p + Vector3.UP * h,
				Vector3.UP,
				h * 0.6,
				0.04,
				h * 0.35,
				6,
				C_MUSH_CAP,
				C_MUSH_CAP,
				_rng
			)
	# Tocones y troncos caídos en el linde del bosque.
	for g: int in 7:
		var ang: float = _rng.randf() * TAU
		var r: float = _rng.randf_range(30.0, 42.0)
		var p := Vector3(cos(ang) * r, 0, sin(ang) * r)
		if not _free(p.x, p.z, 1.5):
			continue
		p.y = _ground(p.x, p.z) - 0.05
		if g % 2 == 0:
			MeshKit.add_prism(st, p, Vector3.UP, 0.45, 0.5, 0.0, 7, C_WOOD_DARK, C_WOOD, _rng, 0.1)
		else:
			var axis := Vector3(cos(ang + 1.3), 0.0, sin(ang + 1.3))
			MeshKit.add_prism(
				st,
				p + Vector3.UP * 0.3 - axis * 1.6,
				axis,
				0.32,
				3.2,
				0.0,
				7,
				C_WOOD_DARK,
				C_WOOD,
				_rng,
				0.08
			)
	# Faroles a lo largo de los caminos (de piedra, con la luz pintada: sin coste de luces).
	var lamp_mat := StandardMaterial3D.new()
	_lamp_mat = lamp_mat
	lamp_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lamp_mat.vertex_color_use_as_albedo = true
	lamp_mat.albedo_color = Color(1.5, 1.3, 0.9)
	var glow: SurfaceTool = MeshKit.begin()
	for seg: PackedVector2Array in _paths:
		var a := Vector3(seg[0].x, 0, seg[0].y)
		var b := Vector3(seg[1].x, 0, seg[1].y)
		var dir: Vector3 = (b - a).normalized()
		var side := Vector3(-dir.z, 0, dir.x)
		var length: float = a.distance_to(b)
		var k: int = 0
		var d: float = 4.0
		while d < length - 2.0:
			var p: Vector3 = a + dir * d + side * (1.9 if k % 2 == 0 else -1.9)
			p.y = _ground(p.x, p.z)
			if p.distance_to(WorldLayout.HUT) < 5.5:
				d += 6.5
				k += 1
				continue
			MeshKit.add_prism(st, p, Vector3.UP, 0.12, 1.5, 0.0, 4, C_STONE_DARK, C_STONE, _rng)
			MeshKit.add_prism(
				st,
				p + Vector3.UP * 1.95,
				Vector3.UP,
				0.22,
				0.06,
				0.2,
				4,
				C_WOOD_DARK,
				C_WOOD_DARK,
				_rng
			)
			MeshKit.add_box(glow, p + Vector3.UP * 1.72, Vector3(0.24, 0.42, 0.24), C_LANTERN)
			# Luz cálida que sólo se enciende de noche (ver set_night).
			var l := OmniLight3D.new()
			l.light_color = Color("#ffc46b")
			l.omni_range = 7.0
			l.light_energy = 0.0
			l.shadow_enabled = false
			l.visible = false
			l.position = p + Vector3.UP * 1.75
			add_child(l)
			_lamp_lights.append(l)
			d += 6.5
			k += 1
	var props := MeshInstance3D.new()
	props.name = "Props"
	props.mesh = MeshKit.commit(st)
	props.material_override = _toon
	add_child(props)
	var lamps := MeshInstance3D.new()
	lamps.name = "LanternGlow"
	lamps.mesh = MeshKit.commit(glow)
	lamps.material_override = lamp_mat
	add_child(lamps)


## Cristales que brotan del suelo alrededor del Cristal Madre (como raíces que asoman).
func _build_crystal_outcrops() -> void:
	var st: SurfaceTool = MeshKit.begin()
	for g: int in 22:
		var ang: float = _rng.randf() * TAU
		var r: float = _rng.randf_range(
			WorldLayout.CRYSTAL_FOOTPRINT + 2.0, WorldLayout.CRYSTAL_FOOTPRINT + 14.0
		)
		var center := Vector3(cos(ang) * r, 0.0, sin(ang) * r)
		if not _free(center.x, center.z, 1.0):
			continue
		var out := Vector3(cos(ang), 0.0, sin(ang))
		for k: int in _rng.randi_range(1, 4):
			var p: Vector3 = (
				center + Vector3(_rng.randf_range(-0.8, 0.8), 0, _rng.randf_range(-0.8, 0.8))
			)
			p.y = _ground(p.x, p.z) - 0.3
			var axis: Vector3 = (Vector3.UP + out * _rng.randf_range(0.1, 0.7)).normalized()
			var h: float = _rng.randf_range(0.5, 1.8) * (1.6 if k == 0 else 1.0)
			MeshKit.add_prism(
				st, p, axis, h * 0.28, h, h * 0.45, 6, Color.WHITE, Color.WHITE, _rng, 0.1, 0.85
			)
	var mi := MeshInstance3D.new()
	mi.name = "CrystalOutcrops"
	mi.mesh = MeshKit.commit(st)
	var m := ShaderMaterial.new()
	m.shader = SHARD_SHADER
	mi.material_override = m
	add_child(mi)


func _build_grass() -> void:
	var colors: Array[Color] = [C_GRASS_DARK, C_GRASS, C_GRASS_LIGHT]
	for c: int in colors.size():
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _tuft_mesh(colors[c], colors[mini(c + 1, colors.size() - 1)])
		var xforms: Array[Transform3D] = []
		var target: int = grass_count / colors.size()
		var attempts: int = 0
		while xforms.size() < target and attempts < target * 6:
			attempts += 1
			# Más densa cerca del claro y en manchas.
			var r: float = lerpf(WorldLayout.CRYSTAL_FOOTPRINT, 140.0, pow(_rng.randf(), 1.6))
			var ang: float = _rng.randf() * TAU
			var x: float = cos(ang) * r
			var z: float = sin(ang) * r
			if not _free(x, z, 0.0):
				continue
			var s: float = _rng.randf_range(0.7, 1.4)
			var basis := Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(s, s, s))
			xforms.append(Transform3D(basis, Vector3(x, _ground(x, z) - 0.02, z)))
		mm.instance_count = xforms.size()
		for i: int in xforms.size():
			mm.set_instance_transform(i, xforms[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Grass%d" % c
		mmi.multimesh = mm
		mmi.material_override = _toon
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)


## Mata de hierba: cinco hojas finas, con las dos caras (se ve desde cualquier lado).
func _tuft_mesh(col: Color, tip_col: Color) -> ArrayMesh:
	var st: SurfaceTool = MeshKit.begin()
	for k: int in 5:
		var a: float = TAU * float(k) / 5.0 + _rng.randf_range(-0.3, 0.3)
		var d := Vector3(cos(a), 0.0, sin(a))
		var side := Vector3(-d.z, 0.0, d.x) * 0.05
		var base: Vector3 = d * 0.06
		var tip: Vector3 = d * 0.2 + Vector3.UP * _rng.randf_range(0.28, 0.5)
		var c: Color = col if k % 2 else tip_col
		MeshKit.add_tri(st, base - side, base + side, tip, c, base - d)
		MeshKit.add_tri(st, base - side, base + side, tip, c, base + d)
	return MeshKit.commit(st)


func _build_flowers() -> void:
	for c: int in FLOWER_COLORS.size():
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _flower_mesh(FLOWER_COLORS[c])
		var xforms: Array[Transform3D] = []
		var target: int = flower_count / FLOWER_COLORS.size()
		var attempts: int = 0
		while xforms.size() < target and attempts < target * 8:
			attempts += 1
			# En corros: un centro y varias flores alrededor.
			var r: float = _rng.randf_range(WorldLayout.CRYSTAL_FOOTPRINT + 3.0, 110.0)
			var ang: float = _rng.randf() * TAU
			var cx: float = cos(ang) * r
			var cz: float = sin(ang) * r
			for k: int in _rng.randi_range(4, 9):
				var x: float = cx + _rng.randf_range(-1.6, 1.6)
				var z: float = cz + _rng.randf_range(-1.6, 1.6)
				if not _free(x, z, 0.0):
					continue
				var s: float = _rng.randf_range(0.8, 1.3)
				var basis := Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(s, s, s))
				xforms.append(Transform3D(basis, Vector3(x, _ground(x, z), z)))
		mm.instance_count = xforms.size()
		for i: int in xforms.size():
			mm.set_instance_transform(i, xforms[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Flowers%d" % c
		mmi.multimesh = mm
		mmi.material_override = _toon
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)


## Flor: tallo y corola de cinco pétalos con el centro dorado.
func _flower_mesh(col: Color) -> ArrayMesh:
	var st: SurfaceTool = MeshKit.begin()
	var h: float = 0.32
	MeshKit.add_prism(st, Vector3.ZERO, Vector3.UP, 0.015, h, 0.0, 3, C_GRASS_DARK, C_GRASS, _rng)
	var top := Vector3.UP * h
	for k: int in 5:
		var a0: float = TAU * float(k) / 5.0
		var a1: float = a0 + TAU / 10.0
		var p0: Vector3 = top + Vector3(cos(a0), 0.15, sin(a0)) * 0.11
		var p1: Vector3 = top + Vector3(cos(a1), 0.0, sin(a1)) * 0.07
		MeshKit.add_tri(st, top, p0, p1, col, top + Vector3.DOWN)
		var a2: float = a0 - TAU / 10.0
		var p2: Vector3 = top + Vector3(cos(a2), 0.0, sin(a2)) * 0.07
		MeshKit.add_tri(st, top, p2, p0, col, top + Vector3.DOWN)
	MeshKit.add_prism(st, top, Vector3.UP, 0.03, 0.03, 0.0, 4, C_LANTERN, C_LANTERN, _rng)
	return MeshKit.commit(st)


## Motas de maná que flotan y suben despacio alrededor del cristal (y alguna luciérnaga).
func _build_motes() -> void:
	var p := GPUParticles3D.new()
	p.name = "ManaMotes"
	p.amount = 90
	p.lifetime = 6.0
	p.preprocess = 6.0
	p.fixed_fps = 12
	p.interpolate = false
	p.visibility_aabb = AABB(Vector3(-50, -2, -50), Vector3(100, 70, 100))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	pm.emission_ring_axis = Vector3.UP
	pm.emission_ring_height = 6.0
	pm.emission_ring_radius = WorldLayout.CRYSTAL_FOOTPRINT + 10.0
	pm.emission_ring_inner_radius = WorldLayout.CRYSTAL_FOOTPRINT - 2.0
	pm.direction = Vector3.UP
	pm.spread = 25.0
	pm.initial_velocity_min = 0.3
	pm.initial_velocity_max = 0.9
	pm.gravity = Vector3(0, 0.05, 0)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.6
	pm.turbulence_noise_scale = 6.0
	var colors := Gradient.new()
	colors.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	colors.offsets = PackedFloat32Array([0.0, 0.4, 0.75])
	colors.colors = PackedColorArray([Color("#c9f6ff"), Color("#c79bff"), Color("#ff7ad9")])
	var ctex := GradientTexture1D.new()
	ctex.gradient = colors
	pm.color_initial_ramp = ctex
	var fade := Curve.new()
	fade.add_point(Vector2(0.0, 0.0))
	fade.add_point(Vector2(0.15, 1.0))
	fade.add_point(Vector2(0.85, 1.0))
	fade.add_point(Vector2(1.0, 0.0))
	var ftex := CurveTexture.new()
	ftex.curve = fade
	pm.scale_curve = ftex
	p.process_material = pm
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
	p.draw_pass_1 = q
	p.position.y = 1.0
	add_child(p)
