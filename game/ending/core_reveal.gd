class_name CoreReveal
extends Node3D
## GDD 9: "al llegar al 99 % el cristal se resquebraja y deja expuesto el Núcleo, una esfera de luz
## que no recibe daño". Vive bajo el Cristal Madre (lo crea `MotherCrystal`).
##
## - El momento: el cristal entero se resquebraja (destello, tormenta de rayos, crujido, la música
##   pasa a la capa tensa y el valle se oscurece) y lo que queda se desprende en trozos grandes que
##   salen volando y estallan al caer, de arriba abajo; luego el Núcleo se enciende.
## - Lo que quede fuera del Núcleo se borra del volumen en otro hilo (la rejilla queda en la esfera
##   del Núcleo, una copia COW: no toca nada compartido), así no se queda ninguna miga flotando.
## - El Núcleo: esfera violeta con luz propia, halo, motas, luz que tiñe el valle y un zumbido.
##   Los golpes rebotan con un destello y, cada poco, "EL NÚCLEO NO CEDE".
## - Red de seguridad: excavar no siempre cuadra con la cuenta de esencia y bajo el suelo hay
##   celdas que no se pueden golpear. Desde `BalanceConfig.core_reveal_scan_from` se mira cada poco
##   (en otro hilo) cuánto queda a tiro; si es casi nada, el Núcleo queda expuesto igual.

enum State { HIDDEN, CRACKING, EXPOSED, GONE }

const ORB_SHADER: Shader = preload("res://ending/core_orb.gdshader")
const GLOW_SHADER: Shader = preload("res://fx/hd/hd_glow.gdshader")
const TOON_SHADER: Shader = preload("res://fx/toon.gdshader")
const TENSION_MUSIC: AudioStream = preload("res://audio/music/mus_core_tension_loop.ogg")
const CRACK_SFX: AudioStream = preload("res://audio/sfx/sfx_core_crack_01.ogg")
const HUM_SFX: AudioStream = preload("res://audio/sfx/amb_core_hum_loop.ogg")
const PEEL_SFX: Array[AudioStream] = [
	preload("res://audio/sfx/sfx_core_peel_01.ogg"),
	preload("res://audio/sfx/sfx_core_peel_02.ogg"),
	preload("res://audio/sfx/sfx_core_peel_03.ogg"),
]
const BOUNCE_SFX: Array[AudioStream] = [
	preload("res://audio/sfx/sfx_core_bounce_01.ogg"),
	preload("res://audio/sfx/sfx_core_bounce_02.ogg"),
]
const CORE_LAYER: int = 4
## La esfera que se ve va un poco por fuera de la del volumen (tapa las facetas de la malla).
const ORB_MARGIN: float = 0.35
const C_LIGHT := Color(0.78, 0.45, 1.0)
const C_HOT := Color(1.6, 1.2, 2.0)
const DEBRIS: int = 26
## Trozos que se desprenden como mucho (el resto se borra al final, de golpe).
const MAX_SITES: int = 36
## Tamaño de las celdas con las que se agrupa lo que queda para elegir los trozos (m).
const BIN_M: float = 7.0
## Segundos que tardan en desprenderse todos los trozos.
const PEEL_SEC: float = 3.0
const HINT_EVERY_SEC: float = 6.0

var state: int = State.HIDDEN
## 0..1: la Gran Convergencia cargándose (el Núcleo tiembla y se blanquea).
var charge: float = 0.0

