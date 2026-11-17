class_name ValleyMilestones
extends Node3D
## El valle cambia a medida que se llena el Pilón (GDD 3 y 4.2). Con cada marca tallada (10, 25,
## 50, 75 y 100 %) aparece algo nuevo que se ve desde el claro:
## - 10 %: auroras de maná en el cielo de noche (sky.gdshader; crecen con el Pilón) y los
##   primeros faroles de maná en la aldea, y dos estandartes en la muralla del castillo.
## - 25 %: faroles en otro barrio y dos estandartes más.
## - 50 %: faroles en el último barrio y banderas en las torres delanteras.
## - 75 %: los campanarios brillan y un gran estandarte cuelga de la torre del homenaje.
## - 100 %: banderas en todas las torres.
## Cada hito es una sola malla (o dos) y una luz por barrio: barato. Al alcanzarlo en directo, lo
## nuevo se enciende parpadeando y un aviso dice qué ha cambiado.

const TOON_SHADER: Shader = preload("res://fx/toon.gdshader")
const GLOW_SHADER: Shader = preload("res://fx/hd/hd_glow.gdshader")
## Centros de los barrios de la aldea y cima del castillo: los mismos que en Valley.
const VILLAGE: Array[Vector3] = [Vector3(-130, 0, -30), Vector3(-85, 0, -105), Vector3(75, 0, -135)]
const CASTLE_TOP := Vector3(85.0, 57.0, -215.0)
## Torres del castillo (x, z, altura) como en Valley._build_castle.
const TOWERS: Array[Vector3] = [
	Vector3(-15, -11, 14),
	Vector3(15, -11, 16),
	Vector3(-15, 11, 13),
	Vector3(15, 11, 15),
	Vector3(-6, -4, 26),
	Vector3(6, 3, 22),
	Vector3(0, -2, 38),
]
const C_WOOD := Color("#5e3a26")
const C_GOLD := Color("#d8a23a")
const C_LANTERN := Color("#ff9be8")
const C_FLAGS: Array[Color] = [Color("#7a4fd0"), Color("#ff7ad9"), Color("#4fb8e8")]
const C_EMBLEM := Color("#ffd27a")
const LANTERNS_PER_BARRIO: int = 8
## Lo que cuenta el aviso de cada hito.
# i18n
const HINTS: PackedStringArray = [
	"EL VALLE DESPIERTA: AURORAS DE MANÁ",
	"LA ALDEA ENCIENDE SUS FAROLES",
	"NUEVAS BANDERAS EN EL CASTILLO",
	"LOS CAMPANARIOS BRILLAN CON TU MANÁ",
	"TODO EL VALLE CELEBRA TU MANÁ",
]

var _groups: Array[Node3D] = []
var _toon: ShaderMaterial
var _glow_mat: StandardMaterial3D
var _halo_mat: ShaderMaterial
var _lights: Array[OmniLight3D] = []
var _light_group: PackedInt32Array = []
var _night: float = 0.0
## Encendido de cada hito (0..1; 1 = ya encendido).
var _appear: PackedFloat32Array = []
var _rng := RandomNumberGenerator.new()


## Fuerza de las auroras (0..1) para un progreso del Pilón: nada antes de la primera marca y
## luego crecen con el nivel visible del Pilón.
static func aurora_strength(ratio: float) -> float:
	if not ManaPylon.mark_reached(ratio, 0):
		return 0.0
	var f0: float = ManaPylon.display_fill(ManaPylon.MARKS[0])
	var k: float = inverse_lerp(f0, 1.0, ManaPylon.display_fill(ratio))
	return lerpf(0.4, 1.0, clampf(k, 0.0, 1.0))


func _ready() -> void:
	add_to_group(&"night_listeners")
	add_to_group(&"valley_milestones")
	_rng.seed = 31
	_toon = ShaderMaterial.new()
	_toon.shader = TOON_SHADER
	_toon.set_shader_parameter("rim", 0.25)
	_glow_mat = StandardMaterial3D.new()
	_glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_glow_mat.vertex_color_use_as_albedo = true
	_halo_mat = ShaderMaterial.new()
	_halo_mat.shader = GLOW_SHADER
	_halo_mat.render_priority = 2
	_halo_mat.set_shader_parameter("color", Color(1.0, 0.55, 0.9))
	_halo_mat.set_shader_parameter("falloff", 2.4)
	for i: int in ManaPylon.MARKS.size():
		var g := Node3D.new()
		g.name = "Mark%d" % i
		add_child(g)
		_groups.append(g)
		_appear.append(1.0)
	for b: int in VILLAGE.size():
		_build_lanterns(_groups[b], VILLAGE[b], b)
	_build_wall_banners(_groups[0], [-5.0, 5.0])
	_build_wall_banners(_groups[1], [-11.0, 11.0])
	_build_flags(_groups[2], [2, 3])
	_build_belfries(_groups[3])
	_build_keep_banner(_groups[3])
	_build_flags(_groups[4], [0, 1, 4, 5, 6])
	refresh()
	Events.pylon_milestone.connect(_on_milestone)
	set_process(false)


