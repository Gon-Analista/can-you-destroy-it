class_name WizardHands
extends Node3D
## Manos del mago en primera persona (low-poly + toon, misma paleta que la referencia:
## mangas violeta, brazaletes dorados, piel cálida). Animación procedural: balanceo, paso,
## empuje al lanzar con retroceso elástico y un orbe de chispa que se carga en cada palma.

const C_SLEEVE := Color("#654fae")
const C_SLEEVE_DARK := Color("#4c3a8f")
const C_GOLD := Color("#d8a23a")
const C_GOLD_LIGHT := Color("#f0c65a")
const C_SKIN := Color("#e9a97f")
const C_SKIN_SHADE := Color("#d18c66")
const SPARK_SHADER: Shader = preload("res://spells/spark.gdshader")

## Pose de reposo de la mano derecha en espacio de cámara; la izquierda es su espejo.
## Muñeca, hacia dónde apuntan los dedos y hacia dónde mira la palma.
const REST_WRIST := Vector3(0.17, -0.25, -0.5)
const REST_FINGERS := Vector3(-0.5, 0.12, -0.85)
const REST_PALM := Vector3(-0.3, 0.95, 0.25)
const HAND_SCALE: float = 0.72

var charge_ratio: float = 1.0
var move_speed: float = 0.0

var _hands: Array[Node3D] = []
var _orbs: Array[MeshInstance3D] = []
var _orb_mats: Array[ShaderMaterial] = []
var _kick: PackedFloat32Array = [0.0, 0.0]
var _kick_vel: PackedFloat32Array = [0.0, 0.0]
var _ready_pop: float = 0.0
var _t: float = 0.0
var _walk_phase: float = 0.0
var _rest_basis: Array[Basis] = []


func _ready() -> void:
	var toon := ShaderMaterial.new()
	toon.shader = preload("res://fx/toon.gdshader")
	toon.set_shader_parameter("rim", 0.35)
	for side: int in 2:
		var mirror := Vector3(-1.0 if side == 0 else 1.0, 1.0, 1.0)
		var f: Vector3 = (REST_FINGERS * mirror).normalized()
		var z: Vector3 = -f
		var y: Vector3 = REST_PALM * mirror
		y = (y - z * y.dot(z)).normalized()
		_rest_basis.append(Basis(y.cross(z), y, z).scaled(Vector3.ONE * HAND_SCALE))
		var root := Node3D.new()
		root.name = "HandL" if side == 0 else "HandR"
		add_child(root)
		var mi := MeshInstance3D.new()
		mi.mesh = _build_hand_mesh(-1.0 if side == 0 else 1.0)
		mi.material_override = toon
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
		var orb := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2.ONE
		orb.mesh = q
		var om := ShaderMaterial.new()
		om.shader = SPARK_SHADER
		om.render_priority = 4
		om.set_shader_parameter("flicker_seed", float(side) * 3.7)
		orb.material_override = om
		orb.position = Vector3(0.0, 0.075, -0.045)
		orb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(orb)
		_hands.append(root)
		_orbs.append(orb)
		_orb_mats.append(om)


## La mano `side` (0 izquierda, 1 derecha) lanza: empujón hacia delante + retroceso.
func play_cast(side: int) -> void:
	_kick_vel[side] = 22.0


func play_ready() -> void:
	_ready_pop = 1.0


func set_orb_colors(core: Color, glow: Color) -> void:
	for m: ShaderMaterial in _orb_mats:
		m.set_shader_parameter("color_core", core)
		m.set_shader_parameter("color_glow", glow)