var _crystal: MotherCrystal
var _volume: CrystalVolume
var _orb: MeshInstance3D
var _orb_mat: ShaderMaterial
var _halo: MeshInstance3D
var _halo_mat: ShaderMaterial
var _light: OmniLight3D
var _body: StaticBody3D
var _motes: GPUParticles3D
var _sparks: Array[GPUParticles3D] = []
var _spark_next: int = 0
var _hum: AudioStreamPlayer3D
var _peel_player: AudioStreamPlayer3D
var _bounce_player: AudioStreamPlayer3D
var _peel_random: AudioStreamRandomizer
var _debris: Array[MeshInstance3D] = []
var _deb_vel: PackedVector3Array = []
var _deb_spin: PackedVector3Array = []
var _deb_life: PackedFloat32Array = []
var _debris_next: int = 0
var _sites: PackedVector4Array = []
var _site_next: int = 0
var _peel_t: float = -1.0
var _crack_t: float = -1.0
var _task: int = -1
var _scan_task: int = -1
var _clear_result: Dictionary = {}
var _scan_result: Array[float] = [-1.0]
var _scan_timer: float = 0.0
var _appear: float = 0.0
var _flash: float = 0.0
var _pulse: float = 0.0
var _now: float = 0.0
var _hint_at: float = -100.0
var _last_peel_sfx: float = -1.0
var _rng := RandomNumberGenerator.new()


func setup(crystal: MotherCrystal) -> void:
	_crystal = crystal
	_volume = crystal.volume


func _ready() -> void:
	add_to_group(&"core_reveal")
	_rng.randomize()
	_build_orb()
	_build_debris()
	_build_audio()
	Events.grimoire_final_revealed.connect(begin)
	var prog: Progression = GameState.progression
	if prog.game_complete:
		state = State.GONE
		_hide_crystal.call_deferred()
	elif GameState.core_exposed:
		# Partida cargada con el Núcleo ya expuesto: sin la escena, todo en su sitio.
		_start_clear()
		_show_exposed(true)
	_apply_visibility()


## Centro del Núcleo (global).
func core_position() -> Vector3:
	return _crystal.to_global(_volume.core_center) if _crystal else global_position


## Radio de la esfera del Núcleo que se ve (m).
func core_radius() -> float:
	return (_volume.core_radius + ORB_MARGIN) if _volume else 6.0


func is_exposed() -> bool:
	return state == State.EXPOSED


## Si un golpe en `at` (global) da en la esfera del Núcleo que se ve.
func covers(at: Vector3) -> bool:
	if state != State.CRACKING and state != State.EXPOSED:
		return false
	return at.distance_to(core_position()) < core_radius() + 0.6


## El cristal llega al 99 %: empieza el momento (una sola vez).
func begin() -> void:
	if state != State.HIDDEN:
		return
	state = State.CRACKING
	_crack_t = 0.0
	_peel_t = -1.0
	_sites.clear()
	_site_next = 0
	# Lo que salga volando ya es Corazón: no hay "NUEVA CAPA" a mitad del momento.
	GameState.progression.deepest_layer = maxi(GameState.progression.deepest_layer, 3)
	_start_clear()
	var arcs: CrystalArcs = _crystal.get_node_or_null(^"Arcs") as CrystalArcs
	if arcs:
		arcs.storm(
			_crystal.global_position, _volume.top, WorldLayout.CRYSTAL_FOOTPRINT, Color(1.2, 0.4, 2)
		)
	_crystal.flash(1.0)
	_crystal.play_accent(CRACK_SFX, 1.0, 0.0)
	for i: int in 6:
		var p: Vector3 = (
			core_position()
			+ Vector3(_rng.randf_range(-14, 14), _rng.randf_range(0, 30), _rng.randf_range(-14, 14))
		)
		_crystal.add_crack(p, _rng.randf_range(2.5, 5.0))
	_trauma(0.9)
	HitStop.trigger(get_tree(), 0.14)
	AudioDirector.play_theme(TENSION_MUSIC, -7.0)
	Events.hint.emit(tr("¡EL CRISTAL SE RESQUEBRAJA!"), Color("#e3b6ff"))
	set_process(true)


