class_name MotherCrystal
extends Node3D
## El Cristal Madre. Recibe impactos y reacciona: destello y onda en la faceta, grieta que se
## queda, temblor, pulso del corazón violeta, fragmentos que saltan, partículas, luz y sonido
## ("tink") que sube de tono con la racha. Ver GDD 10.3.

const CRYSTAL_SHADER: Shader = preload("res://crystal/crystal.gdshader")
const MAX_HITS: int = 6
const MAX_CRACKS: int = 16
const MAX_BURNS: int = 12
const MAX_WEAK: int = 8
## Escala pentatónica (semitonos) que recorre el "tink" a medida que crece la racha.
const STREAK_LADDER: PackedInt32Array = [-5, -3, 0, 2, 4, 7, 9, 12, 14, 16]
const TINKS: Array[AudioStream] = [
	preload("res://audio/sfx/sfx_crystal_tink_01.ogg"),
	preload("res://audio/sfx/sfx_crystal_tink_02.ogg"),
	preload("res://audio/sfx/sfx_crystal_tink_03.ogg"),
	preload("res://audio/sfx/sfx_crystal_tink_04.ogg"),
]
const BREAKS: Array[AudioStream] = [
	preload("res://audio/sfx/sfx_shard_break_01.ogg"),
	preload("res://audio/sfx/sfx_shard_break_02.ogg"),
	preload("res://audio/sfx/sfx_shard_break_03.ogg"),
]
const RESONANT_SFX: AudioStream = preload("res://audio/sfx/sfx_resonant_hit_01.ogg")
const STREAK_SFX: AudioStream = preload("res://audio/sfx/sfx_streak_chime_01.ogg")
const HUM_SFX: AudioStream = preload("res://audio/sfx/amb_crystal_hum_loop.ogg")

@export var crystal_scale: float = WorldLayout.CRYSTAL_SCALE
@export var seed_value: int = 11

var _material: ShaderMaterial
var _mesh_instance: MeshInstance3D
var _shards: ShardPool
var _fx: ImpactFx
var _hd_fx: HdImpact
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
	_rng.randomize()
	_streak = StreakTracker.new(GameState.BALANCE.streak_window_sec)
	var builder := CrystalClusterBuilder.new()
	builder.build(crystal_scale, seed_value)
	_material = ShaderMaterial.new()
	_material.shader = CRYSTAL_SHADER
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "Mesh"
	_mesh_instance.mesh = builder.mesh
	_mesh_instance.material_override = _material
	add_child(_mesh_instance)
	var body := StaticBody3D.new()
	body.name = "Body"
	body.collision_layer = 1 << 1
	body.collision_mask = 0
	body.set_meta(&"mother_crystal", self)
	for hull: PackedVector3Array in builder.hulls:
		var shape := ConvexPolygonShape3D.new()
		shape.points = hull
		var col := CollisionShape3D.new()
		col.shape = shape
		body.add_child(col)
	add_child(body)
	_shards = ShardPool.new()
	_shards.name = "Shards"
	add_child(_shards)
	_fx = ImpactFx.new()
	_fx.name = "ImpactFx"
	add_child(_fx)
	_hd_fx = HdImpact.new()
	_hd_fx.name = "HdImpact"
	add_child(_hd_fx)
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
	_material.set_shader_parameter("core_top", 4.5 * crystal_scale)
	_material.set_shader_parameter("core_bottom", -0.5)


