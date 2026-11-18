class_name CoreTears
extends Node3D
## Lágrimas del Núcleo (GDD 6.1 y 8): el fragmento especial del Corazón Cristalino. Sólo brotan de
## los hechizos combinados que arrancan Corazón (probabilidad por daño y piedad, ver TearDrops),
## flotan a media altura latiendo como un corazón (luz, halo HD, motas y su latido) y hay que
## recogerlas: con F (el Jugador apunta con `target`), con la Telequinesis o, con el Ojo del
## Núcleo, solas desde lejos. Los familiares no las ven. Al recogerlas van directas al contador
## (`GameState.collect_tear`), no a la bolsa ni a la trituradora.
## Antes de excavar (`apply`) aplica también los nodos del Núcleo: Fractura del Corazón (más daño
## de los combinados) y Corazón Vidente (más golpes resonantes en el Corazón).
## Pool fijo: nada se instancia durante el juego.

const TEAR_TYPE: ShardType = preload("res://data/shards/core_tear.tres")
const TEAR_SHADER: Shader = preload("res://crystal/core_tear.gdshader")
const DROP_SFX: AudioStream = preload("res://audio/sfx/sfx_tear_drop_01.ogg")
const PICKUP_SFX: AudioStream = preload("res://audio/sfx/sfx_tear_pickup_01.ogg")
const BEAT_SFX: Array[AudioStream] = [
	preload("res://audio/sfx/sfx_tear_beat_01.ogg"),
	preload("res://audio/sfx/sfx_tear_beat_02.ogg"),
]
const MAX_TEARS: int = 8
## Tamaño de la gota (1 = 0,64 m de alto): grande para leerse a pocos metros en pixel art.
const TEAR_SCALE: float = 1.3
const BURSTS: int = 3
## Latido: periodo y separación del segundo golpe ("lub-dub").
const BEAT_SEC: float = 1.15
const DUB_SEC: float = 0.19
## Flota a esta altura sobre el suelo (o el fondo del túnel) en el que cae.
const HOVER_M: float = 1.25
const PICK_SEC: float = 0.42
## Vuelo solo hacia el mago con el Ojo del Núcleo (m) y lo que alarga el de la Telequinesis.
const EYE_RADIUS_M: float = 40.0
const TK_REACH_MULT: float = 1.5
const C_GLOW := Color(0.9, 0.35, 1.6)
const C_PINK := Color(1.6, 0.55, 1.3)
const C_WHITE := Color(1.8, 1.6, 2.0)

var _crystal: MotherCrystal
var _drops: TearDrops
var _rng := RandomNumberGenerator.new()
## Estado de cada hueco: -1 libre, 0 cayendo, 1 flotando, 2 volando a la mano.
var _state: PackedInt32Array = []
var _t: PackedFloat32Array = []
var _dur: PackedFloat32Array = []
var _from: PackedVector3Array = []
var _to: PackedVector3Array = []
var _phase: PackedFloat32Array = []
var _roots: Array[Node3D] = []
var _bodies: Array[MeshInstance3D] = []
var _halos: Array[MeshInstance3D] = []
var _halo_mats: Array[ShaderMaterial] = []
var _motes: Array[GPUParticles3D] = []
var _lights: Array[OmniLight3D] = []
var _beats: Array[AudioStreamPlayer3D] = []
var _bursts: Array[GPUParticles3D] = []
var _flashes: Array[MeshInstance3D] = []
var _flash_mats: Array[ShaderMaterial] = []
var _flash_t: PackedFloat32Array = []
var _burst_next: int = 0
var _drop_player: AudioStreamPlayer3D
var _pickup_player: AudioStreamPlayer
var _beat_random: AudioStreamRandomizer
var _highlighted: int = -1
var _collect_target: Node3D
var _player: Player
var _time: float = 0.0


func setup(crystal: MotherCrystal) -> void:
	_crystal = crystal


