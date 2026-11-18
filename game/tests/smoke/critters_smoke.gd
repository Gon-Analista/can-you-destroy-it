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
	# La estadística se guarda y se carga.
	var data: Dictionary = prog.call(&"to_dict")
	var popped: int = int(prog.get(&"critters_popped"))
	_check(int(data.get("critters_popped", -1)) == popped, "critters_popped se guarda")
	var fresh: RefCounted = load("res://core/progression.gd").new(1000000)
	fresh.call(&"load_dict", data)
	_check(int(fresh.get(&"critters_popped")) == popped, "y se carga (%d)" % popped)
	_settings.set(&"cartoon_gore", true)
	print("critters_smoke: OK" if _ok else "critters_smoke: FAILED")
	quit(0 if _ok else 1)


## Los del valle están en sitios libres, y cualquier sitio que elige el rebaño también.
func _check_zones(config: Resource) -> void:
	var ring_min: float = float(config.get(&"ring_min"))
	var ring_max: float = float(config.get(&"ring_max"))
	var alive: int = int(_herd.call(&"alive_count"))
	_check(alive > 0, "hay bichos en el valle al empezar (%d)" % alive)
	for c: Node3D in _critters():
		if int(c.get(&"state")) != HIDDEN:
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
	var cap: int = int(_herd.call(&"cap"))
	var most: int = 0
	for i: int in 40:
		_herd.set(&"_respawn_t", 0.0)
		await process_frame
		most = maxi(most, int(_herd.call(&"alive_count")))
	_check(most <= cap, "nunca más de %d vivos (máximo %d)" % [cap, most])
	_check(most >= mini(cap, 3), "salen hasta llenar el tope (%d)" % most)


func _check_single_pop(prog: RefCounted) -> void:
	_herd.set(&"ambient", false)
	var c: Node3D = _first_alive()
	var pool: Node = current_scene.get_tree().get_first_node_in_group(&"shard_pool")
	var shards0: int = int(pool.call(&"count_of", SPLINTER))
	var stat0: int = int(prog.get(&"critters_popped"))
	var def: Resource = c.get(&"def")
	var hit: RefCounted = _hit(c.call(&"center"))
	var taken: bool = _herd.call(&"on_spell_arrived", hit, c.get_node(^"Hitbox"))
	_check(taken, "el golpe en un bicho es para el bicho")
	_check(not bool(c.call(&"is_alive")), "le llega su hora")
	await _wait(0.8)
	_check(int(c.get(&"state")) == HIDDEN, "revienta")
	var drop: int = int(pool.call(&"count_of", SPLINTER)) - shards0
	_check(drop >= int(def.get(&"splinters")), "suelta astillas (%d)" % drop)
	_check(int(prog.get(&"critters_popped")) == stat0 + 1, "cuenta en la partida")
	var gore: Node = _herd.get(&"gore")
	_check(int(gore.get(&"active_chunks")) > 0, "trozos de baba")
	_check(int(gore.get(&"active_eyes")) >= 1, "los ojos salen volando")
	_check(int(gore.get(&"active_splats")) > 0, "manchas en el suelo")


func _check_startle_and_familiar() -> void:
	_herd.call(&"spawn_in_front", 1, 7.0)
	await _wait(1.0)
	var c: Node3D = _first_alive()
	var before: int = int(c.get(&"startles"))
	var p: Vector3 = c.call(&"center")
	var near: RefCounted = _hit(p + Vector3(3.5, 0.0, 0.0))
	var taken: bool = _herd.call(&"on_spell_arrived", near, null)
	_check(not taken, "un golpe en el suelo lejos de ellos no es suyo")
	_check(bool(c.call(&"is_alive")), "a 3,5 m no revienta")
	_check(int(c.get(&"startles")) > before, "pero se asusta")
	var fam: RefCounted = _hit(c.call(&"center"))
	fam.set(&"familiar", true)
	fam.set(&"by_player", false)
	_check(not bool(_herd.call(&"on_spell_arrived", fam, c.get_node(^"Hitbox"))), "familiar: no")
	_check(bool(c.call(&"is_alive")), "los familiares no les hacen nada")


