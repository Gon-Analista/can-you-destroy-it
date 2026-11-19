class_name RuneTable
extends Node3D
## La Mesa de Runas (GDD 4.3, "Pilón 10 %"): un altar de piedra violeta junto al Santuario con
## tres ranuras talladas en la losa y las cinco runas flotando detrás en arco, cada una en su
## piedra con su glifo. Antes del 10 % del Pilón está sellada (cadenas cruzadas, sello encima, las
## piedras caídas y apagadas) y F sólo lo recuerda. Al llegar, las cadenas saltan con un acorde y
## la mesa despierta: luz, motas y zumbido. Las runas compradas se encienden con su color; las
## inscritas bajan a su ranura y giran sobre ella. Con F cerca se abre su pantalla (RuneScreen).

const TOON_SHADER: Shader = preload("res://fx/toon.gdshader")
const HUM: AudioStream = preload("res://audio/sfx/amb_rune_table_hum_loop.ogg")
const UNSEAL_SFX: AudioStream = preload("res://audio/sfx/sfx_rune_unseal_01.ogg")
const SEALED_SFX: AudioStream = preload("res://audio/sfx/sfx_spark_fizzle_01.ogg")
const GUIDE: GuidanceDef = preload("res://data/ui/guidance.tres")
const C_STONE := Color("#e6dddb")
const C_STONE_SHADE := Color("#b9aeb8")
const C_SLAB := Color("#5b4d8a")
const C_SLAB_TOP := Color("#7d6db8")
const C_SOCKET := Color("#241c40")
const C_GOLD := Color("#d8a23a")
const C_CHAIN := Color("#4a4652")
const C_DIM := Color("#8a8496")
const C_LIGHT := Color("#c79bff")
## Altura de la losa, de las ranuras (x local) y del arco de las piedras.
const SLAB_Y: float = 1.02
const SOCKETS: PackedFloat32Array = [-0.55, 0.0, 0.55]
const ARC_Y: float = 1.72
const ARC_R: float = 0.95
const INTERACT_RADIUS: float = 2.6
const AWAKE_RADIUS: float = 7.0

var _player: Node3D
var _stones: Array[Node3D] = []
var _glyphs: Array[Sprite3D] = []
var _locks: Array[Sprite3D] = []
var _chains: Node3D
var _seal: Sprite3D
var _light: OmniLight3D
var _hum: AudioStreamPlayer3D
var _motes: GPUParticles3D
var _burst: GPUParticles3D
var _unlocked: bool = false
var _awake: float = 0.0
var _flash: float = 0.0
var _t: float = 0.0
var _check: float = 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	add_to_group(&"rune_table")
	_rng.seed = 91
	_build_table()
	_build_stones()
	_build_fx()
	_unlocked = RuneBook.table_unlocked(GameState.progression)
	_apply_seal(_unlocked)
	refresh()
	Events.runes_changed.connect(refresh)
	Events.upgrade_bought.connect(func(_id: StringName, _l: int) -> void: refresh())


## True si el jugador está lo bastante cerca para usar la mesa.
func player_in_range() -> bool:
	return _player_distance() <= INTERACT_RADIUS


func is_unlocked() -> bool:
	return _unlocked


## Punto encima de la mesa (aviso, capturas y la guía).
func marker_position() -> Vector3:
	return to_global(Vector3(0.0, ARC_Y + 0.5, 0.0))


## Aviso junto a la mira: sellada, lo que falta; abierta, entero las primeras veces.
func prompt() -> String:
	if not player_in_range():
		return ""
	if not _unlocked:
		return (
			tr("MESA DE RUNAS: SELLADA HASTA EL PILÓN AL %d %%")
			% roundi(RuneBook.BALANCE.rune_table_pylon * 100.0)
		)
	var mode: int = Guidance.prompt_mode(
		GameState.progression.times(&"rune_table"), GUIDE.grimoire_learn, GUIDE.grimoire_forget
	)
	return tr("[F] MESA DE RUNAS") if mode == Guidance.Prompt.FULL else ""


