class_name CritterHerd
extends Node3D
## Los bichos del valle: monstruitos graciosos que salen del suelo con un ¡boing! en la hierba
## del claro, pasean un poco como animales y revientan de forma muy cómica (y algo asquerosa)
## al darles con un hechizo. No atacan, no estorban (el mago los aparta) y dan una propina de
## astillas. Más bichos y especies más raras al llenarse el Pilón (`CritterConfig`).
##
## Golpes: la mira y los hechizos ven la capa `Critter.LAYER`. `intercept()` (desde
## `SpellCaster._on_projectile_arrived`) se queda los que dan en un bicho o en el suelo junto a
## alguno; los de área (Bola de Fuego, Meteoro, Terremoto, Rayo en cadena...) revientan todos los
## que pillan, también los que caen en el cristal (`Events.spell_impacted`). Cada hechizo les da
## su final (ver `Critter.Flavor`). Familiares y rayos del Pilón no les hacen nada.

const CONFIG: CritterConfig = preload("res://data/critters/critter_config.tres")
const SHADER: Shader = preload("res://critters/critter_toon.gdshader")
const SPARK: ElementDef = preload("res://data/elements/spark.tres")
const POOL: int = 16
## Avisos al reventar varios de una (2, 3, 4 o más).
const C_HINT := Color("#ffb3e6")
## Cómo revienta cada elemento (ver `Critter.Flavor`).
const FLAVORS: Dictionary[StringName, Critter.Flavor] = {
	&"spark": Critter.Flavor.FIRE,
	&"frost": Critter.Flavor.FROST,
	&"bolt": Critter.Flavor.BOLT,
	&"earth": Critter.Flavor.EARTH,
	&"arcane": Critter.Flavor.ARCANE,
}
# i18n
const QUIPS: Array[String] = ["¡SPLORCH!", "PERDÓN, BICHITO", "¡QUÉ ASCO! (QUÉ BIEN)", "¡PLOF!"]

static var _instance: CritterHerd

var config: CritterConfig = CONFIG
var voices: CritterVoices
var gore: CritterGore
var body_material: ShaderMaterial
var sclera_material: ShaderMaterial
var pupil_material: StandardMaterial3D
var glint_material: StandardMaterial3D
## Bichos reventados en esta sesión (los de la partida, en `Progression.critters_popped`).
var popped: int = 0
## Sin nuevos bichos por su cuenta (demo y tests).
var ambient: bool = true
## Sólo estas especies (demo y capturas); vacío = todas.
var only_species: Array[StringName] = []

var _critters: Array[Critter] = []
var _rng := RandomNumberGenerator.new()
var _respawn_t: float = 0.0
var _combo_n: int = 0
var _combo_t: float = -1.0
var _last_combo_hint: float = -100.0
var _last_quip: float = -100.0
var _last_stop: float = -100.0
var _bonk_hinted: bool = false
var _cull_i: int = 0
var _now: float = 0.0
var _hd: HdImpact
var _fx: ImpactFx
var _cam_pos := Vector3.ZERO
var _player_pos := WorldLayout.PLAYER_START
var _player: Node3D


## Punto de entrada desde los hechizos que llegan a su blanco: true si el golpe era para los
## bichos (dio en uno, o en el suelo junto a alguno) y ya está resuelto.
static func intercept(hit: SpellHit, collider: Object) -> bool:
	if _instance == null or hit == null or hit.warmup:
		return false
	return _instance.on_spell_arrived(hit, collider)


## Haz de Plasma: true si la mira está sobre un bicho (y lo revienta); el haz no sigue al cristal.
static func beam(hit: SpellHit, aim: Dictionary) -> bool:
	var node: Node = aim["collider"] as Node
	if _instance == null or node == null or not node.has_meta(&"critter"):
		return false
	hit.position = aim["position"]
	_instance.on_spell_arrived(hit, node)
	return true


static func instance() -> CritterHerd:
	return _instance


