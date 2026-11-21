class_name CritterGore
extends Node3D
## El ¡PUM! de un bicho (gore de dibujos animados, nada realista): trozos de baba que botan con
## brillo húmedo, manchas pegajosas en el suelo que se secan al rato, los dos ojazos que salen
## volando, botan, ruedan y se quedan mirando al mago unos segundos, un diente o un huesito, gotas
## de su color y su almita con aureola y ojos en X que sube flotando.
## Sin "sangre de caricatura" (Accesibilidad), confeti, estrellas y una nube.
## Todo en pools con física propia barata (rebote contra `Valley.ground_height`): nada se
## instancia en caliente y los topes los pone `CritterConfig`.

enum Kind { CHUNK, CONFETTI, ICE, TOOTH, BONE }

const GRAVITY: float = 15.0
const CONFETTI_COLORS: Array[Color] = [
	Color("#ff5fa2"), Color("#ffd23f"), Color("#4fd6ff"), Color("#7ee05a"), Color("#c79bff")
]
const C_CHAR := Color("#2b1d1a")
const C_ICE := Color("#bfeeff")
const C_PINK := Color("#ff7ad9")
const SP_TINT: StringName = &"tint"
const GHOSTS: int = 5
const SPRAYS: int = 4
const PUFFS: int = 4
const STARS: int = 3

## Piezas en marcha (para los tests).
var active_chunks: int = 0
var active_splats: int = 0
var active_eyes: int = 0
## Veces que se ha reciclado una pieza aún viva (pool lleno).
var recycled: int = 0
## Último reventón: con sangre (true) o confeti (false).
var last_gore: bool = true

var _config: CritterConfig
var _voices: CritterVoices
var _rng := RandomNumberGenerator.new()
var _time: float = 0.0
var _goo_mat: ShaderMaterial
var _paper_mat: ShaderMaterial
var _bits_mat: ShaderMaterial
var _blob_meshes: Array[ArrayMesh] = []
var _splat_meshes: Array[ArrayMesh] = []
var _ice_mesh: ArrayMesh
var _tooth_mesh: ArrayMesh
var _bone_mesh: ArrayMesh
var _paper_mesh: BoxMesh
# Trozos (baba, hielo, confeti, dientes, huesos).
var _pieces: Array[MeshInstance3D] = []
var _p_pos := PackedVector3Array()
var _p_vel := PackedVector3Array()
var _p_axis := PackedVector3Array()
var _p_angle := PackedFloat32Array()
var _p_spin := PackedFloat32Array()
var _p_size := PackedFloat32Array()
var _p_life := PackedFloat32Array()
var _p_squash := PackedFloat32Array()
var _p_kind := PackedInt32Array()
var _p_rest := PackedByteArray()
var _p_next: int = 0
# Manchas del suelo.
var _splats: Array[MeshInstance3D] = []
var _s_life := PackedFloat32Array()
var _s_total := PackedFloat32Array()
var _s_size := PackedFloat32Array()
var _s_next: int = 0
# Ojos que ruedan.
var _eyes: Array[Node3D] = []
var _e_pupil: Array[MeshInstance3D] = []
var _e_glint: Array[MeshInstance3D] = []
var _e_sclera: Array[MeshInstance3D] = []
var _e_pos := PackedVector3Array()
var _e_vel := PackedVector3Array()
var _e_spin := PackedVector3Array()
var _e_r := PackedFloat32Array()
var _e_life := PackedFloat32Array()
var _e_stare := PackedFloat32Array()
var _e_pp := PackedVector2Array()
var _e_pv := PackedVector2Array()
var _e_next: int = 0
# Almitas con aureola.
var _ghosts: Array[Node3D] = []
var _g_body: Array[MeshInstance3D] = []
var _g_mat: Array[StandardMaterial3D] = []
var _g_x: Array[MeshInstance3D] = []
var _g_halo: Array[MeshInstance3D] = []
var _g_life := PackedFloat32Array()
var _g_from := PackedVector3Array()
var _g_next: int = 0
# Partículas (gotas en el mundo pixel; estrellas, nubes y brasas en la capa de magia).
var _sprays: Array[GPUParticles3D] = []
var _spray_next: int = 0
var _puffs: Array[GPUParticles3D] = []
var _puff_next: int = 0
var _stars: Array[GPUParticles3D] = []
var _star_next: int = 0
var _embers: GPUParticles3D