func _ready() -> void:
	add_to_group(&"core_tears")
	_rng.randomize()
	_drops = TearDrops.new(GameState.BALANCE)
	var mesh: ArrayMesh = _tear_mesh()
	var mat := ShaderMaterial.new()
	mat.shader = TEAR_SHADER
	_beat_random = AudioStreamRandomizer.new()
	for s: AudioStream in BEAT_SFX:
		_beat_random.add_stream(-1, s)
	_beat_random.random_pitch = 1.04
	for i: int in MAX_TEARS:
		_build_slot(i, mesh, mat)
	for i: int in BURSTS:
		var b: GPUParticles3D = HdFx.sparks(
			48, 7.0, 0.045, PackedColorArray([C_WHITE, C_PINK, C_GLOW, Color(0.3, 0.1, 0.6)])
		)
		b.top_level = true
		_depth_tested(b)
		add_child(b)
		_bursts.append(b)
		var f: MeshInstance3D = HdFx.quad(HdFx.GLOW_SHADER, 1.0, 4)
		f.top_level = true
		f.visible = false
		var fm: ShaderMaterial = f.material_override
		fm.set_shader_parameter("color", C_GLOW)
		fm.set_shader_parameter("rays", 1.0)
		fm.set_shader_parameter("ray_count", 8.0)
		fm.set_shader_parameter("falloff", 2.4)
		fm.set_shader_parameter("cover", 0.3)
		add_child(f)
		_flashes.append(f)
		_flash_mats.append(fm)
		_flash_t.append(0.0)
	_drop_player = AudioStreamPlayer3D.new()
	_drop_player.bus = &"SFX"
	_drop_player.stream = DROP_SFX
	_drop_player.unit_size = 30.0
	_drop_player.max_polyphony = 2
	_drop_player.top_level = true
	add_child(_drop_player)
	_pickup_player = AudioStreamPlayer.new()
	_pickup_player.bus = &"SFX"
	_pickup_player.stream = PICKUP_SFX
	_pickup_player.max_polyphony = 2
	add_child(_pickup_player)
	# Las que quedaron flotando en la partida guardada siguen donde estaban.
	for p: Vector3 in GameState.progression.loose_tears.duplicate():
		_spawn_at(p, p, 0.0)
	set_process(_active_count() > 0)


func _build_slot(i: int, mesh: ArrayMesh, mat: ShaderMaterial) -> void:
	_state.append(-1)
	_t.append(0.0)
	_dur.append(1.0)
	_from.append(Vector3.ZERO)
	_to.append(Vector3.ZERO)
	_phase.append(0.0)
	var root := Node3D.new()
	root.name = "Tear%d" % i
	root.top_level = true
	root.visible = false
	add_child(root)
	var body := MeshInstance3D.new()
	body.mesh = mesh
	body.material_override = mat
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(body)
	var halo: MeshInstance3D = HdFx.quad(HdFx.GLOW_SHADER, 3.2, 3)
	var hm: ShaderMaterial = halo.material_override
	hm.set_shader_parameter("color", C_GLOW)
	# Halo ancho y suave (sólo suma luz): la gota de dentro tiene que seguir leyéndose oscura.
	hm.set_shader_parameter("cover", 0.0)
	hm.set_shader_parameter("falloff", 2.6)
	hm.set_shader_parameter("rays", 0.6)
	hm.set_shader_parameter("ray_count", 4.0)
	hm.set_shader_parameter("seed", float(i) * 1.7)
	root.add_child(halo)
	var motes: GPUParticles3D = HdFx.embers(14, 0.07, PackedColorArray([C_WHITE, C_PINK, C_GLOW]))
	motes.lifetime = 1.4
	motes.local_coords = true
	var pm: ParticleProcessMaterial = motes.process_material
	pm.emission_sphere_radius = 0.35
	pm.gravity = Vector3(0, 0.25, 0)
	pm.orbit_velocity_min = 0.25
	pm.orbit_velocity_max = 0.5
	motes.emitting = false
	_depth_tested(motes)
	root.add_child(motes)
	var light := OmniLight3D.new()
	light.light_color = Color(0.75, 0.35, 1.0)
	light.omni_range = 4.5
	light.light_energy = 0.0
	light.shadow_enabled = false
	root.add_child(light)
	var beat := AudioStreamPlayer3D.new()
	beat.bus = &"SFX"
	beat.stream = _beat_random
	beat.unit_size = 3.5
	beat.max_distance = 22.0
	beat.volume_db = -9.0
	root.add_child(beat)
	_roots.append(root)
	_bodies.append(body)
	_halos.append(halo)
	_halo_mats.append(hm)
	_motes.append(motes)
	_lights.append(light)
	_beats.append(beat)