func _ready() -> void:
	_instance = self
	add_to_group(&"critter_herd")
	_rng.randomize()
	_build_materials()
	voices = CritterVoices.new()
	voices.name = "Voices"
	add_child(voices)
	gore = CritterGore.new()
	gore.name = "Gore"
	add_child(gore)
	gore.setup(config, voices, self)
	_hd = HdImpact.new()
	_hd.name = "HdImpact"
	_hd.pool_size = 4
	add_child(_hd)
	_fx = ImpactFx.new()
	_fx.name = "ImpactFx"
	_fx.pool_size = 4
	add_child(_fx)
	for i: int in POOL:
		var c := Critter.new()
		c.name = "Critter%d" % i
		add_child(c)
		c.setup(self, i)
		_critters.append(c)
	Events.spell_impacted.connect(_on_spell_impacted)
	_respawn_t = _respawn_time()
	if OS.is_debug_build():
		_setup_demo()
	_populate.call_deferred()


func _exit_tree() -> void:
	if _instance == self:
		_instance = null


func _process(delta: float) -> void:
	_now += delta
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam:
		_cam_pos = cam.global_position
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group(&"player") as Node3D
	if _player:
		_player_pos = _player.global_position
	var alive: int = 0
	for c: Critter in _critters:
		if c.state == Critter.State.HIDDEN:
			continue
		c.tick(delta, _cam_pos, _player_pos)
		if c.is_alive():
			alive += 1
			if c.global_position.distance_squared_to(_player_pos) < config.startle_radius ** 2:
				c.startle(_player_pos)
	if ambient:
		_cull_far(cam)
	if ambient and alive < cap():
		_respawn_t -= delta
		if _respawn_t <= 0.0:
			_respawn_t = _respawn_time() if spawn_one(true) else 2.0
	if _combo_t >= 0.0:
		_combo_t += delta
		if _combo_t > config.combo_window_sec:
			_end_combo()


# --- Población ------------------------------------------------------------------------------


## Cuántos puede haber vivos ahora (crece con el Pilón).
func cap() -> int:
	var r: float = GameState.progression.pylon_ratio()
	return roundi(lerpf(float(config.alive_start), float(config.alive_end), r))


func alive_count() -> int:
	var n: int = 0
	for c: Critter in _critters:
		if c.is_alive():
			n += 1
	return n


func critters() -> Array[Critter]:
	return _critters


func _populate() -> void:
	if not ambient:
		return
	# Alrededor del mago (no por todo el anillo: detrás del cristal no los vería nadie).
	_player = get_tree().get_first_node_in_group(&"player") as Node3D
	_player_pos = _player.global_position if _player else WorldLayout.PLAYER_START
	for i: int in mini(config.initial_count, cap()):
		var at: Vector3 = find_spot(false)
		if at != Vector3.INF:
			_spawn_at(pick_species(), at, false, _player_pos)


## Uno por frame: el que se ha quedado muy lejos del mago (y fuera de la pantalla) se esconde, y
## el siguiente que salga lo hará cerca de él. Así siempre hay bichos por donde anda.
func _cull_far(cam: Camera3D) -> void:
	_cull_i = (_cull_i + 1) % _critters.size()
	var c: Critter = _critters[_cull_i]
	if not c.is_alive() or c.state == Critter.State.EMERGE:
		return
	if c.global_position.distance_squared_to(_player_pos) < config.despawn_distance ** 2:
		return
	if cam and cam.is_position_in_frustum(c.global_position):
		return
	c.hide_now()


## Saca un bicho nuevo donde no lo vea el mago de cerca. False si no encontró sitio.
func spawn_one(emerge: bool) -> bool:
	var at: Vector3 = find_spot(true)
	if at == Vector3.INF:
		return false
	return _spawn_at(pick_species(), at, emerge, _player_pos) != null


## Depuración y demo: `n` bichos delante del mago (a `dist` m), mirándolo, con su ¡boing!.
func spawn_in_front(n: int, dist: float = 7.0) -> int:
	var player: Node3D = get_tree().get_first_node_in_group(&"player") as Node3D
	if player == null:
		return 0
	var base: Vector3 = player.global_position
	var fwd := Vector3(-sin(player.rotation.y), 0.0, -cos(player.rotation.y))
	var right := Vector3(-fwd.z, 0.0, fwd.x)
	var made: int = 0
	var first: int = _rng.randi() % config.species.size()
	for i: int in n:
		var spread: float = (float(i) - float(n - 1) * 0.5) * 1.7
		var at: Vector3 = base + fwd * (dist + _rng.randf_range(-0.8, 0.8) + absf(spread) * 0.15)
		at += right * spread
		# Uno de cada especie por turno (para verlas todas), o las de --critter-species.
		var def: CritterDef = config.species[(i + first) % config.species.size()]
		if not only_species.is_empty():
			def = _species_by_id(only_species[i % only_species.size()])
		if _spawn_at(def, at, true, base, true):
			made += 1
	return made


