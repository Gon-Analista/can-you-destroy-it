class_name MotherCrystal
extends Node3D
## El Cristal Madre. Recibe impactos y reacciona: destello y onda en la faceta, grieta que se
## queda, temblor, pulso del corazón violeta, fragmentos que saltan, partículas, luz y sonido
## ("tink") que sube de tono con la racha. Ver GDD 10.3.
##
## Es destructible de verdad: un volumen (`CrystalVolume`) que cada golpe erosiona, y su malla
## se rehace por trozos. Las capas (GDD 6) están por profundidad: se llega a ellas excavando.
## La esencia que quita un golpe es el volumen sólido que arranca por la densidad de su capa.

const CRYSTAL_SHADER: Shader = preload("res://crystal/crystal.gdshader")
const MAX_HITS: int = 6
const MAX_CRACKS: int = 16
const MAX_BURNS: int = 12
const MAX_WEAK: int = 8
## Escala pentatónica (semitonos) que recorre el golpe a medida que crece la racha: sube una
## octava y vuelve a empezar (antes subía sin parar y acababa chillando).
const STREAK_LADDER: PackedInt32Array = [0, 2, 4, 7, 9, 12, 9, 7, 4, 2]
## Golpes al cristal (tools/sfx_loop.py): diez variantes en tres timbres (cuenco, cristal y
## mazo) con ataque suave; se eligen al azar sin repetir el anterior.
const TINKS: Array[AudioStream] = [
	preload("res://audio/sfx/sfx_crystal_hit_01.ogg"),
	preload("res://audio/sfx/sfx_crystal_hit_02.ogg"),
	preload("res://audio/sfx/sfx_crystal_hit_03.ogg"),
	preload("res://audio/sfx/sfx_crystal_hit_04.ogg"),
	preload("res://audio/sfx/sfx_crystal_hit_05.ogg"),
	preload("res://audio/sfx/sfx_crystal_hit_06.ogg"),
	preload("res://audio/sfx/sfx_crystal_hit_07.ogg"),
	preload("res://audio/sfx/sfx_crystal_hit_08.ogg"),
	preload("res://audio/sfx/sfx_crystal_hit_09.ogg"),
	preload("res://audio/sfx/sfx_crystal_hit_10.ogg"),
]
const BREAKS: Array[AudioStream] = [
	preload("res://audio/sfx/sfx_shard_break_01.ogg"),
	preload("res://audio/sfx/sfx_shard_break_02.ogg"),
	preload("res://audio/sfx/sfx_shard_break_03.ogg"),
]
const RESONANT_SFX: AudioStream = preload("res://audio/sfx/sfx_resonant_hit_01.ogg")
const STREAK_SFX: AudioStream = preload("res://audio/sfx/sfx_streak_chime_01.ogg")
const HUM_SFX: AudioStream = preload("res://audio/sfx/amb_crystal_hum_loop.ogg")
const SURGE_SFX: AudioStream = preload("res://audio/sfx/sfx_crystal_surge_01.ogg")
const ARC_SFX: Array[AudioStream] = [
	preload("res://audio/sfx/sfx_arc_crackle_01.ogg"),
	preload("res://audio/sfx/sfx_arc_crackle_02.ogg"),
	preload("res://audio/sfx/sfx_arc_crackle_03.ogg"),
]
## Colores de la energía del cristal (rayos): cian y violeta; dorado en los resonantes.
const ARC_COLORS: Array[Color] = [
	Color(0.25, 0.75, 2.0), Color(1.2, 0.3, 1.9), Color(0.4, 0.5, 2.0)
]
## La geoda suena como el resquebrajo, más aguda (ver _break_geode).
const GEODE_SFX: AudioStream = SURGE_SFX
## Partida guardada del volumen excavado (ver SaveSystem).
const STATE_PATH: String = "user://crystal_volume.bin"
## Colores de las Venas Resonantes por elemento (Chispa, Escarcha, Rayo, Tierra, Arcano).
const VEIN_COLORS: PackedColorArray = [
	Color(1.0, 0.55, 0.2),
	Color(0.6, 0.92, 1.0),
	Color(1.0, 0.92, 0.35),
	Color(0.8, 0.62, 0.36),
	Color(0.8, 0.55, 1.0)
]
## Cuánto oscurece lo excavado y cuánto brilla cada capa por dentro.
const LAYER_SHADE: PackedFloat32Array = [0.32, 0.3, 0.22, 0.05, 0.1]
const LAYER_GLOW: PackedFloat32Array = [0.0, 0.1, 0.35, 0.7, 0.9]
## Daño acumulado para el primer "resquebrajo"; cada siguiente pide un 60 % más.
const FIRST_SURGE: float = 15.0
const SURGE_GROWTH: float = 1.6

## El volumen excavable (rejilla de distancias) y sus mallas por trozos.
var volume: CrystalVolume