## Un golpe rebota en el Núcleo: destello, chispas, "dong" y, cada poco, el aviso. Devuelve true
## si lo ha atendido (entonces el cristal no pone su propio aviso).
func react_hard(hit: SpellHit, layer: int) -> bool:
	if layer != CORE_LAYER or state == State.HIDDEN or state == State.GONE or hit.warmup:
		return false
	_flash = 1.0
	var s: GPUParticles3D = _sparks[_spark_next]
	_spark_next = (_spark_next + 1) % _sparks.size()
	s.global_position = hit.position + hit.normal * 0.3
	s.restart()
	_bounce_player.global_position = hit.position
	_bounce_player.pitch_scale = _rng.randf_range(0.94, 1.06)
	_bounce_player.play()
	if hit.by_player and _now - _hint_at > HINT_EVERY_SEC:
		_hint_at = _now
		Events.hint.emit(tr("EL NÚCLEO NO CEDE"), Color("#e3b6ff"))
	return true


## Fin del juego: el Núcleo estalla (lo hace EndingDirector); aquí se apaga todo y el volumen
## se queda vacío (se guarda así: al volver a cargar no hay cristal).
func vanish() -> void:
	state = State.GONE
	_apply_visibility()
	_hum.stop()
	charge = 0.0
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
	_clear_result = {}
	var r: float = _volume.core_radius + 2.0
	var c: Vector3 = _volume.core_center
	# Sin "NUEVA CAPA: NÚCLEO" al borrarlo.
	GameState.progression.deepest_layer = CORE_LAYER
	_crystal.apply_carve(_volume.carve_sphere(c, r, (1 << (CORE_LAYER + 1)) - 1), c, 0.0, 0.0)
	_hide_crystal()


## Sin cristal: ni malla, ni colisión, ni zumbido, ni destellos alrededor.
func _hide_crystal() -> void:
	for path: NodePath in [^"Chunks", ^"Hum", ^"Arcs/AmbientGlints"]:
		var n: Node = _crystal.get_node_or_null(path)
		if n is Node3D:
			(n as Node3D).visible = false
		if n is AudioStreamPlayer3D:
			(n as AudioStreamPlayer3D).stop()
		if n is GPUParticles3D:
			(n as GPUParticles3D).emitting = false
	var body: StaticBody3D = _crystal.get_node_or_null(^"Body") as StaticBody3D
	if body:
		body.collision_layer = 0


func _build_orb() -> void:
	var r: float = core_radius()
	var sphere := SphereMesh.new()
	sphere.radius = r
	sphere.height = r * 2.0
	sphere.radial_segments = 48
	sphere.rings = 24
	_orb = MeshInstance3D.new()
	_orb.name = "CoreOrb"
	_orb.mesh = sphere
	_orb_mat = ShaderMaterial.new()
	_orb_mat.shader = ORB_SHADER
	_orb.material_override = _orb_mat
	_orb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_orb)
	_orb.position = _volume.core_center if _volume else Vector3.ZERO
	_halo = HdFx.quad(GLOW_SHADER, r * 5.0, 1)
	_halo.name = "CoreHalo"
	_halo_mat = _halo.material_override
	_halo_mat.set_shader_parameter("color", C_LIGHT)
	_halo_mat.set_shader_parameter("rays", 0.6)
	_halo_mat.set_shader_parameter("ray_count", 10.0)
	_halo_mat.set_shader_parameter("falloff", 2.6)
	_halo_mat.set_shader_parameter("cover", 0.15)
	_halo.position = _orb.position
	add_child(_halo)
	_light = OmniLight3D.new()
	_light.name = "CoreLight"
	_light.light_color = Color(0.72, 0.42, 1.0)
	_light.omni_range = 55.0
	_light.omni_attenuation = 1.4
	_light.shadow_enabled = false
	_light.position = _orb.position + Vector3(0, 0, r + 2.0)
	add_child(_light)
	_body = StaticBody3D.new()
	_body.name = "CoreBody"
	_body.collision_layer = 0
	_body.collision_mask = 0
	_body.set_meta(&"mother_crystal", _crystal)
	var shape := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = r
	shape.shape = sph
	_body.add_child(shape)
	_body.position = _orb.position
	add_child(_body)
	_motes = HdFx.embers(
		70, 0.5, PackedColorArray([C_HOT, Color(1.0, 0.45, 1.6), Color(0.4, 0.2, 1.0)])
	)
	_motes.name = "CoreMotes"
	_motes.lifetime = 3.5
	var pm: ParticleProcessMaterial = _motes.process_material
	pm.emission_sphere_radius = r * 1.15
	pm.gravity = Vector3(0, 0.6, 0)
	pm.initial_velocity_min = 0.3
	pm.initial_velocity_max = 1.2
	pm.radial_accel_min = -0.6
	pm.radial_accel_max = -0.2
	_motes.position = _orb.position
	add_child(_motes)
	for i: int in 3:
		var sp: GPUParticles3D = HdFx.sparks(
			28, 9.0, 0.09, PackedColorArray([Color(2.2, 1.9, 2.4), C_HOT, Color(1.0, 0.4, 1.8)])
		)
		sp.name = "Bounce%d" % i
		sp.top_level = true
		add_child(sp)
		_sparks.append(sp)