func setup(config: CritterConfig, voices: CritterVoices, herd: CritterHerd) -> void:
	_config = config
	_voices = voices
	_rng.seed = 777
	top_level = true
	_goo_mat = _toon(0.7, 0.3, false)
	_paper_mat = _toon(0.0, 0.45, false)
	_bits_mat = herd.body_material
	for k: int in 3:
		_blob_meshes.append(CritterGoreMeshes.blob_mesh(k))
		_splat_meshes.append(CritterGoreMeshes.splat_mesh(k))
	_ice_mesh = CritterGoreMeshes.ice_shard_mesh()
	_tooth_mesh = CritterGoreMeshes.tooth()
	_bone_mesh = CritterGoreMeshes.bone()
	_paper_mesh = BoxMesh.new()
	_paper_mesh.size = Vector3(0.13, 0.012, 0.09)
	_build_pieces(config.max_chunks + config.max_bits)
	_build_splats(config.max_splats)
	_build_eyes(config.max_eyes, herd)
	_build_ghosts(herd)
	_build_particles()
	set_process(false)


## Revienta `c` (ya acabada su anticipación). `gore`: sangre de caricatura (si no, confeti).
func burst(c: Critter, gore: bool) -> void:
	last_gore = gore
	var def: CritterDef = c.def
	var at: Vector3 = c.center()
	var push: Vector3 = c.push
	var s: float = def.size
	var goo: Color = def.goo_color
	match c.flavor:
		Critter.Flavor.FIRE, Critter.Flavor.BOLT:
			goo = goo.lerp(C_CHAR, 0.55)
		Critter.Flavor.FROST:
			goo = goo.lerp(C_ICE, 0.55)
		Critter.Flavor.ARCANE:
			goo = goo.lerp(C_PINK, 0.35)
	if gore:
		var kind: Kind = Kind.ICE if c.flavor == Critter.Flavor.FROST else Kind.CHUNK
		var n: int = def.chunks
		if c.flavor == Critter.Flavor.EARTH:
			@warning_ignore("integer_division")
			n = maxi(3, n / 2)
		for i: int in n:
			_spawn_piece(kind, at, push, goo, _rng.randf_range(0.16, 0.32) * s, 1.0)
		if def.drops_tooth or c.flavor == Critter.Flavor.BOLT:
			_spawn_piece(Kind.TOOTH, at, push, Color(1, 1, 1, 0), 0.9 * s, 1.1)
		if def.drops_bone or c.flavor == Critter.Flavor.BOLT:
			_spawn_piece(Kind.BONE, at, push, Color(1, 1, 1, 0), 0.9 * s, 1.0)
		if def.drops_tooth and c.flavor == Critter.Flavor.BOLT:
			_spawn_piece(Kind.BONE, at, push, Color(1, 1, 1, 0), 0.8 * s, 1.0)
		var ground: Vector3 = _on_ground(at)
		if c.flavor == Critter.Flavor.EARTH:
			# La tortita se queda en el suelo.
			_spawn_splat(ground, goo.darkened(0.08), c.rig.hit_radius * 3.6)
		else:
			_spawn_splat(ground, goo.darkened(0.08), c.rig.hit_radius * 3.0)
			for k: int in 2:
				var off := Vector3(_rng.randf_range(-1, 1), 0.0, _rng.randf_range(-1, 1)) * s
				_spawn_splat(_on_ground(at + off + push * 0.6), goo.darkened(0.05), 0.7 * s)
		for i: int in c.eye_count():
			# Algo más grandes que en la cara (siguen saltones del susto): se leen rodando.
			_spawn_eye(c.eye_position(i), c.rig.eye_r[i] * 1.3, push, c.def, i)
		_spray(at, goo, s)
		if c.flavor == Critter.Flavor.FIRE:
			_puff(at, Color(0.22, 0.18, 0.17), 1.6 * s)
			_embers.global_position = at
			_embers.restart()
		if c.flavor == Critter.Flavor.FROST:
			_voices.play(CritterVoices.Kind.CLINK, at, 0.0, 0.9)
	else:
		for i: int in 16:
			var col: Color = CONFETTI_COLORS[i % CONFETTI_COLORS.size()]
			_spawn_piece(Kind.CONFETTI, at, push * 0.3, col, 1.0, 0.75)
		_puff(at, Color(1.0, 1.0, 1.0), 1.5 * s)
		_star_burst(at)
	if c.flavor == Critter.Flavor.ARCANE:
		_star_burst(at)
	_spawn_ghost(c)
	set_process(true)


