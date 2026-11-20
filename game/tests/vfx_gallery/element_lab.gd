extends Node3D
## Laboratorio de elementos: los orbes de los seis elementos lado a lado (arriba) y las seis
## combinaciones del Viento (abajo), cargados a tope, sobre un fondo de noche. Sirve para ver de
## un vistazo que cada elemento se distingue por su forma y no sólo por su color.
##
## godot --path game res://tests/vfx_gallery/element_lab.tscn --write-movie /tmp/e/f.png
##   --fixed-fps 30 --quit-after 45

const TOP: Array[String] = [
	"res://data/spells/vfx_flame.tres",
	"res://data/spells/vfx_frost_2.tres",
	"res://data/spells/vfx_bolt.tres",
	"res://data/spells/vfx_wind.tres",
	"res://data/spells/vfx_earth.tres",
	"res://data/spells/vfx_arcane.tres",
]
const BOTTOM: Array[String] = [
	"res://data/spells/vfx_tornado.tres",
	"res://data/spells/vfx_firestorm.tres",
	"res://data/spells/vfx_blizzard.tres",
	"res://data/spells/vfx_tempest.tres",
	"res://data/spells/vfx_sandstorm.tres",
	"res://data/spells/vfx_echo_wind.tres",
]
const TOP_NAMES: PackedStringArray = ["CHISPA", "ESCARCHA", "RAYO", "VIENTO", "TIERRA", "ARCANO"]
const BOTTOM_NAMES: PackedStringArray = [
	"TORNADO", "TORBELLINO", "VENTISCA", "TEMPESTAD", "ARENA", "ECO VIENTO"
]
const STEP: float = 1.25


func _ready() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.06, 0.07, 0.16)
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_hdr_threshold = 1.2
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 0, 4.4)
	cam.fov = 60.0
	add_child(cam)
	for i: int in TOP.size():
		var x: float = (float(i) - 2.5) * STEP
		_orb(TOP[i], Vector3(x, 0.75, 0), 3.2)
		_label(TOP_NAMES[i], Vector3(x, 0.05, 0))
		_orb(BOTTOM[i], Vector3(x, -0.95, 0), 2.4)
		_label(BOTTOM_NAMES[i], Vector3(x, -1.65, 0))


func _orb(path: String, pos: Vector3, s: float) -> void:
	var o := SpellOrb.new()
	o.def = load(path) as SpellVisualDef
	o.charge = 1.0
	o.position = pos
	o.scale = Vector3.ONE * s
	add_child(o)


func _label(text: String, pos: Vector3) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = 24
	l.pixel_size = 0.005
	l.outline_size = 6
	l.position = pos
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	add_child(l)
