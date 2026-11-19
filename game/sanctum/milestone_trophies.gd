class_name MilestoneTrophies
extends Node3D
## Trofeos de los nodos hito en el Santuario (GDD 4.3: "crece físicamente con cada compra"):
## cada hito inscrito pone su pedestal junto al templete, del lado del cristal, con su objeto
## animado.
## - Lanzamiento continuo: un aro de oro con una chispa que nunca se apaga y crepita.
## - Vórtice: un frasco de cristal con un remolino de maná dentro.
## - Rompefacetas: una losa de cristal tallada que gira despacio sobre su pedestal.
## Aparecen con un destello al inscribirlos (y ya puestos al cargar la partida). Lo crea el
## Santuario.

const TOON_SHADER: Shader = preload("res://fx/toon.gdshader")
const SHARD_SHADER: Shader = preload("res://crystal/shard.gdshader")
const VORTEX_SHADER: Shader = preload("res://fx/hd/hd_vortex.gdshader")
const SPARK_VISUAL: SpellVisualDef = preload("res://data/spells/vfx_arcane_orb.tres")
const IDS: Array[StringName] = [&"autocast", &"vortex", &"facet_break"]
## Ángulo (rad) y radio de cada pedestal en el templete: fuera del escalón, a la izquierda de la
## entrada mirando desde el cristal (la entrada y el Espejo quedan libres).
const ANGLES: PackedFloat32Array = [-2.4, -2.85, -3.3]
const RING: float = 4.5
const C_STONE := Color("#e6dddb")
const C_STONE_SHADE := Color("#b9aeb8")
const C_GOLD := Color("#d8a23a")
const C_GOLD_LIGHT := Color("#ffd27a")

var _toon: ShaderMaterial
var _rng := RandomNumberGenerator.new()
var _holders: Dictionary[StringName, Node3D] = {}
var _orb: SpellOrb
var _slab: MeshInstance3D
var _jar_disc: ShaderMaterial
var _poof: GPUParticles3D
var _t: float = 0.0


func _ready() -> void:
	_rng.seed = 71
	_toon = ShaderMaterial.new()
	_toon.shader = TOON_SHADER
	_toon.set_shader_parameter("rim", 0.3)
	for i: int in IDS.size():
		var holder := Node3D.new()
		holder.name = String(IDS[i]).to_pascal_case()
		holder.position = Vector3(cos(ANGLES[i]), 0.0, sin(ANGLES[i])) * RING
		add_child(holder)
		_build_pedestal(holder)
		_holders[IDS[i]] = holder
		holder.visible = GameState.has_upgrade(IDS[i])
	_build_autocast(_holders[&"autocast"])
	_build_vortex(_holders[&"vortex"])
	_build_facet(_holders[&"facet_break"])
	_poof = HdFx.sparks(40, 4.0, 0.03, PackedColorArray([C_GOLD_LIGHT * 2.0, Color(1.6, 0.6, 1.8)]))
	_poof.name = "Poof"
	add_child(_poof)
	Events.upgrade_bought.connect(_on_upgrade_bought)


func _process(delta: float) -> void:
	_t += delta
	var step: float = floor(_t * 12.0) / 12.0
	for id: StringName in IDS:
		var h: Node3D = _holders[id]
		if h.visible and h.scale.x < 0.999:
			h.scale = Vector3.ONE * minf(1.0, h.scale.x + delta * 3.0)
	if _orb and _orb.is_visible_in_tree():
		_orb.position.y = 1.55 + sin(step * 2.2) * 0.05
		var cam: Camera3D = get_viewport().get_camera_3d()
		if cam:
			_orb.global_basis = cam.global_basis.scaled(Vector3.ONE * 0.9)
		_orb.charge = 0.7 + 0.3 * float(int(step * 12.0) % 5 == 0)
	if _slab and _slab.is_visible_in_tree():
		_slab.rotation.y = step * 0.6
		_slab.position.y = 1.75 + sin(step * 1.3) * 0.06
	if _jar_disc:
		_jar_disc.set_shader_parameter("spin", _t * 3.0)


func _on_upgrade_bought(_id: StringName, _level: int) -> void:
	# Mira los tres (al cargar o en la demo puede llegar con otro id).
	for id: StringName in IDS:
		var h: Node3D = _holders[id]
		if h.visible or not GameState.has_upgrade(id):
			continue
		h.visible = true
		h.scale = Vector3.ONE * 0.05
		_poof.global_position = h.global_position + Vector3.UP * 1.4
		_poof.restart()