## Un eco del Arcano: otro reventón pequeño y rosa en el mismo sitio (sin ojos ni almita).
func echo_burst(at: Vector3, def: CritterDef, gore: bool) -> void:
	if gore:
		var goo: Color = def.goo_color.lerp(C_PINK, 0.6)
		for i: int in 4:
			_spawn_piece(
				Kind.CHUNK, at, Vector3.ZERO, goo, _rng.randf_range(0.07, 0.14) * def.size, 0.8
			)
		_spray(at, goo, def.size * 0.7)
	else:
		for i: int in 8:
			_spawn_piece(
				Kind.CONFETTI, at, Vector3.ZERO, C_PINK if i % 2 else Color("#c79bff"), 1.0, 0.6
			)
	_star_burst(at)
	set_process(true)


## Nube de polvo (al salir del suelo, al estornudar).
func dust(at: Vector3, size: float) -> void:
	_puff(at, Color("#d9c7a0"), size)


## Pantalla de carga: un reventón de cada cosa delante de la cámara para compilar los shaders.
func warm_up(at: Vector3, sample: Critter) -> void:
	burst(sample, true)
	burst(sample, false)
	for p: GPUParticles3D in _sprays + _puffs + _stars:
		p.global_position = at
		p.restart()
	await get_tree().create_timer(0.5).timeout
	clear()


## Lo quita todo (tests, depuración).
func clear() -> void:
	for i: int in _pieces.size():
		_p_life[i] = -1.0
		_pieces[i].visible = false
	for i: int in _splats.size():
		_s_life[i] = -1.0
		_splats[i].visible = false
	for i: int in _eyes.size():
		_e_life[i] = -1.0
		_eyes[i].visible = false
	for i: int in _ghosts.size():
		_g_life[i] = -1.0
		_ghosts[i].visible = false
	active_chunks = 0
	active_splats = 0
	active_eyes = 0


func _process(delta: float) -> void:
	_time += delta
	var cam: Camera3D = get_viewport().get_camera_3d()
	var cam_pos: Vector3 = cam.global_position if cam else Vector3.ZERO
	var any: bool = false
	active_chunks = 0
	for i: int in _pieces.size():
		if _p_life[i] >= 0.0:
			_tick_piece(i, delta)
			any = true
			active_chunks += 1
	active_splats = 0
	for i: int in _splats.size():
		if _s_life[i] >= 0.0:
			_tick_splat(i, delta)
			any = true
			active_splats += 1
	active_eyes = 0
	for i: int in _eyes.size():
		if _e_life[i] >= 0.0:
			_tick_eye(i, delta, cam_pos)
			any = true
			active_eyes += 1
	for i: int in _ghosts.size():
		if _g_life[i] >= 0.0:
			_tick_ghost(i, delta, cam_pos)
			any = true
	if not any:
		set_process(false)


# --- Trozos ---------------------------------------------------------------------------------


func _spawn_piece(
	kind: Kind, at: Vector3, push: Vector3, col: Color, size: float, speed: float
) -> void:
	var i: int = _p_next
	_p_next = (_p_next + 1) % _pieces.size()
	if _p_life[i] >= 0.0:
		recycled += 1
	var mi: MeshInstance3D = _pieces[i]
	match kind:
		Kind.CHUNK:
			mi.mesh = _blob_meshes[_rng.randi() % _blob_meshes.size()]
			mi.material_override = _goo_mat
		Kind.ICE:
			mi.mesh = _ice_mesh
			mi.material_override = _goo_mat
		Kind.CONFETTI:
			mi.mesh = _paper_mesh
			mi.material_override = _paper_mat
		Kind.TOOTH:
			mi.mesh = _tooth_mesh
			mi.material_override = _bits_mat
		Kind.BONE:
			mi.mesh = _bone_mesh
			mi.material_override = _bits_mat
	mi.set_instance_shader_parameter(SP_TINT, Color(col, 1.0) if col.a > 0.0 else Color(1, 1, 1, 0))
	mi.visible = true
	var dir := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(0.5, 1.6), _rng.randf_range(-1, 1))
	dir = (dir.normalized() + push * 0.5).normalized()
	var v: float = _rng.randf_range(3.0, 7.5) * speed
	_p_pos[i] = at + dir * 0.15
	_p_vel[i] = dir * v
	_p_axis[i] = (
		Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1))
		. normalized()
	)
	if _p_axis[i].length_squared() < 0.5:
		_p_axis[i] = Vector3.UP
	_p_angle[i] = _rng.randf() * TAU
	_p_spin[i] = _rng.randf_range(7.0, 16.0)
	_p_size[i] = size
	_p_squash[i] = 0.0
	_p_kind[i] = kind
	_p_rest[i] = 0
	var life: float = _rng.randf_range(7.0, 12.0)
	if kind == Kind.CONFETTI:
		life = _rng.randf_range(3.0, 5.0)
	_p_life[i] = life
	_place_piece(i)