## Las motas y chispas de la Lágrima sí respetan la profundidad: el cristal las tapa.
static func _depth_tested(p: GPUParticles3D) -> void:
	var m: BaseMaterial3D = null
	if p.draw_pass_1 is QuadMesh:
		m = (p.draw_pass_1 as QuadMesh).material as BaseMaterial3D
	elif p.draw_pass_1 is RibbonTrailMesh:
		m = (p.draw_pass_1 as RibbonTrailMesh).material as BaseMaterial3D
	if m:
		m = m.duplicate()
		m.no_depth_test = false
		(p.draw_pass_1 as PrimitiveMesh).material = m


# --- Reglas (las llama MotherCrystal) ---


## Antes de excavar: un combinado que cae en el Corazón hace más daño con la Fractura del Corazón
## y, con el Corazón Vidente, puede dar en su punto débil (resonante).
func apply(hit: SpellHit) -> void:
	if hit.warmup or hit.recipe == null or _crystal == null:
		return
	if _layer_under(hit) != TearDrops.HEART_LAYER:
		return
	var mult: float = GameState.stat(&"heart_combo_mult", 1.0)
	var seer: float = GameState.stat(&"heart_resonant_percent", 0.0) / 100.0
	if not hit.resonant and seer > 0.0 and _rng.randf() < seer:
		hit.resonant = true
		mult *= float(GameState.BALANCE.resonant_damage_mult)
	if mult != 1.0:
		hit.damage = maxi(1, roundi(float(hit.damage) * mult))


## Después del golpe: si arrancó Corazón con un combinado, quizá brota una Lágrima.
func react(hit: SpellHit) -> void:
	if hit.warmup or hit.recipe == null or hit.layer != TearDrops.HEART_LAYER:
		return
	# Ojo del Núcleo: multiplica la probabilidad (valor del nodo, x1 cerrado).
	var eye: float = GameState.stat(&"tear_eye", 1.0)
	var prog: Progression = GameState.progression
	if _drops.register_heart_hit(prog, _clock(), hit.damage, _rng.randf(), eye):
		drop(hit.position, hit.normal)


## Un golpe rebota: si es un combinado contra el Núcleo expuesto y faltan Lágrimas para la Gran
## Convergencia, el Núcleo llora (la partida nunca se queda sin final).
func react_hard(hit: SpellHit, layer: int) -> void:
	if hit.warmup or hit.recipe == null or layer != TearDrops.CORE_LAYER:
		return
	if not GameState.core_exposed:
		return
	var prog: Progression = GameState.progression
	if _drops.register_core_hit(prog, _clock(), tears_missing_for_final(prog)):
		drop(hit.position, hit.normal)


## Lágrimas que faltan para inscribir la Gran Convergencia (0 si ya está o hay de sobra).
static func tears_missing_for_final(prog: Progression) -> int:
	for node: UpgradeNode in GameState.UPGRADES:
		if (
			node.id == GameState.GRAND_CONVERGENCE
			and prog.get_level(node.id) < node.get_max_level()
		):
			return maxi(0, node.cost_for_level(prog.get_level(node.id)) - prog.tears)
	return 0


## Suma una Lágrima al contador (no va a la bolsa ni al Pilón) y lo anuncia.
static func credit_tear(at: Vector3) -> void:
	var prog: Progression = GameState.progression
	prog.tears += 1
	prog.tears_total += 1
	Events.tear_collected.emit(at)
	Events.tears_changed.emit(prog.tears)


func _clock() -> float:
	return Time.get_ticks_msec() * 0.001


func _layer_under(hit: SpellHit) -> int:
	var n: Vector3 = (_crystal.global_basis.inverse() * hit.normal).normalized()
	return _crystal.volume.layer_at(_crystal.to_local(hit.position) - n * 0.35)


# --- Lágrimas en el mundo ---


## Brota una Lágrima en `at` (la cara del golpe, `normal` hacia fuera): sale, cae despacio hasta
## flotar sobre el suelo o el fondo del túnel y late. Con todas las plazas ocupadas, la más vieja
## vuela sola al contador (nunca se pierde una).
func drop(at: Vector3, normal: Vector3) -> void:
	var n: Vector3 = normal if normal.length_squared() > 0.01 else Vector3.UP
	var from: Vector3 = at + n.normalized() * 0.6
	var out: Vector3 = at + n.normalized() * 2.4
	var to: Vector3 = _hover_point(out)
	var dur: float = clampf(1.1 + from.distance_to(to) * 0.08, 1.1, 3.0)
	var i: int = _spawn_at(from, to, dur)
	_burst(from, 1.4)
	_drop_player.global_position = from
	_drop_player.play()
	Events.tear_dropped.emit(from)
	if i >= 0:
		_flash_body(i)
	else:
		# Todas volando a la mano a la vez (rarísimo): nunca se pierde una, cuenta en el acto.
		_pickup_player.play()
		credit_tear(from)