## Trozos que se desprenden: prismas de cristal (mallas de MeshKit) en un pool.
func _build_debris() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = TOON_SHADER
	mat.set_shader_parameter("rim", 0.45)
	mat.set_shader_parameter("rim_color", Color(0.85, 0.7, 1.0))
	mat.set_shader_parameter("self_light", 0.35)
	var meshes: Array[ArrayMesh] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 91
	var layers: Array[CrystalLayerDef] = GameState.LAYERS
	for k: int in 4:
		var st: SurfaceTool = MeshKit.begin()
		var light: Color = layers[3 - k % 2].col_light
		var dark: Color = layers[2 + k % 2].col_mid
		for j: int in 2 + k % 2:
			var axis := (
				Vector3(rng.randf_range(-0.6, 0.6), 1.0, rng.randf_range(-0.6, 0.6)).normalized()
			)
			MeshKit.add_prism(
				st,
				Vector3(rng.randf_range(-0.3, 0.3), -0.5, rng.randf_range(-0.3, 0.3)),
				axis,
				rng.randf_range(0.35, 0.55),
				rng.randf_range(0.6, 1.1),
				rng.randf_range(0.2, 0.5),
				5 + j % 2,
				dark,
				light,
				rng,
				0.25
			)
		meshes.append(MeshKit.commit(st))
	for i: int in DEBRIS:
		var mi := MeshInstance3D.new()
		mi.name = "Debris%d" % i
		mi.mesh = meshes[i % meshes.size()]
		mi.material_override = mat
		mi.top_level = true
		mi.visible = false
		add_child(mi)
		_debris.append(mi)
		_deb_vel.append(Vector3.ZERO)
		_deb_spin.append(Vector3.ZERO)
		_deb_life.append(-1.0)


func _build_audio() -> void:
	_hum = AudioStreamPlayer3D.new()
	_hum.name = "CoreHum"
	_hum.bus = &"Ambience"
	_hum.stream = HUM_SFX  # bucle activado en la importación
	_hum.unit_size = 22.0
	_hum.volume_db = -60.0
	add_child(_hum)
	_hum.position = _orb.position
	_peel_random = AudioStreamRandomizer.new()
	for s: AudioStream in PEEL_SFX:
		_peel_random.add_stream(-1, s)
	_peel_random.random_pitch = 1.15
	_peel_player = AudioStreamPlayer3D.new()
	_peel_player.bus = &"SFX"
	_peel_player.stream = _peel_random
	_peel_player.unit_size = 45.0
	_peel_player.max_polyphony = 3
	_peel_player.top_level = true
	add_child(_peel_player)
	var bounces := AudioStreamRandomizer.new()
	for s: AudioStream in BOUNCE_SFX:
		bounces.add_stream(-1, s)
	bounces.random_pitch = 1.05
	_bounce_player = AudioStreamPlayer3D.new()
	_bounce_player.bus = &"SFX"
	_bounce_player.stream = bounces
	_bounce_player.unit_size = 30.0
	_bounce_player.max_polyphony = 2
	_bounce_player.volume_db = -4.0
	_bounce_player.top_level = true
	add_child(_bounce_player)