## Bola de Fuego contra el suelo en medio de un grupo: revientan varios (y salpican).
func _check_area_pop() -> void:
	_pop_all_now()
	await _wait(1.0)
	var made: int = int(_herd.call(&"spawn_in_front", 4, 6.0))
	await _wait(1.2)
	var center := Vector3.ZERO
	var group: Array[Node3D] = []
	for c: Node3D in _critters():
		if bool(c.call(&"is_alive")):
			group.append(c)
			center += c.call(&"center")
	center /= maxf(float(group.size()), 1.0)
	var popped0: int = int(_herd.get(&"popped"))
	var hit: RefCounted = _hit(center)
	hit.set(&"recipe", FIREBALL)
	hit.set(&"tier", FIREBALL.get(&"tier"))
	var taken: bool = _herd.call(&"on_spell_arrived", hit, null)
	_check(taken, "la Bola de Fuego junto a los bichos es para ellos")
	await _wait(1.5)
	var popped: int = int(_herd.get(&"popped")) - popped0
	_check(made == 4 and popped >= 3, "revientan varios de una (%d de %d)" % [popped, made])
	_check(int(_herd.call(&"alive_count")) <= 4 - popped, "y ya no están")


func _check_gore_setting() -> void:
	var gore: Node = _herd.get(&"gore")
	gore.call(&"clear")
	_settings.set(&"cartoon_gore", false)
	_herd.call(&"spawn_in_front", 1, 6.0)
	await _wait(1.0)
	var c: Node3D = _first_alive()
	_herd.call(&"on_spell_arrived", _hit(c.call(&"center")), c.get_node(^"Hitbox"))
	await _wait(0.8)
	_check(not bool(gore.get(&"last_gore")), "sin sangre de caricatura: confeti")
	_check(int(gore.get(&"active_eyes")) == 0, "sin ojos rodando")
	_check(int(gore.get(&"active_splats")) == 0, "sin manchas")
	_check(int(gore.get(&"active_chunks")) > 0, "con confeti")
	_settings.set(&"cartoon_gore", true)
	_herd.call(&"spawn_in_front", 1, 6.0)
	await _wait(1.0)
	c = _first_alive()
	_herd.call(&"on_spell_arrived", _hit(c.call(&"center")), c.get_node(^"Hitbox"))
	await _wait(0.8)
	_check(bool(gore.get(&"last_gore")), "con sangre de caricatura: baba")
	_check(int(gore.get(&"active_eyes")) > 0, "y ojos")


## Muchos reventones seguidos: los pools se reciclan y no pasan de sus topes.
func _check_pools(config: Resource) -> void:
	var gore: Node = _herd.get(&"gore")
	var total: int = 0
	for round_i: int in 5:
		total += int(_herd.call(&"spawn_in_front", 6, 6.0))
		await _wait(0.9)
		_herd.call(&"debug_pop", 0, true)
		await _wait(0.7)
	_check(total >= 25, "salen %d bichos del pool de %d" % [total, _critters().size()])
	_check(_critters().size() == 16, "el pool no crece")
	_check(int(gore.get(&"recycled")) > 0, "las piezas se reciclan (%d)" % gore.get(&"recycled"))
	var max_pieces: int = int(config.get(&"max_chunks")) + int(config.get(&"max_bits"))
	_check(int(gore.get(&"active_chunks")) <= max_pieces, "trozos dentro del tope")
	_check(int(gore.get(&"active_splats")) <= int(config.get(&"max_splats")), "manchas al tope")
	_check(int(gore.get(&"active_eyes")) <= int(config.get(&"max_eyes")), "ojos al tope")


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
		if bool(c.call(&"is_alive")):
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