## Enseña lo de los hitos ya alcanzados (al empezar, al cargar o en la demo), sin fiesta.
func refresh() -> void:
	var reached: int = ManaPylon.marks_reached(GameState.progression.pylon_ratio())
	for i: int in _groups.size():
		_groups[i].visible = i < reached
		_appear[i] = 1.0
	set_night(_night)


## Hitos ya visibles (para tests y demo).
func shown_count() -> int:
	var n: int = 0
	for g: Node3D in _groups:
		if g.visible:
			n += 1
	return n


## De noche los faroles brillan más, alumbran sus casas y se ve su halo.
func set_night(k: float) -> void:
	_night = k
	_glow_mat.albedo_color = Color(1.3, 1.1, 1.3) * (1.0 + k * 0.6)
	_halo_mat.set_shader_parameter("intensity", lerpf(0.12, 0.9, k))
	for i: int in _lights.size():
		var l: OmniLight3D = _lights[i]
		l.light_energy = k * 2.4
		l.visible = k > 0.05 and _groups[_light_group[i]].visible


func _on_milestone(index: int, _mark: float) -> void:
	if index < 0 or index >= _groups.size():
		return
	_groups[index].visible = true
	_appear[index] = 0.0
	set_night(_night)
	Events.hint.emit(tr(HINTS[index]), Color("#ff9be8"))
	set_process(true)


## Lo nuevo se enciende parpadeando (como una lámpara que coge fuerza).
func _process(delta: float) -> void:
	var busy: bool = false
	for i: int in _appear.size():
		if _appear[i] >= 1.0:
			continue
		busy = true
		_appear[i] = minf(1.0, _appear[i] + delta / 1.6)
		var on: bool = fmod(_appear[i] * 9.0, 1.0) < 0.35 + _appear[i] * 0.65
		_groups[i].visible = on or _appear[i] >= 1.0
	if not busy:
		set_process(false)


func _commit(parent: Node3D, st: SurfaceTool, mat: Material, node_name: String) -> void:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = MeshKit.commit(st)
	mi.material_override = mat
	parent.add_child(mi)


## Faroles de maná en corro alrededor del campanario de un barrio, con su halo y una luz.
func _build_lanterns(parent: Node3D, center: Vector3, barrio: int) -> void:
	var posts: SurfaceTool = MeshKit.begin()
	var glow: SurfaceTool = MeshKit.begin()
	for k: int in LANTERNS_PER_BARRIO:
		var a: float = TAU * (float(k) + 0.5 * float(barrio)) / float(LANTERNS_PER_BARRIO)
		var r: float = 19.0 + _rng.randf_range(-1.5, 2.5)
		var p := Vector3(center.x + cos(a) * r, 0.0, center.z + sin(a) * r)
		p.y = Valley.ground_height(p.x, p.z) - 0.1
		MeshKit.add_prism(posts, p, Vector3.UP, 0.18, 3.4, 0.0, 4, C_WOOD, C_WOOD, _rng)
		MeshKit.add_prism(
			posts, p + Vector3.UP * 4.25, Vector3.UP, 0.5, 0.12, 0.35, 4, C_GOLD, C_GOLD, _rng
		)
		MeshKit.add_box(glow, p + Vector3.UP * 3.85, Vector3(0.75, 0.85, 0.75), C_LANTERN)
		var halo: MeshInstance3D = HdFx.quad(GLOW_SHADER, 4.0, 2)
		halo.material_override = _halo_mat
		halo.position = p + Vector3.UP * 3.85
		parent.add_child(halo)
	_commit(parent, posts, _toon, "LanternPosts")
	_commit(parent, glow, _glow_mat, "LanternGlow")
	var light := OmniLight3D.new()
	light.light_color = Color("#ff9be8")
	light.omni_range = 26.0
	light.shadow_enabled = false
	light.position = center + Vector3(0.0, Valley.ground_height(center.x, center.z) + 6.0, 0.0)
	parent.add_child(light)
	_lights.append(light)
	_light_group.append(_groups.find(parent))