func _tick_piece(i: int, delta: float) -> void:
	_p_life[i] -= delta
	if _p_life[i] < 0.0:
		_pieces[i].visible = false
		return
	var kind: int = _p_kind[i]
	if _p_rest[i] == 0:
		var v: Vector3 = _p_vel[i]
		if kind == Kind.CONFETTI:
			# El papel planea: poca gravedad, mucho rozamiento y bamboleo.
			v.y -= GRAVITY * 0.25 * delta
			v *= 1.0 - minf(delta * 2.5, 0.5)
			v.y = maxf(v.y, -1.3)
			v.x += sin(_time * 7.0 + float(i)) * delta * 2.0
		else:
			v.y -= GRAVITY * delta
		var p: Vector3 = _p_pos[i] + v * delta
		var floor_y: float = Valley.ground_height(p.x, p.z) + _rest_height(i)
		if p.y <= floor_y:
			p.y = floor_y
			_land_piece(i, v)
			v = _p_vel[i]
		else:
			_p_vel[i] = v
		_p_pos[i] = p
		_p_angle[i] += _p_spin[i] * delta
	_p_squash[i] = maxf(0.0, _p_squash[i] - delta * 5.0)
	if _p_rest[i] == 0 or _p_squash[i] > 0.0 or _p_life[i] < 1.2:
		_place_piece(i)


func _land_piece(i: int, v: Vector3) -> void:
	var kind: int = _p_kind[i]
	var bounce: float = 0.3
	if kind == Kind.TOOTH or kind == Kind.BONE:
		bounce = 0.45
	elif kind == Kind.ICE:
		bounce = 0.35
	elif kind == Kind.CONFETTI:
		bounce = 0.0
	if -v.y > 1.6 and bounce > 0.0:
		_p_vel[i] = Vector3(v.x * 0.55, -v.y * bounce, v.z * 0.55)
		_p_spin[i] *= 0.6
		_p_squash[i] = 1.0
		var at: Vector3 = _p_pos[i]
		if kind == Kind.CHUNK:
			_voices.play(CritterVoices.Kind.SPLAT, at, -11.0, _rng.randf_range(0.9, 1.3))
			if _rng.randf() < 0.55:
				var col: Color = _pieces[i].get_instance_shader_parameter(SP_TINT)
				_spawn_splat(_on_ground(at), col.darkened(0.1), _p_size[i] * 2.4)
		elif kind == Kind.ICE:
			_voices.play(CritterVoices.Kind.CLINK, at, -12.0, _rng.randf_range(1.6, 2.2))
		else:
			_voices.play(CritterVoices.Kind.BOINK, at, -14.0, _rng.randf_range(1.6, 2.1))
	else:
		# Se queda pegado (la baba, aplastada contra el suelo).
		_p_vel[i] = Vector3.ZERO
		_p_rest[i] = 1
		_p_squash[i] = 0.0


## Altura del centro de la pieza sobre el suelo cuando apoya.
func _rest_height(i: int) -> float:
	match _p_kind[i]:
		Kind.CONFETTI:
			return 0.01
		Kind.TOOTH, Kind.BONE:
			return 0.04 * _p_size[i]
	return _p_size[i] * (0.22 if _p_rest[i] else 0.55)


func _place_piece(i: int) -> void:
	var s: float = _p_size[i]
	var fade: float = clampf(_p_life[i] / 1.2, 0.0, 1.0)
	var b := Basis(_p_axis[i], _p_angle[i])
	var kind: int = _p_kind[i]
	if _p_rest[i] and kind == Kind.CHUNK:
		# Pegote: aplastado contra el suelo.
		b = Basis(Vector3.UP, _p_angle[i])
		_pieces[i].transform = Transform3D(
			b.scaled(Vector3(s * 1.3, s * 0.55, s * 1.3) * fade), _p_pos[i]
		)
		return
	if _p_rest[i] and kind == Kind.CONFETTI:
		b = Basis(Vector3.UP, _p_angle[i])
	var sq: float = _p_squash[i]
	var k: float = s * fade
	if kind == Kind.CONFETTI or kind == Kind.TOOTH or kind == Kind.BONE:
		_pieces[i].transform = Transform3D(b.scaled(Vector3.ONE * k), _p_pos[i])
		return
	_pieces[i].transform = Transform3D(
		b.scaled(Vector3(k * (1.0 + sq * 0.5), k * (1.0 - sq * 0.45), k * (1.0 + sq * 0.5))),
		_p_pos[i]
	)


