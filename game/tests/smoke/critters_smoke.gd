extends SceneTree
## Bichos del valle (critters/): salen en la hierba (nunca en el cristal, los caminos ni los
## edificios) y nunca pasan del tope; un SpellHit en un bicho lo revienta, suelta astillas y
## cuenta en `Progression.critters_popped` (que se guarda); un golpe de área (Bola de Fuego)
## revienta a varios; un hechizo cerca los asusta sin reventarlos; los de los familiares no les
## hacen nada; "sangre de caricatura" cambia baba y ojos por confeti; y los pools se reciclan sin
## pasar de sus topes. No toca la partida guardada.
## godot --headless --path game --script res://tests/smoke/critters_smoke.gd

const HERD_PATH: NodePath = ^"WorldView/WorldViewport/CritterHerd"
const HIDDEN: int = 0
const SPARK: Resource = preload("res://data/elements/spark.tres")
const BOLT: Resource = preload("res://data/elements/bolt.tres")
const FIREBALL: Resource = preload("res://data/spells/recipe_fireball.tres")
const SPLINTER: Resource = preload("res://data/shards/splinter.tres")
const HIT_SCRIPT: GDScript = preload("res://spells/spell_hit.gd")

var _ok: bool = true
var _herd: Node3D
var _settings: Node


func _initialize() -> void:
	root.get_node(^"SaveSystem").set(&"enabled", false)
	_settings = root.get_node(^"Settings")
	var gs: Node = root.get_node(^"GameState")
	gs.call(&"reset")
	change_scene_to_file("res://main/main.tscn")
	await process_frame
	await process_frame
	await _wait(4.0)
	_herd = current_scene.get_node(HERD_PATH)
	var prog: RefCounted = gs.get(&"progression")
	var config: Resource = _herd.get(&"config")
	_check_zones(config)
	await _check_cap()
	await _check_single_pop(prog)
	await _check_startle_and_familiar()
	await _check_area_pop()
	await _check_gore_setting()
	await _check_pools(config)
	var finished: bool = await _check_real_aim(prog)
	_check(finished, "las comprobaciones de la mira llegan al final")
	# La estadística se guarda y se carga.
	var data: Dictionary = prog.call(&"to_dict")
	var popped: int = VariantCast.to_int(prog.get(&"critters_popped"))
	_check(
		VariantCast.to_int(data.get("critters_popped", -1)) == popped, "critters_popped se guarda"
	)
	var progression_script: GDScript = load("res://core/progression.gd")
	var fresh: RefCounted = progression_script.new(1000000)
	fresh.call(&"load_dict", data)
	_check(VariantCast.to_int(fresh.get(&"critters_popped")) == popped, "y se carga (%d)" % popped)
	_settings.set(&"cartoon_gore", true)
	print("critters_smoke: OK" if _ok else "critters_smoke: FAILED")
	quit(0 if _ok else 1)


## Los del valle están en sitios libres, y cualquier sitio que elige el rebaño también.
func _check_zones(config: Resource) -> void:
	var ring_min: float = VariantCast.to_float(config.get(&"ring_min"))
	var ring_max: float = VariantCast.to_float(config.get(&"ring_max"))
	var alive: int = VariantCast.to_int(_herd.call(&"alive_count"))
	_check(alive > 0, "hay bichos en el valle al empezar (%d)" % alive)
	for c: Node3D in _critters():
		if VariantCast.to_int(c.get(&"state")) != HIDDEN:
			var p: Vector3 = c.global_position
			_check(CritterZones.is_free(p.x, p.z, 0.0), "bicho en sitio libre %s" % p)
	var bad: int = 0
	for i: int in 300:
		var p: Vector3 = _herd.call(&"find_spot", false)
		if p == Vector3.INF:
			continue
		var r: float = Vector2(p.x, p.z).length()
		if not CritterZones.is_free(p.x, p.z, 0.0) or r < ring_min or r > ring_max:
			bad += 1
	_check(bad == 0, "300 sitios elegidos, todos en la hierba (%d mal)" % bad)
	# Las zonas prohibidas lo son de verdad.
	var no_go: Array[Vector3] = [
		Vector3.ZERO,
		WorldLayout.PYLON,
		WorldLayout.SANCTUM,
		WorldLayout.HUT,
		WorldLayout.FAMILIAR_NEST,
		CritterZones.hub(),
		Vector3(0.0, 0.0, 62.0),
	]
	for p: Vector3 in no_go:
		_check(not CritterZones.is_free(p.x, p.z, 0.0), "prohibido en %s" % p)