var _material: ShaderMaterial
var _chunks: CrystalChunks
var _body: StaticBody3D
## Esencia arrancada que aún no llega a un punto entero.
var _essence_acc: float = 0.0
var _volume_dirty: bool = false
## Capa del último golpe (la que se ve en el HUD).
var _hit_layer: int = 0
var _hard_hint_at: float = -10.0
var _geode_nodes: Dictionary[int, Geode] = {}
## Efectos de las combinaciones (lanzas, rayos que saltan, reacciones, Trueno, Magnetismo).
var _combos: CrystalCombos
var _shards: ShardPool
var _fx: ImpactFx
var _hd_fx: HdImpact
var _arcs: CrystalArcs
var _arc_player: AudioStreamPlayer3D
var _surge_acc: float = 0.0
var _last_tink: float = -1.0
## Último estallido HD: con mucha cadencia no se encadenan (la pantalla se volvía blanca).
var _last_hd: float = -1.0
var _layer: int = 0
var _next_surge: float = FIRST_SURGE
var _burn_fire: CrystalBurn
var _burns: PackedVector4Array = []
var _burn_radius: PackedFloat32Array = []
var _burn_index: int = 0
var _burn_ticks: int = 0
## Zonas debilitadas (congeladas o quebradizas): posición, radio, multiplicador, fin (en
## `_now`), si se gastan con el siguiente golpe y qué elemento las hizo.
var _weak_pos: PackedVector4Array = []
var _weak_radius: PackedFloat32Array = []
var _weak_kind: PackedFloat32Array = []
var _weak_sec: PackedFloat32Array = []
var _weak_mult: PackedFloat32Array = []
var _weak_end: PackedFloat32Array = []
var _weak_consume: Array[bool] = []
var _weak_element: Array[StringName] = []
var _weak_index: int = 0
var _element_sounds: Dictionary[ElementDef, AudioStreamRandomizer] = {}
var _streak: StreakTracker
var _hits: PackedVector4Array = []
var _hit_resonant: PackedFloat32Array = []
var _cracks: PackedVector4Array = []
var _hit_index: int = 0
var _crack_index: int = 0
var _now: float = 0.0
var _shudder: float = 0.0
var _core_pulse: float = 0.0
var _global_flash: float = 0.0
var _tink_players: Array[AudioStreamPlayer3D] = []
var _tink_next: int = 0
var _tink_random: AudioStreamRandomizer
var _break_player: AudioStreamPlayer3D
var _accent_player: AudioStreamPlayer
## Explosiones de los hechizos combinados (Bola de Fuego...).
var _spell_player: AudioStreamPlayer3D
var _spell_impacts: Dictionary[SpellRecipe, AudioStreamRandomizer] = {}
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	add_to_group(&"mother_crystal")
	_rng.randomize()
	_streak = StreakTracker.new(GameState.BALANCE.streak_window_sec)
	volume = CrystalVolume.new()
	volume.load_baked()
	var resumed: bool = _load_state()
	_material = ShaderMaterial.new()
	_material.shader = CRYSTAL_SHADER
	_setup_material()
	_body = StaticBody3D.new()
	_body.name = "Body"
	_body.collision_layer = 1 << 1
	_body.collision_mask = 0
	_body.set_meta(&"mother_crystal", self)
	add_child(_body)
	_chunks = CrystalChunks.new()
	_chunks.name = "Chunks"
	add_child(_chunks)
	_chunks.setup(volume, _material, _body)
	_chunks.build_all(_chunks.all_chunks() if resumed else volume.surface_chunks)
	_shards = ShardPool.new()
	_shards.name = "Shards"
	add_child(_shards)
	_shards.set_layer_palettes(GameState.LAYERS)
	_fx = ImpactFx.new()
	_fx.name = "ImpactFx"
	add_child(_fx)
	_hd_fx = HdImpact.new()
	_hd_fx.name = "HdImpact"
	add_child(_hd_fx)
	_arcs = CrystalArcs.new()
	_arcs.name = "Arcs"
	add_child(_arcs)
	_combos = CrystalCombos.new()
	_combos.name = "Combos"
	add_child(_combos)
	_combos.setup(self, _arcs, _shards, _hd_fx, _fx)
	_arcs.setup_ambient(
		global_position + Vector3(0.0, volume.top * 0.4, 0.0),
		Vector3(
			WorldLayout.CRYSTAL_FOOTPRINT * 1.4,
			volume.top * 0.75,
			WorldLayout.CRYSTAL_FOOTPRINT * 1.4
		)
	)
	_layer = GameState.layer_index()
	_hit_layer = 0
	for i: int in volume.geodes.size():
		if GameState.progression.geodes.get(i, 0) == 1:
			_reveal_geode(i, false)
	_burn_fire = CrystalBurn.new()
	_burn_fire.name = "Burn"
	_burn_fire.burned.connect(_on_burn_tick)
	add_child(_burn_fire)
	for i: int in MAX_BURNS:
		_burns.append(Vector4(0, 0, 0, -1))
		_burn_radius.append(0.0)
	_material.set_shader_parameter("burns", _burns)
	_material.set_shader_parameter("burn_radius", _burn_radius)
	for i: int in MAX_WEAK:
		_weak_pos.append(Vector4(0, 0, 0, -1))
		_weak_radius.append(0.0)
		_weak_kind.append(0.0)
		_weak_sec.append(1.0)
		_weak_mult.append(1.0)
		_weak_end.append(-1.0)
		_weak_consume.append(false)
		_weak_element.append(&"")
	_push_weak()
	_setup_audio()
	for i: int in MAX_HITS:
		_hits.append(Vector4(0, 0, 0, -1))
		_hit_resonant.append(0.0)
	for i: int in MAX_CRACKS:
		_cracks.append(Vector4.ZERO)
	_material.set_shader_parameter("hits", _hits)
	_material.set_shader_parameter("hit_resonant", _hit_resonant)
	_material.set_shader_parameter("cracks", _cracks)


## Paletas por capa, profundidades, Núcleo, geodas y venas para el shader.
func _setup_material() -> void:
	var keys: Array[String] = ["col_highlight", "col_light", "col_mid", "col_dark"]
	var params: Array[String] = ["pal_highlight", "pal_light", "pal_mid", "pal_dark"]
	for k: int in keys.size():
		var cols := PackedColorArray()
		for layer: CrystalLayerDef in GameState.LAYERS:
			cols.append(layer.get(keys[k]) as Color)
		_material.set_shader_parameter(params[k], cols)
	for key: String in ["col_highlight", "col_light", "col_mid", "col_dark", "col_core"]:
		_material.set_shader_parameter(key, GameState.LAYERS[0].get(key) as Color)
	_material.set_shader_parameter("layer_depth", volume.layer_min_depth)
	_material.set_shader_parameter("layer_shade", LAYER_SHADE)
	_material.set_shader_parameter("layer_glow", LAYER_GLOW)
	_material.set_shader_parameter(
		"core_sphere",
		Vector4(
			volume.core_center.x, volume.core_center.y, volume.core_center.z, volume.core_radius
		)
	)
	_material.set_shader_parameter("core_top", volume.core_center.y + volume.core_radius * 2.5)
	_material.set_shader_parameter("core_bottom", -0.5)
	_material.set_shader_parameter("vein_colors", VEIN_COLORS)
	var gs := PackedVector4Array()
	for g: Dictionary in volume.geodes:
		var c: Vector3 = g["center"]
		gs.append(Vector4(c.x, c.y, c.z, float(g["radius"])))
	while gs.size() < 32:
		gs.append(Vector4.ZERO)
	_material.set_shader_parameter("geodes", gs)


