class_name Familiar
extends Node3D
## Un familiar (GDD 4.3 y 7): un buhito mágico de malla low-poly con el shader toon (como los
## objetos del Santuario), ojos que brillan, alas que aletean en cuatro poses a 12 fps y una estela
## de chispitas con halo en la capa de magia HD. Lo maneja `FamiliarFlock`, que le da la jaula,
## la trituradora, los fragmentos y el cristal. Vuela en arcos (curvas de Bézier), sin navmesh.
## - Recolector: busca fragmentos sueltos, se lleva hasta `carry` colgando de las garras, vuela a
##   la tolva de la trituradora y los suelta uno a uno (como el Envío directo:
##   `CrystalCrusher.receive_direct`). Si se ha juntado bastante, tira de la palanca.
## - Hechicero: revolotea delante del cristal, del lado del mago; cada pocos segundos abre su
##   círculo mágico y le lanza una chispa de verdad (`SparkProjectile` -> `receive_hit`).

enum State { HIDDEN, PERCHED, FLYING, GRAB, DROP, LEVER, ORBIT, CHARGE }
## Qué hace al terminar un vuelo.
enum Goal { NONE, SHARD, HOPPER, LEVER, NEST, ORBIT }

const SPARK: ElementDef = preload("res://data/elements/spark.tres")
const MAX_CARRY: int = 6
const ANIM_FPS: float = 12.0
## Poses del aleteo (grados): arriba, medio, abajo, medio.
const FLAP_POSES: PackedFloat32Array = [58.0, 18.0, -38.0, 18.0]
const FOLDED_DEG: float = -55.0
## Alas plegadas: barridas hacia atrás, pegadas al cuerpo.
const FOLD_SWEEP_DEG: float = 72.0
const GLIDE_DEG: float = 9.0
const CRYSTAL_MASK: int = 1 << 1

var def: FamiliarDef
var flock: FamiliarFlock
## Índice dentro de su tipo: su percha y su sitio sobre la tolva.
var slot: int = 0
var state: State = State.HIDDEN
## Fragmentos que lleva en las garras.
var carried: Array[ShardType] = []
## Hechizos lanzados (para los tests y la demo).
var casts: int = 0

var _model: Node3D
var _wing_l: Node3D
var _wing_r: Node3D
var _carry_meshes: Array[MeshInstance3D] = []
var _halo: MeshInstance3D
var _halo_mat: StandardMaterial3D
var _trail: GPUParticles3D
var _burst: GPUParticles3D
var _t: float = 0.0
var _phase_offset: float = 0.0
var _from := Vector3.ZERO
var _ctrl := Vector3.ZERO
var _to := Vector3.ZERO
var _fly_t: float = 0.0
var _fly_dur: float = 1.0
var _goal: Goal = Goal.NONE
var _prev_pos := Vector3.ZERO
var _vel := Vector3.ZERO
var _timer: float = 0.0
var _target_shard: int = -1
var _target_pos := Vector3.ZERO
var _face_dir := Vector3.FORWARD
var _bank: float = 0.0
var _appear: float = 1.0
var _tug: float = 0.0
## Hechicero.
var _circles: MagicCircles
var _projectiles: Array[SparkProjectile] = []
var _anchor := Vector3.ZERO
var _out := Vector3.BACK
var _aim := Vector3.ZERO
var _anchor_t: float = 0.0
var _orbit_a: float = 0.0
var _cast_t: float = 0.0
var _rng := RandomNumberGenerator.new()


## Lo monta el rebaño (una vez, al crear el pool).
func setup(p_def: FamiliarDef, p_flock: FamiliarFlock, p_slot: int) -> void:
	def = p_def
	flock = p_flock
	slot = p_slot
	_rng.seed = 700 + slot * 31 + int(def.role) * 7
	_phase_offset = _rng.randf() * 4.0
	top_level = true
	_build_model()
	_build_fx()
	if def.role == FamiliarDef.Role.CASTER:
		_circles = MagicCircles.new()
		_circles.name = "MagicCircles"
		add_child(_circles)
		for i: int in 2:
			var p := SparkProjectile.new()
			p.name = "Spark%d" % i
			p.top_level = true
			p.arrived.connect(_on_projectile_arrived)
			add_child(p)
			_projectiles.append(p)
	hide_now()