## Un sitio libre en la hierba del claro, o Vector3.INF. `hidden_from_player`: lejos del mago
## y, si cae en pantalla, aún más lejos (no le salen bichos en las narices).
func find_spot(hidden_from_player: bool) -> Vector3:
	var cam: Camera3D = get_viewport().get_camera_3d()
	for attempt: int in 40:
		var a: float = _rng.randf() * TAU
		var r: float = _rng.randf_range(config.ring_min, config.ring_max)
		var p := Vector3(cos(a) * r, 0.0, sin(a) * r)
		if not CritterZones.is_free(p.x, p.z, config.clearance):
			continue
		var d: float = Vector2(p.x - _player_pos.x, p.z - _player_pos.z).length()
		if d > config.max_player_distance:
			continue
		if hidden_from_player:
			if d < config.min_player_distance:
				continue
			if cam and d < config.in_view_min_distance and cam.is_position_in_frustum(p):
				continue
		if _crowded(p, 2.5, null):
			continue
		return Vector3(p.x, Valley.ground_height(p.x, p.z), p.z)
	return Vector3.INF


## Especie al azar según su peso, entre las que ya salen con el Pilón de ahora.
func pick_species() -> CritterDef:
	var r: float = GameState.progression.pylon_ratio()
	var total: float = 0.0
	for d: CritterDef in config.species:
		if _allowed(d, r):
			total += d.weight
	var roll: float = _rng.randf() * total
	for d: CritterDef in config.species:
		if not _allowed(d, r):
			continue
		roll -= d.weight
		if roll <= 0.0:
			return d
	return config.species[0]


func _allowed(d: CritterDef, pylon: float) -> bool:
	if not only_species.is_empty():
		return only_species.has(d.id)
	return d.min_pylon <= pylon


func _species_by_id(id: StringName) -> CritterDef:
	for d: CritterDef in config.species:
		if d.id == id:
			return d
	return config.species[0]


func _spawn_at(
	def: CritterDef, at: Vector3, emerge: bool, face: Vector3, recycle: bool = false
) -> Critter:
	var free: Critter = null
	for c: Critter in _critters:
		if c.state == Critter.State.HIDDEN:
			free = c
			break
	if free == null and recycle:
		# Pool lleno: se recicla el más lejano del mago.
		var far: float = -1.0
		for c: Critter in _critters:
			var d: float = c.global_position.distance_squared_to(_player_pos)
			if c.is_alive() and d > far:
				far = d
				free = c
	if free == null:
		return null
	at.y = Valley.ground_height(at.x, at.z)
	free.spawn(def, at, emerge, face)
	if emerge:
		voices.play(CritterVoices.Kind.BOING, at, -2.0, def.voice_pitch)
		dust(at + Vector3.UP * 0.2, def.size * 1.4)
	return free


func _respawn_time() -> float:
	return _rng.randf_range(config.respawn_min_sec, config.respawn_max_sec)


func _crowded(p: Vector3, radius: float, except: Critter) -> bool:
	for c: Critter in _critters:
		if c != except and c.is_alive():
			if Vector2(c.global_position.x - p.x, c.global_position.z - p.z).length() < radius:
				return true
	return false


## Adónde pasea `c`: un poco alrededor de donde salió, por sitio libre.
func wander_target(c: Critter) -> Vector3:
	for attempt: int in 8:
		var a: float = _rng.randf() * TAU
		var r: float = _rng.randf_range(0.6, config.wander_radius)
		var p: Vector3 = c.home + Vector3(cos(a) * r, 0.0, sin(a) * r)
		if _walkable(p) and not _crowded(p, 1.0, c):
			return p
	return c.global_position


