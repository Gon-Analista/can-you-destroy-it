class_name Sanctum
extends Node3D
## El Santuario (GDD 4.3): el templete del mago en el linde del claro, donde se compran las
## mejoras. Empieza casi vacío (un atril con el Grimorio flotando sobre un orbe arcano) y crece
## con cada nivel comprado: aparece un objeto nuevo con un destello (velas, estantería, bola de
## cristal, pociones, estandarte, runas que orbitan, telescopio, mapa estelar...).
## Con F cerca del atril se abre el Grimorio para comprar.

const TOON_SHADER: Shader = preload("res://fx/toon.gdshader")
const SHARD_SHADER: Shader = preload("res://crystal/shard.gdshader")
const BOOK_ORB: SpellVisualDef = preload("res://data/spells/vfx_arcane_orb.tres")
const C_STONE := Color("#e6dddb")
const C_STONE_SHADE := Color("#b9aeb8")
const C_WOOD := Color("#8a5a3b")
const C_WOOD_DARK := Color("#5e3a26")
const C_ROOF := Color("#2a43a7")
const C_ROOF_LIGHT := Color("#3d5fd0")
const C_GOLD := Color("#d8a23a")
const C_PAGE := Color("#f1e8d8")
const C_VIOLET := Color("#654fae")
const C_PINK := Color("#ff7ad9")
const C_CYAN := Color("#a5dae5")
const C_RED := Color("#c8423a")
const PILLARS: int = 6
const RADIUS: float = 3.0
## Orden en que aparecen los objetos al comprar (uno por nivel comprado).
const PROPS: Array[StringName] = [
	&"candles",
	&"bookshelf",
	&"crystal_ball",
	&"potions",
	&"banner",
	&"runes",
	&"telescope",
	&"star_map",
	&"candles_2",
	&"bookshelf_2",
	&"lanterns",
]

## Distancia al atril desde la que se puede abrir el Grimorio (m).
@export var interact_radius: float = 3.6

var _toon: ShaderMaterial
var _player: Node3D
var _book: Node3D
var _book_orb: SpellOrb
var _book_light: OmniLight3D
var _props: Dictionary[StringName, Node3D] = {}
var _shown: int = 0
var _runes: Node3D
var _poof: GPUParticles3D
var _t: float = 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	add_to_group(&"sanctum")
	_rng.seed = 33
	_toon = ShaderMaterial.new()
	_toon.shader = TOON_SHADER
	_toon.set_shader_parameter("rim", 0.3)
	_build_temple()
	_build_lectern()
	_build_props()
	_build_poof()
	_shown = mini(GameState.total_upgrade_levels(), PROPS.size())
	for i: int in PROPS.size():
		_props[PROPS[i]].visible = i < _shown
	Events.upgrade_bought.connect(_on_upgrade_bought)


## True si el jugador está lo bastante cerca del atril para comprar.
func player_in_range() -> bool:
	if _player == null:
		_player = get_tree().get_first_node_in_group(&"player") as Node3D
	if _player == null:
		return false
	var d: Vector3 = _player.global_position - global_position
	d.y = 0.0
	return d.length() <= interact_radius


## Punto al que apunta el marcador del HUD (el Grimorio).
func marker_position() -> Vector3:
	return _book.global_position + Vector3.UP * 0.6


func _unhandled_input(event: InputEvent) -> void:
	if (
		event.is_action_pressed(&"interact")
		and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
		and player_in_range()
	):
		get_viewport().set_input_as_handled()
		Events.grimoire_requested.emit(true)


func _process(delta: float) -> void:
	_t += delta
	var step: float = floor(_t * 12.0) / 12.0
	_book.position.y = 1.55 + sin(step * 1.6) * 0.06
	_book.rotation.y = sin(step * 0.7) * 0.15
	_book_light.light_energy = 1.2 + sin(step * 3.0) * 0.25 + (0.8 if player_in_range() else 0.0)
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam:
		_book_orb.global_basis = cam.global_basis.scaled(Vector3.ONE * 2.2)
	if _runes.visible:
		_runes.rotation.y = step * 0.8
	for i: int in PROPS.size():
		var p: Node3D = _props[PROPS[i]]
		if p.visible and p.scale.x < 0.999:
			p.scale = Vector3.ONE * minf(1.0, p.scale.x + delta * 4.0)