func _process(delta: float) -> void:
	_t += delta
	_walk_phase += delta * move_speed * 1.6
	_ready_pop = maxf(0.0, _ready_pop - delta * 3.0)
	for side: int in 2:
		# Muelle amortiguado: el empujón vuelve solo con un pequeño rebote.
		var acc: float = -_kick[side] * 260.0 - _kick_vel[side] * 22.0
		_kick_vel[side] += acc * delta
		_kick[side] += _kick_vel[side] * delta
		var k: float = _kick[side]
		var sgn: float = -1.0 if side == 0 else 1.0
		var rest: Vector3 = REST_WRIST * Vector3(sgn, 1.0, 1.0)
		var sway := Vector3(sin(_t * 1.3 + side) * 0.004, sin(_t * 1.7 + side * 2.0) * 0.005, 0.0)
		var bob := (
			Vector3(
				cos(_walk_phase + side * PI) * 0.012,
				absf(sin(_walk_phase + side * PI)) * 0.016,
				0.0
			)
			* minf(move_speed / 4.0, 1.0)
		)
		var push := Vector3(-sgn * 0.04, 0.05, -0.12) * k
		_hands[side].position = rest + sway + bob + push
		_hands[side].basis = _rest_basis[side] * Basis(Vector3.RIGHT, 0.6 * k)
		var spent: float = clampf(1.0 - absf(k) * 3.0, 0.0, 1.0)
		var orb_size: float = lerpf(0.035, 0.11, charge_ratio) * spent * (1.0 + _ready_pop * 0.8)
		orb_size *= 1.0 + sin(_t * 9.0 + side) * 0.06
		_orbs[side].scale = Vector3.ONE * maxf(orb_size, 0.001)
		_orb_mats[side].set_shader_parameter(
			"intensity", lerpf(0.8, 1.5, charge_ratio) + _ready_pop
		)


## Antebrazo con manga y brazalete + mano abierta con la palma hacia arriba.
## Espacio local: muñeca en el origen, antebrazo hacia +Z, dedos hacia -Z.
func _build_hand_mesh(side: float) -> ArrayMesh:
	var st: SurfaceTool = MeshKit.begin()
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	# Manga (cono truncado de 8 lados), más ancha hacia el codo.
	MeshKit.add_prism(
		st,
		Vector3(0, 0, 0.6),
		Vector3(0, 0, -1),
		0.125,
		0.47,
		0.0,
		8,
		C_SLEEVE,
		C_SLEEVE_DARK,
		rng,
		0.0,
		0.78
	)
	# Brazalete dorado con borde claro.
	MeshKit.add_prism(
		st, Vector3(0, 0, 0.15), Vector3(0, 0, -1), 0.1, 0.06, 0.0, 8, C_GOLD, C_GOLD_LIGHT, rng
	)
	MeshKit.add_prism(
		st, Vector3(0, 0, 0.098), Vector3(0, 0, -1), 0.094, 0.022, 0.0, 8, C_GOLD_LIGHT, C_GOLD, rng
	)
	# Muñeca y palma (la palma mira hacia arriba: +Y).
	MeshKit.add_prism(
		st, Vector3(0, 0, 0.09), Vector3(0, 0, -1), 0.052, 0.06, 0.0, 6, C_SKIN_SHADE, C_SKIN, rng
	)
	MeshKit.add_box(st, Vector3(0, 0, -0.035), Vector3(0.11, 0.04, 0.11), C_SKIN_SHADE, C_SKIN)
	# Dedos: abiertos y curvados hacia arriba, ofreciendo la magia.
	var fingers: Array[Vector3] = [
		Vector3(-0.04, 0.005, -0.09),
		Vector3(-0.013, 0.005, -0.095),
		Vector3(0.014, 0.005, -0.093),
		Vector3(0.04, 0.005, -0.086)
	]
	var lengths: PackedFloat32Array = [0.075, 0.092, 0.087, 0.068]
	for i: int in fingers.size():
		var base: Vector3 = fingers[i]
		var spread: float = (float(i) - 1.5) * 0.14
		var dir := Vector3(spread, 0.45, -1.0).normalized()
		MeshKit.add_prism(st, base, dir, 0.0145, lengths[i], 0.01, 5, C_SKIN, C_SKIN_SHADE, rng)
	# Pulgar hacia el centro de la pantalla.
	MeshKit.add_prism(
		st,
		Vector3(-0.058 * side, 0.005, -0.005),
		Vector3(-0.9 * side, 0.5, -0.55).normalized(),
		0.017,
		0.065,
		0.012,
		5,
		C_SKIN,
		C_SKIN_SHADE,
		rng
	)
	return MeshKit.commit(st)