# --- Manchas --------------------------------------------------------------------------------


func _spawn_splat(at: Vector3, col: Color, size: float) -> void:
	var i: int = _s_next
	_s_next = (_s_next + 1) % _splats.size()
	if _s_life[i] >= 0.0:
		recycled += 1
	var mi: MeshInstance3D = _splats[i]
	mi.mesh = _splat_meshes[_rng.randi() % _splat_meshes.size()]
	mi.set_instance_shader_parameter(SP_TINT, Color(col, 1.0))
	# Cada mancha un pelín más alta que la anterior: no parpadean al solaparse.
	mi.position = at + Vector3.UP * (0.02 + 0.003 * float(i % 6))
	mi.rotation = Vector3(0.0, _rng.randf() * TAU, 0.0)
	mi.scale = Vector3.ONE * 0.01
	mi.visible = true
	_s_size[i] = size
	_s_total[i] = _config.splat_sec * _rng.randf_range(0.8, 1.2)
	_s_life[i] = _s_total[i]


func _tick_splat(i: int, delta: float) -> void:
	_s_life[i] -= delta
	if _s_life[i] < 0.0:
		_splats[i].visible = false
		return
	var age: float = _s_total[i] - _s_life[i]
	var k: float = 1.0
	if age < 0.18:
		# ¡Splat!: se abre de golpe y se pasa un poco.
		var u: float = age / 0.18
		k = 1.0 + sin(u * PI) * 0.25 - (1.0 - u) * (1.0 - u)
	elif _s_life[i] < 2.0:
		k = _s_life[i] / 2.0
	elif age > 0.4:
		return
	var s: float = _s_size[i] * maxf(k, 0.01)
	_splats[i].scale = Vector3(s, 1.0, s)


# --- Ojos -----------------------------------------------------------------------------------


func _spawn_eye(at: Vector3, r: float, push: Vector3, def: CritterDef, side: int) -> void:
	var i: int = _e_next
	_e_next = (_e_next + 1) % _eyes.size()
	if _e_life[i] >= 0.0:
		recycled += 1
	var e: Node3D = _eyes[i]
	e.visible = true
	_e_sclera[i].scale = Vector3.ONE * r
	_e_r[i] = r
	_e_pos[i] = at
	var out := Vector3(
		(-1.0 if side == 0 else 1.0) * _rng.randf_range(0.4, 1.0), 1.4, _rng.randf_range(-0.6, 0.6)
	)
	_e_vel[i] = (out.normalized() + push * 0.4) * _rng.randf_range(4.0, 6.5)
	_e_spin[i] = (
		Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * 14.0
	)
	_e_life[i] = 0.0
	_e_stare[i] = -1.0
	_e_pp[i] = Vector2.ZERO
	_e_pv[i] = Vector2(_rng.randf_range(-6, 6), _rng.randf_range(-6, 6))
	var pr: float = r * def.pupil_ratio
	_e_pupil[i].transform = Transform3D(
		Basis.from_scale(Vector3(pr, pr, pr * 0.4)), Vector3(0, 0, -r * 0.9)
	)
	_e_glint[i].transform = Transform3D(
		Basis.from_scale(Vector3.ONE * pr * 0.3),
		Vector3(-0.32 * pr, 0.38 * pr, -r * 0.9 - pr * 0.42)
	)
	e.scale = Vector3.ONE
	e.global_transform = Transform3D(Basis.IDENTITY, at)