## Adónde huye `c` (hacia `away`, o lo más parecido que esté libre).
func flee_target(c: Critter, away: Vector3) -> Vector3:
	for k: int in 7:
		var ang: float = (float(k + 1) / 2.0) * 0.6 * (1.0 if k % 2 == 0 else -1.0)
		if k == 0:
			ang = 0.0
		var dir: Vector3 = away.rotated(Vector3.UP, ang)
		var p: Vector3 = c.global_position + dir * config.flee_distance
		if _walkable(p):
			return p
	return c.global_position


## En la hierba (los bichos de la demo pueden salir más cerca del cristal, pero no en él).
func _walkable(p: Vector3) -> bool:
	if Vector2(p.x, p.z).length() > config.ring_max + 8.0:
		return false
	return CritterZones.is_free(p.x, p.z, 0.3)


# --- Golpes ---------------------------------------------------------------------------------


## Un hechizo llegó a `collider` (o a nada). Ver `intercept`.
func on_spell_arrived(hit: SpellHit, collider: Object) -> bool:
	if hit.familiar or not hit.by_player:
		return false
	var node: Node = collider as Node
	if node and node.has_meta(&"mother_crystal"):
		return false
	var direct: Critter = null
	if node and node.has_meta(&"critter"):
		direct = node.get_meta(&"critter") as Critter
	if hit.damage <= 0:
		return _bonk(hit, direct)
	var flavor: Critter.Flavor = flavor_of(hit)
	var explosive: bool = _is_explosive(hit)
	var n: int = 0
	if direct and direct.is_alive():
		if direct.center().distance_to(hit.position) < direct.rig.hit_radius + 1.5:
			direct.doom(flavor, 0.0, true, explosive, hit.direction.normalized())
			n += 1
	# Un golpe suelto que dio en uno revienta sólo a ése; los de área, a todos los que pillen.
	if n == 0 or hit.recipe != null:
		n += pop_area(hit.position, blast_radius(hit), flavor, explosive, direct)
	n += _bolt_chain(hit)
	_startle_near(hit.position, config.spell_startle_radius)
	if n == 0:
		return false
	_play_impact(hit)
	return true


## Golpes en el cristal: su área (Meteoro, Bola de Fuego) y la onda del Terremoto también pillan
## bichos; los demás, cerca, se asustan.
func _on_spell_impacted(hit: SpellHit) -> void:
	if hit.warmup or hit.familiar or not hit.by_player:
		return
	var flavor: Critter.Flavor = flavor_of(hit)
	if hit.recipe and hit.recipe.delivery == SpellRecipe.Delivery.GROUND:
		_quake_corridor(hit)
	if hit.recipe and (hit.recipe.area_radius > 0.0 or _is_explosive(hit)):
		pop_area(hit.position, blast_radius(hit), flavor, true, null)
	if not hit.minor:
		# El Rayo que da en el cristal también salta a los bichos que haya al pie.
		_bolt_chain(hit)
	_startle_near(hit.position, config.spell_startle_radius)


## La chispita de aprendiz (sin daño) no revienta a nadie: el bicho se lleva un coscorrón, chilla
## y se va ofendido. True si le dio a uno.
func _bonk(hit: SpellHit, direct: Critter) -> bool:
	_startle_near(hit.position, config.spell_startle_radius)
	if direct == null or not direct.is_alive():
		return false
	direct.bonk(hit.position)
	voices.play(CritterVoices.Kind.BOINK, hit.position, -4.0, _rng.randf_range(1.3, 1.6))
	if hit.tier:
		_fx.play(hit.position, Vector3.UP, hit.tier, false, 0.25)
	if not _bonk_hinted:
		_bonk_hinted = true
		Events.hint.emit(tr("NI COSQUILLAS LE HACES"), C_HINT)
	return true


## Revienta los bichos vivos a menos de `radius` de `center` (los más lejos, un pelín después:
## la onda se ve). Devuelve cuántos.
func pop_area(
	center: Vector3, radius: float, flavor: Critter.Flavor, explosive: bool, except: Critter
) -> int:
	var n: int = 0
	for c: Critter in _critters:
		if c == except or not c.is_alive():
			continue
		var d: float = c.center().distance_to(center)
		if d <= radius + c.rig.hit_radius:
			var push: Vector3 = c.center() - center
			push.y = maxf(push.y, 0.0)
			c.doom(flavor, d * 0.035, true, explosive, push.normalized())
			n += 1
	return n


