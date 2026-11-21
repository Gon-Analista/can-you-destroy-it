class_name StaffVitrine
extends Node3D
## La Vitrina del Báculo (GDD 4.3): una urna de cristal con marco de oro sobre un pedestal de
## piedra, junto al camino del Santuario. Dentro flota el báculo y gira despacio. Mientras no se
## tiene, es sólo una silueta apagada con un candado encima; al comprarlo se enciende con un
## destello y su gema toma el color del elemento que lleva. Con F cerca se abre el Grimorio por
## la constelación del Báculo (sus mejoras siguen viviendo allí: aquí sólo está el sitio).

const TOON_SHADER: Shader = preload("res://fx/toon.gdshader")
const SUMMON_SFX: AudioStream = preload("res://audio/sfx/sfx_staff_summon_01.ogg")
const GUIDE: GuidanceDef = preload("res://data/ui/guidance.tres")
const C_STONE := Color("#e6dddb")
const C_STONE_SHADE := Color("#b9aeb8")
const C_GOLD := Color("#d8a23a")
const C_GOLD_LIGHT := Color("#ffd27a")
const C_WOOD := Color("#8a5a3b")
const C_WOOD_DARK := Color("#5e3a26")
const C_VELVET := Color("#4a2a6e")
const C_GLASS := Color(0.75, 0.9, 1.0, 0.16)
const C_DIM := Color("#8a8496")
## Color de la gema mientras no se sabe su elemento (el de la página del Báculo).
const C_GEM := Color("#ffc46b")
## Pedestal: alto de la losa de terciopelo; urna: medio lado y alto.
const TOP_Y: float = 1.0
const CASE_HALF: float = 0.42
const CASE_H: float = 1.95
## Centro del báculo dentro de la urna.
const STAFF_Y: float = TOP_Y + 0.12
const INTERACT_RADIUS: float = 2.6
const AWAKE_RADIUS: float = 7.0
## Página del Grimorio que abre (la constelación del Báculo).
const PAGE: StringName = &"staff"

var _player: Node3D
var _staff: Node3D
var _staff_mat: ShaderMaterial
var _gem_mat: ShaderMaterial
var _lock: Sprite3D
var _light: OmniLight3D
var _owned: bool = false
var _gem_color: Color = C_GEM
var _awake: float = 0.0
var _flash: float = 0.0
var _t: float = 0.0
var _check: float = 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	add_to_group(&"staff_vitrine")
	_rng.seed = 57
	_build_case()
	_build_staff()
	_build_fx()
	_apply_owned(StaffCombos.owned(), false)
	Events.upgrade_bought.connect(
		func(id: StringName, _l: int) -> void:
			if id == StaffCombos.UNLOCK_UPGRADE:
				_apply_owned(true, true)
	)


## True si el jugador está lo bastante cerca para abrirla.
func player_in_range() -> bool:
	return _player_distance() <= INTERACT_RADIUS


func is_owned() -> bool:
	return _owned


## Punto encima de la urna (aviso, nombre de la estación y capturas).
func marker_position() -> Vector3:
	return to_global(Vector3(0.0, CASE_H + TOP_Y + 0.35, 0.0))


## Aviso junto a la mira: entero las primeras veces, luego sólo la tecla (como el Espejo).
func prompt() -> String:
	if not player_in_range():
		return ""
	var mode: int = Guidance.prompt_mode(
		GameState.progression.times(&"staff_vitrine"), GUIDE.grimoire_learn, GUIDE.grimoire_forget
	)
	return tr("[F] VITRINA DEL BÁCULO") if mode == Guidance.Prompt.FULL else ""