func _mesh(node_name: String, st: SurfaceTool, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = MeshKit.commit(st)
	mi.material_override = mat
	return mi


func _build_pedestal(holder: Node3D) -> void:
	var st: SurfaceTool = MeshKit.begin()
	MeshKit.add_prism(
		st, Vector3.ZERO, Vector3.UP, 0.42, 0.18, 0.0, 6, C_STONE_SHADE, C_STONE, _rng
	)
	MeshKit.add_prism(
		st, Vector3.UP * 0.18, Vector3.UP, 0.26, 0.9, 0.0, 6, C_STONE, C_STONE_SHADE, _rng
	)
	MeshKit.add_prism(st, Vector3.UP * 1.08, Vector3.UP, 0.36, 0.1, 0.0, 6, C_GOLD, C_GOLD, _rng)
	holder.add_child(_mesh("Pedestal", st, _toon))


## Aro de oro con una chispa perpetua que crepita (el Arcano: magia que no se acaba).
func _build_autocast(holder: Node3D) -> void:
	var st: SurfaceTool = MeshKit.begin()
	for k: int in 8:
		var a: float = TAU * float(k) / 8.0
		var p := Vector3(cos(a) * 0.26, 1.42, sin(a) * 0.26)
		MeshKit.add_box(st, p, Vector3(0.09, 0.05, 0.09), C_GOLD_LIGHT if k % 2 == 0 else C_GOLD)
	MeshKit.add_prism(st, Vector3.UP * 1.18, Vector3.UP, 0.05, 0.24, 0.0, 4, C_GOLD, C_GOLD, _rng)
	holder.add_child(_mesh("Ring", st, _toon))
	_orb = SpellOrb.new()
	_orb.name = "Spark"
	_orb.def = SPARK_VISUAL
	_orb.charge = 0.8
	_orb.position = Vector3.UP * 1.55
	holder.add_child(_orb)
	var crackle: GPUParticles3D = HdFx.sparks(
		18, 1.2, 0.012, PackedColorArray([Color(2.4, 2.2, 2.6), Color(1.6, 0.7, 2.0)])
	)
	crackle.name = "Crackle"
	crackle.one_shot = false
	crackle.explosiveness = 0.0
	crackle.lifetime = 0.35
	crackle.emitting = true
	(crackle.process_material as ParticleProcessMaterial).gravity = Vector3.ZERO
	crackle.position = Vector3.UP * 1.55
	holder.add_child(crackle)
	_add_light(holder, Color("#c79bff"), 0.8, Vector3.UP * 1.6)


## Frasco de cristal con un remolino de maná dentro.
func _build_vortex(holder: Node3D) -> void:
	var glass := ShaderMaterial.new()
	glass.shader = SHARD_SHADER
	var st: SurfaceTool = MeshKit.begin()
	MeshKit.add_prism(
		st, Vector3.UP * 1.18, Vector3.UP, 0.22, 0.55, 0.0, 8, Color.WHITE, Color.WHITE, _rng
	)
	var jar: MeshInstance3D = _mesh("Jar", st, glass)
	jar.transparency = 0.55
	holder.add_child(jar)
	var cork: SurfaceTool = MeshKit.begin()
	MeshKit.add_prism(cork, Vector3.UP * 1.73, Vector3.UP, 0.12, 0.1, 0.0, 6, C_GOLD, C_GOLD, _rng)
	holder.add_child(_mesh("Cork", cork, _toon))
	for k: int in 3:
		var disc: MeshInstance3D = HdFx.quad(VORTEX_SHADER, 0.42 - k * 0.08, 2)
		disc.name = "Swirl%d" % k
		disc.rotation.x = -PI * 0.5
		disc.position = Vector3.UP * (1.3 + k * 0.15)
		var m: ShaderMaterial = disc.material_override
		if k == 0:
			_jar_disc = m
		else:
			disc.material_override = _jar_disc
		m.set_shader_parameter("activity", 1.0)
		holder.add_child(disc)
	_add_light(holder, Color(0.55, 0.85, 1.0), 0.7, Vector3.UP * 1.45)


## Una losa de cristal tallada, de pie, que gira despacio.
func _build_facet(holder: Node3D) -> void:
	var mat := ShaderMaterial.new()
	mat.shader = SHARD_SHADER
	var layer: CrystalLayerDef = GameState.LAYERS[2]
	for key: String in ["col_highlight", "col_light", "col_mid", "col_dark", "col_core"]:
		mat.set_shader_parameter(key, layer.get(key))
	var st: SurfaceTool = MeshKit.begin()
	MeshKit.add_prism(
		st,
		Vector3(0, -0.07, 0),
		Vector3.BACK,
		0.42,
		0.14,
		0.0,
		6,
		Color.WHITE,
		Color.WHITE,
		_rng,
		0.2
	)
	_slab = _mesh("Slab", st, mat)
	_slab.position = Vector3.UP * 1.75
	_slab.rotation.z = 0.25
	holder.add_child(_slab)
	var halo: MeshInstance3D = HdFx.quad(HdFx.GLOW_SHADER, 1.6, 1)
	halo.name = "Glow"
	halo.position = Vector3.UP * 1.75
	(halo.material_override as ShaderMaterial).set_shader_parameter("color", Color(0.6, 0.8, 1.0))
	(halo.material_override as ShaderMaterial).set_shader_parameter("intensity", 0.35)
	holder.add_child(halo)
	_add_light(holder, Color("#a5dae5"), 0.6, Vector3.UP * 1.8)


func _add_light(holder: Node3D, color: Color, energy: float, at: Vector3) -> void:
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.omni_range = 2.5
	l.shadow_enabled = false
	l.position = at
	holder.add_child(l)