## Con prisa por salir (sin esperar al reloj), nunca pasan del tope.
func _check_cap() -> void:
	var cap: int = VariantCast.to_int(_herd.call(&"cap"))
	var most: int = 0
	for i: int in 40:
		_herd.set(&"_respawn_t", 0.0)
		await process_frame
		most = maxi(most, VariantCast.to_int(_herd.call(&"alive_count")))
	_check(most <= cap, "nunca más de %d vivos (máximo %d)" % [cap, most])
	_check(most >= mini(cap, 3), "salen hasta llenar el tope (%d)" % most)
	# Uno que se queda muy lejos del mago (a su espalda) se esconde para salir luego cerca.
	_pop_all_now()
	await _wait(1.0)
	var config: Resource = _herd.get(&"config")
	var def: Resource = config.get(&"species")[0]
	var far: Node3D = _herd.call(&"_spawn_at", def, Vector3(0.0, 0.0, 220.0), false, Vector3.ZERO)
	_herd.set(&"_respawn_t", 100.0)
	for i: int in 20:
		await process_frame
	_check(VariantCast.to_int(far.get(&"state")) == HIDDEN, "el que se queda lejos se esconde")


func _check_single_pop(prog: RefCounted) -> void:
	_herd.set(&"ambient", false)
	if _first_alive() == null:
		_herd.call(&"spawn_in_front", 1, 7.0)
		await _wait(1.0)
	var c: Node3D = _first_alive()
	var pool: Node = current_scene.get_tree().get_first_node_in_group(&"shard_pool")
	var shards0: int = VariantCast.to_int(pool.call(&"count_of", SPLINTER))
	var stat0: int = VariantCast.to_int(prog.get(&"critters_popped"))
	var def: Resource = c.get(&"def")
	var hit: RefCounted = _hit(_center(c))
	var taken: bool = _herd.call(&"on_spell_arrived", hit, c.get_node(^"Hitbox"))
	_check(taken, "el golpe en un bicho es para el bicho")
	_check(not VariantCast.to_bool(c.call(&"is_alive")), "le llega su hora")
	await _wait(0.8)
	_check(VariantCast.to_int(c.get(&"state")) == HIDDEN, "revienta")
	var drop: int = VariantCast.to_int(pool.call(&"count_of", SPLINTER)) - shards0
	_check(drop >= VariantCast.to_int(def.get(&"splinters")), "suelta astillas (%d)" % drop)
	_check(VariantCast.to_int(prog.get(&"critters_popped")) == stat0 + 1, "cuenta en la partida")
	var gore: Node = _herd.get(&"gore")
	_check(VariantCast.to_int(gore.get(&"active_chunks")) > 0, "trozos de baba")
	_check(VariantCast.to_int(gore.get(&"active_eyes")) >= 1, "los ojos salen volando")
	_check(VariantCast.to_int(gore.get(&"active_splats")) > 0, "manchas en el suelo")