## Radio en el que un golpe revienta bichos: los de área, generosos (los bichos son pequeños).
func blast_radius(hit: SpellHit) -> float:
	var r: SpellRecipe = hit.recipe
	if r == null:
		return config.point_radius
	var radius: float = r.area_radius * hit.size * 1.6
	match r.delivery:
		SpellRecipe.Delivery.SKY:
			radius = maxf(radius, 3.0)
		SpellRecipe.Delivery.RAIN:
			radius = maxf(radius, 1.4)
	return maxf(radius, config.point_radius)


## Cómo revienta según el hechizo (ver `Critter.Flavor`). La Chispa suelta, baba de siempre.
func flavor_of(hit: SpellHit) -> Critter.Flavor:
	if hit.recipe == null and hit.element == &"spark":
		return Critter.Flavor.GOO
	return FLAVORS.get(hit.element, Critter.Flavor.GOO)


func _is_explosive(hit: SpellHit) -> bool:
	var r: SpellRecipe = hit.recipe
	return r != null and (r.area_radius > 0.0 or r.delivery == SpellRecipe.Delivery.SKY)


## Rayo: salta de bicho en bicho (los más cercanos), con su rayo dibujado.
func _bolt_chain(hit: SpellHit) -> int:
	var chains: int = hit.recipe.chain_count if hit.recipe else 0
	if hit.recipe == null and hit.element_def:
		chains = hit.element_def.chain_count
	if chains <= 0:
		return 0
	var crystal: MotherCrystal = get_tree().get_first_node_in_group(&"mother_crystal")
	var from: Vector3 = hit.position
	var col: Color = hit.tier.color_glow * 1.8 if hit.tier else Color(1.8, 1.7, 0.9)
	var n: int = 0
	for k: int in mini(chains + 1, config.bolt_jumps):
		var best: Critter = null
		var best_d: float = config.bolt_reach
		for c: Critter in _critters:
			if c.is_alive():
				var d: float = c.center().distance_to(from)
				if d < best_d:
					best_d = d
					best = c
		if best == null:
			break
		if crystal:
			crystal.draw_bolt(from, best.center(), 0.08, col, 0.3)
		best.doom(Critter.Flavor.BOLT, 0.06 * float(k + 1), true, false, Vector3.UP)
		from = best.center()
		n += 1
	return n


## Terremoto: la onda corre por el suelo desde los pies del mago hasta el blanco.
func _quake_corridor(hit: SpellHit) -> void:
	var a := Vector2(_player_pos.x, _player_pos.z)
	var b := Vector2(hit.position.x, hit.position.z)
	var ab: Vector2 = b - a
	if ab.length_squared() < 1.0:
		return
	for c: Critter in _critters:
		if not c.is_alive():
			continue
		var p := Vector2(c.global_position.x, c.global_position.z)
		var t: float = clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		if p.distance_to(a + ab * t) < config.quake_width:
			c.doom(Critter.Flavor.EARTH, t * ab.length() / 30.0, true, false, Vector3.UP)


func _startle_near(at: Vector3, radius: float) -> void:
	for c: Critter in _critters:
		if c.is_alive() and c.global_position.distance_to(at) < radius:
			c.startle(at)


## El hechizo estalla en el bicho (no hay cristal que lo haga): destello, fuego y su sonido.
func _play_impact(hit: SpellHit) -> void:
	var n := Vector3.UP
	if hit.tier:
		_fx.play(hit.position, n, hit.tier, hit.resonant, maxf(hit.size, 0.6))
		if hit.recipe or hit.tier.damage >= 3:
			_hd.play(hit.position, n, hit.tier, hit.resonant, hit.recipe != null, hit.size)
	if hit.recipe and not hit.recipe.impact_sfx.is_empty():
		var s: AudioStream = hit.recipe.impact_sfx[_rng.randi() % hit.recipe.impact_sfx.size()]
		AudioDirector.play_sfx(s, -5.0, _rng.randf_range(0.95, 1.08))


# --- Reventón -------------------------------------------------------------------------------