## Retoma el cristal excavado de la partida guardada (si la hay y no es una partida nueva).
func _load_state() -> bool:
	var prog: Progression = GameState.progression
	if not SaveSystem.enabled or prog.essence >= prog.total_essence:
		return false
	if not FileAccess.file_exists(STATE_PATH):
		return false
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(STATE_PATH)
	return volume.load_state(bytes)


## Lo llama SaveSystem: guarda la rejilla sólo si ha cambiado (y la borra en partida nueva).
func save_state() -> void:
	var prog: Progression = GameState.progression
	if prog.essence >= prog.total_essence:
		if FileAccess.file_exists(STATE_PATH):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(STATE_PATH))
		_volume_dirty = false
		return
	if not _volume_dirty:
		return
	var f := FileAccess.open(STATE_PATH, FileAccess.WRITE)
	if f:
		f.store_buffer(volume.state_bytes())
		_volume_dirty = false


func _setup_audio() -> void:
	_tink_random = AudioStreamRandomizer.new()
	for s: AudioStream in TINKS:
		_tink_random.add_stream(-1, s)
	_tink_random.random_pitch = 1.0
	_tink_random.random_volume_offset_db = 2.5
	_tink_random.playback_mode = AudioStreamRandomizer.PLAYBACK_RANDOM_NO_REPEATS
	for i: int in 6:
		var p := AudioStreamPlayer3D.new()
		p.bus = &"SFX"
		p.stream = _tink_random
		p.unit_size = 30.0
		p.max_polyphony = 1
		add_child(p)
		_tink_players.append(p)
	var breaks := AudioStreamRandomizer.new()
	for s: AudioStream in BREAKS:
		breaks.add_stream(-1, s)
	breaks.random_pitch = 1.1
	_break_player = AudioStreamPlayer3D.new()
	_break_player.bus = &"SFX"
	_break_player.stream = breaks
	_break_player.unit_size = 30.0
	_break_player.volume_db = -15.0
	_break_player.max_polyphony = 2
	add_child(_break_player)
	_accent_player = AudioStreamPlayer.new()
	_accent_player.bus = &"SFX"
	_accent_player.max_polyphony = 2
	add_child(_accent_player)
	_spell_player = AudioStreamPlayer3D.new()
	_spell_player.bus = &"SFX"
	_spell_player.unit_size = 40.0
	_spell_player.max_polyphony = 2
	add_child(_spell_player)
	_arc_player = AudioStreamPlayer3D.new()
	_arc_player.bus = &"SFX"
	_arc_player.unit_size = 20.0
	_arc_player.max_polyphony = 2
	var arcs := AudioStreamRandomizer.new()
	for st: AudioStream in ARC_SFX:
		arcs.add_stream(-1, st)
	arcs.random_pitch = 1.2
	_arc_player.stream = arcs
	add_child(_arc_player)
	var hum := AudioStreamPlayer3D.new()
	hum.name = "Hum"
	hum.bus = &"Ambience"
	hum.stream = HUM_SFX  # bucle activado en la importación
	hum.unit_size = 14.0
	hum.volume_db = -6.0
	hum.position = Vector3(0, 4, 0)
	hum.autoplay = true
	add_child(hum)