func _setup_audio() -> void:
	_tink_random = AudioStreamRandomizer.new()
	for s: AudioStream in TINKS:
		_tink_random.add_stream(-1, s)
	_tink_random.random_pitch = 1.0
	_tink_random.random_volume_offset_db = 1.5
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
	_break_player.volume_db = -4.0
	_break_player.max_polyphony = 3
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
	var balance: BalanceConfig = GameState.BALANCE
	hit.streak = _streak.register_hit(_now)
	_apply_weakness(hit)
	GameState.hit_crystal(hit.damage, hit.position)
	var tier: SpellTier = hit.tier

	_hits[_hit_index] = Vector4(hit.position.x, hit.position.y, hit.position.z, _now)
	_hit_resonant[_hit_index] = 1.0 if hit.resonant else 0.0
	_hit_index = (_hit_index + 1) % MAX_HITS
	_cracks[_crack_index] = Vector4(
		hit.position.x,
		hit.position.y,
		hit.position.z,
		tier.crack_radius * (1.6 if hit.resonant else 1.0) * _rng.randf_range(0.85, 1.15)
	)
	_crack_index = (_crack_index + 1) % MAX_CRACKS
	if hit.recipe and hit.recipe.area_radius > 0.0:
		_area_blast(hit)
	_apply_element(hit)
	_material.set_shader_parameter("hits", _hits)
	_material.set_shader_parameter("hit_resonant", _hit_resonant)
	_material.set_shader_parameter("cracks", _cracks)

	_shudder = minf(1.0, _shudder + 0.35 + tier.shake * 2.0 + (0.5 if hit.resonant else 0.0))
	_core_pulse = 1.0
	if hit.resonant:
		_global_flash = 0.55
	var count: int = _rng.randi_range(tier.shards_min, tier.shards_max) * (2 if hit.resonant else 1)
	var shard_type: ShardType = ShardPool.type_for_hit(hit.damage, hit.resonant)
	_shards.spawn(hit.position, hit.normal, shard_type, count, 1.25 if hit.resonant else 1.0)
	_fx.play(hit.position, hit.normal, tier, hit.resonant)
	_hd_fx.play(hit.position, hit.normal, tier, hit.resonant, hit.recipe != null)
	_play_tink(hit)
	if hit.recipe:
		_play_spell_impact(hit)
	if hit.resonant:
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
		var r: float = recipe.area_radius * _rng.randf_range(0.55, 1.0)
		var p: Vector3 = hit.position + (side * cos(a) + up * sin(a)) * r
		_cracks[_crack_index] = Vector4(
			p.x, p.y, p.z, hit.tier.crack_radius * _rng.randf_range(0.45, 0.7)
		)
		_crack_index = (_crack_index + 1) % MAX_CRACKS
		_hits[_hit_index] = Vector4(p.x, p.y, p.z, _now)
		_hit_resonant[_hit_index] = 0.0
		_hit_index = (_hit_index + 1) % MAX_HITS
		_shards.spawn(p, n, splinter, 1, 1.15)
		_fx.play(p, n, hit.tier, false)
		_hd_fx.play(p, n, hit.tier, false)


## Pantalla de carga: dispara una vez cada efecto de impacto y de fuego en `at` (sin daño ni
## fragmentos que recoger) para compilar shaders y partículas antes de jugar.
func warm_up(at: Vector3, normal: Vector3, tier: SpellTier, big_tier: SpellTier) -> void:
	_fx.play(at, normal, tier, true)
	_hd_fx.play(at, normal, tier, false)
	_hd_fx.play(at, normal, big_tier, true, true)
	_burn_fire.ignite(at, normal, 1.0, 0.6, 0.3, 0)
	_add_burn(at, 0.01)
	_shards.warm_up(at + normal * 1.5)
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
			hit.tier.crack_radius * 1.6,
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
		var r2: float = hit.tier.crack_radius * 2.0
		_add_weak(
			hit.position, r2, hit.recipe.shatter_mult, hit.recipe.shatter_sec, true, 2.0, &"shatter"
		)
		_add_burn(hit.position, r2 * 0.8)
		return
	if hit.element != &"spark":
		return
	var big: bool = hit.recipe != null
	var radius: float = hit.tier.crack_radius * (2.4 if big else 1.1)
	_add_burn(hit.position, radius)
	if big and hit.recipe.burn_sec > 0.0:
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


## Golpe de quemadura: quita esencia, mantiene caliente la marca y, uno de cada tres, suelta
## una astilla fundida.
func _on_burn_tick(damage: int, at: Vector3) -> void:
	if damage <= 0:
		return
	GameState.hit_crystal(damage, at)
	Events.crystal_burned.emit(damage, at)
	_burn_ticks += 1
	_core_pulse = maxf(_core_pulse, 0.4)
	if _burn_ticks % 3 == 0:
		var n: Vector3 = at - global_position
		n.y = 0.0
		_shards.spawn(at, n.normalized(), ShardPool.type_for_hit(1, false), 1, 0.8)
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


func _play_tink(hit: SpellHit) -> void:
	var step: int = STREAK_LADDER[mini(hit.streak - 1, STREAK_LADDER.size() - 1)]
	var p: AudioStreamPlayer3D = _tink_players[_tink_next]
	_tink_next = (_tink_next + 1) % _tink_players.size()
	p.global_position = hit.position
	p.pitch_scale = pow(2.0, float(step) / 12.0) * _rng.randf_range(0.99, 1.01)
	p.volume_db = -1.0 if hit.resonant else -4.0
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
		_mesh_instance.position = Vector3(
			_rng.randf_range(-a, a), _rng.randf_range(-a, a) * 0.5, _rng.randf_range(-a, a)
		)
	else:
		_mesh_instance.position = Vector3.ZERO
	_core_pulse = maxf(0.0, _core_pulse - delta * 2.5)
	_material.set_shader_parameter("core_pulse", 0.5 + 0.5 * sin(_now * 1.4) + _core_pulse * 2.0)
	_global_flash = maxf(0.0, _global_flash - delta * 5.0)
	_material.set_shader_parameter("global_flash", _global_flash)