## Fuera de juego (no comprado): invisible y sin procesar.
func hide_now() -> void:
	state = State.HIDDEN
	visible = false
	_trail.emitting = false
	if _circles:
		# Si se retira cargando, su círculo no se queda abierto.
		_circles.cancel()
	_drop_all_claims()
	carried.clear()
	_update_carry_meshes()
	set_process(false)


## Entra en juego. `at` es de donde sale; `announce` = recién comprado (sale del nido con salto).
func activate(at: Vector3, announce: bool) -> void:
	visible = true
	global_position = at
	_prev_pos = at
	_appear = 0.0 if announce else 1.0
	_model.scale = Vector3.ONE * (0.05 if announce else 1.0)
	_cast_t = def.cast_interval * (0.5 + 0.3 * float(slot))
	_anchor_t = 0.0
	set_process(true)
	if announce:
		_burst.restart()
	if def.role == FamiliarDef.Role.CASTER:
		_go_orbit()
	elif announce:
		# Revolotea un momento alrededor del nido antes de posarse.
		_fly(flock.nest.perch(slot) + Vector3.UP * 1.6, Goal.NEST)
	else:
		_perch_now()


func is_active() -> bool:
	return state != State.HIDDEN


## Cuántos fragmentos caben por viaje.
func capacity() -> int:
	return mini(MAX_CARRY, def.carry + GameState.progression.get_level(&"familiar_wings"))


func speed() -> float:
	return def.fly_speed * GameState.stat(&"familiar_speed", 1.0)


## Pantalla de carga: se enseña en `at` con la estela y el destello para compilarlos.
func warm_up(at: Vector3) -> void:
	visible = true
	global_position = at
	_trail.emitting = true
	_burst.restart()
	await get_tree().create_timer(0.4).timeout
	if state == State.HIDDEN:
		visible = false
		_trail.emitting = false


func _process(delta: float) -> void:
	_t += delta
	_timer -= delta
	_tug = maxf(0.0, _tug - delta * 3.0)
	if _appear < 1.0:
		_appear = minf(1.0, _appear + delta * 2.2)
		var k: float = _appear
		_model.scale = Vector3.ONE * maxf(0.05, (1.0 + sin(k * PI * 2.5) * (1.0 - k) * 0.4) * k)
	match state:
		State.FLYING:
			_update_flight(delta)
		State.PERCHED:
			_update_perched()
		State.GRAB:
			_update_grab(delta)
		State.DROP:
			_update_drop(delta)
		State.LEVER:
			_update_lever(delta)
		State.ORBIT:
			_update_orbit(delta)
		State.CHARGE:
			_update_charge(delta)
	_vel = (global_position - _prev_pos) / maxf(delta, 0.0001)
	_prev_pos = global_position
	_update_pose(delta)


# --- Vuelo en arco --------------------------------------------------------------------------


func _fly(to: Vector3, goal: Goal) -> void:
	_from = global_position
	_to = to
	var d: float = _from.distance_to(to)
	var lift: float = maxf(minf(def.cruise_height, d * 0.6), d * def.arc_per_meter)
	_ctrl = (_from + to) * 0.5 + Vector3.UP * lift
	_fly_dur = maxf(0.35, (d + lift * 0.6) / speed())
	_fly_t = 0.0
	_goal = goal
	state = State.FLYING
	_trail.emitting = true
	if d > 2.0:
		flock.voice(FamiliarFlock.Voice.FLAP, global_position)


func _update_flight(delta: float) -> void:
	_fly_t = minf(1.0, _fly_t + delta / _fly_dur)
	var k: float = smoothstep(0.0, 1.0, _fly_t)
	var a: Vector3 = _from.lerp(_ctrl, k)
	var b: Vector3 = _ctrl.lerp(_to, k)
	var pos: Vector3 = a.lerp(b, k)
	# Un balanceo de lado a lado que se apaga al llegar.
	var side: Vector3 = (_to - _from).cross(Vector3.UP)
	if side.length_squared() > 0.01:
		pos += side.normalized() * sin(_fly_t * PI) * sin(_t * 2.6 + _phase_offset) * 0.35
	global_position = pos
	if _fly_t >= 1.0:
		_arrive()