func _check_startle_and_familiar() -> void:
	_herd.call(&"spawn_in_front", 1, 7.0)
	await _wait(1.0)
	var c: Node3D = _first_alive()
	var before: int = VariantCast.to_int(c.get(&"startles"))
	var p: Vector3 = c.call(&"center")
	var near: RefCounted = _hit(p + Vector3(3.5, 0.0, 0.0))
	var taken: bool = _herd.call(&"on_spell_arrived", near, null)
	_check(not taken, "un golpe en el suelo lejos de ellos no es suyo")
	_check(VariantCast.to_bool(c.call(&"is_alive")), "a 3,5 m no revienta")
	_check(VariantCast.to_int(c.get(&"startles")) > before, "pero se asusta")
	var fam: RefCounted = _hit(_center(c))
	fam.set(&"familiar", true)
	fam.set(&"by_player", false)
	_check(
		not VariantCast.to_bool(_herd.call(&"on_spell_arrived", fam, c.get_node(^"Hitbox"))),
		"familiar: no"
	)
	_check(VariantCast.to_bool(c.call(&"is_alive")), "los familiares no les hacen nada")


## Bola de Fuego contra el suelo en medio de un grupo: revientan varios (y salpican).
func _check_area_pop() -> void:
	_pop_all_now()
	await _wait(1.0)
	var made: int = VariantCast.to_int(_herd.call(&"spawn_in_front", 4, 6.0))
	await _wait(1.2)
	var center := Vector3.ZERO
	var group: Array[Node3D] = []
	for c: Node3D in _critters():
		if VariantCast.to_bool(c.call(&"is_alive")):
			group.append(c)
			center += c.call(&"center")
	center /= maxf(float(group.size()), 1.0)
	var popped0: int = VariantCast.to_int(_herd.get(&"popped"))
	var hit: RefCounted = _hit(center)
	hit.set(&"recipe", FIREBALL)
	hit.set(&"tier", FIREBALL.get(&"tier"))
	var taken: bool = _herd.call(&"on_spell_arrived", hit, null)
	_check(taken, "la Bola de Fuego junto a los bichos es para ellos")
	await _wait(1.5)
	var popped: int = VariantCast.to_int(_herd.get(&"popped")) - popped0
	_check(made == 4 and popped >= 3, "revientan varios de una (%d de %d)" % [popped, made])
	_check(VariantCast.to_int(_herd.call(&"alive_count")) <= 4 - popped, "y ya no están")


func _check_gore_setting() -> void:
	var gore: Node = _herd.get(&"gore")
	gore.call(&"clear")
	_settings.set(&"cartoon_gore", false)
	_herd.call(&"spawn_in_front", 1, 6.0)
	await _wait(1.0)
	var c: Node3D = _first_alive()
	_herd.call(&"on_spell_arrived", _hit(_center(c)), c.get_node(^"Hitbox"))
	await _wait(0.8)
	_check(not VariantCast.to_bool(gore.get(&"last_gore")), "sin sangre de caricatura: confeti")
	_check(VariantCast.to_int(gore.get(&"active_eyes")) == 0, "sin ojos rodando")
	_check(VariantCast.to_int(gore.get(&"active_splats")) == 0, "sin manchas")
	_check(VariantCast.to_int(gore.get(&"active_chunks")) > 0, "con confeti")
	_settings.set(&"cartoon_gore", true)
	_herd.call(&"spawn_in_front", 1, 6.0)
	await _wait(1.0)
	c = _first_alive()
	_herd.call(&"on_spell_arrived", _hit(_center(c)), c.get_node(^"Hitbox"))
	await _wait(0.8)
	_check(VariantCast.to_bool(gore.get(&"last_gore")), "con sangre de caricatura: baba")
	_check(VariantCast.to_int(gore.get(&"active_eyes")) > 0, "y ojos")