func _apply_visibility() -> void:
	var shown: bool = state == State.CRACKING or state == State.EXPOSED
	_orb.visible = shown
	_halo.visible = shown
	_light.visible = shown
	_motes.emitting = state == State.EXPOSED
	_motes.visible = shown
	_body.collision_layer = (1 << 1) if shown else 0


func _show_exposed(instant: bool) -> void:
	state = State.EXPOSED
	if instant:
		_appear = 1.0
	_hum.play()
	_apply_visibility()
	set_process(true)


## Lanza en otro hilo el borrado de lo que queda fuera del Núcleo (y dónde quedan trozos).
func _start_clear() -> void:
	if _task >= 0 or _volume == null:
		return
	var v: CrystalVolume = _volume
	var src: PackedFloat32Array = v.sdf
	var out: Dictionary = {}
	_clear_result = out
	_task = WorkerThreadPool.add_task(
		func() -> void: CoreReveal.compute_clear(v, src, out), true, "core_reveal"
	)
	set_process(true)


## Hilo: la rejilla con sólo el Núcleo (`sdf`), los trozos tocados (`chunks`) y dónde queda masa
## (`sites`: centro y tamaño, de arriba abajo). Estática: sólo lee `v` (no cambia) y la copia.
## Con `keep` > 0 (depuración) deja además una costra irregular de ese radio alrededor.
static func compute_clear(
	v: CrystalVolume, src: PackedFloat32Array, out: Dictionary, keep: float = 0.0
) -> void:
	var sdf: PackedFloat32Array = src.duplicate()
	var touched: Dictionary[int, bool] = {}
	var bins: Dictionary[Vector3i, Vector4] = {}
	var c: Vector3 = v.core_center
	var r: float = v.core_radius
	var cell: float = v.cell
	for z: int in v.size.z:
		for y: int in v.size.y:
			var row: int = v.size.x * (y + v.size.y * z)
			for x: int in v.size.x:
				var i: int = row + x
				var old: float = sdf[i]
				var p: Vector3 = v.origin + Vector3(x, y, z) * cell
				var ds: float = p.distance_to(c) - r
				if keep > 0.0:
					var lump: float = sin(p.x * 0.23 + p.y * 0.17) * cos(p.z * 0.21 - p.y * 0.09)
					ds = p.distance_to(c) - keep - 4.0 * lump
				if ds <= old:
					continue
				var was_solid: bool = old < cell
				sdf[i] = ds
				if not was_solid:
					continue
				touched[_chunk_of(v, x, y, z)] = true
				if old < 0.0 and ds > cell and p.y > 0.4:
					var b := Vector3i(floori(p.x / BIN_M), floori(p.y / BIN_M), floori(p.z / BIN_M))
					var acc: Vector4 = bins.get(b, Vector4.ZERO)
					bins[b] = acc + Vector4(p.x, p.y, p.z, 1.0)
	# Cada celda con bastante cristal es un trozo que se desprende.
	var min_cells: float = pow(BIN_M / cell, 3.0) * 0.04
	var sites: Array[Vector4] = []
	for b: Vector3i in bins:
		var acc: Vector4 = bins[b]
		if acc.w < min_cells:
			continue
		var n: float = acc.w
		var size: float = clampf(pow(n * cell * cell * cell, 1.0 / 3.0), 1.5, BIN_M)
		sites.append(Vector4(acc.x / n, acc.y / n, acc.z / n, size))
	# Los más grandes (como mucho MAX_SITES: excavar cada uno cuesta), de arriba abajo.
	sites.sort_custom(func(a: Vector4, b: Vector4) -> bool: return a.w > b.w)
	if sites.size() > MAX_SITES:
		sites.resize(MAX_SITES)
	sites.sort_custom(func(a: Vector4, b: Vector4) -> bool: return a.y > b.y)
	out["sdf"] = sdf
	out["chunks"] = touched.keys()
	out["sites"] = sites