## Punto de entrada de los hechizos: aplica el daño y dispara toda la reacción.
func receive_hit(hit: SpellHit) -> void:
	if hit.damage <= 0:
		_fizzle(hit)
		return
	var balance: BalanceConfig = GameState.BALANCE
	hit.streak = _streak.register_hit(_now)
	_apply_weakness(hit)
	_combos.check_temper(hit)
	_check_geodes(hit)
	var removed: float = _dig(
		hit.position, hit.normal, float(hit.damage), hit.recipe != null, hit.size
	)
	if removed < 0.0:
		_too_hard(hit)
		return
	hit.layer = _hit_layer
	var tier: SpellTier = hit.tier

	_hits[_hit_index] = Vector4(hit.position.x, hit.position.y, hit.position.z, _now)
	_hit_resonant[_hit_index] = 1.0 if hit.resonant else 0.0
	_hit_index = (_hit_index + 1) % MAX_HITS
	_cracks[_crack_index] = Vector4(
		hit.position.x,
		hit.position.y,
		hit.position.z,
		tier.crack_radius * (1.6 if hit.resonant else 1.0) * hit.size * _rng.randf_range(0.85, 1.15)
	)
	_crack_index = (_crack_index + 1) % MAX_CRACKS
	var weak: bool = hit.size < 0.6
	if hit.recipe and hit.recipe.area_radius > 0.0 and not weak:
		_area_blast(hit)
	if hit.recipe and hit.recipe.pierce_depth > 0.0:
		_combos.pierce(hit)
	var chains: int = (
		hit.recipe.chain_count
		if hit.recipe
		else (hit.element_def.chain_count if hit.element_def else 0)
	)
	if chains > 0:
		_combos.chain(hit, chains)
	_apply_element(hit)
	_material.set_shader_parameter("hits", _hits)
	_material.set_shader_parameter("hit_resonant", _hit_resonant)
	_material.set_shader_parameter("cracks", _cracks)

	_shudder = minf(
		1.0,
		_shudder + (0.1 if hit.minor else 0.35 + tier.shake * 2.0) + (0.5 if hit.resonant else 0.0)
	)
	_core_pulse = 1.0
	if hit.resonant:
		_global_flash = 0.55
	# Fragmentos por valor del daño (el maná que da el cristal es la esencia que pierde). Tierra y
	# Lanza Cargada: +25 % de valor. El golpe flojo del tutorial: una astilla.
	var bonus: int = (
		hit.recipe.shard_bonus
		if hit.recipe
		else (hit.element_def.shard_bonus if hit.element_def else 0)
	)
	var power: float = 1.25 if hit.resonant else 1.0
	if weak:
		_shards.spawn(hit.position, hit.normal, ShardPool.TYPES[0], 1, power, _hit_layer)
	else:
		_shards.spawn_worth(
			hit.position, hit.normal, float(hit.damage) * (1.0 + 0.25 * bonus), power, _hit_layer
		)
	_fx.play(hit.position, hit.normal, tier, hit.resonant, hit.size)
	_crystal_reacts(hit)
	if hit.resonant or hit.recipe != null or _now - _last_hd >= 0.12:
		_last_hd = _now
		_hd_fx.play(hit.position, hit.normal, tier, hit.resonant, hit.recipe != null, hit.size)
	if hit.recipe and hit.recipe.delivery == SpellRecipe.Delivery.SKY:
		# Lo que cae del cielo estalla dos veces: el golpe y la onda que se abre.
		_hd_fx.play(hit.position, hit.normal, tier, false, true, hit.size * 2.0)
		_arcs.storm(hit.position - Vector3.UP * 2.0, 18.0, 6.0, hit.recipe.circle_color * 1.2)
		_global_flash = maxf(_global_flash, 0.25)
	_play_tink(hit)
	if hit.recipe and (not hit.minor or _rng.randf() < 0.3):
		_play_spell_impact(hit)
	if hit.minor:
		pass
	elif hit.resonant:
		HitStop.trigger(get_tree(), 0.09)
		_accent_player.stream = RESONANT_SFX
		_accent_player.volume_db = -3.0
		_accent_player.play()
	elif hit.recipe:
		HitStop.trigger(get_tree(), 0.06)
		_global_flash = maxf(_global_flash, 0.3)
	elif tier.damage >= 5:
		HitStop.trigger(get_tree(), 0.025)
	if balance.streak_milestones.has(hit.streak):
		_accent_player.stream = STREAK_SFX
		_accent_player.volume_db = -5.0
		_accent_player.play()
		Events.streak_milestone.emit(hit.streak)
	Events.streak_changed.emit(hit.streak)
	Events.spell_impacted.emit(hit)
	set_process(true)


## Un hechizo sin fuerza (la chispita de aprendiz): ni un rasguño. Un "clink" suave, un poco de
## polvo y, la primera vez, la vergüenza por escrito.
func _fizzle(hit: SpellHit) -> void:
	_fx.play(hit.position, hit.normal, hit.tier, false, 0.25)
	var p: AudioStreamPlayer3D = _tink_players[_tink_next]
	_tink_next = (_tink_next + 1) % _tink_players.size()
	p.global_position = hit.position
	p.pitch_scale = 1.6
	p.volume_db = -20.0
	p.play()
	Events.spell_fizzled.emit(hit.position)


## Explosión en área de un hechizo combinado: golpes secundarios alrededor del impacto, cada uno
## con su grieta, su destello, sus partículas y una astilla. El daño ya va en el golpe principal.
func _area_blast(hit: SpellHit) -> void:
	var recipe: SpellRecipe = hit.recipe
	var n: Vector3 = hit.normal if hit.normal.length_squared() > 0.01 else Vector3.BACK
	var side: Vector3 = n.cross(Vector3.UP if absf(n.y) < 0.95 else Vector3.RIGHT).normalized()
	var up: Vector3 = side.cross(n).normalized()
	var splinter: ShardType = ShardPool.type_for_hit(1, false)
	var phase: float = _rng.randf() * TAU
	for i: int in recipe.area_hits:
		var a: float = phase + TAU * float(i) / float(maxi(recipe.area_hits, 1))
		var r: float = recipe.area_radius * hit.size * _rng.randf_range(0.55, 1.0)
		var p: Vector3 = hit.position + (side * cos(a) + up * sin(a)) * r
		_cracks[_crack_index] = Vector4(
			p.x, p.y, p.z, hit.tier.crack_radius * hit.size * _rng.randf_range(0.45, 0.7)
		)
		_crack_index = (_crack_index + 1) % MAX_CRACKS
		_hits[_hit_index] = Vector4(p.x, p.y, p.z, _now)
		_hit_resonant[_hit_index] = 0.0
		_hit_index = (_hit_index + 1) % MAX_HITS
		_shards.spawn(p, n, splinter, 1, 1.15)
		_fx.play(p, n, hit.tier, false)
		_hd_fx.play(p, n, hit.tier, false)


func _unhandled_input(event: InputEvent) -> void:
	if (
		OS.is_debug_build()
		and event is InputEventKey
		and (event as InputEventKey).pressed
		and not (event as InputEventKey).echo
		and (event as InputEventKey).physical_keycode == KEY_L
	):
		# Debug: L excava un túnel hasta la capa siguiente.
		CrystalDemo.tunnel_to_layer(self, _layer + 1)