## Fin de la anticipación de `c`: ¡PUM!
func burst(c: Critter) -> void:
	var at: Vector3 = c.center()
	var def: CritterDef = c.def
	var gore_on: bool = Settings.cartoon_gore
	gore.burst(c, gore_on)
	var pitch: float = def.voice_pitch * _rng.randf_range(0.9, 1.12)
	if gore_on:
		voices.play(CritterVoices.Kind.SPLORCH, at, 2.0, pitch)
	else:
		voices.play(CritterVoices.Kind.CONFETTI, at, 0.0, pitch)
	if _rng.randf() < 0.5:
		voices.play(CritterVoices.Kind.KAZOO, at, -6.0, pitch)
	var pool: ShardPool = get_tree().get_first_node_in_group(&"shard_pool") as ShardPool
	if pool and def.splinters > 0:
		pool.spawn(at + Vector3.UP * 0.3, Vector3.UP, ShardPool.SPLINTER, def.splinters, 0.45)
	if c.flavor == Critter.Flavor.ARCANE:
		_arcane_echoes(at, def, gore_on)
	if c.explosive:
		# Salpica a los vecinos: reacción en cadena.
		for other: Critter in _critters:
			if other != c and other.is_alive():
				var d: float = other.center().distance_to(at)
				if d < config.chain_radius + other.rig.hit_radius:
					other.doom(
						c.flavor,
						config.chain_delay_sec,
						c.by_player,
						true,
						(other.center() - at).normalized()
					)
	c.hide_now()
	Events.critter_popped.emit(at, def.id)
	if c.by_player:
		_count_pop(def)
		_juice()


func _arcane_echoes(at: Vector3, def: CritterDef, gore_on: bool) -> void:
	for k: int in 2:
		# Método enlazado (no lambda): si el rebaño ya no está, la señal se desconecta sola.
		var t: SceneTreeTimer = get_tree().create_timer(0.22 * float(k + 1))
		t.timeout.connect(_arcane_echo.bind(at, def, gore_on, k))


func _arcane_echo(at: Vector3, def: CritterDef, gore_on: bool, k: int) -> void:
	gore.echo_burst(at, def, gore_on)
	voices.play(CritterVoices.Kind.SPLORCH, at, -6.0 - 3.0 * k, 1.35 + 0.25 * k)


func _count_pop(def: CritterDef) -> void:
	popped += 1
	var prog: Progression = GameState.progression
	prog.critters_popped += 1
	if prog.critters_popped == 1:
		Events.hint.emit(tr("¡PUM! UN %s MENOS") % tr(def.display_name).to_upper(), C_HINT)
	elif _rng.randf() < 0.1 and _now - _last_quip > 20.0:
		_last_quip = _now
		Events.hint.emit(tr(QUIPS[_rng.randi() % QUIPS.size()]), C_HINT)
	if _combo_t < 0.0:
		_combo_t = 0.0
		_combo_n = 0
	_combo_n += 1


func _end_combo() -> void:
	var n: int = _combo_n
	_combo_t = -1.0
	_combo_n = 0
	if n < 2 or _now - _last_combo_hint < 5.0:
		return
	_last_combo_hint = _now
	var text: String = tr("¡DOBLE BICHO!")
	if n == 3:
		text = tr("¡TRIPLE BICHO!")
	elif n > 3:
		text = tr("¡MASACRE DE BICHOS! ×%d") % n
	Events.hint.emit(text, C_HINT)


## Pausa de impacto cortita y golpe de cámara (no más de uno cada poco: en cadena serían
## un frenazo).
func _juice() -> void:
	if _now - _last_stop < 0.3:
		return
	_last_stop = _now
	HitStop.trigger(get_tree(), config.hit_stop_sec)
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam is CameraRig:
		(cam as CameraRig).add_trauma(config.camera_trauma)
		(cam as CameraRig).punch_fov(1.2)


func dust(at: Vector3, size: float) -> void:
	gore.dust(at, size)


## Pantalla de carga: compila los shaders de los bichos y de su reventón delante de la cámara.
func warm_up(at: Vector3) -> void:
	var c: Critter = null
	for k: Critter in _critters:
		if k.state == Critter.State.HIDDEN:
			c = k
			break
	if c == null:
		return
	c.spawn(config.species[0], at, false, _cam_pos)
	gore.warm_up(at, c)
	_fx.play(at, Vector3.UP, SPARK.tiers[0], false)
	_hd.play(at, Vector3.UP, SPARK.tiers[0], false, true)
	# Un momento a la vista (se compila al dibujarse) y fuera.
	get_tree().create_timer(0.4).timeout.connect(c.hide_now)