func _tick_eye(i: int, delta: float, cam: Vector3) -> void:
	_e_life[i] += delta
	var e: Node3D = _eyes[i]
	var r: float = _e_r[i]
	var p: Vector3 = _e_pos[i]
	var v: Vector3 = _e_vel[i]
	if _e_stare[i] < 0.0:
		v.y -= GRAVITY * delta
		p += v * delta
		var floor_y: float = Valley.ground_height(p.x, p.z) + r
		var on_ground: bool = false
		if p.y <= floor_y:
			p.y = floor_y
			on_ground = true
			if -v.y > 1.2:
				v.y = -v.y * 0.5
				v.x *= 0.75
				v.z *= 0.75
				_e_spin[i] *= 0.7
				_e_pv[i] += Vector2(_rng.randf_range(-8, 8), _rng.randf_range(-8, 8))
				_voices.play(CritterVoices.Kind.BOINK, p, -8.0, _rng.randf_range(0.9, 1.4))
			else:
				v.y = 0.0
				# Rueda: frena poco a poco y gira según avanza.
				v.x *= 1.0 - minf(delta * 2.2, 1.0)
				v.z *= 1.0 - minf(delta * 2.2, 1.0)
		var flat := Vector3(v.x, 0.0, v.z)
		if on_ground and flat.length() > 0.05:
			var axis: Vector3 = Vector3.UP.cross(flat).normalized()
			e.global_basis = (
				Basis(axis, flat.length() / r * delta) * e.global_basis.orthonormalized()
			)
		elif not on_ground:
			var w: Vector3 = _e_spin[i]
			if w.length_squared() > 0.01:
				e.global_basis = (
					Basis(w.normalized(), w.length() * delta) * e.global_basis.orthonormalized()
				)
		_e_pos[i] = p
		_e_vel[i] = v
		e.global_position = p
		if on_ground and flat.length() < 0.25 and absf(v.y) < 0.01:
			_e_stare[i] = 0.0
		elif _e_life[i] > 2.2:
			_e_stare[i] = 0.0
		return
	# Quieto: se gira hacia el mago y lo mira fijamente (pupila que aún baila); luego se va.
	_e_stare[i] += delta
	var t: float = _e_stare[i]
	var look: Basis = Basis.looking_at(cam - p, Vector3.UP)
	e.global_basis = e.global_basis.orthonormalized().slerp(look, minf(delta * 6.0, 1.0))
	var target := Vector2(0.0, -0.05)
	var acc: Vector2 = (target - _e_pp[i]) * 160.0 - _e_pv[i] * 5.0
	_e_pv[i] += acc * delta
	_e_pp[i] = (_e_pp[i] + _e_pv[i] * delta).limit_length(0.6)
	var n := Vector3(_e_pp[i].x, _e_pp[i].y, -sqrt(maxf(0.0, 1.0 - _e_pp[i].length_squared())))
	var pr: float = r * 0.55
	var b := Basis.looking_at(n, Vector3.UP)
	_e_pupil[i].transform = Transform3D(Basis(b.x * pr, b.y * pr, b.z * (pr * 0.4)), n * (r * 0.9))
	_e_glint[i].transform = Transform3D(
		Basis.from_scale(Vector3.ONE * pr * 0.3),
		n * (r * 0.9 + pr * 0.42) + (b.y * 0.38 - b.x * 0.32) * pr
	)
	var stare: float = _config.eye_stare_sec
	var blink: float = 1.0
	if t > stare - 0.9 and t < stare - 0.75:
		blink = 0.12
	if t > stare:
		var k: float = 1.0 - (t - stare) / 0.4
		if k <= 0.0:
			_e_life[i] = -1.0
			e.visible = false
			return
		e.scale = Vector3(k, k, k)
		return
	e.scale = Vector3(1.0, blink, 1.0)


# --- Almitas --------------------------------------------------------------------------------


func _spawn_ghost(c: Critter) -> void:
	var i: int = _g_next
	_g_next = (_g_next + 1) % GHOSTS
	var g: Node3D = _ghosts[i]
	g.visible = true
	_g_body[i].mesh = c.rig.body
	var top: float = c.rig.height
	_g_halo[i].position = Vector3(0.0, top * 1.12, 0.0)
	_g_halo[i].scale = Vector3.ONE * c.rig.hit_radius * 1.1
	var eye: Vector3 = (
		c.rig.eye_pos[0]
		if c.rig.stalk_len <= 0.0
		else c.rig.eye_pos[0] + Vector3(0, c.rig.stalk_len * 0.4, 0)
	)
	_g_x[i].position = Vector3(0.0, eye.y, eye.z - 0.04)
	_g_x[i].scale = Vector3.ONE * c.def.size
	_g_from[i] = c.global_position + Vector3.UP * 0.2
	_g_life[i] = 0.0
	g.global_position = _g_from[i]


