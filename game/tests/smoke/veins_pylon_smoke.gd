extends SceneTree
## Venas Resonantes y rama del Pilón:
## - el sector de cada vena en GDScript es el mismo que dibuja el shader;
## - un golpe en la vena con su elemento débil (o con una combinación que lo lleva) hace el doble
##   de daño y suelta Fragmentos Resonantes por una parte de su daño (vein_bonus); con otro
##   elemento, no;
## - la Pureza multiplica el maná de cada fragmento entregado;
## - cada hito del Pilón se celebra una sola vez y el valle cambia con él;
## - la Resonancia del Pilón dispara un rayo que quita esencia.
## godot --headless --path game --script res://tests/smoke/veins_pylon_smoke.gd

var _ok: bool = true
## CrystalDemo (usa GameState: se carga en ejecución, no con preload).
var _demo: Script
var _milestones: Array[int] = []
var _bolts: int = 0
var _last_impact: SpellHit


func _initialize() -> void:
	root.get_node(^"SaveSystem").set(&"enabled", false)
	var gs: Node = root.get_node(^"GameState")
	gs.call(&"reset")
	var veins_script: Script = load("res://crystal/crystal_veins.gd")
	_demo = load("res://crystal/crystal_demo.gd")
	# Mismo sector que el shader: floor((atan(z, x) + PI) / TAU * 5).
	var probes: Array[Vector3] = [
		Vector3(-10, 0, -0.1),
		Vector3(0, 0, -10),
		Vector3(10, 0, 0),
		Vector3(0, 0, 10),
		Vector3(-10, 0, 3)
	]
	for p: Vector3 in probes:
		var expect: int = posmod(floori((atan2(p.z, p.x) + PI) / TAU * 5.0), 5)
		_check(VariantCast.to_int(veins_script.call(&"sector_at", p)) == expect, "sector de %s" % p)
	_check(
		VariantCast.to_int(veins_script.call(&"sector_at", Vector3(0, 5, 30))) == 3,
		"delante: vena de Tierra"
	)
	change_scene_to_file("res://main/main.tscn")
	for i: int in 240:
		await process_frame
	var main: Node = current_scene
	var menu: Node = main.get_node(^"HUDLayer/Hud/GameMenu")
	if VariantCast.to_bool(menu.call(&"is_open")):
		menu.call(&"_close")
	var events: Node = root.get_node(^"Events")
	events.connect(&"pylon_milestone", func(i: int, _m: float) -> void: _milestones.append(i))
	events.connect(&"pylon_bolt", func(_at: Vector3) -> void: _bolts += 1)
	events.connect(&"spell_impacted", func(h: SpellHit) -> void: _last_impact = h)
	var prog: RefCounted = gs.get(&"progression")
	var levels: Dictionary = prog.get(&"upgrade_levels")
	var world: Node = main.get_node(^"WorldView/WorldViewport")
	var crystal: Node3D = world.get_node(^"MotherCrystal")
	var pylon: Node3D = world.get_node(^"ManaPylon")
	var shards: Node = crystal.get_node(^"Shards")
	var veins: Node = crystal.get_node(^"Veins")
	var resonant: Resource = load("res://data/shards/resonant.tres")
	var chunk: Resource = load("res://data/shards/chunk.tres")
	_check(
		VariantCast.to_int(resonant.get(&"value")) == 5 * VariantCast.to_int(chunk.get(&"value")),
		"resonante = 5 grandes"
	)

	# --- Venas: túnel hasta la capa de las venas por delante (sector 3, Tierra) ---
	_demo.call(&"tunnel_to_layer", crystal, 2)
	var earth: Resource = load("res://data/elements/earth.tres")
	var spark: Resource = load("res://data/elements/spark.tres")
	var hit: SpellHit = _vein_hit(crystal, earth)
	# Un golpe fuerte (625, x2 = 1250): los Resonantes valen un 20 % del daño (vein_bonus), 2 de 125.
	hit.damage = 625
	_check(
		VariantCast.to_int(veins.call(&"layer_under", hit)) == 2,
		"el fondo del túnel es la capa de las venas"
	)
	var before_res: int = shards.call(&"count_of", resonant)
	var before_essence: int = prog.get(&"essence")
	crystal.call(&"receive_hit", hit)
	_check(hit.vein == 3 and hit.vein_weak, "Tierra en la vena de Tierra: golpe en la vena")
	_check(hit.damage == 1250, "daño x2 en la vena (%d)" % hit.damage)
	_check(
		VariantCast.to_int(shards.call(&"count_of", resonant)) == before_res + 2,
		"suelta Fragmentos Resonantes por el 20 % de su daño"
	)
	_check(VariantCast.to_int(prog.get(&"essence")) < before_essence, "quita esencia")
	await process_frame
	var wrong: SpellHit = _vein_hit(crystal, spark)
	var res_now: int = shards.call(&"count_of", resonant)
	crystal.call(&"receive_hit", wrong)
	_check(wrong.vein == 3 and not wrong.vein_weak, "Chispa en la vena de Tierra: no")
	_check(wrong.damage == 10, "sin daño extra (%d)" % wrong.damage)
	_check(
		VariantCast.to_int(shards.call(&"count_of", resonant)) == res_now,
		"sin Fragmentos Resonantes"
	)
	var combo: SpellHit = _vein_hit(crystal, spark)
	combo.recipe = load("res://data/spells/recipe_meteor.tres")
	veins.call(&"apply", combo)
	_check(combo.vein_weak and combo.damage == 20, "el Meteoro (Chispa + Tierra) cuenta en la vena")
	var outside: SpellHit = _vein_hit(crystal, earth)
	outside.position = Vector3(0.0, 4.0, 200.0)
	veins.call(&"apply", outside)
	_check(outside.vein == -1 and outside.damage == 10, "fuera de las venas no cuenta")

	# --- Pureza: el maná de cada fragmento entregado ---
	gs.call(&"reset")
	prog = gs.get(&"progression")
	levels = prog.get(&"upgrade_levels")
	pylon.call(&"receive_mana", chunk)
	_check(VariantCast.to_int(prog.get(&"mana")) == 25, "sin Pureza: 25")
	levels[&"purity"] = 2
	pylon.call(&"receive_mana", chunk)
	_check(VariantCast.to_int(prog.get(&"mana")) == 25 + 29, "Pureza II: x1,166 (29)")
	pylon.call(&"receive_mana", resonant)
	_check(
		VariantCast.to_int(prog.get(&"mana")) == 25 + 29 + 146, "Pureza II con un resonante (146)"
	)
	_check(
		VariantCast.to_int(prog.get(&"pylon_progress")) == 25 + 25 + 125,
		"el Pilón suma el valor sin Pureza (lo que perdió el cristal)"
	)

	# --- Hitos del Pilón: una vez cada uno ---
	gs.call(&"reset")
	prog = gs.get(&"progression")
	_milestones.clear()
	gs.call(&"deliver", 99_999)
	_check(_milestones.is_empty(), "antes del 10 %: nada")
	gs.call(&"deliver", 1)
	_check(_milestones.size() == 1 and _milestones[0] == 0, "justo al 10 %: el primer hito")
	gs.call(&"deliver", 10)
	_check(_milestones.size() == 1, "no se repite")
	gs.call(&"deliver", 400_000)
	_check(_milestones.size() == 3 and _milestones[2] == 2, "al pasar del 25 y del 50: dos más")
	var valley: Node = world.get_node(^"ValleyMilestones")
	_check(VariantCast.to_int(valley.call(&"shown_count")) == 3, "el valle enseña tres hitos")
	await create_timer(2.0).timeout
	_check(VariantCast.to_int(valley.call(&"shown_count")) == 3, "tras encenderse siguen ahí")
	var sky: ShaderMaterial = (
		(world.get_node(^"WorldEnvironment") as WorldEnvironment).environment.sky.sky_material
	)
	var day_night: Node = world.get_node(^"DayNight")
	if VariantCast.to_bool(menu.call(&"is_open")):
		menu.call(&"_close")
	paused = false
	day_night.set(&"time_of_day", 0.0)
	await process_frame
	await process_frame
	_check(VariantCast.to_float(sky.get_shader_parameter("aurora")) > 0.3, "auroras de noche")

	# --- Resonancia del Pilón: el rayo quita esencia ---
	levels = prog.get(&"upgrade_levels")
	levels[&"pylon_resonance"] = 1
	var essence0: int = prog.get(&"essence")
	var resonance: Node = pylon.call(&"resonance")
	var at: Variant = resonance.call(&"fire")
	_check(at is Vector3, "el rayo encuentra el cristal")
	_check(_bolts == 1, "aviso del rayo")
	_check(VariantCast.to_int(prog.get(&"essence")) < essence0, "el rayo quita esencia")
	_check(
		_last_impact != null and not _last_impact.by_player and _last_impact.streak == 0,
		"el rayo no es del jugador: no cuenta para la racha"
	)
	# Que terminen las mallas del cristal que se rehacen en otros hilos antes de salir.
	await create_timer(1.5).timeout
	print("veins_pylon_smoke: ", "OK" if _ok else "FALLO")
	quit(0 if _ok else 1)


## Golpe de daño 10 con `element` en el fondo del túnel de demo hasta las venas.
func _vein_hit(crystal: Node3D, element: Resource) -> SpellHit:
	var volume: RefCounted = crystal.get(&"volume")
	var ray: Array = _demo.call(&"tunnel_ray", crystal, 2)
	var p: Vector3 = ray[0]
	var dir: Vector3 = ray[1]
	var t: float = 0.0
	while t < 60.0 and not VariantCast.to_bool(volume.call(&"is_solid", p + dir * t)):
		t += 0.2
	var hit := SpellHit.new()
	hit.position = p + dir * (t - 0.3)
	hit.normal = -dir
	hit.direction = dir
	hit.damage = 10
	hit.element = element.get(&"id")
	hit.element_def = element
	var tiers: Array = element.get(&"tiers")
	hit.tier = tiers[0]
	return hit


func _check(cond: bool, what: String) -> void:
	if not cond:
		_ok = false
		push_error("FALLO: " + what)
	else:
		print("  ok: ", what)