## Pantalla de carga: enseña una Lágrima y su estallido un instante en `at` para compilar su
## shader, el halo y las partículas antes de jugar (la primera del Corazón no da tirón).
func warm_up(at: Vector3) -> void:
	_roots[0].global_position = at
	_roots[0].scale = Vector3.ONE
	_roots[0].visible = true
	_motes[0].emitting = true
	_lights[0].light_energy = 1.0
	_halo_mats[0].set_shader_parameter("intensity", 0.5)
	_burst(at, 0.5)
	await get_tree().create_timer(0.4).timeout
	if _state[0] < 0:
		_roots[0].visible = false
		_motes[0].emitting = false
		_lights[0].light_energy = 0.0


## Donde flota una Lágrima que sale por `p`: a HOVER_M del suelo o del cristal de debajo.
func _hover_point(p: Vector3) -> Vector3:
	if not is_inside_tree():
		return p
	var q := PhysicsRayQueryParameters3D.create(p, p + Vector3.DOWN * 150.0, 1 | (1 << 1))
	var r: Dictionary = get_world_3d().direct_space_state.intersect_ray(q)
	if r.is_empty():
		return p
	var floor_p: Vector3 = r["position"]
	return Vector3(p.x, floor_p.y + HOVER_M, p.z)


func _spawn_at(from: Vector3, to: Vector3, dur: float) -> int:
	var i: int = _free_slot()
	if i < 0:
		return -1
	_state[i] = 0 if dur > 0.0 else 1
	_t[i] = 0.0
	_dur[i] = maxf(dur, 0.01)
	_from[i] = from
	_to[i] = to
	_phase[i] = _rng.randf() * BEAT_SEC
	_roots[i].global_position = from
	_roots[i].visible = true
	_roots[i].scale = Vector3.ONE * (0.2 if dur > 0.0 else 1.0)
	_motes[i].emitting = true
	_bodies[i].set_instance_shader_parameter("highlight", 0.0)
	_sync_loose()
	set_process(true)
	return i


func _free_slot() -> int:
	var oldest: int = -1
	for i: int in MAX_TEARS:
		if _state[i] < 0:
			return i
		if _state[i] == 1 and (oldest < 0 or _t[i] > _t[oldest]):
			oldest = i
	if oldest >= 0:
		# Sin sitio: la más vieja se recoge sola (vuela al mago y suma).
		_credit(oldest)
		return oldest
	return -1


## Lágrimas en el mundo (cayendo o flotando).
func loose_count() -> int:
	var n: int = 0
	for i: int in MAX_TEARS:
		if _state[i] == 0 or _state[i] == 1:
			n += 1
	return n


func _active_count() -> int:
	var n: int = 0
	for i: int in MAX_TEARS:
		if _state[i] >= 0:
			n += 1
	return n


func position_of(i: int) -> Vector3:
	return _roots[i].global_position


# --- Recoger (lo llama el Jugador) ---


## Lágrima a la que se apunta desde `from` mirando `forward` hasta `reach` m (un cono generoso:
## es rara y no se debe escapar), o -1.
func target(from: Vector3, forward: Vector3, reach: float) -> int:
	var best: int = -1
	var best_k: float = INF
	for i: int in MAX_TEARS:
		if _state[i] != 1 and _state[i] != 0:
			continue
		var rel: Vector3 = _roots[i].global_position - from
		var along: float = rel.dot(forward)
		if along <= 0.2 or along > reach:
			continue
		var off: float = (rel - forward * along).length()
		if off > 0.55 + along * 0.08:
			continue
		var k: float = off / along
		if k < best_k:
			best_k = k
			best = i
	return best


## La más cercana a `point` dentro de `radius`, o -1.
func nearest(point: Vector3, radius: float) -> int:
	var best: int = -1
	var best_d: float = radius * radius
	for i: int in MAX_TEARS:
		if _state[i] != 1 and _state[i] != 0:
			continue
		var d: float = _roots[i].global_position.distance_squared_to(point)
		if d < best_d:
			best_d = d
			best = i
	return best