func _tick_ghost(i: int, delta: float, cam: Vector3) -> void:
	_g_life[i] += delta
	var t: float = _g_life[i]
	var total: float = 2.4
	if t > total:
		_g_life[i] = -1.0
		_ghosts[i].visible = false
		return
	var g: Node3D = _ghosts[i]
	var pos: Vector3 = _g_from[i] + Vector3(sin(t * 3.2) * 0.18, t * 0.95, 0.0)
	var d: Vector3 = cam - pos
	g.global_position = pos
	g.rotation = Vector3(0.0, atan2(d.x, d.z) + PI, sin(t * 3.2) * 0.15)
	var pop: float = minf(t / 0.25, 1.0)
	var s: float = 0.6 * (pop + sin(pop * PI) * 0.25)
	g.scale = Vector3.ONE * s
	var a: float = 0.55 * (1.0 - smoothstep(total - 0.7, total, t))
	_g_mat[i].albedo_color = Color(0.92, 0.9, 1.0, a)
	_g_halo[i].rotation.y = t * 2.0


# --- Partículas -----------------------------------------------------------------------------


func _spray(at: Vector3, col: Color, s: float) -> void:
	var p: GPUParticles3D = _sprays[_spray_next]
	_spray_next = (_spray_next + 1) % SPRAYS
	p.global_position = at
	var pm: ParticleProcessMaterial = p.process_material
	pm.color = col
	pm.scale_min = 0.6 * s
	pm.scale_max = 1.5 * s
	p.restart()


func _puff(at: Vector3, col: Color, size: float) -> void:
	var p: GPUParticles3D = _puffs[_puff_next]
	_puff_next = (_puff_next + 1) % PUFFS
	p.global_position = at
	HdFx.set_smoke_size(p, size)
	var pm: ParticleProcessMaterial = p.process_material
	pm.color = col
	p.restart()


func _star_burst(at: Vector3) -> void:
	var p: GPUParticles3D = _stars[_star_next]
	_star_next = (_star_next + 1) % STARS
	p.global_position = at
	p.restart()


# --- Construcción ---------------------------------------------------------------------------


func _toon(wet: float, self_light: float, vertex: bool) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = CritterHerd.SHADER
	m.set_shader_parameter("use_vertex_color", vertex)
	m.set_shader_parameter("wet", wet)
	m.set_shader_parameter("self_light", self_light)
	m.set_shader_parameter("rim", 0.3)
	return m


func _build_pieces(n: int) -> void:
	for i: int in n:
		var mi := MeshInstance3D.new()
		mi.name = "Piece%d" % i
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		add_child(mi)
		_pieces.append(mi)
	_p_pos.resize(n)
	_p_vel.resize(n)
	_p_axis.resize(n)
	_p_angle.resize(n)
	_p_spin.resize(n)
	_p_size.resize(n)
	_p_life.resize(n)
	_p_life.fill(-1.0)
	_p_squash.resize(n)
	_p_kind.resize(n)
	_p_rest.resize(n)


func _build_splats(n: int) -> void:
	for i: int in n:
		var mi := MeshInstance3D.new()
		mi.name = "Splat%d" % i
		mi.material_override = _goo_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		add_child(mi)
		_splats.append(mi)
	_s_life.resize(n)
	_s_life.fill(-1.0)
	_s_total.resize(n)
	_s_size.resize(n)


func _build_eyes(n: int, herd: CritterHerd) -> void:
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 10
	sphere.rings = 6
	for i: int in n:
		var e := Node3D.new()
		e.name = "Eye%d" % i
		e.visible = false
		add_child(e)
		var sc := MeshInstance3D.new()
		sc.mesh = sphere
		sc.material_override = herd.sclera_material
		e.add_child(sc)
		var pu := MeshInstance3D.new()
		pu.mesh = sphere
		pu.material_override = herd.pupil_material
		e.add_child(pu)
		var gl := MeshInstance3D.new()
		gl.mesh = sphere
		gl.material_override = herd.glint_material
		gl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		e.add_child(gl)
		_eyes.append(e)
		_e_sclera.append(sc)
		_e_pupil.append(pu)
		_e_glint.append(gl)
	_e_pos.resize(n)
	_e_vel.resize(n)
	_e_spin.resize(n)
	_e_r.resize(n)
	_e_life.resize(n)
	_e_life.fill(-1.0)
	_e_stare.resize(n)
	_e_pp.resize(n)
	_e_pv.resize(n)