## Primer punto de la superficie yendo de `from` (global) hacia el eje del cristal a su altura.
## {"position", "normal"} en global, o {} si no lo cruza.
func surface_toward(from: Vector3) -> Dictionary:
	var p0: Vector3 = to_local(from)
	var p1 := Vector3(0.0, p0.y, 0.0)
	var steps: int = ceili(p0.distance_to(p1) / (volume.cell * 0.5))
	for k: int in steps + 1:
		var p: Vector3 = p0.lerp(p1, float(k) / float(maxi(steps, 1)))
		if volume.is_solid(p):
			return {"position": to_global(p), "normal": global_basis * volume.normal_at(p)}
	return {}


## Pantalla de carga: dispara una vez cada efecto de impacto y de fuego en `at` (sin daño ni
## fragmentos que recoger) para compilar shaders y partículas antes de jugar.
func warm_up(at: Vector3, normal: Vector3, tier: SpellTier, big_tier: SpellTier) -> void:
	_fx.play(at, normal, tier, true)
	_arcs.strike(at, normal, 1.0, ARC_COLORS[0])
	_hd_fx.play(at, normal, tier, false)
	_hd_fx.play(at, normal, big_tier, true, true)
	_burn_fire.ignite(at, normal, 1.0, 0.6, 0.3, 0)
	_add_burn(at, 0.01)
	_shards.warm_up(at + normal * 1.5)
	set_process(true)


## Arranca cristal donde da el golpe: tanto volumen como esencia lleva el daño en la capa que
## toca. Devuelve la esencia arrancada, o -1 si esa capa no cede ante este golpe (el Corazón
## sólo con combinaciones; el Núcleo, con nada todavía).
func _dig(at: Vector3, normal: Vector3, damage: float, combo: bool, size: float = 1.0) -> float:
	var n: Vector3 = (global_basis.inverse() * normal).normalized()
	var p: Vector3 = to_local(at)
	var layer: int = volume.layer_at(p - n * 0.35)
	var allowed: int = _allowed_mask(combo)
	_hit_layer = layer
	if (allowed >> layer) & 1 == 0:
		return -1.0
	if damage <= 0.0:
		return 0.0
	# Volumen que se lleva el daño en esta capa; el cráter, una cazoleta de ese tamaño con el
	# centro un poco dentro (la malla queda unos centímetros por fuera en lo cóncavo).
	var vol: float = damage / volume.layer_density[layer]
	# Los hechizos más grandes (mejora de Tamaño) abren cráteres más anchos.
	var radius: float = clampf(pow(vol / 0.3, 1.0 / 3.0) * sqrt(size), 0.85, 14.0)
	var center: Vector3 = p - n * radius * 0.25
	var amount: float = radius * 0.2
	# Ajuste en seco: la esencia sale de las celdas que dejan de estar llenas, así que hay que
	# probar cuánto quitaría (y apretar más si se queda corto) antes de excavar.
	var stride: int = 2 if radius > volume.cell * 5.0 else 1
	for attempt: int in 4:
		var dry: float = volume.carve(center, radius, amount, allowed, false, stride)["essence"]
		if (dry >= damage * 0.8 and dry <= damage * 1.25) or attempt == 3:
			break
		amount *= clampf(damage / maxf(dry, damage * 0.25), 0.25, 4.0)
	return _dig_local(center, radius, amount, allowed, damage)


## Erosiona de verdad en `p` (local), cuenta la esencia, rehace los trozos y descubre geodas.
## `credit` >= 0: esencia que se descuenta (el daño del golpe, para que el "-1" de la pantalla y
## el contador cuadren); si no, la del volumen arrancado (túneles de demo).
func _dig_local(
	p: Vector3, radius: float, amount: float, allowed: int, credit: float = -1.0
) -> float:
	return apply_carve(volume.carve(p, radius, amount, allowed), p, radius, credit)


func apply_carve(r: Dictionary, p: Vector3, radius: float, credit: float = -1.0) -> float:
	var removed: float = r["essence"]
	if credit >= 0.0 and removed > 0.0:
		removed = credit
	_chunks.mark_dirty(r["chunks"])
	_volume_dirty = true
	_essence_acc += removed
	var whole: int = floori(_essence_acc)
	if whole > 0:
		_essence_acc -= whole
		GameState.hit_crystal(whole, to_global(p))
	var by_layer: PackedFloat32Array = r["by_layer"]
	for li: int in range(by_layer.size() - 1, -1, -1):
		if by_layer[li] > 0.0 and li > GameState.progression.deepest_layer:
			GameState.progression.deepest_layer = li
			_enter_layer(li)
			break
	_check_pockets(p, radius)
	return removed


## Juicio del Trueno: el rayo baja del cielo al blanco.
func sky_bolt(from: Vector3, to: Vector3, col: Color) -> void:
	_combos.sky_bolt(from, to, col)


## Un rayo de un punto a otro (Rayo).
func draw_bolt(from: Vector3, to: Vector3, width: float, col: Color, life: float) -> void:
	_arcs.bolt_between(from, to, width, col * 1.6, life)


## Haz de Plasma: vaina rosa gruesa casi recta y un núcleo blanco fino.
func draw_beam(from: Vector3, to: Vector3, col: Color) -> void:
	_arcs.bolt_between(from, to, 0.32, Color(col.r, col.g, col.b) * 0.75, 0.08, 0.06, false)
	_arcs.bolt_between(from, to, 0.08, Color(1.3, 1.1, 1.3), 0.08, 0.03, false)


## Magnetismo: rayos desde el mago hacia lo que atrae.
func magnet_pulse(at: Vector3, pulled: int) -> void:
	_combos.magnet_pulse(at, pulled)


## Resonancia Arcana: todo el cristal vibra (ver CrystalCombos.resonance_pulse).
func resonance_pulse(hit: SpellHit) -> void:
	_combos.resonance_pulse(hit)


## Para CrystalCombos: arranca cristal en `at` como un golpe (ver `_dig`).
func dig(at: Vector3, normal: Vector3, damage: float, combo: bool, size: float = 1.0) -> float:
	return _dig(at, normal, damage, combo, size)