func _build_materials() -> void:
	body_material = ShaderMaterial.new()
	body_material.shader = SHADER
	body_material.set_shader_parameter("self_light", 0.32)
	sclera_material = ShaderMaterial.new()
	sclera_material.shader = SHADER
	sclera_material.set_shader_parameter("use_vertex_color", false)
	sclera_material.set_shader_parameter("albedo", Color("#fbfbff"))
	sclera_material.set_shader_parameter("self_light", 0.6)
	sclera_material.set_shader_parameter("bands", 2.0)
	sclera_material.set_shader_parameter("rim", 0.0)
	pupil_material = StandardMaterial3D.new()
	pupil_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pupil_material.albedo_color = Color("#120e1a")
	glint_material = StandardMaterial3D.new()
	glint_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glint_material.albedo_color = Color(1.4, 1.4, 1.4)


# --- Demo -----------------------------------------------------------------------------------


## Modo demo (sólo debug, con --autoplay): --critters=N bichos delante del mago (a
## --critter-dist=m), --critter-species=a,b sólo esas especies, --no-ambient-critters sin los del
## valle, --gore-off sin sangre de caricatura, --critter-pop=s revienta a los s segundos el más
## cercano a la mira (--critter-pop-all todos; --critter-flavor=goo|fire|frost|bolt|earth|arcane),
## --critter-startle=s los asusta y --critter-emote=s[:N] les hace hacer un gesto.
func _setup_demo() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if not args.has("--autoplay"):
		return
	var n: int = 0
	var dist: float = 7.0
	var flavor: Critter.Flavor = Critter.Flavor.GOO
	for a: String in args:
		var v: String = a.get_slice("=", 1)
		if a.begins_with("--critters="):
			n = int(v)
		elif a.begins_with("--critter-dist="):
			dist = float(v)
		elif a.begins_with("--critter-species="):
			for id: String in v.split(","):
				only_species.append(StringName(id))
		elif a.begins_with("--critter-flavor="):
			var names: PackedStringArray = ["goo", "fire", "frost", "bolt", "earth", "arcane"]
			flavor = maxi(names.find(v), 0) as Critter.Flavor
	if args.has("--no-ambient-critters"):
		ambient = false
	if args.has("--gore-off"):
		Settings.cartoon_gore = false
	var tree: SceneTree = get_tree()
	if n > 0:
		tree.create_timer(0.3).timeout.connect(func() -> void: spawn_in_front(n, dist))
	for a: String in args:
		var v: String = a.get_slice("=", 1)
		if a.begins_with("--critter-pop="):
			var all: bool = args.has("--critter-pop-all")
			tree.create_timer(float(v)).timeout.connect(debug_pop.bind(flavor, all))
		elif a.begins_with("--critter-startle="):
			tree.create_timer(float(v)).timeout.connect(
				func() -> void: _startle_near(_player_pos, 100.0)
			)
		elif a.begins_with("--critter-emote="):
			var e: int = int(v.get_slice(":", 1)) if v.contains(":") else -1
			tree.create_timer(float(v.get_slice(":", 0))).timeout.connect(
				func() -> void:
					for c: Critter in _critters:
						c.force_emote((e if e >= 0 else _rng.randi() % 4) as Critter.Emote)
			)


## Demo y depuración: revienta el bicho más cercano al centro de la pantalla (o todos).
func debug_pop(flavor: Critter.Flavor, all: bool = false) -> void:
	var cam: Camera3D = get_viewport().get_camera_3d()
	var best: Critter = null
	var best_d: float = INF
	for c: Critter in _critters:
		if not c.is_alive():
			continue
		if all:
			c.doom(flavor, _rng.randf() * 0.3, true, false, Vector3.UP)
			continue
		var d: float = c.center().distance_to(_cam_pos)
		if cam:
			var fwd: Vector3 = -cam.global_basis.z
			d = (c.center() - _cam_pos).cross(fwd).length()
		if d < best_d:
			best_d = d
			best = c
	if best:
		best.doom(flavor, 0.0, true, false, Vector3.UP)
