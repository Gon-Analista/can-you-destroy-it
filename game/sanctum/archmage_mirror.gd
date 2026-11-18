class_name ArchmageMirror
extends Node3D
## El Espejo del Archimago (GDD 4.3, "desde el inicio"): un espejo alto con marco de oro en arco
## junto al Santuario. Su cristal es una niebla de estrellas con los colores del rango del mago y
## arriba lleva el escudo del rango, que cambia (con destello) al subir. Al acercarse despierta:
## el cristal se aclara, la luz crece y zumba. Con F cerca se abren sus estadísticas
## (`MirrorScreen`). La guía de objetivos no lleva aquí: es un sitio para curiosear.

const TOON_SHADER: Shader = preload("res://fx/toon.gdshader")
const GLASS_SHADER: Shader = preload("res://sanctum/mirror_glass.gdshader")
const HUM: AudioStream = preload("res://audio/sfx/amb_mirror_hum_loop.ogg")
const GUIDE: GuidanceDef = preload("res://data/ui/guidance.tres")
const C_STONE := Color("#e6dddb")
const C_STONE_SHADE := Color("#b9aeb8")
const C_GOLD := Color("#d8a23a")
const C_GOLD_LIGHT := Color("#ffd27a")
const C_GOLD_DARK := Color("#7a4f17")
const C_BACK := Color("#2a1d4a")
## Cristal (m): ancho, alto desde su base, altura de su base y del centro del arco.
const GLASS_W: float = 1.32
const GLASS_H: float = 2.74
const GLASS_BASE: float = 0.45
const ARCH_Y: float = 2.45
const ARCH_R: float = 0.74
const CREST_Y: float = 3.62
## Distancia (m) para abrirlo con F y para que despierte.
const INTERACT_RADIUS: float = 2.6
const AWAKE_RADIUS: float = 7.0

var _player: Node3D
var _glass_mat: ShaderMaterial
var _crest: Sprite3D
var _light: OmniLight3D
var _hum: AudioStreamPlayer3D
var _motes: GPUParticles3D
var _awake: float = 0.0
var _flash: float = 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	add_to_group(&"archmage_mirror")
	_rng.seed = 71
	_build_frame()
	_build_glass()
	_build_crest()
	_build_fx()
	show_rank(GameState.progression.rank)
	Events.rank_changed.connect(
		func(r: int, _p: int) -> void:
			show_rank(r)
			_flash = 1.0
	)


## True si el jugador está lo bastante cerca para abrir el espejo.
func player_in_range() -> bool:
	return _player_distance() <= INTERACT_RADIUS


## Punto encima del espejo (para el aviso y las capturas).
func marker_position() -> Vector3:
	return to_global(Vector3(0.0, CREST_Y, 0.0))


## Aviso junto a la mira: entero las primeras veces, luego sólo la tecla (como el Grimorio).
func prompt() -> String:
	if not player_in_range():
		return ""
	var mode: int = Guidance.prompt_mode(
		GameState.progression.times(&"mirror"), GUIDE.grimoire_learn, GUIDE.grimoire_forget
	)
	return tr("[F] ESPEJO DEL ARCHIMAGO") if mode == Guidance.Prompt.FULL else ""


func prompt_icon() -> bool:
	if not player_in_range():
		return false
	var mode: int = Guidance.prompt_mode(
		GameState.progression.times(&"mirror"), GUIDE.grimoire_learn, GUIDE.grimoire_forget
	)
	return mode == Guidance.Prompt.ICON


func _player_distance() -> float:
	if _player == null:
		_player = get_tree().get_first_node_in_group(&"player") as Node3D
	if _player == null:
		return INF
	var d: Vector3 = _player.global_position - global_position
	d.y = 0.0
	return d.length()


func _unhandled_input(event: InputEvent) -> void:
	if (
		event.is_action_pressed(&"interact")
		and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
		and player_in_range()
	):
		get_viewport().set_input_as_handled()
		GameState.progression.learn(&"mirror")
		_flash = maxf(_flash, 0.5)
		Events.mirror_requested.emit()


func _process(delta: float) -> void:
	var near: float = 1.0 - smoothstep(INTERACT_RADIUS, AWAKE_RADIUS, _player_distance())
	_awake = lerpf(_awake, near, 1.0 - exp(-delta * 3.0))
	_flash = maxf(0.0, _flash - delta * 0.8)
	_glass_mat.set_shader_parameter("awake", _awake)
	_glass_mat.set_shader_parameter("flash", _flash * _flash)
	_light.light_energy = 0.5 + _awake * 0.9 + _flash * 3.0
	_hum.volume_db = lerpf(-30.0, -10.0, _awake)
	_crest.modulate = Color.WHITE.lerp(Color(2.5, 2.5, 2.5), _flash)


## Colores del cristal, luz y escudo del rango `rank`.
func show_rank(rank: int) -> void:
	var def: RankDef = WizardRanks.def_of(rank)
	_glass_mat.set_shader_parameter("color_deep", def.color_dark.darkened(0.55))
	_glass_mat.set_shader_parameter("color_mid", def.color_dark.lerp(def.color, 0.45))
	_glass_mat.set_shader_parameter("color_light", def.color_light)
	_crest.texture = RankCrest.texture(rank)
	_light.light_color = def.color.lerp(Color.WHITE, 0.3)
	var pm: ParticleProcessMaterial = _motes.process_material
	pm.color = def.color_light


func _mesh(node_name: String, st: SurfaceTool) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = MeshKit.commit(st)
	var m := ShaderMaterial.new()
	m.shader = TOON_SHADER
	m.set_shader_parameter("rim", 0.35)
	mi.material_override = m
	add_child(mi)
	return mi