func _arrive() -> void:
	match _goal:
		Goal.SHARD:
			_arrive_shard()
		Goal.HOPPER:
			state = State.DROP
			_timer = 0.25
		Goal.LEVER:
			state = State.LEVER
			_timer = 2.5
		Goal.NEST:
			_perch_now()
		Goal.ORBIT:
			state = State.ORBIT
		_:
			_perch_now()


## Cara al sentido del vuelo (o hacia lo que mira), con alabeo en los giros y aleteo por poses.
func _update_pose(delta: float) -> void:
	var flat := Vector3(_vel.x, 0.0, _vel.z)
	var want: Vector3 = _face_dir
	if (state == State.FLYING or state == State.ORBIT) and flat.length() > 0.6:
		want = flat.normalized()
	var cur := Vector3(-sin(rotation.y), 0.0, -cos(rotation.y))
	var yaw_target: float = atan2(-want.x, -want.z)
	var turn: float = cur.signed_angle_to(want, Vector3.UP)
	rotation.y = lerp_angle(rotation.y, yaw_target, 1.0 - exp(-delta * 7.0))
	_bank = lerpf(_bank, clampf(turn * 0.8, -0.6, 0.6), 1.0 - exp(-delta * 5.0))
	rotation.z = _bank
	# En vuelo se inclina hacia delante (más cuanto más deprisa); quieto, erguido.
	var pitch: float = 0.0
	if state == State.FLYING or state == State.ORBIT:
		pitch = -0.55 * clampf(flat.length() / speed(), 0.0, 1.0) + clampf(_vel.y * 0.04, -0.3, 0.3)
	rotation.x = lerpf(rotation.x, pitch, 1.0 - exp(-delta * 6.0))
	# Aleteo en poses fijas a 12 fps (como un sprite animado a mano).
	var frame: int = int(floor((_t + _phase_offset) * ANIM_FPS))
	var deg: float = FLAP_POSES[frame % FLAP_POSES.size()]
	var sweep: float = 0.0
	match state:
		State.PERCHED:
			# Plegadas; de vez en cuando se esponja (dos poses).
			deg = FOLDED_DEG + (14.0 if int(frame / 6.0) % 9 == 0 else 0.0)
			sweep = FOLD_SWEEP_DEG
		State.FLYING:
			# En los viajes largos planea a mitad de camino.
			if _fly_dur > 2.2 and _fly_t > 0.3 and _fly_t < 0.72:
				deg = GLIDE_DEG + (4.0 if int(frame / 3.0) % 2 == 0 else 0.0)
	_wing_r.rotation = Vector3(0.0, -deg_to_rad(sweep), deg_to_rad(deg))
	_wing_l.rotation = Vector3(0.0, deg_to_rad(sweep), -deg_to_rad(deg))
	# Flota un poco con cada aletazo y al tirar de la palanca da un tirón hacia abajo.
	var bob: float = 0.0
	if state != State.PERCHED:
		bob = (0.05 if frame % 4 < 2 else -0.03) * def.size * 2.0
	else:
		bob = 0.02 if int(frame / 8.0) % 2 == 0 else 0.0
	_model.position.y = bob - _tug * 0.4
	# El halo es tenue (más en vuelo, casi nada en la percha): si no, tiñe el cuerpo y el búho
	# se lee como una mancha azul.
	var glow: float = 0.06 if state == State.PERCHED else 0.11
	if state == State.CHARGE:
		glow = 0.25 + 0.35 * clampf(1.0 - _timer / def.cast_charge_sec, 0.0, 1.0)
	var pulse: float = (0.85 + 0.15 * sin(_t * 5.0 + _phase_offset)) * glow
	_halo_mat.albedo_color = Color(
		def.glow_color.r * pulse, def.glow_color.g * pulse, def.glow_color.b * pulse, 0.0
	)


# --- Recolector -----------------------------------------------------------------------------


func _perch_now() -> void:
	state = State.PERCHED
	_trail.emitting = false
	global_position = flock.nest.perch(slot)
	_face_dir = flock.nest.perch_out(slot)
	_timer = def.rest_sec + float(slot) * 0.35
	if def.role == FamiliarDef.Role.CASTER:
		_go_orbit()


func _update_perched() -> void:
	if _timer > 0.0:
		return
	_timer = def.rest_sec
	if not _seek(global_position, def.search_radius):
		# Nada más que recoger: tritura lo que haya en la tolva, aunque sea poco (si no, unos
		# pocos cristales se quedarían ahí para siempre sin dar maná).
		_maybe_lever(1)


