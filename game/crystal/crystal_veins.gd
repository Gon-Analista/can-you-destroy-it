class_name CrystalVeins
extends Node
## Venas Resonantes (GDD 6 y 6.1): en la capa de las venas, cada lado del cristal tiene vetas de
## un color, y cada una es débil a su elemento. Golpearla con él hace más daño, suelta Fragmentos
## Resonantes (valen como cinco fragmentos grandes) y la vena se enciende y canta su nota. Las
## combinaciones cuentan con cualquiera de sus elementos (premia combinar). Con otro elemento no
## pasa nada especial, salvo un aviso de vez en cuando que dice a qué es débil.
##
## Lógica y dibujo usan la misma regla: el shader del cristal (`li == 2`) pinta las vetas según el
## sector de la posición en el mundo, sector = floor((atan(z, x) + PI) / TAU * 5), y aquí se
## calcula igual con el punto del golpe. Cuenta el sector entero y no sólo las líneas finas del
## voronoi: un cráter (0,85 m o más) siempre toca alguna veta (las celdas miden ~2,4 m), y repetir
## el hash del shader en GDScript (doble precisión) no casaría píxel a píxel.

const SECTORS: int = 5
## Una nota por vena (pentatónica de La), ver tools/sfx_veins.py.
const CHIMES: Array[AudioStream] = [
	preload("res://audio/sfx/sfx_vein_chime_01.ogg"),
	preload("res://audio/sfx/sfx_vein_chime_02.ogg"),
	preload("res://audio/sfx/sfx_vein_chime_03.ogg"),
	preload("res://audio/sfx/sfx_vein_chime_04.ogg"),
	preload("res://audio/sfx/sfx_vein_chime_05.ogg"),
]
const GLOW_SHADER: Shader = preload("res://fx/hd/hd_glow.gdshader")
## Veces que sale el cartel grande; después, como mucho uno cada BANNER_GAP_SEC.
const BANNER_FIRST: int = 4
const BANNER_GAP_SEC: float = 25.0
## Aviso de "esta vena es débil a..." (golpe con otro elemento): como mucho uno cada tanto.
const HINT_GAP_SEC: float = 9.0

var _crystal: MotherCrystal
var _arcs: CrystalArcs
var _shards: ShardPool
var _player: AudioStreamPlayer3D
var _sparks: Array[GPUParticles3D] = []
var _halo: MeshInstance3D
var _halo_mat: ShaderMaterial
var _halo_t: float = 0.0
## Encendido de cada vena en el shader (0..1), que se apaga poco a poco.
var _pulse := PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 0.0])
var _pulsing: bool = false
var _banners: int = 0
var _taught: bool = false
var _last_banner: float = -100.0
var _last_hint: float = -100.0
var _last_chime: float = -1.0
var _now: float = 0.0
var _rng := RandomNumberGenerator.new()


func setup(crystal: MotherCrystal, arcs: CrystalArcs, shards: ShardPool) -> void:
	_crystal = crystal
	_arcs = arcs
	_shards = shards
	_rng.randomize()
	for c: Color in MotherCrystal.VEIN_COLORS:
		var s: GPUParticles3D = HdFx.sparks(
			40, 11.0, 0.07, PackedColorArray([Color(1.8, 1.8, 1.8), c * 2.4, c])
		)
		s.name = "VeinSparks"
		add_child(s)
		_sparks.append(s)
	_halo = HdFx.quad(GLOW_SHADER, 7.0, 4)
	_halo.name = "VeinHalo"
	_halo.visible = false
	_halo_mat = _halo.material_override
	_halo_mat.set_shader_parameter("rays", 1.2)
	_halo_mat.set_shader_parameter("ray_count", 10.0)
	_halo_mat.set_shader_parameter("falloff", 2.0)
	add_child(_halo)
	_player = AudioStreamPlayer3D.new()
	_player.bus = &"SFX"
	_player.unit_size = 40.0
	_player.max_polyphony = 3
	add_child(_player)


## Sector del cristal (0..4) en un punto del mundo: el mismo que usa el shader para las vetas.
static func sector_at(world_pos: Vector3) -> int:
	var s: int = floori((atan2(world_pos.z, world_pos.x) + PI) / TAU * float(SECTORS))
	return posmod(s, SECTORS)


## Si el golpe lleva ese elemento: el suyo, o cualquiera de los de su combinación.
static func carries(hit: SpellHit, element: StringName) -> bool:
	if hit.recipe:
		return hit.recipe.elements.has(element)
	return hit.element == element


## Capa del cristal bajo un golpe (la misma cuenta que MotherCrystal._dig).
func layer_under(hit: SpellHit) -> int:
	var n: Vector3 = (_crystal.global_basis.inverse() * hit.normal).normalized()
	return _crystal.volume.layer_at(_crystal.to_local(hit.position) - n * 0.35)


## Antes de excavar: si el golpe cae en una vena la anota y, si es su elemento débil, hace más
## daño (así el cráter también es más grande).
func apply(hit: SpellHit) -> void:
	hit.vein = -1
	hit.vein_weak = false
	if hit.warmup:
		return
	var def: CrystalLayerDef = GameState.LAYERS[layer_under(hit)]
	if def.vein_elements.is_empty():
		return
	var sector: int = sector_at(hit.position)
	if sector >= def.vein_elements.size():
		return
	hit.vein = sector
	hit.vein_weak = carries(hit, def.vein_elements[sector])
	if hit.vein_weak:
		hit.damage = maxi(1, roundi(float(hit.damage) * def.vein_damage_mult))