## Depuración ("IR AL NÚCLEO"): deja sólo una costra de `keep` m alrededor del Núcleo, como la
## que queda al final de verdad (en otro hilo), y luego llama a `then`.
func debug_trim(keep: float, then: Callable) -> void:
	if _task >= 0 or state != State.HIDDEN:
		then.call()
		return
	var v: CrystalVolume = _volume
	var src: PackedFloat32Array = v.sdf
	var out: Dictionary = {}
	var task: int = WorkerThreadPool.add_task(
		func() -> void: CoreReveal.compute_clear(v, src, out, keep), true, "core_trim"
	)
	while not WorkerThreadPool.is_task_completed(task):
		await get_tree().process_frame
	WorkerThreadPool.wait_for_task_completion(task)
	_clear_result = out
	GameState.progression.deepest_layer = maxi(GameState.progression.deepest_layer, 3)
	_apply_clear()
	then.call()


## Hilo: esencia que queda fuera del Núcleo y por encima del suelo (lo que aún se puede golpear),
## mirando una de cada 2 celdas por eje.
static func reachable_shell(v: CrystalVolume, src: PackedFloat32Array) -> float:
	var total: float = 0.0
	var vol: float = v.cell * v.cell * v.cell * 8.0
	var r2: float = v.core_radius * v.core_radius
	for z: int in range(0, v.size.z, 2):
		for y: int in range(0, v.size.y, 2):
			var row: int = v.size.x * (y + v.size.y * z)
			var wy: float = v.origin.y + float(y) * v.cell
			if wy < 0.4:
				continue
			for x: int in range(0, v.size.x, 2):
				var d: float = src[row + x]
				if d >= v.cell * 0.5:
					continue
				var p: Vector3 = v.origin + Vector3(x, y, z) * v.cell
				if p.distance_squared_to(v.core_center) < r2:
					continue
				var fill: float = clampf(0.5 - d / v.cell, 0.0, 1.0)
				total += fill * vol * v.layer_density[v.layer_at(p)]
	return total


## Igual que CrystalVolume._touch: el trozo de la celda (los vecinos de borde los rehace la
## malla de la celda de al lado, que también cambia).
static func _chunk_of(v: CrystalVolume, x: int, y: int, z: int) -> int:
	var cx: int = clampi(x / v.chunk, 0, v.chunks.x - 1)
	var cy: int = clampi(y / v.chunk, 0, v.chunks.y - 1)
	var cz: int = clampi(z / v.chunk, 0, v.chunks.z - 1)
	return cx + v.chunks.x * (cy + v.chunks.y * cz)


func _process(delta: float) -> void:
	_now += delta
	_poll_tasks()
	_update_scan(delta)
	if state == State.CRACKING:
		_update_crack(delta)
	_update_debris(delta)
	if state == State.EXPOSED or state == State.CRACKING:
		_update_orb(delta)
	elif _task < 0 and _scan_task < 0 and not _debris_busy():
		set_process(false)


func _poll_tasks() -> void:
	if _task >= 0 and WorkerThreadPool.is_task_completed(_task):
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		if state == State.CRACKING:
			_sites = PackedVector4Array(_clear_result.get("sites", []))
			_peel_t = 0.0
		else:
			_apply_clear()
	if _scan_task >= 0 and WorkerThreadPool.is_task_completed(_scan_task):
		WorkerThreadPool.wait_for_task_completion(_scan_task)
		_scan_task = -1
		var left: float = _scan_result[0]
		var bal: BalanceConfig = GameState.BALANCE
		if (
			state == State.HIDDEN
			and left >= 0.0
			and left < float(GameState.progression.total_essence) * bal.core_reveal_leftover
		):
			# Ya no queda nada a tiro fuera del Núcleo: la cuenta se pone en el 99 % (y avisa).
			var prog: Progression = GameState.progression
			GameState.hit_crystal(prog.essence - GameState.core_floor, core_position())