## Para CrystalCombos: zona debilitada (congelada) en `at`.
func add_weak_zone(at: Vector3, radius: float, mult: float, sec: float) -> void:
	_add_weak(at, radius, mult, sec, false, 1.0, &"frost")


## Para CrystalCombos: grieta persistente.
func add_crack(at: Vector3, radius: float) -> void:
	_cracks[_crack_index] = Vector4(at.x, at.y, at.z, radius)
	_crack_index = (_crack_index + 1) % MAX_CRACKS
	_material.set_shader_parameter("cracks", _cracks)


## Para CrystalCombos: destello de todo el cristal (0..1).
func flash(amount: float) -> void:
	_global_flash = maxf(_global_flash, amount)
	set_process(true)


## Capa del último golpe (para el color de los fragmentos).
func hit_layer() -> int:
	return _hit_layer


## Quemadura reciente (< 3 s) cerca de `at`, o -1. La apaga si `consume`.
func hot_burn_near(at: Vector3, slack: float, consume: bool) -> Vector4:
	for i: int in MAX_BURNS:
		var b: Vector4 = _burns[i]
		if b.w < 0.0 or _now - b.w > 3.0:
			continue
		if Vector3(b.x, b.y, b.z).distance_to(at) > _burn_radius[i] + slack:
			continue
		var out := Vector4(b.x, b.y, b.z, _burn_radius[i])
		if consume:
			_burns[i].w = _now - 30.0
			_material.set_shader_parameter("burns", _burns)
		return out
	return Vector4(0, 0, 0, -1)


## Capas que cede este golpe (bit = índice de capa).
func _allowed_mask(combo: bool) -> int:
	var mask: int = 0
	for i: int in GameState.LAYERS.size():
		var layer: CrystalLayerDef = GameState.LAYERS[i]
		if layer.immune or (layer.needs_combo and not combo):
			continue
		mask |= 1 << i
	return mask


## El golpe rebota: chispazo, "clonk" grave y, de vez en cuando, por qué.
func _too_hard(hit: SpellHit) -> void:
	var layer: CrystalLayerDef = GameState.LAYERS[_hit_layer]
	_hits[_hit_index] = Vector4(hit.position.x, hit.position.y, hit.position.z, _now)
	_hit_resonant[_hit_index] = 0.0
	_hit_index = (_hit_index + 1) % MAX_HITS
	_material.set_shader_parameter("hits", _hits)
	_hd_fx.play(hit.position, hit.normal, hit.tier, false)
	_arcs.strike(hit.position, hit.normal, 0.4, ARC_COLORS[1])
	var p: AudioStreamPlayer3D = _tink_players[_tink_next]
	_tink_next = (_tink_next + 1) % _tink_players.size()
	p.global_position = hit.position
	p.pitch_scale = layer.hit_pitch * 0.6
	p.volume_db = -8.0
	p.play()
	_shudder = minf(1.0, _shudder + 0.2)
	if _now - _hard_hint_at > 5.0:
		_hard_hint_at = _now
		Events.hint.emit(
			tr(layer.too_hard_hint) if layer.too_hard_hint != "" else tr("¡DEMASIADO DURO!"),
			layer.col_light.lightened(0.3)
		)
	set_process(true)


## Si el golpe cae en una zona debilitada por otro elemento, hace daño extra (y la zona
## quebradiza se gasta).
func _apply_weakness(hit: SpellHit) -> void:
	for i: int in MAX_WEAK:
		if _weak_end[i] < _now or _weak_element[i] == hit.element:
			continue
		var p: Vector4 = _weak_pos[i]
		if Vector3(p.x, p.y, p.z).distance_to(hit.position) > _weak_radius[i]:
			continue
		hit.weak_mult = _weak_mult[i]
		hit.damage = roundi(float(hit.damage) * _weak_mult[i])
		hit.weakened = true
		_global_flash = maxf(_global_flash, 0.2)
		# Reacción: fuego sobre cristal congelado -> Explosión de Vapor.
		if _weak_kind[i] < 1.5 and hit.element == &"spark":
			_combos.steam(hit, Vector3(p.x, p.y, p.z))
			_weak_end[i] = _now + 0.3
			_push_weak()
		if _weak_consume[i]:
			_weak_end[i] = _now + 0.4
			_weak_sec[i] = (_now + 0.4) - _weak_pos[i].w
			_push_weak()
		return


func _add_weak(
	at: Vector3,
	radius: float,
	mult: float,
	sec: float,
	consume: bool,
	kind: float,
	element: StringName
) -> void:
	_weak_pos[_weak_index] = Vector4(at.x, at.y, at.z, _now)
	_weak_radius[_weak_index] = radius
	_weak_kind[_weak_index] = kind
	_weak_sec[_weak_index] = sec
	_weak_mult[_weak_index] = mult
	_weak_end[_weak_index] = _now + sec
	_weak_consume[_weak_index] = consume
	_weak_element[_weak_index] = element
	_weak_index = (_weak_index + 1) % MAX_WEAK
	_push_weak()


func _push_weak() -> void:
	_material.set_shader_parameter("weak_zones", _weak_pos)
	_material.set_shader_parameter("weak_radius", _weak_radius)
	_material.set_shader_parameter("weak_kind", _weak_kind)
	_material.set_shader_parameter("weak_sec", _weak_sec)