func prompt_icon() -> bool:
	if not player_in_range():
		return false
	var mode: int = Guidance.prompt_mode(
		GameState.progression.times(&"staff_vitrine"), GUIDE.grimoire_learn, GUIDE.grimoire_forget
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
		GameState.progression.learn(&"staff_vitrine")
		_flash = maxf(_flash, 0.5)
		Events.grimoire_page_requested.emit(PAGE)


func _process(delta: float) -> void:
	_t += delta
	_check -= delta
	if _check <= 0.0:
		_check = 0.5
		if _owned:
			_gem_color = _current_gem_color()
	var near: float = 1.0 - smoothstep(INTERACT_RADIUS, AWAKE_RADIUS, _player_distance())
	_awake = lerpf(_awake, near, 1.0 - exp(-delta * 3.0))
	_flash = maxf(0.0, _flash - delta * 0.7)
	# El báculo gira y flota a escalones de 1/12 s (pixel art), más despacio si no se tiene.
	var step: float = floorf(_t * 12.0) / 12.0
	var speed: float = 0.6 if _owned else 0.2
	_staff.rotation.y = step * speed
	_staff.position.y = STAFF_Y + (sin(step * 1.4) * 0.05 if _owned else 0.0)
	var on: float = 1.0 if _owned else 0.25
	var glow: float = (0.35 + _awake * 0.5) * on + _flash * 1.5
	_gem_mat.set_shader_parameter("albedo", _gem_color if _owned else C_DIM)
	_gem_mat.set_shader_parameter("self_light", glow)
	_light.light_color = _gem_color.lerp(Color.WHITE, 0.4)
	_light.light_energy = (0.25 + _awake * 0.6) * on + _flash * 2.5


## Enciende (o apaga) el báculo de la urna; con `celebrate`, destello y gong.
func _apply_owned(owned: bool, celebrate: bool) -> void:
	_owned = owned
	_lock.visible = not owned
	# Sin báculo, la silueta se queda gris y apagada.
	_staff_mat.set_shader_parameter("albedo", Color.WHITE if owned else Color(0.5, 0.5, 0.62))
	_staff_mat.set_shader_parameter("self_light", 0.15 if owned else 0.0)
	if owned:
		_gem_color = _current_gem_color()
	if celebrate:
		_flash = 1.6
		AudioDirector.play_sfx(SUMMON_SFX, -6.0)


## Color del elemento que lleva la gema del báculo del mago (o el de la página si aún no tiene).
func _current_gem_color() -> Color:
	var player: Player = get_tree().get_first_node_in_group(&"player") as Player
	if player == null or player.get_caster() == null:
		return C_GEM
	var el: ElementDef = player.get_caster().staff.element(SpellCaster.ELEMENTS)
	return el.color if el else C_GEM


func _toon(rim: float, glow: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = TOON_SHADER
	m.set_shader_parameter("rim", rim)
	m.set_shader_parameter("self_light", glow)
	return m


func _mesh(parent: Node3D, node_name: String, st: SurfaceTool, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = MeshKit.commit(st)
	mi.material_override = mat
	parent.add_child(mi)
	return mi


## Pedestal de piedra con ribete de oro y losa de terciopelo; urna de cristal con cuatro postes
## de oro, tejadillo y remate; la colisión.
func _build_case() -> void:
	var st: SurfaceTool = MeshKit.begin()
	MeshKit.add_box(st, Vector3(0, 0.1, 0), Vector3(1.3, 0.2, 1.3), C_STONE_SHADE, C_STONE)
	MeshKit.add_box(st, Vector3(0, 0.55, 0), Vector3(0.8, 0.7, 0.8), C_STONE_SHADE, C_STONE)
	MeshKit.add_box(st, Vector3(0, 0.93, 0), Vector3(1.08, 0.1, 1.08), C_GOLD, C_GOLD)
	MeshKit.add_box(st, Vector3(0, TOP_Y, 0), Vector3(0.96, 0.05, 0.96), C_VELVET)
	var top: float = TOP_Y + CASE_H
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			MeshKit.add_box(
				st,
				Vector3(sx * CASE_HALF, TOP_Y + CASE_H * 0.5, sz * CASE_HALF),
				Vector3(0.06, CASE_H, 0.06),
				C_GOLD,
				C_GOLD_LIGHT
			)
	MeshKit.add_box(
		st,
		Vector3(0, top + 0.03, 0),
		Vector3(CASE_HALF * 2.0 + 0.14, 0.08, CASE_HALF * 2.0 + 0.14),
		C_GOLD,
		C_GOLD_LIGHT
	)
	MeshKit.add_prism(
		st, Vector3(0, top + 0.07, 0), Vector3.UP, 0.5, 0.04, 0.32, 4, C_GOLD, C_GOLD_LIGHT, _rng
	)
	_mesh(self, "Pedestal", st, _toon(0.35, 0.12))
	# Los cristales: una caja hueca, transparente y sin sombra (no pinta contorno: no escribe
	# profundidad).
	var gs: SurfaceTool = MeshKit.begin()
	MeshKit.add_box(
		gs,
		Vector3(0, TOP_Y + CASE_H * 0.5, 0),
		Vector3(CASE_HALF * 2.0, CASE_H, CASE_HALF * 2.0),
		C_GLASS
	)
	var glass := StandardMaterial3D.new()
	glass.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	glass.vertex_color_use_as_albedo = true
	var gm: MeshInstance3D = _mesh(self, "Glass", gs, glass)
	gm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var sb := StaticBody3D.new()
	sb.name = "Collision"
	sb.collision_layer = 1
	sb.collision_mask = 0
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.3, top + 0.2, 1.3)
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position.y = (top + 0.2) * 0.5
	sb.add_child(col)
	add_child(sb)


## El báculo: asta de madera con anillos de oro, la garra de tres dedos y la gema.
func _build_staff() -> void:
	_staff = Node3D.new()
	_staff.name = "Staff"
	_staff.position.y = STAFF_Y
	add_child(_staff)
	var st: SurfaceTool = MeshKit.begin()
	var shaft: float = 1.45
	MeshKit.add_prism(
		st, Vector3(0, 0.05, 0), Vector3.UP, 0.045, shaft, 0.0, 6, C_WOOD, C_WOOD_DARK, _rng, 0.1
	)
	MeshKit.add_prism(st, Vector3(0, 0.02, 0), Vector3.UP, 0.06, 0.06, 0.0, 6, C_GOLD, C_GOLD, _rng)
	for y: float in [0.5, shaft - 0.05]:
		MeshKit.add_prism(
			st, Vector3(0, y, 0), Vector3.UP, 0.065, 0.07, 0.0, 6, C_GOLD, C_GOLD, _rng
		)
	for k: int in 3:
		var a: float = TAU * float(k) / 3.0
		var out := Vector3(cos(a), 0.0, sin(a))
		MeshKit.add_prism(
			st,
			Vector3(0, shaft + 0.02, 0) + out * 0.04,
			(Vector3.UP * 1.0 + out * 0.45).normalized(),
			0.025,
			0.22,
			0.06,
			4,
			C_GOLD,
			C_GOLD_LIGHT,
			_rng
		)
	_staff_mat = _toon(0.4, 0.0)
	_mesh(_staff, "Shaft", st, _staff_mat)
	var gs: SurfaceTool = MeshKit.begin()
	var g := Vector3(0, shaft + 0.24, 0)
	MeshKit.add_prism(
		gs, g - Vector3.UP * 0.1, Vector3.UP, 0.14, 0.14, 0.13, 5, Color.WHITE, Color.WHITE, _rng
	)
	MeshKit.add_prism(
		gs, g - Vector3.UP * 0.1, Vector3.DOWN, 0.14, 0.001, 0.11, 5, Color.WHITE, Color.WHITE, _rng
	)
	_gem_mat = _toon(0.5, 0.3)
	_gem_mat.set_shader_parameter("use_vertex_color", false)
	_mesh(_staff, "Gem", gs, _gem_mat)
	# Candado encima mientras no se tiene (el mismo de las ranuras de la Mesa de Runas).
	_lock = Sprite3D.new()
	_lock.name = "Lock"
	_lock.pixel_size = 0.03
	_lock.shaded = false
	_lock.double_sided = true
	_lock.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_lock.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	_lock.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_lock.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	_lock.texture = RuneGlyphs.texture(RuneGlyphs.LOCK, C_DIM)
	_lock.position = Vector3(0.0, TOP_Y + 0.9, 0.0)
	add_child(_lock)


func _build_fx() -> void:
	_light = OmniLight3D.new()
	_light.name = "Light"
	_light.omni_range = 3.4
	_light.shadow_enabled = false
	_light.position = Vector3(0.0, TOP_Y + 1.5, 0.7)
	add_child(_light)
