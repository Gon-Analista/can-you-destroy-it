extends Node3D
## Laboratorio de la Bola de Fuego en vuelo (`FireballFlight` dentro de `SparkProjectile`, el
## mismo código que en el juego), sobre un fondo claro (cielo, cristal) y otro oscuro (valle).
##
## godot --path game res://tests/vfx_gallery/fireball_lab.tscn --write-movie /tmp/f/f.png
##   --fixed-fps 30 --quit-after 90
## Arriba, sobre claro: niveles 1, 4 y 10 cruzando la pantalla de izquierda a derecha y el Eco de
## Fuego. Abajo, sobre oscuro: lo mismo de derecha a izquierda. En el centro, dos que salen de
## debajo de la cámara y se alejan hacia el fondo (como en el juego, de la mano a la mira).
## `--away`: sólo las que se alejan, de nivel 1 y 10, una con Tamaño x1,5.

const FIREBALL: SpellRecipe = preload("res://data/spells/recipe_fireball.tres")
const ECHO: SpellRecipe = preload("res://data/spells/recipe_echo_fire.tres")
const DEPTH: float = 34.0

var _shots: Array[Dictionary] = []


func _ready() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.25, 0.45, 0.85)
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_strength = 1.0
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 1.2
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	var levels: PackedFloat32Array = [0.0, 1.0, 0.8, 0.45, 0.0, 0.0, 0.0]
	for i: int in 7:
		env.set_glow_level(i, levels[i])
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var cam := Camera3D.new()
	cam.fov = 75.0
	add_child(cam)
	_backdrop(Vector3(0, 14, -DEPTH - 6.0), Vector2(160, 30), Color(0.72, 0.87, 1.0))
	_backdrop(Vector3(0, -16, -DEPTH - 6.0), Vector2(160, 30), Color(0.08, 0.15, 0.1))
	if OS.get_cmdline_user_args().has("--away"):
		_shot(FIREBALL, 1, 1.0, Vector3(-0.35, -0.3, -0.85), Vector3(-7, 4, -DEPTH), 20.0)
		_shot(FIREBALL, 10, 1.0, Vector3(0.35, -0.3, -0.85), Vector3(7, 4, -DEPTH), 20.0)
		_shot(FIREBALL, 10, 1.5, Vector3(0.0, -0.3, -0.85), Vector3(0, -9, -DEPTH), 20.0)
		return
	var lv: Array[int] = [1, 4, 10, 4]
	for i: int in 4:
		var r: SpellRecipe = ECHO if i == 3 else FIREBALL
		var y: float = 18.0 - float(i) * 4.5
		_shot(r, lv[i], 1.0, Vector3(-36, y, -DEPTH), Vector3(-8, y + 1.0, -DEPTH), 9.0)
		_shot(r, lv[i], 1.0, Vector3(36, -y, -DEPTH), Vector3(8, 1.0 - y, -DEPTH), 9.0)
	_shot(FIREBALL, 4, 1.0, Vector3(-0.3, -0.3, -0.85), Vector3(-3, 1, -DEPTH), 20.0)
	_shot(FIREBALL, 10, 1.0, Vector3(0.3, -0.3, -0.85), Vector3(3, 1, -DEPTH), 20.0)


func _shot(
	r: SpellRecipe, level: int, size: float, from: Vector3, to: Vector3, speed: float
) -> void:
	var p := SparkProjectile.new()
	add_child(p)
	p.prepare_combo()
	var tier: SpellTier = r.tier.duplicate()
	tier.speed = speed
	tier.flight_sfx = null
	var shot: Dictionary = {
		"p": p, "tier": tier, "recipe": r, "level": level, "size": size, "from": from, "to": to
	}
	_shots.append(shot)
	p.arrived.connect(func(_x: SparkProjectile) -> void: _relaunch.call_deferred(shot))
	_relaunch(shot)


func _relaunch(shot: Dictionary) -> void:
	var p: SparkProjectile = shot["p"]
	var hit := SpellHit.new()
	hit.tier = shot["tier"]
	hit.recipe = shot["recipe"]
	hit.level = shot["level"]
	hit.size = shot["size"]
	hit.warmup = true
	hit.normal = Vector3.BACK
	hit.position = shot["to"]
	p.orb_charge = 1.0
	p.launch(shot["from"], shot["to"], hit, null)


func _backdrop(pos: Vector3, size: Vector2, col: Color) -> void:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = size
	mi.mesh = q
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col
	mi.material_override = m
	mi.position = pos
	add_child(mi)