## Busca el fragmento suelto más cercano a `center` y vuela hacia él. False si no hay.
func _seek(center: Vector3, radius: float) -> bool:
	if flock.shards == null or carried.size() >= capacity():
		return false
	var idx: int = flock.shards.loose_near(center, radius, flock.claims, 1.0)
	if idx < 0:
		return false
	flock.claims[flock.claim_index(self)] = idx
	_target_shard = idx
	_target_pos = flock.shards.position_of(idx)
	_fly(_target_pos + Vector3.UP * 0.7, Goal.SHARD)
	return true


func _arrive_shard() -> void:
	var shards: ShardPool = flock.shards
	if (
		_target_shard < 0
		or not shards.is_loose(_target_shard)
		or shards.position_of(_target_shard).distance_to(_target_pos) > 1.2
	):
		# Se lo han llevado (o rodó): a por otro.
		_drop_all_claims()
		_next_after_shard()
		return
	state = State.GRAB
	_timer = def.grab_sec


## Baja sobre el fragmento, lo atrapa con las garras y sigue.
func _update_grab(delta: float) -> void:
	var low: Vector3 = _target_pos + Vector3.UP * 0.42
	global_position = global_position.lerp(low, 1.0 - exp(-delta * 10.0))
	if _timer > 0.0:
		return
	# El pool recicla fragmentos: si el índice ya es otro (lejos de aquí), no se lo lleva.
	var type: ShardType = null
	if flock.shards.position_of(_target_shard).distance_to(_target_pos) <= 1.2:
		type = flock.shards.take(_target_shard)
	_drop_all_claims()
	if type != null:
		carried.append(type)
		_update_carry_meshes()
		_burst.restart()
		flock.voice(FamiliarFlock.Voice.GRAB, global_position)
		if carried.size() == 1:
			flock.voice(FamiliarFlock.Voice.CHIRP, global_position)
	_next_after_shard()


func _next_after_shard() -> void:
	if carried.size() < capacity() and _seek(global_position, def.chain_radius):
		return
	if not carried.is_empty() and flock.crusher:
		_fly(flock.hopper_spot(slot), Goal.HOPPER)
	elif not _seek(global_position, def.search_radius):
		_fly(flock.nest.perch(slot), Goal.NEST)


## Sobre la tolva: suelta los cristales uno a uno (vuelan en arco y tintinean al caer).
func _update_drop(delta: float) -> void:
	var over: Vector3 = flock.hopper_spot(slot)
	global_position = global_position.lerp(over, 1.0 - exp(-delta * 6.0))
	_face_dir = (flock.crusher.hopper_mouth() - global_position) * Vector3(1, 0, 1)
	if _face_dir.length_squared() < 0.001:
		_face_dir = Vector3.FORWARD
	_face_dir = _face_dir.normalized()
	if _timer > 0.0:
		return
	if carried.is_empty():
		flock.voice(FamiliarFlock.Voice.CHIRP, global_position)
		if not _maybe_lever():
			_next_after_shard()
		return
	_timer = def.drop_gap_sec
	var from: Vector3 = _carry_meshes[carried.size() - 1].global_position
	var type: ShardType = carried.pop_back()
	_update_carry_meshes()
	flock.crusher.receive_direct(type, from)
	flock.dropped += 1


## Si en la tolva hay bastante (`at_least`; por defecto `def.lever_at`) y nadie la está
## usando, va a tirar de la palanca.
func _maybe_lever(at_least: int = -1) -> bool:
	if not flock.wants_lever(self, def.lever_at if at_least < 0 else at_least):
		return false
	_fly(flock.crusher.lever_tip() + Vector3(0.0, 0.25, 0.0), Goal.LEVER)
	return true


func _update_lever(delta: float) -> void:
	var tip: Vector3 = flock.crusher.lever_tip() + Vector3(0.0, 0.25, 0.0)
	global_position = global_position.lerp(tip, 1.0 - exp(-delta * 10.0))
	if _tug > 0.0:
		# Ya tiró: espera a que acabe el tirón.
		if _tug < 0.35:
			_leave_lever()
		return
	if flock.crusher.pull_lever():
		_tug = 1.0
		flock.voice(FamiliarFlock.Voice.CHIRP, global_position)
		_burst.restart()
		flock.pulls += 1
		return
	if flock.crusher.is_busy() or _timer <= 0.0 or flock.crusher.hopper_count() == 0:
		_leave_lever()