## Cada elemento deja su huella en el cristal. Fuego: quemadura al rojo (más grande cuanto más
## nivel) y, si el hechizo lo pide (Bola de Fuego), fuego que sigue ardiendo y quemando.
func _apply_element(hit: SpellHit) -> void:
	# Elementos que debilitan la zona (la Escarcha congela).
	var el: ElementDef = hit.element_def
	if el and el.weaken_mult > 1.0:
		_add_weak(
			hit.position,
			hit.tier.crack_radius * 1.6 * hit.size,
			el.weaken_mult,
			el.weaken_sec,
			false,
			1.0,
			el.id
		)
	if el and not el.impact_sfx.is_empty():
		if not _element_sounds.has(el):
			var r := AudioStreamRandomizer.new()
			for st: AudioStream in el.impact_sfx:
				r.add_stream(-1, st)
			r.random_pitch = 1.1
			_element_sounds[el] = r
		_spell_player.stream = _element_sounds[el]
		_spell_player.global_position = hit.position
		_spell_player.volume_db = -6.0
		_spell_player.play()
	# Combinaciones que dejan la zona quebradiza (Choque Térmico): congelada y al rojo a la vez.
	if hit.recipe and hit.recipe.shatter_mult > 1.0:
		var r2: float = hit.tier.crack_radius * 2.0 * hit.size
		_add_weak(
			hit.position, r2, hit.recipe.shatter_mult, hit.recipe.shatter_sec, true, 2.0, &"shatter"
		)
		_add_burn(hit.position, r2 * 0.8)
		return
	if hit.element != &"spark":
		return
	var big: bool = hit.recipe != null
	var radius: float = hit.tier.crack_radius * (2.4 if big else 1.1) * hit.size
	_add_burn(hit.position, radius)
	if big and hit.recipe.burn_sec > 0.0 and hit.size >= 0.6:
		_burn_fire.ignite(
			hit.position,
			hit.normal,
			radius * 0.9,
			hit.recipe.burn_sec,
			hit.recipe.burn_tick_sec,
			maxi(1, roundi(hit.recipe.burn_damage * GameState.stat(&"fireball_mult", 1.0)))
		)


func _add_burn(at: Vector3, radius: float) -> void:
	_burns[_burn_index] = Vector4(at.x, at.y, at.z, _now)
	_burn_radius[_burn_index] = radius
	_burn_index = (_burn_index + 1) % MAX_BURNS
	_material.set_shader_parameter("burns", _burns)
	_material.set_shader_parameter("burn_radius", _burn_radius)


## Golpe de quemadura: arranca esencia (el fuego también excava), mantiene caliente la marca y,
## uno de cada tres, suelta una astilla fundida.
func _on_burn_tick(damage: int, at: Vector3) -> void:
	if damage <= 0:
		return
	var n: Vector3 = global_basis * volume.normal_at(to_local(at))
	if _dig(at, n, float(damage), true) < 0.0:
		return
	Events.crystal_burned.emit(damage, at)
	_burn_ticks += 1
	_core_pulse = maxf(_core_pulse, 0.4)
	if _burn_ticks % 3 == 0:
		_shards.spawn(at, n, ShardPool.type_for_hit(1, false), 1, 0.8, _hit_layer)
	set_process(true)


func _play_spell_impact(hit: SpellHit) -> void:
	if hit.recipe.impact_sfx.is_empty():
		return
	if not _spell_impacts.has(hit.recipe):
		var r := AudioStreamRandomizer.new()
		for s: AudioStream in hit.recipe.impact_sfx:
			r.add_stream(-1, s)
		r.random_pitch = 1.08
		_spell_impacts[hit.recipe] = r
	_spell_player.stream = _spell_impacts[hit.recipe]
	_spell_player.global_position = hit.position
	_spell_player.volume_db = 0.0 if hit.resonant else -2.0
	_spell_player.play()


## Capa nueva (se ha excavado hasta ella por primera vez): tormenta de rayos, retumbe y aviso.
func _enter_layer(idx: int) -> void:
	_layer = idx
	var layer: CrystalLayerDef = GameState.LAYERS[idx]
	_arcs.storm(global_position, volume.top, WorldLayout.CRYSTAL_FOOTPRINT, ARC_COLORS[1])
	_global_flash = 1.0
	_core_pulse = 1.0
	_shudder = 1.0
	_accent_player.stream = SURGE_SFX
	_accent_player.volume_db = 0.0
	_accent_player.pitch_scale = 0.8
	_accent_player.play()
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam is CameraRig:
		(cam as CameraRig).add_trauma(0.6)
	Events.hint.emit(
		tr("NUEVA CAPA: %s") % tr(layer.display_name).to_upper(), layer.col_light.lightened(0.3)
	)
	Events.crystal_layer_changed.emit(layer, idx)
	set_process(true)


## Una excavación que llega a una bolsa de geoda la abre: se ve la amatista y la geoda dentro.
func _check_pockets(p: Vector3, radius: float) -> void:
	for i: int in volume.geodes.size():
		if GameState.progression.geodes.has(i):
			continue
		var g: Dictionary = volume.geodes[i]
		if (g["center"] as Vector3).distance_to(p) < float(g["radius"]) + radius * 0.6:
			GameState.progression.geodes[i] = 1
			_reveal_geode(i, true)


func _reveal_geode(i: int, announce: bool) -> void:
	var g: Dictionary = volume.geodes[i]
	var r: float = g["radius"]
	var node := Geode.new()
	node.name = "Geode%d" % i
	add_child(node)
	node.place(to_global((g["center"] as Vector3) - Vector3(0.0, r * 0.7, 0.0)), Vector3.UP)
	node.scale = Vector3.ONE * r * 1.4
	_geode_nodes[i] = node
	if not announce:
		return
	_accent_player.stream = STREAK_SFX
	_accent_player.pitch_scale = 1.25
	_accent_player.volume_db = -4.0
	_accent_player.play()
	_global_flash = maxf(_global_flash, 0.3)
	Events.hint.emit(tr("¡UNA GEODA! REVIÉNTALA"), Color("#e9a5ff"))


## Un golpe cerca de una geoda abierta la revienta.
func _check_geodes(hit: SpellHit) -> void:
	var reach: float = 2.0 + hit.tier.crack_radius * 0.5 * hit.size
	for i: int in _geode_nodes:
		var g: Geode = _geode_nodes[i]
		if g.active and g.global_position.distance_to(hit.position) <= reach + g.scale.x * 0.4:
			_break_geode(i, hit)
			return