func _on_upgrade_bought(_id: StringName, _level: int) -> void:
	var total: int = mini(GameState.total_upgrade_levels(), PROPS.size())
	while _shown < total:
		var p: Node3D = _props[PROPS[_shown]]
		p.visible = true
		p.scale = Vector3.ONE * 0.05
		_poof.global_position = p.global_position + Vector3.UP * 0.6
		_poof.restart()
		_shown += 1


func _mesh(node_name: String, st: SurfaceTool, at: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = MeshKit.commit(st)
	mi.material_override = _toon
	mi.position = at
	return mi


func _build_temple() -> void:
	var st: SurfaceTool = MeshKit.begin()
	# Suelo: dos escalones de piedra.
	MeshKit.add_prism(
		st, Vector3.ZERO, Vector3.UP, RADIUS + 0.6, 0.25, 0.0, 8, C_STONE_SHADE, C_STONE, _rng
	)
	MeshKit.add_prism(
		st, Vector3.UP * 0.25, Vector3.UP, RADIUS + 0.2, 0.2, 0.0, 8, C_STONE, C_STONE, _rng
	)
	# Columnas de madera con capitel dorado, dejando abierto el lado que mira al cristal.
	for i: int in PILLARS:
		var a: float = TAU * (float(i) + 0.5) / float(PILLARS)
		var p := Vector3(cos(a), 0.0, sin(a)) * RADIUS + Vector3.UP * 0.45
		MeshKit.add_prism(st, p, Vector3.UP, 0.2, 3.2, 0.0, 6, C_WOOD, C_WOOD_DARK, _rng)
		MeshKit.add_prism(
			st, p + Vector3.UP * 3.2, Vector3.UP, 0.3, 0.18, 0.0, 6, C_GOLD, C_GOLD, _rng
		)
	# Anillo bajo el tejado y tejado cónico azul cobalto con remate de oro.
	MeshKit.add_prism(
		st, Vector3.UP * 3.8, Vector3.UP, RADIUS + 0.35, 0.3, 0.0, 12, C_WOOD_DARK, C_WOOD, _rng
	)
	MeshKit.add_prism(
		st, Vector3.UP * 4.1, Vector3.UP, RADIUS + 0.9, 0.12, 2.6, 12, C_ROOF, C_ROOF_LIGHT, _rng
	)
	MeshKit.add_prism(st, Vector3.UP * 6.75, Vector3.UP, 0.14, 0.5, 0.35, 6, C_GOLD, C_GOLD, _rng)
	add_child(_mesh("Temple", st))
	# Colisión: las columnas (el jugador entra en el templete).
	var sb := StaticBody3D.new()
	sb.name = "Collision"
	sb.collision_layer = 1
	sb.collision_mask = 0
	for i: int in PILLARS:
		var a: float = TAU * (float(i) + 0.5) / float(PILLARS)
		var shape := CylinderShape3D.new()
		shape.radius = 0.25
		shape.height = 3.5
		var col := CollisionShape3D.new()
		col.shape = shape
		col.position = Vector3(cos(a), 0.0, sin(a)) * RADIUS + Vector3.UP * 2.0
		sb.add_child(col)
	add_child(sb)


func _build_lectern() -> void:
	var st: SurfaceTool = MeshKit.begin()
	MeshKit.add_box(st, Vector3(0, 0.55, 0), Vector3(0.6, 0.15, 0.6), C_WOOD_DARK)
	MeshKit.add_box(st, Vector3(0, 0.95, 0), Vector3(0.22, 0.8, 0.22), C_WOOD)
	MeshKit.add_box(st, Vector3(0, 1.38, 0), Vector3(0.75, 0.08, 0.5), C_WOOD_DARK, C_WOOD)
	add_child(_mesh("Lectern", st))
	# El Grimorio: dos páginas abiertas que flotan sobre el atril, con un orbe arcano encima.
	_book = Node3D.new()
	_book.name = "Grimoire"
	add_child(_book)
	var bst: SurfaceTool = MeshKit.begin()
	MeshKit.add_box(bst, Vector3(0, 0, 0), Vector3(0.72, 0.06, 0.5), C_VIOLET)
	var page_l := Vector3(-0.17, 0.05, 0)
	var page_r := Vector3(0.17, 0.05, 0)
	MeshKit.add_box(bst, page_l, Vector3(0.32, 0.04, 0.44), C_PAGE)
	MeshKit.add_box(bst, page_r, Vector3(0.32, 0.04, 0.44), C_PAGE)
	var book_mesh: MeshInstance3D = _mesh("Book", bst)
	var book_mat := StandardMaterial3D.new()
	book_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	book_mat.vertex_color_use_as_albedo = true
	book_mat.albedo_color = Color(1.25, 1.2, 1.3)
	book_mesh.material_override = book_mat
	book_mesh.rotation.x = -0.35
	_book.add_child(book_mesh)
	_book_orb = SpellOrb.new()
	_book_orb.name = "BookOrb"
	_book_orb.def = BOOK_ORB
	_book_orb.charge = 0.6
	_book_orb.position = Vector3.UP * 0.55
	_book.add_child(_book_orb)
	_book_light = OmniLight3D.new()
	_book_light.light_color = Color("#c79bff")
	_book_light.omni_range = 4.5
	_book_light.shadow_enabled = false
	_book_light.position = Vector3.UP * 0.5
	_book.add_child(_book_light)


func _build_props() -> void:
	for i: int in PROPS.size():
		var id: StringName = PROPS[i]
		var holder := Node3D.new()
		holder.name = String(id)
		# Repartidos por dentro del templete, detrás del atril (el lado del cristal queda libre).
		var a: float = PI * 0.15 + TAU * 0.7 * float(i) / float(PROPS.size())
		holder.position = Vector3(cos(a), 0.0, sin(a)) * (RADIUS - 0.75) + Vector3.UP * 0.45
		holder.rotation.y = -a + PI * 0.5
		add_child(holder)
		_build_prop(id, holder)
		_props[id] = holder


func _build_prop(id: StringName, holder: Node3D) -> void:
	var st: SurfaceTool = MeshKit.begin()
	match id:
		&"candles", &"candles_2":
			for k: int in 3:
				var p := Vector3((k - 1) * 0.18, 0.0, (k % 2) * 0.12)
				var h: float = 0.35 + k * 0.12
				MeshKit.add_prism(st, p, Vector3.UP, 0.05, h, 0.0, 5, C_PAGE, C_PAGE, _rng)
				MeshKit.add_prism(
					st, p + Vector3.UP * h, Vector3.UP, 0.03, 0.01, 0.1, 4, C_GOLD, C_GOLD, _rng
				)
			_add_light(holder, Color("#ffd27a"), 0.6, Vector3.UP * 0.6)
		&"bookshelf", &"bookshelf_2":
			MeshKit.add_box(st, Vector3(0, 0.8, 0), Vector3(1.0, 1.6, 0.35), C_WOOD_DARK, C_WOOD)
			var cols: Array[Color] = [C_RED, C_VIOLET, C_ROOF, C_GOLD, Color("#3f9a3c")]
			for row: int in 3:
				for k: int in 5:
					var c: Color = cols[(k + row * 2) % cols.size()]
					MeshKit.add_box(
						st,
						Vector3(-0.36 + k * 0.18, 0.32 + row * 0.48, 0.12),
						Vector3(0.12, 0.3 + float((k + row) % 3) * 0.05, 0.14),
						c
					)
		&"crystal_ball":
			MeshKit.add_prism(st, Vector3.ZERO, Vector3.UP, 0.12, 0.8, 0.0, 6, C_GOLD, C_GOLD, _rng)
			var ball: SurfaceTool = MeshKit.begin()
			MeshKit.add_prism(
				ball,
				Vector3.UP * 0.95,
				Vector3.UP,
				0.22,
				0.12,
				0.2,
				8,
				Color.WHITE,
				Color.WHITE,
				_rng
			)
			MeshKit.add_prism(
				ball,
				Vector3.UP * 0.95,
				Vector3.DOWN,
				0.22,
				0.01,
				0.2,
				8,
				Color.WHITE,
				Color.WHITE,
				_rng
			)
			var bm: MeshInstance3D = _mesh("Ball", ball)
			var sm := ShaderMaterial.new()
			sm.shader = SHARD_SHADER
			bm.material_override = sm
			holder.add_child(bm)
			_add_light(holder, C_CYAN, 0.5, Vector3.UP * 1.0)
		&"potions":
			MeshKit.add_box(st, Vector3(0, 0.45, 0), Vector3(0.9, 0.08, 0.5), C_WOOD)
			for k: int in 4:
				var x: float = -0.3 + k * 0.2
				MeshKit.add_box(st, Vector3(x, 0.2, 0), Vector3(0.06, 0.4, 0.06), C_WOOD_DARK)
			var pc: Array[Color] = [C_PINK, C_CYAN, Color("#ffd27a")]
			for k: int in 3:
				var p := Vector3(-0.25 + k * 0.25, 0.49, 0.0)
				MeshKit.add_prism(st, p, Vector3.UP, 0.08, 0.14, 0.12, 6, pc[k], pc[k], _rng)
		&"banner":
			MeshKit.add_prism(
				st, Vector3.ZERO, Vector3.UP, 0.05, 2.4, 0.08, 5, C_WOOD_DARK, C_GOLD, _rng
			)
			MeshKit.add_box(st, Vector3(0.0, 1.75, 0.08), Vector3(0.6, 0.9, 0.04), C_VIOLET)
			MeshKit.add_box(st, Vector3(0.0, 1.3, 0.09), Vector3(0.6, 0.08, 0.05), C_GOLD)
			MeshKit.add_box(st, Vector3(0.0, 1.85, 0.11), Vector3(0.16, 0.16, 0.03), C_PINK)
		&"runes":
			_runes = holder
			holder.position = Vector3(0.0, 1.2, 0.0)
			for k: int in 4:
				var a: float = TAU * float(k) / 4.0
				MeshKit.add_box(
					st,
					Vector3(cos(a), 0.15 * float(k % 2), sin(a)) * 1.0,
					Vector3(0.16, 0.24, 0.06),
					C_CYAN
				)
		&"telescope":
			MeshKit.add_prism(
				st, Vector3.ZERO, Vector3.UP, 0.06, 0.9, 0.0, 4, C_WOOD_DARK, C_WOOD, _rng
			)
			MeshKit.add_prism(
				st,
				Vector3(0, 0.9, 0),
				Vector3(0.3, 1.0, 0.0),
				0.1,
				0.9,
				0.0,
				6,
				C_GOLD,
				C_GOLD,
				_rng
			)
		&"star_map":
			MeshKit.add_box(st, Vector3(0, 1.0, 0), Vector3(0.9, 1.1, 0.06), C_ROOF)
			for k: int in 7:
				var p := Vector3(_rng.randf_range(-0.35, 0.35), _rng.randf_range(0.6, 1.4), 0.04)
				MeshKit.add_box(st, p, Vector3(0.05, 0.05, 0.02), Color("#ffd27a"))
			MeshKit.add_prism(
				st, Vector3.ZERO, Vector3.UP, 0.05, 0.5, 0.0, 4, C_WOOD_DARK, C_WOOD, _rng
			)
		&"lanterns":
			for k: int in 2:
				var p := Vector3((k * 2 - 1) * 0.3, 0.0, 0.0)
				MeshKit.add_prism(st, p, Vector3.UP, 0.04, 1.4, 0.0, 4, C_WOOD_DARK, C_WOOD, _rng)
				MeshKit.add_box(
					st, p + Vector3.UP * 1.5, Vector3(0.18, 0.24, 0.18), Color("#ffd27a")
				)
			_add_light(holder, Color("#ffd27a"), 0.7, Vector3.UP * 1.5)
	holder.add_child(_mesh("Mesh", st))


func _add_light(holder: Node3D, color: Color, energy: float, at: Vector3) -> void:
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.omni_range = 2.5
	l.shadow_enabled = false
	l.position = at
	holder.add_child(l)


## Destello al aparecer un objeto nuevo.
func _build_poof() -> void:
	_poof = GPUParticles3D.new()
	_poof.name = "Poof"
	_poof.one_shot = true
	_poof.emitting = false
	_poof.amount = 28
	_poof.lifetime = 0.9
	_poof.explosiveness = 0.95
	_poof.fixed_fps = 24
	_poof.local_coords = false
	_poof.top_level = true
	_poof.visibility_aabb = AABB(Vector3(-4, -4, -4), Vector3(8, 8, 8))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.5
	pm.direction = Vector3.UP
	pm.spread = 180.0
	pm.initial_velocity_min = 1.0
	pm.initial_velocity_max = 2.5
	pm.damping_min = 2.0
	pm.damping_max = 3.0
	pm.gravity = Vector3(0, 0.6, 0)
	var colors := Gradient.new()
	colors.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	colors.offsets = PackedFloat32Array([0.0, 0.4, 0.7])
	colors.colors = PackedColorArray([Color("#ffd27a"), Color("#ff7ad9"), Color("#c79bff")])
	var ctex := GradientTexture1D.new()
	ctex.gradient = colors
	pm.color_initial_ramp = ctex
	_poof.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.14, 0.14)
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