## Red de seguridad: desde el 95 % mira cada poco lo que queda de verdad a tiro.
func _update_scan(delta: float) -> void:
	if state != State.HIDDEN or _scan_task >= 0:
		return
	var bal: BalanceConfig = GameState.BALANCE
	if GameState.destroyed_ratio() < bal.core_reveal_scan_from:
		return
	_scan_timer -= delta
	if _scan_timer > 0.0:
		return
	_scan_timer = bal.core_reveal_scan_sec
	var v: CrystalVolume = _volume
	var src: PackedFloat32Array = v.sdf
	var res: Array[float] = _scan_result
	res[0] = -1.0
	_scan_task = WorkerThreadPool.add_task(
		func() -> void: res[0] = CoreReveal.reachable_shell(v, src), true, "core_scan"
	)


## Lo que queda se desprende en trozos, de arriba abajo; al final se borra todo de golpe y el
## Núcleo se enciende.
func _update_crack(delta: float) -> void:
	_crack_t += delta
	_trauma(delta * 0.6)
	if _peel_t < 0.0:
		return
	_peel_t += delta
	var n: int = _sites.size()
	var due: int = n if _peel_t >= PEEL_SEC else ceili(float(n) * _peel_t / PEEL_SEC)
	var allowed: int = (1 << CORE_LAYER) - 1
	while _site_next < mini(due, n):
		var s: Vector4 = _sites[_site_next]
		_site_next += 1
		var p_local: Vector3 = Vector3(s.x, s.y, s.z)
		var r: float = s.w * 0.75
		_crystal.apply_carve(_volume.carve_sphere(p_local, r, allowed), p_local, 0.0, 0.0)
		_throw_debris(_crystal.to_global(p_local), s.w)
		_appear = maxf(_appear, 0.15)
	if _site_next >= n and _peel_t >= minf(PEEL_SEC, 0.4 + 0.12 * float(n)):
		_apply_clear()
		_show_exposed(false)
		_crystal.flash(0.8)
		_trauma(0.5)
		Events.hint.emit(tr("EL NÚCLEO QUEDA EXPUESTO"), Color("#c79bff"))
		Events.core_revealed.emit()


## Deja en el volumen sólo el Núcleo (resultado del hilo) y rehace los trozos que cambian.
func _apply_clear() -> void:
	if not _clear_result.has("sdf"):
		return
	var cur: PackedFloat32Array = _volume.sdf
	var res: PackedFloat32Array = _clear_result["sdf"]
	if cur.size() == res.size():
		_volume.sdf = res
	# Las geodas abiertas que quedaban se van con el resto del cristal.
	for child: Node in _crystal.get_children():
		if child is Geode:
			child.queue_free()
	for gi: int in _volume.geodes.size():
		GameState.progression.geodes[gi] = 2
	var glints: GPUParticles3D = _crystal.get_node_or_null(^"Arcs/AmbientGlints") as GPUParticles3D
	if glints:
		glints.emitting = false
	var empty := PackedFloat32Array()
	empty.resize(_volume.layer_density.size())
	_crystal.apply_carve(
		{"essence": 0.0, "by_layer": empty, "chunks": _clear_result["chunks"]},
		_volume.core_center,
		0.0,
		0.0
	)
	_clear_result = {}