## Muchos reventones seguidos: los pools se reciclan y no pasan de sus topes.
func _check_pools(config: Resource) -> void:
	var gore: Node = _herd.get(&"gore")
	var total: int = 0
	for round_i: int in 5:
		total += VariantCast.to_int(_herd.call(&"spawn_in_front", 6, 6.0))
		await _wait(0.9)
		_herd.call(&"debug_pop", 0, true)
		await _wait(0.7)
	_check(total >= 25, "salen %d bichos del pool de %d" % [total, _critters().size()])
	_check(_critters().size() == 16, "el pool no crece")
	_check(
		VariantCast.to_int(gore.get(&"recycled")) > 0,
		"las piezas se reciclan (%d)" % gore.get(&"recycled")
	)
	var max_pieces: int = (
		VariantCast.to_int(config.get(&"max_chunks")) + VariantCast.to_int(config.get(&"max_bits"))
	)
	_check(VariantCast.to_int(gore.get(&"active_chunks")) <= max_pieces, "trozos dentro del tope")
	_check(
		(
			VariantCast.to_int(gore.get(&"active_splats"))
			<= VariantCast.to_int(config.get(&"max_splats"))
		),
		"manchas al tope"
	)
	_check(
		VariantCast.to_int(gore.get(&"active_eyes")) <= VariantCast.to_int(config.get(&"max_eyes")),
		"ojos al tope"
	)


## Por el camino de verdad (mira de SpellCaster y proyectil): el cristal se sigue golpeando igual,
## un bicho delante se lleva el hechizo, uno detrás del cristal no, y la chispita sin daño del
## principio sólo le da un coscorrón.
func _check_real_aim(prog: RefCounted) -> bool:
	_pop_all_now()
	await _wait(1.0)
	var gore: Node = _herd.get(&"gore")
	gore.call(&"clear")
	var main: Node = current_scene
	var menu: Node = main.get_node(^"HUDLayer/Hud/GameMenu")
	if VariantCast.to_bool(menu.call(&"is_open")):
		menu.call(&"_close")
	var player: Node3D = main.get_node(^"WorldView/WorldViewport/Player")
	var head: Node3D = player.get_node(^"Head")
	var caster: Node = player.call(&"get_caster")
	player.global_position = Vector3(0.0, 0.3, 60.0)
	player.rotation.y = 0.0
	head.rotation.x = deg_to_rad(8.0)
	await physics_frame
	await process_frame
	# Sin bichos delante: la mira da en el cristal y el golpe le quita esencia.
	var aim: Dictionary = caster.call(&"_aim")
	var on_crystal: bool = _on_crystal(aim)
	_check(on_crystal, "sin bichos, la mira da en el cristal")
	caster.call(&"set_debug_level", 3)
	var essence0: int = VariantCast.to_int(prog.get(&"essence"))
	await _cast(caster)
	_check(VariantCast.to_int(prog.get(&"essence")) < essence0, "y el cristal se sigue rompiendo")
	# Un bicho justo detrás del cristal, en la línea de la mira: no se lleva el golpe.
	var cam: Camera3D = caster.get(&"camera")
	var fwd: Vector3 = -cam.global_basis.z
	var aim_at: Vector3 = aim["position"]
	var behind: Vector3 = aim_at + fwd * 25.0
	var config: Resource = _herd.get(&"config")
	var def: Resource = config.get(&"species")[0]
	var c: Node3D = _herd.call(&"_spawn_at", def, behind, false, cam.global_position)
	c.global_position = behind - Vector3(0.0, 0.5, 0.0)
	await physics_frame
	aim = caster.call(&"_aim")
	on_crystal = _on_crystal(aim)
	_check(on_crystal, "un bicho detrás del cristal no le roba la mira")
	essence0 = VariantCast.to_int(prog.get(&"essence"))
	await _cast(caster)
	_check(VariantCast.to_bool(c.call(&"is_alive")), "ni el golpe")
	_check(VariantCast.to_int(prog.get(&"essence")) < essence0, "que va al cristal")
	_pop_all_now()
	await _wait(1.0)
	# Un bicho delante, donde mira el mago (hacia el suelo, a unos 6 m).
	head.rotation.x = deg_to_rad(-15.0)
	await physics_frame
	var ground: Vector3 = caster.call(&"_aim")["position"]
	c = _herd.call(&"_spawn_at", def, ground, false, cam.global_position)
	await physics_frame
	aim = caster.call(&"_aim")
	_check(
		VariantCast.to_bool(aim["collider"] == c.get_node(^"Hitbox")),
		"la mira ve al bicho de delante"
	)
	# La chispita del principio (sin daño): coscorrón, susto y nada más.
	caster.call(&"set_debug_level", 1)
	var startles0: int = VariantCast.to_int(c.get(&"startles"))
	var popped0: int = VariantCast.to_int(prog.get(&"critters_popped"))
	await _cast(caster)
	_check(VariantCast.to_bool(c.call(&"is_alive")), "la chispa sin daño no lo revienta")
	_check(VariantCast.to_int(c.get(&"startles")) > startles0, "pero se lleva un susto")
	_check(VariantCast.to_int(prog.get(&"critters_popped")) == popped0, "y no cuenta")
	# Con un hechizo de verdad, ¡PUM!, y el cristal ni se entera.
	_pop_all_now()
	await _wait(1.0)
	c = _herd.call(&"_spawn_at", def, ground, false, cam.global_position)
	await physics_frame
	caster.call(&"set_debug_level", 3)
	essence0 = VariantCast.to_int(prog.get(&"essence"))
	popped0 = VariantCast.to_int(prog.get(&"critters_popped"))
	await _cast(caster)
	await _wait(0.6)
	_check(not VariantCast.to_bool(c.call(&"is_alive")), "un hechizo de verdad lo revienta")
	_check(VariantCast.to_int(prog.get(&"critters_popped")) == popped0 + 1, "y cuenta")
	_check(VariantCast.to_int(prog.get(&"essence")) == essence0, "sin tocar el cristal")
	# Un Rayo que da en el cristal salta a un bicho que esté cerca del golpe.
	await _wait(0.5)
	c = _herd.call(&"_spawn_at", def, ground, false, cam.global_position)
	var bolt_hit: RefCounted = _hit(_center(c) + Vector3(5.0, 1.0, 0.0))
	bolt_hit.set(&"element", &"bolt")
	bolt_hit.set(&"element_def", BOLT)
	root.get_node(^"Events").emit_signal(&"spell_impacted", bolt_hit)
	_check(
		not VariantCast.to_bool(c.call(&"is_alive")),
		"el Rayo en el cristal salta al bicho de al lado"
	)
	return true