func _leave_lever() -> void:
	flock.release_lever(self)
	if not _seek(global_position, def.search_radius):
		_fly(flock.nest.perch(slot), Goal.NEST)


func _drop_all_claims() -> void:
	_target_shard = -1
	if flock:
		var i: int = flock.claim_index(self)
		if i >= 0:
			flock.claims[i] = -1
		flock.release_lever(self)


## Los fragmentos que lleva cuelgan de las garras.
func _update_carry_meshes() -> void:
	for k: int in MAX_CARRY:
		var mi: MeshInstance3D = _carry_meshes[k]
		if k < carried.size():
			mi.mesh = flock.shard_mesh(carried[k])
			mi.visible = true
		else:
			mi.visible = false


# --- Hechicero ------------------------------------------------------------------------------


## Elige su sitio delante del cristal, del lado del mago (cada hechicero algo girado).
func _pick_anchor() -> bool:
	var crystal: MotherCrystal = flock.crystal
	if crystal == null:
		return false
	var toward: Vector3 = flock.player_position() - crystal.global_position
	toward.y = 0.0
	if toward.length_squared() < 0.01:
		toward = Vector3.BACK
	toward = toward.normalized()
	var from: Vector3 = (
		crystal.global_position
		+ toward * (WorldLayout.CRYSTAL_FOOTPRINT + 40.0)
		+ Vector3.UP * (def.orbit_height + float(slot) * 2.5)
	)
	var surf: Dictionary = crystal.surface_toward(from)
	if surf.is_empty():
		return false
	_aim = surf["position"]
	_out = toward
	# Entre el cristal y el mago, unos metros por delante de él (para que se le vea lanzar).
	var player: Vector3 = flock.player_position()
	var gap: float = Vector2(player.x - _aim.x, player.z - _aim.z).length()
	_anchor = _aim + _out * clampf(gap - 8.0, 3.0, def.orbit_out)
	# Cada hechicero a un lado de la mira (el primero a la izquierda del mago, el otro a la derecha).
	_anchor += _out.cross(Vector3.UP).normalized() * def.orbit_side * (1.0 if slot == 0 else -1.0)
	return true


func _go_orbit() -> void:
	_anchor_t = 6.0 + _rng.randf() * 3.0
	if not _pick_anchor():
		# Sin cristal a la vista: espera sobre la jaula y lo vuelve a intentar.
		_anchor = flock.nest.top() + Vector3.UP * 3.0
		_aim = _anchor + Vector3.FORWARD
		_anchor_t = 2.0
		_cast_t = def.cast_interval
		state = State.ORBIT
		return
	_orbit_a = _rng.randf() * TAU
	_fly(_orbit_point(), Goal.ORBIT)


func _orbit_point() -> Vector3:
	var right: Vector3 = _out.cross(Vector3.UP).normalized()
	return (
		_anchor
		+ right * cos(_orbit_a) * def.orbit_radius
		+ _out * sin(_orbit_a) * def.orbit_radius * 0.5
		+ Vector3.UP * sin(_orbit_a * 2.0) * 0.5
	)


func _update_orbit(delta: float) -> void:
	_orbit_a += delta * 0.9
	global_position = global_position.lerp(_orbit_point(), 1.0 - exp(-delta * 4.0))
	_trail.emitting = true
	_anchor_t -= delta
	_cast_t -= delta
	if _anchor_t <= 0.0:
		# El mago se ha movido: busca otro sitio si queda lejos.
		var old: Vector3 = _anchor
		if _pick_anchor() and old.distance_to(_anchor) > 12.0:
			_go_orbit()
			return
		_anchor_t = 6.0
	if _cast_t <= 0.0:
		state = State.CHARGE
		_timer = def.cast_charge_sec
		flock.voice(FamiliarFlock.Voice.CHIRP, global_position)