func set_highlight(i: int) -> void:
	if i == _highlighted:
		return
	if _highlighted >= 0:
		_bodies[_highlighted].set_instance_shader_parameter("highlight", 0.0)
	_highlighted = i
	if i >= 0:
		_bodies[i].set_instance_shader_parameter("highlight", 1.0)


## Recoge la Lágrima `i`: vuela a `hand` (girando, dejando motas) y al llegar suma al contador.
func collect(i: int, hand: Node3D) -> void:
	if i < 0 or (_state[i] != 0 and _state[i] != 1):
		return
	if i == _highlighted:
		set_highlight(-1)
	_state[i] = 2
	_t[i] = 0.0
	_dur[i] = PICK_SEC
	_from[i] = _roots[i].global_position
	_collect_target = hand
	_flash_body(i)
	_burst(_from[i], 0.8)
	_sync_loose()


func _credit(i: int) -> void:
	var at: Vector3 = _roots[i].global_position
	_release(i)
	# Junto a la mano: un destello pequeño (uno grande delante de la cámara la ciega).
	_burst(at, 0.3)
	_pickup_player.play()
	credit_tear(at)


func _release(i: int) -> void:
	if i == _highlighted:
		set_highlight(-1)
	_state[i] = -1
	_roots[i].visible = false
	_motes[i].emitting = false
	_lights[i].light_energy = 0.0
	_sync_loose()


## Guarda dónde flotan (Progression.loose_tears) para que sigan ahí al volver a cargar.
func _sync_loose() -> void:
	var prog: Progression = GameState.progression
	prog.loose_tears.clear()
	for i: int in MAX_TEARS:
		if _state[i] == 0 or _state[i] == 1:
			prog.loose_tears.append(_to[i])


# --- Animación ---


func _process(delta: float) -> void:
	_time += delta
	var any: bool = false
	for i: int in MAX_TEARS:
		if _state[i] < 0:
			continue
		any = true
		_t[i] += delta
		match _state[i]:
			0:
				_update_fall(i)
			1:
				_update_hover(i)
			2:
				_update_collect(i)
	for k: int in BURSTS:
		if _flash_t[k] > 0.0:
			_flash_t[k] = maxf(0.0, _flash_t[k] - delta * 2.6)
			_flash_mats[k].set_shader_parameter("intensity", _flash_t[k] * 1.1)
			_flashes[k].visible = _flash_t[k] > 0.0
			any = true
	_pull_to_player()
	if not any:
		set_process(false)


## Sale del cristal y cae como una hoja: arco suave, crece hasta su tamaño y se frena al llegar.
func _update_fall(i: int) -> void:
	var k: float = clampf(_t[i] / _dur[i], 0.0, 1.0)
	var e: float = 1.0 - pow(1.0 - k, 3.0)
	var p: Vector3 = _from[i].lerp(_to[i], e)
	p.y += sin(k * PI) * 0.8
	_roots[i].global_position = p
	_roots[i].scale = Vector3.ONE * lerpf(0.2, 1.0, minf(1.0, k * 3.0))
	_roots[i].rotate_y(0.12)
	_pulse(i, 1.0 - k)
	if k >= 1.0:
		_state[i] = 1
		_t[i] = 0.0


## Flota, gira despacio y late: luz, halo, borde y sonido a la vez, dos golpes por latido.
func _update_hover(i: int) -> void:
	var p: Vector3 = _to[i] + Vector3.UP * sin(_time * 1.9 + _phase[i]) * 0.12
	_roots[i].global_position = p
	_roots[i].rotate_y(0.02)
	var bt: float = fmod(_time + _phase[i], BEAT_SEC)
	var beat: float = maxf(_spike(bt), _spike(bt - DUB_SEC) * 0.7)
	_pulse(i, beat)
	var prev: float = fmod(_time + _phase[i] - get_process_delta_time(), BEAT_SEC)
	if bt < prev:
		_beats[i].play()


static func _spike(x: float) -> float:
	if x < 0.0:
		return 0.0
	return exp(-x * 11.0)


