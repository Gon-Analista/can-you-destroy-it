class_name ConvergenceBeam
extends Node3D
## El disparo de la Gran Convergencia: un orbe blanco y violeta que vuela de las manos al Núcleo
## acelerando, con cinco hebras de colores (una por elemento) trenzadas a su alrededor que dejan
## estela y chisporrotean con rayos. Se crea una vez (lo tiene GrandConvergence) y se reutiliza.

signal arrived(at: Vector3)

const FLIGHT_SEC: float = 0.9
const ORB_SCALE: float = 9.0
const STRANDS: int = 5
## Vueltas de la trenza en todo el vuelo.
const TURNS: float = 2.5

var _orb: SpellOrb
var _trails: Array[SpellTrail] = []
var _heads: Array[Node3D] = []
var _light: OmniLight3D
var _colors: PackedColorArray = []
var _from: Vector3
var _to: Vector3
var _t: float = -1.0
var _bolt_t: float = 0.0
var _prev: PackedVector3Array = []


func _ready() -> void:
	top_level = true
	for i: int in STRANDS:
		# Cada hebra es un punto que se mueve; su estela lo sigue sola.
		var head := Node3D.new()
		head.name = "StrandHead%d" % i
		head.top_level = true
		add_child(head)
		_heads.append(head)
		var strand := SpellTrail.new()
		strand.hd = true
		strand.name = "Strand%d" % i
		strand.width = 0.55
		strand.length_sec = 0.4
		strand.near_depth = 2.0
		strand.max_scale = 3.0
		head.add_child(strand)
		_trails.append(strand)
		_prev.append(Vector3.ZERO)
	_light = OmniLight3D.new()
	_light.light_color = Color(0.95, 0.8, 1.0)
	_light.omni_range = 26.0
	_light.shadow_enabled = false
	_light.visible = false
	add_child(_light)
	set_process(false)


func is_flying() -> bool:
	return _t >= 0.0


## Sale de `from` hacia el Núcleo (`to`, su centro; `radius`, el de la esfera).
func launch(
	from: Vector3, to: Vector3, radius: float, colors: PackedColorArray, visual: SpellVisualDef
) -> void:
	_from = from
	_to = to - (to - from).normalized() * radius
	_colors = colors
	if _orb == null:
		_orb = SpellOrb.new()
		_orb.name = "Head"
		_orb.def = visual
		add_child(_orb)
	_orb.visible = true
	_orb.charge = 1.0
	_orb.scale = Vector3.ONE * 0.8
	_orb.global_position = from
	_orb.appear()
	for i: int in STRANDS:
		var c: Color = colors[i % colors.size()]
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
		g.colors = PackedColorArray([Color(2.4, 2.3, 2.5), c * 1.6, Color(c * 0.6, 0.0)])
		_trails[i].set_ramp(g)
		_prev[i] = from
		_heads[i].global_position = from
		_trails[i].start(from)
	_light.visible = true
	_t = 0.0
	_bolt_t = 0.0
	set_process(true)


func _process(delta: float) -> void:
	if _t < 0.0:
		return
	_t += delta
	var u: float = clampf(_t / FLIGHT_SEC, 0.0, 1.0)
	# Acelera: sale despacio de las manos y llega como un rayo.
	var e: float = u * u * (1.6 - 0.6 * u)
	var head: Vector3 = _from.lerp(_to, e)
	var dir: Vector3 = (_to - _from).normalized()
	var side: Vector3 = dir.cross(Vector3.UP)
	side = side.normalized() if side.length() > 0.01 else Vector3.RIGHT
	var up: Vector3 = side.cross(dir).normalized()
	_orb.global_position = head
	# Pegado a la cámara es pequeño (si no, tapa la pantalla); crece al alejarse.
	var away: float = clampf(head.distance_to(_from) / 14.0, 0.0, 1.0)
	_orb.scale = Vector3.ONE * lerpf(0.8, ORB_SCALE, away)
	_light.global_position = head
	_light.light_energy = 6.0 + 6.0 * u
	var braid: float = lerpf(0.05, 1.8, away) * (1.0 - u * 0.45)
	var phase: float = u * TAU * TURNS
	_bolt_t -= delta
	var bolts: bool = _bolt_t <= 0.0
	if bolts:
		_bolt_t = 0.05
	var crystal: MotherCrystal = (
		get_tree().get_first_node_in_group(&"mother_crystal") as MotherCrystal
	)
	for i: int in STRANDS:
		var a: float = phase + TAU * float(i) / STRANDS
		var p: Vector3 = head + (side * cos(a) + up * sin(a)) * braid
		_heads[i].global_position = p
		if bolts and crystal:
			crystal.draw_bolt(_prev[i], p, 0.09, _colors[i % _colors.size()] * 1.4, 0.12)
			_prev[i] = p
	if u >= 1.0:
		_t = -1.0
		_orb.visible = false
		_light.visible = false
		for t: SpellTrail in _trails:
			t.stop()
		set_process(false)
		arrived.emit(_to)