## Se para, mira al cristal y abre su círculo mágico; al llenarse, lanza.
func _update_charge(delta: float) -> void:
	_orbit_a += delta * 0.2
	global_position = global_position.lerp(_orbit_point(), 1.0 - exp(-delta * 2.0))
	var to_aim: Vector3 = _aim - global_position
	_face_dir = Vector3(to_aim.x, 0.0, to_aim.z).normalized()
	var k: float = clampf(1.0 - _timer / def.cast_charge_sec, 0.0, 1.0)
	_circles.charging(k, 1, _beak(), _aim, def.trail_edge * 1.2, def.trail_core)
	if _timer > 0.0:
		return
	_circles.release()
	_cast()
	_cast_t = def.cast_interval * _rng.randf_range(0.85, 1.15)
	state = State.ORBIT


func _beak() -> Vector3:
	return global_position + global_basis * (Vector3(0.0, 0.2, -0.45) * def.size)


func _cast() -> void:
	var origin: Vector3 = _beak()
	var dir: Vector3 = (_aim - origin).normalized()
	var q := PhysicsRayQueryParameters3D.create(origin, _aim + dir * 4.0, CRYSTAL_MASK)
	var r: Dictionary = get_world_3d().direct_space_state.intersect_ray(q)
	if r.is_empty():
		_anchor_t = 0.0
		return
	var projectile: SparkProjectile = null
	for p: SparkProjectile in _projectiles:
		if not p.active:
			projectile = p
			break
	if projectile == null:
		return
	var tiers: Array[SpellTier] = SPARK.tiers
	var idx: int = clampi(
		roundi(GameState.stat(SPARK.power_stat, 0.0)) + def.tier_offset, 0, tiers.size() - 1
	)
	var tier: SpellTier = tiers[idx]
	var hit := SpellHit.new()
	hit.tier = tier
	hit.familiar = true
	hit.by_player = false
	hit.minor = true
	hit.damage = maxi(1, roundi(float(tier.damage) * def.damage_mult))
	hit.element = SPARK.id
	hit.element_def = SPARK
	hit.position = r["position"]
	hit.normal = r["normal"]
	hit.direction = dir
	projectile.orb_charge = 0.8
	projectile.launch(origin, hit.position, hit, r["collider"])
	casts += 1
	_burst.restart()
	flock.voice(FamiliarFlock.Voice.CAST, origin)


func _on_projectile_arrived(projectile: SparkProjectile) -> void:
	var collider: Object = projectile.target_collider
	if collider is Node and (collider as Node).has_meta(&"mother_crystal"):
		var crystal: MotherCrystal = (collider as Node).get_meta(&"mother_crystal")
		crystal.receive_hit(projectile.hit)


# --- Malla y efectos ------------------------------------------------------------------------