func _pulse(i: int, beat: float) -> void:
	_bodies[i].set_instance_shader_parameter("beat", beat)
	var hl: float = 0.2 if i == _highlighted else 0.0
	_halo_mats[i].set_shader_parameter("intensity", 0.12 + beat * 0.6 + hl)
	_halos[i].scale = Vector3.ONE * (1.0 + beat * 0.35)
	_lights[i].light_energy = 0.6 + beat * 2.4
	_bodies[i].scale = Vector3.ONE * (1.0 + beat * 0.12)


## Vuela a la mano girando cada vez más rápido y encoge; al llegar, al contador.
func _update_collect(i: int) -> void:
	var k: float = clampf(_t[i] / _dur[i], 0.0, 1.0)
	var target_p: Vector3 = _from[i]
	if is_instance_valid(_collect_target):
		target_p = _collect_target.global_position
	var p: Vector3 = _from[i].lerp(target_p, k * k)
	p.y += sin(k * PI) * 0.5
	_roots[i].global_position = p
	_roots[i].rotate_y(0.3 + k * 0.6)
	_roots[i].scale = Vector3.ONE * maxf(0.1, 1.0 - k * 0.8)
	_pulse(i, 1.0 - k * 0.5)
	if k >= 1.0:
		_credit(i)


## Telequinesis (más alcance) y Ojo del Núcleo (desde lejos): las Lágrimas vuelan solas al mago.
func _pull_to_player() -> void:
	var reach: float = GameState.stat(&"telekinesis_radius", 0.0) * TK_REACH_MULT
	if GameState.stat(&"tear_eye", 1.0) > 1.0:
		reach = maxf(reach, EYE_RADIUS_M)
	if reach <= 0.0:
		return
	if _player == null:
		_player = get_tree().get_first_node_in_group(&"player") as Player
	var player: Player = _player
	if player == null:
		return
	for i: int in MAX_TEARS:
		if _state[i] != 1:
			continue
		if _roots[i].global_position.distance_to(player.global_position) <= reach:
			collect(i, player.grab_point())


func _flash_body(i: int) -> void:
	var tw: Tween = create_tween()
	tw.tween_method(
		func(v: float) -> void: _bodies[i].set_instance_shader_parameter("flash", v), 1.0, 0.0, 0.35
	)


func _burst(at: Vector3, size: float) -> void:
	var k: int = _burst_next
	_burst_next = (_burst_next + 1) % BURSTS
	_bursts[k].global_position = at
	_bursts[k].restart()
	_flashes[k].global_position = at
	_flashes[k].scale = Vector3.ONE * 3.0 * size
	_flash_t[k] = 1.0
	_flashes[k].visible = true
	set_process(true)


## Malla de la lágrima: perfil de gota girado en 8 lados, caras planas (punta arriba).
static func _tear_mesh() -> ArrayMesh:
	var profile: Array[Vector2] = [
		Vector2(-0.24, 0.0),
		Vector2(-0.21, 0.1),
		Vector2(-0.14, 0.17),
		Vector2(-0.04, 0.19),
		Vector2(0.07, 0.16),
		Vector2(0.18, 0.1),
		Vector2(0.29, 0.045),
		Vector2(0.4, 0.0),
	]
	var sides: int = 8
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for s: int in sides:
		var a0: float = TAU * float(s) / float(sides)
		var a1: float = TAU * float(s + 1) / float(sides)
		for k: int in profile.size() - 1:
			var p0: Vector2 = profile[k] * TEAR_SCALE
			var p1: Vector2 = profile[k + 1] * TEAR_SCALE
			var v00 := Vector3(cos(a0) * p0.y, p0.x, sin(a0) * p0.y)
			var v01 := Vector3(cos(a1) * p0.y, p0.x, sin(a1) * p0.y)
			var v10 := Vector3(cos(a0) * p1.y, p1.x, sin(a0) * p1.y)
			var v11 := Vector3(cos(a1) * p1.y, p1.x, sin(a1) * p1.y)
			if p0.y > 0.0:
				_tri(st, v00, v10, v01)
			if p1.y > 0.0:
				_tri(st, v01, v10, v11)
	return st.commit()


## Un triángulo con la normal hacia fuera del eje (el shader no descarta caras: da igual el giro).
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	var n: Vector3 = (b - a).cross(c - a).normalized()
	var mid: Vector3 = (a + b + c) / 3.0
	if n.dot(Vector3(mid.x, 0.0, mid.z)) < 0.0:
		n = -n
	for v: Vector3 in [a, b, c]:
		st.set_normal(n)
		st.add_vertex(v)