func _break_geode(i: int, hit: SpellHit) -> void:
	var g: Geode = _geode_nodes[i]
	var at: Vector3 = g.global_position
	var n: Vector3 = g.global_basis.y.normalized()
	g.break_open()
	_geode_nodes.erase(i)
	g.queue_free.call_deferred()
	GameState.progression.geodes[i] = 2
	var layer: CrystalLayerDef = GameState.LAYERS[1]
	var chunk: ShardType = ShardPool.TYPES[ShardPool.TYPES.size() - 1]
	_shards.spawn(at + n * 0.5, n, chunk, layer.geode_shards, 1.5, 1)
	_hd_fx.play(at, n, hit.tier, true, true)
	_arcs.strike(at, n, 1.6, Color(1.6, 0.5, 2.0))
	_accent_player.stream = GEODE_SFX
	_accent_player.pitch_scale = 1.5
	_accent_player.volume_db = -2.0
	_accent_player.play()
	_global_flash = maxf(_global_flash, 0.5)
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam is CameraRig:
		(cam as CameraRig).add_trauma(0.3)
	HitStop.trigger(get_tree(), 0.07)
	Events.hint.emit(tr("¡GEODA! +%d FRAGMENTOS GRANDES") % layer.geode_shards, Color("#e9a5ff"))
	Events.geode_broken.emit(at)
	set_process(true)


## El cristal reacciona con energía propia: rayos que recorren la superficie desde el impacto
## (más cuanto más fuerte el golpe y más larga la racha) y destellos en estrella. Cada cierto
## daño acumulado, se resquebraja entero (`_surge`).
func _crystal_reacts(hit: SpellHit) -> void:
	var power: float = (
		clampf(float(hit.damage) / 12.0, 0.1, 1.4) + minf(float(hit.streak) / 30.0, 0.5)
	)
	if hit.recipe or hit.resonant:
		power += 0.6
	var col: Color = (
		Color(2.0, 1.3, 0.3) if hit.resonant else ARC_COLORS[_rng.randi() % ARC_COLORS.size()]
	)
	_arcs.strike(hit.position, hit.normal, power, col)
	if power > 0.5 or _rng.randf() < 0.3:
		_arc_player.global_position = hit.position
		_arc_player.volume_db = lerpf(-14.0, -6.0, clampf(power, 0.0, 1.0))
		_arc_player.play()
	_surge_acc += float(hit.damage)
	if _surge_acc >= _next_surge:
		_surge_acc = 0.0
		_next_surge *= SURGE_GROWTH
		_surge.call_deferred(hit)


## ¡El cristal se resquebraja!: tormenta de rayos por todo el cristal, destello desde el
## corazón, retumbe grave, sacudida y una grieta grande que se queda.
func _surge(hit: SpellHit) -> void:
	_arcs.storm(global_position, volume.top, WorldLayout.CRYSTAL_FOOTPRINT, ARC_COLORS[0])
	_global_flash = 0.85
	_core_pulse = 1.0
	_shudder = 1.0
	_hd_fx.play(hit.position, hit.normal, hit.tier, true, true)
	_accent_player.stream = SURGE_SFX
	_accent_player.volume_db = -2.0
	_accent_player.pitch_scale = 1.0
	_accent_player.play()
	_cracks[_crack_index] = Vector4(hit.position.x, hit.position.y, hit.position.z, 3.5)
	_crack_index = (_crack_index + 1) % MAX_CRACKS
	_material.set_shader_parameter("cracks", _cracks)
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam is CameraRig:
		(cam as CameraRig).add_trauma(0.45)
	HitStop.trigger(get_tree(), 0.08)
	Events.hint.emit(tr("¡EL CRISTAL SE RESQUEBRAJA!"), Color("#a5f0ff"))
	set_process(true)


func _play_tink(hit: SpellHit) -> void:
	# Con mucha cadencia, un golpe audible cada poco (los demás se ven pero no suenan): sin
	# muro de sonido.
	if _now - _last_tink < 0.06 and not hit.resonant and hit.recipe == null:
		return
	_last_tink = _now
	var step: int = STREAK_LADDER[(hit.streak - 1) % STREAK_LADDER.size()]
	var p: AudioStreamPlayer3D = _tink_players[_tink_next]
	_tink_next = (_tink_next + 1) % _tink_players.size()
	p.global_position = hit.position
	p.pitch_scale = (
		pow(2.0, float(step) / 12.0)
		* _rng.randf_range(0.99, 1.01)
		* GameState.LAYERS[_hit_layer].hit_pitch
	)
	p.volume_db = -4.0 if hit.resonant else -10.0
	p.play()
	_break_player.global_position = hit.position
	_break_player.play()


func _process(delta: float) -> void:
	_now += delta
	_material.set_shader_parameter("now", _now)
	if _streak.expire(_now):
		Events.streak_broken.emit(_streak.streak)
		Events.streak_changed.emit(0)
	# Temblor: el cristal es enorme, así que se mueve muy poco (centímetros) y muy rápido.
	if _shudder > 0.0:
		_shudder = maxf(0.0, _shudder - delta * 4.0)
		var a: float = _shudder * _shudder * 0.09
		_chunks.position = Vector3(
			_rng.randf_range(-a, a), _rng.randf_range(-a, a) * 0.5, _rng.randf_range(-a, a)
		)
	else:
		_chunks.position = Vector3.ZERO
	_core_pulse = maxf(0.0, _core_pulse - delta * 2.5)
	_material.set_shader_parameter("core_pulse", 0.5 + 0.5 * sin(_now * 1.4) + _core_pulse * 2.0)
	_global_flash = maxf(0.0, _global_flash - delta * 5.0)
	_material.set_shader_parameter("global_flash", _global_flash)