## Zócalo de piedra, postes y arco de oro (con su filo oscuro por dentro), trasera y remate.
func _build_frame() -> void:
	var st: SurfaceTool = MeshKit.begin()
	MeshKit.add_box(st, Vector3(0, 0.15, 0), Vector3(1.9, 0.3, 0.9), C_STONE_SHADE, C_STONE)
	MeshKit.add_box(st, Vector3(0, 0.375, 0), Vector3(1.6, 0.15, 0.7), C_STONE, C_STONE)
	var half: float = GLASS_W * 0.5 + 0.08
	for side: float in [-1.0, 1.0]:
		MeshKit.add_box(
			st,
			Vector3(side * half, (GLASS_BASE + ARCH_Y) * 0.5, 0.0),
			Vector3(0.16, ARCH_Y - GLASS_BASE, 0.2),
			C_GOLD
		)
		MeshKit.add_box(
			st,
			Vector3(side * (half - 0.09), (GLASS_BASE + ARCH_Y) * 0.5, 0.05),
			Vector3(0.04, ARCH_Y - GLASS_BASE, 0.12),
			C_GOLD_DARK
		)
		# Volutas a media altura.
		MeshKit.add_box(st, Vector3(side * (half + 0.1), 1.3, 0.0), Vector3(0.1, 0.3, 0.14), C_GOLD)
	MeshKit.add_box(st, Vector3(0, GLASS_BASE + 0.03, 0.0), Vector3(half * 2.0, 0.1, 0.22), C_GOLD)
	# Arco: prismas de cuatro lados a lo largo de un semicírculo.
	var segs: int = 10
	for i: int in segs:
		var a0: float = PI * float(i) / float(segs)
		var a1: float = PI * float(i + 1) / float(segs)
		var p0 := Vector3(cos(a0) * half, ARCH_Y + sin(a0) * half, 0.0)
		var p1 := Vector3(cos(a1) * half, ARCH_Y + sin(a1) * half, 0.0)
		MeshKit.add_prism(st, p0, p1 - p0, 0.1, p0.distance_to(p1), 0.0, 4, C_GOLD, C_GOLD, _rng)
	# Trasera (oscura) para que el espejo no se vea hueco por detrás.
	MeshKit.add_box(
		st, Vector3(0, (GLASS_BASE + ARCH_Y) * 0.5, -0.07), Vector3(half * 2.0, 2.0, 0.06), C_BACK
	)
	MeshKit.add_prism(
		st, Vector3(0, ARCH_Y, -0.07), Vector3.BACK, half, 0.06, 0.0, 12, C_BACK, C_BACK, _rng
	)
	# Remate: peana dorada para el escudo.
	var top_y: float = ARCH_Y + half
	MeshKit.add_prism(
		st, Vector3(0, top_y, 0), Vector3.UP, 0.14, 0.14, 0.12, 6, C_GOLD, C_GOLD_LIGHT, _rng
	)
	_mesh("Frame", st)
	# Colisión: el zócalo y el espejo (no se atraviesa).
	var sb := StaticBody3D.new()
	sb.name = "Collision"
	sb.collision_layer = 1
	sb.collision_mask = 0
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.9, 3.3, 0.9)
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position.y = 1.65
	sb.add_child(col)
	add_child(sb)


func _build_glass() -> void:
	var q := QuadMesh.new()
	q.size = Vector2(GLASS_W, GLASS_H)
	var mi := MeshInstance3D.new()
	mi.name = "Glass"
	mi.mesh = q
	_glass_mat = ShaderMaterial.new()
	_glass_mat.shader = GLASS_SHADER
	_glass_mat.set_shader_parameter("size_m", Vector2(GLASS_W, GLASS_H))
	_glass_mat.set_shader_parameter("arch_y", ARCH_Y - GLASS_BASE)
	_glass_mat.set_shader_parameter("arch_r", GLASS_W * 0.5)
	mi.material_override = _glass_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(0.0, GLASS_BASE + GLASS_H * 0.5, 0.02)
	add_child(mi)


func _build_crest() -> void:
	_crest = Sprite3D.new()
	_crest.name = "Crest"
	_crest.pixel_size = 0.032
	_crest.shaded = false
	_crest.double_sided = true
	_crest.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_crest.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	_crest.position = Vector3(0.0, CREST_Y, 0.04)
	_crest.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_crest)


## Luz del cristal, motas de luz que suben delante y el zumbido.
func _build_fx() -> void:
	_light = OmniLight3D.new()
	_light.name = "Light"
	_light.omni_range = 5.0
	_light.shadow_enabled = false
	_light.position = Vector3(0.0, 1.8, 0.7)
	add_child(_light)
	_motes = GPUParticles3D.new()
	_motes.name = "Motes"
	_motes.amount = 14
	_motes.lifetime = 3.0
	_motes.fixed_fps = 12
	_motes.local_coords = false
	_motes.position = Vector3(0.0, 1.0, 0.3)
	_motes.visibility_aabb = AABB(Vector3(-2, -1, -2), Vector3(4, 5, 4))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.6, 0.6, 0.2)
	pm.direction = Vector3.UP
	pm.spread = 20.0
	pm.initial_velocity_min = 0.15
	pm.initial_velocity_max = 0.4
	pm.gravity = Vector3.ZERO
	_motes.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.06, 0.06)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = PixelTextures.star()
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	quad.material = m
	_motes.draw_pass_1 = quad
	add_child(_motes)
	_hum = AudioStreamPlayer3D.new()
	_hum.name = "Hum"
	_hum.bus = &"Ambience"
	_hum.stream = HUM
	_hum.unit_size = 3.0
	_hum.max_distance = 16.0
	_hum.volume_db = -30.0
	_hum.position.y = 1.8
	_hum.autoplay = true
	add_child(_hum)