## Una chispa de la mano izquierda por SpellCaster, y espera a que llegue.
func _cast(caster: Node) -> void:
	caster.set(&"_cooldown", PackedFloat32Array([0.0, 0.0]))
	await process_frame
	caster.call(&"try_cast", 0)
	await _wait(1.2)


## Centro de un bicho (`Critter.center()`; la clase no se puede nombrar en el test).
func _center(c: Node3D) -> Vector3:
	return c.call(&"center")


## True si la mira (`SpellCaster._aim()`) da en el Cristal Madre.
static func _on_crystal(aim: Dictionary) -> bool:
	var collider: Object = aim["collider"]
	return collider is Node and (collider as Node).has_meta(&"mother_crystal")


func _hit(at: Vector3) -> RefCounted:
	var hit: RefCounted = HIT_SCRIPT.new()
	var tiers: Array = SPARK.get(&"tiers")
	hit.set(&"tier", tiers[2])
	hit.set(&"element", &"spark")
	hit.set(&"element_def", SPARK)
	hit.set(&"damage", 5)
	hit.set(&"position", at)
	hit.set(&"normal", Vector3.UP)
	hit.set(&"direction", Vector3.FORWARD)
	return hit


func _critters() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for c: Node in _herd.call(&"critters"):
		out.append(c as Node3D)
	return out


func _first_alive() -> Node3D:
	for c: Node3D in _critters():
		if VariantCast.to_bool(c.call(&"is_alive")):
			return c
	return null


func _pop_all_now() -> void:
	_herd.call(&"debug_pop", 0, true)


func _wait(sec: float) -> void:
	var t: float = 0.0
	while t < sec:
		await process_frame
		t += current_scene.get_process_delta_time()


func _check(cond: bool, what: String) -> void:
	if not cond:
		_ok = false
		printerr("  FALLA: " + what)
	else:
		print("  ok: " + what)