## Estandartes colgados de la muralla delantera del castillo (en `xs`).
func _build_wall_banners(parent: Node3D, xs: Array[float]) -> void:
	var st: SurfaceTool = MeshKit.begin()
	var c: Vector3 = CASTLE_TOP
	for k: int in xs.size():
		var x: float = xs[k]
		var col: Color = C_FLAGS[k % 2]
		var z: float = c.z + 11.0 + 0.25
		MeshKit.add_box(st, Vector3(c.x + x, c.y + 8.3, z), Vector3(3.2, 0.35, 0.35), C_GOLD)
		MeshKit.add_box(st, Vector3(c.x + x, c.y + 5.0, z), Vector3(2.6, 6.2, 0.2), col)
		MeshKit.add_box(st, Vector3(c.x + x, c.y + 5.6, z + 0.15), Vector3(1.1, 1.1, 0.1), C_EMBLEM)
		MeshKit.add_box(
			st, Vector3(c.x + x, c.y + 2.2, z + 0.12), Vector3(2.6, 0.5, 0.1), col.darkened(0.35)
		)
	_commit(parent, st, _toon, "WallBanners")


## Banderas en mástiles sobre los tejados de las torres `towers` (índices en TOWERS).
func _build_flags(parent: Node3D, towers: Array[int]) -> void:
	var st: SurfaceTool = MeshKit.begin()
	for k: int in towers.size():
		var t: Vector3 = TOWERS[towers[k]]
		var r: float = 3.2 if t.z < 30.0 else 4.0
		var apex: Vector3 = CASTLE_TOP + Vector3(t.x, t.z + r * 2.6 - 0.5, t.y)
		var pole_h: float = 7.5
		MeshKit.add_prism(st, apex, Vector3.UP, 0.2, pole_h, 0.4, 4, C_GOLD, C_GOLD, _rng)
		var col: Color = C_FLAGS[(towers[k] + 1) % C_FLAGS.size()]
		var top: Vector3 = apex + Vector3.UP * (pole_h - 1.3)
		MeshKit.add_box(st, top + Vector3(2.2, 0.0, 0.0), Vector3(4.2, 2.4, 0.15), col)
		MeshKit.add_box(st, top + Vector3(2.6, 0.0, 0.1), Vector3(1.0, 1.0, 0.1), C_EMBLEM)
	_commit(parent, st, _toon, "Flags")


## Los campanarios de la aldea se iluminan por dentro.
func _build_belfries(parent: Node3D) -> void:
	var glow: SurfaceTool = MeshKit.begin()
	for b: int in VILLAGE.size():
		var cl: Vector3 = VILLAGE[b]
		var at := Vector3(cl.x, Valley.ground_height(cl.x, cl.z) + 8.4, cl.z)
		MeshKit.add_box(glow, at, Vector3(3.15, 1.6, 3.15), C_LANTERN)
		var halo: MeshInstance3D = HdFx.quad(GLOW_SHADER, 9.0, 2)
		halo.material_override = _halo_mat
		halo.position = at
		parent.add_child(halo)
	_commit(parent, glow, _glow_mat, "Belfries")


## Gran estandarte en la torre del homenaje.
func _build_keep_banner(parent: Node3D) -> void:
	var st: SurfaceTool = MeshKit.begin()
	var t: Vector3 = TOWERS[6]
	var z: float = CASTLE_TOP.z + t.y + 4.25
	var x: float = CASTLE_TOP.x + t.x
	var y: float = CASTLE_TOP.y + 30.5
	MeshKit.add_box(st, Vector3(x, y + 4.6, z), Vector3(4.2, 0.4, 0.4), C_GOLD)
	MeshKit.add_box(st, Vector3(x, y, z), Vector3(3.4, 9.0, 0.2), C_FLAGS[0])
	MeshKit.add_box(st, Vector3(x, y + 1.0, z + 0.15), Vector3(1.6, 1.6, 0.1), C_EMBLEM)
	MeshKit.add_box(st, Vector3(x, y - 1.2, z + 0.15), Vector3(0.6, 2.4, 0.1), C_FLAGS[1])
	_commit(parent, st, _toon, "KeepBanner")
