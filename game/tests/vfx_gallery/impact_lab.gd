extends Node3D
## Laboratorio de impactos: el golpe de cada elemento contra una pared clara (como el cristal),
## lado a lado y repetido cada `EVERY` segundos. Sirve para ver que cada elemento golpea a su
## manera (forma, chispas, humo, ondas) y no sólo con otro color.
##
## godot --path game res://tests/vfx_gallery/impact_lab.tscn --write-movie /tmp/i/f.png
##   --fixed-fps 30 --quit-after 60 [-- --level=N] [--flight]

const NAMES: PackedStringArray = ["CHISPA", "ESCARCHA", "RAYO", "TIERRA", "ARCANO", "VIENTO"]
const STEP: float = 8.5
const EVERY: float = 1.8

var _impact: HdImpact
var _level: int = 5
var _t: float = 0.0
## --flight: cada golpe llega volando (orbe, estela, motas y estrella del elemento).
var _flight: bool = false
var _shots: Array[SparkProjectile] = []


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a == "--flight":
			_flight = true
		if a.begins_with("--level="):
			_level = int(a.get_slice("=", 1))
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.45, 0.62, 0.85)
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_hdr_threshold = 1.2
	add_child(_world_env(env))
	var cam := Camera3D.new()
	cam.position = Vector3(0, 0.0, 17.0)
	cam.fov = 62.0
	add_child(cam)
	var wall := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 30)
	pm.orientation = PlaneMesh.FACE_Z
	wall.mesh = pm
	var wm := StandardMaterial3D.new()
	wm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	wm.albedo_color = Color(0.72, 0.8, 0.95)
	wall.material_override = wm
	wall.position = Vector3(0, 0, -1.0)
	add_child(wall)
	_impact = HdImpact.new()
	_impact.pool_size = 12
	add_child(_impact)
	for i: int in NAMES.size():
		var l := Label3D.new()
		l.text = NAMES[i]
		l.font_size = 48
		l.pixel_size = 0.02
		l.outline_size = 10
		l.modulate = Color(1, 1, 1)
		l.position = _pos(i) + Vector3(0.0, -3.0, 0.5)
		l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		add_child(l)
	for el: ElementDef in SpellCaster.ELEMENTS:
		el.ensure_levels()
	_t = EVERY - 0.2
	if _flight:
		for i: int in NAMES.size():
			var p := SparkProjectile.new()
			add_child(p)
			p.arrived.connect(_on_arrived)
			_shots.append(p)


func _process(delta: float) -> void:
	_t += delta
	if _t < EVERY:
		return
	_t = 0.0
	for i: int in NAMES.size():
		var el: ElementDef = SpellCaster.ELEMENTS[_index(i)]
		var tier: SpellTier = el.tiers[mini(_level, el.tiers.size()) - 1]
		if _flight:
			var hit := SpellHit.new()
			hit.tier = tier
			hit.element = el.id
			hit.element_def = el
			hit.level = _level
			hit.position = _pos(i)
			hit.normal = Vector3.BACK
			_shots[i].launch(Vector3(_pos(i).x * 0.3, -7.0, 13.0), _pos(i), hit, null)
		else:
			_impact.play(_pos(i), Vector3.BACK, tier, false, false, 1.0, _style(i))


func _on_arrived(p: SparkProjectile) -> void:
	var h: SpellHit = p.hit
	_impact.play(h.position, h.normal, h.tier, false, false, 1.0, ImpactStyle.of(h))


## Rejilla de 3 x 2.
func _pos(i: int) -> Vector3:
	return Vector3((float(i % 3) - 1.0) * STEP, 3.4 - floorf(i / 3.0) * 7.2, 0.0)


func _style(i: int) -> int:
	if OS.get_cmdline_user_args().has("--before"):
		return ImpactStyle.FIRE
	return ImpactStyle.ELEMENT_STYLE[SpellCaster.ELEMENTS[_index(i)].id]


## Orden de NAMES -> índice de SpellCaster.ELEMENTS (0 Chispa, 1 Escarcha, 2 Rayo, 3 Tierra,
## 4 Arcano, 5 Viento).
func _index(i: int) -> int:
	return i


func _world_env(env: Environment) -> WorldEnvironment:
	var we := WorldEnvironment.new()
	we.environment = env
	return we