## Almita: el cuerpo del bicho en blanco translúcido (capa de magia), ojos en X y aureola.
func _build_ghosts(_herd: CritterHerd) -> void:
	var halo := TorusMesh.new()
	halo.inner_radius = 0.7
	halo.outer_radius = 1.0
	halo.rings = 12
	halo.ring_segments = 4
	var halo_mat := StandardMaterial3D.new()
	halo_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	halo_mat.albedo_color = Color(2.0, 1.6, 0.5)
	var x_mat := StandardMaterial3D.new()
	x_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	x_mat.albedo_color = Color("#3a2a5a")
	var x_mesh: ArrayMesh = CritterGoreMeshes.x_eyes_mesh()
	for i: int in GHOSTS:
		var g := Node3D.new()
		g.name = "Ghost%d" % i
		g.top_level = true
		g.visible = false
		add_child(g)
		var body := MeshInstance3D.new()
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = Color(0.92, 0.9, 1.0, 0.55)
		m.disable_fog = true
		m.render_priority = 3
		body.material_override = m
		g.add_child(body)
		var x := MeshInstance3D.new()
		x.mesh = x_mesh
		x.material_override = x_mat
		g.add_child(x)
		var h := MeshInstance3D.new()
		h.mesh = halo
		h.material_override = halo_mat
		g.add_child(h)
		MagicLayer.tag(g)
		for mi: MeshInstance3D in [body, x, h]:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_ghosts.append(g)
		_g_body.append(body)
		_g_mat.append(m)
		_g_x.append(x)
		_g_halo.append(h)
	_g_life.resize(GHOSTS)
	_g_life.fill(-1.0)
	_g_from.resize(GHOSTS)


func _build_particles() -> void:
	var drop := SphereMesh.new()
	drop.radius = 0.035
	drop.height = 0.07
	drop.radial_segments = 6
	drop.rings = 3
	drop.material = _toon(0.6, 0.3, true)
	for i: int in SPRAYS:
		var p := GPUParticles3D.new()
		p.name = "Spray%d" % i
		p.amount = 36
		p.lifetime = 0.6
		p.one_shot = true
		p.explosiveness = 0.95
		p.emitting = false
		p.local_coords = false
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		p.visibility_aabb = AABB(Vector3(-8, -8, -8), Vector3(16, 16, 16))
		var pm := ParticleProcessMaterial.new()
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		pm.emission_sphere_radius = 0.2
		pm.direction = Vector3.UP
		pm.spread = 75.0
		pm.initial_velocity_min = 3.0
		pm.initial_velocity_max = 8.0
		pm.gravity = Vector3(0, -GRAVITY, 0)
		p.process_material = pm
		p.draw_pass_1 = drop
		add_child(p)
		_sprays.append(p)
	for i: int in PUFFS:
		var s: GPUParticles3D = HdFx.smoke(14, 1.2, Color.WHITE)
		s.name = "Puff%d" % i
		s.lifetime = 0.9
		s.explosiveness = 1.0
		var spm: ParticleProcessMaterial = s.process_material
		spm.initial_velocity_min = 0.8
		spm.initial_velocity_max = 2.2
		spm.spread = 180.0
		# Con prueba de profundidad: el polvo de un bicho detrás del cristal no se ve a través.
		((s.draw_pass_1 as QuadMesh).material as StandardMaterial3D).no_depth_test = false
		add_child(s)
		_puffs.append(s)
	for i: int in STARS:
		var st: GPUParticles3D = HdFx.embers(
			22, 0.22, PackedColorArray([Color(2.0, 1.7, 0.6), Color("#ff7ad9"), Color("#7fe3ff")])
		)
		st.name = "Stars%d" % i
		st.one_shot = true
		st.explosiveness = 1.0
		st.emitting = false
		st.lifetime = 1.0
		var pm: ParticleProcessMaterial = st.process_material
		pm.initial_velocity_min = 2.0
		pm.initial_velocity_max = 4.5
		pm.gravity = Vector3(0, -2.5, 0)
		var mat: StandardMaterial3D = (st.draw_pass_1 as QuadMesh).material
		mat.albedo_texture = HdFx.soft_star()
		mat.no_depth_test = false
		add_child(st)
		_stars.append(st)
	_embers = HdFx.sparks(
		30, 5.0, 0.03, PackedColorArray([Color(2, 1.4, 0.6), Color(1, 0.35, 0.1)])
	)
	_embers.name = "Embers"
	(_embers.draw_pass_1 as RibbonTrailMesh).material.set(&"no_depth_test", false)
	add_child(_embers)


func _on_ground(p: Vector3) -> Vector3:
	return Vector3(p.x, Valley.ground_height(p.x, p.z), p.z)