## Buhito low-poly: cuerpo y cabeza octogonales, disco facial, orejas de pluma, pico, alas en
## dos pivotes (hombros) y cola. Colores por vértice para el shader toon.
func _build_model() -> void:
	var s: float = def.size
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	_model = Node3D.new()
	_model.name = "Model"
	add_child(_model)
	var st: SurfaceTool = MeshKit.begin()
	var body: Color = def.body_color
	var dark: Color = def.body_color.darkened(0.25)
	# Cuerpo de huevo (cabeza y cuerpo en uno, como un buhito), barriga clara delante.
	_add_egg(st, s, body, dark)
	# Disco facial, orejas y pico.
	MeshKit.add_prism(
		st,
		Vector3(0, 0.24, -0.24) * s,
		Vector3.FORWARD,
		0.2 * s,
		0.07 * s,
		0.0,
		8,
		def.belly_color,
		def.belly_color,
		rng
	)
	for side: float in [-1.0, 1.0]:
		MeshKit.add_prism(
			st,
			Vector3(0.17 * side, 0.34, 0.0) * s,
			Vector3(0.45 * side, 1.0, 0.1),
			0.075 * s,
			0.001,
			0.2 * s,
			4,
			def.wing_color,
			def.wing_color,
			rng
		)
		# Pupila oscura delante del ojo brillante.
		MeshKit.add_box(
			st,
			Vector3(0.1 * side, 0.25, -0.338) * s,
			Vector3(0.05, 0.06, 0.02) * s,
			Color("#1b1838")
		)
		# Patitas.
		MeshKit.add_box(
			st,
			Vector3(0.08 * side, -0.46, -0.04) * s,
			Vector3(0.05, 0.08, 0.08) * s,
			def.beak_color
		)
	MeshKit.add_prism(
		st,
		Vector3(0, 0.19, -0.3) * s,
		Vector3(0, -0.45, -1.0),
		0.045 * s,
		0.001,
		0.1 * s,
		4,
		def.beak_color,
		def.beak_color,
		rng
	)
	# Cola de plumas.
	MeshKit.add_prism(
		st,
		Vector3(0, -0.2, 0.22) * s,
		Vector3(0, -0.5, 1.0),
		0.11 * s,
		0.001,
		0.22 * s,
		3,
		def.wing_color,
		def.wing_tip_color,
		rng
	)
	var mi := MeshInstance3D.new()
	mi.name = "Body"
	mi.mesh = MeshKit.commit(st)
	mi.material_override = flock.toon
	_model.add_child(mi)
	# Ojos que brillan (sin luz: HDR para que el resplandor del valle los recoja).
	var est: SurfaceTool = MeshKit.begin()
	for side: float in [-1.0, 1.0]:
		MeshKit.add_box(
			est, Vector3(0.095 * side, 0.26, -0.312) * s, Vector3(0.12, 0.12, 0.03) * s, Color.WHITE
		)
	var eyes := MeshInstance3D.new()
	eyes.name = "Eyes"
	eyes.mesh = MeshKit.commit(est)
	var em := StandardMaterial3D.new()
	em.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# Del color del halo pero sin quemarse a blanco.
	em.albedo_color = Color(def.glow_color.r, def.glow_color.g, def.glow_color.b) * 0.7
	eyes.material_override = em
	eyes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_model.add_child(eyes)
	_wing_r = _make_wing(1.0)
	_wing_l = _make_wing(-1.0)
	# Fragmentos colgando de las garras.
	for k: int in MAX_CARRY:
		var c := MeshInstance3D.new()
		c.name = "Carry%d" % k
		c.material_override = flock.shard_material
		c.scale = Vector3.ONE * 0.5
		c.position = (
			Vector3(float(k % 3 - 1) * 0.11, -0.62 - float(int(k / 3.0)) * 0.12, -0.02) * (s / 0.55)
		)
		c.rotation = Vector3(0.3 * float(k), 0.9 * float(k), 0.2)
		c.visible = false
		_model.add_child(c)
		_carry_meshes.append(c)


## Huevo low-poly de 8 lados y 7 anillos: más ancho abajo; las caras de delante y abajo son la
## barriga (clara) y las de arriba, la cabeza (algo más oscura).
func _add_egg(st: SurfaceTool, s: float, body: Color, dark: Color) -> void:
	var rings: int = 7
	var sides: int = 8
	var half: float = 0.44
	var pts: Array[PackedVector3Array] = []
	for r: int in rings + 1:
		var y: float = lerpf(-half, half, float(r) / float(rings))
		var k: float = y / half
		var rad: float = 0.34 * sqrt(maxf(0.0, 1.0 - k * k)) * (1.0 - 0.08 * k)
		var ring := PackedVector3Array()
		for i: int in sides:
			var a: float = TAU * (float(i) + 0.5) / float(sides)
			ring.append(Vector3(sin(a) * rad, y, -cos(a) * rad) * s)
		pts.append(ring)
	var center := Vector3.ZERO
	var head: Color = body.darkened(0.1)
	for r: int in rings:
		for i: int in sides:
			var j: int = (i + 1) % sides
			var a: Vector3 = pts[r][i]
			var b: Vector3 = pts[r][j]
			var c: Vector3 = pts[r + 1][j]
			var d: Vector3 = pts[r + 1][i]
			var mid: Vector3 = (a + b + c + d) * 0.25
			var n: Vector3 = mid.normalized()
			var col: Color = body
			if r == 0:
				col = dark
			elif n.z < -0.55 and mid.y < 0.08 * s:
				col = def.belly_color
			elif r >= rings - 2:
				col = head
			# En los polos el anillo es un punto: add_tri descarta el triángulo vacío.
			MeshKit.add_quad(st, a, b, c, d, col, center)