func prompt_icon() -> bool:
	if not player_in_range() or not _unlocked:
		return false
	var mode: int = Guidance.prompt_mode(
		GameState.progression.times(&"rune_table"), GUIDE.grimoire_learn, GUIDE.grimoire_forget
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
		if not _unlocked:
			AudioDirector.play_sfx(SEALED_SFX, -6.0, 0.7)
			Events.hint.emit(prompt(), C_DIM)
			return
		GameState.progression.learn(&"rune_table")
		_flash = maxf(_flash, 0.5)
		Events.rune_table_requested.emit()


## Enciende las piedras de las runas compradas y baja las inscritas a su ranura; las ranuras que
## aún no se tienen llevan candado.
func refresh() -> void:
	var prog: Progression = GameState.progression
	var slots: int = RuneBook.slot_count(prog)
	for i: int in _locks.size():
		_locks[i].visible = _unlocked and i >= slots
	for i: int in RuneBook.RUNES.size():
		var def: RuneDef = RuneBook.RUNES[i]
		var owned: bool = prog.get_level(def.id) > 0
		_glyphs[i].texture = RuneGlyphs.texture(def.glyph, def.color if owned else C_DIM)
		_glyphs[i].modulate = Color(1.6, 1.6, 1.6) if owned else Color(0.8, 0.8, 0.85)


func _process(delta: float) -> void:
	_t += delta
	_check -= delta
	if _check <= 0.0:
		_check = 0.5
		if not _unlocked and RuneBook.table_unlocked(GameState.progression):
			_unseal()
	var near: float = 1.0 - smoothstep(INTERACT_RADIUS, AWAKE_RADIUS, _player_distance())
	_awake = lerpf(_awake, near, 1.0 - exp(-delta * 3.0))
	_flash = maxf(0.0, _flash - delta * 0.8)
	var on: float = 1.0 if _unlocked else 0.15
	_light.light_energy = (0.2 + _awake * 0.45) * on + _flash * 1.4
	_hum.volume_db = lerpf(-34.0, -12.0, _awake * on)
	_place_stones(delta)


## Cada piedra a su sitio: en el arco, sobre su ranura si está inscrita (girando y más baja) o
## caída sobre la losa con la mesa sellada. Se mueven a escalones de 1/12 s (pixel art).
func _place_stones(delta: float) -> void:
	var prog: Progression = GameState.progression
	var step: float = floorf(_t * 12.0) / 12.0
	for i: int in _stones.size():
		var def: RuneDef = RuneBook.RUNES[i]
		var target: Vector3
		var spin: float = 0.0
		if not _unlocked:
			target = Vector3(-0.72 + 0.36 * i, SLAB_Y + 0.11, 0.1 + 0.05 * float(i % 2))
		elif RuneBook.is_inscribed(prog, def.id):
			var slot: int = clampi(RuneBook.slot_index(prog, def.id), 0, SOCKETS.size() - 1)
			target = Vector3(SOCKETS[slot], SLAB_Y + 0.42 + sin(step * 2.2 + i) * 0.05, 0.12)
			spin = step * 1.6 + i
		else:
			var a: float = lerpf(-0.95, 0.95, float(i) / float(_stones.size() - 1))
			target = Vector3(
				sin(a) * ARC_R, ARC_Y - (1.0 - cos(a)) * 0.6 + sin(step * 1.3 + i) * 0.04, -0.38
			)
		var s: Node3D = _stones[i]
		s.position = s.position.lerp(target, 1.0 - exp(-delta * 6.0))
		s.rotation.y = (
			spin if spin != 0.0 else lerp_angle(s.rotation.y, 0.0, 1.0 - exp(-delta * 6.0))
		)
		s.rotation.z = 0.0 if _unlocked else (0.25 if i % 2 == 0 else -0.2)
		s.rotation.x = 0.0 if _unlocked else -1.35


## El Pilón llegó a su marca: las cadenas saltan, el sello se rompe y la mesa despierta.
func _unseal() -> void:
	_unlocked = true
	_apply_seal(true)
	refresh()
	_flash = 1.6
	_burst.restart()
	AudioDirector.play_sfx(UNSEAL_SFX, -2.0)
	Events.hint.emit(tr("¡LA MESA DE RUNAS DESPIERTA! (JUNTO AL SANTUARIO)"), C_LIGHT)
	Events.runes_changed.emit()


func _apply_seal(open: bool) -> void:
	_chains.visible = not open
	_seal.visible = not open
	_motes.emitting = open


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


func _sprite(parent: Node3D, pixel: float) -> Sprite3D:
	var s := Sprite3D.new()
	s.pixel_size = pixel
	s.shaded = false
	s.double_sided = true
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(s)
	return s


## Zócalo, pie, losa con ribete de oro, las tres ranuras y las cadenas del sello.
func _build_table() -> void:
	var st: SurfaceTool = MeshKit.begin()
	MeshKit.add_box(st, Vector3(0, 0.08, 0), Vector3(1.7, 0.16, 1.0), C_STONE_SHADE, C_STONE)
	MeshKit.add_box(st, Vector3(0, 0.5, 0), Vector3(0.9, 0.7, 0.55), C_STONE_SHADE, C_STONE)
	MeshKit.add_box(st, Vector3(0, 0.88, 0), Vector3(1.3, 0.08, 0.8), C_STONE_SHADE, C_STONE)
	MeshKit.add_box(st, Vector3(0, SLAB_Y - 0.03, 0), Vector3(2.0, 0.1, 1.1), C_GOLD, C_GOLD)
	MeshKit.add_box(st, Vector3(0, SLAB_Y + 0.03, 0), Vector3(1.86, 0.06, 0.98), C_SLAB, C_SLAB_TOP)
	for x: float in SOCKETS:
		MeshKit.add_prism(
			st,
			Vector3(x, SLAB_Y + 0.055, 0.12),
			Vector3.UP,
			0.17,
			0.02,
			0.0,
			8,
			C_GOLD,
			C_SOCKET,
			_rng
		)
	# Postes del arco de las piedras, detrás de la losa.
	for side: float in [-1.0, 1.0]:
		MeshKit.add_prism(
			st,
			Vector3(side * 1.05, 0.0, -0.42),
			Vector3.UP,
			0.08,
			1.55,
			0.14,
			6,
			C_STONE,
			C_GOLD,
			_rng
		)
	_mesh(self, "Table", st, _toon(0.35, 0.12))
	# Candado sobre cada ranura que aún no se tiene.
	for x: float in SOCKETS:
		var lock: Sprite3D = _sprite(self, 0.022)
		lock.texture = RuneGlyphs.texture(RuneGlyphs.LOCK, C_DIM)
		lock.position = Vector3(x, SLAB_Y + 0.2, 0.12)
		lock.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		_locks.append(lock)
	_chains = Node3D.new()
	_chains.name = "Chains"
	add_child(_chains)
	var cs: SurfaceTool = MeshKit.begin()
	for k: int in 9:
		for d: float in [-1.0, 1.0]:
			var x: float = -0.95 + 0.24 * k
			MeshKit.add_box(
				cs,
				Vector3(x, SLAB_Y + 0.12 + 0.02 * float(k % 2), d * (0.25 + x * 0.12)),
				Vector3(0.16, 0.05, 0.07),
				C_CHAIN
			)
	_mesh(_chains, "ChainLinks", cs, _toon(0.2, 0.0))
	_seal = _sprite(self, 0.05)
	_seal.texture = RuneGlyphs.texture(RuneGlyphs.SEAL, Color("#9a90b0"))
	_seal.position = Vector3(0.0, SLAB_Y + 0.6, 0.0)
	_seal.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	var sb := StaticBody3D.new()
	sb.name = "Collision"
	sb.collision_layer = 1
	sb.collision_mask = 0
	var shape := BoxShape3D.new()
	shape.size = Vector3(2.0, 1.2, 1.1)
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position.y = 0.6
	sb.add_child(col)
	add_child(sb)


## Una piedra por runa (losa pequeña con su glifo delante).
func _build_stones() -> void:
	for i: int in RuneBook.RUNES.size():
		var stone := Node3D.new()
		stone.name = "Stone%d" % i
		add_child(stone)
		var st: SurfaceTool = MeshKit.begin()
		MeshKit.add_box(st, Vector3.ZERO, Vector3(0.3, 0.36, 0.07), C_SLAB, C_SLAB_TOP)
		MeshKit.add_box(st, Vector3(0, -0.2, 0), Vector3(0.34, 0.04, 0.09), C_GOLD)
		_mesh(stone, "Slab", st, _toon(0.4, 0.15))
		var g: Sprite3D = _sprite(stone, 0.026)
		g.position = Vector3(0.0, 0.0, 0.045)
		_glyphs.append(g)
		stone.position = Vector3(-0.72 + 0.36 * i, SLAB_Y + 0.11, 0.1)
		_stones.append(stone)


func _build_fx() -> void:
	_light = OmniLight3D.new()
	_light.name = "Light"
	_light.light_color = C_LIGHT
	_light.omni_range = 3.6
	_light.shadow_enabled = false
	_light.position = Vector3(0.0, 1.6, 0.6)
	add_child(_light)
	_motes = _particles("Motes", 16, 2.6, false)
	_burst = _particles("Burst", 40, 1.2, true)
	_hum = AudioStreamPlayer3D.new()
	_hum.name = "Hum"
	_hum.bus = &"Ambience"
	_hum.stream = HUM
	_hum.unit_size = 3.0
	_hum.max_distance = 16.0
	_hum.volume_db = -34.0
	_hum.position.y = 1.4
	_hum.autoplay = true
	add_child(_hum)


## Motas de luz que suben de la losa (o el estallido de colores al romperse el sello).
func _particles(node_name: String, amount: int, life: float, burst: bool) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = node_name
	p.amount = amount
	p.lifetime = life
	p.fixed_fps = 12
	p.local_coords = false
	p.one_shot = burst
	p.explosiveness = 0.9 if burst else 0.0
	p.emitting = false
	p.position = Vector3(0.0, SLAB_Y + 0.2, 0.0)
	p.visibility_aabb = AABB(Vector3(-3, -1, -3), Vector3(6, 5, 6))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.8, 0.05, 0.4)
	pm.direction = Vector3.UP
	pm.spread = 60.0 if burst else 15.0
	pm.initial_velocity_min = 1.5 if burst else 0.15
	pm.initial_velocity_max = 4.0 if burst else 0.4
	pm.gravity = Vector3(0, -2.0, 0) if burst else Vector3.ZERO
	var g := Gradient.new()
	g.colors = PackedColorArray([Color("#ffc46b"), Color("#6be4ff"), Color("#ff5a6e"), C_LIGHT])
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_initial_ramp = gt
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.06, 0.06) * (1.6 if burst else 1.0)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = PixelTextures.star()
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	quad.material = m
	p.draw_pass_1 = quad
	add_child(p)
	return p