## Después del golpe: la reacción de la vena (o el aviso si el elemento no era el suyo).
func react(hit: SpellHit) -> void:
	if hit.vein < 0:
		return
	var def: CrystalLayerDef = GameState.LAYERS[hit.layer]
	if def.vein_elements.is_empty():
		return
	var col: Color = MotherCrystal.VEIN_COLORS[hit.vein]
	var element: StringName = def.vein_elements[hit.vein]
	if not hit.vein_weak:
		_wrong(hit, def, col)
		return
	var n: Vector3 = hit.normal if hit.normal.length_squared() > 0.01 else Vector3.BACK
	var count: int = ceili(
		float(def.vein_shards * (2 if hit.resonant else 1)) * (1.0 + (hit.size - 1.0) * 0.6)
	)
	if hit.minor:
		count = 1 if _rng.randf() < 0.35 else 0
	if count > 0:
		_shards.spawn(hit.position, n, ShardPool.RESONANT, count, 1.2, hit.layer, col)
	_burst(hit, n, col)
	_chime(hit)
	Events.vein_hit.emit(hit, element)
	_banner(def, hit.vein, col)


## La vena se enciende: rayos de su color que corren por la veta, chispas y un halo.
func _burst(hit: SpellHit, n: Vector3, col: Color) -> void:
	var power: float = 0.6 if hit.minor else 1.4
	_arcs.strike(hit.position, n, power, col * 1.6)
	var side: Vector3 = n.cross(Vector3.UP if absf(n.y) < 0.95 else Vector3.RIGHT).normalized()
	var up: Vector3 = side.cross(n).normalized()
	for k: int in 1 if hit.minor else 4:
		var a: float = _rng.randf() * TAU
		var to: Vector3 = (
			hit.position
			+ (side * cos(a) + up * sin(a)) * _rng.randf_range(2.5, 6.5) * sqrt(hit.size)
			+ n * 0.15
		)
		_arcs.bolt_between(hit.position + n * 0.2, to, 0.12, col * 1.4, 0.55)
	_pulse[hit.vein] = maxf(_pulse[hit.vein], 0.5 if hit.minor else 1.0)
	_pulsing = true
	var sparks: GPUParticles3D = _sparks[hit.vein]
	sparks.global_position = hit.position + n * 0.4
	sparks.amount_ratio = 0.35 if hit.minor else 1.0
	sparks.restart()
	if not hit.minor:
		_halo.global_position = hit.position + n * 0.8
		_halo_mat.set_shader_parameter("color", Color(col.r, col.g, col.b))
		_halo_mat.set_shader_parameter("seed", _rng.randf() * 6.0)
		_halo_t = 1.0
		_halo.visible = true
		_crystal.flash(0.22)


func _chime(hit: SpellHit) -> void:
	if _now - _last_chime < 0.12 and hit.minor:
		return
	_last_chime = _now
	_player.stream = CHIMES[hit.vein % CHIMES.size()]
	_player.global_position = hit.position
	_player.pitch_scale = _rng.randf_range(0.985, 1.015)
	_player.volume_db = -10.0 if hit.minor else -2.0
	_player.play()


## Cartel "¡VENA DE CHISPA!": las primeras veces y luego de tarde en tarde.
func _banner(def: CrystalLayerDef, sector: int, col: Color) -> void:
	if _banners >= BANNER_FIRST and _now - _last_banner < BANNER_GAP_SEC:
		return
	_banners += 1
	_last_banner = _now
	var vein_name: String = tr(def.vein_names[sector]) if sector < def.vein_names.size() else ""
	Events.hint.emit(
		tr("¡VENA DE %s! DAÑO x%d") % [vein_name.to_upper(), roundi(def.vein_damage_mult)],
		col.lightened(0.25)
	)
	if not _taught:
		_taught = true
		Events.hint.emit(tr("FRAGMENTOS RESONANTES: VALEN x5"), col.lightened(0.4))


## Golpe en una vena con otro elemento: un chispazo tenue de su color y, de vez en cuando, a
## qué es débil.
func _wrong(hit: SpellHit, def: CrystalLayerDef, col: Color) -> void:
	if not hit.minor:
		_arcs.strike(hit.position, hit.normal, 0.2, col * 1.4)
	if _now - _last_hint < HINT_GAP_SEC:
		return
	_last_hint = _now
	var vein_name: String = tr(def.vein_names[hit.vein]) if hit.vein < def.vein_names.size() else ""
	Events.hint.emit(tr("ESTA VENA ES DÉBIL A: %s") % vein_name.to_upper(), col.lightened(0.3))


func _process(delta: float) -> void:
	_now += delta
	if _pulsing:
		_pulsing = false
		for i: int in _pulse.size():
			_pulse[i] = maxf(0.0, _pulse[i] - delta * 0.9)
			_pulsing = _pulsing or _pulse[i] > 0.0
		_crystal.set_crystal_param(&"vein_pulse", _pulse)
	if _halo_t <= 0.0:
		return
	_halo_t = maxf(0.0, _halo_t - delta * 2.2)
	_halo_mat.set_shader_parameter("intensity", _halo_t * _halo_t * 0.7)
	_halo.scale = Vector3.ONE * (0.6 + (1.0 - _halo_t) * 0.8)
	if _halo_t <= 0.0:
		_halo.visible = false