## Ala (lado +1 derecha, -1 izquierda): plana con grosor, plumas claras en la punta.
func _make_wing(side: float) -> Node3D:
	var s: float = def.size
	var pivot := Node3D.new()
	pivot.name = "WingR" if side > 0.0 else "WingL"
	pivot.position = Vector3(0.26 * side, 0.02, 0.02) * s
	_model.add_child(pivot)
	var pts: Array[Vector3] = [
		Vector3(0.0, 0.05, -0.12),
		Vector3(0.42, 0.06, -0.1),
		Vector3(0.66, 0.0, 0.1),
		Vector3(0.34, 0.02, 0.2),
		Vector3(0.0, -0.02, 0.17),
	]
	for i: int in pts.size():
		pts[i] = Vector3(pts[i].x * side, pts[i].y, pts[i].z) * s
	var th := Vector3(0.0, 0.025 * s, 0.0)
	var st: SurfaceTool = MeshKit.begin()
	var center: Vector3 = (pts[0] + pts[2]) * 0.5
	for i: int in range(1, pts.size() - 1):
		var a: Vector3 = pts[0]
		var b: Vector3 = pts[i]
		var c: Vector3 = pts[i + 1]
		MeshKit.add_tri(st, a + th, b + th, c + th, def.wing_color, center - Vector3.UP)
		MeshKit.add_tri(st, a - th, b - th, c - th, def.wing_tip_color, center + Vector3.UP)
	# Bordes (para que no se vea hueca de canto).
	for i: int in pts.size():
		var p0: Vector3 = pts[i]
		var p1: Vector3 = pts[(i + 1) % pts.size()]
		MeshKit.add_quad(
			st, p0 + th, p1 + th, p1 - th, p0 - th, def.wing_color.darkened(0.2), center
		)
	# Tres plumas largas al final del ala.
	for k: int in 3:
		var root: Vector3 = pts[2].lerp(pts[3], float(k) / 3.0)
		var tip: Vector3 = root + Vector3(0.06 * side, -0.01, 0.13) * s
		var root2: Vector3 = pts[2].lerp(pts[3], (float(k) + 0.8) / 3.0)
		MeshKit.add_tri(st, root, tip, root2, def.wing_tip_color, root + Vector3.DOWN * s)
		MeshKit.add_tri(st, root, tip, root2, def.wing_tip_color, root + Vector3.UP * s)
	var mi := MeshInstance3D.new()
	mi.name = "Wing"
	mi.mesh = MeshKit.commit(st)
	mi.material_override = flock.toon
	pivot.add_child(mi)
	return pivot


## Halo suave y estela de chispitas (capa de magia HD; las tapa el cristal).
func _build_fx() -> void:
	_halo = MeshInstance3D.new()
	_halo.name = "Halo"
	var q := QuadMesh.new()
	q.size = Vector2.ONE * def.size * 1.7
	_halo.mesh = q
	_halo_mat = StandardMaterial3D.new()
	_halo_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_halo_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_halo_mat.blend_mode = BaseMaterial3D.BLEND_MODE_PREMULT_ALPHA
	_halo_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_halo_mat.albedo_texture = HdFx.soft_dot()
	_halo_mat.albedo_color = Color(def.glow_color, 0.0)
	_halo_mat.disable_fog = true
	_halo_mat.render_priority = 5
	_halo.material_override = _halo_mat
	_halo.layers = MagicLayer.MAGIC_LAYER
	_halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_halo.position = Vector3.UP * 0.05 * def.size
	add_child(_halo)
	_trail = HdFx.embers(36, 0.07, PackedColorArray([def.trail_core, def.trail_edge]))
	_trail.name = "Trail"
	_trail.lifetime = 0.9
	_trail.emitting = false
	var pm: ParticleProcessMaterial = _trail.process_material
	pm.gravity = Vector3(0, -0.6, 0)
	pm.emission_sphere_radius = 0.18 * def.size
	pm.initial_velocity_min = 0.05
	pm.initial_velocity_max = 0.3
	var trail_mat: StandardMaterial3D = (_trail.draw_pass_1 as QuadMesh).material
	trail_mat.albedo_texture = HdFx.soft_star()
	trail_mat.no_depth_test = false
	_trail.position = Vector3(0.0, -0.1, 0.2) * def.size
	add_child(_trail)
	_burst = HdFx.sparks(14, 3.0, 0.02, PackedColorArray([def.trail_core * 1.2, def.trail_edge]))
	_burst.name = "Burst"
	(_burst.draw_pass_1 as RibbonTrailMesh).material.set(&"no_depth_test", false)
	add_child(_burst)