func _throw_debris(at: Vector3, size: float) -> void:
	var i: int = _debris_next
	_debris_next = (_debris_next + 1) % DEBRIS
	var d: MeshInstance3D = _debris[i]
	var out: Vector3 = at - core_position()
	out.y = 0.0
	out = out.normalized() if out.length() > 0.1 else Vector3.BACK
	# Nunca hacia la cara del mago: los que irían hacia la cámara salen de lado.
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam:
		var to_cam: Vector3 = cam.global_position - at
		to_cam.y = 0.0
		to_cam = to_cam.normalized()
		var toward: float = out.dot(to_cam)
		if toward > 0.2:
			out = (out - to_cam * toward * 1.5).normalized()
	d.global_position = at
	d.scale = Vector3.ONE * size * _rng.randf_range(0.45, 0.7)
	d.rotation = Vector3(_rng.randf() * TAU, _rng.randf() * TAU, _rng.randf() * TAU)
	d.visible = true
	_deb_vel[i] = out * _rng.randf_range(7.0, 15.0) + Vector3.UP * _rng.randf_range(5.0, 11.0)
	_deb_spin[i] = Vector3(
		_rng.randf_range(-3, 3), _rng.randf_range(-3, 3), _rng.randf_range(-3, 3)
	)
	_deb_life[i] = 0.0
	if _now - _last_peel_sfx > 0.12:
		_last_peel_sfx = _now
		_peel_player.global_position = at
		_peel_player.play()
	_crystal.add_crack(at, size * 0.8)


func _update_debris(delta: float) -> void:
	for i: int in DEBRIS:
		if _deb_life[i] < 0.0:
			continue
		var d: MeshInstance3D = _debris[i]
		_deb_life[i] += delta
		_deb_vel[i] += Vector3.DOWN * 16.0 * delta
		d.global_position += _deb_vel[i] * delta
		d.rotation += _deb_spin[i] * delta
		var ground: float = Valley.ground_height(d.global_position.x, d.global_position.z)
		if d.global_position.y < ground + 0.4 or _deb_life[i] > 4.0:
			# Al caer estalla en chispas y polvo de cristal.
			var s: GPUParticles3D = _sparks[_spark_next]
			_spark_next = (_spark_next + 1) % _sparks.size()
			s.global_position = d.global_position + Vector3.UP * 0.5
			s.restart()
			d.visible = false
			_deb_life[i] = -1.0


func _debris_busy() -> bool:
	for l: float in _deb_life:
		if l >= 0.0:
			return true
	return false


func _update_orb(delta: float) -> void:
	if state == State.EXPOSED:
		_appear = minf(1.0, _appear + delta / 1.6)
	_flash = maxf(0.0, _flash - delta * 3.0)
	# Latido lento (más deprisa al cargar la Gran Convergencia).
	var beat_hz: float = lerpf(0.55, 2.4, charge)
	_pulse = pow(0.5 + 0.5 * sin(_now * TAU * beat_hz), 3.0)
	_orb_mat.set_shader_parameter("now", _now)
	_orb_mat.set_shader_parameter("appear", _appear)
	_orb_mat.set_shader_parameter("pulse", _pulse)
	_orb_mat.set_shader_parameter("flash", _flash)
	_orb_mat.set_shader_parameter("charge", charge)
	var shake: float = charge * charge * 0.25
	_orb.position = (
		_volume.core_center
		+ Vector3(_rng.randf_range(-shake, shake), _rng.randf_range(-shake, shake), 0.0)
	)
	_orb.scale = Vector3.ONE * lerpf(0.85, 1.0, _appear) * (1.0 + 0.015 * _pulse + 0.06 * charge)
	_halo_mat.set_shader_parameter(
		"intensity", _appear * (0.55 + 0.35 * _pulse + 0.5 * charge + _flash * 0.6)
	)
	_halo.scale = Vector3.ONE * (1.0 + 0.4 * charge)
	_light.light_energy = _appear * (2.0 + 2.5 * _pulse + 6.0 * charge + _flash * 3.0)
	_hum.volume_db = lerpf(-30.0, -6.0, _appear) + charge * 4.0
	_hum.pitch_scale = 1.0 + charge * 0.25


func _trauma(amount: float) -> void:
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam is CameraRig:
		(cam as CameraRig).add_trauma(amount)
